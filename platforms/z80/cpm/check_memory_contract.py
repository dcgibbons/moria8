#!/usr/bin/env python3
"""Static memory-contract checker for the CP/M 2.2 Z80 port (platforms/z80/cpm/)."""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import argparse
import os
import re
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path


CPM_SRC_DIR = Path(__file__).resolve().parent
ROOT = CPM_SRC_DIR.parents[2]
DEFAULT_BUILD_DIR = ROOT / "build" / "cpm"
CORE_Z80_DIR = ROOT / "core" / "z80"
DEFAULT_SJASMPLUS = Path(os.environ.get("SJASMPLUS") or (ROOT / "tools" / "sjasmplus" / "sjasmplus"))

# ============================================================
# Authoritative 52 KB TPA Memory Contract Constants
# (must stay synced with platforms/z80/cpm/memory.inc & docs/CPM_MEMORY_CONTRACT.md)
# ============================================================
BDOS_MIN_TOP = 0xD100
CPM_RECORD_SIZE = 128

RESIDENT_BASE = 0x0100
RESIDENT_LIMIT = 0x5600
RESIDENT_MAX_SIZE = 0x5500  # 21,760 B

OVL_WINDOW_BASE = 0x5600
OVL_WINDOW_LIMIT = 0x6A00
OVL_WINDOW_SIZE = 0x1400  # 5,120 B = 40 * 128 B
OVL_MAX_RECORDS = 40

BSS_BASE = 0x6A00
BSS_LIMIT = 0x8C00
BSS_MAX_SIZE = 0x2200  # 8,704 B
Z80_STATE_BASE = 0x6A00
Z80_STATE_SIZE = 64

STACK_BOTTOM = 0x8C00
STACK_TOP = 0x8E00
STACK_CANARY_ADDR = 0x8C00

CPM_CHAR_SHADOW_BASE = 0x8E00
CPM_CHAR_SHADOW_SIZE = 1920
CPM_COLOR_SHADOW_BASE = 0x9580
CPM_COLOR_SHADOW_SIZE = 1920

MAP_BASE = 0x9D00
MAP_SIZE = 13068  # 198 * 66
MAP_END = 0xD00B

FCB_POOL_BASE = 0xD00C
FCB_SIZE = 36
FCB_DAT_ADDR = 0xD00C
FCB_SAVE_ADDR = 0xD030
FCB_TMP_ADDR = 0xD054
FCB_POOL_LIMIT = 0xD080

CPM_DMA_BUF_BASE = 0xD080
CPM_DMA_BUF_SIZE = 128

# Explicit MORIA8.DAT TOC slot mapping for all 19 overlays:
#   slots 0..13  -> ovl_start..ovl_legal
#   slots 14..19 -> RO assets (MONSTER_CAT, ITEM_CAT, HUFF_STREAM, TITLE_ART, LICENSE, SRCOFFR)
#   slots 20..24 -> split gameplay overlays (ovl_items_eff..ovl_item_mgt)
OVERLAY_SLOT_MAP: dict[int, str] = {
    0: "ovl_start",
    1: "ovl_town",
    2: "ovl_death",
    3: "ovl_gen",
    4: "ovl_help",
    5: "ovl_ui",
    6: "ovl_items",
    7: "ovl_spell",
    8: "ovl_modal",
    9: "ovl_chest",
    10: "ovl_home",
    11: "ovl_storage",
    12: "ovl_title",
    13: "ovl_legal",
    20: "ovl_items_eff",
    21: "ovl_spell_eff",
    22: "ovl_actions",
    23: "ovl_mon_ext",
    24: "ovl_item_mgt",
}
OVERLAY_NAMES: tuple[str, ...] = tuple(OVERLAY_SLOT_MAP.values())
M1_REQUIRED_OVERLAYS: tuple[str, ...] = ("ovl_title", "ovl_legal")
M2_REQUIRED_OVERLAYS: tuple[str, ...] = (
    "ovl_title",
    "ovl_legal",
    "ovl_start",
    "ovl_gen",
    "ovl_town",
    "ovl_home",
    "ovl_storage",
)
M3_REQUIRED_OVERLAYS: tuple[str, ...] = M2_REQUIRED_OVERLAYS + (
    "ovl_actions",
    "ovl_chest",
    "ovl_modal",
    "ovl_ui",
    "ovl_help",
    "ovl_death",
)
OVERLAY_SHORT_NAMES: tuple[str, ...] = tuple(
    sorted((name[len("ovl_"):] for name in OVERLAY_NAMES), key=lambda s: (-len(s), s))
)

CALL_JP_3BYTE_OPCODES: frozenset[int] = frozenset({
    0xCD, 0xC4, 0xCC, 0xD4, 0xDC, 0xE4, 0xEC, 0xF4, 0xFC,  # CALL nn / CALL cc, nn
    0xC3, 0xC2, 0xCA, 0xD2, 0xDA, 0xE2, 0xEA, 0xF2, 0xFA,  # JP nn / JP cc, nn
})
JR_DJNZ_2BYTE_OPCODES: frozenset[int] = frozenset({
    0x10, 0x18, 0x20, 0x28, 0x30, 0x38,  # DJNZ e / JR e / JR cc, e
})
LST_FILE_OPEN_RE = re.compile(r"^#\s*file\s+opened:\s*(.+?)\s*$")
LST_FILE_CLOSE_RE = re.compile(r"^#\s*file\s+closed:\s*(.+?)\s*$")
LST_LINE_RE = re.compile(r"^\s*\d+\+?\s+([0-9A-Fa-f]{4})\s(.*)$")
LST_HEX_BYTES_RE = re.compile(r"^[0-9A-Fa-f]{2}(?:\s+[0-9A-Fa-f]{2})*$")

DAT_MAGIC = b"M8CP"
DAT_VERSION = 1
DAT_HEADER_RECORDS = 2
DAT_HEADER_BYTES = 256
DAT_MAX_ENTRIES = 41
DAT_MAX_REC_COUNT = 255   # u8 rec_count limit in 3-byte in-RAM DAT TOC cache
DAT_MIN_RO_SLOTS = 20     # slots 0..19 always in TOC; 14..19 RO data must always be non-empty
DAT_RO_REQUIRED_SLOTS = range(14, 20)
DAT_RO_SLOT_FILES: dict[int, str] = {
    14: "monster_cat_ascii.bin",
    15: "item_cat_ascii.bin",
    16: "huff_stream.bin",
    17: "title_art.bin",
    18: "license.txt",
    19: "srcoffr.txt",
}
DAT_REQUIRED_SLOTS = 25   # slots 0..24 for full m5/all milestone

# sjasmplus --sym line format: "LABEL: EQU 0x00005600"
SYM_LINE_RE = re.compile(
    r"^([A-Za-z_@.][A-Za-z0-9_@.]*):\s*EQU\s+(?:0x|\$)([0-9A-Fa-f]+)\s*$"
)
LABEL_DEF_RE = re.compile(r"^(@?[A-Za-z_][A-Za-z0-9_.]*)\s*:")
MODULE_START_RE = re.compile(r"^MODULE\s+([A-Za-z_][A-Za-z0-9_]*)\b", re.IGNORECASE)
MODULE_END_RE = re.compile(r"^ENDMODULE\b", re.IGNORECASE)
INCLUDE_RE = re.compile(r'^\s*INCLUDE\s+["\']([^"\']+)["\']', re.IGNORECASE)

COND_SET = {"NZ", "Z", "NC", "C", "PO", "PE", "P", "M"}
Z80_CTRL_FLOW_RE = re.compile(r"^(CALL|JP|JR|DJNZ)\s+(.+)$", re.IGNORECASE)
# Longest-first short-name alternation prevents ovl_items matching ovl_items_eff_*.
OVL_PREFIX_RE = re.compile(
    r"^ovl_(" + "|".join(OVERLAY_SHORT_NAMES) + r")([_.])([A-Za-z0-9_.]+)$"
)

Z80_RESERVED_WORDS = {
    "ADC", "ADD", "AND", "BIT", "CALL", "CCF", "CP", "CPD", "CPDR", "CPI", "CPIR",
    "CPL", "DAA", "DEC", "DI", "DJNZ", "EI", "EX", "EXX", "HALT", "IM", "IN", "INC",
    "IND", "INDR", "INI", "INIR", "JP", "JR", "LD", "LDD", "LDDR", "LDI", "LDIR",
    "NEG", "NOP", "OR", "OTDR", "OTIR", "OUT", "OUTD", "OUTI", "POP", "PUSH", "RES",
    "RET", "RETI", "RETN", "RL", "RLA", "RLC", "RLCA", "RLD", "RR", "RRA", "RRC",
    "RRCA", "RRD", "RST", "SBC", "SCF", "SET", "SLA", "SRA", "SRL", "SUB", "XOR",
    # Directives / pseudo-ops
    "ALIGN", "ASSERT", "BLOCK", "BYTE", "DB", "DD", "DEFARRAY", "DEFB", "DEFINE",
    "DEFL", "DEFM", "DEPHASE", "DEFS", "DEFW", "DEVICE", "DISPLAY", "DM", "DS",
    "DUP", "DW", "DWORD", "DZ", "EDUP", "ELSE", "END", "ENDI", "ENDIF", "ENDLUA",
    "ENDM", "ENDMODULE", "ENDS", "ENT", "EQU", "EXPORT", "EXTERN", "FPOS", "GLOBAL",
    "IF", "IFDEF", "IFNDEF", "INCBIN", "INCLUDE", "INSERT", "LUA", "MACRO", "MODULE",
    "OPT", "ORG", "OUTEND", "OUTPUT", "PAGE", "PHASE", "PUBLIC", "REPT", "SAVEBIN",
    "SAVETAP", "SETBP", "SHELLEXEC", "SLDOPT", "SLOT", "STRUCT", "TEXT", "UNDEF",
    "UNDEFINE", "WORD",
}

# Resident symbol prefixes allowed in overlay/trampoline management without violating cross-overlay rules
RESIDENT_OVL_INFRA_PREFIXES = (
    "overlay_",
    "ovl_stack",
    "ovl_window_",
    "ovl_current",
    "ovl_load",
    "ovl_dispatch",
    "ovl_to_dat",
)

# Fixed symbol addresses required in main.sym for M1+
FIXED_MAIN_SYMBOLS = {
    "resident_start": RESIDENT_BASE,
    "bss_start": BSS_BASE,
    "z80_state": Z80_STATE_BASE,
    "stack_bottom": STACK_BOTTOM,
    "stack_top": STACK_TOP,
    "cpm_char_shadow": CPM_CHAR_SHADOW_BASE,
    "cpm_color_shadow": CPM_COLOR_SHADOW_BASE,
    "map_base": MAP_BASE,
    "fcb_dat": FCB_DAT_ADDR,
    "fcb_save": FCB_SAVE_ADDR,
    "fcb_tmp": FCB_TMP_ADDR,
    "cpm_dma_buf": CPM_DMA_BUF_BASE,
}

# Optional fixed symbols checked whenever defined in main.sym
OPTIONAL_FIXED_SYMBOLS = {
    "stack_canary": STACK_CANARY_ADDR,
}

MILESTONE_CHOICES = ("m0", "m1", "m2", "m3", "m4", "m5", "all")


def parse_sym_file(sym_path: Path) -> dict[str, int]:
    """Parse sjasmplus --sym output (`NAME: EQU 0xHHHHHHHH`)."""
    symbols: dict[str, int] = {}
    for line_no, raw in enumerate(
        sym_path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1
    ):
        line = raw.strip()
        if not line:
            continue
        match = SYM_LINE_RE.match(line)
        if match:
            symbols[match.group(1)] = int(match.group(2), 16)
        elif not line.startswith(";"):
            raise ValueError(f"{sym_path.name}:{line_no}: unrecognized symbol line {line!r}")
    return symbols


def strip_z80_comments_and_strings(text: str, mask_strings: bool = True) -> str:
    """Remove ; and // comments, /* ... */ block comments, and optionally quoted literals while preserving AF' and newlines."""
    out: list[str] = []
    i = 0
    n = len(text)
    in_block = False
    in_line = False
    in_double = False
    in_single = False
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                i += 2
                continue
            out.append("\n" if ch == "\n" else " ")
            i += 1
        elif in_line:
            if ch == "\n":
                in_line = False
                out.append("\n")
            i += 1
        elif in_double:
            if ch == "\\" and i + 1 < n:
                if not mask_strings:
                    out.append(ch)
                    out.append(text[i + 1])
                i += 2
                continue
            if ch == '"':
                in_double = False
                if not mask_strings:
                    out.append(ch)
            elif ch == "\n":
                in_double = False
                out.append("\n")
            elif not mask_strings:
                out.append(ch)
            i += 1
        elif in_single:
            if ch == "\\" and i + 1 < n:
                if not mask_strings:
                    out.append(ch)
                    out.append(text[i + 1])
                i += 2
                continue
            if ch == "'":
                in_single = False
                if not mask_strings:
                    out.append(ch)
            elif ch == "\n":
                in_single = False
                out.append("\n")
            elif not mask_strings:
                out.append(ch)
            i += 1
        else:
            if ch == "/" and nxt == "*":
                in_block = True
                i += 2
            elif ch == ";" or (ch == "/" and nxt == "/"):
                in_line = True
                i += 1
            elif ch == '"':
                in_double = True
                out.append(ch if not mask_strings else " ")
                i += 1
            elif ch == "'":
                # Keep Z80 AF' shadow register apostrophe intact; only open single-quoted
                # char/string literal when preceded by delimiter and closed on the same line.
                prev_is_ident = i > 0 and (text[i - 1].isalnum() or text[i - 1] in "_@.")
                eol = text.find("\n", i + 1)
                line_end = n if eol == -1 else eol
                has_close = False
                if not prev_is_ident:
                    k = i + 1
                    while k < line_end:
                        if text[k] == "\\" and k + 1 < line_end:
                            k += 2
                            continue
                        if text[k] == "'":
                            has_close = True
                            break
                        k += 1
                if has_close:
                    in_single = True
                    out.append(ch if not mask_strings else " ")
                else:
                    out.append(ch)
                i += 1
            else:
                out.append(ch)
                i += 1
    return "".join(out)


