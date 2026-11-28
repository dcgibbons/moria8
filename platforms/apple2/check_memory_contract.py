#!/usr/bin/env python3
"""Validate Apple II linked symbols and emitted PRG ownership boundaries."""

from __future__ import annotations

import argparse
import re
import struct
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import build_catalog  # noqa: E402
import check_item_catalog_ports  # noqa: E402

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
    PrgSpec("legalui", 0xA400, 0xB200, "legal_code_end"),
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
    PrgSpec("ovl.modal", 0xA400, 0xAE00, "ovl_modal_misc_end"),
    PrgSpec("ovl.help", 0xA400, 0xBA00, "ovl_help_end"),
    PrgSpec("ovl.ui", 0xA400, 0xAC00, "ovl_ui_end"),
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
    if linked_boot_end - loader_src > 1024:
        raise ContractViolation("relocated loader exceeds $A600-$A9FF")
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

    for raw_name in ("MORIA8.RES", "OVL.UI", "OVL.ITEMS", "OVL.SPELL", "OVL.MODAL", "A2.HUFFDATA"):
        raw_p = BUILD / "bin" / raw_name
        lz4_p = BUILD / "bin" / f"{raw_name}.LZ4"
        if raw_p.is_file() and lz4_p.is_file():
            raw_bytes = raw_p.read_bytes()
            lz4_bytes = lz4_p.read_bytes()
            decoded = build_catalog.lz4_decode(lz4_bytes)
            if decoded != raw_bytes:
                raise ContractViolation(
                    f"{raw_name}.LZ4 round-trip failed: lz4={len(lz4_bytes)}, raw={len(raw_bytes)}"
                )
            print(f"ASSERT {raw_name}.LZ4 PASS {len(lz4_bytes)}->{len(raw_bytes)}B")
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

    cat_errs = check_item_catalog_ports.verify_port("apple2")
    if cat_errs:
        raise ContractViolation("item catalog 0..360 check failed: " + "; ".join(cat_errs[:4]))
    print("ASSERT item-catalog-0..360 PASS 361 items")
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

    # ProDOS (.po) Rule 7 selftests (positive seedling/sapling + missing/wrong-type/LF failures)
    lic_cr = (ROOT / "data" / "LICENSE").read_bytes().replace(b"\n", b"\r")
    offer_cr = (ROOT / "data" / "SOURCE-OFFER").read_bytes().replace(b"\n", b"\r")
    good_po = _build_test_pro140(
        "MORIA8",
        [
            ("LICENSE", 0x04, lic_cr),
            ("SOURCE.OFFER", 0x04, offer_cr),
        ],
    )
    if validate_disk(good_po):
        raise AssertionError("valid synthetic .po failed Rule 7 check")
    with tempfile.NamedTemporaryFile(suffix=".po") as tf:
        Path(tf.name).write_bytes(good_po)
        if check_disk(Path(tf.name), quiet=True):
            raise AssertionError("check_disk failed on valid synthetic .po")

    bad_po_cases = (
        ("missing LICENSE", [("SOURCE.OFFER", 0x04, offer_cr)]),
        ("missing SOURCE.OFFER", [("LICENSE", 0x04, lic_cr)]),
        ("wrong file_type BIN", [("LICENSE", 0x06, lic_cr), ("SOURCE.OFFER", 0x04, offer_cr)]),
        (
            "unconverted LF in LICENSE",
            [("LICENSE", 0x04, (ROOT / "data" / "LICENSE").read_bytes()), ("SOURCE.OFFER", 0x04, offer_cr)],
        ),
        (
            "unconverted LF in SOURCE.OFFER",
            [("LICENSE", 0x04, lic_cr), ("SOURCE.OFFER", 0x04, (ROOT / "data" / "SOURCE-OFFER").read_bytes())],
        ),
    )
    for label, entries in bad_po_cases:
        bad_po = _build_test_pro140("MORIA8", entries)
        if not validate_disk(bad_po):
            raise AssertionError(f"negative ProDOS fixture unexpectedly passed: {label}")

    print("RESULT 17 asserts 0 failures")
    return 0


PRODOS_BLOCK_SIZE = 512
PRODOS_VOL_DIR_BLOCK = 2
PRODOS_TXT_TYPE = 0x04
LEGAL_DISK_FILES = (
    ("LICENSE", "LICENSE"),
    ("SOURCE.OFFER", "SOURCE-OFFER"),
)


def _prodos_read_block(po: bytes, block: int) -> bytes:
    off = block * PRODOS_BLOCK_SIZE
    if block < 0 or off + PRODOS_BLOCK_SIZE > len(po):
        raise ContractViolation(f"ProDOS block {block} out of range (image {len(po)} B)")
    return po[off : off + PRODOS_BLOCK_SIZE]


