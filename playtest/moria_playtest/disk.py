"""``make playtest-disk``: disk save/load edge cases, played through the real UI.

Each scenario boots the shipping disk with its own drives and save media,
lets the bot play a character where one is needed, and then drives Disk
Setup, saving, loading and the failure paths with scripted keys. Results are
checked against the game's state and the disk images themselves. Load faults
are injected through the monitor at ``hal_asset_load_prg_header``: the next N
calls of a file get its name changed, so the drive answers FILE NOT FOUND.
"""

from __future__ import annotations

import argparse
import json
import re
import socket
import struct
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from .game import Mode, Observation
from .goals import GOALS
from .launch import PLAYTEST_OUT, Build, allocate_port, check_disk
from .ports import PORTS, Port
from .recorder import SessionLog
from .session import Character
from .vice import CMD_MEM_GET, StopInfo
from .worker import Worker

D64_SIZE = 174848
MARKER = "moria8.id"   # what Disk Setup's initialize writes (and the only thing)
# The disk load a trip up to town makes: the generation overlay (64.GEN, 4.GEN);
# the C128 caches that in Bank 1 and loads only the cold chest overlay, for
# the store restock, from disk.
TOWN_LOAD = {"c64": ".gen", "plus4": ".gen", "c128": ".chest"}
ATTEMPTS = 3   # asset_load_retry's attempts on the Commodore ports
KERNAL_ST = 0x90   # the KERNAL's I/O status byte (C64, C128, Plus/4)
FULL_DISK_LEFT = 12   # blocks full_disk leaves free: fewer than any save
SAVE_PREFIX = "the.game"   # slot files (platforms/commodore/*/hal/storage.s)
DISK_SEED = 1003   # a seed whose Human Warrior reaches DL2 quickly (any seed works)


# core/player.s player_sync_from_zp: zero-page label -> (PL_ constant, byte)
ZP_PLAYER_FIELDS = (
    ("zp_player_x", ("PL_MAP_X", 0)), ("zp_player_y", ("PL_MAP_Y", 0)),
    ("zp_player_hp_lo", ("PL_HP_LO", 0)), ("zp_player_hp_hi", ("PL_HP_LO", 1)),
    ("zp_player_mhp_lo", ("PL_MHP_LO", 0)), ("zp_player_mhp_hi", ("PL_MHP_LO", 1)),
    ("zp_player_mp", ("PL_MANA", 0)), ("zp_player_mmp", ("PL_MAX_MANA", 0)),
    ("zp_player_lvl", ("PL_LEVEL", 0)), ("zp_player_dlvl", ("PL_DLEVEL", 0)),
    ("zp_player_ac", ("PL_AC", 0)), ("zp_player_food", ("PL_FOOD_LO", 0)),
    ("zp_player_food_hi", ("PL_FOOD_LO", 1)), ("zp_light_radius", ("PL_LIGHT_RAD", 0)),
)


class ScenarioFail(Exception):
    """A disk scenario saw the game do the wrong thing."""


class TextMonitor:
    """VICE's text remote monitor: the binary monitor cannot attach images."""

    def __init__(self, port: int) -> None:
        self.port = port
        self.sock: socket.socket | None = None

    def command(self, line: str, settle: float = 0.5) -> str:
        deadline = time.monotonic() + 10
        while self.sock is None:   # VICE may still be opening its server
            try:
                self.sock = socket.create_connection(("127.0.0.1", self.port), timeout=10)
            except ConnectionRefusedError:
                if time.monotonic() > deadline:
                    raise
                time.sleep(0.1)
        self.sock.sendall(line.encode() + b"\n")
        time.sleep(settle)
        self.sock.settimeout(0.5)
        out = b""
        try:
            while chunk := self.sock.recv(4096):
                out += chunk
        except socket.timeout:
            pass
        return out.decode("latin1")

    def drain(self) -> None:
        """Discard the prompts VICE writes at each monitor entry (a full socket would block it)."""
        if self.sock is None:
            return
        self.sock.settimeout(0)
        try:
            while self.sock.recv(65536):
                pass
        except (BlockingIOError, socket.timeout):
            pass

    def close(self) -> None:
        if self.sock is not None:
            self.sock.close()
            self.sock = None


