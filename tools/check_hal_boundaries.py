#!/usr/bin/env python3
"""Baseline-aware HAL boundary audit for Commodore common assembly."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


COMMENT_RE = re.compile(r"//.*$")


@dataclass(frozen=True, order=True)
class Finding:
    path: str
    rule: str
    token: str

    def line(self) -> str:
        return f"{self.path}\t{self.rule}\t{self.token}"


RULES: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("raw-c64-bank-port", re.compile(r"\$0*01\b", re.IGNORECASE)),
    ("raw-vic-cia-sid-ted-vdc-address", re.compile(r"\$(?:d[0-9a-f]{3}|dd00|ff3e|ff3f)\b", re.IGNORECASE)),
    ("platform-name", re.compile(r"\b(?:VIC|VDC|TED|SID|CIA|REU|MMU)\b", re.IGNORECASE)),
    ("drive-model", re.compile(r"\b(?:1541|1551|1571|1581|SD2IEC)\b", re.IGNORECASE)),
    ("kernal-symbol", re.compile(r"\bKERNAL_[A-Z0-9_]+\b")),
    ("target-conditional", re.compile(r"#if[^\n]*(?:C64|C128|PLUS4)\b")),
)

DEFAULT_SKIP_NAMES = {
    "compat",
}


def strip_comment(line: str) -> str:
    return COMMENT_RE.sub("", line)


def find_violations(root: Path) -> set[Finding]:
    findings: set[Finding] = set()
    for source in sorted(root.rglob("*.s")):
        if any(part in DEFAULT_SKIP_NAMES for part in source.parts):
            continue
        rel = source.as_posix()
        for raw_line in source.read_text(encoding="utf-8", errors="replace").splitlines():
            line = strip_comment(raw_line)
            for rule_name, pattern in RULES:
                for match in pattern.finditer(line):
                    findings.add(Finding(rel, rule_name, match.group(0)))
    return findings


def read_baseline(path: Path) -> set[Finding]:
    if not path.exists():
        return set()
    findings: set[Finding] = set()
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            raise SystemExit(f"Malformed baseline entry in {path}: {raw_line!r}")
        findings.add(Finding(parts[0], parts[1], parts[2]))
    return findings


def write_baseline(path: Path, findings: set[Finding]) -> None:
    lines = [
        "# Current common-code HAL boundary violations.",
        "# Format: path<TAB>rule<TAB>token",
        "# Do not add entries casually; remove entries as code migrates behind HAL.",
        "",
    ]
    lines.extend(finding.line() for finding in sorted(findings))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default="commodore/common", type=Path)
    parser.add_argument("--baseline", default="docs/hal_boundary_allowlist.txt", type=Path)
    parser.add_argument("--write-baseline", action="store_true")
    args = parser.parse_args()

    findings = find_violations(args.root)

    if args.write_baseline:
        write_baseline(args.baseline, findings)
        return 0

    baseline = read_baseline(args.baseline)
    new_findings = sorted(findings - baseline)
    stale_baseline = sorted(baseline - findings)

    if new_findings:
        print("New common-code HAL boundary violations:")
        for finding in new_findings:
            print(f"  {finding.line()}")
    if stale_baseline:
        print("Stale HAL boundary allowlist entries:")
        for finding in stale_baseline:
            print(f"  {finding.line()}")
    if new_findings or stale_baseline:
        return 1

    print(f"HAL boundary audit passed ({len(findings)} baseline entries).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
