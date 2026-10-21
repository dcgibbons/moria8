#!/usr/bin/env python3
"""Validate Commander X16 linked symbols and emitted PRG ownership boundaries."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "cx16"
MAIN_SYM = BUILD / "main.sym"
SYMBOL_RE = re.compile(r"^\.label ([A-Za-z0-9_]+)=\$([0-9a-fA-F]+)$")


class ContractViolation(Exception):
    """A linked or emitted artifact violates the Commander X16 memory contract."""


@dataclass(frozen=True)
class PrgSpec:
    filename: str
    start: int
    limit: int
    end_symbol: str | None = None
    min_payload: int = 1
    signature: bytes = b""


PRG_SPECS = (
    PrgSpec("MORIA8.PRG", 0x0801, 0x9B00, "program_end"),
    PrgSpec("CX16.AUXDATA", 0x6000, 0x8000, "ovl_auxdata_end"),
    PrgSpec("CX16.HUFFDATA", 0x8000, 0xA000, "ovl_huffdata_end"),
    PrgSpec("OVL.START", 0xA000, 0xC000, "ovl_start_end"),
    PrgSpec("OVL.TOWN", 0xA000, 0xC000, "ovl_town_end"),
    PrgSpec("OVL.DEATH", 0xA000, 0xC000, "ovl_death_end"),
    PrgSpec("OVL.MODAL", 0xA000, 0xC000, "ovl_modal_misc_end"),
    PrgSpec("OVL.HELP", 0xA000, 0xC000, "ovl_help_end"),
    PrgSpec("OVL.UI", 0xA000, 0xC000, "ovl_ui_end"),
    PrgSpec("OVL.ITEMS", 0xA000, 0xC000, "ovl_items_end"),
    PrgSpec("OVL.SPELL", 0xA000, 0xC000, "ovl_spell_end"),
    PrgSpec("OVL.GEN", 0xA000, 0xC000, "ovl_gen_end"),
    PrgSpec("OVL.STORAGE", 0xA000, 0xC000, "ovl_storage_end"),
    PrgSpec("OVL.TITLE", 0xA000, 0xC000, "ovl_title_end"),
    PrgSpec("OVL.CHEST", 0xA000, 0xC000, "ovl_chest_end"),
    PrgSpec("MONSTER.DB.1", 0xA000, 0xC000, min_payload=512),
    PrgSpec("MONSTER.DB.2", 0xA000, 0xC000, min_payload=512),
    PrgSpec("MONSTER.DB.3", 0xA000, 0xC000, min_payload=512),
    PrgSpec("MONSTER.DB.4", 0xA000, 0xC000, min_payload=512),
    PrgSpec("TITLE", 0xA000, 0xC000, min_payload=256),
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
    start = blob[0] | (blob[1] << 8)
    if start != spec.start:
        raise ContractViolation(
            f"{spec.filename}: load ${start:04X}, expected ${spec.start:04X}"
        )
    payload = blob[2:]
    if len(payload) < spec.min_payload:
        raise ContractViolation(
            f"{spec.filename}: payload {len(payload)} B < {spec.min_payload} B"
        )
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

    zp_save_buf = require_symbol(main_symbols, "zp_save_buf")
    if not 0x0801 <= zp_save_buf < 0x9B00:
        raise ContractViolation(f"zp_save_buf outside resident RAM: ${zp_save_buf:04X}")
    program_end = require_symbol(main_symbols, "program_end")
    if program_end > 0x9B00:
        raise ContractViolation(
            f"program_end ${program_end:04X} overlaps tier name pool $9B00"
        )
    ego_slots = require_symbol(main_symbols, "cx16_ego_suffix_slots")
    if not (0x6000 <= ego_slots < 0x8000 and (ego_slots & 0xFF) == 0):
        raise ContractViolation(
            f"cx16_ego_suffix_slots ${ego_slots:04X} not page-aligned in Bank 3 ($6000-$7FFF)"
        )
    foreign = [
        name
        for name in main_symbols
        if name.startswith(("a2_", "c128_", "c64_", "plus4_"))
        or name.endswith(("_a2", "_c128", "_c64", "_plus4"))
        or "plus4" in name
    ]
    if foreign:
        raise ContractViolation(f"foreign platform symbols in CX16 build: {foreign}")
    print("ASSERT main-symbol-owners PASS")
    checks += 1

    print(f"RESULT {checks} asserts 0 failures")
    return 0


def selftest() -> int:
    valid = PrgSpec("fixture.prg", 0xA000, 0xC000, signature=b"M8")
    prg_extent(bytes((0x00, 0xA0)) + b"M8payload", valid)

    bad_fixtures = (
        (b"\x00", valid),
        (bytes((0x01, 0xA0)) + b"M8", valid),
        (bytes((0x00, 0xA0)) + b"X" * 0x2001, valid),
        (bytes((0x00, 0xA0)) + b"NO", valid),
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
