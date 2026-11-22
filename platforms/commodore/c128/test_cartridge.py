#!/usr/bin/env python3
"""Exercise the Commodore 128 Magic Desk 128 cartridge and persistence in x128.

Every launched emulator is bounded to 30 seconds; monitor operations share
that deadline. Scratch and logs belong under the caller's build directory.
"""
from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import argparse
import errno
import json
import os
import pty
import re
import shutil
import subprocess
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
import catalog_disk  # noqa: E402
import make_c128_md128  # noqa: E402
from vice_config import vice_config  # noqa: E402
from vice_connector import PROMPT_RE, VICEConnector, allocate_free_port  # noqa: E402

MONITOR_ERROR_RE = re.compile(
    r"(?im)^\s*(?:ERROR\b|Unknown command|Syntax error|Invalid argument|Unknown resource)"
)


def symbols(path: Path) -> dict[str, int]:
    out: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line.startswith(".label "):
            continue
        name, rhs = line[7:].split("=", 1)
        val = rhs.split()[0]
        if val.startswith("$"):
            out[name] = int(val[1:], 16)
    return out


def screen_bytes(text: str) -> bytes:
    return bytes(ord(ch) - 0x60 if "a" <= ch <= "z" else ord(ch) for ch in text)


def prepare_run(args: argparse.Namespace) -> None:
    base = args.output.resolve()
    base.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    args.output = Path(tempfile.mkdtemp(prefix=f"run-{stamp}-", dir=base))
    print(f"Evidence: {args.output}", flush=True)


def build_vice_command(
    vice: str,
    port: int,
    *,
    ntsc: bool = False,
    crt: Path | None = None,
    raw_bin: Path | None = None,
    drive8: Path | None = None,
    drive8_ro: bool = False,
    drive9: Path | None = None,
    autostart: Path | None = None,
) -> list[str]:
    media: list[str] = []
    if crt is not None:
        media += ["-cartcrt", str(crt)]
    if raw_bin is not None:
        media += ["-cartmd128", str(raw_bin)]
    if drive8 is not None:
        attach8 = "-attach8ro" if drive8_ro else "-attach8rw"
        media += ["-drive8truedrive", "-drive8type", "1571", attach8, "-8", str(drive8.resolve())]
    else:
        media += ["+busdevice8", "-drive8type", "0"]
    if drive9 is not None:
        media += ["-drive9truedrive", "-drive9type", "1571", "-attach9rw", "-9", str(drive9.resolve())]
    else:
        media += ["+busdevice9", "-drive9type", "0"]
    if autostart is not None:
        media += ["-autostart", str(autostart.resolve())]
    return [
        vice,
        "-config",
        vice_config(vice),
        "-default",
        "+saveres",
        "-VDC16KB",   # a stock C128's VDC; VICE defaults to 64 KB (maintainer, 2026-11-16)
        "+autostart-delay-random",
        "-console",
        "-nativemonitor",
        "-warp",
        "-80col",
        "+sound",
        "-sounddev",
        "dummy",
        "+confirmonexit",
        *media,
        "-ntsc" if ntsc else "-pal",
        "-remotemonitor",
        "-remotemonitoraddress",
        f"127.0.0.1:{port}",
    ]


