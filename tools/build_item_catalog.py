#!/usr/bin/env python3
"""Offline deterministic generator and packer for the VMS Moria 4.8 item catalog.

Reads platforms/shared/item_catalog/item_catalog_spec.json and produces:
  - Binary ITEM.CAT ('ITM2', <= 7,800 bytes enforced by assertion)
  - Canonical Huffman + non-recursive $80+ token string pool
  - Kick Assembler sources under platforms/shared/item_catalog/ (--emit-s):
      * item_hot_tables.s  (segmentless hot arrays & constants)
      * item_cat_layout.s  ('ITM2' header/record/subtable layout constants)
      * item_cat_data.s    (segmentless .byte image of ITEM.CAT)

Optional upstream verification (--vms-src PATH or VMS_SRC env var) cross-checks
VMS Moria 4.8 include/values.inc and include/misc.inc when available; default
executions are 100% offline with zero external dependencies or host paths.
"""
from __future__ import annotations

import argparse
import heapq
import json
import os
import re
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import huff_encoder as huff  # noqa: E402

DEFAULT_SPEC = ROOT / "platforms" / "shared" / "item_catalog" / "item_catalog_spec.json"
DEFAULT_EMIT_DIR = ROOT / "platforms" / "shared" / "item_catalog"
DEFAULT_PY_OUT = ROOT / "tools" / "item_ids.py"

ITMCAT_MAGIC = b"ITM2"
ITMCAT_HDR_SIZE = 32
ITMCAT_SIZE_CAP = 7800
STR_BLOCK_STRIDE = 8
PAGE_SIZE = 255
ITEM_PAGE_BIT = 0x40
ICAT_POTION = 10
ICAT_SCROLL = 11
ICAT_RING = 12
ICAT_WAND = 14
ICAT_STAFF = 15
ICAT_CLOAK = 19

FIXED_POTION_UNK = 0xFF
MAX_DISPLAY_LEN = 63  # Fits core/6502/huffman.s HD_DECODE_BUF_SIZE = 64

FLAVOUR_BOUNDS = {
    ICAT_POTION: 46,
    ICAT_SCROLL: 49,
    ICAT_RING: 30,
    ICAT_WAND: 24,
    ICAT_STAFF: 25,
}


def char_to_screencode(ch: str) -> int:
    """Convert ASCII character to C64 mixed screencode (supporting '*')."""
    if ch == "*":
        return 0x2A
    return huff.ascii_to_screencode(ch)


def screencode_to_char(sc: int) -> str:
    """Invert char_to_screencode for Python round-trip verification."""
    if sc == 0x2A:
        return "*"
    if 0x01 <= sc <= 0x1A:
        return chr(ord("a") + sc - 1)
    if 0x41 <= sc <= 0x5A:
        return chr(ord("A") + sc - 0x41)
    if 0x30 <= sc <= 0x39 or sc in (0x20, 0x21, 0x27, 0x28, 0x29, 0x2C, 0x2D, 0x2E, 0x2F, 0x3A, 0x3B, 0x3D, 0x3E, 0x3F):
        return chr(sc)
    raise ValueError(f"Invalid screencode: 0x{sc:02x}")


def text_to_screencodes(text: str) -> list[int]:
    """Encode an ASCII catalog string to C64 mixed screencodes (< $80)."""
    codes = [char_to_screencode(ch) for ch in text]
    for code in codes:
        if not (1 <= code < 0x80):
            raise ValueError(f"Screencode 0x{code:02x} out of literal range for {text!r}")
    return codes


def build_canonical_huffman(freq: Counter[int]) -> tuple[dict[int, str], list[int], list[int]]:
    """Build deterministic MSB-first canonical Huffman tables.

    Returns:
        codes: symbol -> bitstring ('0'/'1')
        counts: list indexed by bit length 0..max_len (counts[0] == 0)
        syms: symbols ordered by (bit_len, symbol)
    """
    tree = huff.build_tree(freq)
    raw_codes = huff.build_codes(tree)
    if not raw_codes:
        raise ValueError("Cannot build Huffman table for empty frequency map")
    lengths = {sym: len(code) for sym, code in raw_codes.items()}
    max_len = max(lengths.values())
    if max_len > 15:
        raise ValueError(f"Canonical Huffman max code length {max_len} exceeds 15")

    counts = [0] * (max_len + 1)
    for bit_len in lengths.values():
        counts[bit_len] += 1

    ordered = sorted(lengths.items(), key=lambda kv: (kv[1], kv[0]))
    syms = [sym for sym, _ in ordered]

    next_code = [0] * (max_len + 1)
    code = 0
    for bits in range(1, max_len + 1):
        code = (code + counts[bits - 1]) << 1
        next_code[bits] = code

    codes: dict[int, str] = {}
    for sym, bit_len in ordered:
        c = next_code[bit_len]
        next_code[bit_len] += 1
        codes[sym] = format(c, f"0{bit_len}b")

    return codes, counts, syms


