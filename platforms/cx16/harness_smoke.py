#!/usr/bin/env python3
"""Runtime smoke checks for the Commander X16 runtime.

This speaks x16emu's documented -testbench protocol directly. It intentionally
tests RAM-visible contracts instead of screenshots: the CX16 port is still a
runtime, and map/player/town-interaction state is the stable contract.
"""

import argparse
import os
import select
import subprocess
import sys
import time

from check_memory_contract import (
    CX16_BANKED_RAM_BASE,
    CX16_RAM_BANK_REG,
    check_product_symbols,
)


STATUS_CARRY = 0x01
TOWN_FLAGS = 0x0C
TILE_FLOOR = 0x00
TILE_WALL_H = 0x10
TILE_DOOR_OPEN = 0x70
TILE_DOOR_CLOSED = 0x80
TILE_STAIRS_DN = 0x90
TILE_STAIRS_UP = 0xA0
TILE_RUBBLE = 0xB0
TILE_QUARTZ = 0xD0
TILE_TRAP = 0xE0
TILE_TYPE_MASK = 0xF0
DUNGEON_FLAGS = 0x0C
FLAG_HAS_ITEM = 0x02
FLAG_OCCUPIED = 0x01
VIEWPORT_X = 1
VIEWPORT_Y = 2
PL_RACE = 17
PL_CLASS = 18
PL_LEVEL = 19
PL_INT_CUR = 28
PL_DEX_CUR = 30
PL_CON_CUR = 31
PL_HP_LO = 33
PL_HP_HI = 34
PL_MHP_LO = 35
PL_MHP_HI = 36
PL_MANA = 37
PL_MAX_MANA = 38
PL_AC = 39
PL_TOHIT = 40
PL_TODMG = 41
PL_GOLD_0 = 43
PL_XP_0 = 46
PL_XP_1 = 47
PL_XP_2 = 48
PL_XP_FRAC_LO = 109
PL_XP_FRAC_HI = 110
PL_FOOD_LO = 51
PL_FOOD_HI = 52
PL_FLAGS = 54
PL_MAX_DLVL = 56
PL_EXPFACT = 106
PLF_MALE = 0x01
PLF_SEARCHING = 0x10
KEYBUF = 0xA800
KEYBUF_COUNT = 0xA80A
MAP_COLS = 198
MAP_ROWS = 66
MAX_FLOOR_ITEMS = 42
MAX_INV_SLOTS = 22
MAX_MONSTERS = 32
MONSTER_ENTRY_SIZE = 12
MX_X = 0
MX_Y = 1
MX_TYPE = 2
MX_HP_LO = 3
MX_HP_HI = 4
MX_FLAGS = 5
EMPTY_SLOT = 0xFF
EQUIP_LIGHT = 28
EQUIP_WEAPON = 22
EQUIP_BODY = 23
ITEM_LEATHER_ARMOR = 7
ITEM_LANTERN = 14
ITEM_RATION = 15
ITEM_POTION_CURE = 17
ITEM_SCROLL_LIGHT = 20
ITEM_WAND_LIGHT = 39
ITEM_STAFF_DETECT = 44
ITEM_FLASK_OIL = 61
ITEM_PICK = 63
STARTING_PICK_DIG_ABILITY = 24
ICAT_WEAPON = 2
FI_EMPTY = 0xFF
CLEAR_SENTINEL_ROW = 24
CLEAR_SENTINEL_COL = 0
CMD_NONE = 0x00
CMD_MOVE_N = 0x01
CMD_MOVE_W = 0x03
CMD_MOVE_S = 0x02
CMD_MOVE_E = 0x04
CMD_MOVE_NW = 0x05
CMD_MOVE_NE = 0x06
CMD_MOVE_SW = 0x07
CMD_MOVE_SE = 0x08
CMD_REST = 0x0B
CMD_SEARCH = 0x0C
CMD_OPEN = 0x0D
CMD_CLOSE = 0x0E
CMD_PICKUP = 0x0F
CMD_DROP = 0x10
CMD_INVENTORY = 0x11
CMD_EQUIPMENT = 0x12
CMD_WEAR = 0x13
CMD_TAKEOFF = 0x14
CMD_EAT = 0x15
CMD_QUAFF = 0x16
CMD_READ = 0x17
CMD_AIM = 0x18
CMD_USE = 0x19
CMD_CAST = 0x1A
CMD_PRAY = 0x1B
CMD_CHAR_INFO = 0x1C
CMD_MAP = 0x1D
CMD_RECALL = 0x1E
CMD_LOOK = 0x1F
CMD_RUN = 0x20
CMD_SAVE = 0x21
CMD_QUIT = 0x22
CMD_HELP = 0x23
CMD_VERSION = 0x24
CMD_RUN_N = 0x25
CMD_RUN_S = 0x26
CMD_RUN_W = 0x27
CMD_RUN_E = 0x28
CMD_RUN_NW = 0x29
CMD_RUN_NE = 0x2A
CMD_RUN_SW = 0x2B
CMD_RUN_SE = 0x2C
CMD_GAIN = 0x2D
CMD_FIRE = 0x2E
CMD_THROW = 0x2F
CMD_REFUEL = 0x30
CMD_BASH = 0x31
CMD_TUNNEL = 0x32
CMD_WIZARD = 0x33
CMD_SEARCH_MODE = 0x34
CMD_DISARM = 0x35
CMD_AUTOREST = 0x36
CX16_STATE_TITLE = 0
CX16_STATE_NEW_GAME = 1
CX16_STATE_DUNGEON = 2
CX16_STATE_DEAD = 3
GAME_FLAG_WINNER = 0x04
CREATURE_BALROG = 56
CREATURE_BALROG_TIER = 4
SC_PLAYER = 0x00
SC_REVERSE_SPACE = 0xA0
TEXT_COLOR = 0x01
COL_WHITE = 0x01
COL_GREEN = 0x05
STORE_COLOR = 0x07
TITLE_BORDER_COLOR = 0x0F
CX16_TRANSFER_TEST_BANK = 2
CX16_TRANSFER_GUARD_BANK = 3
CX16_TRANSFER_TEST_OFFSET = 0x00F0
CX16_TRANSFER_TEST_COUNT = 0x0104
CX16_TIER1_BANK = 4
CX16_TIER_GUARD_BANK = 3
CX16_DUNGEON_MODULE_BANK = 8
CX16_DUNGEON_MODULE_GUARD_BANK = 3
CX16_ITEM_CATALOG_BANK = 9
CX16_ITEM_CATALOG_GUARD_BANK = 3
CX16_OVERLAY_DEATH_BANK = 14
VERA_ADDR_L = 0x9F20
VERA_ADDR_M = 0x9F21
VERA_ADDR_H = 0x9F22
VERA_DATA0 = 0x9F23
VERA_CTRL = 0x9F25
VERA_INC_1 = 0x10
VERA_TEXT_BASE = 0x1B000
VERA_TEXT_ROW_STRIDE = 256


