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
MAP_COLS = 198
MAP_ROWS = 66
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
CMD_DROP = 0x10
CMD_INVENTORY = 0x11
CMD_CAST = 0x1A
CMD_CHAR_INFO = 0x1C
CMD_MAP = 0x1D
CMD_RECALL = 0x1E
CMD_LOOK = 0x1F
CMD_SAVE = 0x21
CMD_HELP = 0x23
CMD_VERSION = 0x24
CMD_GAIN = 0x2D
CMD_FIRE = 0x2E
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
CX16_TIER_GUARD_BANK = 5
CX16_DUNGEON_MODULE_BANK = 8
CX16_DUNGEON_MODULE_GUARD_BANK = 9
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
        raise TimeoutError("timed out waiting for x16emu output")

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
    row_lo = require(labels, "map_row_lo")
    row_hi = require(labels, "map_row_hi")
    row_addr = bench.get_memory(row_lo + y) | (bench.get_memory(row_hi + y) << 8)
    return bench.get_memory(row_addr + x)


def screen_code(ch):
    value = ord(ch)
    if 65 <= value <= 90:
        return value - 64
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


def assert_eq(actual, expected, label):
    if actual != expected:
        raise AssertionError(f"{label}: expected ${expected:02X}, got ${actual:02X}")


def assert_screen_text(bench, row, col, text, label):
    for offset, ch in enumerate(text):
        actual = screen_char_at(bench, row, col + offset)
        expected = screen_code(ch)
        assert_eq(actual, expected, f"{label} char {offset}")


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


def assert_map_tile_type(bench, labels, x, y, expected_type, label):
    assert_eq(tile_type(map_tile_at(bench, labels, x, y)), expected_type, label)


def tile_type(tile):
    return tile & TILE_TYPE_MASK


def find_map_tile_type(bench, labels, wanted_type, label):
    for y in range(MAP_ROWS):
        for x in range(MAP_COLS):
            if tile_type(map_tile_at(bench, labels, x, y)) == wanted_type:
                return x, y
    raise AssertionError(f"{label}: tile type ${wanted_type:02X} not found")


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
        assert_tier_prg_load_to_bank(bench, labels, args.cwd)
        assert_dungeon_module_load_execute(bench, labels, args.cwd)

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
        assert_screen_text(bench, 25, 24, "MONSTER.DB.1 LOADED", "dungeon tier loaded")
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

        set_player_position(bench, labels, wall_x + 1, wall_y + 1)
        bench.set_a(CMD_MOVE_NW)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, wall_x + 1, wall_y + 1, "dungeon blocked wall move")

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
