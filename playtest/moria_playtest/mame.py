"""The MAME backend (§21.3): the Apple IIe, and later the Atari and BBC ports.

``mame_bridge.lua`` stops the emulator where the game's key wait reads its key
source and serves memory reads and writes over two FIFOs until a key is fed.
``MameGame`` is the ``Game`` driver over that bridge: the same observation,
classification and seeding, with the key fed as the value the wait reads.
MAME saves state only between timeslices, so these ports run without
snapshots: each character boots, and an unresponsive emulator ends it.
"""

from __future__ import annotations

import os
import select
import signal
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

from .abi import Abi
from .game import EmulatorUnresponsive, Game, GameFault, Observation, derive_rng
from .ports import Port
from .screen import ROWS
from .vice import StopInfo

BRIDGE = Path(__file__).with_name("mame_bridge.lua")
REG_IDS = {"PC": 0, "A": 1, "X": 2, "Y": 3, "SP": 4}


class BridgeClosed(Exception):
    """MAME exited or the bridge stopped answering."""


@dataclass
class Stop:
    kind: str     # "S" key wait, "H" hang
    pc: int
    sp: int
    a: int
    x: int
    y: int
    time: float   # emulated seconds


@dataclass
class MameProcess:
    """One owned MAME process and its bridge FIFOs."""

    worker: int
    workdir: Path
    disk: Path
    target: Port
    hang_emulated_seconds: float = 300.0
    proc: subprocess.Popen[bytes] | None = None
    args: list[str] = field(default_factory=list)
    log_path: Path | None = None
    _in: object = None
    _out: int = -1          # read end: a raw non-blocking descriptor
    _buffer: bytes = b""    # bytes read past the last complete line

    def start(self, rom_args: list[str], tap_spec: str, connect_timeout: float = 60.0) -> "MameProcess":
        fifo_in, fifo_out = self.workdir / "bridge.in", self.workdir / "bridge.out"
        for fifo in (fifo_in, fifo_out):
            fifo.unlink(missing_ok=True)
            os.mkfifo(fifo)
        cfg = self.workdir / "mame"
        cfg.mkdir(exist_ok=True)
        port = self.target
        self.args = ["mame", port.mame_machine, *rom_args,
                     *(arg for kind in ("cfg", "nvram", "state", "snapshot", "diff", "comment", "input")
                       for arg in (f"-{kind}_directory", str(cfg))),
                     port.mame_media, str(self.disk), "-video", "none", "-sound", "none", "-nothrottle",
                     "-autoboot_script", str(BRIDGE), "-autoboot_delay", "0"]
        env = dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy",
                   MORIA8_BRIDGE_IN=str(fifo_in), MORIA8_BRIDGE_OUT=str(fifo_out),
                   MORIA8_BRIDGE_ITEMS=port.mame_items, MORIA8_BRIDGE_TAPS=tap_spec,
                   MORIA8_BRIDGE_HANG=str(self.hang_emulated_seconds), MORIA8_BRIDGE_BOOT=port.mame_boot)
        self.log_path = self.workdir / "mame.log"
        log = self.log_path.open("ab")
        self.proc = subprocess.Popen(self.args, cwd=self.workdir, stdin=subprocess.DEVNULL, stdout=log,
                                     stderr=subprocess.STDOUT, env=env, start_new_session=True)
        log.close()
        # Opening a FIFO blocks until both ends are open; the bridge opens
        # "in" then "out", in the same order, once the machine has booted.
        deadline = time.monotonic() + connect_timeout
        self._in = self._open(fifo_in, os.O_WRONLY, deadline)
        self._out = self._open(fifo_out, os.O_RDONLY, deadline)   # type: ignore[assignment]
        return self

    def _open(self, path: Path, flags: int, deadline: float) -> object:
        while True:
            try:
                fd = os.open(path, flags | os.O_NONBLOCK)
                break
            except OSError:   # no reader yet on a write open
                if time.monotonic() > deadline or not self.alive():
                    self.kill()
                    raise BridgeClosed(f"MAME bridge did not open {path.name}")
                time.sleep(0.05)
        if flags == os.O_RDONLY:
            return fd
        os.set_blocking(fd, True)
        return os.fdopen(fd, "w")

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def send(self, line: str) -> None:
        try:
            self._in.write(line + "\n")   # type: ignore[attr-defined]
            self._in.flush()              # type: ignore[attr-defined]
        except (BrokenPipeError, OSError) as exc:
            raise BridgeClosed(str(exc)) from exc

    def receive(self, timeout: float) -> str:
        deadline = time.monotonic() + timeout
        while b"\n" not in self._buffer:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError
            if not select.select([self._out], [], [], min(remaining, 1.0))[0]:
                if not self.alive():
                    raise BridgeClosed("MAME exited")
                continue
            chunk = os.read(self._out, 1 << 16)
            if not chunk:
                raise BridgeClosed("MAME closed the bridge")
            self._buffer += chunk
        line, self._buffer = self._buffer.split(b"\n", 1)
        return line.decode("ascii")

    def kill(self, grace: float = 2.0) -> None:
        try:
            if self._in is not None:
                self._in.close()   # type: ignore[attr-defined]
            if self._out >= 0:
                os.close(self._out)
        except OSError:
            pass
        self._in, self._out, self._buffer = None, -1, b""
        proc, self.proc = self.proc, None
        if proc is None or proc.poll() is not None:
            return
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=grace)
        except ProcessLookupError:
            return
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=grace)


