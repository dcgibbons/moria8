#!/usr/bin/env python3
"""Report Moria8 product memory, shipping media, and test-variant headroom budgets.

Reads KickAssembler .sym/.vs symbol tables, built .prg/binary outputs, shipping
disk/cartridge images (.d64/.d71/.d81/.po/.atr/.ssd/.crt/.car/.zip), and test
variant artifacts under build/ and build/test/.

Standard library only. Contains zero external host paths.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass, field
import json
import os
from pathlib import Path
import re
import struct
import sys
import tempfile
import unittest
import zipfile

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BUILD_DIR = REPO_ROOT / "build"
TIGHT_THRESHOLD_BYTES = 64

CANONICAL_PORTS = (
    "c64",
    "plus4",
    "c128",
    "apple2",
    "cx16",
    "atari8",
    "bbcmaster",
)

SYM_LINE_RE = re.compile(r"^\s*\.label\s+([A-Za-z0-9_]+)\s*=\s*\$([0-9a-fA-F]+)\b")
VS_LINE_RE = re.compile(r"^\s*al\s+(?:[A-Za-z]:)?([0-9a-fA-F]+)\s+\.([A-Za-z0-9_]+)\b")
TMP_RUN_SEG_RE = re.compile(r"tmp/run\.[^/]+/")
MKTEMP_SUFFIX_RE = re.compile(r"\.[A-Za-z0-9_]{6}(?=/|$)")


@dataclass(frozen=True)
class SegmentSpec:
    name: str
    category: str
    base_addr: int
    ceil_addr: int
    end_sym: str | None = None
    prg_file: str | None = None
    measure: str = "max"  # "max", "sym", "prg", "cache_prg", "cache_sym", "atari_high_tail", "c64_hidden_aux"
    dynamic_ceil_sym: str | None = None
    dynamic_base_sym: str | None = None
    sym_plus_bytes: int = 0
    note: str = ""
    optional: bool = False


@dataclass
class SegmentBudget:
    port: str
    variant: str
    name: str
    category: str
    base_addr: int
    ceil_addr: int
    end_addr: int | None
    sym_end: int | None
    prg_end: int | None
    used_bytes: int | None
    capacity_bytes: int
    free_bytes: int | None
    tight: bool
    overflow: bool
    status: str  # "ok", "tight", "overflow", "missing"
    note: str = ""


@dataclass
class BankSummary:
    port: str
    variant: str
    name: str
    used_units: int
    total_units: int
    unit_label: str
    free_units: int
    note: str = ""


@dataclass
class MediaBudget:
    port: str
    kind: str
    path: str
    used_units: int
    total_units: int
    free_units: int
    unit_label: str
    used_bytes: int | None = None
    capacity_bytes: int | None = None
    free_bytes: int | None = None
    entries_used: int | None = None
    entries_total: int | None = None
    note: str = ""


@dataclass
class TestVariantBudget:
    port: str
    mode: str
    name: str
    source_path: str
    source_kind: str  # "sym", "prg+sym", "prg"
    ceiling_name: str
    base_addr: int
    ceil_addr: int
    end_addr: int
    used_bytes: int
    free_bytes: int | None
    delta_vs_prod: int | None
    tight: bool
    overflow: bool
    extra_checks: list[dict] = field(default_factory=list)
    note: str = ""


def display_path(path: Path, anchor: Path = REPO_ROOT) -> str:
    """Return a clean repo-relative or anchor-relative path without host prefixes."""
    try:
        return path.resolve().relative_to(anchor.resolve()).as_posix()
    except ValueError:
        try:
            return path.resolve().relative_to(REPO_ROOT.resolve()).as_posix()
        except ValueError:
            return path.name


def parse_sym_text(text: str) -> dict[str, int]:
    labels: dict[str, int] = {}
    for line in text.splitlines():
        m = SYM_LINE_RE.match(line)
        if m:
            labels[m.group(1)] = int(m.group(2), 16)
    return labels


def parse_vs_text(text: str) -> dict[str, int]:
    labels: dict[str, int] = {}
    for line in text.splitlines():
        m = VS_LINE_RE.match(line)
        if m:
            labels[m.group(2)] = int(m.group(1), 16)
    return labels


def parse_symbol_file(path: Path) -> dict[str, int]:
    text = path.read_text(encoding="utf-8", errors="replace")
    if path.suffix.lower() == ".vs":
        return parse_vs_text(text)
    return parse_sym_text(text)


def read_prg_span(path: Path) -> tuple[int, int, int]:
    """Return (load_addr, end_excl, payload_bytes) from a 2-byte LE PRG file."""
    data = path.read_bytes()
    if len(data) < 2:
        raise ValueError(f"PRG file too short ({len(data)} bytes): {path.name}")
    load_addr = data[0] | (data[1] << 8)
    payload_bytes = len(data) - 2
    return load_addr, load_addr + payload_bytes, payload_bytes


def measure_segment(
    port: str,
    variant: str,
    build_dir: Path,
    syms: dict[str, int],
    spec: SegmentSpec,
) -> SegmentBudget:
    base_addr = syms[spec.dynamic_base_sym] if (spec.dynamic_base_sym and spec.dynamic_base_sym in syms) else spec.base_addr
    ceil_addr = syms[spec.dynamic_ceil_sym] if (spec.dynamic_ceil_sym and spec.dynamic_ceil_sym in syms) else spec.ceil_addr
    cap_bytes = max(0, ceil_addr - base_addr)

    sym_end: int | None = None
    note = spec.note
    if spec.measure == "atari_high_tail":
        if "id_known_bits" in syms and base_addr <= syms["id_known_bits"] < ceil_addr:
            sym_end = syms["id_known_bits"] + 20
        elif "consol_released" in syms and base_addr <= syms["consol_released"] < ceil_addr:
            sym_end = syms["consol_released"] + 1
    elif spec.measure == "c64_hidden_aux":
        if spec.end_sym and spec.end_sym in syms:
            sym_end = syms[spec.end_sym] + spec.sym_plus_bytes
        elif "recall_data_end" in syms and base_addr <= syms["recall_data_end"] <= ceil_addr:
            sym_end = syms["recall_data_end"]
            if variant == "cart" and "zp_save_buf" not in syms:
                note = "$D700-$DEFF hidden RAM ($DF00-$DFFF REU reserved; msg_history 320B + recall[279] 1,116B active, zp_save_buf omitted on cart)"
            else:
                note = "$D700-$DEFF hidden RAM ($DF00-$DFFF REU reserved; zp_save_buf 142B + msg_history 320B + recall[279] 1,116B)"
        elif "msg_history" in syms:
            sym_end = syms["msg_history"] + 320
            if variant == "cart" and "zp_save_buf" not in syms and sym_end is not None:
                note = "$D700-$DEFF hidden RAM ($DF00-$DFFF REU reserved; msg_history 320B active, zp_save_buf omitted on cart)"
    elif spec.measure == "c128_bank1_high":
        if spec.end_sym and spec.end_sym in syms and base_addr <= syms[spec.end_sym] <= ceil_addr:
            sym_end = syms[spec.end_sym] + spec.sym_plus_bytes
    elif spec.end_sym and spec.end_sym in syms:
        sym_end = syms[spec.end_sym] + spec.sym_plus_bytes
    elif spec.name == "Plus4HighBss" and variant == "cart":
        sym_end = base_addr
        note = "$DF00-$DFFF hidden RAM (unused on cart; disk item.cat 254B sector LRU cache omitted)"

    prg_load: int | None = None
    prg_end: int | None = None
    prg_payload: int | None = None
    raw_size: int | None = None
    if spec.prg_file:
        prg_path = build_dir / spec.prg_file
        if prg_path.is_file():
            if spec.measure == "raw_bin":
                raw_size = prg_path.stat().st_size
            else:
                prg_load, prg_end, prg_payload = read_prg_span(prg_path)

    end_addr: int | None = None
    used_bytes: int | None = None

    if spec.measure in ("sym", "c64_hidden_aux", "atari_high_tail"):
        end_addr = sym_end
        if end_addr is not None:
            used_bytes = max(0, end_addr - base_addr)
    elif spec.measure == "c128_bank1_high":
        if sym_end is not None:
            end_addr = sym_end
            used_bytes = max(0, end_addr - base_addr)
            if prg_end is not None and prg_end > 0xD8B8:
                end_addr = max(end_addr, prg_end)
                used_bytes = max(0, end_addr - base_addr)
        elif prg_end is not None:
            end_addr = prg_end
            used_bytes = max(0, end_addr - base_addr)
    elif spec.measure == "raw_bin":
        if raw_size is not None:
            used_bytes = raw_size
            end_addr = base_addr + raw_size
    elif spec.measure == "prg":
        end_addr = prg_end
        if end_addr is not None:
            used_bytes = prg_payload
    elif spec.measure == "cache_prg":
        if prg_payload is not None:
            used_bytes = prg_payload
            end_addr = base_addr + prg_payload
        elif sym_end is not None and spec.dynamic_base_sym is None:
            # Fallback if only symbol end is known against overlay window base.
            used_bytes = max(0, sym_end - base_addr)
            end_addr = sym_end
    elif spec.measure == "cache_sym":
        # Cache slot comparison where base_addr == 0 and ceil_addr == slot capacity, or window diff.
        if sym_end is not None:
            used_bytes = max(0, sym_end - base_addr)
            end_addr = sym_end
    else:
        candidates = [v for v in (sym_end, prg_end) if v is not None]
        if candidates:
            end_addr = max(candidates)
            used_bytes = max(0, end_addr - base_addr)
            if sym_end is not None and prg_end is not None and sym_end != prg_end:
                diff = prg_end - sym_end
                extra = f"prg ${prg_end:04X} vs sym ${sym_end:04X} ({diff:+d} B)"
                note = f"{note}; {extra}" if note else extra

    if prg_load is not None and spec.measure not in ("cache_prg", "cache_sym") and prg_load != base_addr:
        mismatch = f"prg load ${prg_load:04X} != expected ${base_addr:04X}"
        note = f"{note}; {mismatch}" if note else mismatch

    if end_addr is None or used_bytes is None:
        return SegmentBudget(
            port=port,
            variant=variant,
            name=spec.name,
            category=spec.category,
            base_addr=base_addr,
            ceil_addr=ceil_addr,
            end_addr=None,
            sym_end=sym_end,
            prg_end=prg_end,
            used_bytes=None,
            capacity_bytes=cap_bytes,
            free_bytes=None,
            tight=False,
            overflow=False,
            status="missing",
            note=note,
        )

    free_bytes = ceil_addr - end_addr
    if spec.measure == "cache_prg":
        free_bytes = cap_bytes - used_bytes
    overflow = free_bytes < 0
    tight = free_bytes < TIGHT_THRESHOLD_BYTES
    status = "overflow" if overflow else ("tight" if tight else "ok")
    return SegmentBudget(
        port=port,
        variant=variant,
        name=spec.name,
        category=spec.category,
        base_addr=base_addr,
        ceil_addr=ceil_addr,
        end_addr=end_addr,
        sym_end=sym_end,
        prg_end=prg_end,
        used_bytes=used_bytes,
        capacity_bytes=cap_bytes,
        free_bytes=free_bytes,
        tight=tight,
        overflow=overflow,
        status=status,
        note=note,
    )


def build_port_specs() -> dict[tuple[str, str], list[SegmentSpec]]:
    """Return authoritative segment specifications derived from platform main.s/memory*.s."""
    specs: dict[tuple[str, str], list[SegmentSpec]] = {}

    # C64 overlays shared between disk & cart
    c64_overlays = [
        ("ovl.start", "ovl_start_end"),
        ("ovl.town", "ovl_town_end"),
        ("ovl.death", "ovl_death_end"),
        ("ovl.modal", "ovl_modal_misc_end"),
        ("ovl.gen", "ovl_gen_end"),
        ("ovl.help", "ovl_help_end"),
        ("ovl.ui", "ovl_ui_end"),
        ("ovl.items", "ovl_items_end"),
        ("ovl.spell", "ovl_spell_end"),
        ("ovl.chest", "ovl_chest_end"),
        ("ovl.home", "ovl_home_end"),
        ("ovl.storage", "ovl_storage_end"),
        ("ovl.title", "ovl_title_end"),
    ]
    for variant in ("disk", "cart"):
        s: list[SegmentSpec] = [
            SegmentSpec("Default (Resident)", "resident", 0x0801, 0xC000, end_sym="program_end", measure="sym", note="<= MAP_BASE ($C000)"),
            SegmentSpec(
                "SaveResidentStateProbe",
                "resident_low",
                0x0801,
                0xA000,
                end_sym="c64_save_resident_state_probe_end",
                dynamic_base_sym="c64_save_resident_state_probe_start",
                measure="sym",
                optional=True,
                note="save_resident_state probe < $A000 BASIC ROM",
            ),
            SegmentSpec("InitTail", "init", 0x0801, 0xCE00, end_sym="catalog_init_tail_end", prg_file="moria8.prg", measure="max", note="<= CATALOG_IDX_LOAD ($CE00)"),
            SegmentSpec("C64HuffIndex", "aux", 0xD500, 0xD700, end_sym="huff_str_index_end", measure="sym", note="$D500-$D6FF hidden RAM"),
            SegmentSpec(
                "C64HiddenAux",
                "aux",
                0xD700,
                0xDF00,
                end_sym="c64_hidden_aux_end",
                measure="c64_hidden_aux",
                note="$D700-$DEFF hidden RAM ($DF00-$DFFF reserved for REU; zp_save_buf 142B + msg_history 320B)",
            ),
            SegmentSpec("64.bank", "banked", 0xF000, 0xFFFA, end_sym="banked_code_end", prg_file="64.bank", note="<= $FFFA CPU vectors"),
            SegmentSpec("legalui", "overlay", 0xE000, 0xE600, end_sym="legal_code_end", prg_file="legalui", dynamic_ceil_sym="legal_zp_save", note="<= legal_zp_save"),
        ]
        for fname, sym_name in c64_overlays:
            s.append(SegmentSpec(fname, "overlay", 0xE000, 0xF000, end_sym=sym_name, prg_file=fname))
        specs[("c64", variant)] = s

    # Plus/4 disk & cart
    for variant in ("disk", "cart"):
        s = [
            SegmentSpec("Default (Resident)", "resident", 0x1001, 0xC800, end_sym="program_end", measure="sym", note="<= MAP_BASE ($C800)"),
            SegmentSpec("InitTail", "init", 0x1001, 0xD600, end_sym="catalog_init_tail_end", prg_file="moria4.prg", measure="max", note="<= CATALOG_IDX_LOAD ($D600)"),
            SegmentSpec("Plus4HuffIndex", "aux", 0xDD00, 0xDF00, end_sym="huff_str_index_end", measure="sym", note="$DD00-$DEFF hidden RAM"),
            SegmentSpec(
                "Plus4HighBss",
                "aux",
                0xDF00,
                0xE000,
                end_sym="plus4_high_bss_end",
                measure="sym",
                note="$DF00-$DFFF hidden RAM (item.cat 254B sector LRU cache on disk); $0400-$07FF 1,024B non-gen monster catalog LRU cache window",
            ),
            SegmentSpec("4.bank", "banked", 0xF000, 0xFC00, end_sym="banked_code_end", prg_file="4.bank", note="HARD ceiling < $FC00 (not $FDFF)"),
            SegmentSpec("legalui", "overlay", 0xE000, 0xE600, end_sym="legal_code_end", prg_file="legalui", dynamic_ceil_sym="legal_zp_save", note="<= legal_zp_save"),
        ]
        for fname, sym_name in c64_overlays:
            s.append(SegmentSpec(fname, "overlay", 0xE000, 0xF000, end_sym=sym_name, prg_file=fname))
        specs[("plus4", variant)] = s

    # C128 disk & cart
    c128_overlays = [
        ("ovl.start", "ovl_start_end"),
        ("ovl.town", "ovl_town_end"),
        ("ovl.death", "ovl_death_end"),
        ("ovl.modal", "ovl_modal_misc_end"),
        ("ovl.gen", "ovl_gen_end"),
        ("ovl.help", "ovl_help_end"),
        ("ovl.ui", "ovl_ui_end"),
        ("ovl.items", "ovl_items_end"),
        ("ovl.disarm", "ovl_disarm_end"),
        ("ovl.chest", "ovl_chest_end"),
    ]
    for variant in ("disk", "cart"):
        fdisk_ceil = 0x0FB0 if variant == "cart" else 0x1000
        fdisk_note = "Common <= MMU_COMMON_CART_BASE ($0FB0)" if variant == "cart" else "Common <= $1000"
        s = [
            SegmentSpec("128.proj", "resident_low", 0x0A80, 0x0B00, prg_file="128.proj.prg", measure="prg", note="Common projectile slot"),
            SegmentSpec("128.input", "resident_low", 0x0B00, 0x0C00, prg_file="128.input.prg", measure="prg", note="Common input slot"),
            SegmentSpec("128.fdisk", "resident_low", 0x0D60, fdisk_ceil, end_sym="runtime_common_data_end", prg_file="128.fdisk.prg", note=fdisk_note),
            SegmentSpec("128.runtime", "resident_low", 0x1000, 0x1A00, prg_file="128.runtime.prg", measure="prg", note="<= FLOOR_ITEM_BASE ($1A00)"),
            SegmentSpec("Default (moria128)", "resident", 0x1C01, 0xAF00, end_sym="program_end", prg_file="moria128.prg", note="Consolidated Bank 0 resident <= $AF00"),
        ]
        if variant == "cart":
            s.append(
                SegmentSpec(
                    "cart_reader (MMU_CR=$3A)",
                    "resident_low",
                    0x1C01,
                    0x8000,
                    end_sym="cart_reader_end",
                    dynamic_base_sym="cart_reader_start",
                    measure="sym",
                    optional=True,
                    note="Bank 0 cart reader < $8000 ROM window",
                )
            )
        s.extend([
            SegmentSpec("128.persist", "play_slot", 0xAF00, 0xD000, end_sym="c128_resident_persist_end", prg_file="128.persist.prg", note="$AF00 modal persist slot <= $D000"),
            SegmentSpec("128.play", "play_slot", 0xAF00, 0xD000, end_sym="c128_resident_play_end", prg_file="128.play.prg", note="$AF00 gameplay slot <= $D000"),
            SegmentSpec("128.bank", "banked", 0xF000, 0xFF00, end_sym="banked_code_end", prg_file="128.bank.prg", note="HARD .assert <= $FF00 (MMU page)"),
            SegmentSpec(
                "Bank1DB (Bank1)",
                "aux",
                0x7400,
                0x7A60,
                end_sym="zp_save_buf",
                sym_plus_bytes=142,
                measure="sym",
                optional=True,
                note="Bank 1 recall[279] (1,116B) + zp_save_buf (142B) <= BANK1_TIER_CACHE_BASE ($7A60)",
            ),
            SegmentSpec("128.cat (Bank1)", "aux", 0x7E60, 0x9568, prg_file="128.cat.prg", measure="prg", note="Bank 1 catalog fields"),
            SegmentSpec("128.cnm (Bank1)", "aux", 0xA000, 0xB000, prg_file="128.cnm.prg", measure="prg", note="Bank 1 catalog names"),
            SegmentSpec(
                "Bank1High / 128.cex (Bank1)",
                "aux",
                0xD000,
                0xE000,
                end_sym="msg_history_end",
                prg_file="128.cex.prg",
                measure="c128_bank1_high",
                optional=True,
                note="Bank 1 $D000-$DFFF ($7F NOIO): 128.cex $D000-$D8B7 (2,232B) + store_inv reserve $D8B8-$DCB7 (1,024B) + msg_history $DCB8-$DF37 (640B)",
            ),
            SegmentSpec("128.huff (Bank1)", "aux", 0xF000, 0xFF00, prg_file="128.huff.prg", measure="prg", note="Bank 1 Huffman corpus"),
            SegmentSpec("legalui", "overlay", 0xE000, 0xE600, end_sym="legal_code_end", prg_file="legalui", dynamic_ceil_sym="legal_zp_save", note="<= legal_zp_save"),
            SegmentSpec("cache.ovl.disarm (Bank1)", "cache", 0xE000, 0xE300, prg_file="ovl.disarm", end_sym="ovl_disarm_end", note="Bank 1 cache cap (3 pages = 768 B)"),
            SegmentSpec("cache.ovl.modal (Bank1)", "cache", 0xE000, 0xE500, prg_file="ovl.modal", end_sym="ovl_modal_misc_end", note="Bank 1 cache cap (5 pages = 1,280 B)"),
        ])
        for fname, sym_name in c128_overlays:
            s.append(SegmentSpec(fname, "overlay", 0xE000, 0xF000, end_sym=sym_name, prg_file=fname))
        s.extend([
            SegmentSpec(
                "ovl.home",
                "overlay",
                0xE000,
                0xF000,
                end_sym="ovl_home_end",
                prg_file="ovl.home",
                note="Disk 128.home (uncached #11); OVL_STORAGE=12 active (SAVE_IN_STORAGE_OVERLAY OFF; save/load in 128.persist)",
            ),
            SegmentSpec(
                "ovl.storage",
                "overlay",
                0xE000,
                0xF000,
                end_sym="ovl_storage_end",
                prg_file="ovl.storage",
                optional=True,
                note="Disk 128.storage (uncached #12; cold item commands/exchange/quaff3)",
            ),
            SegmentSpec(
                "ovl.title",
                "overlay",
                0xE000,
                0xF000,
                end_sym="ovl_title_end",
                prg_file="ovl.title",
                optional=True,
                note="Title overlay (optional; C128 uses t128 + ovl.ui)",
            ),
        ])
        specs[("c128", variant)] = s

    # Apple IIe (disk-only)
    a2_overlays = [
        ("ovl.start", "ovl_start_end"),
        ("ovl.town", "ovl_town_end"),
        ("ovl.death", "ovl_death_end"),
        ("ovl.modal", "ovl_modal_misc_end"),
        ("ovl.gen", "ovl_gen_end"),
        ("ovl.help", "ovl_help_end"),
        ("ovl.ui", "ovl_ui_end"),
        ("ovl.items", "ovl_items_end"),
        ("ovl.spell", "ovl_spell_end"),
        ("ovl.chest", "ovl_chest_end"),
        ("ovl.home", "ovl_home_end"),
        ("ovl.storage", "ovl_storage_end"),
        ("ovl.title", "ovl_title_end"),
    ]
    a2_specs = [
        SegmentSpec("Default (moria8a2)", "resident", 0x0A00, 0x7C00, end_sym="program_end", prg_file="moria8a2.prg", note="Main RAM <= A2PlaySlot ($7C00)"),
        SegmentSpec("MainZPSave (zp_save_buf)", "aux", 0x0200, 0x0290, end_sym="zp_save_buf", dynamic_base_sym="zp_save_buf", sym_plus_bytes=142, measure="sym", optional=True, note="Main $0200-$028D zp_save_buf (142 B < $0290 pathname)"),
        SegmentSpec("MainLowScratch", "aux", 0x0301, 0x033C, end_sym="input_kbdbuf_shadow", dynamic_base_sym="a2_probe_buf", sym_plus_bytes=1, measure="sym", optional=True, note="Main $0301-$033A scratch (58 B < $033C door scan)"),
        SegmentSpec("A2PlaySlot (a2.play)", "play_slot", 0x7C00, 0xA000, end_sym="a2_play_end", prg_file="a2.play", note="Main RAM play slot < $A000"),
        SegmentSpec("A2AuxData", "aux", 0x3B0C, 0x5000, prg_file="a2.auxdata", measure="prg", note="Aux RAM $3B0C-$4FFF"),
        SegmentSpec("A2Catalog", "aux", 0x5000, 0x6700, end_sym="catalog_fields_end", prg_file="a2.catalog", note="Aux RAM catalog fields"),
        SegmentSpec("A2HuffData", "aux", 0x8D00, 0xAA00, end_sym="ovl_huffdata_end", prg_file="a2.huffdata", note="Aux cache HUFF+names <= $AA00"),
        SegmentSpec(
            "A2.CATEXT (Aux LC B2)",
            "aux",
            0xD000,
            0xE000,
            prg_file="bin/A2.CATEXT",
            measure="raw_bin",
            optional=True,
            note="Aux LC Bank 2 $D000-$D8B7 extended monster catalog (2,232 B; PackBits A2.CATEXT.PB)",
        ),
        SegmentSpec("BANKED_DATA_END guard", "aux", 0xBA00, 0xBB00, end_sym="BANKED_DATA_END", prg_file=None, measure="sym", optional=True, note="256 B data/tier tail ($BA00-$BAFF); excluded from code cap"),
        SegmentSpec("cache.ovl.ui (Aux)", "cache", 0x0000, 0x0600, prg_file="ovl.ui", measure="cache_prg", note="Aux cache $6700-$6CFF (6 pages)"),
        SegmentSpec("cache.ovl.spell (Aux)", "cache", 0x0000, 0x1400, prg_file="ovl.spell", measure="cache_prg", note="Aux cache $6D00-$80FF (20 pages)"),
        SegmentSpec("cache.ovl.modal (Aux)", "cache", 0x0000, 0x0C00, prg_file="ovl.modal", measure="cache_prg", note="Aux cache $8100-$8CFF (12 pages)"),
        SegmentSpec("cache.ovl.items (Aux)", "cache", 0x0000, 0x1600, prg_file="ovl.items", measure="cache_prg", note="Aux cache $AA00-$BFFF (22 pages)"),
        SegmentSpec("legalui", "overlay", 0xA400, 0xAA00, end_sym="legal_code_end", prg_file="legalui", dynamic_ceil_sym="legal_zp_save", note="<= legal_zp_save"),
    ]
    for fname, sym_name in a2_overlays:
        a2_specs.append(SegmentSpec(fname, "overlay", 0xA400, 0xBA00, end_sym=sym_name, prg_file=fname, note="Code window $A400-$B9FF (5,632 B; $BA00-$BAFF data separate)"))
    specs[("apple2", "disk")] = a2_specs

    # CX16 (disk & cart)
    cx16_overlays = [
        ("OVL.START", "ovl_start_end"),
        ("OVL.TOWN", "ovl_town_end"),
        ("OVL.DEATH", "ovl_death_end"),
        ("OVL.MODAL", "ovl_modal_misc_end"),
        ("OVL.GEN", "ovl_gen_end"),
        ("OVL.HELP", "ovl_help_end"),
        ("OVL.UI", "ovl_ui_end"),
        ("OVL.ITEMS", "ovl_items_end"),
        ("OVL.SPELL", "ovl_spell_end"),
        ("OVL.CHEST", "ovl_chest_end"),
        ("OVL.HOME", "ovl_home_end"),
        ("OVL.STORAGE", "ovl_storage_end"),
        ("OVL.TITLE", "ovl_title_end"),
    ]
    cx16_ovl_notes = {
        "OVL.HOME": "HiRAM Bank 19",
        "OVL.STORAGE": "HiRAM Bank 20",
        "OVL.TITLE": "HiRAM Bank 21",
    }
    for variant in ("disk", "cart"):
        s = [
            SegmentSpec("Default (MORIA8.PRG)", "resident", 0x0801, 0x9B00, end_sym="program_end", prg_file="MORIA8.PRG", note="Unified Resident+Play <= $9B00 tier pool"),
        ]
        if variant == "cart":
            s.append(
                SegmentSpec(
                    "CartLiveHelperLimit ($9980)",
                    "resident_low",
                    0x0801,
                    0x9980,
                    end_sym="program_end",
                    prg_file="MORIA8.PRG",
                    measure="max",
                    optional=True,
                    note="cartridge_test_live.s <= $9980",
                )
            )
        s.extend([
            SegmentSpec("CX16.AUXDATA (Bank 3)", "aux", 0x6000, 0x8000, end_sym="ovl_auxdata_end", prg_file="CX16.AUXDATA", note="8 KB Bank 3 ($6000-$7FFF)"),
            SegmentSpec("CX16.HUFFDATA (Bank 4)", "aux", 0x8000, 0xA000, end_sym="ovl_huffdata_end", prg_file="CX16.HUFFDATA", note="8 KB Bank 4 ($8000-$9FFF)"),
            SegmentSpec("MONSTER.EXT (Bank 5)", "aux", 0xA000, 0xC000, prg_file="MONSTER.EXT", measure="prg", optional=True, note="8 KB Bank 5 ($A000-$BFFF; Phase 5 extended monster catalog)"),
            SegmentSpec("ITEM.CAT (Bank 6)", "aux", 0xA000, 0xC000, prg_file="ITEM.CAT", measure="prg", optional=True, note="8 KB Bank 6 ($A000-$BFFF; 'ITM2' catalog)"),
            SegmentSpec("TITLE (Bank 22)", "aux", 0xA000, 0xC000, prg_file="TITLE", measure="prg", note="8 KB Bank 22 ($A000-$BFFF)"),
            SegmentSpec("MONSTER.CAT (Bank 23)", "aux", 0xA000, 0xC000, end_sym="catalog_bank_end", prg_file="MONSTER.CAT", note="8 KB Bank 23 ($A000-$BFFF)"),
            SegmentSpec("LEGALUI", "overlay", 0xA000, 0xA600, end_sym="legal_code_end", prg_file="LEGALUI", dynamic_ceil_sym="legal_zp_save", note="Bank 24 <= legal_zp_save"),
        ])
        for fname, sym_name in cx16_overlays:
            s.append(SegmentSpec(fname, "overlay", 0xA000, 0xC000, end_sym=sym_name, prg_file=fname, note=cx16_ovl_notes.get(fname, "")))
        specs[("cx16", variant)] = s

    # Atari 8-bit (disk & cart)
    atari_overlays = [
        ("OVL.STA", "ovl_start_end"),
        ("OVL.TWN", "ovl_town_end"),
        ("OVL.DTH", "ovl_death_end"),
        ("OVL.MDL", "ovl_modal_misc_end"),
        ("OVL.GEN", "ovl_gen_end"),
        ("OVL.HLP", "ovl_help_end"),
        ("OVL.UI", "ovl_ui_end"),
        ("OVL.ITM", "ovl_items_end"),
        ("OVL.SPL", "ovl_spell_end"),
        ("OVL.CHS", "ovl_chest_end"),
        ("OVL.HOM", "ovl_home_end"),
        ("OVL.STO", "ovl_storage_end"),
        ("OVL.TTL", "ovl_title_end"),
    ]
    for variant in ("disk", "cart"):
        s = [
            SegmentSpec("LowHelpers", "resident_low", 0x0C00, 0x4000, end_sym="low_helpers_end", measure="sym", note="Low banking/SIO helpers <= $4000"),
            SegmentSpec("Default (MORIA8.RES)", "resident", 0x0C00, 0xC100, end_sym="program_end", prg_file="MORIA8.RES", note="<= MAP_BASE ($C100)"),
            SegmentSpec("HighResident", "aux", 0xDDCE, 0xDF3E, end_sym="high_resident_end", measure="sym", dynamic_base_sym="msg_history_atari", dynamic_ceil_sym="combat_msg_buf", note="$DDCE-$DF3D msg_history (320B) + item_name_decode_buf (48B) <= combat_msg_buf ($DF3E)"),
            SegmentSpec("HighRAM Tail", "aux", 0xDF3E, 0xE000, measure="atari_high_tail", dynamic_base_sym="combat_msg_buf", note="High RAM combat/name/spell/PIW/MD/chest/digit/consol <= $E000"),
            SegmentSpec("ATARI.BNK", "banked", 0xF000, 0xFFFA, end_sym="banked_code_end", prg_file="ATARI.BNK", note="<= $FFFA CPU vectors"),
            SegmentSpec("TITLE.DAT", "aux", 0xC100, 0xC400, prg_file="TITLE.DAT", measure="prg", note="$C100-$C3FF (768 B max)"),
            SegmentSpec("legalui", "overlay", 0xE000, 0xE600, end_sym="legal_code_end", prg_file="legalui", dynamic_ceil_sym="legal_zp_save", note="<= legal_zp_save"),
        ]
        for fname, sym_name in atari_overlays:
            s.append(SegmentSpec(fname, "overlay", 0xE000, 0xF000, end_sym=sym_name, prg_file=fname))
        specs[("atari8", variant)] = s

    # BBC Master 128 (disk-only)
    beeb_overlays = [
        ("ovl.start", "ovl_start_end"),
        ("ovl.town", "ovl_town_end"),
        ("ovl.death", "ovl_death_end"),
        ("ovl.modal", "ovl_modal_misc_end"),
        ("ovl.gen", "ovl_gen_end"),
        ("ovl.help", "ovl_help_end"),
        ("ovl.ui", "ovl_ui_end"),
        ("ovl.items", "ovl_items_end"),
        ("ovl.spell", "ovl_spell_end"),
        ("ovl.chest", "ovl_chest_end"),
        ("ovl.home", "ovl_home_end"),
        ("ovl.storage", "ovl_storage_end"),
        ("ovl.title", "ovl_title_end"),
    ]
    beeb_specs = [
        SegmentSpec("LowHelpers", "resident_low", 0x0E00, 0x3000, end_sym="low_helpers_end", measure="sym", note="Main RAM helpers <= LYNNE ($3000)"),
        SegmentSpec("Default (moria8.res)", "resident", 0x0E00, 0x8000, end_sym="program_end", prg_file="moria8.res.prg", note="Main RAM <= SWR window ($8000)"),
        SegmentSpec("BeebPlaySlot (beeb.play)", "play_slot", 0x8000, 0xA400, end_sym="beeb_play_end", prg_file="beeb.play", note="SWR Bank 4 play slot <= $A400"),
        SegmentSpec("ANDY (beeb.huffdata)", "aux", 0x8000, 0x8F00, end_sym="ovl_huffdata_end", prg_file="beeb.huffdata", dynamic_ceil_sym="zp_save_buf", note="ANDY $8000-$8EFF <= zp_save_buf ($8F00)"),
        SegmentSpec("ANDY (zp_save_buf)", "aux", 0x8F00, 0x9000, end_sym="zp_save_buf", dynamic_base_sym="zp_save_buf", sym_plus_bytes=174, measure="sym", note="ANDY $8F00-$8FAD ZP save (174 B <= $9000)"),
        SegmentSpec("BeebLynneAux", "aux", 0x3F80, 0x4400, end_sym="beeb_lynne_aux_end", measure="sym", note="LYNNE $3F80-$43FF (recall[279] 1,116 B <= $4400 bitmap)"),
        SegmentSpec("BeebAuxData (Bank 6)", "aux", 0x6000, 0x7300, end_sym="ovl_auxdata_end", prg_file="beeb.auxdata", note="SWR Bank 6 $8000-$92FF (19 pages; virtual $6000-$72FF; $9300-$94FF = 2p ITEMCAT)"),
        SegmentSpec("BeebCatalog (Bank 6)", "aux", 0x9500, 0xBA00, end_sym="beeb_catalog_end", prg_file="beeb.catalog", note="SWR Bank 6 catalog (37 pages; $9500-$B9FF)"),
        SegmentSpec(
            "MONEXT (DFS)",
            "aux",
            0x0000,
            9 * 256,
            prg_file="bin/MON.EXT",
            measure="raw_bin",
            optional=True,
            note="DFS MONEXT (279 x 8 B = 2,232 B in 9 sectors; streamed 8 B/species via < $3000 OSGBPB A=3)",
        ),
        SegmentSpec("cache.ovl.modal (Bank 5)", "cache", 0x0000, 12 * 256, prg_file="ovl.modal", measure="cache_prg", note="SWR Bank 5 $B400-$BFFF (12 pages)"),
        SegmentSpec("cache.ovl.ui (Bank 6)", "cache", 0x0000, 6 * 256, prg_file="ovl.ui", measure="cache_prg", note="SWR Bank 6 $BA00-$BFFF (6 pages)"),
        SegmentSpec("cache.ovl.spell (Bank 7)", "cache", 0x0000, 21 * 256, prg_file="ovl.spell", measure="cache_prg", note="SWR Bank 7 $8000-$94FF (21 pages)"),
        SegmentSpec("cache.ovl.items (Bank 7)", "cache", 0x0000, 23 * 256, prg_file="ovl.items", measure="cache_prg", note="SWR Bank 7 $9500-$ABFF (23 pages)"),
        SegmentSpec("cache.ovl.gen (Bank 7)", "cache", 0x0000, 16 * 256, prg_file="ovl.gen", measure="cache_prg", note="SWR Bank 7 $AC00-$BBFF (16 pages; $BC00-$BFFF = 4p ITEMCAT)"),
        SegmentSpec("legalui", "overlay", 0xA800, 0xAE00, end_sym="legal_code_end", prg_file="legalui", dynamic_ceil_sym="legal_zp_save", note="<= legal_zp_save"),
    ]
    for fname, sym_name in beeb_overlays:
        ovl_note = "DFS OVLHOM ($A800-$BFFF)" if fname == "ovl.home" else ""
        beeb_specs.append(SegmentSpec(fname, "overlay", 0xA800, 0xC000, end_sym=sym_name, prg_file=fname, note=ovl_note))
    specs[("bbcmaster", "disk")] = beeb_specs

    return specs


def _parse_vice_crt_chips(raw: bytes, filename: str) -> tuple[int, list[tuple[int, int, int, bytes]]]:
    if len(raw) < 64 or not raw[:16].endswith(b"CARTRIDGE   ") and not raw[:16].startswith((b"C64 CARTRIDGE", b"PLUS4 CARTRIDGE", b"C128 CARTRIDGE")):
        raise ValueError(f"Unrecognized cartridge signature in {filename}")
    hdr_len = struct.unpack_from(">I", raw, 16)[0]
    hw_type = struct.unpack_from(">H", raw, 22)[0]
    pos = hdr_len
    chips: list[tuple[int, int, int, bytes]] = []
    while pos + 16 <= len(raw):
        magic, pkt_len, _ctype, bank, addr, size = struct.unpack_from(">4sIHHHH", raw, pos)
        if magic != b"CHIP" or pkt_len < 16 or pos + pkt_len > len(raw):
            raise ValueError(f"Corrupt CHIP packet in {filename} at {pos}")
        chips.append((bank, addr, size, raw[pos + 16 : pos + 16 + size]))
        pos += pkt_len
    return hw_type, chips


def _count_c128_md128_slots(build_dir: Path) -> int | None:
    crt_path = build_dir.parent / "moria8-c128.crt"
    if crt_path.is_file():
        try:
            _hw_type, chips = _parse_vice_crt_chips(crt_path.read_bytes(), crt_path.name)
            for bank, addr, _size, data in chips:
                if bank == 0 and addr == 0x8000 and len(data) >= 0x200:
                    dir_bytes = data[0x100:0x200]
                    return sum(1 for i in range(32) if dir_bytes[i * 8 : (i + 1) * 8] != b"\xff" * 8)
            for bank, _addr, _size, data in chips:
                if bank == 0 and len(data) >= 0x200:
                    dir_bytes = data[0x100:0x200]
                    return sum(1 for i in range(32) if dir_bytes[i * 8 : (i + 1) * 8] != b"\xff" * 8)
        except (OSError, ValueError):
            pass

    for jpath in (
        build_dir / "moria8-c128.json",
        build_dir.parent / "c128-cart" / "moria8-c128.json",
        build_dir.parent / "moria8-c128.json",
    ):
        if jpath.is_file():
            try:
                jdata = json.loads(jpath.read_text(encoding="utf-8"))
                assets = jdata.get("assets")
                if isinstance(assets, list):
                    return len(assets)
            except Exception:
                pass
    return None


def _collect_atari_xe_bank_stats(build_dir: Path, syms: dict[str, int]) -> dict | None:
    xe_keys = ("XE_BANK0_USED_PAGES", "XE_BANK1_USED_PAGES", "XE_BANK2_USED_PAGES", "XE_BANK3_USED_PAGES")
    if all(k in syms for k in xe_keys):
        banks = [syms[k] for k in xe_keys]
        used_pages = sum(banks)
        bank3_free = syms.get("XE_BANK3_FREE_PAGES", max(0, 64 - banks[3]))
        return {
            "banks": banks,
            "used_pages": used_pages,
            "total_pages": 256,
            "free_pages": max(0, 256 - used_pages),
            "bank3_free": bank3_free,
            "bank3_free_hi": max(0x40, 0x80 - bank3_free),
        }

    table_syms = ("xe_slot_portb", "xe_slot_win_hi", "xe_slot_pages")
    res_path = build_dir / "MORIA8.RES"
    if not all(k in syms for k in table_syms) or not res_path.is_file():
        return None
    try:
        res_start, _end, _payload_len = read_prg_span(res_path)
        payload = res_path.read_bytes()[2:]
    except (OSError, ValueError):
        return None

    slot_count = syms["xe_slot_win_hi"] - syms["xe_slot_portb"]
    if not (1 <= slot_count <= 32):
        return None
    tables: list[bytes] = []
    for key in table_syms:
        off = syms[key] - res_start
        if off < 0 or off + slot_count > len(payload):
            return None
        tables.append(payload[off : off + slot_count])

    portb_to_bank = {0xE2: 0, 0xE6: 1, 0xEA: 2, 0xEE: 3}
    banks = [0, 0, 0, 0]
    bank_max_hi = [0x40, 0x40, 0x40, 0x40]
    for pb, win_hi, pages in zip(*tables):
        bank = portb_to_bank.get(pb)
        if bank is None:
            return None
        banks[bank] += pages
        bank_max_hi[bank] = max(bank_max_hi[bank], win_hi + pages)

    used_pages = sum(banks)
    bank3_free = max(0, 0x80 - bank_max_hi[3])
    return {
        "banks": banks,
        "slot_count": slot_count,
        "used_pages": used_pages,
        "total_pages": 256,
        "free_pages": max(0, 256 - used_pages),
        "bank3_free": bank3_free,
        "bank3_free_hi": bank_max_hi[3],
    }


def collect_bank_summaries(port: str, variant: str, build_dir: Path, syms: dict[str, int]) -> list[BankSummary]:
    out: list[BankSummary] = []
    if port == "c128":
        if variant == "cart":
            md128_used = _count_c128_md128_slots(build_dir)
            if md128_used is not None:
                out.append(BankSummary(
                    port=port,
                    variant=variant,
                    name="MD128 Directory Slots",
                    used_units=md128_used,
                    total_units=32,
                    unit_label="dir slots",
                    free_units=max(0, 32 - md128_used),
                    note=f"MD128 {md128_used}/32 dir slots (C128M-011)",
                ))
        cex_path = build_dir / "128.cex.prg"
        b1_msg_end = syms.get("msg_history_end")
        if (b1_msg_end is not None and 0xD000 < b1_msg_end <= 0xE000) or cex_path.is_file():
            b1_used = (b1_msg_end - 0xD000) if (b1_msg_end is not None and 0xD000 < b1_msg_end <= 0xE000) else 3896
            b1_free = max(0, 4096 - b1_used)
            b1_note = (
                f"Bank 1 $D000-$DFFF ($7F NOIO): 128.cex $D000-$D8B7 (2,232 B) + "
                f"store_inv reserve $D8B8-$DCB7 (1,024 B) + msg_history $DCB8-${0xD000 + b1_used - 1:04X} (640 B); "
                f"${0xD000 + b1_used:04X}-$DFFF free ({b1_free} B)"
            )
        else:
            b1_used = 0
            b1_free = 4096
            b1_note = "Bank 1 $D000-$DFFF (4 KB) C128M-002 spike-verified"
        out.append(BankSummary(
            port=port,
            variant=variant,
            name="Bank 1 High RAM ($D000-$DFFF)",
            used_units=b1_used,
            total_units=4096,
            unit_label="bytes",
            free_units=b1_free,
            note=b1_note,
        ))
    elif port == "apple2":
        pak_path = (build_dir / "bin" / "MORIA8.PAK") if (build_dir / "bin" / "MORIA8.PAK").is_file() else (build_dir / "MORIA8.PAK")
        if pak_path.is_file():
            try:
                pak_data = pak_path.read_bytes()
                if pak_data:
                    pak_used = pak_data[0]
                    out.append(BankSummary(
                        port=port,
                        variant=variant,
                        name="MORIA8.PAK Entries",
                        used_units=pak_used,
                        total_units=42,
                        unit_label="entries",
                        free_units=max(0, 42 - pak_used),
                        note=f"MORIA8.PAK {pak_used}/42 entries ({len(pak_data):,} B)",
                    ))
            except OSError:
                pass
        po_path = build_dir.parent / "moria8-apple2.po"
        if po_path.is_file():
            try:
                po_mb = parse_prodos_po(po_path, port)
                out.append(BankSummary(
                    port=port,
                    variant=variant,
                    name="ProDOS Disk (moria8-apple2.po)",
                    used_units=po_mb.used_units,
                    total_units=po_mb.total_units,
                    unit_label="blocks",
                    free_units=po_mb.free_units,
                    note=f".po {po_mb.free_units}/{po_mb.total_units} free blocks ({po_mb.free_bytes:,} B)",
                ))
            except (OSError, ValueError):
                pass
        if "a2_aux_scratch_base" in syms and "a2_aux_scratch_end" in syms:
            aux_base = syms["a2_aux_scratch_base"]
            aux_end = syms["a2_aux_scratch_end"]
            aux_sz = max(0, aux_end - aux_base + 1)
            parts: list[str] = []
            if "zp_save_buf" in syms:
                zp_b = syms["zp_save_buf"]
                parts.append(f"Main ${zp_b:04X}-${zp_b + 141:04X} zp_save_buf")
            if "a2_probe_buf" in syms and "input_kbdbuf_shadow" in syms:
                sc_b = syms["a2_probe_buf"]
                sc_e = syms["input_kbdbuf_shadow"]
                parts.append(f"Main ${sc_b:04X}-${sc_e:04X} ({sc_e - sc_b + 1} B scratch)")
            parts.append(f"Aux ${aux_base:04X}-${aux_end:04X} ({aux_sz} B)")
            out.append(BankSummary(
                port=port,
                variant=variant,
                name="Aux Scratch ($0200-$03FF)",
                used_units=0,
                total_units=aux_sz,
                unit_label="bytes",
                free_units=aux_sz,
                note="; ".join(parts),
            ))
        if "a2_aux_scratch_base" in syms or pak_path.is_file() or po_path.is_file():
            item_cat_bin = build_dir / "bin" / "ITEM.CAT"
            catext_bin = build_dir / "bin" / "A2.CATEXT"
            if item_cat_bin.is_file() and catext_bin.is_file():
                icat_sz = item_cat_bin.stat().st_size
                cext_sz = catext_bin.stat().st_size
                lc_used = 1116 + cext_sz + icat_sz
                lc_free = max(0, 16378 - lc_used)
                lc_note = (
                    f"Aux LC Bank 1 & Bank 2 ($D000-$FFF9, ~16 KB): Bank 1 $D000-$D45B recall[279] (1,116 B) + "
                    f"Bank 2 $D000-${0xD000 + cext_sz - 1:04X} A2.CATEXT ({cext_sz:,} B) + "
                    f"High RAM $E000-${0xE000 + icat_sz - 1:04X} ITEM.CAT ({icat_sz:,} B)"
                )
            elif item_cat_bin.is_file():
                icat_sz = item_cat_bin.stat().st_size
                lc_used = 1116 + icat_sz
                lc_free = max(0, 16378 - lc_used)
                lc_note = (
                    f"Aux LC Bank 1 & Bank 2 ($D000-$FFF9, ~16 KB): Bank 1 $D000-$D45B recall[279] (1,116 B) + "
                    f"High RAM $E000-${0xE000 + icat_sz - 1:04X} ITEM.CAT ({icat_sz:,} B)"
                )
            else:
                lc_used = 0
                lc_free = 16378
                lc_note = "MAME spike-verified Aux LC Bank 1 & Bank 2 ($D000-$FFF9, ~16 KB)"
            out.append(BankSummary(
                port=port,
                variant=variant,
                name="Aux Language Card ($D000-$FFF9)",
                used_units=lc_used,
                total_units=16378,
                unit_label="bytes",
                free_units=lc_free,
                note=lc_note,
            ))
    elif port == "cx16":
        # platforms/cx16/memory.s allocates Banks 0-4, Bank 5 (MONSTER.EXT), Bank 6 (ITEM.CAT),
        # and Banks 9-24 (13 overlays incl. Bank 19 OVL.HOME, Bank 22 TITLE, Bank 23 MONSTER.CAT, Bank 24 LEGALUI):
        # 23 allocated banks out of 64; Banks 7-8 + Banks 25-63 (41 banks = 328 KB) are free.
        has_item_cat = (build_dir / "ITEM.CAT").is_file()
        has_mon_ext = (build_dir / "MONSTER.EXT").is_file()
        used_banks = 21 + int(has_item_cat) + int(has_mon_ext)
        total_banks = 64
        free_banks = total_banks - used_banks
        if has_item_cat and has_mon_ext:
            cx16_note = (
                f"Banks 0-6 (MONSTER.EXT Bank 5, ITEM.CAT Bank 6) & 9-24 (OVL.HOME Bank 19, OVL.STORAGE..LEGALUI Banks 20-24); "
                f"free: Banks 7-8 and Banks 25-63 ({free_banks * 8} KB free)"
            )
        elif has_item_cat:
            cx16_note = (
                f"Banks 0-4, 6 (ITEM.CAT), & 9-24 (OVL.HOME Bank 19, OVL.STORAGE..LEGALUI Banks 20-24); "
                f"free: CX16_BANK_CATALOG_EXT (Bank 5), Banks 7-8, and Banks 25-63 ({free_banks * 8} KB free)"
            )
        else:
            cx16_note = (
                f"Banks 0-4 & 9-24 (OVL.HOME Bank 19, OVL.STORAGE..LEGALUI Banks 20-24); "
                f"free: CX16_BANK_CATALOG_EXT (Bank 5), Banks 6-8, and Banks 25-63 ({free_banks * 8} KB free)"
            )
        out.append(BankSummary(
            port=port,
            variant=variant,
            name="HiRAM Banks ($A000-$BFFF)",
            used_units=used_banks,
            total_units=total_banks,
            unit_label="8KB banks",
            free_units=free_banks,
            note=cx16_note,
        ))
    elif port == "atari8":
        if variant == "disk":
            xe = _collect_atari_xe_bank_stats(build_dir, syms)
            if xe is not None:
                slots_str = f" (Slots 0..{xe['slot_count'] - 1})" if xe.get("slot_count") else ""
                if xe["bank3_free"] > 0:
                    free_tail_str = (
                        f"{xe['bank3_free']} contiguous free ({xe['bank3_free'] * 256:,} B at Bank 3 "
                        f"${xe['bank3_free_hi']:02X}00-$7FFF)"
                    )
                else:
                    free_tail_str = "0 contiguous free (Bank 3 $4000-$7FFF full)"
                out.append(BankSummary(
                    port=port,
                    variant=variant,
                    name="130XE Extended RAM Pages",
                    used_units=xe["used_pages"],
                    total_units=xe["total_pages"],
                    unit_label="256B pages",
                    free_units=xe["free_pages"],
                    note=(
                        f"Banks 0/1/2/3={xe['banks'][0]}/{xe['banks'][1]}/{xe['banks'][2]}/{xe['banks'][3]}/64p{slots_str}; "
                        f"{free_tail_str}"
                    ),
                ))
    elif port == "bbcmaster":
        # SWR Banks 5-7 layout per cache_layout.s:
        # Bank 5: Map ($8000-$B30B -> 52 pages) + OVL.MODAL (12 pages) = 64/64 pages
        # Bank 6: BeebAuxData (19 pages) + ITEMCAT (2 pages) + BeebCatalog (37 pages) + OVL.UI (6 pages) = 64/64 pages
        # Bank 7: OVL.SPELL (21) + OVL.ITEMS (23) + OVL.GEN (16) + ITEMCAT (4) = 64/64 pages
        # Bank 4: BeebPlaySlot (36 pages $8000-$A3FF) + TierNamePool (4 pages $A400-$A7FF) + Window (24 pages $A800-$BFFF) = 64/64 pages
        if "beeb_lynne_aux_end" in syms:
            lynne_used = max(0, syms["beeb_lynne_aux_end"] - 0x3F80)
            lynne_free = max(0, 0x4400 - syms["beeb_lynne_aux_end"])
        else:
            lynne_used = 160
            lynne_free = 992
        out.append(BankSummary(
            port=port,
            variant=variant,
            name="SWR Banks 4-7 Pages",
            used_units=256,
            total_units=256,
            unit_label="256B pages",
            free_units=0,
            note=f"Banks 4/5/6/7 = 64/64 each; BeebLynneAux active ({lynne_used:,}/1,152 B used, {lynne_free:,} B free)",
        ))
    return out


# ---------------- Shipping Media Parsers ----------------

def parse_cbm_disk(path: Path, port: str) -> MediaBudget:
    data = path.read_bytes()
    ext = path.suffix.lower()
    if ext == ".d64":
        tracks = 40 if len(data) >= 196608 else 35
        if len(data) < 358 * 256:
            raise ValueError(f"Truncated D64 image: {path.name}")
        bam = data[357 * 256 : 358 * 256]
        # Track 18 (index 17) is directory/BAM track; CBM DOS counts free data blocks excluding Track 18.
        total_sectors_per_track = (
            [21] * 17 + [19] * 7 + [17] * 6 + [17] * 5 + ([17] * 5 if tracks == 40 else [])
        )
        free_blocks = sum(bam[4 + t * 4] for t in range(tracks) if t != 17)
        total_blocks = sum(total_sectors_per_track[t] for t in range(tracks) if t != 17)
        return MediaBudget(
            port=port,
            kind="d64",
            path="",
            used_units=total_blocks - free_blocks,
            total_units=total_blocks,
            free_units=free_blocks,
            unit_label="blocks",
            note=f"{tracks}-track CBM BAM (dir Track 18 free={bam[4 + 17 * 4]})",
        )
    if ext == ".d71":
        if len(data) < 349696:
            raise ValueError(f"Truncated D71 image: {path.name}")
        bam1 = data[357 * 256 : 358 * 256]
        side1_free = sum(bam1[4 + t * 4] for t in range(35) if t != 17)
        side2_free = sum(bam1[0xDD + t] for t in range(35) if t != 17)
        free_blocks = side1_free + side2_free
        total_blocks = 664 * 2
        return MediaBudget(
            port=port,
            kind="d71",
            path="",
            used_units=total_blocks - free_blocks,
            total_units=total_blocks,
            free_units=free_blocks,
            unit_label="blocks",
            note=f"Side1={side1_free} free + Side2={side2_free} free (excl Track 18/53)",
        )
    if ext == ".d81":
        if len(data) < 819200:
            raise ValueError(f"Truncated D81 image: {path.name}")
        # Track 40 (1-based) starts at sector 39 * 40 = 1560. BAM1=sec 1, BAM2=sec 2.
        bam1 = data[1561 * 256 : 1562 * 256]
        bam2 = data[1562 * 256 : 1563 * 256]
        side1_free = sum(bam1[16 + t * 6] for t in range(40) if t != 39)
        side2_free = sum(bam2[16 + t * 6] for t in range(40))
        free_blocks = side1_free + side2_free
        total_blocks = 79 * 40
        return MediaBudget(
            port=port,
            kind="d81",
            path="",
            used_units=total_blocks - free_blocks,
            total_units=total_blocks,
            free_units=free_blocks,
            unit_label="blocks",
            note=f"Side1={side1_free} + Side2={side2_free} free (excl Track 40)",
        )
    raise ValueError(f"Unsupported CBM disk format: {path.name}")


def parse_prodos_po(path: Path, port: str = "apple2") -> MediaBudget:
    data = path.read_bytes()
    if len(data) < 7 * 512:
        raise ValueError(f"ProDOS image too small: {path.name}")
    vh = data[2 * 512 : 3 * 512]
    bitmap_blk, total_blocks = struct.unpack_from("<HH", vh, 0x27)
    if total_blocks == 0 or (bitmap_blk + (total_blocks + 4095) // 4096) * 512 > len(data):
        raise ValueError(f"Invalid ProDOS volume header in {path.name}")
    bm_start = bitmap_blk * 512
    bm = data[bm_start : bm_start + ((total_blocks + 4095) // 4096) * 512]
    free_blocks = 0
    for b in range(total_blocks):
        if (bm[b >> 3] >> (7 - (b & 7))) & 1:
            free_blocks += 1
    return MediaBudget(
        port=port,
        kind="po",
        path="",
        used_units=total_blocks - free_blocks,
        total_units=total_blocks,
        free_units=free_blocks,
        unit_label="blocks",
        used_bytes=(total_blocks - free_blocks) * 512,
        capacity_bytes=total_blocks * 512,
        free_bytes=free_blocks * 512,
        note=f"ProDOS 512B blocks (bitmap blk {bitmap_blk})",
    )


def parse_atari_atr(path: Path, port: str = "atari8") -> MediaBudget:
    data = path.read_bytes()
    if len(data) < 16:
        raise ValueError(f"ATR file too small: {path.name}")
    magic, _para_lo, sec_sz = struct.unpack_from("<HHH", data, 0)
    if magic != 0x0296 or sec_sz == 0:
        raise ValueError(f"Invalid ATR magic/sector size in {path.name}")
    body = data[16:]
    # Boot sectors 1..3 are always 128 bytes; rest are sec_sz bytes (128 for SD/ED).
    def sector_offset(sec_1based: int) -> int:
        if sec_1based <= 3:
            return (sec_1based - 1) * 128
        return 3 * 128 + (sec_1based - 4) * sec_sz

    vtoc_off = sector_offset(360)
    if vtoc_off + 128 > len(body):
        raise ValueError(f"ATR missing VTOC sector 360: {path.name}")
    vtoc = body[vtoc_off : vtoc_off + sec_sz]
    total_low, free_low = struct.unpack_from("<HH", vtoc, 1)

    total_secs_in_img = 3 + max(0, (len(body) - 3 * 128) // sec_sz)
    free_high = 0
    total_units = total_low
    if total_secs_in_img >= 1024:
        vtoc2_off = sector_offset(1024)
        if vtoc2_off + 128 <= len(body):
            vtoc2 = body[vtoc2_off : vtoc2_off + sec_sz]
            free_high = struct.unpack_from("<H", vtoc2, 122)[0]
            # DOS 2.5 ED has sectors 1..1023 addressable (sectors 720..1023 = 303 high sectors; total data = 1010, max sector = 1023).
            total_units = 1023
    dir_used = 0
    dir_total = 64
    sec368_off = sector_offset(368)
    if sec368_off + 128 <= len(body):
        for sec in range(361, 369):
            d_off = sector_offset(sec)
            for idx in range(8):
                flags = body[d_off + idx * 16]
                if flags != 0 and not (flags & 0x80):
                    dir_used += 1

    free_total = free_low + free_high
    return MediaBudget(
        port=port,
        kind="atr",
        path="",
        used_units=max(0, total_units - free_total),
        total_units=total_units,
        free_units=free_total,
        unit_label="sectors",
        entries_used=dir_used,
        entries_total=dir_total,
        note=f"DOS 2.5 {dir_used}/{dir_total} files (free_low={free_low}, free_high={free_high}, sec_sz={sec_sz}B)",
    )


def parse_bbc_ssd(path: Path, port: str = "bbcmaster") -> MediaBudget:
    data = path.read_bytes()
    if len(data) < 512:
        raise ValueError(f"SSD file too small: {path.name}")
    s1 = data[256:512]
    num_entries = s1[5] // 8
    total_secs = ((s1[6] & 0x03) << 8) | s1[7]
    if total_secs == 0:
        total_secs = len(data) // 256
    used_secs = 2  # catalog sectors 0..1
    for i in range(min(num_entries, 31)):
        off = 8 + i * 8
        length = s1[off + 4] | (s1[off + 5] << 8) | (((s1[off + 6] >> 4) & 0x03) << 16)
        used_secs += (length + 255) // 256
    free_secs = max(0, total_secs - used_secs)
    return MediaBudget(
        port=port,
        kind="ssd",
        path="",
        used_units=used_secs,
        total_units=total_secs,
        free_units=free_secs,
        unit_label="sectors",
        used_bytes=used_secs * 256,
        capacity_bytes=total_secs * 256,
        free_bytes=free_secs * 256,
        entries_used=num_entries,
        entries_total=31,
        note=f"DFS catalog entries {num_entries}/31",
    )


def _read_cart_manifest_info(json_manifest: Path | None) -> tuple[int | None, int | None, int | None]:
    """Return (asset_count, asset_bytes_sum, roml_bytes_used) from a cartridge JSON manifest."""
    if not json_manifest or not json_manifest.is_file():
        return None, None, None
    try:
        jdata = json.loads(json_manifest.read_text(encoding="utf-8"))
    except Exception:
        return None, None, None
    roml_used = int(jdata["roml_bytes_used"]) if "roml_bytes_used" in jdata else None
    assets = jdata.get("assets")
    if isinstance(assets, list) and assets:
        sizes = [int(a["size"]) for a in assets if isinstance(a, dict) and "size" in a]
        asset_sum = sum(sizes) if len(sizes) == len(assets) else None
        return len(assets), asset_sum, roml_used
    return None, None, roml_used


def _format_asset_summary(asset_count: int | None, asset_sum: int | None) -> str:
    if not asset_count:
        return ""
    if asset_sum is not None:
        return f"{asset_count} assets ({asset_sum:,} B)"
    return f"{asset_count} assets"


def parse_cart_image(path: Path, port: str, json_manifest: Path | None = None) -> MediaBudget:
    raw = path.read_bytes()
    suffix = path.suffix.lower()
    asset_count, asset_sum, roml_used = _read_cart_manifest_info(json_manifest)
    asset_desc = _format_asset_summary(asset_count, asset_sum)
    asset_suffix = f"; {asset_desc}" if asset_desc else ""

    if suffix == ".car":
        if len(raw) < 16 or raw[:4] != b"CART":
            raise ValueError(f"Invalid Atari .car header: {path.name}")
        _magic, cart_type, _csum, _unused = struct.unpack_from(">4sIII", raw, 0)
        body = raw[16:]
        cap = len(body)
        used = len(body.rstrip(b"\xff"))
        free = cap - used
        return MediaBudget(
            port=port,
            kind="car",
            path="",
            used_units=used,
            total_units=cap,
            free_units=free,
            unit_label="bytes",
            used_bytes=used,
            capacity_bytes=cap,
            free_bytes=free,
            entries_used=asset_count,
            note=f"AtariMax type {cart_type} ({cap // 1024} KB; free {free / 1000:.1f} KB{asset_suffix})",
        )

    if raw[:16] == b"CX16 CARTRIDGE\r\n":
        hdr_size = 480
        if len(raw) < hdr_size:
            raise ValueError(f"Truncated CX16 CRT: {path.name}")
        body = raw[hdr_size:]
        cap = len(body)
        used = len(body.rstrip(b"\xff"))
        free = cap - used
        return MediaBudget(
            port=port,
            kind="crt",
            path="",
            used_units=used,
            total_units=cap,
            free_units=free,
            unit_label="bytes",
            used_bytes=used,
            capacity_bytes=cap,
            free_bytes=free,
            entries_used=asset_count,
            note=f"CX16 ROM ({cap // 1024} KB; free {free / 1000:.1f} KB{asset_suffix})",
        )

    # Standard VICE CRT (C64 EasyFlash / Plus4 c264 / C128 MD128)
    hw_type, chips = _parse_vice_crt_chips(raw, path.name)

    if port == "c64" and hw_type == 32:
        # Bank 0 may include an 8 KB Ultimax boot ROMH ($A000) while payload banks stay in 8K ROML mode.
        is_16k = any(bank > 0 and addr >= 0xA000 for bank, addr, _, _ in chips)
        cap = 64 * (16384 if is_16k else 8192)
        counted_chips = chips if is_16k else [c for c in chips if c[1] < 0xA000]
        boot_romh = 0 if is_16k else sum(1 for c in chips if c[1] >= 0xA000)
        alloc = sum(s for _, _, s, _ in counted_chips)
        trimmed = sum(len(d.rstrip(b"\xff")) for _, _, _, d in counted_chips)
        asset_parts: list[str] = []
        if roml_used is not None:
            asset_parts.append(f"roml_used={roml_used:,} B")
        if asset_desc:
            asset_parts.append(asset_desc)
        free = cap - alloc
        mode_str = "16K" if is_16k else "8K ROML"
        romh_note = f" + {boot_romh} boot ROMH" if boot_romh else ""
        extra_note = ("; " + "; ".join(asset_parts)) if asset_parts else ""
        return MediaBudget(
            port=port,
            kind="crt",
            path="",
            used_units=alloc,
            total_units=cap,
            free_units=free,
            unit_label="bytes",
            used_bytes=alloc,
            capacity_bytes=cap,
            free_bytes=free,
            entries_used=asset_count,
            note=f"EasyFlash {mode_str} ({len(counted_chips)}/64 banks alloc{romh_note}; non-FF={trimmed:,} B{extra_note})",
        )

    cap = sum(s for _, _, s, _ in chips)
    concat = b"".join(d for _, _, _, d in sorted(chips, key=lambda x: (x[0], x[1])))
    used = len(concat.rstrip(b"\xff"))
    free = cap - used
    return MediaBudget(
        port=port,
        kind="crt",
        path="",
        used_units=used,
        total_units=cap,
        free_units=free,
        unit_label="bytes",
        used_bytes=used,
        capacity_bytes=cap,
        free_bytes=free,
        entries_used=asset_count,
        note=f"{len(chips)} banks ({cap // 1024} KB; free {free / 1000:.1f} KB{asset_suffix})",
    )


def parse_zip_bundle(path: Path, port: str) -> MediaBudget:
    with zipfile.ZipFile(path, "r") as zf:
        infos = zf.infolist()
        raw_bytes = sum(i.file_size for i in infos)
    zip_bytes = path.stat().st_size
    return MediaBudget(
        port=port,
        kind="zip",
        path="",
        used_units=raw_bytes,
        total_units=0,
        free_units=0,
        unit_label="bytes",
        used_bytes=raw_bytes,
        capacity_bytes=None,
        free_bytes=None,
        entries_used=len(infos),
        note=f"{len(infos)} files, {raw_bytes:,} B uncompressed ({zip_bytes:,} B zip)",
    )


def collect_shipping_media(build_dir: Path, port_filter: str | None) -> list[MediaBudget]:
    media_specs: list[tuple[str, str, str]] = [
        ("c64", "moria8-c64.d64", "cbm"),
        ("c64", "moria8-c64.crt", "cart"),
        ("c64", "moria8-c64.zip", "zip"),
        ("plus4", "moria8-plus4.d64", "cbm"),
        ("plus4", "moria8-plus4.crt", "cart"),
        ("c128", "moria8-c128.d64", "cbm"),
        ("c128", "moria8-c128.d71", "cbm"),
        ("c128", "moria8-c128.d81", "cbm"),
        ("c128", "moria8-c128.crt", "cart"),
        ("apple2", "moria8-apple2.po", "po"),
        ("cx16", "moria8-cx16.crt", "cart"),
        ("cx16", "moria8-cx16.zip", "zip"),
        ("atari8", "moria8-atari8.atr", "atr"),
        ("atari8", "moria8-atari8.car", "cart"),
        ("bbcmaster", "moria8-bbcmaster.ssd", "ssd"),
    ]
    filter_port = port_filter.split("-")[0] if port_filter else None
    results: list[MediaBudget] = []
    for port, fname, parser_kind in media_specs:
        if filter_port and port != filter_port:
            continue
        p = build_dir / fname
        if not p.is_file():
            continue
        if parser_kind == "cbm":
            mb = parse_cbm_disk(p, port)
        elif parser_kind == "po":
            mb = parse_prodos_po(p, port)
        elif parser_kind == "atr":
            mb = parse_atari_atr(p, port)
        elif parser_kind == "ssd":
            mb = parse_bbc_ssd(p, port)
        elif parser_kind == "cart":
            jpath = next(
                (
                    cand
                    for cand in (
                        build_dir / f"moria8-{port}.json",
                        build_dir / f"{port}-cart" / f"moria8-{port}.json",
                    )
                    if cand.is_file()
                ),
                None,
            )
            mb = parse_cart_image(p, port, jpath)
        else:
            mb = parse_zip_bundle(p, port)
        mb.path = display_path(p, build_dir.parent)
        results.append(mb)
    return results


# ---------------- Test Variant Scanner ----------------

TEST_PORT_CONFIG: dict[str, tuple[int, int, str, int]] = {
    # port -> (resident_base, resident_ceil, ceiling_name, banked_ceil)
    "c64": (0x0801, 0xC000, "MAP_BASE ($C000)", 0xFFFA),
    "plus4": (0x1001, 0xC800, "MAP_BASE ($C800)", 0xFC00),
    "c128": (0x1C01, 0xAF00, "128.play / 128.persist ($AF00)", 0xFF00),
    "apple2": (0x0A00, 0x7C00, "A2_PLAY_BASE ($7C00)", 0xA000),
    "cx16": (0x0801, 0x9B00, "TIER_POOL ($9B00)", 0xC000),
    "atari8": (0x0C00, 0xC100, "MAP_BASE ($C100)", 0xFFFA),
    "bbcmaster": (0x0E00, 0x8000, "SWR_WINDOW ($8000)", 0xA400),
}


def infer_test_port_mode(rel_parts: tuple[str, ...]) -> tuple[str | None, str]:
    joined = "/".join(p.lower() for p in rel_parts)
    for part in reversed(rel_parts):
        pl = part.lower()
        for port in CANONICAL_PORTS:
            if pl == f"{port}-cart" or pl.startswith(f"{port}-cartridge"):
                return port, "cart"
            if pl == port or pl.startswith(f"{port}-"):
                mode = "cart" if ("cart" in joined or "cold_live_work" in joined) else "disk"
                return port, mode
    for port in CANONICAL_PORTS:
        if port in joined:
            mode = "cart" if ("cart" in joined or "cold_live_work" in joined) else "disk"
            return port, mode
    return None, "disk"


def normalize_test_variant_name(rel_dir: str, stem: str, port: str) -> str:
    cleaned = TMP_RUN_SEG_RE.sub("", rel_dir)
    cleaned = MKTEMP_SUFFIX_RE.sub("", cleaned)
    parts = [p for p in cleaned.split("/") if p and p != "."]
    # Strip redundant outer port / trailing port-mode dir when descriptive mid-part exists
    if parts and parts[0].lower() == port:
        parts = parts[1:]
    if parts and parts[-1].lower() in (port, f"{port}-cart", "build"):
        parts = parts[:-1]
    base_name = "/".join(parts) if parts else stem
    if stem not in ("main", "moria8", "moria4", "moria128"):
        return f"{base_name}/{stem}" if parts else stem
    return base_name


def _load_prod_syms_map(build_dir: Path) -> dict[tuple[str, str], dict[str, int]]:
    out: dict[tuple[str, str], dict[str, int]] = {}
    for port in CANONICAL_PORTS:
        for mode, subdir in (("disk", port), ("cart", f"{port}-cart")):
            pdir = build_dir / subdir
            if not pdir.is_dir():
                continue
            sp = pdir / "main.sym"
            vp = pdir / "main.vs"
            if sp.is_file():
                out[(port, mode)] = parse_symbol_file(sp)
            elif vp.is_file():
                out[(port, mode)] = parse_symbol_file(vp)
    return out


def scan_test_variants(
    test_dir: Path,
    build_dir: Path,
    port_filter: str | None,
    prod_syms_by_target: dict[tuple[str, str], dict[str, int]] | None = None,
) -> list[TestVariantBudget]:
    if not test_dir.is_dir():
        return []

    if prod_syms_by_target is None:
        prod_syms_by_target = _load_prod_syms_map(build_dir)

    prod_prg_ends: dict[tuple[str, str], int] = {}
    for port, (subdir, prg_name) in (
        ("c64", ("c64", "moria8.prg")),
        ("plus4", ("plus4", "moria4.prg")),
        ("c128", ("c128", "moria128.prg")),
    ):
        p = build_dir / subdir / prg_name
        if p.is_file():
            try:
                prod_prg_ends[(port, "disk")] = read_prg_span(p)[1]
            except ValueError:
                pass

    ignored_sym_prefixes = ("boot", "tier", "title", "cartridge_boot", "legal")
    ignored_prg_names = {
        "boot.prg", "boot4.prg", "boot128.prg", "boot128.chain.prg", "boot128.diag.prg",
        "bootart64.prg", "bootart128.prg", "bootsect128.prg",
        "driver.prg", "keys.prg", "key-count.prg", "catalog-test.prg",
        "cartridge_test_live.prg", "moria8.prg", "moria4.prg", "moria128.prg",
    }

    best_by_key: dict[tuple[str, str, str], tuple[float, TestVariantBudget]] = {}
    filter_base, filter_var = (port_filter.split("-", 1) + [""])[:2] if port_filter else (None, "")

    for root_str, _dirs, files in sorted(os.walk(test_dir)):
        root = Path(root_str)
        rel_dir = root.relative_to(test_dir).as_posix()
        rel_parts = () if rel_dir == "." else tuple(rel_dir.split("/"))
        port, mode = infer_test_port_mode(rel_parts)
        if not port:
            continue
        if filter_base and port != filter_base:
            continue
        if filter_var == "cart" and mode != "cart":
            continue

        base_addr, ceil_addr, ceil_name, bank_ceil = TEST_PORT_CONFIG[port]
        prod_syms = prod_syms_by_target.get((port, mode)) or prod_syms_by_target.get((port, "disk")) or {}
        sym_candidates = [
            f for f in sorted(files)
            if f.endswith((".sym", ".vs"))
            and not f.startswith(ignored_sym_prefixes)
        ]

        # Group by stem so main.sym beats main.vs in the exact same directory.
        stems: dict[str, Path] = {}
        for fname in sym_candidates:
            p = root / fname
            stem = p.stem
            if stem not in stems or p.suffix.lower() == ".sym":
                stems[stem] = p

        for stem, sym_path in sorted(stems.items()):
            syms = parse_symbol_file(sym_path)
            if "program_end" not in syms:
                continue
            pe = syms["program_end"]
            free_main = ceil_addr - pe
            used_main = max(0, pe - base_addr)

            extra_checks: list[dict] = []
            slot_specs: list[tuple[str, int, str]] = []
            if port == "c128":
                slot_specs = [
                    ("c128_resident_play_end", 0xD000, "128.play"),
                    ("c128_resident_persist_end", 0xD000, "128.persist"),
                    ("banked_code_end", bank_ceil, "128.bank"),
                ]
                if mode == "cart":
                    slot_specs.append(("cart_reader_end", 0x8000, "cart_reader"))
            elif port in ("c64", "plus4", "atari8"):
                slot_specs = [("banked_code_end", bank_ceil, "banked")]
            elif port == "apple2":
                slot_specs = [("a2_play_end", 0xA000, "a2.play")]
            elif port == "bbcmaster":
                slot_specs = [("beeb_play_end", 0xA400, "beeb.play")]

            for sym_lbl, slot_ceil, slot_label in slot_specs:
                if sym_lbl not in syms:
                    continue
                val = syms[sym_lbl]
                f_b = slot_ceil - val
                prod_val = prod_syms.get(sym_lbl)
                same_as_prod = (prod_val is not None) and (val <= prod_val)
                # Shared non-resident slots already tight in product (e.g. 64.bank=6B)
                # should not flag unrelated resident tests unless the test expanded them.
                slot_tight = (f_b < TIGHT_THRESHOLD_BYTES) and (not same_as_prod)
                extra_checks.append({
                    "name": slot_label,
                    "end_addr": val,
                    "ceil_addr": slot_ceil,
                    "free_bytes": f_b,
                    "same_as_prod": same_as_prod,
                    "tight": slot_tight,
                })

            any_overflow = (free_main < 0) or any(c["free_bytes"] < 0 for c in extra_checks)
            any_tight = (free_main < TIGHT_THRESHOLD_BYTES) or any(c["tight"] for c in extra_checks)

            variant_name = normalize_test_variant_name(rel_dir, stem, port)
            mtime = sym_path.stat().st_mtime
            entry = TestVariantBudget(
                port=port,
                mode=mode,
                name=variant_name,
                source_path=display_path(sym_path, test_dir.parent),
                source_kind="sym",
                ceiling_name=ceil_name,
                base_addr=base_addr,
                ceil_addr=ceil_addr,
                end_addr=pe,
                used_bytes=used_main,
                free_bytes=free_main,
                delta_vs_prod=None,
                tight=any_tight,
                overflow=any_overflow,
                extra_checks=extra_checks,
            )
            key = (port, mode, variant_name)
            prev = best_by_key.get(key)
            if prev is None or mtime > prev[0]:
                best_by_key[key] = (mtime, entry)

        # Standalone test PRGs in test root dirs (e.g. c64/moria_*.prg, c128/moria128.*.prg)
        for fname in sorted(files):
            if not fname.endswith(".prg") or fname in ignored_prg_names:
                continue
            if not fname.startswith("moria"):
                continue
            prg_path = root / fname
            try:
                load_addr, prg_end, payload = read_prg_span(prg_path)
            except ValueError:
                continue

            stem = prg_path.stem
            if port == "c128" and stem.startswith("moria128."):
                short_name = stem.split(".", 1)[1]
                # If a main_<short>.vs file matched it, skip duplicate PRG-only entry and merge info instead
                matched_vs_key = (port, mode, f"main_{short_name}")
                if matched_vs_key in best_by_key:
                    continue
                free_b = ceil_addr - prg_end
                prod_end = prod_prg_ends.get((port, mode))
                delta = (prg_end - prod_end) if prod_end is not None else None
                entry = TestVariantBudget(
                    port=port,
                    mode=mode,
                    name=short_name,
                    source_path=display_path(prg_path, test_dir.parent),
                    source_kind="prg",
                    ceiling_name=ceil_name,
                    base_addr=load_addr,
                    ceil_addr=ceil_addr,
                    end_addr=prg_end,
                    used_bytes=payload,
                    free_bytes=free_b,
                    delta_vs_prod=delta,
                    tight=(free_b < TIGHT_THRESHOLD_BYTES),
                    overflow=(free_b < 0),
                    note="PRG end (no dedicated .vs/.sym)",
                )
                key = (port, mode, short_name)
                mtime = prg_path.stat().st_mtime
                prev = best_by_key.get(key)
                if prev is None or mtime > prev[0]:
                    best_by_key[key] = (mtime, entry)
            elif port in ("c64", "plus4"):
                # C64/Plus4 moria_*.prg include init-only tail past MAP_BASE up to CATALOG_IDX_LOAD.
                tail_ceil = 0xCE00 if port == "c64" else 0xD600
                tail_name = "CATALOG_IDX_LOAD ($CE00)" if port == "c64" else "CATALOG_IDX_LOAD ($D600)"
                prod_end = prod_prg_ends.get((port, mode))
                delta = (prg_end - prod_end) if prod_end is not None else None
                free_tail = tail_ceil - prg_end
                prod_prog_end = prod_syms.get("program_end")
                est_res_free: int | None = None
                extra_checks_prg: list[dict] = []
                if delta is not None and prod_prog_end is not None:
                    est_res_free = (ceil_addr - prod_prog_end) - delta
                    extra_checks_prg.append({
                        "name": f"est.res (<${ceil_addr:04X})",
                        "end_addr": prod_prog_end + delta,
                        "ceil_addr": ceil_addr,
                        "free_bytes": est_res_free,
                        "same_as_prod": delta <= 0,
                        "tight": est_res_free < TIGHT_THRESHOLD_BYTES,
                    })
                    note = f"est. resident ~{est_res_free:,} B (<${ceil_addr:04X}); PRG includes init tail past MAP_BASE"
                else:
                    note = "PRG includes init-only tail past MAP_BASE; no per-PRG .sym"
                tight = (free_tail < TIGHT_THRESHOLD_BYTES) or (
                    est_res_free is not None and est_res_free < TIGHT_THRESHOLD_BYTES
                )
                overflow = (free_tail < 0) or (
                    delta is not None and delta > 0 and est_res_free is not None and est_res_free < 0
                )
                entry = TestVariantBudget(
                    port=port,
                    mode=mode,
                    name=stem,
                    source_path=display_path(prg_path, test_dir.parent),
                    source_kind="prg",
                    ceiling_name=tail_name,
                    base_addr=load_addr,
                    ceil_addr=tail_ceil,
                    end_addr=prg_end,
                    used_bytes=payload,
                    free_bytes=free_tail,
                    delta_vs_prod=delta,
                    tight=tight,
                    overflow=overflow,
                    extra_checks=extra_checks_prg,
                    note=note,
                )
                key = (port, mode, stem)
                mtime = prg_path.stat().st_mtime
                prev = best_by_key.get(key)
                if prev is None or mtime > prev[0]:
                    best_by_key[key] = (mtime, entry)

    variants = [v for _, v in best_by_key.values()]
    variants.sort(key=lambda v: (v.port, v.mode, 1 if v.free_bytes is None else 0, v.free_bytes or 0, v.name))
    return variants


# ---------------- Orchestration & Formatting ----------------

def collect_report(
    build_dir: Path,
    test_dir: Path,
    port_filter: str | None = None,
) -> dict:
    port_specs = build_port_specs()
    targets: list[tuple[str, str]] = [
        ("c64", "disk"),
        ("c64", "cart"),
        ("plus4", "disk"),
        ("plus4", "cart"),
        ("c128", "disk"),
        ("c128", "cart"),
        ("apple2", "disk"),
        ("cx16", "disk"),
        ("cx16", "cart"),
        ("atari8", "disk"),
        ("atari8", "cart"),
        ("bbcmaster", "disk"),
    ]
    if port_filter:
        if "-" in port_filter:
            fp, fv = port_filter.split("-", 1)
            targets = [(p, v) for (p, v) in targets if p == fp and v == fv]
        else:
            targets = [(p, v) for (p, v) in targets if p == port_filter]
        if not targets:
            raise ValueError(f"Unknown --port filter: {port_filter!r}")

    port_reports: list[dict] = []
    prod_syms_by_target: dict[tuple[str, str], dict[str, int]] = {}
    missing_targets: list[str] = []
    tight_items: list[dict] = []
    overflow_items: list[dict] = []

    for port, variant in targets:
        subdir = f"{port}-cart" if variant == "cart" else port
        pdir = build_dir / subdir
        if not pdir.is_dir():
            missing_targets.append(subdir)
            continue

        sym_path = pdir / "main.sym"
        vs_path = pdir / "main.vs"
        syms: dict[str, int] = {}
        sym_source = None
        if sym_path.is_file():
            syms = parse_symbol_file(sym_path)
            sym_source = display_path(sym_path, build_dir.parent)
        elif vs_path.is_file():
            syms = parse_symbol_file(vs_path)
            sym_source = display_path(vs_path, build_dir.parent)

        segs: list[SegmentBudget] = []
        for spec in port_specs[(port, variant)]:
            sb = measure_segment(port, variant, pdir, syms, spec)
            if sb.status == "missing" and spec.optional:
                continue
            segs.append(sb)
            if sb.overflow:
                overflow_items.append({
                    "scope": "product",
                    "port": f"{port}-{variant}",
                    "name": sb.name,
                    "free_bytes": sb.free_bytes,
                    "ceil": f"${sb.ceil_addr:04X}",
                })
            elif sb.tight:
                tight_items.append({
                    "scope": "product",
                    "port": f"{port}-{variant}",
                    "name": sb.name,
                    "free_bytes": sb.free_bytes,
                    "ceil": f"${sb.ceil_addr:04X}",
                })

        banks = collect_bank_summaries(port, variant, pdir, syms)
        port_reports.append({
            "port": port,
            "variant": variant,
            "build_subdir": subdir,
            "sym_source": sym_source,
            "segments": [asdict(s) for s in segs],
            "banks": [asdict(b) for b in banks],
        })
        if syms:
            prod_syms_by_target[(port, variant)] = syms

    media = collect_shipping_media(build_dir, port_filter)
    tests = scan_test_variants(test_dir, build_dir, port_filter, prod_syms_by_target or None)

    for tv in tests:
        if tv.overflow:
            overflow_items.append({
                "scope": "test",
                "port": f"{tv.port}-{tv.mode}",
                "name": tv.name,
                "free_bytes": tv.free_bytes,
                "ceil": tv.ceiling_name,
                "extra_checks": [c for c in tv.extra_checks if c["free_bytes"] < 0],
            })
        elif tv.tight:
            tight_items.append({
                "scope": "test",
                "port": f"{tv.port}-{tv.mode}",
                "name": tv.name,
                "free_bytes": tv.free_bytes,
                "ceil": tv.ceiling_name,
                "extra_checks": [c for c in tv.extra_checks if c["tight"]],
            })

    return {
        "build_dir": display_path(build_dir, REPO_ROOT),
        "test_dir": display_path(test_dir, REPO_ROOT),
        "tight_threshold_bytes": TIGHT_THRESHOLD_BYTES,
        "missing_build_targets": missing_targets,
        "overflows": overflow_items,
        "tight_items": tight_items,
        "ports": port_reports,
        "media": [asdict(m) for m in media],
        "tests": [asdict(t) for t in tests],
    }


def fmt_hex(val: int | None) -> str:
    return "-" if val is None else f"${val:04X}"


def fmt_bytes(val: int | None) -> str:
    return "-" if val is None else f"{val:,} B"


def render_markdown(report: dict) -> str:
    lines: list[str] = []
    lines.append("# Moria8 Memory, Media & Test Headroom Report")
    lines.append("")
    lines.append(
        f"- Build root: `{report['build_dir']}` | Test root: `{report['test_dir']}` | "
        f"Tight threshold: `< {report['tight_threshold_bytes']} B`"
    )
    if report["missing_build_targets"]:
        lines.append("- Absent optional build targets: " + ", ".join(f"`{t}`" for t in report["missing_build_targets"]))
    lines.append("")

    def _format_watchlist_free(item: dict) -> str:
        free_str = fmt_bytes(item["free_bytes"])
        extra = item.get("extra_checks") or []
        if extra:
            min_extra = min(extra, key=lambda c: c["free_bytes"])
            free_str = f"{free_str} (`{min_extra['name']}` {min_extra['free_bytes']} B)"
        return free_str

    def _effective_free(item: dict) -> int:
        vals = [c["free_bytes"] for c in (item.get("extra_checks") or []) if c.get("free_bytes") is not None]
        if item.get("free_bytes") is not None:
            vals.append(item["free_bytes"])
        return min(vals) if vals else 99999

    # Summary Watchlist
    if report["overflows"]:
        lines.append("## Overflows (< 0 B Free)")
        lines.append("")
        lines.append("| Scope | Target | Item | Free | Ceiling |")
        lines.append("| --- | --- | --- | ---: | --- |")
        for item in sorted(report["overflows"], key=lambda x: (_effective_free(x), x["port"], x["name"])):
            lines.append(
                f"| {item['scope']} | `{item['port']}` | `{item['name']}` | **{_format_watchlist_free(item)}** | `{item['ceil']}` |"
            )
        lines.append("")

    lines.append("## Tight Budget Watchlist (< 64 B Free)")
    lines.append("")
    if not report["tight_items"]:
        lines.append("None.")
    else:
        lines.append("| Scope | Target | Segment / Variant | Free | Ceiling |")
        lines.append("| --- | --- | --- | ---: | --- |")
        for item in sorted(report["tight_items"], key=lambda x: (_effective_free(x), x["port"], x["name"])):
            lines.append(
                f"| {item['scope']} | `{item['port']}` | `{item['name']}` | **{_format_watchlist_free(item)}** | `{item['ceil']}` |"
            )
    lines.append("")

    # Per-Port Segments
    lines.append("## Product Memory Budgets")
    lines.append("")
    for pdata in report["ports"]:
        lines.append(f"### `{pdata['port']}` (`{pdata['variant']}` — `{pdata['build_subdir']}`)")
        if pdata["sym_source"]:
            lines.append(f"Symbols: `{pdata['sym_source']}`")
        lines.append("")
        lines.append("| Segment | Base | End | Ceiling | Used | Cap | Free | Status | Notes |")
        lines.append("| --- | --- | --- | --- | ---: | ---: | ---: | --- | --- |")
        for seg in pdata["segments"]:
            flag = "OVERFLOW" if seg["overflow"] else ("TIGHT (<64B)" if seg["tight"] else seg["status"])
            lines.append(
                f"| `{seg['name']}` | `{fmt_hex(seg['base_addr'])}` | `{fmt_hex(seg['end_addr'])}` | "
                f"`{fmt_hex(seg['ceil_addr'])}` | {fmt_bytes(seg['used_bytes'])} | "
                f"{fmt_bytes(seg['capacity_bytes'])} | {fmt_bytes(seg['free_bytes'])} | "
                f"{flag} | {seg['note']} |"
            )
        for bank in pdata["banks"]:
            lines.append("")
            lines.append(
                f"- **{bank['name']}**: `{bank['used_units']}/{bank['total_units']}` {bank['unit_label']} used, "
                f"**`{bank['free_units']}` free** ({bank['note']})"
            )
        lines.append("")

    # Shipping Media
    lines.append("## Shipping Media Headroom")
    lines.append("")
    if not report["media"]:
        lines.append("No shipping disk or cartridge images present.")
    else:
        lines.append("| Port | Kind | Image | Used | Total | Free | Details |")
        lines.append("| --- | --- | --- | ---: | ---: | ---: | --- |")
        for m in report["media"]:
            if m["total_units"] > 0:
                used_s = f"{m['used_units']:,} {m['unit_label']}"
                tot_s = f"{m['total_units']:,} {m['unit_label']}"
                free_s = f"**{m['free_units']:,} {m['unit_label']}**"
            else:
                used_s = f"{m['used_units']:,} {m['unit_label']}"
                tot_s = "-"
                free_s = "-"
            lines.append(
                f"| `{m['port']}` | `{m['kind']}` | `{m['path']}` | {used_s} | {tot_s} | {free_s} | {m['note']} |"
            )
    lines.append("")

    # Test Variants
    lines.append("## Test Variant Headroom")
    lines.append("")
    if not report["tests"]:
        lines.append("No compiled test variants present.")
    else:
        sym_tests = [t for t in report["tests"] if t["source_kind"] == "sym"]
        prg_tests = [t for t in report["tests"] if t["source_kind"] == "prg"]

        if sym_tests:
            lines.append("### Symbol-Measured Test Variants")
            lines.append("")
            lines.append("| Port | Mode | Variant | End | Ceiling | Free | Changed / Test-Tight Slots | Status |")
            lines.append("| --- | --- | --- | --- | --- | ---: | --- | --- |")
            for t in sym_tests:
                flag = "**OVERFLOW**" if t["overflow"] else ("**TIGHT (<64B)**" if t["tight"] else "ok")
                extras = ", ".join(
                    f"{c['name']}={c['free_bytes']}B"
                    for c in t["extra_checks"]
                    if c["tight"] or c["free_bytes"] < 0 or (not c.get("same_as_prod") and c["free_bytes"] < 256)
                )
                lines.append(
                    f"| `{t['port']}` | `{t['mode']}` | `{t['name']}` | `{fmt_hex(t['end_addr'])}` | "
                    f"`{t['ceiling_name']}` | {fmt_bytes(t['free_bytes'])} | {extras or '-'} | {flag} |"
                )
            lines.append("")

        if prg_tests:
            lines.append("### Standalone Test PRG Artifacts (Without Dedicated .sym/.vs)")
            lines.append("")
            lines.append("| Port | Variant | PRG End | Ceiling | Headroom | Delta vs Prod PRG | Notes |")
            lines.append("| --- | --- | --- | --- | ---: | ---: | --- |")
            for t in prg_tests:
                delta_s = f"{t['delta_vs_prod']:+d} B" if t["delta_vs_prod"] is not None else "-"
                flag = " **OVERFLOW**" if t["overflow"] else (" **TIGHT**" if t["tight"] else "")
                lines.append(
                    f"| `{t['port']}` | `{t['name']}` | `{fmt_hex(t['end_addr'])}` | `{t['ceiling_name']}` | "
                    f"{fmt_bytes(t['free_bytes'])}{flag} | {delta_s} | {t['note']} |"
                )
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


# ---------------- Synthetic Self-Tests ----------------

def _build_synthetic_d64(free_t1: int = 10, free_t18: int = 14) -> bytes:
    buf = bytearray(174848)
    bam_off = 357 * 256
    for t in range(35):
        buf[bam_off + 4 + t * 4] = free_t18 if t == 17 else free_t1
    return bytes(buf)


def _build_synthetic_d71(free_s1: int = 5, free_s2: int = 7, free_t18: int = 13, free_t53: int = 0) -> bytes:
    buf = bytearray(349696)
    bam_off = 357 * 256
    for t in range(35):
        buf[bam_off + 4 + t * 4] = free_t18 if t == 17 else free_s1
        buf[bam_off + 0xDD + t] = free_t53 if t == 17 else free_s2
    return bytes(buf)


def _build_synthetic_d81(free_s1: int = 20, free_s2: int = 30, free_t40: int = 32) -> bytes:
    buf = bytearray(819200)
    bam1 = 1561 * 256
    bam2 = 1562 * 256
    for t in range(40):
        buf[bam1 + 16 + t * 6] = free_t40 if t == 39 else free_s1
        buf[bam2 + 16 + t * 6] = free_s2
    return bytes(buf)


def _build_synthetic_po(total_blocks: int = 280, free_blocks: int = 14) -> bytes:
    buf = bytearray(total_blocks * 512)
    vh = 2 * 512
    bitmap_blk = 6
    struct.pack_into("<HH", buf, vh + 0x27, bitmap_blk, total_blocks)
    bm = bitmap_blk * 512
    # Mark last `free_blocks` bits as 1 (free), earlier bits 0 (allocated)
    for b in range(total_blocks - free_blocks, total_blocks):
        buf[bm + (b >> 3)] |= 1 << (7 - (b & 7))
    return bytes(buf)


def _build_synthetic_atr(free_low: int = 0, free_high: int = 145, file_count: int = 0) -> bytes:
    buf = bytearray(16 + 1040 * 128)
    struct.pack_into("<HHH", buf, 0, 0x0296, (1040 * 128) // 16, 128)
    vtoc = 16 + 359 * 128
    struct.pack_into("<HH", buf, vtoc + 1, 707, free_low)
    for idx in range(min(file_count, 64)):
        sec = 361 + (idx // 8)
        d_off = 16 + 3 * 128 + (sec - 4) * 128 + (idx % 8) * 16
        buf[d_off] = 0x42
    vtoc2 = 16 + 1023 * 128
    struct.pack_into("<H", buf, vtoc2 + 122, free_high)
    return bytes(buf)


def _build_synthetic_ssd(entry_lengths: list[int], total_secs: int = 800) -> bytes:
    buf = bytearray(total_secs * 256)
    buf[256 + 5] = len(entry_lengths) * 8
    buf[256 + 6] = (total_secs >> 8) & 0x03
    buf[256 + 7] = total_secs & 0xFF
    for i, length in enumerate(entry_lengths):
        off = 256 + 8 + i * 8
        buf[off + 4] = length & 0xFF
        buf[off + 5] = (length >> 8) & 0xFF
        buf[off + 6] = ((length >> 16) & 0x03) << 4
    return bytes(buf)


def _build_synthetic_vice_crt(sig: bytes, hw_type: int, chips: list[tuple[int, int, bytes]]) -> bytes:
    out = bytearray(64)
    out[:16] = sig
    struct.pack_into(">I", out, 16, 64)
    struct.pack_into(">H", out, 22, hw_type)
    for bank, addr, data in chips:
        pkt = bytearray(16 + len(data))
        struct.pack_into(">4sIHHHH", pkt, 0, b"CHIP", len(pkt), 0, bank, addr, len(data))
        pkt[16:] = data
        out.extend(pkt)
    return bytes(out)


def _build_synthetic_car(used_bytes: int, total_bytes: int = 131072) -> bytes:
    hdr = struct.pack(">4sIII", b"CART", 41, 0, 0)
    body = b"\xAA" * used_bytes + b"\xFF" * (total_bytes - used_bytes)
    return hdr + body


def _build_synthetic_cx16_crt(used_bytes: int, total_bytes: int = 131072) -> bytes:
    hdr = b"CX16 CARTRIDGE\r\n".ljust(480, b"\x00")
    body = b"\xAA" * used_bytes + b"\xFF" * (total_bytes - used_bytes)
    return hdr + body


def _make_prg(load_addr: int, size_bytes: int) -> bytes:
    return struct.pack("<H", load_addr) + (b"\xEA" * size_bytes)


class _BudgetSelfTests(unittest.TestCase):
    def test_sym_and_vs_parsers(self) -> None:
        sym = parse_sym_text("  .label program_end=$bfb4\n.label banked_code_end = $FFF4 // cmt\n")
        vs = parse_vs_text("al C:00c798 .program_end\nal 00FB92 .banked_code_end\n")
        self.assertEqual(sym["program_end"], 0xBFB4)
        self.assertEqual(sym["banked_code_end"], 0xFFF4)
        self.assertEqual(vs["program_end"], 0xC798)
        self.assertEqual(vs["banked_code_end"], 0xFB92)

    def test_boundary_math_and_hard_ceilings(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bdir = root / "build"
            # Plus/4 must enforce $FC00 (NOT $FDFF) and Plus4HighBss ($DF00-$DFFF)
            p4 = bdir / "plus4"
            p4.mkdir(parents=True)
            (p4 / "main.sym").write_text(".label program_end=$c798\n.label banked_code_end=$fb92\n.label ovl_town_end=$eff4\n.label plus4_high_bss_end=$dfa0\n")
            (p4 / "4.bank").write_bytes(_make_prg(0xF000, 0x0B92))
            (p4 / "ovl.town").write_bytes(_make_prg(0xE000, 0x0FF4))

            # C128 must enforce $AF00 on consolidated moria128 and $FF00 on 128.bank
            c128 = bdir / "c128"
            c128.mkdir(parents=True)
            (c128 / "main.sym").write_text(
                ".label program_end=$aca3\n.label c128_resident_play_end=$cfb6\n"
                ".label c128_resident_persist_end=$bbc3\n.label banked_code_end=$fede\n"
            )
            (c128 / "moria128.prg").write_bytes(_make_prg(0x1C01, 0xACA3 - 0x1C01))
            (c128 / "128.bank.prg").write_bytes(_make_prg(0xF000, 0x0EDE))

            # Apple IIe: $A400-$B9FF code cap (5,632 B), $BA00-$BAFF NOT double-counted
            a2 = bdir / "apple2"
            a2.mkdir(parents=True)
            (a2 / "main.sym").write_text(".label program_end=$7bef\n.label a2_play_end=$9fbe\n.label ovl_items_end=$b9ce\n.label BANKED_DATA_END=$baff\n")
            (a2 / "ovl.items").write_bytes(_make_prg(0xA400, 0xB9CE - 0xA400))

            rep = collect_report(bdir, root / "test")
            by_port = {p["build_subdir"]: {s["name"]: s for s in p["segments"]} for p in rep["ports"]}

            self.assertEqual(by_port["plus4"]["4.bank"]["ceil_addr"], 0xFC00)
            self.assertEqual(by_port["plus4"]["4.bank"]["free_bytes"], 110)
            self.assertEqual(by_port["plus4"]["Plus4HighBss"]["used_bytes"], 160)
            self.assertEqual(by_port["plus4"]["Plus4HighBss"]["free_bytes"], 96)
            self.assertEqual(by_port["plus4"]["ovl.town"]["free_bytes"], 12)
            self.assertTrue(by_port["plus4"]["ovl.town"]["tight"])

            self.assertEqual(by_port["c128"]["Default (moria128)"]["ceil_addr"], 0xAF00)
            self.assertEqual(by_port["c128"]["Default (moria128)"]["free_bytes"], 605)
            self.assertEqual(by_port["c128"]["128.bank"]["ceil_addr"], 0xFF00)
            self.assertEqual(by_port["c128"]["128.bank"]["free_bytes"], 34)
            self.assertTrue(by_port["c128"]["128.bank"]["tight"])

            self.assertEqual(by_port["apple2"]["ovl.items"]["ceil_addr"], 0xBA00)
            self.assertEqual(by_port["apple2"]["ovl.items"]["free_bytes"], 50)
            self.assertEqual(by_port["apple2"]["cache.ovl.items (Aux)"]["free_bytes"], 50)
            self.assertEqual(by_port["apple2"]["BANKED_DATA_END guard"]["ceil_addr"], 0xBB00)
            self.assertEqual(by_port["apple2"]["BANKED_DATA_END guard"]["free_bytes"], 1)

    def test_shipping_media_parsers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bdir = root / "build"
            bdir.mkdir()
            (bdir / "moria8-c64.d64").write_bytes(_build_synthetic_d64(free_t1=6, free_t18=14))
            (bdir / "moria8-c128.d71").write_bytes(_build_synthetic_d71(free_s1=5, free_s2=10))
            (bdir / "moria8-c128.d81").write_bytes(_build_synthetic_d81(free_s1=20, free_s2=30))
            (bdir / "moria8-apple2.po").write_bytes(_build_synthetic_po(280, 14))
            (bdir / "moria8-atari8.atr").write_bytes(_build_synthetic_atr(0, 145))
            (bdir / "moria8-bbcmaster.ssd").write_bytes(_build_synthetic_ssd([257, 512], 800))  # 2+2+2=6 secs used -> 794 free
            (bdir / "moria8-plus4.crt").write_bytes(
                _build_synthetic_vice_crt(b"PLUS4 CARTRIDGE ", 1, [(0, 0x8000, b"\x00" * 100 + b"\xff" * 16284)])
            )
            (bdir / "moria8-c64.crt").write_bytes(
                _build_synthetic_vice_crt(
                    b"C64 CARTRIDGE   ",
                    32,
                    [
                        (0, 0x8000, b"\x01" * 100 + b"\xff" * 8092),
                        (0, 0xA000, b"\x02" * 50 + b"\xff" * 8142),  # bank-0 boot ROMH must stay 8K ROML mode
                        (1, 0x8000, b"\x11" * 200 + b"\xff" * 7992),
                    ],
                )
            )
            (bdir / "moria8-atari8.car").write_bytes(_build_synthetic_car(110848, 131072))

            media = {(m.port, m.kind): m for m in collect_shipping_media(bdir, None)}
            self.assertEqual(media[("c64", "d64")].free_units, 34 * 6)
            self.assertEqual(media[("c128", "d71")].free_units, 34 * 5 + 34 * 10)
            self.assertEqual(media[("c128", "d81")].free_units, 39 * 20 + 40 * 30)
            self.assertEqual(media[("apple2", "po")].free_units, 14)
            self.assertEqual(media[("apple2", "po")].total_units, 280)
            self.assertEqual(media[("atari8", "atr")].free_units, 145)
            self.assertEqual(media[("bbcmaster", "ssd")].entries_used, 2)
            self.assertEqual(media[("bbcmaster", "ssd")].free_units, 794)
            self.assertEqual(media[("plus4", "crt")].used_units, 100)
            self.assertEqual(media[("c64", "crt")].total_units, 524288)
            self.assertEqual(media[("c64", "crt")].used_units, 16384)
            self.assertEqual(media[("atari8", "car")].free_units, 20224)

    def test_test_scanner_tight_threshold_and_missing_graceful(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bdir = root / "build"
            tdir = bdir / "test"
            (bdir / "c128").mkdir(parents=True)
            (bdir / "c128" / "main.sym").write_text(
                ".label program_end=$ACA3\n.label c128_resident_play_end=$CFB6\n"
                ".label c128_resident_persist_end=$BBC3\n.label banked_code_end=$FEDE\n"
            )
            (tdir / "c128" / "tight_case").mkdir(parents=True)
            (tdir / "c128" / "tight_case" / "main.vs").write_text(
                "al C:00AEEA .program_end\nal C:00CFB6 .c128_resident_play_end\nal C:00FEDE .banked_code_end\n"
            )
            (tdir / "c128" / "slot_tight_case").mkdir(parents=True)
            (tdir / "c128" / "slot_tight_case" / "main.vs").write_text(
                "al C:00AC00 .program_end\nal C:00CFD9 .c128_resident_play_end\nal C:00FEDE .banked_code_end\n"
            )
            (tdir / "c128" / "unchanged_bank_ok").mkdir(parents=True)
            (tdir / "c128" / "unchanged_bank_ok" / "main.vs").write_text(
                "al C:00AC00 .program_end\nal C:00CFB6 .c128_resident_play_end\nal C:00FEDE .banked_code_end\n"
            )
            (tdir / "plus4" / "ok_case").mkdir(parents=True)
            (tdir / "plus4" / "ok_case" / "main.sym").write_text(".label program_end=$c700\n")

            rep = collect_report(bdir, tdir)
            self.assertEqual(len(rep["ports"]), 1)
            tests = {t["name"]: t for t in rep["tests"]}
            self.assertEqual(tests["tight_case"]["free_bytes"], 22)
            self.assertTrue(tests["tight_case"]["tight"])
            self.assertTrue(tests["slot_tight_case"]["tight"])
            self.assertFalse(tests["unchanged_bank_ok"]["tight"])
            self.assertEqual(tests["ok_case"]["free_bytes"], 256)
            self.assertFalse(tests["ok_case"]["tight"])

            # Verify missing optional build targets exit cleanly when build_dir is empty.
            empty_rep = collect_report(root / "missing_build", tdir)
            self.assertEqual(len(empty_rep["ports"]), 0)

    def test_standalone_prg_estimated_resident_tightness(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bdir = root / "build"
            tdir = bdir / "test"
            (bdir / "c64").mkdir(parents=True)
            # C64 product resident has 76 B free ($BFB4 -> $C000); PRG ends at $C65A.
            (bdir / "c64" / "main.sym").write_text(".label program_end=$BFB4\n")
            (bdir / "c64" / "moria8.prg").write_bytes(_make_prg(0x0801, 0xC65A - 0x0801))

            (tdir / "c64").mkdir(parents=True)
            # +76 B vs prod PRG -> ~0 B est resident free -> TIGHT (not overflow)
            (tdir / "c64" / "moria_zero_free_smoke.prg").write_bytes(_make_prg(0x0801, (0xC65A - 0x0801) + 76))
            # +46 B vs prod PRG -> ~30 B est resident free -> TIGHT
            (tdir / "c64" / "moria_tight_smoke.prg").write_bytes(_make_prg(0x0801, (0xC65A - 0x0801) + 46))
            # +12 B vs prod PRG -> ~64 B est resident free -> OK (boundary)
            (tdir / "c64" / "moria_boundary_ok_smoke.prg").write_bytes(_make_prg(0x0801, (0xC65A - 0x0801) + 12))
            # +80 B vs prod PRG -> -4 B est resident free when PRG grew past prod -> OVERFLOW
            (tdir / "c64" / "moria_est_overflow_smoke.prg").write_bytes(_make_prg(0x0801, (0xC65A - 0x0801) + 80))

            rep = collect_report(bdir, tdir)
            tests = {t["name"]: t for t in rep["tests"]}
            self.assertTrue(tests["moria_zero_free_smoke"]["tight"])
            self.assertFalse(tests["moria_zero_free_smoke"]["overflow"])
            self.assertEqual(tests["moria_zero_free_smoke"]["extra_checks"][0]["free_bytes"], 0)
            self.assertTrue(tests["moria_tight_smoke"]["tight"])
            self.assertFalse(tests["moria_tight_smoke"]["overflow"])
            self.assertEqual(tests["moria_tight_smoke"]["extra_checks"][0]["free_bytes"], 30)
            self.assertFalse(tests["moria_boundary_ok_smoke"]["tight"])
            self.assertFalse(tests["moria_boundary_ok_smoke"]["overflow"])
            self.assertEqual(tests["moria_boundary_ok_smoke"]["extra_checks"][0]["free_bytes"], 64)
            self.assertTrue(tests["moria_est_overflow_smoke"]["overflow"])
            self.assertEqual(tests["moria_est_overflow_smoke"]["extra_checks"][0]["free_bytes"], -4)
            self.assertIn("est. resident ~30 B (<$C000)", tests["moria_tight_smoke"]["note"])

    def test_phase1_port_budgets_and_bank_summaries(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bdir = root / "build"
            tdir = bdir / "test"

            # 1. C64 disk & cart C64HiddenAux ($D700-$DEFF)
            c64 = bdir / "c64"
            c64.mkdir(parents=True)
            (c64 / "main.sym").write_text(".label program_end=$beac\n.label zp_save_buf=$d700\n.label msg_history=$d78e\n")
            c64c = bdir / "c64-cart"
            c64c.mkdir(parents=True)
            (c64c / "main.sym").write_text(".label program_end=$bbce\n.label msg_history=$d78e\n")

            # 2. Plus/4 disk & cart Plus4HighBss ($DF00-$DFFF)
            p4 = bdir / "plus4"
            p4.mkdir(parents=True)
            (p4 / "main.sym").write_text(".label program_end=$c705\n.label plus4_high_bss_end=$dfa0\n")
            p4c = bdir / "plus4-cart"
            p4c.mkdir(parents=True)
            (p4c / "main.sym").write_text(".label program_end=$c54b\n.label plus4_high_bss_end=$dfa0\n")

            # 3. C128 disk & cart merged Bank 0 (<$AF00) + cart_reader + MD128 CRT dir slots
            c128 = bdir / "c128"
            c128.mkdir(parents=True)
            (c128 / "main.sym").write_text(
                ".label program_end=$aca3\n.label c128_resident_persist_end=$bbc3\n"
                ".label c128_resident_play_end=$cfb6\n.label banked_code_end=$fede\n"
            )
            (c128 / "moria128.prg").write_bytes(_make_prg(0x1C01, 0xACA3 - 0x1C01))
            c128c = bdir / "c128-cart"
            c128c.mkdir(parents=True)
            (c128c / "main.sym").write_text(
                ".label program_end=$ab04\n.label cart_reader_start=$1fe6\n.label cart_reader_end=$21d1\n"
                ".label c128_resident_persist_end=$bbc3\n.label c128_resident_play_end=$cfb6\n"
                ".label banked_code_end=$fede\n"
            )
            (c128c / "moria128.prg").write_bytes(_make_prg(0x1C01, 0xAB04 - 0x1C01))
            md128_bank0 = bytearray(b"\xff" * 16384)
            for slot in range(27):
                md128_bank0[0x100 + slot * 8 : 0x100 + (slot + 1) * 8] = bytes([slot + 1] + [0] * 7)
            (bdir / "moria8-c128.crt").write_bytes(_build_synthetic_vice_crt(b"C128 CARTRIDGE  ", 4, [(0, 0x8000, bytes(md128_bank0))]))

            # 4. Apple IIe low scratch, zp_save_buf, MORIA8.PAK, .po, Aux scratch & LC
            a2 = bdir / "apple2"
            (a2 / "bin").mkdir(parents=True)
            (a2 / "main.sym").write_text(
                ".label program_end=$7bd5\n.label a2_play_end=$9fbe\n"
                ".label zp_save_buf=$0200\n.label a2_probe_buf=$0301\n.label input_kbdbuf_shadow=$033a\n"
                ".label a2_aux_scratch_base=$0200\n.label a2_aux_scratch_end=$03ff\n"
            )
            (a2 / "bin" / "MORIA8.PAK").write_bytes(bytes([19]) + b"\x00" * 511)
            (bdir / "moria8-apple2.po").write_bytes(_build_synthetic_po(280, 31))

            # 5. CX16 BankSummary
            cx16 = bdir / "cx16"
            cx16.mkdir(parents=True)
            (cx16 / "main.sym").write_text(".label program_end=$993b\n")

            # 6. Atari 8-bit disk (130XE binary slot tables in MORIA8.RES) & cart (none)
            a8 = bdir / "atari8"
            a8.mkdir(parents=True)
            res_start = 0x0C00
            portb_off = 0x15D9 - res_start
            win_off = 0x15E9 - res_start
            pages_off = 0x1609 - res_start
            res_payload = bytearray(0xC0AF - res_start)
            # Construct exact 64/64/64/29 = 221 pages packing with Bank 3 ending at $5D00
            slot_portb = [0xE2, 0xE2, 0xE2, 0xEE, 0xE2, 0xE6, 0xE6, 0xE6, 0xEE, 0xE6, 0xEA, 0xEA, 0xEA, 0xEA, 0xE2, 0xE6]
            slot_winhi = [0x40, 0x50, 0x60, 0x4E, 0x70, 0x40, 0x50, 0x60, 0x40, 0x70, 0x40, 0x50, 0x60, 0x70, 0x7D, 0x7D]
            slot_pages = [16, 16, 16, 15, 13, 16, 16, 16, 14, 13, 16, 16, 16, 16, 3, 3]
            res_payload[portb_off : portb_off + 16] = bytes(slot_portb)
            res_payload[win_off : win_off + 16] = bytes(slot_winhi)
            res_payload[pages_off : pages_off + 16] = bytes(slot_pages)
            (a8 / "MORIA8.RES").write_bytes(struct.pack("<H", res_start) + bytes(res_payload))
            (a8 / "main.sym").write_text(
                ".label low_helpers_end=$220b\n.label program_end=$c0af\n"
                ".label xe_slot_portb=$15d9\n.label xe_slot_win_hi=$15e9\n.label xe_slot_pages=$1609\n"
            )
            a8c = bdir / "atari8-cart"
            a8c.mkdir(parents=True)
            (a8c / "main.sym").write_text(".label low_helpers_end=$2200\n.label program_end=$bdbc\n")

            # 7. BBC Master 128 ANDY split & BeebLynneAux
            beeb = bdir / "bbcmaster"
            beeb.mkdir(parents=True)
            (beeb / "main.sym").write_text(
                ".label low_helpers_end=$2437\n.label program_end=$7f80\n"
                ".label ovl_huffdata_end=$8edd\n.label zp_save_buf=$8f00\n.label beeb_lynne_aux_end=$4020\n"
            )
            (beeb / "beeb.huffdata").write_bytes(_make_prg(0x8000, 0x0EDD))

            rep = collect_report(bdir, tdir)
            ports_by_sub = {p["build_subdir"]: p for p in rep["ports"]}
            segs = {sub: {s["name"]: s for s in p["segments"]} for sub, p in ports_by_sub.items()}
            banks = {sub: {b["name"]: b for b in p["banks"]} for sub, p in ports_by_sub.items()}

            # Assertions: C64
            self.assertEqual(segs["c64"]["C64HiddenAux"]["used_bytes"], 462)
            self.assertEqual(segs["c64"]["C64HiddenAux"]["free_bytes"], 1586)
            self.assertIn("REU", segs["c64"]["C64HiddenAux"]["note"])
            self.assertEqual(segs["c64-cart"]["C64HiddenAux"]["free_bytes"], 1586)
            self.assertIn("omitted on cart", segs["c64-cart"]["C64HiddenAux"]["note"])

            # Assertions: Plus/4
            self.assertEqual(segs["plus4"]["Plus4HighBss"]["used_bytes"], 160)
            self.assertEqual(segs["plus4"]["Plus4HighBss"]["free_bytes"], 96)
            self.assertIn("LRU cache", segs["plus4"]["Plus4HighBss"]["note"])
            self.assertEqual(segs["plus4-cart"]["Plus4HighBss"]["free_bytes"], 96)

            # Assertions: C128
            for legacy in ("128.world", "128.item", "128.select", "128.diskio"):
                self.assertNotIn(legacy, segs["c128"])
            self.assertEqual(segs["c128"]["Default (moria128)"]["ceil_addr"], 0xAF00)
            self.assertEqual(segs["c128"]["Default (moria128)"]["free_bytes"], 605)
            self.assertEqual(segs["c128-cart"]["Default (moria128)"]["free_bytes"], 1020)
            self.assertEqual(segs["c128-cart"]["cart_reader (MMU_CR=$3A)"]["ceil_addr"], 0x8000)
            self.assertEqual(segs["c128-cart"]["cart_reader (MMU_CR=$3A)"]["free_bytes"], 24111)
            self.assertEqual(banks["c128-cart"]["MD128 Directory Slots"]["used_units"], 27)
            self.assertEqual(banks["c128-cart"]["MD128 Directory Slots"]["total_units"], 32)
            self.assertEqual(banks["c128-cart"]["MD128 Directory Slots"]["free_units"], 5)
            self.assertIn("C128M-002 spike-verified", banks["c128"]["Bank 1 High RAM ($D000-$DFFF)"]["note"])

            # Assertions: Apple IIe
            self.assertEqual(segs["apple2"]["MainZPSave (zp_save_buf)"]["used_bytes"], 142)
            self.assertEqual(segs["apple2"]["MainZPSave (zp_save_buf)"]["free_bytes"], 2)
            self.assertEqual(segs["apple2"]["MainLowScratch"]["used_bytes"], 58)
            self.assertEqual(segs["apple2"]["MainLowScratch"]["free_bytes"], 1)
            self.assertEqual(banks["apple2"]["MORIA8.PAK Entries"]["used_units"], 19)
            self.assertEqual(banks["apple2"]["ProDOS Disk (moria8-apple2.po)"]["free_units"], 31)
            self.assertEqual(banks["apple2"]["Aux Scratch ($0200-$03FF)"]["free_units"], 512)
            self.assertIn("Aux LC Bank 1 & Bank 2 ($D000-$FFF9, ~16 KB)", banks["apple2"]["Aux Language Card ($D000-$FFF9)"]["note"])

            # Assertions: CX16
            self.assertEqual(banks["cx16"]["HiRAM Banks ($A000-$BFFF)"]["used_units"], 21)
            self.assertEqual(banks["cx16"]["HiRAM Banks ($A000-$BFFF)"]["free_units"], 43)
            self.assertIn("CX16_BANK_CATALOG_EXT", banks["cx16"]["HiRAM Banks ($A000-$BFFF)"]["note"])
            self.assertIn("344 KB free", banks["cx16"]["HiRAM Banks ($A000-$BFFF)"]["note"])

            # Assertions: Atari 8-bit
            self.assertEqual(banks["atari8"]["130XE Extended RAM Pages"]["used_units"], 221)
            self.assertEqual(banks["atari8"]["130XE Extended RAM Pages"]["total_units"], 256)
            self.assertEqual(banks["atari8"]["130XE Extended RAM Pages"]["free_units"], 35)
            self.assertIn("8,960 B at Bank 3 $5D00-$7FFF", banks["atari8"]["130XE Extended RAM Pages"]["note"])
            self.assertNotIn("130XE Extended RAM Pages", banks["atari8-cart"])
            xe_sym_stats = _collect_atari_xe_bank_stats(
                a8,
                {"XE_BANK0_USED_PAGES": 64, "XE_BANK1_USED_PAGES": 64, "XE_BANK2_USED_PAGES": 64, "XE_BANK3_USED_PAGES": 29, "XE_BANK3_FREE_PAGES": 35},
            )
            self.assertEqual(xe_sym_stats["used_pages"], 221)
            self.assertEqual(xe_sym_stats["bank3_free"], 35)

            # Assertions: BBC Master 128
            self.assertEqual(segs["bbcmaster"]["ANDY (beeb.huffdata)"]["ceil_addr"], 0x8F00)
            self.assertEqual(segs["bbcmaster"]["ANDY (beeb.huffdata)"]["free_bytes"], 35)
            self.assertTrue(segs["bbcmaster"]["ANDY (beeb.huffdata)"]["tight"])
            self.assertEqual(segs["bbcmaster"]["ANDY (zp_save_buf)"]["used_bytes"], 174)
            self.assertEqual(segs["bbcmaster"]["ANDY (zp_save_buf)"]["free_bytes"], 82)
            self.assertEqual(segs["bbcmaster"]["BeebLynneAux"]["used_bytes"], 160)
            self.assertEqual(segs["bbcmaster"]["BeebLynneAux"]["free_bytes"], 992)
            self.assertIn("BeebLynneAux active (160/1,152 B used, 992 B free)", banks["bbcmaster"]["SWR Banks 4-7 Pages"]["note"])

    def test_phase2_port_budgets_and_bank_summaries(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bdir = root / "build"
            tdir = bdir / "test"

            # 1. C64 disk & cart: ovl.home/storage/title + SaveResidentStateProbe <= $A000
            c64 = bdir / "c64"
            c64.mkdir(parents=True)
            (c64 / "main.sym").write_text(
                ".label program_end=$b8b6\n.label c64_save_resident_state_probe_start=$9b14\n"
                ".label c64_save_resident_state_probe_end=$9bb0\n.label ovl_home_end=$e397\n"
                ".label ovl_storage_end=$ee09\n.label ovl_title_end=$e0c1\n"
            )
            (c64 / "ovl.home").write_bytes(_make_prg(0xE000, 0x0397))
            (c64 / "ovl.storage").write_bytes(_make_prg(0xE000, 0x0E09))
            (c64 / "ovl.title").write_bytes(_make_prg(0xE000, 0x00C1))
            (bdir / "moria8-c64.json").write_text(json.dumps({"roml_bytes_used": 111693, "assets": [{"size": 100} for _ in range(21)]}))
            (bdir / "moria8-c64.crt").write_bytes(
                _build_synthetic_vice_crt(b"C64 CARTRIDGE   ", 32, [(0, 0x8000, b"\x01" * 100 + b"\xff" * 8092)])
            )

            # 2. Plus/4 disk & cart: ovl.home/storage/title + 21-asset Magic Desk CRT manifest
            p4 = bdir / "plus4"
            p4.mkdir(parents=True)
            (p4 / "main.sym").write_text(
                ".label program_end=$c0d0\n.label ovl_home_end=$e397\n"
                ".label ovl_storage_end=$eeef\n.label ovl_title_end=$e0b1\n"
            )
            (p4 / "ovl.home").write_bytes(_make_prg(0xE000, 0x0397))
            (p4 / "ovl.storage").write_bytes(_make_prg(0xE000, 0x0EEF))
            (p4 / "ovl.title").write_bytes(_make_prg(0xE000, 0x00B1))
            p4c = bdir / "plus4-cart"
            p4c.mkdir(parents=True)
            (p4c / "main.sym").write_text((p4 / "main.sym").read_text())
            (p4c / "moria8-plus4.json").write_text(json.dumps({"assets": [{"size": 200} for _ in range(21)]}))
            (bdir / "moria8-plus4.crt").write_bytes(
                _build_synthetic_vice_crt(b"PLUS4 CARTRIDGE ", 1, [(0, 0x8000, b"\x00" * 120 + b"\xff" * 16264)])
            )

            # 3. C128 disk & cart: ovl.home (128.home #11) + 28/32 MD128 dir slots
            c128 = bdir / "c128"
            c128.mkdir(parents=True)
            (c128 / "main.sym").write_text(".label program_end=$ad00\n.label ovl_home_end=$e397\n")
            (c128 / "ovl.home").write_bytes(_make_prg(0xE000, 0x0397))
            c128c = bdir / "c128-cart"
            c128c.mkdir(parents=True)
            (c128c / "main.sym").write_text(".label program_end=$ab61\n.label ovl_home_end=$e397\n")
            (c128c / "ovl.home").write_bytes(_make_prg(0xE000, 0x0397))
            md128_bank0 = bytearray(b"\xff" * 16384)
            for slot in range(28):
                md128_bank0[0x100 + slot * 8 : 0x100 + (slot + 1) * 8] = bytes([slot + 1] + [0] * 7)
            (bdir / "moria8-c128.crt").write_bytes(_build_synthetic_vice_crt(b"C128 CARTRIDGE  ", 4, [(0, 0x8000, bytes(md128_bank0))]))

            # 4. Atari 8-bit: OVL.HOM/STO/TTL + 19-slot MORIA8.RES (235/256) + .atr (20/64) + .car (20 assets)
            a8 = bdir / "atari8"
            a8.mkdir(parents=True)
            res_start = 0x0C00
            portb_off = 0x15FD - res_start
            win_off = 0x1610 - res_start
            pages_off = 0x1636 - res_start
            res_payload = bytearray(0xB844 - res_start)
            slot_portb = [
                0xE2, 0xE2, 0xE2, 0xEE, 0xE2, 0xE6, 0xE6, 0xE6, 0xEE, 0xE6,
                0xEA, 0xEA, 0xEA, 0xEE, 0xE2, 0xE6, 0xEA, 0xEA, 0xEE,
            ]
            slot_winhi = [
                0x40, 0x50, 0x60, 0x4E, 0x70, 0x40, 0x50, 0x60, 0x40, 0x70,
                0x40, 0x50, 0x60, 0x5C, 0x7D, 0x7D, 0x70, 0x72, 0x69,
            ]
            slot_pages = [16, 16, 16, 14, 13, 16, 16, 16, 14, 13, 16, 16, 16, 13, 3, 3, 2, 14, 2]
            res_payload[portb_off : portb_off + 19] = bytes(slot_portb)
            res_payload[win_off : win_off + 19] = bytes(slot_winhi)
            res_payload[pages_off : pages_off + 19] = bytes(slot_pages)
            (a8 / "MORIA8.RES").write_bytes(struct.pack("<H", res_start) + bytes(res_payload))
            (a8 / "main.sym").write_text(
                ".label program_end=$b844\n.label xe_slot_portb=$15fd\n.label xe_slot_win_hi=$1610\n"
                ".label xe_slot_pages=$1636\n.label ovl_home_end=$e397\n"
                ".label ovl_storage_end=$ede8\n.label ovl_title_end=$e11d\n"
            )
            (a8 / "OVL.HOM").write_bytes(_make_prg(0xE000, 0x0397))
            (a8 / "OVL.STO").write_bytes(_make_prg(0xE000, 0x0DE8))
            (a8 / "OVL.TTL").write_bytes(_make_prg(0xE000, 0x011D))
            a8c = bdir / "atari8-cart"
            a8c.mkdir(parents=True)
            (a8c / "main.sym").write_text(".label program_end=$b540\n.label ovl_home_end=$e397\n")
            (a8c / "moria8-atari8.json").write_text(json.dumps({"assets": [{"size": 300} for _ in range(20)]}))
            (bdir / "moria8-atari8.atr").write_bytes(_build_synthetic_atr(0, 140, file_count=20))
            (bdir / "moria8-atari8.car").write_bytes(_build_synthetic_car(111360, 131072))

            # 5. Apple IIe: ovl.home + 20/42 PAK + 250/280 .po
            a2 = bdir / "apple2"
            (a2 / "bin").mkdir(parents=True)
            (a2 / "main.sym").write_text(".label program_end=$7ade\n.label a2_play_end=$9eb2\n.label ovl_home_end=$a91c\n")
            (a2 / "ovl.home").write_bytes(_make_prg(0xA400, 0x051C))
            (a2 / "bin" / "MORIA8.PAK").write_bytes(bytes([20]) + b"\x00" * 511)
            (bdir / "moria8-apple2.po").write_bytes(_build_synthetic_po(280, 30))

            # 6. BBC Master 128: ovl.home (DFS OVLHOM) + 15/31 .ssd (384/800 free)
            beeb = bdir / "bbcmaster"
            beeb.mkdir(parents=True)
            (beeb / "main.sym").write_text(".label program_end=$7ebd\n.label ovl_home_end=$ad0e\n")
            (beeb / "ovl.home").write_bytes(_make_prg(0xA800, 0x050E))
            (bdir / "moria8-bbcmaster.ssd").write_bytes(_build_synthetic_ssd([256] * 15, 800))

            # 7. CX16 disk & cart: OVL.HOME Bank 19, shifted Banks 20-24, CartLiveHelperLimit ($9980), 21/64 HiRAM, 21 CRT assets
            cx16 = bdir / "cx16"
            cx16.mkdir(parents=True)
            (cx16 / "main.sym").write_text(
                ".label program_end=$93fb\n.label ovl_home_end=$a49d\n.label ovl_storage_end=$ad10\n"
                ".label ovl_title_end=$a220\n.label catalog_bank_end=$b758\n.label legal_code_end=$a3aa\n.label legal_zp_save=$a600\n"
            )
            (cx16 / "OVL.HOME").write_bytes(_make_prg(0xA000, 0x049D))
            cx16c = bdir / "cx16-cart"
            cx16c.mkdir(parents=True)
            (cx16c / "main.sym").write_text((cx16 / "main.sym").read_text().replace("$93fb", "$9411"))
            (cx16c / "MORIA8.PRG").write_bytes(_make_prg(0x0801, 0x9411 - 0x0801))
            (cx16c / "moria8-cx16.json").write_text(json.dumps({"assets": [{"size": 400} for _ in range(21)]}))
            (bdir / "moria8-cx16.crt").write_bytes(_build_synthetic_cx16_crt(101776, 131072))

            rep = collect_report(bdir, tdir)
            segs = {p["build_subdir"]: {s["name"]: s for s in p["segments"]} for p in rep["ports"]}
            banks = {p["build_subdir"]: {b["name"]: b for b in p["banks"]} for p in rep["ports"]}
            media = {(m["port"], m["kind"]): m for m in rep["media"]}

            # C64
            self.assertEqual(segs["c64"]["SaveResidentStateProbe"]["free_bytes"], 1104)
            self.assertEqual(segs["c64"]["ovl.home"]["free_bytes"], 3177)
            self.assertEqual(segs["c64"]["ovl.storage"]["free_bytes"], 503)
            self.assertEqual(segs["c64"]["ovl.title"]["free_bytes"], 3903)
            self.assertEqual(media[("c64", "crt")]["entries_used"], 21)

            # Plus/4
            self.assertEqual(segs["plus4"]["ovl.home"]["free_bytes"], 3177)
            self.assertEqual(segs["plus4"]["ovl.storage"]["free_bytes"], 273)
            self.assertEqual(segs["plus4"]["ovl.title"]["free_bytes"], 3919)
            self.assertEqual(media[("plus4", "crt")]["entries_used"], 21)
            self.assertIn("21 assets", media[("plus4", "crt")]["note"])

            # C128
            self.assertEqual(segs["c128"]["ovl.home"]["free_bytes"], 3177)
            self.assertIn("128.home", segs["c128"]["ovl.home"]["note"])
            self.assertIn("SAVE_IN_STORAGE_OVERLAY OFF", segs["c128"]["ovl.home"]["note"])
            self.assertEqual(banks["c128-cart"]["MD128 Directory Slots"]["used_units"], 28)
            self.assertEqual(banks["c128-cart"]["MD128 Directory Slots"]["free_units"], 4)

            # Atari 8-bit
            self.assertEqual(segs["atari8"]["OVL.HOM"]["free_bytes"], 3177)
            self.assertEqual(segs["atari8"]["OVL.STO"]["free_bytes"], 536)
            self.assertEqual(segs["atari8"]["OVL.TTL"]["free_bytes"], 3811)
            self.assertEqual(banks["atari8"]["130XE Extended RAM Pages"]["used_units"], 235)
            self.assertEqual(banks["atari8"]["130XE Extended RAM Pages"]["free_units"], 21)
            self.assertIn("64/64/64/43/64p (Slots 0..18)", banks["atari8"]["130XE Extended RAM Pages"]["note"])
            self.assertIn("5,376 B at Bank 3 $6B00-$7FFF", banks["atari8"]["130XE Extended RAM Pages"]["note"])
            self.assertEqual(media[("atari8", "atr")]["entries_used"], 20)
            self.assertIn("20/64 files", media[("atari8", "atr")]["note"])
            self.assertEqual(media[("atari8", "car")]["entries_used"], 20)
            self.assertIn("20 assets", media[("atari8", "car")]["note"])

            # Apple IIe
            self.assertEqual(segs["apple2"]["ovl.home"]["ceil_addr"], 0xBA00)
            self.assertEqual(segs["apple2"]["ovl.home"]["free_bytes"], 4324)
            self.assertEqual(banks["apple2"]["MORIA8.PAK Entries"]["used_units"], 20)
            self.assertEqual(banks["apple2"]["ProDOS Disk (moria8-apple2.po)"]["used_units"], 250)
            self.assertEqual(banks["apple2"]["ProDOS Disk (moria8-apple2.po)"]["free_units"], 30)

            # BBC Master 128
            self.assertEqual(segs["bbcmaster"]["ovl.home"]["ceil_addr"], 0xC000)
            self.assertEqual(segs["bbcmaster"]["ovl.home"]["free_bytes"], 4850)
            self.assertIn("DFS OVLHOM", segs["bbcmaster"]["ovl.home"]["note"])
            self.assertEqual(media[("bbcmaster", "ssd")]["entries_used"], 15)

            # CX16
            self.assertEqual(segs["cx16"]["OVL.HOME"]["free_bytes"], 7011)
            self.assertIn("Bank 19", segs["cx16"]["OVL.HOME"]["note"])
            self.assertIn("TITLE (Bank 22)", segs["cx16"])
            self.assertIn("MONSTER.CAT (Bank 23)", segs["cx16"])
            self.assertIn("Bank 24", segs["cx16"]["LEGALUI"]["note"])
            self.assertEqual(segs["cx16-cart"]["CartLiveHelperLimit ($9980)"]["free_bytes"], 1391)
            self.assertEqual(banks["cx16"]["HiRAM Banks ($A000-$BFFF)"]["used_units"], 21)
            self.assertEqual(banks["cx16"]["HiRAM Banks ($A000-$BFFF)"]["free_units"], 43)
            self.assertIn("344 KB free", banks["cx16"]["HiRAM Banks ($A000-$BFFF)"]["note"])
            self.assertEqual(media[("cx16", "crt")]["entries_used"], 21)
            self.assertIn("21 assets", media[("cx16", "crt")]["note"])

    def test_phase4_port_budgets_and_bank_summaries(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bdir = root / "build"
            tdir = bdir / "test"

            # 1. C64 disk & cart: C64HiddenAux with recall_data_end ($DD2A -> 470 B free)
            c64 = bdir / "c64"
            c64.mkdir(parents=True)
            (c64 / "main.sym").write_text(".label program_end=$bf43\n.label zp_save_buf=$d700\n.label msg_history=$d78e\n.label recall_data_end=$dd2a\n")
            c64c = bdir / "c64-cart"
            c64c.mkdir(parents=True)
            (c64c / "main.sym").write_text(".label program_end=$b8b4\n.label msg_history=$d78e\n.label recall_data_end=$dd2a\n")

            # 2. Plus/4 disk (254 B item.cat buf) & cart (Plus4HighBss omitted -> 0 B used, 256 B free)
            p4 = bdir / "plus4"
            p4.mkdir(parents=True)
            (p4 / "main.sym").write_text(".label program_end=$c71b\n.label plus4_high_bss_end=$dffe\n")
            p4c = bdir / "plus4-cart"
            p4c.mkdir(parents=True)
            (p4c / "main.sym").write_text(".label program_end=$c313\n")

            # 3. C128 disk & cart: Bank1DB ($7400-$7A60, zp_save_buf=$785c + 142B = $78EA -> 374 B free), ovl.storage, 29/32 MD128 slots
            c128 = bdir / "c128"
            c128.mkdir(parents=True)
            (c128 / "main.sym").write_text(".label program_end=$adf9\n.label zp_save_buf=$785c\n.label ovl_home_end=$ee61\n.label ovl_storage_end=$effb\n")
            (c128 / "ovl.home").write_bytes(_make_prg(0xE000, 0x0E61))
            (c128 / "ovl.storage").write_bytes(_make_prg(0xE000, 0x0FFB))
            c128c = bdir / "c128-cart"
            c128c.mkdir(parents=True)
            (c128c / "main.sym").write_text((c128 / "main.sym").read_text())
            (c128c / "ovl.home").write_bytes(_make_prg(0xE000, 0x0E61))
            (c128c / "ovl.storage").write_bytes(_make_prg(0xE000, 0x0FFB))
            md128_bank0 = bytearray(b"\xff" * 16384)
            for slot in range(29):
                md128_bank0[0x100 + slot * 8 : 0x100 + (slot + 1) * 8] = bytes([slot + 1] + [0] * 7)
            (bdir / "moria8-c128.crt").write_bytes(_build_synthetic_vice_crt(b"C128 CARTRIDGE  ", 4, [(0, 0x8000, bytes(md128_bank0))]))

            # 4. Atari 8-bit: HighRAM Tail uses consol_released ($DFC3+1=$DFC4 -> 60 B free) when id_known_bits is in Default ($2809)
            a8 = bdir / "atari8"
            a8.mkdir(parents=True)
            (a8 / "main.sym").write_text(
                ".label program_end=$c081\n.label msg_history_atari=$ddce\n.label high_resident_end=$df3e\n"
                ".label combat_msg_buf=$df3e\n.label consol_released=$dfc3\n.label id_known_bits=$2809\n"
                ".label XE_BANK0_USED_PAGES=$40\n.label XE_BANK1_USED_PAGES=$40\n.label XE_BANK2_USED_PAGES=$40\n.label XE_BANK3_USED_PAGES=$40\n"
            )

            # 5. Apple IIe: Aux LC active (1,116 B recall[279] + 7,573 B ITEM.CAT = 8,689 B used)
            a2 = bdir / "apple2"
            (a2 / "bin").mkdir(parents=True)
            (a2 / "main.sym").write_text(".label program_end=$7baa\n.label a2_aux_scratch_base=$0200\n.label a2_aux_scratch_end=$03ff\n")
            (a2 / "bin" / "ITEM.CAT").write_bytes(b"\x00" * 7573)

            # 6. CX16: Bank 6 ITEM.CAT -> 22/64 HiRAM banks used (42 free = 336 KB)
            cx16 = bdir / "cx16"
            cx16.mkdir(parents=True)
            (cx16 / "main.sym").write_text(".label program_end=$9347\n")
            (cx16 / "ITEM.CAT").write_bytes(_make_prg(0xA000, 7573))

            # 7. BBC Master 128: BeebAuxData 19p ($7300 ceil), cache.ovl.items 23p ($1700), cache.ovl.gen 16p ($1000), BeebLynneAux 1,116B
            beeb = bdir / "bbcmaster"
            beeb.mkdir(parents=True)
            (beeb / "main.sym").write_text(".label program_end=$7fdc\n.label beeb_lynne_aux_end=$43dc\n.label ovl_auxdata_end=$72d8\n")
            (beeb / "beeb.auxdata").write_bytes(_make_prg(0x6000, 0x12D8))
            (beeb / "ovl.items").write_bytes(_make_prg(0xA800, 5721))
            (beeb / "ovl.gen").write_bytes(_make_prg(0xA800, 3922))

            rep = collect_report(bdir, tdir)
            segs = {p["build_subdir"]: {s["name"]: s for s in p["segments"]} for p in rep["ports"]}
            banks = {p["build_subdir"]: {b["name"]: b for b in p["banks"]} for p in rep["ports"]}

            self.assertEqual(segs["c64"]["C64HiddenAux"]["used_bytes"], 1578)
            self.assertEqual(segs["c64"]["C64HiddenAux"]["free_bytes"], 470)
            self.assertEqual(segs["c64-cart"]["C64HiddenAux"]["free_bytes"], 470)

            self.assertEqual(segs["plus4"]["Plus4HighBss"]["used_bytes"], 254)
            self.assertEqual(segs["plus4"]["Plus4HighBss"]["free_bytes"], 2)
            self.assertEqual(segs["plus4-cart"]["Plus4HighBss"]["status"], "ok")
            self.assertEqual(segs["plus4-cart"]["Plus4HighBss"]["used_bytes"], 0)
            self.assertEqual(segs["plus4-cart"]["Plus4HighBss"]["free_bytes"], 256)

            self.assertNotIn("128.names (Bank1)", segs["c128"])
            self.assertEqual(segs["c128"]["Bank1DB (Bank1)"]["used_bytes"], 1258)
            self.assertEqual(segs["c128"]["Bank1DB (Bank1)"]["free_bytes"], 374)
            self.assertEqual(segs["c128"]["ovl.storage"]["free_bytes"], 5)
            self.assertEqual(banks["c128-cart"]["MD128 Directory Slots"]["used_units"], 29)
            self.assertEqual(banks["c128-cart"]["MD128 Directory Slots"]["free_units"], 3)

            self.assertEqual(segs["atari8"]["HighRAM Tail"]["end_addr"], 0xDFC4)
            self.assertEqual(segs["atari8"]["HighRAM Tail"]["used_bytes"], 134)
            self.assertEqual(segs["atari8"]["HighRAM Tail"]["free_bytes"], 60)
            self.assertEqual(banks["atari8"]["130XE Extended RAM Pages"]["used_units"], 256)
            self.assertEqual(banks["atari8"]["130XE Extended RAM Pages"]["free_units"], 0)
            self.assertIn("Bank 3 $4000-$7FFF full", banks["atari8"]["130XE Extended RAM Pages"]["note"])

            self.assertEqual(banks["apple2"]["Aux Language Card ($D000-$FFF9)"]["used_units"], 8689)
            self.assertEqual(banks["apple2"]["Aux Language Card ($D000-$FFF9)"]["free_units"], 7689)

            self.assertEqual(segs["cx16"]["ITEM.CAT (Bank 6)"]["used_bytes"], 7573)
            self.assertEqual(segs["cx16"]["ITEM.CAT (Bank 6)"]["free_bytes"], 619)
            self.assertEqual(banks["cx16"]["HiRAM Banks ($A000-$BFFF)"]["used_units"], 22)
            self.assertEqual(banks["cx16"]["HiRAM Banks ($A000-$BFFF)"]["free_units"], 42)
            self.assertIn("336 KB free", banks["cx16"]["HiRAM Banks ($A000-$BFFF)"]["note"])

            self.assertEqual(segs["bbcmaster"]["BeebLynneAux"]["used_bytes"], 1116)
            self.assertEqual(segs["bbcmaster"]["BeebLynneAux"]["free_bytes"], 36)
            self.assertEqual(segs["bbcmaster"]["BeebAuxData (Bank 6)"]["ceil_addr"], 0x7300)
            self.assertEqual(segs["bbcmaster"]["BeebAuxData (Bank 6)"]["free_bytes"], 40)
            self.assertEqual(segs["bbcmaster"]["cache.ovl.items (Bank 7)"]["ceil_addr"], 0x1700)
            self.assertEqual(segs["bbcmaster"]["cache.ovl.items (Bank 7)"]["free_bytes"], 167)
            self.assertFalse(segs["bbcmaster"]["cache.ovl.items (Bank 7)"]["overflow"])
            self.assertEqual(segs["bbcmaster"]["cache.ovl.gen (Bank 7)"]["ceil_addr"], 0x1000)
            self.assertEqual(segs["bbcmaster"]["cache.ovl.gen (Bank 7)"]["free_bytes"], 174)

    def test_phase5_port_budgets_and_bank_summaries(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bdir = root / "build"
            tdir = bdir / "test"

            c128 = bdir / "c128"
            c128.mkdir(parents=True)
            (c128 / "main.sym").write_text(".label program_end=$ae7e\n.label msg_history=$dcb8\n.label msg_history_end=$df38\n")
            (c128 / "128.cex.prg").write_bytes(_make_prg(0xD000, 2232))

            a2 = bdir / "apple2"
            (a2 / "bin").mkdir(parents=True)
            (a2 / "main.sym").write_text(".label program_end=$7bde\n.label a2_aux_scratch_base=$0200\n.label a2_aux_scratch_end=$03ff\n")
            (a2 / "bin" / "ITEM.CAT").write_bytes(b"\x00" * 7573)
            (a2 / "bin" / "A2.CATEXT").write_bytes(b"\x00" * 2232)

            cx16 = bdir / "cx16"
            cx16.mkdir(parents=True)
            (cx16 / "main.sym").write_text(".label program_end=$9368\n")
            (cx16 / "ITEM.CAT").write_bytes(_make_prg(0xA000, 7573))
            (cx16 / "MONSTER.EXT").write_bytes(_make_prg(0xA000, 2232))

            beeb = bdir / "bbcmaster"
            (beeb / "bin").mkdir(parents=True)
            (beeb / "main.sym").write_text(".label program_end=$7f5f\n.label beeb_lynne_aux_end=$43dc\n")
            (beeb / "bin" / "MON.EXT").write_bytes(b"\x00" * 2232)

            rep = collect_report(bdir, tdir)
            segs = {p["build_subdir"]: {s["name"]: s for s in p["segments"]} for p in rep["ports"]}
            banks_by_port = {p["build_subdir"]: {b["name"]: b for b in p["banks"]} for p in rep["ports"]}

            self.assertEqual(segs["c128"]["Bank1High / 128.cex (Bank1)"]["used_bytes"], 3896)
            self.assertEqual(segs["c128"]["Bank1High / 128.cex (Bank1)"]["free_bytes"], 200)
            self.assertEqual(banks_by_port["c128"]["Bank 1 High RAM ($D000-$DFFF)"]["used_units"], 3896)
            self.assertEqual(banks_by_port["c128"]["Bank 1 High RAM ($D000-$DFFF)"]["free_units"], 200)

            self.assertEqual(segs["apple2"]["A2.CATEXT (Aux LC B2)"]["used_bytes"], 2232)
            self.assertEqual(segs["apple2"]["A2.CATEXT (Aux LC B2)"]["free_bytes"], 1864)
            self.assertEqual(banks_by_port["apple2"]["Aux Language Card ($D000-$FFF9)"]["used_units"], 10921)
            self.assertEqual(banks_by_port["apple2"]["Aux Language Card ($D000-$FFF9)"]["free_units"], 5457)

            self.assertEqual(segs["cx16"]["MONSTER.EXT (Bank 5)"]["used_bytes"], 2232)
            self.assertEqual(segs["cx16"]["MONSTER.EXT (Bank 5)"]["free_bytes"], 5960)
            self.assertEqual(banks_by_port["cx16"]["HiRAM Banks ($A000-$BFFF)"]["used_units"], 23)
            self.assertEqual(banks_by_port["cx16"]["HiRAM Banks ($A000-$BFFF)"]["free_units"], 41)
            self.assertIn("328 KB free", banks_by_port["cx16"]["HiRAM Banks ($A000-$BFFF)"]["note"])

            self.assertEqual(segs["bbcmaster"]["MONEXT (DFS)"]["used_bytes"], 2232)
            self.assertEqual(segs["bbcmaster"]["MONEXT (DFS)"]["free_bytes"], 72)


def run_selftest() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(_BudgetSelfTests)
    runner = unittest.TextTestRunner(stream=sys.stdout, verbosity=2)
    result = runner.run(suite)
    return 0 if result.wasSuccessful() else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Report Moria8 product, shipping media, and test variant memory budgets.")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of Markdown")
    parser.add_argument("--port", default=None, help="Filter to a port (e.g. c64, c64-cart, plus4, c128, apple2, cx16, atari8, bbcmaster)")
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR, help="Build directory root (default: build/)")
    parser.add_argument("--test-dir", type=Path, default=None, help="Test artifact root (default: <build-dir>/test)")
    parser.add_argument("--selftest", action="store_true", help="Run synthetic parser and boundary unit tests")
    args = parser.parse_args(argv)

    if args.selftest:
        return run_selftest()

    build_dir = args.build_dir
    test_dir = args.test_dir if args.test_dir is not None else (build_dir / "test")
    report = collect_report(build_dir=build_dir, test_dir=test_dir, port_filter=args.port)

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(render_markdown(report), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
