#!/usr/bin/env python3
"""Exercise the actual EasyFlash reset and cartridge-enabled product in VICE.

Every launched emulator is bounded to 30 seconds; monitor operations share
that deadline. Scratch and logs belong under the caller's build directory.
"""
from __future__ import annotations

import argparse
import json
import os
import errno
import pty
from pathlib import Path
import re
import subprocess
import sys
import time
import threading
import shutil
import tempfile
from datetime import datetime, timezone
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from vice_connector import VICEConnector, allocate_free_port, PROMPT_RE
from vice_config import vice_config
import catalog_disk
import make_easyflash

MONITOR_ERROR_RE = re.compile(r"(?im)^\s*(?:ERROR\b|Unknown command|Syntax error|Invalid argument|Unknown resource)")


def symbols(path):
    return {name: int(value, 16) for name, value in
            re.findall(r"\.label (\w+)=\$([0-9a-fA-F]+)", path.read_text())}


def prepare_run(args):
    base = args.output.resolve()
    base.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    args.output = Path(tempfile.mkdtemp(prefix=f"run-{stamp}-", dir=base))
    print(f"Evidence: {args.output}", flush=True)


class Experiment:
    def __init__(self, args, initial_break=None, name="assets", disk=None, disk_build=False):
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
        port = allocate_free_port()
        self.mon = VICEConnector(port=port, timeout=0.2)
        self.log = (self.out / "console.log").open("wb", buffering=0)
        self.console_master, console_slave = pty.openpty()
        os.set_blocking(self.console_master, False)
        self.console_stop = threading.Event()
        self.console_thread = None
        test_crt = self.out / "cartridge.crt"
        media_args = []
        if not disk_build:
            shutil.copyfile(args.crt, test_crt)
            media_args += ["-cartcrt", str(test_crt)]
        if disk is not None:
            if disk_build:
                media_args += ["-autostartprgmode", "1", "-drive9type", "1541", "-8", str(args.disk_image.resolve()), "-attach9rw", "-9", str(disk.resolve())]
            else:
                media_args += ["-8", str(disk.resolve())]
        command = [args.vice, "-config", vice_config(args.vice),
            "-default", "+saveres", "+autostart-delay-random", "-console", "-nativemonitor", "-warp",
            "+sound", "-sounddev", "dummy", "+confirmonexit", "+easyflashcrtwrite",
            *media_args, "-ntsc" if args.ntsc else "-pal", "-remotemonitor", "-remotemonitoraddress",
            f"127.0.0.1:{port}"]
        self.event("launch", command=command, video="ntsc" if args.ntsc else "pal",
                   mode="disk" if disk_build else "cartridge", monitor_port=port)
        try:
            env = dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
            try:
                self.proc = subprocess.Popen(command, stdout=console_slave, stderr=subprocess.STDOUT, env=env, cwd=ROOT)
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
            # A greeting alone is not a response to our command. The final
            # register row and prompt prove the stopped monitor is ready.
            self.batch([])
            self.batch(["del", f"break ${initial_break:04x}"])
            self.phase = "autostart" if disk_build else "reset"
            self.event("phase")
            if disk_build:
                # Inject the normal PRG; the existing C64 gate covers disk boot.
                self.cmd(f'autostart "{(self.symbol_path.parent / "moria8.prg").resolve()}"')
            else:
                self.cmd("reset 1")
            # Asynchronous startup may itself have hit the armed breakpoint.
            if not re.search(rf"(?im)^\s*\.;{initial_break:04x}\s", self.cmd("r")):
                self.until(initial_break)
            self.phase = "entry"
            self.event("phase")
            if disk_build:
                self.write(0xBA, b"\x08")  # The normal disk loader's device fixture
                self.phase = "title"
                self.event("phase")
                self.until(self.sym["title_menu_loop"])
            self.phase = "running"
            self.event("phase")
        except Exception as exc:
            self.event("startup_error", error=repr(exc))
            self.close()
            raise

    def event(self, kind, **details):
        with self.event_lock:
            record = dict(event=kind, phase=self.phase, elapsed=time.monotonic()-self.started,
                          pid=self.proc.pid if self.proc else None,
                          returncode=self.proc.poll() if self.proc else None,
                          checks=self.count, watchdog_fired=self.watchdog_fired,
                          termination_action=self.termination_action, **details)
            with (self.out / "events.jsonl").open("a") as log:
                log.write(json.dumps(record) + "\n")
            return record

    def capture_console(self):
        # A tty makes VICE's console line-buffered. Copy it directly to disk;
        # changing LogFileName crashes the installed VICE 3.10 build (#2240).
        stopping = False
        while True:
            try:
                data = os.read(self.console_master, 65536)
            except BlockingIOError:
                if stopping:
                    return
                # Re-read after waking: cleanup can signal stop at the same
                # time the exiting child makes its last bytes readable.
                stopping = self.console_stop.wait(0.01)
                continue
            except OSError as exc:
                if exc.errno != errno.EIO:  # Slave closed: ordinary tty EOF
                    self.event("console_error", error=repr(exc))
                return
            if not data:
                return
            self.log.write(data)

    def watchdog(self):
        if self.proc.poll() is None:
            self.watchdog_fired = True
            self.termination_action = "watchdog_kill"
            try:
                self.proc.kill()
            except ProcessLookupError:
                pass
            self.event("watchdog")

    def more_response(self):
        try:
            response = self.mon.read_until_prompt(deadline=self.deadline)
        except Exception as exc:
            self.event("monitor_error", error=repr(exc))
            raise
        with (self.out / "monitor.log").open("a") as log:
            log.write(response + "\n")
        return response

    def cmd(self, command, expect_prompt=True):
        # Preserve the pending command even if the peer dies before replying.
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

    def batch(self, commands):
        script = self.out / "commands.mon"
        script.write_text("\n".join([*commands, "r"]) + "\n")
        response = self.cmd(f'pb "{script}"')
        while ("STOPWATCH" not in response or not re.search(r"(?m)^\s*\.;[0-9a-fA-F]+", response)
               or not PROMPT_RE.search(response.encode())):
            response += self.more_response()
        if MONITOR_ERROR_RE.search(response):
            raise AssertionError(response)
        return response

    def memory(self, address, size, bank="ram"):
        target = self.out / "memory.bin"
        target.unlink(missing_ok=True)
        self.batch([f"bank {bank}", f'bsave "{target}" 0 ${address:04x} ${address+size-1:04x}', "bank cpu"])
        data = target.read_bytes()
        assert len(data) == size, (len(data), size)
        return data

    def write(self, address, data):
        target = self.out / "driver.prg"
        target.write_bytes(address.to_bytes(2, "little") + bytes(data))
        self.cmd(f'load "{target}" 0')

    def until(self, address, start=None, alternatives=()):
        commands = ["del"]
        for forbidden in getattr(self, "forbidden", ()):
            commands.append(f"break ${forbidden:04x}")
        # RAM breakpoints must exclude execution from BASIC/KERNAL ROM.
        for target in (address, *alternatives):
            guard = ""
            if 0xA000 <= target < 0xC000:
                guard = " if (@cpu:$0001 & $03) != $03"
            elif target >= 0xE000:
                guard = " if (@cpu:$0001 & $02) == $00"
            commands.append(f"break ${target:04x}{guard}")
        self.batch(commands)
        response = self.cmd("g" if start is None else f"g ${start:04x}")
        for target in (address, *alternatives):
            if re.search(rf"(?:C:|PC:|PC=)\$?{target:04x}", response, re.I):
                return target
        raise AssertionError(f"Did not reach ${address:04x}: {response}")

    def call(self, routine, a=0, port=0x36, irq_masked=True, carry=False):
        # Title-only map loan: callers here never resume gameplay.
        # C600-C6FF holds the driver, C7F0-C7F1 holds results.
        assert self.sym["program_end"] <= 0xC000
        assert len((self.args.symbols.parent / "title").read_bytes()) - 2 <= 0x600
        code = [0x78 if irq_masked else 0x58, 0xA9, port, 0x85, 1,
                0xA9, a, 0x20, routine & 255, routine >> 8,
                0x08, 0x68, 0x8D, 0xF0, 0xC7, 0xA5, 1, 0x8D, 0xF1, 0xC7]
        end = 0xC600 + len(code)
        code += [0x4C, end & 255, end >> 8]
        before = int(self.cmd("r").split(".;")[-1].splitlines()[0].split()[-1])
        self.write(0xC600, code)
        self.until(end, 0xC600)
        cycles = int(self.cmd("r").split(".;")[-1].splitlines()[0].split()[-1]) - before
        flags, restored_port = self.memory(0xC7F0, 2)
        assert restored_port == port, (routine, restored_port, port)
        assert bool(flags & 4) == irq_masked, (routine, flags)
        assert bool(flags & 1) == carry, (routine, flags)
        return cycles

    def keys(self, text):
        data = text.encode("ascii") if isinstance(text, str) else bytes(text)
        assert 0 < len(data) <= 10
        key_file = self.out / "keys.prg"
        count_file = self.out / "key-count.prg"
        key_file.write_bytes(b"\x77\x02" + data)
        count_file.write_bytes(b"\xc6\x00" + bytes([len(data)]))
        self.batch([f'load "{key_file}" 0', f'load "{count_file}" 0'])

    def key_at_input(self, text):
        self.until(self.sym["hal_input_get_key"])
        self.keys(text)

    def return_address(self):
        registers = self.cmd("r")
        row = next(line for line in registers.splitlines() if line.strip().startswith(".;"))
        sp = int(row.split()[4], 16)
        return int.from_bytes(self.memory(0x0100 + sp + 1, 2), "little") + 1

    def assert_carry(self, expected=True):
        flags = re.search(r"\b([01]{8})\b", self.cmd("r"))
        assert flags and (flags[1][-1] == "1") == expected, "Unexpected persistence carry result"

    def check(self, message):
        self.count += 1
        self.event("check", message=message)
        print(f"PASS {message}", flush=True)

    def close(self):
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


