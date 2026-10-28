"""Game driver: one-key sync, observation, mode detection, seeding (§6.3, §6.4, §6.7).

The only input checkpoint is the entry of ``input_get_key``. At every stop the
driver reads one batched observation, classifies the UI mode, and feeds exactly
one key by writing the KERNAL keyboard buffer (C64 ``$0277``/``$C6``, Plus/4
``$0527``/``$EF``). Feeding at the entry means the game's poll loop runs once
per key, which keeps ``zp_entropy`` (mixed into ``rng_seed``) deterministic.
"""

from __future__ import annotations

import hashlib
import re
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

from .abi import Abi
from .ports import C64, Port
from .screen import ROWS, decode_rows
from .vice import (CMD_MEM_SET, CMD_REGISTERS_SET, RESP_CHECKPOINT_INFO, StopInfo, ViceMonitor,
                   ViceTimeout, parse_checkpoint)

# KERNAL entry points that only run on a crash or reset, per port
# (ports.Port.crash_entries); the C64's are named here for the M0 report.
KERNAL_RESET, KERNAL_NMI_WARM = C64.crash_entries

STACK_PAGE = 0x0100
PAL_CYCLES_PER_SECOND = C64.cycles_per_second

KEY_RETURN = 0x0D
ITEM_PROMPT = re.compile(r"which (?:item|potion|scroll|food|wand|staff) \(a-")   # "Quaff which potion (a-c)?"
# Spells and prayers (core/huffman_data.s PM_YOU_PRAY/PM_YOU_CAST/IGS_PROMPT,
# PM_FOOTER_PRAY/PM_FOOTER_CAST): book choice, spell choice, and the "?" list.
SPELL_BOOK_PROMPT = re.compile(r"^(?:Prayer book|Spell book|Study which book) \(a-")
SPELL_WHICH_PROMPT = re.compile(r"^(?:Pray|Cast) which\? \(a-", re.I)
SPELL_LIST_TITLES = ("Prayer Book", "Mage Book")   # core/player_magic_select_overlay.s
SPELL_LEARN_TITLE, SPELL_LEARN_PROMPT = "Study", "Learn which? (a-"   # the Mage-book Study list (M5d)
KEY_SPACE = 0x20
KEY_RUNSTOP = 0x03


class Mode(str, Enum):
    COMMAND = "COMMAND"
    DISMISS = "DISMISS"
    CHARGEN = "CHARGEN"
    DEATH = "DEATH"
    DIRECTION = "DIRECTION"   # get_direction_target (added for M2 doors)
    STORE = "STORE"           # store screen (ui_store.s): menu and buy prompts
    ITEM = "ITEM"             # "Wear which item (a-v)?" and its "?" item list (M3 round 13)
    SPELL = "SPELL"           # book prompt, "Pray which?" and its "?" list (core/player_magic.s, M5b)
    UNKNOWN = "UNKNOWN"


# Store prompts (core/ui_store.s), checked in order; the menu is the default.
STORE_STAGES = (
    ("buy_confirm", "Buy? (Y/N)"),
    ("buy_which", "Buy which item?"),
    ("message", "You cannot afford that."),
    ("message", "Your pack is full."),
    ("message", "Get out of my store!"),
    ("haggle", "Your offer?"),
    ("haggle", "Take it? (Y/N)"),
)

CHARGEN_STAGES = (
    ("title", "N)ew  L)oad"),
    ("race", "Choose your race"),
    ("stats", "Roll Statistics"),
    ("class", "Choose your class"),
    ("name", "Enter your name"),
    ("sex", "Choose your sex"),
)


class GameFault(Exception):
    """A game-side failure the auditor files as a finding."""

    def __init__(self, kind: str, detail: str, pc: int | None = None) -> None:
        super().__init__(f"{kind}: {detail}")
        self.kind = kind
        self.detail = detail
        self.pc = pc


class EmulatorUnresponsive(Exception):
    """The 60 s response/resume budget expired; the emulator must be killed."""


