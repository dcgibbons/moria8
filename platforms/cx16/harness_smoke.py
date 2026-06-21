#!/usr/bin/env python3
"""Runtime smoke checks for the Commander X16 bootstrap.

This speaks x16emu's documented -testbench protocol directly. It intentionally
tests RAM-visible contracts instead of screenshots: the CX16 port is still a
bootstrap, and map/player/town-interaction state is the stable contract.
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
PL_FOOD_LO = 51
PL_FOOD_HI = 52
PL_FLAGS = 54
PLF_SEARCHING = 0x10
KEYBUF = 0xA800
KEYBUF_COUNT = 0xA80A
MAP_COLS = 198
MAP_ROWS = 66
MAX_FLOOR_ITEMS = 42
EQUIP_LIGHT = 28
EQUIP_WEAPON = 22
ITEM_LANTERN = 14
ITEM_RATION = 15
ITEM_POTION_CURE = 17
ITEM_SCROLL_LIGHT = 20
ITEM_WAND_LIGHT = 39
ITEM_STAFF_DETECT = 44
ITEM_FLASK_OIL = 61
ITEM_PICK = 63
BOOTSTRAP_PICK_DIG_ABILITY = 24
ICAT_WEAPON = 2
FI_EMPTY = 0xFF
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
CMD_CHAR_INFO = 0x1C
CMD_MAP = 0x1D
CMD_RECALL = 0x1E
CMD_LOOK = 0x1F
CMD_SAVE = 0x21
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
CMD_REFUEL = 0x30
CMD_BASH = 0x31
CMD_TUNNEL = 0x32
CMD_WIZARD = 0x33
CMD_SEARCH_MODE = 0x34
CMD_DISARM = 0x35
CMD_AUTOREST = 0x36
SC_PLAYER = 0x00
SC_REVERSE_SPACE = 0xA0
TEXT_COLOR = 0x01
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
        self.command(f"RUN {address:04X}", wait=False)
        self.wait_ready(timeout=timeout)

    def set_memory(self, address, value):
        self.command(f"STM {address:04X} {value:02X}")

    def set_a(self, value):
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
    if 65 <= value <= 90:
        return value - 64
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
    bench.set_memory(KEYBUF, petscii)
    bench.set_memory(KEYBUF_COUNT, 1)


def set_key_held(bench, held):
    bench.set_memory(KEYBUF_COUNT, 1 if held else 0)


def set_inventory_slot0(bench, labels, item_id, qty=1, p1=0):
    bench.set_memory(require(labels, "inv_item_id"), item_id)
    bench.set_memory(require(labels, "inv_qty"), qty)
    bench.set_memory(require(labels, "inv_p1"), p1)
    bench.set_memory(require(labels, "inv_to_hit"), 0)
    bench.set_memory(require(labels, "inv_to_dam"), 0)
    bench.set_memory(require(labels, "inv_to_ac"), 0)
    bench.set_memory(require(labels, "inv_flags"), 0)
    bench.set_memory(require(labels, "inv_ego"), 0)


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
    for slot in range(MAX_FLOOR_ITEMS):
        item_id = bench.get_memory(item_base + slot)
        if item_id == 0xFF:
            continue
        x = bench.get_memory(item_x_base + slot)
        y = bench.get_memory(item_y_base + slot)
        tile = map_tile_at(bench, labels, x, y)
        if not (tile & FLAG_HAS_ITEM):
            raise AssertionError(f"floor item slot {slot} at ({x},{y}) missing FLAG_HAS_ITEM")
        return

    raise AssertionError("zp_item_count is nonzero but no occupied floor item slot was found")


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
        assert_screen_text(bench, 18, 27, "N)EW  L)OAD  Q)UIT", "title menu")

        bench.run(require(labels, "cx16_new_game_start"), timeout=8)

        assert_eq(bench.get_memory(require(labels, "cx16_state")), 1, "CX16 state")
        assert_player_position(bench, labels, 31, 18, "new game")
        assert_eq(bench.get_memory(require(labels, "zp_player_dlvl")), 0, "town depth")
        assert_eq(bench.get_memory(require(labels, "inv_item_id") + EQUIP_WEAPON), ITEM_PICK, "bootstrap weapon")
        assert_eq(bench.get_memory(require(labels, "zp_player_str")), 18, "bootstrap strength")
        bench.run(require(labels, "tramp_dig_ability"))
        assert_eq(
            bench.get_memory(require(labels, "tun_dig_ability")),
            BOOTSTRAP_PICK_DIG_ABILITY,
            "bootstrap pick dig ability from banked item catalog",
        )
        assert_eq(map_tile_at(bench, labels, 32, 18), TILE_STAIRS_DN | TOWN_FLAGS, "town stairs tile")
        assert_screen_text(bench, 0, 33, "TOWN", "town title")
        assert_screen_text(
            bench,
            26,
            14,
            "HJKL/YUBN OR NUMBERS MOVE. SHIFT-Q RETURNS TO TITLE.",
            "town help",
        )
        assert_screen_cell(bench, 20, 38, SC_PLAYER, TEXT_COLOR, "initial player")

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
        assert_screen_text(bench, 26, 29, "STORE DOOR 1", "store door message")

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
        assert_eq(bench.get_memory(require(labels, "cx16_state")), 2, "CX16 dungeon bootstrap state")
        assert_eq(bench.get_memory(require(labels, "cx16_loaded_tier")), 1, "loaded tier")
        assert_eq(bench.get_memory(require(labels, "cx16_loaded_tier_bank")), 4, "loaded tier bank")
        assert_eq(bench.get_memory(require(labels, "cx16_dungeon_module_status")), 1, "dungeon module status after stairs")
        assert_eq(bench.get_memory(require(labels, "cx16_dungeon_depth")), 1, "dungeon bootstrap depth")
        assert_eq(bench.get_memory(require(labels, "zp_player_dlvl")), 1, "shared dungeon depth")
        entry_x = bench.get_memory(require(labels, "zp_player_x"))
        entry_y = bench.get_memory(require(labels, "zp_player_y"))
        assert_player_position(bench, labels, entry_x, entry_y, "dungeon entry player position")
        assert_floor_items_spawned(bench, labels)
        assert_map_tile_type(bench, labels, entry_x, entry_y, TILE_STAIRS_UP, "module stairs up tile")
        down_x, down_y = find_map_tile_type(bench, labels, TILE_STAIRS_DN, "module stairs down")
        floor_x, floor_y = find_map_tile_type(bench, labels, TILE_FLOOR, "module floor")
        wall_x, wall_y = find_map_tile_type(bench, labels, TILE_WALL_H, "module wall")
        assert_map_tile_type(bench, labels, down_x, down_y, TILE_STAIRS_DN, "module stairs down tile")
        assert_map_tile_type(bench, labels, floor_x, floor_y, TILE_FLOOR, "module floor tile")
        assert_map_tile_type(bench, labels, wall_x, wall_y, TILE_WALL_H, "module wall tile")
        assert_screen_text(bench, 0, 31, "DUNGEON LEVEL 1", "dungeon title")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "dungeon entry player")
        assert_screen_cell(bench, 2, 1, screen_code(" "), 0, "unvisited dungeon rock")
        assert_screen_text(bench, 25, 24, "MONSTER TIER 1 READY", "dungeon tier ready")
        assert_screen_text(
            bench,
            26,
            10,
            "HJKL/YUBN OR NUMBERS MOVE. < RETURNS TO TOWN. SHIFT-Q TITLE.",
            "dungeon help",
        )

        move_command, move_x, move_y = find_adjacent_floor_move(bench, labels, entry_x, entry_y)
        assert_screen_contains_cell(bench, screen_code("."), 11, "visible dungeon floor")
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        bench.set_a(move_command)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, move_x, move_y, "dungeon adjacent move")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "dungeon moved player")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "dungeon movement does not full-clear")

        set_player_position(bench, labels, entry_x, entry_y)
        bench.run(require(labels, "cx16_draw_dungeon_bootstrap"))
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        bench.set_a(move_command)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_player_position(bench, labels, move_x, move_y, "dungeon move through dispatcher")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "dungeon scrolling movement does not full-clear")

        set_player_position(bench, labels, entry_x, entry_y)
        bench.set_memory(require(labels, "player_data") + PL_FLAGS, PLF_SEARCHING)
        bench.set_a(move_command)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        if bench.get_memory(require(labels, "player_data") + PL_FLAGS) & PLF_SEARCHING:
            raise AssertionError("dungeon movement did not clear search mode")

        set_player_position(bench, labels, wall_x + 1, wall_y + 1)
        bench.set_a(CMD_MOVE_NW)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, wall_x + 1, wall_y + 1, "dungeon blocked wall move")

        door_x, door_y, door_px, door_py = find_adjacent_tile_type(
            bench, labels, TILE_DOOR_CLOSED, "closed dungeon door"
        )
        set_player_position(bench, labels, door_px, door_py)
        bench.set_memory(require(labels, "zp_player_str"), 18)
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        stuff_direction_to_target(bench, door_px, door_py, door_x, door_y)
        bench.set_a(CMD_OPEN)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_map_tile_type(bench, labels, door_x, door_y, TILE_DOOR_OPEN, "opened dungeon door")
        assert_player_position(bench, labels, door_px, door_py, "open command keeps player position")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "open command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "open command does not full-clear")

        stuff_direction_to_target(bench, door_px, door_py, door_x, door_y)
        bench.set_a(CMD_CLOSE)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_map_tile_type(bench, labels, door_x, door_y, TILE_DOOR_CLOSED, "closed dungeon door")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "close command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "close command does not full-clear")

        set_player_position(bench, labels, door_px, door_py)
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        bench.set_a(CMD_SEARCH)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        if assert_screen_text_matches(bench, 26, 23, "SEARCH/REST/LOOK NOT WIRED YET."):
            raise AssertionError("search command still rendered the activity stub")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "search command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "search command does not full-clear")

        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        bench.set_a(CMD_REST)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        if assert_screen_text_matches(bench, 26, 23, "SEARCH/REST/LOOK NOT WIRED YET."):
            raise AssertionError("rest command still rendered the activity stub")
        assert_player_position(bench, labels, door_px, door_py, "rest command keeps player position")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "rest command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "rest command does not full-clear")

        bench.set_memory(require(labels, "player_data") + PL_FLAGS, 0)
        bench.set_a(CMD_SEARCH_MODE)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        if not (bench.get_memory(require(labels, "player_data") + PL_FLAGS) & PLF_SEARCHING):
            raise AssertionError("search mode command did not set the searching flag")
        assert_screen_text(bench, 25, 0, "Search mode on.", "search mode on message")
        bench.set_a(CMD_SEARCH_MODE)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        if bench.get_memory(require(labels, "player_data") + PL_FLAGS) & PLF_SEARCHING:
            raise AssertionError("search mode command did not clear the searching flag")
        assert_screen_text(bench, 25, 0, "Search mode off.", "search mode off message")

        set_player_position(bench, labels, door_px, door_py)
        set_map_tile(bench, labels, door_x, door_y, TILE_FLOOR | DUNGEON_FLAGS)
        bench.set_memory(require(labels, "zp_player_str"), 18)
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        stuff_direction_to_target(bench, door_px, door_py, door_x, door_y)
        bench.set_a(CMD_BASH)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_player_position(bench, labels, door_px, door_py, "bash command keeps player position")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "bash command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "bash command does not full-clear")

        set_player_position(bench, labels, door_px, door_py)
        set_map_tile(bench, labels, door_x, door_y, TILE_RUBBLE | DUNGEON_FLAGS)
        bench.set_memory(require(labels, "zp_player_str"), 255)
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        for _ in range(8):
            if tile_type(map_tile_at(bench, labels, door_x, door_y)) == TILE_FLOOR:
                break
            stuff_direction_to_target(bench, door_px, door_py, door_x, door_y)
            bench.set_a(CMD_TUNNEL)
            bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_map_tile_type(bench, labels, door_x, door_y, TILE_FLOOR, "tunnel with pick removes rubble")
        assert_player_position(bench, labels, door_px, door_py, "tunnel command keeps player position")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "tunnel command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "tunnel command does not full-clear")
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
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        stuff_direction_to_target(bench, door_px, door_py, door_x, door_y)
        bench.set_a(CMD_DISARM)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(require(labels, "trap_count")), 0, "disarm command removes trap")
        assert_map_tile_type(bench, labels, door_x, door_y, TILE_FLOOR, "disarm command restores floor")
        assert_player_position(bench, labels, door_x, door_y, "disarm command moves onto trap")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "disarm command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "disarm command does not full-clear")

        set_player_position(bench, labels, floor_x, floor_y)
        item_count_before_pickup = bench.get_memory(require(labels, "zp_item_count"))
        add_floor_item(bench, labels, floor_x, floor_y, ITEM_PICK)
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        bench.set_a(CMD_PICKUP)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(
            bench.get_memory(require(labels, "zp_item_count")),
            item_count_before_pickup,
            "pickup command removes floor item",
        )
        assert_eq(bench.get_memory(require(labels, "inv_item_id")), ITEM_PICK, "pickup command fills inventory slot")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "pickup command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "pickup command does not full-clear")

        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
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
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "drop command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "drop command does not full-clear")

        inv_base = require(labels, "inv_item_id")
        bench.set_memory(inv_base, ITEM_PICK)
        bench.set_memory(require(labels, "inv_qty"), 1)
        bench.set_memory(require(labels, "inv_p1"), BOOTSTRAP_PICK_DIG_ABILITY)
        bench.set_memory(require(labels, "inv_to_hit"), 0)
        bench.set_memory(require(labels, "inv_to_dam"), 0)
        bench.set_memory(require(labels, "inv_to_ac"), 0)
        bench.set_memory(require(labels, "inv_flags"), 0)
        bench.set_memory(require(labels, "inv_ego"), 0)
        bench.set_memory(inv_base + EQUIP_WEAPON, FI_EMPTY)
        stuff_key(bench, ord("A"))
        bench.set_a(CMD_WEAR)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), FI_EMPTY, "wear command removes carried item")
        assert_eq(bench.get_memory(inv_base + EQUIP_WEAPON), ITEM_PICK, "wear command equips weapon")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "wear command keeps player glyph")

        stuff_key(bench, ord("A"))
        bench.set_a(CMD_TAKEOFF)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), ITEM_PICK, "takeoff command restores carried item")
        assert_eq(bench.get_memory(inv_base + EQUIP_WEAPON), FI_EMPTY, "takeoff command clears weapon slot")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "takeoff command keeps player glyph")

        bench.set_memory(inv_base, ITEM_RATION)
        bench.set_memory(require(labels, "inv_qty"), 1)
        bench.set_memory(require(labels, "zp_player_food"), 0)
        bench.set_memory(require(labels, "zp_player_food_hi"), 0)
        bench.set_memory(require(labels, "player_data") + PL_FOOD_LO, 0)
        bench.set_memory(require(labels, "player_data") + PL_FOOD_HI, 0)
        bench.set_a(CMD_EAT)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), FI_EMPTY, "eat command consumes food")
        if bench.get_memory(require(labels, "zp_player_food_hi")) == 0:
            raise AssertionError("eat command did not increase food counter")
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
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        stuff_key(bench, ord("A"))
        bench.set_a(CMD_QUAFF)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), FI_EMPTY, "quaff command consumes potion")
        if bench.get_memory(require(labels, "zp_player_hp_lo")) <= 10:
            raise AssertionError("quaff command did not heal the player")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "quaff command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "quaff command does not full-clear")

        bench.set_memory(inv_base, ITEM_FLASK_OIL)
        bench.set_memory(require(labels, "inv_qty"), 1)
        bench.set_memory(require(labels, "inv_p1"), 20)
        bench.set_memory(inv_base + EQUIP_LIGHT, ITEM_LANTERN)
        bench.set_memory(require(labels, "inv_qty") + EQUIP_LIGHT, 1)
        bench.set_memory(require(labels, "inv_p1") + EQUIP_LIGHT, 10)
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        bench.set_a(CMD_REFUEL)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), FI_EMPTY, "refuel command consumes oil flask")
        assert_eq(bench.get_memory(require(labels, "inv_p1") + EQUIP_LIGHT), 30, "refuel command adds oil")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "refuel command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "refuel command does not full-clear")

        set_inventory_slot0(bench, labels, ITEM_SCROLL_LIGHT)
        bench.set_memory(require(labels, "id_known") + ITEM_SCROLL_LIGHT, 0)
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        stuff_key(bench, ord("A"))
        bench.set_a(CMD_READ)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), FI_EMPTY, "read command consumes scroll")
        assert_eq(bench.get_memory(require(labels, "id_known") + ITEM_SCROLL_LIGHT), 1, "read command marks scroll known")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "read command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "read command does not full-clear")

        set_inventory_slot0(bench, labels, ITEM_WAND_LIGHT, p1=2)
        bench.set_memory(require(labels, "id_known") + ITEM_WAND_LIGHT, 0)
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        stuff_key(bench, ord("A"))
        bench.set_a(CMD_AIM)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), ITEM_WAND_LIGHT, "aim command keeps wand")
        assert_eq(bench.get_memory(require(labels, "inv_p1")), 1, "aim command consumes one wand charge")
        assert_eq(bench.get_memory(require(labels, "id_known") + ITEM_WAND_LIGHT), 1, "aim command marks wand known")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "aim command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "aim command does not full-clear")

        set_inventory_slot0(bench, labels, ITEM_STAFF_DETECT, p1=2)
        bench.set_memory(require(labels, "id_known") + ITEM_STAFF_DETECT, 0)
        bench.set_memory(require(labels, "eff_detect_timer"), 0)
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        stuff_key(bench, ord("A"))
        bench.set_a(CMD_USE)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_eq(bench.get_memory(inv_base), ITEM_STAFF_DETECT, "use command keeps staff")
        assert_eq(bench.get_memory(require(labels, "inv_p1")), 1, "use command consumes one staff charge")
        assert_eq(bench.get_memory(require(labels, "id_known") + ITEM_STAFF_DETECT), 1, "use command marks staff known")
        assert_eq(bench.get_memory(require(labels, "eff_detect_timer")), 20, "use command activates detect monsters")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "use command keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "use command does not full-clear")

        set_player_position(bench, labels, entry_x, entry_y)
        set_map_tile(bench, labels, move_x, move_y, TILE_TRAP | DUNGEON_FLAGS)
        bench.run(require(labels, "cx16_draw_dungeon_bootstrap"))
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        bench.set_a(run_command_for_move(move_command))
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_player_position(bench, labels, entry_x, entry_y, "run command stops before visible trap")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "run trap stop keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "run trap stop does not full-clear")
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
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        saved_bank = bench.get_memory(CX16_RAM_BANK_REG)
        bench.set_a(move_command)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        if bench.get_memory(require(labels, "zp_player_hp_lo")) >= 100:
            raise AssertionError("movement onto trap did not apply trap damage")
        assert_eq(bench.get_memory(CX16_RAM_BANK_REG), saved_bank, "trap trigger restored caller RAM bank")
        assert_player_position(bench, labels, move_x, move_y, "movement trap moves player onto trap")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "movement trap keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "movement trap does not full-clear")
        bench.set_memory(require(labels, "trap_count"), 0)
        set_map_tile(bench, labels, move_x, move_y, TILE_FLOOR | DUNGEON_FLAGS)
        bench.set_memory(require(labels, "zp_player_hp_lo"), 100)
        bench.set_memory(require(labels, "player_data") + PL_HP_LO, 100)

        set_player_position(bench, labels, entry_x, entry_y)
        bench.run(require(labels, "cx16_draw_dungeon_bootstrap"))
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        bench.set_a(run_command_for_move(move_command))
        bench.run(require(labels, "cx16_dispatch_game_command"))
        run_x = bench.get_memory(require(labels, "zp_player_x"))
        run_y = bench.get_memory(require(labels, "zp_player_y"))
        if (run_x, run_y) == (entry_x, entry_y):
            raise AssertionError("run command did not move the player")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "dungeon running does not full-clear")

        build_horizontal_run_corridor(bench, labels)
        add_floor_item(bench, labels, 22, 12, ITEM_PICK)
        set_player_position(bench, labels, 20, 12)
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        bench.set_a(CMD_RUN_E)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        assert_player_position(bench, labels, 22, 12, "run command stops on floor item")
        assert_screen_contains_cell(bench, SC_PLAYER, TEXT_COLOR, "run item stop keeps player glyph")
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "dungeon run item stop does not full-clear")

        build_horizontal_run_corridor(bench, labels)
        set_player_position(bench, labels, 20, 12)
        bench.run(require(labels, "input_run_cancel_reset"))
        set_key_held(bench, True)
        screen_put_cell_raw(bench, 1, 0, screen_code("*"), 2)
        bench.set_a(CMD_RUN_E)
        bench.run(require(labels, "cx16_dispatch_game_command"))
        cancel_x = bench.get_memory(require(labels, "zp_player_x"))
        if cancel_x > 22:
            raise AssertionError(f"run cancel ignored held key; player reached x={cancel_x}")
        set_key_held(bench, False)
        assert_screen_cell(bench, 1, 0, screen_code("*"), 2, "dungeon run cancel does not full-clear")

        set_player_position(bench, labels, floor_x, floor_y)
        bench.run(require(labels, "cx16_try_stairs_up"))
        assert_screen_text(bench, 26, 28, "YOU SEE NO STAIRS HERE.", "no stairs message")

        set_player_position(bench, labels, entry_x, entry_y)
        bench.run(require(labels, "cx16_try_stairs_up"))
        assert_eq(bench.get_memory(require(labels, "cx16_state")), 1, "returned to town state")
        assert_eq(bench.get_memory(require(labels, "zp_player_dlvl")), 0, "returned to town depth")
        assert_screen_text(bench, 0, 33, "TOWN", "town title after upstairs")

        for command, col, text, label in (
            (CMD_REST, 23, "SEARCH/REST/LOOK NOT WIRED YET.", "rest command"),
            (CMD_SEARCH, 23, "SEARCH/REST/LOOK NOT WIRED YET.", "search command"),
            (CMD_LOOK, 23, "SEARCH/REST/LOOK NOT WIRED YET.", "look command"),
            (CMD_SEARCH_MODE, 23, "SEARCH/REST/LOOK NOT WIRED YET.", "search mode command"),
            (CMD_AUTOREST, 23, "SEARCH/REST/LOOK NOT WIRED YET.", "autorest command"),
            (CMD_OPEN, 23, "ITEM/FEATURE COMMAND NOT WIRED YET.", "open command"),
            (CMD_DROP, 23, "ITEM/FEATURE COMMAND NOT WIRED YET.", "drop command"),
            (CMD_INVENTORY, 23, "ITEM/FEATURE COMMAND NOT WIRED YET.", "inventory command"),
            (CMD_FIRE, 23, "ITEM/FEATURE COMMAND NOT WIRED YET.", "fire command"),
            (CMD_BASH, 23, "ITEM/FEATURE COMMAND NOT WIRED YET.", "bash command"),
            (CMD_TUNNEL, 23, "ITEM/FEATURE COMMAND NOT WIRED YET.", "tunnel command"),
            (CMD_DISARM, 23, "ITEM/FEATURE COMMAND NOT WIRED YET.", "disarm command"),
            (CMD_CAST, 25, "MAGIC/RECALL NOT WIRED YET.", "cast command"),
            (CMD_RECALL, 25, "MAGIC/RECALL NOT WIRED YET.", "recall command"),
            (CMD_GAIN, 25, "MAGIC/RECALL NOT WIRED YET.", "gain command"),
            (CMD_SAVE, 24, "SAVE/LOAD NOT WIRED YET.", "save command"),
            (CMD_HELP, 8, "MOVE HJKL/YUBN/12346789. > STAIRS. SHIFT-Q TITLE.", "help command"),
            (CMD_CHAR_INFO, 19, "CHARACTER INFO: TOWN BOOTSTRAP, DEPTH 0.", "character info command"),
            (CMD_VERSION, 24, "MORIA8 CX16 BOOTSTRAP V1.3.1", "version command"),
            (CMD_MAP, 24, "INFO/HELP NOT WIRED YET.", "map command"),
            (CMD_WIZARD, 26, "WIZARD MODE NOT ENABLED.", "wizard command"),
        ):
            bench.set_a(command)
            bench.run(require(labels, "cx16_dispatch_game_command"))
            assert_screen_text(bench, 26, col, text, label)

        print("CX16 runtime smoke passed")
    finally:
        bench.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
