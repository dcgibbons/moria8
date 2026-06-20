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


STATUS_CARRY = 0x01
TOWN_FLAGS = 0x0C
TILE_STAIRS_DN = 0x90
CMD_MOVE_W = 0x03
CMD_MOVE_S = 0x02
CMD_MOVE_E = 0x04
SC_PLAYER = 0x00
SC_REVERSE_SPACE = 0xA0
TEXT_COLOR = 0x01
STORE_COLOR = 0x07
TITLE_BORDER_COLOR = 0x0F
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--x16emu", required=True)
    parser.add_argument("--rom", default="")
    parser.add_argument("--prg", required=True)
    parser.add_argument("--symbols", required=True)
    parser.add_argument("--cwd", default="")
    args = parser.parse_args()

    labels = load_symbols(args.symbols)
    cwd = args.cwd if args.cwd else None
    prg = args.prg
    if cwd:
        prg = os.path.basename(prg)
    bench = X16Bench(args.x16emu, args.rom, prg, cwd)
    try:
        bench.run(require(labels, "cx16_memory_init"))
        if bench.get_status() & STATUS_CARRY:
            raise AssertionError("cx16_memory_init reported failure")

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
        assert_screen_text(
            bench,
            26,
            22,
            "DUNGEON ENTRY NOT WIRED YET.",
            "stairs down message",
        )

        bench.set_memory(require(labels, "zp_player_x"), 31)
        bench.set_memory(require(labels, "zp_player_y"), 18)
        bench.run(require(labels, "town_basic_check_stairs_at_player"))
        assert_eq(bench.get_a(), 0, "non-stairs probe")
        bench.run(require(labels, "cx16_try_stairs_up"))
        assert_screen_text(bench, 26, 28, "YOU SEE NO STAIRS HERE.", "no stairs message")

        print("CX16 runtime smoke passed")
    finally:
        bench.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
