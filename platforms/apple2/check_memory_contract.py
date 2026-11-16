#!/usr/bin/env python3
"""Validate Apple II linked symbols and emitted PRG ownership boundaries."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import build_catalog  # noqa: E402

BUILD = ROOT / "build" / "apple2"
MAIN_SYM = BUILD / "main.sym"
BOOT_SYM = BUILD / "boot.sym"
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
    PrgSpec("legalui", 0xA400, 0xAA00, "legal_code_end"),
    PrgSpec("moria8a2.prg", 0x0A00, 0x7C00, "program_end"),
    PrgSpec("a2.play", 0x7C00, 0xA000, "a2_play_end", b"M8P"),
    # Aux RAM above the map (cache_layout.s): aux data, the monster
    # catalog's fields, and the Huffman corpus with the catalog's names.
    PrgSpec("a2.auxdata", 0x3B0C, 0x5000, "a2_auxdata_end"),
    PrgSpec("a2.catalog", 0x5000, 0x6700, "catalog_fields_end"),
    PrgSpec("a2.huffdata", 0x8D00, 0xAA00, "ovl_huffdata_end"),
    PrgSpec("ovl.start", 0xA400, 0xBA00, "ovl_start_end"),
    PrgSpec("ovl.town", 0xA400, 0xBA00, "ovl_town_end"),
    PrgSpec("ovl.death", 0xA400, 0xBA00, "ovl_death_end"),
    PrgSpec("ovl.modal", 0xA400, 0xB000, "ovl_modal_misc_end"),
    PrgSpec("ovl.help", 0xA400, 0xBA00, "ovl_help_end"),
    PrgSpec("ovl.ui", 0xA400, 0xAA00, "ovl_ui_end"),
    PrgSpec("ovl.items", 0xA400, 0xBA00, "ovl_items_end"),
    PrgSpec("ovl.spell", 0xA400, 0xB800, "ovl_spell_end"),
    PrgSpec("ovl.gen", 0xA400, 0xBA00, "ovl_gen_end"),
    PrgSpec("ovl.storage", 0xA400, 0xBA00, "ovl_storage_end"),
    PrgSpec("ovl.title", 0xA400, 0xBA00, "ovl_title_end"),
    PrgSpec("ovl.chest", 0xA400, 0xBA00, "ovl_chest_end"),
    PrgSpec("ovl.home", 0xA400, 0xBA00, "ovl_home_end"),
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

    check_low_memory_claims(main_symbols)
    storage_blob = (BUILD / "ovl.storage").read_bytes()[2:]
    lrr_addr = require_symbol(main_symbols, "load_resume_reset")
    wiz_rst = require_symbol(main_symbols, "wizard_reset_session_state")
    lrr_off = lrr_addr - 0xA400
    exp_jsr = bytes((0x20, wiz_rst & 0xFF, wiz_rst >> 8))
    if not (0 <= lrr_off <= len(storage_blob) - 3) or storage_blob[lrr_off : lrr_off + 3] != exp_jsr:
        raise ContractViolation(
            f"load_resume_reset (${lrr_addr:04X}) not physically emitted in ovl.storage"
        )
    death_blob = (BUILD / "ovl.death").read_bytes()[2:]
    urd_addr = require_symbol(main_symbols, "ui_recall_display")
    rw_addr = require_symbol(main_symbols, "rcl_white")
    rstrs_addr = require_symbol(main_symbols, "rcl_strs")
    urd_off = urd_addr - 0xA400
    exp_urd_jsr = bytes((0x20, rw_addr & 0xFF, rw_addr >> 8))
    if (
        not (0 <= urd_off <= len(death_blob) - 3)
        or death_blob[urd_off : urd_off + 3] != exp_urd_jsr
        or not (0xA400 <= rstrs_addr < 0xA400 + len(death_blob))
    ):
        raise ContractViolation(
            f"ui_recall_display (${urd_addr:04X}) / rcl_strs (${rstrs_addr:04X}) not physically emitted in ovl.death"
        )
    rvb_addr = require_symbol(main_symbols, "recall_view_body")
    if not 0x7C00 <= rvb_addr < 0xA000:
        raise ContractViolation(
            f"recall_view_body (${rvb_addr:04X}) must stay in A2PlaySlot ($7C00-$9FFF)"
        )
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

    item_cat_path = BUILD / "bin" / "ITEM.CAT"
    if item_cat_path.is_file():
        item_cat = item_cat_path.read_bytes()
        item_cat_end = 0xE000 + len(item_cat)
        if not item_cat.startswith(b"ITM2") or item_cat_end > 0xFFFA:
            raise ContractViolation(
                f"ITEM.CAT invalid or exceeds Aux LC $E000-$FFF9: "
                f"len={len(item_cat)}, end=${item_cat_end:04X}"
            )
        print(f"ASSERT ITEM.CAT PASS $E000-${item_cat_end - 1:04X}")
        checks += 1

    catext_path = BUILD / "bin" / "A2.CATEXT"
    if catext_path.is_file():
        catext = catext_path.read_bytes()
        expected_catext = build_catalog.ext_row_major_bytes(
            build_catalog.load_spec()["creatures"]
        )
        catext_end = 0xD000 + len(catext)
        if len(catext) != 2232 or catext != expected_catext or catext_end > 0xE000:
            raise ContractViolation(
                f"A2.CATEXT invalid or exceeds Aux LC Bank 2 $D000-$DFFF: "
                f"len={len(catext)}, end=${catext_end:04X}"
            )
        print(f"ASSERT A2.CATEXT PASS $D000-${catext_end - 1:04X}")
        checks += 1

    for raw_name in ("A2.AUXDATA", "A2.CATALOG", "A2.CATEXT"):
        raw_p = BUILD / "bin" / raw_name
        pb_p = BUILD / "bin" / f"{raw_name}.PB"
        if raw_p.is_file() and pb_p.is_file():
            raw_bytes = raw_p.read_bytes()
            pb_bytes = pb_p.read_bytes()
            decoded = build_catalog.packbits_decode(pb_bytes)
            if decoded != raw_bytes or len(pb_bytes) > 0x2400:
                raise ContractViolation(
                    f"{raw_name}.PB PackBits round-trip or staging size failed: "
                    f"pb={len(pb_bytes)}, raw={len(raw_bytes)}"
                )
            print(f"ASSERT {raw_name}.PB PASS {len(pb_bytes)}->{len(raw_bytes)}B")
            checks += 1

    pak_path = BUILD / "bin" / "MORIA8.PAK"
    if pak_path.is_file():
        pak = pak_path.read_bytes()
        if len(pak) < 512 or pak[0] != 22 or len(pak) > 131072:
            raise ContractViolation(
                f"MORIA8.PAK invalid count or exceeds sapling ceiling: "
                f"entries={pak[0] if pak else -1}, bytes={len(pak)}"
            )
        print(f"ASSERT MORIA8.PAK PASS {pak[0]} entries {len(pak)}B")
        checks += 1

    print(f"RESULT {checks} asserts 0 failures")
    return 0


LOW_SCRATCH_SYMBOLS = (
    "a2_probe_buf",
    "a2_program_volume",
    "a2_save_volume",
    "a2_last_status",
    "a2_media_status",
    "a2_name_write",
    "a2_name_replace",
    "a2_name_scratch",
    "a2_name_drive",
    "a2_asset_verify",
    "a2_asset_dest",
    "hal_storage_diag_code",
    "hal_storage_diag_phase",
    "hal_storage_diag_readst",
    "hal_storage_diag_device",
    "sfa_save_row",
    "sfa_save_col",
    "sfa_save_char",
    "igk_key",
    "input_kbdbuf_shadow",
)


def check_low_memory_claims(symbols: dict[str, int]) -> None:
    if require_symbol(symbols, "a2_play_start") != 0x7C00:
        raise ContractViolation("a2_play_start is not $7C00")
    zp_save_buf = require_symbol(symbols, "zp_save_buf")
    if zp_save_buf != 0x0200 or zp_save_buf + 142 > 0x0290:
        raise ContractViolation(
            f"zp_save_buf out of Main $0200-$028F bounds: ${zp_save_buf:04X}"
        )
    for name in LOW_SCRATCH_SYMBOLS:
        addr = require_symbol(symbols, name)
        if not 0x0300 < addr < 0x033C:
            raise ContractViolation(
                f"{name} out of Main $0301-$033B scratch bounds: ${addr:04X}"
            )
    aux_base = require_symbol(symbols, "a2_aux_scratch_base")
    aux_end = require_symbol(symbols, "a2_aux_scratch_end")
    if aux_base != 0x0200 or aux_end != 0x03FF:
        raise ContractViolation(
            f"Aux scratch window unexpected: ${aux_base:04X}-${aux_end:04X}"
        )
    decode_buf = require_symbol(symbols, "item_name_decode_buf")
    if decode_buf < 0x037D or decode_buf + 48 > 0x03D0:
        raise ContractViolation(
            f"item_name_decode_buf out of Page-3 $037D-$03CF bounds: ${decode_buf:04X}"
        )
    for name in (
        "hal_item_cat_read_byte",
        "hal_recall_read_byte",
        "hal_recall_write_byte",
        "a2_aux_lc_bounce_xfer",
        "catalog_fetch_ext",
        "cat_ext_record",
        "recall_view_display",
        "recall_view_cdefense",
    ):
        addr = require_symbol(symbols, name)
        if not 0x0A00 <= addr < 0x7C00:
            raise ContractViolation(
                f"{name} must stay in resident Default ($0A00-$7BFF): ${addr:04X}"
            )
    if require_symbol(symbols, "cat_ext_record") + 8 > 0x7C00:
        raise ContractViolation("cat_ext_record[0..7] overflows resident Default ($7C00)")


def selftest() -> int:
    valid = PrgSpec("fixture.prg", 0x2000, 0x2100, signature=b"M8")
    prg_extent(bytes((0x00, 0x20)) + b"M8payload", valid)

    valid_symbols = {
        "a2_play_start": 0x7C00,
        "zp_save_buf": 0x0200,
        "a2_aux_scratch_base": 0x0200,
        "a2_aux_scratch_end": 0x03FF,
        "item_name_decode_buf": 0x0380,
        "hal_item_cat_read_byte": 0x6000,
        "hal_recall_read_byte": 0x6020,
        "hal_recall_write_byte": 0x6040,
        "a2_aux_lc_bounce_xfer": 0x6060,
        "catalog_fetch_ext": 0x6080,
        "cat_ext_record": 0x60A0,
        "recall_view_display": 0x6140,
        "recall_view_cdefense": 0x6152,
    }
    for idx, name in enumerate(LOW_SCRATCH_SYMBOLS):
        valid_symbols[name] = 0x0301 + idx
    check_low_memory_claims(valid_symbols)

    bad_symbol_cases = (
        {"zp_save_buf": 0x0A00},
        {"zp_save_buf": 0x0204},
        {"igk_key": 0x0300},
        {"igk_key": 0x033C},
        {"a2_aux_scratch_end": 0x03FE},
        {"item_name_decode_buf": 0x037C},
        {"item_name_decode_buf": 0x03A1},
        {"hal_item_cat_read_byte": 0x7C00},
        {"hal_recall_read_byte": 0x0900},
        {"catalog_fetch_ext": 0xA400},
        {"cat_ext_record": 0x7BF9},
        {"recall_view_display": 0xA400},
        {"recall_view_cdefense": 0x7C00},
    )
    for patch in bad_symbol_cases:
        sample = dict(valid_symbols)
        sample.update(patch)
        try:
            check_low_memory_claims(sample)
        except ContractViolation:
            continue
        raise AssertionError(f"negative symbol fixture passed: {patch}")

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

    print("RESULT 11 asserts 0 failures")
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