class X16Bench:
    def __init__(self, x16emu, rom, prg, cwd):
        cmd = [x16emu, "-testbench", "-warp"]
        if rom:
            cmd.extend(["-rom", rom])
        cmd.extend(["-prg", prg])
        self.proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            cwd=cwd,
        )
        self.last_command = "startup"
        self.last_a = None
        self.wait_ready()

    def close(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=2)

    def _readline(self, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            wait = max(0.0, deadline - time.monotonic())
            ready, _, _ = select.select([self.proc.stdout], [], [], wait)
            if not ready:
                continue
            line = self.proc.stdout.readline()
            if line:
                return line.strip()
            if self.proc.poll() is not None:
                raise RuntimeError(f"x16emu exited with status {self.proc.returncode}")
            time.sleep(0.01)
        raise TimeoutError(f"timed out waiting for x16emu output after {self.last_command}")

    def wait_ready(self, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            line = self._readline(timeout=max(0.1, deadline - time.monotonic()))
            if line.startswith("ERR"):
                raise RuntimeError(line)
            if line == "RDY":
                return
        raise TimeoutError("timed out waiting for RDY")

    def command(self, text, wait=True):
        self.last_command = text
        self.proc.stdin.write(text + "\n")
        self.proc.stdin.flush()
        if wait:
            self.wait_ready()

    def run(self, address, timeout=5):
        suffix = "" if self.last_a is None else f" A={self.last_a:02X}"
        self.last_command = f"RUN {address:04X}{suffix}"
        self.proc.stdin.write(f"RUN {address:04X}\n")
        self.proc.stdin.flush()
        self.wait_ready(timeout=timeout)

    def set_memory(self, address, value):
        self.command(f"STM {address:04X} {value:02X}")

    def set_a(self, value):
        self.last_a = value
        self.command(f"STA {value:02X}")

    def get_memory(self, address):
        self.command(f"RQM {address:04X}", wait=False)
        return int(self._readline(), 16)

    def get_a(self):
        self.command("RQA", wait=False)
        return int(self._readline(), 16)

    def get_status(self):
        self.command("RST", wait=False)
        return int(self._readline(), 16)


def load_symbols(path):
    labels = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line.startswith(".label "):
                continue
            name_value = line[len(".label ") :].split()[0]
            if "=" not in name_value:
                continue
            name, value = name_value.split("=", 1)
            if value.startswith("$"):
                labels[name] = int(value[1:], 16)
    return labels


def require(labels, name):
    try:
        return labels[name]
    except KeyError:
        raise AssertionError(f"missing symbol: {name}") from None


def map_tile_at(bench, labels, x, y):
    return bench.get_memory(map_row_addr(bench, labels, y) + x)


def map_row_addr(bench, labels, y):
    row_lo = require(labels, "map_row_lo")
    row_hi = require(labels, "map_row_hi")
    return bench.get_memory(row_lo + y) | (bench.get_memory(row_hi + y) << 8)


def screen_code(ch):
    value = ord(ch)
    if 97 <= value <= 122:
        return value - 96
    if ch == "@":
        return SC_PLAYER
    return value


def vera_set_addr(bench, address):
    bench.set_memory(VERA_CTRL, 0)
    bench.set_memory(VERA_ADDR_L, address & 0xFF)
    bench.set_memory(VERA_ADDR_M, (address >> 8) & 0xFF)
    bench.set_memory(VERA_ADDR_H, VERA_INC_1 | ((address >> 16) & 0x01))


def screen_cell_addr(row, col):
    return VERA_TEXT_BASE + (row * VERA_TEXT_ROW_STRIDE) + (col * 2)


def screen_char_at(bench, row, col):
    vera_set_addr(bench, screen_cell_addr(row, col))
    return bench.get_memory(VERA_DATA0)


def screen_attr_at(bench, row, col):
    vera_set_addr(bench, screen_cell_addr(row, col) + 1)
    return bench.get_memory(VERA_DATA0)


def screen_put_cell_raw(bench, row, col, char_code, attr):
    vera_set_addr(bench, screen_cell_addr(row, col))
    bench.set_memory(VERA_DATA0, char_code)
    bench.set_memory(VERA_DATA0, attr)


def stuff_key(bench, petscii):
    saved_bank = bench.get_memory(CX16_RAM_BANK_REG)
    bench.set_memory(CX16_RAM_BANK_REG, 0)
    bench.set_memory(KEYBUF_COUNT, 0)
    for offset in range(10):
        bench.set_memory(KEYBUF + offset, petscii)
    bench.set_memory(KEYBUF_COUNT, 1)
    bench.set_memory(CX16_RAM_BANK_REG, saved_bank)


def set_key_held(bench, held):
    saved_bank = bench.get_memory(CX16_RAM_BANK_REG)
    bench.set_memory(CX16_RAM_BANK_REG, 0)
    bench.set_memory(KEYBUF_COUNT, 1 if held else 0)
    bench.set_memory(CX16_RAM_BANK_REG, saved_bank)


def set_inventory_slot(bench, labels, slot, item_id, qty=1, p1=0, to_hit=0, to_dam=0, to_ac=0):
    bench.set_memory(require(labels, "inv_item_id") + slot, item_id)
    bench.set_memory(require(labels, "inv_qty") + slot, qty)
    bench.set_memory(require(labels, "inv_p1") + slot, p1)
    bench.set_memory(require(labels, "inv_to_hit") + slot, to_hit)
    bench.set_memory(require(labels, "inv_to_dam") + slot, to_dam)
    bench.set_memory(require(labels, "inv_to_ac") + slot, to_ac)
    bench.set_memory(require(labels, "inv_flags") + slot, 0)
    bench.set_memory(require(labels, "inv_ego") + slot, 0)


def set_inventory_slot0(bench, labels, item_id, qty=1, p1=0):
    set_inventory_slot(bench, labels, 0, item_id, qty=qty, p1=p1)


def add_floor_item(bench, labels, x, y, item_id):
    bench.set_memory(require(labels, "fi_add_x"), x)
    bench.set_memory(require(labels, "fi_add_y"), y)
    bench.set_memory(require(labels, "fi_add_id"), item_id)
    bench.set_memory(require(labels, "fi_add_qty"), 1)
    bench.set_memory(require(labels, "fi_add_p1"), 0)
    bench.set_memory(require(labels, "fi_add_to_hit"), 0)
    bench.set_memory(require(labels, "fi_add_to_dam"), 0)
    bench.set_memory(require(labels, "fi_add_to_ac"), 0)
    bench.set_memory(require(labels, "fi_add_flags"), 0)
    bench.set_memory(require(labels, "fi_add_ego"), 0)
    bench.run(require(labels, "floor_item_add"))
    if not (bench.get_status() & STATUS_CARRY):
        raise AssertionError("floor_item_add failed")


def assert_eq(actual, expected, label):
    if actual != expected:
        raise AssertionError(f"{label}: expected ${expected:02X}, got ${actual:02X}")


def assert_screen_text(bench, row, col, text, label):
    for offset, ch in enumerate(text):
        actual = screen_char_at(bench, row, col + offset)
        expected = screen_code(ch)
        assert_eq(actual, expected, f"{label} char {offset}")


def assert_screen_text_matches(bench, row, col, text):
    for offset, ch in enumerate(text):
        if screen_char_at(bench, row, col + offset) != screen_code(ch):
            return False
    return True


def assert_screen_cell(bench, row, col, char_code, attr, label):
    assert_eq(screen_char_at(bench, row, col), char_code, f"{label} char")
    assert_eq(screen_attr_at(bench, row, col), attr, f"{label} attr")


def assert_screen_contains_cell(bench, char_code, attr, label):
    for row in range(30):
        for col in range(80):
            if screen_char_at(bench, row, col) == char_code and screen_attr_at(bench, row, col) == attr:
                return row, col
    raise AssertionError(f"{label}: screen cell not found")


def set_player_position(bench, labels, x, y):
    bench.set_memory(require(labels, "cx16_player_x"), x)
    bench.set_memory(require(labels, "cx16_player_y"), y)
    bench.set_memory(require(labels, "zp_player_x"), x)
    bench.set_memory(require(labels, "zp_player_y"), y)


def assert_player_position(bench, labels, x, y, label):
    assert_eq(bench.get_memory(require(labels, "cx16_player_x")), x, f"{label} local x")
    assert_eq(bench.get_memory(require(labels, "cx16_player_y")), y, f"{label} local y")
    assert_eq(bench.get_memory(require(labels, "zp_player_x")), x, f"{label} shared x")
    assert_eq(bench.get_memory(require(labels, "zp_player_y")), y, f"{label} shared y")


def assert_map_tile(bench, labels, x, y, expected, label):
    assert_eq(map_tile_at(bench, labels, x, y), expected, label)


def reset_turn(bench, labels):
    bench.set_memory(require(labels, "zp_turn_lo"), 0)
    bench.set_memory(require(labels, "zp_turn_hi"), 0)


def assert_turns(bench, labels, expected, label):
    assert_eq(bench.get_memory(require(labels, "zp_turn_lo")), expected & 0xFF, f"{label} turn lo")
    assert_eq(bench.get_memory(require(labels, "zp_turn_hi")), (expected >> 8) & 0xFF, f"{label} turn hi")


def set_map_tile(bench, labels, x, y, value):
    bench.set_memory(map_row_addr(bench, labels, y) + x, value)


def assert_map_tile_type(bench, labels, x, y, expected_type, label):
    assert_eq(tile_type(map_tile_at(bench, labels, x, y)), expected_type, label)


def tile_type(tile):
    return tile & TILE_TYPE_MASK


def assert_floor_items_spawned(bench, labels):
    item_count = bench.get_memory(require(labels, "zp_item_count"))
    if item_count == 0:
        raise AssertionError("dungeon entry did not spawn floor items")

    item_base = require(labels, "fi_item_id")
    item_x_base = require(labels, "fi_x")
    item_y_base = require(labels, "fi_y")
    seen = set()
    occupied_slots = 0
    for slot in range(MAX_FLOOR_ITEMS):
        item_id = bench.get_memory(item_base + slot)
        if item_id == 0xFF:
            continue
        occupied_slots += 1
        x = bench.get_memory(item_x_base + slot)
        y = bench.get_memory(item_y_base + slot)
        if (x, y) in seen:
            raise AssertionError(f"generated floor items stacked at ({x},{y})")
        seen.add((x, y))
        tile = map_tile_at(bench, labels, x, y)
        if not (tile & FLAG_HAS_ITEM):
            raise AssertionError(f"floor item slot {slot} at ({x},{y}) missing FLAG_HAS_ITEM")
        if tile & FLAG_OCCUPIED:
            raise AssertionError(f"floor item slot {slot} at ({x},{y}) is under a monster")

    if occupied_slots == 0:
        raise AssertionError("zp_item_count is nonzero but no occupied floor item slot was found")


def top_floor_item_slot_at(bench, labels, x, y):
    item_base = require(labels, "fi_item_id")
    item_x_base = require(labels, "fi_x")
    item_y_base = require(labels, "fi_y")
    for slot in range(MAX_FLOOR_ITEMS - 1, -1, -1):
        if bench.get_memory(item_base + slot) == FI_EMPTY:
            continue
        if bench.get_memory(item_x_base + slot) == x and bench.get_memory(item_y_base + slot) == y:
            return slot
    raise AssertionError(f"no floor item at ({x},{y})")


def find_top_floor_item_by_id(bench, labels, wanted_item_id):
    item_base = require(labels, "fi_item_id")
    item_x_base = require(labels, "fi_x")
    item_y_base = require(labels, "fi_y")
    for slot in range(MAX_FLOOR_ITEMS - 1, -1, -1):
        if bench.get_memory(item_base + slot) != wanted_item_id:
            continue
        x = bench.get_memory(item_x_base + slot)
        y = bench.get_memory(item_y_base + slot)
        if top_floor_item_slot_at(bench, labels, x, y) == slot:
            tile = map_tile_at(bench, labels, x, y)
            if not (tile & FLAG_HAS_ITEM):
                raise AssertionError(f"floor item {wanted_item_id} at ({x},{y}) missing FLAG_HAS_ITEM")
            if tile & FLAG_OCCUPIED:
                raise AssertionError(f"floor item {wanted_item_id} at ({x},{y}) is under a monster")
            return slot, x, y
    raise AssertionError(f"top floor item id {wanted_item_id} not found")


def find_map_tile_type(bench, labels, wanted_type, label):
    for y in range(MAP_ROWS):
        for x in range(MAP_COLS):
            if tile_type(map_tile_at(bench, labels, x, y)) == wanted_type:
                return x, y
    raise AssertionError(f"{label}: tile type ${wanted_type:02X} not found")


def find_adjacent_tile_type(bench, labels, wanted_type, label):
    for y in range(1, MAP_ROWS - 1):
        for x in range(1, MAP_COLS - 1):
            if tile_type(map_tile_at(bench, labels, x, y)) != wanted_type:
                continue
            for px, py in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if tile_type(map_tile_at(bench, labels, px, py)) == TILE_FLOOR:
                    return x, y, px, py
    raise AssertionError(f"{label}: adjacent tile type ${wanted_type:02X} not found")


def find_adjacent_floor_move(bench, labels, x, y):
    for command, dx, dy in (
        (CMD_MOVE_E, 1, 0),
        (CMD_MOVE_W, -1, 0),
        (CMD_MOVE_S, 0, 1),
        (CMD_MOVE_N, 0, -1),
        (CMD_MOVE_SE, 1, 1),
        (CMD_MOVE_SW, -1, 1),
        (CMD_MOVE_NE, 1, -1),
        (CMD_MOVE_NW, -1, -1),
    ):
        nx = x + dx
        ny = y + dy
        if 0 <= nx < MAP_COLS and 0 <= ny < MAP_ROWS:
            if tile_type(map_tile_at(bench, labels, nx, ny)) == TILE_FLOOR:
                return command, nx, ny
    raise AssertionError("generated dungeon entry has no adjacent floor move")


def find_player_pos_to_attack(bench, labels, monster_x, monster_y):
    for command, dx, dy in (
        (CMD_MOVE_E, 1, 0),
        (CMD_MOVE_W, -1, 0),
        (CMD_MOVE_S, 0, 1),
        (CMD_MOVE_N, 0, -1),
        (CMD_MOVE_SE, 1, 1),
        (CMD_MOVE_SW, -1, 1),
        (CMD_MOVE_NE, 1, -1),
        (CMD_MOVE_NW, -1, -1),
    ):
        px = monster_x - dx
        py = monster_y - dy
        if 0 <= px < MAP_COLS and 0 <= py < MAP_ROWS:
            tile = map_tile_at(bench, labels, px, py)
            if tile_type(tile) == TILE_FLOOR and not (tile & FLAG_OCCUPIED):
                return command, px, py
    raise AssertionError("spawned monster has no adjacent floor for player attack")


def first_live_monster(bench, labels):
    base = require(labels, "monster_table")
    for slot in range(MAX_MONSTERS):
        entry = base + (slot * MONSTER_ENTRY_SIZE)
        mon_type = bench.get_memory(entry + MX_TYPE)
        if mon_type != EMPTY_SLOT:
            return (
                slot,
                bench.get_memory(entry + MX_X),
                bench.get_memory(entry + MX_Y),
                bench.get_memory(entry + MX_HP_LO),
                bench.get_memory(entry + MX_HP_HI),
            )
    raise AssertionError("no live monster found")


def clear_live_monsters(bench, labels):
    base = require(labels, "monster_table")
    for slot in range(MAX_MONSTERS):
        entry = base + (slot * MONSTER_ENTRY_SIZE)
        if bench.get_memory(entry + MX_TYPE) == EMPTY_SLOT:
            continue
        x = bench.get_memory(entry + MX_X)
        y = bench.get_memory(entry + MX_Y)
        set_map_tile(bench, labels, x, y, map_tile_at(bench, labels, x, y) & ~FLAG_OCCUPIED)
        for offset in range(MONSTER_ENTRY_SIZE):
            bench.set_memory(entry + offset, EMPTY_SLOT)
    bench.set_memory(require(labels, "zp_mon_count"), 0)


def clear_carried_inventory(bench, labels):
    inv_base = require(labels, "inv_item_id")
    for slot in range(MAX_INV_SLOTS):
        bench.set_memory(inv_base + slot, FI_EMPTY)
        bench.set_memory(require(labels, "inv_qty") + slot, 0)
        bench.set_memory(require(labels, "inv_p1") + slot, 0)
        bench.set_memory(require(labels, "inv_to_hit") + slot, 0)
        bench.set_memory(require(labels, "inv_to_dam") + slot, 0)
        bench.set_memory(require(labels, "inv_to_ac") + slot, 0)
        bench.set_memory(require(labels, "inv_flags") + slot, 0)
        bench.set_memory(require(labels, "inv_ego") + slot, 0)


def count_carried_item(bench, labels, item_id):
    inv_base = require(labels, "inv_item_id")
    total = 0
    for slot in range(MAX_INV_SLOTS):
        if bench.get_memory(inv_base + slot) == item_id:
            total += 1
    return total


def find_carried_item_slot(bench, labels, item_id):
    inv_base = require(labels, "inv_item_id")
    for slot in range(MAX_INV_SLOTS):
        if bench.get_memory(inv_base + slot) == item_id:
            return slot
    raise AssertionError(f"carried item id {item_id} not found")


def place_monster(bench, labels, slot, x, y, monster_type, hp_lo=1, hp_hi=0):
    entry = require(labels, "monster_table") + (slot * MONSTER_ENTRY_SIZE)
    for offset in range(MONSTER_ENTRY_SIZE):
        bench.set_memory(entry + offset, 0)
    bench.set_memory(entry + MX_X, x)
    bench.set_memory(entry + MX_Y, y)
    bench.set_memory(entry + MX_TYPE, monster_type)
    bench.set_memory(entry + MX_HP_LO, hp_lo)
    bench.set_memory(entry + MX_HP_HI, hp_hi)
    set_map_tile(bench, labels, x, y, map_tile_at(bench, labels, x, y) | FLAG_OCCUPIED)
    bench.set_memory(require(labels, "zp_mon_count"), bench.get_memory(require(labels, "zp_mon_count")) + 1)


def run_command_for_move(move_command):
    return {
        CMD_MOVE_N: CMD_RUN_N,
        CMD_MOVE_S: CMD_RUN_S,
        CMD_MOVE_W: CMD_RUN_W,
        CMD_MOVE_E: CMD_RUN_E,
        CMD_MOVE_NW: CMD_RUN_NW,
        CMD_MOVE_NE: CMD_RUN_NE,
        CMD_MOVE_SW: CMD_RUN_SW,
        CMD_MOVE_SE: CMD_RUN_SE,
    }[move_command]


def key_for_delta(dx, dy):
    return {
        (0, -1): ord("K"),
        (0, 1): ord("J"),
        (-1, 0): ord("H"),
        (1, 0): ord("L"),
        (-1, -1): ord("Y"),
        (1, -1): ord("U"),
        (-1, 1): ord("B"),
        (1, 1): ord("N"),
    }[(dx, dy)]


def stuff_direction_to_target(bench, player_x, player_y, target_x, target_y):
    stuff_key(bench, key_for_delta(target_x - player_x, target_y - player_y))


def build_horizontal_run_corridor(bench, labels, x0=20, y=12, length=12):
    for x in range(x0 - 1, x0 + length + 1):
        set_map_tile(bench, labels, x, y - 1, TILE_WALL_H | DUNGEON_FLAGS)
        set_map_tile(bench, labels, x, y, TILE_WALL_H | DUNGEON_FLAGS)
        set_map_tile(bench, labels, x, y + 1, TILE_WALL_H | DUNGEON_FLAGS)
    for x in range(x0, x0 + length):
        set_map_tile(bench, labels, x, y, TILE_FLOOR | DUNGEON_FLAGS)


def assert_banked_ram_isolation(bench):
    saved_bank = bench.get_memory(CX16_RAM_BANK_REG)

    bench.set_memory(CX16_RAM_BANK_REG, 0)
    bank0_saved = bench.get_memory(CX16_BANKED_RAM_BASE)
    bench.set_memory(CX16_BANKED_RAM_BASE, 0xA6)

    bench.set_memory(CX16_RAM_BANK_REG, 1)
    bank1_saved = bench.get_memory(CX16_BANKED_RAM_BASE)
    bench.set_memory(CX16_BANKED_RAM_BASE, 0x5B)

    bench.set_memory(CX16_RAM_BANK_REG, 0)
    assert_eq(bench.get_memory(CX16_BANKED_RAM_BASE), 0xA6, "bank 0 visible byte")
    bench.set_memory(CX16_BANKED_RAM_BASE, bank0_saved)

    bench.set_memory(CX16_RAM_BANK_REG, 1)
    assert_eq(bench.get_memory(CX16_BANKED_RAM_BASE), 0x5B, "bank 1 visible byte")
    bench.set_memory(CX16_BANKED_RAM_BASE, bank1_saved)

    bench.set_memory(CX16_RAM_BANK_REG, saved_bank)


def set_zp_pointer(bench, labels, name, address):
    bench.set_memory(require(labels, name), address & 0xFF)
    bench.set_memory(require(labels, f"{name}_hi"), (address >> 8) & 0xFF)


def set_transfer_count(bench, labels, count):
    bench.set_memory(require(labels, "zp_temp0"), count & 0xFF)
    bench.set_memory(require(labels, "zp_temp1"), (count >> 8) & 0xFF)


def transfer_pattern(index):
    return (0x31 + (index * 0x25)) & 0xFF


def read_prg(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if len(data) < 2:
        raise AssertionError(f"{path}: PRG is too short")
    load = data[0] | (data[1] << 8)
    return load, data[2:]


def assert_banked_transfer_helpers(bench, labels):
    saved_bank = bench.get_memory(CX16_RAM_BANK_REG)
    source = require(labels, "cx16_contract_floor_item_base")
    banked_addr = CX16_BANKED_RAM_BASE + CX16_TRANSFER_TEST_OFFSET

    for offset in range(CX16_TRANSFER_TEST_COUNT):
        bench.set_memory(source + offset, transfer_pattern(offset))

    bench.set_memory(CX16_RAM_BANK_REG, CX16_TRANSFER_TEST_BANK)
    for offset in range(CX16_TRANSFER_TEST_COUNT):
        bench.set_memory(banked_addr + offset, 0)

    bench.set_memory(CX16_RAM_BANK_REG, CX16_TRANSFER_GUARD_BANK)
    for offset in range(CX16_TRANSFER_TEST_COUNT):
        bench.set_memory(banked_addr + offset, 0xE7)

    bench.set_memory(CX16_RAM_BANK_REG, 1)
    set_zp_pointer(bench, labels, "zp_ptr0", source)
    set_zp_pointer(bench, labels, "zp_ptr1", banked_addr)
    set_transfer_count(bench, labels, CX16_TRANSFER_TEST_COUNT)
    bench.set_a(CX16_TRANSFER_TEST_BANK)
    bench.run(require(labels, "cx16_copy_fixed_to_banked"))
    assert_eq(bench.get_memory(CX16_RAM_BANK_REG), 1, "copy fixed-to-banked restored caller bank")

    bench.set_memory(CX16_RAM_BANK_REG, CX16_TRANSFER_TEST_BANK)
    for offset in range(CX16_TRANSFER_TEST_COUNT):
        assert_eq(
            bench.get_memory(banked_addr + offset),
            transfer_pattern(offset),
            f"banked copy byte {offset}",
        )

    bench.set_memory(CX16_RAM_BANK_REG, CX16_TRANSFER_GUARD_BANK)
    for offset in range(CX16_TRANSFER_TEST_COUNT):
        assert_eq(bench.get_memory(banked_addr + offset), 0xE7, f"guard bank byte {offset}")
        bench.set_memory(source + offset, 0)

    bench.set_memory(CX16_RAM_BANK_REG, 1)
    set_zp_pointer(bench, labels, "zp_ptr0", source)
    set_zp_pointer(bench, labels, "zp_ptr1", banked_addr)
    set_transfer_count(bench, labels, CX16_TRANSFER_TEST_COUNT)
    bench.set_a(CX16_TRANSFER_TEST_BANK)
    bench.run(require(labels, "cx16_copy_banked_to_fixed"))
    assert_eq(bench.get_memory(CX16_RAM_BANK_REG), 1, "copy banked-to-fixed restored caller bank")

    for offset in range(CX16_TRANSFER_TEST_COUNT):
        assert_eq(
            bench.get_memory(source + offset),
            transfer_pattern(offset),
            f"fixed copy-back byte {offset}",
        )

    bench.set_memory(CX16_RAM_BANK_REG, saved_bank)


def assert_tier_prg_load_to_bank(bench, labels, cwd):
    path = os.path.join(cwd, "MONSTER.DB.1")
    load, payload = read_prg(path)
    expected_load = require(labels, "cx16_contract_tier_load_base")
    assert_eq(load & 0xFF, expected_load & 0xFF, "tier PRG load low")
    assert_eq(load >> 8, expected_load >> 8, "tier PRG load high")

    saved_bank = bench.get_memory(CX16_RAM_BANK_REG)

    bench.set_memory(CX16_RAM_BANK_REG, CX16_TIER1_BANK)
    for offset in range(len(payload)):
        bench.set_memory(load + offset, 0)

    bench.set_memory(CX16_RAM_BANK_REG, CX16_TIER_GUARD_BANK)
    guard_offsets = list(range(0, min(16, len(payload))))
    guard_offsets.extend(range(max(0, len(payload) - 16), len(payload)))
    for offset in guard_offsets:
        bench.set_memory(load + offset, 0xE7)

    bench.set_memory(CX16_RAM_BANK_REG, 1)
    bench.set_a(1)
    bench.run(require(labels, "cx16_load_tier_to_bank"), timeout=8)
    if bench.get_status() & STATUS_CARRY:
        raise AssertionError("cx16_load_tier_to_bank reported failure")
    assert_eq(bench.get_memory(CX16_RAM_BANK_REG), 1, "tier load restored caller bank")

    bench.set_memory(CX16_RAM_BANK_REG, CX16_TIER1_BANK)
    for offset, expected in enumerate(payload):
        assert_eq(bench.get_memory(load + offset), expected, f"tier 1 bank payload byte {offset}")

    bench.set_memory(CX16_RAM_BANK_REG, CX16_TIER_GUARD_BANK)
    for offset in guard_offsets:
        assert_eq(bench.get_memory(load + offset), 0xE7, f"tier guard bank byte {offset}")

    bench.set_memory(CX16_RAM_BANK_REG, saved_bank)


def assert_dungeon_module_load_execute(bench, labels, cwd):
    path = os.path.join(cwd, "DUNGEON.GEN")
    load, payload = read_prg(path)
    expected_load = require(labels, "cx16_contract_dungeon_module_load_base")
    assert_eq(load & 0xFF, expected_load & 0xFF, "dungeon module PRG load low")
    assert_eq(load >> 8, expected_load >> 8, "dungeon module PRG load high")

    saved_bank = bench.get_memory(CX16_RAM_BANK_REG)

    bench.set_memory(CX16_RAM_BANK_REG, CX16_DUNGEON_MODULE_BANK)
    for offset in range(len(payload)):
        bench.set_memory(load + offset, 0)

    bench.set_memory(CX16_RAM_BANK_REG, CX16_DUNGEON_MODULE_GUARD_BANK)
    guard_offsets = list(range(0, min(16, len(payload))))
    guard_offsets.extend(range(max(0, len(payload) - 16), len(payload)))
    for offset in guard_offsets:
        bench.set_memory(load + offset, 0xC9)

    bench.set_memory(CX16_RAM_BANK_REG, 1)
    bench.run(require(labels, "cx16_load_dungeon_module"), timeout=8)
    if bench.get_status() & STATUS_CARRY:
        raise AssertionError("cx16_load_dungeon_module reported failure")
    assert_eq(bench.get_memory(CX16_RAM_BANK_REG), 1, "dungeon module load restored caller bank")

    bench.set_memory(CX16_RAM_BANK_REG, CX16_DUNGEON_MODULE_BANK)
    for offset, expected in enumerate(payload):
        assert_eq(bench.get_memory(load + offset), expected, f"dungeon module bank payload byte {offset}")

    bench.set_memory(CX16_RAM_BANK_REG, 1)
    bench.run(require(labels, "cx16_probe_dungeon_module"), timeout=8)
    if bench.get_status() & STATUS_CARRY:
        raise AssertionError("cx16_probe_dungeon_module reported failure")
    assert_eq(bench.get_memory(CX16_RAM_BANK_REG), 1, "dungeon module probe restored caller bank")
    assert_eq(bench.get_memory(require(labels, "cx16_dungeon_module_status")), 1, "dungeon module status")
    assert_eq(bench.get_memory(require(labels, "cx16_dungeon_module_ret_a")), 0xD6, "dungeon module magic A")
    assert_eq(bench.get_memory(require(labels, "cx16_dungeon_module_ret_x")), 0x16, "dungeon module magic X")
    assert_eq(bench.get_memory(require(labels, "cx16_dungeon_module_ret_y")), 0x01, "dungeon module version")

    bench.set_memory(CX16_RAM_BANK_REG, CX16_DUNGEON_MODULE_GUARD_BANK)
    for offset in guard_offsets:
        assert_eq(bench.get_memory(load + offset), 0xC9, f"dungeon module guard bank byte {offset}")

    bench.set_memory(CX16_RAM_BANK_REG, saved_bank)


def assert_item_catalog_load_to_bank(bench, labels, cwd):
    path = os.path.join(cwd, "ITEMCAT.1")
    load, payload = read_prg(path)
    expected_load = require(labels, "cx16_contract_item_catalog_load_base")
    assert_eq(load & 0xFF, expected_load & 0xFF, "item catalog PRG load low")
    assert_eq(load >> 8, expected_load >> 8, "item catalog PRG load high")

    saved_bank = bench.get_memory(CX16_RAM_BANK_REG)

    bench.set_memory(CX16_RAM_BANK_REG, CX16_ITEM_CATALOG_BANK)
    for offset in range(len(payload)):
        bench.set_memory(load + offset, 0)

    bench.set_memory(CX16_RAM_BANK_REG, CX16_ITEM_CATALOG_GUARD_BANK)
    guard_offsets = list(range(0, min(16, len(payload))))
    guard_offsets.extend(range(max(0, len(payload) - 16), len(payload)))
    for offset in guard_offsets:
        bench.set_memory(load + offset, 0xA9)

    bench.set_memory(CX16_RAM_BANK_REG, 1)
    bench.run(require(labels, "cx16_load_item_catalog"), timeout=8)
    if bench.get_status() & STATUS_CARRY:
        raise AssertionError("cx16_load_item_catalog reported failure")
    assert_eq(bench.get_memory(CX16_RAM_BANK_REG), 1, "item catalog load restored caller bank")
    assert_eq(bench.get_memory(require(labels, "cx16_item_catalog_status")), 1, "item catalog status")

    bench.set_memory(CX16_RAM_BANK_REG, CX16_ITEM_CATALOG_BANK)
    for offset, expected in enumerate(payload):
        assert_eq(bench.get_memory(load + offset), expected, f"item catalog bank payload byte {offset}")

    bench.set_memory(CX16_RAM_BANK_REG, CX16_ITEM_CATALOG_GUARD_BANK)
    for offset in guard_offsets:
        assert_eq(bench.get_memory(load + offset), 0xA9, f"item catalog guard bank byte {offset}")

    bench.set_memory(CX16_RAM_BANK_REG, saved_bank)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--x16emu", required=True)
    parser.add_argument("--rom", default="")
    parser.add_argument("--prg", required=True)
    parser.add_argument("--symbols", required=True)
    parser.add_argument("--cwd", default="")
    args = parser.parse_args()

    labels = load_symbols(args.symbols)
    check_product_symbols(labels)
    cwd = args.cwd if args.cwd else None
    if cwd:
        try:
            os.unlink(os.path.join(cwd, "THE.GAME"))
        except FileNotFoundError:
            pass
    prg = args.prg
    if cwd:
        prg = os.path.basename(prg)
    bench = X16Bench(args.x16emu, args.rom, prg, cwd)
    try:
        bench.run(require(labels, "cx16_memory_init"))
        if bench.get_status() & STATUS_CARRY:
            raise AssertionError("cx16_memory_init reported failure")
        assert_eq(bench.get_memory(CX16_RAM_BANK_REG), 0, "default RAM bank after memory init")
        assert_banked_ram_isolation(bench)
        assert_banked_transfer_helpers(bench, labels)
        bench.run(require(labels, "cx16_preload_static_assets"), timeout=12)
        if bench.get_status() & STATUS_CARRY:
            raise AssertionError("cx16_preload_static_assets reported failure")
        assert_eq(bench.get_memory(require(labels, "cx16_preload_status")), 0, "preload status")
        assert_tier_prg_load_to_bank(bench, labels, args.cwd)
        assert_dungeon_module_load_execute(bench, labels, args.cwd)
        assert_item_catalog_load_to_bank(bench, labels, args.cwd)

        bench.run(require(labels, "screen_init"))
        bench.run(require(labels, "cx16_title_enter_menu"), timeout=8)
        assert_eq(bench.get_memory(require(labels, "cx16_state")), 0, "CX16 title state")
        assert_screen_cell(bench, 1, 22, screen_code("+"), TITLE_BORDER_COLOR, "title border")
        assert_screen_cell(bench, 3, 25, SC_REVERSE_SPACE, TEXT_COLOR, "title logo block")
        assert_screen_text(bench, 18, 27, "N)EW", "title menu")

        bench.run(require(labels, "cx16_new_game_start"), timeout=8)

        assert_eq(bench.get_memory(require(labels, "cx16_state")), 1, "CX16 state")
        assert_player_position(bench, labels, 31, 18, "new game")
        assert_eq(bench.get_memory(require(labels, "zp_player_dlvl")), 0, "town depth")
        assert_eq(bench.get_memory(require(labels, "inv_item_id") + EQUIP_WEAPON), ITEM_PICK, "starting weapon")
        assert_eq(bench.get_memory(require(labels, "zp_player_str")), 18, "starting strength")
        assert_eq(bench.get_memory(require(labels, "player_data") + PL_FLAGS), PLF_MALE, "starting sex flag")
        bench.run(require(labels, "tramp_dig_ability"))
        assert_eq(
            bench.get_memory(require(labels, "tun_dig_ability")),
            STARTING_PICK_DIG_ABILITY,
            "starting pick dig ability from banked item catalog",
        )
        assert_eq(map_tile_at(bench, labels, 32, 18), TILE_STAIRS_DN | TOWN_FLAGS, "town stairs tile")
        assert_screen_text(bench, 25, 1, "CX16", "town status name")
        assert_screen_text(bench, 25, 58, "LV:1", "town status level")
        assert_screen_text(bench, 25, 66, "DL:0", "town status depth")
        assert_screen_text(
            bench,
            29,
            14,
            "Move: HJKL/YUBN or numbers. Shift-Q title.",
            "town help",
        )
        assert_screen_cell(bench, 20, 38, SC_PLAYER, TEXT_COLOR, "initial player")

        for routine, title, label in (
            ("cx16_draw_inventory_view", "Inventory", "town inventory"),
            ("cx16_draw_equipment_view", "Equipment", "town equipment"),
        ):
            bench.run(require(labels, routine))
            assert_screen_text(bench, 0, 35, title, f"{label} modal title")
            bench.run(require(labels, "cx16_restore_current_view"))
            assert_eq(bench.get_memory(require(labels, "cx16_state")), 1, f"{label} restores town state")
            assert_screen_text(bench, 25, 66, "DL:0", f"{label} restores town status")
            assert_screen_text(
                bench,
                29,
                14,
                "Move: HJKL/YUBN or numbers. Shift-Q title.",
                f"{label} restores town help",
            )

        bench.set_a(CMD_MOVE_E)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, 32, 18, "move east onto stairs")
        assert_screen_cell(bench, 20, 39, SC_PLAYER, TEXT_COLOR, "moved player")

        set_player_position(bench, labels, 0, 1)
        bench.set_a(CMD_MOVE_W)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, 0, 1, "blocked west edge move")

        store_x = bench.get_memory(require(labels, "store_door_x"))
        store_y = bench.get_memory(require(labels, "store_door_y"))
        store_screen_row = store_y + 2
        store_screen_col = store_x + 7
        assert_screen_cell(
            bench,
            store_screen_row,
            store_screen_col,
            screen_code("1"),
            STORE_COLOR,
            "store door number",
        )
        bench.set_memory(require(labels, "zp_player_x"), store_x)
        bench.set_memory(require(labels, "zp_player_y"), store_y)
        bench.run(require(labels, "town_basic_check_store_door"))
        if not (bench.get_status() & STATUS_CARRY):
            raise AssertionError("store-door probe did not set carry")
        assert_eq(bench.get_a(), 0, "store-door index")

        set_player_position(bench, labels, store_x - 1, store_y)
        bench.set_memory(require(labels, "zp_player_hp_lo"), 5)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 5)
        bench.set_memory(require(labels, "zp_player_food"), 0)
        bench.set_memory(require(labels, "zp_player_food_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_FOOD_LO, 0)
        bench.set_memory(require(labels, "player_data") + PL_FOOD_HI, 0)
        bench.set_memory(require(labels, "cx16_store_idx"), 0xFF)
        bench.set_a(CMD_MOVE_E)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, store_x, store_y, "move onto store door")
        assert_eq(bench.get_memory(require(labels, "cx16_store_idx")), 0, "store entry command index")
        assert_screen_cell(
            bench,
            store_screen_row,
            store_screen_col,
            SC_PLAYER,
            TEXT_COLOR,
            "player on store door",
        )
        assert_screen_text(bench, 0, 0, "Rested and resupplied.", "town recovery message")
        assert_eq(bench.get_memory(require(labels, "zp_player_hp_lo")), 12, "town recovery restores hp")
        assert_eq(bench.get_memory(require(labels, "zp_player_food")), 0xD0, "town recovery food low")
        assert_eq(bench.get_memory(require(labels, "zp_player_food_hi")), 0x07, "town recovery food high")
        assert_eq(bench.get_memory(require(labels, "player_data") + PL_GOLD_0), 190, "town recovery charges gold")
        assert_eq(bench.get_memory(require(labels, "inv_item_id")), ITEM_RATION, "town recovery adds ration")
        assert_eq(bench.get_memory(require(labels, "inv_item_id") + 1), ITEM_POTION_CURE, "town recovery adds cure potion")
        assert_eq(count_carried_item(bench, labels, ITEM_RATION), 1, "town recovery ration count")
        assert_eq(count_carried_item(bench, labels, ITEM_POTION_CURE), 1, "town recovery cure potion count")

        bench.set_a(CMD_MOVE_S)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, store_x, store_y + 1, "leave store door")
        assert_screen_cell(
            bench,
            store_screen_row,
            store_screen_col,
            screen_code("1"),
            STORE_COLOR,
            "restored store door number",
        )

        bench.set_memory(require(labels, "zp_player_hp_lo"), 4)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 4)
        bench.set_memory(require(labels, "zp_player_food"), 0)
        bench.set_memory(require(labels, "zp_player_food_hi"), 0)
        bench.set_a(CMD_MOVE_N)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, store_x, store_y, "second store recovery entry")
        assert_eq(bench.get_memory(require(labels, "zp_player_hp_lo")), 12, "second town recovery restores hp")
        assert_eq(bench.get_memory(require(labels, "player_data") + PL_GOLD_0), 180, "second town recovery charges gold")
        assert_eq(count_carried_item(bench, labels, ITEM_RATION), 2, "second town recovery tops up rations")
        assert_eq(count_carried_item(bench, labels, ITEM_POTION_CURE), 2, "second town recovery tops up cure potions")

        bench.set_a(CMD_MOVE_S)
        bench.run(require(labels, "cx16_try_move_command"))
        bench.set_memory(require(labels, "zp_player_hp_lo"), 3)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 3)
        bench.set_a(CMD_MOVE_N)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, store_x, store_y, "third store recovery entry")
        assert_eq(bench.get_memory(require(labels, "zp_player_hp_lo")), 12, "third town recovery restores hp")
        assert_eq(bench.get_memory(require(labels, "player_data") + PL_GOLD_0), 170, "third town recovery charges gold")
        assert_eq(count_carried_item(bench, labels, ITEM_RATION), 2, "third town recovery caps rations")
        assert_eq(count_carried_item(bench, labels, ITEM_POTION_CURE), 2, "third town recovery caps cure potions")

        bench.set_a(CMD_MOVE_S)
        bench.run(require(labels, "cx16_try_move_command"))

        bench.set_memory(require(labels, "zp_player_x"), 31)
        bench.set_memory(require(labels, "zp_player_y"), 18)
        bench.run(require(labels, "town_basic_check_store_door"))
        if bench.get_status() & STATUS_CARRY:
            raise AssertionError("store-door probe matched non-door town floor")

        bench.set_memory(require(labels, "zp_player_x"), 32)
        bench.set_memory(require(labels, "zp_player_y"), 18)
        bench.run(require(labels, "town_basic_check_stairs_at_player"))
        assert_eq(bench.get_a(), 9, "stairs-down probe")
        bench.run(require(labels, "cx16_try_stairs_down"))
        assert_eq(bench.get_memory(require(labels, "cx16_state")), 2, "CX16 dungeon state")
        assert_eq(bench.get_memory(require(labels, "cx16_loaded_tier")), 1, "loaded tier")
        assert_eq(bench.get_memory(require(labels, "cx16_loaded_tier_bank")), 4, "loaded tier bank")
        assert_eq(bench.get_memory(require(labels, "cx16_dungeon_module_status")), 1, "dungeon module status after stairs")
        assert_eq(bench.get_memory(require(labels, "cx16_dungeon_depth")), 1, "dungeon depth")
        assert_eq(bench.get_memory(require(labels, "zp_player_dlvl")), 1, "shared dungeon depth")
        entry_x = bench.get_memory(require(labels, "zp_player_x"))
        entry_y = bench.get_memory(require(labels, "zp_player_y"))
        assert_player_position(bench, labels, entry_x, entry_y, "dungeon entry player position")
        assert_floor_items_spawned(bench, labels)
        find_top_floor_item_by_id(bench, labels, ITEM_RATION)
        _, seeded_potion_x, seeded_potion_y = find_top_floor_item_by_id(bench, labels, ITEM_POTION_CURE)
        _, seeded_armor_x, seeded_armor_y = find_top_floor_item_by_id(bench, labels, ITEM_LEATHER_ARMOR)
        _, seeded_oil_x, seeded_oil_y = find_top_floor_item_by_id(bench, labels, ITEM_FLASK_OIL)
        assert_map_tile_type(bench, labels, entry_x, entry_y, TILE_STAIRS_UP, "module stairs up tile")
        down_x, down_y = find_map_tile_type(bench, labels, TILE_STAIRS_DN, "module stairs down")
        floor_x, floor_y = find_map_tile_type(bench, labels, TILE_FLOOR, "module floor")
        wall_x, wall_y = find_map_tile_type(bench, labels, TILE_WALL_H, "module wall")
        assert_map_tile_type(bench, labels, down_x, down_y, TILE_STAIRS_DN, "module stairs down tile")
        assert_map_tile_type(bench, labels, floor_x, floor_y, TILE_FLOOR, "module floor tile")
        assert_map_tile_type(bench, labels, wall_x, wall_y, TILE_WALL_H, "module wall tile")
        assert_screen_text(bench, 25, 1, "CX16", "dungeon status name")
        assert_screen_text(bench, 25, 58, "LV:1", "dungeon status level")
        assert_screen_text(bench, 25, 66, "DL:1", "dungeon status depth")
        assert_screen_text(bench, 26, 1, "ST:18", "dungeon status stats")
        assert_screen_text(bench, 27, 1, "HP:12/12", "dungeon status hp")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "dungeon entry player")
        assert_screen_cell(bench, 2, 1, screen_code(" "), 0, "unvisited dungeon rock")
        assert_screen_text(bench, 0, 0, "Dungeon level 1 ready.", "dungeon level ready")
        assert_screen_text(
            bench,
            29,
            10,
            "Move: HJKL/YUBN/numbers. S save. s search. Shift-Q title.",
            "dungeon help",
        )

        inv_base = require(labels, "inv_item_id")
        old_ac = bench.get_memory(require(labels, "player_data") + PL_AC)
        set_player_position(bench, labels, seeded_armor_x, seeded_armor_y)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        bench.set_a(CMD_PICKUP)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        find_carried_item_slot(bench, labels, ITEM_LEATHER_ARMOR)
        assert_turns(bench, labels, 1, "generated armor pickup consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "generated armor pickup keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "generated armor pickup does not full-clear")

        reset_turn(bench, labels)
        stuff_key(bench, ord("A"))
        bench.set_a(CMD_WEAR)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base + EQUIP_BODY), ITEM_LEATHER_ARMOR, "generated leather armor equips body slot")
        armor_ac = bench.get_memory(require(labels, "player_data") + PL_AC)
        if armor_ac <= old_ac:
            raise AssertionError("generated leather armor did not improve AC")
        assert_turns(bench, labels, 1, "generated armor wear consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "generated armor wear keeps player glyph")

        set_player_position(bench, labels, seeded_potion_x, seeded_potion_y)
        reset_turn(bench, labels)
        bench.set_a(CMD_PICKUP)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(count_carried_item(bench, labels, ITEM_POTION_CURE), 3, "generated cure potion pickup adds to carried potions")
        assert_turns(bench, labels, 1, "generated potion pickup consumes one turn")
        bench.set_memory(require(labels, "zp_player_hp_lo"), 5)
        bench.set_memory(require(labels, "zp_player_hp_hi"), 0)
        bench.set_memory(require(labels, "zp_player_mhp_lo"), 50)
        bench.set_memory(require(labels, "zp_player_mhp_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 5)
        bench.set_memory(require(labels, "player_data") + PL_HP_HI, 0)
        bench.set_memory(require(labels, "player_data") + PL_MHP_LO, 50)
        bench.set_memory(require(labels, "player_data") + PL_MHP_HI, 0)
        reset_turn(bench, labels)
        stuff_key(bench, ord("C"))
        bench.set_a(CMD_QUAFF)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        if bench.get_memory(require(labels, "zp_player_hp_lo")) <= 5:
            raise AssertionError("generated cure potion did not heal the player")
        assert_eq(count_carried_item(bench, labels, ITEM_POTION_CURE), 2, "generated cure potion is consumed")
        assert_turns(bench, labels, 1, "generated potion quaff consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "generated potion quaff keeps player glyph")

        reset_turn(bench, labels)
        stuff_key(bench, ord("B"))
        bench.set_a(CMD_TAKEOFF)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        find_carried_item_slot(bench, labels, ITEM_LEATHER_ARMOR)
        assert_eq(bench.get_memory(inv_base + EQUIP_BODY), FI_EMPTY, "generated leather armor takeoff clears body slot")
        if bench.get_memory(require(labels, "player_data") + PL_AC) >= armor_ac:
            raise AssertionError("generated leather armor takeoff did not reduce AC")
        assert_turns(bench, labels, 1, "generated armor takeoff consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "generated armor takeoff keeps player glyph")

        set_player_position(bench, labels, seeded_oil_x, seeded_oil_y)
        reset_turn(bench, labels)
        bench.set_a(CMD_PICKUP)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        oil_slot = find_carried_item_slot(bench, labels, ITEM_FLASK_OIL)
        assert_eq(bench.get_memory(require(labels, "inv_p1") + oil_slot), 20, "generated oil has refuel value")
        bench.set_memory(inv_base + EQUIP_LIGHT, ITEM_LANTERN)
        bench.set_memory(require(labels, "inv_qty") + EQUIP_LIGHT, 1)
        bench.set_memory(require(labels, "inv_p1") + EQUIP_LIGHT, 10)
        reset_turn(bench, labels)
        bench.set_a(CMD_REFUEL)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(require(labels, "inv_p1") + EQUIP_LIGHT), 30, "generated oil refuels equipped lantern")
        assert_eq(count_carried_item(bench, labels, ITEM_FLASK_OIL), 0, "generated oil is consumed")
        assert_turns(bench, labels, 1, "generated oil refuel consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "generated oil refuel keeps player glyph")

        assert_eq(bench.get_memory(require(labels, "zp_mon_count")), 3, "dungeon monster count")
        monster_slot, monster_x, monster_y, monster_hp, monster_hp_hi = first_live_monster(bench, labels)
        monster_base = require(labels, "monster_table") + (monster_slot * MONSTER_ENTRY_SIZE)
        assert_eq(bench.get_memory(monster_base + MX_TYPE), 0, "first spawned monster type")
        assert_eq(monster_hp, 10, "spawned monster hp low from tier hit dice")
        assert_eq(monster_hp_hi, 0, "spawned monster hp high")
        if not (map_tile_at(bench, labels, monster_x, monster_y) & FLAG_OCCUPIED):
            raise AssertionError("spawned monster tile missing FLAG_OCCUPIED")
        attack_command, attack_px, attack_py = find_player_pos_to_attack(bench, labels, monster_x, monster_y)
        set_player_position(bench, labels, attack_px, attack_py)
        bench.run(require(labels, "update_visibility"))
        bench.set_memory(monster_base + MX_TYPE, 1)
        bench.run(require(labels, "cx16_draw_dungeon"))
        mon_screen_row = monster_y - bench.get_memory(require(labels, "cx16_view_y")) + VIEWPORT_Y
        mon_screen_col = monster_x - bench.get_memory(require(labels, "cx16_view_x")) + VIEWPORT_X
        assert_screen_cell(
            bench,
            mon_screen_row,
            mon_screen_col,
            0x17,
            COL_WHITE,
            "visible white worm mass glyph",
        )
        bench.set_memory(require(labels, "zp_turn_lo"), 23)
        stuff_direction_to_target(bench, attack_px, attack_py, monster_x, monster_y)
        bench.set_a(CMD_LOOK)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_screen_text(bench, 0, 0, "Direction?", "look command prompts for white worm direction")
        assert_screen_text(bench, 1, 0, "You see a White Worm mass.", "look command describes white worm mass")
        assert_eq(bench.get_memory(require(labels, "zp_turn_lo")), 23, "white worm look is free")
        bench.set_memory(monster_base + MX_TYPE, 0)
        bench.run(require(labels, "cx16_draw_dungeon"))
        assert_screen_cell(
            bench,
            mon_screen_row,
            mon_screen_col,
            screen_code("k"),
            TEXT_COLOR,
            "visible kobold glyph",
        )

        bench.set_memory(require(labels, "zp_turn_lo"), 23)
        stuff_direction_to_target(bench, attack_px, attack_py, monster_x, monster_y)
        bench.set_a(CMD_LOOK)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_screen_text(bench, 0, 0, "Direction?", "look command prompts for monster direction")
        assert_screen_text(bench, 1, 0, "You see a Kobold.", "look command describes kobold")
        assert_eq(bench.get_memory(require(labels, "zp_turn_lo")), 23, "monster look is free")
        bench.run(require(labels, "msg_init"))
        bench.set_memory(require(labels, "player_data") + PL_LEVEL, 2)
        bench.set_memory(require(labels, "zp_player_lvl"), 2)
        bench.set_memory(require(labels, "player_data") + PL_EXPFACT, 100)
        bench.set_memory(require(labels, "player_data") + PL_XP_0, 23)
        bench.set_memory(require(labels, "player_data") + PL_XP_1, 0)
        bench.set_memory(require(labels, "player_data") + PL_XP_2, 0)
        bench.set_memory(require(labels, "player_data") + PL_XP_FRAC_LO, 0)
        bench.set_memory(require(labels, "player_data") + PL_XP_FRAC_HI, 0)
        xp_before_combat = bench.get_memory(require(labels, "player_data") + PL_XP_0)
        bench.set_memory(monster_base + MX_HP_LO, 20)
        bench.set_memory(monster_base + MX_HP_HI, 0)
        bench.set_memory(require(labels, "inv_to_dam") + EQUIP_WEAPON, 8)
        bench.set_memory(require(labels, "player_data") + PL_TOHIT, 120)
        bench.set_memory(require(labels, "player_data") + PL_TODMG, 10)
        reset_turn(bench, labels)
        first_hit_hp = 20
        for _ in range(20):
            set_player_position(bench, labels, attack_px, attack_py)
            bench.set_a(attack_command)
            bench.run(require(labels, "cx16_dispatch_game_command"))
            first_hit_hp = bench.get_memory(monster_base + MX_HP_LO)
            if first_hit_hp < 20:
                break
        if first_hit_hp == 20:
            raise AssertionError("melee hit did not damage monster")
        if first_hit_hp > 9:
            raise AssertionError("melee hit ignored PL_TODMG/equipment damage bonus")
        if bench.get_memory(require(labels, "zp_turn_lo")) == 0:
            raise AssertionError("melee attack did not consume a turn")
        assert_screen_text(bench, 0, 0, "You hit the Kobold.", "melee hit message")
        for _ in range(20):
            set_player_position(bench, labels, attack_px, attack_py)
            bench.set_a(attack_command)
            bench.run(require(labels, "cx16_dispatch_game_command"))
            if bench.get_memory(monster_base + MX_TYPE) == EMPTY_SLOT:
                break
        assert_eq(bench.get_memory(monster_base + MX_TYPE), EMPTY_SLOT, "tier-backed melee removes monster")
        assert_eq(bench.get_memory(require(labels, "zp_mon_count")), 2, "monster kill decrements count")
        assert_screen_text(bench, 0, 0, "You have slain the Kobold.", "monster kill message")
        assert_eq(
            bench.get_memory(require(labels, "player_data") + PL_XP_0),
            (xp_before_combat + 2) & 0xFF,
            "monster kill awards scaled tier xp",
        )
        assert_eq(
            bench.get_memory(require(labels, "player_data") + PL_XP_FRAC_HI),
            0x40,
            "level-up halves fractional excess xp",
        )
        assert_eq(bench.get_memory(require(labels, "player_data") + PL_LEVEL), 3, "monster xp advances player level")
        assert_eq(bench.get_memory(require(labels, "zp_player_lvl")), 3, "level-up syncs zero-page level")
        assert_eq(
            bench.get_memory(require(labels, "player_data") + PL_HP_LO),
            bench.get_memory(require(labels, "player_data") + PL_MHP_LO),
            "level-up heals current HP to max HP",
        )
        if map_tile_at(bench, labels, monster_x, monster_y) & FLAG_OCCUPIED:
            raise AssertionError("monster kill did not clear FLAG_OCCUPIED")

        place_monster(bench, labels, monster_slot, monster_x, monster_y, 1, 1, 0)
        bench.run(require(labels, "cx16_draw_dungeon"))
        assert_screen_cell(
            bench,
            mon_screen_row,
            mon_screen_col,
            0x17,
            COL_WHITE,
            "replacement white worm mass glyph",
        )
        for _ in range(20):
            set_player_position(bench, labels, attack_px, attack_py)
            bench.set_a(attack_command)
            bench.run(require(labels, "cx16_dispatch_game_command"))
            if bench.get_memory(monster_base + MX_TYPE) == EMPTY_SLOT:
                break
        assert_eq(bench.get_memory(monster_base + MX_TYPE), EMPTY_SLOT, "white worm mass kill removes monster")
        assert_eq(bench.get_memory(require(labels, "zp_mon_count")), 2, "white worm mass kill decrements count")
        assert_screen_text(bench, 0, 0, "You have slain the White Worm mass.", "white worm mass kill message")
        if map_tile_at(bench, labels, monster_x, monster_y) & FLAG_OCCUPIED:
            raise AssertionError("white worm mass kill did not clear FLAG_OCCUPIED")

        saved_tier = bench.get_memory(require(labels, "cx16_loaded_tier"))
        saved_flags = bench.get_memory(require(labels, "zp_game_flags"))
        saved_bank = bench.get_memory(CX16_RAM_BANK_REG)
        bench.set_memory(CX16_RAM_BANK_REG, CX16_OVERLAY_DEATH_BANK)
        saved_mon_type = bench.get_memory(require(labels, "cx16_mon_type"))
        bench.set_memory(require(labels, "cx16_loaded_tier"), CREATURE_BALROG_TIER)
        bench.set_memory(require(labels, "cx16_mon_type"), CREATURE_BALROG)
        bench.set_memory(require(labels, "zp_game_flags"), saved_flags & ~GAME_FLAG_WINNER)
        bench.run(require(labels, "cx16_overlay_note_kill"))
        if not (bench.get_memory(require(labels, "zp_game_flags")) & GAME_FLAG_WINNER):
            raise AssertionError("Balrog kill helper did not set winner flag")
        bench.set_memory(require(labels, "cx16_mon_type"), saved_mon_type)
        bench.set_memory(CX16_RAM_BANK_REG, saved_bank)
        bench.set_memory(require(labels, "cx16_loaded_tier"), saved_tier)
        bench.set_memory(require(labels, "zp_game_flags"), saved_flags)
        clear_live_monsters(bench, labels)

        set_player_position(bench, labels, entry_x, entry_y)
        move_command, move_x, move_y = find_adjacent_floor_move(bench, labels, entry_x, entry_y)
        assert_screen_contains_cell(bench, screen_code("."), 11, "visible dungeon floor")
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        bench.set_a(move_command)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, move_x, move_y, "dungeon adjacent move")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "dungeon moved player")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "dungeon movement does not full-clear")

        set_player_position(bench, labels, entry_x, entry_y)
        bench.run(require(labels, "cx16_draw_dungeon"))
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        bench.set_a(move_command)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_player_position(bench, labels, move_x, move_y, "dungeon move through dispatcher")
        assert_turns(bench, labels, 1, "dungeon move consumes one turn")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "dungeon scrolling movement does not full-clear")

        set_player_position(bench, labels, entry_x, entry_y)
        bench.set_memory(require(labels, "player_data") + PL_FLAGS, PLF_SEARCHING)
        bench.run(require(labels, "cx16_draw_dungeon_ui"))
        assert_screen_text(bench, 27, 70, "Search*", "search status before movement")
        reset_turn(bench, labels)
        bench.set_a(move_command)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        if not (bench.get_memory(require(labels, "player_data") + PL_FLAGS) & PLF_SEARCHING):
            raise AssertionError("dungeon movement cleared search mode")
        assert_turns(bench, labels, 2, "search-mode movement consumes extra search turn")
        assert_screen_text(bench, 27, 70, "Search*", "search status after movement")
        bench.set_memory(require(labels, "player_data") + PL_FLAGS, 0)
        bench.run(require(labels, "cx16_draw_dungeon_ui"))

        set_player_position(bench, labels, wall_x + 1, wall_y + 1)
        bench.set_a(CMD_MOVE_NW)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, wall_x + 1, wall_y + 1, "dungeon blocked wall move")

        door_x, door_y, door_px, door_py = find_adjacent_tile_type(
            bench, labels, TILE_DOOR_CLOSED, "closed dungeon door"
        )
        set_player_position(bench, labels, door_px, door_py)
        bench.set_memory(require(labels, "zp_player_str"), 18)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        bench.run(require(labels, "msg_clear"))
        stuff_direction_to_target(bench, door_px, door_py, door_x, door_y)
        bench.set_a(CMD_OPEN)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_map_tile_type(bench, labels, door_x, door_y, TILE_DOOR_OPEN, "opened dungeon door")
        assert_player_position(bench, labels, door_px, door_py, "open command keeps player position")
        assert_turns(bench, labels, 1, "open command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "open command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "open command does not full-clear")

        reset_turn(bench, labels)
        bench.run(require(labels, "msg_clear"))
        stuff_direction_to_target(bench, door_px, door_py, door_x, door_y)
        bench.set_a(CMD_CLOSE)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_map_tile_type(bench, labels, door_x, door_y, TILE_DOOR_CLOSED, "closed dungeon door")
        assert_turns(bench, labels, 1, "close command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "close command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "close command does not full-clear")

        set_player_position(bench, labels, door_px, door_py)
        bench.set_memory(require(labels, "zp_turn_lo"), 17)
        stuff_direction_to_target(bench, door_px, door_py, door_x, door_y)
        bench.set_a(CMD_LOOK)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_screen_text(bench, 0, 0, "Direction?", "look command prompts for direction")
        assert_screen_text(bench, 1, 0, "You see a closed door.", "look command describes closed door")
        assert_eq(bench.get_memory(require(labels, "zp_turn_lo")), 17, "look command is free")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "look command keeps player glyph")

        set_player_position(bench, labels, door_px, door_py)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        bench.set_a(CMD_SEARCH)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        if assert_screen_text_matches(bench, 0, 0, "That is only useful in the dungeon."):
            raise AssertionError("search command rendered the dungeon-only message")
        assert_turns(bench, labels, 1, "search command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "search command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "search command does not full-clear")

        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        bench.set_memory(require(labels, "zp_player_food"), 10)
        bench.set_memory(require(labels, "zp_player_food_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_FOOD_LO, 10)
        bench.set_memory(require(labels, "player_data") + PL_FOOD_HI, 0)
        bench.set_memory(require(labels, "zp_player_hp_lo"), 10)
        bench.set_memory(require(labels, "zp_player_hp_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 10)
        bench.set_memory(require(labels, "player_data") + PL_HP_HI, 0)
        bench.set_memory(require(labels, "zp_player_mhp_lo"), 12)
        bench.set_memory(require(labels, "zp_player_mhp_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_MHP_LO, 12)
        bench.set_memory(require(labels, "player_data") + PL_MHP_HI, 0)
        bench.set_memory(require(labels, "player_data") + PL_CON_CUR, 18)
        bench.set_memory(require(labels, "zp_regen_counter"), 1)
        reset_turn(bench, labels)
        bench.set_a(CMD_REST)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        if assert_screen_text_matches(bench, 0, 0, "That is only useful in the dungeon."):
            raise AssertionError("rest command rendered the dungeon-only message")
        assert_turns(bench, labels, 1, "rest command consumes one turn")
        assert_eq(bench.get_memory(require(labels, "zp_player_food")), 9, "rest command ticks hunger")
        assert_eq(bench.get_memory(require(labels, "zp_player_hp_lo")), 11, "rest command runs shared HP regen")
        assert_player_position(bench, labels, door_px, door_py, "rest command keeps player position")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "rest command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "rest command does not full-clear")

        bench.set_memory(require(labels, "zp_player_hp_lo"), 8)
        bench.set_memory(require(labels, "zp_player_hp_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 8)
        bench.set_memory(require(labels, "player_data") + PL_HP_HI, 0)
        bench.set_memory(require(labels, "zp_player_mhp_lo"), 12)
        bench.set_memory(require(labels, "zp_player_mhp_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_MHP_LO, 12)
        bench.set_memory(require(labels, "player_data") + PL_MHP_HI, 0)
        reset_turn(bench, labels)
        bench.set_memory(require(labels, "player_data") + PL_FLAGS, PLF_SEARCHING)
        bench.set_a(CMD_AUTOREST)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_turns(bench, labels, 1, "injured auto-rest consumes one turn")
        if bench.get_memory(require(labels, "player_data") + PL_FLAGS) & PLF_SEARCHING:
            raise AssertionError("auto-rest did not clear search mode")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "auto-rest keeps player glyph")

        bench.set_memory(require(labels, "zp_player_hp_lo"), 12)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 12)
        reset_turn(bench, labels)
        bench.set_a(CMD_AUTOREST)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_turns(bench, labels, 0, "recovered auto-rest consumes no turn")

        bench.set_memory(require(labels, "player_data") + PL_FLAGS, 0)
        reset_turn(bench, labels)
        bench.set_a(CMD_SEARCH_MODE)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        if not (bench.get_memory(require(labels, "player_data") + PL_FLAGS) & PLF_SEARCHING):
            raise AssertionError("search mode command did not set the searching flag")
        assert_turns(bench, labels, 0, "search mode toggle consumes no turn")
        assert_screen_text(bench, 0, 0, "Search mode on.", "search mode on message")
        assert_screen_text(bench, 27, 70, "Search*", "search mode status on")
        bench.set_a(CMD_SEARCH_MODE)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        if bench.get_memory(require(labels, "player_data") + PL_FLAGS) & PLF_SEARCHING:
            raise AssertionError("search mode command did not clear the searching flag")
        assert_turns(bench, labels, 0, "search mode off consumes no turn")
        assert_screen_text(bench, 0, 0, "Search mode off.", "search mode off message")
        assert_eq(screen_char_at(bench, 27, 70), screen_code(" "), "search mode status off")

        set_player_position(bench, labels, door_px, door_py)
        set_map_tile(bench, labels, door_x, door_y, TILE_FLOOR | DUNGEON_FLAGS)
        bench.set_memory(require(labels, "zp_player_str"), 18)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        stuff_direction_to_target(bench, door_px, door_py, door_x, door_y)
        bench.set_a(CMD_BASH)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_player_position(bench, labels, door_px, door_py, "bash command keeps player position")
        assert_turns(bench, labels, 1, "bash empty-space command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "bash command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "bash command does not full-clear")

        set_player_position(bench, labels, door_px, door_py)
        set_map_tile(bench, labels, door_x, door_y, TILE_RUBBLE | DUNGEON_FLAGS)
        bench.set_memory(require(labels, "zp_player_str"), 255)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        for _ in range(8):
            if tile_type(map_tile_at(bench, labels, door_x, door_y)) == TILE_FLOOR:
                break
            stuff_direction_to_target(bench, door_px, door_py, door_x, door_y)
            bench.set_a(CMD_TUNNEL)
            bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_map_tile_type(bench, labels, door_x, door_y, TILE_FLOOR, "tunnel with pick removes rubble")
        assert_player_position(bench, labels, door_px, door_py, "tunnel command keeps player position")
        if bench.get_memory(require(labels, "zp_turn_lo")) == 0:
            raise AssertionError("tunnel command did not consume a turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "tunnel command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "tunnel command does not full-clear")
        bench.set_memory(require(labels, "zp_player_str"), 18)

        set_player_position(bench, labels, door_px, door_py)
        set_map_tile(bench, labels, door_x, door_y, TILE_TRAP | DUNGEON_FLAGS)
        bench.set_memory(require(labels, "trap_count"), 1)
        bench.set_memory(require(labels, "trap_x"), door_x)
        bench.set_memory(require(labels, "trap_y"), door_y)
        bench.set_memory(require(labels, "trap_type"), 0)
        bench.set_memory(require(labels, "player_data") + PL_RACE, 3)
        bench.set_memory(require(labels, "player_data") + PL_CLASS, 3)
        bench.set_memory(require(labels, "player_data") + PL_LEVEL, 40)
        bench.set_memory(require(labels, "player_data") + PL_DEX_CUR, 118)
        bench.set_memory(require(labels, "player_data") + PL_INT_CUR, 118)
        bench.set_memory(require(labels, "zp_player_lvl"), 40)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        stuff_direction_to_target(bench, door_px, door_py, door_x, door_y)
        bench.set_a(CMD_DISARM)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(require(labels, "trap_count")), 0, "disarm command removes trap")
        assert_map_tile_type(bench, labels, door_x, door_y, TILE_FLOOR, "disarm command restores floor")
        assert_player_position(bench, labels, door_x, door_y, "disarm command moves onto trap")
        assert_turns(bench, labels, 1, "disarm success consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "disarm command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "disarm command does not full-clear")

        set_player_position(bench, labels, floor_x, floor_y)
        clear_carried_inventory(bench, labels)
        item_count_before_pickup = bench.get_memory(require(labels, "zp_item_count"))
        add_floor_item(bench, labels, floor_x, floor_y, ITEM_PICK)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        bench.set_a(CMD_PICKUP)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(
            bench.get_memory(require(labels, "zp_item_count")),
            item_count_before_pickup,
            "pickup command removes floor item",
        )
        assert_eq(bench.get_memory(require(labels, "inv_item_id")), ITEM_PICK, "pickup command fills inventory slot")
        assert_turns(bench, labels, 1, "pickup command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "pickup command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "pickup command does not full-clear")

        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        stuff_key(bench, ord("A"))
        bench.set_a(CMD_DROP)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(require(labels, "inv_item_id")), FI_EMPTY, "drop command clears inventory slot")
        assert_eq(
            bench.get_memory(require(labels, "zp_item_count")),
            item_count_before_pickup + 1,
            "drop command creates floor item",
        )
        if not (map_tile_at(bench, labels, floor_x, floor_y) & FLAG_HAS_ITEM):
            raise AssertionError("drop command did not mark the floor item tile")
        assert_turns(bench, labels, 1, "drop command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "drop command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "drop command does not full-clear")

        bench.set_memory(inv_base, ITEM_PICK)
        bench.set_memory(require(labels, "inv_qty"), 1)
        bench.set_memory(require(labels, "inv_p1"), STARTING_PICK_DIG_ABILITY)
        bench.set_memory(require(labels, "inv_to_hit"), 0)
        bench.set_memory(require(labels, "inv_to_dam"), 0)
        bench.set_memory(require(labels, "inv_to_ac"), 0)
        bench.set_memory(require(labels, "inv_flags"), 0)
        bench.set_memory(require(labels, "inv_ego"), 0)
        bench.set_memory(inv_base + EQUIP_WEAPON, FI_EMPTY)
        reset_turn(bench, labels)
        stuff_key(bench, ord("A"))
        bench.set_a(CMD_WEAR)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), FI_EMPTY, "wear command removes carried item")
        assert_eq(bench.get_memory(inv_base + EQUIP_WEAPON), ITEM_PICK, "wear command equips weapon")
        assert_turns(bench, labels, 1, "wear command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "wear command keeps player glyph")

        reset_turn(bench, labels)
        stuff_key(bench, ord("A"))
        bench.set_a(CMD_TAKEOFF)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), ITEM_PICK, "takeoff command restores carried item")
        assert_eq(bench.get_memory(inv_base + EQUIP_WEAPON), FI_EMPTY, "takeoff command clears weapon slot")
        assert_turns(bench, labels, 1, "takeoff command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "takeoff command keeps player glyph")

        bench.set_memory(inv_base, ITEM_RATION)
        bench.set_memory(require(labels, "inv_qty"), 1)
        bench.set_memory(require(labels, "zp_player_food"), 0)
        bench.set_memory(require(labels, "zp_player_food_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_FOOD_LO, 0)
        bench.set_memory(require(labels, "player_data") + PL_FOOD_HI, 0)
        reset_turn(bench, labels)
        bench.set_a(CMD_EAT)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), FI_EMPTY, "eat command consumes food")
        if bench.get_memory(require(labels, "zp_player_food_hi")) == 0:
            raise AssertionError("eat command did not increase food counter")
        assert_turns(bench, labels, 1, "eat command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "eat command keeps player glyph")

        bench.set_memory(inv_base, ITEM_POTION_CURE)
        bench.set_memory(require(labels, "inv_qty"), 1)
        bench.set_memory(require(labels, "inv_p1"), 0)
        bench.set_memory(require(labels, "zp_player_hp_lo"), 10)
        bench.set_memory(require(labels, "zp_player_hp_hi"), 0)
        bench.set_memory(require(labels, "zp_player_mhp_lo"), 50)
        bench.set_memory(require(labels, "zp_player_mhp_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 10)
        bench.set_memory(require(labels, "player_data") + PL_HP_HI, 0)
        bench.set_memory(require(labels, "player_data") + PL_MHP_LO, 50)
        bench.set_memory(require(labels, "player_data") + PL_MHP_HI, 0)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        stuff_key(bench, ord("A"))
        bench.set_a(CMD_QUAFF)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), FI_EMPTY, "quaff command consumes potion")
        if bench.get_memory(require(labels, "zp_player_hp_lo")) <= 10:
            raise AssertionError("quaff command did not heal the player")
        assert_turns(bench, labels, 1, "quaff command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "quaff command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "quaff command does not full-clear")

        bench.set_memory(inv_base, ITEM_FLASK_OIL)
        bench.set_memory(require(labels, "inv_qty"), 1)
        bench.set_memory(require(labels, "inv_p1"), 20)
        bench.set_memory(inv_base + EQUIP_LIGHT, ITEM_LANTERN)
        bench.set_memory(require(labels, "inv_qty") + EQUIP_LIGHT, 1)
        bench.set_memory(require(labels, "inv_p1") + EQUIP_LIGHT, 10)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        bench.set_a(CMD_REFUEL)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), FI_EMPTY, "refuel command consumes oil flask")
        assert_eq(bench.get_memory(require(labels, "inv_p1") + EQUIP_LIGHT), 30, "refuel command adds oil")
        assert_turns(bench, labels, 1, "refuel command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "refuel command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "refuel command does not full-clear")

        set_inventory_slot0(bench, labels, ITEM_SCROLL_LIGHT)
        bench.set_memory(require(labels, "id_known") + ITEM_SCROLL_LIGHT, 0)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        stuff_key(bench, ord("A"))
        bench.set_a(CMD_READ)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), FI_EMPTY, "read command consumes scroll")
        assert_eq(bench.get_memory(require(labels, "id_known") + ITEM_SCROLL_LIGHT), 1, "read command marks scroll known")
        assert_turns(bench, labels, 1, "read command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "read command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "read command does not full-clear")

        set_inventory_slot0(bench, labels, ITEM_WAND_LIGHT, p1=2)
        bench.set_memory(require(labels, "id_known") + ITEM_WAND_LIGHT, 0)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        stuff_key(bench, ord("A"))
        bench.set_a(CMD_AIM)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), ITEM_WAND_LIGHT, "aim command keeps wand")
        assert_eq(bench.get_memory(require(labels, "inv_p1")), 1, "aim command consumes one wand charge")
        assert_eq(bench.get_memory(require(labels, "id_known") + ITEM_WAND_LIGHT), 1, "aim command marks wand known")
        assert_turns(bench, labels, 1, "aim command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "aim command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "aim command does not full-clear")

        set_inventory_slot0(bench, labels, ITEM_STAFF_DETECT, p1=2)
        bench.set_memory(require(labels, "id_known") + ITEM_STAFF_DETECT, 0)
        bench.set_memory(require(labels, "eff_detect_timer"), 0)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        reset_turn(bench, labels)
        stuff_key(bench, ord("A"))
        bench.set_a(CMD_USE)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), ITEM_STAFF_DETECT, "use command keeps staff")
        assert_eq(bench.get_memory(require(labels, "inv_p1")), 1, "use command consumes one staff charge")
        assert_eq(bench.get_memory(require(labels, "id_known") + ITEM_STAFF_DETECT), 1, "use command marks staff known")
        assert_eq(bench.get_memory(require(labels, "eff_detect_timer")), 19, "use command activates and ticks detect monsters")
        assert_turns(bench, labels, 1, "use command consumes one turn")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "use command keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "use command does not full-clear")

        set_player_position(bench, labels, entry_x, entry_y)
        set_map_tile(bench, labels, move_x, move_y, TILE_TRAP | DUNGEON_FLAGS)
        bench.run(require(labels, "cx16_draw_dungeon"))
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        bench.set_a(run_command_for_move(move_command))
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_player_position(bench, labels, entry_x, entry_y, "run command stops before visible trap")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "run trap stop keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "run trap stop does not full-clear")
        set_map_tile(bench, labels, move_x, move_y, TILE_FLOOR | DUNGEON_FLAGS)

        set_player_position(bench, labels, entry_x, entry_y)
        set_map_tile(bench, labels, move_x, move_y, TILE_FLOOR | DUNGEON_FLAGS)
        bench.set_memory(require(labels, "trap_count"), 1)
        bench.set_memory(require(labels, "trap_x"), move_x)
        bench.set_memory(require(labels, "trap_y"), move_y)
        bench.set_memory(require(labels, "trap_type"), 0)
        bench.set_memory(require(labels, "zp_player_hp_lo"), 100)
        bench.set_memory(require(labels, "zp_player_hp_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 100)
        bench.set_memory(require(labels, "player_data") + PL_HP_HI, 0)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        saved_bank = bench.get_memory(CX16_RAM_BANK_REG)
        bench.set_a(move_command)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        if bench.get_memory(require(labels, "zp_player_hp_lo")) >= 100:
            raise AssertionError("movement onto trap did not apply trap damage")
        assert_eq(bench.get_memory(CX16_RAM_BANK_REG), saved_bank, "trap trigger restored caller RAM bank")
        assert_player_position(bench, labels, move_x, move_y, "movement trap moves player onto trap")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "movement trap keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "movement trap does not full-clear")
        bench.set_memory(require(labels, "trap_count"), 0)
        set_map_tile(bench, labels, move_x, move_y, TILE_FLOOR | DUNGEON_FLAGS)
        bench.set_memory(require(labels, "zp_player_hp_lo"), 100)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 100)

        set_player_position(bench, labels, entry_x, entry_y)
        bench.run(require(labels, "cx16_draw_dungeon"))
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        bench.set_a(run_command_for_move(move_command))
        bench.run(require(labels, "cx16_dispatch_game_command"))
        run_x = bench.get_memory(require(labels, "zp_player_x"))
        run_y = bench.get_memory(require(labels, "zp_player_y"))
        if (run_x, run_y) == (entry_x, entry_y):
            raise AssertionError("run command did not move the player")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "dungeon running does not full-clear")

        build_horizontal_run_corridor(bench, labels)
        add_floor_item(bench, labels, 22, 12, ITEM_PICK)
        set_player_position(bench, labels, 20, 12)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        bench.set_a(CMD_RUN_E)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_player_position(bench, labels, 22, 12, "run command stops on floor item")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "run item stop keeps player glyph")
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "dungeon run item stop does not full-clear")

        build_horizontal_run_corridor(bench, labels)
        set_player_position(bench, labels, 20, 12)
        bench.run(require(labels, "input_run_cancel_reset"))
        set_key_held(bench, True)
        screen_put_cell_raw(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2)
        bench.set_a(CMD_RUN_E)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        cancel_x = bench.get_memory(require(labels, "zp_player_x"))
        if cancel_x > 22:
            raise AssertionError(f"run cancel ignored held key; player reached x={cancel_x}")
        set_key_held(bench, False)
        assert_screen_cell(bench, CLEAR_SENTINEL_ROW, CLEAR_SENTINEL_COL, screen_code("*"), 2, "dungeon run cancel does not full-clear")

        set_player_position(bench, labels, floor_x, floor_y)
        bench.run(require(labels, "cx16_try_stairs_up"))
        assert_screen_text(bench, 0, 0, "You see no stairs here.", "no stairs message")

        down_x, down_y = find_map_tile_type(bench, labels, TILE_STAIRS_DN, "stairs down before deeper level")
        set_player_position(bench, labels, down_x, down_y)
        bench.run(require(labels, "cx16_try_stairs_down"))
        assert_eq(bench.get_memory(require(labels, "cx16_state")), 2, "deeper dungeon state")
        assert_eq(bench.get_memory(require(labels, "cx16_dungeon_depth")), 2, "deeper dungeon module depth")
        assert_eq(bench.get_memory(require(labels, "zp_player_dlvl")), 2, "deeper shared dungeon depth")
        assert_eq(bench.get_memory(require(labels, "cx16_loaded_tier")), 1, "deeper tier")
        assert_eq(bench.get_memory(require(labels, "cx16_loaded_tier_bank")), 4, "deeper tier bank")
        assert_eq(bench.get_memory(require(labels, "player_data") + PL_MAX_DLVL), 2, "max dungeon depth after descent")
        entry2_x = bench.get_memory(require(labels, "zp_player_x"))
        entry2_y = bench.get_memory(require(labels, "zp_player_y"))
        assert_map_tile_type(bench, labels, entry2_x, entry2_y, TILE_STAIRS_UP, "deeper entry stairs up")
        assert_floor_items_spawned(bench, labels)
        assert_screen_text(bench, 0, 0, "Dungeon level 2 ready.", "deeper level ready message")
        assert_screen_text(bench, 25, 66, "DL:2", "deeper status depth")

        bench.run(require(labels, "cx16_try_stairs_up"))
        assert_eq(bench.get_memory(require(labels, "cx16_state")), 2, "shallower dungeon state")
        assert_eq(bench.get_memory(require(labels, "cx16_dungeon_depth")), 1, "shallower dungeon module depth")
        assert_eq(bench.get_memory(require(labels, "zp_player_dlvl")), 1, "shallower shared dungeon depth")
        return_x = bench.get_memory(require(labels, "zp_player_x"))
        return_y = bench.get_memory(require(labels, "zp_player_y"))
        assert_map_tile_type(bench, labels, return_x, return_y, TILE_STAIRS_DN, "ascended return stairs down")
        assert_screen_text(bench, 0, 0, "Dungeon level 1 ready.", "shallower level ready message")
        assert_screen_text(bench, 25, 66, "DL:1", "shallower status depth")

        clear_carried_inventory(bench, labels)
        set_inventory_slot(bench, labels, 0, ITEM_RATION)
        set_inventory_slot(bench, labels, 1, ITEM_POTION_CURE)
        set_inventory_slot(bench, labels, 2, ITEM_STAFF_DETECT, p1=1)
        set_inventory_slot(bench, labels, EQUIP_WEAPON, ITEM_PICK, p1=STARTING_PICK_DIG_ABILITY, to_hit=1, to_dam=2)
        set_inventory_slot(bench, labels, EQUIP_BODY, ITEM_LEATHER_ARMOR, to_ac=4)
        set_inventory_slot(bench, labels, EQUIP_LIGHT, ITEM_LANTERN, p1=24)
        bench.set_memory(require(labels, "player_data") + PL_LEVEL, 5)
        bench.set_memory(require(labels, "zp_player_lvl"), 5)
        bench.set_memory(require(labels, "player_data") + PL_MHP_LO, 50)
        bench.set_memory(require(labels, "player_data") + PL_MHP_HI, 0)
        bench.set_memory(require(labels, "zp_player_mhp_lo"), 50)
        bench.set_memory(require(labels, "zp_player_mhp_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 7)
        bench.set_memory(require(labels, "player_data") + PL_HP_HI, 0)
        bench.set_memory(require(labels, "zp_player_hp_lo"), 7)
        bench.set_memory(require(labels, "zp_player_hp_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_MAX_MANA, 9)
        bench.set_memory(require(labels, "player_data") + PL_MANA, 2)
        bench.set_memory(require(labels, "zp_player_mmp"), 9)
        bench.set_memory(require(labels, "zp_player_mp"), 2)
        bench.set_memory(require(labels, "player_data") + PL_FOOD_LO, 0)
        bench.set_memory(require(labels, "player_data") + PL_FOOD_HI, 0)
        bench.set_memory(require(labels, "zp_player_food"), 0)
        bench.set_memory(require(labels, "zp_player_food_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_GOLD_0, 90)
        bench.set_memory(require(labels, "player_data") + PL_AC, 12)
        bench.set_memory(require(labels, "zp_player_ac"), 12)

        up_x, up_y = find_map_tile_type(bench, labels, TILE_STAIRS_UP, "stairs up before town return")
        set_player_position(bench, labels, up_x, up_y)
        bench.run(require(labels, "cx16_try_stairs_up"))
        assert_eq(bench.get_memory(require(labels, "cx16_state")), 1, "returned to town state")
        assert_eq(bench.get_memory(require(labels, "zp_player_dlvl")), 0, "returned to town depth")
        assert_screen_text(bench, 25, 66, "DL:0", "town status depth after upstairs")
        assert_player_position(bench, labels, 31, 18, "returned to town start")
        assert_eq(bench.get_memory(require(labels, "zp_player_hp_lo")), 7, "stairs up does not recover hp")
        assert_eq(bench.get_memory(require(labels, "zp_player_mp")), 2, "stairs up does not recover mana")
        assert_eq(bench.get_memory(require(labels, "player_data") + PL_GOLD_0), 90, "stairs up does not charge gold")
        assert_eq(count_carried_item(bench, labels, ITEM_RATION), 1, "stairs up preserves carried ration")
        assert_eq(count_carried_item(bench, labels, ITEM_POTION_CURE), 1, "stairs up preserves carried cure potion")
        assert_eq(bench.get_memory(inv_base + EQUIP_WEAPON), ITEM_PICK, "stairs up preserves equipped weapon")
        assert_eq(bench.get_memory(inv_base + EQUIP_BODY), ITEM_LEATHER_ARMOR, "stairs up preserves equipped armor")
        assert_eq(bench.get_memory(inv_base + EQUIP_LIGHT), ITEM_LANTERN, "stairs up preserves equipped light")
        assert_eq(bench.get_memory(require(labels, "inv_p1") + EQUIP_LIGHT), 24, "stairs up preserves lantern fuel")

        set_player_position(bench, labels, store_x, store_y + 1)
        bench.set_a(CMD_MOVE_N)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, store_x, store_y, "returned dungeon survivor enters town recovery")
        assert_screen_text(bench, 0, 0, "Rested and resupplied.", "post-dungeon town recovery message")
        assert_eq(bench.get_memory(require(labels, "zp_player_hp_lo")), 50, "post-dungeon town recovery restores hp")
        assert_eq(bench.get_memory(require(labels, "zp_player_mp")), 9, "post-dungeon town recovery restores mana")
        assert_eq(bench.get_memory(require(labels, "zp_player_food")), 0xD0, "post-dungeon town recovery food low")
        assert_eq(bench.get_memory(require(labels, "zp_player_food_hi")), 0x07, "post-dungeon town recovery food high")
        assert_eq(bench.get_memory(require(labels, "player_data") + PL_GOLD_0), 80, "post-dungeon town recovery charges gold")
        assert_eq(count_carried_item(bench, labels, ITEM_RATION), 2, "post-dungeon town recovery tops up rations")
        assert_eq(count_carried_item(bench, labels, ITEM_POTION_CURE), 2, "post-dungeon town recovery tops up cure potions")
        assert_eq(bench.get_memory(inv_base + 2), ITEM_STAFF_DETECT, "post-dungeon town recovery preserves carried tool")
        assert_eq(bench.get_memory(require(labels, "inv_p1") + 2), 1, "post-dungeon town recovery preserves tool charges")
        assert_eq(bench.get_memory(inv_base + EQUIP_WEAPON), ITEM_PICK, "post-dungeon town recovery preserves weapon")
        assert_eq(bench.get_memory(inv_base + EQUIP_BODY), ITEM_LEATHER_ARMOR, "post-dungeon town recovery preserves armor")
        assert_eq(bench.get_memory(inv_base + EQUIP_LIGHT), ITEM_LANTERN, "post-dungeon town recovery preserves light")
        assert_eq(bench.get_memory(require(labels, "inv_p1") + EQUIP_LIGHT), 24, "post-dungeon town recovery preserves lantern fuel")

        set_player_position(bench, labels, 32, 18)
        bench.run(require(labels, "cx16_try_stairs_down"))
        assert_eq(bench.get_memory(require(labels, "cx16_state")), 2, "re-entered dungeon state")
        assert_eq(bench.get_memory(require(labels, "cx16_dungeon_depth")), 1, "re-entered dungeon module depth")
        assert_eq(bench.get_memory(require(labels, "zp_player_dlvl")), 1, "re-entered shared dungeon depth")
        reentry_x = bench.get_memory(require(labels, "zp_player_x"))
        reentry_y = bench.get_memory(require(labels, "zp_player_y"))
        assert_map_tile_type(bench, labels, reentry_x, reentry_y, TILE_STAIRS_UP, "re-entry starts on stairs up")
        assert_floor_items_spawned(bench, labels)
        find_top_floor_item_by_id(bench, labels, ITEM_RATION)
        find_top_floor_item_by_id(bench, labels, ITEM_POTION_CURE)
        find_top_floor_item_by_id(bench, labels, ITEM_LEATHER_ARMOR)
        find_top_floor_item_by_id(bench, labels, ITEM_FLASK_OIL)
        assert_eq(bench.get_memory(require(labels, "zp_mon_count")), 3, "re-entry spawns monsters")
        assert_eq(bench.get_memory(require(labels, "zp_player_hp_lo")), 50, "re-entry preserves recovered hp")
        assert_eq(bench.get_memory(require(labels, "zp_player_mp")), 9, "re-entry preserves recovered mana")
        assert_eq(bench.get_memory(require(labels, "player_data") + PL_GOLD_0), 80, "re-entry preserves spent gold")
        assert_eq(count_carried_item(bench, labels, ITEM_RATION), 2, "re-entry preserves carried rations")
        assert_eq(count_carried_item(bench, labels, ITEM_POTION_CURE), 2, "re-entry preserves carried cure potions")
        assert_eq(bench.get_memory(inv_base + EQUIP_WEAPON), ITEM_PICK, "re-entry preserves weapon")
        assert_eq(bench.get_memory(inv_base + EQUIP_BODY), ITEM_LEATHER_ARMOR, "re-entry preserves armor")
        assert_eq(bench.get_memory(inv_base + EQUIP_LIGHT), ITEM_LANTERN, "re-entry preserves light")
        assert_screen_text(bench, 0, 0, "Dungeon level 1 ready.", "re-entry level ready message")
        assert_screen_text(bench, 25, 66, "DL:1", "re-entry status depth")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "re-entry player glyph")

        saved_mon_slot, saved_mon_x, saved_mon_y, _, _ = first_live_monster(bench, labels)
        saved_mon_base = require(labels, "monster_table") + (saved_mon_slot * MONSTER_ENTRY_SIZE)
        saved_mon_type = bench.get_memory(saved_mon_base + MX_TYPE)
        saved_item_slot, saved_item_x, saved_item_y = find_top_floor_item_by_id(bench, labels, ITEM_FLASK_OIL)
        saved_tile = map_tile_at(bench, labels, reentry_x, reentry_y)
        bench.set_memory(require(labels, "zp_msg_flags"), 0)
        stuff_key(bench, ord("S"))
        bench.run(require(labels, "cx16_poll_game"), timeout=12)
        assert_screen_text(bench, 0, 0, "Game saved.", "save key command message")
        if cwd and not os.path.exists(os.path.join(cwd, "THE.GAME")):
            raise AssertionError("CX16 save command did not create THE.GAME")

        bench.set_memory(require(labels, "cx16_state"), CX16_STATE_NEW_GAME)
        bench.set_memory(require(labels, "cx16_player_x"), 1)
        bench.set_memory(require(labels, "cx16_player_y"), 1)
        bench.set_memory(require(labels, "cx16_dungeon_depth"), 9)
        bench.set_memory(require(labels, "zp_player_x"), 1)
        bench.set_memory(require(labels, "zp_player_y"), 1)
        bench.set_memory(require(labels, "zp_player_dlvl"), 0)
        bench.set_memory(require(labels, "zp_player_hp_lo"), 1)
        bench.set_memory(require(labels, "zp_player_mp"), 1)
        bench.set_memory(require(labels, "player_data") + PL_GOLD_0, 1)
        bench.set_memory(inv_base + EQUIP_WEAPON, FI_EMPTY)
        bench.set_memory(inv_base + EQUIP_BODY, FI_EMPTY)
        bench.set_memory(inv_base + EQUIP_LIGHT, FI_EMPTY)
        bench.set_memory(require(labels, "fi_item_id") + saved_item_slot, FI_EMPTY)
        bench.set_memory(saved_mon_base + MX_TYPE, EMPTY_SLOT)
        set_map_tile(bench, labels, reentry_x, reentry_y, TILE_FLOOR | DUNGEON_FLAGS)

        bench.run(require(labels, "cx16_load_game_record"), timeout=12)
        assert_screen_text(bench, 0, 0, "Game loaded.", "load command message")
        assert_eq(bench.get_memory(require(labels, "cx16_state")), 2, "load restores dungeon state")
        assert_eq(bench.get_memory(require(labels, "cx16_player_x")), reentry_x, "load restores local x")
        assert_eq(bench.get_memory(require(labels, "cx16_player_y")), reentry_y, "load restores local y")
        assert_eq(bench.get_memory(require(labels, "zp_player_x")), reentry_x, "load restores shared x")
        assert_eq(bench.get_memory(require(labels, "zp_player_y")), reentry_y, "load restores shared y")
        assert_eq(bench.get_memory(require(labels, "zp_player_dlvl")), 1, "load restores depth")
        assert_eq(bench.get_memory(require(labels, "cx16_dungeon_depth")), 1, "load restores module depth")
        assert_eq(bench.get_memory(require(labels, "zp_player_hp_lo")), 50, "load restores hp")
        assert_eq(bench.get_memory(require(labels, "zp_player_mp")), 9, "load restores mana")
        assert_eq(bench.get_memory(require(labels, "player_data") + PL_GOLD_0), 80, "load restores gold")
        assert_eq(bench.get_memory(inv_base + EQUIP_WEAPON), ITEM_PICK, "load restores weapon")
        assert_eq(bench.get_memory(inv_base + EQUIP_BODY), ITEM_LEATHER_ARMOR, "load restores armor")
        assert_eq(bench.get_memory(inv_base + EQUIP_LIGHT), ITEM_LANTERN, "load restores light")
        assert_eq(bench.get_memory(require(labels, "fi_item_id") + saved_item_slot), ITEM_FLASK_OIL, "load restores floor item id")
        assert_eq(bench.get_memory(require(labels, "fi_x") + saved_item_slot), saved_item_x, "load restores floor item x")
        assert_eq(bench.get_memory(require(labels, "fi_y") + saved_item_slot), saved_item_y, "load restores floor item y")
        assert_eq(bench.get_memory(saved_mon_base + MX_TYPE), saved_mon_type, "load restores monster type")
        assert_eq(bench.get_memory(saved_mon_base + MX_X), saved_mon_x, "load restores monster x")
        assert_eq(bench.get_memory(saved_mon_base + MX_Y), saved_mon_y, "load restores monster y")
        assert_eq(map_tile_at(bench, labels, reentry_x, reentry_y), saved_tile, "load restores map tile")
        assert_screen_text(bench, 25, 66, "DL:1", "load redraws status depth")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "load redraws player glyph")

        bench.run(require(labels, "cx16_return_to_town"))
        assert_eq(bench.get_memory(require(labels, "cx16_state")), 1, "post-re-entry reset returns to town state")
        assert_eq(bench.get_memory(require(labels, "zp_player_dlvl")), 0, "post-re-entry reset returns to town depth")

        bench.run(require(labels, "cx16_draw_help_view"))
        assert_screen_text(bench, 3, 35, "Commands", "help view title")
        assert_screen_text(bench, 7, 14, "Move: HJKL/YUBN or 12346789", "help view movement")
        assert_screen_text(bench, 9, 14, "Run: shifted direction keys or . direction", "help view run")
        assert_screen_text(bench, 11, 14, "Features: O)pen C)lose s)earch X)look R)est", "help view features")
        assert_screen_text(bench, 13, 14, "More: Ctrl-B bash +)tunnel Shift-D disarm #)search", "help view more")
        assert_screen_text(bench, 15, 14, "Items: G)et D)rop I)nventory E)quipment", "help view items")
        assert_screen_text(bench, 17, 14, "Use: W)ear T)akeoff Shift-E eat Q)uaff R)ead", "help view use")
        assert_screen_text(bench, 19, 14, "Tools: A)im Z)use Shift-R refuel", "help view tools")
        assert_screen_text(bench, 21, 14, "Views: ?)help Shift-C character V)version", "help view views")
        assert_screen_text(bench, 23, 14, "System: S save, Shift-Q title", "help view system")
        for key, command, label in (
            (ord("O"), CMD_OPEN, "O maps to open"),
            (ord("C"), CMD_CLOSE, "C maps to close"),
            (ord("S"), CMD_SAVE, "S maps to save"),
            (ord("s"), CMD_SEARCH, "s maps to search"),
            (ord("X"), CMD_LOOK, "X maps to look"),
            (ord("5"), CMD_REST, "5 maps to rest"),
            (0x02, CMD_BASH, "Ctrl-B maps to bash"),
            (ord("+"), CMD_TUNNEL, "+ maps to tunnel"),
            (0xC4, CMD_DISARM, "Shift-D maps to disarm"),
            (ord("#"), CMD_SEARCH_MODE, "# maps to search mode"),
            (0x12, CMD_AUTOREST, "Ctrl-R maps to autorest"),
            (ord("G"), CMD_PICKUP, "G maps to pickup"),
            (ord(","), CMD_PICKUP, ", maps to pickup"),
            (ord("D"), CMD_DROP, "D maps to drop"),
            (ord("I"), CMD_INVENTORY, "I maps to inventory"),
            (ord("E"), CMD_EQUIPMENT, "E maps to equipment"),
            (ord("W"), CMD_WEAR, "W maps to wear"),
            (ord("T"), CMD_TAKEOFF, "T maps to take off"),
            (0xC5, CMD_EAT, "Shift-E maps to eat"),
            (ord("Q"), CMD_QUAFF, "Q maps to quaff"),
            (ord("R"), CMD_READ, "R maps to read"),
            (ord("A"), CMD_AIM, "A maps to aim"),
            (ord("Z"), CMD_USE, "Z maps to use"),
            (0xD2, CMD_REFUEL, "Shift-R maps to refuel"),
            (ord("?"), CMD_HELP, "? maps to help"),
            (0xC3, CMD_CHAR_INFO, "Shift-C maps to character info"),
            (ord("V"), CMD_VERSION, "V maps to version command"),
            (0xD1, CMD_QUIT, "Shift-Q maps to quit"),
            (0xD3, CMD_SAVE, "Shift-S maps to save"),
        ):
            bench.set_a(key)
            bench.run(require(labels, "petscii_to_command"))
            assert_eq(bench.get_a(), command, label)
        for key, label in (
            (ord("M"), "M unmapped until magic exists"),
            (ord("P"), "P unmapped until prayer exists"),
            (ord("F"), "F unmapped until gain spell exists"),
            (ord("f"), "f unmapped until gain spell exists"),
            (0xC6, "Shift-F unmapped until ranged fire exists"),
            (0xD4, "Shift-T unmapped until throw exists"),
            (ord("/"), "/ unmapped until recall/identify exists"),
            (0x17, "Ctrl-W unmapped until wizard mode exists"),
        ):
            bench.set_a(key)
            bench.run(require(labels, "petscii_to_command"))
            assert_eq(bench.get_a(), CMD_NONE, label)
        bench.run(require(labels, "cx16_draw_version_view"))
        assert_screen_text(bench, 10, 24, "Moria8 CX16 Port V1.3.1", "version view")
        bench.run(require(labels, "cx16_seed_starting_player_state"))
        bench.run(require(labels, "cx16_draw_character_view"))
        assert_screen_text(bench, 0, 33, "Character Info", "character view title")
        assert_screen_text(bench, 2, 22, "Name: CX16", "character view name")
        assert_screen_text(bench, 3, 22, "Race: Human", "character view race")
        assert_screen_text(bench, 3, 43, "Class: Warrior", "character view class")
        assert_screen_text(bench, 9, 22, "HP:12/12", "character view hp")
        assert_screen_text(bench, 9, 39, "Mana: 0/0", "character view mana")
        assert_screen_text(bench, 10, 22, "Gold: 200", "character view gold")
        assert_screen_text(bench, 12, 22, "Sex: Male  SC: 50", "character view sex social class")
        assert_screen_text(bench, 18, 33, "Press any key", "character view footer")
        bench.run(require(labels, "cx16_new_game_draw"))

        for command, text, label in (
            (CMD_REST, "That is only useful in the dungeon.", "rest command"),
            (CMD_SEARCH, "That is only useful in the dungeon.", "search command"),
            (CMD_LOOK, "That is only useful in the dungeon.", "look command"),
            (CMD_SEARCH_MODE, "That is only useful in the dungeon.", "search mode command"),
            (CMD_AUTOREST, "That is only useful in the dungeon.", "autorest command"),
            (CMD_OPEN, "That is only useful in the dungeon.", "open command"),
            (CMD_DROP, "That is only useful in the dungeon.", "drop command"),
            (CMD_FIRE, "That is only useful in the dungeon.", "fire command"),
            (CMD_BASH, "That is only useful in the dungeon.", "bash command"),
            (CMD_TUNNEL, "That is only useful in the dungeon.", "tunnel command"),
            (CMD_DISARM, "That is only useful in the dungeon.", "disarm command"),
        ):
            bench.run(require(labels, "msg_init"))
            bench.set_a(command)
            bench.run(require(labels, "cx16_dispatch_game_command"))
            assert_screen_text(bench, 0, 0, text, label)

        bench.set_a(1)
        bench.run(require(labels, "cx16_enter_dungeon_level"), timeout=8)
        death_slot, death_mon_x, death_mon_y, _, _ = first_live_monster(bench, labels)
        for slot in range(MAX_MONSTERS):
            mon_base = require(labels, "monster_table") + (slot * MONSTER_ENTRY_SIZE)
            if bench.get_memory(mon_base + MX_TYPE) != EMPTY_SLOT:
                bench.set_memory(mon_base + MX_TYPE, 0)
        bench.set_memory(require(labels, "monster_table") + (death_slot * MONSTER_ENTRY_SIZE) + MX_TYPE, 1)
        bench.set_memory(require(labels, "player_data") + PL_AC, 0)
        bench.set_memory(require(labels, "cx16_mon_slot"), death_slot)
        bench.set_memory(CX16_RAM_BANK_REG, CX16_OVERLAY_DEATH_BANK)
        tier_damage_seen = False
        for _ in range(20):
            bench.run(require(labels, "cx16_overlay_monster_attack_damage"))
            if bench.get_memory(require(labels, "cx16_mon_damage")) != 0:
                tier_damage_seen = True
                break
        if not tier_damage_seen:
            raise AssertionError("tier-backed monster attack damage rolled zero")
        bench.set_memory(CX16_RAM_BANK_REG, 0)
        death_command, death_px, death_py = find_player_pos_to_attack(bench, labels, death_mon_x, death_mon_y)
        set_player_position(bench, labels, death_px, death_py)
        bench.set_memory(require(labels, "zp_player_hp_lo"), 12)
        bench.set_memory(require(labels, "zp_player_hp_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 12)
        bench.set_memory(require(labels, "player_data") + PL_HP_HI, 0)
        hp_after_attack = 12
        bench.set_memory(require(labels, "monster_table") + (death_slot * MONSTER_ENTRY_SIZE) + MX_TYPE, 0)
        for _ in range(20):
            bench.set_a(CMD_REST)
            bench.run(require(labels, "cx16_dispatch_game_command"))
            hp_after_attack = bench.get_memory(require(labels, "zp_player_hp_lo"))
            if hp_after_attack < 12:
                break
        if hp_after_attack >= 12:
            raise AssertionError("monster attack did not damage player")
        if hp_after_attack == 0:
            raise AssertionError("monster attack killed player before death-flow check")
        assert_screen_text(bench, 0, 0, "The Kobold hits you.", "monster attack message")
        bench.set_memory(require(labels, "monster_table") + (death_slot * MONSTER_ENTRY_SIZE) + MX_TYPE, 1)
        bench.set_memory(require(labels, "zp_player_hp_lo"), 1)
        bench.set_memory(require(labels, "zp_player_hp_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 1)
        bench.set_memory(require(labels, "player_data") + PL_HP_HI, 0)
        for _ in range(20):
            bench.set_a(CMD_REST)
            bench.run(require(labels, "cx16_dispatch_game_command"))
            if bench.get_memory(require(labels, "cx16_state")) == CX16_STATE_DEAD:
                break
        assert_eq(bench.get_memory(require(labels, "cx16_state")), CX16_STATE_DEAD, "monster attack enters death state")
        assert_eq(bench.get_memory(require(labels, "zp_death_source")), 1, "monster death source records tier creature")
        assert_screen_text(bench, 0, 0, "* You have died *", "death flow message")
        stuff_key(bench, 0xD1)
        bench.run(require(labels, "cx16_poll_dead"))
        assert_eq(bench.get_memory(require(labels, "cx16_state")), 0, "death flow quit returns to title")
        assert_eq(bench.get_memory(require(labels, "zp_game_flags")) & 0x01, 0x01, "death flag remains set on title")
        stuff_key(bench, ord("N"))
        bench.run(require(labels, "cx16_poll_menu"), timeout=8)
        assert_eq(bench.get_memory(require(labels, "cx16_state")), CX16_STATE_NEW_GAME, "new game after death reaches town")
        assert_eq(bench.get_memory(require(labels, "zp_game_flags")) & 0x01, 0, "new game after death clears death flag")
        assert_eq(bench.get_memory(require(labels, "zp_death_source")), 0, "new game after death clears death source")
        bench.set_a(1)
        bench.run(require(labels, "cx16_enter_dungeon_level"), timeout=8)
        assert_eq(bench.get_memory(require(labels, "cx16_state")), CX16_STATE_DUNGEON, "new game after death enters dungeon")
        bench.set_a(CMD_REST)
        bench.run(require(labels, "cx16_dispatch_game_command"), timeout=8)
        assert_eq(
            bench.get_memory(require(labels, "cx16_state")),
            CX16_STATE_DUNGEON,
            "new game after death survives first dungeon turn",
        )

        print("CX16 runtime smoke passed")
    finally:
        bench.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
