"""CP/M Z80 backend for the playtester: ``cpm_runner --control`` over stdio."""

from __future__ import annotations

import hashlib
import json
import os
import select
import signal
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .abi import Abi
from .game import EmulatorUnresponsive, Game, GameFault, Observation, classify, derive_rng
from .launch import BUILD, parent_death_hook
from .ports import Port
from .screen import ROWS
from .vice import StopInfo

SCREEN_ROWS_VISIBLE = 24
Z80_STATE_SIZE = 64
STACK_CANARY_MAGIC = b"M8SK"
RUN_MAX_STEPS = 50_000_000

CPM_SPECIAL_KEYS: dict[int, bytes] = {
    0x9D: b"\x1b[D",   # left arrow -> CSI D
    0x1D: b"\x1b[C",   # right arrow -> CSI C
    0x91: b"\x1b[A",   # up arrow -> CSI A
    0x11: b"\x1b[B",   # down arrow -> CSI B
    0x14: b"\x08",     # PETSCII DEL/INST -> backspace
    0x03: b"\x1b",     # PETSCII RUN/STOP -> ESC
}


def cpm_keys(key: int) -> bytes:
    """Translate a PETSCII key code from the brain/tour into CP/M ASCII/CSI bytes."""
    if key in CPM_SPECIAL_KEYS:
        return CPM_SPECIAL_KEYS[key]
    if 0x41 <= key <= 0x5A:
        return bytes((key | 0x20,))   # unshifted PETSCII letter -> lowercase ASCII
    if 0xC1 <= key <= 0xDA:
        return bytes((key & 0x7F,))   # shifted PETSCII letter -> uppercase ASCII
    return bytes((key & 0xFF,))


def _decode_cpm_rows(raw_1920: bytes, cols: int) -> list[str]:
    rows = [
        "".join(chr(b) if 0x20 <= b < 0x7F else " " for b in raw_1920[r * cols:(r + 1) * cols])
        for r in range(SCREEN_ROWS_VISIBLE)
    ]
    rows.append(" " * cols)
    return rows


@dataclass
class CpmProcess:
    """One owned ``cpm_runner --control`` subprocess and its JSON-lines pipes."""

    worker: int
    workdir: Path
    disk: Path
    target: Port
    hang_emulated_seconds: float = 300.0
    proc: subprocess.Popen[bytes] | None = None
    args: list[str] = field(default_factory=list)
    log_path: Path | None = None
    _out: int = -1
    _buffer: bytes = b""

    def start_cpm(self) -> "CpmProcess":
        candidates = (
            self.disk / self.target.emulator,
            self.disk.parent / self.target.emulator,
            BUILD / self.target.out / self.target.emulator,
        )
        runner = next((cand for cand in candidates if cand.is_file()), candidates[-1])
        if not runner.is_file():
            raise FileNotFoundError(f"CP/M runner binary not found: {runner}")
        com_path = self.disk / self.target.program
        if not com_path.is_file():
            raise FileNotFoundError(f"CP/M program not found: {com_path}")
        self.args = [str(runner), "--control", "--workdir", str(self.disk), str(com_path)]
        self.log_path = self.workdir / "cpm_runner.log"
        log = self.log_path.open("ab")
        self.proc = subprocess.Popen(
            self.args,
            cwd=self.disk,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=log,
            start_new_session=True,
            preexec_fn=parent_death_hook(),
        )
        log.close()
        assert self.proc.stdout is not None
        self._out = self.proc.stdout.fileno()
        os.set_blocking(self._out, False)
        return self

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def send_line(self, payload: dict[str, Any]) -> None:
        if self.proc is None or self.proc.stdin is None or not self.alive():
            raise EmulatorUnresponsive("cpm_runner process is not running")
        encoded = (json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8")
        try:
            self.proc.stdin.write(encoded)
            self.proc.stdin.flush()
        except OSError as exc:
            raise EmulatorUnresponsive(f"cpm_runner stdin closed: {exc}") from exc

    def recv_line(self, timeout: float) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while b"\n" not in self._buffer:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("cpm_runner timed out")
            ready, _, _ = select.select([self._out], [], [], remaining)
            if not ready:
                raise TimeoutError("cpm_runner timed out")
            chunk = os.read(self._out, 65536)
            if not chunk:
                raise EmulatorUnresponsive("cpm_runner exited unexpectedly")
            self._buffer += chunk
        line, _, self._buffer = self._buffer.partition(b"\n")
        return json.loads(line.decode("utf-8"))

    def kill(self, grace: float = 2.0) -> None:
        proc, self.proc = self.proc, None
        self._out = -1
        if proc is None:
            return
        if proc.stdin is not None:
            if proc.poll() is None:
                try:
                    proc.stdin.write(b'{"cmd":"quit"}\n')
                    proc.stdin.flush()
                except OSError:
                    pass
            try:
                proc.stdin.close()
            except OSError:
                pass
        if proc.stdout is not None:
            try:
                proc.stdout.close()
            except OSError:
                pass
        if proc.poll() is not None:
            return
        try:
            proc.wait(timeout=min(grace, 0.5))
            return
        except subprocess.TimeoutExpired:
            pass
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        try:
            proc.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=grace)