class Experiment:
    def __init__(
        self,
        args: argparse.Namespace,
        *,
        name: str,
        initial_break: int | None = None,
        use_bin: bool = False,
        drive8: Path | None = None,
        drive9: Path | None = None,
        disk_build: bool = False,
    ) -> None:
        self.args = args
        self.disk_build = disk_build
        self.symbol_path = args.disk_symbols if disk_build else args.symbols
        self.sym = symbols(self.symbol_path)
        if initial_break is None:
            initial_break = self.sym["title_menu_loop"] if disk_build else self.sym["entry"]
        self.out = args.output.resolve() / name / "attempt-1"
        self.out.mkdir(parents=True, exist_ok=False)
        self.started = time.monotonic()
        self.deadline = self.started + 30.0
        self.phase = "launch"
        self.count = 0
        self.watchdog_fired = False
        self.termination_action: str | None = None
        self.event_lock = threading.Lock()
        self.closed = False
        self.proc: subprocess.Popen[bytes] | None = None
        self.timer: threading.Timer | None = None
        self.forbidden: set[int] = {
            self.sym["runtime_load_failed"],
            *(
                {self.sym["cart_invalid_asset"]}
                if "cart_invalid_asset" in self.sym
                else set()
            ),
        }

        port = allocate_free_port()
        self.mon = VICEConnector(port=port, timeout=0.2)
        self.log = (self.out / "console.log").open("wb", buffering=0)
        self.console_master, console_slave = pty.openpty()
        os.set_blocking(self.console_master, False)
        self.console_stop = threading.Event()
        self.console_thread: threading.Thread | None = None

        crt_copy: Path | None = None
        bin_copy: Path | None = None
        drive8_path: Path | None = drive8
        autostart_path: Path | None = None
        if disk_build:
            disk8_copy = self.out / args.disk_image.name
            shutil.copyfile(args.disk_image, disk8_copy)
            drive8_path = disk8_copy
            autostart_path = disk8_copy
        else:
            if use_bin:
                bin_copy = self.out / "cartridge.bin"
                shutil.copyfile(args.bin, bin_copy)
            else:
                crt_copy = self.out / "cartridge.crt"
                shutil.copyfile(args.crt, crt_copy)

        command = build_vice_command(
            args.vice,
            port,
            ntsc=args.ntsc,
            crt=crt_copy,
            raw_bin=bin_copy,
            drive8=drive8_path,
            drive8_ro=disk_build,
            drive9=drive9,
            autostart=autostart_path,
        )
        self.event(
            "launch",
            command=command,
            video="ntsc" if args.ntsc else "pal",
            mode="disk" if disk_build else ("bin" if use_bin else "crt"),
            monitor_port=port,
        )
        try:
            env = dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
            try:
                self.proc = subprocess.Popen(
                    command, stdout=console_slave, stderr=subprocess.STDOUT, env=env, cwd=ROOT
                )
            finally:
                os.close(console_slave)
            self.console_thread = threading.Thread(target=self.capture_console, daemon=True)
            self.console_thread.start()
            self.timer = threading.Timer(max(0.0, self.deadline - time.monotonic()), self.watchdog)
            self.timer.start()
            self.phase = "connect"
            self.event("phase")
            self.mon.connect()
            self.phase = "ready"
            self.event("phase")
            self.batch([])
            if disk_build:
                self.batch(["del", f"break ${initial_break:04x}"])
                self.phase = "autostart"
                self.event("phase")
                self.until(initial_break)
            else:
                self.batch(["del", f"break ${initial_break:04x}"])
                self.phase = "reset"
                self.event("phase")
                self.cmd("reset 1")
                if not re.search(rf"(?im)^\s*\.;{initial_break:04x}\s", self.cmd("r")):
                    self.until(initial_break)
            self.phase = "running"
            self.event("phase")
        except Exception as exc:
            self.event("startup_error", error=repr(exc))
            self.close()
            raise

    def event(self, kind: str, **details: object) -> dict[str, object]:
        with self.event_lock:
            record = dict(
                event=kind,
                phase=self.phase,
                elapsed=time.monotonic() - self.started,
                pid=self.proc.pid if self.proc else None,
                returncode=self.proc.poll() if self.proc else None,
                checks=self.count,
                watchdog_fired=self.watchdog_fired,
                termination_action=self.termination_action,
                **details,
            )
            with (self.out / "events.jsonl").open("a") as log:
                log.write(json.dumps(record) + "\n")
            return record

    def capture_console(self) -> None:
        stopping = False
        while True:
            try:
                data = os.read(self.console_master, 65536)
            except BlockingIOError:
                if stopping:
                    return
                stopping = self.console_stop.wait(0.01)
                continue
            except OSError as exc:
                if exc.errno != errno.EIO:
                    self.event("console_error", error=repr(exc))
                return
            if not data:
                return
            self.log.write(data)

    def watchdog(self) -> None:
        if self.proc and self.proc.poll() is None:
            self.watchdog_fired = True
            self.termination_action = "watchdog_kill"
            try:
                self.proc.kill()
            except ProcessLookupError:
                pass
            self.event("watchdog")

    def more_response(self) -> str:
        try:
            response = self.mon.read_until_prompt(deadline=self.deadline)
        except Exception as exc:
            self.event("monitor_error", error=repr(exc))
            raise
        with (self.out / "monitor.log").open("a") as log:
            log.write(response + "\n")
        return response

    def cmd(self, command: str, expect_prompt: bool = True) -> str:
        with (self.out / "monitor.log").open("a") as log:
            log.write(command + "\n")
        try:
            response = self.mon.send_command(
                command, expect_prompt=expect_prompt, deadline=self.deadline
            )
        except Exception as exc:
            self.event("monitor_error", command=command, error=repr(exc))
            raise
        with (self.out / "monitor.log").open("a") as log:
            log.write(response + "\n")
        while expect_prompt and not PROMPT_RE.search(response.encode()):
            response += self.more_response()
        if MONITOR_ERROR_RE.search(response):
            raise AssertionError(response)
        return response

    def batch(self, commands: list[str]) -> str:
        script = self.out / "commands.mon"
        script.write_text("\n".join([*commands, "r"]) + "\n")
        response = self.cmd(f'pb "{script}"')
        while (
            "STOPWATCH" not in response
            or not re.search(r"(?m)^\s*\.;[0-9a-fA-F]+", response)
            or not PROMPT_RE.search(response.encode())
        ):
            response += self.more_response()
        if MONITOR_ERROR_RE.search(response):
            raise AssertionError(response)
        return response

    def memory(self, address: int, size: int, bank: str = "ram") -> bytes:
        target = self.out / "memory.bin"
        target.unlink(missing_ok=True)
        self.batch([f"bank {bank}", f'bsave "{target}" 0 ${address:04x} ${address+size-1:04x}', "bank cpu"])
        data = target.read_bytes()
        assert len(data) == size, (len(data), size)
        return data

    def write(self, address: int, data: bytes, bank: str = "ram") -> None:
        target = self.out / "driver.prg"
        target.write_bytes(address.to_bytes(2, "little") + bytes(data))
        self.batch([f"bank {bank}", f'load "{target}" 0', "bank cpu"])

    def until(self, address: int, start: int | None = None, alternatives: tuple[int, ...] = ()) -> int:
        commands = ["del"]
        for forbidden in sorted(self.forbidden):
            commands.append(f"break ${forbidden:04x}")
        for target in (address, *alternatives):
            guard = ""
            if target >= 0xE000:
                guard = " if (@cpu:$ff00 & $f0) == $30"
            elif target >= 0x4000:
                guard = " if (@cpu:$ff00 & $c0) == $00"
            commands.append(f"break ${target:04x}{guard}")
        self.batch(commands)
        response = self.cmd("g" if start is None else f"g ${start:04x}")
        for target in (address, *alternatives):
            if re.search(rf"(?:C:|PC:|PC=)\$?{target:04x}", response, re.I):
                return target
        raise AssertionError(f"Did not reach ${address:04x}: {response}")

    def key(self, ch: str | bytes) -> None:
        code = ch[0] if isinstance(ch, (bytes, bytearray)) else ord(ch)
        labels = ("hal_input_get_key", "input_get_key_fast")
        registers = self.cmd("r")
        if not any(re.search(rf"(?im)^\s*\.;{self.sym[label]:04x}\s", registers) for label in labels):
            self.until(self.sym[labels[0]], alternatives=(self.sym[labels[1]],))
            registers = self.cmd("r")
        row = next(line for line in registers.splitlines() if line.strip().startswith(".;"))
        sp = int(row.split()[4], 16)
        ret = int.from_bytes(self.memory(0x0101 + sp, 2), "little") + 1
        self.cmd(f"r a={code:02x}")
        self.cmd(f"r sp={(sp + 2) & 255:02x}")
        self.cmd(f"r pc={ret:04x}")

    def return_address(self) -> int:
        registers = self.cmd("r")
        row = next(line for line in registers.splitlines() if line.strip().startswith(".;"))
        sp = int(row.split()[4], 16)
        return int.from_bytes(self.memory(0x0101 + sp, 2), "little") + 1

    def assert_carry(self, expected: bool = True) -> None:
        flags = re.search(r"\b([01]{8})\b", self.cmd("r"))
        assert flags and (flags[1][-1] == "1") == expected, f"Unexpected carry: {flags}"

    def vdc_has(self, text: str) -> None:
        scr = self.memory(0, 80 * 25, "vdc")
        assert screen_bytes(text) in scr, f"Missing on 80-col VDC: {text!r}"

    def call_overlay_load(self, ovl_id: int) -> None:
        # Call overlay_load(A=ovl_id) via free Bank 0 scratch between program_end and $AF00.
        scratch = self.sym["program_end"]
        result = scratch + 0x10
        assert result < 0xAF00, f"No scratch headroom below $AF00: program_end=${scratch:04x}"
        code = [
            0xA9, ovl_id,
            0x20, self.sym["overlay_load"] & 255, self.sym["overlay_load"] >> 8,
            0x08, 0x68, 0x8D, result & 255, result >> 8,
        ]
        end = scratch + len(code)
        code += [0x4C, end & 255, end >> 8]
        self.write(scratch, bytes(code))
        self.until(end, start=scratch)
        assert (self.memory(result, 1)[0] & 1) == 0, f"overlay_load({ovl_id}) set carry"

    def call_carry_fn(self, addr: int) -> bool:
        scratch = self.sym["program_end"]
        result = scratch + 0x10
        assert result < 0xAF00, f"No scratch headroom below $AF00: program_end=${scratch:04x}"
        code = [
            0x20, addr & 255, addr >> 8,
            0x08, 0x68, 0x8D, result & 255, result >> 8,
        ]
        end = scratch + len(code)
        code += [0x4C, end & 255, end >> 8]
        self.write(scratch, bytes(code))
        self.until(end, start=scratch)
        return bool(self.memory(result, 1)[0] & 1)

    def call_catalog_fetch_ext(self, creature_id: int) -> bytes:
        scratch = self.sym["program_end"]
        assert scratch + 0x20 < 0xAF00, f"No scratch headroom below $AF00: program_end=${scratch:04x}"
        self.write(self.sym["cat_id_lo"], bytes([creature_id & 0xFF]))
        self.write(self.sym["cat_id_hi"], bytes([(creature_id >> 8) & 0xFF]))
        self.write(self.sym["cat_ext_record"], b"\xa5" * 8)
        fn = self.sym["catalog_fetch_ext"]
        code = [0x20, fn & 255, fn >> 8]
        end = scratch + len(code)
        code += [0x4C, end & 255, end >> 8]
        self.write(scratch, bytes(code))
        self.until(end, start=scratch)
        return self.memory(self.sym["cat_ext_record"], 8)

    def check(self, message: str) -> None:
        self.count += 1
        self.event("check", message=message)
        print(f"PASS {message}", flush=True)

    def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        if self.timer:
            self.timer.cancel()
        self.event("before_cleanup")
        if self.proc and self.proc.poll() is None:
            self.termination_action = "monitor_quit"
            try:
                self.cmd("quit", expect_prompt=False)
            except (OSError, RuntimeError):
                self.termination_action = "cleanup_terminate"
                self.proc.terminate()
            try:
                self.proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.termination_action = "cleanup_kill"
                self.proc.kill()
                self.proc.wait()
        self.mon.close()
        self.console_stop.set()
        if self.console_thread:
            self.console_thread.join(timeout=1)
        os.close(self.console_master)
        self.log.close()
        (self.out / "result.json").write_text(json.dumps(self.event("closed"), indent=2) + "\n")


