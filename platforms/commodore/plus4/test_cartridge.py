#!/usr/bin/env python3
"""Exercise the Plus/4 c264 magic cart autostart ROM and cartridge product in VICE.

Every launched emulator is bounded to 30 seconds; monitor operations share
that deadline. Scratch and logs belong under the caller's build directory.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import errno
import json
import os
from pathlib import Path
import pty
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from vice_connector import VICEConnector, allocate_free_port, PROMPT_RE  # noqa: E402
from vice_config import vice_config  # noqa: E402
import catalog_disk  # noqa: E402
import make_plus4_magic  # noqa: E402

MONITOR_ERROR_RE = re.compile(
    r"(?im)^\s*(?:ERROR\b|Unknown command|Syntax error|Invalid argument|Unknown resource)"
)


def symbols(path: Path) -> dict[str, int]:
    return {
        name: int(value, 16)
        for name, value in re.findall(r"\.label (\w+)=\$([0-9a-fA-F]+)", path.read_text())
    }


def prepare_run(args: argparse.Namespace) -> None:
    base = args.output.resolve()
    base.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    args.output = Path(tempfile.mkdtemp(prefix=f"run-{stamp}-", dir=base))
    print(f"Evidence: {args.output}", flush=True)


class Experiment:
    def __init__(
        self,
        args: argparse.Namespace,
        initial_break: int | None = None,
        name: str = "assets",
        disk: Path | None = None,
        disk_build: bool = False,
        raw_bin: Path | None = None,
        enable_drive9: bool = False,
    ) -> None:
        self.args = args
        self.symbol_path = args.disk_symbols if disk_build else args.symbols
        self.sym = symbols(self.symbol_path)
        if initial_break is None:
            initial_break = self.sym["entry"]
        self.out = args.output.resolve() / name / "attempt-1"
        self.out.mkdir(parents=True, exist_ok=False)
        self.started = time.monotonic()
        self.deadline = self.started + 30
        self.phase = "launch"
        self.count = 0
        self.watchdog_fired = False
        self.termination_action = None
        self.event_lock = threading.Lock()
        self.closed = False
        self.proc = None
        self.timer = None
        self.forbidden: set[int] = set()
        port = allocate_free_port()
        self.mon = VICEConnector(port=port, timeout=0.2)
        self.log = (self.out / "console.log").open("wb", buffering=0)
        self.console_master, console_slave = pty.openpty()
        os.set_blocking(self.console_master, False)
        self.console_stop = threading.Event()
        self.console_thread = None

        media_args: list[str] = []
        if not disk_build:
            if raw_bin is not None:
                test_bin = self.out / "cartridge.bin"
                shutil.copyfile(raw_bin, test_bin)
                media_args += ["-cartmagic", str(test_bin)]
            else:
                test_crt = self.out / "cartridge.crt"
                shutil.copyfile(args.crt, test_crt)
                media_args += ["-cartcrt", str(test_crt)]
        if disk is not None:
            if disk_build:
                disk8_copy = self.out / args.disk_image.name
                shutil.copyfile(args.disk_image, disk8_copy)
                media_args += [
                    "-autostartprgmode", "1",
                    "-drive9type", "1541",
                    "-attach8ro",
                    "-8", str(disk8_copy.resolve()),
                    "-attach9rw",
                    "-9", str(disk.resolve()),
                ]
            else:
                media_args += ["-8", str(disk.resolve())]
        elif enable_drive9:
            media_args += ["-drive9type", "1541"]

        command = [
            args.vice,
            "-config", vice_config(args.vice),
            "-default", "+saveres", "+autostart-delay-random",
            "-console", "-nativemonitor", "-warp",
            "+sound", "-sounddev", "dummy", "+confirmonexit",
            *media_args,
            "-ntsc" if args.ntsc else "-pal",
            "-remotemonitor", "-remotemonitoraddress", f"127.0.0.1:{port}",
        ]
        self.event(
            "launch",
            command=command,
            video="ntsc" if args.ntsc else "pal",
            mode="disk" if disk_build else ("cartmagic" if raw_bin is not None else "cartcrt"),
            monitor_port=port,
        )
        try:
            env = dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
            try:
                self.proc = subprocess.Popen(
                    command,
                    stdout=console_slave,
                    stderr=subprocess.STDOUT,
                    env=env,
                    cwd=ROOT,
                )
            finally:
                os.close(console_slave)
            self.console_thread = threading.Thread(target=self.capture_console, daemon=True)
            self.console_thread.start()
            self.timer = threading.Timer(max(0, self.deadline - time.monotonic()), self.watchdog)
            self.timer.start()
            self.phase = "connect"
            self.event("phase")
            self.mon.connect()
            self.phase = "ready"
            self.event("phase")
            self.batch([])
            self.batch(["del", f"break ${initial_break:04x}"])
            self.phase = "autostart" if disk_build else "reset"
            self.event("phase")
            if disk_build:
                self.cmd(f'autostart "{(self.symbol_path.parent / "moria4.prg").resolve()}"')
            else:
                self.cmd("reset 1")
            if not re.search(rf"(?im)^\s*\.;{initial_break:04x}\s", self.cmd("r")):
                self.until(initial_break)
            self.phase = "entry"
            self.event("phase")
            if disk_build:
                self.write(0xAA, b"\x08")
                self.write(0xAE, b"\x08")
                self.phase = "title"
                self.event("phase")
                self.until(self.sym["title_menu_loop"])
            self.phase = "running"
            self.event("phase")
        except Exception as exc:
            self.event("startup_error", error=repr(exc))
            self.close()
            raise

    def event(self, kind: str, **details) -> dict:
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
            response = self.mon.send_command(command, expect_prompt=expect_prompt, deadline=self.deadline)
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
        self.batch([f"bank {bank}", f'bsave "{target}" 0 ${address:04x} ${address + size - 1:04x}', "bank cpu"])
        data = target.read_bytes()
        assert len(data) == size, (len(data), size)
        return data

    def write(self, address: int, data: bytes) -> None:
        target = self.out / "driver.prg"
        target.write_bytes(address.to_bytes(2, "little") + bytes(data))
        self.cmd(f'load "{target}" 0')

    def until(self, address: int, start: int | None = None, alternatives: tuple[int, ...] = ()) -> int:
        commands = ["del"]
        for forbidden in getattr(self, "forbidden", ()):
            commands.append(f"break ${forbidden:04x}")
        for target in (address, *alternatives):
            commands.append(f"break ${target:04x}")
        self.batch(commands)
        response = self.cmd("g" if start is None else f"g ${start:04x}")
        for target in (address, *alternatives):
            if re.search(rf"(?:C:|PC:|PC=)\$?{target:04x}", response, re.I):
                return target
        raise AssertionError(f"Did not reach ${address:04x}: {response}")

    def call(self, routine: int, a: int = 0, irq_masked: bool = True, carry: bool = False) -> int:
        # Title-only map loan ($CE00-$CFFF): callers here never resume gameplay.
        # C800-CAFF holds loaded title art; CE00-CEFF holds the driver; CFF0 holds saved P.
        assert self.sym["program_end"] <= 0xC800
        assert len((self.args.symbols.parent / "title").read_bytes()) - 2 <= 0x600
        code = [
            0x78 if irq_masked else 0x58,
            0x8D, 0x3F, 0xFF,           # sta PLUS4_RAM_ENABLE ($FF3F)
            0xA9, a,
            0x20, routine & 255, routine >> 8,
            0x08, 0x68,                 # php; pla
            0x8D, 0xF0, 0xCF,           # sta $CFF0
        ]
        end = 0xCE00 + len(code)
        code += [0x4C, end & 255, end >> 8]
        before = int(self.cmd("r").split(".;")[-1].splitlines()[0].split()[-1])
        self.write(0xCE00, bytes(code))
        self.until(end, 0xCE00)
        cycles = int(self.cmd("r").split(".;")[-1].splitlines()[0].split()[-1]) - before
        flags = self.memory(0xCFF0, 1)[0]
        assert bool(flags & 4) == irq_masked, (routine, flags)
        assert bool(flags & 1) == carry, (routine, flags)
        # Prove cart_read restored RAM visibility and $FDD0 (no C1LO/KERNAL leak).
        assert cpu_memory(self, 0x8000, 4) == self.memory(0x8000, 4, "ram"), "C1LO ROM leaked after call"
        assert cpu_memory(self, 0xE000, 4) == self.memory(0xE000, 4, "ram"), "KERNAL ROM leaked after call"
        return cycles

    def keys(self, text: str | bytes) -> None:
        raw = text.encode("ascii") if isinstance(text, str) else bytes(text)
        for ch in raw:
            self.key_at_input(chr(ch) if ch < 128 else bytes([ch]))

    def key_at_input(self, key_val: str | bytes, wait: bool = True) -> None:
        byte_val = ord(key_val) if isinstance(key_val, str) else key_val[0]
        if wait:
            self.until(self.sym["hal_input_get_key"])
        row = next(line for line in self.cmd("r").splitlines() if line.strip().startswith(".;"))
        sp = int(row.split()[4], 16)
        ret = int.from_bytes(self.memory(0x0100 + sp + 1, 2), "little") + 1
        self.batch([
            f"r a={byte_val:02x}",
            f"r sp={(sp + 2) & 255:02x}",
            f"r pc={ret:04x}",
        ])

    def return_address(self) -> int:
        registers = self.cmd("r")
        row = next(line for line in registers.splitlines() if line.strip().startswith(".;"))
        sp = int(row.split()[4], 16)
        return int.from_bytes(self.memory(0x0100 + sp + 1, 2), "little") + 1

    def assert_carry(self, expected: bool = True) -> None:
        flags = re.search(r"\b([01]{8})\b", self.cmd("r"))
        assert flags and (flags[1][-1] == "1") == expected, "Unexpected persistence carry result"

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


def cpu_memory(exp: Experiment, address: int, size: int = 1) -> bytes:
    target = exp.out / "io.bin"
    target.unlink(missing_ok=True)
    exp.batch(["bank cpu", f'bsave "{target}" 0 ${address:04x} ${address + size - 1:04x}'])
    return target.read_bytes()


def assert_ted_cursor_hidden(exp: Experiment, context: str) -> None:
    ted_cursor = exp.memory(0xFF0C, 2, bank="io")
    pos = ((ted_cursor[0] & 0x03) << 8) | ted_cursor[1]
    assert pos >= 1000, f"TED hardware cursor visible on-screen at cell {pos} ({context}): {ted_cursor.hex()}"
    assert pos == 0x03FF, f"Expected parked TED cursor at $03FF ({context}), got ${pos:04x}"


def run_boot_workspace(args: argparse.Namespace) -> int:
    boot = symbols(args.symbols.parent / "cartridge_boot.sym")
    address = boot["boot_copy_prepare"]
    exp = Experiment(args, initial_break=address, name="boot")
    try:
        if not re.search(f"{address:04x}", exp.cmd("r"), re.I):
            exp.until(address)
        assert_ted_cursor_hidden(exp, "boot_copy_prepare")
        kernal_vectors = exp.memory(0x0312, 0x20)
        assert kernal_vectors[0] != 0xFF and any(kernal_vectors[0x16:0x18]), (
            "Boot ROM did not initialize KERNAL vectors before boot_copy_prepare"
        )
        before = int(exp.cmd("r").split(".;")[-1].splitlines()[0].split()[-1])
        exp.until(exp.sym["entry"])
        cycles = int(exp.cmd("r").split(".;")[-1].splitlines()[0].split()[-1]) - before
        print(f"INFO Plus/4 resident boot copy: {cycles} emulated cycles", flush=True)
        assert exp.memory(0x0312, 0x20) == kernal_vectors, "Boot copier altered KERNAL vectors $0312-$0331"
        exp.check("boot preserves KERNAL vectors at $0312-$0331 and completes resident copy")
        return exp.count
    finally:
        exp.close()


def run(args: argparse.Namespace) -> int:
    exp = Experiment(args, name="assets")
    try:
        registers = exp.cmd("r")
        if not re.search(f"{exp.sym['entry']:04x}", registers, re.I):
            exp.until(exp.sym["entry"])
        raw = (args.symbols.parent / "moria4.prg").read_bytes()
        assert exp.memory(0x1001, len(raw) - 2) == raw[2:]
        exp.check("native reset copied resident across $8000-$BFFF via bounce buffer and ROM bank crossings")
        exp.until(exp.sym["title_menu_loop"])
        assert_ted_cursor_hidden(exp, "title_menu_loop")
        runtime = (args.symbols.parent / "4.bank").read_bytes()[2:]
        assert exp.memory(0xF000, len(runtime)) == runtime
        exp.check("normal startup reached title without an attached disk; 4.bank matches at $F000")
        assert exp.memory(exp.sym["program_device"], 2) == bytes([8, 8]), "Cartridge must default to device 8"
        exp.check("cold cartridge defaults to device 8 without a preceding disk LOAD")
        page2 = exp.memory(0x0200, 0x59)
        manifest = json.loads((args.symbols.parent / "moria8-plus4.json").read_text())
        ovl_consts = catalog_disk.consts(ROOT / "platforms/commodore/common/overlay.s")
        for round_no in range(2):
            for symbol, filename in make_plus4_magic.OVERLAYS:
                asset = next(
                    a for a in manifest["assets"] if a["id"] == make_plus4_magic.CONTRACT["CART_ASSET_" + symbol]
                )
                cycles = exp.call(
                    exp.sym["overlay_load"],
                    ovl_consts["OVL_" + symbol],
                    irq_masked=bool(round_no),
                )
                expected = (args.symbols.parent / ("ovl." + filename)).read_bytes()[2:]
                assert exp.memory(0xE000, len(expected)) == expected, asset["name"]
                # Plus/4 TED slows CPU to single clock on active display lines (~26 TED ticks/byte).
                assert cycles < 28 * len(expected) + 12000, (asset["name"], cycles)
                if round_no == 0 and symbol == "STARTUP":
                    print(f"INFO startup overlay: {len(expected)} bytes, {cycles} emulated cycles", flush=True)
        exp.check("all thirteen overlays match through production dispatch in both IRQ states")
        records = catalog_disk.records()
        record_size = catalog_disk.layout()["CATALOG_RECORD_SIZE"]
        catalog_offset = manifest["assets"][make_plus4_magic.CONTRACT["CART_ASSET_CATALOG"]]["rom_offset"]
        crossing_ids = [
            i for i in range(len(records))
            if (catalog_offset + i * record_size) % make_plus4_magic.BANK_SIZE + record_size
            > make_plus4_magic.BANK_SIZE
        ]
        for record_id in sorted({0, 1, 255, 256, len(records) - 1, *crossing_ids}):
            exp.write(exp.sym["cat_id_lo"], record_id.to_bytes(2, "little"))
            cycles = exp.call(exp.sym["catalog_fetch_record"], irq_masked=True)
            # Plus/4 TED slows CPU to single clock on active display lines (~1.6x TED ticks/cycle).
            assert cycles < 4000, (record_id, cycles)
            assert exp.memory(exp.sym["cat_record"], record_size) == records[record_id]
        exp.check("catalog records match source, including 8-bit ID and bank boundaries")
        exp.call(exp.sym["cart_load_title"], irq_masked=True)
        title = (args.symbols.parent / "title").read_bytes()[2:]
        assert exp.memory(make_plus4_magic.MAP_BASE, len(title)) == title
        exp.check("title art reload matches at MAP_BASE ($C800)")
        legal_id = make_plus4_magic.CONTRACT["CART_ASSET_LEGAL_NOTICE"]
        legal_asset = next(asset for asset in manifest["assets"] if asset["id"] == legal_id)
        cache = exp.sym["legal_input_cache"]
        exp.write(cache, bytes([0xA5]) * 256)
        exp.write(exp.sym["cart_offset"], legal_asset["size"].to_bytes(2, "little"))
        exp.write(exp.sym["cart_is_record"], b"\x02")
        exp.call(exp.sym["cart_read"], legal_id, carry=True)
        assert exp.memory(cache, 256) == bytes([0xA5]) * 256
        exp.check("legal ROM read rejects the descriptor boundary without touching its cache")
        item_cat = catalog_disk.item_catalog_bytes()
        item_asset = next(
            asset for asset in manifest["assets"]
            if asset["id"] == make_plus4_magic.CONTRACT["CART_ASSET_ITEM_CATALOG"]
        )
        assert item_asset["size"] == len(item_cat)
        wrapper = 0xCE80
        byte_out = 0xCFF4
        x_out = 0xCFF5
        read_fn = exp.sym["hal_item_cat_cart_read_byte"]
        exp.write(
            wrapper,
            bytes([
                0xA2, 0x5A,
                0x20, read_fn & 0xFF, read_fn >> 8,
                0x8D, byte_out & 0xFF, byte_out >> 8,
                0x8E, x_out & 0xFF, x_out >> 8,
                0x18,
                0x60,
            ]),
        )
        cross = make_plus4_magic.CONTRACT["CART_ROM_WINDOW_BASE"] + make_plus4_magic.BANK_SIZE - item_asset["source"]
        offsets = [0, 1, 2, 3, len(item_cat) - 2, len(item_cat) - 1]
        if 0 < cross < len(item_cat):
            offsets.extend([max(0, cross - 2), max(0, cross - 1), cross, min(len(item_cat) - 1, cross + 1)])
        for off in dict.fromkeys(offsets):
            exp.write(exp.sym["item_cat_off_lo"], off.to_bytes(2, "little"))
            exp.call(wrapper, irq_masked=True)
            got = exp.memory(byte_out, 1)
            assert got == item_cat[off:off + 1], (
                f"hal_item_cat_cart_read_byte mismatch at {off}: got {got!r}, expected {item_cat[off:off + 1]!r}"
            )
            assert exp.memory(x_out, 1) == b"\x5A", "hal_item_cat_cart_read_byte clobbered X"
        exp.check("item catalog cart reader reads header, bank boundary, and EOF cleanly")
        assert exp.memory(0x0200, 0x59) == page2
        exp.check("diagnostic calls preserve all product-owned page-2 scratch")
        return exp.count
    finally:
        exp.close()


def run_zero_length(args: argparse.Namespace) -> int:
    fixture = args.output.resolve() / "zero-length.crt"
    raw = bytearray(args.crt.read_bytes())
    offset = (
        0x40
        + 16
        + make_plus4_magic.CONTRACT["CART_DIRECTORY"]
        - 0x8000
        + make_plus4_magic.CONTRACT["CART_ASSET_CHEST"] * make_plus4_magic.CONTRACT["CART_DESCRIPTOR_SIZE"]
        + 5
    )
    raw[offset:offset + 2] = bytes(2)
    fixture.write_bytes(raw)
    exp = Experiment(SimpleNamespace(**{**vars(args), "crt": fixture}), name="zero-length")
    try:
        exp.until(exp.sym["title_menu_loop"])
        original = exp.memory(0xE000, 0x1000)
        exp.call(exp.sym["cart_load_asset"], make_plus4_magic.CONTRACT["CART_ASSET_CHEST"])
        assert exp.memory(0xE000, 0x1000) == original
        exp.check("zero-length descriptor leaves its destination untouched")
        return exp.count
    finally:
        exp.close()


def run_catalog(args: argparse.Namespace) -> int:
    exp = Experiment(args, name="catalog")
    try:
        exp.until(exp.sym["title_menu_loop"])
        driver_symbols = symbols(args.symbols.parent / "cartridge_test_catalog.sym")
        exp.cmd(f'load "{(args.symbols.parent / "catalog-test.prg").resolve()}" 0')
        exp.forbidden = {driver_symbols["test_fail"]}
        exp.until(driver_symbols["test_pass"], driver_symbols["test_start"])
        expected = bytearray()
        for record in catalog_disk.records():
            expected.extend((
                sum(record) & 255,
                sum((len(record) - i) * b for i, b in enumerate(record)) & 255,
            ))
        assert exp.memory(0xC800, len(expected)) == expected
        exp.check(f"all {len(catalog_disk.records())} catalog records match source checksums and preserve math scratch")
        return exp.count
    finally:
        exp.close()


def run_gameplay(args: argparse.Namespace) -> int:
    from test_cartridge_persistence import snapshot

    exp = Experiment(args, name="gameplay")

    def menu_key(text: str, next_label: str) -> None:
        exp.keys(text)
        exp.until(exp.sym[next_label])

    def page() -> None:
        exp.until(exp.sym["legal_page_begin"])
        for addr_base in (0x0C00, 0x0800):
            exp.write(addr_base + 768, bytes([0x0A]) * 232)
        exp.until(exp.sym["legal_page_begin"] + 3)
        assert exp.memory(0x0C00, 1000) == b" " * 1000, "Full clear left stale text"
        attrs = exp.memory(0x0800, 1000)
        assert bytes(a & 0x7F for a in attrs) == b"\x71" * 1000, "Full clear left stale attributes"
        exp.until(exp.sym["legal_page_wait"])

    try:
        exp.until(exp.sym["title_menu_loop"])
        menu = "N)ew  L)oad  D)isk Setup  A)bout"
        row = exp.memory(0x0C00 + 18 * 40, 40)
        start = (40 - len(menu)) // 2
        want = bytes(ord(ch) - 0x60 if "a" <= ch <= "z" else ord(ch) for ch in menu)
        assert row[start:start + len(menu)] == want, f"Title menu not centred: {row!r}"

        exp.key_at_input("A")
        exp.until(exp.sym["legal_menu_wait"])
        exp.key_at_input("1")
        page()
        first = exp.memory(0x0C00, 1000)
        assert b"MORIA8 LICENSE NOTICE" in first
        exp.key_at_input("R")
        page()
        assert exp.memory(0x0C00, 1000) == first
        exp.key_at_input("Q")
        exp.until(exp.sym["legal_menu_wait"])
        exp.key_at_input("2")
        page()
        assert b"MORIA8 SOURCE OFFER" in exp.memory(0x0C00, 1000)
        for _ in range(5):
            if exp.memory(exp.sym["legal_eof"], 1) == b"\x40":
                break
            exp.key_at_input(" ")
            page()
        else:
            raise AssertionError("Source offer failed to reach EOF")
        exp.key_at_input("Q")
        exp.until(exp.sym["legal_menu_wait"])
        exp.key_at_input("Q")
        exp.until(exp.sym["title_menu_loop"])
        exp.check("title legal viewer reads both ROM documents, restarts, pages to EOF and returns")

        exp.key_at_input("N")
        exp.until(exp.sym["create_select_race"])
        menu_key("A", "create_roll_stats")
        menu_key("\r", "create_select_class")
        menu_key("A", "create_enter_name")
        menu_key("P4TEST\r", "create_select_gender")
        menu_key("A", "input_get_modal_dismiss_key")
        exp.key_at_input(" ")
        exp.until(exp.sym["main_loop"])
        assert exp.memory(exp.sym["zp_player_dlvl"], 1) == b"\0"
        exp.check("normal character creation and summary return reach town, no disk")

        before = snapshot(exp)
        exp.key_at_input("?")
        exp.until(exp.sym["hal_input_get_key"])
        hint = bytes(ord(ch) - 0x60 if "a" <= ch <= "z" else ord(ch) for ch in "L:License")
        assert hint in exp.memory(0x0C00, 40), "Help does not show the License shortcut"
        exp.key_at_input(" ", wait=False)
        exp.until(exp.sym["hal_input_get_key"])
        entry = bytes(ord(ch) - 0x60 if "a" <= ch <= "z" else ord(ch) for ch in "L License / Source")
        assert entry in exp.memory(0x0C00, 1000), "Help does not list the reader"
        exp.key_at_input("L", wait=False)
        exp.until(exp.sym["tramp_ui_legal_display"])
        exp.until(exp.sym["legal_menu_wait"])
        exp.key_at_input("Q")
        exp.until(exp.sym["hal_input_get_key"])
        exp.key_at_input("Q", wait=False)
        exp.until(exp.sym["main_loop"])
        assert snapshot(exp) == before, "Legal modal changed player, map or inventory"
        assert_ted_cursor_hidden(exp, "gameplay after Help/Legal modal")
        exp.check("Help legal modal reloads Help and returns without changing game state")

        world = exp.memory(make_plus4_magic.MAP_BASE, 80 * 48)
        stair = next(i for i, b in enumerate(world) if b & 0xF0 == 0x90)
        exp.write(exp.sym["zp_player_x"], bytes([stair % 80]))
        exp.write(exp.sym["zp_player_y"], bytes([stair // 80]))
        exp.key_at_input(">")
        exp.until(exp.sym["cmd_stairs_dn"])
        exp.until(exp.sym["main_loop"])
        assert exp.memory(exp.sym["zp_player_dlvl"], 1) == b"\x01"
        world = exp.memory(make_plus4_magic.MAP_BASE, 80 * 48)
        assert any(b & 0xF0 == 0xA0 for b in world), "Generated level lacks upstairs"
        exp.check("normal stairs dispatch generated dungeon level 1 and returned to play")

        # Quit via Shift+Q ($D1) + 'Y' -> game_over_prompt -> title_menu_loop with zero disks.
        exp.key_at_input(b"\xd1")
        exp.key_at_input("Y")
        exp.until(exp.sym["game_over_prompt"])
        exp.until(exp.sym["title_menu_loop"])
        exp.check("Quit returns cleanly to title menu with zero disks attached")

        # exit_trampoline cleanly resets and re-enters the cartridge instead of dead BASIC.
        exp.until(exp.sym["entry"], exp.sym["exit_trampoline"])
        exp.until(exp.sym["title_menu_loop"])
        exp.check("exit_trampoline cleanly restarts cartridge to title menu")
        return exp.count
    finally:
        exp.close()


def run_raw_magic(args: argparse.Namespace) -> int:
    assert args.bin is not None
    exp = Experiment(args, name="raw-magic", raw_bin=args.bin)
    try:
        exp.until(exp.sym["title_menu_loop"])
        exp.key_at_input("A")
        exp.until(exp.sym["legal_menu_wait"])
        exp.key_at_input("Q")
        exp.until(exp.sym["title_menu_loop"])
        exp.key_at_input("N")
        exp.until(exp.sym["create_select_race"])
        for ch, lbl in (
            ("A", "create_roll_stats"),
            ("\r", "create_select_class"),
            ("A", "create_enter_name"),
        ):
            exp.key_at_input(ch)
            exp.until(exp.sym[lbl])
        exp.keys("RAW\r")
        exp.until(exp.sym["create_select_gender"])
        exp.key_at_input("A")
        exp.until(exp.sym["input_get_modal_dismiss_key"])
        exp.key_at_input(" ")
        exp.until(exp.sym["main_loop"])
        exp.check("raw -cartmagic 256 KB image boots, shows legal modal and reaches town with zero disks")
        return exp.count
    finally:
        exp.close()


def selftest() -> None:
    contract = make_plus4_magic.CONTRACT
    assert contract["CART_BANK_COUNT"] == 16
    assert contract["CART_ROM_BANK_SIZE"] == 0x4000
    assert contract["CART_REG_C1LO_KERNAL"] == 0xFDD2
    assert contract["CART_REG_BASIC_KERNAL"] == 0xFDD0
    assert contract["CART_REG_BANK"] == 0xFDFE
    assert contract["CART_ASSET_COUNT"] == 22
    with tempfile.TemporaryDirectory(prefix="plus4-harness-selftest-") as tmp:
        sym_path = Path(tmp) / "test.sym"
        sym_path.write_text(".label entry=$100e\n.label title_menu_loop=$c300\n")
        parsed = symbols(sym_path)
        assert parsed == {"entry": 0x100E, "title_menu_loop": 0xC300}
    print("PASS selftest: Plus/4 cartridge harness constants and symbol parser verified", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--crt", type=Path)
    parser.add_argument("--bin", type=Path)
    parser.add_argument("--symbols", type=Path)
    parser.add_argument("--vice", default="xplus4")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--ntsc", action="store_true")
    options = parser.parse_args()
    if options.selftest:
        selftest()
        if options.crt is None:
            sys.exit(0)
    if options.crt is None or options.symbols is None or options.output is None:
        parser.error("--crt, --symbols and --output are required unless running --selftest alone")
    prepare_run(options)
    count = (
        run_boot_workspace(options)
        + run(options)
        + run_catalog(options)
        + run_gameplay(options)
        + run_zero_length(options)
    )
    if options.bin is not None:
        count += run_raw_magic(options)
    print(f"Plus/4 cartridge experiment: {count} checks passed", flush=True)
