#!/usr/bin/env python3
"""Verify platform layout HAL constants match the screen implementations."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_CONSTANTS = {
    "hal_layout_screen_cols": "SCREEN_COLS",
    "hal_layout_screen_rows": "SCREEN_ROWS",
    "hal_layout_viewport_x": "VIEWPORT_X",
    "hal_layout_viewport_y": "VIEWPORT_Y",
    "hal_layout_viewport_w": "VIEWPORT_W",
    "hal_layout_viewport_h": "VIEWPORT_H",
    "hal_layout_msg_row": "MSG_ROW",
    "hal_layout_status_row": "STATUS_ROW",
    "hal_layout_input_row": "INPUT_ROW",
}

PLATFORMS = {
    "c64": {
        "layout": ROOT / "commodore/c64/hal/layout.s",
        "screen": ROOT / "commodore/c64/screen.s",
    },
    "c128": {
        "layout": ROOT / "commodore/c128/hal/layout.s",
        "screen": ROOT / "commodore/c128/screen_vdc.s",
    },
    "plus4": {
        "layout": ROOT / "commodore/plus4/hal/layout.s",
        "screen": ROOT / "commodore/plus4/screen.s",
    },
}


def parse_consts(path: Path) -> dict[str, int]:
    constants: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"\s*\.const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^/]+)", line)
        if not match:
            continue
        name = match.group(1)
        value = match.group(2).strip().lower()
        try:
            if value.startswith("$"):
                constants[name] = int(value[1:], 16)
            else:
                constants[name] = int(value, 10)
        except ValueError:
            pass
    return constants


def main() -> int:
    errors: list[str] = []
    for platform, paths in PLATFORMS.items():
        layout_path = paths["layout"]
        screen_path = paths["screen"]
        if not layout_path.exists():
            errors.append(f"{platform}: missing {layout_path.relative_to(ROOT)}")
            continue
        layout_consts = parse_consts(layout_path)
        screen_consts = parse_consts(screen_path)
        for hal_name, screen_name in REQUIRED_CONSTANTS.items():
            if hal_name not in layout_consts:
                errors.append(f"{platform}: missing {hal_name} in {layout_path.relative_to(ROOT)}")
                continue
            if screen_name not in screen_consts:
                errors.append(f"{platform}: missing {screen_name} in {screen_path.relative_to(ROOT)}")
                continue
            if layout_consts[hal_name] != screen_consts[screen_name]:
                errors.append(
                    f"{platform}: {hal_name}={layout_consts[hal_name]} differs from "
                    f"{screen_name}={screen_consts[screen_name]}"
                )

    if errors:
        print("HAL layout export check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    print(f"HAL layout export check passed ({len(REQUIRED_CONSTANTS)} constants x {len(PLATFORMS)} platforms).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
