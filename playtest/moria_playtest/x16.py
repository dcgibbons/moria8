"""The Commander X16 backend (§21.3): ``x16emu -testbench``.

The testbench has no breakpoints or snapshots. The game's key
wait yields to it when the X16 KERNAL has no key (``cx16_testbench_enabled``,
``jmp $FFFD``, platforms/cx16/input.s), and a key is fed as the existing
harness does: ``igk_char``, then ``RUN input_get_key_testbench_resume``.
Memory is read with an emulator patched for block reads (``RQB``, ``RQV``,
``STB``; docs/BACKLOG.md) when it has them, else one byte per ``RQM``,
pipelined; banked RAM through the testbench's ``RAM`` bank select, and
VERA's text through VRAM (``RQV``) or its address registers, each restored
after the read. Each character boots.
"""

from __future__ import annotations

import os
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

from .abi import Abi
from .game import EmulatorUnresponsive, Observation
from .mame import BridgeClosed, MameGame, MameProcess, Stop
from .ports import Port
from .vice import StopInfo

RAM_BANK_REG = 0x0000
BANK_WINDOW = 0xA000
BANK_SIZE = 0x2000
VERA_ADDR_L, VERA_ADDR_M, VERA_ADDR_H, VERA_DATA0, VERA_CTRL = 0x9F20, 0x9F21, 0x9F22, 0x9F23, 0x9F25
VERA_TEXT = 0x1B000   # VRAM text: 256 bytes a row, character then colour
FULL_MAP_EVERY = 50   # steps between whole-map reads (read_map)
ROOM_REACH = (25, 10)   # how far a lit room reaches from the character in it (rooms 3..23 x 3..8,
                        # DUNGEON_GENERATION_CONTRACT.md)
# Keys after which only the squares in view can have changed: moves, rest,
# search, open/close, bash, disarm, throw, fire, eat, refuel, look, pick up,
# wear, drop, and prompt answers. Anything else (read, quaff, cast, pray,
# use, aim, stairs) rereads the whole map.
LOCAL_KEYS = frozenset(b"HJKLYUBN5S#XGOCWD \r\x1b\x03\x02\x12") | {0xC4, 0xD4, 0xC6, 0xC5, 0xD2}


@dataclass
class X16Process(MameProcess):
    """One owned ``x16emu -testbench`` and its stdin/stdout."""

    def start_x16(self, emulator: str, rom: str, connect_timeout: float = 60.0) -> "X16Process":
        self.args = [emulator, "-testbench", "-warp", "-zeroram", "-rom", rom,
                     "-fsroot", str(self.disk), "-prg", str(self.disk / self.target.program)]
        env = dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
        self.log_path = self.workdir / "x16emu.log"
        self.proc = subprocess.Popen(self.args, cwd=self.workdir, stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env,
                                     text=True, start_new_session=True)
        self._in = self.proc.stdin
        assert self.proc.stdout is not None
        self._out = self.proc.stdout.fileno()   # read raw: receive() buffers whole lines
        os.set_blocking(self._out, False)
        self.ready(connect_timeout)
        return self

    def kill(self, grace: float = 2.0) -> None:
        """The read end is proc.stdout's descriptor: close it through its
        owner, once. Closing it raw left proc.stdout to close the same number
        again later, by then another file's (an X16 session ended in
        "Bad file descriptor", M6)."""
        out = self.proc.stdout if self.proc is not None else None
        self._out = -1
        super().kill(grace)
        if out is not None:
            out.close()

    def ready(self, timeout: float) -> None:
        """Wait for the testbench's prompt: at start, after a write, and when
        a RUN reaches the key wait's yield."""
        while True:
            line = self.receive(timeout)
            if line == "RDY":
                return
            if line.startswith(("ERR", "INV")):
                raise BridgeClosed(f"x16emu testbench: {line}")