def blank_d71(args: argparse.Namespace, name: str) -> Path:
    path = args.output.resolve() / f"{name}.d71"
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [args.c1541, "-format", "moria8save,08", "d71", str(path)],
        check=True,
        capture_output=True,
        timeout=10,
    )
    return path


def snapshot(exp: Experiment) -> dict[str, bytes]:
    player = catalog_disk.consts(ROOT / "core/player.s")
    slots = catalog_disk.consts(ROOT / "core/item_defs.s")["TOTAL_INV_SLOTS"]
    map_base = exp.sym["MAP_BASE"] if "MAP_BASE" in exp.sym else 0x4000
    data = {
        "player": exp.memory(exp.sym["player_data"], player["PL_STRUCT_SIZE"]),
        "map": exp.memory(map_base, 13068, "ram01"),
        "recall": exp.memory(0x7400, 1116, "ram01"),
    }
    for name in (
        "inv_item_id",
        "inv_qty",
        "inv_p1",
        "inv_to_hit",
        "inv_to_dam",
        "inv_to_ac",
        "inv_flags",
        "inv_ego",
    ):
        data[name] = exp.memory(exp.sym[name], slots)
    return data


def create_character(exp: Experiment) -> None:
    exp.key("N")
    exp.until(exp.sym["create_select_race"])
    for ch, target in (
        ("A", "create_roll_stats"),
        ("\r", "create_select_class"),
        ("A", "create_enter_name"),
    ):
        exp.key(ch)
        exp.until(exp.sym[target])
    for ch in "C128\r":
        exp.key(ch)
    exp.until(exp.sym["create_select_gender"])
    exp.key("A")
    exp.until(exp.sym["input_get_modal_dismiss_key"])
    exp.key(" ")
    exp.until(exp.sym["main_loop"])


