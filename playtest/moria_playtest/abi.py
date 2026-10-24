"""Hand-listed symbol and offset table for the C64 build (§6.2).

Addresses resolve from the build's KickAss ``.vs`` file. ``.const`` values are
not exported to the ``.vs``, so each one is listed with its expected value and
checked against the single-line definition in its source file. ``check()``
fails when a name disappears or a value no longer matches; a PR that changes a
listed struct updates this table.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from .launch import C64_VS, ROOT

# Labels resolved from main.vs, with the file that defines them.
LABELS: dict[str, str] = {
    "zp_rng_0": "core/zeropage.s",
    "zp_player_x": "core/zeropage.s",
    "zp_player_y": "core/zeropage.s",
    "zp_player_hp_lo": "core/zeropage.s",
    "zp_player_mhp_lo": "core/zeropage.s",
    "zp_player_lvl": "core/zeropage.s",
    "zp_player_dlvl": "core/zeropage.s",
    "zp_turn_lo": "core/zeropage.s",
    "zp_game_flags": "core/zeropage.s",
    "zp_hunger_state": "core/zeropage.s",
    "zp_mon_count": "core/zeropage.s",
    "zp_entropy": "core/zeropage.s",
    "zp_view_x": "core/zeropage.s",
    "zp_view_y": "core/zeropage.s",
    "player_data": "core/player.s",
    "monster_table": "core/monster.s",
    "cr_level": "core/monster.s",
    "store_door_x": "core/dungeon_data.s",
    "store_door_y": "core/dungeon_data.s",
    "current_overlay": "platforms/commodore/common/overlay.s",
    "input_get_key": "platforms/commodore/c64/input.s",
    "input_get_command": "platforms/commodore/c64/input.s",
    "msg_show_more": "core/ui_messages.s",
    "get_direction_target": "core/dungeon_features.s",
    "rng_seed": "core/rng.s",
    "game_new_start": "core/game_loop.s",
    "main_loop": "core/game_loop.s",
}

# (defining file, expected value)
CONSTS: dict[str, tuple[str, int]] = {
    "SCREEN_RAM": ("platforms/commodore/c64/memory.s", 0x0400),
    "COLOR_RAM": ("platforms/commodore/c64/memory.s", 0xD800),
    "MAP_BASE": ("platforms/commodore/c64/memory.s", 0xC000),
    "hal_layout_map_cols": ("platforms/commodore/c64/hal/layout.s", 80),
    "hal_layout_map_rows": ("platforms/commodore/c64/hal/layout.s", 48),
    "hal_layout_viewport_x": ("platforms/commodore/c64/hal/layout.s", 1),
    "hal_layout_viewport_y": ("platforms/commodore/c64/hal/layout.s", 2),
    "hal_layout_viewport_w": ("platforms/commodore/c64/hal/layout.s", 38),
    "hal_layout_viewport_h": ("platforms/commodore/c64/hal/layout.s", 19),
    "hal_layout_status_row": ("platforms/commodore/c64/hal/layout.s", 21),
    "KBDBUF_COUNT": ("platforms/commodore/c64/input.s", 0xC6),
    "GAME_FLAG_OVER": ("core/zeropage.s", 0x01),
    "STORE_COUNT": ("core/dungeon_data.s", 8),
    "GAME_FLAG_WIZARD": ("core/zeropage.s", 0x02),
    "GAME_FLAG_WINNER": ("core/zeropage.s", 0x04),
    "PL_RACE": ("core/player.s", 17),
    "PL_CLASS": ("core/player.s", 18),
    "PL_LEVEL": ("core/player.s", 19),
    "PL_DLEVEL": ("core/player.s", 20),
    "PL_HP_LO": ("core/player.s", 33),
    "PL_MHP_LO": ("core/player.s", 35),
    "PL_GOLD_0": ("core/player.s", 43),
    "PL_XP_0": ("core/player.s", 46),
    "PL_MAP_X": ("core/player.s", 49),
    "PL_MAP_Y": ("core/player.s", 50),
    "PL_MAX_DLVL": ("core/player.s", 56),
    "PL_STRUCT_SIZE": ("core/player.s", 111),
    "MAX_MONSTERS": ("core/monster.s", 32),
    "MAX_DUNGEON_CREATURES": ("core/monster.s", 57),
    "MAX_TOWN_CREATURES": ("core/monster.s", 8),
    "MONSTER_ENTRY_SIZE": ("core/monster.s", 12),
    "EMPTY_SLOT": ("core/monster.s", 0xFF),
    "MX_X": ("core/monster.s", 0),
    "MX_Y": ("core/monster.s", 1),
    "MX_TYPE": ("core/monster.s", 2),
    "MX_HP_LO": ("core/monster.s", 3),
    "MX_FLAGS": ("core/monster.s", 5),
    "MF_VISIBLE": ("core/monster.s", 0x08),
    "MF_DETECTED": ("core/monster.s", 0x10),
    "TILE_TYPE_MASK": ("core/dungeon_data.s", 0xF0),
    "TILE_FLOOR": ("core/dungeon_data.s", 0x00),
    "TILE_DOOR_OPEN": ("core/dungeon_data.s", 0x70),
    "TILE_DOOR_CLOSED": ("core/dungeon_data.s", 0x80),
    "TILE_STAIRS_DN": ("core/dungeon_data.s", 0x90),
    "TILE_STAIRS_UP": ("core/dungeon_data.s", 0xA0),
    "TILE_SECRET": ("core/dungeon_data.s", 0xF0),
    "FLAG_OCCUPIED": ("core/dungeon_data.s", 0x01),
    "FLAG_VISITED": ("core/dungeon_data.s", 0x04),
    "FLAG_LIT": ("core/dungeon_data.s", 0x08),
}

# KERNAL keyboard buffer (fixed by the C64 KERNAL, not the game).
KERNAL_KEYD = 0x0277


def parse_value(text: str) -> int:
    text = text.strip()
    if text.startswith("$"):
        return int(text[1:], 16)
    if text.startswith("%"):
        return int(text[1:], 2)
    return int(text, 10)


def parse_vs(path: Path) -> dict[str, list[int]]:
    """Multimap name -> addresses (overlay symbols can share addresses)."""
    symbols: dict[str, list[int]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) != 3 or parts[0] != "al":
            continue
        addr = int(parts[1].split(":")[1], 16)
        symbols.setdefault(parts[2].lstrip("."), []).append(addr)
    return symbols


@dataclass
class Abi:
    labels: dict[str, int]
    consts: dict[str, int]
    all_symbols: dict[str, list[int]]

    def __post_init__(self) -> None:
        # Plain attributes: __getattr__ ran millions of times a session (M4
        # profile). Labels win over consts, as in __getattr__.
        for table in (self.consts, self.labels):
            for name, value in table.items():
                if name.isidentifier() and name not in ("labels", "consts", "all_symbols"):
                    self.__dict__[name] = value

    def __getattr__(self, name: str) -> int:
        labels = self.__dict__.get("labels", {})
        if name in labels:
            return labels[name]
        consts = self.__dict__.get("consts", {})
        if name in consts:
            return consts[name]
        raise AttributeError(name)


def const_value(root: Path, file: str, name: str) -> int | None:
    pattern = re.compile(rf"^\s*\.const\s+{re.escape(name)}\s*=\s*(\$[0-9A-Fa-f]+|%[01]+|\d+)\b")
    for line in (root / file).read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            return parse_value(match.group(1))
    return None


def check(vs_path: Path = C64_VS, root: Path = ROOT) -> list[str]:
    """Return every mismatch between this table and the build/sources."""
    errors: list[str] = []
    symbols = parse_vs(vs_path)
    for name, file in LABELS.items():
        addrs = symbols.get(name)
        if not addrs:
            errors.append(f"label {name} ({file}) missing from {vs_path.name}")
        elif len(set(addrs)) > 1:
            errors.append(f"label {name} is ambiguous in {vs_path.name}: {sorted(set(addrs))}")
    for name, (file, expected) in CONSTS.items():
        actual = const_value(root, file, name)
        if actual is None:
            errors.append(f".const {name} not found as a single-line literal in {file}")
        elif actual != expected:
            errors.append(f".const {name} in {file} is {actual:#x}, table expects {expected:#x}")
    return errors


def load(vs_path: Path = C64_VS, root: Path = ROOT) -> Abi:
    errors = check(vs_path, root)
    if errors:
        raise RuntimeError("playtest ABI table is stale:\n  " + "\n  ".join(errors))
    symbols = parse_vs(vs_path)
    labels = {name: symbols[name][0] for name in LABELS}
    consts = {name: value for name, (_, value) in CONSTS.items()}
    return Abi(labels, consts, symbols)