def run(args):
    exp = Experiment(args)
    try:
        registers = exp.cmd("r")
        if not re.search(f"{exp.sym['entry']:04x}", registers, re.I):
            exp.until(exp.sym["entry"])
        raw = (args.symbols.parent / "moria8.prg").read_bytes()
        assert exp.memory(0x0801, len(raw)-2) == raw[2:]
        exp.check("native reset copied resident exactly, including ROM bank crossings")
        exp.until(exp.sym["title_menu_loop"])
        assert cpu_memory(exp, 0xD031) == b"\xff"
        assert exp.memory(exp.sym["c64_hw_flags"], 1) == b"\0"
        runtime = (args.symbols.parent / "64.bank").read_bytes()[2:]
        assert exp.memory(0xF000, len(runtime)) == runtime
        exp.check("normal startup reached title without an attached disk; runtime matches")
        assert exp.memory(exp.sym["program_device"], 2) == bytes([8, 8]), "Cartridge must default to save device 8"
        exp.check("cold cartridge defaults to device 8 without a preceding disk LOAD")
        page2 = [(0x0200, exp.memory(0x0200, 0x59)), (0x02A7, exp.memory(0x02A7, 0x59))]
        manifest = json.loads(args.crt.with_suffix(".json").read_text())
        for round_no in range(2):
            for symbol, filename in make_easyflash.OVERLAYS:
                asset = next(a for a in manifest["assets"] if a["id"] == make_easyflash.CONTRACT["CART_ASSET_" + symbol])
                # Real overlay dispatch, filename HAL adapter and ROM copier.
                cycles = exp.call(exp.sym["overlay_load"], catalog_disk.consts(ROOT / "platforms/commodore/common/overlay.s")["OVL_" + symbol],
                         port=0x34 if round_no else 0x36, irq_masked=bool(round_no))
                expected = (args.symbols.parent / ("ovl." + filename)).read_bytes()[2:]
                assert exp.memory(0xE000, len(expected)) == expected, asset["name"]
                assert cycles < 24 * len(expected) + 8000, (asset["name"], cycles)
                if round_no == 0 and symbol == "STARTUP":
                    print(f"INFO startup overlay: {len(expected)} bytes, {cycles} emulated cycles", flush=True)
        exp.check("all ten overlays match through production dispatch in both banking/IRQ states")
        records = catalog_disk.records()
        record_size = catalog_disk.layout()["CATALOG_RECORD_SIZE"]
        catalog_offset = manifest["assets"][make_easyflash.CONTRACT["CART_ASSET_CATALOG"]]["rom_offset"]
        crossing_ids = [i for i in range(len(records))
                        if (catalog_offset + i * record_size) % make_easyflash.BANK_SIZE + record_size > make_easyflash.BANK_SIZE]
        assert crossing_ids, "Fixture must exercise a record across a ROM bank"
        for record_id in sorted({0, 1, 255, 256, len(records)-1, *crossing_ids}):
            exp.write(exp.sym["cat_id_lo"], record_id.to_bytes(2, "little"))
            cycles = exp.call(exp.sym["catalog_fetch_record"], port=0x34)
            assert cycles < 2000, (record_id, cycles)
            assert exp.memory(exp.sym["cat_record"], record_size) == records[record_id]
        exp.check("catalog records match source, including 8 KB and 8-bit ID boundaries")
        exp.call(exp.sym["cart_load_title"], port=0x36)
        title = (args.symbols.parent / "title").read_bytes()[2:]
        assert exp.memory(0xC000, len(title)) == title
        exp.check("title art reload matches")
        legal_id = make_easyflash.CONTRACT["CART_ASSET_LEGAL_NOTICE"]
        legal_asset = next(asset for asset in manifest["assets"] if asset["id"] == legal_id)
        cache = exp.sym["legal_input_cache"]
        exp.write(cache, bytes([0xA5]) * 256)
        exp.write(exp.sym["cart_offset"], legal_asset["size"].to_bytes(2, "little"))
        exp.write(exp.sym["cart_is_record"], b"\x02")
        exp.call(exp.sym["cart_read"], legal_id, carry=True)
        assert exp.memory(cache, 256) == bytes([0xA5]) * 256
        exp.check("legal ROM read rejects the descriptor boundary without touching its cache")
        for address, original in page2:
            assert exp.memory(address, len(original)) == original
        exp.check("diagnostic calls preserve all product-owned page-2 scratch")
        return exp.count
    finally:
        exp.close()