def setup_disk(exp: Experiment, *, initialize: bool = False, disk_build: bool = False, drive: int = 8) -> None:
    exp.key("D")
    exp.until(exp.sym["tramp_disk_setup"])
    exp.key("2" if disk_build or drive == 9 else "1")
    if disk_build or drive == 9:
        exp.key(str(drive))
        exp.key("\r")
        exp.key("3")
    exp.until(exp.sym["uds_insert_prompt_wait_key"])
    exp.key(" ")
    if initialize:
        exp.until(exp.sym["uds_show_init_prompt"])
        exp.key("Y")
    exp.until(exp.sym["title_menu_loop"])
    assert exp.memory(exp.sym["program_device"], 1) == b"\x08"
    assert exp.memory(exp.sym["save_device"], 1) == bytes([drive if (disk_build or drive == 9) else 8])
    assert exp.memory(exp.sym["disk_mode"], 1) == bytes([2 if (disk_build or drive == 9) else 1])
    assert exp.memory(exp.sym["disk_setup_done"], 1) == b"\x01"


def save_character(exp: Experiment, *, overwrite: bool = False) -> dict[str, bytes]:
    exp.key(b"\xd3")  # Shift+S
    exp.key("1")
    exp.until(exp.sym["save_game"])
    target = exp.return_address()
    if overwrite:
        exp.key("Y")
    exp.until(exp.sym["save_write_block"])
    prev = set(exp.forbidden)
    exp.forbidden = prev | {exp.sym["input_get_modal_dismiss_key"], exp.sym["save_return_fail"]}
    try:
        for _ in range(4):
            if exp.until(target, alternatives=(exp.sym["msg_show_more"],)) == target:
                break
            exp.key(" ")
        else:
            raise AssertionError("Unexpected save paging loop")
    finally:
        exp.forbidden = prev
    exp.assert_carry(expected=True)
    return snapshot(exp)


def load_character(exp: Experiment, expected: dict[str, bytes]) -> None:
    exp.key("L")
    exp.until(exp.sym["title_load_game"])
    exp.key("1")
    exp.until(exp.sym["load_game"])
    target = exp.return_address()
    exp.until(target)
    exp.assert_carry(expected=True)
    assert snapshot(exp) == expected, "Save snapshot mismatch across load"
    exp.until(exp.sym["main_loop"])


