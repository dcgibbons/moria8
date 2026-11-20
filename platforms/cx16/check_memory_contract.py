#!/usr/bin/env python3
"""Validate Commander X16 linked symbols and emitted PRG ownership boundaries."""

from __future__ import annotations

import argparse
import re
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(ROOT / "tools"))
import check_item_catalog_ports  # noqa: E402
BUILD = ROOT / "build" / "cx16"
MEMORY_S = Path(__file__).resolve().parent / "memory.s"
MAIN_SYM = BUILD / "main.sym"
SYMBOL_RE = re.compile(r"^\.label ([A-Za-z0-9_]+)=\$([0-9a-fA-F]+)(?:\s*\{)?$")
BANK_CONST_RE = re.compile(
    r"^\s*\.const\s+(CX16_BANK_[A-Z0-9_]+)\s*=\s*(\$[0-9a-fA-F]+|\d+)"
)
LOW_RAM_CEILING = 0x9B00
LOW_RAM_CART_LIVE_CEILING = 0x9980
LOW_RAM_MIN_FREE = 1500
AUXDATA_CEILING = 0x8000
AUXDATA_MAX_USED_END = 0x7800


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
    PrgSpec("LEGALUI", 0xA000, 0xAE00, "legal_code_end"),
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
    PrgSpec("OVL.HOME", 0xA000, 0xC000, "ovl_home_end"),
    PrgSpec("OVL.STORAGE", 0xA000, 0xC000, "ovl_storage_end"),
    PrgSpec("OVL.TITLE", 0xA000, 0xC000, "ovl_title_end"),
    PrgSpec("OVL.CHEST", 0xA000, 0xC000, "ovl_chest_end"),
    PrgSpec("MONSTER.CAT", 0xA000, 0xC000, "catalog_bank_end"),
    PrgSpec("MONSTER.EXT", 0xA000, 0xA8B8, min_payload=2232),
    PrgSpec("ITEM.CAT", 0xA000, 0xC000, signature=b"ITM2"),
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


def check_artifacts(build_dir: Path = BUILD) -> int:
    main_symbols = read_symbols(build_dir / "main.sym")
    checks = 0

    for spec in PRG_SPECS:
        path = build_dir / spec.filename
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

    policy_path = MEMORY_S.parent / "hal" / "lifecycle_policy.s"
    if not re.search(
        r"^\s*#define\s+HAL_PLATFORM_MONSTER_CATALOG\b",
        policy_path.read_text(),
        re.MULTILINE,
    ):
        raise ContractViolation(
            f"{policy_path}: expected HAL_PLATFORM_MONSTER_CATALOG enabled"
        )
    bank_consts = parse_bank_constants(MEMORY_S.read_text(), catalog_enabled=True)
    used_banks, free_banks = check_bank_allocations(bank_consts, build_dir)
    print(
        f"ASSERT bank-allocations PASS {used_banks}/{bank_consts['CX16_BANK_COUNT']} "
        f"used ({free_banks} free: Banks 7-8 & "
        f"{bank_consts['CX16_BANK_WARM_BASE']}-{bank_consts['CX16_BANK_WARM_END']})"
    )
    checks += 1

    low_free = check_low_ram_bounds(main_symbols)
    aux_free = AUXDATA_CEILING - require_symbol(main_symbols, "ovl_auxdata_end")
    print(
        f"ASSERT main-symbol-owners PASS low_ram_free={low_free}B "
        f"auxdata_free={aux_free}B"
    )
    checks += 1

    if build_dir.resolve() == BUILD.resolve():
        cat_errs = check_item_catalog_ports.verify_port("cx16")
        if cat_errs:
            raise ContractViolation("item catalog 0..360 check failed: " + "; ".join(cat_errs[:4]))
        print("ASSERT item-catalog-0..360 PASS 361 items")
        checks += 1
        default_zip = ROOT / "build" / "moria8-cx16.zip"
        if default_zip.is_file():
            check_zip_bundle(default_zip, build_dir=build_dir, data_dir=ROOT / "data")
            print(f"ASSERT {default_zip.name} PASS 23 entries")
            checks += 1

    print(f"RESULT {checks} asserts 0 failures")
    return 0


