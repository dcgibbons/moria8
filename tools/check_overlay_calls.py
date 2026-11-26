#!/usr/bin/env python3
"""
tools/check_overlay_calls.py
Module ownership: platform-tooling static cross-overlay & resident->overlay
validator across all 7 Moria8 disk ports and 5 cartridge builds.

Validates all 12 Moria8 configurations pre-build (without requiring ``build/``)
by following Kick Assembler ``#import`` graphs, conditional directives
(``#if``/``#ifdef``/``#ifndef``/``#elif``/``#else``/``#endif`` — both top-level
and inside ``.macro`` bodies), ``.segment`` switches, and ``.macro`` expansions
from each port's ``main.s``.

Flags an error if:
1. Code/data inside Overlay ``A`` references (``jsr``, ``jmp``, ``bra``,
   conditional branch, indirect jump, memory operand ``lda``/``sta``/etc.,
   ``<label``/``>label``, or ``.word label``) a symbol defined ONLY in other
   overlay segment(s) ``B != A`` without staging through a verified resident
   swap dispatcher.
2. Code/data inside a non-overlay segment (``Default``, ``RuntimeBanked``,
   ``A2PlaySlot``, ``BeebPlaySlot``, ``C128ResidentPlay``, etc.) references an
   overlay-only symbol unless that target overlay is proven mapped (declared
   manifest trampoline, explicit ``overlay_load`` / bank switch / dispatcher,
   or co-executed helper/table whose callers all have that overlay mapped).
3. Post-build ``--check-sym`` finds a trampoline placed outside valid resident
   executable RAM ranges (e.g. inside ``MAP_BASE``, hardware I/O holes, tier
   pools, overlay windows, or CPU vector pages) or an overlay target outside
   its port's overlay window.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Mapping, Optional, Sequence, Set, Tuple

sys.dont_write_bytecode = True

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import gen_trampolines  # noqa: E402
from trampoline_manifest import PORT_ENTRIES, PORTS, TrampolineEntry  # noqa: E402


CART_PORTS: Tuple[str, ...] = (
    "c64-cart",
    "plus4-cart",
    "c128-cart",
    "cx16-cart",
    "atari8-cart",
)
ALL_TARGETS: Tuple[str, ...] = PORTS + CART_PORTS

BASE_PORT_OF: Dict[str, str] = {
    **{p: p for p in PORTS},
    "c64-cart": "c64",
    "plus4-cart": "plus4",
    "c128-cart": "c128",
    "cx16-cart": "cx16",
    "atari8-cart": "atari8",
}

OVERLAY_WINDOW: Dict[str, Tuple[int, int]] = {
    "apple2": (0xA400, 0xB9FF),
    "bbcmaster": (0xA800, 0xBFFF),
    "cx16": (0xA000, 0xBFFF),
    "atari8": (0xE000, 0xEFFF),
    "c64": (0xE000, 0xEFFF),
    "plus4": (0xE000, 0xEFFF),
    "c128": (0xE000, 0xEFFF),
}

# Exact valid inclusive (lo, hi) executable RAM spans for non-alias trampolines
# on each port (Default, PlaySlot, C128 runtime slots, RuntimeBanked). Excludes
# ZP/stack, MAP_BASE, tier-name pools, I/O holes, overlay windows, MMU $FF00,
# and CPU vectors ($FFFA-$FFFF).
RESIDENT_CODE_RANGES: Dict[str, Tuple[Tuple[int, int], ...]] = {
    "apple2": (
        (0x0A00, 0x7BFF),  # Default
        (0x7C00, 0x9FFF),  # A2PlaySlot
    ),
    "bbcmaster": (
        (0x0E00, 0x7FFF),  # LowHelpers + Default
        (0x8000, 0xA3FF),  # BeebPlaySlot
    ),
    "cx16": (
        (0x0801, 0x9AFF),  # Unified Resident+Play (< $9B00 tier pool)
    ),
    "atari8": (
        (0x0C00, 0xC0FF),  # LowHelpers + Default (< $C100 MAP_BASE)
        (0xF000, 0xFFF9),  # RuntimeBanked (< $FFFA vectors)
    ),
    "c64": (
        (0x0801, 0xBFFF),  # Default (< $C000 MAP_BASE)
        (0xF000, 0xFFF9),  # RuntimeBanked (< $FFFA vectors)
    ),
    "plus4": (
        (0x1001, 0xC7FF),  # Default (< $C800 MAP_BASE)
        (0xF000, 0xFBFF),  # RuntimeBanked (< $FC00 TED/ROM stub)
    ),
    "c128": (
        (0x0A80, 0x0FFF),  # 128.proj / 128.input / 128.fdisk common slots
        (0x1000, 0x19FF),  # 128.runtime (< $1A00 FLOOR_ITEM_BASE)
        (0x1C01, 0xAEFF),  # Default moria128.prg
        (0xAF00, 0xCFFF),  # C128ResidentPersist / C128ResidentPlay (< $D000 I/O)
        (0xF000, 0xFEFF),  # RuntimeBankedCode (< $FF00 MMU)
    ),
}

OVL_CONST_TO_SEGMENT: Dict[str, str] = {
    "OVL_STARTUP": "StartupOverlay",
    "OVL_TOWN": "TownOverlay",
    "OVL_DEATH": "DeathOverlay",
    "OVL_MODAL_MISC": "ModalMiscOverlay",
    "OVL_DUNGEON_GEN": "DungeonGenOverlay",
    "OVL_HELP": "HelpOverlay",
    "OVL_UI": "UiOverlay",
    "OVL_ITEMS": "ItemActionsOverlay",
    "OVL_SPELL": "SpellOverlay",
    "OVL_DISARM": "DisarmOverlay",
    "OVL_CHEST": "ChestOverlay",
    "OVL_HOME": "HomeOverlay",
    "OVL_STORAGE": "StorageOverlay",
    "OVL_TITLE": "TitleOverlay",
    # C128 symbolic & numeric overlay IDs
    "C128_STARTUP_OVERLAY_ID": "StartupOverlay",
    "C128_TOWN_OVERLAY_ID": "TownOverlay",
    "C128_DEATH_OVERLAY_ID": "DeathOverlay",
    "C128_MODAL_MISC_OVERLAY_ID": "ModalMiscOverlay",
    "C128_MODAL_OVERLAY_ID": "ModalMiscOverlay",
    "C128_DUNGEON_GEN_OVERLAY_ID": "DungeonGenOverlay",
    "C128_HELP_OVERLAY_ID": "HelpOverlay",
    "C128_UI_OVERLAY_ID": "UiOverlay",
    "C128_ITEMS_OVERLAY_ID": "ItemActionsOverlay",
    "C128_DISARM_OVERLAY_ID": "DisarmOverlay",
    "C128_CHEST_OVERLAY_ID": "ChestOverlay",
    "C128_HOME_OVERLAY_ID": "HomeOverlay",
    "C128_STORAGE_OVERLAY_ID": "StorageOverlay",
    "1": "StartupOverlay",
    "2": "TownOverlay",
    "3": "DeathOverlay",
    "4": "ModalMiscOverlay",
    "5": "DungeonGenOverlay",
    "6": "HelpOverlay",
    "7": "UiOverlay",
    "8": "ItemActionsOverlay",
    "9": "SpellOverlay",
    "10": "ChestOverlay",
    "11": "HomeOverlay",
    "12": "StorageOverlay",
    "13": "TitleOverlay",
    # CX16 direct HiRAM bank constants
    "CX16_BANK_STARTUP": "StartupOverlay",
    "CX16_BANK_TOWN": "TownOverlay",
    "CX16_BANK_DEATH": "DeathOverlay",
    "CX16_BANK_GEN": "DungeonGenOverlay",
    "CX16_BANK_DUNGEON_GEN": "DungeonGenOverlay",
    "CX16_BANK_HELP": "HelpOverlay",
    "CX16_BANK_UI": "UiOverlay",
    "CX16_BANK_ITEMS": "ItemActionsOverlay",
    "CX16_BANK_SPELL": "SpellOverlay",
    "CX16_BANK_MODAL": "ModalMiscOverlay",
    "CX16_BANK_MODAL_MISC": "ModalMiscOverlay",
    "CX16_BANK_CHEST": "ChestOverlay",
    "CX16_BANK_HOME": "HomeOverlay",
    "CX16_BANK_STORAGE": "StorageOverlay",
    "CX16_BANK_TITLE_OVL": "TitleOverlay",
    "CX16_BANK_LEGAL": "LegalOverlay",
}

# Verified resident overlay-swap dispatchers and the target overlay they page in
# before calling the staged handler pointer.
_SWAP_DIRECT_DISPATCHERS: Mapping[str, str] = {
    "chest_dispatch": "ChestOverlay",
    "chest_swap_dispatch": "ChestOverlay",
    "modal_swap_dispatch": "ModalMiscOverlay",
    "help_swap_dispatch": "HelpOverlay",
    "death_swap_dispatch": "DeathOverlay",
    "tramp_death_call_restore_spell": "DeathOverlay",
    "tramp_chest_call_restore_items": "ChestOverlay",
    "storage_swap_dispatch": "StorageOverlay",
    "c128_call_chest_preserve_ovl": "ChestOverlay",
    "c128_call_gen_preserve_ovl": "DungeonGenOverlay",
    "c128_call_help_preserve_ovl": "HelpOverlay",
    "c128_call_storage_preserve_ovl": "StorageOverlay",
    "a8_disp_chs": "ChestOverlay",
    "a8_swap_dth": "DeathOverlay",
    "a8_disp_hlp_piw": "HelpOverlay",
    "a8_disp_sto": "StorageOverlay",
    "tramp_items_dispatch": "ItemActionsOverlay",
}
_SWAP_PATCH_TARGETS: Mapping[str, Tuple[str, str]] = {
    "tsci_target": ("tramp_spell_call_items", "SpellOverlay"),
    "tpdi_target": ("tramp_p3_death_items", "DeathOverlay"),
}

# Generic dispatchers that take the overlay ID in A or X alongside <sym/>sym.
_GENERIC_OVL_DISPATCHERS: Set[str] = {
    "tramp_ovl_dispatch",
    "ovl_dispatch_ay",
    "ovl_swap_dispatch_x",
    "c128_call_ovl_preserve_common",
}

# Overlay load / bank-switch primitives that map an overlay in-place.
_OVERLAY_LOAD_CALLS: Set[str] = {
    "overlay_load",
    "overlay_load_no_kernal",
    "overlay_load_disk",
    "c128_select_overlay",
    "c128_load_overlay",
}

# Helper routines whose post-condition leaves a specific overlay mapped.
_HELPER_LEAVES_OVERLAY_MAPPED: Mapping[str, str] = {
    "save_prepare_slot_prompt": "StorageOverlay",
    "disk_prepare_selected_save_media": "StorageOverlay",
    "tramp_game_over_prepare": "DeathOverlay",
    "game_over_prepare_for_disk_io": "DeathOverlay",
    "tramp_sr_gen_loaded": "DungeonGenOverlay",
    "hal_asset_load_legal": "LegalOverlay",
    "legal_load_ui": "LegalOverlay",
}


@dataclass(frozen=True)
class PortConfig:
    port: str
    entry: str
    defines: Mapping[str, int]
    libdirs: Tuple[str, ...]
    base_port: Optional[str] = None

    @property
    def canonical_port(self) -> str:
        return self.base_port or BASE_PORT_OF.get(self.port, self.port)


PORT_CONFIGS: Dict[str, PortConfig] = {
    "apple2": PortConfig(
        port="apple2",
        entry="platforms/apple2/main.s",
        defines={"APPLE2": 1},
        libdirs=(
            "core/6502",
            "platforms/apple2",
            "platforms/apple2/hal",
            "platforms/commodore/common",
            "platforms/shared",
        ),
    ),
    "bbcmaster": PortConfig(
        port="bbcmaster",
        entry="platforms/bbcmaster/main.s",
        defines={"BBCMASTER": 1},
        libdirs=(
            "core/6502",
            "platforms/bbcmaster",
            "platforms/bbcmaster/hal",
            "platforms/commodore/common",
            "platforms/commodore/c64",
            "platforms",
            ".",
        ),
    ),
    "cx16": PortConfig(
        port="cx16",
        entry="platforms/cx16/main.s",
        defines={"CX16": 1},
        libdirs=(
            "core/6502",
            "platforms/cx16",
            "platforms/cx16/hal",
            "platforms/commodore/common",
        ),
    ),
    "atari8": PortConfig(
        port="atari8",
        entry="platforms/atari8/main.s",
        defines={"ATARI8": 1},
        libdirs=(
            "core/6502",
            "platforms/atari8",
            "platforms/atari8/hal",
            "platforms/commodore/common",
            "platforms/commodore/c64",
            "platforms",
            ".",
        ),
    ),
    "c64": PortConfig(
        port="c64",
        entry="platforms/commodore/c64/main.s",
        defines={"DEBUG_FEAT_DISK_TRACE": 0},
        libdirs=("core/6502", "platforms/commodore/common", "platforms/commodore/c64"),
    ),
    "plus4": PortConfig(
        port="plus4",
        entry="platforms/commodore/plus4/main.s",
        defines={"PLUS4": 1},
        libdirs=("core/6502", "platforms/commodore/common", "platforms/commodore/c64"),
    ),
    "c128": PortConfig(
        port="c128",
        entry="platforms/commodore/c128/main.s",
        defines={"C128": 1},
        libdirs=("core/6502", "platforms/commodore/common", "platforms/commodore/c64"),
    ),
    # 5 shipping cartridge configurations
    "c64-cart": PortConfig(
        port="c64-cart",
        base_port="c64",
        entry="platforms/commodore/c64/main.s",
        defines={"DEBUG_FEAT_DISK_TRACE": 0, "C64_CARTRIDGE": 1},
        libdirs=("core/6502", "platforms/commodore/common", "platforms/commodore/c64"),
    ),
    "plus4-cart": PortConfig(
        port="plus4-cart",
        base_port="plus4",
        entry="platforms/commodore/plus4/main.s",
        defines={"PLUS4": 1, "PLUS4_CARTRIDGE": 1},
        libdirs=("core/6502", "platforms/commodore/common", "platforms/commodore/c64"),
    ),
    "c128-cart": PortConfig(
        port="c128-cart",
        base_port="c128",
        entry="platforms/commodore/c128/main.s",
        defines={"C128": 1, "C128_CARTRIDGE": 1},
        libdirs=("core/6502", "platforms/commodore/common", "platforms/commodore/c64"),
    ),
    "cx16-cart": PortConfig(
        port="cx16-cart",
        base_port="cx16",
        entry="platforms/cx16/main.s",
        defines={"CX16": 1, "CX16_CARTRIDGE": 1},
        libdirs=(
            "core/6502",
            "platforms/cx16",
            "platforms/cx16/hal",
            "platforms/commodore/common",
        ),
    ),
    "atari8-cart": PortConfig(
        port="atari8-cart",
        base_port="atari8",
        entry="platforms/atari8/main.s",
        defines={"ATARI8": 1, "ATARI8_CARTRIDGE": 1},
        libdirs=(
            "core/6502",
            "platforms/atari8",
            "platforms/atari8/hal",
            "platforms/commodore/common",
            "platforms/commodore/c64",
            "platforms",
            ".",
        ),
    ),
}


@dataclass(frozen=True)
class SymbolRef:
    segment: str
    symbol: str
    kind: str
    file: str
    line: int
    stmt_index: int = -1
    owner_label: Optional[str] = None


@dataclass(frozen=True)
class CrossOverlayViolation:
    port: str
    caller_segment: str
    target_segments: Tuple[str, ...]
    symbol: str
    ref_kind: str
    file: str
    line: int

    def format(self) -> str:
        tgt = ", ".join(self.target_segments)
        return (
            f"{self.port}: cross-overlay {self.ref_kind} from {self.caller_segment} -> "
            f"[{tgt}] symbol '{self.symbol}' at {self.file}:{self.line}"
        )


@dataclass
class PortAnalysis:
    port: str
    overlay_segments: Set[str]
    sym_segments: Dict[str, Set[str]]
    sym_aliases: Dict[str, List[Tuple[str, str]]]
    refs: List[SymbolRef]
    const_names: Set[str]
    defines: Dict[str, int]
    symbol_defines: Dict[str, str]
    import_errors: List[str]
    stmt_log: Tuple[Tuple[str, Optional[str], str], ...] = ()
    label_stmt_index: Mapping[Tuple[str, str], int] = ()
    manifest_entries: Tuple[TrampolineEntry, ...] = ()


_BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
_MACRO_HEADER_RE = re.compile(r"^\s*\.macro\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*(.*)$")
_FUNC_HEADER_RE = re.compile(r"^\s*\.function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
_SEGDEF_RE = re.compile(r"^\s*\.segmentdef\s+([A-Za-z_][A-Za-z0-9_]*)\s*(.*)$")
_SEGMENT_RE = re.compile(r"^\s*\.segment\s+([A-Za-z_][A-Za-z0-9_]*)\b")
_IMPORT_RE = re.compile(r'^\s*#import\s+"([^"]+)"')
_DEFINE_RE = re.compile(r"^\s*#define\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s+(.*))?$")
_UNDEF_RE = re.compile(r"^\s*#undef\s+([A-Za-z_][A-Za-z0-9_]*)\b")
_CONST_RE = re.compile(r"^\s*\.const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=")
_LABEL_DEF_RE = re.compile(r"^\s*@?([A-Za-z_][A-Za-z0-9_]*)\s*:(.*)$")
_LOCAL_LABEL_DEF_RE = re.compile(r"^\s*![A-Za-z0-9_]*\s*:(.*)$")
_DOT_LABEL_RE = re.compile(r"^\s*\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$")
_MACRO_CALL_RE = re.compile(r"^\s*:([A-Za-z_][A-Za-z0-9_]*)\s*\((.*)\)\s*$")
_BRANCH_CALL_RE = re.compile(
    r"^\s*(jsr|jmp|bra|bcc|bcs|beq|bne|bmi|bpl|bvc|bvs)\s+(?!\()([A-Za-z_][A-Za-z0-9_]*)\b",
    re.IGNORECASE,
)
_INDIRECT_CALL_RE = re.compile(
    r"^\s*(jmp|jsr)\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\b",
    re.IGNORECASE,
)
_MEM_OP_RE = re.compile(
    r"^\s*(lda|ldx|ldy|sta|stx|sty|stz|cmp|cpx|cpy|adc|sbc|and|ora|eor|bit|inc|dec|asl|lsr|rol|ror|tsb|trb)\s+(.+)$",
    re.IGNORECASE,
)
_HI_LO_RE = re.compile(r"#?\s*[<>]\s*\(?\s*([A-Za-z_][A-Za-z0-9_]*)\b")
_WORD_DIR_RE = re.compile(r"^\s*\.word\s+(.+)$", re.IGNORECASE)
_BYTE_DIR_RE = re.compile(r"^\s*\.byte\s+(.+)$", re.IGNORECASE)
_IDENT_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\b")
_PLAIN_IDENT_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)$")
_SYM_LINE_RE = re.compile(r"^\.label\s+([A-Za-z_][A-Za-z0-9_]*)=\$([0-9a-fA-F]+)\b")
_CPU_REG_TOKENS = frozenset({"a", "x", "y", "sp"})


def _strip_line_comment(line: str) -> str:
    in_str = False
    escaped = False
    i = 0
    while i < len(line):
        ch = line[i]
        if escaped:
            escaped = False
        elif ch == "\\" and in_str:
            escaped = True
        elif ch == '"':
            in_str = not in_str
        elif not in_str and ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
            return line[:i]
        i += 1
    return line


def _split_statements(line: str) -> List[str]:
    parts: List[str] = []
    cur: List[str] = []
    in_str = False
    escaped = False
    for ch in line:
        if escaped:
            cur.append(ch)
            escaped = False
            continue
        if ch == "\\" and in_str:
            cur.append(ch)
            escaped = True
            continue
        if ch == '"':
            in_str = not in_str
            cur.append(ch)
            continue
        if not in_str and ch == ";":
            parts.append("".join(cur))
            cur = []
            continue
        cur.append(ch)
    parts.append("".join(cur))
    return parts


def _brace_delta(line: str) -> int:
    in_str = False
    escaped = False
    delta = 0
    for ch in line:
        if escaped:
            escaped = False
            continue
        if ch == "\\" and in_str:
            escaped = True
            continue
        if ch == '"':
            in_str = not in_str
            continue
        if not in_str:
            if ch == "{":
                delta += 1
            elif ch == "}":
                delta -= 1
    return delta


def _tokenize_cond(expr: str) -> List[Tuple[str, str]]:
    tokens: List[Tuple[str, str]] = []
    i = 0
    n = len(expr)
    while i < n:
        ch = expr[i]
        if ch.isspace():
            i += 1
            continue
        two = expr[i : i + 2]
        if two in ("&&", "||", "==", "!=", "<=", ">="):
            tokens.append(("OP", two))
            i += 2
            continue
        if ch in ("!", "(", ")", "<", ">", "+", "-", "*", "/"):
            tokens.append(("OP", ch))
            i += 1
            continue
        if ch == "$":
            j = i + 1
            while j < n and expr[j] in "0123456789abcdefABCDEF":
                j += 1
            tokens.append(("NUM", str(int(expr[i + 1 : j] or "0", 16))))
            i = j
            continue
        if ch.isdigit():
            j = i
            while j < n and expr[j].isdigit():
                j += 1
            tokens.append(("NUM", expr[i:j]))
            i = j
            continue
        if ch.isalpha() or ch == "_":
            j = i
            while j < n and (expr[j].isalnum() or expr[j] == "_"):
                j += 1
            tokens.append(("ID", expr[i:j]))
            i = j
            continue
        i += 1
    return tokens


def _eval_if_expr(expr: str, defines: Mapping[str, int]) -> bool:
    tokens = _tokenize_cond(expr)
    pos = 0

    def peek() -> Optional[Tuple[str, str]]:
        return tokens[pos] if pos < len(tokens) else None

    def consume() -> Tuple[str, str]:
        nonlocal pos
        tok = tokens[pos]
        pos += 1
        return tok

    def parse_or() -> int:
        val = parse_and()
        while peek() == ("OP", "||"):
            consume()
            rhs = parse_and()
            val = int(bool(val) or bool(rhs))
        return val

    def parse_and() -> int:
        val = parse_cmp()
        while peek() == ("OP", "&&"):
            consume()
            rhs = parse_cmp()
            val = int(bool(val) and bool(rhs))
        return val

    def parse_cmp() -> int:
        val = parse_add()
        tok = peek()
        if tok is not None and tok[0] == "OP" and tok[1] in ("==", "!=", "<", ">", "<=", ">="):
            op = consume()[1]
            rhs = parse_add()
            if op == "==":
                return int(val == rhs)
            if op == "!=":
                return int(val != rhs)
            if op == "<":
                return int(val < rhs)
            if op == ">":
                return int(val > rhs)
            if op == "<=":
                return int(val <= rhs)
            if op == ">=":
                return int(val >= rhs)
        return val

    def parse_add() -> int:
        val = parse_unary()
        while peek() is not None and peek()[0] == "OP" and peek()[1] in ("+", "-"):
            op = consume()[1]
            rhs = parse_unary()
            val = val + rhs if op == "+" else val - rhs
        return val

    def parse_unary() -> int:
        tok = peek()
        if tok == ("OP", "!"):
            consume()
            return int(not bool(parse_unary()))
        if tok == ("OP", "-"):
            consume()
            return -parse_unary()
        return parse_primary()

    def parse_primary() -> int:
        tok = peek()
        if tok is None:
            return 0
        if tok == ("OP", "("):
            consume()
            val = parse_or()
            if peek() == ("OP", ")"):
                consume()
            return val
        consume()
        kind, text = tok
        if kind == "NUM":
            return int(text, 10)
        if kind == "ID":
            if text == "true":
                return 1
            if text == "false":
                return 0
            return int(defines.get(text, 0))
        return 0

    return bool(parse_or())


def _step_preproc_cond(
    stripped: str,
    cond_stack: List[Tuple[bool, bool]],
    defines: Mapping[str, int],
) -> bool:
    """Update cond_stack if stripped is #if/#ifdef/#ifndef/#elif/#else/#endif. Returns True if handled."""
    if stripped.startswith("#if "):
        parent_active = cond_stack[-1][0] if cond_stack else True
        taken = parent_active and _eval_if_expr(stripped[4:], defines)
        cond_stack.append((taken, taken))
        return True
    if stripped.startswith("#ifdef "):
        parent_active = cond_stack[-1][0] if cond_stack else True
        name = stripped[7:].strip()
        taken = parent_active and (name in defines)
        cond_stack.append((taken, taken))
        return True
    if stripped.startswith("#ifndef "):
        parent_active = cond_stack[-1][0] if cond_stack else True
        name = stripped[8:].strip()
        taken = parent_active and (name not in defines)
        cond_stack.append((taken, taken))
        return True
    if stripped.startswith("#elif "):
        if cond_stack:
            parent_active = cond_stack[-2][0] if len(cond_stack) >= 2 else True
            _, already_taken = cond_stack[-1]
            if parent_active and not already_taken:
                taken = _eval_if_expr(stripped[6:], defines)
                cond_stack[-1] = (taken, taken)
            else:
                cond_stack[-1] = (False, already_taken)
        return True
    if stripped == "#else" or stripped.startswith("#else ") or stripped.startswith("#else/"):
        if cond_stack:
            parent_active = cond_stack[-2][0] if len(cond_stack) >= 2 else True
            _, already_taken = cond_stack[-1]
            cond_stack[-1] = (parent_active and not already_taken, True)
        return True
    if stripped.startswith("#endif"):
        if cond_stack:
            cond_stack.pop()
        return True
    return False