class MameMonitor:
    """The memory side of ``ViceMonitor`` over the bridge, for the code that
    reads game memory through ``game.mon``: banks are the bridge's names."""

    def __init__(self, process: MameProcess, port: Port, response_timeout: float = 60.0) -> None:
        self.process = process
        self.banks = {name: (space, offset) for name, space, offset in port.mame_banks}
        self.response_timeout = response_timeout
        self.pending: dict[int, bytes] = {}
        self.next_id = 0

    def bank(self, name: str) -> tuple[str, int]:
        """A driver bank: the bridge space and the offset of address 0 in it."""
        return self.banks.get(name, (name, 0))

    def mem_get(self, start: int, length: int, bank: tuple[str, int] = ("cpu", 0)) -> bytes:
        space, offset = bank
        out = b""
        while len(out) < length:   # keep each reply line a sensible size
            n = min(length - len(out), 0x4000)
            self.process.send(f"R {space} {offset + start + len(out):X} {n}")
            reply = self.process.receive(self.response_timeout)
            if not reply.startswith("D "):
                raise BridgeClosed(f"unexpected bridge reply {reply[:40]!r}")
            out += bytes.fromhex(reply[2:])
        return out

    def mem_set(self, start: int, data: bytes, bank: tuple[str, int] = ("cpu", 0)) -> None:
        space, offset = bank
        self.process.send(f"W {space} {offset + start:X} {data.hex()}")
        if self.process.receive(self.response_timeout) != "O":
            raise BridgeClosed("bridge write not acknowledged")

    # Pipelined reads (Game.observe) run one at a time over the bridge.
    def send_mem_get(self, start: int, length: int, bank: tuple[str, int] = ("cpu", 0)) -> int:
        self.next_id += 1
        self.pending[self.next_id] = self.mem_get(start, length, bank)
        return self.next_id

    def recv_mem_get(self, request_id: int, length: int) -> bytes:
        return self.pending.pop(request_id)


def apple2_keys(key: int) -> int:
    """The Apple IIe key that input_translate (platforms/apple2/input.s) turns
    into the PETSCII ``key`` the brain chose."""
    special = {0x9D: 0x08, 0x1D: 0x15, 0x91: 0x0B, 0x11: 0x0A, 0x14: 0x7F}
    if 0x41 <= key <= 0x5A:
        return key | 0x20           # unshifted letter: lower case
    if 0xC1 <= key <= 0xDA:
        return key & 0x7F           # shifted letter: upper case
    return special.get(key, key)


KEY_MAPS = {"apple2": apple2_keys}