def run_boot_workspace(args):
    boot = symbols(args.symbols.parent / "cartridge_boot.sym")
    address = boot["boot_copy_prepare"]
    exp = Experiment(args, initial_break=address, name="boot")
    try:
        if not re.search(f"{address:04x}", exp.cmd("r"), re.I):
            exp.until(address)
        original = exp.memory(0x0277, 0x89)
        before = int(exp.cmd("r").split(".;")[-1].splitlines()[0].split()[-1])
        exp.until(exp.sym["entry"])
        cycles = int(exp.cmd("r").split(".;")[-1].splitlines()[0].split()[-1]) - before
        print(f"INFO resident boot copy: {cycles} emulated cycles", flush=True)
        assert exp.memory(0x0277, 0x89) == original
        exp.check("boot preserves KERNAL keyboard/editor settings at $0277-$02FF")
        return exp.count
    finally:
        exp.close()


def run_zero_length(args):
    # A malformed-but-safe fixture exercises the reader's zero-count boundary.
    # Alter an unused overlay descriptor in a private CRT under build/.
    fixture = args.output.resolve() / "zero-length.crt"
    raw = bytearray(args.crt.read_bytes())
    offset = (0x40 + 16 + make_easyflash.CONTRACT["CART_DIRECTORY"] - 0x8000
              + make_easyflash.CONTRACT["CART_ASSET_CHEST"] * make_easyflash.CONTRACT["CART_DESCRIPTOR_SIZE"] + 5)
    raw[offset:offset+2] = bytes(2)
    fixture.write_bytes(raw)
    exp = Experiment(SimpleNamespace(**{**vars(args), "crt": fixture}), name="zero-length")
    try:
        exp.until(exp.sym["title_menu_loop"])
        original = exp.memory(0xE000, 0x1000)
        exp.call(exp.sym["cart_load_asset"], make_easyflash.CONTRACT["CART_ASSET_CHEST"])
        assert exp.memory(0xE000, 0x1000) == original
        exp.check("zero-length descriptor leaves its destination untouched")
        return exp.count
    finally:
        exp.close()


