#!/usr/bin/env python3
from __future__ import annotations

import re
import socket
import time
from dataclasses import dataclass
from pathlib import Path

PROMPT_RE = re.compile(rb"\([A-Z]:\$[0-9A-Fa-f]{4}\)\s*$")
SYMBOL_RE = re.compile(r"^\S+\s+\S:([0-9A-Fa-f]+)\s+(\S+)$")


def normalize_addr(addr: int | str) -> str:
    if isinstance(addr, int):
        return f"{addr & 0xFFFF:04X}"
    value = addr.strip().upper()
    if value.startswith("$"):
        value = value[1:]
    if len(value) > 4:
        value = value[-4:]
    return value.zfill(4)


@dataclass(frozen=True)
class TestSymbols:
    start_addr: str
    pass_addr: str
    fail_addr: str | None = None
    raw_start_addr: str | None = None
    raw_pass_addr: str | None = None
    raw_fail_addr: str | None = None


@dataclass(frozen=True)
class MonitorTestResult:
    passed: bool
    reason: str = ""
    last_status: str = ""

    @property
    def exit_code(self) -> int:
        return 0 if self.passed else 2


def parse_vs_symbols(vs_path: str | Path) -> dict[str, str]:
    symbols: dict[str, str] = {}
    for raw_line in Path(vs_path).read_text(encoding="utf-8").splitlines():
        match = SYMBOL_RE.match(raw_line.strip())
        if not match:
            continue
        addr, name = match.groups()
        symbols[name] = normalize_addr(addr)
    return symbols


def extract_test_symbols(vs_path: str | Path) -> TestSymbols:
    symbols = parse_vs_symbols(vs_path)
    raw_start_addr = symbols.get(".test_start")
    raw_pass_addr = symbols.get(".test_pass")
    raw_fail_addr = symbols.get(".test_fail")
    start_addr = raw_start_addr
    pass_addr = raw_pass_addr
    fail_addr = raw_fail_addr
    if not start_addr or not pass_addr:
        raise ValueError(f"missing .test_start/.test_pass in {vs_path}")
    return TestSymbols(
        start_addr=start_addr,
        pass_addr=pass_addr,
        fail_addr=fail_addr,
        raw_start_addr=raw_start_addr,
        raw_pass_addr=raw_pass_addr,
        raw_fail_addr=raw_fail_addr,
    )