def _prodos_root_entries(po: bytes) -> dict[str, tuple[int, int, int, int]]:
    """Return mapping upper_name -> (storage_type, file_type, key_pointer, eof) from root dir."""
    if len(po) < 6 * PRODOS_BLOCK_SIZE or len(po) % PRODOS_BLOCK_SIZE != 0:
        raise ContractViolation(f"invalid ProDOS .po size: {len(po)} B")
    entries: dict[str, tuple[int, int, int, int]] = {}
    seen_blocks: set[int] = set()
    blk_num = PRODOS_VOL_DIR_BLOCK
    entry_len = 0x27
    entries_per_blk = 0x0D
    first = True
    while blk_num != 0:
        if blk_num in seen_blocks:
            raise ContractViolation(f"ProDOS volume directory cycle at block {blk_num}")
        seen_blocks.add(blk_num)
        blk = _prodos_read_block(po, blk_num)
        next_blk = struct.unpack_from("<H", blk, 2)[0]
        if first:
            hdr_type = blk[4] >> 4
            if hdr_type != 0x0F:
                raise ContractViolation(f"ProDOS block 2 missing volume header (storage type {hdr_type:#x})")
            entry_len = blk[0x23] or 0x27
            entries_per_blk = blk[0x24] or 0x0D
            start_slot = 1
            first = False
        else:
            start_slot = 0
        for slot in range(start_slot, entries_per_blk):
            off = 4 + slot * entry_len
            if off + entry_len > PRODOS_BLOCK_SIZE:
                break
            type_len = blk[off]
            storage_type = type_len >> 4
            name_len = type_len & 0x0F
            if storage_type == 0 or name_len == 0:
                continue
            name = blk[off + 1 : off + 1 + name_len].decode("ascii", errors="replace").upper()
            file_type = blk[off + 0x10]
            key_pointer = struct.unpack_from("<H", blk, off + 0x11)[0]
            eof = blk[off + 0x15] | (blk[off + 0x16] << 8) | (blk[off + 0x17] << 16)
            entries[name] = (storage_type, file_type, key_pointer, eof)
        blk_num = next_blk
    return entries


def _prodos_read_file(po: bytes, storage_type: int, key_pointer: int, eof: int) -> bytes:
    if storage_type == 1:  # seedling (<= 512 B)
        if eof > PRODOS_BLOCK_SIZE:
            raise ContractViolation(f"ProDOS seedling EOF {eof} exceeds 512 B")
        return _prodos_read_block(po, key_pointer)[:eof]
    if storage_type == 2:  # sapling (<= 128 KB)
        idx = _prodos_read_block(po, key_pointer)
        out = bytearray()
        nblocks = (eof + PRODOS_BLOCK_SIZE - 1) // PRODOS_BLOCK_SIZE
        if nblocks > 256:
            raise ContractViolation(f"ProDOS sapling block count {nblocks} > 256")
        for i in range(nblocks):
            blk = idx[i] | (idx[256 + i] << 8)
            out.extend(bytes(PRODOS_BLOCK_SIZE) if blk == 0 else _prodos_read_block(po, blk))
        return bytes(out[:eof])
    if storage_type == 3:  # tree
        master = _prodos_read_block(po, key_pointer)
        out = bytearray()
        rem = eof
        m_idx = 0
        while rem > 0 and m_idx < 128:
            sub_blk = master[m_idx] | (master[256 + m_idx] << 8)
            m_idx += 1
            if sub_blk == 0:
                chunk = min(rem, 256 * PRODOS_BLOCK_SIZE)
                out.extend(bytes(chunk))
                rem -= chunk
                continue
            sub = _prodos_read_block(po, sub_blk)
            for i in range(256):
                if rem <= 0:
                    break
                dblk = sub[i] | (sub[256 + i] << 8)
                take = min(rem, PRODOS_BLOCK_SIZE)
                out.extend((bytes(PRODOS_BLOCK_SIZE) if dblk == 0 else _prodos_read_block(po, dblk))[:take])
                rem -= take
        return bytes(out[:eof])
    raise ContractViolation(f"unsupported ProDOS storage_type {storage_type}")