@dataclass
class Observation:
    step: int
    pc: int
    sp: int
    port01: int
    ret: int
    overlay: int
    zp: bytes
    player: bytes
    monsters: bytes
    screen: bytes
    rows: list[str]
    mode: Mode = Mode.UNKNOWN
    stage: str = ""
    abi: Abi | None = field(default=None, repr=False)

    def zp8(self, label: str) -> int:
        assert self.abi is not None
        return self.zp[getattr(self.abi, label)]

    def zp16(self, label: str) -> int:
        assert self.abi is not None
        addr = getattr(self.abi, label)
        return self.zp[addr] | (self.zp[addr + 1] << 8)

    @property
    def dlvl(self) -> int:
        return self.zp8("zp_player_dlvl")

    @property
    def clvl(self) -> int:
        return self.zp8("zp_player_lvl")

    @property
    def hp(self) -> int:
        value = self.zp16("zp_player_hp_lo")
        return value - 0x10000 if value & 0x8000 else value  # negative at death

    @property
    def mhp(self) -> int:
        return self.zp16("zp_player_mhp_lo")

    @property
    def pos(self) -> tuple[int, int]:
        return self.zp8("zp_player_x"), self.zp8("zp_player_y")

    @property
    def game_flags(self) -> int:
        return self.zp8("zp_game_flags")

    @property
    def rng(self) -> bytes:
        assert self.abi is not None
        return self.zp[self.abi.zp_rng_0:self.abi.zp_rng_0 + 4]

    @property
    def jiffies(self) -> int:
        """The KERNAL jiffy clock: 24-bit, big endian; pauses while IRQs are masked."""
        assert self.abi is not None
        at = self.abi.consts.get("KERNAL_JIFFY")
        return int.from_bytes(self.zp[at:at + 3], "big") if at is not None else 0

    @property
    def xp(self) -> int:
        assert self.abi is not None
        base = self.abi.PL_XP_0
        return int.from_bytes(self.player[base:base + 3], "little")

    def summary(self) -> dict[str, object]:
        return {"step": self.step, "mode": self.mode.value, "stage": self.stage,
                "dlvl": self.dlvl, "clvl": self.clvl, "hp": self.hp, "mhp": self.mhp,
                "pos": list(self.pos), "xp": self.xp, "overlay": self.overlay,
                "sp": self.sp, "jiffies": self.jiffies}


def classify(obs: Observation, abi: Abi, command_ret: int,
             resident_prompts: dict[int, str] | None = None) -> tuple[Mode, str]:
    """Screen text and game state first; the call stack only as a resident-code hint.

    ``resident_prompts`` maps return addresses inside resident code (never an
    overlay, so unambiguous) to stage names for prompts that M0-M2 do not
    handle yet; they stay UNKNOWN (cancelled) but are labelled.
    """
    screen = "\n".join(obs.rows)
    if "* You have died *" in screen or "* Total Winner *" in screen:
        return Mode.DEATH, "tombstone"
    if obs.game_flags & abi.GAME_FLAG_OVER and "Disk Setup" in obs.rows[0]:
        return Mode.DEATH, "disk_setup"  # score save asks for a save drive
    status = obs.rows[21]
    if obs.ret == command_ret and "LV:" in status and "DL:" in status:
        return Mode.COMMAND, "command"
    if "-more-" in obs.rows[0] or "-more-" in obs.rows[1]:
        return Mode.DISMISS, "more"
    if "B)uy  S)ell  Q)uit" in screen:
        for stage, marker in STORE_STAGES:
            if marker in screen:
                return Mode.STORE, stage
        return Mode.STORE, "menu"
    if "Character Info" in screen and "Press any key" in screen:
        return Mode.DISMISS, "info"  # end of chargen, or SHIFT+C in play
    for stage, marker in CHARGEN_STAGES:
        if marker in screen:
            return Mode.CHARGEN, stage
    if "Press any key" in screen:
        return Mode.DISMISS, "anykey"
    if SPELL_BOOK_PROMPT.search(obs.rows[0]):
        return Mode.SPELL, "book"
    if SPELL_WHICH_PROMPT.search(obs.rows[0]):
        return Mode.SPELL, "which"
    bottom = obs.rows[abi.hal_layout_screen_rows - 1]   # the list's prompt (player_magic_select_overlay.s)
    if obs.rows[0].strip() in SPELL_LIST_TITLES and SPELL_WHICH_PROMPT.search(bottom.strip()):
        return Mode.SPELL, "list"
    if obs.rows[0].strip() == SPELL_LEARN_TITLE and bottom.strip().startswith(SPELL_LEARN_PROMPT):
        return Mode.SPELL, "learn"
    if ITEM_PROMPT.search(obs.rows[0]):
        return Mode.ITEM, "which"
    if obs.rows[0].strip() == "Inventory":
        return Mode.ITEM, "list"   # the "?" list at an item prompt (no "Press any key")
    if obs.game_flags & abi.GAME_FLAG_OVER:
        return Mode.DEATH, "other"
    stage = (resident_prompts or {}).get(obs.ret, "")
    return (Mode.DIRECTION if stage == "direction" else Mode.UNKNOWN), stage