@dataclass
class CpmMonitor:
    """Monitor-compatible JSON-lines adapter over ``CpmProcess``."""

    process: CpmProcess
    response_timeout: float = 60.0
    next_id: int = 0
    pending: dict[int, bytes] = field(default_factory=dict)

    def call(self, payload: dict[str, Any], timeout: float | None = None) -> dict[str, Any]:
        self.next_id += 1
        req_id = self.next_id
        msg = dict(payload, id=req_id)
        try:
            self.process.send_line(msg)
            res = self.process.recv_line(self.response_timeout if timeout is None else timeout)
        except TimeoutError:
            self.process.kill()
            raise EmulatorUnresponsive(f"cpm_runner did not respond to {payload.get('cmd')}") from None
        if not res.get("ok"):
            raise RuntimeError(f"cpm_runner {payload.get('cmd')} failed: {res.get('error', res)}")
        return res

    def bank(self, name: str) -> tuple[str, int]:
        return (name, 0)

    def load_register_ids(self) -> dict[str, int]:
        return {"PC": 0, "SP": 4}

    def checkpoint_list(self) -> list[object]:
        return []

    def mem_get(self, start: int, length: int, bank: tuple[str, int] = ("ram", 0)) -> bytes:
        res = self.call({"cmd": "read_mem", "addr": start, "len": length})
        return bytes.fromhex(res["hex"])

    def mem_set(self, start: int, data: bytes, bank: tuple[str, int] = ("ram", 0)) -> None:
        self.call({"cmd": "write_mem", "addr": start, "hex": data.hex()})

    def send_mem_get(self, start: int, length: int, bank: tuple[str, int] = ("ram", 0)) -> int:
        self.next_id += 1
        req_id = self.next_id
        self.pending[req_id] = self.mem_get(start, length, bank)
        return req_id

    def recv_mem_get(self, request_id: int, length: int) -> bytes:
        return self.pending.pop(request_id)


