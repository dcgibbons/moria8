#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
C128_TESTS = SCRIPT_DIR.parent.parent / "c128" / "tests"
if str(C128_TESTS) not in sys.path:
    sys.path.insert(0, str(C128_TESTS))

from vice_connector import VICEConnector, normalize_addr, parse_vs_symbols


BYTE_RE = re.compile(r"C:([0-9A-Fa-f]{4})\s+([0-9A-Fa-f]{2})")
REG_RE = re.compile(
    r"(?:\.;|\.C:)[0-9A-Fa-f]{4}\s+"
    r"([0-9A-Fa-f]{2})\s+([0-9A-Fa-f]{2})\s+"
    r"([0-9A-Fa-f]{2})\s+([0-9A-Fa-f]{2})\b"
)
FLAG_RE = re.compile(r"([NV.][V.]-[B.][D.][I.][Z.][C.])")
FLAG_BITS_RE = re.compile(
    r"(?:\.;|\.C:)[0-9A-Fa-f]{4}\s+"
    r"(?:[0-9A-Fa-f]{2}\s+){6}([01]{8})\b"
)
DRIVE_1541U = 0x04
STATUS_TOO_MANY_DEVICES = 0xFC

ERROR_MUTE_MESSAGE = (
    b"\x0e\x05\xc5\xd2\xd2\xcf\xd2: \xc6AILED TO MUTE DEVICE #00.\x00"
)
WARNING_1541U_MESSAGE = (
    b"\x0e\x05\xd7\xc1\xd2\xce\xc9\xce\xc7: \xc2UGGY 1541\xd5 FIRMWARE DETECTED. "
    b"\xd0LEASE UPDATE.\x00"
)


def read_byte(connector: VICEConnector, address: int) -> int:
    response = connector.send_command(f"m {address:04x} {address:04x}")
    match = BYTE_RE.search(response)
    if not match:
        raise RuntimeError(f"could not read ${address:04x}: {response.strip()}")
    return int(match.group(2), 16)


def read_d011_mode(connector: VICEConnector) -> int:
    return read_byte(connector, 0xD011) & 0x7F


def read_bytes(connector: VICEConnector, start: int, length: int) -> bytes:
    return bytes(read_byte(connector, start + offset) for offset in range(length))


def flags_value(text: str) -> int:
    bits = FLAG_BITS_RE.search(text)
    if bits:
        return int(bits.group(1), 2)
    matches = FLAG_RE.findall(text.upper())
    if not matches:
        raise RuntimeError(f"could not parse processor flags: {text.strip()}")
    flags = matches[-1]
    value = 0x20
    for index, bit in ((0, 0x80), (1, 0x40), (3, 0x10), (4, 0x08), (5, 0x04), (6, 0x02), (7, 0x01)):
        if flags[index] != ".":
            value |= bit
    return value


def register_values(connector: VICEConnector) -> tuple[dict[str, int], int]:
    response = connector.send_command("r")
    match = REG_RE.search(response)
    if not match:
        raise RuntimeError(f"could not parse processor registers: {response.strip()}")
    registers = {
        name: int(value, 16)
        for name, value in zip(("A", "X", "Y", "SP"), match.groups())
    }
    return registers, flags_value(response)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def find_unique(data: bytes, pattern: list[int | None], name: str) -> int:
    matches = [
        offset
        for offset in range(len(data) - len(pattern) + 1)
        if all(expected is None or data[offset + index] == expected for index, expected in enumerate(pattern))
    ]
    if len(matches) != 1:
        raise RuntimeError(f"expected one {name} pattern, found {len(matches)}")
    return matches[0]


def screen_codes(message: bytes) -> bytes:
    result = bytearray()
    for value in message:
        if value == 0:
            break
        if value in (0x05, 0x0E):
            continue
        if 0x40 <= value <= 0x5F:
            value -= 0x40
        elif 0xC0 <= value <= 0xDF:
            value -= 0x80
        result.append(value)
    return bytes(result)


