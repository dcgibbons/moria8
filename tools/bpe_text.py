#!/usr/bin/env python3
"""Validate and inspect BPE-compressed 6502 help and background tables.

Verifies that every hand- or tool-packed BPE dictionary (`help_dict_l/r` in
40-col and 80-col help data, and `bg_dict_l/r` in `background_data.s`) is
acyclic, bounded in recursion depth (to protect the 6502 stack), free of
out-of-range tokens, and decodes every entry cleanly.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent

HELP40_CTRL_BASE = 0xF9
HELP80_CTRL_BASE = 0xFB


def strip_comments(text: str) -> str:
    out = []
    for line in text.splitlines():
        line = re.sub(r"//.*", "", line)
        out.append(line)
    return "\n".join(out)


def preprocess_conditionals(text: str, defines: dict[str, bool] | None = None) -> str:
    """Resolve simple #if <SYM> / #else / #endif blocks in assembly data files."""
    out: list[str] = []
    # Stack entries: (active_branch, branch_taken_before)
    stack: list[bool] = []
    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        m_if = re.match(r"^#if\s+(!?)([A-Za-z_][A-Za-z0-9_]*)\s*(?://.*)?$", stripped)
        if m_if:
            neg, sym = m_if.group(1) == "!", m_if.group(2)
            val = True if defines is None else defines.get(sym, False)
            if neg:
                val = not val
            parent_ok = all(stack)
            stack.append(parent_ok and val)
            continue
        if re.match(r"^#else\b", stripped):
            if not stack:
                raise ValueError("Unmatched #else in conditional preprocessing")
            parent_ok = all(stack[:-1])
            stack[-1] = parent_ok and not stack[-1]
            continue
        if re.match(r"^#endif\b", stripped):
            if not stack:
                raise ValueError("Unmatched #endif in conditional preprocessing")
            stack.pop()
            continue
        if all(stack):
            out.append(raw_line)
    if stack:
        raise ValueError("Unclosed #if conditional block")
    return "\n".join(out)


def parse_byte_labels(text: str, defines: dict[str, bool] | None = None) -> dict[str, list[int]]:
    cleaned = strip_comments(preprocess_conditionals(text, defines))
    labels: dict[str, list[int]] = {}
    current: str | None = None
    for raw_line in cleaned.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        m_lbl = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
        if m_lbl:
            current = m_lbl.group(1)
            labels.setdefault(current, [])
            line = m_lbl.group(2).strip()
        if current is None or not line.startswith(".byte"):
            continue
        vals = line[5:].split(",")
        for item in vals:
            tok = item.strip()
            if not tok or tok.startswith("<") or tok.startswith(">"):
                continue
            if tok.startswith("$"):
                labels[current].append(int(tok[1:], 16))
            else:
                labels[current].append(int(tok, 10))
    return labels


def screencode_to_ascii(code: int) -> str:
    if code == 0x00:
        return "@"
    if 1 <= code <= 26:
        return chr(ord("a") + code - 1)
    if 0x20 <= code <= 0x3F:
        return chr(code)
    if 0x41 <= code <= 0x5A:
        return chr(code)
    extra = {0x1B: "[", 0x1C: "\\", 0x1D: "]", 0x1E: "^", 0x1F: "_", 0x40: "@", 0x5B: "[", 0x5C: "\\", 0x5D: "]", 0x7B: "{", 0x7D: "}"}
    if code in extra:
        return extra[code]
    if 0 <= code < 0x80:
        return f"<{code:02X}>"
    raise ValueError(f"Non-literal byte ${code:02X} passed to screencode_to_ascii")