def run_catalog(args):
    exp = Experiment(args, name="catalog")
    try:
        exp.until(exp.sym["title_menu_loop"])
        driver_symbols = symbols(args.symbols.parent / "cartridge_test_catalog.sym")
        exp.cmd(f'load "{(args.symbols.parent / "catalog-test.prg").resolve()}" 0')
        exp.forbidden = {driver_symbols["test_fail"]}
        exp.until(driver_symbols["test_pass"], driver_symbols["test_start"])
        expected = bytearray()
        for record in catalog_disk.records():
            expected.extend((sum(record) & 255,
                sum((len(record)-i) * b for i, b in enumerate(record)) & 255))
        assert exp.memory(0xC800, len(expected)) == expected
        exp.check(f"all {len(catalog_disk.records())} catalog records match source checksums and preserve math scratch")
        return exp.count
    finally:
        exp.close()


def run_nmi(args):
    exp = Experiment(args, name="nmi")
    try:
        exp.until(exp.sym["title_menu_loop"])
        original_vector = exp.memory(0x0318, 2)
        original_zp = exp.memory(2, 0x8E)
        routine = exp.sym["cart_load_asset"]
        # Call the actual reader, stop inside its mapped copy loop, then
        # cause a hardware CIA2 timer NMI rather than calling its handler.
        code = [0x78, 0xA9, 0x36, 0x85, 1, 0xA9, make_easyflash.CONTRACT["CART_ASSET_STARTUP"],
                0x20, routine & 255, routine >> 8]
        end = 0xC600 + len(code)
        exp.write(0xC600, code + [0x4C, end & 255, end >> 8])
        exp.until(exp.sym["cart_source"], 0xC600)
        exp.cmd("> dd0e 00")
        exp.cmd("> dd04 01 00")
        exp.cmd("> dd0d 81")
        exp.cmd("> dd0e 19")
        exp.until(exp.sym["cart_nmi"])
        exp.until(end)
        expected = (args.symbols.parent / "ovl.start").read_bytes()[2:]
        assert exp.memory(0xE000, len(expected)) == expected
        assert exp.memory(0x0318, 2) == original_vector
        assert exp.memory(2, 0x8E) == original_zp
        exp.check("hardware NMI during mapped transfer returns safely; vector and game ZP restored")
        return exp.count
    finally:
        exp.close()


