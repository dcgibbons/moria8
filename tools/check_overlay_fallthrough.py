#!/usr/bin/env python3
"""
tools/check_overlay_fallthrough.py
Module ownership: platform-tooling static check for code that runs off the end
of a segment or overlay region.

Flags:
1. A ``:Macro()`` expansion that is the last emitted code before a ``.segment``
   switch or region ``*_end:`` label when the macro's body does not end in
   ``rts``/``rti``/``jmp``/``bra``/``brl``/``brk`` — even when trailing
   non-emitting directives (``#endif``, ``.assert``, ``.print``, ``#undef``,
   etc.) or labels intervene.
2. An ``#import "..."`` immediately preceding an overlay/code ``*_end:`` or
   ``.segment`` switch when the imported file's last emitted item is a
   non-terminating instruction or non-terminating code ``:Macro()``.

``--selftest`` runs synthetic fixtures.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Set, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent
SCAN_DIRS = ("core", "platforms")
SKIP_PARTS = {"build", "var", "tools", "tests", ".git"}

MACRO_START = re.compile(r"\s*\.macro\s+(\w+)\s*\(")
FUNC_START = re.compile(r"\s*\.function\s+(\w+)\s*\(")
EXPANSION = re.compile(r"^\s*:(\w+)\(")
TERMINATOR = re.compile(r"^(rts|rti|jmp|bra|brl|brk)\b", re.IGNORECASE)
REGION_END = re.compile(r"^(\.segment\b|\w*_end:)")
CODE_REGION_END = re.compile(
    r"^(\.segment\b|(?:ovl_|legal_code_|program_|banked_code_|a2_play_|beeb_play_|c128_resident_(?:play|persist)_|low_helpers_|cart_reader_)\w*end:)"
)
NON_EMITTING = re.compile(
    r"^(?:#(?:if|ifdef|ifndef|elif|else|endif|define|undef|importonce)\b"
    r"|\.(?:assert|print|eval|var|const|label|encoding|filenamespace|import)\b|\})"
)
DATA_DIR = re.compile(r"^\.(?:byte|word|dword|text|fill|lohifill|align|pc)\b", re.IGNORECASE)
IMPORT_RE = re.compile(r'^#import\s+"([^"]+)"')
LEADING_LABEL = re.compile(r"^!?@?[A-Za-z_][A-Za-z0-9_]*\s*:\s*(.*)$")


def code_line(line: str) -> str:
    in_str = False
    escaped = False
    for idx, ch in enumerate(line):
        if escaped:
            escaped = False
        elif ch == "\\" and in_str:
            escaped = True
        elif ch == '"':
            in_str = not in_str
        elif not in_str and ch == "/" and idx + 1 < len(line) and line[idx + 1] == "/":
            return line[:idx].strip()
    return line.strip()


def strip_leading_labels(stmt: str) -> str:
    cur = stmt.strip()
    while cur:
        m = LEADING_LABEL.match(cur)
        if not m or REGION_END.match(cur):
            break
        cur = m.group(1).strip()
    return cur


def _brace_delta(line: str) -> int:
    in_str = False
    escaped = False
    delta = 0
    for ch in line:
        if escaped:
            escaped = False
        elif ch == "\\" and in_str:
            escaped = True
        elif ch == '"':
            in_str = not in_str
        elif not in_str:
            if ch == "{":
                delta += 1
            elif ch == "}":
                delta -= 1
    return delta


def macro_last_instructions(sources: Iterable[Tuple[str, List[str]]]) -> Dict[str, str]:
    """Each code macro's last instruction ('' for one holding none: a
    segment switch or data macro, never flagged)."""
    last: Dict[str, str] = {}
    for _, lines in sources:
        i = 0
        while i < len(lines):
            cleaned_hdr = code_line(lines[i])
            match = MACRO_START.match(cleaned_hdr)
            if not match:
                i += 1
                continue
            depth = _brace_delta(cleaned_hdr)
            body: List[str] = []
            if "{" in cleaned_hdr:
                after_brace = cleaned_hdr.split("{", 1)[1]
                if depth <= 0 and "}" in after_brace:
                    after_brace = after_brace.rsplit("}", 1)[0]
                if after_brace.strip():
                    body.append(after_brace)
            i += 1
            while i < len(lines) and depth > 0:
                cl = code_line(lines[i])
                depth += _brace_delta(cl)
                if depth <= 0 and "}" in cl:
                    cl = cl.rsplit("}", 1)[0]
                body.append(cl)
                i += 1
            instructions: List[str] = []
            for raw_b in body:
                s = strip_leading_labels(raw_b)
                if not s or s == "}" or NON_EMITTING.match(s):
                    continue
                if DATA_DIR.match(s) or s.startswith("."):
                    instructions.append("")
                else:
                    instructions.append(s)
            last[match.group(1)] = instructions[-1] if instructions and instructions[-1] else ""
    return last


def _top_level_lines(lines: List[str]) -> List[Tuple[int, str]]:
    """Yield (1-based line_no, cleaned_line) outside .macro/.function definitions."""
    out: List[Tuple[int, str]] = []
    skip_depth = 0
    in_def = False
    for idx, raw in enumerate(lines, start=1):
        cl = code_line(raw)
        if not in_def and (MACRO_START.match(cl) or FUNC_START.match(cl)):
            delta = _brace_delta(cl)
            if delta > 0:
                in_def = True
                skip_depth = delta
            continue
        if in_def:
            skip_depth += _brace_delta(cl)
            if skip_depth <= 0:
                in_def = False
                skip_depth = 0
            continue
        out.append((idx, cl))
    return out


def _resolve_import(imp_target: str, cur_file: str, source_map: Dict[str, List[str]]) -> Optional[str]:
    norm = imp_target.replace("\\", "/")
    rel = (Path(cur_file).parent / norm).as_posix()
    parts: List[str] = []
    for part in rel.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if parts:
                parts.pop()
        else:
            parts.append(part)
    cand = "/".join(parts)
    if cand in source_map:
        return cand
    if norm in source_map:
        return norm
    for prefix in ("core/", "platforms/commodore/common/", "platforms/shared/"):
        if prefix + norm in source_map:
            return prefix + norm
    return None


def _file_last_emitted(
    fname: str,
    source_map: Dict[str, List[str]],
    last_macro: Dict[str, str],
    seen: Set[str],
) -> Tuple[str, str]:
    """Return (kind, detail) for the last emitted statement in fname.
    kind in {'term', 'data', 'code', 'empty'}.
    """
    if fname in seen or fname not in source_map:
        return ("empty", "")
    top = _top_level_lines(source_map[fname])
    for lineno, cl in reversed(top):
        if not cl:
            continue
        if cl.startswith(".segment"):
            break
        s = strip_leading_labels(cl)
        if not s or NON_EMITTING.match(s) or REGION_END.match(s):
            continue
        m_imp = IMPORT_RE.match(s)
        if m_imp:
            resolved = _resolve_import(m_imp.group(1), fname, source_map)
            if resolved is not None:
                kind, detail = _file_last_emitted(resolved, source_map, last_macro, seen | {fname})
                if kind != "empty":
                    return (kind, detail)
            continue
        m_exp = EXPANSION.match(s)
        if m_exp:
            m_name = m_exp.group(1)
            m_last = last_macro.get(m_name, "")
            if not m_last:
                return ("data", f"{fname}:{lineno} :{m_name}()")
            if TERMINATOR.match(m_last):
                return ("term", f"{fname}:{lineno} :{m_name}()")
            return ("code", f"{fname}:{lineno}: :{m_name}() ends in '{m_last}'")
        if ";" in s:
            sub_stmts = [strip_leading_labels(p) for p in s.split(";") if strip_leading_labels(p)]
            if sub_stmts:
                s = sub_stmts[-1]
        if DATA_DIR.match(s) or s.startswith("."):
            return ("data", f"{fname}:{lineno} {s}")
        if TERMINATOR.match(s):
            return ("term", f"{fname}:{lineno} {s}")
        return ("code", f"{fname}:{lineno}: ends in '{s}'")
    return ("empty", "")


def findings(sources: List[Tuple[str, List[str]]]) -> List[str]:
    source_map = dict(sources)
    last = macro_last_instructions(sources)
    found: List[str] = []

    for name, lines in sources:
        top = _top_level_lines(lines)
        for idx, (lineno, cl) in enumerate(top):
            s = strip_leading_labels(cl)
            # 1. Macro expansion followed (ignoring non-emitting directives/labels) by REGION_END
            match = EXPANSION.match(s)
            if match and last.get(match.group(1)) and not TERMINATOR.match(last[match.group(1)]):
                following = ""
                for _, next_cl in top[idx + 1 :]:
                    if not next_cl:
                        continue
                    if REGION_END.match(next_cl):
                        following = next_cl
                        break
                    next_s = strip_leading_labels(next_cl)
                    if not next_s or NON_EMITTING.match(next_s):
                        continue
                    if next_s.startswith("#import"):
                        m_imp = IMPORT_RE.match(next_s)
                        if m_imp:
                            resolved = _resolve_import(m_imp.group(1), name, source_map)
                            if resolved is not None:
                                kind, _ = _file_last_emitted(resolved, source_map, last, {name})
                                if kind == "empty":
                                    continue
                    following = next_s
                    break
                if following and REGION_END.match(following):
                    found.append(
                        f"{name}:{lineno}: :{match.group(1)}() ends in '{last[match.group(1)]}', "
                        f"then '{following}': the CPU runs past the region's end"
                    )

            # 2. #import of a cold file before CODE_REGION_END whose last emitted item falls through
            m_imp = IMPORT_RE.match(s)
            if m_imp:
                resolved = _resolve_import(m_imp.group(1), name, source_map)
                if resolved is None:
                    continue
                following = ""
                for _, next_cl in top[idx + 1 :]:
                    if not next_cl:
                        continue
                    if CODE_REGION_END.match(next_cl):
                        following = next_cl
                        break
                    if REGION_END.match(next_cl):
                        following = next_cl
                        break
                    next_s = strip_leading_labels(next_cl)
                    if not next_s or NON_EMITTING.match(next_s):
                        continue
                    following = next_s
                    break
                if following and CODE_REGION_END.match(following):
                    kind, detail = _file_last_emitted(resolved, source_map, last, {name})
                    if kind == "code":
                        found.append(
                            f"{name}:{lineno}: #import \"{m_imp.group(1)}\" ({detail}), "
                            f"then '{following}': the CPU runs past the region's end"
                        )
    return found


def repo_sources() -> List[Tuple[str, List[str]]]:
    paths = sorted(
        p
        for scan_dir in SCAN_DIRS
        if (REPO_ROOT / scan_dir).is_dir()
        for p in (REPO_ROOT / scan_dir).rglob("*.s")
        if not (SKIP_PARTS & set(p.relative_to(REPO_ROOT).parts))
    )
    return [
        (str(p.relative_to(REPO_ROOT)), p.read_text(encoding="utf-8", errors="replace").splitlines())
        for p in paths
    ]


def selftest() -> int:
    body = ".macro Body() {\n    jsr work\n    bcs !done+\n    clc\n!done:\n%s}\n"
    cases = [
        ("runs off an overlay's end", [("m.s", body % ""), ("u.s", "x:\n    :Body()\novl_town_end:\n")], 1),
        ("runs into a segment switch", [("m.s", body % ""), ("u.s", "x:\n    :Body()\n.segment Default\n")], 1),
        (
            "trailing #endif/.assert/.print/#undef do not mask missing rts",
            [
                ("m.s", body % ""),
                (
                    "u.s",
                    "x:\n    :Body()\n#endif\n#undef FOO\n.print \"sz\"\n.assert \"ok\", 1, 1\novl_town_end:\n",
                ),
            ],
            1,
        ),
        (
            "#imported cold file ending without rts before ovl_*_end",
            [
                ("cold.s", "cold_fn:\n    jsr helper\n    clc\n#endif\n"),
                ("u.s", ".segment TownOverlay\n#import \"cold.s\"\n.assert \"fit\", 1, 1\novl_town_end:\n"),
            ],
            1,
        ),
        (
            "#imported cold file ending in macro without rts before .segment",
            [
                ("m.s", body % ""),
                ("cold.s", "cold_fn:\n    :Body()\n"),
                ("u.s", ".segment TownOverlay\n#import \"cold.s\"\n.segment Default\n"),
            ],
            1,
        ),
        (
            "#imported cold file ending in rts or data passes",
            [
                ("cold_ok.s", "cold_fn:\n    rts\ncold_tbl: .byte 1, 2\n"),
                ("u.s", ".segment TownOverlay\n#import \"cold_ok.s\"\novl_town_end:\n"),
            ],
            0,
        ),
        ("returns itself", [("m.s", body % "    rts\n"), ("u.s", "x:\n    :Body()\novl_town_end:\n")], 0),
        ("its caller returns", [("m.s", body % ""), ("u.s", "x:\n    :Body()\n    rts\novl_town_end:\n")], 0),
        ("a jump ends it", [("m.s", body % "    jmp elsewhere\n"), ("u.s", "x:\n    :Body()\n.segment Default\n")], 0),
        ("a data macro", [("m.s", ".macro Table() {\n    .byte 1, 2\n}\n"), ("u.s", "    :Table()\n.segment Default\n")], 0),
    ]
    failed = 0
    for what, files, want in cases:
        got = len(findings([(fname, txt.splitlines()) for fname, txt in files]))
        status = "PASS" if got == want else "FAIL"
        failed += got != want
        print(f"{status} {what}: {got} finding(s), want {want}")
    return 1 if failed else 0


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    found = findings(repo_sources())
    for line in found:
        print(line)
    print(f"check_overlay_fallthrough: {len(found)} finding(s)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