def _parse_int_literal(text: str) -> Optional[int]:
    s = text.strip()
    if not s:
        return None
    if s.startswith("$"):
        try:
            return int(s[1:], 16)
        except ValueError:
            return None
    if s.startswith("%"):
        try:
            return int(s[1:], 2)
        except ValueError:
            return None
    try:
        return int(s, 10)
    except ValueError:
        return None


def _is_overlay_segment_name(name: str, extra: str = "") -> bool:
    if name.endswith("Overlay"):
        return True
    low = extra.lower()
    return "ovl." in low or "legalui" in low


def _preprocess_lines(text: str) -> List[Tuple[int, str]]:
    cleaned = _BLOCK_COMMENT_RE.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    out: List[Tuple[int, str]] = []
    for idx, line in enumerate(cleaned.splitlines(), start=1):
        out.append((idx, _strip_line_comment(line)))
    return out


class _KickAssAnalyzer:
    def __init__(
        self,
        config: PortConfig,
        read_source: Callable[[str], Optional[str]],
        manifest_entries: Optional[Sequence[TrampolineEntry]] = None,
    ) -> None:
        self.config = config
        self.read_source = read_source
        self.manifest_entries: Tuple[TrampolineEntry, ...] = tuple(manifest_entries or ())
        self.defines: Dict[str, int] = dict(config.defines)
        self.symbol_defines: Dict[str, str] = {}
        self.overlay_segments: Set[str] = set()
        self.sym_segments: Dict[str, Set[str]] = {}
        self.sym_aliases: Dict[str, List[Tuple[str, str]]] = {}
        self.refs: List[SymbolRef] = []
        self.const_names: Set[str] = set()
        self.macros: Dict[str, Tuple[Tuple[str, ...], List[Tuple[int, str, str]]]] = {}
        self.imported_once: Set[str] = set()
        self.import_stack: List[str] = []
        self.import_errors: List[str] = []
        self.current_segment = "Default"
        self.current_label: Optional[str] = None
        self.stmt_log: List[Tuple[str, Optional[str], str]] = []
        self.label_stmt_index: Dict[Tuple[str, str], int] = {}
        self.macro_depth = 0
        self.manifest_injected = False

    def _resolve_import(self, imp_path: str, cur_file: str) -> Optional[str]:
        norm_imp = imp_path.replace("\\", "/")
        cur_parent = Path(cur_file).parent
        candidates: List[str] = []
        rel_candidate = _norm_posix(cur_parent / norm_imp)
        if rel_candidate is not None:
            candidates.append(rel_candidate)
        for libdir in self.config.libdirs:
            lib_cand = _norm_posix(Path(libdir) / norm_imp)
            if lib_cand is not None and lib_cand not in candidates:
                candidates.append(lib_cand)
        for cand in candidates:
            if self.read_source(cand) is not None:
                return cand
        return None

    def _inject_manifest_trampolines(self, inc_label: str) -> None:
        if self.manifest_injected or not self.manifest_entries:
            return
        self.manifest_injected = True
        canon = self.config.canonical_port
        if canon in PORTS and tuple(self.manifest_entries) == tuple(PORT_ENTRIES[canon]):
            rendered = gen_trampolines.render_port(canon)
            self._execute_lines(inc_label, _preprocess_lines(rendered))
        else:
            for entry in self.manifest_entries:
                if entry.is_generated:
                    self.sym_segments.setdefault(entry.name, set()).add(self.current_segment)

    def parse_file(self, rel_path: str) -> None:
        raw = self.read_source(rel_path)
        if raw is None:
            self.import_errors.append(f"{self.config.port}: missing file {rel_path}")
            return
        lines = _preprocess_lines(raw)
        has_importonce = any(line.strip() == "#importonce" for _, line in lines)
        if has_importonce:
            if rel_path in self.imported_once:
                return
            self.imported_once.add(rel_path)
        if rel_path in self.import_stack:
            return
        self.import_stack.append(rel_path)
        try:
            self._execute_lines(rel_path, lines)
        finally:
            self.import_stack.pop()

    def _apply_define(self, raw_line: str) -> bool:
        m_def = _DEFINE_RE.match(raw_line)
        if m_def:
            name = m_def.group(1)
            rhs = (m_def.group(2) or "").strip()
            val = _parse_int_literal(rhs) if rhs else 1
            if val is None and rhs in self.defines:
                val = self.defines[rhs]
            self.defines[name] = 1 if val is None else val
            if rhs and _PLAIN_IDENT_RE.match(rhs):
                self.symbol_defines[name] = rhs
            return True
        m_undef = _UNDEF_RE.match(raw_line)
        if m_undef:
            undef_name = m_undef.group(1)
            self.defines.pop(undef_name, None)
            self.symbol_defines.pop(undef_name, None)
            return True
        return False

    def _execute_lines(self, rel_path: str, lines: Sequence[Tuple[int, str]]) -> None:
        cond_stack: List[Tuple[bool, bool]] = []
        skip_fn_brace: Optional[int] = None
        brace_depth = 0
        capture_macro: Optional[Tuple[str, Tuple[str, ...], int, List[Tuple[int, str, str]]]] = None
        skip_dot_if_depth: Optional[int] = None

        for lineno, raw_line in lines:
            stripped = raw_line.strip()

            # Preprocessor conditionals outside macro capture (inside macro capture,
            # #if/#elif/#else/#endif are stored in body and evaluated on expansion).
            if capture_macro is None and _step_preproc_cond(stripped, cond_stack, self.defines):
                continue

            if capture_macro is None and cond_stack and not cond_stack[-1][0]:
                continue

            if capture_macro is not None:
                m_name, m_params, start_depth, body = capture_macro
                delta = _brace_delta(raw_line)
                new_depth = brace_depth + delta
                if new_depth <= start_depth:
                    tail = raw_line.rsplit("}", 1)[0]
                    if tail.strip():
                        body.append((lineno, rel_path, tail))
                    self.macros[m_name] = (m_params, body)
                    capture_macro = None
                    brace_depth = new_depth
                else:
                    body.append((lineno, rel_path, raw_line))
                    brace_depth = new_depth
                continue

            if skip_fn_brace is not None:
                brace_depth += _brace_delta(raw_line)
                if brace_depth <= skip_fn_brace:
                    skip_fn_brace = None
                continue

            if skip_dot_if_depth is not None:
                brace_depth += _brace_delta(raw_line)
                if brace_depth <= skip_dot_if_depth:
                    skip_dot_if_depth = None
                continue

            if _FUNC_HEADER_RE.match(raw_line):
                prev = brace_depth
                brace_depth += _brace_delta(raw_line)
                if brace_depth > prev:
                    skip_fn_brace = prev
                continue

            m_macro = _MACRO_HEADER_RE.match(raw_line)
            if m_macro:
                m_name = m_macro.group(1)
                params = tuple(p.strip() for p in m_macro.group(2).split(",") if p.strip())
                rest = m_macro.group(3)
                if "{" in rest:
                    after_open = rest.split("{", 1)[1]
                    prev = brace_depth
                    brace_depth += _brace_delta(raw_line)
                    if brace_depth <= prev:
                        inner = after_open.rsplit("}", 1)[0]
                        body = [(lineno, rel_path, inner)] if inner.strip() else []
                        self.macros[m_name] = (params, body)
                    else:
                        body = [(lineno, rel_path, after_open)] if after_open.strip() else []
                        capture_macro = (m_name, params, prev, body)
                continue

            brace_depth += _brace_delta(raw_line)

            if not stripped or stripped == "#importonce":
                continue

            if (
                stripped.startswith(".assert")
                or stripped.startswith(".print")
                or stripped.startswith(".eval")
                or stripped.startswith(".var")
                or stripped.startswith(".error")
            ):
                continue

            if stripped.startswith(".if ") or stripped.startswith(".if("):
                if "{" in stripped:
                    m_if = re.match(r"^\s*\.if\s*\(([^)]+)\)\s*\{(.*)$", stripped)
                    if m_if:
                        cond_ok = _eval_if_expr(m_if.group(1), self.defines)
                        if not cond_ok:
                            if "}" not in m_if.group(2):
                                skip_dot_if_depth = brace_depth - _brace_delta(raw_line)
                            continue
                continue

            if self._apply_define(raw_line):
                continue

            m_imp = _IMPORT_RE.match(raw_line)
            if m_imp:
                imp_path = m_imp.group(1)
                if imp_path.endswith("_trampolines.inc"):
                    resolved = self._resolve_import(imp_path, rel_path)
                    if resolved is not None:
                        self.manifest_injected = True
                        self.parse_file(resolved)
                    else:
                        self._inject_manifest_trampolines(imp_path)
                    continue
                resolved = self._resolve_import(imp_path, rel_path)
                if resolved is None:
                    if Path(imp_path).name == "version_strings.inc":
                        self.const_names.add("TITLE_VERSION_LEN")
                    else:
                        self.import_errors.append(
                            f"{self.config.port}: unresolved #import {imp_path!r} from {rel_path}:{lineno}"
                        )
                else:
                    self.parse_file(resolved)
                continue

            for stmt in _split_statements(raw_line):
                self._process_statement(rel_path, lineno, stmt.strip())

    def _expand_macro(
        self,
        params: Tuple[str, ...],
        body: Sequence[Tuple[int, str, str]],
        args: Sequence[str],
    ) -> None:
        subst = dict(zip(params, args))
        unsubstituted_params = set(params[len(args) :])
        m_cond_stack: List[Tuple[bool, bool]] = []
        for m_line, m_file, m_text in body:
            expanded = m_text
            for p_name, a_val in subst.items():
                expanded = re.sub(rf"\b{re.escape(p_name)}\b", a_val, expanded)
            stripped = expanded.strip()
            if _step_preproc_cond(stripped, m_cond_stack, self.defines):
                continue
            if m_cond_stack and not m_cond_stack[-1][0]:
                continue
            if self._apply_define(expanded):
                continue
            for m_stmt in _split_statements(expanded):
                self._process_statement(m_file, m_line, m_stmt.strip(), macro_params=unsubstituted_params)

    def _process_statement(
        self,
        rel_path: str,
        lineno: int,
        stmt: str,
        macro_params: Set[str] = frozenset(),
    ) -> None:
        if not stmt:
            return
        if (
            stmt.startswith(".assert")
            or stmt.startswith(".print")
            or stmt.startswith(".eval")
            or stmt.startswith(".var")
            or stmt.startswith(".pc")
            or stmt.startswith(".encoding")
            or stmt.startswith(".text")
            or stmt.startswith(".fill")
            or stmt.startswith(".align")
            or stmt.startswith(".import")
        ):
            return

        # Strip optional leading global or local (!name:) label(s)
        while True:
            m_lbl = _LABEL_DEF_RE.match(stmt)
            if m_lbl:
                lbl_name = m_lbl.group(1)
                self.sym_segments.setdefault(lbl_name, set()).add(self.current_segment)
                self.current_label = lbl_name
                self.label_stmt_index.setdefault((self.current_segment, lbl_name), len(self.stmt_log))
                stmt = m_lbl.group(2).strip()
                if not stmt:
                    return
                continue
            m_loc = _LOCAL_LABEL_DEF_RE.match(stmt)
            if m_loc:
                # Preserve self-modifying marker info in stmt_log before stripping
                if m_loc.group(1).strip():
                    self.stmt_log.append((self.current_segment, self.current_label, stmt.split(":", 1)[0].strip() + ":"))
                stmt = m_loc.group(1).strip()
                if not stmt:
                    return
                continue
            break

        m_segdef = _SEGDEF_RE.match(stmt)
        if m_segdef:
            seg_name = m_segdef.group(1)
            if _is_overlay_segment_name(seg_name, m_segdef.group(2)):
                self.overlay_segments.add(seg_name)
            return

        m_seg = _SEGMENT_RE.match(stmt)
        if m_seg:
            seg_name = m_seg.group(1)
            self.current_segment = seg_name
            self.current_label = None
            if seg_name.endswith("Overlay"):
                self.overlay_segments.add(seg_name)
            return

        m_const = _CONST_RE.match(stmt)
        if m_const:
            const_name = m_const.group(1)
            self.const_names.add(const_name)
            rhs = stmt.split("=", 1)[1].strip()
            val = _parse_int_literal(rhs)
            if val is not None:
                self.defines[const_name] = val
            elif _PLAIN_IDENT_RE.match(rhs):
                self.symbol_defines[const_name] = rhs
            return

        m_dot_lbl = _DOT_LABEL_RE.match(stmt)
        if m_dot_lbl:
            lbl_name = m_dot_lbl.group(1)
            rhs = m_dot_lbl.group(2).strip()
            m_plain = _PLAIN_IDENT_RE.match(rhs)
            if m_plain:
                self.sym_aliases.setdefault(lbl_name, []).append((self.current_segment, m_plain.group(1)))
            else:
                val = _parse_int_literal(rhs)
                if val is None:
                    self.sym_segments.setdefault(lbl_name, set()).add(self.current_segment)
                else:
                    self.const_names.add(lbl_name)
            return

        m_call = _MACRO_CALL_RE.match(stmt)
        if m_call:
            m_name = m_call.group(1)
            raw_args = m_call.group(2).strip()
            macro = self.macros.get(m_name)
            if macro is not None and self.macro_depth < 8:
                params, body = macro
                args = [a.strip() for a in raw_args.split(",")] if raw_args else []
                self.macro_depth += 1
                try:
                    self._expand_macro(params, body, args)
                finally:
                    self.macro_depth -= 1
            return

        stmt_idx = len(self.stmt_log)
        self.stmt_log.append((self.current_segment, self.current_label, stmt))

        # 1. Direct branches & calls (jsr / jmp / bra / conditional branch)
        m_br = _BRANCH_CALL_RE.match(stmt)
        if m_br:
            op = m_br.group(1).lower()
            sym = m_br.group(2)
            if sym not in macro_params and sym not in self.const_names:
                self.refs.append(SymbolRef(self.current_segment, sym, op, rel_path, lineno, stmt_idx, self.current_label))
            return

        # 2. Indirect calls/jumps: jmp (sym) / jmp (sym,x) / jsr (sym,x)
        m_ind = _INDIRECT_CALL_RE.match(stmt)
        if m_ind:
            op = m_ind.group(1).lower() + "_ind"
            sym = m_ind.group(2)
            if sym not in macro_params and sym not in self.const_names:
                self.refs.append(SymbolRef(self.current_segment, sym, op, rel_path, lineno, stmt_idx, self.current_label))
            return

        # 3. .word pointer directives
        m_word = _WORD_DIR_RE.match(stmt)
        if m_word:
            for m_id in _IDENT_RE.finditer(m_word.group(1)):
                sym = m_id.group(1)
                if sym not in macro_params and sym not in self.const_names:
                    self.refs.append(SymbolRef(self.current_segment, sym, ".word", rel_path, lineno, stmt_idx, self.current_label))
            return

        # 4. .byte <sym / >sym pointer table directives
        m_byte = _BYTE_DIR_RE.match(stmt)
        if m_byte:
            for item in m_byte.group(1).split(","):
                item_s = item.strip()
                if item_s.startswith("<") or item_s.startswith(">"):
                    m_id = _IDENT_RE.search(item_s[1:])
                    if m_id:
                        sym = m_id.group(1)
                        if sym not in macro_params and sym not in self.const_names:
                            self.refs.append(SymbolRef(self.current_segment, sym, ".byte_hl", rel_path, lineno, stmt_idx, self.current_label))
            return

        # 5. Immediate/expression hi/lo byte (<sym / >sym)
        found_hl = False
        for m_hl in _HI_LO_RE.finditer(stmt):
            sym = m_hl.group(1)
            if sym not in macro_params and sym not in self.const_names:
                self.refs.append(SymbolRef(self.current_segment, sym, "addr_hl", rel_path, lineno, stmt_idx, self.current_label))
                found_hl = True
        if found_hl:
            return

        # 6. Non-branch memory operands (lda/sta/ldx/ldy/cmp/adc/sbc/inc/dec/etc.)
        m_mem = _MEM_OP_RE.match(stmt)
        if m_mem:
            op = m_mem.group(1).lower()
            operand = m_mem.group(2).strip()
            if not operand.startswith("#"):
                for m_id in _IDENT_RE.finditer(operand):
                    sym = m_id.group(1)
                    if sym.lower() in _CPU_REG_TOKENS:
                        continue
                    if sym not in macro_params and sym not in self.const_names:
                        self.refs.append(SymbolRef(self.current_segment, sym, op, rel_path, lineno, stmt_idx, self.current_label))


