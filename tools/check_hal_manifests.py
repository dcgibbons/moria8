#!/usr/bin/env python3
"""Validate platform HAL capability/layout manifests."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = ("c64", "c128", "plus4")
REQUIRED_TOP_KEYS = ("platform", "machine", "display", "storage", "memory", "capabilities")
REQUIRED_CAPABILITIES = (
    "reu_overlay_cache",
    "vdc_80_column",
    "ted_display",
    "sid_sound",
    "ted_sound",
    "two_drive_save",
)
REQUIRED_MEMORY_KEYS = (
    "banking",
    "map_base",
    "map_end",
    "banked_data_base",
    "banked_data_end",
    "io_hole_base",
    "io_hole_end",
)

EXPECTED = {
    "c64": {
        "columns": 40,
        "display": "vic_ii",
        "banking": "$01",
        "map_base": "$c000",
        "requires_drives": {"1541"},
        "memory_file": "commodore/c64/memory.s",
        "direct_display_consts": True,
    },
    "c128": {
        "columns": 80,
        "display": "vdc",
        "banking": "$ff00+$01",
        "map_base": "$4000",
        "requires_drives": {"1541", "1571"},
        "memory_file": "commodore/c128/memory128.s",
        "direct_display_consts": False,
    },
    "plus4": {
        "columns": 40,
        "display": "ted",
        "banking": "$ff3e/$ff3f",
        "map_base": "$c800",
        "requires_drives": {"1541", "1551"},
        "memory_file": "commodore/plus4/memory.s",
        "direct_display_consts": True,
    },
}


def fail(errors: list[str], platform: str, message: str) -> None:
    errors.append(f"{platform}: {message}")


def source_const(path: Path, name: str) -> str | None:
    prefix = f".const {name}"
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if not stripped.startswith(prefix):
            continue
        value = stripped.split("=", 1)[1].split("//", 1)[0].strip().lower()
        if value.startswith("$"):
            return value
    return None


def validate_manifest(platform: str, data: dict) -> list[str]:
    errors: list[str] = []
    for key in REQUIRED_TOP_KEYS:
        if key not in data:
            fail(errors, platform, f"missing top-level key {key}")
    if errors:
        return errors

    if data["platform"] != platform:
        fail(errors, platform, f"platform field is {data['platform']!r}")

    display = data["display"]
    expected = EXPECTED[platform]
    if display.get("hardware") != expected["display"]:
        fail(errors, platform, f"display.hardware must be {expected['display']}")
    if display.get("columns") != expected["columns"]:
        fail(errors, platform, f"display.columns must be {expected['columns']}")
    for key in ("screen_ram", "color_ram"):
        if key not in display:
            fail(errors, platform, f"display missing {key}")

    storage = data["storage"]
    for key in ("bus", "program_media", "save_media", "default_program_device", "default_save_device", "compatible_drives"):
        if key not in storage:
            fail(errors, platform, f"storage missing {key}")
    if storage.get("default_program_device") != 8:
        fail(errors, platform, "default_program_device must be 8")
    if storage.get("default_save_device") != 9:
        fail(errors, platform, "default_save_device must be 9")
    compatible = set(storage.get("compatible_drives", []))
    missing_drives = sorted(expected["requires_drives"] - compatible)
    if missing_drives:
        fail(errors, platform, f"compatible_drives missing {', '.join(missing_drives)}")

    memory = data["memory"]
    for key in REQUIRED_MEMORY_KEYS:
        if key not in memory:
            fail(errors, platform, f"memory missing {key}")
    if memory.get("banking") != expected["banking"]:
        fail(errors, platform, f"memory.banking must be {expected['banking']}")
    if memory.get("map_base") != expected["map_base"]:
        fail(errors, platform, f"memory.map_base must be {expected['map_base']}")
    memory_file = ROOT / expected["memory_file"]
    source_map_base = source_const(memory_file, "MAP_BASE")
    if source_map_base and memory.get("map_base") != source_map_base:
        fail(errors, platform, f"memory.map_base differs from {expected['memory_file']} MAP_BASE")
    source_map_end = source_const(memory_file, "MAP_END")
    if source_map_end and memory.get("map_end") != source_map_end:
        fail(errors, platform, f"memory.map_end differs from {expected['memory_file']} MAP_END")
    if expected["direct_display_consts"]:
        source_screen_ram = source_const(memory_file, "SCREEN_RAM")
        if source_screen_ram and display.get("screen_ram") != source_screen_ram:
            fail(errors, platform, f"display.screen_ram differs from {expected['memory_file']} SCREEN_RAM")
        source_color_ram = source_const(memory_file, "COLOR_RAM")
        if source_color_ram and display.get("color_ram") != source_color_ram:
            fail(errors, platform, f"display.color_ram differs from {expected['memory_file']} COLOR_RAM")

    capabilities = data["capabilities"]
    for key in REQUIRED_CAPABILITIES:
        if key not in capabilities:
            fail(errors, platform, f"capabilities missing {key}")
        elif not isinstance(capabilities[key], bool):
            fail(errors, platform, f"capabilities.{key} must be boolean")
    if platform == "plus4" and capabilities.get("reu_overlay_cache"):
        fail(errors, platform, "Plus/4 manifest must not advertise REU overlay cache")
    if platform == "plus4" and not capabilities.get("ted_display"):
        fail(errors, platform, "Plus/4 manifest must advertise TED display")
    if platform == "c128" and not capabilities.get("vdc_80_column"):
        fail(errors, platform, "C128 manifest must advertise VDC 80-column display")

    return errors


def main() -> int:
    errors: list[str] = []
    for platform in PLATFORMS:
        path = ROOT / "commodore" / platform / "hal" / "manifest.json"
        if not path.exists():
            errors.append(f"{platform}: missing {path.relative_to(ROOT)}")
            continue
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError as exc:
            errors.append(f"{platform}: invalid JSON in {path.relative_to(ROOT)}: {exc}")
            continue
        errors.extend(validate_manifest(platform, data))

    if errors:
        print("HAL manifest check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    print(f"HAL manifest check passed ({len(PLATFORMS)} platforms).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