def _extract_flow_target(op: str, operand_str: str) -> str | None:
    """Extract base target symbol from CALL/JP/JR/DJNZ operand (strips leading `@` and `+ off`, ignores `(HL)`)."""
    op_up = op.upper()
    s = operand_str.strip()
    if not s:
        return None
    parts = [p.strip() for p in s.split(",", 1)]
    if len(parts) == 2 and op_up in ("CALL", "JP", "JR") and parts[0].upper() in COND_SET:
        target = parts[1]
    else:
        target = parts[0]
    if target.startswith("("):
        return None
    m = re.match(r"^(@?[A-Za-z_][A-Za-z0-9_.]*)(?:\s*[+-].*)?$", target)
    if m:
        return m.group(1).lstrip("@")
    return None


def _overlay_owner_from_path(path: Path) -> str | None:
    stem = path.stem.lower()
    if stem in OVERLAY_NAMES:
        return stem
    for ovl in sorted(OVERLAY_NAMES, key=lambda s: (-len(s), s)):
        if stem.startswith(ovl + "_"):
            return ovl
    return None


def _overlay_owner_from_symbol(sym: str) -> str | None:
    clean = sym.lstrip("@")
    if clean.isupper():
        return None
    low = clean.lower()
    for infra in RESIDENT_OVL_INFRA_PREFIXES:
        if low.startswith(infra):
            return None
    m = OVL_PREFIX_RE.match(low)
    if m:
        return f"ovl_{m.group(1)}"
    return None


def _resolve_include_path(inc_spec: str, current_file: Path, src_dirs: list[Path]) -> Path | None:
    rel = Path(inc_spec)
    candidates = [current_file.parent / rel] + [d / rel for d in src_dirs]
    for cand in candidates:
        if cand.is_file():
            resolved = cand.resolve()
            if any(resolved.is_relative_to(d.resolve()) for d in src_dirs):
                return resolved
    return None


def _collect_include_owners(src_dirs: list[Path]) -> tuple[dict[Path, set[str]], list[str]]:
    """Trace INCLUDE graph from main.asm ('resident') and ovl_*.asm ('ovl_<name>')."""
    owners_by_file: dict[Path, set[str]] = {}
    errors: list[str] = []

    roots: list[tuple[Path, str]] = []
    for sdir in src_dirs:
        if not sdir.exists():
            continue
        for p in sorted(sdir.rglob("*.asm")):
            low_name = p.name.lower()
            if low_name == "main.asm":
                roots.append((p.resolve(), "resident"))
            else:
                ovl = _overlay_owner_from_path(p)
                if ovl is not None and p.stem.lower() == ovl:
                    roots.append((p.resolve(), ovl))

    for root_path, owner in roots:
        stack = [root_path]
        visited: set[Path] = set()
        while stack:
            cur = stack.pop()
            if cur in visited:
                continue
            visited.add(cur)
            owners_by_file.setdefault(cur, set()).add(owner)
            cleaned = strip_z80_comments_and_strings(
                cur.read_text(encoding="utf-8", errors="replace"),
                mask_strings=False,
            )
            for line in cleaned.splitlines():
                m_inc = INCLUDE_RE.match(line)
                if not m_inc:
                    continue
                target = _resolve_include_path(m_inc.group(1), cur, src_dirs)
                if target is not None and target not in visited:
                    stack.append(target)

    for fpath, owners in sorted(owners_by_file.items()):
        if fpath.suffix.lower() in (".asm", ".z80") and len(owners) > 1:
            rel = fpath.relative_to(ROOT) if fpath.is_relative_to(ROOT) else fpath
            owner_list = ", ".join(sorted(owners))
            errors.append(
                f"{rel}: included by multiple owners ({owner_list}); move shared code to resident or macros/constants to .inc"
            )
    return owners_by_file, errors


def validate_moria8_dat(dat_path: Path, require_all_slots: bool = False) -> list[str]:
    """Validate MORIA8.DAT 'M8CP' 2-record TOC header and record-aligned extents."""
    errors: list[str] = []
    if not dat_path.exists():
        return [f"missing {dat_path}"]
    data = dat_path.read_bytes()
    if len(data) < DAT_HEADER_BYTES:
        return [f"{dat_path.name}: size {len(data)} B < 256 B 2-record header"]
    if len(data) % CPM_RECORD_SIZE != 0:
        errors.append(
            f"{dat_path.name}: file size {len(data)} B is not a multiple of {CPM_RECORD_SIZE} B CP/M record"
        )
    if data[0:4] != DAT_MAGIC:
        errors.append(f"{dat_path.name}: invalid magic {data[0:4]!r}, expected {DAT_MAGIC!r}")
        return errors
    version = data[4]
    if version != DAT_VERSION:
        errors.append(f"{dat_path.name}: unsupported version {version}, expected {DAT_VERSION}")
    entry_count = data[5]
    if entry_count < DAT_MIN_RO_SLOTS or entry_count > DAT_MAX_ENTRIES:
        errors.append(
            f"{dat_path.name}: invalid entry_count {entry_count} (expected {DAT_MIN_RO_SLOTS}..{DAT_MAX_ENTRIES})"
        )
        return errors
    if require_all_slots and entry_count < DAT_REQUIRED_SLOTS:
        errors.append(
            f"{dat_path.name}: entry_count {entry_count} < required {DAT_REQUIRED_SLOTS} slots for full build"
        )

    total_recs = len(data) // CPM_RECORD_SIZE
    seen_spans: list[tuple[int, int, int]] = []
    for idx in range(DAT_MAX_ENTRIES):
        start_rec, rec_count, byte_len = struct.unpack_from("<HHH", data, 6 + idx * 6)
        if idx >= entry_count:
            if (start_rec, rec_count, byte_len) != (0, 0, 0):
                errors.append(
                    f"{dat_path.name}: unused TOC slot {idx} not zeroed ({start_rec}, {rec_count}, {byte_len})"
                )
            continue
        if byte_len == 0:
            if start_rec != 0 or rec_count != 0:
                errors.append(
                    f"{dat_path.name}: TOC slot {idx} has byte_len=0 with non-zero start_rec={start_rec}/rec_count={rec_count}"
                )
                continue
            if idx in DAT_RO_REQUIRED_SLOTS:
                errors.append(f"{dat_path.name}: required RO asset TOC slot {idx} is empty")
            elif require_all_slots and idx < DAT_REQUIRED_SLOTS:
                errors.append(f"{dat_path.name}: required TOC slot {idx} is empty")
            continue
        if start_rec < DAT_HEADER_RECORDS:
            errors.append(
                f"{dat_path.name}: TOC slot {idx} start_rec={start_rec} overlaps 2-record header"
            )
        if rec_count == 0:
            errors.append(
                f"{dat_path.name}: TOC slot {idx} has rec_count=0 with byte_len={byte_len}"
            )
            continue
        if rec_count > DAT_MAX_REC_COUNT:
            errors.append(
                f"{dat_path.name}: TOC slot {idx} rec_count={rec_count} exceeds {DAT_MAX_REC_COUNT} u8 TOC cache limit"
            )
        if start_rec + rec_count > total_recs:
            errors.append(
                f"{dat_path.name}: TOC slot {idx} ({start_rec}+{rec_count}) exceeds file records ({total_recs})"
            )
        expected_recs = (byte_len + CPM_RECORD_SIZE - 1) // CPM_RECORD_SIZE
        if rec_count != expected_recs:
            errors.append(
                f"{dat_path.name}: TOC slot {idx} rec_count={rec_count} mismatches byte_len={byte_len} (expected {expected_recs})"
            )
        if idx in OVERLAY_SLOT_MAP and (rec_count > OVL_MAX_RECORDS or byte_len > OVL_WINDOW_SIZE):
            errors.append(
                f"{dat_path.name}: overlay TOC slot {idx} ({OVERLAY_SLOT_MAP[idx]}) uses {rec_count} recs / {byte_len} B > {OVL_MAX_RECORDS} recs / {OVL_WINDOW_SIZE} B"
            )
        start_byte = start_rec * CPM_RECORD_SIZE
        pad_start = start_byte + byte_len
        pad_end = start_byte + rec_count * CPM_RECORD_SIZE
        if pad_end <= len(data) and any(b != 0 for b in data[pad_start:pad_end]):
            errors.append(f"{dat_path.name}: TOC slot {idx} has non-zero record padding")
        end_rec = start_rec + rec_count
        for prev_idx, p_start, p_end in seen_spans:
            if start_rec < p_end and p_start < end_rec:
                errors.append(
                    f"{dat_path.name}: TOC slot {idx} [{start_rec},{end_rec}) overlaps slot {prev_idx} [{p_start},{p_end})"
                )
        seen_spans.append((idx, start_rec, end_rec))
    return errors


def _lookup_ovl_bound(syms: dict[str, int], ovl_name: str, suffix: str) -> int | None:
    for candidate in (
        f"ovl_{suffix}",
        f"{ovl_name}_{suffix}",
        f"{ovl_name}.ovl_{suffix}",
        f"{ovl_name}.{ovl_name}_{suffix}",
    ):
        if candidate in syms:
            return syms[candidate]
    return None


def _build_overlay_symbol_maps(
    main_syms: dict[str, int],
    ovl_syms: dict[str, dict[str, int]],
) -> tuple[set[str], dict[str, set[str]]]:
    """Build resident symbol set and overlay-owned symbol map."""
    resident_syms = {
        k.lstrip("@")
        for k, v in main_syms.items()
        if RESIDENT_BASE <= v < RESIDENT_LIMIT or BSS_BASE <= v < BDOS_MIN_TOP
    }
    sym_to_overlay: dict[str, set[str]] = {}
    for ovl_name, syms in ovl_syms.items():
        ovl_end = _lookup_ovl_bound(syms, ovl_name, "end") or OVL_WINDOW_LIMIT
        for raw_sym, addr in syms.items():
            sym = raw_sym.lstrip("@")
            if sym.isupper():
                continue
            if OVL_WINDOW_BASE <= addr < ovl_end and sym not in resident_syms:
                sym_to_overlay.setdefault(sym, set()).add(ovl_name)
            mod_owner = _overlay_owner_from_symbol(sym)
            if mod_owner == ovl_name and "." in sym and OVL_WINDOW_BASE <= addr < ovl_end:
                sym_to_overlay.setdefault(sym, set()).add(ovl_name)
    return resident_syms, sym_to_overlay


def _check_flow_stmt(
    location: str,
    stmt: str,
    active_ovl: str | None,
    in_tramp: bool,
    cur_label: str,
    resident_syms: set[str],
    sym_to_overlay: dict[str, set[str]],
    errors: list[str],
    target_addr: int | None = None,
    active_ovl_end: int = OVL_WINDOW_LIMIT,
) -> None:
    """Validate one CALL/JP/JR/DJNZ statement against cross-overlay and non-trampoline rules."""
    m_flow = Z80_CTRL_FLOW_RE.match(stmt)
    if not m_flow:
        return
    target = _extract_flow_target(m_flow.group(1), m_flow.group(2))
    if target is not None and target.startswith("."):
        return

    target_ovl_by_name = _overlay_owner_from_symbol(target) if target else None
    target_ovls_by_sym = sym_to_overlay.get(target, set()) if target else set()
    if target and active_ovl and "." not in target:
        dotted = f"{active_ovl}.{target}"
        if dotted in sym_to_overlay:
            target_ovls_by_sym = sym_to_overlay[dotted]

    if active_ovl is not None:
        if target_ovl_by_name is not None and target_ovl_by_name != active_ovl:
            errors.append(
                f"{location}: cross-overlay call/jump '{stmt}' from {active_ovl} to {target_ovl_by_name} (must use resident tramp_*)"
            )
        elif target_ovls_by_sym and active_ovl not in target_ovls_by_sym:
            others = ", ".join(sorted(target_ovls_by_sym))
            errors.append(
                f"{location}: cross-overlay call/jump '{stmt}' from {active_ovl} to symbol owned by {others}"
            )
        elif target_addr is not None and active_ovl_end <= target_addr < OVL_WINDOW_LIMIT:
            errors.append(
                f"{location}: out-of-bounds overlay call/jump '{stmt}' to 0x{target_addr:04X} >= ovl_end 0x{active_ovl_end:04X}"
            )
    elif not in_tramp:
        if target_ovl_by_name is not None:
            errors.append(
                f"{location}: direct call/jump '{stmt}' from non-trampoline resident '{cur_label}' to {target}"
            )
        elif target and target_ovls_by_sym and target not in resident_syms:
            others = ", ".join(sorted(target_ovls_by_sym))
            errors.append(
                f"{location}: direct call/jump '{stmt}' from non-trampoline resident '{cur_label}' to overlay symbol ({others})"
            )
        elif target_addr is not None and OVL_WINDOW_BASE <= target_addr < OVL_WINDOW_LIMIT:
            errors.append(
                f"{location}: direct call/jump '{stmt}' from non-trampoline resident '{cur_label}' to overlay address 0x{target_addr:04X}"
            )


