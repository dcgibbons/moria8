#!/usr/bin/env python3
"""Pack MORIA8.DAT random-access CP/M container and emit dat_toc.inc.

MORIA8.DAT format ('M8CP' v1):
  Records 0..1 (256 bytes header, zero-padded):
    - [0..3]   (4 B): 'M8CP' magic
    - [4]      (1 B): version = 1
    - [5]      (1 B): entry_count (<= 41)
    - [6..251] (up to 41 x 6 B): little-endian [u16 start_rec, u16 rec_count, u16 byte_len]
    - [252..255]: 0x00 padding

  Records 2+ (128-byte CP/M records):
    Every present entry begins on an exact 128-byte CP/M record boundary and is
    padded with 0x00 to a multiple of 128 bytes. Missing optional overlay slots
    (with --allow-missing-overlays) record [0, 0, 0].
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True

REPO_ROOT = Path(__file__).resolve().parent.parent
TOOLS_DIR = REPO_ROOT / "tools"
DEFAULT_OUT_DIR = REPO_ROOT / "build" / "cpm"
DEFAULT_SJASMPLUS = TOOLS_DIR / "sjasmplus" / "sjasmplus"

DAT_MAGIC = b"M8CP"
DAT_VERSION = 1
CPM_REC_SIZE = 128
DAT_HEADER_RECS = 2
DAT_HEADER_BYTES = DAT_HEADER_RECS * CPM_REC_SIZE  # 256 B
DAT_ENTRY_SIZE = 6
DAT_TOC_OFFSET = 6
DAT_MAX_ENTRIES = (DAT_HEADER_BYTES - DAT_TOC_OFFSET) // DAT_ENTRY_SIZE  # 41
DAT_MAX_REC_COUNT = 255  # 3-byte in-RAM TOC cache stores (u16 start_rec, u8 rec_count)
OVL_MAX_RECORDS = 40     # 5,120 B overlay window (0x5600..0x69FF)


@dataclass(frozen=True)
class DatSlotSpec:
    slot_id: int
    const_name: str
    candidates: tuple[str, ...]
    is_overlay: bool


FIXED_SLOTS: tuple[DatSlotSpec, ...] = (
    DatSlotSpec(0, "DAT_ID_OVL_START", ("ovl_start.ovl", "ovl.start", "OVL.START"), True),
    DatSlotSpec(1, "DAT_ID_OVL_TOWN", ("ovl_town.ovl", "ovl.town", "OVL.TOWN"), True),
    DatSlotSpec(2, "DAT_ID_OVL_DEATH", ("ovl_death.ovl", "ovl.death", "OVL.DEATH"), True),
    DatSlotSpec(3, "DAT_ID_OVL_GEN", ("ovl_gen.ovl", "ovl.gen", "OVL.GEN"), True),
    DatSlotSpec(4, "DAT_ID_OVL_HELP", ("ovl_help.ovl", "ovl.help", "OVL.HELP"), True),
    DatSlotSpec(5, "DAT_ID_OVL_UI", ("ovl_ui.ovl", "ovl.ui", "OVL.UI"), True),
    DatSlotSpec(6, "DAT_ID_OVL_ITEMS", ("ovl_items.ovl", "ovl.items", "OVL.ITEMS"), True),
    DatSlotSpec(7, "DAT_ID_OVL_SPELL", ("ovl_spell.ovl", "ovl.spell", "OVL.SPELL"), True),
    DatSlotSpec(8, "DAT_ID_OVL_MODAL", ("ovl_modal.ovl", "ovl.modal", "OVL.MODAL"), True),
    DatSlotSpec(9, "DAT_ID_OVL_CHEST", ("ovl_chest.ovl", "ovl.chest", "OVL.CHEST"), True),
    DatSlotSpec(10, "DAT_ID_OVL_HOME", ("ovl_home.ovl", "ovl.home", "OVL.HOME"), True),
    DatSlotSpec(11, "DAT_ID_OVL_STORAGE", ("ovl_storage.ovl", "ovl.storage", "OVL.STORAGE"), True),
    DatSlotSpec(12, "DAT_ID_OVL_TITLE", ("ovl_title.ovl", "ovl.title", "OVL.TITLE"), True),
    DatSlotSpec(13, "DAT_ID_OVL_LEGAL", ("ovl_legal.ovl", "legalui.ovl", "ovl.legal", "legalui", "LEGALUI"), True),
    DatSlotSpec(14, "DAT_ID_MONSTER_CAT", ("monster_cat_ascii.bin",), False),
    DatSlotSpec(15, "DAT_ID_ITEM_CAT", ("item_cat_ascii.bin",), False),
    DatSlotSpec(16, "DAT_ID_HUFF_STREAM", ("huff_stream.bin",), False),
    DatSlotSpec(17, "DAT_ID_TITLE_ART", ("title_art.bin",), False),
    DatSlotSpec(18, "DAT_ID_LICENSE", ("license.txt",), False),
    DatSlotSpec(19, "DAT_ID_SRCOFFR", ("srcoffr.txt",), False),
    DatSlotSpec(20, "DAT_ID_OVL_ITEMS_EFF", ("ovl_items_eff.ovl", "ovl.items_eff", "OVL.ITEMS_EFF"), True),
    DatSlotSpec(21, "DAT_ID_OVL_SPELL_EFF", ("ovl_spell_eff.ovl", "ovl.spell_eff", "OVL.SPELL_EFF"), True),
    DatSlotSpec(22, "DAT_ID_OVL_ACTIONS", ("ovl_actions.ovl", "ovl.actions", "OVL.ACTIONS"), True),
    DatSlotSpec(23, "DAT_ID_OVL_MON_EXT", ("ovl_mon_ext.ovl", "ovl.mon_ext", "OVL.MON_EXT"), True),
    DatSlotSpec(24, "DAT_ID_OVL_ITEM_MGT", ("ovl_item_mgt.ovl", "ovl.item_mgt", "OVL.ITEM_MGT"), True),
)

SLOT_BY_NAME: dict[str, int] = {
    **{s.const_name: s.slot_id for s in FIXED_SLOTS},
    **{s.const_name[len("DAT_ID_") :]: s.slot_id for s in FIXED_SLOTS},
}
OVERLAY_SLOT_IDS: frozenset[int] = frozenset(s.slot_id for s in FIXED_SLOTS if s.is_overlay)


def pack_cpm_dat(slot_payloads: list[bytes | None]) -> tuple[bytes, list[dict[str, int]]]:
    """Pack slot payloads into a 128-byte record-aligned 'M8CP' MORIA8.DAT image."""
    entry_count = len(slot_payloads)
    if not (1 <= entry_count <= DAT_MAX_ENTRIES):
        raise ValueError(f"entry_count {entry_count} must be in 1..{DAT_MAX_ENTRIES}")

    header = bytearray(DAT_HEADER_BYTES)
    header[0:4] = DAT_MAGIC
    header[4] = DAT_VERSION
    header[5] = entry_count

    body = bytearray()
    next_rec = DAT_HEADER_RECS
    entries: list[dict[str, int]] = []

    for slot_id, payload in enumerate(slot_payloads):
        if payload is None or len(payload) == 0:
            start_rec = 0
            rec_count = 0
            byte_len = 0
        else:
            byte_len = len(payload)
            if byte_len > 0xFFFF:
                raise ValueError(f"Slot {slot_id} payload ({byte_len} B) exceeds u16 byte_len")
            rec_count = (byte_len + CPM_REC_SIZE - 1) // CPM_REC_SIZE
            if rec_count > DAT_MAX_REC_COUNT:
                raise ValueError(
                    f"Slot {slot_id} record count {rec_count} ({byte_len} B) exceeds DAT_MAX_REC_COUNT ({DAT_MAX_REC_COUNT})"
                )
            if slot_id in OVERLAY_SLOT_IDS and rec_count > OVL_MAX_RECORDS:
                raise ValueError(
                    f"Overlay slot {slot_id} record count {rec_count} ({byte_len} B) exceeds OVL_MAX_RECORDS ({OVL_MAX_RECORDS} = {OVL_MAX_RECORDS * CPM_REC_SIZE} B)"
                )
            start_rec = next_rec
            if start_rec + rec_count > 0xFFFF:
                raise ValueError(f"MORIA8.DAT total records ({start_rec + rec_count}) exceeds u16")
            padded_len = rec_count * CPM_REC_SIZE
            body.extend(payload)
            body.extend(b"\x00" * (padded_len - byte_len))
            next_rec += rec_count

        struct.pack_into(
            "<HHH",
            header,
            DAT_TOC_OFFSET + slot_id * DAT_ENTRY_SIZE,
            start_rec,
            rec_count,
            byte_len,
        )
        entries.append(
            {
                "slot_id": slot_id,
                "start_rec": start_rec,
                "rec_count": rec_count,
                "byte_len": byte_len,
            }
        )

    dat_bytes = bytes(header) + bytes(body)
    assert len(dat_bytes) % CPM_REC_SIZE == 0
    return dat_bytes, entries


def unpack_cpm_dat(blob: bytes) -> list[dict[str, object]]:
    """Validate and unpack a 'M8CP' MORIA8.DAT container."""
    if len(blob) < DAT_HEADER_BYTES or len(blob) % CPM_REC_SIZE != 0:
        raise ValueError(f"Invalid MORIA8.DAT size: {len(blob)}")
    magic = blob[0:4]
    version = blob[4]
    entry_count = blob[5]
    if magic != DAT_MAGIC:
        raise ValueError(f"Invalid magic {magic!r}")
    if version != DAT_VERSION:
        raise ValueError(f"Unsupported version {version}")
    if not (1 <= entry_count <= DAT_MAX_ENTRIES):
        raise ValueError(f"Invalid entry_count {entry_count}")

    total_recs = len(blob) // CPM_REC_SIZE
    seen_recs: set[int] = set()
    out: list[dict[str, object]] = []

    for slot_id in range(entry_count):
        start_rec, rec_count, byte_len = struct.unpack_from(
            "<HHH", blob, DAT_TOC_OFFSET + slot_id * DAT_ENTRY_SIZE
        )
        if rec_count == 0:
            assert start_rec == 0 and byte_len == 0, (slot_id, start_rec, rec_count, byte_len)
            payload = b""
        else:
            assert rec_count <= DAT_MAX_REC_COUNT, (slot_id, rec_count, DAT_MAX_REC_COUNT)
            if slot_id in OVERLAY_SLOT_IDS:
                assert rec_count <= OVL_MAX_RECORDS, (slot_id, rec_count, OVL_MAX_RECORDS)
            assert start_rec >= DAT_HEADER_RECS, (slot_id, start_rec)
            assert start_rec + rec_count <= total_recs, (slot_id, start_rec, rec_count, total_recs)
            assert (rec_count - 1) * CPM_REC_SIZE < byte_len <= rec_count * CPM_REC_SIZE, (
                slot_id, rec_count, byte_len
            )
            for r in range(start_rec, start_rec + rec_count):
                assert r not in seen_recs, f"Overlapping record {r} at slot {slot_id}"
                seen_recs.add(r)
            start_byte = start_rec * CPM_REC_SIZE
            end_byte = start_byte + byte_len
            pad_end = start_byte + rec_count * CPM_REC_SIZE
            assert all(b == 0 for b in blob[end_byte:pad_end]), f"Non-zero padding in slot {slot_id}"
            payload = blob[start_byte:end_byte]

        out.append(
            {
                "slot_id": slot_id,
                "start_rec": start_rec,
                "rec_count": rec_count,
                "byte_len": byte_len,
                "payload": payload,
            }
        )

    for tail_slot in range(entry_count, DAT_MAX_ENTRIES):
        tup = struct.unpack_from("<HHH", blob, DAT_TOC_OFFSET + tail_slot * DAT_ENTRY_SIZE)
        assert tup == (0, 0, 0), f"Non-zero unused TOC slot {tail_slot}: {tup}"
    assert blob[DAT_TOC_OFFSET + DAT_MAX_ENTRIES * DAT_ENTRY_SIZE : DAT_HEADER_BYTES] == b"\x00" * 4
    return out


def render_dat_toc_inc(entry_count: int = len(FIXED_SLOTS)) -> str:
    """Render sjasmplus dat_toc.inc with DAT_ID_* and header layout constants (0xNN hex)."""
    lines = [
        "; Generated by tools/make_cpm_dat.py. Do not edit.",
        "; 'M8CP' MORIA8.DAT container TOC constants and fixed slot IDs.",
        "",
        "    IFNDEF DAT_TOC_INC",
        "    DEFINE DAT_TOC_INC 1",
        "DAT_MAGIC_0 EQU 0x4d             ; 'M'",
        "DAT_MAGIC_1 EQU 0x38             ; '8'",
        "DAT_MAGIC_2 EQU 0x43             ; 'C'",
        "DAT_MAGIC_3 EQU 0x50             ; 'P'",
        f"DAT_FORMAT_VERSION EQU {DAT_VERSION}",
        f"DAT_CPM_RECORD_SIZE EQU {CPM_REC_SIZE}",
        "    IFNDEF DAT_HEADER_RECORDS_DEFINED",
        "    DEFINE DAT_HEADER_RECORDS_DEFINED 1",
        f"DAT_HEADER_RECORDS EQU {DAT_HEADER_RECS}",
        "    ENDIF",
        "    IFNDEF DAT_HEADER_BYTES_DEFINED",
        "    DEFINE DAT_HEADER_BYTES_DEFINED 1",
        f"DAT_HEADER_BYTES EQU {DAT_HEADER_BYTES}",
        "    ENDIF",
        "    IFNDEF DAT_VERSION_DEFINED",
        "    DEFINE DAT_VERSION_DEFINED 1",
        f"DAT_VERSION EQU {DAT_VERSION}",
        "    ENDIF",
        "    IFNDEF DAT_MAX_ENTRIES_DEFINED",
        "    DEFINE DAT_MAX_ENTRIES_DEFINED 1",
        f"DAT_MAX_ENTRIES EQU {DAT_MAX_ENTRIES}",
        "    ENDIF",
        f"DAT_ENTRY_SIZE EQU {DAT_ENTRY_SIZE}",
        f"DAT_TOC_OFFSET EQU {DAT_TOC_OFFSET}",
        f"DAT_ENTRY_COUNT EQU {entry_count}",
        "",
        "; 6-byte directory entry field offsets",
        "DAT_OFF_START_REC EQU 0          ; uint16 LE: first 128 B CP/M record (>= 2)",
        "DAT_OFF_REC_COUNT EQU 2          ; uint16 LE: 128 B record count (0 = absent)",
        "DAT_OFF_BYTE_LEN EQU 4           ; uint16 LE: exact payload length in bytes",
        "",
        "; Fixed slot IDs",
        *[f"{slot.const_name} EQU {slot.slot_id}" for slot in FIXED_SLOTS],
        f"DAT_ASSET_COUNT EQU {len(FIXED_SLOTS)}",
        "    ENDIF",
        "",
    ]
    return "\n".join(lines)


def _parse_slot_overrides(raw_specs: list[str]) -> dict[int, Path]:
    overrides: dict[int, Path] = {}
    for item in raw_specs:
        if "=" not in item:
            raise ValueError(f"Expected SLOT=PATH, got {item!r}")
        key, path_str = item.split("=", 1)
        key_clean = key.strip()
        if key_clean.isdigit() or key_clean.lower().startswith("0x"):
            slot_id = int(key_clean, 0)
        elif key_clean in SLOT_BY_NAME:
            slot_id = SLOT_BY_NAME[key_clean]
        else:
            raise ValueError(f"Unknown slot identifier {key_clean!r}")
        if not (0 <= slot_id < DAT_MAX_ENTRIES):
            raise ValueError(f"Slot ID {slot_id} out of range 0..{DAT_MAX_ENTRIES - 1}")
        overrides[slot_id] = Path(path_str)
    return overrides


def _resolve_slot_path(
    slot: DatSlotSpec,
    assets_dir: Path,
    ovl_dir: Path,
    overrides: dict[int, Path],
) -> Path | None:
    if slot.slot_id in overrides:
        p = overrides[slot.slot_id]
        return p if p.is_file() else None
    search_dir = ovl_dir if slot.is_overlay else assets_dir
    for name in slot.candidates:
        cand = search_dir / name
        if cand.is_file():
            return cand
    return None


def pack_from_dirs(
    out_dat: Path,
    out_inc: Path,
    assets_dir: Path,
    ovl_dir: Path,
    overrides: dict[int, Path] | None = None,
    allow_missing_overlays: bool = False,
) -> tuple[bytes, list[dict[str, int]]]:
    """Resolve slot inputs, pack MORIA8.DAT, verify unpack, and write dat_toc.inc."""
    overrides = overrides or {}
    max_slot = max([s.slot_id for s in FIXED_SLOTS] + list(overrides.keys()))
    payloads: list[bytes | None] = [None] * (max_slot + 1)

    for slot in FIXED_SLOTS:
        path = _resolve_slot_path(slot, assets_dir, ovl_dir, overrides)
        if path is None:
            if slot.is_overlay and allow_missing_overlays and slot.slot_id not in overrides:
                payloads[slot.slot_id] = None
                continue
            expected = overrides.get(slot.slot_id) or (
                (ovl_dir if slot.is_overlay else assets_dir) / slot.candidates[0]
            )
            raise FileNotFoundError(f"Missing required slot {slot.slot_id} ({slot.const_name}): {expected}")
        data = path.read_bytes()
        if len(data) == 0:
            raise ValueError(f"Empty 0-byte file for slot {slot.slot_id} ({slot.const_name}): {path}")
        payloads[slot.slot_id] = data

    for slot_id, path in overrides.items():
        if slot_id >= len(FIXED_SLOTS):
            if not path.is_file():
                raise FileNotFoundError(f"Missing extra slot {slot_id}: {path}")
            data = path.read_bytes()
            if len(data) == 0:
                raise ValueError(f"Empty 0-byte file for extra slot {slot_id}: {path}")
            payloads[slot_id] = data

    dat_bytes, entries = pack_cpm_dat(payloads)
    unpacked = unpack_cpm_dat(dat_bytes)
    for slot_id, payload in enumerate(payloads):
        expected = payload or b""
        assert unpacked[slot_id]["payload"] == expected, f"Roundtrip mismatch for slot {slot_id}"

    out_dat.parent.mkdir(parents=True, exist_ok=True)
    out_dat.write_bytes(dat_bytes)
    out_inc.parent.mkdir(parents=True, exist_ok=True)
    out_inc.write_text(render_dat_toc_inc(len(payloads)), encoding="utf-8")
    return dat_bytes, entries


def _find_sjasmplus() -> Path | None:
    env_bin = os.environ.get("SJASMPLUS", "").strip()
    if env_bin:
        p = Path(env_bin)
        if p.is_file():
            return p
        which_env = shutil.which(env_bin)
        if which_env:
            return Path(which_env)
        raise FileNotFoundError(f"SJASMPLUS={env_bin!r} not found")
    if DEFAULT_SJASMPLUS.is_file():
        return DEFAULT_SJASMPLUS
    which = shutil.which("sjasmplus")
    return Path(which) if which else None


def run_selftest() -> int:
    """Run offline self-tests for MORIA8.DAT packing, missing overlays, and dat_toc.inc."""
    sys.path.insert(0, str(TOOLS_DIR))
    import build_z80_assets as bza  # noqa: E402

    dollar_hex_re = re.compile(r"(^|[^A-Za-z0-9_])\$[0-9A-Fa-f]+")

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        assets_dir = tmp / "assets"
        ovl_dir = tmp / "ovls"
        assets_dir.mkdir()
        ovl_dir.mkdir()

        bza.generate_all(assets_dir)

        # 1. Early-milestone pack with --allow-missing-overlays (0 overlays present, 6 data assets packed).
        dat_partial = tmp / "partial.dat"
        inc_partial = tmp / "dat_toc.inc"
        blob_p, entries_p = pack_from_dirs(
            dat_partial,
            inc_partial,
            assets_dir,
            ovl_dir,
            allow_missing_overlays=True,
        )
        assert len(blob_p) % CPM_REC_SIZE == 0
        assert blob_p[0:4] == b"M8CP" and blob_p[4] == 1 and blob_p[5] == 25
        for s in FIXED_SLOTS:
            if s.is_overlay:
                assert entries_p[s.slot_id]["start_rec"] == 0 and entries_p[s.slot_id]["rec_count"] == 0
        assert entries_p[14]["start_rec"] == 2
        assert entries_p[14]["byte_len"] == 17920 and entries_p[14]["rec_count"] == 140
        unpacked_p = unpack_cpm_dat(blob_p)
        assert unpacked_p[14]["payload"] == (assets_dir / "monster_cat_ascii.bin").read_bytes()
        assert unpacked_p[15]["payload"] == (assets_dir / "item_cat_ascii.bin").read_bytes()
        assert unpacked_p[16]["payload"] == (assets_dir / "huff_stream.bin").read_bytes()
        assert unpacked_p[17]["payload"] == (assets_dir / "title_art.bin").read_bytes()
        assert unpacked_p[18]["payload"] == (assets_dir / "license.txt").read_bytes()
        assert unpacked_p[19]["payload"] == (assets_dir / "srcoffr.txt").read_bytes()

        # 2. Missing overlays without --allow-missing-overlays must raise FileNotFoundError.
        missing_caught = False
        try:
            pack_from_dirs(tmp / "fail.dat", inc_partial, assets_dir, ovl_dir, allow_missing_overlays=False)
        except FileNotFoundError:
            missing_caught = True
        assert missing_caught, "Expected FileNotFoundError when overlays missing without flag"

        # 2b. Existing 0-byte file must raise ValueError (even with --allow-missing-overlays).
        empty_ovl = ovl_dir / FIXED_SLOTS[0].candidates[0]
        empty_ovl.write_bytes(b"")
        empty_caught = False
        try:
            pack_from_dirs(tmp / "empty.dat", inc_partial, assets_dir, ovl_dir, allow_missing_overlays=True)
        except ValueError:
            empty_caught = True
        assert empty_caught, "Expected ValueError for existing 0-byte overlay file"
        empty_ovl.unlink()

        # 3. Full 25-slot pack with synthetic overlays (0..13 and 20..24, non-multiple-of-128 lengths).
        expected_ovls: dict[int, bytes] = {}
        for slot in FIXED_SLOTS:
            if not slot.is_overlay:
                continue
            payload = bytes(((slot.slot_id * 37 + i) & 0xFF) for i in range(100 + slot.slot_id * 17))
            (ovl_dir / slot.candidates[0]).write_bytes(payload)
            expected_ovls[slot.slot_id] = payload

        dat_full = tmp / "MORIA8.DAT"
        blob_f, entries_f = pack_from_dirs(
            dat_full,
            inc_partial,
            assets_dir,
            ovl_dir,
            allow_missing_overlays=False,
        )
        unpacked_f = unpack_cpm_dat(blob_f)
        for slot_id, exp_bytes in expected_ovls.items():
            assert unpacked_f[slot_id]["payload"] == exp_bytes
            assert entries_f[slot_id]["start_rec"] >= 2
            assert entries_f[slot_id]["byte_len"] == len(exp_bytes)

        # 4. Capacity & record-limit guards (> 41 entries, > 255 recs on data slot, > 40 recs on overlay slots).
        cap_caught = False
        try:
            pack_cpm_dat([b"x"] * 42)
        except ValueError:
            cap_caught = True
        assert cap_caught, "Expected ValueError for > 41 entries"

        # Exactly 255 records (32,640 B) on non-overlay slot 14 succeeds; 256 records (32,641 B) fails.
        ok_data_slots: list[bytes | None] = [None] * 25
        ok_data_slots[14] = b"\x55" * (DAT_MAX_REC_COUNT * CPM_REC_SIZE)
        ok_data_blob, _ = pack_cpm_dat(ok_data_slots)
        assert unpack_cpm_dat(ok_data_blob)[14]["rec_count"] == DAT_MAX_REC_COUNT

        bad_data_slots: list[bytes | None] = [None] * 25
        bad_data_slots[14] = b"\x55" * (DAT_MAX_REC_COUNT * CPM_REC_SIZE + 1)
        data_ovf_caught = False
        try:
            pack_cpm_dat(bad_data_slots)
        except ValueError:
            data_ovf_caught = True
        assert data_ovf_caught, "Expected ValueError for > 255 records on data slot"

        # Exactly 40 records (5,120 B) on overlay slot succeeds; 41 records (5,121 B) fails (for 0..13 and 20..24).
        ok_ovl_slots: list[bytes | None] = [None] * 25
        ok_ovl_slots[0] = b"\xAA" * (OVL_MAX_RECORDS * CPM_REC_SIZE)
        ok_ovl_slots[24] = b"\xBB" * (OVL_MAX_RECORDS * CPM_REC_SIZE)
        ok_ovl_blob, _ = pack_cpm_dat(ok_ovl_slots)
        ok_ovl_unpacked = unpack_cpm_dat(ok_ovl_blob)
        assert ok_ovl_unpacked[0]["rec_count"] == OVL_MAX_RECORDS
        assert ok_ovl_unpacked[24]["rec_count"] == OVL_MAX_RECORDS

        for ovl_slot_id in (0, 13, 20, 24):
            bad_ovl_slots: list[bytes | None] = [None] * 25
            bad_ovl_slots[ovl_slot_id] = b"\xAA" * (OVL_MAX_RECORDS * CPM_REC_SIZE + 1)
            ovl_ovf_caught = False
            try:
                pack_cpm_dat(bad_ovl_slots)
            except ValueError:
                ovl_ovf_caught = True
            assert ovl_ovf_caught, f"Expected ValueError for > 40 records on overlay slot {ovl_slot_id}"

        # 5. Verify dat_toc.inc has zero '$' hex literals, --emit-inc-only works, and assembles cleanly under sjasmplus.
        only_inc = tmp / "only_dat_toc.inc"
        assert main(["--emit-inc-only", "--out-inc", str(only_inc)]) == 0
        assert only_inc.read_text(encoding="utf-8") == render_dat_toc_inc(len(FIXED_SLOTS))

        toc_txt = inc_partial.read_text(encoding="utf-8")
        for lineno, line in enumerate(toc_txt.splitlines(), start=1):
            assert not dollar_hex_re.search(line), f"dat_toc.inc:{lineno} contains '$': {line!r}"

        sjasm = _find_sjasmplus()
        if sjasm is not None:
            test_asm = tmp / "test_dat_toc.asm"
            test_asm.write_text(
                "\n".join([
                    "    DEVICE NOSLOT64K",
                    "    ORG 0x0100",
                    '    INCLUDE "dat_toc.inc"',
                    '    INCLUDE "dat_toc.inc"',
                    "    ASSERT DAT_ID_OVL_START == 0",
                    "    ASSERT DAT_ID_OVL_TITLE == 12",
                    "    ASSERT DAT_ID_OVL_LEGAL == 13",
                    "    ASSERT DAT_ID_MONSTER_CAT == 14",
                    "    ASSERT DAT_ID_ITEM_CAT == 15",
                    "    ASSERT DAT_ID_HUFF_STREAM == 16",
                    "    ASSERT DAT_ID_TITLE_ART == 17",
                    "    ASSERT DAT_ID_LICENSE == 18",
                    "    ASSERT DAT_ID_SRCOFFR == 19",
                    "    ASSERT DAT_ID_OVL_ITEMS_EFF == 20",
                    "    ASSERT DAT_ID_OVL_SPELL_EFF == 21",
                    "    ASSERT DAT_ID_OVL_ACTIONS == 22",
                    "    ASSERT DAT_ID_OVL_MON_EXT == 23",
                    "    ASSERT DAT_ID_OVL_ITEM_MGT == 24",
                    "    ASSERT DAT_ENTRY_COUNT == 25",
                    "    ASSERT DAT_MAX_ENTRIES == 41",
                    "    ASSERT DAT_HEADER_BYTES == 256",
                    "",
                ]),
                encoding="utf-8",
            )
            res = subprocess.run(
                [str(sjasm), "--syntax=abfw", f"-I{tmp}", f"--raw={tmp}/test_dat_toc.bin", str(test_asm)],
                capture_output=True,
                text=True,
                check=False,
            )
            assert res.returncode == 0, f"sjasmplus failed on dat_toc.inc:\n{res.stderr}"

            cpm_dir = REPO_ROOT / "platforms" / "z80" / "cpm"
            if (cpm_dir / "memory.inc").is_file():
                for order_name, first_inc, second_inc in (
                    ("mem_then_toc", "memory.inc", "dat_toc.inc"),
                    ("toc_then_mem", "dat_toc.inc", "memory.inc"),
                ):
                    combo_asm = tmp / f"test_{order_name}.asm"
                    combo_asm.write_text(
                        "\n".join([
                            "    DEVICE NOSLOT64K",
                            "    ORG 0x0100",
                            f'    INCLUDE "{first_inc}"',
                            f'    INCLUDE "{second_inc}"',
                            "    ASSERT DAT_ID_SRCOFFR == 19",
                            "    ASSERT DAT_ID_OVL_ITEM_MGT == 24",
                            "    ASSERT DAT_MAX_ENTRIES == 41",
                            "    ASSERT DAT_HEADER_BYTES == 256",
                            "    ASSERT DAT_HEADER_RECORDS == 2",
                            "    ASSERT DAT_VERSION == 1",
                            "",
                        ]),
                        encoding="utf-8",
                    )
                    res_combo = subprocess.run(
                        [str(sjasm), "--nologo", f"-I{cpm_dir}", f"-I{tmp}", f"--raw={tmp}/{order_name}.bin", str(combo_asm)],
                        capture_output=True,
                        text=True,
                        check=False,
                    )
                    assert res_combo.returncode == 0, (
                        f"sjasmplus failed on {order_name} ({first_inc} -> {second_inc}):\n{res_combo.stderr}"
                    )

    print(
        f"make_cpm_dat selftest PASSED: partial={len(blob_p)} B ({len(blob_p)//128} recs), "
        f"full_25={len(blob_f)} B ({len(blob_f)//128} recs), max_entries={DAT_MAX_ENTRIES}"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR, help="Default output/input directory (build/cpm)")
    parser.add_argument("--assets-dir", type=Path, default=None, help="Directory with generated Z80 binary assets")
    parser.add_argument("--ovl-dir", type=Path, default=None, help="Directory with built .ovl binaries")
    parser.add_argument("--out-dat", type=Path, default=None, help="Output MORIA8.DAT path")
    parser.add_argument("--out-inc", type=Path, default=None, help="Output dat_toc.inc path")
    parser.add_argument("--slot", action="append", default=[], metavar="SLOT=PATH", help="Explicit slot override")
    parser.add_argument("--allow-missing-overlays", action="store_true", help="Zero-fill missing overlay slots (0..13, 20..24)")
    parser.add_argument("--emit-inc-only", action="store_true", help="Emit dat_toc.inc without packing MORIA8.DAT")
    parser.add_argument("--selftest", action="store_true", help="Run offline MORIA8.DAT packer self-test")
    args = parser.parse_args(argv)

    if args.selftest:
        return run_selftest()

    out_dir = args.out_dir
    out_inc = args.out_inc or (out_dir / "dat_toc.inc")
    if args.emit_inc_only:
        out_inc.parent.mkdir(parents=True, exist_ok=True)
        out_inc.write_text(render_dat_toc_inc(), encoding="utf-8")
        print(f"make_cpm_dat: wrote {out_inc}")
        return 0

    assets_dir = args.assets_dir or out_dir
    ovl_dir = args.ovl_dir or out_dir
    out_dat = args.out_dat or (out_dir / "MORIA8.DAT")
    overrides = _parse_slot_overrides(args.slot)

    blob, entries = pack_from_dirs(
        out_dat,
        out_inc,
        assets_dir,
        ovl_dir,
        overrides=overrides,
        allow_missing_overlays=args.allow_missing_overlays,
    )
    present = sum(1 for e in entries if e["rec_count"] > 0)
    print(
        f"make_cpm_dat: wrote {out_dat} ({len(blob)} B, {len(blob)//CPM_REC_SIZE} recs, "
        f"{present}/{len(entries)} slots populated) and {out_inc}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