def expand_bpe(
    stream: list[int],
    dict_l: list[int],
    dict_r: list[int],
    ctrl_base: int,
    max_depth: int = 8,
) -> tuple[str, int]:
    """Decode BPE bytes and return (text, observed_max_recursion_depth)."""
    peak_depth = 0

    def emit(b: int, depth: int) -> str:
        nonlocal peak_depth
        if depth > max_depth:
            raise ValueError(f"BPE recursion depth exceeded {max_depth} on token ${b:02X}")
        if depth > peak_depth:
            peak_depth = depth
        if b < 0x80:
            return screencode_to_ascii(b)
        if b >= ctrl_base:
            return f"<{b:02X}>"
        idx = b - 0x80
        if idx >= len(dict_l):
            raise ValueError(f"Out-of-range BPE token ${b:02X} (dict size {len(dict_l)})")
        return emit(dict_l[idx], depth + 1) + emit(dict_r[idx], depth + 1)

    return "".join(emit(b, 0) for b in stream), peak_depth


def validate_dict(dict_l: list[int], dict_r: list[int], ctrl_base: int, max_depth: int = 8) -> int:
    if len(dict_l) != len(dict_r):
        raise ValueError(f"dict_l ({len(dict_l)}) != dict_r ({len(dict_r)})")
    if len(dict_l) > (ctrl_base - 0x80):
        raise ValueError(f"dict size {len(dict_l)} overlaps ctrl_base ${ctrl_base:02X}")
    memo: dict[int, int] = {}
    visiting: set[int] = set()

    def token_depth(b: int) -> int:
        if b < 0x80 or b >= ctrl_base:
            return 0
        idx = b - 0x80
        if idx >= len(dict_l):
            raise ValueError(f"Dictionary references out-of-range token ${b:02X}")
        if idx in memo:
            return memo[idx]
        if idx in visiting:
            raise ValueError(f"Cycle detected in BPE dictionary at token ${b:02X}")
        visiting.add(idx)
        d = 1 + max(token_depth(dict_l[idx]), token_depth(dict_r[idx]))
        visiting.remove(idx)
        memo[idx] = d
        return d

    worst = 0
    for i in range(len(dict_l)):
        worst = max(worst, token_depth(0x80 + i))
    if worst > max_depth:
        raise ValueError(f"Dictionary max depth {worst} exceeds stack guard {max_depth}")
    return worst


def help_stream_layout_check(
    stream: list[int],
    dict_l: list[int],
    dict_r: list[int],
    ctrl_base: int,
    col2: int = 44,
    max_depth: int = 8,
    forbid_hi_ascii: bool = True,
) -> tuple[str, int, int]:
    """Decode one help stream line and track (text, peak_depth, max_printed_col)."""
    col = 2
    max_printed_col = 0
    parts: list[str] = []
    peak_depth = 0

    def emit(b: int, depth: int) -> None:
        nonlocal col, max_printed_col, peak_depth
        if depth > max_depth:
            raise ValueError(f"BPE recursion depth exceeded {max_depth} on token ${b:02X}")
        if depth > peak_depth:
            peak_depth = depth
        if b < 0x80:
            if forbid_hi_ascii and b >= 0x60:
                raise ValueError(
                    f"Help stream contains unportable $60-$7F byte ${b:02X} (blanks/graphics on Apple IIe/Atari8)"
                )
            ch = screencode_to_ascii(b)
            parts.append(ch)
            max_printed_col = max(max_printed_col, col)
            col += len(ch) if ch else 1
            return
        if b >= ctrl_base:
            parts.append(f"<{b:02X}>")
            if b < 0xFD:
                if ctrl_base == HELP80_CTRL_BASE:
                    if b == 0xFB:
                        col = col2
                else:
                    if b == 0xFB:
                        col = 20
                    elif b == 0xFA:
                        col = 15
                    elif b == 0xF9:
                        col = 27
            return
        idx = b - 0x80
        if idx >= len(dict_l):
            raise ValueError(f"Out-of-range BPE token ${b:02X} (dict size {len(dict_l)})")
        emit(dict_l[idx], depth + 1)
        emit(dict_r[idx], depth + 1)

    i = 0
    while i < len(stream):
        b = stream[i]
        if b == 0xFC:
            if i + 1 >= len(stream):
                raise ValueError("Truncated $FC tab-to-column escape in help stream")
            col = stream[i + 1]
            parts.append(f"<FC:{col}>")
            i += 2
            continue
        emit(b, 0)
        i += 1
    return "".join(parts), peak_depth, max_printed_col


