#!/usr/bin/env python3
"""Verify every Commodore platform exports asset-loader HAL contracts."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_LABELS = (
    "hal_asset_load",
    "hal_asset_load_prg_header",
)

PLATFORM_FILES = {
    "c64": ROOT / "commodore/c64/config.s",
    "c128": ROOT / "commodore/c128/config128.s",
    "plus4": ROOT / "commodore/plus4/config.s",
}

TRANSACTION_BODIES = {
    "c64": (
        ROOT / "commodore/c64/config.s",
        "hal_asset_load_prg_header",
        ("$ffbd", "$ffba", "hal_asset_load", "$ffc3", "$ffcc"),
    ),
    "c128": (
        ROOT / "commodore/common/reu.s",
        "c128_preload_asset_load",
        ("w_setnam", "w_setlfs", "w_load", "w_close", "w_clrchn", "safe_setbnk"),
    ),
    "plus4": (
        ROOT / "commodore/plus4/config.s",
        "hal_asset_load_prg_header",
        ("$ffbd", "$ffba", "hal_asset_load", "$ffc3", "$ffcc"),
    ),
}
OVERLAY_COMMON = ROOT / "commodore/common/overlay.s"
STRING_BANK_COMMON = ROOT / "commodore/common/string_bank.s"
OVERLAY_FORBIDDEN_TOKENS = (
    "$ffbd",
    "$ffba",
    "$ffd5",
    "$ffc3",
    "$ffcc",
    "c128_preload_asset_load",
    ":AssetLoad()",
)
STRING_BANK_FORBIDDEN_TOKENS = (
    "$ffbd",
    "$ffba",
    "$ffd5",
    "$ffc3",
    "$ffcc",
    "$dd00",
    ":AssetLoad()",
)


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


def label_body(path: Path, label: str) -> str | None:
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(
        rf"(?ms)^{re.escape(label)}:\s*(?P<body>.*?)(?=^[A-Za-z_][A-Za-z0-9_]*:|^\.label\s+|^\.const\s+|\Z)",
        text,
    )
    if not match:
        return None
    return match.group("body")


def check_common_overlay_loader() -> list[str]:
    text = OVERLAY_COMMON.read_text(encoding="utf-8", errors="replace")
    errors: list[str] = []
    body = label_body(OVERLAY_COMMON, "overlay_load_disk")
    if body is None:
        return ["overlay.s: missing overlay_load_disk body"]
    if "hal_asset_load_prg_header" not in body:
        errors.append("overlay.s: overlay_load_disk does not call hal_asset_load_prg_header")
    for token in OVERLAY_FORBIDDEN_TOKENS:
        if token in body:
            errors.append(f"overlay.s: overlay_load_disk still contains {token}")
    if "c128_preload_asset_load" in text:
        errors.append("overlay.s: direct c128_preload_asset_load call remains")
    return errors


def check_common_string_bank_loader() -> list[str]:
    errors: list[str] = []
    body = label_body(STRING_BANK_COMMON, "bank_load_recall")
    if body is None:
        return ["string_bank.s: missing bank_load_recall body"]
    if "hal_asset_load_prg_header" not in body:
        errors.append("string_bank.s: bank_load_recall does not call hal_asset_load_prg_header")
    for token in STRING_BANK_FORBIDDEN_TOKENS:
        if token in body:
            errors.append(f"string_bank.s: bank_load_recall still contains {token}")
    return errors


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

        body_path, label, required_tokens = TRANSACTION_BODIES[platform]
        body = label_body(body_path, label)
        if body is None:
            print(
                f"{platform}: missing transaction body {label} in "
                f"{body_path.relative_to(ROOT)}"
            )
            failed = True
            continue
        missing_tokens = [token for token in required_tokens if token not in body]
        if missing_tokens:
            print(
                f"{platform}: {label} is missing transaction operations in "
                f"{body_path.relative_to(ROOT)}"
            )
            for token in missing_tokens:
                print(f"  {token}")
            failed = True

    overlay_errors = check_common_overlay_loader()
    if overlay_errors:
        for error in overlay_errors:
            print(error)
        failed = True
    string_bank_errors = check_common_string_bank_loader()
    if string_bank_errors:
        for error in string_bank_errors:
            print(error)
        failed = True

    if failed:
        return 1

    print(
        "Asset-loader HAL export check passed "
        f"({len(REQUIRED_LABELS)} label x {len(PLATFORM_FILES)} platforms, "
        f"{len(TRANSACTION_BODIES)} PRG-header transactions, "
        "common overlay/string-bank HAL paths)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
