#!/usr/bin/env python3
"""Static memory-contract checker for the Atari 8-bit port (platforms/atari8/)."""

from __future__ import annotations

import argparse
import re
import struct
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BUILD_DIR = ROOT / "build" / "atari8"

OS_PAGE2_DCB_BASE = 0x0200
OS_PAGE2_DCB_END = 0x031A
LOW_RESIDENT_START = 0x0C00
LOW_HELPERS_LIMIT = 0x4000
MAP_BASE = 0xC100
MAP_END = 0xCFFF
IO_HOLE_BASE = 0xD000
IO_HOLE_END = 0xD7FF
HIGH_RESIDENT_BASE = 0xD800
OVERLAY_BASE = 0xE000
OVERLAY_LIMIT = 0xF000
BANKED_BASE = 0xF000
BANKED_LIMIT = 0xFFFA

ALLOWED_MAP_SYMBOLS = {
    "MAP_BASE",
    "MAP_END",
    "CREATURE_BASE",
    "hiscore_table",
}

ALLOWED_IO_SYMBOLS = {
    "hal_entropy_timer0_lo",
    "hal_entropy_timer0_hi",
    "hal_entropy_timer1_lo",
    "hal_entropy_timer1_hi",
}

REQUIRED_HIGH_RESIDENT_SYMBOLS = {
    "fi_item_id": 0xDC00,
    "hd_decode_buf": 0xDD00,
    "zp_save_buf": 0xDD40,
    "msg_history": 0xDDCE,
}

REQUIRED_LOW_SYMBOLS = (
    "entry_main",
    "atari_font_init",
    "atari_nmi_handler",
    "atari_irq_handler",
    "exit_trampoline",
    "EnterSio",
    "ExitSio",
    "save_zp",
    "restore_zp",
    "sio_sector_buf",
    "xe_detect",
    "xe_cache_stash",
    "xe_cache_fetch",
    "xe_slot_populated",
    "hal_asset_load_prg_header",
    "hal_asset_load_title",
    "hal_storage_probe_media",
    "atari_write_sio_sector",
    "hal_storage_open",
    "hal_storage_chrin",
    "hal_storage_chrout",
    "hal_storage_close",
    "low_helpers_end",
)

OVERLAY_FILES = (
    "OVL.STA",
    "OVL.TWN",
    "OVL.DTH",
    "OVL.MDL",
    "OVL.HLP",
    "OVL.UI",
    "OVL.ITM",
    "OVL.SPL",
    "OVL.CHS",
    "OVL.GEN",
)

TIER_FILES = (
    "MONSTER.DB1",
    "MONSTER.DB2",
    "MONSTER.DB3",
    "MONSTER.DB4",
)

LABEL_RE = re.compile(r"^\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\$([0-9A-Fa-f]+)\b")


def parse_sym_file(sym_path: Path) -> dict[str, int]:
    symbols: dict[str, int] = {}
    for line in sym_path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = LABEL_RE.match(line.strip())
        if match:
            symbols[match.group(1)] = int(match.group(2), 16)
    return symbols


def prg_span(prg_path: Path) -> tuple[int, int]:
    data = prg_path.read_bytes()
    if len(data) < 3:
        raise ValueError(f"{prg_path.name}: PRG too short ({len(data)} bytes)")
    start = struct.unpack_from("<H", data, 0)[0]
    end_excl = start + (len(data) - 2)
    return start, end_excl


