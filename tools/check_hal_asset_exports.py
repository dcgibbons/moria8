#!/usr/bin/env python3
"""Verify every Commodore platform exports asset-loader HAL contracts."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_LABELS = (
    "hal_asset_load",
    "hal_asset_load_prg_header",
    "hal_asset_load_title",
    "hal_asset_close_channel",
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
TITLE_TRANSACTION_BODIES = {
    "c64": (
        ROOT / "commodore/c64/config.s",
        "hal_asset_load_title",
        ("hal_storage_title_name", "$ffbd", "$ffba", "kernal_load_safe", "$ffc3", "$ffcc", "$dd00"),
    ),
    "c128": (
        ROOT / "commodore/common/title_cache_runtime128.s",
        "c128_title_asset_load",
        ("safe_setbnk", "hal_storage_title_name", "hal_storage_setnam", "hal_storage_setlfs", "kernal_load", "w_close"),
    ),
    "plus4": (
        ROOT / "commodore/plus4/config.s",
        "hal_asset_load_title",
        ("hal_storage_title_name", "$ffbd", "$ffba", "hal_asset_load", "$ffc3", "$ffcc"),
    ),
}
CLOSE_TRANSACTION_BODIES = {
    "c64": (
        ROOT / "commodore/c64/config.s",
        "hal_asset_close_channel",
        ("$ffc3", "$ffcc"),
    ),
    "plus4": (
        ROOT / "commodore/plus4/config.s",
        "hal_asset_close_channel",
        ("$ffc3", "$ffcc", ":EnterKernal()", ":ExitKernal()"),
    ),
}
OVERLAY_COMMON = ROOT / "commodore/common/overlay.s"
STRING_BANK_COMMON = ROOT / "commodore/common/string_bank.s"
TITLE_SCREEN_COMMON = ROOT / "commodore/common/title_screen.s"
TITLE_CACHE_COMMON = ROOT / "commodore/common/title_cache_runtime128.s"
TIER_MANAGER_COMMON = ROOT / "commodore/common/tier_manager.s"
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
TITLE_SCREEN_FORBIDDEN_TOKENS = (
    "hal_storage_setnam",
    "hal_storage_setlfs",
    "hal_storage_close",
    "kernal_load",
    "kernal_load_safe",
    "w_close",
    "safe_setbnk",
)
TIER_LOAD_FORBIDDEN_TOKENS = (
    "$ffbd",
    "$ffba",
    "$ffd5",
    "$ffc3",
    "$ffcc",
    "$dd00",
    ":AssetLoad()",
    ":EnterKernal()",
    ":ExitKernal()",
)
TIER_INIT_FORBIDDEN_TOKENS = (
    "$ffc3",
    "$ffcc",
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


def check_common_title_loader() -> list[str]:
    errors: list[str] = []
    body = label_body(TITLE_SCREEN_COMMON, "title_load_and_draw")
    if body is None:
        return ["title_screen.s: missing title_load_and_draw body"]
    if "hal_asset_load_title" not in body:
        errors.append("title_screen.s: title_load_and_draw does not call hal_asset_load_title")
    for token in TITLE_SCREEN_FORBIDDEN_TOKENS:
        if token in body:
            errors.append(f"title_screen.s: title_load_and_draw still contains {token}")

    cache_body = label_body(TITLE_CACHE_COMMON, "c128_title_load_and_draw_cached")
    if cache_body is None:
        errors.append("title_cache_runtime128.s: missing c128_title_load_and_draw_cached body")
    elif "hal_asset_load_title" not in cache_body:
        errors.append(
            "title_cache_runtime128.s: c128_title_load_and_draw_cached does not call hal_asset_load_title"
        )
    return errors


def check_common_tier_loader() -> list[str]:
    errors: list[str] = []
    init_body = label_body(TIER_MANAGER_COMMON, "tier_init")
    load_body = label_body(TIER_MANAGER_COMMON, "tier_load_disk")
    if init_body is None:
        errors.append("tier_manager.s: missing tier_init body")
    elif "hal_asset_close_channel" not in init_body:
        errors.append("tier_manager.s: tier_init does not call hal_asset_close_channel")
    elif any(token in init_body for token in TIER_INIT_FORBIDDEN_TOKENS):
        for token in TIER_INIT_FORBIDDEN_TOKENS:
            if token in init_body:
                errors.append(f"tier_manager.s: tier_init still contains {token}")

    if load_body is None:
        return ["tier_manager.s: missing tier_load_disk body"]
    if "hal_asset_load_prg_header" not in load_body:
        errors.append("tier_manager.s: tier_load_disk does not call hal_asset_load_prg_header")
    for token in TIER_LOAD_FORBIDDEN_TOKENS:
        if token in load_body:
            errors.append(f"tier_manager.s: tier_load_disk still contains {token}")
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

        title_body_path, title_label, title_required_tokens = TITLE_TRANSACTION_BODIES[platform]
        title_body = label_body(title_body_path, title_label)
        if title_body is None:
            print(
                f"{platform}: missing title transaction body {title_label} in "
                f"{title_body_path.relative_to(ROOT)}"
            )
            failed = True
            continue
        title_missing_tokens = [
            token for token in title_required_tokens if token not in title_body
        ]
        if title_missing_tokens:
            print(
                f"{platform}: {title_label} is missing title transaction operations in "
                f"{title_body_path.relative_to(ROOT)}"
            )
            for token in title_missing_tokens:
                print(f"  {token}")
            failed = True

        if platform in CLOSE_TRANSACTION_BODIES:
            close_body_path, close_label, close_required_tokens = CLOSE_TRANSACTION_BODIES[platform]
            close_body = label_body(close_body_path, close_label)
            if close_body is None:
                print(
                    f"{platform}: missing close transaction body {close_label} in "
                    f"{close_body_path.relative_to(ROOT)}"
                )
                failed = True
                continue
            close_missing_tokens = [
                token for token in close_required_tokens if token not in close_body
            ]
            if close_missing_tokens:
                print(
                    f"{platform}: {close_label} is missing close transaction operations in "
                    f"{close_body_path.relative_to(ROOT)}"
                )
                for token in close_missing_tokens:
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
    title_errors = check_common_title_loader()
    if title_errors:
        for error in title_errors:
            print(error)
        failed = True
    tier_errors = check_common_tier_loader()
    if tier_errors:
        for error in tier_errors:
            print(error)
        failed = True

    if failed:
        return 1

    print(
        "Asset-loader HAL export check passed "
        f"({len(REQUIRED_LABELS)} label x {len(PLATFORM_FILES)} platforms, "
        f"{len(TRANSACTION_BODIES)} PRG-header transactions, "
        f"{len(TITLE_TRANSACTION_BODIES)} title transactions, "
        f"{len(CLOSE_TRANSACTION_BODIES)} standalone close transactions, "
        "common overlay/string-bank/title/tier HAL paths)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
