#!/usr/bin/env python3
"""Balrog Save Format V2 ($22) extractor, cross-port converter, and disk packager.

Transfers real non-wizard Town checkpoints from ``var/moria8/balrog/`` (never
modifying anything inside ``var/``) to any of the seven Moria8 platforms:

- ``80x48`` (7,858 B): ``c64`` (``MORIA01\\x22``), ``atari8`` (``MORIA01\\x22``),
  ``plus4`` (``MORIA+4\\x22`` with recomputed 16-bit checksum).
- ``198x66`` (17,164 B): ``c128``, ``apple2``, ``cx16``, ``bbcmaster``
  (``MORIA01\\x22``), splicing the Balrog character's earned state
  (``player_data``, ``player_background``, ``ZP_STATE``, ``eff_fear_timer``,
  ``ZP_RNG``, ``inv_*``, ``id_known_bits``, ``flavors``, ``stores``, ``recall``)
  onto a clean native ``198x66`` Town geometry (``stairs``, ``rooms[21]``,
  ``traps``, ``monsters``, ``doors``, ``cat_slot_id``, ``floor_items``,
  ``MAP_BASE[13068]``) with the player placed on valid Town floor next to the
  down stairs at ``(31, 18)``.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BALROG_ROOT = REPO_ROOT / "var" / "moria8" / "balrog"
ITEM_SPEC_PATH = REPO_ROOT / "platforms" / "shared" / "item_catalog" / "item_catalog_spec.json"

SAVE_VERSION = 0x22
MAGIC_STD = b"MORIA01" + bytes([SAVE_VERSION])
MAGIC_PLUS4 = b"MORIA+4" + bytes([SAVE_VERSION])
MARKER_MAGIC = b"M8SAVE"

SIZE_80X48 = 7858
SIZE_198X66 = 17164

# Common V2 stream layout prefix (offsets 0..1836 identical across all ports)
OFF_MAGIC = 0
LEN_MAGIC = 8
OFF_PLAYER = 8
LEN_PLAYER = 114
OFF_BG = 122
LEN_BG = 160
OFF_ZP_STATE = 282
LEN_ZP_STATE = 32
OFF_FEAR = 314
LEN_FEAR = 1
OFF_ZP_RNG = 315
LEN_ZP_RNG = 4
OFF_INV = 319
LEN_INV = 8 * 34  # 272
OFF_KNOWN = 591
LEN_KNOWN = 47
OFF_FLAVOUR = 638
LEN_FLAVOUR = 174
OFF_STORES = 812
LEN_STORES = 8 * 128  # 1024
OFF_PREFIX_END = 1836

# player_data offsets
PL_RACE = 17
PL_CLASS = 18
PL_LEVEL = 19
PL_DLEVEL = 20
PL_HP_LO = 33
PL_MHP_LO = 35
PL_MANA = 37
PL_MAX_MANA = 38
PL_AC = 39
PL_GOLD_0 = 43
PL_XP_0 = 46
PL_MAP_X = 49
PL_MAP_Y = 50
PL_FLAGS = 54
PL_LIGHT_RAD = 55
PL_MAX_DLVL = 56
PLF_RESTING = 0x20

# ZP_STATE offsets (relative to OFF_ZP_STATE, covering $40..$5F)
ZP_GAME_FLAGS = 3       # $43 (bit 1 = GAME_FLAG_WIZARD)
ZP_MON_COUNT = 13       # $4D
ZP_ITEM_COUNT = 14      # $4E
ZP_WORD_RECALL = 30     # $5E

# Geometry + recall + map spans after OFF_PREFIX_END
LEN_STAIRS = 7
LEN_ROOMS_80X48 = 1 + 6 * 8       # 49
LEN_ROOMS_198X66 = 1 + 6 * 21     # 127
LEN_TRAPS = 1 + 3 * 16            # 49
LEN_MONSTERS = 32 * 12            # 384
LEN_DOORS = 1 + 3 * 16            # 49
LEN_CAT_SLOTS = 64
LEN_FLOOR_ITEMS = 11 * 42         # 462
LEN_RECALL = 4 * 279              # 1116
MAP_COLS_198 = 198
MAP_ROWS_66 = 66
LEN_MAP_80X48 = 80 * 48           # 3840
LEN_MAP_198X66 = MAP_COLS_198 * MAP_ROWS_66  # 13068

OFF_RECALL_80X48 = 2900
OFF_MAP_80X48 = 4016
OFF_CKSUM_80X48 = 7856

OFF_STAIRS_198X66 = 1836
OFF_ROOMS_198X66 = 1843
OFF_TRAPS_198X66 = 1970
OFF_MONSTERS_198X66 = 2019
OFF_DOORS_198X66 = 2403
OFF_CAT_SLOTS_198X66 = 2452
OFF_FLOOR_ITEMS_198X66 = 2516
OFF_RECALL_198X66 = 2978
OFF_MAP_198X66 = 4094
OFF_CKSUM_198X66 = 17162

# Town layout constants (core/6502/dungeon_data.s & core/6502/dungeon_gen.s)
TOWN_MAP_COLS = 66
TOWN_MAP_ROWS = 22
TOWN_STAIRS_X = 32
TOWN_STAIRS_Y = 18
TOWN_START_X = 31
TOWN_START_Y = 18

TILE_FLOOR = 0x00
TILE_WALL_H = 0x10
TILE_WALL_V = 0x20
TILE_CORNER_TL = 0x30
TILE_CORNER_TR = 0x40
TILE_CORNER_BL = 0x50
TILE_CORNER_BR = 0x60
TILE_DOOR_OPEN = 0x70
TILE_STAIRS_DN = 0x90
FLAG_OCCUPIED = 0x01
TOWN_FLAGS = 0x0C  # FLAG_LIT | FLAG_VISITED

STORE_POS_X = (10, 22, 34, 46, 10, 22, 34, 46)
STORE_POS_Y = (2, 2, 2, 2, 12, 12, 12, 12)
STORE_DOOR_X = (15, 27, 39, 51, 15, 27, 39, 51)
STORE_DOOR_Y = (6, 6, 6, 6, 16, 16, 16, 16)
STORE_W = 10
STORE_H = 5

RACES = ("Human", "Half-Elf", "Elf", "Halfling", "Gnome", "Dwarf", "Half-Orc", "Half-Troll")
CLASSES = ("Warrior", "Mage", "Priest", "Rogue", "Ranger", "Paladin")

PLATFORMS_80X48 = ("c64", "plus4", "atari8")
PLATFORMS_198X66 = ("c128", "apple2", "cx16", "bbcmaster")
ALL_PLATFORMS = PLATFORMS_80X48 + PLATFORMS_198X66

# 7 distinct non-wizard Town checkpoints chosen across levels, races, classes, and depths.
# 6 carry Scrolls of Word of Recall directly in pack; Halfling Rogue (cx16) has 5,976g
# and 10 Scrolls of Word of Recall in Town Temple (door at (51, 6), store '4').
BALROG_ASSIGNMENTS: dict[str, str] = {
    "c64": "20261118-221145-balrog-c64-gnome-warrior-1170785731-clvl09-ac000-xp00000368",
    "plus4": "20261118-221048-balrog-c64-half-troll-warrior-963717515-clvl12",
    "cx16": "20261119-045259-balrog-c64-halfling-rogue-1095196730-clvl15-ac044-xp00001921",
    "atari8": "20261118-210038-balrog-c64-human-ranger-1338958496-clvl26-ac044-xp00031104",
    "c128": "20261121-064538-balrog-c64-half-elf-mage-952455164-clvl28-ac047-xp00055796",
    "apple2": "20261120-011152-balrog-c64-dwarf-priest-372556219-clvl30",
    "bbcmaster": "20261121-164927-balrog-c64-elf-rogue-1423364357-clvl38-ac060-xp02049013",
}

WOR_ITEM_ID = 135  # Scroll of Word of Recall (platforms/shared/item_catalog/item_catalog_spec.json)


def _d64_ts_offset(track: int, sector: int) -> int:
    if track < 1 or track > 35:
        raise ValueError(f"invalid D64 track {track}")
    if track <= 17:
        sec_before = (track - 1) * 21
    elif track <= 24:
        sec_before = 17 * 21 + (track - 18) * 19
    elif track <= 30:
        sec_before = 17 * 21 + 7 * 19 + (track - 25) * 18
    else:
        sec_before = 17 * 21 + 7 * 19 + 6 * 18 + (track - 31) * 17
    return (sec_before + sector) * 256


def extract_d64_file(d64_path: Path, filename: str = "THE.GAME") -> bytes:
    """Read a SEQ/PRG file cleanly from a ``.d64`` image without mutating it."""
    d64_bytes = d64_path.read_bytes()
    if len(d64_bytes) < 174848:
        raise ValueError(f"{d64_path}: truncated D64 ({len(d64_bytes)} bytes)")
    track, sector = 18, 1
    visited_dir: set[tuple[int, int]] = set()
    while track != 0:
        if (track, sector) in visited_dir:
            raise ValueError(f"{d64_path}: directory cycle at ({track}, {sector})")
        visited_dir.add((track, sector))
        off = _d64_ts_offset(track, sector)
        sec = d64_bytes[off : off + 256]
        next_t, next_s = sec[0], sec[1]
        for slot in range(8):
            ent = sec[slot * 32 : (slot + 1) * 32]
            if (ent[2] & 0x07) == 0:
                continue
            raw_name = ent[5:21].split(b"\xa0")[0].decode("latin1")
            if raw_name.lower() == filename.lower():
                ft, fs = ent[3], ent[4]
                out = bytearray()
                visited_file: set[tuple[int, int]] = set()
                while ft != 0:
                    if (ft, fs) in visited_file:
                        raise ValueError(f"{d64_path}: file cycle in {filename} at ({ft}, {fs})")
                    visited_file.add((ft, fs))
                    foff = _d64_ts_offset(ft, fs)
                    fsec = d64_bytes[foff : foff + 256]
                    ft, fs = fsec[0], fsec[1]
                    if ft == 0:
                        out.extend(fsec[2 : fs + 1])
                    else:
                        out.extend(fsec[2:256])
                return bytes(out)
        track, sector = next_t, next_s
    raise FileNotFoundError(f"{filename!r} not found in {d64_path}")


def resolve_checkpoint_d64(checkpoint: str | Path) -> Path:
    """Resolve a platform name, Balrog directory name, dir Path, or save.d64 Path."""
    if isinstance(checkpoint, str) and checkpoint in BALROG_ASSIGNMENTS:
        checkpoint = BALROG_ASSIGNMENTS[checkpoint]
    p = Path(checkpoint)
    if p.is_file():
        return p
    if p.is_dir():
        d64 = p / "save.d64"
        if d64.is_file():
            return d64
    rel = BALROG_ROOT / str(checkpoint) / "save.d64"
    if rel.is_file():
        return rel
    raise FileNotFoundError(f"cannot resolve Balrog checkpoint {checkpoint!r}")


def extract_balrog_save(checkpoint: str | Path) -> bytes:
    """Extract and validate a 7,858 B ``THE.GAME`` payload from a Balrog checkpoint."""
    d64_path = resolve_checkpoint_d64(checkpoint)
    data = extract_d64_file(d64_path, "THE.GAME")
    info = verify_save(data, expected_magic=MAGIC_STD)
    if info["size"] != SIZE_80X48:
        raise ValueError(f"{d64_path}: expected 80x48 save ({SIZE_80X48} B), got {info['size']} B")
    if info["wizard_flag"]:
        raise ValueError(f"{d64_path}: wizard flag is unexpectedly set")
    return data


def compute_checksum(payload_without_cksum: bytes) -> int:
    """16-bit additive checksum across all stream bytes including 8-byte save_magic."""
    return sum(payload_without_cksum) & 0xFFFF


def recompute_checksum(payload: bytes | bytearray) -> bytes:
    """Return ``payload`` with its trailing 2-byte LE additive checksum recomputed."""
    if len(payload) not in (SIZE_80X48, SIZE_198X66):
        raise ValueError(f"unexpected V2 save length {len(payload)}")
    body = bytes(payload[:-2])
    cksum = compute_checksum(body)
    return body + bytes((cksum & 0xFF, cksum >> 8))


def decode_paged_item(slot_lo: int, ego_or_meta_hi: int) -> tuple[int | None, int]:
    """Decode V2 Base-255 9-bit item ID and 6-bit ego ID."""
    if slot_lo == 0xFF:
        return None, 0
    item_id = slot_lo + (255 if (ego_or_meta_hi & 0x40) else 0)
    return item_id, ego_or_meta_hi & 0x3F


def verify_save(data: bytes, *, expected_magic: bytes | None = None) -> dict:
    """Validate Save Format V2 ($22) stream header, length, checksum, and parsed summary."""
    if len(data) not in (SIZE_80X48, SIZE_198X66):
        raise ValueError(f"invalid V2 save size {len(data)} (expected {SIZE_80X48} or {SIZE_198X66})")
    magic = data[:LEN_MAGIC]
    if expected_magic is not None and magic != expected_magic:
        raise ValueError(f"magic mismatch: got {magic!r}, expected {expected_magic!r}")
    if magic not in (MAGIC_STD, MAGIC_PLUS4):
        raise ValueError(f"invalid V2 magic {magic!r}")
    stored_cksum = int.from_bytes(data[-2:], "little")
    calc_cksum = compute_checksum(data[:-2])
    if stored_cksum != calc_cksum:
        raise ValueError(f"checksum mismatch: stored {stored_cksum:#06x}, calculated {calc_cksum:#06x}")

    pl = data[OFF_PLAYER : OFF_PLAYER + LEN_PLAYER]
    zp = data[OFF_ZP_STATE : OFF_ZP_STATE + LEN_ZP_STATE]
    inv = data[OFF_INV : OFF_INV + LEN_INV]
    inv_id, inv_qty, inv_ego = inv[0:34], inv[34:68], inv[238:272]
    wor_qty = sum(inv_qty[i] for i in range(34) if decode_paged_item(inv_id[i], inv_ego[i])[0] == WOR_ITEM_ID)
    stores = data[OFF_STORES : OFF_STORES + LEN_STORES]
    si_id, si_qty, si_meta_hi = stores[0:128], stores[128:256], stores[896:1024]
    store_wor = sum(si_qty[i] for i in range(128) if decode_paged_item(si_id[i], si_meta_hi[i])[0] == WOR_ITEM_ID)

    return {
        "size": len(data),
        "layout": "80x48" if len(data) == SIZE_80X48 else "198x66",
        "magic": magic,
        "checksum": stored_cksum,
        "race": RACES[pl[PL_RACE]] if pl[PL_RACE] < len(RACES) else f"race#{pl[PL_RACE]}",
        "class": CLASSES[pl[PL_CLASS]] if pl[PL_CLASS] < len(CLASSES) else f"class#{pl[PL_CLASS]}",
        "clvl": pl[PL_LEVEL],
        "dlvl": pl[PL_DLEVEL],
        "max_dl": pl[PL_MAX_DLVL],
        "hp": pl[PL_HP_LO] | (pl[PL_HP_LO + 1] << 8),
        "mhp": pl[PL_MHP_LO] | (pl[PL_MHP_LO + 1] << 8),
        "mp": pl[PL_MANA],
        "mmp": pl[PL_MAX_MANA],
        "ac": pl[PL_AC],
        "gold": pl[PL_GOLD_0] | (pl[PL_GOLD_0 + 1] << 8) | (pl[PL_GOLD_0 + 2] << 16),
        "xp": pl[PL_XP_0] | (pl[PL_XP_0 + 1] << 8) | (pl[PL_XP_0 + 2] << 16),
        "x": pl[PL_MAP_X],
        "y": pl[PL_MAP_Y],
        "wor_qty": wor_qty,
        "store_wor": store_wor,
        "wor_timer": zp[ZP_WORD_RECALL],
        "wizard_flag": bool(zp[ZP_GAME_FLAGS] & 0x02),
    }


def build_clean_town_map_198x66() -> bytes:
    """Build the exact 198x66 Town backing map matching ``core/6502/dungeon_gen.s:town_generate``."""
    m = bytearray([TILE_WALL_H] * LEN_MAP_198X66)

    def put(x: int, y: int, val: int) -> None:
        m[y * MAP_COLS_198 + x] = val

    # Step 2: 66x22 playable town floor rectangle
    for y in range(TOWN_MAP_ROWS):
        row_off = y * MAP_COLS_198
        m[row_off : row_off + TOWN_MAP_COLS] = bytes([TILE_FLOOR | TOWN_FLAGS] * TOWN_MAP_COLS)

    # Step 3: Outer boundary walls
    put(0, 0, TILE_CORNER_TL | TOWN_FLAGS)
    put(TOWN_MAP_COLS - 1, 0, TILE_CORNER_TR | TOWN_FLAGS)
    put(0, TOWN_MAP_ROWS - 1, TILE_CORNER_BL | TOWN_FLAGS)
    put(TOWN_MAP_COLS - 1, TOWN_MAP_ROWS - 1, TILE_CORNER_BR | TOWN_FLAGS)
    for x in range(1, TOWN_MAP_COLS - 1):
        put(x, 0, TILE_WALL_H | TOWN_FLAGS)
        put(x, TOWN_MAP_ROWS - 1, TILE_WALL_H | TOWN_FLAGS)
    for y in range(1, TOWN_MAP_ROWS - 1):
        put(0, y, TILE_WALL_V | TOWN_FLAGS)
        put(TOWN_MAP_COLS - 1, y, TILE_WALL_V | TOWN_FLAGS)

    # Step 4: 8 store buildings
    for idx in range(8):
        left = STORE_POS_X[idx]
        top = STORE_POS_Y[idx]
        right = left + STORE_W - 1
        bot = top + STORE_H - 1
        put(left, top, TILE_CORNER_TL | TOWN_FLAGS)
        put(right, top, TILE_CORNER_TR | TOWN_FLAGS)
        put(left, bot, TILE_CORNER_BL | TOWN_FLAGS)
        put(right, bot, TILE_CORNER_BR | TOWN_FLAGS)
        for x in range(left + 1, right):
            put(x, top, TILE_WALL_H | TOWN_FLAGS)
            put(x, bot, TILE_WALL_H | TOWN_FLAGS)
        for y in range(top + 1, bot):
            put(left, y, TILE_WALL_V | TOWN_FLAGS)
            put(right, y, TILE_WALL_V | TOWN_FLAGS)
            for x in range(left + 1, right):
                put(x, y, TILE_WALL_H)
        put(STORE_DOOR_X[idx], STORE_DOOR_Y[idx], TILE_DOOR_OPEN | TOWN_FLAGS)

    # Step 5: Down stairs
    put(TOWN_STAIRS_X, TOWN_STAIRS_Y, TILE_STAIRS_DN | TOWN_FLAGS)
    return bytes(m)


def build_clean_town_198x66(*, magic: bytes = MAGIC_STD) -> bytes:
    """Build a valid empty 17,164 B native 198x66 Town save with player at ``(31, 18)``."""
    if len(magic) != LEN_MAGIC:
        raise ValueError("magic must be 8 bytes")
    pl = bytearray(LEN_PLAYER)
    pl[PL_LEVEL] = 1
    pl[PL_DLEVEL] = 0
    pl[PL_MAP_X] = TOWN_START_X
    pl[PL_MAP_Y] = TOWN_START_Y
    pl[PL_LIGHT_RAD] = 1
    pl[PL_MAX_DLVL] = 0

    out = bytearray()
    out.extend(magic)
    out.extend(pl)
    out.extend(bytes(LEN_BG + LEN_ZP_STATE + LEN_FEAR + LEN_ZP_RNG))
    out.extend(bytes([0xFF] * 34))
    out.extend(bytes(7 * 34))
    out.extend(bytes(LEN_KNOWN + LEN_FLAVOUR))
    out.extend(bytes([0xFF] * 128))
    out.extend(bytes(7 * 128))
    out.extend(bytes(LEN_STAIRS + LEN_ROOMS_198X66 + LEN_TRAPS))
    out.extend(bytes([0xFF] * LEN_MONSTERS))  # monster_table empty
    out.extend(bytes(LEN_DOORS))
    out.extend(bytes(32))                    # cat_slot_id_lo
    out.extend(bytes([0xFF] * 32))           # cat_slot_id_hi: empty
    out.extend(bytes([0xFF] * 42))           # fi_item_id: empty
    out.extend(bytes(10 * 42))               # remaining 10 floor-item arrays
    out.extend(bytes(LEN_RECALL))
    out.extend(build_clean_town_map_198x66())
    out.extend(b"\x00\x00")
    assert len(out) == SIZE_198X66
    return recompute_checksum(out)


def to_80x48_save(balrog_bytes: bytes, platform: str) -> bytes:
    """Convert an 80x48 Balrog save for ``c64``, ``atari8``, or ``plus4``."""
    if platform not in PLATFORMS_80X48:
        raise ValueError(f"{platform!r} is not an 80x48 platform")
    verify_save(balrog_bytes, expected_magic=MAGIC_STD)
    out = bytearray(balrog_bytes)
    magic = MAGIC_PLUS4 if platform == "plus4" else MAGIC_STD
    out[0:LEN_MAGIC] = magic
    return recompute_checksum(out)


def to_198x66_save(
    balrog_bytes: bytes,
    native_template: bytes | None = None,
    *,
    magic: bytes = MAGIC_STD,
) -> bytes:
    """Splice an 80x48 Balrog Town save onto a clean native 198x66 Town save."""
    info = verify_save(balrog_bytes, expected_magic=MAGIC_STD)
    if info["size"] != SIZE_80X48:
        raise ValueError(f"expected 80x48 Balrog source ({SIZE_80X48} B), got {info['size']} B")
    if info["dlvl"] != 0:
        raise ValueError(f"Balrog source must be in Town (dlvl=0), got dlvl={info['dlvl']}")
    if info["wizard_flag"]:
        raise ValueError("Balrog source has wizard flag set")

    if native_template is None:
        native_template = build_clean_town_198x66(magic=magic)
    else:
        tinfo = verify_save(native_template, expected_magic=magic)
        if tinfo["size"] != SIZE_198X66:
            raise ValueError(f"expected 198x66 template ({SIZE_198X66} B), got {tinfo['size']} B")
        if tinfo["dlvl"] != 0:
            raise ValueError(f"native template must be in Town (dlvl=0), got dlvl={tinfo['dlvl']}")

    # Validate template player (x, y) is on a walkable, unoccupied Town floor tile.
    tpl_x = native_template[OFF_PLAYER + PL_MAP_X]
    tpl_y = native_template[OFF_PLAYER + PL_MAP_Y]
    if not (1 <= tpl_x < TOWN_MAP_COLS - 1 and 1 <= tpl_y < TOWN_MAP_ROWS - 1):
        raise ValueError(f"template player position ({tpl_x}, {tpl_y}) outside Town interior")
    tile = native_template[OFF_MAP_198X66 + tpl_y * MAP_COLS_198 + tpl_x]
    if (tile & 0xF0) not in (TILE_FLOOR, TILE_STAIRS_DN, TILE_DOOR_OPEN) or (tile & FLAG_OCCUPIED):
        raise ValueError(f"template player tile ({tpl_x}, {tpl_y}) = {tile:#04x} is not clean walkable floor")

    out = bytearray(native_template)
    out[0:LEN_MAGIC] = magic
    # Copy earned character state: player_data..stores (offsets 8..1836)
    out[OFF_PLAYER:OFF_PREFIX_END] = balrog_bytes[OFF_PLAYER:OFF_PREFIX_END]
    # Restore template Town position and ensure clean non-resting Town state
    out[OFF_PLAYER + PL_DLEVEL] = 0
    out[OFF_PLAYER + PL_MAP_X] = tpl_x
    out[OFF_PLAYER + PL_MAP_Y] = tpl_y
    out[OFF_PLAYER + PL_FLAGS] &= ~PLF_RESTING
    # Clear zp_mon_count / zp_item_count (also recounted by load_game) and ensure non-wizard
    out[OFF_ZP_STATE + ZP_MON_COUNT] = 0
    out[OFF_ZP_STATE + ZP_ITEM_COUNT] = 0
    out[OFF_ZP_STATE + ZP_GAME_FLAGS] &= ~0x02

    # Copy monster recall (1,116 B: 80x48 @ 2900..4016 -> 198x66 @ 2978..4094)
    out[OFF_RECALL_198X66 : OFF_RECALL_198X66 + LEN_RECALL] = balrog_bytes[
        OFF_RECALL_80X48 : OFF_RECALL_80X48 + LEN_RECALL
    ]

    result = recompute_checksum(out)
    verify_save(result, expected_magic=magic)
    return result


def convert_save_for_platform(
    source: str | Path | bytes,
    platform: str,
    native_template: bytes | None = None,
) -> bytes:
    """Convert a Balrog checkpoint (name, path, or bytes) into a target platform's V2 save."""
    if platform not in ALL_PLATFORMS:
        raise ValueError(f"unknown platform {platform!r}; expected one of {ALL_PLATFORMS}")
    if isinstance(source, (bytes, bytearray)):
        balrog_bytes = bytes(source)
    else:
        balrog_bytes = extract_balrog_save(source)
    if platform in PLATFORMS_80X48:
        return to_80x48_save(balrog_bytes, platform)
    return to_198x66_save(balrog_bytes, native_template=native_template, magic=MAGIC_STD)