def validate_build(build_dir: Path) -> list[str]:
    errors: list[str] = []
    sym_path = build_dir / "main.sym"
    if not sym_path.exists():
        return [f"missing symbol file {sym_path}"]

    symbols = parse_sym_file(sym_path)

    for sym in REQUIRED_LOW_SYMBOLS:
        if sym not in symbols:
            errors.append(f"missing required low-resident symbol {sym}")
            continue
        addr = symbols[sym]
        limit = LOW_HELPERS_LIMIT if sym == "low_helpers_end" else LOW_HELPERS_LIMIT - 1
        if not (LOW_RESIDENT_START <= addr <= limit):
            errors.append(f"{sym} at ${addr:04X} violates < $4000 low-RAM contract")

    if "program_end" not in symbols:
        errors.append("missing symbol program_end")
    else:
        prog_end = symbols["program_end"]
        if not (LOW_RESIDENT_START <= prog_end <= MAP_BASE):
            errors.append(f"program_end at ${prog_end:04X} exceeds MAP_BASE (${MAP_BASE:04X})")

    if "banked_code_end" not in symbols:
        errors.append("missing symbol banked_code_end")
    else:
        bank_end = symbols["banked_code_end"]
        if not (BANKED_BASE <= bank_end <= BANKED_LIMIT):
            errors.append(f"banked_code_end at ${bank_end:04X} exceeds CPU vectors (${BANKED_LIMIT:04X})")

    # Check HighResident symbols ($D800-$DFFF)
    for sym, expected_addr in REQUIRED_HIGH_RESIDENT_SYMBOLS.items():
        if sym not in symbols:
            errors.append(f"missing required high-resident symbol {sym}")
        elif symbols[sym] != expected_addr:
            errors.append(f"{sym} at ${symbols[sym]:04X} != expected ${expected_addr:04X}")

    if "high_resident_end" not in symbols:
        errors.append("missing symbol high_resident_end")
    else:
        high_end = symbols["high_resident_end"]
        if not (HIGH_RESIDENT_BASE <= high_end <= OVERLAY_BASE):
            errors.append(f"high_resident_end at ${high_end:04X} exceeds ${OVERLAY_BASE:04X}")

    # Check symbol overlap with protected windows ($0200-$031A, $C100-$CFFF, $D000-$D7FF)
    for sym, addr in symbols.items():
        if OS_PAGE2_DCB_BASE <= addr <= OS_PAGE2_DCB_END:
            errors.append(
                f"symbol {sym} at ${addr:04X} overlaps protected OS Page 2 / DCB (${OS_PAGE2_DCB_BASE:04X}-${OS_PAGE2_DCB_END:04X})"
            )
        elif MAP_BASE <= addr <= MAP_END and sym not in ALLOWED_MAP_SYMBOLS:
            errors.append(
                f"symbol {sym} at ${addr:04X} overlaps MAP_BASE (${MAP_BASE:04X}-${MAP_END:04X})"
            )
        elif IO_HOLE_BASE <= addr <= IO_HOLE_END and sym not in ALLOWED_IO_SYMBOLS:
            errors.append(
                f"symbol {sym} at ${addr:04X} overlaps Hardware I/O hole (${IO_HOLE_BASE:04X}-${IO_HOLE_END:04X})"
            )

    # Check MORIA8.RES PRG span
    res_prg = build_dir / "MORIA8.RES"
    if not res_prg.exists():
        errors.append("missing MORIA8.RES")
    else:
        start, end_excl = prg_span(res_prg)
        if start != LOW_RESIDENT_START:
            errors.append(f"MORIA8.RES load address ${start:04X} != ${LOW_RESIDENT_START:04X}")
        if end_excl > MAP_BASE:
            errors.append(f"MORIA8.RES end ${end_excl:04X} overlaps MAP_BASE (${MAP_BASE:04X})")

    # Check ATARI.BNK PRG span
    bnk_prg = build_dir / "ATARI.BNK"
    if not bnk_prg.exists():
        errors.append("missing ATARI.BNK")
    else:
        start, end_excl = prg_span(bnk_prg)
        if start != BANKED_BASE:
            errors.append(f"ATARI.BNK load address ${start:04X} != ${BANKED_BASE:04X}")
        if end_excl > BANKED_LIMIT:
            errors.append(f"ATARI.BNK end ${end_excl:04X} overlaps CPU vectors (${BANKED_LIMIT:04X})")

    # Check overlays and monster tiers ($E000-$EFFF)
    for name in OVERLAY_FILES + TIER_FILES:
        p = build_dir / name
        if not p.exists():
            errors.append(f"missing {name}")
            continue
        start, end_excl = prg_span(p)
        if start != OVERLAY_BASE:
            errors.append(f"{name} load address ${start:04X} != ${OVERLAY_BASE:04X}")
        if end_excl > OVERLAY_LIMIT:
            errors.append(f"{name} end ${end_excl:04X} exceeds ${OVERLAY_LIMIT:04X}")

    # Check TITLE.DAT ($C100, <= 3 pages = 768 B)
    title_prg = build_dir / "TITLE.DAT"
    if not title_prg.exists():
        errors.append("missing TITLE.DAT")
    else:
        start, end_excl = prg_span(title_prg)
        if start != MAP_BASE:
            errors.append(f"TITLE.DAT load address ${start:04X} != ${MAP_BASE:04X}")
        if end_excl - start > 0x0300:
            errors.append(f"TITLE.DAT payload {end_excl - start} B exceeds 3-page (768 B) 130XE Slot 14 span")

    # Check boot.prg ($0800, 384 B)
    boot_prg = build_dir / "boot.prg"
    if not boot_prg.exists():
        errors.append("missing boot.prg")
    else:
        start, end_excl = prg_span(boot_prg)
        if start != 0x0800 or (end_excl - start) != 384:
            errors.append(f"boot.prg span ${start:04X}-${end_excl:04X} must be $0800-$0980 (384 B)")

    return errors