class X16Monitor:
    """``game.mon`` over the testbench. Banks: ``("cpu", 0)`` the CPU's view,
    ``("bank", n)`` RAM bank n's window, ``("map", 0)`` the map's virtual
    addresses (MAP_BASE, Banks 1-2), ``("vera", 0)`` VERA text."""

    def __init__(self, process: X16Process, response_timeout: float = 60.0) -> None:
        self.process = process
        self.response_timeout = response_timeout
        self.pending: dict[int, bytes] = {}
        self.next_id = 0
        self.map_base = 0
        # A stock x16emu answers the block read "ERR ...": a byte at a time.
        process.send("RQB 0000 1")
        self.block = not process.receive(response_timeout).startswith("ERR")

    def bank(self, name: str) -> tuple[str, int]:
        return {"ram": ("cpu", 0), "io": ("cpu", 0)}.get(name, (name, 0))

    def _run(self, commands: list[str]) -> list[int]:
        """Send ``commands`` at once and return the bytes the reads answer."""
        self.process.send("\n".join(commands))
        values = []
        for command in commands:
            line = self.process.receive(self.response_timeout)
            if command.startswith("RQM"):
                values.append(int(line, 16))
            elif command.startswith(("RQB", "RQV")) and not line.startswith("ERR"):
                values += bytes.fromhex(line)
            elif line != "RDY":
                raise BridgeClosed(f"testbench answered {command!r} with {line!r}")
        return values

    def _banked(self, reads: list[tuple[int, int]]) -> bytes:
        """Bytes at (bank, address) pairs, the RAM bank restored after."""
        saved = self._run([f"RQM {RAM_BANK_REG:04X}"])[0]
        commands, bank, run = [], -1, None
        for b, addr in reads:
            if b != bank:
                commands.append(f"RAM {b:02X}")
                bank, run = b, None
            if self.block and run is not None and addr == run[0] + run[1]:
                run[1] += 1
                commands[-1] = f"RQB {run[0]:04X} {run[1]:X}"
            elif self.block:
                run = [addr, 1]
                commands.append(f"RQB {addr:04X} 1")
            else:
                commands.append(f"RQM {addr:04X}")
        commands.append(f"RAM {saved:02X}")
        return bytes(self._run(commands))

    def mem_get(self, start: int, length: int, bank: tuple[str, int] = ("cpu", 0)) -> bytes:
        kind, number = bank
        if kind == "cpu":
            if self.block:
                return bytes(self._run([f"RQB {start:04X} {length:X}"]))
            return bytes(self._run([f"RQM {addr:04X}" for addr in range(start, start + length)]))
        if kind == "bank":
            return self._banked([(number, addr) for addr in range(start, start + length)])
        if kind == "map":
            offsets = range(start - self.map_base, start - self.map_base + length)
            return self._banked([(1 + off // BANK_SIZE, BANK_WINDOW + off % BANK_SIZE) for off in offsets])
        if kind == "vera":
            return self.vera_text(start, length)
        raise ValueError(f"no X16 bank {bank!r}")

    def vera_text(self, start: int, length: int) -> bytes:
        """Screen characters for cells start..start+length of an 80-column screen."""
        if self.block:   # VRAM read directly: the data port is not touched
            commands = []
            for cell in range(start, start + length):
                r, c = divmod(cell, 80)
                if c == 0 or cell == start:
                    commands.append([VERA_TEXT + r * 256 + c * 2, 0])
                commands[-1][1] += 2
            data = self._run([f"RQV {addr:05X} {n:X}" for addr, n in commands])
            return bytes(data[::2])
        saved = self._run([f"RQM {reg:04X}" for reg in (VERA_ADDR_L, VERA_ADDR_M, VERA_ADDR_H, VERA_CTRL)])
        commands = [f"STM {VERA_CTRL:04X} 00", f"STM {VERA_ADDR_H:04X} {VERA_TEXT >> 16:02X}"]
        row = -1
        for cell in range(start, start + length):
            r, c = divmod(cell, 80)
            if r != row:
                commands.append(f"STM {VERA_ADDR_M:04X} {(VERA_TEXT >> 8 & 0xFF) + r:02X}")
                row = r
            commands += [f"STM {VERA_ADDR_L:04X} {c * 2:02X}", f"RQM {VERA_DATA0:04X}"]
        commands += [f"STM {reg:04X} {value:02X}" for reg, value in
                     zip((VERA_ADDR_L, VERA_ADDR_M, VERA_ADDR_H, VERA_CTRL), saved)]
        return bytes(self._run(commands))

    def mem_set(self, start: int, data: bytes, bank: tuple[str, int] = ("cpu", 0)) -> None:
        assert bank[0] == "cpu", bank
        if self.block:
            self._run([f"STB {start:04X} {data.hex()}"])
            return
        self._run([f"STM {start + i:04X} {value:02X}" for i, value in enumerate(data)])

    def send_mem_get(self, start: int, length: int, bank: tuple[str, int] = ("cpu", 0)) -> int:
        self.next_id += 1
        self.pending[self.next_id] = self.mem_get(start, length, bank)
        return self.next_id

    def recv_mem_get(self, request_id: int, length: int) -> bytes:
        return self.pending.pop(request_id)


class X16Game(MameGame):
    """``Game`` over the testbench: a stop is the key wait's yield."""

    def __init__(self, process: X16Process, abi: Abi, workdir: Path, *, port: Port,
                 resume_budget: float = 60.0, hang_emulated_seconds: float = 300.0) -> None:
        super().__init__(process, abi, workdir, port=port, resume_budget=resume_budget,
                         hang_emulated_seconds=hang_emulated_seconds)
        self.mon = X16Monitor(process)   # type: ignore[assignment]
        self.mon.map_base = abi.MAP_BASE
        self.map: bytearray | None = None   # read_map's copy of the level map
        self.map_dlvl = self.map_step = self.map_keys = 0

    def read_map(self) -> bytes:
        """The level map, most steps rereading only the squares in view and
        the room the character is in: the testbench reads a byte a command,
        and the whole 198x66 map every step cost each X16 driver a core (M6).
        The whole map is read again on a new level, after a key that can
        change squares out of sight (``LOCAL_KEYS``), and every
        ``FULL_MAP_EVERY`` steps. Two seeds' 5,600 steps matched a whole read
        on every square the bot uses (all but ``FLAG_OCCUPIED``)."""
        abi = self.abi
        cols, rows = abi.hal_layout_map_cols, abi.hal_layout_map_rows
        view_x, view_y, px, py, dlvl = self.mon._run([f"RQM {a:04X}" for a in (
            abi.zp_view_x, abi.zp_view_y, abi.zp_player_x, abi.zp_player_y, abi.zp_player_dlvl)])
        keys = self.keylog[self.map_keys:] if self.map_keys <= len(self.keylog) else self.keylog
        if self.map is None or dlvl != self.map_dlvl or self.step - self.map_step >= FULL_MAP_EVERY \
                or not set(keys) <= LOCAL_KEYS:
            self.map = bytearray(self.mon.mem_get(abi.MAP_BASE, cols * rows, ("map", 0)))
            self.map_step = self.step
        else:
            # The squares in view, and the room the character may have lit,
            # which can reach past the edge of the screen.
            x0 = max(min(view_x, px - ROOM_REACH[0]), 0)
            x1 = min(max(view_x + abi.hal_layout_viewport_w, px + ROOM_REACH[0] + 1), cols)
            y0 = max(min(view_y, py - ROOM_REACH[1]), 0)
            for y in range(y0, min(max(view_y + abi.hal_layout_viewport_h, py + ROOM_REACH[1] + 1), rows)):
                self.map[y * cols + x0:y * cols + x1] = self.mon.mem_get(abi.MAP_BASE + y * cols + x0,
                                                                         x1 - x0, ("map", 0))
        self.map_dlvl, self.map_keys = dlvl, len(self.keylog)
        return bytes(self.map)

    def read_screen(self) -> bytes:
        cols = self.port.screen_cols
        return self.mon.mem_get(0, cols * 24, ("vera", 0)) + b"\x20" * cols

    def boot(self) -> Observation:
        self.map = None
        self.arm()
        self.mon.mem_set(self.abi.cx16_testbench_enabled, b"\x01")
        self.process.send(f"RUN {self.abi.entry_bootstrap:04X}")
        obs = self._run_to_input(time.monotonic())
        self.resolve_sites()
        return self.observe(StopInfo(pc=obs.pc))

    def _run_to_input(self, wall0: float) -> Observation:
        self.stats["resumes"] += 1
        try:
            self.process.ready(max(self.resume_budget - (time.monotonic() - wall0), 0.1))
            sp = self._stack_pointer()
        except TimeoutError:
            raise EmulatorUnresponsive(f"no key wait within {self.resume_budget:.0f}s wall") from None
        except BridgeClosed as exc:
            raise EmulatorUnresponsive(str(exc)) from exc
        self.stop = Stop("S", self.abi.input_get_key, sp, 0, 0, 0, 0.0)
        self.step += 1
        obs = self.observe(StopInfo(pc=self.abi.input_get_key))
        self.stats["max_resume_wall"] = max(self.stats["max_resume_wall"], time.monotonic() - wall0)
        return obs

    def _stack_pointer(self) -> int:
        self.process.send("RSP")
        return int(self.process.receive(self.mon.response_timeout), 16) & 0xFF

    def press(self, key: int) -> Observation:
        wall0 = time.monotonic()
        self.mon.mem_set(self.abi.igk_char, bytes([key]))
        self.process.send(f"RUN {self.abi.input_get_key_testbench_resume:04X}")
        self.keylog.append(key)
        return self._run_to_input(wall0)

