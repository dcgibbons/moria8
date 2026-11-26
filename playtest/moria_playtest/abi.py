"""Hand-listed symbol and offset table for a build (§6.2).

Addresses resolve from the build's KickAss ``.vs`` file. ``.const`` values are
not exported to the ``.vs``, so each one is listed with its expected value and
checked against the single-line definition in its source file. ``check()``
fails when a name disappears or a value no longer matches; a PR that changes a
listed struct updates this table. Each port (ports.py) adds its own rows:
its screen, map and layout constants, and its input labels.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from .launch import C64_VS, ROOT
from .ports import C64, Port

# Labels resolved from main.vs, with the file that defines them.
LABELS: dict[str, str] = {
    "zp_rng_0": "core/6502/zeropage.s",
    "zp_player_x": "core/6502/zeropage.s",
    "zp_player_y": "core/6502/zeropage.s",
    "zp_player_hp_lo": "core/6502/zeropage.s",
    "zp_player_mhp_lo": "core/6502/zeropage.s",
    "zp_player_lvl": "core/6502/zeropage.s",
    "zp_player_mp": "core/6502/zeropage.s",
    "zp_player_mmp": "core/6502/zeropage.s",
    "zp_eff_resist": "core/6502/zeropage.s",
    "eff_resist_cold_timer": "core/6502/zeropage.s",
    "zp_player_dlvl": "core/6502/zeropage.s",
    "zp_turn_lo": "core/6502/zeropage.s",
    "zp_game_flags": "core/6502/zeropage.s",
    "zp_hunger_state": "core/6502/zeropage.s",
    "zp_mon_count": "core/6502/zeropage.s",
    "zp_entropy": "core/6502/zeropage.s",
    "zp_view_x": "core/6502/zeropage.s",
    "zp_view_y": "core/6502/zeropage.s",
    "zp_light_radius": "core/6502/zeropage.s",
    "player_data": "core/6502/player.s",
    "monster_table": "core/6502/monster.s",
    "cr_level": "core/6502/monster.s",
    "store_door_x": "core/6502/dungeon_data.s",
    "store_door_y": "core/6502/dungeon_data.s",
    "current_overlay": "platforms/commodore/common/overlay.s",
    "msg_show_more": "core/6502/ui_messages.s",
    "get_direction_target": "core/6502/dungeon_features.s",
    "rng_seed": "core/6502/rng.s",
    "game_new_start": "core/6502/game_loop.s",
    "main_loop": "core/6502/game_loop.s",
}

# (defining file, expected value)
CONSTS: dict[str, tuple[str, int]] = {
    "GAME_FLAG_OVER": ("core/6502/zeropage.s", 0x01),
    "STORE_COUNT": ("core/6502/dungeon_data.s", 8),
    "GAME_FLAG_WIZARD": ("core/6502/zeropage.s", 0x02),
    "GAME_FLAG_WINNER": ("core/6502/zeropage.s", 0x04),
    "PL_RACE": ("core/6502/player.s", 17),
    "PL_CLASS": ("core/6502/player.s", 18),
    "PL_LEVEL": ("core/6502/player.s", 19),
    "PL_DLEVEL": ("core/6502/player.s", 20),
    "PL_HP_LO": ("core/6502/player.s", 33),
    "PL_MHP_LO": ("core/6502/player.s", 35),
    "PL_GOLD_0": ("core/6502/player.s", 43),
    "PL_XP_0": ("core/6502/player.s", 46),
    "PL_MAP_X": ("core/6502/player.s", 49),
    "PL_MAP_Y": ("core/6502/player.s", 50),
    "PL_MAX_DLVL": ("core/6502/player.s", 56),
    "PL_MANA": ("core/6502/player.s", 37),
    "PL_MAX_MANA": ("core/6502/player.s", 38),
    "PL_AC": ("core/6502/player.s", 39),
    "PL_FOOD_LO": ("core/6502/player.s", 51),
    "PL_LIGHT_RAD": ("core/6502/player.s", 55),
    "PL_WEIGHT": ("core/6502/player.s", 59),      # body weight, lb (the character sheet's; the weight limit adds it)
    "PL_STRUCT_SIZE": ("core/6502/player.s", 114),
    "MAX_MONSTERS": ("core/6502/monster.s", 32),
    "TIER_DUNGEON_CREATURES": ("core/6502/monster.s", 57),      # dungeon creature rows, tier builds
    "CATALOG_DUNGEON_CREATURES": ("core/6502/monster.s", 32),   # ... monster-catalog builds
    "MAX_TOWN_CREATURES": ("core/6502/monster.s", 8),
    "MONSTER_ENTRY_SIZE": ("core/6502/monster.s", 12),
    "EMPTY_SLOT": ("core/6502/monster.s", 0xFF),
    "MX_X": ("core/6502/monster.s", 0),
    "MX_Y": ("core/6502/monster.s", 1),
    "MX_TYPE": ("core/6502/monster.s", 2),
    "MX_HP_LO": ("core/6502/monster.s", 3),
    "MX_FLAGS": ("core/6502/monster.s", 5),
    "MF_VISIBLE": ("core/6502/monster.s", 0x08),
    "MF_DETECTED": ("core/6502/monster.s", 0x10),
    "TILE_TYPE_MASK": ("core/6502/dungeon_data.s", 0xF0),
    "TILE_FLOOR": ("core/6502/dungeon_data.s", 0x00),
    "TILE_DOOR_OPEN": ("core/6502/dungeon_data.s", 0x70),
    "TILE_DOOR_CLOSED": ("core/6502/dungeon_data.s", 0x80),
    "TILE_STAIRS_DN": ("core/6502/dungeon_data.s", 0x90),
    "TILE_STAIRS_UP": ("core/6502/dungeon_data.s", 0xA0),
    "TILE_SECRET": ("core/6502/dungeon_data.s", 0xF0),
    "FLAG_OCCUPIED": ("core/6502/dungeon_data.s", 0x01),
    "FLAG_VISITED": ("core/6502/dungeon_data.s", 0x04),
    "FLAG_LIT": ("core/6502/dungeon_data.s", 0x08),
}

# KERNAL keyboard buffer (fixed by the C64 KERNAL, not the game).
KERNAL_KEYD = C64.kernal["KERNAL_KEYD"]


def _const_specs(port: Port) -> dict[str, tuple[str, int] | tuple[str, int, str]]:
    base = port.base_consts if port.base_consts is not None else CONSTS
    return {**base, **port.consts}


def tables(port: Port = C64) -> tuple[dict[str, str], dict[str, tuple[str, int]]]:
    """The labels and constants checked for ``port``: shared rows and its own."""
    base_labels = port.base_labels if port.base_labels is not None else LABELS
    consts = {name: (spec[0], spec[1]) for name, spec in _const_specs(port).items()}
    return {**base_labels, **port.labels}, consts


def parse_value(text: str) -> int:
    text = text.strip()
    if text.startswith(("0x", "0X")):
        return int(text[2:], 16)
    if text.startswith("$"):
        return int(text[1:], 16)
    if text.startswith("%"):
        return int(text[1:], 2)
    return int(text, 10)


SYM_LABEL = re.compile(r"^\s*\.label\s+(\w+)\s*=\s*\$([0-9A-Fa-f]+)")
SJASM_SYM = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*):\s*EQU\s+0x([0-9A-Fa-f]+)\b")


def parse_vs(path: Path) -> dict[str, list[int]]:
    """Multimap name -> addresses (overlay symbols can share addresses), from
    a VICE ``.vs`` file or, for a port that keeps none (the X16 or CP/M),
    KickAss/sjasmplus ``.sym``."""
    symbols: dict[str, list[int]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if path.suffix == ".sym":
            match = SYM_LABEL.match(line) or SJASM_SYM.match(line)
            if match:
                symbols.setdefault(match.group(1), []).append(int(match.group(2), 16))
            continue
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
    equ_pattern = re.compile(rf"^\s*{re.escape(name)}\s+EQU\s+(0x[0-9A-Fa-f]+|%[01]+|\d+)\b")
    for line in (root / file).read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            return parse_value(match.group(1))
        equ_match = equ_pattern.match(line.split(";", 1)[0])
        if equ_match:
            return parse_value(equ_match.group(1))
    return None


def check(vs_path: Path = C64_VS, root: Path = ROOT, port: Port = C64) -> list[str]:
    """Return every mismatch between this table and the build/sources."""
    errors: list[str] = []
    symbols = parse_vs(vs_path)
    labels, _ = tables(port)
    consts = _const_specs(port)
    for name, file in labels.items():
        addrs = symbols.get(name)
        if not addrs:
            errors.append(f"label {name} ({file}) missing from {vs_path.name}")
        elif len(set(addrs)) > 1:
            errors.append(f"label {name} is ambiguous in {vs_path.name}: {sorted(set(addrs))}")
    for virtual_name, offset, real_sym in port.zp_aliases:
        if not 0 <= offset < 256:
            errors.append(f"zp alias {virtual_name} offset {offset:#x} out of range 0..0xff")
        addrs = symbols.get(real_sym)
        if not addrs:
            errors.append(f"zp alias {virtual_name} target {real_sym} missing from {vs_path.name}")
        elif len(set(addrs)) > 1:
            errors.append(f"zp alias {virtual_name} target {real_sym} ambiguous in {vs_path.name}: {sorted(set(addrs))}")
    for name, spec in consts.items():
        file, expected = spec[0], spec[1]
        source_name = spec[2] if len(spec) == 3 else name
        actual = const_value(root, file, source_name)
        kind = "EQU" if file.endswith((".inc", ".asm")) else ".const"
        if actual is None:
            errors.append(f"{kind} {source_name} not found as a single-line literal in {file}")
        elif actual != expected:
            errors.append(f"{kind} {source_name} in {file} is {actual:#x}, table expects {expected:#x}")
    return errors


def load(vs_path: Path = C64_VS, root: Path = ROOT, port: Port = C64) -> Abi:
    errors = check(vs_path, root, port)
    if errors:
        raise RuntimeError("playtest ABI table is stale:\n  " + "\n  ".join(errors))
    symbols = parse_vs(vs_path)
    label_files, _ = tables(port)
    const_specs = _const_specs(port)
    labels = {name: symbols[name][0] for name in label_files}
    all_symbols = dict(symbols)
    for virtual_name, offset, real_sym in port.zp_aliases:
        labels[virtual_name] = offset
        all_symbols[virtual_name] = symbols[real_sym]
    consts = {**{name: spec[1] for name, spec in const_specs.items()}, **port.kernal}
    return Abi(labels, consts, all_symbols)