def check_zip_bundle(
    zip_path: Path,
    build_dir: Path = BUILD,
    data_dir: Path = ROOT / "data",
) -> None:
    """Validate shipping moria8-cx16.zip entries and LF->CR compliance files."""
    if not zip_path.is_file():
        raise ContractViolation(f"missing CX16 zip bundle: {zip_path}")
    expected_prg_names = {spec.filename for spec in PRG_SPECS}
    expected_names = expected_prg_names | {"LICENSE", "SOURCE-OFFER"}
    try:
        with zipfile.ZipFile(zip_path, "r") as zf:
            bad_member = zf.testzip()
            if bad_member is not None:
                raise ContractViolation(f"{zip_path.name}: corrupt zip entry {bad_member}")
            names = [info.filename for info in zf.infolist()]
            if len(names) != len(set(names)):
                raise ContractViolation(f"{zip_path.name}: duplicate archive entries in {names}")
            name_set = set(names)
            missing = sorted(expected_names - name_set)
            extra = sorted(name_set - expected_names)
            if missing or extra:
                raise ContractViolation(
                    f"{zip_path.name}: entry mismatch (missing={missing}, extra={extra})"
                )
            for doc_name in ("LICENSE", "SOURCE-OFFER"):
                src_doc = data_dir / doc_name
                if not src_doc.is_file():
                    raise ContractViolation(f"missing source compliance file: {src_doc}")
                want_doc = src_doc.read_bytes().replace(b"\n", b"\r")
                got_doc = zf.read(doc_name)
                if got_doc != want_doc:
                    raise ContractViolation(
                        f"{zip_path.name}: {doc_name} does not match LF->CR data/{doc_name}"
                    )
            for spec in PRG_SPECS:
                got_blob = zf.read(spec.filename)
                prg_extent(got_blob, spec)
                disk_file = build_dir / spec.filename
                if disk_file.is_file() and got_blob != disk_file.read_bytes():
                    raise ContractViolation(
                        f"{zip_path.name}: {spec.filename} differs from {disk_file}"
                    )
    except zipfile.BadZipFile as exc:
        raise ContractViolation(f"{zip_path.name}: invalid zip file: {exc}") from exc


def parse_bank_constants(memory_text: str, catalog_enabled: bool = True) -> dict[str, int]:
    """Extract active CX16_BANK_* constants from platforms/cx16/memory.s."""
    consts: dict[str, int] = {}
    if_stack: list[bool] = []
    for raw_line in memory_text.splitlines():
        line = raw_line.split("//", 1)[0].strip()
        if line.startswith("#if HAL_PLATFORM_MONSTER_CATALOG"):
            if_stack.append(catalog_enabled)
            continue
        if line.startswith("#if "):
            if_stack.append(True)
            continue
        if line.startswith("#else"):
            if if_stack:
                if_stack[-1] = not if_stack[-1]
            continue
        if line.startswith("#endif"):
            if if_stack:
                if_stack.pop()
            continue
        if not all(if_stack):
            continue
        match = BANK_CONST_RE.match(line)
        if match:
            val_str = match.group(2)
            consts[match.group(1)] = (
                int(val_str[1:], 16) if val_str.startswith("$") else int(val_str, 10)
            )
    return consts