def write_synthetic_prg(path: Path, start: int, length: int) -> None:
    path.write_bytes(struct.pack("<H", start) + (b"\xea" * length))


def run_selftest() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        bdir = Path(tmp)
        sym_lines = [f".label {name}=${0x0C00 + i * 0x10:04x}" for i, name in enumerate(REQUIRED_LOW_SYMBOLS)]
        sym_lines.append(".label program_end=$bd00")
        sym_lines.append(".label banked_code_end=$fe80")
        for sym, addr in REQUIRED_HIGH_RESIDENT_SYMBOLS.items():
            sym_lines.append(f".label {sym}=${addr:04x}")
        sym_lines.append(".label high_resident_end=$df0e")
        base_sym_text = "\n".join(sym_lines) + "\n"
        (bdir / "main.sym").write_text(base_sym_text, encoding="utf-8")

        write_synthetic_prg(bdir / "MORIA8.RES", 0x0C00, 0xB100)
        write_synthetic_prg(bdir / "ATARI.BNK", 0xF000, 0x0E80)
        write_synthetic_prg(bdir / "TITLE.DAT", 0xC100, 620)
        write_synthetic_prg(bdir / "boot.prg", 0x0800, 384)
        for name in OVERLAY_FILES + TIER_FILES:
            write_synthetic_prg(bdir / name, 0xE000, 0x0800)

        errs = validate_build(bdir)
        if errs:
            print(f"FAIL: valid synthetic build rejected: {errs}", file=sys.stderr)
            return 1

        # Negative test 1: low helper above $4000 must fail
        (bdir / "main.sym").write_text(base_sym_text.replace("EnterSio=$0c50", "EnterSio=$4000"), encoding="utf-8")
        if not validate_build(bdir):
            print("FAIL: failed to catch EnterSio >= $4000", file=sys.stderr)
            return 1

        # Negative test 2: program_end overlapping MAP_BASE ($C100) must fail
        (bdir / "main.sym").write_text(base_sym_text.replace("program_end=$bd00", "program_end=$c101"), encoding="utf-8")
        if not validate_build(bdir):
            print("FAIL: failed to catch program_end > MAP_BASE", file=sys.stderr)
            return 1

        # Negative test 3: symbol in OS Page 2 / DCB ($0200-$031A) must fail
        (bdir / "main.sym").write_text(base_sym_text + ".label bad_os_sym=$0220\n", encoding="utf-8")
        if not validate_build(bdir):
            print("FAIL: failed to catch symbol in $0200-$031A", file=sys.stderr)
            return 1

        # Negative test 4: symbol in Hardware I/O hole ($D000-$D7FF) must fail
        (bdir / "main.sym").write_text(base_sym_text + ".label bad_io_sym=$d200\n", encoding="utf-8")
        if not validate_build(bdir):
            print("FAIL: failed to catch symbol in $D000-$D7FF", file=sys.stderr)
            return 1

        # Negative test 5: symbol in MAP_BASE ($C100-$CFFF) must fail
        (bdir / "main.sym").write_text(base_sym_text + ".label bad_map_sym=$c500\n", encoding="utf-8")
        if not validate_build(bdir):
            print("FAIL: failed to catch symbol in $C100-$CFFF", file=sys.stderr)
            return 1

    print("Atari 8-bit memory contract self-test: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true", help="Run synthetic pass/fail self-tests.")
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR)
    args = parser.parse_args()

    if args.selftest:
        return run_selftest()

    errors = validate_build(args.build_dir)
    if errors:
        print("Atari 8-bit memory contract check FAILED:", file=sys.stderr)
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        return 1

    print("Atari 8-bit memory contract check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