def derive_rng(seed: int, phase: int) -> bytes:
    raw = hashlib.sha256(f"moria8-playtest:{seed}:{phase}".encode()).digest()[:4]
    return raw if any(raw) else b"\xa5\x00\x00\x00"


def snapshot_cpu_clock(path: Path) -> int:
    """Main CPU cycle counter from a VICE snapshot's MAINCPU module.

    The binary monitor exposes only LIN/CYC (position within a frame), so the
    snapshot is the one exact, deterministic source of emulated time.
    """
    data = path.read_bytes()
    index = data.find(b"MAINCPU\x00")
    if index < 0:
        raise RuntimeError(f"no MAINCPU module in {path}")
    # 16-byte name, major, minor, 32-bit size, then the 64-bit CLK.
    return int.from_bytes(data[index + 22:index + 30], "little")


def find_jsr(code: bytes, base: int, target: int | tuple[int, ...]) -> int:
    """Address just after the first ``JSR`` to ``target`` (or any of several) in ``code``."""
    targets = target if isinstance(target, tuple) else (target,)
    found = [index for t in targets for index in (code.find(bytes([0x20, t & 0xFF, t >> 8])),) if index >= 0]
    if not found:
        raise RuntimeError(f"JSR {'/'.join(f'${t:04X}' for t in targets)} not found after ${base:04X}")
    return base + min(found) + 3