@dataclass
class Rig:
    """One emulator with a scenario's drives, driven at the input stop."""

    port: Port
    build: Build
    run_dir: Path
    drive9: bool = True        # a second drive on the bus (empty unless attached)
    reu: bool = True           # C64: overlays come from the REU after boot
    worker: Worker | None = None
    text: TextMonitor | None = None
    obs: Observation | None = None
    screens: list[str] = field(default_factory=list)   # every screen seen, for the report
    readonly: dict[int, bool] = field(default_factory=dict)   # device -> attached write-protected

    def __post_init__(self) -> None:
        text_port = allocate_port(500)   # far above the binary monitors' range
        args = ["-remotemonitor", "-remotemonitoraddress", f"127.0.0.1:{text_port}"]
        if self.drive9:
            args += ["-drive9type", "1541", "-drive9truedrive"]
        if not self.reu and "-reu" in self.port.resource_args:
            args += ["+reu"]   # the port's REU off: overlays load from disk again
        self.worker = Worker(self.run_dir, 0, build=self.build, extra_args=tuple(args))
        self.text = TextMonitor(text_port)

    # -- keys and screens --------------------------------------------------

    @property
    def game(self):
        assert self.worker is not None and self.worker.game is not None
        return self.worker.game

    def screen(self) -> str:
        assert self.obs is not None
        return "\n".join(row.rstrip() for row in self.obs.rows)

    def press(self, key: int | str) -> Observation:
        code = ord(key) if isinstance(key, str) else key
        if self.text is not None:
            self.text.drain()
        self.obs = self.game.press(code)
        self.screens.append(self.screen())
        return self.obs

    def keys(self, sequence: str) -> Observation:
        for ch in sequence:
            self.press(ch)
        assert self.obs is not None
        return self.obs

    def expect(self, text: str) -> None:
        if text.lower() not in self.screen().lower():
            raise ScenarioFail(f"expected {text!r} on screen:\n{self.screen()}")

    def until(self, text: str, key: int | str, limit: int = 12) -> None:
        """Press ``key`` until ``text`` shows (a prompt a key or two away)."""
        for _ in range(limit):
            if text.lower() in self.screen().lower():
                return
            self.press(key)
        self.expect(text)

    # -- media -------------------------------------------------------------

    def attach(self, device: int, image: Path, *, readonly: bool = False) -> None:
        assert self.text is not None
        # File permissions cannot do it: tools/isolated.sh runs us as root in
        # a user namespace, so VICE opens a 0444 file read-write.
        self.set_readonly(device, readonly)
        # The connection stays open and is never sent "x": the binary monitor
        # holds the CPU at the input stop. Either "x" or closing the connection
        # made VICE resume the CPU at later checkpoints by itself, so the
        # harness saw stops whose CPU had run on.
        out = self.text.command(f'attach "{image}" {device}')
        if "error" in out.lower():
            raise ScenarioFail(f"attach {image.name} to {device}: {out.strip()}")

    def set_readonly(self, device: int, readonly: bool) -> None:
        """VICE's write-protect switch for the next attach."""
        self.game.mon.resource_set(f"AttachDevice{device}d0Readonly", int(readonly))   # VICE 3.7+
        self.readonly[device] = readonly

    def flush(self, device: int, image: Path) -> Path:
        """Detach and reattach ``image``: true drive emulation keeps written
        tracks in memory and writes them to the file only then."""
        self.attach(device, image, readonly=self.readonly.get(device, False))
        return image

    # -- play --------------------------------------------------------------

    def boot(self, seed: int = DISK_SEED) -> Observation:
        assert self.worker is not None
        self.obs = self.worker.start_at_title()
        self.game.seed_title(seed)
        return self.obs

    def play_to(self, goal: str, seed: int = DISK_SEED) -> Observation:
        """The bot plays a new character (from the title) to ``goal``."""
        assert self.worker is not None
        session = SessionLog(self.run_dir / "bot", {"mode": "disk", "goal": goal})
        character = Character(self.worker, GOALS[goal], seed, session)
        character.keep_worker = True
        result = character.play()
        if result.outcome != "reached":
            raise ScenarioFail(f"the bot did not reach {goal} ({result.outcome}: {result.findings})")
        self.obs = self.game.last
        return self.obs

    def fail_loads(self, count: int, name: str = "") -> list[str]:
        """Make the next ``count`` asset loads of a file whose name contains
        ``name`` fail. Returns the failed names.

        At the loader's entry the requested name's first character is changed,
        so the drive itself answers FILE NOT FOUND; the next call puts it back.
        Only data is patched: the emulator has already fetched the opcode at
        a stop (a patched Plus/4 JSR ran with half its operand changed), and
        once the text monitor has attached a disk VICE's binary monitor reads
        and writes a drive's registers."""
        game, abi = self.game, self.game.abi
        entry = abi.all_symbols["hal_asset_load_prg_header"][0]
        code = game.mon.mem_get(entry, 8, game.ram)
        cpu = game.mon.bank("cpu")
        cp = game.mon.checkpoint_set(entry)
        failed: list[str] = []
        patched: list[tuple[int, bytes]] = []   # (address, original first character)
        ids = game.reg_ids

        def fail(stop: StopInfo) -> None:
            if game.mon.mem_get(entry, 8, cpu) != code:
                return   # a ROM over the loader's RAM runs that address too
            while patched:
                address, original = patched.pop()
                game.mon.mem_set(address, original, game.ram)
            regs = stop.registers or {}
            length, lo, hi = (regs.get(ids[r], 0) for r in ("A", "X", "Y"))
            address = lo | hi << 8
            file = game.mon.mem_get(address, max(length, 1), game.ram).decode("latin1").lower()
            if len(failed) < count and name in file:
                failed.append(file)
                patched.append((address, game.mon.mem_get(address, 1, game.ram)))
                game.mon.mem_set(address, b"!", game.ram)   # no file on any disk starts with "!"
            elif len(failed) >= count:
                game.mon.checkpoint_delete(cp)
                del game.stop_hooks[cp]

        game.stop_hooks[cp] = fail
        return failed

    def drive_error(self, device: int) -> str:
        """The drive's own error message (the 1541's buffer at $02D5): what
        the game read, or will read, from its command channel."""
        mon = self.game.mon
        body = struct.pack("<BHHBH", 0, 0x02D5, 0x02D5 + 39, device - 7, 0)   # memspace 1 = drive 8
        raw = mon.call(CMD_MEM_GET, body).body[2:42]
        return raw.split(b"\x00")[0].decode("latin1")

    def lose_status_reads(self, count: int = 1, caller: str = "plus4_require_program_media") -> list[int]:
        """The next ``count`` Plus/4 drive status reads made by ``caller`` lose
        their first byte, as a JiffyDOS transfer the drive's disk-controller
        IRQ cut short does: ST reports a read timeout ($42). Only ST is
        patched, at the first READST after ``caller`` is entered. Returns the
        list the lost reads are counted in."""
        game, abi = self.game, self.game.abi
        entry = abi.all_symbols[caller][0]
        readst = abi.all_symbols["plus4_kernal_readst"][0]
        code = game.mon.mem_get(entry, 8, game.ram)
        cpu = game.mon.bank("cpu")
        cp_entry = game.mon.checkpoint_set(entry)
        cp_readst = game.mon.checkpoint_set(readst)
        lost: list[int] = []
        armed = [False]

        def enter(stop: StopInfo) -> None:
            if game.mon.mem_get(entry, 8, cpu) == code:   # not the KERNAL ROM at that address
                armed[0] = True

        def lose(stop: StopInfo) -> None:
            if not armed[0]:
                return
            armed[0] = False
            game.mon.mem_set(KERNAL_ST, b"\x42", game.ram)
            lost.append(entry)
            if len(lost) >= count:
                for cp in (cp_entry, cp_readst):
                    game.mon.checkpoint_delete(cp)
                    del game.stop_hooks[cp]

        game.stop_hooks[cp_entry] = enter
        game.stop_hooks[cp_readst] = lose
        return lost

    def retries(self) -> int:
        game = self.game
        return game.mon.mem_get(game.abi.all_symbols["asset_load_retries"][0], 1, game.ram)[0]

    def character(self) -> bytes:
        """Everything a save must bring back: the player record (with the
        fields play keeps in zero page, as player_sync_from_zp copies them),
        the pack and equipment."""
        game, abi = self.game, self.game.abi
        record = bytearray(game.mon.mem_get(abi.player_data, abi.PL_STRUCT_SIZE, game.ram))
        zp = game.mon.mem_get(0, 256, game.ram)
        for label, offset in ZP_PLAYER_FIELDS:
            record[getattr(abi, offset[0]) + offset[1]] = zp[abi.all_symbols[label][0]]
        inv = abi.all_symbols["inv_item_id"][0]
        inv_end = abi.all_symbols["inv_ego"][0] + (abi.all_symbols["inv_ego"][0] - abi.all_symbols["inv_flags"][0])
        return bytes(record) + game.mon.mem_get(inv, inv_end - inv, game.ram)

    def stop(self) -> None:
        if self.text is not None:
            self.text.close()
        if self.worker is not None:
            self.worker.stop()


