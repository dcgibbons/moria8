"""Game driver: one-key sync, observation, mode detection, seeding (§6.3, §6.4, §6.7).

The only input checkpoint is the entry of ``input_get_key``. At every stop the
driver reads one batched observation, classifies the UI mode, and feeds exactly
one key by writing the KERNAL keyboard buffer (``$0277``/``$C6``). Feeding at
the entry means the game's poll loop runs once per key, which keeps
``zp_entropy`` (mixed into ``rng_seed``) deterministic.
"""

from __future__ import annotations

import hashlib
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

from .abi import KERNAL_KEYD, Abi
from .screen import decode_rows
from .vice import StopInfo, ViceMonitor, ViceTimeout

# KERNAL entry points that only run on a crash or reset. Banked RAM code can
# occupy the same addresses ($F000-$FFFA), so a hit is a crash only when the
# KERNAL ROM is visible ($01 bit 1, HIRAM, set).
KERNAL_RESET = 0xFCE2
KERNAL_NMI_WARM = 0xFE66

STACK_PAGE = 0x0100
KERNAL_JIFFY = 0x00A0      # 24-bit, big endian, 60 Hz; pauses while IRQs are masked
PAL_CYCLES_PER_SECOND = 985248

KEY_RETURN = 0x0D
KEY_SPACE = 0x20
KEY_RUNSTOP = 0x03


class Mode(str, Enum):
    COMMAND = "COMMAND"
    DISMISS = "DISMISS"
    CHARGEN = "CHARGEN"
    DEATH = "DEATH"
    DIRECTION = "DIRECTION"   # get_direction_target (added for M2 doors)
    STORE = "STORE"           # store screen (ui_store.s): menu and buy prompts
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
        return int.from_bytes(self.zp[KERNAL_JIFFY:KERNAL_JIFFY + 3], "big")

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


def find_jsr(code: bytes, base: int, target: int) -> int:
    """Address just after the first ``JSR target`` in ``code``."""
    needle = bytes([0x20, target & 0xFF, target >> 8])
    index = code.find(needle)
    if index < 0:
        raise RuntimeError(f"JSR ${target:04X} not found after ${base:04X}")
    return base + index + 3