def _norm_posix(path: Path) -> Optional[str]:
    parts: List[str] = []
    for part in path.as_posix().split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if not parts:
                return None
            parts.pop()
        else:
            parts.append(part)
    return "/".join(parts)


def analyze_port(
    config: PortConfig,
    read_source: Callable[[str], Optional[str]],
    manifest_entries: Optional[Sequence[TrampolineEntry]] = None,
) -> PortAnalysis:
    analyzer = _KickAssAnalyzer(config, read_source, manifest_entries=manifest_entries)
    analyzer.parse_file(config.entry)

    # Resolve single/multi-hop `.label alias = target` into defining segments
    resolved_segments: Dict[str, Set[str]] = {k: set(v) for k, v in analyzer.sym_segments.items()}
    for _ in range(4):
        changed = False
        for alias_name, defs in analyzer.sym_aliases.items():
            target_set = resolved_segments.setdefault(alias_name, set())
            for seg, target_sym in defs:
                if target_sym in resolved_segments and resolved_segments[target_sym]:
                    before = len(target_set)
                    target_set.update(resolved_segments[target_sym])
                    if len(target_set) != before:
                        changed = True
                elif target_sym in analyzer.const_names:
                    analyzer.const_names.add(alias_name)
                else:
                    before = len(target_set)
                    target_set.add(seg)
                    if len(target_set) != before:
                        changed = True
        if not changed:
            break

    return PortAnalysis(
        port=config.port,
        overlay_segments=analyzer.overlay_segments,
        sym_segments=resolved_segments,
        sym_aliases=analyzer.sym_aliases,
        refs=analyzer.refs,
        const_names=analyzer.const_names,
        defines=dict(analyzer.defines),
        symbol_defines=dict(analyzer.symbol_defines),
        import_errors=analyzer.import_errors,
        stmt_log=tuple(analyzer.stmt_log),
        label_stmt_index=dict(analyzer.label_stmt_index),
        manifest_entries=tuple(analyzer.manifest_entries),
    )


