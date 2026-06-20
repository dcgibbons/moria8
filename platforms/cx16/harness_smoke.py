#!/usr/bin/env python3
"""Runtime smoke checks for the Commander X16 bootstrap.

This speaks x16emu's documented -testbench protocol directly. It intentionally
tests RAM-visible contracts instead of screenshots: the CX16 port is still a
bootstrap, and map/player/town-interaction state is the stable contract.
"""

import argparse
import select
import subprocess
import sys
import time


STATUS_CARRY = 0x01
TOWN_FLAGS = 0x0C
TILE_STAIRS_DN = 0x90
CMD_MOVE_W = 0x03
CMD_MOVE_E = 0x04


class X16Bench:
    def __init__(self, x16emu, rom, prg):
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


def assert_eq(actual, expected, label):
    if actual != expected:
        raise AssertionError(f"{label}: expected ${expected:02X}, got ${actual:02X}")


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
    args = parser.parse_args()

    labels = load_symbols(args.symbols)
    bench = X16Bench(args.x16emu, args.rom, args.prg)
    try:
        bench.run(require(labels, "cx16_memory_init"))
        if bench.get_status() & STATUS_CARRY:
            raise AssertionError("cx16_memory_init reported failure")

        bench.run(require(labels, "screen_init"))
        bench.run(require(labels, "cx16_new_game_start"), timeout=8)

        assert_eq(bench.get_memory(require(labels, "cx16_state")), 1, "CX16 state")
        assert_player_position(bench, labels, 31, 18, "new game")
        assert_eq(bench.get_memory(require(labels, "zp_player_dlvl")), 0, "town depth")
        assert_eq(map_tile_at(bench, labels, 32, 18), TILE_STAIRS_DN | TOWN_FLAGS, "town stairs tile")

        bench.set_a(CMD_MOVE_E)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, 32, 18, "move east onto stairs")

        set_player_position(bench, labels, 0, 1)
        bench.set_a(CMD_MOVE_W)
        bench.run(require(labels, "cx16_try_move_command"))
        assert_player_position(bench, labels, 0, 1, "blocked west edge move")

        store_x = bench.get_memory(require(labels, "store_door_x"))
        store_y = bench.get_memory(require(labels, "store_door_y"))
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

        bench.set_memory(require(labels, "zp_player_x"), 31)
        bench.set_memory(require(labels, "zp_player_y"), 18)
        bench.run(require(labels, "town_basic_check_stairs_at_player"))
        assert_eq(bench.get_a(), 0, "non-stairs probe")
        bench.run(require(labels, "cx16_try_stairs_up"))

        print("CX16 runtime smoke passed")
    finally:
        bench.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