def validate_disk(po: bytes) -> list[str]:
    """Verify Rule 7 standalone TXT files LICENSE and SOURCE.OFFER on a ProDOS .po image."""
    errors: list[str] = []
    entries = _prodos_root_entries(po)
    for prodos_name, src_name in LEGAL_DISK_FILES:
        entry = entries.get(prodos_name)
        if entry is None:
            errors.append(f"Rule 7 release legal file {prodos_name} missing from ProDOS root directory")
            continue
        storage_type, file_type, key_pointer, eof = entry
        if file_type != PRODOS_TXT_TYPE:
            errors.append(
                f"Rule 7 legal file {prodos_name} has ProDOS file_type ${file_type:02X}, expected TXT (${PRODOS_TXT_TYPE:02X})"
            )
            continue
        payload = _prodos_read_file(po, storage_type, key_pointer, eof)
        expected = (ROOT / "data" / src_name).read_bytes().replace(b"\n", b"\r")
        if b"\n" in payload or payload != expected:
            errors.append(
                f"Rule 7 legal file {prodos_name} content/EOL mismatch "
                f"(expected LF->CR copy of data/{src_name}, {len(expected)} B, got {len(payload)} B)"
            )
    return errors


def _build_test_pro140(vol_name: str, files: list[tuple[str, int, bytes]]) -> bytes:
    """Minimal pure-Python ProDOS 140K .po writer supporting seedling & sapling files for selftest."""
    img = bytearray(280 * PRODOS_BLOCK_SIZE)
    dir_blk = bytearray(PRODOS_BLOCK_SIZE)
    vname = vol_name.upper().encode("ascii")[:15]
    dir_blk[4] = (0x0F << 4) | len(vname)
    dir_blk[5 : 5 + len(vname)] = vname
    dir_blk[0x23] = 0x27  # entry_length
    dir_blk[0x24] = 0x0D  # entries_per_block
    struct.pack_into("<H", dir_blk, 0x25, len(files))  # file_count
    struct.pack_into("<H", dir_blk, 0x27, 6)  # bit_map_pointer
    struct.pack_into("<H", dir_blk, 0x29, 280)  # total_blocks

    next_blk = 7
    for idx, (fname, ftype, data) in enumerate(files, start=1):
        off = 4 + idx * 0x27
        raw_name = fname.upper().encode("ascii")[:15]
        eof = len(data)
        if eof <= PRODOS_BLOCK_SIZE:
            stype = 1
            key_ptr = next_blk
            img[next_blk * PRODOS_BLOCK_SIZE : next_blk * PRODOS_BLOCK_SIZE + eof] = data
            next_blk += 1
        else:
            stype = 2
            idx_blk = next_blk
            next_blk += 1
            nblks = (eof + PRODOS_BLOCK_SIZE - 1) // PRODOS_BLOCK_SIZE
            for b_i in range(nblks):
                dblk = next_blk
                next_blk += 1
                img[idx_blk * PRODOS_BLOCK_SIZE + b_i] = dblk & 0xFF
                img[idx_blk * PRODOS_BLOCK_SIZE + 256 + b_i] = (dblk >> 8) & 0xFF
                chunk = data[b_i * PRODOS_BLOCK_SIZE : (b_i + 1) * PRODOS_BLOCK_SIZE]
                img[dblk * PRODOS_BLOCK_SIZE : dblk * PRODOS_BLOCK_SIZE + len(chunk)] = chunk
            key_ptr = idx_blk
        dir_blk[off] = (stype << 4) | len(raw_name)
        dir_blk[off + 1 : off + 1 + len(raw_name)] = raw_name
        dir_blk[off + 0x10] = ftype
        struct.pack_into("<H", dir_blk, off + 0x11, key_ptr)
        dir_blk[off + 0x15] = eof & 0xFF
        dir_blk[off + 0x16] = (eof >> 8) & 0xFF
        dir_blk[off + 0x17] = (eof >> 16) & 0xFF
    img[PRODOS_VOL_DIR_BLOCK * PRODOS_BLOCK_SIZE : (PRODOS_VOL_DIR_BLOCK + 1) * PRODOS_BLOCK_SIZE] = dir_blk
    return bytes(img)


def check_disk(disk_path: Path, *, quiet: bool = False) -> list[str]:
    errors = validate_disk(disk_path.read_bytes())
    if not quiet:
        if errors:
            for err in errors:
                print(f"ASSERT apple2-disk-rule7 FAIL {err}", file=sys.stderr)
            print(f"RESULT 1 asserts {len(errors)} failures", file=sys.stderr)
        else:
            print(f"ASSERT apple2-disk-rule7 PASS {disk_path.name}")
            print("RESULT 1 asserts 0 failures")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--disk", type=Path, help="check this .po holds Rule 7 LICENSE and SOURCE.OFFER")
    args = parser.parse_args()
    try:
        if args.selftest:
            return selftest()
        if args.disk:
            return 1 if check_disk(args.disk) else 0
        return check_artifacts()
    except (ContractViolation, OSError) as exc:
        print(f"ASSERT memory-contract FAIL {exc}")
        print("RESULT 1 asserts 1 failures")
        return 1


if __name__ == "__main__":
    sys.exit(main())
