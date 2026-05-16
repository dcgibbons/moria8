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
        "map_cols": "MAP40_COLS",
        "map_rows": "MAP40_ROWS",
    },
    "c128": {
        "layout": ROOT / "commodore/c128/hal/layout.s",
        "screen": ROOT / "commodore/c128/screen_vdc.s",
        "map_cols": "C128_MAP_COLS",
        "map_rows": "C128_MAP_ROWS",
    },
    "plus4": {
        "layout": ROOT / "commodore/plus4/hal/layout.s",
        "screen": ROOT / "commodore/plus4/screen.s",
        "map_cols": "MAP40_COLS",
        "map_rows": "MAP40_ROWS",
    },
}

MAP_CONSTANTS = {
    "hal_layout_map_cols": "map_cols",
    "hal_layout_map_rows": "map_rows",
}

POLICY_CONSTANTS = (
    "hal_layout_store_price_col",
    "hal_layout_equipment_title_col",
    "hal_layout_equipment_footer_col",
    "hal_layout_inventory_title_col",
    "hal_layout_inventory_footer_col",
    "hal_layout_inventory_select_col",
    "hal_layout_inventory_identify_col",
    "hal_layout_character_title_col",
    "hal_layout_character_wizard_col",
    "hal_layout_character_footer_col",
    "hal_layout_character_col_l",
    "hal_layout_character_col_name",
    "hal_layout_character_col_mid",
    "hal_layout_character_col_r",
    "hal_layout_character_stat_col0",
    "hal_layout_character_stat_col1",
    "hal_layout_character_stat_col2",
    "hal_layout_wizard_compact_menu",
    "hal_layout_wizard_40col_menu",
    "hal_layout_wizard_title_col",
    "hal_layout_wizard_menu_col",
    "hal_layout_wizard_footer_col",
    "hal_layout_status_row21_name_col",
    "hal_layout_status_row21_state_col",
    "hal_layout_status_row21_lv_col",
    "hal_layout_status_row21_dl_col",
    "hal_layout_status_row22_st_col",
    "hal_layout_status_row22_in_col",
    "hal_layout_status_row22_wi_col",
    "hal_layout_status_row22_dx_col",
    "hal_layout_status_row22_co_col",
    "hal_layout_status_row22_ch_col",
    "hal_layout_status_row23_hp_col",
    "hal_layout_status_row23_mp_col",
    "hal_layout_status_row23_ac_col",
    "hal_layout_status_row23_au_col",
    "hal_layout_status_row23_hunger_col",
    "hal_layout_status_row23_state_col",
    "hal_layout_status_searching_on_row21",
    "hal_layout_status_searching_on_row23",
)


def parse_consts(path: Path) -> dict[str, str]:
    constants: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"\s*\.const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^/]+)", line)
        if not match:
            continue
        name = match.group(1)
        value = match.group(2).strip().lower()
        constants[name] = value
    return constants


def resolve_const(constants: dict[str, str], name: str) -> int | None:
    seen: set[str] = set()
    value = constants.get(name)
    while value is not None:
        if value == "true":
            return 1
        if value == "false":
            return 0
        if value.startswith("$"):
            return int(value[1:], 16)
        if re.fullmatch(r"[0-9]+", value):
            return int(value, 10)
        if not re.fullmatch(r"[a-z_][a-z0-9_]*", value):
            return None
        if value in seen:
            return None
        seen.add(value)
        value = constants.get(value)
    return None


def main() -> int:
    errors: list[str] = []
    dungeon_consts = parse_consts(ROOT / "commodore/common/dungeon_data.s")
    for platform, paths in PLATFORMS.items():
        layout_path = paths["layout"]
        screen_path = paths["screen"]
        if not layout_path.exists():
            errors.append(f"{platform}: missing {layout_path.relative_to(ROOT)}")
            continue
        layout_consts = parse_consts(layout_path)
        screen_consts = layout_consts | parse_consts(screen_path)
        for hal_name, screen_name in REQUIRED_CONSTANTS.items():
            if hal_name not in layout_consts:
                errors.append(f"{platform}: missing {hal_name} in {layout_path.relative_to(ROOT)}")
                continue
            if screen_name not in screen_consts:
                errors.append(f"{platform}: missing {screen_name} in {screen_path.relative_to(ROOT)}")
                continue
            hal_value = resolve_const(layout_consts, hal_name)
            screen_value = resolve_const(screen_consts, screen_name)
            if hal_value is None:
                errors.append(f"{platform}: cannot resolve {hal_name} in {layout_path.relative_to(ROOT)}")
                continue
            if screen_value is None:
                errors.append(f"{platform}: cannot resolve {screen_name} in {screen_path.relative_to(ROOT)}")
                continue
            if hal_value != screen_value:
                errors.append(
                    f"{platform}: {hal_name}={hal_value} differs from "
                    f"{screen_name}={screen_value}"
                )
        for hal_name, map_key in MAP_CONSTANTS.items():
            map_name = paths[map_key]
            if hal_name not in layout_consts:
                errors.append(f"{platform}: missing {hal_name} in {layout_path.relative_to(ROOT)}")
                continue
            if map_name not in dungeon_consts:
                errors.append(f"{platform}: missing {map_name} in commodore/common/dungeon_data.s")
                continue
            hal_value = resolve_const(layout_consts, hal_name)
            map_value = resolve_const(dungeon_consts, map_name)
            if hal_value is None:
                errors.append(f"{platform}: cannot resolve {hal_name} in {layout_path.relative_to(ROOT)}")
                continue
            if map_value is None:
                errors.append(f"{platform}: cannot resolve {map_name} in commodore/common/dungeon_data.s")
                continue
            if hal_value != map_value:
                errors.append(
                    f"{platform}: {hal_name}={hal_value} differs from "
                    f"{map_name}={map_value}"
                )
        for hal_name in POLICY_CONSTANTS:
            if hal_name not in layout_consts:
                errors.append(f"{platform}: missing {hal_name} in {layout_path.relative_to(ROOT)}")
                continue
            if resolve_const(layout_consts, hal_name) is None:
                errors.append(f"{platform}: cannot resolve {hal_name} in {layout_path.relative_to(ROOT)}")

    if errors:
        print("HAL layout export check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    total_constants = len(REQUIRED_CONSTANTS) + len(MAP_CONSTANTS) + len(POLICY_CONSTANTS)
    print(f"HAL layout export check passed ({total_constants} constants x {len(PLATFORMS)} platforms).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