def package_cbm_save_disk(
    save_bytes: bytes,
    out_disk: Path,
    *,
    disk_type: str | None = None,
    label: str = "moria8 save,m8",
    c1541: str = "c1541",
) -> Path:
    """Write a Commodore ``.d64`` or ``.d71`` Save Disk with ``MORIA8.ID`` and ``THE.GAME``."""
    fmt = disk_type or ("d71" if out_disk.suffix.lower() == ".d71" else "d64")
    if fmt not in ("d64", "d71"):
        raise ValueError(f"unsupported CBM disk format {fmt!r}")
    verify_save(save_bytes)
    out_disk.parent.mkdir(parents=True, exist_ok=True)
    out_disk.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        marker_path = tmp / "MORIA8.ID"
        save_path = tmp / "THE.GAME"
        marker_path.write_bytes(MARKER_MAGIC)
        save_path.write_bytes(save_bytes)
        subprocess.run(
            [
                c1541,
                "-format",
                label,
                fmt,
                str(out_disk),
                "-attach",
                str(out_disk),
                "-write",
                str(marker_path),
                "moria8.id,s",
                "-write",
                str(save_path),
                "the.game,s",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    return out_disk


def _cmd_list() -> int:
    for plat, dirname in BALROG_ASSIGNMENTS.items():
        raw = extract_balrog_save(dirname)
        info = verify_save(raw)
        print(
            f"{plat:10s} | {info['race']:10s} {info['class']:8s} "
            f"clvl={info['clvl']:2d} maxDL={info['max_dl']:2d} "
            f"HP={info['hp']:3d}/{info['mhp']:3d} MP={info['mp']:3d}/{info['mmp']:3d} "
            f"AC={info['ac']:2d} gold={info['gold']:8d} WoR={info['wor_qty']:2d}(st={info['store_wor']:2d}) | {dirname}"
        )
    return 0


def _cmd_inspect(target: Path) -> int:
    data = extract_d64_file(target, "THE.GAME") if target.suffix.lower() in (".d64", ".d71") else target.read_bytes()
    info = verify_save(data)
    print(json.dumps({**info, "magic": info["magic"].decode("latin1")}, indent=2))
    return 0


def _cmd_export(args: argparse.Namespace) -> int:
    src = args.checkpoint or args.platform
    tpl = Path(args.template).read_bytes() if args.template else None
    payload = convert_save_for_platform(src, args.platform, native_template=tpl)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    if args.disk or out.suffix.lower() in (".d64", ".d71"):
        if args.platform not in ("c64", "plus4", "c128"):
            raise SystemExit("--disk / .d64 / .d71 output is only for Commodore platforms")
        package_cbm_save_disk(payload, out)
    else:
        out.write_bytes(payload)
    info = verify_save(payload)
    print(
        f"wrote {out} ({info['layout']}, {info['size']} B, cksum={info['checksum']:#06x}): "
        f"{info['race']} {info['class']} clvl {info['clvl']} maxDL {info['max_dl']}"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Balrog Save Format V2 ($22) transfer tool")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="Inspect the 7 assigned Balrog saves")

    p_ins = sub.add_parser("inspect", help="Inspect a raw save file or .d64/.d71 save disk")
    p_ins.add_argument("target", type=Path)

    p_exp = sub.add_parser("export", help="Convert a Balrog checkpoint for a target platform")
    p_exp.add_argument("platform", choices=ALL_PLATFORMS)
    p_exp.add_argument("output", type=Path)
    p_exp.add_argument("--checkpoint", help="Override Balrog dir or save.d64 path (defaults to platform assignment)")
    p_exp.add_argument("--template", help="Optional native 198x66 Town save file to splice onto")
    p_exp.add_argument("--disk", action="store_true", help="Package output as a Commodore .d64/.d71 save disk")

    args = ap.parse_args(argv)
    if args.cmd == "list":
        return _cmd_list()
    if args.cmd == "inspect":
        return _cmd_inspect(args.target)
    if args.cmd == "export":
        return _cmd_export(args)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
