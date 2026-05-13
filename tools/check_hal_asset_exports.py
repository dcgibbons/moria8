#!/usr/bin/env python3
"""Verify every Commodore platform exports the asset-loader HAL labels."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_LABELS = (
    "hal_asset_load",
)

PLATFORM_FILES = {
    "c64": ROOT / "commodore/c64/config.s",
    "c128": ROOT / "commodore/c128/config128.s",
    "plus4": ROOT / "commodore/plus4/config.s",
}


def exported_labels(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    labels: set[str] = set()
    for match in re.finditer(r"(?m)^([A-Za-z_][A-Za-z0-9_]*):", text):
        labels.add(match.group(1))
    for match in re.finditer(r"(?m)^\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text):
        labels.add(match.group(1))
    for match in re.finditer(r"(?m)^\.const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text):
        labels.add(match.group(1))
    return labels


def macro_uses_asset_hal(path: Path) -> bool:
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"(?ms)^\.macro\s+AssetLoad\(\)\s*\{(?P<body>.*?)^\}", text)
    return bool(match and "hal_asset_load" in match.group("body"))


def main() -> int:
    failed = False
    for platform, path in PLATFORM_FILES.items():
        if not path.exists():
            print(f"{platform}: missing {path.relative_to(ROOT)}")
            failed = True
            continue
        labels = exported_labels(path)
        missing = [label for label in REQUIRED_LABELS if label not in labels]
        if missing:
            print(f"{platform}: missing asset-loader HAL exports in {path.relative_to(ROOT)}")
            for label in missing:
                print(f"  {label}")
            failed = True
        if not macro_uses_asset_hal(path):
            print(f"{platform}: AssetLoad() does not route through hal_asset_load")
            failed = True

    if failed:
        return 1

    print(f"Asset-loader HAL export check passed ({len(REQUIRED_LABELS)} label x {len(PLATFORM_FILES)} platforms).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