def check_bank_allocations(
    consts: dict[str, int], build_dir: Path | None = None
) -> tuple[int, int]:
    """Validate non-overlapping HiRAM bank partition 0..63 and free Banks 5, 7-8."""
    required = (
        "CX16_BANK_KERNAL_VARS",
        "CX16_BANK_MAP_LO",
        "CX16_BANK_MAP_HI",
        "CX16_BANK_AUXDATA",
        "CX16_BANK_HUFFDATA",
        "CX16_BANK_CATALOG_EXT",
        "CX16_BANK_ITEM_CAT",
        "CX16_BANK_EXT_BASE",
        "CX16_BANK_EXT_END",
        "CX16_BANK_OVERLAY_BASE",
        "CX16_BANK_OVERLAY_END",
        "CX16_BANK_TITLE_ART",
        "CX16_BANK_CATALOG",
        "CX16_BANK_LEGAL",
        "CX16_BANK_WARM_BASE",
        "CX16_BANK_WARM_END",
        "CX16_BANK_COUNT",
    )
    missing = [name for name in required if name not in consts]
    if missing:
        raise ContractViolation(f"missing CX16_BANK constants: {missing}")
    if "CX16_BANK_TIER_BASE" in consts or "CX16_BANK_TIER_END" in consts:
        raise ContractViolation("legacy CX16_BANK_TIER_* active despite MONSTER.CAT")

    count = consts["CX16_BANK_COUNT"]
    if count != 64:
        raise ContractViolation(f"CX16_BANK_COUNT={count}, expected 64")
    if consts["CX16_BANK_CATALOG_EXT"] != 5:
        raise ContractViolation(
            f"CX16_BANK_CATALOG_EXT={consts['CX16_BANK_CATALOG_EXT']}, expected 5"
        )
    if consts["CX16_BANK_ITEM_CAT"] != 6:
        raise ContractViolation(
            f"CX16_BANK_ITEM_CAT={consts['CX16_BANK_ITEM_CAT']}, expected 6"
        )
    if (consts["CX16_BANK_EXT_BASE"], consts["CX16_BANK_EXT_END"]) != (7, 8):
        raise ContractViolation(
            f"CX16_BANK_EXT_BASE..END={consts['CX16_BANK_EXT_BASE']}.."
            f"{consts['CX16_BANK_EXT_END']}, expected 7..8"
        )
    if (consts["CX16_BANK_WARM_BASE"], consts["CX16_BANK_WARM_END"]) != (25, 63):
        raise ContractViolation(
            f"CX16_BANK_WARM_BASE..END={consts['CX16_BANK_WARM_BASE']}.."
            f"{consts['CX16_BANK_WARM_END']}, expected 25..63"
        )

    spans = (
        ("kernal", consts["CX16_BANK_KERNAL_VARS"], consts["CX16_BANK_KERNAL_VARS"], True),
        ("map", consts["CX16_BANK_MAP_LO"], consts["CX16_BANK_MAP_HI"], True),
        ("auxdata", consts["CX16_BANK_AUXDATA"], consts["CX16_BANK_AUXDATA"], True),
        ("huffdata", consts["CX16_BANK_HUFFDATA"], consts["CX16_BANK_HUFFDATA"], True),
        ("catalog_ext", consts["CX16_BANK_CATALOG_EXT"], consts["CX16_BANK_CATALOG_EXT"], True),
        ("item_cat", consts["CX16_BANK_ITEM_CAT"], consts["CX16_BANK_ITEM_CAT"], True),
        ("ext_pool", consts["CX16_BANK_EXT_BASE"], consts["CX16_BANK_EXT_END"], False),
        ("overlays", consts["CX16_BANK_OVERLAY_BASE"], consts["CX16_BANK_OVERLAY_END"], True),
        ("title_art", consts["CX16_BANK_TITLE_ART"], consts["CX16_BANK_TITLE_ART"], True),
        ("catalog", consts["CX16_BANK_CATALOG"], consts["CX16_BANK_CATALOG"], True),
        ("legal", consts["CX16_BANK_LEGAL"], consts["CX16_BANK_LEGAL"], True),
        ("warm_pool", consts["CX16_BANK_WARM_BASE"], consts["CX16_BANK_WARM_END"], False),
    )

    owners: dict[int, str] = {}
    used_banks = 0
    free_banks = 0
    for label, lo, hi, active in spans:
        if lo < 0 or hi >= count or lo > hi:
            raise ContractViolation(f"invalid bank span {label}: {lo}..{hi}")
        for bank in range(lo, hi + 1):
            if bank in owners:
                raise ContractViolation(
                    f"bank {bank} collision between {owners[bank]} and {label}"
                )
            owners[bank] = label
        span_len = hi - lo + 1
        if active:
            used_banks += span_len
        else:
            free_banks += span_len

    gaps = [bank for bank in range(count) if bank not in owners]
    if gaps:
        raise ContractViolation(f"unassigned bank IDs in 0..{count - 1}: {gaps}")

    ovl_count = consts["CX16_BANK_OVERLAY_END"] - consts["CX16_BANK_OVERLAY_BASE"] + 1
    ovl_specs = [spec for spec in PRG_SPECS if spec.filename.startswith("OVL.")]
    if len(ovl_specs) != ovl_count:
        raise ContractViolation(
            f"overlay bank count {ovl_count} != PRG_SPECS OVL count {len(ovl_specs)}"
        )

    if build_dir is not None:
        legacy = [
            f"MONSTER.DB.{idx}"
            for idx in range(1, 5)
            if (build_dir / f"MONSTER.DB.{idx}").exists()
        ]
        if legacy:
            raise ContractViolation(f"legacy tier files present in {build_dir}: {legacy}")

    return used_banks, free_banks


