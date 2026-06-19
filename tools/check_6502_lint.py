#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SCAN_DIRS = (
    ROOT / "core",
    ROOT / "platforms" / "commodore" / "c64",
    ROOT / "platforms" / "commodore" / "c128",
)
SKIP_PATH_PARTS = {"out", "tests"}
SKIP_FILES = {
    Path("platforms/commodore/c128/vdc_demo.s"),
}

LABEL_RE = re.compile(r"^\s*([A-Za-z_@.+!?][\w@.+!?-]*:)\s*")
REDUNDANT_ZERO_COMPARE_RE = re.compile(r"^\s*(cmp|cpx|cpy)\s+#(?:\$00|0)\b", re.IGNORECASE)
BRANCH_RE = re.compile(r"^\s*(bcc|bcs|beq|bne|bmi|bpl|bvc|bvs)\b", re.IGNORECASE)

FLAG_SETTING_MNEMONICS = {
    "cmp": {"lda", "adc", "sbc", "and", "ora", "eor", "asl", "lsr", "rol", "ror", "pla", "txa", "tya"},
    "cpx": {"ldx", "tax", "inx", "dex", "tsx", "plx"},
    "cpy": {"ldy", "tay", "iny", "dey", "ply"},
}
FLAG_BRANCHES = {"beq", "bne", "bmi", "bpl"}


@dataclass(frozen=True)
class Instruction:
    path: Path
    line_no: int
    mnemonic: str
    operand: str
    line: str


@dataclass(frozen=True)
class Finding:
    severity: str
    path: Path
    line_no: int
    line: str
    reason: str
    detail: str | None = None


def strip_comment(line: str) -> str:
    return line.split("//", 1)[0]


def strip_leading_labels(line: str) -> str:
    current = line
    while True:
        match = LABEL_RE.match(current)
        if not match:
            return current
        current = current[match.end():]


def iter_source_files(scan_roots: list[Path]) -> list[Path]:
    files: list[Path] = []
    for root in scan_roots:
        for path in sorted(root.rglob("*.s")):
            rel = path.relative_to(ROOT)
            if any(part in SKIP_PATH_PARTS for part in rel.parts):
                continue
            if rel in SKIP_FILES:
                continue
            files.append(path)
    return files


def parse_instructions(path: Path) -> list[Instruction]:
    instructions: list[Instruction] = []
    for line_no, raw_line in enumerate(path.read_text().splitlines(), start=1):
        code = strip_leading_labels(strip_comment(raw_line)).strip()
        if not code:
            continue
        if code.startswith(".") or code.startswith(":"):
            continue
        parts = code.split(None, 1)
        mnemonic = parts[0].lower()
        operand = parts[1] if len(parts) > 1 else ""
        instructions.append(
            Instruction(
                path=path.relative_to(ROOT),
                line_no=line_no,
                mnemonic=mnemonic,
                operand=operand,
                line=raw_line.rstrip(),
            )
        )
    return instructions


def find_redundant_zero_compares(instructions: list[Instruction]) -> list[Finding]:
    findings: list[Finding] = []
    for index, instr in enumerate(instructions):
        if not REDUNDANT_ZERO_COMPARE_RE.match(strip_comment(instr.line)):
            continue
        if index == 0 or index + 1 >= len(instructions):
            continue

        prev_instr = instructions[index - 1]
        next_instr = instructions[index + 1]
        if prev_instr.mnemonic not in FLAG_SETTING_MNEMONICS[instr.mnemonic]:
            continue
        if next_instr.mnemonic not in FLAG_BRANCHES:
            continue

        findings.append(
            Finding(
                severity="error",
                path=instr.path,
                line_no=instr.line_no,
                line=instr.line,
                reason="redundant zero-compare after a flag-setting instruction",
                detail=(
                    f"previous `{prev_instr.mnemonic}` already set N/Z; "
                    f"next `{next_instr.mnemonic}` can branch directly"
                ),
            )
        )
    return findings