class VICEConnector:
    def __init__(self, host: str = "127.0.0.1", port: int = 6510, timeout: float = 5.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.sock: socket.socket | None = None

    def _drain_after_prompt(self, data: bytes, quiet_window: float = 0.05) -> bytes:
        if self.sock is None:
            return data
        original_timeout = self.sock.gettimeout()
        try:
            self.sock.settimeout(quiet_window)
            while True:
                try:
                    chunk = self.sock.recv(4096)
                except socket.timeout:
                    break
                if not chunk:
                    break
                data += chunk
        finally:
            self.sock.settimeout(original_timeout)
        return data

    def connect(
        self,
        *,
        retries: int = 50,
        retry_delay: float = 0.1,
        debug: bool = False,
    ) -> None:
        last_error: Exception | None = None
        for _ in range(retries):
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(self.timeout)
            try:
                sock.connect((self.host, self.port))
            except OSError as exc:
                last_error = exc
                sock.close()
                time.sleep(retry_delay)
                continue
            self.sock = sock
            greeting = self.read_until_prompt(allow_partial=True)
            if debug and greeting:
                print(greeting)
            return
        raise ConnectionError(f"unable to connect to VICE monitor at {self.host}:{self.port}") from last_error

    def close(self) -> None:
        if self.sock is not None:
            try:
                self.sock.close()
            finally:
                self.sock = None

    def read_until_prompt(self, *, allow_partial: bool = False, deadline: float | None = None) -> str:
        if self.sock is None:
            raise RuntimeError("VICE connector is not connected")

        data = b""
        while True:
            if deadline is not None and time.monotonic() >= deadline:
                if allow_partial:
                    break
                raise TimeoutError("timed out waiting for monitor prompt")
            try:
                chunk = self.sock.recv(4096)
            except socket.timeout:
                if PROMPT_RE.search(data) or allow_partial:
                    break
                continue
            except ConnectionResetError as exc:
                raise ConnectionError("monitor connection reset") from exc
            if not chunk:
                raise ConnectionError("monitor connection closed")
            data += chunk
            if PROMPT_RE.search(data):
                data = self._drain_after_prompt(data)
                break
        return data.decode("ascii", errors="ignore")

    def send_command(
        self,
        command: str = "",
        *,
        debug: bool = False,
        expect_prompt: bool = True,
        deadline: float | None = None,
    ) -> str:
        if self.sock is None:
            raise RuntimeError("VICE connector is not connected")
        payload = command.rstrip("\n") + "\n"
        if debug:
            print(f">>> {payload.rstrip()}")
        self.sock.sendall(payload.encode("ascii"))
        if not expect_prompt:
            return ""
        response = self.read_until_prompt(deadline=deadline)
        if debug and response:
            print(response)
        return response

    def fill_memory(self, start_addr: int | str, end_addr: int | str, value: int | str, *, debug: bool = False) -> str:
        return self.send_command(
            f"f {normalize_addr(start_addr)} {normalize_addr(end_addr)} {normalize_addr(value)[-2:]}",
            debug=debug,
        )

    def poke(self, addr: int | str, value: int | str, *, debug: bool = False) -> str:
        return self.send_command(f"> {normalize_addr(addr)} {normalize_addr(value)[-2:]}", debug=debug)

    def set_register(self, register: str, value: int | str, *, debug: bool = False) -> str:
        return self.send_command(f"r {register.lower()}={normalize_addr(value)}", debug=debug)

    def load_prg(self, prg_path: str | Path, *, debug: bool = False) -> str:
        return self.send_command(f'load "{Path(prg_path).resolve()}" 0', debug=debug)

    def dump_snapshot(self, snapshot_path: str | Path, *, debug: bool = False) -> str:
        return self.send_command(f'dump "{Path(snapshot_path).resolve()}"', debug=debug)

    def undump_snapshot(self, snapshot_path: str | Path, *, debug: bool = False) -> str:
        if self.sock is None:
            raise RuntimeError("VICE connector is not connected")
        payload = f'undump "{Path(snapshot_path).resolve()}"\n'
        if debug:
            print(f">>> {payload.rstrip()}")
        self.sock.sendall(payload.encode("ascii"))
        time.sleep(0.1)
        self.close()
        self.connect(debug=debug)
        return ""

    def clear_breakpoints(self, *, debug: bool = False) -> str:
        return self.send_command("del", debug=debug)

    def break_at(self, addr: int | str, *, debug: bool = False) -> str:
        return self.send_command(f"break {normalize_addr(addr)}", debug=debug)

    def go(self, start_addr: int | str | None = None) -> str:
        if start_addr is None:
            return self.send_command("g", expect_prompt=False)
        return self.send_command(f"g {normalize_addr(start_addr)}", expect_prompt=False)

    def run_until(self, addr: int | str, *, timeout: float, debug: bool = False) -> str:
        deadline = time.monotonic() + timeout
        return self.send_command(f"until ${normalize_addr(addr)}", deadline=deadline, debug=debug)

    def reset_test_environment(self) -> None:
        self.fill_memory("0000", "00FF", "00")
        self.poke("FF00", "3E")
        self.poke("D506", "07")

    def wait_for_stop(
        self,
        *,
        pass_addr: int | str,
        fail_addr: int | str | None = None,
        timeout: float = 5.0,
    ) -> MonitorTestResult:
        deadline = time.monotonic() + timeout
        pass_marker = f"C:${normalize_addr(pass_addr)}"
        fail_marker = f"C:${normalize_addr(fail_addr)}" if fail_addr is not None else None
        try:
            last_status = self.read_until_prompt(deadline=deadline)
        except TimeoutError:
            return MonitorTestResult(False, f"timeout after {timeout}s", "")
        except ConnectionError as exc:
            return MonitorTestResult(False, str(exc), "")

        upper_status = last_status.upper()
        if pass_marker in upper_status:
            return MonitorTestResult(True, "", last_status)
        if fail_marker and fail_marker in upper_status:
            return MonitorTestResult(False, f"reached test_fail label at ${normalize_addr(fail_addr)}", last_status)
        if "JAM" in upper_status or "INVALID OPCODE" in upper_status:
            return MonitorTestResult(False, "CPU JAM", last_status)
        return MonitorTestResult(False, "stopped without reaching pass/fail breakpoint", last_status)


def run_test_case(
    connector: VICEConnector,
    *,
    prg_path: str | Path,
    start_addr: int | str,
    pass_addr: int | str,
    fail_addr: int | str | None = None,
    timeout: float = 5.0,
    reset_environment: bool = True,
    debug: bool = False,
) -> MonitorTestResult:
    if reset_environment:
        connector.fill_memory("0000", "00FF", "00", debug=debug)
        connector.poke("FF00", "3E", debug=debug)
        connector.poke("D506", "07", debug=debug)
    connector.load_prg(prg_path, debug=debug)
    connector.clear_breakpoints(debug=debug)
    connector.break_at(pass_addr, debug=debug)
    if fail_addr is not None:
        connector.break_at(fail_addr, debug=debug)
    connector.set_register("sp", "ff", debug=debug)
    connector.set_register("pc", start_addr, debug=debug)
    connector.go()
    return connector.wait_for_stop(pass_addr=pass_addr, fail_addr=fail_addr, timeout=timeout)