def apple2_text(main: bytes, aux: bytes) -> bytes:
    """The 80-column text page as C64 screen codes, 25 rows (the 25th blank).

    Even columns are in aux RAM, odd in main, from ``$0400 + (row & 7) * $80
    + (row >> 3) * $28``, as platforms/apple2/screen_a2.s writes them."""
    out = bytearray(b"\x20" * 80 * ROWS)
    for row in range(24):
        base = (row & 7) * 0x80 + (row >> 3) * 0x28
        for col in range(80):
            code = (aux if col % 2 == 0 else main)[base + col // 2] & 0x7F   # bit 7 clear: inverse
            out[row * 80 + col] = APPLE2_TO_SCREEN_CODE[code]
    return bytes(out)


def a2_char_map(code: int) -> int:
    """platforms/apple2/main.s a2_char_map_aux: C64 screen code -> display code."""
    return (0xC0 if code == 0 else (code + 0x60) | 0x80 if code < 0x1B else (code + 0x40) | 0x80
            if code < 0x20 else code | 0x80 if code < 0x5B else (code + 0x40) | 0x80 if code < 0x60
            else 0xA0)


# Its inverse, bit 7 dropped (normal and inverse video alike); the first
# screen code wins where two share a display code ('@' over $40), and a code
# the map never writes reads as a space.
APPLE2_TO_SCREEN_CODE = bytes(next((sc for sc in range(0x80) if a2_char_map(sc) & 0x7F == code), 0x20)
                              for code in range(0x80))


class MameGame(Game):
    """``Game`` over the MAME bridge: no checkpoints, registers or snapshots."""

    def __init__(self, process: MameProcess, abi: Abi, workdir: Path, *, port: Port,
                 resume_budget: float = 60.0, hang_emulated_seconds: float = 300.0) -> None:
        super().__init__(MameMonitor(process, port), abi, workdir, resume_budget=resume_budget,  # type: ignore[arg-type]
                         hang_emulated_seconds=hang_emulated_seconds, port=port)
        self.process = process
        self.stop: Stop | None = None
        self.key_map = KEY_MAPS.get(port.key_map, lambda key: key)

    @staticmethod
    def tap_spec(abi: Abi, port: Port) -> str:
        """The bridge's taps: each read counts as the key wait only from inside
        input_get_key, not the routines after it that read the same source."""
        start, end = abi.input_get_key, getattr(abi, port.key_wait_end) - 1
        return ";".join(f"{kind},{getattr(abi, addr) if isinstance(addr, str) else addr:X},{start:X},{end:X}"
                        + (f",{getattr(abi, buffer):X}" if buffer else "")
                        for kind, addr, buffer in port.key_taps)

    def arm(self) -> None:
        self.ram = self.mon.bank("ram")             # type: ignore[assignment]
        self.io = self.mon.bank("io")               # type: ignore[assignment]
        self.screen_bank = self.mon.bank(self.port.screen_bank)   # type: ignore[assignment]
        self.map_bank = self.mon.bank(self.port.map_bank)         # type: ignore[assignment]
        self.reg_ids = dict(REG_IDS)
        self.input_cps, self.crash_cps = {}, {}

    def resolve_seed_site(self) -> None:
        pass   # no reseed on MAME (seed_title); the Apple's game_new_start is not loaded at the title

    def registers(self) -> dict[int, int]:
        stop = self.stop
        assert stop is not None
        # The key wait pushed key_wait_pushes bytes: report the stack pointer
        # of input_get_key's entry, where the driver reads its caller.
        return {0: self.abi.input_get_key, 1: stop.a, 2: stop.x, 3: stop.y,
                4: (stop.sp + self.port.key_wait_pushes) & 0xFF}

    def observe(self, stop: StopInfo) -> Observation:
        return super().observe(StopInfo(pc=stop.pc, registers=self.registers()))

    def read_screen(self) -> bytes:
        """The screen as C64 screen codes (Port.screen_decoder): the Apple
        IIe's text page, or a 24-row screen of screen codes, padded to 25."""
        if self.port.screen_decoder == "apple2_80":
            main = self.mon.mem_get(0x0400, 0x400, self.mon.bank("ram"))
            aux = self.mon.mem_get(0x0400, 0x400, self.mon.bank("aux"))
            return apple2_text(main, aux)
        cols = self.port.screen_cols
        shown = self.mon.mem_get(getattr(self.abi, self.port.screen_const), cols * 24,
                                 self.mon.bank(self.port.screen_bank))
        return shown + b"\x20" * cols

    def colors(self) -> bytes:
        """No port on MAME keeps C64 colours: all white."""
        return b"\x01" * (self.port.screen_cols * ROWS)

    def boot(self) -> Observation:
        self.arm()
        obs = self._run_to_input(time.monotonic())
        self.resolve_sites()
        return self.observe(StopInfo(pc=obs.pc))

    def _run_to_input(self, wall0: float) -> Observation:
        self.stats["resumes"] += 1
        remaining = self.resume_budget - (time.monotonic() - wall0)
        try:
            line = self.process.receive(max(remaining, 0.1))
        except TimeoutError:
            raise EmulatorUnresponsive(f"no key wait within {self.resume_budget:.0f}s wall") from None
        except BridgeClosed as exc:
            raise EmulatorUnresponsive(str(exc)) from exc
        kind, *fields = line.split()
        pc, sp, a, x, y = (int(f, 16) for f in fields[:5])
        self.stop = Stop(kind, pc, sp, a, x, y, float(fields[5]))
        if kind == "H":
            raise GameFault("hang", f"no key wait for {self.hang_emulated_seconds:.0f}+ emulated seconds", pc)
        self.step += 1
        obs = self.observe(StopInfo(pc=pc))
        self.stats["max_resume_wall"] = max(self.stats["max_resume_wall"], time.monotonic() - wall0)
        return obs

    def press(self, key: int) -> Observation:
        wall0 = time.monotonic()
        self.process.send(f"K {self.key_map(key):02X}")
        self.keylog.append(key)
        return self._run_to_input(wall0)

    def seed_title(self, seed: int) -> None:
        """MAME runs deterministically from the seeded title RNG; the new-game
        reseed point (a code breakpoint on VICE) has no MAME equivalent."""
        self.seed = seed
        self.mon.mem_set(self.abi.zp_rng_0, derive_rng(seed, 0), self.ram)

    def dump(self, path: Path) -> None:
        raise NotImplementedError("MAME ports run without snapshots")

    def undump(self, path: Path) -> Observation:
        raise NotImplementedError("MAME ports run without snapshots")