class Game:
    """Drives one VICE process at the ``input_get_key`` sync point."""

    def __init__(self, monitor: ViceMonitor, abi: Abi, workdir: Path, *,
                 resume_budget: float = 60.0, hang_emulated_seconds: float = 300.0,
                 poll_interval: float = 1.0) -> None:
        self.mon = monitor
        self.abi = abi
        self.clock_path = workdir / "clock.vsf"
        self.resume_budget = resume_budget
        self.hang_emulated_seconds = hang_emulated_seconds
        self.poll_interval = poll_interval
        self.ram = 0
        self.io = 0
        self.reg_ids: dict[str, int] = {}
        self.input_cp = -1
        self.crash_cps: dict[int, int] = {}
        self.seed_cp: int | None = None
        self.seed: int = 0
        self.step = 0
        self.keylog: list[int] = []
        self.command_ret = 0
        self.resident_prompts: dict[int, str] = {}
        self.seed_site = 0
        self.last: Observation | None = None
        self.stats = {"resumes": 0, "interrupts": 0, "false_crash_hits": 0,
                      "max_resume_wall": 0.0, "max_resume_jiffies": 0}

    # -- setup ------------------------------------------------------------

    def arm(self) -> None:
        """(Re-)arm checkpoints; required after connect, undump, or restart."""
        mon = self.mon
        self.ram = mon.bank("ram")
        self.io = mon.bank("io")
        self.reg_ids = mon.load_register_ids()
        for cp in mon.checkpoint_list():
            mon.checkpoint_delete(cp.number)
        self.input_cp = mon.checkpoint_set(self.abi.input_get_key)
        self.crash_cps = {mon.checkpoint_set(addr): addr for addr in (KERNAL_RESET, KERNAL_NMI_WARM)}
        self.seed_cp = None

    def resolve_sites(self) -> None:
        """Find return/seed addresses by scanning resident code (needs a booted game)."""
        abi = self.abi
        code = self.mon.mem_get(abi.input_get_command, 64, self.ram)
        self.command_ret = find_jsr(code, abi.input_get_command, abi.input_get_key) - 1
        offset = self.command_ret + 1 - abi.input_get_command
        run_ret = find_jsr(code[offset:], self.command_ret + 1, abi.input_get_key) - 1
        code = self.mon.mem_get(abi.get_direction_target, 64, self.ram)
        direction_ret = find_jsr(code, abi.get_direction_target, abi.input_get_key) - 1
        self.resident_prompts = {run_ret: "run_direction", direction_ret: "direction"}
        code = self.mon.mem_get(abi.game_new_start, 160, self.ram)
        self.seed_site = find_jsr(code, abi.game_new_start, abi.rng_seed)

    # -- observation ------------------------------------------------------

    def observe(self, stop: StopInfo) -> Observation:
        mon, abi = self.mon, self.abi
        regs = stop.registers or mon.registers()
        sp = regs.get(self.reg_ids.get("SP", 4), 0)
        port01 = regs.get(self.reg_ids.get("01", 56), 0)
        ids = [
            mon.send_mem_get(0x0000, 256, self.ram),
            mon.send_mem_get(STACK_PAGE, 256, self.ram),
            mon.send_mem_get(abi.player_data, abi.PL_STRUCT_SIZE, self.ram),
            mon.send_mem_get(abi.monster_table, abi.MAX_MONSTERS * abi.MONSTER_ENTRY_SIZE, self.ram),
            mon.send_mem_get(abi.SCREEN_RAM, 1000, self.ram),
            mon.send_mem_get(abi.current_overlay, 1, self.ram),
        ]
        zp = mon.recv_mem_get(ids[0], 256)
        stack = mon.recv_mem_get(ids[1], 256)
        player = mon.recv_mem_get(ids[2], abi.PL_STRUCT_SIZE)
        monsters = mon.recv_mem_get(ids[3], abi.MAX_MONSTERS * abi.MONSTER_ENTRY_SIZE)
        screen = mon.recv_mem_get(ids[4], 1000)
        overlay = mon.recv_mem_get(ids[5], 1)[0]
        ret = stack[(sp + 1) & 0xFF] | (stack[(sp + 2) & 0xFF] << 8)
        obs = Observation(self.step, stop.pc, sp, port01, ret, overlay, zp, player, monsters,
                          screen, decode_rows(screen), abi=abi)
        obs.mode, obs.stage = classify(obs, abi, self.command_ret, self.resident_prompts)
        self.last = obs
        return obs

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
                clock0 = self._interrupt_and_check(clock0)
                continue
            if stop.jam:
                raise GameFault("crash", f"CPU JAM at ${stop.pc:04X}", stop.pc)
            if stop.checkpoint == self.input_cp:
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
                regs = stop.registers or mon.registers()
                port01 = regs.get(self.reg_ids.get("01", 56), 0)
                if port01 & 0x02:
                    raise GameFault("crash", f"KERNAL ${stop.pc:04X} entered with ROM visible "
                                    f"($01=${port01:02X})", stop.pc)
                self.stats["false_crash_hits"] += 1
            mon.resume()

    def _interrupt_and_check(self, clock0: int | None) -> int:
        """Stop the CPU briefly during a long resume and check emulated time.

        The first interrupt records the clock; a later one raises a ``hang``
        when more than ``hang_emulated_seconds`` of emulated time has passed
        since then without reaching an input stop.
        """
        mon = self.mon
        self.stats["interrupts"] += 1
        mon.ping()
        mon.drain_events()
        clock = self.cpu_clock()
        if clock0 is None:
            clock0 = clock
        elapsed = (clock - clock0) / PAL_CYCLES_PER_SECOND
        if elapsed > self.hang_emulated_seconds:
            pc = mon.registers().get(self.reg_ids.get("PC", 3), 0)
            raise GameFault("hang", f"no input stop for {elapsed:.0f}+ emulated seconds", pc)
        mon.resume()
        return clock0

    def press(self, key: int) -> Observation:
        """Feed exactly one key at the current input stop and run to the next one."""
        mon = self.mon
        ids = [mon.send_mem_set(KERNAL_KEYD, bytes([key]), self.ram),
               mon.send_mem_set(self.abi.KBDBUF_COUNT, b"\x01", self.ram)]
        resume_id = mon.send_resume()
        wall0 = time.monotonic()
        for request_id in ids:
            mon.wait(request_id, 0x02)
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

    def undump(self, path: Path) -> Observation:
        """Load a snapshot taken at an input stop and re-observe without resuming."""
        pc = self.mon.undump(str(path.resolve()))
        self.mon.drain_events()
        self.arm()
        self.resolve_sites()  # classification needs the resident return sites
        if pc != self.abi.input_get_key:
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