def _eval_string_pool(
    seqs: list[list[int]],
    tokens: list[list[int]],
    stride: int = STR_BLOCK_STRIDE,
) -> tuple[int, dict[int, str], list[int], list[int]]:
    """Compute exact byte size and canonical codes for seqs + non-recursive tokens."""
    freq: Counter[int] = Counter()
    for seq in seqs:
        freq.update(seq)
        freq[0] += 1
    for tok in tokens:
        freq.update(tok)
        freq[0] += 1

    codes, counts, syms = build_canonical_huffman(freq)
    total_bits = sum(cnt * len(codes[sym]) for sym, cnt in freq.items())
    stream_bytes = (total_bits + 7) // 8
    canon_bytes = len(counts) + len(syms)
    blk_bytes = ((len(seqs) + len(tokens) + stride - 1) // stride) * 2
    return stream_bytes + canon_bytes + blk_bytes, codes, counts, syms


def tokenize_and_encode_strings(
    raw_strings: list[str],
    stride: int = STR_BLOCK_STRIDE,
) -> dict[str, object]:
    """Mine non-recursive $80+ phrase tokens to minimize canonical Huffman pool size."""
    cur = [text_to_screencodes(s) for s in raw_strings]
    tokens: list[list[int]] = []
    best_size, best_codes, best_counts, best_syms = _eval_string_pool(cur, tokens, stride)
    best_state = (best_size, [list(s) for s in cur], [], best_codes, best_counts, best_syms)

    cur_size = best_size
    cur_codes = best_codes
    for tok_offset in range(128):
        tok_id = 0x80 + tok_offset
        sub_counts: Counter[tuple[int, ...]] = Counter()
        for seq in cur:
            n = len(seq)
            for length in range(2, min(22, n + 1)):
                last_end = -1
                for pos in range(0, n - length + 1):
                    if pos < last_end:
                        continue
                    sub = tuple(seq[pos : pos + length])
                    if any(b >= 0x80 for b in sub):
                        continue
                    sub_counts[sub] += 1
                    last_end = pos + length

        scored = []
        for sub, cnt in sub_counts.items():
            if cnt < 2:
                continue
            sub_bits = sum(len(cur_codes[b]) for b in sub)
            est_gain = (cnt - 1) * sub_bits - cnt * 7 - 24
            if est_gain > -40:
                scored.append((est_gain, sub))
        scored.sort(key=lambda kv: (kv[0], kv[1]), reverse=True)

        best_step = None
        for _, sub in scored[:20]:
            length = len(sub)
            sub_list = list(sub)
            test_cur = []
            for seq in cur:
                out = []
                i = 0
                n = len(seq)
                while i < n:
                    if i + length <= n and seq[i : i + length] == sub_list:
                        out.append(tok_id)
                        i += length
                    else:
                        out.append(seq[i])
                        i += 1
                test_cur.append(out)
            test_tokens = tokens + [sub_list]
            try:
                sz, c_codes, c_counts, c_syms = _eval_string_pool(test_cur, test_tokens, stride)
            except ValueError:
                continue
            if best_step is None or sz < best_step[0]:
                best_step = (sz, test_cur, test_tokens, c_codes, c_counts, c_syms)

        if best_step is None:
            break
        cur_size, cur, tokens, cur_codes, cur_counts, cur_syms = best_step
        if cur_size < best_state[0]:
            best_state = (cur_size, [list(s) for s in cur], [list(t) for t in tokens], cur_codes, cur_counts, cur_syms)
        elif cur_size > best_state[0] + 32:
            break

    _, final_seqs, final_tokens, final_codes, final_counts, final_syms = best_state

    # Pack unified MSB-first bitstream: strings[0..N-1] followed by tokens[0..T-1]
    all_entries = final_seqs + final_tokens
    bit_chunks: list[str] = []
    blk_bitpos: list[int] = []
    bit_pos = 0
    for idx, seq in enumerate(all_entries):
        if idx % stride == 0:
            blk_bitpos.append(bit_pos)
        for sym in seq:
            code = final_codes[sym]
            bit_chunks.append(code)
            bit_pos += len(code)
        nul = final_codes[0]
        bit_chunks.append(nul)
        bit_pos += len(nul)

    assert bit_pos < 0x10000, f"Bitstream offset {bit_pos} overflows uint16"
    bitstr = "".join(bit_chunks)
    if len(bitstr) % 8:
        bitstr += "0" * (8 - len(bitstr) % 8)
    stream_bytes = bytes(int(bitstr[i : i + 8], 2) for i in range(0, len(bitstr), 8))

    return {
        "tok_count": len(final_tokens),
        "stride": stride,
        "blk_bitpos": blk_bitpos,
        "canon_counts": final_counts,
        "canon_syms": final_syms,
        "stream_bytes": stream_bytes,
        "total_bits": bit_pos,
    }


def validate_spec(spec: dict) -> None:
    """Validate structural, boundary, and gameplay invariants on the catalog spec."""
    items = spec["items"]
    egos = spec["egos"]
    flavs = spec["flavours"]
    consts = spec["constants"]

    assert len(items) == consts["ITEM_TYPE_COUNT"] == 361
    assert len(egos) == consts["EGO_COUNT"] == 55
    assert len(flavs) == consts["FLAVOUR_COUNT"] == 174
    items_by_name = {it["name"]: it for it in items}
    assert items_by_name["Cloak"]["cat"] == ICAT_CLOAK, (
        f"Cloak must use ICAT_CLOAK (19), got {items_by_name['Cloak']['cat']}"
    )
    assert items_by_name["Staff of Speed"]["cost"] == 1000, (
        f"Staff of Speed cost must be 1000, got {items_by_name['Staff of Speed']['cost']}"
    )
    assert sum(1 for it in items if it["base_ac"] >= 15) == 9, (
        "Expected 9 heavy armors with base_ac >= 15"
    )
    assert sum(1 for it in items if it.get("vms_source") == "m8_custom" and it["cat"] != 1) == 0, (
        "Non-gold m8_custom items must not appear in VMS 361-item catalog"
    )

    expected_flav_counts = [
        ("potion", consts["FLAVOUR_POTION_COUNT"]),
        ("scroll", consts["FLAVOUR_SCROLL_COUNT"]),
        ("ring", consts["FLAVOUR_RING_COUNT"]),
        ("wand", consts["FLAVOUR_WAND_COUNT"]),
        ("staff", consts["FLAVOUR_STAFF_COUNT"]),
    ]
    offset = 0
    for cls_name, expected_len in expected_flav_counts:
        chunk = flavs[offset : offset + expected_len]
        assert len(chunk) == expected_len
        for idx, fl in enumerate(chunk):
            assert fl["class"] == cls_name and fl["local_idx"] == idx and fl["id"] == offset + idx
            assert 0 <= fl["color"] < 16
            assert 1 <= len(fl["name"]) <= MAX_DISPLAY_LEN
        offset += expected_len
    assert offset == 174

    for idx, ego in enumerate(egos, start=1):
        assert ego["id"] == idx
        assert 1 <= len(ego["name"]) <= MAX_DISPLAY_LEN
        assert 0 <= ego["cost_delta"] < 0x10000
        assert -128 <= ego["tohit"] <= 127
        assert -128 <= ego["todam"] <= 127
        assert -128 <= ego["toac"] <= 127
        assert -32768 <= ego["p1"] <= 32767

    for idx, it in enumerate(items):
        assert it["id"] == idx
        assert 0 <= it["cat"] < 32
        assert 0 <= it["color"] < 16
        assert 0 <= it["base_ac"] <= 255
        assert 0 <= it["dice"] <= 255 and 0 <= it["sides"] <= 255
        assert 0 <= it["weight"] < 0x10000
        assert 0 <= it["cost"] < 0x10000
        assert 0 <= it["vms_level"] <= 63
        assert it["missile_type"] in (0, 1, 2, 3, 0x81, 0x82, 0x83), (
            f"Unexpected missile_type {it['missile_type']!r} on item #{idx}"
        )
        assert 1 <= len(it["name"]) <= MAX_DISPLAY_LEN
        if it["base_ac"] >= 15:
            assert idx < PAGE_SIZE, f"Heavy armor #{idx} {it['name']!r} must be on Page 0 (< {PAGE_SIZE})"
        if it["cat"] in FLAVOUR_BOUNDS:
            if it.get("fixed_flavor"):
                assert it["unknown_idx"] == FIXED_POTION_UNK
            else:
                assert 0 <= it["unknown_idx"] < FLAVOUR_BOUNDS[it["cat"]]
        else:
            assert it["unknown_idx"] == 0


def build_item_cat(spec: dict, size_cap: int = ITMCAT_SIZE_CAP) -> tuple[bytes, dict]:
    """Compile item_catalog_spec.json into binary 'ITM2' ITEM.CAT and layout metadata."""
    validate_spec(spec)
    items = spec["items"]
    egos = spec["egos"]
    flavs = spec["flavours"]

    costs = sorted({it["cost"] for it in items})
    weights = sorted({it["weight"] for it in items})
    dmgs = sorted({(it["dice"], it["sides"]) for it in items})
    wds = sorted({(it["weight"], it["dice"], it["sides"]) for it in items})
    flags_all = sorted({x["flags"] for x in items + egos})
    bonuses_all = sorted({(x["p1"], x["tohit"], x["todam"], x["toac"]) for x in items + egos})
    effects_all = sorted({(x["flags"], x["p1"], x["tohit"], x["todam"], x["toac"]) for x in items + egos})

    cost_idx = {v: i for i, v in enumerate(costs)}
    weight_idx = {v: i for i, v in enumerate(weights)}
    dmg_idx = {v: i for i, v in enumerate(dmgs)}
    wd_idx = {v: i for i, v in enumerate(wds)}
    flag_idx = {v: i for i, v in enumerate(flags_all)}
    bonus_idx = {v: i for i, v in enumerate(bonuses_all)}
    effect_idx = {v: i for i, v in enumerate(effects_all)}

    assert len(costs) <= 128, f"costs={len(costs)} overflows 7-bit cost_idx"
    assert len(weights) <= 256
    assert len(dmgs) <= 256
    assert len(wds) <= 128, f"wds={len(wds)} overflows 7-bit wd_idx (bit 7 = ammo bit)"
    assert len(flags_all) <= 256
    assert len(bonuses_all) <= 256
    assert len(effects_all) <= 256

    rec_bytes = bytearray()
    for it in items:
        c_i = cost_idx[it["cost"]] | (0x80 if it.get("is_depth_variant") else 0x00)
        w_i = wd_idx[(it["weight"], it["dice"], it["sides"])] | (it["missile_type"] & 0x80)
        e_i = effect_idx[(it["flags"], it["p1"], it["tohit"], it["todam"], it["toac"])]
        lm_i = (it["vms_level"] & 0x3F) | ((it["missile_type"] & 0x03) << 6)
        rec_bytes.extend((c_i, w_i, e_i, lm_i))

    cold_costs = b"".join(struct.pack("<H", c) for c in costs)
    cold_weights = b"".join(struct.pack("<H", w) for w in weights)
    cold_dmgs = bytes(b for d, s in dmgs for b in (d, s))
    cold_wds = bytes(b for (w, d, s) in wds for b in (weight_idx[w], dmg_idx[(d, s)]))
    cold_flags = b"".join(struct.pack("<I", f) for f in flags_all)
    cold_bonuses = b"".join(struct.pack("<hbbb", p1, th, td, ta) for (p1, th, td, ta) in bonuses_all)
    cold_effects = bytes(
        b
        for (fl, p1, th, td, ta) in effects_all
        for b in (flag_idx[fl], bonus_idx[(p1, th, td, ta)])
    )
    ego_bytes = bytearray()
    for ego in egos:
        e_i = effect_idx[(ego["flags"], ego["p1"], ego["tohit"], ego["todam"], ego["toac"])]
        ego_bytes.extend(struct.pack("<BH", e_i, ego["cost_delta"]))

    raw_strings = [it["name"] for it in items] + [e["name"] for e in egos] + [f["name"] for f in flavs]
    str_pack = tokenize_and_encode_strings(raw_strings, stride=STR_BLOCK_STRIDE)

    off_records = ITMCAT_HDR_SIZE
    off_costs = off_records + len(rec_bytes)
    off_weights = off_costs + len(cold_costs)
    off_dmgs = off_weights + len(cold_weights)
    off_wds = off_dmgs + len(cold_dmgs)
    off_flags = off_wds + len(cold_wds)
    off_bonuses = off_flags + len(cold_flags)
    off_effects = off_bonuses + len(cold_bonuses)
    off_egos = off_effects + len(cold_effects)
    off_blk_index = off_egos + len(ego_bytes)
    blk_bytes = b"".join(struct.pack("<H", bp) for bp in str_pack["blk_bitpos"])
    off_canon_counts = off_blk_index + len(blk_bytes)
    canon_counts_b = bytes(str_pack["canon_counts"])
    canon_syms_b = bytes(str_pack["canon_syms"])
    off_canon_syms = off_canon_counts + len(canon_counts_b)
    off_stream = off_canon_syms + len(canon_syms_b)
    stream_b = str_pack["stream_bytes"]
    total_size = off_stream + len(stream_b)

    assert total_size <= size_cap, (
        f"ITEM.CAT size {total_size} exceeds hard cap {size_cap} bytes!"
    )

    header = struct.pack(
        "<4sHHBBBBBBBBBBBBBBHHHHH",
        ITMCAT_MAGIC,
        total_size,
        len(items),
        len(egos),
        len(flavs),
        str_pack["tok_count"],
        STR_BLOCK_STRIDE,
        len(costs),
        len(weights),
        len(dmgs),
        len(wds),
        len(flags_all),
        len(bonuses_all),
        len(effects_all),
        len(canon_counts_b) - 1,
        len(canon_syms_b),
        len(str_pack["blk_bitpos"]),
        off_records,
        off_costs,
        off_blk_index,
        off_canon_counts,
        off_stream,
    )
    assert len(header) == ITMCAT_HDR_SIZE

    binary = (
        header
        + bytes(rec_bytes)
        + cold_costs
        + cold_weights
        + cold_dmgs
        + cold_wds
        + cold_flags
        + cold_bonuses
        + cold_effects
        + bytes(ego_bytes)
        + blk_bytes
        + canon_counts_b
        + canon_syms_b
        + stream_b
    )
    assert len(binary) == total_size

    offsets = {
        "total_size": total_size,
        "hdr_size": ITMCAT_HDR_SIZE,
        "records": off_records,
        "records_size": len(rec_bytes),
        "costs": off_costs,
        "costs_size": len(cold_costs),
        "weights": off_weights,
        "weights_size": len(cold_weights),
        "dmgs": off_dmgs,
        "dmgs_size": len(cold_dmgs),
        "wds": off_wds,
        "wds_size": len(cold_wds),
        "flags": off_flags,
        "flags_size": len(cold_flags),
        "bonuses": off_bonuses,
        "bonuses_size": len(cold_bonuses),
        "effects": off_effects,
        "effects_size": len(cold_effects),
        "egos": off_egos,
        "egos_size": len(ego_bytes),
        "blk_index": off_blk_index,
        "blk_index_size": len(blk_bytes),
        "canon_counts": off_canon_counts,
        "canon_counts_size": len(canon_counts_b),
        "canon_syms": off_canon_syms,
        "canon_syms_size": len(canon_syms_b),
        "stream": off_stream,
        "stream_size": len(stream_b),
        "counts": {
            "items": len(items),
            "egos": len(egos),
            "flavours": len(flavs),
            "tokens": str_pack["tok_count"],
            "stride": STR_BLOCK_STRIDE,
            "blk_count": len(str_pack["blk_bitpos"]),
            "costs": len(costs),
            "weights": len(weights),
            "dmgs": len(dmgs),
            "wds": len(wds),
            "flags": len(flags_all),
            "bonuses": len(bonuses_all),
            "effects": len(effects_all),
            "canon_max_len": len(canon_counts_b) - 1,
            "canon_num_syms": len(canon_syms_b),
            "stream_bits": str_pack["total_bits"],
        },
    }
    return binary, offsets


def decode_item_cat(blob: bytes) -> dict:
    """Decode and parse all strings and records directly from an 'ITM2' ITEM.CAT blob."""
    (
        magic,
        total_size,
        item_count,
        ego_count,
        flav_count,
        tok_count,
        stride,
        num_costs,
        num_weights,
        num_dmgs,
        num_wds,
        num_flags,
        num_bonuses,
        num_effects,
        canon_max_len,
        canon_num_syms,
        blk_count,
        off_records,
        off_cold,
        off_blk_index,
        off_canon,
        off_stream,
    ) = struct.unpack_from("<4sHHBBBBBBBBBBBBBBHHHHH", blob, 0)

    assert magic == ITMCAT_MAGIC, f"Bad magic: {magic!r}"
    assert total_size == len(blob) <= ITMCAT_SIZE_CAP

    pos = off_cold
    costs = list(struct.unpack_from(f"<{num_costs}H", blob, pos))
    pos += num_costs * 2
    weights = list(struct.unpack_from(f"<{num_weights}H", blob, pos))
    pos += num_weights * 2
    dmgs = [(blob[pos + 2 * i], blob[pos + 2 * i + 1]) for i in range(num_dmgs)]
    pos += num_dmgs * 2
    wds = [(blob[pos + 2 * i], blob[pos + 2 * i + 1]) for i in range(num_wds)]
    pos += num_wds * 2
    flags_tbl = list(struct.unpack_from(f"<{num_flags}I", blob, pos))
    pos += num_flags * 4
    bonuses = [struct.unpack_from("<hbbb", blob, pos + 5 * i) for i in range(num_bonuses)]
    pos += num_bonuses * 5
    effects = [(blob[pos + 2 * i], blob[pos + 2 * i + 1]) for i in range(num_effects)]
    pos += num_effects * 2
    egos_raw = [struct.unpack_from("<BH", blob, pos + 3 * i) for i in range(ego_count)]
    pos += ego_count * 3
    assert pos == off_blk_index

    blk_bitpos = list(struct.unpack_from(f"<{blk_count}H", blob, off_blk_index))
    canon_counts = list(blob[off_canon : off_canon + canon_max_len + 1])
    canon_syms = list(blob[off_canon + canon_max_len + 1 : off_canon + canon_max_len + 1 + canon_num_syms])
    assert off_canon + canon_max_len + 1 + canon_num_syms == off_stream

    stream = blob[off_stream:]

    def read_entry(entry_id: int) -> list[int]:
        blk = entry_id // stride
        skip = entry_id % stride
        bp = blk_bitpos[blk]

        def read_sym(cur_bp: int) -> tuple[int, int]:
            code = 0
            idx = 0
            for bl in range(1, canon_max_len + 1):
                bit = (stream[cur_bp >> 3] >> (7 - (cur_bp & 7))) & 1
                cur_bp += 1
                code = (code << 1) | bit
                cnt = canon_counts[bl]
                if code < cnt:
                    return canon_syms[idx + code], cur_bp
                code -= cnt
                idx += cnt
            raise ValueError(f"Corrupt canonical Huffman code at bit {cur_bp}")

        for _ in range(skip):
            while True:
                sym, bp = read_sym(bp)
                if sym == 0:
                    break
        out = []
        while True:
            sym, bp = read_sym(bp)
            if sym == 0:
                return out
            out.append(sym)

    base_item = 0
    base_ego = item_count
    base_flav = item_count + ego_count
    base_tok = base_flav + flav_count

    def decode_text(entry_id: int) -> str:
        raw = read_entry(entry_id)
        expanded: list[int] = []
        for sym in raw:
            if sym >= 0x80:
                tok_raw = read_entry(base_tok + (sym - 0x80))
                assert all(0 < b < 0x80 for b in tok_raw), "Non-recursive invariant violated"
                expanded.extend(tok_raw)
            else:
                expanded.append(sym)
        return "".join(screencode_to_char(sc) for sc in expanded)

    decoded_items = []
    for i in range(item_count):
        c_d, w_m, e_i, l_m = blob[off_records + 4 * i : off_records + 4 * i + 4]
        w_idx, d_idx = wds[w_m & 0x7F]
        fl_idx, bn_idx = effects[e_i]
        p1, tohit, todam, toac = bonuses[bn_idx]
        decoded_items.append(
            {
                "id": i,
                "name": decode_text(base_item + i),
                "cost": costs[c_d & 0x7F],
                "is_depth_variant": bool(c_d & 0x80),
                "weight": weights[w_idx],
                "dice": dmgs[d_idx][0],
                "sides": dmgs[d_idx][1],
                "flags": flags_tbl[fl_idx],
                "p1": p1,
                "tohit": tohit,
                "todam": todam,
                "toac": toac,
                "vms_level": l_m & 0x3F,
                "missile_type": (w_m & 0x80) | ((l_m >> 6) & 0x03),
            }
        )

    decoded_egos = []
    for i, (e_i, cost_delta) in enumerate(egos_raw):
        fl_idx, bn_idx = effects[e_i]
        p1, tohit, todam, toac = bonuses[bn_idx]
        decoded_egos.append(
            {
                "id": i + 1,
                "name": decode_text(base_ego + i),
                "cost_delta": cost_delta,
                "flags": flags_tbl[fl_idx],
                "p1": p1,
                "tohit": tohit,
                "todam": todam,
                "toac": toac,
            }
        )

    decoded_flavs = [
        {"id": i, "name": decode_text(base_flav + i)} for i in range(flav_count)
    ]
    return {"items": decoded_items, "egos": decoded_egos, "flavours": decoded_flavs}


def verify_roundtrip(spec: dict, blob: bytes) -> None:
    """Assert bit-exact round-trip equality of all 361 items, 55 egos, and 174 flavors."""
    dec = decode_item_cat(blob)
    for exp, got in zip(spec["items"], dec["items"]):
        for key in (
            "id", "name", "cost", "is_depth_variant", "weight", "dice", "sides",
            "flags", "p1", "tohit", "todam", "toac", "vms_level", "missile_type",
        ):
            assert got[key] == exp[key], f"Item {exp['id']} field {key}: {got[key]!r} != {exp[key]!r}"
    for exp, got in zip(spec["egos"], dec["egos"]):
        for key in ("id", "name", "cost_delta", "flags", "p1", "tohit", "todam", "toac"):
            assert got[key] == exp[key], f"Ego {exp['id']} field {key}: {got[key]!r} != {exp[key]!r}"
    for exp, got in zip(spec["flavours"], dec["flavours"]):
        assert got["name"] == exp["name"], f"Flavour {exp['id']}: {got['name']!r} != {exp['name']!r}"


def _hex_rows(vals: list[int], width: int = 16, comments: list[str] | None = None) -> list[str]:
    if comments is not None:
        return [f"    .byte ${v:02x}  // {c}" for v, c in zip(vals, comments)]
    return ["    .byte " + ", ".join(f"${v:02x}" for v in vals[k : k + width]) for k in range(0, len(vals), width)]


def compute_item_slugs(items: list[dict]) -> dict[int, str]:
    """Derive deterministic, ID-independent uppercase slugs for every catalog item.

    Never embeds logical item IDs or list positions in symbol names so that
    catalog reordering and renumbering preserve every symbol name unchanged:
      - '*X*' greater scrolls/items normalize to 'STAR_X'.
      - VMS gold_list (tval == 100) items normalize under 'GOLD_<NAME>' ('GOLD_COINS'
        for plain 'Gold') and disambiguate multi-entry minerals by intrinsic cost rank.
      - Depth-variant pairs disambiguate by '_L<vms_level>'.
      - Multi-subval VMS items (e.g. Ring/Amulet of Adornment) disambiguate by
        '_VMS_SUB<subval>'.
    """
    def raw_base(it: dict) -> str:
        s = re.sub(r"\*([^*]+)\*", r"STAR_\1", it["name"])
        s = s.replace("'", "")
        s = re.sub(r"[^A-Za-z0-9]+", "_", s).strip("_").upper()
        if it.get("tval") == 100:
            return "GOLD_COINS" if s == "GOLD" else f"GOLD_{s}"
        if it.get("cat") == 9 and s == "SLIME_MOLD":
            return "FOOD_SLIME_MOLD"
        return s

    groups: dict[str, list[dict]] = defaultdict(list)
    for it in items:
        groups[raw_base(it)].append(it)

    out: dict[int, str] = {}
    for base, grp in groups.items():
        if len(grp) == 1:
            out[grp[0]["id"]] = base
            continue
        levels = {x["vms_level"] for x in grp}
        subvals = {x["subval"] for x in grp}
        if len(levels) == len(grp):
            for x in grp:
                out[x["id"]] = f"{base}_L{x['vms_level']}"
        elif len(subvals) == len(grp) and all(x.get("tval") != 100 for x in grp):
            for x in grp:
                out[x["id"]] = f"{base}_VMS_SUB{x['subval']}"
        else:
            ordered = sorted(
                grp,
                key=lambda x: (x["cost"], x.get("vms_source") or "", x["subval"], x["vms_level"]),
            )
            for rank, x in enumerate(ordered, start=1):
                out[x["id"]] = f"{base}_{rank}"

    if len(set(out.values())) != len(items):
        raise ValueError("Duplicate item slug generated")
    for slug in out.values():
        if not re.fullmatch(r"[A-Z][A-Z0-9_]*", slug):
            raise ValueError(f"Invalid item slug {slug!r}")
    return out


def render_item_ids_s(spec: dict) -> str:
    """Render segmentless Kick Assembler item constants (item_ids.s)."""
    items = spec["items"]
    page_size = spec["constants"]["PAGE_SIZE"]
    slugs = compute_item_slugs(items)
    lines = [
        "#importonce",
        "// Generated by tools/build_item_catalog.py from item_catalog_spec.json. Do not edit.",
        "// Segmentless symbolic item IDs, Base-255 slot_lo bytes, and page bits ($00 / $40).",
        "// Safe to #import standalone in unit tests or via core/6502/item_defs.s; emits zero bytes.",
        "",
    ]
    for it in items:
        item_id = it["id"]
        slug = slugs[item_id]
        slot_lo = item_id if item_id < page_size else item_id - page_size
        page_bit = 0x00 if item_id < page_size else ITEM_PAGE_BIT
        lines.extend(
            [
                f"// {it['name']} (cat={it['cat']}, tval={it['tval']}, subval={it['subval']}, vms_level={it['vms_level']})",
                f".const ITEM_{slug} = {item_id}",
                f".const ITEM_SLOT_{slug} = {slot_lo}",
                f".const ITEM_PAGE_{slug} = ${page_bit:02x}",
            ]
        )
    lines.append("")
    return "\n".join(lines)


def render_item_ids_py(spec: dict) -> str:
    """Render Python symbolic item constants and Base-255 helpers (tools/item_ids.py)."""
    items = spec["items"]
    consts = spec["constants"]
    page_size = consts["PAGE_SIZE"]
    slugs = compute_item_slugs(items)
    lines = [
        '"""Generated symbolic item IDs from item_catalog_spec.json. Do not edit.',
        "",
        "Regenerate via: python3 -B tools/build_item_catalog.py --emit-s",
        '"""',
        "from __future__ import annotations",
        "",
        f"ITEM_TYPE_COUNT = {consts['ITEM_TYPE_COUNT']}",
        f"ITEM_PAGE_SIZE = {page_size}",
        f"ITEM_PAGE_BIT = 0x{ITEM_PAGE_BIT:02X}",
        "EGO_ID_MASK = 0x3F",
        "FI_EMPTY = 0xFF",
        "",
    ]
    for it in items:
        item_id = it["id"]
        slug = slugs[item_id]
        slot_lo = item_id if item_id < page_size else item_id - page_size
        page_bit = 0x00 if item_id < page_size else ITEM_PAGE_BIT
        lines.extend(
            [
                f"ITEM_{slug} = {item_id}",
                f"ITEM_SLOT_{slug} = {slot_lo}",
                f"ITEM_PAGE_{slug} = 0x{page_bit:02X}",
            ]
        )
    lines.extend(
        [
            "",
            "SLUG_BY_ID: dict[int, str] = {",
            *[f'    {it["id"]}: "{slugs[it["id"]]}",' for it in items],
            "}",
            "",
            "ID_BY_SLUG: dict[str, int] = {v: k for k, v in SLUG_BY_ID.items()}",
            "",
            "",
            "def item_slot(item_id: int) -> int:",
            '    """Return Base-255 8-bit slot_lo (0..254) for logical item_id."""',
            "    if not (0 <= item_id < ITEM_TYPE_COUNT):",
            '        raise ValueError(f"item_id {item_id} out of range 0..{ITEM_TYPE_COUNT - 1}")',
            "    return item_id if item_id < ITEM_PAGE_SIZE else item_id - ITEM_PAGE_SIZE",
            "",
            "",
            "def item_page(item_id: int) -> int:",
            '    """Return Base-255 page bit (0x00 or ITEM_PAGE_BIT=0x40) for logical item_id."""',
            "    if not (0 <= item_id < ITEM_TYPE_COUNT):",
            '        raise ValueError(f"item_id {item_id} out of range 0..{ITEM_TYPE_COUNT - 1}")',
            "    return 0x00 if item_id < ITEM_PAGE_SIZE else ITEM_PAGE_BIT",
            "",
            "",
            "def pack_item_ego(item_id: int, ego_id: int = 0) -> tuple[int, int]:",
            '    """Pack logical item_id + ego_id into (slot_lo, page_bit | ego_id)."""',
            "    if not (0 <= ego_id <= EGO_ID_MASK):",
            '        raise ValueError(f"ego_id {ego_id} out of range 0..{EGO_ID_MASK}")',
            "    return item_slot(item_id), item_page(item_id) | ego_id",
            "",
            "",
            "def lua_item_consts(*slugs: str) -> str:",
            '    """Emit Lua ITEM_*, ITEM_SLOT_*, and ITEM_PAGE_* constants for MAME harnesses."""',
            '    lines = [f"ITEM_PAGE_BIT = 0x{ITEM_PAGE_BIT:02X}"]',
            "    for slug in slugs:",
            "        item_id = ID_BY_SLUG[slug]",
            '        lines.append(f"ITEM_{slug} = {item_id}")',
            '        lines.append(f"ITEM_SLOT_{slug} = {item_slot(item_id)}")',
            '        lines.append(f"ITEM_PAGE_{slug} = 0x{item_page(item_id):02X}")',
            '    return "\\n".join(lines) + "\\n"',
            "",
        ]
    )
    return "\n".join(lines)


def emit_python_ids(spec: dict, out_path: Path = DEFAULT_PY_OUT) -> None:
    """Write generated Python item constants to out_path."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render_item_ids_py(spec))


def emit_assembly(spec: dict, blob: bytes, offsets: dict, out_dir: Path) -> None:
    """Write segmentless Kick Assembler data and layout files into out_dir."""
    out_dir.mkdir(parents=True, exist_ok=True)
    items = spec["items"]
    flavs = spec["flavours"]
    consts = spec["constants"]
    hdr = "// Generated by tools/build_item_catalog.py from item_catalog_spec.json. Do not edit."

    extra_ac = [it for it in items if it["base_ac"] >= 15]
    it_cat_vals = [it["cat"] for it in items]
    it_col_ac_vals = [((it["color"] & 0x0F) << 4) | min(it["base_ac"], 15) for it in items]
    it_unk_vals = [it["unknown_idx"] for it in items]
    flav_col_vals = [fl["color"] for fl in flavs]

    # 1. item_hot_tables.s (pure constants + data arrays, zero .segment directives)
    hot = [
        hdr,
        "// Segmentless hot item catalog constants and lookup arrays.",
        "// Wrap #import inside Default / AuxData / ResidentItems as required by the port.",
        "",
        "#if !ITEM_DEFS_CONSTS_INCLUDED",
        f".const ITEM_TYPE_COUNT = {consts['ITEM_TYPE_COUNT']}",
        f".const ITEM_PAGE_SIZE = {consts['PAGE_SIZE']}",
        f".const EGO_COUNT = {consts['EGO_COUNT']}",
        f".const FLAVOUR_COUNT = {consts['FLAVOUR_COUNT']}",
        f".const FLAVOUR_POTION_COUNT = {consts['FLAVOUR_POTION_COUNT']}",
        f".const FLAVOUR_SCROLL_COUNT = {consts['FLAVOUR_SCROLL_COUNT']}",
        f".const FLAVOUR_RING_COUNT = {consts['FLAVOUR_RING_COUNT']}",
        f".const FLAVOUR_WAND_COUNT = {consts['FLAVOUR_WAND_COUNT']}",
        f".const FLAVOUR_STAFF_COUNT = {consts['FLAVOUR_STAFF_COUNT']}",
        f".const IT_AC_EXTRA_COUNT = {len(extra_ac)}",
        "#endif",
        "",
        "it_category:",
        *_hex_rows(it_cat_vals, comments=[f"{it['id']}: {it['name']}" for it in items]),
        "",
        "it_color_ac:",
        *_hex_rows(
            it_col_ac_vals,
            comments=[f"{it['id']}: {it['name']} (col=${it['color']:x}, ac={it['base_ac']})" for it in items],
        ),
        "",
        "it_ac_extra_id_lo:",
        *_hex_rows([it["id"] & 0xFF for it in extra_ac], comments=[f"{it['id']}: {it['name']}" for it in extra_ac]),
        "it_ac_extra_id_hi:",
        *_hex_rows([it["id"] >> 8 for it in extra_ac]),
        "it_ac_extra_val:",
        *_hex_rows([it["base_ac"] for it in extra_ac], comments=[f"{it['base_ac']}: {it['name']}" for it in extra_ac]),
        "",
        "it_unknown_idx:",
        *_hex_rows(it_unk_vals, comments=[f"{it['id']}: {it['name']}" for it in items]),
        "",
        "flavour_colors:",
        *_hex_rows(flav_col_vals, comments=[f"{fl['id']} ({fl['class']} {fl['local_idx']}): {fl['name']}" for fl in flavs]),
        "",
    ]
    (out_dir / "item_hot_tables.s").write_text("\n".join(hot))

    # 2. item_cat_layout.s
    cnts = offsets["counts"]
    layout = [
        "#importonce",
        hdr,
        "// Binary 'ITM2' ITEM.CAT layout constants (segmentless).",
        "",
        f".const ITMCAT_SIZE_CAP = {ITMCAT_SIZE_CAP}",
        f".const ITMCAT_TOTAL_SIZE = {offsets['total_size']}",
        f".const ITMCAT_HDR_SIZE = {ITMCAT_HDR_SIZE}",
        "",
        "// 'ITM2' 32-byte header field offsets",
        ".const ITMCAT_HDR_MAGIC = 0           // 4 bytes: 'ITM2'",
        ".const ITMCAT_HDR_TOTAL_SIZE = 4      // 2 bytes: total byte size",
        f".const ITMCAT_HDR_ITEM_COUNT = 6      // 2 bytes: item count ({cnts['items']})",
        ".const ITMCAT_HDR_EGO_COUNT = 8       // 1 byte: ego count (55)",
        ".const ITMCAT_HDR_FLAV_COUNT = 9      // 1 byte: flavour count (174)",
        ".const ITMCAT_HDR_TOK_COUNT = 10      // 1 byte: non-recursive $80+ token count",
        ".const ITMCAT_HDR_STR_STRIDE = 11     // 1 byte: strings per block-index entry",
        ".const ITMCAT_HDR_NUM_COSTS = 12      // 1 byte",
        ".const ITMCAT_HDR_NUM_WEIGHTS = 13    // 1 byte",
        ".const ITMCAT_HDR_NUM_DMGS = 14       // 1 byte",
        ".const ITMCAT_HDR_NUM_WDS = 15        // 1 byte",
        ".const ITMCAT_HDR_NUM_FLAGS = 16      // 1 byte",
        ".const ITMCAT_HDR_NUM_BONUSES = 17    // 1 byte",
        ".const ITMCAT_HDR_NUM_EFFECTS = 18    // 1 byte",
        ".const ITMCAT_HDR_CANON_MAX_LEN = 19  // 1 byte: max Huffman code bit length",
        ".const ITMCAT_HDR_CANON_NUM_SYMS = 20 // 1 byte: canonical symbol count",
        ".const ITMCAT_HDR_BLK_COUNT = 21      // 1 byte: block bitpos entry count",
        ".const ITMCAT_HDR_OFF_RECORDS = 22    // 2 bytes",
        ".const ITMCAT_HDR_OFF_COLD_TABLES = 24 // 2 bytes",
        ".const ITMCAT_HDR_OFF_BLK_INDEX = 26  // 2 bytes",
        ".const ITMCAT_HDR_OFF_CANON = 28      // 2 bytes",
        ".const ITMCAT_HDR_OFF_STREAM = 30     // 2 bytes",
        "",
        f"// Cold item record layout (4 bytes per item ID 0..{cnts['items'] - 1})",
        ".const ITMCAT_REC_SIZE = 4",
        ".const ITMCAT_REC_COST_DEPTH = 0      // bits 0..6 = cost_idx, bit 7 = is_depth_variant",
        ".const ITMCAT_REC_WD_AMMO = 1         // bits 0..6 = wd_idx, bit 7 = is_ammo ($80)",
        ".const ITMCAT_REC_EFFECT_IDX = 2      // index into cold_effects",
        ".const ITMCAT_REC_LVL_MISSILE = 3     // bits 0..5 = vms_level, bits 6..7 = missile family (1..3)",
        ".const ITMCAT_REC_COST_MASK = $7f",
        ".const ITMCAT_REC_DEPTH_BIT = $80",
        ".const ITMCAT_REC_WD_MASK = $7f",
        ".const ITMCAT_REC_AMMO_BIT = $80",
        ".const ITMCAT_REC_LVL_MASK = $3f",
        ".const ITMCAT_REC_MISSILE_SHIFT = 6",
        "",
        "// Deduplicated subtable element strides and string bases",
        ".const ITMCAT_COST_SIZE = 2           // uint16 LE",
        ".const ITMCAT_WEIGHT_SIZE = 2         // uint16 LE (0.1 lb)",
        ".const ITMCAT_DMG_SIZE = 2            // dice, sides",
        ".const ITMCAT_WD_SIZE = 2             // weight_idx, dmg_idx",
        ".const ITMCAT_FLAG_SIZE = 4           // uint32 LE",
        ".const ITMCAT_BONUS_SIZE = 5          // int16 p1, int8 tohit, int8 todam, int8 toac",
        ".const ITMCAT_EFFECT_SIZE = 2         // flags_idx, bonus_idx",
        ".const ITMCAT_EGO_SIZE = 3            // effect_idx, uint16 cost_delta",
        ".const ITMCAT_STR_BASE_ITEM = 0",
        f".const ITMCAT_STR_BASE_EGO = {cnts['items']}",
        f".const ITMCAT_STR_BASE_FLAV = {cnts['items'] + cnts['egos']}",
        f".const ITMCAT_STR_BASE_TOK = {cnts['items'] + cnts['egos'] + cnts['flavours']}",
        ".const ITMCAT_TOK_MIN = $80",
        f".const ITMCAT_MAX_STR_LEN = {max(len(it['name']) for it in items)}",
        f".const ITMCAT_STR_STRIDE = {cnts['stride']}",
        f".const ITMCAT_TOK_COUNT = {cnts['tokens']}",
        f".const ITMCAT_BLK_COUNT = {cnts['blk_count']}",
        f".const ITMCAT_CANON_MAX_LEN = {cnts['canon_max_len']}",
        f".const ITMCAT_CANON_NUM_SYMS = {cnts['canon_num_syms']}",
        "",
        "// Exact byte offsets within ITEM.CAT for this build",
        f".const ITMCAT_OFF_RECORDS = {offsets['records']}",
        f".const ITMCAT_OFF_COSTS = {offsets['costs']}",
        f".const ITMCAT_OFF_WEIGHTS = {offsets['weights']}",
        f".const ITMCAT_OFF_DMGS = {offsets['dmgs']}",
        f".const ITMCAT_OFF_WDS = {offsets['wds']}",
        f".const ITMCAT_OFF_FLAGS = {offsets['flags']}",
        f".const ITMCAT_OFF_BONUSES = {offsets['bonuses']}",
        f".const ITMCAT_OFF_EFFECTS = {offsets['effects']}",
        f".const ITMCAT_OFF_EGOS = {offsets['egos']}",
        f".const ITMCAT_OFF_BLK_INDEX = {offsets['blk_index']}",
        f".const ITMCAT_OFF_CANON_COUNTS = {offsets['canon_counts']}",
        f".const ITMCAT_OFF_CANON_SYMS = {offsets['canon_syms']}",
        f".const ITMCAT_OFF_STREAM = {offsets['stream']}",
        "",
    ]
    (out_dir / "item_cat_layout.s").write_text("\n".join(layout))

    # 3. item_cat_data.s (segmentless packed 'ITM2' byte payload)
    data = [
        "#importonce",
        hdr,
        f"// Segmentless packed 'ITM2' ITEM.CAT payload ({len(blob)} bytes, cap {ITMCAT_SIZE_CAP}).",
        f".assert \"ITEM.CAT exceeds {ITMCAT_SIZE_CAP}-byte cap\", {len(blob)} <= {ITMCAT_SIZE_CAP}, true",
        "item_cat_data:",
        *_hex_rows(list(blob)),
        "item_cat_data_end:",
        "",
    ]
    (out_dir / "item_cat_data.s").write_text("\n".join(data))

    # 4. item_ids.s (segmentless symbolic constants: ITEM_*, ITEM_SLOT_*, ITEM_PAGE_*)
    (out_dir / "item_ids.s").write_text(render_item_ids_s(spec))


def verify_against_vms(spec: dict, vms_src: Path) -> None:
    """Optional cross-check of VMS Moria 4.8 values.inc and misc.inc when supplied."""
    inc = vms_src / "include" if (vms_src / "include" / "values.inc").is_file() else vms_src
    values_path = inc / "values.inc"
    misc_path = inc / "misc.inc"
    if not values_path.is_file() or not misc_path.is_file():
        raise FileNotFoundError(f"Expected values.inc and misc.inc under {inc}")

    values_txt = values_path.read_text()
    misc_txt = misc_path.read_text()
    assert "object_list" in values_txt and "gold_list" in values_txt
    assert "magic_treasure" in misc_txt and "Explosion Device" in misc_txt

    # Verify every spec entry citing object_list:<N> fits 1..344
    for it in spec["items"]:
        src = it.get("vms_source", "")
        if src.startswith("object_list:"):
            idx = int(src.split(":", 1)[1])
            assert 1 <= idx <= 344, f"Out-of-range VMS object_list index {idx} on item {it['id']}"

    # Verify all 55 ego suffixes align with misc.inc (mapping Umoria/Moria8 expansions to VMS tags)
    ego_aliases = {
        "slay animal": "slay monster",
        "of slay animal": "of slay monster",
        "flame": "flame tongue",
        "frost": "frost brand",
        "resist": " r ",
    }
    all_inc_txt = "\n".join(p.read_text(errors="replace") for p in sorted(inc.glob("*.inc")))
    misc_norm = " " + re.sub(r"[^a-z]+", " ", all_inc_txt.lower()) + " "
    for ego in spec["egos"]:
        core = re.sub(r"[^a-z]+", " ", ego["name"].lower()).strip()
        target = ego_aliases.get(core, core)
        assert core in misc_norm or target in misc_norm, (
            f"Ego {ego['id']} {ego['name']!r} ({target!r}) not found in misc.inc"
        )


def run_selftest() -> None:
    """Run offline self-tests verifying layout, bounds, size cap, and round-trip decode."""
    spec = json.loads(DEFAULT_SPEC.read_text())
    validate_spec(spec)
    blob, offsets = build_item_cat(spec)
    assert len(blob) <= ITMCAT_SIZE_CAP, f"Size cap failed: {len(blob)}"
    verify_roundtrip(spec, blob)

    # Confirm ALL 5 committed generated files match item_catalog_spec.json exactly
    import tempfile  # noqa: PLC0415

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        emit_assembly(spec, blob, offsets, tmp_path)
        tmp_py = tmp_path / "item_ids.py"
        emit_python_ids(spec, tmp_py)
        expected_files = (
            (DEFAULT_EMIT_DIR / "item_ids.s", tmp_path / "item_ids.s"),
            (DEFAULT_PY_OUT, tmp_py),
            (DEFAULT_EMIT_DIR / "item_hot_tables.s", tmp_path / "item_hot_tables.s"),
            (DEFAULT_EMIT_DIR / "item_cat_layout.s", tmp_path / "item_cat_layout.s"),
            (DEFAULT_EMIT_DIR / "item_cat_data.s", tmp_path / "item_cat_data.s"),
        )
        for committed_path, generated_path in expected_files:
            assert committed_path.is_file(), f"Missing committed generated file: {committed_path}"
            assert committed_path.read_text(encoding="utf-8") == generated_path.read_text(encoding="utf-8"), (
                f"Committed {committed_path.relative_to(REPO_ROOT)} is out of sync with item_catalog_spec.json"
            )

    # Confirm hot tables contain NO .segment directive and expose required symbols
    hot_s = DEFAULT_EMIT_DIR / "item_hot_tables.s"
    if hot_s.is_file():
        hot_txt = hot_s.read_text()
        assert ".segment" not in hot_txt, "item_hot_tables.s must not declare any .segment"
        for sym in (
            "ITEM_TYPE_COUNT = 361",
            "EGO_COUNT = 55",
            "FLAVOUR_COUNT = 174",
            "FLAVOUR_POTION_COUNT = 46",
            "FLAVOUR_SCROLL_COUNT = 49",
            "FLAVOUR_RING_COUNT = 30",
            "FLAVOUR_WAND_COUNT = 24",
            "FLAVOUR_STAFF_COUNT = 25",
            "IT_AC_EXTRA_COUNT = 9",
            "it_category:",
            "it_color_ac:",
            "it_ac_extra_id_lo:",
            "it_ac_extra_id_hi:",
            "it_ac_extra_val:",
            "it_unknown_idx:",
            "flavour_colors:",
        ):
            assert sym in hot_txt, f"Missing symbol {sym!r} in item_hot_tables.s"

    # Verify size-cap enforcement triggers if exceeded
    cap_caught = False
    try:
        build_item_cat(spec, size_cap=100)
    except AssertionError:
        cap_caught = True
    assert cap_caught, "Size-cap assertion failed to trigger"

    # Canonical Huffman synthetic test with '*' and mixed case
    sample = ["Scroll of *Destruction*", "Amulet of DOOM", "Ring of Gain Strength"]
    packed = tokenize_and_encode_strings(sample)
    assert packed["tok_count"] >= 0 and len(packed["stream_bytes"]) > 0

    # Verify symbolic item ID slugs are unique, ID-free, and reorder/renumber-invariant
    slugs = compute_item_slugs(spec["items"])
    assert len(slugs) == len(spec["items"]) == 361
    renumbered = [dict(it, id=1000 - idx) for idx, it in enumerate(reversed(spec["items"]))]
    renumbered_slugs = compute_item_slugs(renumbered)
    for orig, rev in zip(reversed(spec["items"]), renumbered):
        assert slugs[orig["id"]] == renumbered_slugs[rev["id"]], (
            f"Slug changed under reordering/renumbering: {slugs[orig['id']]} != {renumbered_slugs[rev['id']]}"
        )
    # Verify exact 361-item VMS layout invariants (0 non-gold custom items,
    # Gold small/large #0..1 and Ruined Chest #210 retained, Page 0 = 255 items, Page 1 = 106 items).
    m8_non_gold = [
        it for it in spec["items"]
        if it.get("vms_source") == "m8_custom" and it.get("cat") != 1
    ]
    assert m8_non_gold == [], f"Unexpected non-gold custom items in 361-item spec: {m8_non_gold}"
    assert spec["items"][0]["name"] == "Gold (small)" and spec["items"][1]["name"] == "Gold (large)"
    assert spec["items"][254]["id"] == 254 and spec["items"][255]["id"] == 255
    assert all(it["cat"] in (1, 9, 10, 11, 14, 15, 13, 8, 18, 0, 17, 19, 3, 2, 5, 7) for it in spec["items"][:255])
    assert all(it["cat"] in (6, 4, 2, 12, 16, 20) for it in spec["items"][255:])

    ids_s = DEFAULT_EMIT_DIR / "item_ids.s"
    if ids_s.is_file():
        ids_txt = ids_s.read_text()
        assert ".segment" not in ids_txt and ".byte" not in ids_txt and ".word" not in ids_txt
        assert ids_txt == render_item_ids_s(spec), "Committed item_ids.s is out of sync with item_catalog_spec.json"

    if DEFAULT_PY_OUT.is_file():
        py_txt = DEFAULT_PY_OUT.read_text()
        assert py_txt == render_item_ids_py(spec), "Committed tools/item_ids.py is out of sync with item_catalog_spec.json"
        import item_ids as gen_ids  # noqa: PLC0415

        assert gen_ids.ITEM_TYPE_COUNT == len(spec["items"])
        for it in spec["items"]:
            slug = slugs[it["id"]]
            lid = getattr(gen_ids, f"ITEM_{slug}")
            slot_lo = getattr(gen_ids, f"ITEM_SLOT_{slug}")
            page_bit = getattr(gen_ids, f"ITEM_PAGE_{slug}")
            assert lid == it["id"]
            assert gen_ids.pack_item_ego(lid, 0) == (slot_lo, page_bit)
            assert slot_lo + (gen_ids.ITEM_PAGE_SIZE if page_bit else 0) == lid

    print(
        f"build_item_catalog selftest PASSED: ITEM.CAT={len(blob)}/{ITMCAT_SIZE_CAP} B, "
        f"{len(spec['items'])} items ({len(slugs)} symbolic slugs) + 55 egos + 174 flavours round-tripped cleanly."
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build offline VMS Moria 4.8 ITEM.CAT catalog.")
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC, help="Path to item_catalog_spec.json")
    parser.add_argument("--out", type=Path, help="Output directory for ITEM.CAT and item_catalog_report.json")
    parser.add_argument(
        "--emit-s",
        nargs="?",
        const=DEFAULT_EMIT_DIR,
        type=Path,
        help="Emit item_hot_tables.s, item_cat_layout.s, item_cat_data.s, item_ids.s (+ tools/item_ids.py)",
    )
    parser.add_argument(
        "--emit-py",
        nargs="?",
        const=DEFAULT_PY_OUT,
        type=Path,
        help="Emit Python symbolic item constants (default: tools/item_ids.py)",
    )
    parser.add_argument("--vms-src", type=Path, help="Optional VMS Moria source path for upstream verification")
    parser.add_argument("--selftest", action="store_true", help="Run offline validation and round-trip self-test")
    args = parser.parse_args(argv)

    if args.selftest:
        run_selftest()
        return 0

    spec = json.loads(args.spec.read_text())
    blob, offsets = build_item_cat(spec)
    verify_roundtrip(spec, blob)

    vms_path = args.vms_src or (Path(os.environ["VMS_SRC"]) if os.environ.get("VMS_SRC") else None)
    if vms_path is not None:
        verify_against_vms(spec, vms_path)

    if args.emit_s is not None:
        emit_assembly(spec, blob, offsets, args.emit_s)
        if args.emit_py is None and args.emit_s.resolve() == DEFAULT_EMIT_DIR.resolve():
            emit_python_ids(spec, DEFAULT_PY_OUT)

    if args.emit_py is not None:
        emit_python_ids(spec, args.emit_py)

    if args.out is not None:
        args.out.mkdir(parents=True, exist_ok=True)
        (args.out / "ITEM.CAT").write_bytes(blob)
        report = {
            "total_bytes": len(blob),
            "size_cap": ITMCAT_SIZE_CAP,
            "margin_bytes": ITMCAT_SIZE_CAP - len(blob),
            "offsets": offsets,
        }
        (args.out / "item_catalog_report.json").write_text(json.dumps(report, indent=2) + "\n")

    cnts = offsets["counts"]
    cold_tot = (
        offsets["records_size"]
        + offsets["costs_size"]
        + offsets["weights_size"]
        + offsets["dmgs_size"]
        + offsets["wds_size"]
        + offsets["flags_size"]
        + offsets["bonuses_size"]
        + offsets["effects_size"]
        + offsets["egos_size"]
    )
    str_tot = (
        offsets["blk_index_size"]
        + offsets["canon_counts_size"]
        + offsets["canon_syms_size"]
        + offsets["stream_size"]
    )
    print(
        f"ITEM.CAT: {len(blob)} B (cap {ITMCAT_SIZE_CAP} B, margin {ITMCAT_SIZE_CAP - len(blob)} B) | "
        f"hdr={offsets['hdr_size']} B, cold={cold_tot} B, "
        f"strings={str_tot} B (toks={cnts['tokens']}, blk={offsets['blk_index_size']} B, "
        f"canon={offsets['canon_counts_size'] + offsets['canon_syms_size']} B, stream={offsets['stream_size']} B)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