def check_low_ram_bounds(main_symbols: dict[str, int]) -> int:
    """Validate Low-RAM headroom, extended helper bounds, and Bank 3 table placement."""
    zp_save_buf = require_symbol(main_symbols, "zp_save_buf")
    if not 0x0801 <= zp_save_buf < LOW_RAM_CEILING:
        raise ContractViolation(f"zp_save_buf outside resident RAM: ${zp_save_buf:04X}")

    program_end = require_symbol(main_symbols, "program_end")
    if program_end > LOW_RAM_CEILING:
        raise ContractViolation(
            f"program_end ${program_end:04X} overlaps tier name pool ${LOW_RAM_CEILING:04X}"
        )
    low_free = LOW_RAM_CEILING - program_end
    if low_free < LOW_RAM_MIN_FREE:
        raise ContractViolation(
            f"Low-RAM headroom {low_free} B < {LOW_RAM_MIN_FREE} B "
            f"(program_end ${program_end:04X})"
        )

    helper_syms = (
        "cx16_bank_read_byte",
        "cx16_bank_write_byte",
        "cx16_bank_read_block",
        "cx16_bank_write_block",
        "cx16_bank_copy",
        "cx16_bank_helpers_end",
    )
    prev = 0x080D
    for name in helper_syms:
        addr = require_symbol(main_symbols, name)
        if not (prev <= addr <= program_end < LOW_RAM_CEILING):
            raise ContractViolation(
                f"{name} ${addr:04X} outside fixed Low RAM [$080D..${program_end:04X}]"
            )
        prev = addr

    ovl_auxdata_end = require_symbol(main_symbols, "ovl_auxdata_end")
    if not 0x6000 < ovl_auxdata_end <= AUXDATA_MAX_USED_END:
        raise ContractViolation(
            f"ovl_auxdata_end ${ovl_auxdata_end:04X} exceeds ${AUXDATA_MAX_USED_END:04X}"
        )
    key_map_petscii = require_symbol(main_symbols, "key_map_petscii")
    key_map_cmd = require_symbol(main_symbols, "key_map_cmd")
    if not (0x6000 <= key_map_petscii < key_map_cmd < ovl_auxdata_end <= AUXDATA_CEILING):
        raise ContractViolation(
            f"key_map tables ${key_map_petscii:04X}/${key_map_cmd:04X} outside Bank 3 AuxData"
        )
    hicr = require_symbol(main_symbols, "hal_item_cat_read_byte")
    if not (0x080D <= hicr < program_end < LOW_RAM_CEILING):
        raise ContractViolation(
            f"hal_item_cat_read_byte ${hicr:04X} outside fixed Low RAM [$080D..${program_end:04X})"
        )
    cat_ext_rec = require_symbol(main_symbols, "cat_ext_record")
    cat_fetch_ext = require_symbol(main_symbols, "catalog_fetch_ext")
    if not (0x080D <= cat_ext_rec < cat_fetch_ext < program_end <= LOW_RAM_CART_LIVE_CEILING):
        raise ContractViolation(
            f"cat_ext_record ${cat_ext_rec:04X} / catalog_fetch_ext ${cat_fetch_ext:04X} "
            f"outside Low-RAM [$080D..${LOW_RAM_CART_LIVE_CEILING:04X}]"
        )
    if cat_ext_rec + 8 > cat_fetch_ext:
        raise ContractViolation(
            f"cat_ext_record ${cat_ext_rec:04X} shorter than 8 B before ${cat_fetch_ext:04X}"
        )
    recall_start = require_symbol(main_symbols, "recall_data_start")
    recall_end = require_symbol(main_symbols, "recall_data_end")
    if not (0x6000 <= recall_start < recall_end <= ovl_auxdata_end <= AUXDATA_CEILING):
        raise ContractViolation(
            f"recall_data ${recall_start:04X}-${recall_end:04X} outside Bank 3 AuxData ($6000-$7FFF)"
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
    return low_free


def selftest() -> int:
    checks = 0
    valid = PrgSpec("fixture.prg", 0xA000, 0xC000, signature=b"M8")
    prg_extent(bytes((0x00, 0xA0)) + b"M8payload", valid)
    checks += 1

    bad_prg_fixtures = (
        (b"\x00", valid),
        (bytes((0x01, 0xA0)) + b"M8", valid),
        (bytes((0x00, 0xA0)) + b"X" * 0x2001, valid),
        (bytes((0x00, 0xA0)) + b"NO", valid),
    )
    for blob, spec in bad_prg_fixtures:
        try:
            prg_extent(blob, spec)
        except ContractViolation:
            checks += 1
            continue
        raise AssertionError("negative PRG fixture unexpectedly passed")

    good_consts = {
        "CX16_BANK_KERNAL_VARS": 0,
        "CX16_BANK_MAP_LO": 1,
        "CX16_BANK_MAP_HI": 2,
        "CX16_BANK_AUXDATA": 3,
        "CX16_BANK_HUFFDATA": 4,
        "CX16_BANK_CATALOG_EXT": 5,
        "CX16_BANK_ITEM_CAT": 6,
        "CX16_BANK_EXT_BASE": 7,
        "CX16_BANK_EXT_END": 8,
        "CX16_BANK_OVERLAY_BASE": 9,
        "CX16_BANK_OVERLAY_END": 21,
        "CX16_BANK_TITLE_ART": 22,
        "CX16_BANK_CATALOG": 23,
        "CX16_BANK_LEGAL": 24,
        "CX16_BANK_WARM_BASE": 25,
        "CX16_BANK_WARM_END": 63,
        "CX16_BANK_COUNT": 64,
    }
    assert check_bank_allocations(good_consts) == (23, 41)
    checks += 1

    bad_bank_mutations = (
        {"CX16_BANK_EXT_END": 9},       # collides with overlays
        {"CX16_BANK_CATALOG_EXT": 6},   # collides with ITEM.CAT + gap
        {"CX16_BANK_ITEM_CAT": 7},      # wrong item catalog bank + collides
        {"CX16_BANK_TIER_BASE": 5},     # legacy tier constants active
        {"CX16_BANK_WARM_BASE": 26},    # invalid warm base + gap
    )
    for patch in bad_bank_mutations:
        bad = dict(good_consts)
        bad.update(patch)
        try:
            check_bank_allocations(bad)
        except ContractViolation:
            checks += 1
            continue
        raise AssertionError(f"negative bank fixture unexpectedly passed: {patch}")

    parsed = parse_bank_constants(
        "\n".join(
            [
                "#if HAL_PLATFORM_MONSTER_CATALOG",
                ".const CX16_BANK_CATALOG_EXT = 5",
                "#else",
                ".const CX16_BANK_TIER_BASE = 5",
                "#endif",
            ]
        ),
        catalog_enabled=True,
    )
    if parsed != {"CX16_BANK_CATALOG_EXT": 5}:
        raise AssertionError(f"parse_bank_constants mismatch: {parsed}")
    checks += 1

    good_syms = {
        "zp_save_buf": 0x081A,
        "cx16_bank_read_byte": 0x6600,
        "cx16_bank_write_byte": 0x661A,
        "cx16_bank_read_block": 0x6631,
        "cx16_bank_write_block": 0x664B,
        "cx16_bank_copy": 0x6665,
        "cx16_bank_helpers_end": 0x66AA,
        "cat_ext_record": 0x3800,
        "catalog_fetch_ext": 0x3808,
        "program_end": 0x9120,
        "hal_item_cat_read_byte": 0x0900,
        "key_map_petscii": 0x6000,
        "key_map_cmd": 0x6046,
        "recall_data_start": 0x6100,
        "recall_data_end": 0x655C,
        "ovl_auxdata_end": 0x7500,
    }
    assert check_low_ram_bounds(good_syms) == 0x9B00 - 0x9120
    checks += 1

    bad_sym_mutations = (
        {"program_end": 0x9525},               # < 1500 B headroom
        {"cx16_bank_helpers_end": 0x9B05},     # helper outside Low RAM
        {"hal_item_cat_read_byte": 0x9C00},    # reader outside Low RAM
        {"catalog_fetch_ext": 0x9A00},         # ext fetcher above $9980 ceiling
        {"cat_ext_record": 0x3804},            # < 8 B before catalog_fetch_ext
        {"key_map_petscii": 0x0C80},           # key map stuck in Low RAM
        {"recall_data_start": 0x0900},         # recall stuck in Low RAM
    )
    for patch in bad_sym_mutations:
        bad = dict(good_syms)
        bad.update(patch)
        try:
            check_low_ram_bounds(bad)
        except ContractViolation:
            checks += 1
            continue
        raise AssertionError(f"negative symbol fixture unexpectedly passed: {patch}")

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        bdir = tmp / "cx16"
        ddir = tmp / "data"
        bdir.mkdir()
        ddir.mkdir()
        (ddir / "LICENSE").write_bytes(b"Line1\nLine2\n")
        (ddir / "SOURCE-OFFER").write_bytes(b"Offer1\nOffer2\n")
        for spec in PRG_SPECS:
            body_len = max(spec.min_payload, len(spec.signature) + 4)
            body = spec.signature + b"\xEA" * (body_len - len(spec.signature))
            (bdir / spec.filename).write_bytes(
                bytes((spec.start & 0xFF, spec.start >> 8)) + body
            )
        good_zip = tmp / "moria8-cx16.zip"
        with zipfile.ZipFile(good_zip, "w") as zf:
            for spec in PRG_SPECS:
                zf.writestr(spec.filename, (bdir / spec.filename).read_bytes())
            zf.writestr("LICENSE", b"Line1\rLine2\r")
            zf.writestr("SOURCE-OFFER", b"Offer1\rOffer2\r")
        check_zip_bundle(good_zip, build_dir=bdir, data_dir=ddir)
        checks += 1

        bad_zip_missing = tmp / "missing.zip"
        with zipfile.ZipFile(bad_zip_missing, "w") as zf:
            for spec in PRG_SPECS:
                if spec.filename != "ITEM.CAT":
                    zf.writestr(spec.filename, (bdir / spec.filename).read_bytes())
            zf.writestr("LICENSE", b"Line1\rLine2\r")
            zf.writestr("SOURCE-OFFER", b"Offer1\rOffer2\r")
        try:
            check_zip_bundle(bad_zip_missing, build_dir=bdir, data_dir=ddir)
        except ContractViolation:
            checks += 1
        else:
            raise AssertionError("zip missing ITEM.CAT unexpectedly passed")

        bad_zip_lf = tmp / "unconverted_lf.zip"
        with zipfile.ZipFile(bad_zip_lf, "w") as zf:
            for spec in PRG_SPECS:
                zf.writestr(spec.filename, (bdir / spec.filename).read_bytes())
            zf.writestr("LICENSE", b"Line1\nLine2\n")
            zf.writestr("SOURCE-OFFER", b"Offer1\rOffer2\r")
        try:
            check_zip_bundle(bad_zip_lf, build_dir=bdir, data_dir=ddir)
        except ContractViolation:
            checks += 1
        else:
            raise AssertionError("zip with unconverted LF LICENSE unexpectedly passed")

    print(f"RESULT {checks} asserts 0 failures")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--build-dir", type=Path, default=BUILD)
    parser.add_argument("--zip", type=Path, default=None, help="Verify a built moria8-cx16.zip bundle")
    args = parser.parse_args()
    try:
        if args.selftest:
            return selftest()
        if args.zip is not None:
            check_zip_bundle(args.zip, build_dir=args.build_dir, data_dir=ROOT / "data")
            print(f"ASSERT {args.zip.name} PASS 23 entries")
            print("RESULT 1 asserts 0 failures")
            return 0
        return check_artifacts(args.build_dir)
    except (ContractViolation, OSError) as exc:
        print(f"ASSERT memory-contract FAIL {exc}")
        print("RESULT 1 asserts 1 failures")
        return 1


if __name__ == "__main__":
    sys.exit(main())