class Game:
    """Drives one VICE process at the ``input_get_key`` sync point."""

    def __init__(self, monitor: ViceMonitor, abi: Abi, workdir: Path, *,
                 resume_budget: float = 60.0, hang_emulated_seconds: float = 300.0,
                 poll_interval: float = 1.0, port: Port = C64) -> None:
        self.mon = monitor
        self.abi = abi
        self.port = port
        self.clock_path = workdir / "clock.vsf"
        self.resume_budget = resume_budget
        self.hang_emulated_seconds = hang_emulated_seconds
        self.poll_interval = poll_interval
        self.ram = 0
        self.io = 0
        self.reg_ids: dict[str, int] = {}
        self.input_cp = -1
        self.input_cps: dict[int, int] = {}   # checkpoint -> key entry address
        self.crash_cps: dict[int, int] = {}
        self.seed_cp: int | None = None
        self.seed: int = 0
        self.step = 0
        self.keylog: list[int] = []
        self.command_ret = 0
        self.resident_prompts: dict[int, str] = {}
        self.seed_site = 0
        self.key_exits: dict[int, int] = {}   # key-wait stop -> its ``sta igk_key`` exit (key_feed "return")
        self.color_index: dict[int, int] = {}
        self.screen_bank = 0
        self.map_bank = 0
        self.last: Observation | None = None
        self.stats = {"resumes": 0, "interrupts": 0, "false_crash_hits": 0,
                      "max_resume_wall": 0.0, "max_resume_jiffies": 0}

    # -- setup ------------------------------------------------------------

    def arm(self) -> None:
        """(Re-)arm checkpoints; required after connect, undump, or restart."""
        mon = self.mon
        self.ram = mon.bank("ram")
        self.io = mon.bank("io")
        self.screen_bank = mon.bank(self.port.screen_bank)
        self.map_bank = mon.bank(self.port.map_bank)
        self.reg_ids = mon.load_register_ids()
        for cp in mon.checkpoint_list():
            mon.checkpoint_delete(cp.number)
        self.input_cps = {mon.checkpoint_set(addr): addr for addr in self.key_stops()}
        self.input_cp = next(iter(self.input_cps))
        self.crash_cps = {mon.checkpoint_set(addr): addr for addr in self.port.crash_entries}
        self.seed_cp = None

    def key_entries(self) -> tuple[int, ...]:
        return tuple(getattr(self.abi, name) for name in self.port.key_entries)

    def key_stops(self) -> tuple[int, ...]:
        """Where the driver stops for a key. A KERNAL-buffer port stops at the
        key routines' entries. A port fed by return (the C128) stops inside
        each routine's wait loop, at the ``beq`` back to the poll followed by
        ``sta igk_key; pla``: the routine's own work at entry (the C128's
        c128_restore_runtime_vectors, which puts back the MMU mode and the
        common-RAM map helpers) has run as it does for a pressed key. Jumping
        from the entry to the exit skipped it, and the game ran into data
        (M6 C128 round m6d: 19 hangs with the PC in tables and zero page).
        Before the game is loaded (a cold boot) the loops cannot be found:
        the entries until boot() has found them."""
        if self.port.key_feed != "return":
            return self.key_entries()
        stops: dict[int, int] = {}
        loop_exit = bytes([0x8D, self.abi.igk_key & 0xFF, self.abi.igk_key >> 8, 0x68])
        for entry in self.key_entries():
            code = self.mon.mem_get(entry, 128, self.ram)
            at = code.find(loop_exit)
            if at < 2 or code[at - 2] != 0xF0:   # BEQ back to the poll
                return self.key_entries()
            stops[entry + at - 2] = entry + at
        self.key_exits = stops
        return tuple(stops)

    def resolve_sites(self) -> None:
        """Find return/seed addresses by scanning resident code (needs a booted game)."""
        abi = self.abi
        entries = self.key_entries()
        code = self.mon.mem_get(abi.input_get_command, 64, self.ram)
        self.command_ret = find_jsr(code, abi.input_get_command, entries) - 1
        self.resident_prompts = {}
        offset = self.command_ret + 1 - abi.input_get_command
        try:   # the C64's run direction; the C128 reads it elsewhere
            run_ret = find_jsr(code[offset:], self.command_ret + 1, entries) - 1
            self.resident_prompts[run_ret] = "run_direction"
        except RuntimeError:
            pass
        code = self.mon.mem_get(abi.get_direction_target, 64, self.ram)
        direction_ret = find_jsr(code, abi.get_direction_target, entries) - 1
        self.resident_prompts[direction_ret] = "direction"
        self.resolve_seed_site()
        if self.port.color_table:
            native = self.mon.mem_get(abi.all_symbols[self.port.color_table][0], 16, self.ram)
            self.color_index = {}
            for index, value in enumerate(native):
                self.color_index.setdefault(value & self.port.color_mask, index)

    def resolve_seed_site(self) -> None:
        """The new game's ``JSR rng_seed``, where seed_title's reseed lands."""
        code = self.mon.mem_get(self.abi.game_new_start, 160, self.ram)
        self.seed_site = find_jsr(code, self.abi.game_new_start, self.abi.rng_seed)

    # -- observation ------------------------------------------------------

    def observe(self, stop: StopInfo) -> Observation:
        mon, abi = self.mon, self.abi
        regs = stop.registers or mon.registers()
        sp = regs.get(self.reg_ids.get("SP", 4), 0)
        if stop.pc in self.key_exits:   # inside a wait loop: the entry's stack, before its pushes
            sp = (sp + self.port.key_wait_pushes) & 0xFF
        port01 = regs.get(self.reg_ids.get("01", 56), 0)
        ids = [
            mon.send_mem_get(0x0000, 256, self.ram),
            mon.send_mem_get(STACK_PAGE, 256, self.ram),
            mon.send_mem_get(abi.player_data, abi.PL_STRUCT_SIZE, self.ram),
            mon.send_mem_get(abi.monster_table, abi.MAX_MONSTERS * abi.MONSTER_ENTRY_SIZE, self.ram),
            None if self.port.screen_decoder else
            mon.send_mem_get(getattr(abi, self.port.screen_const), self.port.screen_cols * ROWS,
                             self.screen_bank),
            mon.send_mem_get(abi.current_overlay, 1, self.ram),
        ]
        zp = mon.recv_mem_get(ids[0], 256)
        stack = mon.recv_mem_get(ids[1], 256)
        player = mon.recv_mem_get(ids[2], abi.PL_STRUCT_SIZE)
        monsters = mon.recv_mem_get(ids[3], abi.MAX_MONSTERS * abi.MONSTER_ENTRY_SIZE)
        screen = (self.read_screen() if ids[4] is None
                  else mon.recv_mem_get(ids[4], self.port.screen_cols * ROWS))
        overlay = mon.recv_mem_get(ids[5], 1)[0]
        ret = stack[(sp + 1) & 0xFF] | (stack[(sp + 2) & 0xFF] << 8)
        obs = Observation(self.step, stop.pc, sp, port01, ret, overlay, zp, player, monsters,
                          screen, decode_rows(screen, self.port.screen_cols), abi=abi)
        obs.mode, obs.stage = classify(obs, abi, self.command_ret, self.resident_prompts)
        self.last = obs
        return obs

    def read_screen(self) -> bytes:
        """The screen as C64 screen codes, for a port that keeps it otherwise
        (``Port.screen_decoder``)."""
        raise NotImplementedError(self.port.screen_decoder)

    def colors(self) -> bytes:
        """The screen's colours as C64 colour indexes (white where a port's
        colour has no C64 index)."""
        port = self.port
        raw = self.mon.mem_get(getattr(self.abi, port.color_const), port.screen_cols * ROWS,
                               self.mon.bank(port.color_bank))
        if not port.color_table:
            return bytes(c & 0x0F for c in raw)
        return bytes(self.color_index.get(c & port.color_mask, 1) for c in raw)

    def cpu_clock(self) -> int:
        """Exact emulated cycle count (costs one snapshot dump; CPU must be stopped)."""
        self.clock_path.parent.mkdir(parents=True, exist_ok=True)
        self.mon.dump(str(self.clock_path.resolve()), save_roms=False, save_disks=False)
        return snapshot_cpu_clock(self.clock_path)

    def ram_hash(self) -> str:
        # A full 0x0000-0xffff request reports length 0, so read two halves.
        ram = self.mon.mem_get(0x0000, 0x8000, self.ram) + self.mon.mem_get(0x8000, 0x8000, self.ram)
        return hashlib.sha256(ram).hexdigest()

    # -- running ----------------------------------------------------------

    def boot(self) -> Observation:
        """From a fresh VICE process: arm, run to the title menu, resolve sites."""
        self.arm()
        self.mon.resume()
        obs = self._run_to_input(time.monotonic())
        if self.port.key_feed == "return" and obs.pc not in self.key_exits:
            # The game is loaded now: stop in the wait loop instead (key_stops),
            # the same key wait, not a new step.
            self.arm()
            self.mon.resume()
            obs = self._run_to_input(time.monotonic())
            self.step -= 1
        self.resolve_sites()
        return self.observe(StopInfo(pc=obs.pc, registers=self.mon.registers()))

    def _run_to_input(self, wall0: float) -> Observation:
        mon = self.mon
        self.stats["resumes"] += 1
        clock0: int | None = None
        while True:
            remaining = self.resume_budget - (time.monotonic() - wall0)
            if remaining <= 0:
                raise EmulatorUnresponsive(f"no input stop within {self.resume_budget:.0f}s wall")
            try:
                stop = mon.wait_stop(timeout=min(self.poll_interval, remaining))
            except ViceTimeout:
                clock0, caught = self._interrupt_and_check(clock0)
                if caught is None:
                    continue
                stop = caught
            if stop.jam:
                raise GameFault("crash", f"CPU JAM at ${stop.pc:04X}", stop.pc)
            if stop.checkpoint in self.input_cps:
                self.step += 1
                jiffies0 = self.last.jiffies if self.last else None
                obs = self.observe(stop)
                wall = time.monotonic() - wall0
                self.stats["max_resume_wall"] = max(self.stats["max_resume_wall"], wall)
                if jiffies0 is not None:
                    self.stats["max_resume_jiffies"] = max(self.stats["max_resume_jiffies"],
                                                           (obs.jiffies - jiffies0) % (1 << 24))
                return obs
            if stop.checkpoint is not None and stop.checkpoint == self.seed_cp:
                self._apply_seed()
            elif stop.checkpoint in self.crash_cps:
                rom = self._rom_status(stop)
                if rom is not None:
                    raise GameFault("crash", f"KERNAL ${stop.pc:04X} entered with ROM visible ({rom})", stop.pc)
                self.stats["false_crash_hits"] += 1
            mon.resume()

    def _rom_status(self, stop: StopInfo) -> str | None:
        """How the KERNAL ROM shows as visible at a crash entry, or None when
        banked RAM code is running at that address instead."""
        if self.port.rom_status == "ted":   # TED $FF13 bit 0 reads 1 with the ROM selected
            ff13 = self.mon.mem_get(0xFF13, 1, self.io)[0]
            return f"$FF13=${ff13:02X}" if ff13 & 0x01 else None
        if self.port.rom_status == "mmu":   # C128 MMU configuration: bits 5-4 clear map the KERNAL
            cr = self.mon.mem_get(0xD500, 1, self.io)[0]
            return None if cr & 0x30 else f"$D500=${cr:02X}"
        regs = stop.registers or self.mon.registers()
        port01 = regs.get(self.reg_ids.get("01", 56), 0)   # $01 bit 1, HIRAM
        return f"$01=${port01:02X}" if port01 & 0x02 else None

    def _interrupt_and_check(self, clock0: int | None) -> tuple[int, StopInfo | None]:
        """Stop the CPU briefly during a long resume and check emulated time.

        The first interrupt records the clock; a later one raises a ``hang``
        when more than ``hang_emulated_seconds`` of emulated time has passed
        since then without reaching an input stop.

        A checkpoint that fired as the wait timed out is returned as the stop
        it is: discarding its event with the interrupt's own and resuming ran
        the CPU on past the input stop into the key-wait loop (M4 rounds
        65-74: three false ``hang`` findings under 32 parallel emulators,
        each with the PC in that loop).
        """
        mon = self.mon
        self.stats["interrupts"] += 1
        mon.ping()
        hits = [cp.number for event in mon.drain_events() if event.kind == RESP_CHECKPOINT_INFO
                for cp in (parse_checkpoint(event.body),) if cp.hit]
        regs = mon.registers()
        pc = regs.get(self.reg_ids.get("PC", 3), 0)
        if hits or pc in self.input_cps.values():
            self.stats["caught_stops"] = self.stats.get("caught_stops", 0) + 1
            at_entry = next((cp for cp, addr in self.input_cps.items() if addr == pc), self.input_cp)
            return (clock0 or 0), StopInfo(pc=pc, checkpoint=hits[-1] if hits else at_entry, registers=regs)
        clock = self.cpu_clock()
        if clock0 is None:
            clock0 = clock
        elapsed = (clock - clock0) / self.port.cycles_per_second
        if elapsed > self.hang_emulated_seconds:
            raise GameFault("hang", f"no input stop for {elapsed:.0f}+ emulated seconds", pc)
        mon.resume()
        return clock0, None

    def press(self, key: int) -> Observation:
        """Feed exactly one key at the current input stop and run to the next one."""
        mon = self.mon
        if self.port.key_feed == "return":
            assert self.last is not None   # stopped at a key entry
            exit_pc = self.key_exits[self.last.pc]
            ids = [(mon.send_mem_set(self.abi.igk_key, bytes([key]), self.ram), CMD_MEM_SET),
                   (mon.send_registers_set({self.reg_ids["A"]: key, self.reg_ids["PC"]: exit_pc}),
                    CMD_REGISTERS_SET)]
        else:
            ids = [(mon.send_mem_set(self.abi.KERNAL_KEYD, bytes([key]), self.ram), CMD_MEM_SET),
                   (mon.send_mem_set(self.abi.KBDBUF_COUNT, b"\x01", self.ram), CMD_MEM_SET)]
        resume_id = mon.send_resume()
        wall0 = time.monotonic()
        for request_id, command in ids:
            mon.wait(request_id, command)
        mon.finish_resume(resume_id)
        self.keylog.append(key)
        return self._run_to_input(wall0)

    # -- seeding ----------------------------------------------------------

    def seed_title(self, seed: int) -> None:
        """At the title stop: seed the RNG used by chargen, and arm the new-game reseed."""
        self.seed = seed
        self.mon.mem_set(self.abi.zp_rng_0, derive_rng(seed, 0), self.ram)
        self.seed_cp = self.mon.checkpoint_set(self.seed_site)

    def _apply_seed(self) -> None:
        self.mon.mem_set(self.abi.zp_rng_0, derive_rng(self.seed, 1), self.ram)
        if self.seed_cp is not None:
            self.mon.checkpoint_delete(self.seed_cp)
        self.seed_cp = None

    # -- snapshots --------------------------------------------------------

    def dump(self, path: Path) -> None:
        if self.mon.mem_get(self.abi.KBDBUF_COUNT, 1, self.ram)[0] != 0:
            raise RuntimeError("refusing to snapshot with a non-empty keyboard buffer")
        path.parent.mkdir(parents=True, exist_ok=True)
        self.mon.dump(str(path.resolve()), save_roms=False, save_disks=True)
        for bank in self.port.snapshot_banks:
            number = self.mon.bank(bank)
            # A full 0x0000-0xffff request reports length 0, so two halves.
            path.with_suffix(f".{bank}").write_bytes(self.mon.mem_get(0x0000, 0x8000, number)
                                                     + self.mon.mem_get(0x8000, 0x8000, number))

    def undump(self, path: Path) -> Observation:
        """Load a snapshot taken at an input stop and re-observe without resuming."""
        pc = self.mon.undump(str(path.resolve()))
        self.mon.drain_events()
        for bank in self.port.snapshot_banks:
            data = path.with_suffix(f".{bank}").read_bytes()
            self.mon.mem_set(0x0000, data[:0x8000], self.mon.bank(bank))
            self.mon.mem_set(0x8000, data[0x8000:], self.mon.bank(bank))
        self.arm()
        self.resolve_sites()  # classification needs the resident return sites
        if pc not in self.key_stops():
            raise RuntimeError(f"snapshot PC ${pc:04X} is not the input stop")
        self.keylog = []
        return self.observe(StopInfo(pc=pc, registers=self.mon.registers()))

    # -- scripted chargen ----------------------------------------------------

    @staticmethod
    def chargen_key(obs: Observation, name: str = "BOT", race: str = "H", klass: str = "A") -> int:
        """Scripted chargen through the real prompts (§6.4); default Half-Troll Warrior."""
        stage = obs.stage
        if stage == "title":
            return ord("N")
        if stage == "race":
            return ord(race)
        if stage in ("stats",):
            return KEY_RETURN
        if stage == "class":
            return ord(klass)
        if stage == "name":
            typed = obs.rows[4].strip()
            if len(typed) < len(name):
                return ord(name[len(typed)])
            return KEY_RETURN
        if stage == "sex":
            return ord("A")
        return KEY_SPACE