# -- disk images ----------------------------------------------------------------

def c1541(*args: str) -> None:
    subprocess.run(["c1541", *args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def blank_d64(path: Path, name: str = "save,01") -> Path:
    path.unlink(missing_ok=True)
    c1541("-format", name, "d64", str(path))
    return path


DIR_ENTRY = re.compile(r'^\d+\s+"([^"]*)"\s+(?:del|seq|prg|usr|rel)\b', re.IGNORECASE)


def parse_listing(listing: str) -> list[str]:
    """File names in ``c1541 -list`` output, the header and free-blocks lines excluded."""
    return [m.group(1) for line in listing.splitlines() if (m := DIR_ENTRY.match(line.strip()))]


def d64_files(image: Path) -> list[str]:
    """File names in a .d64's directory."""
    return parse_listing(subprocess.run(["c1541", "-attach", str(image), "-list"], check=True,
                                        capture_output=True, text=True).stdout)


def d64_read(image: Path, name: str, out: Path) -> bytes | None:
    """A file's contents from a .d64 (None when it is not there)."""
    out.unlink(missing_ok=True)
    if name not in d64_files(image):
        return None
    c1541("-attach", str(image), "-read", f"{name},s", str(out))   # saves are SEQ files
    return out.read_bytes()


def d64_blocks_free(image: Path) -> int:
    listing = subprocess.run(["c1541", "-attach", str(image), "-list"], check=True,
                             capture_output=True, text=True).stdout
    match = re.search(r"^(\d+) blocks free", listing, re.MULTILINE)
    if not match:
        raise ScenarioFail(f"no free-block count for {image.name}")
    return int(match.group(1))


def has_save(image: Path) -> bool:
    """A Save Disk marker and at least one saved game (THE.GAME, THE.GAME2..)."""
    files = d64_files(image)
    return MARKER in files and any(name.startswith(SAVE_PREFIX) for name in files)


# -- flows (the screens and keys of the C64 UI; see the explore option) ------------

KEY_SAVE = 0xD3   # SHIFT+S: save and quit
KEY_QUIT = 0xD1   # SHIFT+Q: quit without saving


def save_first_time(rig: Rig, slot: str = "1") -> None:
    """SHIFT+S with no Disk Setup yet: Done with the shown save drive, take
    the disk, initialize it, pick ``slot``; the save ends at the title."""
    rig.press(KEY_SAVE)
    rig.expect("Disk Setup")
    rig.press("3")
    rig.expect("Insert a Save Disk")
    rig.press(" ")
    rig.expect("Initialize this disk?")
    rig.press("Y")
    rig.expect("Select Slot")
    rig.press(slot)
    rig.expect("N)ew  L)oad")


Action = int | str | Callable[["Rig"], None]


def answer(rig: Rig, prompts: list[tuple[str, Action]], end: str | Callable[[Rig], bool],
           limit: int = 16) -> None:
    """Answer each prompt ``(text, key or action)`` as it shows until ``end``
    (text on screen, or a test) holds; any other screen is a failure."""
    done = end if callable(end) else lambda r: end.lower() in r.screen().lower()
    for _ in range(limit):
        if done(rig):
            return
        screen = rig.screen().lower()
        for text, action in prompts:
            if text.lower() in screen:
                if callable(action):
                    action(rig)
                else:
                    rig.press(action)
                break
        else:
            raise ScenarioFail(f"unexpected screen waiting for {end!r}:\n{rig.screen()}")
    if not done(rig):
        raise ScenarioFail(f"never reached {end!r}:\n{rig.screen()}")


def swap_prompts(program: Path, save: Path) -> list[tuple[str, Action]]:
    """One drive: put in the disk each prompt asks for, then press a key. The
    Plus/4 asks for the Program Disk between initializing and the slot list
    (that list is an overlay); the C64 does not."""
    def insert(image: Path) -> Callable[[Rig], None]:
        def act(rig: Rig) -> None:
            rig.attach(8, image)
            rig.press(" ")
        return act
    return [("Insert program disk", insert(program)), ("Insert save disk", insert(save)),
            ("Insert a separate Save Disk", insert(save)), ("Initialize this disk?", "Y"),
            ("Select Slot", "1")]


def in_game(rig: Rig) -> bool:
    return rig.obs is not None and rig.obs.mode == Mode.COMMAND


def back_out(rig: Rig, want: Callable[[Rig], bool], limit: int = 6) -> None:
    """Dismiss messages and leave menus (space, then Q) until ``want`` holds."""
    for _ in range(limit):
        if want(rig):
            return
        screen = rig.screen()
        rig.press("Q" if "Q) Back" in screen else " ")
    if not want(rig):
        raise ScenarioFail(f"could not back out of:\n{rig.screen()}")


def save_failed(rig: Rig) -> bool:
    return any(text in rig.screen() for text in ("Disk is full.", "Disk is write-protected.", "Disk error"))


def at_title(rig: Rig) -> bool:
    return "N)ew  L)oad" in rig.screen()


def overwrite_slot(rig: Rig, slot: str) -> None:
    """SHIFT+S, a used ``slot``, Y to overwrite: the save starts."""
    rig.press(KEY_SAVE)
    rig.expect("Select Slot")
    rig.press(slot)
    rig.expect("Overwrite?")
    rig.press("Y")


def save_again(rig: Rig, slot: str = "1") -> None:
    """SHIFT+S after Disk Setup: the slot (overwriting), ending at the title."""
    rig.press(KEY_SAVE)
    answer(rig, [("Select Slot", slot), ("Y/N", "Y"), ("Press any key", " ")], "N)ew  L)oad")


def resume(rig: Rig, slot: str = "1") -> None:
    """L)oad at the title, ``slot``: back at the command prompt."""
    rig.press("L")
    rig.expect("Select Slot")
    rig.press(slot)
    if rig.obs is None or rig.obs.mode != Mode.COMMAND:
        raise ScenarioFail(f"resume did not reach the command prompt:\n{rig.screen()}")


def same_character(before: bytes, after: bytes) -> None:
    if before != after:
        diff = [i for i, (a, b) in enumerate(zip(before, after)) if a != b]
        raise ScenarioFail("resumed character differs at offsets "
                           + ", ".join(f"{i}: {before[i]:#04x}->{after[i]:#04x}" for i in diff[:12]))


# -- scenarios ----------------------------------------------------------------------

@dataclass
class Scenario:
    name: str
    run: Callable[[Rig, Path], None]   # the rig and a directory for its media
    doc: str
    drive9: bool = True
    reu: bool = True
    expect_fail: dict[str, str] = field(default_factory=dict)   # port -> the known defect
    ports: tuple[str, ...] = ()   # where it applies (default: every port the queue runs)


def s_save_resume(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    save = blank_d64(media / "save.d64")
    rig.attach(9, save)
    before = rig.character()
    save_first_time(rig)
    if not has_save(rig.flush(9, save)):
        raise ScenarioFail(f"no saved game on the save disk: {d64_files(save)}")
    resume(rig)
    same_character(before, rig.character())


def s_save_overwrite(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    rig.attach(9, blank_d64(media / "save.d64"))
    save_first_time(rig)
    resume(rig)
    for _ in range(3):
        rig.press("5")   # rest: food and turns move on
    after_rest = rig.character()
    save_again(rig)
    resume(rig)
    same_character(after_rest, rig.character())


def s_decline_init(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    save = blank_d64(media / "save.d64")
    rig.attach(9, save)
    rig.press(KEY_SAVE)
    answer(rig, [("3) Done", "3"), ("Insert a Save Disk", " ")], "Initialize this disk?")
    rig.press("N")
    back_out(rig, in_game)
    if d64_files(rig.flush(9, save)):
        raise ScenarioFail(f"declining wrote to the disk: {d64_files(save)}")
    save_first_time(rig)
    if not has_save(rig.flush(9, save)):
        raise ScenarioFail(f"no saved game after initializing: {d64_files(save)}")


def s_foreign_disk(rig: Rig, media: Path) -> None:
    save = blank_d64(media / "other.d64", "other game,og")
    payload = media / "other.prg"
    payload.write_bytes(bytes([0x01, 0x08]) + bytes(range(256)) * 8)
    c1541("-attach", str(save), "-write", str(payload), "other game")
    rig.play_to("enter_dungeon")
    rig.attach(9, save)
    save_first_time(rig)
    files = d64_files(rig.flush(9, save))
    if "other game" not in files or not has_save(save):
        raise ScenarioFail(f"the other game's file or the save is missing: {files}")
    resume(rig)


def unformatted_d64(path: Path) -> Path:
    """A .d64 whose every sector reads as error 21 (no sync): a never-formatted disk."""
    path.write_bytes(bytes(D64_SIZE) + bytes([0x03]) * 683)
    return path


def s_unformatted_disk(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    rig.attach(9, unformatted_d64(media / "unformatted.d64"))
    rig.press(KEY_SAVE)
    answer(rig, [("3) Done", "3"), ("Insert a Save Disk", " "), ("Initialize this disk?", "Y")],
           "Could not initialize disk.")
    save = blank_d64(media / "save.d64")
    rig.attach(9, save)
    answer(rig, [("Press any key", " "), ("3) Done", "3"), ("Insert a Save Disk", " "),
                 ("Initialize this disk?", "Y"), ("Select Slot", "1")], "N)ew  L)oad")
    if not has_save(rig.flush(9, save)):
        raise ScenarioFail(f"no saved game after recovering: {d64_files(save)}")


def s_program_drive_as_save(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    before = Path(rig.worker.disk).read_bytes()
    rig.press(KEY_SAVE)
    answer(rig, [("3) Done", "2")], "Save drive (8-11)")
    rig.keys("8\r")
    answer(rig, [("3) Done", "3"), ("Press any key", " ")], "Program disk cannot hold saves.")
    if rig.flush(8, Path(rig.worker.disk)).read_bytes() != before:
        raise ScenarioFail("the Program Disk was written to")


def s_write_protected(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    save = blank_d64(media / "save.d64")
    rig.attach(9, save)
    save_first_time(rig)
    resume(rig)
    image = rig.flush(9, save).read_bytes()
    rig.attach(9, save, readonly=True)
    overwrite_slot(rig, "1")
    for _ in range(6):   # until an error shows, or the save "succeeds" to the title
        if "protect" in rig.screen().lower() or "error" in rig.screen().lower() or at_title(rig):
            break
        rig.press("Y" if "Y/N" in rig.screen() and "Saving" not in rig.screen() else " ")
    changed = rig.flush(9, save).read_bytes() != image
    if at_title(rig):
        raise ScenarioFail("saving to a write-protected disk returned to the title with no error"
                           + (" (and the image changed: VICE wrote it)" if changed else
                              " (the image is unchanged: the save was lost silently)"))
    rig.expect("Disk is write-protected.")
    if changed:
        raise ScenarioFail("the write-protected image changed")
    back_out(rig, in_game)


def s_full_disk(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    save = blank_d64(media / "save.d64")
    rig.attach(9, save)
    save_first_time(rig)
    rig.flush(9, save)
    filler = media / "filler.seq"
    # Leave fewer free blocks than a save takes (26 on the C64, 62 on the
    # C128), so the write runs out: the drive's 72 DISK FULL. Filling to 0
    # free made the DOS search past track 35 (67 ILLEGAL TRACK OR SECTOR).
    filler.write_bytes(bytes(254 * (d64_blocks_free(save) - FULL_DISK_LEFT)))
    c1541("-attach", str(save), "-write", str(filler), "filler,s")
    rig.attach(9, save)
    resume(rig)
    first = d64_read(save, SAVE_PREFIX, media / "slot1.bin")
    rig.press(KEY_SAVE)
    answer(rig, [("Select Slot", "2"), ("Y/N", "Y"), ("-more-", " ")], save_failed)
    # The 1541 says 72 DISK FULL, or, when its search runs past track 35,
    # 67 ILLEGAL TRACK OR SECTOR: the game names only the first.
    drive = rig.drive_error(9)
    if not drive.startswith(("72", "67")):
        raise ScenarioFail(f"the fill did not run the disk out: the drive says {drive!r}")
    rig.expect("Disk is full." if drive.startswith("72") else "Disk error")
    back_out(rig, in_game)
    overwrite_slot(rig, "1")   # overwriting slot 1 needs room too
    for _ in range(6):
        if save_failed(rig) or at_title(rig):
            break
        rig.press(" ")
    if d64_read(rig.flush(9, save), SAVE_PREFIX, media / "slot1-after.bin") != first:
        raise ScenarioFail("a failed save on a full disk lost or changed the slot 1 save")


def s_load_empty_slot(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    rig.attach(9, blank_d64(media / "save.d64"))
    save_first_time(rig)
    rig.press("L")
    rig.expect("Select Slot")
    rig.press("2")
    if in_game(rig):
        raise ScenarioFail("an empty slot started a game")
    back_out(rig, at_title)
    resume(rig)


def s_swap_save_resume(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    program = Path(rig.worker.disk)
    save = blank_d64(media / "save.d64")
    before = rig.character()
    swaps = swap_prompts(program, save)
    rig.press(KEY_SAVE)
    answer(rig, [("3) Done", "1"), *swaps], at_title)
    rig.press("L")
    answer(rig, [("3) Done", "1"), *swaps], in_game)
    same_character(before, rig.character())


def s_program_disk_as_save(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    rig.press(KEY_SAVE)
    answer(rig, [("3) Done", "1")], "Insert a separate Save Disk")
    rig.press(" ")   # the Program Disk is still in the drive
    rig.expect("Program disk cannot hold saves.")
    save = blank_d64(media / "save.d64")
    rig.press(" ")
    answer(rig, swap_prompts(Path(rig.worker.disk), save), at_title)
    if not has_save(rig.flush(8, save)):
        raise ScenarioFail(f"no saved game after the right disk: {d64_files(save)}")


def up_to_town(rig: Rig) -> None:
    """``<`` on the up staircase the descent left the player on."""
    rig.press("<")
    if not in_game(rig) or rig.obs is None or rig.obs.dlvl != 0:
        raise ScenarioFail(f"not back in town after <:\n{rig.screen()}")


def s_load_retry_town(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    name = rig.character()[:16]
    failed = rig.fail_loads(1, TOWN_LOAD[rig.port.name])
    before = rig.retries()
    up_to_town(rig)
    if len(failed) != 1 or (rig.retries() - before) % 256 != 1:
        raise ScenarioFail(f"expected one failed and one repeated load: {failed}, "
                           f"{(rig.retries() - before) % 256} repeated")
    if rig.character()[:16] != name:
        raise ScenarioFail("a different character after the trip to town")


def s_load_retry_resume(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    rig.attach(9, blank_d64(media / "save.d64"))
    before = rig.character()
    save_first_time(rig)
    failed = rig.fail_loads(1)
    retries = rig.retries()
    resume(rig)
    if len(failed) != 1 or (rig.retries() - retries) % 256 != 1:
        raise ScenarioFail(f"expected one failed and one repeated load: {failed}, "
                           f"{(rig.retries() - retries) % 256} repeated")
    same_character(before, rig.character())


def s_status_retry_resume(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    rig.attach(9, blank_d64(media / "save.d64"))
    before = rig.character()
    save_first_time(rig)
    lost = rig.lose_status_reads(1)
    resume(rig)
    if len(lost) != 1:
        raise ScenarioFail(f"expected one lost status read, saw {len(lost)}")
    same_character(before, rig.character())


def s_load_fail_town(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    name = rig.character()[:16]
    attempts = ATTEMPTS
    failed = rig.fail_loads(attempts, TOWN_LOAD[rig.port.name])
    try:
        up_to_town(rig)
    except Exception as exc:   # a restart or a crash
        raise ScenarioFail(f"a load that never succeeds lost the game: {type(exc).__name__}: "
                           f"{str(exc).splitlines()[0]}") from None
    if len(failed) != attempts:
        raise ScenarioFail(f"expected {attempts} failed loads: {failed}")
    if rig.character()[:16] != name:
        raise ScenarioFail("a load that never succeeds lost the game (a new character)")


def s_quit_confirm(rig: Rig, media: Path) -> None:
    rig.play_to("enter_dungeon")
    before = rig.character()
    rig.press(KEY_QUIT)
    rig.expect("Do you really want to quit? Y/N")
    rig.press("N")
    if not in_game(rig):
        raise ScenarioFail(f"N did not return to the game:\n{rig.screen()}")
    if "really want to quit" in rig.screen():
        raise ScenarioFail("the answered question stayed on the message line")
    same_character(before, rig.character())   # no turn taken
    rig.press(KEY_QUIT)
    rig.expect("Do you really want to quit? Y/N")
    rig.press("Y")
    if not at_title(rig):
        raise ScenarioFail(f"Y did not quit to the title:\n{rig.screen()}")


SCENARIOS = [
    Scenario("save_resume", s_save_resume,
             "first save to a blank disk in drive 9 (initialize it), resume from the title"),
    Scenario("save_overwrite", s_save_overwrite, "save over slot 1 after playing on; the newer game loads"),
    Scenario("decline_init", s_decline_init, "a blank save disk, initialize declined: nothing written, then accepted"),
    Scenario("foreign_disk", s_foreign_disk, "another program's disk as the save disk: its files survive"),
    Scenario("unformatted_disk", s_unformatted_disk, "a never-formatted save disk fails cleanly; a good one then works"),
    Scenario("program_drive_as_save", s_program_drive_as_save,
             "drive 8 (the Program Disk) picked as the save drive: refused, nothing written"),
    Scenario("write_protected", s_write_protected, "saving to a write-protected save disk: reported, image unchanged"),
    Scenario("full_disk", s_full_disk, "a new save on a full save disk: reported"),
    Scenario("load_empty_slot", s_load_empty_slot, "loading an empty slot does not start a game"),
    Scenario("swap_save_resume", s_swap_save_resume,
             "one drive: swap to a blank save disk, save, swap back; resume the same way", drive9=False),
    Scenario("program_disk_as_save", s_program_disk_as_save,
             "one drive: the Program Disk left in when asked for the save disk is refused", drive9=False),
    Scenario("quit_confirm", s_quit_confirm, "SHIFT+Q asks first: N plays on (no turn taken), Y quits",
             drive9=False),
    Scenario("load_retry_town", s_load_retry_town,
             "one failed load on the way up to town is repeated: play goes on", reu=False),
    Scenario("load_retry_resume", s_load_retry_resume,
             "one failed load while resuming from the title is repeated", reu=False,
             ports=("c64", "plus4")),   # the C128 resumes through its own runtime loader
    Scenario("status_retry_resume", s_status_retry_resume,
             "a drive status read cut short while resuming is asked again", ports=("plus4",)),
    Scenario("load_fail_town", s_load_fail_town,
             "a load on the way up to town that never succeeds keeps the game", reu=False,
             expect_fail={port: "restarts or crashes (backlog: one fatal-load handler)"
                          for port in ("c64", "plus4", "c128")}),
]


class RunSummary:
    """``summary.json`` in the run directory, rewritten as each scenario
    starts and ends, so the dashboard shows a run in progress."""

    def __init__(self, out: Path, port: Port, scenarios: list[Scenario]) -> None:
        self.path = out / "summary.json"
        self.data: dict[str, object] = {
            "port": port.name, "started": time.strftime("%Y-%m-%dT%H:%M:%S"), "finished": None,
            "scenarios": [{"name": sc.name, "doc": sc.doc, "outcome": "pending", "seconds": None,
                           "detail": "", "known": sc.expect_fail.get(port.name, "")} for sc in scenarios]}
        self.write()

    def update(self, name: str, **fields: object) -> None:
        for row in self.data["scenarios"]:   # type: ignore[union-attr]
            if row["name"] == name:
                row.update(fields)
        self.write()

    def finish(self) -> None:
        self.data["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S")
        self.write()

    def write(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.data, indent=1))
        tmp.replace(self.path)


def run_scenario(port: Port, scenario: Scenario, out: Path) -> tuple[str, str]:
    run_dir = out / scenario.name
    media = run_dir / "media"
    media.mkdir(parents=True, exist_ok=True)
    rig = Rig(port, Build.shipping(port), run_dir, drive9=scenario.drive9, reu=scenario.reu)
    started = time.monotonic()
    outcome, detail = "error", "interrupted"   # what the finally records if run() never returns
    try:
        scenario.run(rig, media)
        outcome, detail = "pass", ""
    except ScenarioFail as exc:
        outcome, detail = "fail", str(exc)
    except Exception as exc:   # an emulator or harness error is a failure too, with its cause
        outcome, detail = "error", f"{type(exc).__name__}: {exc}"
    finally:
        (run_dir / "screens.txt").write_text("\n=====\n".join(rig.screens))
        (run_dir / "result.txt").write_text(f"{outcome}\n{detail}\n")
        rig.stop()
    if port.name in scenario.expect_fail:
        outcome = {"pass": "xpass", "fail": "xfail"}.get(outcome, outcome)
    print(f"  {scenario.name:24s} {outcome:6s} {time.monotonic() - started:6.1f}s  {detail.splitlines()[0] if detail else ''}",
          flush=True)
    return outcome, detail


def explore(port: Port, keys: str, drive9: bool, reu: bool, play: str | None, blank9: bool) -> int:
    """Print the screen after each key, from the title or after the bot has
    played to ``play`` (finding a flow's prompts)."""
    run_dir = PLAYTEST_OUT / "disk" / f"explore-{port.name}"
    rig = Rig(port, Build.shipping(port), run_dir, drive9=drive9, reu=reu)
    try:
        if play:
            rig.play_to(play)
        else:
            rig.boot()
        if blank9:
            rig.attach(9, blank_d64(run_dir / "blank9.d64"))
        print(rig.screen())
        for ch in keys.encode().decode("unicode_escape"):
            rig.press(ch)
            print(f"--- after {ch!r}")
            print(rig.screen())
    finally:
        rig.stop()
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default="c64", choices=sorted(PORTS))
    parser.add_argument("--explore", help="keys to press from the title, printing each screen")
    parser.add_argument("--no-drive9", action="store_true")
    parser.add_argument("--no-reu", action="store_true")
    parser.add_argument("--play", help="explore: let the bot play to this goal first")
    parser.add_argument("--blank9", action="store_true", help="explore: a blank disk in drive 9")
    parser.add_argument("--scenarios", help="comma-separated scenario names (default: all)")
    args = parser.parse_args(argv)
    port = PORTS[args.port]
    if port.backend != "vice":
        print(f"playtest-disk: {port.name} is not covered yet: the scenarios swap media "
              "through VICE's monitor (docs/AI_PLAYTEST_DESIGN.md)", file=sys.stderr)
        return 2
    check_disk(Build.shipping(port))
    if args.explore is not None:
        return explore(port, args.explore, not args.no_drive9, not args.no_reu, args.play, args.blank9)
    chosen = [sc for sc in SCENARIOS if (not args.scenarios or sc.name in args.scenarios.split(","))
              and (not sc.ports or port.name in sc.ports)]
    out = PLAYTEST_OUT / "disk" / f"{time.strftime('%Y%m%d-%H%M%S')}-{port.name}"
    print(f"disk scenarios on {port.name}: {out}", flush=True)
    summary = RunSummary(out, port, chosen)
    outcomes = []
    for sc in chosen:
        summary.update(sc.name, outcome="running")
        started = time.monotonic()
        outcome, detail = run_scenario(port, sc, out)
        summary.update(sc.name, outcome=outcome, seconds=round(time.monotonic() - started, 1),
                       detail=detail.splitlines()[0][:300] if detail else "")
        outcomes.append(outcome)
    summary.finish()
    bad = [o for o in outcomes if o in ("fail", "error", "xpass")]
    print(f"{len(outcomes) - len(bad)}/{len(outcomes)} as expected", flush=True)
    return 1 if bad or not outcomes else 0


if __name__ == "__main__":
    sys.exit(main())