_SWAP_STORE_RE = re.compile(r"^\s*st[axy]\s+([A-Za-z_][A-Za-z0-9_]*)\s*\+\s*[12]\b", re.IGNORECASE)
_SELF_MOD_LOCAL_RE = re.compile(r"^\s*st[axy]\s+(![A-Za-z0-9_]+)\+\s*\+\s*[12]\b", re.IGNORECASE)
_DEFERRED_PTR_STORE_RE = re.compile(r"^\s*st[axy]\s+([A-Za-z_][A-Za-z0-9_]*)\b", re.IGNORECASE)
_IMM_OVL_LOAD_RE = re.compile(r"^\s*ld[axy]\s+#([A-Za-z0-9_]+)(?:\s*-\s*1)?\b", re.IGNORECASE)
_LOCAL_BRANCH_RE = re.compile(
    r"^\s*(?:bra|jmp|bcc|bcs|beq|bne|bmi|bpl|bvc|bvs)\s+![A-Za-z0-9_]+[+-]?\s*$",
    re.IGNORECASE,
)
_TABLE_LOAD_RE = re.compile(r"^\s*ld[axy]\s+([A-Za-z_][A-Za-z0-9_]*)\b", re.IGNORECASE)
_TERMINATOR_OP_RE = re.compile(r"^\s*(?:rts|rti)\b", re.IGNORECASE)