class BootHarness:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.boot_symbols = parse_vs_symbols(args.boot_vs)
        self.main_symbols = parse_vs_symbols(args.main_vs)
        self.symbols = {**self.boot_symbols, **self.main_symbols}
        self.connector = VICEConnector(args.host, args.port, timeout=0.5)
        self.process: subprocess.Popen[bytes] | None = None
        self.vice_log = tempfile.TemporaryFile()
        self.kres = args.kres_prg.read_bytes()
        require(self.kres[:2] == bytes((0x00, 0x04)), "KRES64 has the wrong PRG header")
        require(len(self.kres) == 240, "KRES64 has the wrong size")
        self.vendor = self.vendor_layout(args.kinst_prg)

    @staticmethod
    def vendor_layout(path: Path) -> dict[str, int | bytes]:
        image = path.read_bytes()
        require(image[:2] == bytes((0x00, 0x20)), "KINST64 has the wrong PRG header")
        payload = image[2:]
        base = 0x2000
        error_offset = payload.find(ERROR_MUTE_MESSAGE)
        warning_offset = payload.find(WARNING_1541U_MESSAGE)
        require(error_offset >= 0 and warning_offset >= 0, "KINST64 vendor messages are incomplete")

        message_offset = find_unique(
            payload,
            [0xAD, 0x20, 0xD0, 0x48, 0xAD, 0x21, 0xD0, 0x48, 0xA9, 0x02, 0x8D, 0x20, 0xD0, 0x8D, 0x21, 0xD0],
            "vendor message routine",
        )
        message_address = base + message_offset
        warning_index = warning_offset - error_offset
        require(0 <= warning_index <= 0xFF, "vendor warning is outside the message index table")
        caller_offset = find_unique(
            payload,
            [0xAD, None, None, 0xC9, DRIVE_1541U, 0xD0, None, 0xA2, warning_index,
             0x20, message_address & 0xFF, message_address >> 8, 0x28, 0xA9, 0x00,
             0xA2, None, 0xA0, 0xE0, 0x18, 0x60],
            "1541U warning caller",
        )
        drive_type = int.from_bytes(payload[caller_offset + 1:caller_offset + 3], "little")
        require(drive_type == base + caller_offset + 16,
                "vendor warning and success return do not share drive-type storage")

        second_device_loop = find_unique(
            payload,
            [0xA5, 0xBA, 0x48, 0xA2, 0x08, 0x86, 0xBA, 0x68, 0x48, 0xC5, 0xBA,
             0xF0, None, 0xA9, 0x00, 0x85, 0x90],
            "vendor second-device loop",
        )
        mutefail_offset = find_unique(
            payload,
            [0xA5, 0xBA, 0xA2, 0x2F, 0x38, 0xE8, 0xA8, 0xE9, 0x0A, 0xB0, 0xFA,
             0x8E, None, None, 0x98, 0x69, 0x30, 0x8D, None, None, 0xA2, 0x00,
             0x20, message_address & 0xFF, message_address >> 8, 0x68, 0x85, 0xBA,
             0xA9, STATUS_TOO_MANY_DEVICES, 0x4C, None, None],
            "vendor mutefail path",
        )
        mute_device = int.from_bytes(payload[mutefail_offset + 12:mutefail_offset + 14], "little")
        require(mute_device + 1 == int.from_bytes(payload[mutefail_offset + 18:mutefail_offset + 20], "little"),
                "vendor mutefail digits are not adjacent")
        require(mute_device == base + error_offset + ERROR_MUTE_MESSAGE.index(b"00."),
                "vendor mutefail digits are not inside the complete error message")
        return {
            "message": message_address,
            "warning_check": base + caller_offset,
            "message_return": base + caller_offset + 12,
            "drive_type": drive_type,
            "error_message": base + error_offset,
            "warning_message": base + warning_offset,
            "warning_index": warning_index,
            "second_device_probe": base + second_device_loop + 13,
            "mutefail": base + mutefail_offset,
            "mutefail_message_return": base + mutefail_offset + 25,
        }

    def symbol(self, name: str) -> int:
        value = self.symbols.get(name)
        if value is None:
            raise RuntimeError(f"missing symbol {name}")
        return int(value, 16)

    def command(self) -> list[str]:
        command = [
            self.args.vice,
            "-config", "/dev/null", "-default", "+saveres", "-console",
            "-warp", "+sound", "-sounddev", "dummy", "-remotemonitor",
            "-binarymonitor", "-binarymonitoraddress", f"{self.args.host}:{self.args.port}",
        ]
        if self.args.device == 9:
            command.extend([
                "+busdevice8", "-drive8type", "0",
                "-drive9truedrive", "-drive9type", "1541", "-attach9rw", "-9", str(self.args.boot_d64),
                "-autostartprgmode", "1", "-autostart", str(self.args.boot_prg),
            ])
        else:
            command.extend([
                "-drive8truedrive", "-drive8type", "1541", "-attach8rw", "-8", str(self.args.boot_d64),
                "+busdevice9", "-drive9type", "0", "-autostart", str(self.args.boot_d64),
            ])
        return command

    def start(self) -> None:
        self.process = subprocess.Popen(self.command(), stdout=self.vice_log, stderr=subprocess.STDOUT)
        if self.args.device == 9:
            time.sleep(2.0)
        self.connector.connect(retries=120, retry_delay=0.1)

    def diagnostics(self) -> str:
        status = self.process.poll() if self.process is not None else None
        self.vice_log.seek(0)
        output = self.vice_log.read().decode("utf-8", errors="replace").strip()
        return f"VICE exit status: {status}\n{output}" if output else f"VICE exit status: {status}"

    def stop(self) -> None:
        if self.process is not None and self.process.poll() is None:
            try:
                self.connector.send_command("quit", expect_prompt=False)
                self.process.wait(timeout=2)
            except Exception:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=2)
        self.connector.close()
        self.vice_log.close()

    def arm_boot(self, first_symbol: str) -> None:
        self.connector.clear_breakpoints()
        self.connector.break_at(self.symbol(first_symbol))
        if self.args.device != 8:
            self.connector.poke(0xBA, self.args.device)
        self.connector.poke(self.symbol(".c64_test_boot_gate"), 1)
        self.connector.go()
        self.wait(first_symbol)

    def inject_nmi_and_continue_to(self, symbol: str) -> None:
        self.connector.clear_breakpoints()
        self.connector.break_at(self.symbol(symbol))
        self.connector.send_command("nmi")
        self.connector.go()
        self.wait(symbol)

    def continue_to(self, symbol: str) -> None:
        self.continue_to_address(self.symbol(symbol), symbol)

    def continue_to_address(self, address: int, description: str) -> None:
        self.connector.clear_breakpoints()
        self.connector.break_at(address)
        self.connector.go()
        result = self.connector.wait_for_stop(pass_addr=address, timeout=self.args.timeout)
        if not result.passed:
            raise RuntimeError(f"did not reach {description}: {result.reason}\n{result.last_status}")

    def wait(self, symbol: str) -> None:
        address = self.symbol(symbol)
        result = self.connector.wait_for_stop(pass_addr=address, timeout=self.args.timeout)
        if not result.passed:
            try:
                live_status = self.connector.send_command("r", deadline=time.monotonic() + 2.0)
            except Exception as exc:
                live_status = f"could not capture live registers: {exc}"
            raise RuntimeError(
                f"did not reach {symbol}: {result.reason}\n{result.last_status}\n{live_status}")

    def set_failure(self, status: int) -> None:
        self.connector.set_register("a", status)
        self.connector.set_register("fl", 0xA1)  # N, unused, and C set; V/D/I/Z clear.

    def assert_failure_result(self, status: int, *, interrupt_masked: bool = False) -> None:
        registers, flags = register_values(self.connector)
        require(registers.get("A") == status, f"A was not preserved: {registers}")
        expected_mask = 0xCB if interrupt_masked else 0xCF
        require(flags & expected_mask == 0x81, f"LOAD P was not preserved: ${flags:02x}")
        if interrupt_masked:
            require(flags & 0x04, f"P6 cleanup did not mask interrupts: ${flags:02x}")

    def current_result(self) -> tuple[int, int]:
        registers, flags = register_values(self.connector)
        if "A" not in registers:
            raise RuntimeError(f"could not read LOAD result registers: {registers}")
        return registers["A"], flags & 0xCF

    def assert_same_result(self, expected: tuple[int, int]) -> None:
        actual = self.current_result()
        require(actual == expected, f"LOAD A/P changed across cleanup: expected {expected}, got {actual}")

    def assert_kernal_cleanup(self) -> None:
        require(read_byte(self.connector, 0x98) == 0, "logical file 2 remains in KERNAL file table")
        require(read_byte(self.connector, 0x99) == 0, "default input channel was not restored")
        require(read_byte(self.connector, 0x9A) == 3, "default output channel was not restored")

    def snapshot_canaries(self) -> tuple[bytes, bytes]:
        return read_bytes(self.connector, 0x0340, 77), read_bytes(self.connector, 0x0500, 0x300)

    def assert_canaries(self, expected: tuple[bytes, bytes]) -> None:
        require(read_bytes(self.connector, 0x0340, 77) == expected[0], "terminal trampoline or state changed across LOAD")
        require(read_bytes(self.connector, 0x0500, 0x300) == expected[1], "copied chain changed across LOAD")

    def inject_kernal_failure(self, pre: str, call_return: str, status: int) -> None:
        canaries = self.snapshot_canaries()
        p6 = "p6" in pre
        self.continue_to(".c64_test_p6_kernal_load_return" if p6 else ".c64_test_chain_kernal_load_return")
        self.set_failure(status)
        self.continue_to(call_return)
        self.assert_failure_result(status, interrupt_masked=p6)
        self.assert_kernal_cleanup()
        self.assert_canaries(canaries)

    def inject_boot_failure(self, call_return: str, status: int) -> None:
        self.set_failure(status)
        self.continue_to(call_return)
        self.assert_failure_result(status)
        self.assert_kernal_cleanup()

    def observe_boot_cleanup(self, call_return: str) -> None:
        result = self.current_result()
        self.continue_to(call_return)
        self.assert_same_result(result)
        self.assert_kernal_cleanup()

    def observe_chain_cleanup(self, pre: str, call_return: str, *, p6: bool = False) -> None:
        canaries = self.snapshot_canaries()
        self.continue_to(".c64_test_p6_kernal_load_return" if p6 else ".c64_test_chain_kernal_load_return")
        result = self.current_result()
        self.continue_to(call_return)
        if p6:
            actual = self.current_result()
            require(actual[0] == result[0] and actual[1] & 0xCB == result[1] & 0xCB,
                    f"P6 LOAD A/P changed across cleanup: expected {result}, got {actual}")
            require(actual[1] & 0x04, f"P6 cleanup did not mask interrupts: ${actual[1]:02x}")
        else:
            self.assert_same_result(result)
        self.assert_kernal_cleanup()
        self.assert_canaries(canaries)

    def inject_krill_failure(self, return_symbol: str, status: int) -> None:
        self.set_failure(status)
        self.continue_to(return_symbol)

    def assert_terminal(self, status: int) -> None:
        self.continue_to(".c64_test_terminal_before_warm_start")
        require(read_byte(self.connector, self.symbol(".c64_test_error_load_a")) == status, "terminal A evidence mismatch")
        require(read_byte(self.connector, self.symbol(".c64_test_error_load_p")) == 0xB1, "terminal full-P evidence mismatch")
        require(read_byte(self.connector, 0x0500) == 0x20, "terminal clear did not erase the dead chain")
        require(read_d011_mode(self.connector) == 0x1B, "terminal transition did not enable clean text")

    def assert_title(self, *, evidence: int, device: int = 8) -> None:
        self.continue_to(".c64_test_fastload_pass_sym")
        require(read_byte(self.connector, 0x033A) == evidence, f"boot-art evidence is not ${evidence:02x}")
        require(read_byte(self.connector, 0x033B) == device, f"boot device is not {device}")
        require(read_byte(self.connector, self.symbol(".program_device")) == device, f"program device is not {device}")

    def assert_vendor_message_entry(self, message: bytes, address_key: str, expected_x: int) -> None:
        registers, _ = register_values(self.connector)
        require(registers.get("X") == expected_x, f"vendor message index mismatch: {registers}")
        address = int(self.vendor[address_key])
        require(read_bytes(self.connector, address, len(message)) == message,
                "loaded KINST64 does not contain the complete vendor message")

    def assert_vendor_message_visible(self, message: bytes) -> None:
        expected = screen_codes(message)
        screen = read_bytes(self.connector, 0x0400, 1000)
        require(expected in screen, "complete vendor message was not visible in screen RAM")

    def run(self) -> None:
        scenario = self.args.scenario
        if scenario == "kinst_failure":
            self.arm_boot(".c64_test_boot_kernal_load_return")
            self.inject_boot_failure(".c64_test_kinst_call_return", 0xE1)
            self.continue_to(".c64_test_kinst_failure_continuation")
            require(read_byte(self.connector, 0x0334) == 0 and read_byte(self.connector, 0x0339) == 0,
                    "KINST64 failure left Krill evidence set")
            return
        if scenario == "bootart_failure":
            self.arm_boot(".c64_test_boot_kernal_load_return")
            self.continue_to(".c64_test_boot_kernal_load_return")
            self.inject_boot_failure(".c64_test_bootart_call_return", 0xE2)
            self.continue_to(".c64_test_bootart_failure_continuation")
            require(read_byte(self.connector, 0x033A) == 0, "BOOTART64 failure left art evidence set")
            return
        if scenario == "missing_bootart_krill":
            self.arm_boot(".c64_test_fastload_pass_sym")
            evidence = read_byte(self.connector, 0x033A)
            require(evidence == 0, f"missing Krill BOOTART64 produced CRC/art evidence ${evidence:02x}")
            require(read_byte(self.connector, 0x0334) == 0x4B and read_byte(self.connector, 0x0335) == 0xD2,
                    "missing Krill BOOTART64 disabled the installed loader")
            require(read_byte(self.connector, self.symbol(".krill_active")) == 0xFF,
                    "missing Krill BOOTART64 did not retain the Krill runtime")
            require(read_byte(self.connector, self.symbol(".krill_boot_used")) == 1,
                    "missing Krill BOOTART64 did not complete Krill payload loading")
            return
        if scenario == "installer_1541u_warning":
            self.arm_boot(".c64_test_installer_pre")
            warning_check = int(self.vendor["warning_check"])
            self.continue_to_address(warning_check, "vendor 1541U warning check")
            self.connector.poke(int(self.vendor["drive_type"]), DRIVE_1541U)
            message = WARNING_1541U_MESSAGE
            self.continue_to_address(int(self.vendor["message"]), "vendor message entry")
            self.assert_vendor_message_entry(message, "warning_message", int(self.vendor["warning_index"]))
            self.continue_to_address(int(self.vendor["message_return"]), "vendor message return")
            self.assert_vendor_message_visible(message)
            self.continue_to(".c64_test_installer_result_restored")
            registers, flags = register_values(self.connector)
            d011 = read_d011_mode(self.connector)
            require(d011 == 0x0B, f"boot did not reblank after vendor message: $D011=${d011:02x}")
            require(registers.get("A") == 0 and not flags & 1,
                    f"1541U warning did not retain installer success: {registers}, P=${flags:02x}")
            self.continue_to(".c64_test_installer_resident_copied")
            require(read_bytes(self.connector, 0x0400, 238) == self.kres[2:],
                    "post-warning resident does not match clean embedded KRES64")
            self.assert_title(evidence=0x81)
            return
        if scenario == "installer_mute_failure":
            self.arm_boot(".c64_test_installer_pre")
            self.continue_to_address(int(self.vendor["second_device_probe"]), "vendor second-device probe")
            registers, _ = register_values(self.connector)
            require(registers.get("X") == 9 and read_byte(self.connector, 0xBA) == 9,
                    f"vendor second-device state is not device 9: {registers}")
            require("SP" in registers and read_byte(self.connector, 0x0100 | ((registers["SP"] + 1) & 0xFF)) == 8,
                    "vendor active-device stack byte is not device 8")
            self.connector.set_register("pc", int(self.vendor["mutefail"]))
            message = ERROR_MUTE_MESSAGE.replace(b"#00.", b"#09.")
            self.continue_to_address(int(self.vendor["message"]), "vendor mutefail message entry")
            self.assert_vendor_message_entry(message, "error_message", 0)
            self.continue_to_address(int(self.vendor["mutefail_message_return"]), "vendor mutefail message return")
            self.assert_vendor_message_visible(message)
            self.continue_to(".c64_test_installer_result_restored")
            registers, flags = register_values(self.connector)
            require(registers.get("A") == STATUS_TOO_MANY_DEVICES and flags & 1,
                    f"failed-mute status was not returned by installer: {registers}, P=${flags:02x}")
            require(read_byte(self.connector, 0xBA) == 8, "vendor mutefail path did not restore active FA")
            require(read_d011_mode(self.connector) == 0x0B, "boot did not reblank after failed-mute message")
            self.continue_to(".c64_test_installer_failure_continuation")
            require(read_byte(self.connector, 0x0334) == 0 and read_byte(self.connector, 0x0335) == 0,
                    "failed-mute installer path left resident magic set")
            require(read_bytes(self.connector, 0x0400, 238) != self.kres[2:],
                    "failed-mute installer path copied or exposed the clean resident")
            self.assert_title(evidence=0x80)
            return
        if scenario == "krill_install_success_cleanup":
            self.arm_boot(".c64_test_boot_kernal_load_return")
            self.observe_boot_cleanup(".c64_test_kinst_call_return")
            self.assert_title(evidence=0x81)
            return
        if scenario == "kernal_success_cleanup":
            self.arm_boot(".c64_test_boot_kernal_load_return")
            self.observe_boot_cleanup(".c64_test_kinst_call_return")
            self.continue_to(".c64_test_boot_kernal_load_return")
            self.observe_boot_cleanup(".c64_test_bootart_call_return")
            self.continue_to(".c64_test_kernal_moria_pre")
            self.observe_chain_cleanup(".c64_test_kernal_moria_pre", ".c64_test_kernal_moria_return")
            self.continue_to(".c64_test_kernal_init_pre")
            self.observe_chain_cleanup(".c64_test_kernal_init_pre", ".c64_test_kernal_init_return")
            self.continue_to(".c64_test_p6_bank_pre")
            self.observe_chain_cleanup(".c64_test_p6_bank_pre", ".c64_test_p6_cleanup_return", p6=True)
            self.assert_title(evidence=0x80)
            return
        if scenario == "device9_krill":
            self.arm_boot(".c64_test_boot_kernal_load_return")
            self.continue_to(".c64_test_installer_pre")
            self.continue_to(".c64_test_installer_return")
            self.continue_to(".c64_test_krill_moria_return")
            self.assert_title(evidence=0x81, device=9)
            return
        if scenario == "device9_fallback":
            self.arm_boot(".c64_test_boot_kernal_load_return")
            self.continue_to(".c64_test_bootart_call_return")
            self.continue_to(".c64_test_kernal_moria_return")
            self.continue_to(".c64_test_kernal_init_pre")
            require(read_byte(self.connector, 0x033B) == 9, "chain lost the captured device before 64.INIT")
            self.assert_kernal_cleanup()
            self.continue_to(".c64_test_kernal_init_return")
            self.continue_to(".c64_test_p6_complete")
            self.assert_title(evidence=0x80, device=9)
            return
        if scenario == "rom_vector_nmi":
            self.arm_boot(".c64_test_chain_rom_vectors_ready")
            require(read_byte(self.connector, 0x01) == 0x37, "chain did not expose ROM vectors")
            self.inject_nmi_and_continue_to(".c64_test_runtime_vectors_ready")
            self.assert_title(evidence=0x80)
            return
        if scenario == "terminal_rom_vector_nmi":
            self.arm_boot(".c64_test_kernal_moria_pre")
            self.inject_kernal_failure(
                ".c64_test_kernal_moria_pre", ".c64_test_kernal_moria_return", 0xE8)
            self.continue_to(".c64_test_terminal_rom_vectors_ready")
            require(read_byte(self.connector, 0x01) == 0x37, "terminal path did not expose ROM vectors")
            self.inject_nmi_and_continue_to(".c64_test_terminal_before_warm_start")
            require(read_byte(self.connector, self.symbol(".c64_test_error_load_a")) == 0xE8,
                    "terminal NMI changed saved LOAD status")
            return

        kernal_terminal = {
            "kernal_moria_failure": (".c64_test_kernal_moria_pre", ".c64_test_kernal_moria_return", 0xE3),
            "kernal_init_failure": (".c64_test_kernal_init_pre", ".c64_test_kernal_init_return", 0xE4),
        }
        if scenario in kernal_terminal:
            pre, returned, status = kernal_terminal[scenario]
            self.arm_boot(pre)
            self.inject_kernal_failure(pre, returned, status)
            self.assert_terminal(status)
            return

        krill_returns = {
            "krill_moria_failure": ".c64_test_krill_moria_return",
            "krill_bank_failure": ".c64_test_krill_bank_return",
            "krill_init_failure": ".c64_test_krill_init_return",
        }
        if scenario in krill_returns:
            returned = krill_returns[scenario]
            self.arm_boot(returned)
            self.set_failure(0xF1)
            self.continue_to(".c64_test_recovery_blanked")
            require(read_d011_mode(self.connector) == 0x0B, "Krill recovery did not blank before uninstall")
            self.assert_title(evidence=0)
            return

        if scenario in ("recovery_moria_failure", "recovery_init_failure"):
            self.arm_boot(".c64_test_krill_moria_return")
            self.set_failure(0xF2)
            pre = ".c64_test_recovery_moria_pre" if scenario == "recovery_moria_failure" else ".c64_test_recovery_init_pre"
            returned = ".c64_test_recovery_moria_return" if scenario == "recovery_moria_failure" else ".c64_test_recovery_init_return"
            status = 0xE5 if scenario == "recovery_moria_failure" else 0xE6
            self.continue_to(pre)
            require(read_d011_mode(self.connector) == 0x0B, "KERNAL recovery path is not blank")
            self.inject_kernal_failure(pre, returned, status)
            self.assert_terminal(status)
            return

        if scenario == "recovery_success_cleanup":
            self.arm_boot(".c64_test_krill_moria_return")
            self.set_failure(0xF2)
            self.continue_to(".c64_test_recovery_moria_pre")
            require(read_d011_mode(self.connector) == 0x0B, "successful recovery did not remain blank")
            self.observe_chain_cleanup(".c64_test_recovery_moria_pre", ".c64_test_recovery_moria_return")
            self.continue_to(".c64_test_recovery_init_pre")
            self.observe_chain_cleanup(".c64_test_recovery_init_pre", ".c64_test_recovery_init_return")
            self.continue_to(".c64_test_p6_bank_pre")
            self.observe_chain_cleanup(".c64_test_p6_bank_pre", ".c64_test_p6_cleanup_return", p6=True)
            self.assert_title(evidence=0)
            return

        if scenario == "p6_bank_failure":
            self.arm_boot(".c64_test_p6_bank_pre")
            require(read_d011_mode(self.connector) == 0x0B, "P6 began with display enabled")
            self.inject_kernal_failure(".c64_test_p6_bank_pre", ".c64_test_p6_cleanup_return", 0xE7)
            self.continue_to(".c64_test_p6_bank_failure")
            require(read_d011_mode(self.connector) == 0x0B, "P6 failure enabled the display")
            return

        raise RuntimeError(f"unknown scenario {scenario}")


def main() -> int:
    parser = argparse.ArgumentParser(description="C64 boot-art handoff production-path smoke")
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--vice", required=True)
    parser.add_argument("--boot-d64", required=True, type=Path)
    parser.add_argument("--boot-prg", required=True, type=Path)
    parser.add_argument("--boot-vs", required=True, type=Path)
    parser.add_argument("--main-vs", required=True, type=Path)
    parser.add_argument("--kinst-prg", required=True, type=Path)
    parser.add_argument("--kres-prg", required=True, type=Path)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6510)
    parser.add_argument("--device", type=int, choices=(8, 9), default=8)
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()

    harness = BootHarness(args)
    try:
        harness.start()
        harness.run()
    except Exception as exc:
        print(f"FAIL: {args.scenario}: {exc}\n{harness.diagnostics()}")
        return 2
    finally:
        harness.stop()
    print(f"PASS: {args.scenario}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