def _scan_cleaned_line_statements(
    raw_line: str,
    cur_label: str,
    cur_module_ovl: str | None,
) -> tuple[str, str | None, list[tuple[str, str]]]:
    """Scan labels/MODULE/statements on one stripped assembly source line."""
    starts_col0 = len(raw_line) > 0 and not raw_line[0].isspace()
    line = raw_line.strip()
    if not line:
        return cur_label, cur_module_ovl, []
    m_mod = MODULE_START_RE.match(line)
    if m_mod:
        mod_low = m_mod.group(1).lower()
        return cur_label, (mod_low if mod_low in OVERLAY_NAMES else None), []
    if MODULE_END_RE.match(line):
        return cur_label, None, []

    stmts: list[tuple[str, str]] = []
    pos = 0
    while pos < len(line):
        rem = line[pos:].lstrip()
        if not rem:
            break
        m_lbl = LABEL_DEF_RE.match(rem)
        if m_lbl:
            lbl = m_lbl.group(1).lstrip("@")
            lbl_up = lbl.upper()
            if lbl_up not in Z80_RESERVED_WORDS and not lbl_up.startswith("ASSERT"):
                if not lbl.startswith("."):
                    cur_label = lbl
                pos = len(line) - len(rem) + m_lbl.end()
                continue
        if pos == 0 and starts_col0:
            m_solo = re.match(r"^(@?[A-Za-z_][A-Za-z0-9_.]*)$", rem)
            if m_solo:
                tok = m_solo.group(1).lstrip("@")
                tok_up = tok.upper()
                if tok_up not in Z80_RESERVED_WORDS and not tok_up.startswith("ASSERT"):
                    if not tok.startswith("."):
                        cur_label = tok
                    break
            m_col0 = re.match(r"^(@?[A-Za-z_][A-Za-z0-9_.]*)\s+(.+)$", rem)
            if m_col0:
                tok_raw = m_col0.group(1)
                tok = tok_raw.lstrip("@")
                tok_up = tok.upper()
                rest = m_col0.group(2).lstrip()
                if tok_up not in Z80_RESERVED_WORDS and not tok_up.startswith("ASSERT"):
                    if rest.upper().startswith(("EQU", "DEFL")) or rest.startswith("="):
                        break
                    if not tok.startswith("."):
                        cur_label = tok
                    pos = len(line) - len(rem) + len(tok_raw)
                    continue

        colon_idx = rem.find(":")
        if colon_idx == -1:
            stmt = rem.strip()
            pos = len(line)
        else:
            stmt = rem[:colon_idx].strip()
            pos = len(line) - len(rem) + colon_idx + 1
        if stmt:
            stmts.append((stmt, cur_label))
    return cur_label, cur_module_ovl, stmts


def validate_cross_overlay_sources(
    src_dirs: list[Path],
    main_syms: dict[str, int],
    ovl_syms: dict[str, dict[str, int]],
) -> list[str]:
    """Audit Z80 assembly sources and INCLUDE graphs for cross-overlay direct calls."""
    errors: list[str] = []

    owners_by_file, inc_errors = _collect_include_owners(src_dirs)
    errors.extend(inc_errors)
    resident_syms, sym_to_overlay = _build_overlay_symbol_maps(main_syms, ovl_syms)

    for src_dir in src_dirs:
        if not src_dir.exists():
            continue
        asm_files = sorted(
            p for p in src_dir.rglob("*")
            if p.is_file() and p.suffix.lower() in (".asm", ".z80", ".inc")
        )
        for path in asm_files:
            rel = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
            owners = owners_by_file.get(path.resolve(), set())
            if len(owners) == 1:
                sole = next(iter(owners))
                file_ovl = None if sole == "resident" else sole
            elif len(owners) > 1:
                file_ovl = None
            else:
                file_ovl = _overlay_owner_from_path(path)

            is_tramp_file = path.name.lower() == "trampolines.asm"
            cleaned = strip_z80_comments_and_strings(
                path.read_text(encoding="utf-8", errors="replace")
            )
            cur_module_ovl: str | None = None
            cur_label = ""
            for line_no, raw_line in enumerate(cleaned.splitlines(), start=1):
                cur_label, cur_module_ovl, stmts = _scan_cleaned_line_statements(
                    raw_line, cur_label, cur_module_ovl
                )
                active_ovl = cur_module_ovl or file_ovl
                for stmt, stmt_label in stmts:
                    in_tramp = is_tramp_file or stmt_label.lower().startswith(
                        ("tramp_", "overlay_dispatch", "ovl_dispatch", "overlay_trampoline")
                    )
                    _check_flow_stmt(
                        f"{rel}:{line_no}",
                        stmt,
                        active_ovl,
                        in_tramp,
                        stmt_label,
                        resident_syms,
                        sym_to_overlay,
                        errors,
                    )
    return errors


_UNPREFIXED_3B: frozenset[int] = CALL_JP_3BYTE_OPCODES | {
    0x01, 0x11, 0x21, 0x31, 0x22, 0x2A, 0x32, 0x3A,
}
_UNPREFIXED_2B: frozenset[int] = frozenset({
    0x06, 0x0E, 0x10, 0x16, 0x18, 0x1E, 0x20, 0x26,
    0x28, 0x2E, 0x30, 0x36, 0x38, 0x3E, 0xC6, 0xCE,
    0xD3, 0xD6, 0xDB, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE,
})
_ED_4B: frozenset[int] = frozenset({0x43, 0x4B, 0x53, 0x5B, 0x63, 0x6B, 0x73, 0x7B})
_DD_FD_4B: frozenset[int] = frozenset({0x21, 0x22, 0x2A, 0x36, 0xCB})
_DD_FD_3B: frozenset[int] = frozenset({
    0x34, 0x35, 0x46, 0x4E, 0x56, 0x5E, 0x66, 0x6E,
    0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x77, 0x7E,
    0x86, 0x8E, 0x96, 0x9E, 0xA6, 0xAE, 0xB6, 0xBE,
})


def _z80_insn_len(buf: list[int], off: int) -> int | None:
    """Return Z80 instruction byte length at buf[off], or None if incomplete/invalid."""
    if off >= len(buf):
        return None
    op = buf[off]
    if op == 0xCB:
        length = 2
    elif op == 0xED:
        if off + 1 >= len(buf):
            return None
        length = 4 if buf[off + 1] in _ED_4B else 2
    elif op in (0xDD, 0xFD):
        if off + 1 >= len(buf):
            return None
        op2 = buf[off + 1]
        if op2 in _DD_FD_4B:
            length = 4
        elif op2 in _DD_FD_3B:
            length = 3
        elif op2 in (0xCB, 0xDD, 0xED, 0xFD):
            return None
        elif op2 in _UNPREFIXED_3B:
            length = 4
        elif op2 in _UNPREFIXED_2B:
            length = 3
        else:
            length = 2
    elif op in _UNPREFIXED_3B:
        length = 3
    elif op in _UNPREFIXED_2B:
        length = 2
    else:
        length = 1
    return length if off + length <= len(buf) else None


def _decode_lst_target_at(pc: int, emitted: list[int], off: int | None, op: str) -> int | None:
    if off is None:
        return None
    op_up = op.upper()
    if op_up in ("CALL", "JP") and off + 3 <= len(emitted) and emitted[off] in CALL_JP_3BYTE_OPCODES:
        return emitted[off + 1] | (emitted[off + 2] << 8)
    if op_up in ("JR", "DJNZ") and off + 2 <= len(emitted) and emitted[off] in JR_DJNZ_2BYTE_OPCODES:
        raw_disp = emitted[off + 1]
        disp = raw_disp - 256 if raw_disp >= 128 else raw_disp
        return (pc + off + 2 + disp) & 0xFFFF
    return None


def validate_listing_files(
    lst_dir: Path,
    main_syms: dict[str, int],
    ovl_syms: dict[str, dict[str, int]],
) -> list[str]:
    """Audit sjasmplus .lst files for cross-overlay or non-trampoline overlay calls/jumps."""
    errors: list[str] = []
    resident_syms, sym_to_overlay = _build_overlay_symbol_maps(main_syms, ovl_syms)

    lst_jobs: list[tuple[Path, str | None]] = []
    main_lst = lst_dir / "main.lst"
    if main_lst.is_file():
        lst_jobs.append((main_lst, None))
    for ovl_name in OVERLAY_NAMES:
        olst = lst_dir / f"{ovl_name}.lst"
        if olst.is_file():
            lst_jobs.append((olst, ovl_name))

    for lst_path, owner_ovl in lst_jobs:
        ovl_end = (
            _lookup_ovl_bound(ovl_syms.get(owner_ovl, {}), owner_ovl, "end") or OVL_WINDOW_LIMIT
            if owner_ovl
            else OVL_WINDOW_LIMIT
        )
        file_stack: list[list[str]] = [[lst_path.name.lower(), ""]]
        cur_module_ovl: str | None = None
        pending: dict[str, object] | None = None
        oob_err_count = 0

        def _flush_pending() -> None:
            nonlocal pending
            if pending is None:
                return
            p_line = int(pending["line_no"])  # type: ignore[arg-type]
            p_pc = int(pending["pc"])  # type: ignore[arg-type]
            p_emitted: list[int] = pending["emitted"]  # type: ignore[assignment]
            p_file = str(pending["cur_file"])
            p_mod_ovl: str | None = pending["cur_module_ovl"]  # type: ignore[assignment]
            p_stmts: list[tuple[str, str]] = pending["stmts"]  # type: ignore[assignment]
            pending = None

            if not p_stmts:
                return
            stmt_offsets: list[int | None]
            if len(p_stmts) == 1:
                stmt_offsets = [0 if p_emitted else None]
            else:
                walked: list[int | None] = []
                off = 0
                ok = True
                for _stmt, _lbl in p_stmts:
                    ilen = _z80_insn_len(p_emitted, off)
                    if ilen is None:
                        ok = False
                        break
                    walked.append(off)
                    off += ilen
                stmt_offsets = walked if (ok and off == len(p_emitted)) else [None] * len(p_stmts)

            is_tramp_file = p_file == "trampolines.asm"
            active_ovl = p_mod_ovl or owner_ovl
            for (stmt, stmt_label), stmt_off in zip(p_stmts, stmt_offsets):
                m_flow = Z80_CTRL_FLOW_RE.match(stmt)
                if not m_flow:
                    continue
                target_addr = _decode_lst_target_at(p_pc, p_emitted, stmt_off, m_flow.group(1))
                in_tramp = is_tramp_file or stmt_label.lower().startswith(
                    ("tramp_", "overlay_dispatch", "ovl_dispatch", "overlay_trampoline")
                )
                _check_flow_stmt(
                    f"{lst_path.name}:{p_line} ({p_file})",
                    stmt,
                    active_ovl,
                    in_tramp,
                    stmt_label,
                    resident_syms,
                    sym_to_overlay,
                    errors,
                    target_addr=target_addr,
                    active_ovl_end=ovl_end,
                )

        for lst_line_no, raw_line in enumerate(
            lst_path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1
        ):
            m_open = LST_FILE_OPEN_RE.match(raw_line)
            if m_open:
                _flush_pending()
                fname = Path(m_open.group(1)).name.lower()
                file_stack.append([fname, ""])
                continue
            m_close = LST_FILE_CLOSE_RE.match(raw_line)
            if m_close:
                _flush_pending()
                if len(file_stack) > 1:
                    file_stack.pop()
                continue

            m_lst = LST_LINE_RE.match(raw_line)
            if not m_lst:
                continue
            pc = int(m_lst.group(1), 16)
            body = m_lst.group(2)
            if not body or body.startswith("~"):
                _flush_pending()
                continue

            bytes_col = body[:12].strip()
            src_raw = body[13:] if len(body) > 13 else ""
            emitted: list[int] = []
            if bytes_col and LST_HEX_BYTES_RE.match(bytes_col):
                emitted = [int(tok, 16) for tok in bytes_col.split()]

            cur_file = file_stack[-1][0]
            if oob_err_count < 3:
                if owner_ovl is not None:
                    if emitted and (pc < OVL_WINDOW_BASE or pc + len(emitted) > ovl_end):
                        errors.append(
                            f"{lst_path.name}:{lst_line_no} ({cur_file}): overlay emitted {len(emitted)} B at 0x{pc:04X} outside [0x{OVL_WINDOW_BASE:04X}, 0x{ovl_end:04X})"
                        )
                        oob_err_count += 1
                    elif (0 < pc < OVL_WINDOW_BASE or pc > ovl_end) and cur_file != "main_exp.inc":
                        errors.append(
                            f"{lst_path.name}:{lst_line_no} ({cur_file}): overlay PC 0x{pc:04X} outside [0x{OVL_WINDOW_BASE:04X}, 0x{ovl_end:04X}]"
                        )
                        oob_err_count += 1
                elif emitted and pc < RESIDENT_BASE:
                    errors.append(
                        f"{lst_path.name}:{lst_line_no} ({cur_file}): resident emitted {len(emitted)} B at 0x{pc:04X} below RESIDENT_BASE 0x{RESIDENT_BASE:04X}"
                    )
                    oob_err_count += 1

            if not src_raw.strip():
                if (
                    pending is not None
                    and emitted
                    and pc == int(pending["pc"]) + len(pending["emitted"])  # type: ignore[arg-type]
                ):
                    pending["emitted"].extend(emitted)  # type: ignore[attr-defined]
                else:
                    _flush_pending()
                continue

            _flush_pending()

            cleaned_src = strip_z80_comments_and_strings(src_raw)
            cur_file, cur_label = file_stack[-1]
            # INCLUDE "main_exp.inc" emits EQU symbols only; never flag declaration files.
            if cur_file == "main_exp.inc":
                continue

            cur_label, cur_module_ovl, stmts = _scan_cleaned_line_statements(
                cleaned_src, cur_label, cur_module_ovl
            )
            file_stack[-1][1] = cur_label
            if stmts:
                pending = {
                    "line_no": lst_line_no,
                    "pc": pc,
                    "emitted": emitted,
                    "cur_file": cur_file,
                    "cur_module_ovl": cur_module_ovl,
                    "stmts": stmts,
                }
        _flush_pending()
    return errors