def check_page_line_limit(page_lines: int, max_lines: int, name: str) -> None:
    if page_lines > max_lines:
        raise ValueError(f"{name}: page has {page_lines} lines (limit {max_lines})")


def check_help_streams(
    files: list[Path],
    ctrl_base: int,
    expected_substrings: tuple[str, ...] = (),
    defines: dict[str, bool] | None = None,
    max_lines: int | None = None,
    max_cols: int | None = None,
    col2: int = 44,
) -> tuple[int, int]:
    combined_text = "\n".join(p.read_text() for p in files)
    labels = parse_byte_labels(combined_text, defines=defines)
    dict_l = labels["help_dict_l"]
    dict_r = labels["help_dict_r"]
    worst_depth = validate_dict(dict_l, dict_r, ctrl_base)
    decoded_lines: list[str] = []
    for name in ("help_lines", "help_more_lines", "help_legend_lines"):
        if name not in labels:
            continue
        data = labels[name]
        page_lines = 0
        i = 0
        while i < len(data):
            ltype = data[i]
            i += 1
            if ltype == 3:
                break
            if ltype not in (0, 1, 2):
                raise ValueError(f"{name}: invalid line type {ltype} at offset {i - 1}")
            end = data.index(0, i)
            text, _, max_printed = help_stream_layout_check(
                data[i:end], dict_l, dict_r, ctrl_base, col2=col2
            )
            if ltype in (0, 1) and not text.strip():
                raise ValueError(f"{name}: decoded empty content line at offset {i}")
            if max_cols is not None and max_printed > max_cols:
                raise ValueError(
                    f"{name}: line {page_lines} reaches column {max_printed} > {max_cols}: {text!r}"
                )
            decoded_lines.append(text)
            page_lines += 1
            i = end + 1
        if max_lines is not None:
            check_page_line_limit(page_lines, max_lines, name)
    if expected_substrings:
        joined = "\n".join(decoded_lines)
        for needle in expected_substrings:
            if needle not in joined:
                raise ValueError(f"Decoded help stream missing expected text: {needle!r}")
    return len(dict_l), worst_depth


def check_background() -> tuple[int, int]:
    bg_path = ROOT / "core/6502/background_data.s"
    labels = parse_byte_labels(bg_path.read_text())
    dict_l = labels["bg_dict_l"]
    dict_r = labels["bg_dict_r"]
    worst_depth = validate_dict(dict_l, dict_r, 0x100, max_depth=8)
    checked = 0
    for name, data in labels.items():
        if not re.fullmatch(r"bg_s(?:\d+|_[a-z_]+)", name):
            continue
        if not data or data[-1] != 0:
            raise ValueError(f"{name}: missing NUL terminator")
        text, _ = expand_bpe(data[:-1], dict_l, dict_r, 0x100, max_depth=8)
        if not text:
            raise ValueError(f"{name}: empty decoded fragment")
        checked += 1
    if checked == 0:
        raise ValueError("No background fragment labels matched")
    return len(dict_l), worst_depth


def encode_strings(strings: list[list[int]], max_dict: int = 121) -> tuple[list[int], list[int], list[list[int]]]:
    """Greedy BPE encoder for authoring new byte streams."""
    dict_l: list[int] = []
    dict_r: list[int] = []
    cur = [list(s) for s in strings]
    while len(dict_l) < max_dict:
        counts: dict[tuple[int, int], int] = {}
        for seq in cur:
            for a, b in zip(seq, seq[1:]):
                counts[(a, b)] = counts.get((a, b), 0) + 1
        if not counts:
            break
        pair, freq = max(counts.items(), key=lambda kv: (kv[1], kv[0]))
        if freq < 2:
            break
        tok = 0x80 + len(dict_l)
        dict_l.append(pair[0])
        dict_r.append(pair[1])
        next_cur: list[list[int]] = []
        for seq in cur:
            out: list[int] = []
            i = 0
            while i < len(seq):
                if i + 1 < len(seq) and (seq[i], seq[i + 1]) == pair:
                    out.append(tok)
                    i += 2
                else:
                    out.append(seq[i])
                    i += 1
            next_cur.append(out)
        cur = next_cur
    return dict_l, dict_r, cur