def _is_resident_sym(sym: str, analysis: PortAnalysis) -> bool:
    segs = analysis.sym_segments.get(sym, set())
    return any(s not in analysis.overlay_segments for s in segs)


def _resolve_ovl_token(tok: str, analysis: PortAnalysis) -> Optional[str]:
    cur = tok
    for _ in range(4):
        if cur in OVL_CONST_TO_SEGMENT:
            return OVL_CONST_TO_SEGMENT[cur]
        if cur in analysis.defines:
            val_str = str(analysis.defines[cur])
            if val_str in OVL_CONST_TO_SEGMENT:
                return OVL_CONST_TO_SEGMENT[val_str]
        nxt = analysis.symbol_defines.get(cur)
        if not nxt or nxt == cur:
            break
        cur = nxt
    return None


def _window_targets_swap_dispatcher(
    start_idx: int,
    segment: str,
    target_overlay: str,
    analysis: PortAnalysis,
    allow_local_stub: bool = True,
    max_steps: int = 18,
) -> bool:
    """Return True if statements starting at start_idx pass args straight to a resident swap dispatcher."""
    pending_dispatcher: Optional[str] = None
    staged_ovl: Optional[str] = None
    saw_local_branch = False
    limit = min(len(analysis.stmt_log), start_idx + max_steps)
    for idx in range(start_idx, limit):
        seg, _lbl, stmt = analysis.stmt_log[idx]
        if seg != segment:
            break
        if stmt.startswith("!") and stmt.endswith(":"):
            continue
        if _LOCAL_BRANCH_RE.match(stmt):
            saw_local_branch = True
            continue
        m_imm = _IMM_OVL_LOAD_RE.match(stmt)
        if m_imm:
            ovl_seg = _resolve_ovl_token(m_imm.group(1), analysis)
            if ovl_seg is not None:
                staged_ovl = ovl_seg
            continue
        m_st = _SWAP_STORE_RE.match(stmt)
        if m_st:
            patch = m_st.group(1)
            patch_info = _SWAP_PATCH_TARGETS.get(patch)
            if (
                patch_info is not None
                and patch_info[1] == target_overlay
                and _is_resident_sym(patch, analysis)
                and _is_resident_sym(patch_info[0], analysis)
            ):
                pending_dispatcher = patch_info[0]
            continue
        # Fallthrough into a direct swap dispatcher label (e.g. hal_player_recalc_pflags -> modal_swap_dispatch:)
        if idx > start_idx and _lbl and _SWAP_DIRECT_DISPATCHERS.get(_lbl) == target_overlay:
            return True
        if idx > start_idx and _lbl in _GENERIC_OVL_DISPATCHERS and staged_ovl == target_overlay:
            return True
        m_br = _BRANCH_CALL_RE.match(stmt)
        if m_br:
            op = m_br.group(1).lower()
            dest = m_br.group(2)
            if op in ("jsr", "jmp", "bra", "bne", "beq"):
                if pending_dispatcher is not None and dest == pending_dispatcher:
                    return True
                if (
                    pending_dispatcher is None
                    and _SWAP_DIRECT_DISPATCHERS.get(dest) == target_overlay
                    and _is_resident_sym(dest, analysis)
                ):
                    return True
                if pending_dispatcher is None and dest in _GENERIC_OVL_DISPATCHERS and staged_ovl == target_overlay:
                    return True
                if allow_local_stub and pending_dispatcher is None and op in ("jsr", "jmp", "bra"):
                    stub_idx = analysis.label_stmt_index.get((segment, dest))
                    if stub_idx is not None and _window_targets_swap_dispatcher(
                        stub_idx,
                        segment,
                        target_overlay,
                        analysis,
                        allow_local_stub=False,
                    ):
                        return True
                if op in ("jsr", "jmp", "bra"):
                    return False
            return False
        if _TERMINATOR_OP_RE.match(stmt):
            if saw_local_branch:
                continue
            break
        if stmt.startswith("."):
            break
    return False


def _table_targets_swap_dispatcher(
    table_label: str,
    segment: str,
    target_overlay: str,
    analysis: PortAnalysis,
) -> bool:
    """Return True if a .byte pointer table in segment feeds a matching resident swap dispatcher."""
    for idx, (seg, _lbl, stmt) in enumerate(analysis.stmt_log):
        if seg != segment:
            continue
        m_ld = _TABLE_LOAD_RE.match(stmt)
        if m_ld and m_ld.group(1) == table_label:
            if _window_targets_swap_dispatcher(idx + 1, segment, target_overlay, analysis, max_steps=12):
                return True
    return False


def _is_safe_swap_dispatch_ref(
    ref: SymbolRef,
    other_ovls: Tuple[str, ...],
    analysis: PortAnalysis,
) -> bool:
    if len(other_ovls) != 1 or ref.stmt_index < 0:
        return False
    target_overlay = other_ovls[0]
    if ref.kind == "addr_hl":
        return _window_targets_swap_dispatcher(ref.stmt_index + 1, ref.segment, target_overlay, analysis)
    if ref.kind == ".byte_hl" and ref.owner_label:
        return _table_targets_swap_dispatcher(ref.owner_label, ref.segment, target_overlay, analysis)
    return False


def _is_deferred_resident_ptr_store(ref: SymbolRef, analysis: PortAnalysis) -> bool:
    """Return True when resident code only stores <sym/>sym into a resident pointer variable
    (e.g. pm_active_name_lo/hi) without dereferencing or calling an unguarded consumer."""
    if ref.kind != "addr_hl" or ref.stmt_index < 0 or ref.segment in analysis.overlay_segments:
        return False
    limit = min(len(analysis.stmt_log), ref.stmt_index + 4)
    for idx in range(ref.stmt_index + 1, limit):
        seg, lbl, stmt = analysis.stmt_log[idx]
        if seg != ref.segment or lbl != ref.owner_label:
            break
        m_st = _DEFERRED_PTR_STORE_RE.match(stmt)
        if m_st:
            dst = m_st.group(1)
            # Direct store into named state variable (not zp_ptr* immediate dereference)
            if not dst.startswith("zp_ptr") and dst not in _SWAP_PATCH_TARGETS:
                return True
            return False
        if _IMM_OVL_LOAD_RE.match(stmt):
            continue
        break
    return False