def find_branch_jump_ladders(instructions: list[Instruction]) -> list[Finding]:
    findings: list[Finding] = []
    for index, instr in enumerate(instructions[:-1]):
        if instr.mnemonic not in {"bcc", "bcs", "beq", "bne", "bmi", "bpl", "bvc", "bvs"}:
            continue
        next_instr = instructions[index + 1]
        if next_instr.mnemonic != "jmp":
            continue
        findings.append(
            Finding(
                severity="warn",
                path=instr.path,
                line_no=instr.line_no,
                line=instr.line,
                reason="branch followed immediately by jump",
                detail="review whether this is a deliberate branch-range workaround or an invertible branch",
            )
        )
    return findings


def scan_paths(scan_roots: list[Path]) -> tuple[list[Finding], list[Finding], int]:
    errors: list[Finding] = []
    warnings: list[Finding] = []
    file_count = 0
    for path in iter_source_files(scan_roots):
        file_count += 1
        instructions = parse_instructions(path)
        errors.extend(find_redundant_zero_compares(instructions))
        warnings.extend(find_branch_jump_ladders(instructions))
    return errors, warnings, file_count


def run_self_test() -> int:
    sample_path = ROOT / "core" / "demo_sample.s"
    sample_lines = [
        "lda some_value",
        "cmp #0",
        "beq done",
        "bne skip",
        "jmp somewhere",
        "jsr rng_range",
        "cmp #0",
        "bne retry",
        "eor #$ff",
        "cmp #0",
        "bne found",
    ]
    instructions = []
    for idx, line in enumerate(sample_lines, start=1):
        instructions.extend(parse_instructions_from_line(sample_path, idx, line))

    errors = find_redundant_zero_compares(instructions)
    warnings = find_branch_jump_ladders(instructions)

    failures: list[str] = []
    if len(errors) != 2:
        failures.append(f"expected 2 redundant-compare errors, got {len(errors)}")
    if len(warnings) != 1:
        failures.append(f"expected 1 branch-jump warning, got {len(warnings)}")
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print("self-test: PASS")
    return 0


def parse_instructions_from_line(path: Path, line_no: int, raw_line: str) -> list[Instruction]:
    code = strip_leading_labels(strip_comment(raw_line)).strip()
    if not code or code.startswith(".") or code.startswith(":"):
        return []
    parts = code.split(None, 1)
    return [
        Instruction(
            path=path.relative_to(ROOT),
            line_no=line_no,
            mnemonic=parts[0].lower(),
            operand=parts[1] if len(parts) > 1 else "",
            line=raw_line.rstrip(),
        )
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan assembly for recurring 6502 anti-patterns.")
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="Optional roots or files to scan. Defaults to core, platforms/commodore/c64, platforms/commodore/c128.",
    )
    parser.add_argument("--self-test", action="store_true", help="Run internal parser self-checks and exit.")
    parser.add_argument(
        "--max-branch-warnings",
        type=int,
        default=20,
        help="Maximum number of branch-then-jump warnings to print (default: 20).",
    )
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    scan_roots = [path if path.is_absolute() else ROOT / path for path in args.paths] if args.paths else list(DEFAULT_SCAN_DIRS)
    errors, warnings, file_count = scan_paths(scan_roots)

    for finding in errors:
        detail = f"\n  {finding.detail}" if finding.detail else ""
        print(f"ERROR: {finding.path}:{finding.line_no}: {finding.reason}\n  {finding.line}{detail}")

    for finding in warnings[: args.max_branch_warnings]:
        detail = f"\n  {finding.detail}" if finding.detail else ""
        print(f"WARN: {finding.path}:{finding.line_no}: {finding.reason}\n  {finding.line}{detail}")
    if len(warnings) > args.max_branch_warnings:
        print(f"WARN: suppressed {len(warnings) - args.max_branch_warnings} additional branch-jump warning(s)")

    print(
        f"Scanned {file_count} files: "
        f"{len(errors)} error(s), {len(warnings)} warning(s)."
    )
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