class CpmGame(Game):
    """``Game`` over ``cpm_runner --control`` (Z80 CP/M 2.2)."""

    def __init__(self, process: CpmProcess, abi: Abi, workdir: Path, *, port: Port,
                 resume_budget: float = 60.0, hang_emulated_seconds: float = 300.0) -> None:
        super().__init__(CpmMonitor(process, response_timeout=resume_budget), abi, workdir,  # type: ignore[arg-type]
                         resume_budget=resume_budget, hang_emulated_seconds=hang_emulated_seconds, port=port)
        self.process = process
        self.cpm_mon: CpmMonitor = self.mon  # type: ignore[assignment]
        self._last_regs: dict[str, int] = {}

    def arm(self, crash: bool = True) -> None:
        self.ram = ("ram", 0)
        self.io = ("ram", 0)
        self.screen_bank = ("ram", 0)
        self.map_bank = ("ram", 0)
        self.cpm_mon.call({"cmd": "clear_breakpoints"})
        self.cpm_mon.call({"cmd": "add_breakpoint", "addr": self.abi.input_get_key})
        self.input_cps = {1: self.abi.input_get_key}
        self.input_cp = 1
        self.crash_cps = {}

    def resolve_sites(self) -> None:
        self.command_ret = self.abi.game_loop_cmd_ret
        self.resident_prompts = {self.abi.game_loop_run_dir_ret: "run_direction"}

    def _run_to_input(self, wall0: float) -> Observation:
        self.stats["resumes"] += 1
        res = self.cpm_mon.call({"cmd": "run", "max_steps": RUN_MAX_STEPS}, timeout=self.resume_budget)
        reason = res.get("reason", "")
        pc = int(res.get("pc", 0))
        sp = int(res.get("sp", 0))
        if reason == "step_limit":
            raise GameFault("hang", f"no input breakpoint within {RUN_MAX_STEPS} Z80 steps", pc)
        if reason != "breakpoint":
            detail = res.get("exit_reason") or reason
            raise GameFault("crash", f"cpm_runner stopped ({reason}: {detail})", pc)
        self._last_regs = {"pc": pc, "sp": sp}
        self.step += 1
        obs = self.observe(StopInfo(pc=pc))
        self.stats["max_resume_wall"] = max(self.stats["max_resume_wall"], time.monotonic() - wall0)
        return obs

    def boot(self) -> Observation:
        self.arm()
        wall0 = time.monotonic()
        self.cpm_mon.call({"cmd": "ping"}, timeout=self.resume_budget)
        obs = self._run_to_input(wall0)
        self.resolve_sites()
        obs.mode, obs.stage = classify(obs, self.abi, self.command_ret, self.resident_prompts)
        self.last = obs
        return obs

    def observe(self, stop: StopInfo) -> Observation:
        abi, mon = self.abi, self.cpm_mon
        if not self._last_regs or self._last_regs.get("pc") != stop.pc:
            regs = mon.call({"cmd": "regs"})
            pc = int(regs["pc"])
            sp = int(regs["sp"])
        else:
            pc = self._last_regs["pc"]
            sp = self._last_regs["sp"]

        canary = mon.mem_get(abi.stack_canary, len(STACK_CANARY_MAGIC), self.ram)
        if canary != STACK_CANARY_MAGIC:
            raise GameFault("stack", f"Z80 stack canary corrupted: {canary!r}", pc)

        state = mon.mem_get(abi.z80_state, Z80_STATE_SIZE, self.ram)
        zp = bytearray(256)
        zp[:Z80_STATE_SIZE] = state
        zp[abi.zp_eff_resist] = mon.mem_get(abi.all_symbols["zp_eff_resist"][0], 1, self.ram)[0]
        zp[abi.eff_resist_cold_timer] = mon.mem_get(abi.all_symbols["eff_resist_cold_timer"][0], 1, self.ram)[0]

        ret_bytes = mon.mem_get(sp, 2, self.ram)
        ret = ret_bytes[0] | (ret_bytes[1] << 8)
        player = mon.mem_get(abi.player_data, abi.PL_STRUCT_SIZE, self.ram)
        monsters = mon.mem_get(abi.monster_table, abi.MAX_MONSTERS * abi.MONSTER_ENTRY_SIZE, self.ram)
        overlay = state[abi.abi_current_overlay - abi.z80_state]
        raw_screen = mon.mem_get(abi.cpm_char_shadow, self.port.screen_cols * SCREEN_ROWS_VISIBLE, self.ram)
        rows = _decode_cpm_rows(raw_screen, self.port.screen_cols)
        screen = raw_screen + (b" " * self.port.screen_cols)

        obs = Observation(
            self.step, pc, sp, 0, ret, overlay, bytes(zp), player, monsters, screen, rows, abi=abi
        )
        obs.mode, obs.stage = classify(obs, abi, self.command_ret, self.resident_prompts)
        self.last = obs
        return obs

    def colors(self) -> bytes:
        raw = self.cpm_mon.mem_get(self.abi.cpm_color_shadow, self.port.screen_cols * SCREEN_ROWS_VISIBLE, self.ram)
        return bytes(c & self.port.color_mask for c in raw) + (b"\x01" * self.port.screen_cols)

    def press(self, key: int) -> Observation:
        wall0 = time.monotonic()
        self.cpm_mon.call({"cmd": "send_keys", "bytes": list(cpm_keys(key))}, timeout=self.resume_budget)
        self.keylog.append(key)
        return self._run_to_input(wall0)

    def seed_title(self, seed: int) -> None:
        self.seed = seed
        self.cpm_mon.mem_set(self.rng_addr(), derive_rng(seed, 0), self.ram)
        self.cpm_mon.mem_set(self.abi.all_symbols["abi_entropy_poll"][0], b"\x00\x00\x00\x00", self.ram)

    def ram_hash(self) -> str:
        return hashlib.sha256(self.cpm_mon.mem_get(0x0000, 65536, self.ram)).hexdigest()

    def dump(self, path: Path) -> None:
        raise NotImplementedError("CP/M Z80 runs without snapshots")

    def undump(self, path: Path) -> Observation:
        raise NotImplementedError("CP/M Z80 runs without snapshots")