def _build_non_overlay_safety_checker(
    analysis: PortAnalysis,
) -> Callable[[SymbolRef, Tuple[str, ...]], bool]:
    tramp_by_name: Dict[str, TrampolineEntry] = {e.name: e for e in analysis.manifest_entries}

    # Index statements per (segment, global_label)
    routine_indices: Dict[Tuple[str, str], List[int]] = {}
    for idx, (seg, lbl, _stmt) in enumerate(analysis.stmt_log):
        if lbl:
            routine_indices.setdefault((seg, lbl), []).append(idx)

    # Reverse call/reference graph across the port (propagating through aliases)
    callers_of: Dict[str, List[SymbolRef]] = {}
    for rf in analysis.refs:
        callers_of.setdefault(rf.symbol, []).append(rf)
    for alias_name, defs in analysis.sym_aliases.items():
        if alias_name in callers_of:
            for _seg, target_sym in defs:
                callers_of.setdefault(target_sym, []).extend(callers_of[alias_name])

    def _prefix_loads_overlay(seg: str, lbl: str, upto_idx: int, target_ovl: str) -> bool:
        """Check if statements in (seg, lbl) prior to upto_idx explicitly map target_ovl,
        or if upto_idx is a self-modifying JSR placeholder patched before overlay_load."""
        indices = routine_indices.get((seg, lbl), ())
        if not indices:
            return False
        start_idx = indices[0]
        candidate_ovls: Set[str] = set()
        mapped_ovls: Set[str] = set()
        patched_locals: Set[str] = set()
        prev_local_label: Optional[str] = None

        for i in range(start_idx, min(upto_idx + 1, len(analysis.stmt_log))):
            s_seg, _s_lbl, stmt = analysis.stmt_log[i]
            if s_seg != seg:
                break
            if stmt.startswith("!") and stmt.endswith(":"):
                prev_local_label = stmt[:-1]
                continue
            if i == upto_idx:
                if prev_local_label and prev_local_label in patched_locals:
                    return True
                return target_ovl in mapped_ovls
            m_sm = _SELF_MOD_LOCAL_RE.match(stmt)
            if m_sm:
                patched_locals.add(m_sm.group(1))
                continue
            if target_ovl == "LegalOverlay" and re.match(r"^\s*ld[axy]\s+cart_is_legal\b", stmt, re.IGNORECASE):
                mapped_ovls.add("LegalOverlay")
                continue
            m_imm = _IMM_OVL_LOAD_RE.match(stmt)
            if m_imm:
                ovl_seg = _resolve_ovl_token(m_imm.group(1), analysis)
                if ovl_seg is not None:
                    candidate_ovls.add(ovl_seg)
                continue
            # CX16 direct HiRAM bank switch: sta CX16_RAM_BANK_REG / sta $00
            if candidate_ovls and re.match(
                r"^\s*st[axy]\s+(?:CX16_RAM_BANK_REG|\$00)\b", stmt, re.IGNORECASE
            ):
                mapped_ovls.update(candidate_ovls)
                candidate_ovls.clear()
                if target_ovl in mapped_ovls:
                    return True
                continue
            m_br = _BRANCH_CALL_RE.match(stmt)
            if m_br and m_br.group(1).lower() in ("jsr", "jmp"):
                callee = m_br.group(2)
                for _aseg, asym in analysis.sym_aliases.get(callee, ()):
                    if asym in _OVERLAY_LOAD_CALLS:
                        callee = asym
                        break
                if callee in _OVERLAY_LOAD_CALLS:
                    mapped_ovls.update(candidate_ovls)
                    candidate_ovls.clear()
                    if target_ovl in mapped_ovls:
                        return True
                    # Dynamic overlay_load (e.g. c128_call_ovl_preserve_common) with self-mod target
                    if patched_locals:
                        return True
                    continue
                if _HELPER_LEAVES_OVERLAY_MAPPED.get(callee) == target_ovl:
                    return True
                if callee in tramp_by_name:
                    te = tramp_by_name[callee]
                    if te.kind in ("game_over_prepare_ovl", "a8_ovl_gen_loaded"):
                        if te.overlay and _resolve_ovl_token(te.overlay, analysis) == target_ovl:
                            return True
        return target_ovl in mapped_ovls

    def _routine_entered_with_overlay(lbl: str, target_ovl: str) -> bool:
        if lbl in tramp_by_name:
            te = tramp_by_name[lbl]
            if te.overlay and _resolve_ovl_token(te.overlay, analysis) == target_ovl:
                return True
            for tgt in te.all_targets:
                if target_ovl in analysis.sym_segments.get(tgt, set()):
                    return True
        if _SWAP_DIRECT_DISPATCHERS.get(lbl) == target_ovl:
            return True
        return False

    def _callers_guarantee_overlay(
        seg: str,
        lbl: Optional[str],
        target_ovl: str,
        seen: FrozenSet[Tuple[str, str]] = frozenset(),
    ) -> bool:
        if seg == target_ovl:
            return True
        if not lbl or (seg, lbl) in seen or len(seen) >= 5:
            return False
        if _routine_entered_with_overlay(lbl, target_ovl):
            return True
        # Legal viewer transport callbacks in platforms/*/legal.s & cartridge_copy.s
        # are invoked exclusively while LegalOverlay is mapped at LEGAL_BASE.
        if target_ovl == "LegalOverlay" and (lbl.startswith("legal_") or "legal" in lbl):
            return True
        incoming = [
            c for c in callers_of.get(lbl, ())
            if not (c.segment == seg and c.owner_label == lbl)
        ]
        if not incoming:
            return False
        next_seen = seen | {(seg, lbl)}
        for caller in incoming:
            if caller.segment == target_ovl:
                continue
            if caller.owner_label and caller.stmt_index >= 0:
                if _prefix_loads_overlay(caller.segment, caller.owner_label, caller.stmt_index, target_ovl):
                    continue
            if not _callers_guarantee_overlay(caller.segment, caller.owner_label, target_ovl, next_seen):
                return False
        return True

    def _is_safe(ref: SymbolRef, target_ovls: Tuple[str, ...]) -> bool:
        if _is_safe_swap_dispatch_ref(ref, target_ovls, analysis):
            return True
        if _is_deferred_resident_ptr_store(ref, analysis):
            return True
        for tovl in target_ovls:
            if ref.owner_label in tramp_by_name:
                te = tramp_by_name[ref.owner_label]
                if te.overlay and _resolve_ovl_token(te.overlay, analysis) == tovl:
                    return True
                if ref.symbol in te.all_targets:
                    return True
            if ref.owner_label and ref.stmt_index >= 0:
                if _prefix_loads_overlay(ref.segment, ref.owner_label, ref.stmt_index, tovl):
                    return True
            if _callers_guarantee_overlay(ref.segment, ref.owner_label, tovl):
                return True
        return False

    return _is_safe


def find_cross_overlay_violations(analysis: PortAnalysis) -> List[CrossOverlayViolation]:
    violations: List[CrossOverlayViolation] = []
    seen: Set[Tuple[str, str, str, str, int]] = set()
    ovl_segs = analysis.overlay_segments
    is_safe_non_overlay = _build_non_overlay_safety_checker(analysis)

    for ref in analysis.refs:
        if ref.symbol in analysis.const_names:
            continue
        def_segs = analysis.sym_segments.get(ref.symbol)
        if not def_segs:
            continue
        if ref.segment in def_segs:
            continue
        non_overlay_defs = [s for s in def_segs if s not in ovl_segs]
        if non_overlay_defs:
            continue
        other_ovls = tuple(sorted(s for s in def_segs if s != ref.segment))
        if not other_ovls:
            continue
        if ref.segment in ovl_segs:
            if _is_safe_swap_dispatch_ref(ref, other_ovls, analysis):
                continue
        else:
            if is_safe_non_overlay(ref, other_ovls):
                continue
        dedup_key = (ref.segment, ref.symbol, ref.kind, ref.file, ref.line)
        if dedup_key in seen:
            continue
        seen.add(dedup_key)
        violations.append(
            CrossOverlayViolation(
                port=analysis.port,
                caller_segment=ref.segment,
                target_segments=other_ovls,
                symbol=ref.symbol,
                ref_kind=ref.kind,
                file=ref.file,
                line=ref.line,
            )
        )
    return violations