def cpu_memory(exp, address):
    # Experiment.memory deliberately reads underlying RAM; hardware probes
    # need the CPU-visible I/O mapping instead.
    target = exp.out / "io.bin"
    exp.batch(["bank cpu", f'bsave "{target}" 0 ${address:04x} ${address:04x}'])
    return target.read_bytes()


def redirect_turbo_register(exp):
    # VICE has no Ultimate clock registers. Redirect only the four hardware
    # operands in the linked production routines to a simulated register in
    # the now-dead boot cassette buffer. Gameplay/map memory stays untouched.
    register = 0x033C
    count = 0
    for start, end in (("c64u_turbo_detect", "c64u_turbo_detect_end"),
                       ("c64u_turbo_fast", "c64u_turbo_end")):
        address = exp.sym[start]
        code = exp.memory(address, exp.sym[end] - address)
        for opcode in (0xAD, 0x8D):
            operand = bytes([opcode, 0x31, 0xD0])
            count += code.count(operand)
            code = code.replace(operand, bytes([opcode, register & 255, register >> 8]))
        exp.write(address, code)
    assert count == 4, count
    return register


def run_turbo(args):
    probe = symbols(args.symbols)["c64u_turbo_detect"]
    exp = Experiment(args, initial_break=probe, name="turbo")
    def call(name):
        routine = exp.sym[name]
        # Title-only scratch loan, as in Experiment.call. Set carry explicitly
        # because the detector's CMP changes it; inspect the CPU port below.
        code = [0x78, 0xA9, 0x36, 0x85, 1, 0x18,
                0x20, routine & 255, routine >> 8]
        end = 0xC600 + len(code)
        exp.write(0xC600, code + [0x4C, end & 255, end >> 8])
        exp.until(end, 0xC600)
        assert cpu_memory(exp, 1) == b"\x36"
    def state(depth, flags, speed):
        assert exp.memory(exp.sym["c64u_turbo_depth"], 1) == bytes([depth])
        assert exp.memory(exp.sym["c64_hw_flags"], 1) == bytes([flags])
        assert exp.memory(register, 1) == bytes([speed])
    try:
        # A coincidental UCI-looking byte in real EasyFlash RAM must not
        # identify Ultimate or enable turbo on the stock VIC.
        exp.cmd("> df1d c9")
        assert cpu_memory(exp, 0xDF1D) == b"\xc9"
        assert cpu_memory(exp, 0xD031) == b"\xff"
        exp.write(exp.sym["c64_hw_flags"], b"\x07")
        call("c64u_turbo_detect")
        assert exp.memory(exp.sym["c64_hw_flags"], 1) == b"\0"
        exp.check("stock VIC rejects a false UCI signature in EasyFlash RAM")
        register = redirect_turbo_register(exp)
        # Ultimate documentation: FF means unavailable; exposed speed/badline
        # settings are detected without changing the register during probing.
        for speed in (0xFF, 0, 0x0F, 0x80, 0x8F):
            exp.write(register, bytes([speed]))
            call("c64u_turbo_detect")
            state(0, 0 if speed == 0xFF else 3, speed)
        exp.check("read-only turbo probe handles disabled, normal, fast and badline settings")
        exp.write(register, b"\xff")
        call("c64u_turbo_detect")
        call("c64u_turbo_fast")
        call("c64u_turbo_normal")
        state(0, 0, 0xFF)
        exp.check("unavailable turbo leaves the simulated register and nesting untouched")
        for speed in (0, 5, 0x85, 0x8F):
            exp.write(register, bytes([speed]))
            call("c64u_turbo_detect")
            call("c64u_turbo_fast")
            state(1, 7, 0x0F)
            assert exp.memory(exp.sym["c64u_turbo_prev"], 1) == bytes([speed])
            call("c64u_turbo_fast")
            state(2, 7, 0x0F)
            call("c64u_turbo_normal")
            state(1, 7, 0x0F)
            call("c64u_turbo_normal")
            state(0, 3, speed)
            call("c64u_turbo_normal")
            state(0, 3, speed)
        exp.check("nested production bursts restore the exact prior speed and badline bit")
        return exp.count
    finally:
        exp.close()