def validate_build(
    build_dir: Path,
    milestone: str = "all",
    src_dirs: list[Path] | None = None,
    dat_path: Path | None = None,
    lst_dir: Path | None = None,
) -> list[str]:
    errors: list[str] = []
    resolved_dat = dat_path or (build_dir / "MORIA8.DAT")
    resolved_lst_dir = lst_dir or build_dir

    if milestone == "m0":
        return validate_moria8_dat(resolved_dat, require_all_slots=False)

    require_all_overlays = milestone in ("m4", "m5", "all")
    if require_all_overlays:
        required_overlays = OVERLAY_NAMES
    elif milestone == "m3":
        required_overlays = M3_REQUIRED_OVERLAYS
    elif milestone == "m2":
        required_overlays = M2_REQUIRED_OVERLAYS
    else:
        required_overlays = M1_REQUIRED_OVERLAYS
    require_dat = True

    com_path = build_dir / "MORIA8.COM"
    sym_path = build_dir / "main.sym"
    main_lst_path = resolved_lst_dir / "main.lst"
    if not com_path.exists():
        errors.append(f"missing {com_path}")
    if not main_lst_path.exists():
        errors.append(f"missing {main_lst_path}")
    if not sym_path.exists():
        errors.append(f"missing {sym_path}")
        return errors

    try:
        main_syms = parse_sym_file(sym_path)
    except ValueError as exc:
        return [str(exc)]

    # 1. MORIA8.COM resident binary & symbol checks (0x0100 <= resident_end <= 0x5600)
    if "resident_end" not in main_syms:
        errors.append("main.sym missing required symbol 'resident_end'")
    else:
        res_end = main_syms["resident_end"]
        if not (RESIDENT_BASE < res_end <= RESIDENT_LIMIT):
            errors.append(
                f"resident_end at 0x{res_end:04X} violates [0x{RESIDENT_BASE:04X}, 0x{RESIDENT_LIMIT:04X}]"
            )
        if com_path.exists():
            com_size = len(com_path.read_bytes())
            if com_size == 0:
                errors.append("MORIA8.COM is empty (0 bytes)")
            elif com_size > RESIDENT_MAX_SIZE:
                errors.append(
                    f"MORIA8.COM size {com_size} B exceeds {RESIDENT_MAX_SIZE} B resident limit (0x{RESIDENT_BASE:04X}..0x{RESIDENT_LIMIT - 1:04X})"
                )
            elif RESIDENT_BASE + com_size != res_end:
                errors.append(
                    f"MORIA8.COM size {com_size} B (end 0x{RESIDENT_BASE + com_size:04X}) != resident_end 0x{res_end:04X}"
                )

    # 2. Resident BSS span (0x6A00 <= bss_end <= 0x8C00)
    if "bss_end" not in main_syms:
        errors.append("main.sym missing required symbol 'bss_end'")
    else:
        bss_end = main_syms["bss_end"]
        if not (BSS_BASE <= bss_end <= BSS_LIMIT):
            errors.append(
                f"bss_end at 0x{bss_end:04X} violates BSS span [0x{BSS_BASE:04X}, 0x{BSS_LIMIT:04X}]"
            )

    # 3. Fixed ABI / shadow / map / FCB / DMA addresses
    for sym_name, expected in FIXED_MAIN_SYMBOLS.items():
        if sym_name not in main_syms:
            errors.append(f"main.sym missing required contract symbol '{sym_name}'")
        elif main_syms[sym_name] != expected:
            errors.append(
                f"{sym_name} at 0x{main_syms[sym_name]:04X} != contract 0x{expected:04X}"
            )
    for sym_name, expected in OPTIONAL_FIXED_SYMBOLS.items():
        if sym_name in main_syms and main_syms[sym_name] != expected:
            errors.append(
                f"{sym_name} at 0x{main_syms[sym_name]:04X} != contract 0x{expected:04X}"
            )

    # Verify resident tramp_* stubs live strictly inside resident [0x0100, resident_end)
    res_ceiling = min(main_syms.get("resident_end", RESIDENT_LIMIT), RESIDENT_LIMIT)
    for sym_name, addr in main_syms.items():
        if sym_name.lstrip("@").startswith("tramp_"):
            if not (RESIDENT_BASE <= addr < res_ceiling):
                errors.append(
                    f"trampoline '{sym_name}' at 0x{addr:04X} must reside in [0x{RESIDENT_BASE:04X}, 0x{res_ceiling:04X})"
                )

    # 4. Built overlay .ovl binaries, .sym files, & .lst files
    ovl_syms_map: dict[str, dict[str, int]] = {}
    built_ovl_bytes: dict[str, bytes] = {}
    for ovl_name in OVERLAY_NAMES:
        ovl_bin = build_dir / f"{ovl_name}.ovl"
        ovl_sym = build_dir / f"{ovl_name}.sym"
        ovl_lst = resolved_lst_dir / f"{ovl_name}.lst"
        is_required = ovl_name in required_overlays
        any_present = ovl_bin.exists() or ovl_sym.exists() or ovl_lst.exists()
        if not any_present:
            if is_required:
                errors.append(
                    f"missing required overlay artifacts for {ovl_name} ({ovl_bin.name}, {ovl_sym.name}, {ovl_lst.name})"
                )
            continue
        if not ovl_bin.exists():
            errors.append(f"missing overlay binary {ovl_bin.name}")
        if not ovl_lst.exists():
            errors.append(f"missing overlay listing {ovl_lst.name}")
        if not ovl_sym.exists():
            errors.append(f"missing overlay symbol file {ovl_sym.name}")
            continue
        if not ovl_bin.exists():
            continue

        try:
            osyms = parse_sym_file(ovl_sym)
        except ValueError as exc:
            errors.append(str(exc))
            continue
        ovl_syms_map[ovl_name] = osyms

        ovl_start = _lookup_ovl_bound(osyms, ovl_name, "start")
        ovl_end = _lookup_ovl_bound(osyms, ovl_name, "end")
        if ovl_start is None:
            errors.append(f"{ovl_sym.name}: missing 'ovl_start' (or '{ovl_name}_start') symbol")
        elif ovl_start != OVL_WINDOW_BASE:
            errors.append(
                f"{ovl_sym.name}: start at 0x{ovl_start:04X} != OVL_WINDOW_BASE 0x{OVL_WINDOW_BASE:04X}"
            )
        if ovl_end is None:
            errors.append(f"{ovl_sym.name}: missing 'ovl_end' (or '{ovl_name}_end') symbol")
        else:
            if not (OVL_WINDOW_BASE < ovl_end <= OVL_WINDOW_LIMIT):
                errors.append(
                    f"{ovl_sym.name}: ovl_end at 0x{ovl_end:04X} exceeds 0x{OVL_WINDOW_LIMIT:04X} ({OVL_WINDOW_SIZE} B limit)"
                )

        ovl_bytes = ovl_bin.read_bytes()
        built_ovl_bytes[ovl_name] = ovl_bytes
        ovl_len = len(ovl_bytes)
        if ovl_len == 0:
            errors.append(f"{ovl_bin.name}: empty overlay binary (0 bytes)")
        elif ovl_len > OVL_WINDOW_SIZE:
            errors.append(
                f"{ovl_bin.name}: size {ovl_len} B exceeds {OVL_WINDOW_SIZE} B ({OVL_MAX_RECORDS} x 128 B records)"
            )
        elif ovl_end is not None and OVL_WINDOW_BASE + ovl_len != ovl_end:
            errors.append(
                f"{ovl_bin.name}: size {ovl_len} B (end 0x{OVL_WINDOW_BASE + ovl_len:04X}) != ovl_end 0x{ovl_end:04X}"
            )

        # Symbol-level cross-overlay contamination check: ovl_<B>_* or ovl_<B>.* inside ovl_<A>.sym
        # Ignore resident/BSS symbols imported identically via main_exp.inc.
        for sym_name, addr in osyms.items():
            if (
                sym_name in main_syms
                and main_syms[sym_name] == addr
                and not (OVL_WINDOW_BASE <= addr < OVL_WINDOW_LIMIT)
            ):
                continue
            owner = _overlay_owner_from_symbol(sym_name)
            if owner is not None and owner != ovl_name:
                errors.append(
                    f"{ovl_sym.name}: cross-overlay symbol '{sym_name}' (0x{addr:04X}) owned by {owner}"
                )

    # 5. Cross-overlay Z80 source & listing audit
    if src_dirs is None:
        src_dirs = [CPM_SRC_DIR, CORE_Z80_DIR]
    errors.extend(validate_cross_overlay_sources(src_dirs, main_syms, ovl_syms_map))
    errors.extend(validate_listing_files(resolved_lst_dir, main_syms, ovl_syms_map))

    # 6. MORIA8.DAT 'M8CP' TOC check + byte-for-byte overlay slot parity
    if resolved_dat.exists() or require_dat:
        dat_errors = validate_moria8_dat(resolved_dat, require_all_slots=require_all_overlays)
        errors.extend(dat_errors)
        if not dat_errors and resolved_dat.exists():
            dat_bytes = resolved_dat.read_bytes()
            entry_count = dat_bytes[5]
            for slot_id, ovl_name in OVERLAY_SLOT_MAP.items():
                is_required = ovl_name in required_overlays
                if slot_id >= entry_count:
                    if is_required or ovl_name in built_ovl_bytes:
                        errors.append(
                            f"{resolved_dat.name}: overlay slot {slot_id} ({ovl_name}) missing from entry_count={entry_count}"
                        )
                    continue
                start_rec, rec_count, byte_len = struct.unpack_from("<HHH", dat_bytes, 6 + slot_id * 6)
                if rec_count == 0 or byte_len == 0:
                    if is_required:
                        errors.append(
                            f"{resolved_dat.name}: required overlay TOC slot {slot_id} ({ovl_name}) is empty"
                        )
                    elif ovl_name in built_ovl_bytes:
                        errors.append(
                            f"{resolved_dat.name}: built {ovl_name}.ovl is absent from TOC slot {slot_id}"
                        )
                    continue
                if ovl_name in built_ovl_bytes:
                    start_off = start_rec * CPM_RECORD_SIZE
                    dat_payload = dat_bytes[start_off : start_off + byte_len]
                    if dat_payload != built_ovl_bytes[ovl_name]:
                        errors.append(
                            f"{resolved_dat.name}: TOC slot {slot_id} ({ovl_name}) payload ({len(dat_payload)} B) differs from {ovl_name}.ovl ({len(built_ovl_bytes[ovl_name])} B)"
                        )
            for slot_id, asset_name in DAT_RO_SLOT_FILES.items():
                asset_path = build_dir / asset_name
                if slot_id >= entry_count or not asset_path.is_file():
                    continue
                start_rec, rec_count, byte_len = struct.unpack_from("<HHH", dat_bytes, 6 + slot_id * 6)
                start_off = start_rec * CPM_RECORD_SIZE
                dat_payload = dat_bytes[start_off : start_off + byte_len]
                expected_asset = asset_path.read_bytes()
                if dat_payload != expected_asset:
                    errors.append(
                        f"{resolved_dat.name}: RO slot {slot_id} ({asset_name}) payload ({len(dat_payload)} B) differs from {asset_path.name} ({len(expected_asset)} B)"
                    )
                elif asset_name == "license.txt" and (ROOT / "data" / "LICENSE").is_file():
                    lic_crlf = (ROOT / "data" / "LICENSE").read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
                    if dat_payload != lic_crlf:
                        errors.append(f"{resolved_dat.name}: RO slot {slot_id} (license.txt) differs from CRLF data/LICENSE")
                elif asset_name == "srcoffr.txt" and (ROOT / "data" / "SOURCE-OFFER").is_file():
                    src_crlf = (ROOT / "data" / "SOURCE-OFFER").read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
                    if dat_payload != src_crlf:
                        errors.append(f"{resolved_dat.name}: RO slot {slot_id} (srcoffr.txt) differs from CRLF data/SOURCE-OFFER")

    return errors