def run_selftest() -> int:
    samples = [[ord(c) - 96 if "a" <= c <= "z" else ord(c) for c in "attack and cast a spell and cast"]]
    dl, dr, enc = encode_strings(samples)
    assert dl and dr
    decoded, depth = expand_bpe(enc[0], dl, dr, HELP40_CTRL_BASE)
    assert decoded == "attack and cast a spell and cast", decoded
    assert depth <= 8
    assert screencode_to_ascii(0x00) == "@"
    at_dec, _ = expand_bpe([0x00], [], [], HELP40_CTRL_BASE)
    assert at_dec == "@", at_dec
    pp_sample = "#if FOO\n.byte 1\n#else\n.byte 2\n#endif\n"
    assert ".byte 1" in preprocess_conditionals(pp_sample, {"FOO": True})
    assert ".byte 2" not in preprocess_conditionals(pp_sample, {"FOO": True})
    assert ".byte 2" in preprocess_conditionals(pp_sample, {"FOO": False})
    try:
        check_page_line_limit(23, 22, "help_lines")
        raise AssertionError("max_lines check failed")
    except ValueError:
        pass
    try:
        help_stream_layout_check([0x7B], [], [], HELP80_CTRL_BASE)
        raise AssertionError("$60-$7F help byte check failed")
    except ValueError:
        pass
    try:
        help_stream_layout_check([0xFC], [], [], HELP80_CTRL_BASE)
        raise AssertionError("truncated $FC check failed")
    except ValueError:
        pass
    try:
        validate_dict([0x80], [0x20], HELP40_CTRL_BASE)
        raise AssertionError("cycle check failed")
    except ValueError:
        pass
    print("bpe_text selftest passed")
    return 0


def run_check() -> int:
    h40_expected = (
        "[ <FF>Armor",
        "] <FF>Helm/Bt",
        "[ <FF>Ammo",
        "\\ <FF>Bow",
        "a-z/A-Z <FF>Monsters",
    )
    h40_size, h40_depth = check_help_streams(
        [
            ROOT / "core/6502/ui_help_data.s",
            ROOT / "core/6502/ui_help_page2_data.s",
            ROOT / "core/6502/ui_help_page3_data.s",
        ],
        HELP40_CTRL_BASE,
        expected_substrings=h40_expected,
        max_lines=23,
        max_cols=38,
    )
    h80_expected = (
        "SHIFT+F<FF> Fire",
        "X<FF> Look",
        "Z<FF> Use Staff",
        "] / [ \\<FF> Helm",
        "a-z/A-Z<FF> Monsters",
    )
    h80_size, h80_depth = check_help_streams(
        [ROOT / "platforms/commodore/c128/ui_help_data_80.s"],
        HELP80_CTRL_BASE,
        expected_substrings=h80_expected,
        defines={"HAL_PLATFORM_LEGAL_VIEWER": True},
        max_lines=22,
        max_cols=78,
    )
    check_help_streams(
        [ROOT / "platforms/commodore/c128/ui_help_data_80.s"],
        HELP80_CTRL_BASE,
        expected_substrings=h80_expected,
        defines={"HAL_PLATFORM_LEGAL_VIEWER": False},
        max_lines=22,
        max_cols=78,
    )
    bg_size, bg_depth = check_background()
    print(
        f"bpe_text check passed: help40={h40_size} tokens (depth {h40_depth}), "
        f"help80={h80_size} tokens (depth {h80_depth}), background={bg_size} tokens (depth {bg_depth})"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        rc = run_selftest()
        if rc:
            return rc
    if args.check or not args.selftest:
        return run_check()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