def run_gameplay(args, turbo=False):
    probe = symbols(args.symbols)["c64u_turbo_detect"] if turbo else None
    exp = Experiment(args, initial_break=probe, name="gameplay-turbo" if turbo else "gameplay")
    def keys(text):
        data = text.encode("ascii")
        exp.write(0x0277, data)
        exp.write(0x00C6, bytes([len(data)]))
    def menu_key(text, next_label):
        exp.until(exp.sym["hal_input_get_key"])
        keys(text)
        exp.until(exp.sym[next_label])
    def page():
        exp.until(exp.sym["legal_page_begin"])
        # Stale-page fixture for the HAL full-clear invariant. Sprite pointers
        # after the 1000 visible cells retain their existing ownership.
        exp.write(0x0700, bytes([0x0A]) * 232)
        exp.write(0xDB00, bytes([0x0A]) * 232)
        color = exp.memory(exp.sym["zp_text_color"], 1)[0]
        exp.until(exp.sym["legal_page_begin"] + 3)
        assert exp.memory(0x0400, 1000) == b" " * 1000, "Full clear left stale text"
        assert bytes(a & 15 for a in exp.memory(0xD800, 1000, "cpu")) == bytes([color]) * 1000, "Full clear left stale attributes"
        exp.until(exp.sym["legal_page_wait"])
    try:
        if turbo:
            register = redirect_turbo_register(exp)
            exp.write(register, b"\x85")
        exp.until(exp.sym["title_menu_loop"])
        assert exp.memory(exp.sym["c64_hw_flags"], 1) == bytes([3 if turbo else 0])
        if turbo:
            assert exp.memory(register, 1) == b"\x85"
        keys("A")
        exp.until(exp.sym["legal_menu_wait"])
        exp.key_at_input("1")
        page()
        first = exp.memory(0x0400, 1000)
        assert b"MORIA8 LICENSE NOTICE" in first
        exp.key_at_input("R")
        page()
        assert exp.memory(0x0400, 1000) == first
        exp.key_at_input("Q")
        exp.until(exp.sym["legal_menu_wait"])
        exp.key_at_input("2")
        page()
        assert b"MORIA8 SOURCE OFFER" in exp.memory(0x0400, 1000)
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
        keys("N")
        exp.until(exp.sym["create_select_race"])
        menu_key("A", "create_roll_stats")
        menu_key("\r", "create_select_class")
        menu_key("A", "create_enter_name")
        menu_key("EFTEST\r", "create_select_gender")
        menu_key("A", "input_get_modal_dismiss_key")
        # Modal entry flushes buffered keys before waiting for a fresh key.
        exp.until(exp.sym["hal_input_get_key"])
        keys(" ")
        exp.until(exp.sym["main_loop"])
        assert exp.memory(exp.sym["zp_player_dlvl"], 1) == b"\0"
        exp.check("normal character creation and summary return reach town, no disk")
        from test_cartridge_persistence import snapshot
        before = snapshot(exp)
        exp.key_at_input("?")
        exp.until(exp.sym["hal_input_get_key"])
        hint = bytes(ord(ch) - 0x60 if "a" <= ch <= "z" else ord(ch) for ch in "L:License")
        assert hint in exp.memory(0x0400, 40), "Help does not show the License shortcut"
        exp.keys(" ")
        exp.until(exp.sym["hal_input_get_key"])
        entry = bytes(ord(ch) - 0x60 if "a" <= ch <= "z" else ord(ch) for ch in "L License / Source")
        assert entry in exp.memory(0x0400, 1000), "Help does not list the reader"
        exp.keys("L")
        exp.until(exp.sym["tramp_ui_legal_display"])
        exp.write(exp.sym["zp_snd_effect"], b"\x00\x01\x01")
        exp.until(exp.sym["legal_menu_wait"])
        exp.key_at_input("Q")
        exp.until(exp.sym["legal_return"])
        exp.write(exp.sym["zp_ui_dirty"], b"\x80")
        dirty_offset = exp.sym["zp_ui_dirty"] - 2
        exp.write(exp.sym["legal_zp_save"] + dirty_offset, b"\x01")
        exp.until(exp.return_address())
        assert exp.memory(exp.sym["zp_ui_dirty"], 1) == b"\x81"
        assert exp.memory(exp.sym["zp_snd_effect"], 1) == b"\xff"
        exp.check("legal return retains both dirty producers and sound expiry during input")
        exp.until(exp.sym["hal_input_get_key"])
        exp.keys("Q")
        exp.until(exp.sym["main_loop"])
        assert snapshot(exp) == before, "Legal modal changed player, map or inventory"
        exp.check("Help legal modal reloads Help and returns without changing game state")
        # Put the player on the town's actual down staircase, then use normal
        # command dispatch. This fixture changes position, not the generator.
        world = exp.memory(0xC000, 80*48)
        stair = next(i for i,b in enumerate(world) if b & 0xF0 == 0x90)
        exp.write(exp.sym["zp_player_x"], bytes([stair % 80]))
        exp.write(exp.sym["zp_player_y"], bytes([stair // 80]))
        exp.until(exp.sym["hal_input_get_key"])
        keys(">")
        exp.until(exp.sym["cmd_stairs_dn"])
        exp.until(exp.sym["tramp_level_generate"])
        if turbo:
            assert exp.memory(register, 1) == b"\x0f"
        assert exp.memory(exp.sym["c64u_turbo_depth"], 1) == bytes([1 if turbo else 0])
        exp.until(exp.sym["main_loop"])
        if turbo:
            assert exp.memory(register, 1) == b"\x85"
        assert exp.memory(exp.sym["c64u_turbo_depth"], 1) == b"\0"
        assert exp.memory(exp.sym["c64_hw_flags"], 1) == bytes([3 if turbo else 0])
        assert exp.memory(exp.sym["zp_player_dlvl"], 1) == b"\x01"
        world = exp.memory(0xC000, 80*48)
        assert any(b & 0xF0 == 0xA0 for b in world), "Generated level lacks upstairs"
        exp.check("normal stairs dispatch generated dungeon level 1 and returned to play")
        if turbo:
            exp.check("production stairs/generation burst restores prior speed before gameplay resumes")
        return exp.count
    finally:
        exp.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--crt", type=Path, required=True)
    parser.add_argument("--symbols", type=Path, required=True)
    parser.add_argument("--vice", default="x64sc")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ntsc", action="store_true")
    options = parser.parse_args()
    prepare_run(options)
    count = (run_turbo(options) + run_boot_workspace(options) + run(options)
             + run_catalog(options) + run_nmi(options) + run_gameplay(options)
             + run_gameplay(options, turbo=True) + run_zero_length(options))
    print(f"Cartridge experiment: {count} checks passed")