def _write_synthetic_dat(
    path: Path,
    payloads: dict[int, bytes],
    entry_count: int = DAT_REQUIRED_SLOTS,
    magic: bytes = DAT_MAGIC,
    override_entries: dict[int, tuple[int, int, int]] | None = None,
) -> None:
    """Emit a synthetic 'M8CP' MORIA8.DAT file for selftests."""
    records: list[bytes] = [b"", b""]  # 2 header records reserved
    toc: list[tuple[int, int, int]] = [(0, 0, 0)] * DAT_MAX_ENTRIES
    cur_rec = DAT_HEADER_RECORDS
    for idx in range(entry_count):
        if idx in payloads:
            raw = payloads[idx]
            rec_cnt = (len(raw) + CPM_RECORD_SIZE - 1) // CPM_RECORD_SIZE if len(raw) > 0 else 1
            padded = raw.ljust(rec_cnt * CPM_RECORD_SIZE, b"\x00")
            for r in range(rec_cnt):
                records.append(padded[r * CPM_RECORD_SIZE : (r + 1) * CPM_RECORD_SIZE])
            toc[idx] = (cur_rec, rec_cnt, len(raw))
            cur_rec += rec_cnt
    if override_entries:
        for idx, vals in override_entries.items():
            toc[idx] = vals
    hdr = bytearray(DAT_HEADER_BYTES)
    hdr[0:4] = magic[:4].ljust(4, b"\x00")
    hdr[4] = DAT_VERSION
    hdr[5] = entry_count
    for idx, (srec, rcnt, blen) in enumerate(toc):
        struct.pack_into("<HHH", hdr, 6 + idx * 6, srec, rcnt, blen)
    records[0] = bytes(hdr[:CPM_RECORD_SIZE])
    records[1] = bytes(hdr[CPM_RECORD_SIZE:])
    path.write_bytes(b"".join(records))


def _create_valid_fixture(bdir: Path, sdir: Path) -> None:
    """Populate a valid synthetic CP/M build + source fixture."""
    for target_dir in (bdir, sdir):
        if target_dir.exists():
            shutil.rmtree(target_dir)
        target_dir.mkdir(parents=True, exist_ok=True)
    res_size = 0x1000
    (bdir / "MORIA8.COM").write_bytes(b"\x00" * res_size)
    (bdir / "main.sym").write_text(
        "\n".join([
            f"resident_start: EQU 0x{RESIDENT_BASE:08X}",
            f"resident_end: EQU 0x{RESIDENT_BASE + res_size:08X}",
            f"overlay_trampoline: EQU 0x{RESIDENT_BASE + 0x080:08X}",
            f"tramp_town_enter: EQU 0x{RESIDENT_BASE + 0x100:08X}",
            f"tramp_items_use: EQU 0x{RESIDENT_BASE + 0x110:08X}",
            f"tramp_items_eff_quaff: EQU 0x{RESIDENT_BASE + 0x120:08X}",
            f"tramp_colonless: EQU 0x{RESIDENT_BASE + 0x130:08X}",
            f"bss_start: EQU 0x{BSS_BASE:08X}",
            f"z80_state: EQU 0x{Z80_STATE_BASE:08X}",
            f"bss_end: EQU 0x{BSS_BASE + 0x0400:08X}",
            f"stack_bottom: EQU 0x{STACK_BOTTOM:08X}",
            f"stack_canary: EQU 0x{STACK_CANARY_ADDR:08X}",
            f"stack_top: EQU 0x{STACK_TOP:08X}",
            f"cpm_char_shadow: EQU 0x{CPM_CHAR_SHADOW_BASE:08X}",
            f"cpm_color_shadow: EQU 0x{CPM_COLOR_SHADOW_BASE:08X}",
            f"map_base: EQU 0x{MAP_BASE:08X}",
            f"fcb_dat: EQU 0x{FCB_DAT_ADDR:08X}",
            f"fcb_save: EQU 0x{FCB_SAVE_ADDR:08X}",
            f"fcb_tmp: EQU 0x{FCB_TMP_ADDR:08X}",
            f"cpm_dma_buf: EQU 0x{CPM_DMA_BUF_BASE:08X}",
        ]) + "\n",
        encoding="utf-8",
    )
    (bdir / "main.lst").write_text(
        "\n".join([
            "# file opened: main.asm",
            " 1    0100                INCLUDE \"trampolines.asm\"",
            "# file opened: trampolines.asm",
            " 1+   0100              OVL_TITLE_VEC EQU OVL_WINDOW_BASE + 0",
            " 2+   0100              tramp_town_enter:",
            " 3+   0100 CD 80 01       CALL overlay_trampoline",
            " 4+   0103 02             DB 2",
            " 5+   0104 00 56          DW OVL_TITLE_VEC",
            "# file closed: trampolines.asm",
            " 2    0200              main_loop:",
            " 3    0200 CD 00 02       CALL tramp_town_enter",
            " 4    0203 C3 00 00       JP 0x0000",
            "# file closed: main.asm",
        ]) + "\n",
        encoding="utf-8",
    )

    dat_payloads: dict[int, bytes] = {}
    for slot_id, ovl_name in OVERLAY_SLOT_MAP.items():
        ovl_len = 0x0200
        blob = bytes([(slot_id + 1) & 0xFF]) * ovl_len
        (bdir / f"{ovl_name}.ovl").write_bytes(blob)
        dat_payloads[slot_id] = blob
        (bdir / f"{ovl_name}.sym").write_text(
            "\n".join([
                f"ovl_start: EQU 0x{OVL_WINDOW_BASE:08X}",
                f"{ovl_name}_entry: EQU 0x{OVL_WINDOW_BASE:08X}",
                f"{ovl_name}_helper: EQU 0x{OVL_WINDOW_BASE + 0x20:08X}",
                f"{ovl_name}.mod_helper: EQU 0x{OVL_WINDOW_BASE + 0x30:08X}",
                f"ovl_end: EQU 0x{OVL_WINDOW_BASE + ovl_len:08X}",
                f"overlay_trampoline: EQU 0x{RESIDENT_BASE + 0x080:08X}",
                f"tramp_town_enter: EQU 0x{RESIDENT_BASE + 0x100:08X}",
            ]) + "\n",
            encoding="utf-8",
        )
        (bdir / f"{ovl_name}.lst").write_text(
            "\n".join([
                f"# file opened: {ovl_name}.asm",
                ' 1    5600                INCLUDE "main_exp.inc"',
                "# file opened: main_exp.inc",
                f" 1+   0000              tramp_town_enter: EQU 0x{RESIDENT_BASE + 0x100:08X}",
                "# file closed: main_exp.inc",
                f" 2    5600 C3 20 56     {ovl_name}_entry: JP {ovl_name}_helper",
                f" 3    5620 CD 00 02     {ovl_name}_helper: CALL tramp_town_enter",
                " 4    5623 C9             RET",
                f"# file closed: {ovl_name}.asm",
            ]) + "\n",
            encoding="utf-8",
        )
    for asset_slot in DAT_RO_REQUIRED_SLOTS:
        dat_payloads[asset_slot] = b"ASSET" * 16
    _write_synthetic_dat(bdir / "MORIA8.DAT", dat_payloads, entry_count=DAT_REQUIRED_SLOTS)

    sdir.mkdir(parents=True, exist_ok=True)
    core_dir = sdir / "core_z80"
    core_dir.mkdir(parents=True, exist_ok=True)
    (sdir / "main.asm").write_text(
        "\n".join([
            '    INCLUDE "trampolines.asm"',
            "main_loop:",
            "    EX AF, AF'",
            "    CALL tramp_town_enter",
            "    RET",
            "tramp_colonless",
            "    LD A, 2",
            "    JP ovl_town_entry",
        ]) + "\n",
        encoding="utf-8",
    )
    (sdir / "trampolines.asm").write_text(
        "\n".join([
            "OVL_TOWN_VEC EQU OVL_WINDOW_BASE + 0",
            "tramp_town_enter:",
            "    CALL overlay_trampoline",
            "    DB 2",
            "    DW OVL_TOWN_VEC",
            "tramp_items_use:",
            "    CALL overlay_trampoline",
            "    DB 7",
            "    DW OVL_WINDOW_BASE + 0",
            "tramp_items_eff_quaff:",
            "    CALL overlay_trampoline",
            "    DB 15",
            "    DW ovl_items_eff_entry",
        ]) + "\n",
        encoding="utf-8",
    )
    (sdir / "ovl_town.asm").write_text(
        "\n".join([
            '    INCLUDE "core_z80/town_impl.asm"',
            '    INCLUDE "main_exp.inc"',
            "    MODULE ovl_town",
            "ovl_town_entry:",
            "    EX AF, AF' : CALL ovl_town_helper",
            "    CALL @ovl_town_helper",
            "    CALL mod_helper",
            "    CALL tramp_items_eff_quaff",
            "    RET",
            "mod_helper:",
            "    RET",
            "    ENDMODULE",
        ]) + "\n",
        encoding="utf-8",
    )
    (core_dir / "town_impl.asm").write_text(
        "\n".join([
            "ovl_town_helper:",
            "    CALL ovl_town.mod_helper + 0",
            "    RET",
        ]) + "\n",
        encoding="utf-8",
    )