def parse_sym_file(path: Path) -> Dict[str, int]:
    symbols: Dict[str, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = _SYM_LINE_RE.match(line.strip())
        if m:
            symbols[m.group(1)] = int(m.group(2), 16)
    return symbols


def _addr_in_ranges(addr: int, ranges: Sequence[Tuple[int, int]]) -> bool:
    return any(lo <= addr <= hi for lo, hi in ranges)


def _format_ranges(ranges: Sequence[Tuple[int, int]]) -> str:
    return ", ".join(f"${lo:04x}-${hi:04x}" for lo, hi in ranges)


# Startup init-only tail trampolines (run once before MAP_BASE/CATALOG_IDX_LOAD).
INIT_TAIL_TRAMPOLINE_RANGES: Mapping[Tuple[str, str], Tuple[int, int]] = {
    # c64/main.s:2591 tramp_reu_show_status lives in the disk init-only tail
    # (program_end..CATALOG_IDX_LOAD-1), dead before MAP_BASE ($C000) is used.
    ("c64", "tramp_reu_show_status"): (0xB000, 0xCDFF),
}


def check_sym_port(
    port: str,
    sym_path: Path,
    analysis: PortAnalysis,
    entries: Sequence[TrampolineEntry],
) -> List[str]:
    errors: List[str] = []
    if not sym_path.exists():
        return [f"{port}: missing symbol file {sym_path}"]
    sym_addrs = parse_sym_file(sym_path)
    canon_port = BASE_PORT_OF.get(port, port)
    ovl_lo, ovl_hi = OVERLAY_WINDOW[canon_port]
    valid_ranges = RESIDENT_CODE_RANGES[canon_port]

    refs_by_file: Dict[str, Set[str]] = {}
    for ref in analysis.refs:
        refs_by_file.setdefault(ref.file, set()).add(ref.symbol)

    for entry in entries:
        if not entry.is_generated and entry.name not in sym_addrs:
            continue
        if entry.name not in sym_addrs:
            errors.append(f"{port}:{entry.name}: generated trampoline symbol missing from {sym_path}")
            continue

        expected_ovl_seg = OVL_CONST_TO_SEGMENT.get(entry.overlay) if entry.overlay else None
        def_segs = analysis.sym_segments.get(entry.name, set())

        if entry.kind == "alias":
            if entry.target and entry.target in sym_addrs and sym_addrs[entry.name] != sym_addrs[entry.target]:
                errors.append(
                    f"{port}:{entry.name}: alias=${sym_addrs[entry.name]:04x} != "
                    f"{entry.target}=${sym_addrs[entry.target]:04x}"
                )
        else:
            # Custom aliases (`.label tramp_x = ovl_target`) or custom overlay-tail
            # entries explicitly authored inside their declared overlay segment
            # (e.g. `tramp_game_over_run` inside `DeathOverlay`, whose callers are
            # already verified by `find_cross_overlay_violations` to load `OVL_DEATH`
            # first) must reside inside `ovl_lo..ovl_hi`.
            is_ovl_alias = entry.name in analysis.sym_aliases and bool(def_segs) and all(
                s in analysis.overlay_segments for s in def_segs
            )
            is_declared_in_own_overlay = (
                entry.kind == "custom"
                and expected_ovl_seg is not None
                and def_segs == {expected_ovl_seg}
            )
            addr = sym_addrs[entry.name]
            if is_ovl_alias or is_declared_in_own_overlay:
                if not (ovl_lo <= addr <= ovl_hi):
                    errors.append(
                        f"{port}:{entry.name}: overlay-resident entry=${addr:04x} "
                        f"outside overlay window ${ovl_lo:04x}-${ovl_hi:04x}"
                    )
            else:
                init_range = INIT_TAIL_TRAMPOLINE_RANGES.get((port, entry.name))
                if ovl_lo <= addr <= ovl_hi:
                    errors.append(
                        f"{port}:{entry.name}: trampoline symbol landed in overlay window "
                        f"(${addr:04x} inside ${ovl_lo:04x}-${ovl_hi:04x})"
                    )
                elif init_range is not None and init_range[0] <= addr <= init_range[1]:
                    pass
                elif not _addr_in_ranges(addr, valid_ranges):
                    errors.append(
                        f"{port}:{entry.name}: trampoline symbol at invalid non-resident address "
                        f"${addr:04x} (expected in [{_format_ranges(valid_ranges)}])"
                    )

        if entry.dispatcher and entry.dispatcher not in sym_addrs:
            errors.append(f"{port}:{entry.name}: dispatcher {entry.dispatcher!r} missing from {sym_path}")

        # Multi-branch `#if/#else` custom trampolines (e.g. `atari8:tramp_ui_legal_display`
        # declaring both `cart_load_asset` and `asset_load_retry`) compile only the targets
        # referenced in the active preprocessor branch of `entry.owner_file`.
        active_targets = entry.all_targets
        if entry.kind == "custom" and len(entry.all_targets) > 1 and entry.owner_file:
            owner_refs = refs_by_file.get(entry.owner_file, set())
            filtered = tuple(t for t in entry.all_targets if t in owner_refs or t in analysis.sym_segments)
            if filtered:
                active_targets = filtered

        for tgt in active_targets:
            if tgt not in sym_addrs:
                errors.append(f"{port}:{entry.name}: target {tgt!r} missing from {sym_path}")
                continue
            tgt_addr = sym_addrs[tgt]
            if entry.overlay:
                tgt_segs = analysis.sym_segments.get(tgt, set())
                if expected_ovl_seg and expected_ovl_seg in tgt_segs:
                    if not (ovl_lo <= tgt_addr <= ovl_hi):
                        errors.append(
                            f"{port}:{entry.name}: overlay target {tgt}=${tgt_addr:04x} "
                            f"outside overlay window ${ovl_lo:04x}-${ovl_hi:04x} ({expected_ovl_seg})"
                        )
    return errors


def _repo_reader(repo_root: Path) -> Callable[[str], Optional[str]]:
    def _read(rel_path: str) -> Optional[str]:
        p = repo_root / rel_path
        if p.is_file():
            return p.read_text(encoding="utf-8")
        return None

    return _read


def run_selftest() -> int:
    import tempfile

    def _make_reader(files: Mapping[str, str]) -> Callable[[str], Optional[str]]:
        return lambda rel: files.get(rel)

    cfg = PortConfig(
        port="testport",
        entry="platforms/test/main.s",
        defines={"TESTPORT": 1},
        libdirs=("core/6502", "platforms/test"),
    )

    # 1. Clean: resident trampoline + explicit overlay_load + co-executed helper + intra-overlay + dual-defined
    clean_files = {
        "platforms/test/main.s": "\n".join([
            ".segmentdef TownOverlay [outPrg=\"ovl.town\", start=$e000]",
            ".segmentdef SpellOverlay [outPrg=\"ovl.spell\", start=$e000]",
            ".segment Default",
            "overlay_load: rts",
            "tramp_spell_fn:",
            "    lda #OVL_SPELL",
            "    jsr overlay_load",
            "    jmp spell_fn",
            "town_coexec_helper:",
            "    lda town_scratch",
            "    rts",
            ".assert \"town bounds\", town_entry >= $e000 && spell_fn >= $e000, true",
            ".segment TownOverlay",
            "town_entry:",
            "    jsr tramp_spell_fn",
            "    jsr town_local",
            "    jsr town_coexec_helper",
            "    jsr shared_helper",
            "town_local:",
            "    rts",
            "town_scratch: .byte 0",
            "#import \"shared.s\"",
            ".segment SpellOverlay",
            "spell_fn:",
            "    jsr shared_helper",
            "    rts",
            "#import \"shared.s\"",
        ]),
        "core/6502/shared.s": "shared_helper:\n    rts\n",
    }
    res_clean = analyze_port(cfg, _make_reader(clean_files))
    assert not res_clean.import_errors, res_clean.import_errors
    v_clean = find_cross_overlay_violations(res_clean)
    assert not v_clean, [v.format() for v in v_clean]

    # 2. C5b Violation: jsr / jmp / bra / bne / .word / <# / ># AND lda / sta / sbc / inc across overlays
    bad_files = {
        "platforms/test/main.s": "\n".join([
            ".segmentdef TownOverlay [outPrg=\"ovl.town\", start=$e000]",
            ".segmentdef DeathOverlay [outPrg=\"ovl.death\", start=$e000]",
            ".macro BadSeg() {",
            "    .segment TownOverlay",
            "}",
            ":BadSeg()",
            "town_caller:",
            "    jsr death_helper",
            "    jmp death_tail",
            "    bra death_branch_target",
            "    bne death_cond_target",
            "    lda #<death_table",
            "    ldy #>death_table",
            "    lda death_table,x",
            "    sta death_scratch",
            "    inc death_scratch",
            "    .word death_vec",
            ".segment DeathOverlay",
            "death_helper: rts",
            "death_tail: rts",
            "death_branch_target: rts",
            "death_cond_target: rts",
            "death_table: .byte 0",
            "death_scratch: .byte 0",
            "death_vec: .byte 0",
        ]),
    }
    res_bad = analyze_port(cfg, _make_reader(bad_files))
    v_bad = find_cross_overlay_violations(res_bad)
    found_syms = {(v.caller_segment, v.target_segments, v.symbol, v.ref_kind) for v in v_bad}
    expected = {
        ("TownOverlay", ("DeathOverlay",), "death_helper", "jsr"),
        ("TownOverlay", ("DeathOverlay",), "death_tail", "jmp"),
        ("TownOverlay", ("DeathOverlay",), "death_branch_target", "bra"),
        ("TownOverlay", ("DeathOverlay",), "death_cond_target", "bne"),
        ("TownOverlay", ("DeathOverlay",), "death_table", "addr_hl"),
        ("TownOverlay", ("DeathOverlay",), "death_table", "lda"),
        ("TownOverlay", ("DeathOverlay",), "death_scratch", "sta"),
        ("TownOverlay", ("DeathOverlay",), "death_scratch", "inc"),
        ("TownOverlay", ("DeathOverlay",), "death_vec", ".word"),
    }
    assert found_syms == expected, f"Expected {expected}, got {found_syms}"

    # 3. C5a Violation: unguarded non-overlay (Default / RuntimeBanked / A2PlaySlot) -> overlay call & mem access
    res_to_ovl_files = {
        "platforms/test/main.s": "\n".join([
            ".segmentdef TownOverlay [outPrg=\"ovl.town\", start=$e000]",
            ".segmentdef SpellOverlay [outPrg=\"ovl.spell\", start=$e000]",
            ".segmentdef RuntimeBanked [outPrg=\"bank\", start=$f000]",
            ".segment Default",
            "overlay_load: rts",
            "main_loop:",
            "    jsr unguarded_spell_fn",       # BUG: Default calling SpellOverlay without overlay_load
            "    lda spell_only_var",           # BUG: Default reading SpellOverlay variable directly
            "    jsr leaky_helper",
            "    lda #OVL_TOWN",
            "    jsr overlay_load",
            "    jsr unguarded_spell_fn",       # BUG: loaded OVL_TOWN, but calling SpellOverlay!
            "    jsr town_ok_fn",               # OK: OVL_TOWN was just loaded!
            "    rts",
            "leaky_helper:",
            "    sta town_only_scratch",        # BUG: called from main_loop without TownOverlay mapped!
            "    rts",
            ".segment RuntimeBanked",
            "banked_bad_caller:",
            "    jmp unguarded_spell_fn",       # BUG: RuntimeBanked jumping to SpellOverlay!
            ".segment TownOverlay",
            "town_ok_fn: rts",
            "town_only_scratch: .byte 0",
            ".segment SpellOverlay",
            "unguarded_spell_fn: rts",
            "spell_only_var: .byte 0",
        ]),
    }
    res_r2o = analyze_port(cfg, _make_reader(res_to_ovl_files))
    v_r2o = {(v.caller_segment, v.symbol, v.ref_kind, v.line) for v in find_cross_overlay_violations(res_r2o)}
    expected_r2o = {
        ("Default", "unguarded_spell_fn", "jsr", 7),
        ("Default", "spell_only_var", "lda", 8),
        ("Default", "unguarded_spell_fn", "jsr", 12),
        ("Default", "town_only_scratch", "sta", 16),
        ("RuntimeBanked", "unguarded_spell_fn", "jmp", 20),
    }
    assert v_r2o == expected_r2o, f"Expected {expected_r2o}, got {v_r2o}"

    # 4. C5c Violation: #if/#elif/#else/#endif inside .macro must NOT leak inactive resident defs!
    macro_cond_files = {
        "platforms/test/main.s": "\n".join([
            "#define USE_OVERLAY_PLACEMENT 1",
            ".segmentdef TownOverlay [outPrg=\"ovl.town\", start=$e000]",
            ".segmentdef SpellOverlay [outPrg=\"ovl.spell\", start=$e000]",
            ".macro SelectTargetSeg() {",
            "#if USE_OVERLAY_PLACEMENT",
            "    .segment SpellOverlay",
            "#else",
            "    .segment Default",
            "#endif",
            "}",
            ":SelectTargetSeg()",
            "macro_placed_fn: rts",
            ".segment TownOverlay",
            "town_bad:",
            "    jsr macro_placed_fn",
        ]),
    }
    res_mc = analyze_port(cfg, _make_reader(macro_cond_files))
    assert res_mc.sym_segments["macro_placed_fn"] == {"SpellOverlay"}, res_mc.sym_segments["macro_placed_fn"]
    v_mc = find_cross_overlay_violations(res_mc)
    assert len(v_mc) == 1 and v_mc[0].symbol == "macro_placed_fn", v_mc

    # 5. C5d + C5e: check_sym_port catches trampolines in MAP_BASE ($C000), I/O ($D000), overlay ($E000),
    #    and vectors ($FFFA), while accepting Default ($0900) and RuntimeBanked ($F100), on c64 & c64-cart!
    sym_entries = (
        TrampolineEntry(port="c64", name="tramp_ok_default", kind="ovl_direct", overlay="OVL_SPELL", target="spell_fn"),
        TrampolineEntry(port="c64", name="tramp_ok_banked", kind="ovl_direct", overlay="OVL_SPELL", target="spell_fn"),
        TrampolineEntry(port="c64", name="tramp_bad_map", kind="ovl_direct", overlay="OVL_SPELL", target="spell_fn"),
        TrampolineEntry(port="c64", name="tramp_bad_io", kind="ovl_direct", overlay="OVL_SPELL", target="spell_fn"),
        TrampolineEntry(port="c64", name="tramp_bad_ovl", kind="ovl_direct", overlay="OVL_SPELL", target="spell_fn"),
        TrampolineEntry(port="c64", name="tramp_bad_vec", kind="ovl_direct", overlay="OVL_SPELL", target="spell_fn"),
    )
    cart_cfg = PortConfig(
        port="c64-cart",
        base_port="c64",
        entry="platforms/test/main.s",
        defines={"C64_CARTRIDGE": 1},
        libdirs=("platforms/test",),
    )
    cart_files = {
        "platforms/test/main.s": "\n".join([
            ".segmentdef SpellOverlay [outPrg=\"ovl.spell\", start=$e000]",
            ".segmentdef TownOverlay [outPrg=\"ovl.town\", start=$e000]",
            "#ifdef C64_CARTRIDGE",
            ".segment TownOverlay",
            "cart_bad_caller: jsr spell_fn",
            "#endif",
            ".segment SpellOverlay",
            "spell_fn: rts",
        ])
    }
    res_cart = analyze_port(cart_cfg, _make_reader(cart_files), manifest_entries=sym_entries)
    v_cart = find_cross_overlay_violations(res_cart)
    assert len(v_cart) == 1 and v_cart[0].port == "c64-cart" and v_cart[0].symbol == "spell_fn", v_cart

    with tempfile.TemporaryDirectory() as td:
        sym_file = Path(td) / "main.sym"
        sym_file.write_text(
            "\n".join([
                ".label tramp_ok_default=$0900",
                ".label tramp_ok_banked=$f100",
                ".label tramp_bad_map=$c100",
                ".label tramp_bad_io=$d400",
                ".label tramp_bad_ovl=$e123",
                ".label tramp_bad_vec=$fffa",
                ".label spell_fn=$e200",
            ]) + "\n",
            encoding="utf-8",
        )
        sym_errs = check_sym_port("c64-cart", sym_file, res_cart, sym_entries)
        assert len(sym_errs) == 4, sym_errs
        assert any("tramp_bad_map" in e for e in sym_errs)
        assert any("tramp_bad_io" in e for e in sym_errs)
        assert any("tramp_bad_ovl" in e for e in sym_errs)
        assert any("tramp_bad_vec" in e for e in sym_errs)

        # Verify custom overlay-resident tail, c64 init-tail, and #if/#else active-branch targets
        cond_cfg = PortConfig(port="atari8", entry="platforms/atari8/main.s", defines={"ATARI8": 1}, libdirs=("platforms/atari8",))
        cond_files = {
            "platforms/atari8/main.s": "\n".join([
                ".segmentdef DeathOverlay [outPrg=\"ovl.dth\", start=$e000]",
                ".segment Default",
                "#import \"legal.s\"",
                ".segment DeathOverlay",
                "tramp_game_over_run: jsr score_calculate ; rts",
                "score_calculate: rts",
            ]),
            "platforms/atari8/legal.s": "\n".join([
                "#if ATARI8_CARTRIDGE",
                "tramp_ui_legal_display: jsr cart_load_asset ; jmp legal_viewer",
                "#else",
                "tramp_ui_legal_display: jsr asset_load_retry ; jmp legal_viewer",
                "#endif",
            ]),
        }
        cond_entries = (
            TrampolineEntry(port="atari8", name="tramp_game_over_run", kind="custom", overlay="OVL_DEATH", targets=("score_calculate",), owner_file="platforms/atari8/main.s", reason="death tail"),
            TrampolineEntry(port="atari8", name="tramp_ui_legal_display", kind="custom", targets=("cart_load_asset", "asset_load_retry", "legal_viewer"), owner_file="platforms/atari8/legal.s", reason="dual legal"),
        )
        res_cond = analyze_port(cond_cfg, _make_reader(cond_files), manifest_entries=cond_entries)
        cond_sym = Path(td) / "atari8.sym"
        cond_sym.write_text(
            ".label tramp_game_over_run=$e120\n"
            ".label score_calculate=$e200\n"
            ".label tramp_ui_legal_display=$f100\n"
            ".label asset_load_retry=$2100\n"
            ".label legal_viewer=$e300\n",
            encoding="utf-8",
        )
        assert check_sym_port("atari8", cond_sym, res_cond, cond_entries) == []

        c64_init_entries = (
            TrampolineEntry(port="c64", name="tramp_reu_show_status", kind="custom", target="reu_show_status_banked", owner_file="platforms/commodore/c64/main.s", reason="init tail"),
        )
        c64_sym = Path(td) / "c64.sym"
        c64_sym.write_text(".label tramp_reu_show_status=$c059\n.label reu_show_status_banked=$f400\n", encoding="utf-8")
        assert check_sym_port("c64", c64_sym, res_cart, c64_init_entries) == []
        assert len(check_sym_port("c64-cart", c64_sym, res_cart, c64_init_entries)) == 1

    # 6. Resident swap-call target staging & version_strings.inc / missing #import checks
    swap_files = {
        "platforms/test/main.s": "\n".join([
            "#import \"build/version_strings.inc\"",
            ".segmentdef ItemActionsOverlay [outPrg=\"ovl.items\", start=$e000]",
            ".segmentdef ChestOverlay [outPrg=\"ovl.chest\", start=$e000]",
            ".segmentdef SpellOverlay [outPrg=\"ovl.spell\", start=$e000]",
            ".segment Default",
            "overlay_load: rts",
            "chest_dispatch: lda #OVL_CHEST ; jsr overlay_load ; rts",
            "tramp_spell_call_items: lda #OVL_SPELL ; jsr overlay_load ; jsr tsci_target ; rts",
            "tsci_target: jsr $0000 ; rts",
            "msg_print_ay: rts",
            ".segment ItemActionsOverlay",
            "valid_chest_call:",
            "    lda #<chest_fn",
            "    ldy #>chest_fn",
            "    jmp chest_dispatch",
            "valid_spell_call:",
            "    lda #<spell_fn",
            "    sta tsci_target+1",
            "    lda #>spell_fn",
            "    sta tsci_target+2",
            "    jsr tramp_spell_call_items",
            "wrong_overlay_swap:",
            "    lda #<spell_fn",
            "    ldy #>spell_fn",
            "    jmp chest_dispatch",
            "unsafe_str_ptr:",
            "    lda #<chest_str",
            "    ldy #>chest_str",
            "    jsr msg_print_ay",
            ".segment ChestOverlay",
            "chest_fn: rts",
            "chest_str: .byte 0",
            ".segment SpellOverlay",
            "spell_fn: rts",
        ])
    }
    res_swap = analyze_port(cfg, _make_reader(swap_files))
    assert "TITLE_VERSION_LEN" in res_swap.const_names
    v_swap = {(v.symbol, v.ref_kind) for v in find_cross_overlay_violations(res_swap)}
    assert v_swap == {("spell_fn", "addr_hl"), ("chest_str", "addr_hl")}, v_swap

    missing_files = {"platforms/test/main.s": "#import \"nonexistent_foo.s\"\n"}
    res_missing = analyze_port(cfg, _make_reader(missing_files))
    assert any("nonexistent_foo.s" in e for e in res_missing.import_errors), res_missing.import_errors

    print(
        "check_overlay_calls selftest passed "
        "(C5a non-ovl->ovl, C5b mem ops, C5c macro #if, C5d sym ranges, C5e cart configs, swap dispatchers)"
    )
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Static pre-build and post-build cross-overlay & resident->overlay checker for all 7 Moria8 ports and 5 cartridges."
    )
    parser.add_argument(
        "--port",
        choices=ALL_TARGETS,
        help="Check only one port or cartridge target (default: all 7 ports + 5 cartridges)",
    )
    parser.add_argument(
        "--check-sym",
        action="store_true",
        help="Also validate trampoline addresses & targets against build/<target>/main.sym",
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="Run built-in unit self-tests",
    )
    args = parser.parse_args(argv)

    if args.selftest:
        return run_selftest()

    target_ports = (args.port,) if args.port else ALL_TARGETS
    reader = _repo_reader(REPO_ROOT)

    total_errors = 0
    sym_checked = 0
    for port in target_ports:
        cfg = PORT_CONFIGS[port]
        entries = PORT_ENTRIES[cfg.canonical_port]
        analysis = analyze_port(cfg, reader, manifest_entries=entries)

        if analysis.import_errors:
            for err in analysis.import_errors:
                print(f"ERROR: {err}", file=sys.stderr)
            total_errors += len(analysis.import_errors)

        violations = find_cross_overlay_violations(analysis)
        if violations:
            for viol in violations:
                print(f"ERROR: {viol.format()}", file=sys.stderr)
            total_errors += len(violations)

        if args.check_sym:
            sym_path = REPO_ROOT / "build" / port / "main.sym"
            # Disk ports are required under --check-sym; cart configs are checked when built (or when explicitly named via --port)
            if port in CART_PORTS and args.port is None and not sym_path.exists():
                continue
            sym_checked += 1
            sym_errs = check_sym_port(port, sym_path, analysis, entries)
            for err in sym_errs:
                print(f"ERROR: {err}", file=sys.stderr)
            total_errors += len(sym_errs)

    if total_errors:
        print(
            f"overlay call check FAILED ({total_errors} issue(s) across {len(target_ports)} target(s))",
            file=sys.stderr,
        )
        return 1

    suffix = f" + {sym_checked} .sym" if args.check_sym else ""
    print(f"overlay call check{suffix} passed ({len(target_ports)} target(s), 0 overlay violations)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