def run_cartridge_boot_and_assets(args: argparse.Namespace) -> int:
    exp = Experiment(args, name="crt-boot-assets")
    cart_dir = args.symbols.parent
    try:
        raw_res = (cart_dir / "moria128.prg").read_bytes()[2:]
        assert exp.memory(0x1C01, len(raw_res)) == raw_res
        exp.check("native Magic Desk 128 cold boot copied moria128.prg across ROM banks")

        exp.until(exp.sym["c128_preload_resident_play"])
        for filename, addr, bank in (
            ("128.bank.prg", 0xF000, "ram"),
            ("128.cat.prg", 0x7E60, "ram01"),
            ("128.cnm.prg", 0xA000, "ram01"),
            ("128.cex.prg", 0xD000, "ram01"),
        ):
            payload = (cart_dir / filename).read_bytes()[2:]
            assert exp.memory(addr, len(payload), bank) == payload, filename
        cex_payload = (cart_dir / "128.cex.prg").read_bytes()[2:]
        assert len(cex_payload) == 279 * 8
        assert exp.memory(0x7400, 1116, "ram01") == b"\x00" * 1116
        huff = (cart_dir / "128.huff.prg").read_bytes()[2:]
        hvec = (cart_dir / "128.hvec.prg").read_bytes()[2:]
        assert exp.memory(0xF000, len(huff), "ram01") == huff
        assert exp.memory(0xFFFA, len(hvec), "ram01") == hvec
        exp.check("Bank 0 resident image, banked runtime, Bank 1 recall BSS, and 279-creature catalog+cex/Huffman/vector match")

        exp.until(exp.sym["title_menu_loop"])
        paused_title = exp.until(exp.sym["hal_input_get_key"], alternatives=(exp.sym["input_get_key_fast"],))
        for cid in (0, 1, 100, 255, 256, 278):
            got_ext = exp.call_catalog_fetch_ext(cid)
            want_ext = cex_payload[cid * 8 : (cid + 1) * 8]
            assert got_ext == want_ext, f"cart catalog_fetch_ext({cid}): {got_ext!r} != {want_ext!r}"
        exp.cmd(f"r pc={paused_title:04x}")
        exp.check("production catalog_fetch_ext read Bank 1 $D000-$D8B7 128.cex records via $7F helper")
        assert exp.memory(exp.sym["program_device"], 2) == b"\x08\x08"
        assert exp.memory(exp.sym["disk_mode"], 1) == b"\x00"
        assert exp.memory(exp.sym["disk_setup_done"], 1) == b"\x00"
        menu = "N)ew  L)oad  D)isk Setup  A)bout"
        row = exp.memory(18 * 80, 80, "vdc")
        start = (80 - len(menu)) // 2
        assert row[start:start + len(menu)] == screen_bytes(menu), row
        exp.check("zero-disk cold boot reached centered 80-col VDC title with device 8 default")

        # Title A -> Legal viewer (LICENSE + SOURCE-OFFER + Q return)
        exp.key("A")
        exp.until(exp.sym["legal_menu_wait"])
        exp.key("1")
        exp.until(exp.sym["legal_page_wait"])
        exp.vdc_has("MORIA8 LICENSE NOTICE")
        exp.key("Q")
        exp.until(exp.sym["legal_menu_wait"])
        exp.key("2")
        exp.until(exp.sym["legal_page_wait"])
        exp.vdc_has("MORIA8 SOURCE OFFER")
        for _ in range(6):
            if exp.memory(exp.sym["legal_eof"], 1) == b"\x40":
                break
            exp.key(" ")
            exp.until(exp.sym["legal_page_wait"])
        else:
            raise AssertionError("SOURCE-OFFER did not reach EOF")
        exp.key("Q")
        exp.until(exp.sym["legal_menu_wait"])
        exp.key("3")
        exp.until(exp.sym["legal_sysinfo_wait"])
        for text in ("Moria 8 - System Info", "Save V2 ($22)", "Magic Desk 128 Cartridge", "Drives:"):
            exp.vdc_has(text)
        exp.key(" ")
        exp.until(exp.sym["legal_menu_wait"])
        exp.key("Q")
        exp.until(exp.sym["title_menu_loop"])
        exp.check("Title A legal viewer paged LICENSE, SOURCE-OFFER, and System Info from ROM")

        # Verify all 12 overlays (including cold ovl.chest, ovl.home, and ovl.storage) through overlay_load
        ovl_consts = catalog_disk.consts(ROOT / "platforms/commodore/common/overlay.s")
        for symbol, name in make_c128_md128.OVERLAYS:
            exp.call_overlay_load(ovl_consts["OVL_" + symbol])
            expected = (cart_dir / f"ovl.{name}").read_bytes()[2:]
            assert exp.memory(0xE000, len(expected)) == expected, name
        exp.check("all 12 overlays including cold ovl.chest, ovl.home, and ovl.storage load cleanly via overlay_load")
        return exp.count
    finally:
        exp.close()