def run_selftest() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)

        # 1. Passing fixture (19 overlays + colonless tramp + dotted MODULE + EX AF,AF' + @global + core_z80 INCLUDE)
        ok_b = root / "ok_build"
        ok_s = root / "ok_src"
        ok_b.mkdir()
        _create_valid_fixture(ok_b, ok_s)
        errs = validate_build(ok_b, milestone="all", src_dirs=[ok_s])
        if errs:
            print(f"FAIL: valid fixture rejected: {errs}", file=sys.stderr)
            return 1

        # 2. Milestone M0 & M1 checks (including mandatory RO slots 14..19 and entry_count >= 20)
        m0_b = root / "m0_build"
        m0_b.mkdir()
        if not validate_build(m0_b, milestone="m0", src_dirs=[]):
            print("FAIL: m0 failed to catch missing MORIA8.DAT in --build-dir", file=sys.stderr)
            return 1
        _write_synthetic_dat(
            m0_b / "MORIA8.DAT",
            {s: b"R" * 128 for s in DAT_RO_REQUIRED_SLOTS},
            entry_count=DAT_MIN_RO_SLOTS,
        )
        if validate_build(m0_b, milestone="m0", src_dirs=[]):
            print("FAIL: valid m0 partial MORIA8.DAT rejected", file=sys.stderr)
            return 1
        # Missing RO slot 19 must fail even under m0
        _write_synthetic_dat(
            m0_b / "MORIA8.DAT",
            {s: b"R" * 128 for s in range(14, 19)},
            entry_count=DAT_MIN_RO_SLOTS,
        )
        if not validate_build(m0_b, milestone="m0", src_dirs=[]):
            print("FAIL: m0 failed to catch empty required RO asset slot 19", file=sys.stderr)
            return 1
        # entry_count < 20 must fail even under m0
        _write_synthetic_dat(
            m0_b / "MORIA8.DAT",
            {s: b"R" * 128 for s in range(14, 19)},
            entry_count=19,
        )
        if not validate_build(m0_b, milestone="m0", src_dirs=[]):
            print("FAIL: m0 failed to catch entry_count < 20", file=sys.stderr)
            return 1
        # byte_len == 0 with rec_count != 0 must fail
        _write_synthetic_dat(
            m0_b / "MORIA8.DAT",
            {s: b"R" * 128 for s in DAT_RO_REQUIRED_SLOTS},
            entry_count=DAT_MIN_RO_SLOTS,
            override_entries={0: (2, 1, 0)},
        )
        if not validate_build(m0_b, milestone="m0", src_dirs=[]):
            print("FAIL: m0 failed to catch byte_len=0 with rec_count=1", file=sys.stderr)
            return 1
        # Corrupt magic must fail under m0
        _write_synthetic_dat(
            m0_b / "MORIA8.DAT",
            {s: b"R" * 128 for s in DAT_RO_REQUIRED_SLOTS},
            entry_count=DAT_MIN_RO_SLOTS,
            magic=b"NOPE",
        )
        if not validate_build(m0_b, milestone="m0", src_dirs=[]):
            print("FAIL: m0 failed to catch corrupt MORIA8.DAT", file=sys.stderr)
            return 1
        # Boundary test: 255 records on non-overlay slot and 40 records on overlay slot must PASS
        _write_synthetic_dat(
            m0_b / "MORIA8.DAT",
            {
                0: b"O" * (OVL_MAX_RECORDS * CPM_RECORD_SIZE),
                14: b"R" * (DAT_MAX_REC_COUNT * CPM_RECORD_SIZE),
                **{s: b"R" * 128 for s in range(15, 20)},
            },
            entry_count=DAT_MIN_RO_SLOTS,
        )
        if validate_build(m0_b, milestone="m0", src_dirs=[]):
            print("FAIL: boundary 40-rec overlay / 255-rec RO MORIA8.DAT rejected", file=sys.stderr)
            return 1
        # rec_count == 256 on non-overlay slot must FAIL (u8 cache overflow guard)
        _write_synthetic_dat(
            m0_b / "MORIA8.DAT",
            {
                14: b"R" * ((DAT_MAX_REC_COUNT + 1) * CPM_RECORD_SIZE),
                **{s: b"R" * 128 for s in range(15, 20)},
            },
            entry_count=DAT_MIN_RO_SLOTS,
        )
        if not validate_build(m0_b, milestone="m0", src_dirs=[]):
            print("FAIL: failed to catch rec_count=256 on non-overlay slot", file=sys.stderr)
            return 1
        # rec_count == 41 on overlay slot must FAIL (5,120 B / 40-record window guard)
        _write_synthetic_dat(
            m0_b / "MORIA8.DAT",
            {
                0: b"O" * ((OVL_MAX_RECORDS + 1) * CPM_RECORD_SIZE),
                **{s: b"R" * 128 for s in DAT_RO_REQUIRED_SLOTS},
            },
            entry_count=DAT_MIN_RO_SLOTS,
        )
        if not validate_build(m0_b, milestone="m0", src_dirs=[]):
            print("FAIL: failed to catch rec_count=41 on overlay slot", file=sys.stderr)
            return 1

        m1_b = root / "m1_build"
        m1_b.mkdir()
        (m1_b / "MORIA8.COM").write_bytes((ok_b / "MORIA8.COM").read_bytes())
        (m1_b / "main.sym").write_text((ok_b / "main.sym").read_text(encoding="utf-8"), encoding="utf-8")
        # Incomplete M1 (missing ovl_title, ovl_legal, .lst, and MORIA8.DAT) must fail
        if not validate_build(m1_b, milestone="m1", src_dirs=[ok_s]):
            print("FAIL: incomplete m1 fixture (missing overlays/lst/DAT) was accepted", file=sys.stderr)
            return 1

        # Complete M1 fixture: MORIA8.COM, main.{sym,lst}, ovl_title.{ovl,sym,lst}, ovl_legal.{ovl,sym,lst}, MORIA8.DAT slots 12..19
        (m1_b / "main.lst").write_text((ok_b / "main.lst").read_text(encoding="utf-8"), encoding="utf-8")
        m1_dat_payloads: dict[int, bytes] = {s: b"ASSET" * 16 for s in DAT_RO_REQUIRED_SLOTS}
        for slot_id, ovl_name in ((12, "ovl_title"), (13, "ovl_legal")):
            ovl_bytes = (ok_b / f"{ovl_name}.ovl").read_bytes()
            (m1_b / f"{ovl_name}.ovl").write_bytes(ovl_bytes)
            (m1_b / f"{ovl_name}.sym").write_text((ok_b / f"{ovl_name}.sym").read_text(encoding="utf-8"), encoding="utf-8")
            (m1_b / f"{ovl_name}.lst").write_text((ok_b / f"{ovl_name}.lst").read_text(encoding="utf-8"), encoding="utf-8")
            m1_dat_payloads[slot_id] = ovl_bytes
        _write_synthetic_dat(m1_b / "MORIA8.DAT", m1_dat_payloads, entry_count=DAT_MIN_RO_SLOTS)
        errs = validate_build(m1_b, milestone="m1", src_dirs=[ok_s])
        if errs:
            print(f"FAIL: valid m1 fixture rejected: {errs}", file=sys.stderr)
            return 1
        if not validate_build(m1_b, milestone="all", src_dirs=[ok_s]):
            print("FAIL: milestone='all' failed to require all 19 overlays and MORIA8.DAT", file=sys.stderr)
            return 1

        # M1 negative checks: missing main.lst, missing ovl_title.lst, empty DAT slot 13, mismatched slot 12
        (m1_b / "main.lst").unlink()
        if not validate_build(m1_b, milestone="m1", src_dirs=[ok_s]):
            print("FAIL: m1 failed to catch missing main.lst", file=sys.stderr)
            return 1
        (m1_b / "main.lst").write_text((ok_b / "main.lst").read_text(encoding="utf-8"), encoding="utf-8")

        (m1_b / "ovl_title.lst").unlink()
        if not validate_build(m1_b, milestone="m1", src_dirs=[ok_s]):
            print("FAIL: m1 failed to catch missing ovl_title.lst", file=sys.stderr)
            return 1
        (m1_b / "ovl_title.lst").write_text((ok_b / "ovl_title.lst").read_text(encoding="utf-8"), encoding="utf-8")

        _write_synthetic_dat(
            m1_b / "MORIA8.DAT",
            {12: m1_dat_payloads[12], **{s: m1_dat_payloads[s] for s in DAT_RO_REQUIRED_SLOTS}},
            entry_count=DAT_MIN_RO_SLOTS,
        )
        if not validate_build(m1_b, milestone="m1", src_dirs=[ok_s]):
            print("FAIL: m1 failed to catch empty ovl_legal slot 13 in MORIA8.DAT", file=sys.stderr)
            return 1

        _write_synthetic_dat(
            m1_b / "MORIA8.DAT",
            {12: b"\xAA" * len(m1_dat_payloads[12]), 13: m1_dat_payloads[13], **{s: m1_dat_payloads[s] for s in DAT_RO_REQUIRED_SLOTS}},
            entry_count=DAT_MIN_RO_SLOTS,
        )
        if not validate_build(m1_b, milestone="m1", src_dirs=[ok_s]):
            print("FAIL: m1 failed to catch mismatched ovl_title slot 12 payload", file=sys.stderr)
            return 1
        # M1 fixture is incomplete for M2 (missing ovl_start/gen/town/home/storage)
        _write_synthetic_dat(m1_b / "MORIA8.DAT", m1_dat_payloads, entry_count=DAT_MIN_RO_SLOTS)
        if not validate_build(m1_b, milestone="m2", src_dirs=[ok_s]):
            print("FAIL: m2 accepted M1-only fixture missing M2 overlays", file=sys.stderr)
            return 1

        # Complete M2 fixture: all 7 M2 overlays + .sym + .lst + MORIA8.DAT slots
        m2_b = root / "m2_build"
        m2_b.mkdir()
        (m2_b / "MORIA8.COM").write_bytes((ok_b / "MORIA8.COM").read_bytes())
        (m2_b / "main.sym").write_text((ok_b / "main.sym").read_text(encoding="utf-8"), encoding="utf-8")
        (m2_b / "main.lst").write_text((ok_b / "main.lst").read_text(encoding="utf-8"), encoding="utf-8")
        m2_dat_payloads: dict[int, bytes] = {s: b"ASSET" * 16 for s in DAT_RO_REQUIRED_SLOTS}
        for slot_id, ovl_name in OVERLAY_SLOT_MAP.items():
            if ovl_name not in M2_REQUIRED_OVERLAYS:
                continue
            ovl_bytes = (ok_b / f"{ovl_name}.ovl").read_bytes()
            (m2_b / f"{ovl_name}.ovl").write_bytes(ovl_bytes)
            (m2_b / f"{ovl_name}.sym").write_text((ok_b / f"{ovl_name}.sym").read_text(encoding="utf-8"), encoding="utf-8")
            (m2_b / f"{ovl_name}.lst").write_text((ok_b / f"{ovl_name}.lst").read_text(encoding="utf-8"), encoding="utf-8")
            m2_dat_payloads[slot_id] = ovl_bytes
        _write_synthetic_dat(m2_b / "MORIA8.DAT", m2_dat_payloads, entry_count=DAT_MIN_RO_SLOTS)
        errs = validate_build(m2_b, milestone="m2", src_dirs=[ok_s])
        if errs:
            print(f"FAIL: valid m2 fixture rejected: {errs}", file=sys.stderr)
            return 1
        # Negative M2 checks: missing ovl_storage.ovl, missing ovl_storage.lst, empty DAT slot 11
        (m2_b / "ovl_storage.ovl").unlink()
        if not validate_build(m2_b, milestone="m2", src_dirs=[ok_s]):
            print("FAIL: m2 failed to catch missing ovl_storage.ovl", file=sys.stderr)
            return 1
        (m2_b / "ovl_storage.ovl").write_bytes(m2_dat_payloads[11])
        (m2_b / "ovl_storage.lst").unlink()
        if not validate_build(m2_b, milestone="m2", src_dirs=[ok_s]):
            print("FAIL: m2 failed to catch missing ovl_storage.lst", file=sys.stderr)
            return 1
        (m2_b / "ovl_storage.lst").write_text((ok_b / "ovl_storage.lst").read_text(encoding="utf-8"), encoding="utf-8")
        m2_missing_slot11 = {k: v for k, v in m2_dat_payloads.items() if k != 11}
        _write_synthetic_dat(m2_b / "MORIA8.DAT", m2_missing_slot11, entry_count=DAT_MIN_RO_SLOTS)
        if not validate_build(m2_b, milestone="m2", src_dirs=[ok_s]):
            print("FAIL: m2 failed to catch empty ovl_storage slot 11 in MORIA8.DAT", file=sys.stderr)
            return 1
        _write_synthetic_dat(m2_b / "MORIA8.DAT", m2_dat_payloads, entry_count=DAT_MIN_RO_SLOTS)
        if not validate_build(m2_b, milestone="m3", src_dirs=[ok_s]):
            print("FAIL: m3 accepted M2-only fixture missing M3 overlays", file=sys.stderr)
            return 1

        # Complete M3 fixture: all 13 M3 overlays + .sym + .lst + MORIA8.DAT slots
        m3_b = root / "m3_build"
        m3_b.mkdir()
        (m3_b / "MORIA8.COM").write_bytes((ok_b / "MORIA8.COM").read_bytes())
        (m3_b / "main.sym").write_text((ok_b / "main.sym").read_text(encoding="utf-8"), encoding="utf-8")
        (m3_b / "main.lst").write_text((ok_b / "main.lst").read_text(encoding="utf-8"), encoding="utf-8")
        m3_dat_payloads: dict[int, bytes] = {s: b"ASSET" * 16 for s in DAT_RO_REQUIRED_SLOTS}
        for slot_id, ovl_name in OVERLAY_SLOT_MAP.items():
            if ovl_name not in M3_REQUIRED_OVERLAYS:
                continue
            ovl_bytes = (ok_b / f"{ovl_name}.ovl").read_bytes()
            (m3_b / f"{ovl_name}.ovl").write_bytes(ovl_bytes)
            (m3_b / f"{ovl_name}.sym").write_text((ok_b / f"{ovl_name}.sym").read_text(encoding="utf-8"), encoding="utf-8")
            (m3_b / f"{ovl_name}.lst").write_text((ok_b / f"{ovl_name}.lst").read_text(encoding="utf-8"), encoding="utf-8")
            m3_dat_payloads[slot_id] = ovl_bytes
        _write_synthetic_dat(m3_b / "MORIA8.DAT", m3_dat_payloads, entry_count=DAT_REQUIRED_SLOTS)
        errs = validate_build(m3_b, milestone="m3", src_dirs=[ok_s])
        if errs:
            print(f"FAIL: valid m3 fixture rejected: {errs}", file=sys.stderr)
            return 1
        (m3_b / "ovl_actions.ovl").unlink()
        if not validate_build(m3_b, milestone="m3", src_dirs=[ok_s]):
            print("FAIL: m3 failed to catch missing ovl_actions.ovl", file=sys.stderr)
            return 1
        (m3_b / "ovl_actions.ovl").write_bytes(m3_dat_payloads[22])
        m3_missing_slot22 = {k: v for k, v in m3_dat_payloads.items() if k != 22}
        _write_synthetic_dat(m3_b / "MORIA8.DAT", m3_missing_slot22, entry_count=DAT_REQUIRED_SLOTS)
        if not validate_build(m3_b, milestone="m3", src_dirs=[ok_s]):
            print("FAIL: m3 failed to catch empty ovl_actions slot 22 in MORIA8.DAT", file=sys.stderr)
            return 1
        _write_synthetic_dat(m3_b / "MORIA8.DAT", m3_dat_payloads, entry_count=DAT_REQUIRED_SLOTS)
        if not validate_build(m3_b, milestone="m4", src_dirs=[ok_s]):
            print("FAIL: m4 accepted M3-only fixture missing M4 overlays", file=sys.stderr)
            return 1
        errs = validate_build(ok_b, milestone="m4", src_dirs=[ok_s])
        if errs:
            print(f"FAIL: valid full fixture rejected under m4: {errs}", file=sys.stderr)
            return 1
        if not validate_build(m3_b, milestone="m5", src_dirs=[ok_s]):
            print("FAIL: m5 accepted M3-only fixture missing M4/M5 overlays", file=sys.stderr)
            return 1
        errs = validate_build(ok_b, milestone="m5", src_dirs=[ok_s])
        if errs:
            print(f"FAIL: valid full fixture (19 overlays + 25/25 DAT slots) rejected under m5: {errs}", file=sys.stderr)
            return 1
        m5_missing_slot24: dict[int, bytes] = {s: b"ASSET" * 16 for s in DAT_RO_REQUIRED_SLOTS}
        for slot_id, ovl_name in OVERLAY_SLOT_MAP.items():
            if slot_id != 24:
                m5_missing_slot24[slot_id] = (ok_b / f"{ovl_name}.ovl").read_bytes()
        _write_synthetic_dat(m3_b / "MORIA8.DAT", m5_missing_slot24, entry_count=24)
        if not validate_build(ok_b, milestone="m5", src_dirs=[ok_s], dat_path=m3_b / "MORIA8.DAT"):
            print("FAIL: m5 failed to catch 24-slot MORIA8.DAT missing slot 24", file=sys.stderr)
            return 1
        (ok_b / "huff_stream.bin").write_bytes(b"ASSET" * 16)
        (ok_b / "title_art.bin").write_bytes(b"ASSET" * 16)
        m5_tamper_ro = {
            **{slot_id: (ok_b / f"{ovl_name}.ovl").read_bytes() for slot_id, ovl_name in OVERLAY_SLOT_MAP.items()},
            **{s: b"ASSET" * 16 for s in DAT_RO_REQUIRED_SLOTS},
            16: b"TAMPER" + b"X" * 74,
        }
        _write_synthetic_dat(m3_b / "MORIA8.DAT", m5_tamper_ro, entry_count=DAT_REQUIRED_SLOTS)
        ro_errs = validate_build(ok_b, milestone="m5", src_dirs=[ok_s], dat_path=m3_b / "MORIA8.DAT")
        if not any("RO slot 16" in err for err in ro_errs):
            print(f"FAIL: m5 failed to catch tampered RO slot 16 in MORIA8.DAT: {ro_errs}", file=sys.stderr)
            return 1
        (ok_b / "huff_stream.bin").unlink()
        (ok_b / "title_art.bin").unlink()

        # 3. Resident overflow fixture (> 0x5600)
        res_b = root / "res_over"
        res_s = root / "res_src"
        res_b.mkdir()
        _create_valid_fixture(res_b, res_s)
        (res_b / "MORIA8.COM").write_bytes(b"\x00" * (RESIDENT_MAX_SIZE + 1))
        (res_b / "main.sym").write_text(
            (ok_b / "main.sym").read_text(encoding="utf-8").replace(
                f"0x{RESIDENT_BASE + 0x1000:08X}",
                f"0x{RESIDENT_LIMIT + 1:08X}",
            ),
            encoding="utf-8",
        )
        if not validate_build(res_b, milestone="all", src_dirs=[res_s]):
            print("FAIL: failed to catch resident overflow (> 0x5600)", file=sys.stderr)
            return 1

        # 4. Overlay overflow fixture (> 0x6A00 / > 5120 B / > 40 records) & wrong ORG
        ovl_b = root / "ovl_over"
        ovl_s = root / "ovl_src"
        ovl_b.mkdir()
        _create_valid_fixture(ovl_b, ovl_s)
        (ovl_b / "ovl_items_eff.ovl").write_bytes(b"\xC9" * (OVL_WINDOW_SIZE + 1))
        (ovl_b / "ovl_items_eff.sym").write_text(
            "\n".join([
                f"ovl_start: EQU 0x{OVL_WINDOW_BASE:08X}",
                f"ovl_end: EQU 0x{OVL_WINDOW_LIMIT + 1:08X}",
            ]) + "\n",
            encoding="utf-8",
        )
        if not validate_build(ovl_b, milestone="all", src_dirs=[ovl_s]):
            print("FAIL: failed to catch split overlay overflow (> 0x6A00)", file=sys.stderr)
            return 1

        _create_valid_fixture(ovl_b, ovl_s)
        (ovl_b / "ovl_gen.sym").write_text(
            "\n".join([
                "ovl_start: EQU 0x00005900",
                "ovl_end: EQU 0x00005B00",
            ]) + "\n",
            encoding="utf-8",
        )
        if not validate_build(ovl_b, milestone="all", src_dirs=[ovl_s]):
            print("FAIL: failed to catch overlay start != 0x5600", file=sys.stderr)
            return 1

        # 5. BSS overflow fixture (> 0x8C00) & fixed ABI mismatch
        bss_b = root / "bss_over"
        bss_s = root / "bss_src"
        bss_b.mkdir()
        _create_valid_fixture(bss_b, bss_s)
        (bss_b / "main.sym").write_text(
            (ok_b / "main.sym").read_text(encoding="utf-8").replace(
                f"0x{BSS_BASE + 0x0400:08X}",
                f"0x{STACK_BOTTOM + 1:08X}",
            ),
            encoding="utf-8",
        )
        if not validate_build(bss_b, milestone="all", src_dirs=[bss_s]):
            print("FAIL: failed to catch BSS overflow (> 0x8C00)", file=sys.stderr)
            return 1

        (bss_b / "main.sym").write_text(
            (ok_b / "main.sym").read_text(encoding="utf-8").replace(
                f"0x{Z80_STATE_BASE:08X}",
                "0x00006A10",
            ),
            encoding="utf-8",
        )
        if not validate_build(bss_b, milestone="all", src_dirs=[bss_s]):
            print("FAIL: failed to catch z80_state != 0x6A00", file=sys.stderr)
            return 1

        # 6. Cross-overlay call violation fixtures:
        xov_b = root / "xov_build"
        xov_s = root / "xov_src"
        xov_b.mkdir()
        # (a) Direct CALL ovl_items_eff_* from ovl_town.asm (longest-first prefix + EX AF,AF')
        _create_valid_fixture(xov_b, xov_s)
        (xov_s / "ovl_town.asm").write_text(
            "ovl_town_entry:\n    EX AF, AF' : CALL ovl_items_eff_entry\n    RET\n",
            encoding="utf-8",
        )
        if not validate_build(xov_b, milestone="all", src_dirs=[xov_s]):
            print("FAIL: failed to catch EX AF, AF' + cross-overlay CALL ovl_items_eff_entry", file=sys.stderr)
            return 1

        # (b) Leading '@' cannot bypass cross-overlay CALL
        (xov_s / "ovl_town.asm").write_text(
            "ovl_town_entry:\n    CALL @ovl_items_helper\n    RET\n",
            encoding="utf-8",
        )
        if not validate_build(xov_b, milestone="all", src_dirs=[xov_s]):
            print("FAIL: failed to catch CALL @ovl_items_helper leading-@ bypass", file=sys.stderr)
            return 1

        # (c) Offset expression CALL target + 3 across overlays
        (xov_s / "ovl_town.asm").write_text(
            "ovl_town_entry:\n    CALL ovl_items_helper + 3\n    RET\n",
            encoding="utf-8",
        )
        if not validate_build(xov_b, milestone="all", src_dirs=[xov_s]):
            print("FAIL: failed to catch CALL ovl_items_helper + 3 cross-overlay offset", file=sys.stderr)
            return 1

        # (d) Dotted MODULE symbol call from another overlay (incl. @ prefix)
        (xov_s / "ovl_town.asm").write_text(
            "ovl_town_entry:\n    CALL @ovl_items.mod_helper\n    RET\n",
            encoding="utf-8",
        )
        if not validate_build(xov_b, milestone="all", src_dirs=[xov_s]):
            print("FAIL: failed to catch dotted MODULE @ovl_items.mod_helper call", file=sys.stderr)
            return 1

        # (e) Standalone colonless col-0 non-trampoline label resets cur_label so direct CALL fails
        _create_valid_fixture(xov_b, xov_s)
        (xov_s / "main.asm").write_text(
            "tramp_colonless\n    LD A, 2\n    JP ovl_town_entry\nhelper_colonless\n    CALL ovl_town_entry\n    RET\n",
            encoding="utf-8",
        )
        if not validate_build(xov_b, milestone="all", src_dirs=[xov_s]):
            print("FAIL: failed to catch direct CALL under standalone colonless non-trampoline col-0 label", file=sys.stderr)
            return 1

        # (f) core_z80 file included by ovl_town calling ovl_items_helper
        _create_valid_fixture(xov_b, xov_s)
        (xov_s / "core_z80" / "town_impl.asm").write_text(
            "ovl_town_helper:\n    CALL ovl_items_helper\n    RET\n",
            encoding="utf-8",
        )
        if not validate_build(xov_b, milestone="all", src_dirs=[xov_s]):
            print("FAIL: failed to catch cross-overlay CALL inside core_z80 file included by ovl_town", file=sys.stderr)
            return 1

        # (g) core_z80 .asm included by BOTH ovl_town and ovl_items
        _create_valid_fixture(xov_b, xov_s)
        (xov_s / "core_z80" / "shared_bad.asm").write_text("shared_fn:\n    RET\n", encoding="utf-8")
        (xov_s / "ovl_items.asm").write_text(
            '    INCLUDE "core_z80/shared_bad.asm"\novl_items_entry:\n    RET\n',
            encoding="utf-8",
        )
        (xov_s / "ovl_town.asm").write_text(
            '    INCLUDE "core_z80/shared_bad.asm"\novl_town_entry:\n    RET\n',
            encoding="utf-8",
        )
        if not validate_build(xov_b, milestone="all", src_dirs=[xov_s]):
            print("FAIL: failed to catch .asm file included by two overlays", file=sys.stderr)
            return 1

        # (h) foo_overlay.asm must NOT bypass non-trampoline check
        _create_valid_fixture(xov_b, xov_s)
        (xov_s / "foo_overlay.asm").write_text(
            "foo_entry:\n    CALL ovl_town_entry\n    RET\n",
            encoding="utf-8",
        )
        if not validate_build(xov_b, milestone="all", src_dirs=[xov_s]):
            print("FAIL: foo_overlay.asm bypassed non-trampoline resident check", file=sys.stderr)
            return 1

        # (i) Symbol-table cross-overlay symbol leak in ovl_town.sym
        _create_valid_fixture(xov_b, xov_s)
        (xov_b / "ovl_town.sym").write_text(
            (ok_b / "ovl_town.sym").read_text(encoding="utf-8") + "ovl_spell.cast: EQU 0x00005840\n",
            encoding="utf-8",
        )
        if not validate_build(xov_b, milestone="all", src_dirs=[xov_s]):
            print("FAIL: failed to catch dotted .sym cross-overlay symbol leak", file=sys.stderr)
            return 1

        # (j) .lst audit: raw-address, conditional, & multi-statement/continuation-line CALL/JP/JR in main.lst and out-of-bounds JP in ovl_title.lst
        for bad_lst_line in (
            "99    0300 CD 00 56       CALL 0x5600\n",
            "99    0300 AF CD 00 56    XOR A : CALL 0x5600\n",
            "99    0300 AF C4 00 56    XOR A : CALL NZ, 0x5600\n",
            "99    0300 AF CA 00 57    XOR A : JP Z, 0x5700\n",
            "99    55FD AF 30 02       XOR A : JR NC, 0x5602\n",
            "99    0300 21 34 12 CD    LD HL, 0x1234 : CALL 0x5600\n99    0304 00 56\n",
            "99    0300 00 CD 00 56    NOP : CALL 0x5600 : NOP\n99    0304 00\n",
            "99    0300 F4 00 02 CD    CALL P, 0x0200 : CALL 0x5600\n99    0304 00 56\n",
        ):
            _create_valid_fixture(xov_b, xov_s)
            (xov_b / "main.lst").write_text(
                (ok_b / "main.lst").read_text(encoding="utf-8") + bad_lst_line,
                encoding="utf-8",
            )
            if not validate_build(xov_b, milestone="all", src_dirs=[xov_s]):
                print(f"FAIL: failed to catch main.lst violation: {bad_lst_line.strip()}", file=sys.stderr)
                return 1

        # Negative false-positive check: LD HL, 0x3805 : JR .ok at 0x55FD contains 0x38 0x18 suffix,
        # but JR .ok jumps backwards to 0x55FD (< 0x5600) -> MUST PASS!
        _create_valid_fixture(xov_b, xov_s)
        (xov_b / "main.lst").write_text(
            (ok_b / "main.lst").read_text(encoding="utf-8")
            + "99    55FD 21 05 38 18    .ok: LD HL, 0x3805 : JR .ok\n99    5601 FB\n",
            encoding="utf-8",
        )
        errs_ok_jr = validate_build(xov_b, milestone="all", src_dirs=[xov_s])
        if errs_ok_jr:
            print(f"FAIL: false positive on LD HL, 0x3805 : JR .ok at 0x55FD: {errs_ok_jr}", file=sys.stderr)
            return 1

        _create_valid_fixture(xov_b, xov_s)
        (xov_b / "ovl_title.lst").write_text(
            (ok_b / "ovl_title.lst").read_text(encoding="utf-8") + "99    5630 C3 00 59       JP 0x5900\n",
            encoding="utf-8",
        )
        if not validate_build(xov_b, milestone="all", src_dirs=[xov_s]):
            print("FAIL: failed to catch out-of-bounds JP 0x5900 in ovl_title.lst", file=sys.stderr)
            return 1

        # 7. Corrupt MORIA8.DAT TOC, stale .ovl mismatch, & standalone --dat check
        dat_b = root / "dat_bad"
        dat_s = root / "dat_src"
        dat_b.mkdir()
        _create_valid_fixture(dat_b, dat_s)
        _write_synthetic_dat(dat_b / "MORIA8.DAT", {0: b"X" * 128}, magic=b"BAD!")
        if not validate_build(dat_b, milestone="all", src_dirs=[dat_s]):
            print("FAIL: failed to catch bad MORIA8.DAT magic", file=sys.stderr)
            return 1
        _write_synthetic_dat(
            dat_b / "MORIA8.DAT",
            {0: b"X" * 256, 1: b"Y" * 256},
            override_entries={1: (2, 2, 256)},
        )
        if not validate_build(dat_b, milestone="all", src_dirs=[dat_s]):
            print("FAIL: failed to catch overlapping MORIA8.DAT records", file=sys.stderr)
            return 1

        # Built .ovl byte mismatch against populated MORIA8.DAT slot must fail
        _create_valid_fixture(dat_b, dat_s)
        stale_blob = bytearray((dat_b / "ovl_town.ovl").read_bytes())
        stale_blob[0] ^= 0xFF
        (dat_b / "ovl_town.ovl").write_bytes(bytes(stale_blob))
        if not validate_build(dat_b, milestone="all", src_dirs=[dat_s]):
            print("FAIL: failed to catch stale MORIA8.DAT payload mismatching ovl_town.ovl", file=sys.stderr)
            return 1

        # Verify standalone --dat CLI path succeeds even when --build-dir exists without MORIA8.COM
        dat_cli = subprocess.run(
            [
                sys.executable,
                "-B",
                str(Path(__file__).resolve()),
                "--dat",
                str(ok_b / "MORIA8.DAT"),
                "--build-dir",
                str(m0_b),
            ],
            capture_output=True,
            text=True,
        )
        if dat_cli.returncode != 0:
            print(f"FAIL: standalone --dat failed when --build-dir exists: {dat_cli.stderr}", file=sys.stderr)
            return 1

        # 8. Real sjasmplus + memory.inc assembly integration test (when installed)
        if DEFAULT_SJASMPLUS.exists() and (CPM_SRC_DIR / "memory.inc").exists():
            sj_out = root / "sj_test"
            sj_out.mkdir()
            (sj_out / "trampolines.asm").write_text(
                "\n".join([
                    "OVL_TITLE_VEC EQU OVL_WINDOW_BASE + 0",
                    "    EXPORT tramp_title_menu",
                    "tramp_title_menu:",
                    "    CALL overlay_trampoline",
                    "    DB OVL_TITLE",
                    "    DW OVL_TITLE_VEC",
                    "    EXPORT tramp_legal_viewer",
                    "tramp_legal_viewer:",
                    "    CALL overlay_trampoline",
                    "    DB OVL_LEGAL",
                    "    DW OVL_WINDOW_BASE + 0",
                ]) + "\n",
                encoding="utf-8",
            )
            test_asm = sj_out / "probe.asm"
            test_asm.write_text(
                "\n".join([
                    '    DEVICE NOSLOT64K',
                    '    INCLUDE "memory.inc"',
                    '    ORG RESIDENT_BASE',
                    'resident_start:',
                    '    LD HL, (CPM_BDOS_VEC)',
                    '    LD SP, STACK_TOP',
                    '    CALL tramp_title_menu',
                    '    JP CPM_WARM_BOOT',
                    '    EXPORT overlay_trampoline',
                    'overlay_trampoline:',
                    '    RET',
                    '    INCLUDE "trampolines.asm"',
                    'resident_end:',
                    '    ASSERT_RESIDENT_FIT resident_start, resident_end',
                    '    ORG BSS_BASE',
                    'bss_start:',
                    'z80_state: DS Z80_STATE_SIZE, 0',
                    'bss_end:',
                    '    ASSERT_BSS_FIT bss_start, bss_end',
                    '    ORG STACK_BOTTOM',
                    'stack_bottom:',
                    'stack_canary: DB STACK_CANARY_B0, STACK_CANARY_B1, STACK_CANARY_B2, STACK_CANARY_B3',
                    '    ORG STACK_TOP',
                    'stack_top:',
                    '    ORG CPM_CHAR_SHADOW_BASE',
                    'cpm_char_shadow: DS CPM_CHAR_SHADOW_SIZE, 0',
                    '    ORG CPM_COLOR_SHADOW_BASE',
                    'cpm_color_shadow: DS CPM_COLOR_SHADOW_SIZE, 0',
                    '    ORG MAP_BASE',
                    'map_base: DS MAP_SIZE, 0',
                    '    ORG FCB_DAT_ADDR',
                    'fcb_dat: DS FCB_SIZE, 0',
                    '    ORG FCB_SAVE_ADDR',
                    'fcb_save: DS FCB_SIZE, 0',
                    '    ORG FCB_TMP_ADDR',
                    'fcb_tmp: DS FCB_SIZE, 0',
                    '    ORG CPM_DMA_BUF_BASE',
                    'cpm_dma_buf: DS CPM_DMA_BUF_SIZE, 0',
                    '    SAVEBIN "MORIA8.COM", resident_start, resident_end - resident_start',
                ]) + "\n",
                encoding="utf-8",
            )
            proc = subprocess.run(
                [
                    str(DEFAULT_SJASMPLUS),
                    "--nologo",
                    f"-I{CPM_SRC_DIR}",
                    f"-I{sj_out}",
                    f"--outprefix={sj_out}/",
                    f"--sym={sj_out}/main.sym",
                    f"--exp={sj_out}/main_exp.inc",
                    f"--lst={sj_out}/main.lst",
                    str(test_asm),
                ],
                capture_output=True,
                text=True,
            )
            if proc.returncode != 0:
                print(
                    f"FAIL: sjasmplus failed assembling memory.inc probe:\n{proc.stderr}",
                    file=sys.stderr,
                )
                return 1
            sj_dat: dict[int, bytes] = {s: b"R" * 128 for s in DAT_RO_REQUIRED_SLOTS}
            sj_ovls = [
                (slot_id, ovl_name)
                for slot_id, ovl_name in OVERLAY_SLOT_MAP.items()
                if ovl_name in M3_REQUIRED_OVERLAYS or ovl_name == "ovl_items_eff"
            ]
            for slot_id, ovl_name in sj_ovls:
                ovl_asm = sj_out / f"{ovl_name}.asm"
                ovl_asm.write_text(
                    "\n".join([
                        '    DEVICE NOSLOT64K',
                        '    INCLUDE "memory.inc"',
                        '    INCLUDE "main_exp.inc"',
                        '    ORG OVL_WINDOW_BASE',
                        'ovl_start:',
                        f'    JP {ovl_name}_entry',
                        f'{ovl_name}_entry:',
                        '    CALL tramp_legal_viewer',
                        '    RET',
                        'ovl_end:',
                        '    ASSERT_OVL_FIT ovl_start, ovl_end',
                        f'    SAVEBIN "{ovl_name}.ovl", ovl_start, ovl_end - ovl_start',
                    ]) + "\n",
                    encoding="utf-8",
                )
                oproc = subprocess.run(
                    [
                        str(DEFAULT_SJASMPLUS),
                        "--nologo",
                        f"-I{CPM_SRC_DIR}",
                        f"-I{sj_out}",
                        f"--outprefix={sj_out}/",
                        f"--sym={sj_out}/{ovl_name}.sym",
                        f"--lst={sj_out}/{ovl_name}.lst",
                        str(ovl_asm),
                    ],
                    capture_output=True,
                    text=True,
                )
                if oproc.returncode != 0:
                    print(
                        f"FAIL: sjasmplus failed assembling {ovl_name} probe:\n{oproc.stderr}",
                        file=sys.stderr,
                    )
                    return 1
                sj_dat[slot_id] = (sj_out / f"{ovl_name}.ovl").read_bytes()
            _write_synthetic_dat(sj_out / "MORIA8.DAT", sj_dat, entry_count=DAT_REQUIRED_SLOTS)
            errs = validate_build(sj_out, milestone="m1", src_dirs=[])
            if errs:
                print(f"FAIL: sjasmplus-assembled memory.inc failed m1 contract: {errs}", file=sys.stderr)
                return 1
            errs = validate_build(sj_out, milestone="m2", src_dirs=[])
            if errs:
                print(f"FAIL: sjasmplus-assembled memory.inc failed m2 contract: {errs}", file=sys.stderr)
                return 1
            errs = validate_build(sj_out, milestone="m3", src_dirs=[])
            if errs:
                print(f"FAIL: sjasmplus-assembled memory.inc failed m3 contract: {errs}", file=sys.stderr)
                return 1

            # Real sjasmplus --lst multi-statement pass/fail checks
            if len(_UNPREFIXED_3B) != 26:
                print(
                    f"FAIL: expected 26 opcodes in _UNPREFIXED_3B, got {len(_UNPREFIXED_3B)}",
                    file=sys.stderr,
                )
                return 1
            sj_lst_dir = root / "sj_lst_cases"
            sj_lst_dir.mkdir()
            for case_name, body_lines, expect_fail in (
                ("bad_ld_call", ["    ORG 0x0300", "    LD HL, 0x1234 : CALL 0x5600"], True),
                ("bad_mid_call", ["    ORG 0x0300", "    NOP : CALL 0x5600 : NOP"], True),
                ("bad_call_p_call", ["    ORG 0x0300", "    CALL P, 0x0200 : CALL 0x5600"], True),
                ("ok_ld_jr", ["    ORG 0x55FA", ".ok:", "    LD HL, 0x3805 : JR .ok"], False),
            ):
                c_asm = sj_lst_dir / f"{case_name}.asm"
                c_lst = sj_lst_dir / "main.lst"
                c_asm.write_text(
                    "\n".join(["    DEVICE NOSLOT64K", "main_fn:", *body_lines, "    RET"]) + "\n",
                    encoding="utf-8",
                )
                c_proc = subprocess.run(
                    [str(DEFAULT_SJASMPLUS), "--nologo", f"--lst={c_lst}", str(c_asm)],
                    capture_output=True,
                    text=True,
                )
                if c_proc.returncode != 0:
                    print(f"FAIL: sjasmplus failed on {case_name}:\n{c_proc.stderr}", file=sys.stderr)
                    return 1
                c_errs = validate_listing_files(sj_lst_dir, {"main_fn": 0x0300}, {})
                if expect_fail and not c_errs:
                    print(f"FAIL: real sjasmplus --lst case {case_name} was not caught", file=sys.stderr)
                    return 1
                if not expect_fail and c_errs:
                    print(f"FAIL: real sjasmplus --lst case {case_name} triggered false positive: {c_errs}", file=sys.stderr)
                    return 1

            for case_name, lst_name, body_lines, expected_substr in (
                (
                    "ovl_pre_org_db",
                    "ovl_chest.lst",
                    ["    DB 0x11, 0x22, 0x33", "    ORG 0x5600", "ovl_start:", "    RET", "ovl_end:"],
                    "outside",
                ),
                (
                    "ovl_pre_org_ds",
                    "ovl_chest.lst",
                    ["    DS 16", "    ORG 0x5600", "ovl_start:", "    RET", "ovl_end:"],
                    "outside",
                ),
                (
                    "main_pre_org_db",
                    "main.lst",
                    ["    DB 0xAA, 0xBB", "    ORG 0x0100", "    RET"],
                    "below RESIDENT_BASE",
                ),
            ):
                case_dir = sj_lst_dir / case_name
                case_dir.mkdir()
                c_asm = case_dir / f"{case_name}.asm"
                c_lst = case_dir / lst_name
                c_asm.write_text(
                    "\n".join(["    DEVICE NOSLOT64K", "main_fn:", *body_lines]) + "\n",
                    encoding="utf-8",
                )
                c_proc = subprocess.run(
                    [str(DEFAULT_SJASMPLUS), "--nologo", f"--lst={c_lst}", str(c_asm)],
                    capture_output=True,
                    text=True,
                )
                if c_proc.returncode != 0:
                    print(f"FAIL: sjasmplus failed on {case_name}:\n{c_proc.stderr}", file=sys.stderr)
                    return 1
                c_ovl_syms = (
                    {"ovl_chest": {"ovl_start": 0x5600, "ovl_end": 0x5601}}
                    if lst_name != "main.lst"
                    else {}
                )
                c_errs = validate_listing_files(case_dir, {"main_fn": 0x0300}, c_ovl_syms)
                if not any(expected_substr in err for err in c_errs):
                    print(
                        f"FAIL: real sjasmplus --lst case {case_name} did not report {expected_substr!r}: {c_errs}",
                        file=sys.stderr,
                    )
                    return 1

    print("CP/M Z80 memory contract self-test: PASS")
    return 0


