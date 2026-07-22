#!/usr/bin/env python3
"""Validate Apple II linked symbols and emitted PRG ownership boundaries."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "apple2"
MAIN_SYM = Path(__file__).with_name("main.sym")
BOOT_SYM = Path(__file__).with_name("boot.sym")
SYMBOL_RE = re.compile(r"^\.label ([A-Za-z0-9_]+)=\$([0-9a-fA-F]+)$")


class ContractViolation(Exception):
    """A linked or emitted artifact violates the Apple II memory contract."""


@dataclass(frozen=True)
class PrgSpec:
    filename: str
    start: int
    limit: int
    end_symbol: str | None = None
    signature: bytes = b""


PRG_SPECS = (
    PrgSpec("moria8a2.prg", 0x0A00, 0x7C00, "program_end"),
    PrgSpec("a2.play", 0x7C00, 0xA000, "a2_play_end", b"M8P"),
    PrgSpec("a2.auxdata", 0x3B0C, 0x5700),
    PrgSpec("ovl.start", 0xA400, 0xBA00, "ovl_start_end"),
    PrgSpec("ovl.town", 0xA400, 0xBA00, "ovl_town_end"),
    PrgSpec("ovl.death", 0xA400, 0xBA00, "ovl_death_end"),
    PrgSpec("ovl.modal", 0xA400, 0xBA00, "ovl_modal_misc_end"),
    PrgSpec("ovl.help", 0xA400, 0xBA00, "ovl_help_end"),
    PrgSpec("ovl.ui", 0xA400, 0xBA00, "ovl_ui_end"),
    PrgSpec("ovl.items", 0xA400, 0xBA00, "ovl_items_end"),
    PrgSpec("ovl.spell", 0xA400, 0xBA00, "ovl_spell_end"),
    PrgSpec("ovl.gen", 0xA400, 0xBA00, "ovl_gen_end"),
    PrgSpec("ovl.storage", 0xA400, 0xBA00, "ovl_storage_end"),
    PrgSpec("ovl.title", 0xA400, 0xBA00, "ovl_title_end"),
    PrgSpec("monster.db.1", 0xA400, 0xBB00),
    PrgSpec("monster.db.2", 0xA400, 0xBB00),
    PrgSpec("monster.db.3", 0xA400, 0xBB00),
    PrgSpec("monster.db.4", 0xA400, 0xBB00),
    PrgSpec("title.prg", 0x4000, 0x7C00),
)


def read_symbols(path: Path) -> dict[str, int]:
    if not path.is_file():
        raise ContractViolation(f"missing symbol file: {path}")
    symbols: dict[str, int] = {}
    for line in path.read_text().splitlines():
        match = SYMBOL_RE.match(line)
        if match:
            symbols[match.group(1)] = int(match.group(2), 16)
    return symbols


def require_symbol(symbols: dict[str, int], name: str) -> int:
    try:
        return symbols[name]
    except KeyError as exc:
        raise ContractViolation(f"missing symbol: {name}") from exc


def prg_extent(blob: bytes, spec: PrgSpec) -> tuple[int, int]:
    if len(blob) < 3:
        raise ContractViolation(f"{spec.filename}: truncated PRG")
    start = blob[0] | blob[1] << 8
    if start != spec.start:
        raise ContractViolation(
            f"{spec.filename}: load ${start:04X}, expected ${spec.start:04X}"
        )
    payload = blob[2:]
    end = start + len(payload)
    if end > spec.limit:
        raise ContractViolation(
            f"{spec.filename}: end ${end:04X} exceeds ${spec.limit:04X}"
        )
    if spec.signature and not payload.startswith(spec.signature):
        raise ContractViolation(f"{spec.filename}: signature mismatch")
    return start, end


def check_artifacts() -> int:
    main_symbols = read_symbols(MAIN_SYM)
    boot_symbols = read_symbols(BOOT_SYM)
    checks = 0

    for spec in PRG_SPECS:
        path = BUILD / spec.filename
        if not path.is_file():
            raise ContractViolation(f"missing build artifact: {path}")
        _, end = prg_extent(path.read_bytes(), spec)
        if spec.end_symbol:
            linked_end = require_symbol(main_symbols, spec.end_symbol)
            if end != linked_end:
                raise ContractViolation(
                    f"{spec.filename}: emitted end ${end:04X} != "
                    f"{spec.end_symbol} ${linked_end:04X}"
                )
        print(f"ASSERT {spec.filename} PASS ${spec.start:04X}-${end - 1:04X}")
        checks += 1

    if require_symbol(main_symbols, "a2_play_start") != 0x7C00:
        raise ContractViolation("a2_play_start is not $7C00")
    zp_save_buf = require_symbol(main_symbols, "zp_save_buf")
    if not 0x0A00 <= zp_save_buf < 0x7C00:
        raise ContractViolation(f"zp_save_buf outside resident RAM: ${zp_save_buf:04X}")
    print("ASSERT main-symbol-owners PASS")
    checks += 1

    boot_path = BUILD / "moria8.system.prg"
    _, boot_end = prg_extent(
        boot_path.read_bytes(), PrgSpec(boot_path.name, 0x2000, 0xBF00)
    )
    linked_boot_end = require_symbol(boot_symbols, "loader_end")
    if boot_end != linked_boot_end:
        raise ContractViolation(
            f"{boot_path.name}: emitted end ${boot_end:04X} != "
            f"loader_end ${linked_boot_end:04X}"
        )
    loader_src = require_symbol(boot_symbols, "loader_src")
    if linked_boot_end - loader_src > 512:
        raise ContractViolation("relocated loader exceeds $0800-$09FF")
    if linked_boot_end - (loader_src + 0x100) > 255:
        raise ContractViolation("relocated loader tail exceeds 8-bit copy count")
    print(f"ASSERT {boot_path.name} PASS $2000-${boot_end - 1:04X}")
    checks += 1

    print(f"RESULT {checks} asserts 0 failures")
    return 0


def selftest() -> int:
    valid = PrgSpec("fixture.prg", 0x2000, 0x2100, signature=b"M8")
    prg_extent(bytes((0x00, 0x20)) + b"M8payload", valid)

    bad_fixtures = (
        (b"\x00", valid),
        (bytes((0x01, 0x20)) + b"M8", valid),
        (bytes((0x00, 0x20)) + b"X" * 0x101, valid),
        (bytes((0x00, 0x20)) + b"NO", valid),
    )
    for blob, spec in bad_fixtures:
        try:
            prg_extent(blob, spec)
        except ContractViolation:
            continue
        raise AssertionError("negative fixture unexpectedly passed")

    print("RESULT 5 asserts 0 failures")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    try:
        return selftest() if args.selftest else check_artifacts()
    except (ContractViolation, OSError) as exc:
        print(f"ASSERT memory-contract FAIL {exc}")
        print("RESULT 1 asserts 1 failures")
        return 1


if __name__ == "__main__":
    sys.exit(main())
