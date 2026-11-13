#!/usr/bin/env python3
"""Keep the item docs in step with the item catalog.

docs/WIZARD.md: the ID range it quotes (the wizard's ``ITEM 0-N`` prompt,
which core/wizard.s derives from ITEM_TYPE_COUNT) is ``0-(ITEM_TYPE_COUNT-1)``,
and its Item IDs table has one row per item, named as the game shows it.
The names come from the C64 item-description test's ``ein_<id>`` table, which
the test checks against the production formatter for every item.

docs/FEATURE_MAP.md: the Moria8 master item table (section 8.3.1) has a row
for every item ID and its heading counts them.

An item added without its doc rows fails here, naming the IDs (maintainer,
2026-11-11: "so we can't miss wizard updates when we add stuff").
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ITEM_DEFS = ROOT / "core" / "item_defs.s"
NAMES = ROOT / "platforms" / "commodore" / "c64" / "tests" / "test_item_desc.s"
WIZARD = ROOT / "docs" / "WIZARD.md"
FEATURE_MAP = ROOT / "docs" / "FEATURE_MAP.md"

COUNT = re.compile(r"^\.const ITEM_TYPE_COUNT\s*=\s*(\d+)", re.M)
NAME = re.compile(r'^ein_(\d+):\s*\.text "([^"]*)"', re.M)
WIZARD_ROW = re.compile(r"^\| (\d+) \| (.+?) \|$", re.M)
# "`ITEM 0-152: `", "item IDs `0-152`": every range the wizard doc quotes
WIZARD_RANGE = re.compile(r"(?:ITEM |item IDs `)0-(\d+)")
MASTER_START, MASTER_END = "### 8.3.1 ", "### 8.3.2 "
MASTER_ROW = re.compile(r"^\| `(\d+)(?:\.\.(\d+))?` \| \*\*", re.M)
MASTER_HEADING = re.compile(r"All (\d+) Item Templates, IDs `0\.\.(\d+)`")


def item_count(defs: str) -> int:
    match = COUNT.search(defs)
    if match is None:
        raise SystemExit("check_wizard_doc: no ITEM_TYPE_COUNT in core/item_defs.s")
    return int(match.group(1))


def check_wizard(count: int, names: dict[int, str], doc: str) -> list[str]:
    errors = []
    rows = {int(i): name.strip() for i, name in WIZARD_ROW.findall(doc)}
    for item in range(count):
        if item not in rows:
            errors.append(f"docs/WIZARD.md: no Item IDs row for {item} ({names.get(item, '?')})")
        elif item in names and rows[item] != names[item]:
            errors.append(f"docs/WIZARD.md: item {item} is '{rows[item]}', the game shows '{names[item]}'")
    for item in sorted(i for i in rows if i >= count):
        errors.append(f"docs/WIZARD.md: row {item} is past the catalog (ITEM_TYPE_COUNT {count})")
    ranges = WIZARD_RANGE.findall(doc)
    if not ranges:
        errors.append("docs/WIZARD.md: quotes no item ID range (ITEM 0-N)")
    for last in ranges:
        if int(last) != count - 1:
            errors.append(f"docs/WIZARD.md: quotes the range 0-{last}, the catalog is 0-{count - 1}")
    return errors


def check_feature_map(count: int, doc: str) -> list[str]:
    try:
        section = doc[doc.index(MASTER_START):doc.index(MASTER_END)]
    except ValueError:
        return ["docs/FEATURE_MAP.md: no section 8.3.1 (the Moria8 master item table)"]
    ids: set[int] = set()
    for first, last in MASTER_ROW.findall(section):
        ids.update(range(int(first), int(last or first) + 1))
    errors = [f"docs/FEATURE_MAP.md: section 8.3.1 has no row for item {item}"
              for item in range(count) if item not in ids]
    heading = MASTER_HEADING.search(section.splitlines()[0])
    if heading is None or (int(heading.group(1)), int(heading.group(2))) != (count, count - 1):
        errors.append(f"docs/FEATURE_MAP.md: the section 8.3.1 heading should read "
                      f"'All {count} Item Templates, IDs `0..{count - 1}`'")
    return errors


def check(defs: str, names_src: str, wizard: str, feature_map: str) -> list[str]:
    count = item_count(defs)
    names = {int(i): name for i, name in NAME.findall(names_src)}
    return check_wizard(count, names, wizard) + check_feature_map(count, feature_map)


def selftest() -> None:
    defs = ".const ITEM_TYPE_COUNT = 3\n"
    names = 'ein_0:  .text "Gold" ; .byte 0\nein_1: .text "Dagger" ; .byte 0\nein_2: .text "Robe" ; .byte 0\n'
    wizard = "- Item generation: `ITEM 0-2: `\nuses item IDs `0-2`\n| 0 | Gold |\n| 1 | Dagger |\n| 2 | Robe |\n"
    fmap = ("### 8.3.1 Moria8 Master Item Table (All 3 Item Templates, IDs `0..2`)\n"
            "| `0..1` | **Gold** |\n| `2` | **Robe** |\n### 8.3.2 VMS\n")
    assert check(defs, names, wizard, fmap) == [], check(defs, names, wizard, fmap)
    # An item added (count 4) with nothing else: every check names it.
    errors = check(".const ITEM_TYPE_COUNT = 4\n", names + 'ein_3: .text "Crown" ; .byte 0\n', wizard, fmap)
    assert any("no Item IDs row for 3 (Crown)" in e for e in errors), errors
    assert any("range 0-2, the catalog is 0-3" in e for e in errors), errors
    assert any("no row for item 3" in e for e in errors), errors
    assert any("heading should read 'All 4" in e for e in errors), errors
    # A name that is not the game's.
    errors = check(defs, names, wizard.replace("| 1 | Dagger |", "| 1 | dagger |"), fmap)
    assert errors == ["docs/WIZARD.md: item 1 is 'dagger', the game shows 'Dagger'"], errors
    print("check_wizard_doc self-test: PASS")


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        selftest()
        return 0
    errors = check(ITEM_DEFS.read_text(), NAMES.read_text(), WIZARD.read_text(), FEATURE_MAP.read_text())
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        print(f"Item doc check FAILED ({len(errors)} problems): update docs/WIZARD.md and "
              "docs/FEATURE_MAP.md section 8.3.1 with the catalog", file=sys.stderr)
        return 1
    print(f"Item doc check passed ({item_count(ITEM_DEFS.read_text())} items).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
