#!/usr/bin/env python3
"""
tools/check_overlay_calls.py
Module ownership: platform-tooling static cross-overlay call validator (Phase 3).
Validates all 7 Moria8 ports pre-build (without requiring ``build/``) by
following Kick Assembler ``#import`` graphs, conditional directives
(``#if``/``#elif``/``#else``/``#endif``), ``.segment`` switches, and segment
``.macro`` expansions from each port's ``main.s``.

Flags an error if code/data inside Overlay ``A`` references (``jsr``, ``jmp``,
``bra``, conditional branch, ``<label``/``>label``, or ``.word label``) a symbol
whose definitions in that port belong ONLY to other overlay segment(s) ``B != A``
(and NOT to resident/banked segments or Overlay ``A`` itself).

Also supports ``--check-sym`` (post-build ``build/<port>/main.sym`` verification
of generated trampoline targets) and ``--selftest`` (synthetic fixtures).
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

from trampoline_manifest import PORT_ENTRIES, PORTS, TrampolineEntry  # noqa: E402


OVERLAY_WINDOW: Dict[str, Tuple[int, int]] = {
    "apple2": (0xA400, 0xB9FF),
    "bbcmaster": (0xA800, 0xBFFF),
    "cx16": (0xA000, 0xBFFF),
    "atari8": (0xE000, 0xEFFF),
    "c64": (0xE000, 0xEFFF),
    "plus4": (0xE000, 0xEFFF),
    "c128": (0xE000, 0xEFFF),
}

RESIDENT_MAX_LIMIT: Dict[str, int] = {
    "apple2": 0xA400,    # Default < $7C00, A2PlaySlot < $A000
    "bbcmaster": 0xA800, # Default < $8000, BeebPlaySlot < $A400
    "cx16": 0xA000,      # Unified resident <= $9AFF
    "atari8": 0xFFFF,    # RuntimeBanked up to $FFFA, Default < $C100 (overlays $E000-$EFFF)
    "c64": 0xFFFF,       # RuntimeBanked at $F000-$FFFA, Default < $C000
    "plus4": 0xFFFF,     # RuntimeBanked at $F000-$FBFF
    "c128": 0xFFFF,      # RuntimeBankedCode at $F000-$FFFA
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
    # C128 numeric / C128_* aliases
    "C128_HELP_OVERLAY_ID": "HelpOverlay",
    "C128_UI_OVERLAY_ID": "UiOverlay",
    "C128_ITEMS_OVERLAY_ID": "ItemActionsOverlay",
    "C128_DISARM_OVERLAY_ID": "DisarmOverlay",
    "C128_CHEST_OVERLAY_ID": "ChestOverlay",
    "C128_HOME_OVERLAY_ID": "HomeOverlay",
    "3": "DeathOverlay",
    "10": "ChestOverlay",
    "11": "HomeOverlay",
}

# Verified resident overlay-swap dispatchers and the target overlay they page in
# before calling the staged handler pointer. Any <sym/>sym passed solely into
# these dispatchers does not dereference the target while the wrong overlay is
# mapped, whereas arbitrary <sym/>sym or dispatcher mismatches remain errors.
_SWAP_DIRECT_DISPATCHERS: Mapping[str, str] = {
    "chest_dispatch": "ChestOverlay",
}
_SWAP_PATCH_TARGETS: Mapping[str, Tuple[str, str]] = {
    "tsci_target": ("tramp_spell_call_items", "SpellOverlay"),
    "tpdi_target": ("tramp_p3_death_items", "DeathOverlay"),
}


@dataclass(frozen=True)
class PortConfig:
    port: str
    entry: str
    defines: Mapping[str, int]
    libdirs: Tuple[str, ...]


PORT_CONFIGS: Dict[str, PortConfig] = {
    "apple2": PortConfig(
        port="apple2",
        entry="platforms/apple2/main.s",
        defines={"APPLE2": 1},
        libdirs=(
            "core",
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
            "core",
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
            "core",
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
            "core",
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
        libdirs=("core", "platforms/commodore/common", "platforms/commodore/c64"),
    ),
    "plus4": PortConfig(
        port="plus4",
        entry="platforms/commodore/plus4/main.s",
        defines={"PLUS4": 1},
        libdirs=("core", "platforms/commodore/common", "platforms/commodore/c64"),
    ),
    "c128": PortConfig(
        port="c128",
        entry="platforms/commodore/c128/main.s",
        defines={"C128": 1},
        libdirs=("core", "platforms/commodore/common", "platforms/commodore/c64"),
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
    import_errors: List[str]
    stmt_log: Tuple[Tuple[str, str], ...] = ()
    label_stmt_index: Mapping[Tuple[str, str], int] = ()


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
_DOT_LABEL_RE = re.compile(r"^\s*\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$")
_MACRO_CALL_RE = re.compile(r"^\s*:([A-Za-z_][A-Za-z0-9_]*)\s*\((.*)\)\s*$")
_BRANCH_CALL_RE = re.compile(
    r"^\s*(jsr|jmp|bra|bcc|bcs|beq|bne|bmi|bpl|bvc|bvs)\s+(?!\()([A-Za-z_][A-Za-z0-9_]*)\b",
    re.IGNORECASE,
)
_HI_LO_RE = re.compile(r"#?\s*[<>]\s*\(?\s*([A-Za-z_][A-Za-z0-9_]*)\b")
_WORD_DIR_RE = re.compile(r"^\s*\.word\s+(.+)$", re.IGNORECASE)
_BYTE_DIR_RE = re.compile(r"^\s*\.byte\s+(.+)$", re.IGNORECASE)
_IDENT_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\b")
_PLAIN_IDENT_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)$")
_SYM_LINE_RE = re.compile(r"^\.label\s+([A-Za-z_][A-Za-z0-9_]*)=\$([0-9a-fA-F]+)\b")


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
        self.manifest_entries = manifest_entries
        self.defines: Dict[str, int] = dict(config.defines)
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
        self.stmt_log: List[Tuple[str, str]] = []
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

    def _inject_manifest_trampolines(self) -> None:
        if self.manifest_injected or self.manifest_entries is None:
            return
        self.manifest_injected = True
        for entry in self.manifest_entries:
            if entry.is_generated:
                self.sym_segments.setdefault(entry.name, set()).add("Default")

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

    def _execute_lines(self, rel_path: str, lines: Sequence[Tuple[int, str]]) -> None:
        cond_stack: List[Tuple[bool, bool]] = []
        skip_fn_brace: Optional[int] = None
        brace_depth = 0
        capture_macro: Optional[Tuple[str, Tuple[str, ...], int, List[Tuple[int, str, str]]]] = None
        skip_dot_if_depth: Optional[int] = None

        for lineno, raw_line in lines:
            stripped = raw_line.strip()

            # Preprocessor conditionals (#if/#elif/#else/#endif) run outside macro capture,
            # though macros are typically unconditional. Track #if inside normal code first.
            if capture_macro is None and (
                stripped.startswith("#if")
                or stripped.startswith("#elif")
                or stripped.startswith("#else")
                or stripped.startswith("#endif")
            ):
                if stripped.startswith("#if "):
                    parent_active = cond_stack[-1][0] if cond_stack else True
                    taken = parent_active and _eval_if_expr(stripped[4:], self.defines)
                    cond_stack.append((taken, taken))
                elif stripped.startswith("#ifdef "):
                    parent_active = cond_stack[-1][0] if cond_stack else True
                    name = stripped[7:].strip()
                    taken = parent_active and (name in self.defines)
                    cond_stack.append((taken, taken))
                elif stripped.startswith("#elif "):
                    if cond_stack:
                        parent_active = cond_stack[-2][0] if len(cond_stack) >= 2 else True
                        _, already_taken = cond_stack[-1]
                        if parent_active and not already_taken:
                            taken = _eval_if_expr(stripped[6:], self.defines)
                            cond_stack[-1] = (taken, taken)
                        else:
                            cond_stack[-1] = (False, already_taken)
                elif stripped == "#else" or stripped.startswith("#else ") or stripped.startswith("#else/"):
                    if cond_stack:
                        parent_active = cond_stack[-2][0] if len(cond_stack) >= 2 else True
                        _, already_taken = cond_stack[-1]
                        cond_stack[-1] = (parent_active and not already_taken, True)
                elif stripped.startswith("#endif"):
                    if cond_stack:
                        cond_stack.pop()
                continue

            if cond_stack and not cond_stack[-1][0]:
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

            # Compile-time diagnostics / assertions / expressions never execute at runtime
            if (
                stripped.startswith(".assert")
                or stripped.startswith(".print")
                or stripped.startswith(".eval")
                or stripped.startswith(".var")
                or stripped.startswith(".error")
            ):
                continue

            # Ignore non-executed compile-time .if (...) when known false (e.g., player_create cutpoints)
            if stripped.startswith(".if ") or stripped.startswith(".if("):
                # Evaluate simple equality if possible; skip inactive body block
                if "{" in stripped:
                    m_if = re.match(r"^\s*\.if\s*\(([^)]+)\)\s*\{(.*)$", stripped)
                    if m_if:
                        cond_ok = _eval_if_expr(m_if.group(1), self.defines)
                        if not cond_ok:
                            if "}" not in m_if.group(2):
                                skip_dot_if_depth = brace_depth - _brace_delta(raw_line)
                            continue
                continue

            m_def = _DEFINE_RE.match(raw_line)
            if m_def:
                name = m_def.group(1)
                rhs = (m_def.group(2) or "").strip()
                val = _parse_int_literal(rhs) if rhs else 1
                self.defines[name] = 1 if val is None else val
                continue

            m_undef = _UNDEF_RE.match(raw_line)
            if m_undef:
                self.defines.pop(m_undef.group(1), None)
                continue

            m_imp = _IMPORT_RE.match(raw_line)
            if m_imp:
                imp_path = m_imp.group(1)
                if imp_path.endswith("_trampolines.inc"):
                    self._inject_manifest_trampolines()
                    resolved = self._resolve_import(imp_path, rel_path)
                    if resolved is not None:
                        self.parse_file(resolved)
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

    def _process_statement(self, rel_path: str, lineno: int, stmt: str, macro_params: Set[str] = frozenset()) -> None:
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

        # Strip optional leading label(s)
        while True:
            m_lbl = _LABEL_DEF_RE.match(stmt)
            if not m_lbl:
                break
            lbl_name = m_lbl.group(1)
            self.sym_segments.setdefault(lbl_name, set()).add(self.current_segment)
            self.current_label = lbl_name
            self.label_stmt_index.setdefault((self.current_segment, lbl_name), len(self.stmt_log))
            stmt = m_lbl.group(2).strip()
            if not stmt:
                return

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
                subst = dict(zip(params, args))
                self.macro_depth += 1
                try:
                    for m_line, m_file, m_text in body:
                        expanded = m_text
                        for p_name, a_val in subst.items():
                            expanded = re.sub(rf"\b{re.escape(p_name)}\b", a_val, expanded)
                        for m_stmt in _split_statements(expanded):
                            self._process_statement(m_file, m_line, m_stmt.strip())
                finally:
                    self.macro_depth -= 1
            return

        if self.current_segment not in self.overlay_segments:
            return

        stmt_idx = len(self.stmt_log)
        self.stmt_log.append((self.current_segment, stmt))

        # Record symbol references from code/data inside an active overlay segment
        m_br = _BRANCH_CALL_RE.match(stmt)
        if m_br:
            op = m_br.group(1).lower()
            sym = m_br.group(2)
            if sym not in macro_params and sym not in self.const_names:
                self.refs.append(SymbolRef(self.current_segment, sym, op, rel_path, lineno, stmt_idx, self.current_label))
            return

        m_word = _WORD_DIR_RE.match(stmt)
        if m_word:
            for m_id in _IDENT_RE.finditer(m_word.group(1)):
                sym = m_id.group(1)
                if sym not in macro_params and sym not in self.const_names:
                    self.refs.append(SymbolRef(self.current_segment, sym, ".word", rel_path, lineno, stmt_idx, self.current_label))
            return

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

        for m_hl in _HI_LO_RE.finditer(stmt):
            sym = m_hl.group(1)
            if sym not in macro_params and sym not in self.const_names:
                self.refs.append(SymbolRef(self.current_segment, sym, "addr_hl", rel_path, lineno, stmt_idx, self.current_label))


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
        import_errors=analyzer.import_errors,
        stmt_log=tuple(analyzer.stmt_log),
        label_stmt_index=dict(analyzer.label_stmt_index),
    )


_SWAP_STORE_RE = re.compile(r"^\s*st[axy]\s+([A-Za-z_][A-Za-z0-9_]*)\s*\+\s*[12]\b", re.IGNORECASE)
_TABLE_LOAD_RE = re.compile(r"^\s*ld[axy]\s+([A-Za-z_][A-Za-z0-9_]*)\b", re.IGNORECASE)
_TERMINATOR_OP_RE = re.compile(r"^\s*(?:rts|rti|bra)\b", re.IGNORECASE)


def _is_resident_sym(sym: str, analysis: PortAnalysis) -> bool:
    segs = analysis.sym_segments.get(sym, set())
    return any(s not in analysis.overlay_segments for s in segs)


def _window_targets_swap_dispatcher(
    start_idx: int,
    segment: str,
    target_overlay: str,
    analysis: PortAnalysis,
    allow_local_stub: bool = True,
    max_steps: int = 8,
) -> bool:
    """Return True if statements starting at start_idx pass args straight to a resident swap dispatcher."""
    pending_dispatcher: Optional[str] = None
    limit = min(len(analysis.stmt_log), start_idx + max_steps)
    for idx in range(start_idx, limit):
        seg, stmt = analysis.stmt_log[idx]
        if seg != segment:
            break
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
        m_br = _BRANCH_CALL_RE.match(stmt)
        if m_br:
            op = m_br.group(1).lower()
            dest = m_br.group(2)
            if op in ("jsr", "jmp"):
                if pending_dispatcher is not None and dest == pending_dispatcher:
                    return True
                if (
                    pending_dispatcher is None
                    and _SWAP_DIRECT_DISPATCHERS.get(dest) == target_overlay
                    and _is_resident_sym(dest, analysis)
                ):
                    return True
                if allow_local_stub and pending_dispatcher is None:
                    stub_idx = analysis.label_stmt_index.get((segment, dest))
                    if stub_idx is not None and _window_targets_swap_dispatcher(
                        stub_idx,
                        segment,
                        target_overlay,
                        analysis,
                        allow_local_stub=False,
                    ):
                        return True
                return False
            # Allow conditional branches only if continuing straight flow is unnecessary; break on control changes
            return False
        if _TERMINATOR_OP_RE.match(stmt) or stmt.startswith("."):
            break
    return False


def _table_targets_swap_dispatcher(
    table_label: str,
    segment: str,
    target_overlay: str,
    analysis: PortAnalysis,
) -> bool:
    """Return True if a .byte pointer table in segment feeds a matching resident swap dispatcher."""
    for idx, (seg, stmt) in enumerate(analysis.stmt_log):
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


def find_cross_overlay_violations(analysis: PortAnalysis) -> List[CrossOverlayViolation]:
    violations: List[CrossOverlayViolation] = []
    seen: Set[Tuple[str, str, str, str, int]] = set()
    ovl_segs = analysis.overlay_segments

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
        if _is_safe_swap_dispatch_ref(ref, other_ovls, analysis):
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
    ovl_lo, ovl_hi = OVERLAY_WINDOW[port]
    res_max = RESIDENT_MAX_LIMIT[port]

    for entry in entries:
        if not entry.is_generated:
            continue
        if entry.name not in sym_addrs:
            errors.append(f"{port}:{entry.name}: generated trampoline symbol missing from {sym_path}")
        elif entry.kind == "alias":
            if entry.target and entry.target in sym_addrs and sym_addrs[entry.name] != sym_addrs[entry.target]:
                errors.append(
                    f"{port}:{entry.name}: alias=${sym_addrs[entry.name]:04x} != "
                    f"{entry.target}=${sym_addrs[entry.target]:04x}"
                )
        else:
            addr = sym_addrs[entry.name]
            if addr >= res_max and not (ovl_lo <= addr <= ovl_hi):
                pass
            if ovl_lo <= addr <= ovl_hi:
                errors.append(
                    f"{port}:{entry.name}: trampoline symbol landed in overlay window "
                    f"(${addr:04x} inside ${ovl_lo:04x}-${ovl_hi:04x})"
                )

        if entry.dispatcher and entry.dispatcher not in sym_addrs:
            errors.append(f"{port}:{entry.name}: dispatcher {entry.dispatcher!r} missing from {sym_path}")

        for tgt in entry.all_targets:
            if tgt not in sym_addrs:
                errors.append(f"{port}:{entry.name}: target {tgt!r} missing from {sym_path}")
                continue
            tgt_addr = sym_addrs[tgt]
            if entry.overlay:
                expected_seg = OVL_CONST_TO_SEGMENT.get(entry.overlay)
                def_segs = analysis.sym_segments.get(tgt, set())
                if expected_seg and expected_seg in def_segs:
                    if not (ovl_lo <= tgt_addr <= ovl_hi):
                        errors.append(
                            f"{port}:{entry.name}: overlay target {tgt}=${tgt_addr:04x} "
                            f"outside overlay window ${ovl_lo:04x}-${ovl_hi:04x} ({expected_seg})"
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
    def _make_reader(files: Mapping[str, str]) -> Callable[[str], Optional[str]]:
        return lambda rel: files.get(rel)

    cfg = PortConfig(
        port="testport",
        entry="platforms/test/main.s",
        defines={"TESTPORT": 1},
        libdirs=("core", "platforms/test"),
    )

    # 1. Clean: resident trampoline call + intra-overlay call + dual-defined helper + .assert ignore
    clean_files = {
        "platforms/test/main.s": "\n".join([
            ".segmentdef TownOverlay [outPrg=\"ovl.town\", start=$e000]",
            ".segmentdef SpellOverlay [outPrg=\"ovl.spell\", start=$e000]",
            ".segment Default",
            "tramp_spell_fn:",
            "    rts",
            ".assert \"town bounds\", town_entry >= $e000 && spell_fn >= $e000, true",
            ".segment TownOverlay",
            "town_entry:",
            "    jsr tramp_spell_fn",
            "    jsr town_local",
            "    jsr shared_helper",
            "town_local:",
            "    rts",
            "#import \"shared.s\"",
            ".segment SpellOverlay",
            "spell_fn:",
            "    jsr shared_helper",
            "    rts",
            "#import \"shared.s\"",
        ]),
        "core/shared.s": "shared_helper:\n    rts\n",
    }
    res_clean = analyze_port(cfg, _make_reader(clean_files))
    assert not res_clean.import_errors, res_clean.import_errors
    v_clean = find_cross_overlay_violations(res_clean)
    assert not v_clean, [v.format() for v in v_clean]

    # 2. Violation: jsr / jmp / bra / bne / .word / <# / ># across overlays
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
            "    .word death_vec",
            ".segment DeathOverlay",
            "death_helper: rts",
            "death_tail: rts",
            "death_branch_target: rts",
            "death_cond_target: rts",
            "death_table: .byte 0",
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
        ("TownOverlay", ("DeathOverlay",), "death_vec", ".word"),
    }
    assert found_syms == expected, f"Expected {expected}, got {found_syms}"

    # 3. Resident generated trampoline manifest fallback when build/trampolines does not exist
    manifest_sample = (
        TrampolineEntry(port="testport", name="tramp_gen_call", kind="ovl_direct", overlay="OVL_SPELL", target="spell_fn"),
    )
    gen_files = {
        "platforms/test/main.s": "\n".join([
            ".segmentdef TownOverlay [outPrg=\"ovl.town\", start=$e000]",
            ".segmentdef SpellOverlay [outPrg=\"ovl.spell\", start=$e000]",
            "#import \"build/trampolines/testport_trampolines.inc\"",
            ".segment TownOverlay",
            "town_entry:",
            "    jsr tramp_gen_call",
            ".segment SpellOverlay",
            "spell_fn: rts",
        ])
    }
    res_gen = analyze_port(cfg, _make_reader(gen_files), manifest_entries=manifest_sample)
    assert not res_gen.import_errors, res_gen.import_errors
    assert not find_cross_overlay_violations(res_gen)

    # 4. Resident swap-call target staging: valid passes, wrong-overlay swap or bare ptr fails
    swap_files = {
        "platforms/test/main.s": "\n".join([
            ".segmentdef ItemActionsOverlay [outPrg=\"ovl.items\", start=$e000]",
            ".segmentdef ChestOverlay [outPrg=\"ovl.chest\", start=$e000]",
            ".segmentdef SpellOverlay [outPrg=\"ovl.spell\", start=$e000]",
            ".segment Default",
            "chest_dispatch: rts",
            "tramp_spell_call_items: jsr tsci_target",
            "tsci_target: jsr $0000",
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
    v_swap = find_cross_overlay_violations(res_swap)
    found_swap = {(v.symbol, v.ref_kind) for v in v_swap}
    expected_swap = {
        ("spell_fn", "addr_hl"),
        ("chest_str", "addr_hl"),
    }
    assert found_swap == expected_swap, f"Expected {expected_swap}, got {found_swap}"

    # 5. Clean-tree build/version_strings.inc tolerance vs real missing #import error
    ver_files = {
        "platforms/test/main.s": "\n".join([
            "#import \"build/version_strings.inc\"",
            ".segment TownOverlay",
            "town_entry: rts",
        ])
    }
    res_ver = analyze_port(cfg, _make_reader(ver_files))
    assert not res_ver.import_errors, res_ver.import_errors
    assert "TITLE_VERSION_LEN" in res_ver.const_names

    missing_files = {
        "platforms/test/main.s": "#import \"nonexistent_foo.s\"\n"
    }
    res_missing = analyze_port(cfg, _make_reader(missing_files))
    assert any("nonexistent_foo.s" in e for e in res_missing.import_errors), res_missing.import_errors

    print("check_overlay_calls selftest passed (clean, jsr/jmp/bra/bne/addr_hl/.word violations, swap dispatchers, manifest .inc + version_strings.inc fallbacks)")
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Static pre-build and post-build cross-overlay call checker for all 7 Moria8 ports."
    )
    parser.add_argument(
        "--port",
        choices=PORTS,
        help="Check only one port (default: all 7 ports)",
    )
    parser.add_argument(
        "--check-sym",
        action="store_true",
        help="Also validate generated trampoline targets against build/<port>/main.sym",
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="Run built-in unit self-tests",
    )
    args = parser.parse_args(argv)

    if args.selftest:
        return run_selftest()

    target_ports = (args.port,) if args.port else PORTS
    reader = _repo_reader(REPO_ROOT)

    total_errors = 0
    for port in target_ports:
        cfg = PORT_CONFIGS[port]
        entries = PORT_ENTRIES[port]
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
            sym_errs = check_sym_port(port, sym_path, analysis, entries)
            for err in sym_errs:
                print(f"ERROR: {err}", file=sys.stderr)
            total_errors += len(sym_errs)

    if total_errors:
        print(
            f"overlay call check FAILED ({total_errors} issue(s) across {len(target_ports)} port(s))",
            file=sys.stderr,
        )
        return 1

    suffix = " + .sym" if args.check_sym else ""
    print(f"overlay call check{suffix} passed ({len(target_ports)} port(s), 0 cross-overlay violations)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
