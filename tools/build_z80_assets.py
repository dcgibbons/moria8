#!/usr/bin/env python3
"""Generate pure 7-bit ASCII Z80/CP/M assets and sjasmplus .inc files for Moria8.

Consumes in-repo data and catalog specs (zero hardcoded host paths):
  - data/huffman_strings.txt
  - platforms/shared/catalog/monster_catalog_spec.json
  - platforms/shared/item_catalog/item_catalog_spec.json
  - data/LICENSE
  - data/SOURCE-OFFER
  - version.json

Emits into --out-dir (default: build/cpm):
  - huff_ascii.inc, huff_stream.bin
  - monster_cat_ascii.bin, monster_idx_z80.inc
  - item_cat_ascii.bin, item_ids_z80.inc, item_cat_layout_z80.inc, item_hot_tables_z80.inc, item_cat_pinned_z80.inc
  - title_art.bin
  - license.txt, srcoffr.txt
  - version_z80.inc
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
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
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import build_catalog as bc  # noqa: E402
import build_item_catalog as bic  # noqa: E402
import huff_encoder as huff  # noqa: E402
import parse_creatures as pc  # noqa: E402
import version_info  # noqa: E402

DEFAULT_OUT_DIR = REPO_ROOT / "build" / "cpm"
DEFAULT_HUFFMAN_TXT = REPO_ROOT / "data" / "huffman_strings.txt"
DEFAULT_MONSTER_SPEC = REPO_ROOT / "platforms" / "shared" / "catalog" / "monster_catalog_spec.json"
DEFAULT_ITEM_SPEC = REPO_ROOT / "platforms" / "shared" / "item_catalog" / "item_catalog_spec.json"
DEFAULT_LICENSE = REPO_ROOT / "data" / "LICENSE"
DEFAULT_SOURCE_OFFER = REPO_ROOT / "data" / "SOURCE-OFFER"
DEFAULT_VERSION_JSON = REPO_ROOT / "version.json"
DEFAULT_SJASMPLUS = TOOLS_DIR / "sjasmplus" / "sjasmplus"

CPM_RECORD_SIZE = 128
MONSTER_RECS_PER_CPM_REC = 2
MONSTER_CPM_RECORDS = -(-bc.CREATURE_COUNT // MONSTER_RECS_PER_CPM_REC)  # 140
HUFF_TREE_STRIDE = 64

# Logical 16-color C64-compatible palette indices mapped to ANSI SGR on CP/M.
TC_BLACK = 0x00
TC_WHITE = 0x01
TC_CYAN = 0x03
TC_YELLOW = 0x07
TC_DGREY = 0x0B
TC_LGREY = 0x0F

TITLE_ROWS = 24
TITLE_COLS = 80
TITLE_BOX_COL = 21
TITLE_BOX_WIDTH = 38
TITLE_INNER_COL = TITLE_BOX_COL + 1
TITLE_INNER_WIDTH = TITLE_BOX_WIDTH - 2

TITLE_MORIA8_ART: tuple[str, ...] = (
    "#   #  ###  ####  ###   ##   ###",
    "## ##  # #  #  #   #   #  #  # #",
    "# # #  # #  ####   #   ####  ###",
    "#   #  # #  ##     #   #  #  # #",
    "#   #  ###  # ##  ###  #  #  ###",
)


def assert_printable_ascii_text(text: str, context: str) -> bytes:
    """Validate and encode text strictly as printable 7-bit ASCII (0x20..0x7E)."""
    raw = text.encode("ascii")
    for idx, b in enumerate(raw):
        if not (0x20 <= b <= 0x7E):
            raise ValueError(f"{context}: non-printable ASCII byte 0x{b:02x} at offset {idx} in {text!r}")
    return raw


def sjasm_db_rows(vals: list[int], width: int = 16, comments: list[str] | None = None) -> list[str]:
    """Format byte values as indented sjasmplus DB lines using 0xNN hex literals."""
    if comments is not None:
        return [f"    DB 0x{v:02x}  ; {c}" for v, c in zip(vals, comments)]
    return [
        "    DB " + ", ".join(f"0x{v:02x}" for v in vals[k : k + width])
        for k in range(0, len(vals), width)
    ]


def sjasm_dw_rows(vals: list[int], comments: list[str] | None = None) -> list[str]:
    """Format 16-bit word values as indented sjasmplus DW lines using 0xNNNN hex literals."""
    if comments is not None:
        return [f"    DW 0x{v:04x}  ; {c}" for v, c in zip(vals, comments)]
    return [f"    DW 0x{v:04x}" for v in vals]


# ---------------------------------------------------------------------------
# (a) Huffman ASCII corpus
# ---------------------------------------------------------------------------

def parse_huffman_strings(input_path: Path) -> tuple[list[str], dict[int, str]]:
    """Parse data/huffman_strings.txt with exact huff_encoder.py rules."""
    raw_lines = input_path.read_text(encoding="utf-8").splitlines()
    texts: list[str] = []
    labels: dict[int, str] = {}

    for raw in raw_lines:
        line = raw.rstrip("\n\r")
        check = line.strip()
        if not check or check.startswith("#"):
            continue
        trimmed = line.lstrip()
        if trimmed.startswith("@"):
            space_pos = trimmed.index(" ")
            label = trimmed[1:space_pos]
            text = trimmed[space_pos + 1 :]
        else:
            label = None
            text = trimmed

        if text.endswith(" ~"):
            text = text[:-1]

        assert_printable_ascii_text(text, f"huffman string #{len(texts)}")
        idx = len(texts)
        texts.append(text)
        if label:
            labels[idx] = label

    return texts, labels


def decode_huffman_string(
    left_table: list[int],
    right_table: list[int],
    stream_bytes: bytes,
    byte_offset: int,
) -> bytes:
    """Decode one MSB-first NUL-terminated Huffman string from tree + stream."""
    out = bytearray()
    pos = byte_offset
    bit_mask = 0
    cur_byte = 0
    node_count = len(left_table)

    while True:
        node = 0
        while True:
            if bit_mask == 0:
                if pos >= len(stream_bytes):
                    raise ValueError(f"Huffman stream EOF at offset {pos}")
                cur_byte = stream_bytes[pos]
                pos += 1
                bit_mask = 0x80
            bit = cur_byte & bit_mask
            bit_mask >>= 1
            if node >= node_count:
                raise ValueError(f"Invalid internal Huffman node index {node} >= {node_count}")
            nxt = right_table[node] if bit else left_table[node]
            if nxt & 0x80:
                ch = nxt & 0x7F
                if ch == 0:
                    return bytes(out)
                if not (0x20 <= ch <= 0x7E):
                    raise ValueError(f"Decoded non-ASCII Huffman leaf 0x{ch:02x}")
                out.append(ch)
                break
            node = nxt


def build_huffman_ascii_assets(input_path: Path) -> dict[str, object]:
    """Build huff_ascii.inc and huff_stream.bin in pure 7-bit ASCII."""
    texts, labels = parse_huffman_strings(input_path)
    ascii_lists = [list(assert_printable_ascii_text(t, f"huffman[{i}]")) for i, t in enumerate(texts)]

    freq: Counter[int] = Counter()
    for bs in ascii_lists:
        freq.update(bs)
        freq[0x00] += 1

    root = huff.build_tree(freq)
    codes = huff.build_codes(root)
    left_table, right_table = huff.flatten_tree(root)

    assert len(left_table) == len(right_table) < 0x7F, (
        f"Huffman tree has {len(left_table)} internal nodes (must be < 127)"
    )
    assert len(left_table) <= HUFF_TREE_STRIDE, (
        f"Huffman tree has {len(left_table)} internal nodes (exceeds {HUFF_TREE_STRIDE}-byte stride)"
    )
    for b in left_table + right_table:
        if b & 0x80:
            leaf = b & 0x7F
            assert leaf == 0 or (0x20 <= leaf <= 0x7E), f"Leaf 0x{leaf:02x} not NUL or printable ASCII"
        else:
            assert 0 <= b < len(left_table), f"Node child {b} out of range"

    compressed_chunks: list[list[int]] = []
    offsets: list[int] = []
    stream_buf = bytearray()
    total_uncompressed = 0
    for bs in ascii_lists:
        offsets.append(len(stream_buf))
        chunk, _bits = huff.compress_string(bs, codes)
        compressed_chunks.append(chunk)
        stream_buf.extend(chunk)
        total_uncompressed += len(bs) + 1

    stream_bytes = bytes(stream_buf)
    assert len(stream_bytes) < 0x10000, f"Huffman stream {len(stream_bytes)} overflows 16-bit offset"

    # Byte-for-byte decode verification for every string.
    for i, text in enumerate(texts):
        decoded = decode_huffman_string(left_table, right_table, stream_bytes, offsets[i])
        expected = text.encode("ascii")
        assert decoded == expected, f"Huffman roundtrip mismatch [{i}]: {decoded!r} != {expected!r}"

    first_labeled = next((i for i in range(len(texts)) if i in labels), len(texts))
    node_count = len(left_table)

    inc_lines = [
        "; Generated by tools/build_z80_assets.py from data/huffman_strings.txt. Do not edit.",
        f"; {len(texts)} strings, {total_uncompressed} B uncompressed -> {len(stream_bytes)} B stream, {node_count} nodes",
        "",
        "    IFNDEF HUFF_ASCII_CONSTS_INCLUDED",
        "    DEFINE HUFF_ASCII_CONSTS_INCLUDED 1",
        f"HUFF_STR_COUNT EQU {len(texts)}",
        f"HSTR_INSULT_COUNT EQU {first_labeled}",
        f"HUFF_NODE_COUNT EQU {node_count}",
        f"HUFF_TREE_STRIDE EQU {HUFF_TREE_STRIDE}",
        f"HUFF_STREAM_SIZE EQU {len(stream_bytes)}",
        "",
        "; Named string constants",
    ]
    for idx in sorted(labels):
        inc_lines.append(f"HSTR_{labels[idx]} EQU {idx}")
    inc_lines.extend([
        "    ENDIF",
        "",
        "    IFNDEF HUFF_CONSTS_ONLY",
        "    IFNDEF HUFF_NO_TREE",
        "    IFNDEF HUFF_ASCII_TREE_INCLUDED",
        "    DEFINE HUFF_ASCII_TREE_INCLUDED 1",
        f"; Huffman tree: {node_count} internal nodes, page-aligned with +{HUFF_TREE_STRIDE} stride",
        "; Children: 0x00..0x7E = node index, 0x80+ = leaf (& 0x7F = ASCII byte, 0x80 = NUL)",
        "    ALIGN 256",
        "huff_tree_left:",
        *sjasm_db_rows(left_table),
        f"    ASSERT HUFF_NODE_COUNT <= {HUFF_TREE_STRIDE}",
        "    ASSERT (huff_tree_left & 0xFF) == 0",
        *([f"    DS {HUFF_TREE_STRIDE} - {node_count}, 0"] if node_count < HUFF_TREE_STRIDE else []),
        "huff_tree_right:",
        *sjasm_db_rows(right_table),
        f"    ASSERT huff_tree_right == huff_tree_left + {HUFF_TREE_STRIDE}",
        "    ENDIF",
        "    ENDIF",
        "",
        "    IFNDEF HUFF_NO_INDEX",
        "    IFNDEF HUFF_ASCII_INDEX_INCLUDED",
        "    DEFINE HUFF_ASCII_INDEX_INCLUDED 1",
        "; String index: 16-bit byte offsets into huff_stream.bin / huff_str_data",
        "huff_str_index:",
        *sjasm_dw_rows(
            offsets,
            comments=[
                f"[{i}]{(' @' + labels[i]) if i in labels else ''} \"{texts[i][:30]}\""
                for i in range(len(texts))
            ],
        ),
        "huff_str_index_end:",
        "    ENDIF",
        "    ENDIF",
        "    ENDIF",
        "",
        "    IFDEF HUFF_INCLUDE_STREAM",
        "    IFNDEF HUFF_ASCII_STREAM_INCLUDED",
        "    DEFINE HUFF_ASCII_STREAM_INCLUDED 1",
        "huff_str_data:",
    ])
    for i, chunk in enumerate(compressed_chunks):
        inc_lines.append(f"    ; [{i}] \"{texts[i]}\" ({len(ascii_lists[i]) + 1} -> {len(chunk)} bytes)")
        inc_lines.extend(sjasm_db_rows(chunk))
    inc_lines.extend([
        "huff_str_data_end:",
        "    ENDIF",
        "    ENDIF",
        "",
    ])

    return {
        "huff_ascii_inc": "\n".join(inc_lines),
        "huff_stream_bin": stream_bytes,
        "left_table": left_table,
        "right_table": right_table,
        "offsets": offsets,
        "string_count": len(texts),
        "node_count": node_count,
        "stream_size": len(stream_bytes),
    }


# ---------------------------------------------------------------------------
# (b) Monster Catalog (Phase 5 57 B records in pure 7-bit ASCII)
# ---------------------------------------------------------------------------

def build_monster_ascii_assets(spec_path: Path) -> dict[str, object]:
    """Build 140-record monster_cat_ascii.bin (17,920 B) and monster_idx_z80.inc."""
    spec_doc = bc.load_spec(spec_path)
    creatures = spec_doc["creatures"]
    assert len(creatures) == bc.CREATURE_COUNT

    records: list[bytes] = []
    for n, sc in enumerate(creatures):
        assert sc["index"] == n
        core = bc.phase5_core_row(sc)
        cchar = sc["cchar"]
        assert len(cchar) == 1 and pc.char_to_screencode(cchar) == core["cr_display"], (
            f"Monster #{n} cchar {cchar!r} != screencode {core['cr_display']}"
        )
        ascii_glyph = ord(cchar)
        assert 0x20 <= ascii_glyph <= 0x7E
        core["cr_display"] = ascii_glyph

        ext = bc.phase5_ext_row(sc)
        fields = [core[k] for k in bc.CORE_FIELD_KEYS] + ext
        assert len(fields) == 29 and all(0 <= b < 256 for b in fields)

        name_bytes = assert_printable_ascii_text(sc["moria8_name"], f"monster[{n}] moria8_name")
        assert len(name_bytes) <= bc.CATALOG_NAME_MAX, (n, len(name_bytes))
        name_padded = name_bytes + b"\x00" * (26 - len(name_bytes))

        rec = struct.pack("<H", n) + bytes(fields) + name_padded
        assert len(rec) == bc.PHASE5_RECORD_SIZE == 57
        records.append(rec)

    # Pack 2 x 57 B = 114 B per 128 B CP/M record -> 140 records = 17,920 B (0 straddles).
    out = bytearray()
    for sec in range(MONSTER_CPM_RECORDS):
        chunk = b"".join(
            records[sec * MONSTER_RECS_PER_CPM_REC : (sec + 1) * MONSTER_RECS_PER_CPM_REC]
        )
        assert len(chunk) <= CPM_RECORD_SIZE
        out.extend(chunk)
        out.extend(b"\x00" * (CPM_RECORD_SIZE - len(chunk)))
    monster_bin = bytes(out)
    assert len(monster_bin) == MONSTER_CPM_RECORDS * CPM_RECORD_SIZE == 17920

    # Round-trip verify all 279 records from packed CP/M records.
    for n, sc in enumerate(creatures):
        rec_off = (n >> 1) * CPM_RECORD_SIZE + (n & 1) * bc.PHASE5_RECORD_SIZE
        rec = monster_bin[rec_off : rec_off + bc.PHASE5_RECORD_SIZE]
        assert struct.unpack_from("<H", rec, 0)[0] == n
        assert rec[2] == ord(sc["cchar"])
        exp_core = bc.phase5_core_row(sc)
        exp_core["cr_display"] = ord(sc["cchar"])
        exp_fields = bytes([exp_core[k] for k in bc.CORE_FIELD_KEYS] + bc.phase5_ext_row(sc))
        assert rec[2:31] == exp_fields
        nul = rec[31:57].index(0)
        assert rec[31 : 31 + nul].decode("ascii") == sc["moria8_name"]
        assert all(b == 0 for b in rec[31 + nul : 57])

    win = set(range(bc.CREATURE_COUNT - bc.WIN_MON_TOT, bc.CREATURE_COUNT))
    raw_counts = [
        sum(1 for i, c in enumerate(creatures) if c["level"] == lvl and i not in win)
        for lvl in range(bc.MAX_MONS_LEVEL + 1)
    ]
    playable_counts = list(raw_counts)
    undead_bmp = bc.undead_bitmap(creatures)

    field_offsets: list[tuple[str, int]] = []
    off = 2
    for key in bc.CORE_FIELD_KEYS:
        field_offsets.append((f"CAT_REC_{key.upper()}", off))
        off += 1
    for label in bc.EXT_FIELD_LABELS:
        short = label[len("cat_") :].upper()
        field_offsets.append((f"CAT_REC_CR_{short}", off))
        off += 1
    assert off == 31

    idx_lines = [
        "; Generated by tools/build_z80_assets.py from monster_catalog_spec.json. Do not edit.",
        "; Phase 5 CP/M monster catalog constants and resident level/undead index.",
        "",
        "    IFNDEF MONSTER_IDX_CONSTS_INCLUDED",
        "    DEFINE MONSTER_IDX_CONSTS_INCLUDED 1",
        f"CATALOG_COUNT EQU {bc.CREATURE_COUNT}",
        f"CATALOG_SOA_FIELDS EQU {len(bc.CORE_FIELD_KEYS)}",
        f"CATALOG_EXT_FIELDS EQU {bc.EXT_SOA_FIELD_COUNT}",
        f"CATALOG_TOTAL_FIELDS EQU {len(bc.CORE_FIELD_KEYS) + bc.EXT_SOA_FIELD_COUNT}",
        f"CATALOG_RECORD_SIZE EQU {bc.PHASE5_RECORD_SIZE}",
        "CATALOG_RECORD_CORE_OFF EQU 2",
        "CATALOG_RECORD_EXT_OFF EQU 23",
        "CATALOG_RECORD_NAME EQU 31",
        "CATALOG_RECORD_NAME_SIZE EQU 26",
        f"CATALOG_RECORDS_PER_CPM_REC EQU {MONSTER_RECS_PER_CPM_REC}",
        f"CATALOG_CPM_REC_COUNT EQU {MONSTER_CPM_RECORDS}",
        f"CATALOG_TOWN_COUNT EQU {raw_counts[0]}",
        f"CATALOG_WIN_FIRST EQU {min(win)}",
        f"CATALOG_IGGY_ID EQU {next(i for i in win if creatures[i]['name'] == 'Evil Iggy')}",
        f"CATALOG_BALROG_ID EQU {next(i for i in win if creatures[i]['name'] == 'Balrog')}",
        f"CATALOG_MAX_MONS_LEVEL EQU {bc.MAX_MONS_LEVEL}",
        f"CATALOG_NAME_MAX EQU {bc.CATALOG_NAME_MAX}",
        "",
        "; Field offsets within a 57-byte monster record (0..1 = uint16 LE catalog ID)",
        *[f"{sym} EQU {val}" for sym, val in field_offsets],
        "CAT_REC_NAME EQU 31",
        "    ENDIF",
        "",
        "    IFNDEF MONSTER_IDX_CONSTS_ONLY",
        "    IFNDEF MONSTER_IDX_TABLES_INCLUDED",
        "    DEFINE MONSTER_IDX_TABLES_INCLUDED 1",
        "cat_level_raw:      ; creatures per level 0-40, win creatures excluded",
        *sjasm_db_rows(raw_counts),
        "cat_level_playable: ; the same, playable creatures only",
        *sjasm_db_rows(playable_counts),
        "cat_undead:         ; bit i%8 of byte i/8: creature i has CD_UNDEAD",
        *sjasm_db_rows(undead_bmp),
        "catalog_index_end:",
        "    ENDIF",
        "    ENDIF",
        "",
    ]

    return {
        "monster_cat_ascii_bin": monster_bin,
        "monster_idx_z80_inc": "\n".join(idx_lines),
        "creature_count": len(creatures),
        "cpm_records": MONSTER_CPM_RECORDS,
    }


# ---------------------------------------------------------------------------
# (c) Item Catalog ('ITM2' in pure 7-bit ASCII)
# ---------------------------------------------------------------------------

def _text_to_ascii_codes(text: str) -> list[int]:
    """Encode item catalog string strictly to 7-bit printable ASCII bytes (< 0x80)."""
    codes = list(assert_printable_ascii_text(text, "item_catalog"))
    for code in codes:
        if not (1 <= code < 0x80):
            raise ValueError(f"ASCII byte 0x{code:02x} out of literal range for {text!r}")
    return codes


def _ascii_code_to_char(code: int) -> str:
    """Invert _text_to_ascii_codes for build_item_catalog.decode_item_cat."""
    if not (0x20 <= code <= 0x7E):
        raise ValueError(f"Invalid decoded ASCII byte: 0x{code:02x}")
    return chr(code)


def build_item_ascii_assets(spec_path: Path) -> dict[str, object]:
    """Build ASCII 'ITM2' item_cat_ascii.bin + sjasmplus .inc files via build_item_catalog.py."""
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    bic.validate_spec(spec)

    orig_t2s = bic.text_to_screencodes
    orig_s2c = bic.screencode_to_char
    try:
        bic.text_to_screencodes = _text_to_ascii_codes
        bic.screencode_to_char = _ascii_code_to_char
        blob, offsets = bic.build_item_cat(spec)
        bic.verify_roundtrip(spec, blob)
        decoded = bic.decode_item_cat(blob)
    finally:
        bic.text_to_screencodes = orig_t2s
        bic.screencode_to_char = orig_s2c

    assert len(blob) <= bic.ITMCAT_SIZE_CAP, f"ASCII ITEM.CAT {len(blob)} exceeds {bic.ITMCAT_SIZE_CAP}"
    assert len(decoded["items"]) == 361
    assert len(decoded["egos"]) == 55
    assert len(decoded["flavours"]) == 174
    # Confirm lowercase ASCII bytes are actually stored as ASCII (>= 0x61), not C64 screencodes (0x01..0x1A).
    canon_off = offsets["canon_syms"]
    canon_len = offsets["canon_syms_size"]
    canon_syms = blob[canon_off : canon_off + canon_len]
    assert ord("a") in canon_syms and not any(1 <= b <= 0x1A for b in canon_syms if b != 0), (
        "Canonical symbol table contains non-ASCII control codes instead of lowercase ASCII"
    )

    items = spec["items"]
    flavs = spec["flavours"]
    consts = spec["constants"]
    slugs = bic.compute_item_slugs(items)
    page_size = consts["PAGE_SIZE"]

    # 1. item_ids_z80.inc
    ids_lines = [
        "; Generated by tools/build_z80_assets.py from item_catalog_spec.json. Do not edit.",
        "; Symbolic item IDs, Base-255 slot_lo bytes, and page bits (0x00 / 0x40).",
        "",
        "    IFNDEF ITEM_IDS_Z80_INC",
        "    DEFINE ITEM_IDS_Z80_INC 1",
    ]
    for it in items:
        item_id = it["id"]
        slug = slugs[item_id]
        slot_lo = item_id if item_id < page_size else item_id - page_size
        page_bit = 0x00 if item_id < page_size else bic.ITEM_PAGE_BIT
        ids_lines.extend([
            f"; {it['name']} (cat={it['cat']}, tval={it['tval']}, subval={it['subval']}, vms_level={it['vms_level']})",
            f"ITEM_{slug} EQU {item_id}",
            f"ITEM_SLOT_{slug} EQU {slot_lo}",
            f"ITEM_PAGE_{slug} EQU 0x{page_bit:02x}",
        ])
    ids_lines.extend(["    ENDIF", ""])

    # 2. item_cat_layout_z80.inc
    cnts = offsets["counts"]
    layout_lines = [
        "; Generated by tools/build_z80_assets.py from item_catalog_spec.json. Do not edit.",
        "; Binary 'ITM2' ASCII ITEM.CAT layout constants.",
        "",
        "    IFNDEF ITEM_CAT_LAYOUT_Z80_INC",
        "    DEFINE ITEM_CAT_LAYOUT_Z80_INC 1",
        f"ITMCAT_SIZE_CAP EQU {bic.ITMCAT_SIZE_CAP}",
        f"ITMCAT_TOTAL_SIZE EQU {offsets['total_size']}",
        f"ITMCAT_HDR_SIZE EQU {bic.ITMCAT_HDR_SIZE}",
        "",
        "; 'ITM2' 32-byte header field offsets",
        "ITMCAT_HDR_MAGIC EQU 0           ; 4 bytes: 'ITM2'",
        "ITMCAT_HDR_TOTAL_SIZE EQU 4      ; 2 bytes: total byte size",
        f"ITMCAT_HDR_ITEM_COUNT EQU 6      ; 2 bytes: item count ({cnts['items']})",
        "ITMCAT_HDR_EGO_COUNT EQU 8       ; 1 byte: ego count (55)",
        "ITMCAT_HDR_FLAV_COUNT EQU 9      ; 1 byte: flavour count (174)",
        "ITMCAT_HDR_TOK_COUNT EQU 10      ; 1 byte: non-recursive 0x80+ token count",
        "ITMCAT_HDR_STR_STRIDE EQU 11     ; 1 byte: strings per block-index entry",
        "ITMCAT_HDR_NUM_COSTS EQU 12      ; 1 byte",
        "ITMCAT_HDR_NUM_WEIGHTS EQU 13    ; 1 byte",
        "ITMCAT_HDR_NUM_DMGS EQU 14       ; 1 byte",
        "ITMCAT_HDR_NUM_WDS EQU 15        ; 1 byte",
        "ITMCAT_HDR_NUM_FLAGS EQU 16      ; 1 byte",
        "ITMCAT_HDR_NUM_BONUSES EQU 17    ; 1 byte",
        "ITMCAT_HDR_NUM_EFFECTS EQU 18    ; 1 byte",
        "ITMCAT_HDR_CANON_MAX_LEN EQU 19  ; 1 byte: max Huffman code bit length",
        "ITMCAT_HDR_CANON_NUM_SYMS EQU 20 ; 1 byte: canonical symbol count",
        "ITMCAT_HDR_BLK_COUNT EQU 21      ; 1 byte: block bitpos entry count",
        "ITMCAT_HDR_OFF_RECORDS EQU 22    ; 2 bytes",
        "ITMCAT_HDR_OFF_COLD_TABLES EQU 24 ; 2 bytes",
        "ITMCAT_HDR_OFF_BLK_INDEX EQU 26  ; 2 bytes",
        "ITMCAT_HDR_OFF_CANON EQU 28      ; 2 bytes",
        "ITMCAT_HDR_OFF_STREAM EQU 30     ; 2 bytes",
        "",
        f"; Cold item record layout (4 bytes per item ID 0..{cnts['items'] - 1})",
        "ITMCAT_REC_SIZE EQU 4",
        "ITMCAT_REC_COST_DEPTH EQU 0      ; bits 0..6 = cost_idx, bit 7 = is_depth_variant",
        "ITMCAT_REC_WD_AMMO EQU 1         ; bits 0..6 = wd_idx, bit 7 = is_ammo (0x80)",
        "ITMCAT_REC_EFFECT_IDX EQU 2      ; index into cold_effects",
        "ITMCAT_REC_LVL_MISSILE EQU 3     ; bits 0..5 = vms_level, bits 6..7 = missile family (1..3)",
        "ITMCAT_REC_COST_MASK EQU 0x7f",
        "ITMCAT_REC_DEPTH_BIT EQU 0x80",
        "ITMCAT_REC_WD_MASK EQU 0x7f",
        "ITMCAT_REC_AMMO_BIT EQU 0x80",
        "ITMCAT_REC_LVL_MASK EQU 0x3f",
        "ITMCAT_REC_MISSILE_SHIFT EQU 6",
        "",
        "; Deduplicated subtable element strides and string bases",
        "ITMCAT_COST_SIZE EQU 2           ; uint16 LE",
        "ITMCAT_WEIGHT_SIZE EQU 2         ; uint16 LE (0.1 lb)",
        "ITMCAT_DMG_SIZE EQU 2            ; dice, sides",
        "ITMCAT_WD_SIZE EQU 2             ; weight_idx, dmg_idx",
        "ITMCAT_FLAG_SIZE EQU 4           ; uint32 LE",
        "ITMCAT_BONUS_SIZE EQU 5          ; int16 p1, int8 tohit, int8 todam, int8 toac",
        "ITMCAT_EFFECT_SIZE EQU 2         ; flags_idx, bonus_idx",
        "ITMCAT_EGO_SIZE EQU 3            ; effect_idx, uint16 cost_delta",
        "ITMCAT_STR_BASE_ITEM EQU 0",
        f"ITMCAT_STR_BASE_EGO EQU {cnts['items']}",
        f"ITMCAT_STR_BASE_FLAV EQU {cnts['items'] + cnts['egos']}",
        f"ITMCAT_STR_BASE_TOK EQU {cnts['items'] + cnts['egos'] + cnts['flavours']}",
        "ITMCAT_TOK_MIN EQU 0x80",
        f"ITMCAT_MAX_STR_LEN EQU {max(len(it['name']) for it in items)}",
        f"ITMCAT_STR_STRIDE EQU {cnts['stride']}",
        f"ITMCAT_TOK_COUNT EQU {cnts['tokens']}",
        f"ITMCAT_BLK_COUNT EQU {cnts['blk_count']}",
        f"ITMCAT_CANON_MAX_LEN EQU {cnts['canon_max_len']}",
        f"ITMCAT_CANON_NUM_SYMS EQU {cnts['canon_num_syms']}",
        "",
        "; Exact byte offsets within item_cat_ascii.bin for this build",
        f"ITMCAT_OFF_RECORDS EQU {offsets['records']}",
        f"ITMCAT_OFF_COSTS EQU {offsets['costs']}",
        f"ITMCAT_OFF_WEIGHTS EQU {offsets['weights']}",
        f"ITMCAT_OFF_DMGS EQU {offsets['dmgs']}",
        f"ITMCAT_OFF_WDS EQU {offsets['wds']}",
        f"ITMCAT_OFF_FLAGS EQU {offsets['flags']}",
        f"ITMCAT_OFF_BONUSES EQU {offsets['bonuses']}",
        f"ITMCAT_OFF_EFFECTS EQU {offsets['effects']}",
        f"ITMCAT_OFF_EGOS EQU {offsets['egos']}",
        f"ITMCAT_OFF_BLK_INDEX EQU {offsets['blk_index']}",
        f"ITMCAT_OFF_CANON_COUNTS EQU {offsets['canon_counts']}",
        f"ITMCAT_OFF_CANON_SYMS EQU {offsets['canon_syms']}",
        f"ITMCAT_OFF_STREAM EQU {offsets['stream']}",
        "    ENDIF",
        "",
    ]

    # 3. item_hot_tables_z80.inc
    extra_ac = [it for it in items if it["base_ac"] >= 15]
    it_cat_vals = [it["cat"] for it in items]
    it_col_ac_vals = [((it["color"] & 0x0F) << 4) | min(it["base_ac"], 15) for it in items]
    it_unk_vals = [it["unknown_idx"] for it in items]
    flav_col_vals = [fl["color"] for fl in flavs]

    hot_lines = [
        "; Generated by tools/build_z80_assets.py from item_catalog_spec.json. Do not edit.",
        "; Hot item catalog constants and lookup arrays for sjasmplus.",
        "",
        "    IFNDEF ITEM_DEFS_CONSTS_INCLUDED",
        "    DEFINE ITEM_DEFS_CONSTS_INCLUDED 1",
        f"ITEM_TYPE_COUNT EQU {consts['ITEM_TYPE_COUNT']}",
        f"ITEM_PAGE_SIZE EQU {consts['PAGE_SIZE']}",
        f"EGO_COUNT EQU {consts['EGO_COUNT']}",
        f"FLAVOUR_COUNT EQU {consts['FLAVOUR_COUNT']}",
        f"FLAVOUR_POTION_COUNT EQU {consts['FLAVOUR_POTION_COUNT']}",
        f"FLAVOUR_SCROLL_COUNT EQU {consts['FLAVOUR_SCROLL_COUNT']}",
        f"FLAVOUR_RING_COUNT EQU {consts['FLAVOUR_RING_COUNT']}",
        f"FLAVOUR_WAND_COUNT EQU {consts['FLAVOUR_WAND_COUNT']}",
        f"FLAVOUR_STAFF_COUNT EQU {consts['FLAVOUR_STAFF_COUNT']}",
        f"IT_AC_EXTRA_COUNT EQU {len(extra_ac)}",
        "    ENDIF",
        "",
        "    IFNDEF ITEM_HOT_TABLES_CONSTS_ONLY",
        "    IFNDEF ITEM_HOT_TABLES_Z80_INCLUDED",
        "    DEFINE ITEM_HOT_TABLES_Z80_INCLUDED 1",
        "it_category:",
        *sjasm_db_rows(it_cat_vals, comments=[f"{it['id']}: {it['name']}" for it in items]),
        "",
        "it_color_ac:",
        *sjasm_db_rows(
            it_col_ac_vals,
            comments=[f"{it['id']}: {it['name']} (col=0x{it['color']:x}, ac={it['base_ac']})" for it in items],
        ),
        "",
        "it_ac_extra_id_lo:",
        *sjasm_db_rows([it["id"] & 0xFF for it in extra_ac], comments=[f"{it['id']}: {it['name']}" for it in extra_ac]),
        "it_ac_extra_id_hi:",
        *sjasm_db_rows([it["id"] >> 8 for it in extra_ac]),
        "it_ac_extra_val:",
        *sjasm_db_rows([it["base_ac"] for it in extra_ac], comments=[f"{it['base_ac']}: {it['name']}" for it in extra_ac]),
        "",
        "it_unknown_idx:",
        *sjasm_db_rows(it_unk_vals, comments=[f"{it['id']}: {it['name']}" for it in items]),
        "",
        "flavour_colors:",
        *sjasm_db_rows(
            flav_col_vals,
            comments=[f"{fl['id']} ({fl['class']} {fl['local_idx']}): {fl['name']}" for fl in flavs],
        ),
        "    ENDIF",
        "    ENDIF",
        "",
    ]

    # 4. item_cat_pinned_z80.inc (367 B pinned RO metadata extracted from item_cat_ascii.bin)
    blk_index_bytes = list(blob[offsets["blk_index"] : offsets["canon_counts"]])
    canon_counts_bytes = list(blob[offsets["canon_counts"] : offsets["canon_syms"]])
    canon_syms_bytes = list(blob[offsets["canon_syms"] : offsets["stream"]])
    pinned_total = len(blk_index_bytes) + len(canon_counts_bytes) + len(canon_syms_bytes)
    assert len(blk_index_bytes) == offsets["blk_index_size"]
    assert len(canon_counts_bytes) == offsets["canon_counts_size"]
    assert len(canon_syms_bytes) == offsets["canon_syms_size"]
    assert pinned_total == offsets["stream"] - offsets["blk_index"]

    pinned_lines = [
        "; Generated by tools/build_z80_assets.py from item_catalog_spec.json. Do not edit.",
        f"; Pinned read-only ITEM.CAT metadata ({pinned_total} bytes) for resident MORIA8.COM.",
        "",
        "    IFNDEF ITEM_CAT_PINNED_Z80_INC",
        "    DEFINE ITEM_CAT_PINNED_Z80_INC 1",
        f"ICAT_PINNED_BLK_INDEX_SIZE EQU {len(blk_index_bytes)}",
        f"ICAT_PINNED_CANON_COUNTS_SIZE EQU {len(canon_counts_bytes)}",
        f"ICAT_PINNED_CANON_SYMS_SIZE EQU {len(canon_syms_bytes)}",
        f"ICAT_PINNED_TOTAL_SIZE EQU {pinned_total}",
        "",
        "    IFNDEF ITEM_CAT_PINNED_CONSTS_ONLY",
        "icat_blk_index:",
        *sjasm_db_rows(blk_index_bytes),
        "icat_canon_counts:",
        *sjasm_db_rows(canon_counts_bytes),
        "icat_canon_syms:",
        *sjasm_db_rows(canon_syms_bytes),
        "icat_pinned_end:",
        "    ASSERT (icat_pinned_end - icat_blk_index) == ICAT_PINNED_TOTAL_SIZE",
        "    ENDIF",
        "    ENDIF",
        "",
    ]

    # 5. pick_item_tables_z80.inc (13-tier depth-bucketed 340-item pool matching core/6502/pick_item_type_cold.s)
    spawnable = sorted(
        (it for it in items if it["id"] >= 20 and it["id"] != 210),
        key=lambda it: (min(int(it["min_lvl_m8"]), 12), int(it["id"])),
    )
    assert len(spawnable) == 340, f"Expected 340 spawnable items, got {len(spawnable)}"
    page_size = int(consts["PAGE_SIZE"])
    pit_sorted_lo = [it["id"] if it["id"] < page_size else it["id"] - page_size for it in spawnable]
    pit_sorted_hi_bits = []
    for base in range(0, len(spawnable), 8):
        mask = 0
        for bit in range(8):
            if base + bit < len(spawnable) and spawnable[base + bit]["id"] >= page_size:
                mask |= 1 << bit
        pit_sorted_hi_bits.append(mask)
    pit_bounds = []
    tier_cursor = 0
    for tier in range(13):
        while tier_cursor < len(spawnable) and min(int(spawnable[tier_cursor]["min_lvl_m8"]), 12) <= tier:
            tier_cursor += 1
        pit_bounds.append(tier_cursor)
    assert pit_bounds[-1] == 340

    pit_lines = [
        "; Generated by tools/build_z80_assets.py from item_catalog_spec.json. Do not edit.",
        "; Depth-bucketed 340-item floor/chest/drop pool matching core/6502/pick_item_type_cold.s.",
        "",
        "    IFNDEF PICK_ITEM_TABLES_Z80_INC",
        "    DEFINE PICK_ITEM_TABLES_Z80_INC 1",
        "PIT_MAX_LEVEL EQU 12",
        "PIT_SPAWNABLE_COUNT EQU 340",
        "pit_sorted_lo:",
        *sjasm_db_rows(pit_sorted_lo),
        "pit_sorted_hi_bits:",
        *sjasm_db_rows(pit_sorted_hi_bits),
        "pit_level_bounds_lo:",
        *sjasm_db_rows([b & 0xFF for b in pit_bounds]),
        "pit_level_bounds_hi:",
        *sjasm_db_rows([b >> 8 for b in pit_bounds]),
        "pit_bit_masks:",
        "    DB 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80",
        "    ENDIF",
        "",
    ]

    return {
        "item_cat_ascii_bin": blob,
        "item_ids_z80_inc": "\n".join(ids_lines),
        "item_cat_layout_z80_inc": "\n".join(layout_lines),
        "item_hot_tables_z80_inc": "\n".join(hot_lines),
        "item_cat_pinned_z80_inc": "\n".join(pinned_lines),
        "pick_item_tables_z80_inc": "\n".join(pit_lines),
        "pinned_offsets": (offsets["blk_index"], offsets["stream"]),
        "pinned_total_size": pinned_total,
        "total_size": len(blob),
        "counts": cnts,
    }


# ---------------------------------------------------------------------------
# (d) Title Art & (f) Version
# ---------------------------------------------------------------------------

def load_cpm_version(
    version_path: Path,
    *,
    channel: str | None = None,
    build_num: str | None = None,
    suffix: str | None = None,
) -> tuple[str, str]:
    """Load bare semver (e.g. '2.0.0-rc1') and display version ('v2.0.0-rc1') from version.json['cpm']."""
    pv = version_info.resolve_port_version(
        version_path,
        "cpm",
        channel=channel,
        build_num=build_num,
        suffix=suffix,
    )
    assert_printable_ascii_text(pv.display, "version")
    return pv.bare, pv.display


def build_version_z80_inc(bare_ver: str, prefixed_ver: str) -> str:
    """Render sjasmplus version_z80.inc using 0xNN / EQU / DB directives."""
    m = re.match(r"^(\d+)(?:\.(\d+))?(?:\.(\d+))?", bare_ver)
    major = int(m.group(1)) if m and m.group(1) else 0
    minor = int(m.group(2)) if m and m.group(2) else 0
    patch = int(m.group(3)) if m and m.group(3) else 0

    lines = [
        "; Generated by tools/build_z80_assets.py from version.json. Do not edit.",
        "",
        "    IFNDEF VERSION_Z80_INC",
        "    DEFINE VERSION_Z80_INC 1",
        f"MORIA8_VERSION_MAJOR EQU {major}",
        f"MORIA8_VERSION_MINOR EQU {minor}",
        f"MORIA8_VERSION_PATCH EQU {patch}",
        f"TITLE_VERSION_LEN EQU {len(prefixed_ver)}",
        f"VERSION_STR_LEN EQU {len(bare_ver)}",
        "    MACRO EmitTitleVersion",
        f'        DB "{prefixed_ver}"',
        "    ENDM",
        "    MACRO EmitVersionBare",
        f'        DB "{bare_ver}"',
        "    ENDM",
        "    ENDIF",
        "",
    ]
    return "\n".join(lines)


def _center_in_inner(text: str) -> int:
    return TITLE_INNER_COL + (TITLE_INNER_WIDTH - len(text)) // 2


def build_title_art_bin(prefixed_ver: str) -> bytes:
    """Build 80x24 title screen segment stream [row, col, color, len, ascii..., 0xFF]."""
    segments: list[tuple[int, int, int, str]] = []

    def add_seg(row: int, col: int, color: int, text: str) -> None:
        assert 0 <= row < TITLE_ROWS
        assert 0 <= col < TITLE_COLS
        assert 0 <= color < 16
        assert 1 <= len(text) <= TITLE_COLS and col + len(text) <= TITLE_COLS
        assert_printable_ascii_text(text, f"title_art row {row}")
        segments.append((row, col, color, text))

    def add_border_row(row: int) -> None:
        add_seg(row, TITLE_BOX_COL, TC_LGREY, "|")
        add_seg(row, TITLE_BOX_COL + TITLE_BOX_WIDTH - 1, TC_LGREY, "|")

    hbar = "+" + ("-" * TITLE_INNER_WIDTH) + "+"

    # Row 1: top border
    add_seg(1, TITLE_BOX_COL, TC_LGREY, hbar)
    # Row 2: spacer
    add_border_row(2)
    # Rows 3..7: MORIA8 block art
    art_col = _center_in_inner(TITLE_MORIA8_ART[0])
    for i, art_line in enumerate(TITLE_MORIA8_ART):
        row = 3 + i
        add_seg(row, TITLE_BOX_COL, TC_LGREY, "|")
        add_seg(row, art_col, TC_WHITE, art_line)
        add_seg(row, TITLE_BOX_COL + TITLE_BOX_WIDTH - 1, TC_LGREY, "|")
    # Row 8: spacer
    add_border_row(8)
    # Row 9: subtitle ("The Dungeons of Moria" starts at col 30 on 80-col, matching 6502 +8 offset)
    subtitle = "The Dungeons of Moria"
    add_seg(9, TITLE_BOX_COL, TC_LGREY, "|")
    add_seg(9, _center_in_inner(subtitle) + 1, TC_YELLOW, subtitle)
    add_seg(9, TITLE_BOX_COL + TITLE_BOX_WIDTH - 1, TC_LGREY, "|")
    # Row 10: divider
    add_seg(10, TITLE_BOX_COL, TC_LGREY, hbar)
    # Row 11: spacer
    add_border_row(11)
    # Row 12: edition
    edition = "CP/M Z80 Edition"
    add_seg(12, TITLE_BOX_COL, TC_LGREY, "|")
    add_seg(12, _center_in_inner(edition), TC_CYAN, edition)
    add_seg(12, TITLE_BOX_COL + TITLE_BOX_WIDTH - 1, TC_LGREY, "|")
    # Row 13: version from version.json
    add_seg(13, TITLE_BOX_COL, TC_LGREY, "|")
    add_seg(13, _center_in_inner(prefixed_ver), TC_DGREY, prefixed_ver)
    add_seg(13, TITLE_BOX_COL + TITLE_BOX_WIDTH - 1, TC_LGREY, "|")
    # Row 14: original author credit
    orig_credit = "Based on Moria by R.A. Koeneke"
    add_seg(14, TITLE_BOX_COL, TC_LGREY, "|")
    add_seg(14, _center_in_inner(orig_credit), TC_DGREY, orig_credit)
    add_seg(14, TITLE_BOX_COL + TITLE_BOX_WIDTH - 1, TC_LGREY, "|")
    # Row 15: port author credit
    port_credit = "CP/M port by Chad Gibbons"
    add_seg(15, TITLE_BOX_COL, TC_LGREY, "|")
    add_seg(15, _center_in_inner(port_credit), TC_DGREY, port_credit)
    add_seg(15, TITLE_BOX_COL + TITLE_BOX_WIDTH - 1, TC_LGREY, "|")
    # Row 16: divider
    add_seg(16, TITLE_BOX_COL, TC_LGREY, hbar)
    # Rows 17..18: menu rows inside frame
    add_border_row(17)
    add_border_row(18)
    # Row 19: bottom border
    add_seg(19, TITLE_BOX_COL, TC_LGREY, hbar)

    out = bytearray()
    for row, col, color, text in segments:
        raw = text.encode("ascii")
        out.extend((row, col, color, len(raw)))
        out.extend(raw)
    out.append(0xFF)
    return bytes(out)


def decode_title_art_bin(blob: bytes) -> list[str]:
    """Validate and render title_art.bin onto an 80x24 virtual ASCII screen."""
    grid = [[" "] * TITLE_COLS for _ in range(TITLE_ROWS)]
    pos = 0
    n = len(blob)
    found_end = False
    while pos < n:
        row = blob[pos]
        pos += 1
        if row == 0xFF:
            found_end = True
            assert pos == n, f"Trailing bytes after 0xFF in title_art.bin at {pos}"
            break
        assert pos + 3 <= n, "Truncated segment header in title_art.bin"
        col = blob[pos]
        color = blob[pos + 1]
        length = blob[pos + 2]
        pos += 3
        assert 0 <= row < TITLE_ROWS, f"Invalid row {row}"
        assert 0 <= col < TITLE_COLS, f"Invalid col {col}"
        assert 0 <= color < 16, f"Invalid color {color}"
        assert 1 <= length <= TITLE_COLS and col + length <= TITLE_COLS, f"Segment OOB: col={col}, len={length}"
        assert pos + length <= n, "Truncated segment payload in title_art.bin"
        seg = blob[pos : pos + length]
        pos += length
        for i, b in enumerate(seg):
            assert 0x20 <= b <= 0x7E, f"Non-printable ASCII 0x{b:02x} in title_art.bin"
            grid[row][col + i] = chr(b)
    assert found_end, "Missing 0xFF terminator in title_art.bin"
    return ["".join(r) for r in grid]


# ---------------------------------------------------------------------------
# (e) Legal text CRLF conversion
# ---------------------------------------------------------------------------

def convert_text_crlf(src_path: Path) -> bytes:
    """Convert LF/CRLF text file to clean 7-bit ASCII with CR+LF line endings."""
    text = src_path.read_text(encoding="utf-8")
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    while lines and lines[-1] == "":
        lines.pop()
    for idx, line in enumerate(lines):
        assert_printable_ascii_text(line, f"{src_path.name}:{idx + 1}")
    crlf_text = "\r\n".join(lines) + "\r\n"
    return crlf_text.encode("ascii")


# ---------------------------------------------------------------------------
# Generation & Selftest
# ---------------------------------------------------------------------------

def generate_all(
    out_dir: Path,
    huffman_txt: Path = DEFAULT_HUFFMAN_TXT,
    monster_spec: Path = DEFAULT_MONSTER_SPEC,
    item_spec: Path = DEFAULT_ITEM_SPEC,
    license_file: Path = DEFAULT_LICENSE,
    source_offer_file: Path = DEFAULT_SOURCE_OFFER,
    version_file: Path = DEFAULT_VERSION_JSON,
) -> dict[str, object]:
    """Generate all CP/M Z80 ASCII assets into out_dir and return summary metadata."""
    out_dir.mkdir(parents=True, exist_ok=True)

    huff_res = build_huffman_ascii_assets(huffman_txt)
    (out_dir / "huff_ascii.inc").write_text(str(huff_res["huff_ascii_inc"]), encoding="utf-8")
    (out_dir / "huff_stream.bin").write_bytes(bytes(huff_res["huff_stream_bin"]))

    mon_res = build_monster_ascii_assets(monster_spec)
    (out_dir / "monster_cat_ascii.bin").write_bytes(bytes(mon_res["monster_cat_ascii_bin"]))
    (out_dir / "monster_idx_z80.inc").write_text(str(mon_res["monster_idx_z80_inc"]), encoding="utf-8")

    item_res = build_item_ascii_assets(item_spec)
    (out_dir / "item_cat_ascii.bin").write_bytes(bytes(item_res["item_cat_ascii_bin"]))
    (out_dir / "item_ids_z80.inc").write_text(str(item_res["item_ids_z80_inc"]), encoding="utf-8")
    (out_dir / "item_cat_layout_z80.inc").write_text(str(item_res["item_cat_layout_z80_inc"]), encoding="utf-8")
    (out_dir / "item_hot_tables_z80.inc").write_text(str(item_res["item_hot_tables_z80_inc"]), encoding="utf-8")
    (out_dir / "item_cat_pinned_z80.inc").write_text(str(item_res["item_cat_pinned_z80_inc"]), encoding="utf-8")
    (out_dir / "pick_item_tables_z80.inc").write_text(str(item_res["pick_item_tables_z80_inc"]), encoding="utf-8")

    bare_ver, prefixed_ver = load_cpm_version(version_file)
    version_inc = build_version_z80_inc(bare_ver, prefixed_ver)
    version_info.atomic_write_if_changed(out_dir / "version_z80.inc", version_inc)

    title_bin = build_title_art_bin(prefixed_ver)
    decode_title_art_bin(title_bin)
    (out_dir / "title_art.bin").write_bytes(title_bin)

    license_bytes = convert_text_crlf(license_file)
    srcoffr_bytes = convert_text_crlf(source_offer_file)
    (out_dir / "license.txt").write_bytes(license_bytes)
    (out_dir / "srcoffr.txt").write_bytes(srcoffr_bytes)

    return {
        "out_dir": str(out_dir),
        "huff_strings": huff_res["string_count"],
        "huff_nodes": huff_res["node_count"],
        "huff_stream_bytes": huff_res["stream_size"],
        "monsters": mon_res["creature_count"],
        "monster_bytes": len(bytes(mon_res["monster_cat_ascii_bin"])),
        "item_cat_bytes": item_res["total_size"],
        "item_pinned_bytes": item_res["pinned_total_size"],
        "title_art_bytes": len(title_bin),
        "license_bytes": len(license_bytes),
        "srcoffr_bytes": len(srcoffr_bytes),
        "version": prefixed_ver,
    }


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
    """Run exhaustive offline validation of all Z80/CP/M ASCII asset generators."""
    dollar_hex_re = re.compile(r"(^|[^A-Za-z0-9_])\$[0-9A-Fa-f]+")
    inc_files = (
        "huff_ascii.inc",
        "monster_idx_z80.inc",
        "item_ids_z80.inc",
        "item_cat_layout_z80.inc",
        "item_hot_tables_z80.inc",
        "item_cat_pinned_z80.inc",
        "pick_item_tables_z80.inc",
        "version_z80.inc",
    )

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        summary = generate_all(tmp)

        # 1. Verify no '$' hex literals in any generated .inc file.
        for inc_name in inc_files:
            txt = (tmp / inc_name).read_text(encoding="utf-8")
            for lineno, line in enumerate(txt.splitlines(), start=1):
                assert not dollar_hex_re.search(line), (
                    f"{inc_name}:{lineno} contains '$' hex literal: {line!r}"
                )

        # 2. Verify strict version.json 'cpm' requirement (no silent fallback).
        bad_ver = tmp / "bad_version.json"
        bad_ver.write_text('{"c128": "2.0.0"}\n', encoding="utf-8")
        ver_caught = False
        try:
            load_cpm_version(bad_ver)
        except ValueError:
            ver_caught = True
        assert ver_caught, "Expected ValueError when version.json omits 'cpm'"

        # Verify prerelease resolution retains base numeric MAJOR/MINOR/PATCH and emits full suffix.
        rc_bare, rc_disp = load_cpm_version(DEFAULT_VERSION_JSON, channel="rc", build_num="1", suffix="")
        assert rc_bare.endswith("-rc1") and rc_disp == f"v{rc_bare}"
        rc_inc = build_version_z80_inc(rc_bare, rc_disp)
        assert f'DB "{rc_disp}"' in rc_inc and f'DB "{rc_bare}"' in rc_inc

        # 3. Verify Huffman stream round-trip and confirm huff_data.bin is not emitted.
        assert not (tmp / "huff_data.bin").exists()
        huff_res = build_huffman_ascii_assets(DEFAULT_HUFFMAN_TXT)
        stream_bin = (tmp / "huff_stream.bin").read_bytes()
        assert stream_bin == huff_res["huff_stream_bin"]
        texts, _labels = parse_huffman_strings(DEFAULT_HUFFMAN_TXT)
        for i, expected in enumerate(texts):
            dec = decode_huffman_string(
                list(huff_res["left_table"]),  # type: ignore[arg-type]
                list(huff_res["right_table"]),  # type: ignore[arg-type]
                stream_bin,
                list(huff_res["offsets"])[i],  # type: ignore[arg-type]
            )
            assert dec == expected.encode("ascii")

        # 4. Verify Monster Catalog 140 records = 17,920 B.
        mon_bin = (tmp / "monster_cat_ascii.bin").read_bytes()
        assert len(mon_bin) == 140 * 128 == 17920
        assert all(b == 0 for b in mon_bin[139 * 128 + 57 : 140 * 128])

        # 5. Verify Item Catalog <= 7,800 B, ASCII round-trip, and pinned RO metadata.
        item_bin = (tmp / "item_cat_ascii.bin").read_bytes()
        assert item_bin[:4] == b"ITM2"
        assert len(item_bin) <= 7800
        item_res = build_item_ascii_assets(DEFAULT_ITEM_SPEC)
        pin_start, pin_end = item_res["pinned_offsets"]  # type: ignore[misc]
        assert pin_end - pin_start == 367, f"Expected 367 B pinned metadata, got {pin_end - pin_start}"

        # 6. Verify Title Art 80x24 grid.
        title_bin = (tmp / "title_art.bin").read_bytes()
        grid = decode_title_art_bin(title_bin)
        joined = "\n".join(grid)
        _, prefixed_ver = load_cpm_version(DEFAULT_VERSION_JSON)
        for expected in (
            TITLE_MORIA8_ART[0],
            "The Dungeons of Moria",
            "CP/M Z80 Edition",
            prefixed_ver,
            "Based on Moria by R.A. Koeneke",
            "CP/M port by Chad Gibbons",
        ):
            assert expected in joined, f"Missing {expected!r} in rendered title_art.bin"
        assert "GPL" not in joined and "Free Software" not in joined
        assert grid[17][22:58].strip() == "" and grid[18][22:58].strip() == ""

        # 7. Verify CRLF legal texts.
        for fname in ("license.txt", "srcoffr.txt"):
            raw = (tmp / fname).read_bytes()
            assert raw.endswith(b"\r\n")
            assert b"\n" not in raw.replace(b"\r\n", b"")
            assert all(b in (0x0D, 0x0A) or (0x20 <= b <= 0x7E) for b in raw)

        # 8. Assemble all .inc files together with sjasmplus (incl. ALIGN 256, pinned bytes, consts-only).
        sjasm = _find_sjasmplus()
        if sjasm is not None:
            asm_full = tmp / "test_full.asm"
            asm_full.write_text(
                "\n".join([
                    "    DEVICE NOSLOT64K",
                    "    ORG 0x0103",
                    '    INCLUDE "version_z80.inc"',
                    '    INCLUDE "huff_ascii.inc"',
                    '    INCLUDE "huff_ascii.inc"',
                    '    INCLUDE "monster_idx_z80.inc"',
                    '    INCLUDE "monster_idx_z80.inc"',
                    '    INCLUDE "item_ids_z80.inc"',
                    '    INCLUDE "item_cat_layout_z80.inc"',
                    '    INCLUDE "item_hot_tables_z80.inc"',
                    '    INCLUDE "item_cat_pinned_z80.inc"',
                    "ver_test:",
                    "    EmitTitleVersion",
                    "    DB 0",
                    "    ASSERT (huff_tree_left & 0xFF) == 0",
                    "    ASSERT huff_tree_right == huff_tree_left + 64",
                    "    ASSERT (cat_level_playable - cat_level_raw) == 41",
                    "    ASSERT (cat_undead - cat_level_playable) == 41",
                    "    ASSERT (catalog_index_end - cat_undead) == 35",
                    "    ASSERT ITEM_TYPE_COUNT == 361",
                    "    ASSERT CATALOG_COUNT == 279",
                    "    ASSERT HUFF_STR_COUNT == 248",
                    "    ASSERT ICAT_PINNED_TOTAL_SIZE == 367",
                    "",
                ]),
                encoding="utf-8",
            )
            res = subprocess.run(
                [str(sjasm), "--syntax=abfw", f"-I{tmp}", f"--raw={tmp}/test_full.bin", f"--sym={tmp}/test_full.sym", str(asm_full)],
                capture_output=True,
                text=True,
                check=False,
            )
            assert res.returncode == 0, f"sjasmplus full test failed:\n{res.stderr}\n{res.stdout}"
            assert "warning:" not in res.stderr.lower(), f"sjasmplus warnings:\n{res.stderr}"

            # Verify assembled pinned metadata matches item_cat_ascii.bin byte-for-byte.
            asm_pinned = tmp / "test_pinned.asm"
            asm_pinned.write_text(
                "\n".join([
                    "    DEVICE NOSLOT64K",
                    "    ORG 0x0100",
                    '    INCLUDE "item_cat_pinned_z80.inc"',
                    "",
                ]),
                encoding="utf-8",
            )
            res_pin = subprocess.run(
                [str(sjasm), "--syntax=abfw", f"-I{tmp}", f"--raw={tmp}/test_pinned.bin", str(asm_pinned)],
                capture_output=True,
                text=True,
                check=False,
            )
            assert res_pin.returncode == 0, f"sjasmplus pinned test failed:\n{res_pin.stderr}"
            pinned_bin = (tmp / "test_pinned.bin").read_bytes()
            assert pinned_bin == item_bin[pin_start:pin_end], (
                f"item_cat_pinned_z80.inc mismatch: {len(pinned_bin)} B vs {pin_end - pin_start} B"
            )

            asm_consts = tmp / "test_consts.asm"
            asm_consts.write_text(
                "\n".join([
                    "    DEVICE NOSLOT64K",
                    "    ORG 0x5400",
                    "    DEFINE HUFF_CONSTS_ONLY 1",
                    "    DEFINE MONSTER_IDX_CONSTS_ONLY 1",
                    "    DEFINE ITEM_HOT_TABLES_CONSTS_ONLY 1",
                    "    DEFINE ITEM_CAT_PINNED_CONSTS_ONLY 1",
                    '    INCLUDE "huff_ascii.inc"',
                    '    INCLUDE "monster_idx_z80.inc"',
                    '    INCLUDE "item_hot_tables_z80.inc"',
                    '    INCLUDE "item_cat_pinned_z80.inc"',
                    "consts_end:",
                    "    ASSERT consts_end == 0x5400",
                    "",
                ]),
                encoding="utf-8",
            )
            res2 = subprocess.run(
                [str(sjasm), "--syntax=abfw", f"-I{tmp}", f"--raw={tmp}/test_consts.bin", str(asm_consts)],
                capture_output=True,
                text=True,
                check=False,
            )
            assert res2.returncode == 0, f"sjasmplus consts-only test failed:\n{res2.stderr}\n{res2.stdout}"
            assert (tmp / "test_consts.bin").read_bytes() == b""

            # Verify split HUFF_NO_INDEX / HUFF_NO_TREE page-tail packing contract.
            asm_split = tmp / "test_split.asm"
            asm_split.write_text(
                "\n".join([
                    "    DEVICE NOSLOT64K",
                    "    ORG 0x0105",
                    "    ALIGN 256",
                    "split_page:",
                    "    DEFINE HUFF_NO_INDEX 1",
                    '    INCLUDE "huff_ascii.inc"',
                    "    UNDEFINE HUFF_NO_INDEX",
                    "    ASSERT (split_page & 0xFF) == 0",
                    "    ASSERT huff_tree_left == split_page + 0x00",
                    "    ASSERT huff_tree_right == split_page + 0x40",
                    "    ASSERT ($ - split_page) == 0x78",
                    '    INCLUDE "monster_idx_z80.inc"',
                    "split_sgr_lut:",
                    "    DS 16, 0x37",
                    "    ASSERT ($ - split_page) == 0xFD",
                    "    DEFINE HUFF_NO_TREE 1",
                    '    INCLUDE "huff_ascii.inc"',
                    "    UNDEFINE HUFF_NO_TREE",
                    "    ASSERT huff_str_index == split_page + 0xFD",
                    "    ASSERT (huff_str_index_end - huff_str_index) == (HUFF_STR_COUNT * 2)",
                    "",
                ]),
                encoding="utf-8",
            )
            res3 = subprocess.run(
                [str(sjasm), "--syntax=abfw", f"-I{tmp}", f"--raw={tmp}/test_split.bin", str(asm_split)],
                capture_output=True,
                text=True,
                check=False,
            )
            assert res3.returncode == 0, f"sjasmplus split huff_ascii test failed:\n{res3.stderr}\n{res3.stdout}"
            assert "warning:" not in res3.stderr.lower(), f"sjasmplus split warnings:\n{res3.stderr}"

    print(
        "build_z80_assets selftest PASSED: "
        f"huff={summary['huff_strings']} strings/{summary['huff_stream_bytes']} B "
        f"({summary['huff_nodes']} nodes, +64 page-aligned), "
        f"monsters={summary['monsters']} ({summary['monster_bytes']} B = 140 recs), "
        f"item_cat={summary['item_cat_bytes']} B (pinned={summary['item_pinned_bytes']} B), "
        f"title_art={summary['title_art_bytes']} B, "
        f"version={summary['version']}"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR, help="Output directory (default: build/cpm)")
    parser.add_argument("--huffman-txt", type=Path, default=DEFAULT_HUFFMAN_TXT)
    parser.add_argument("--monster-spec", type=Path, default=DEFAULT_MONSTER_SPEC)
    parser.add_argument("--item-spec", type=Path, default=DEFAULT_ITEM_SPEC)
    parser.add_argument("--license-file", type=Path, default=DEFAULT_LICENSE)
    parser.add_argument("--source-offer-file", type=Path, default=DEFAULT_SOURCE_OFFER)
    parser.add_argument("--version-file", type=Path, default=DEFAULT_VERSION_JSON)
    parser.add_argument("--selftest", action="store_true", help="Run offline generator & sjasmplus self-test")
    args = parser.parse_args(argv)

    if args.selftest:
        return run_selftest()

    summary = generate_all(
        args.out_dir,
        huffman_txt=args.huffman_txt,
        monster_spec=args.monster_spec,
        item_spec=args.item_spec,
        license_file=args.license_file,
        source_offer_file=args.source_offer_file,
        version_file=args.version_file,
    )
    print(
        f"build_z80_assets: wrote {summary['out_dir']} | "
        f"huff={summary['huff_stream_bytes']} B, monster={summary['monster_bytes']} B, "
        f"item={summary['item_cat_bytes']} B, title={summary['title_art_bytes']} B, "
        f"license={summary['license_bytes']} B, srcoffr={summary['srcoffr_bytes']} B"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