def run_md128_gameplay_and_reset(args: argparse.Namespace) -> int:
    exp = Experiment(args, name="md128-gameplay", use_bin=True)
    cart_dir = args.symbols.parent
    try:
        exp.until(exp.sym["title_menu_loop"])
        exp.vdc_has("N)ew  L)oad  D)isk Setup  A)bout")
        create_character(exp)
        assert exp.memory(exp.sym["zp_player_dlvl"], 1) == b"\x00"
        exp.check("-cartmd128 raw BIN booted and reached town with zero disk")

        before = snapshot(exp)
        exp.key("?")
        exp.until(exp.sym["hal_input_get_key"])
        exp.vdc_has("L:License")
        exp.key(" ")
        exp.until(exp.sym["hal_input_get_key"])
        exp.vdc_has("L License / Source")
        exp.key("L")
        exp.until(exp.sym["legal_menu_wait"])
        exp.key("Q")
        exp.until(exp.sym["legal_return"])
        exp.until(exp.sym["hal_input_get_key"])
        exp.key("Q")
        exp.until(exp.sym["main_loop"])
        assert snapshot(exp) == before
        exp.check("in-game Help and Legal modal returned without mutating game state")

        exp.key(b"\xd6")  # SHIFT+V: System Info
        exp.until(exp.sym["legal_sysinfo_wait"])
        for text in ("Moria 8 - System Info", "Magic Desk 128 Cartridge", "Turn 0  Town", "RNG:"):
            exp.vdc_has(text)
        exp.key(" ")
        exp.until(exp.sym["main_loop"])
        assert snapshot(exp) == before
        exp.check("SHIFT+V System Info rendered VDC session telemetry without mutating game state")

        # Move to town down staircase and descend to dungeon level 1 (ovl.gen + spawns)
        world = exp.memory(0x4000, 198 * 66, "ram01")
        stair = next(i for i, b in enumerate(world) if (b & 0xF0) == 0x90)
        exp.write(exp.sym["zp_player_x"], bytes([stair % 198]))
        exp.write(exp.sym["zp_player_y"], bytes([stair // 198]))
        exp.key(">")
        exp.until(exp.sym["cmd_stairs_dn"])
        exp.until(exp.sym["tramp_level_generate"])
        exp.until(exp.sym["main_loop"])
        assert exp.memory(exp.sym["zp_player_dlvl"], 1) == b"\x01"
        assert exp.memory(exp.sym["zp_mon_count"], 1)[0] > 0, "No dungeon monsters spawned"
        exp.check("ovl.gen generated dungeon level 1 and spawned monsters from Bank 1 catalog")

        # Load cold ovl.chest, ovl.home, and ovl.storage through overlay_load during active dungeon state
        paused_at = exp.until(exp.sym["hal_input_get_key"], alternatives=(exp.sym["input_get_key_fast"],))
        ovl_consts = catalog_disk.consts(ROOT / "platforms/commodore/common/overlay.s")
        for ovl_name, ovl_sym in (("ovl.chest", "OVL_CHEST"), ("ovl.home", "OVL_HOME"), ("ovl.storage", "OVL_STORAGE")):
            ovl_code = (cart_dir / ovl_name).read_bytes()[2:]
            exp.call_overlay_load(ovl_consts[ovl_sym])
            assert exp.memory(0xE000, len(ovl_code)) == ovl_code
        exp.check("cold ovl.chest, ovl.home, and ovl.storage loaded identically via overlay_load from MD128 ROM")

        # Resume the paused key-wait frame, then test real Shift+Q quit -> game_over_prompt -> title
        exp.cmd(f"r pc={paused_at:04x}")
        exp.key(b"\xd1")
        exp.key("Y")
        exp.until(exp.sym["game_over_prompt"])
        exp.until(exp.sym["title_menu_loop"])
        exp.vdc_has("N)ew  L)oad  D)isk Setup  A)bout")
        exp.check("Shift+Q quit cleanly returned via game_over_prompt to title")

        # Test exit_trampoline warm/cold reset re-enters cartridge boot cleanly
        exp.until(exp.sym["title_menu_loop"], start=exp.sym["exit_trampoline"])
        exp.check("exit_trampoline reset cleanly re-entered MD128 boot to title")
        return exp.count
    finally:
        exp.close()


def run_persistence_failure_paths(args: argparse.Namespace) -> int:
    # 1. Zero-disk cancels on D)isk Setup, L)oad, and in-game Shift+S
    exp0 = Experiment(args, name="crt-zero-disk-cancels")
    try:
        exp0.until(exp0.sym["title_menu_loop"])
        exp0.key("D")
        exp0.until(exp0.sym["tramp_disk_setup"])
        exp0.key("Q")
        exp0.until(exp0.sym["title_menu_loop"])
        assert exp0.memory(exp0.sym["disk_setup_done"], 1) == b"\x00"
        exp0.check("cancelled D)isk Setup kept disk_setup_done=0 and returned to title")

        exp0.key("L")
        exp0.until(exp0.sym["tramp_disk_setup"])
        exp0.key("Q")
        exp0.until(exp0.sym["title_menu_loop"])
        assert exp0.memory(exp0.sym["disk_setup_done"], 1) == b"\x00"
        exp0.check("L)oad without setup cancelled Disk Setup cleanly back to title")

        create_character(exp0)
        exp0.key(b"\xd3")  # Shift+S triggers Disk Setup when unconfigured
        exp0.until(exp0.sym["tramp_disk_setup"])
        exp0.key("Q")
        exp0.until(exp0.sym["main_loop"])
        assert exp0.memory(exp0.sym["disk_setup_done"], 1) == b"\x00"
        exp0.check("in-game Shift+S cancelled Disk Setup cleanly back to gameplay")
        count = exp0.count
    finally:
        exp0.close()

    # 2. Uninitialized .d71 rejection via disk_require_save_media + Disk Setup marker recovery + missing save load
    uninit_disk = blank_d71(args, "blank-uninit")
    exp_u = Experiment(args, name="crt-uninit-and-missing-load", drive8=uninit_disk)
    try:
        exp_u.until(exp_u.sym["title_menu_loop"])
        paused_title = exp_u.until(exp_u.sym["hal_input_get_key"], alternatives=(exp_u.sym["input_get_key_fast"],))
        assert exp_u.call_carry_fn(exp_u.sym["disk_require_save_media"]) is True
        exp_u.write(exp_u.sym["disk_setup_done"], b"\x01")
        exp_u.write(exp_u.sym["disk_mode"], b"\x00")
        assert exp_u.call_carry_fn(exp_u.sym["disk_require_save_media"]) is True
        exp_u.write(exp_u.sym["disk_mode"], b"\x01")
        exp_u.write(exp_u.sym["save_device"], b"\x08")
        assert exp_u.call_carry_fn(exp_u.sym["disk_require_save_media"]) is True
        exp_u.check("disk_require_save_media rejected unconfigured and unmarked .d71 media")

        exp_u.write(exp_u.sym["disk_setup_done"], b"\x00")
        exp_u.write(exp_u.sym["disk_mode"], b"\x00")
        exp_u.cmd(f"r pc={paused_title:04x}")
        setup_disk(exp_u, initialize=True, drive=8)
        paused_after_setup = exp_u.until(exp_u.sym["hal_input_get_key"], alternatives=(exp_u.sym["input_get_key_fast"],))
        assert exp_u.call_carry_fn(exp_u.sym["disk_init_drive"]) is False
        assert exp_u.call_carry_fn(exp_u.sym["disk_require_save_media"]) is False
        exp_u.check("Disk Setup marker init + disk_init_drive made disk_require_save_media succeed")

        exp_u.cmd(f"r pc={paused_after_setup:04x}")
        exp_u.key("L")
        exp_u.until(exp_u.sym["title_load_game"])
        exp_u.key("1")
        exp_u.until(exp_u.sym["input_get_modal_dismiss_key"])
        exp_u.key(" ")
        exp_u.until(exp_u.sym["title_menu_loop"])
        exp_u.check("L)oad on empty initialized .d71 failed cleanly and returned to title")
        return count + exp_u.count
    finally:
        exp_u.close()


def run_persistence_and_interchange(args: argparse.Namespace) -> int:
    count = run_persistence_failure_paths(args)

    save_disk = blank_d71(args, "save")
    exp = Experiment(args, name="crt-save-reload", drive8=save_disk)
    try:
        exp.until(exp.sym["title_menu_loop"])
        setup_disk(exp, initialize=True, drive=8)
        create_character(exp)
        expected = save_character(exp)
        exp.until(exp.sym["title_menu_loop"])
        load_character(exp, expected)
        exp.check("cartridge Drive 8 .d71 save and reload swapped 128.play <-> 128.persist cleanly")

        # Declining Overwrite? ('N') returns to main_loop and preserves prior Drive 8 save
        gold_addr = exp.sym["player_data"] + 43
        exp.write(gold_addr, b"\xe7\x03\x00")
        exp.key(b"\xd3")  # Shift+S
        exp.key("1")
        exp.until(exp.sym["save_game"])
        exp.key("N")
        exp.until(exp.sym["save_return_fail"])
        exp.assert_carry(expected=False)
        exp.until(exp.sym["main_loop"])
        exp.key(b"\xd1")  # Shift+Q back to title to verify disk still holds original save
        exp.key("Y")
        exp.until(exp.sym["title_menu_loop"])
        load_character(exp, expected)
        exp.check("declined overwrite preserved existing Drive 8 save and resumed cleanly")

        expected = save_character(exp, overwrite=True)
        exp.until(exp.sym["title_menu_loop"])
        exp.check("cartridge overwrite save succeeded on Drive 8 without swap prompt")
        count += exp.count
    finally:
        exp.close()

    # Verify disk edition loads 128.cex into Bank 1 $D000-$D8B7 and loads cartridge-written .d71 save identically
    disk_cex = (args.disk_symbols.parent / "128.cex.prg").read_bytes()[2:]
    exp2 = Experiment(args, name="disk-load-crt-save", drive9=save_disk, disk_build=True)
    try:
        assert exp2.memory(0xD000, len(disk_cex), "ram01") == disk_cex
        setup_disk(exp2, disk_build=True, drive=9)
        load_character(exp2, expected)
        paused_disk = exp2.until(exp2.sym["hal_input_get_key"], alternatives=(exp2.sym["input_get_key_fast"],))
        for cid in (0, 100, 278):
            assert exp2.call_catalog_fetch_ext(cid) == disk_cex[cid * 8 : (cid + 1) * 8]
        exp2.cmd(f"r pc={paused_disk:04x}")
        exp2.check("disk edition loaded 128.cex to Bank 1 $D000, verified catalog_fetch_ext, and loaded cartridge .d71 save")
        count += exp2.count
    finally:
        exp2.close()

    # Verify negative save rejection on MD128 cartridge: wrong-version ($21) and corrupt checksum
    def set_old_version(blob: bytearray) -> None:
        assert blob[7] == 0x22, f"Unexpected save version {blob[7]:#x}"
        blob[7] = 0x21

    def corrupt_payload(blob: bytearray) -> None:
        assert len(blob) > 100
        blob[100] ^= 0x55

    for neg_name, mutator, want_result in (
        ("wrong-v21", set_old_version, 4),
        ("corrupt-checksum", corrupt_payload, 2),
    ):
        neg_disk = args.output.resolve() / f"{neg_name}.d71"
        shutil.copyfile(save_disk, neg_disk)
        seq_tmp = args.output.resolve() / f"{neg_name}.the.game"
        seq_tmp.unlink(missing_ok=True)
        subprocess.run(
            [args.c1541, "-attach", str(neg_disk), "-read", "the.game,s", str(seq_tmp)],
            check=True,
            capture_output=True,
            timeout=10,
        )
        blob = bytearray(seq_tmp.read_bytes())
        mutator(blob)
        seq_tmp.write_bytes(blob)
        subprocess.run(
            [args.c1541, "-attach", str(neg_disk), "-delete", "the.game", "-write", str(seq_tmp), "the.game,s"],
            check=True,
            capture_output=True,
            timeout=10,
        )
        seq_tmp.unlink(missing_ok=True)
        exp_neg = Experiment(args, name=f"crt-neg-{neg_name}", drive8=neg_disk)
        try:
            exp_neg.until(exp_neg.sym["title_menu_loop"])
            setup_disk(exp_neg, drive=8)
            exp_neg.forbidden.add(exp_neg.sym["main_loop"])
            exp_neg.key("L")
            exp_neg.until(exp_neg.sym["title_load_game"])
            exp_neg.key("1")
            exp_neg.until(exp_neg.sym["input_get_modal_dismiss_key"])
            got = exp_neg.memory(exp_neg.sym["load_result"], 1)[0]
            assert got == want_result, f"{neg_name}: load_result={got}, expected {want_result}"
            exp_neg.key(" ")
            exp_neg.until(exp_neg.sym["title_menu_loop"])
            exp_neg.check(f"cartridge load rejected {neg_name} save cleanly (load_result={want_result})")
            count += exp_neg.count
        finally:
            exp_neg.close()

    # Verify Drive 9 cartridge persistence (two-drive setup)
    d9_disk = blank_d71(args, "save-drive9")
    exp9 = Experiment(args, name="crt-drive9-save-reload", drive9=d9_disk)
    try:
        exp9.until(exp9.sym["title_menu_loop"])
        setup_disk(exp9, initialize=True, drive=9)
        create_character(exp9)
        expected9 = save_character(exp9)
        exp9.until(exp9.sym["title_menu_loop"])
        load_character(exp9, expected9)
        exp9.check("cartridge Drive 9 .d71 save and reload succeeded")
        return count + exp9.count
    finally:
        exp9.close()


def run_selftest() -> None:
    cmd_crt = build_vice_command("x128", 6510, crt=Path("build/moria8-c128.crt"))
    assert "-80col" in cmd_crt and "-cartcrt" in cmd_crt and "-pal" in cmd_crt
    assert cmd_crt.index("-VDC16KB") > cmd_crt.index("-default")   # -default would reset it
    cmd_bin = build_vice_command(
        "x128", 6510, ntsc=True, raw_bin=Path("build/c128-cart/moria8-c128.bin"), drive8=Path("save.d71")
    )
    assert "-cartmd128" in cmd_bin and "-ntsc" in cmd_bin and "-drive8type" in cmd_bin and "1571" in cmd_bin
    assert "-attach8rw" in cmd_bin and "-attach8ro" not in cmd_bin
    cmd_ro = build_vice_command("x128", 6510, drive8=Path("moria128.d71"), drive8_ro=True)
    assert "-attach8ro" in cmd_ro and "-attach8rw" not in cmd_ro
    assert screen_bytes("N)ew") == b"N)\x05\x17"
    print("PASS test_cartridge.py selftest")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--crt", type=Path)
    parser.add_argument("--bin", type=Path)
    parser.add_argument("--symbols", type=Path)
    parser.add_argument("--disk-image", type=Path)
    parser.add_argument("--disk-symbols", type=Path)
    parser.add_argument("--vice", default="x128")
    parser.add_argument("--c1541", default="c1541")
    parser.add_argument("--output", type=Path, default=ROOT / "build/test/c128-cartridge")
    parser.add_argument("--ntsc", action="store_true")
    args = parser.parse_args()

    if args.selftest:
        run_selftest()
        return

    for required in ("crt", "bin", "symbols", "disk_image", "disk_symbols"):
        if getattr(args, required) is None:
            parser.error(f"--{required.replace('_', '-')} is required unless --selftest is used")

    prepare_run(args)
    total = (
        run_cartridge_boot_and_assets(args)
        + run_md128_gameplay_and_reset(args)
        + run_persistence_and_interchange(args)
    )
    mode = "NTSC" if args.ntsc else "PAL"
    print(f"C128 cartridge ({mode}): {total} checks passed", flush=True)


if __name__ == "__main__":
    main()