def _parse_milestone(raw_milestone: str, raw_milestones: str | None) -> str:
    if raw_milestones:
        items = [m.strip().lower() for m in raw_milestones.split(",") if m.strip()]
        if not items:
            raise ValueError("--milestones cannot be empty")
        for m in items:
            if m not in MILESTONE_CHOICES:
                raise ValueError(f"unknown milestone {m!r}; choose from {MILESTONE_CHOICES}")
        if "all" in items or "m5" in items:
            return "all"
        order = {name: idx for idx, name in enumerate(MILESTONE_CHOICES)}
        return max(items, key=lambda m: order[m])
    m = raw_milestone.strip().lower()
    if m not in MILESTONE_CHOICES:
        raise ValueError(f"unknown milestone {m!r}; choose from {MILESTONE_CHOICES}")
    return m


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true", help="Run synthetic pass/fail self-tests.")
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR)
    parser.add_argument(
        "--lst-dir",
        type=Path,
        default=None,
        help="Directory containing main.lst and ovl_*.lst (defaults to --build-dir).",
    )
    parser.add_argument(
        "--milestone",
        default="all",
        help="Contract milestone gate (m0, m1, m2, m3, m4, m5, all). Default: all.",
    )
    parser.add_argument(
        "--milestones",
        default=None,
        help="Alias/comma-separated milestone list (e.g. m1,m2).",
    )
    parser.add_argument("--dat", type=Path, default=None, help="Explicit MORIA8.DAT path to validate standalone.")
    parser.add_argument(
        "--no-src-audit",
        action="store_true",
        help="Skip Z80 assembly source cross-overlay scan.",
    )
    args = parser.parse_args()

    if args.selftest:
        return run_selftest()

    try:
        milestone = _parse_milestone(args.milestone, args.milestones)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if args.dat is not None:
        errors = validate_moria8_dat(args.dat, require_all_slots=(milestone in ("m5", "all")))
    else:
        src_dirs = [] if args.no_src_audit else [CPM_SRC_DIR, CORE_Z80_DIR]
        errors = validate_build(
            args.build_dir,
            milestone=milestone,
            src_dirs=src_dirs,
            lst_dir=args.lst_dir,
        )

    if errors:
        print(f"CP/M Z80 memory contract check FAILED ({milestone}):", file=sys.stderr)
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        return 1

    print(f"CP/M Z80 memory contract check passed ({milestone}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
