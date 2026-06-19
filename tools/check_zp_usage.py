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
LOW_ZP_MAX = 0x8F
HIGH_ZP_MIN = 0x90
HIGH_ZP_MAX = 0xFF

OPCODES = {
    "adc", "and", "asl", "bcc", "bcs", "beq", "bit", "bmi", "bne", "bpl", "bra",
    "brk", "bvc", "bvs", "clc", "cld", "cli", "clv", "cmp", "cpx", "cpy", "dec",
    "dex", "dey", "eor", "inc", "inx", "iny", "jmp", "jsr", "lda", "ldx", "ldy",
    "lsr", "nop", "ora", "pha", "php", "phx", "phy", "pla", "plp", "plx", "ply",
    "rol", "ror", "rti", "rts", "sbc", "sec", "sed", "sei", "sta", "stp", "stx",
    "sty", "stz", "tax", "tay", "trb", "tsb", "tsx", "txa", "txs", "tya", "wai",
}

LABEL_RE = re.compile(r"^\s*([A-Za-z_@.+!?][\w@.+!?-]*:)\s*")
RAW_ZP_RE = re.compile(r"(?<![#<>A-Za-z0-9_])\$(?P<addr>[0-9A-Fa-f]{2})(?![0-9A-Fa-f])")


@dataclass(frozen=True)
class Finding:
    severity: str
    path: Path
    line_no: int
    addr: int
    line: str
    reason: str


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


def classify_operand(path: Path, line_no: int, line: str) -> list[Finding]:
    findings: list[Finding] = []
    code = strip_leading_labels(strip_comment(line)).strip()
    if not code:
        return findings

    parts = code.split(None, 1)
    mnemonic = parts[0].lower()
    if mnemonic not in OPCODES:
        return findings

    operand = parts[1] if len(parts) > 1 else ""
    if not operand:
        return findings
    if operand.lstrip().startswith("#"):
        return findings

    for match in RAW_ZP_RE.finditer(operand):
        addr = int(match.group("addr"), 16)
        rel = path.relative_to(ROOT)
        display_line = line.rstrip()
        if addr == 0xba:
            allowed_paths = {
                "platforms/commodore/c64/boot.s",
                "platforms/commodore/c128/boot128.s",
                "platforms/commodore/c128/bootsect128.s",
                "platforms/commodore/c128/title_cache_runtime.s",
                "platforms/commodore/common/disk_swap.s",
                "platforms/commodore/c64/tests/test_disk_swap.s",
                "platforms/commodore/c128/tests/test_disk_swap128.s",
            }
            if rel.as_posix() in allowed_paths:
                continue
        if HIGH_ZP_MIN <= addr <= HIGH_ZP_MAX:
            findings.append(
                Finding(
                    severity="error",
                    path=rel,
                    line_no=line_no,
                    addr=addr,
                    line=display_line,
                    reason="raw volatile zero-page operand in $90-$FF",
                )
            )
        elif 0x02 <= addr <= LOW_ZP_MAX:
            findings.append(
                Finding(
                    severity="warn",
                    path=rel,
                    line_no=line_no,
                    addr=addr,
                    line=display_line,
                    reason="raw zero-page operand should usually use a named label",
                )
            )
    return findings


def scan_paths(scan_roots: list[Path]) -> list[Finding]:
    findings: list[Finding] = []
    for path in iter_source_files(scan_roots):
        for line_no, line in enumerate(path.read_text().splitlines(), start=1):
            findings.extend(classify_operand(path, line_no, line))
    return findings


def run_self_test() -> int:
    sample_path = ROOT / "core" / "demo_sample.s"
    cases = [
        ("lda $90", ["error"]),
        ("lda ($fe),y", ["error"]),
        ("sta $14", ["warn"]),
        ("lda #$ff", []),
        (".byte $ff", []),
        ("// sta $90", []),
        ("label: lda $8f,x", ["warn"]),
        ("lda $d020", []),
    ]
    failures: list[str] = []
    for index, (line, expected) in enumerate(cases, start=1):
        actual = [finding.severity for finding in classify_operand(sample_path, index, line)]
        if actual != expected:
            failures.append(f"case {index}: expected {expected}, got {actual} for {line!r}")
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print("self-test: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan assembly for raw zero-page operands.")
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="Optional roots or files to scan. Defaults to core, platforms/commodore/c64, platforms/commodore/c128.",
    )
    parser.add_argument("--self-test", action="store_true", help="Run internal parser self-checks and exit.")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    scan_roots = [path if path.is_absolute() else ROOT / path for path in args.paths] if args.paths else list(DEFAULT_SCAN_DIRS)
    findings = scan_paths(scan_roots)

    errors = [finding for finding in findings if finding.severity == "error"]
    warnings = [finding for finding in findings if finding.severity == "warn"]

    for bucket in (errors, warnings):
        for finding in bucket:
            print(
                f"{finding.severity.upper()}: {finding.path}:{finding.line_no}: "
                f"${finding.addr:02X} {finding.reason}\n  {finding.line}"
            )

    print(
        f"Scanned {len(iter_source_files(scan_roots))} files: "
        f"{len(errors)} error(s), {len(warnings)} warning(s)."
    )
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
