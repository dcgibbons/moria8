#!/usr/bin/env python3
"""Commander X16 headless testbench smoke harness for moria8 (docs/CX16_PORT_PLAN.md).

Drives x16emu -testbench -warp against build/cx16/MORIA8.PRG and preloaded bank
payloads. Uses the testbench yield hook in platforms/cx16/input.s
(cx16_testbench_enabled -> jmp $FFFD when KERNAL_GETIN returns 0) to inspect
VERA text VRAM ($1B000) and system/banked RAM, and to inject keystrokes via
igk_char + RUN input_get_key_testbench_resume.
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD_CX16 = ROOT / "build" / "cx16"

MENU_START_COL = 28
MENU_EXPECTED_STR = "N)ew  L)oad  D)isk Setup"


def _load_symbols(sym_path: Path) -> dict[str, int]:
    syms: dict[str, int] = {}
    for raw in sym_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line.startswith(".label ") or "=" not in line:
            continue
        lhs, rhs = line[7:].split("=", 1)
        name = lhs.strip()
        val_str = rhs.split("//", 1)[0].strip().lstrip("$")
        try:
            syms[name] = int(val_str, 16)
        except ValueError:
            pass
    return syms


def vera_code_to_ascii(b: int) -> str:
    """Convert a VERA PET_UPPER_LOWER screen code to printable ASCII."""
    if b == 0x00:
        return "@"
    if 0x01 <= b <= 0x1A:
        return chr(0x60 + b)
    if 0x1B <= b <= 0x1F:
        return chr(0x40 + b)
    if 0x20 <= b <= 0x3F:
        return chr(b)
    if b == 0x40:
        return "-"
    if 0x41 <= b <= 0x5A:
        return chr(b)
    return "."


class X16Bench:
    """Client for x16emu -testbench."""

    def __init__(self, x16emu: Path, rom: Path | None, workdir: Path, syms: dict[str, int]):
        self.x16emu = x16emu
        self.rom = rom
        self.workdir = workdir
        self.syms = syms
        self.proc: subprocess.Popen[str] | None = None
        self._row_cache: dict[int, bytes] = {}
        self.output_lines: list[str] = []
        self.asserts = 0
        self.failures = 0

    def log(self, line: str) -> None:
        self.output_lines.append(line)

    def assert_line(self, name: str, ok: bool, detail: str = "") -> None:
        self.asserts += 1
        if ok:
            self.log(f"ASSERT {name} PASS")
        else:
            self.failures += 1
            suffix = f" {detail}" if detail else ""
            self.log(f"ASSERT {name} FAIL{suffix}")

    def start(self, boot_to_title: bool = True) -> None:
        cmd = [str(self.x16emu), "-testbench", "-warp", "-zeroram"]
        rom_path = self.rom
        if rom_path is None and (self.x16emu.parent / "rom.bin").is_file():
            rom_path = self.x16emu.parent / "rom.bin"
        if rom_path is not None and rom_path.is_file():
            cmd += ["-rom", str(rom_path)]
        cmd += ["-fsroot", str(self.workdir), "-prg", str(self.workdir / "MORIA8.PRG")]
        env = os.environ.copy()
        env["SDL_VIDEODRIVER"] = "dummy"
        env["SDL_AUDIODRIVER"] = "dummy"
        self.proc = subprocess.Popen(
            cmd,
            cwd=str(self.workdir),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=env,
        )
        self._wait_rdy()
        if boot_to_title:
            self.write_u8(self.syms["cx16_testbench_enabled"], 1)
            self.run_addr(self.syms["entry_bootstrap"])

    def close(self) -> None:
        if self.proc is not None:
            try:
                if self.proc.stdin:
                    self.proc.stdin.close()
                self.proc.wait(timeout=3)
            except Exception:
                self.proc.kill()
            self.proc = None

    def _readline(self) -> str:
        assert self.proc is not None and self.proc.stdout is not None
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError("x16emu EOF while waiting for testbench response")
        return line.strip()

    def _wait_rdy(self) -> None:
        while True:
            line = self._readline()
            if line == "RDY":
                return
            if line.startswith("ERR") or line.startswith("INV"):
                raise RuntimeError(f"x16emu testbench error: {line}")

    def _send(self, cmd: str) -> None:
        assert self.proc is not None and self.proc.stdin is not None
        self.proc.stdin.write(cmd + "\n")
        self.proc.stdin.flush()

    def read_u8(self, addr: int) -> int:
        self._send(f"RQM {addr:04X}")
        while True:
            line = self._readline()
            if line in ("RDY", "Testbench mode..."):
                continue
            return int(line, 16)

    def write_u8(self, addr: int, val: int) -> None:
        self._send(f"STM {addr:04X} {val & 0xFF:02X}")
        self._wait_rdy()

    def read_bank_u8(self, bank: int, addr: int) -> int:
        saved = self.read_u8(0x0000)
        self.write_u8(0x0000, bank)
        val = self.read_u8(addr)
        self.write_u8(0x0000, saved)
        return val

    def write_bank_u8(self, bank: int, addr: int, val: int) -> None:
        saved = self.read_u8(0x0000)
        self.write_u8(0x0000, bank)
        self.write_u8(addr, val)
        self.write_u8(0x0000, saved)

    def map_read(self, x: int, y: int) -> int:
        off = y * 198 + x
        bank = 1 if off < 0x2000 else 2
        addr = 0xA000 + (off & 0x1FFF)
        return self.read_bank_u8(bank, addr)

    def map_write(self, x: int, y: int, val: int) -> None:
        off = y * 198 + x
        bank = 1 if off < 0x2000 else 2
        addr = 0xA000 + (off & 0x1FFF)
        self.write_bank_u8(bank, addr, val)

    def run_addr(self, addr: int) -> None:
        self._row_cache.clear()
        self._send(f"RUN {addr:04X}")
        self._wait_rdy()

    def inject_petscii(self, code: int) -> None:
        self.write_u8(self.syms["igk_char"], code & 0xFF)
        self.run_addr(self.syms["input_get_key_testbench_resume"])

    def press(self, ch: str) -> None:
        if ch == "\r":
            code = 0x0D
        elif ch == " ":
            code = 0x20
        elif len(ch) == 1 and ch.isalpha():
            code = ord(ch.upper())
        else:
            code = ord(ch)
        self.inject_petscii(code)

    def shift(self, ch: str) -> None:
        if ch == ".":
            code = 0x3E  # '>'
        elif ch == ",":
            code = 0x3C  # '<'
        elif ch == "/":
            code = 0x3F  # '?'
        elif len(ch) == 1 and ch.isalpha():
            code = ord(ch.upper()) | 0x80
        else:
            code = ord(ch)
        self.inject_petscii(code)

    def ctrl(self, ch: str) -> None:
        code = ord(ch.upper()) - 0x40
        self.inject_petscii(code)

    def row_bytes(self, r: int) -> bytes:
        if r in self._row_cache:
            return self._row_cache[r]
        assert self.proc is not None and self.proc.stdin is not None
        saved_ctrl = self.read_u8(0x9F25)
        self.write_u8(0x9F25, 0x00)
        saved_l = self.read_u8(0x9F20)
        saved_m = self.read_u8(0x9F21)
        saved_h = self.read_u8(0x9F22)

        cmds = [
            "STM 9F22 01",
            f"STM 9F21 {0xB0 + r:02X}",
        ]
        for c in range(80):
            cmds.append(f"STM 9F20 {c * 2:02X}")
            cmds.append("RQM 9F23")
        self.proc.stdin.write("\n".join(cmds) + "\n")
        self.proc.stdin.flush()

        # Expect 2 RDY lines for the initial STM 9F22 / STM 9F21, then 80 pairs of (RDY, hex).
        self._wait_rdy()
        self._wait_rdy()
        out = bytearray(80)
        for c in range(80):
            self._wait_rdy()
            out[c] = int(self._readline(), 16)

        self.write_u8(0x9F20, saved_l)
        self.write_u8(0x9F21, saved_m)
        self.write_u8(0x9F22, saved_h)
        self.write_u8(0x9F25, saved_ctrl)

        res = bytes(out)
        self._row_cache[r] = res
        return res

    def cell(self, r: int, c: int) -> int:
        return self.row_bytes(r)[c]

    def rowtext(self, r: int) -> str:
        return "".join(vera_code_to_ascii(b) for b in self.row_bytes(r))

    def screen_has(self, txt: str) -> bool:
        for r in range(24):
            if txt in self.rowtext(r):
                return True
        return False

    def dump(self, tag: str) -> None:
        self.log(f"SCREEN {tag}")
        for r in range(24):
            self.log(f"ROW {r:02d} {self.rowtext(r)}")

    def press_until(self, txt: str, ch: str, tries: int = 12) -> bool:
        for _ in range(tries):
            self.press(ch)
            if self.screen_has(txt):
                return True
        self.log(f"RETRY EXHAUSTED for: {txt}")
        return False

    def in_town(self) -> bool:
        r2 = self.row_bytes(2)
        r3 = self.row_bytes(3)
        n = sum(1 for c in range(80) if r2[c] == 0x23 and r3[c] == 0x23)
        return n >= 5

    def on_title(self) -> bool:
        return MENU_EXPECTED_STR in self.rowtext(18)

    def drain_more(self, max_presses: int = 8) -> None:
        for _ in range(max_presses):
            if not self.screen_has("-more-"):
                break
            self.press(" ")

    def wizard_menu_open(self, tries: int = 12) -> bool:
        for _ in range(tries):
            if self.screen_has("Q to cancel"):
                return True
            if self.screen_has("-more-"):
                self.press(" ")
                continue
            if self.screen_has("WIZARD?"):
                self.press("Y")
                if self.screen_has("Q to cancel"):
                    return True
            else:
                self.ctrl("W")
                if self.screen_has("WIZARD?"):
                    self.press("Y")
                if self.screen_has("Q to cancel"):
                    return True
        return False

    def chargen(self, class_key: str) -> None:
        self.press_until("Choose your race", "N")
        self.press_until("Roll Statistics", "A")
        self.press_until("Choose your class", "\r")
        self.press_until("Enter your name", class_key)
        for ch in "TEST":
            self.press(ch)
        self.press_until("Choose your sex", "\r")
        self.press("A")
        self.press(" ")
        self.assert_line("town_reached", self.in_town(), "did not reach town after chargen")


def scenario_boot_title(tb: X16Bench) -> None:
    row0 = tb.row_bytes(0)
    row18_txt = tb.rowtext(18)
    row23_txt = tb.rowtext(23)
    tb.assert_line("menu_reached", tb.on_title(), f"row18={row18_txt!r}")
    tb.assert_line(
        "menu_col_28",
        row18_txt[MENU_START_COL : MENU_START_COL + len(MENU_EXPECTED_STR)] == MENU_EXPECTED_STR,
        f"slice={row18_txt[MENU_START_COL:MENU_START_COL + len(MENU_EXPECTED_STR)]!r}",
    )
    tb.assert_line(
        "row0_clean",
        all(b == 0x20 for b in row0),
        f"row0={row0[:16].hex()}",
    )
    # Verify title art rendered on rows 2..15
    art_nonzero = sum(
        1
        for r in range(2, 16)
        for b in tb.row_bytes(r)
        if b != 0x20
    )
    tb.assert_line("title_art_present", art_nonzero > 64, f"nonzero={art_nonzero}")
    tb.assert_line("sysinfo_label", "COMMANDER X16" in row23_txt, f"row23={row23_txt!r}")
    tb.assert_line("sysinfo_ram", "512KB RAM" in row23_txt, f"row23={row23_txt!r}")
    tb.log("SCENARIO DONE")


def scenario_priest_pray(tb: X16Bench) -> None:
    tb.chargen("C")
    tb.press("I")
    tb.assert_line(
        "book_present",
        tb.screen_has("Beginners Handbook"),
        "Beginners Handbook missing from starting inventory",
    )
    tb.dump("inventory")
    tb.press(" ")

    tb.press("P")
    tb.assert_line("pray_prompt", tb.screen_has("Prayer book"), "'p' did not show the prayer-book prompt")
    tb.assert_line(
        "no_nothing_there",
        not tb.screen_has("You have nothing there."),
        "'p' printed 'You have nothing there.' despite the book",
    )
    tb.press("A")
    tb.assert_line("pray_list", tb.screen_has("Pray which?"), "book selection did not reach the prayer list")
    tb.shift("/")
    tb.assert_line("list_title", tb.screen_has("Prayer Book"), "'?' list overlay did not render")
    tb.assert_line(
        "list_names",
        tb.screen_has("Detect Evil") and tb.screen_has("Bless"),
        "'?' list shows garbled prayer names/mana/level",
    )
    tb.press("A")
    tb.drain_more()
    tb.assert_line(
        "pray_executed",
        not tb.screen_has("Prayer Book") and not tb.screen_has("Pray which?"),
        "prayer selection did not consume the turn",
    )
    tb.dump("after_p")
    tb.log("SCENARIO DONE")


def scenario_priest_map_area(tb: X16Bench) -> None:
    tb.chargen("C")
    pd = tb.syms["player_data"]
    inv_id = tb.syms["inv_item_id"]
    inv_qty = tb.syms["inv_qty"]
    tb.write_u8(pd + 19, 33)
    tb.write_u8(0x33, 33)
    tb.write_u8(pd + 37, 50)
    tb.write_u8(0x31, 50)
    tb.write_u8(pd + 63, tb.read_u8(pd + 63) | 0x40)
    gave_book = False
    for i in range(31):
        if tb.read_u8(inv_id + i) == 0xFF:
            tb.write_u8(inv_id + i, 59)
            tb.write_u8(inv_qty + i, 1)
            gave_book = True
            break
    tb.assert_line("book_granted", gave_book, "no empty inventory slot for the book")

    tb.press("P")
    tb.assert_line("pray_prompt", tb.screen_has("Prayer book"), "'p' did not show the prayer-book prompt")
    tb.press("B")
    tb.assert_line("pray_list", tb.screen_has("Pray which?"), "book selection did not reach the prayer list")
    tb.shift("/")
    tb.assert_line("list_names", tb.screen_has("Sense Surroundings"), "'?' list missing Sense Surroundings")
    tb.press("A")
    tb.drain_more()
    tb.assert_line(
        "map_executed",
        not tb.screen_has("Prayer Book") and not tb.screen_has("Pray which?"),
        "prayer selection did not consume the turn",
    )
    mp_after = tb.read_u8(0x31)
    pl_after = tb.read_u8(pd + 37)
    tb.assert_line(
        "map_mana_spent",
        39 <= mp_after <= 41 and 39 <= pl_after <= 41,
        f"mana mirrors not at 50-11 (+-regen): zp={mp_after} save={pl_after}",
    )
    tb.assert_line("map_return", tb.in_town(), "did not return to the town view")
    tb.dump("after_map_area")
    tb.log("SCENARIO DONE")


def scenario_help_overlay(tb: X16Bench) -> None:
    tb.chargen("A")
    tb.shift("/")
    tb.assert_line("help_open", tb.screen_has("Command Reference"), "'?' did not open the help overlay")
    tb.press("Q")
    tb.assert_line("help_close", tb.in_town(), "help did not return to the town view")
    tb.dump("after_help")
    tb.log("SCENARIO DONE")


def scenario_wizard_flow(tb: X16Bench) -> None:
    tb.chargen("A")
    tb.assert_line("wizard_menu", tb.wizard_menu_open(), "wizard menu did not open")
    tb.press_until("ITEM", "G")
    tb.press("4")
    tb.press("8")
    tb.press("\r")
    tb.assert_line("wizard_gain", tb.screen_has("OK"), "item generation did not report OK")
    tb.press("I")
    tb.assert_line("inventory_open", tb.screen_has("Inventory"), "inventory screen did not render")
    tb.assert_line(
        "gain_in_inventory",
        tb.screen_has("Beginners Handbook"),
        "generated item not in inventory",
    )
    tb.press(" ")
    tb.assert_line("wizard_menu2", tb.wizard_menu_open(), "wizard menu did not reopen")
    tb.press("X")
    tb.drain_more()
    tb.assert_line(
        "gain_level_msg",
        tb.screen_has("Welcome to level"),
        "gain level printed garbage instead of the level-up message",
    )
    tb.assert_line("gain_level_lv", tb.screen_has("LV:2"), "status line did not advance to LV:2")
    tb.dump("after_wizard")
    tb.log("SCENARIO DONE")


def scenario_wizard_summon_town(tb: X16Bench) -> None:
    tb.chargen("A")
    mt = tb.syms["monster_table"]
    crd = tb.syms["cr_display"]
    crnh = tb.syms["cr_name_hi"]
    px_addr = tb.syms["zp_player_x"]
    py_addr = tb.syms["zp_player_y"]
    before = {i for i in range(32) if tb.read_u8(mt + i * 12 + 2) != 0xFF}
    tb.assert_line("wizard_menu", tb.wizard_menu_open(), "wizard menu did not open")
    tb.press("S")
    tb.drain_more()
    px = tb.read_u8(px_addr)
    py = tb.read_u8(py_addr)
    found = False
    new_type = 0xFF
    adjacent = False
    for i in range(32):
        ty = tb.read_u8(mt + i * 12 + 2)
        if ty != 0xFF and i not in before:
            found = True
            new_type = ty
            mx = tb.read_u8(mt + i * 12)
            my = tb.read_u8(mt + i * 12 + 1)
            if abs(mx - px) <= 1 and abs(my - py) <= 1:
                adjacent = True
    tb.assert_line("summon_spawned", found, "no new live monster slot after summon")
    tb.assert_line("summon_town_roster", 57 <= new_type <= 64, f"summoned type {new_type} outside town roster")
    tb.assert_line(
        "summon_glyph",
        new_type != 0xFF and tb.read_u8(crd + new_type) != 0,
        "summoned creature has zero glyph (renders '@')",
    )
    tb.assert_line(
        "summon_name",
        new_type != 0xFF and tb.read_u8(crnh + new_type) != 0,
        "summoned creature has null name pointer (shows '?')",
    )
    tb.assert_line("summon_adjacent", adjacent, "summoned monster not adjacent")
    tb.dump("after_summon")
    tb.log("SCENARIO DONE")


def _descend_to_dl1(tb: X16Bench) -> bool:
    dlvl_addr = tb.syms["zp_player_dlvl"]
    for _ in range(10):
        tb.press("L")
        tb.drain_more()
        tb.shift(".")
        tb.drain_more()
        if tb.read_u8(dlvl_addr) == 1:
            return True
    return False


def scenario_balrog_victory(tb: X16Bench) -> None:
    tb.chargen("A")
    descended = _descend_to_dl1(tb)
    tb.assert_line("descended", descended, "zp_player_dlvl never reached 1")
    dlvl_addr = tb.syms["zp_player_dlvl"]
    busy_addr = tb.syms["generation_busy_active_api"]
    settled = tb.read_u8(dlvl_addr) == 1 and tb.read_u8(busy_addr) == 0 and not tb.screen_has("GENERATING")
    tb.assert_line("gen_settled", settled, f"dlvl={tb.read_u8(dlvl_addr)} busy={tb.read_u8(busy_addr)}")

    mt = tb.syms["monster_table"]
    px_addr = tb.syms["zp_player_x"]
    py_addr = tb.syms["zp_player_y"]
    gf_addr = tb.syms["zp_game_flags"]
    pd = tb.syms["player_data"]
    cr_lvl = tb.syms["cr_level"]

    slot = -1
    base = 0
    for i in range(32):
        b = mt + i * 12
        if tb.read_u8(b + 2) != 0xFF:
            slot = i
            base = b
            break
    tb.assert_line("monster_found", slot >= 0, "no live monster on DL:1")

    px0 = tb.read_u8(px_addr)
    py0 = tb.read_u8(py_addr)
    mx, my = px0 + 1, py0
    for cx, cy in ((px0 + 1, py0), (px0 - 1, py0), (px0, py0 + 1), (px0, py0 - 1)):
        if (tb.map_read(cx, cy) & 0xF0) == 0:
            mx, my = cx, cy
            break
    tb.write_u8(base + 0, mx)
    tb.write_u8(base + 1, my)
    tb.map_write(mx, my, tb.map_read(mx, my) | 0x01)
    tb.assert_line("flag_set", (tb.map_read(mx, my) & 0x01) == 1, f"map byte={tb.map_read(mx, my):#x}")

    tb.write_u8(base + 2, 56)
    tb.write_u8(base + 3, 1)
    tb.write_u8(base + 4, 0)
    tb.write_u8(base + 8, 0xFF)
    tb.write_u8(cr_lvl + 56, 100)
    tb.write_u8(pd + 40, 127)
    tb.assert_line("poke_landed", tb.read_u8(base + 2) == 56, f"readback={tb.read_u8(base + 2)}")

    def dirkey(dx: int, dy: int) -> str:
        if dx > 0 and dy > 0:
            return "n"
        if dx > 0 and dy < 0:
            return "u"
        if dx < 0 and dy > 0:
            return "b"
        if dx < 0 and dy < 0:
            return "y"
        if dx > 0:
            return "l"
        if dx < 0:
            return "h"
        if dy > 0:
            return "j"
        return "k"

    def find_balrog() -> int | None:
        for i in range(32):
            b = mt + i * 12
            if tb.read_u8(b + 2) == 56:
                return b
        return None

    def place_adjacent(b: int) -> tuple[int, int] | None:
        px = tb.read_u8(px_addr)
        py = tb.read_u8(py_addr)
        for cx, cy in (
            (px + 1, py),
            (px - 1, py),
            (px, py + 1),
            (px, py - 1),
            (px + 1, py + 1),
            (px - 1, py - 1),
            (px + 1, py - 1),
            (px - 1, py + 1),
        ):
            if (tb.map_read(cx, cy) & 0xF0) == 0:
                ox = tb.read_u8(b + 0)
                oy = tb.read_u8(b + 1)
                tb.map_write(ox, oy, tb.map_read(ox, oy) & 0xFE)
                tb.write_u8(b + 0, cx)
                tb.write_u8(b + 1, cy)
                tb.map_write(cx, cy, tb.map_read(cx, cy) | 0x01)
                return cx, cy
        return None

    dead = False
    for _ in range(24):
        tb.drain_more()
        b = find_balrog()
        if b is None:
            dead = (tb.read_u8(gf_addr) & 0x04) == 0x04
            break
        base = b
        px = tb.read_u8(px_addr)
        py = tb.read_u8(py_addr)
        bx = tb.read_u8(b + 0)
        by = tb.read_u8(b + 1)
        if abs(px - bx) > 1 or abs(py - by) > 1:
            placed = place_adjacent(b)
            if placed is None:
                break
            bx, by = placed
        tb.press(dirkey(bx - px, by - py))
        tb.drain_more()
        if tb.read_u8(b + 2) == 0xFF or (tb.read_u8(gf_addr) & 0x04) == 0x04:
            dead = True
            break

    tb.assert_line("balrog_killed", dead, f"type={tb.read_u8(base + 2)} hp={tb.read_u8(base + 3)}")
    tb.assert_line(
        "winner_flag",
        (tb.read_u8(gf_addr) & 0x04) == 0x04,
        "GAME_FLAG_WINNER not set after Balrog kill",
    )
    tb.drain_more()
    tb.shift("S")
    blocked = tb.screen_has("Winner: Shift+Q") or (
        not tb.screen_has("Select Slot") and tb.screen_has("DL:1")
    )
    tb.assert_line("save_blocked", blocked, "save flow proceeded or game lost")
    tb.dump("after_balrog")
    tb.log("SCENARIO DONE")


def scenario_quaff_p3(tb: X16Bench) -> None:
    tb.chargen("A")
    tb.assert_line("wizard_menu", tb.wizard_menu_open(), "wizard menu did not open")
    tb.press_until("ITEM", "G")
    tb.press("9")
    tb.press("7")
    tb.press("\r")
    tb.assert_line("wizard_gain", tb.screen_has("OK"), "item generation did not report OK")
    tb.press("q")
    tb.assert_line("quaff_prompt", tb.screen_has("Quaff which potion"), "quaff prompt did not open")
    tb.press("a")
    tb.assert_line("quaff_msg", tb.screen_has("strength return"), "quaff effect message missing")
    tb.log("SCENARIO DONE")


def scenario_scroll_objdet(tb: X16Bench) -> None:
    tb.chargen("A")
    tb.assert_line("wizard_menu", tb.wizard_menu_open(), "wizard menu did not open")
    tb.press_until("ITEM", "G")
    tb.press("1")
    tb.press("0")
    tb.press("3")
    tb.press("\r")
    tb.assert_line("wizard_gain", tb.screen_has("OK"), "item generation did not report OK")
    tb.press("r")
    tb.assert_line("read_prompt", tb.screen_has("Read which scroll"), "read prompt did not open")
    tb.press("a")
    tb.assert_line("od_msg", tb.screen_has("sense treasure"), "object detection message missing")
    tb.assert_line("od_not_dead", not tb.screen_has("slain"), "object detection slew the player")
    tb.drain_more()
    tb.assert_line(
        "od_no_stray",
        not tb.screen_has("tasted terrible"),
        "stray poison message after object detection",
    )
    tb.log("SCENARIO DONE")


def scenario_scroll_map(tb: X16Bench) -> None:
    tb.chargen("A")
    tb.assert_line("wizard_menu", tb.wizard_menu_open(), "wizard menu did not open")
    tb.press_until("ITEM", "G")
    tb.press("1")
    tb.press("0")
    tb.press("2")
    tb.press("\r")
    tb.assert_line("wizard_gain", tb.screen_has("OK"), "item generation did not report OK")
    tb.press("r")
    tb.assert_line("read_prompt", tb.screen_has("Read which scroll"), "read prompt did not open")
    tb.press("a")
    tb.assert_line("map_msg", tb.screen_has("map grow clearer"), "magic mapping message missing")
    tb.assert_line("map_not_dead", not tb.screen_has("slain"), "magic mapping slew the player")
    tb.log("SCENARIO DONE")


def scenario_scroll_rune(tb: X16Bench) -> None:
    tb.chargen("A")
    tb.assert_line("wizard_menu", tb.wizard_menu_open(), "wizard menu did not open")
    tb.press_until("ITEM", "G")
    tb.press("1")
    tb.press("0")
    tb.press("5")
    tb.press("\r")
    tb.assert_line("wizard_gain", tb.screen_has("OK"), "item generation did not report OK")
    tb.press("r")
    tb.assert_line("read_prompt", tb.screen_has("Read which scroll"), "read prompt did not open")
    tb.press("a")
    tb.assert_line("no_balrog", not tb.screen_has("Balrog"), "Balrog appeared after rune scroll")
    tb.assert_line("rune_msg", tb.screen_has("strange rune"), "rune effect message missing")
    tb.assert_line(
        "rune_glyph",
        tb.read_u8(tb.syms["glyph_active"]) == 1,
        "rune of protection did not create its glyph",
    )
    tb.dump("after_rune")
    tb.log("SCENARIO DONE")


def scenario_dungeon_descend(tb: X16Bench) -> None:
    tb.chargen("A")
    descended = _descend_to_dl1(tb)
    tb.assert_line("descended", descended, "status does not show DL:1")
    tb.assert_line("dungeon_render", not tb.in_town(), "town map still visible after descent")
    tb.press("L")
    tb.drain_more()
    tb.press("L")
    tb.drain_more()
    tb.assert_line("move_ok", tb.screen_has("DL:1"), "dungeon view lost after movement")
    tb.dump("after_descend")
    tb.log("SCENARIO DONE")


def scenario_deep_objdet(tb: X16Bench) -> None:
    tb.chargen("A")
    _descend_to_dl1(tb)
    tb.wizard_menu_open()
    tb.press_until("DLVL", "L")
    tb.press("1")
    tb.press("0")
    tb.press("\r")
    tb.drain_more()
    tb.wizard_menu_open()
    tb.press("S")
    tb.drain_more()
    tb.wizard_menu_open()
    tb.press_until("ITEM", "G")
    tb.press("1")
    tb.press("0")
    tb.press("3")
    tb.press("\r")
    tb.drain_more()
    tb.press("r")
    tb.press("a")
    od_msg = tb.screen_has("sense treasure")
    for _ in range(8):
        if od_msg:
            break
        if tb.screen_has("-more-"):
            tb.press(" ")
            if tb.screen_has("sense treasure"):
                od_msg = True
                break
    tb.assert_line("od_msg", od_msg, "object detection message missing")
    tb.assert_line("od_not_dead", not tb.screen_has("slain"), "object detection slew the player")
    tb.assert_line("od_no_terrible", not tb.screen_has("tasted terrible"), "stray poison message appeared")
    tb.log("SCENARIO DONE")


def scenario_death_flow(tb: X16Bench) -> None:
    tb.chargen("A")
    _descend_to_dl1(tb)
    tb.assert_line("wizard_menu", tb.wizard_menu_open(), "wizard menu did not open")
    tb.press_until("DLVL", "L")
    tb.press("1")
    tb.press("0")
    tb.press("\r")
    tb.drain_more()
    tb.assert_line("wizard_menu2", tb.wizard_menu_open(), "wizard menu did not reopen")
    tb.press("S")
    tb.drain_more()
    died = False
    for _ in range(120):
        if tb.screen_has("You have died"):
            died = True
            break
        if tb.screen_has("-more-"):
            tb.press(" ")
        else:
            tb.press("5")
    tb.assert_line("died", died, "death screen did not appear")
    tb.dump("after_death")
    tb.press(" ")
    tb.assert_line("death_restart_title", tb.on_title(), "did not return to title after death screen")
    tb.log("SCENARIO DONE")


def scenario_mage_list(tb: X16Bench) -> None:
    tb.chargen("B")
    tb.press("M")
    tb.assert_line(
        "cast_prompt",
        tb.screen_has("Spell book") or tb.screen_has("Cast"),
        "no cast book prompt",
    )
    tb.press("A")
    tb.assert_line("cast_list", tb.screen_has("Cast which?"), "book selection did not reach the cast list")
    tb.shift("/")
    tb.assert_line("list_title", tb.screen_has("Mage Book"), "mage list title missing")
    tb.assert_line("name_mm", tb.screen_has("Magic Missile"), "Magic Missile missing")
    tb.assert_line("name_dm", tb.screen_has("Detect Monsters"), "Detect Monsters missing/garbled")
    tb.assert_line("name_pd", tb.screen_has("Phase Door"), "Phase Door missing")
    tb.assert_line("no_priest_names", not tb.screen_has("Protect"), "priest name leaked into mage list")
    tb.dump("mage_list")
    tb.log("SCENARIO DONE")


def _finish_save_to_title(tb: X16Bench) -> bool:
    for _ in range(20):
        if tb.on_title():
            return True
        if tb.screen_has("Overwrite?"):
            tb.press("Y")
        elif tb.screen_has("-more-") or tb.screen_has("Game saved") or tb.screen_has("Saved"):
            tb.press(" ")
        else:
            tb.press(" ")
    return tb.on_title()


def scenario_save_load(tb: X16Bench) -> None:
    tb.chargen("A")
    tb.shift("S")
    tb.assert_line("save_slot_prompt", tb.screen_has("Select Slot 1-4"), "save slot prompt did not appear")
    tb.press("1")
    title_ok = _finish_save_to_title(tb)
    tb.assert_line("save_completed", title_ok, "save did not complete")
    tb.assert_line("title_after_save", title_ok, "did not return to title after save-and-quit")
    tb.assert_line(
        "host_marker",
        (tb.workdir / "THE.GAME").is_file(),
        "THE.GAME not written to HostFS working directory",
    )
    tb.press("L")
    tb.assert_line("load_slots", tb.screen_has("Save Slots:"), "load did not show the slot list")
    tb.assert_line("slot_has_name", tb.screen_has("test"), "saved character name missing from slot list")
    tb.write_u8(0x6F, 0xC1)
    tb.press("1")
    tb.assert_line("loaded", tb.screen_has("Welcome back to Moria8!"), "load did not resume the saved game")
    tb.assert_line(
        "stats_restored",
        tb.screen_has("test") and tb.screen_has("Human"),
        "status line does not show the restored character",
    )
    tb.assert_line(
        "invuln_cleared",
        tb.read_u8(0x6F) == 0,
        f"eff_invuln_timer not cleared on load: {tb.read_u8(0x6F)}",
    )
    tb.dump("after_load")
    tb.log("SCENARIO DONE")


def scenario_save_slot_tracking(tb: X16Bench) -> None:
    tb.chargen("A")
    tb.shift("S")
    tb.assert_line("st_slot_prompt", tb.screen_has("Select Slot 1-4"), "save slot prompt did not appear")
    tb.press("2")
    title_ok = _finish_save_to_title(tb)
    tb.assert_line("st_saved", title_ok, "save to slot 2 did not complete")
    tb.assert_line(
        "host_marker",
        (tb.workdir / "THE.GAME2").is_file(),
        "THE.GAME2 not written to HostFS working directory",
    )
    tb.press("L")
    tb.assert_line("st_load_slots", tb.screen_has("Save Slots:"), "load did not show the slot list")
    tb.press("2")
    tb.assert_line("st_loaded", tb.screen_has("Welcome back to Moria8!"), "load from slot 2 did not resume")
    tb.drain_more()
    descended = _descend_to_dl1(tb)
    tb.assert_line("st_descended", descended, "did not descend after load")
    tb.shift("S")
    tb.assert_line(
        "st_marker",
        tb.screen_has("Select Slot 1-4") and tb.screen_has("2) *"),
        "loaded slot not marked with '*' in the save menu",
    )
    tb.press("2")
    saved2 = _finish_save_to_title(tb)
    tb.assert_line("st_resaved", saved2, "re-save to slot 2 did not complete")
    tb.dump("after_slot_tracking")
    tb.log("SCENARIO DONE")


def scenario_scroll_delta(tb: X16Bench) -> None:
    tb.chargen("A")
    tb.write_u8(0x1A, 0xDE)
    tb.write_u8(0x1B, 0xAD)
    tb.write_u8(0x1C, 0xBE)
    tb.write_u8(0x1D, 0xEF)
    descended = _descend_to_dl1(tb)
    tb.assert_line("descended", descended, "status does not show DL:1")

    px_addr = tb.syms["zp_player_x"]
    py_addr = tb.syms["zp_player_y"]
    vx_addr = tb.syms["zp_view_x"]
    vy_addr = tb.syms["zp_view_y"]

    def east_mobile() -> bool:
        ok = 0
        for _ in range(4):
            px = tb.read_u8(px_addr)
            tb.press("l")
            if tb.read_u8(px_addr) > px:
                ok += 1
            tb.drain_more()
        return ok >= 3

    for t in range(1, 11):
        tb.write_u8(0x1A, 0xDE)
        tb.write_u8(0x1B, (0xAD + t) & 0xFF)
        tb.write_u8(0x1C, (0xBE + t * 16) & 0xFF)
        tb.write_u8(0x1D, 0xEF)
        tb.wizard_menu_open()
        tb.press("T")
        tb.press("Q")
        tb.drain_more()
        if east_mobile():
            break

    def view_row(r: int) -> str:
        return tb.rowtext(r)[1:79]

    before: dict[int, str] = {}
    vx0 = tb.read_u8(vx_addr)
    scrolled = False
    presses = 0
    while presses < 250 and not scrolled:
        p0 = (tb.read_u8(px_addr) << 8) | tb.read_u8(py_addr)
        advanced = False
        for d in ("l", "u", "n", "k", "j"):
            for r in range(2, 20):
                before[r] = view_row(r)
            tb.press(d)
            presses += 1
            tb.drain_more()
            if tb.read_u8(vx_addr) != vx0:
                scrolled = True
                break
            if ((tb.read_u8(px_addr) << 8) | tb.read_u8(py_addr)) != p0:
                advanced = True
                break
        if not advanced and not scrolled:
            break

    tb.assert_line("scrolled", scrolled, "no horizontal scroll after east-seek walk")
    pvx = tb.read_u8(px_addr) - tb.read_u8(vx_addr)
    limit = max(1, pvx - 7)
    bad = 0
    checked = 0
    for r in range(2, 20):
        a = view_row(r)
        b = before[r]
        for c in range(limit):
            checked += 1
            if a[c] != b[c + 1]:
                bad += 1
    tb.assert_line("delta_shift", bad == 0, f"{bad} shifted cells mismatch of {checked}")

    vy0 = tb.read_u8(vy_addr)
    vscrolled = False
    vdirs = ("k", "j", "k", "k", "j", "k")
    for i in range(60):
        tb.press(vdirs[i % len(vdirs)])
        tb.drain_more()
        if tb.read_u8(vy_addr) != vy0:
            vscrolled = True
            break
    vleak = False
    if vscrolled:
        for r in range(21):
            t = tb.rowtext(r)
            if "MP:" in t or "AU:" in t:
                vleak = True
    tb.assert_line("v_no_status_leak", not vleak, "status text leaked outside status rows after vertical scroll")
    tb.log("SCENARIO DONE")


def scenario_disk_setup(tb: X16Bench) -> None:
    save_dev_addr = tb.syms["save_device"]
    tb.press("D")
    tb.assert_line("ds_menu", tb.screen_has("Disk Setup"), "disk setup menu did not appear")
    tb.assert_line("ds_prog_dev", tb.screen_has("Program Device: #8"), "program device #8 not shown")
    tb.press("2")
    tb.assert_line("ds_dev9", tb.screen_has("Save Device:    #9") and tb.read_u8(save_dev_addr) == 9, "save device #9 not active")
    tb.press("3")
    tb.assert_line("ds_dev10", tb.screen_has("Save Device:    #10") and tb.read_u8(save_dev_addr) == 10, "save device #10 not active")
    tb.press("4")
    tb.assert_line("ds_dev11", tb.screen_has("Save Device:    #11") and tb.read_u8(save_dev_addr) == 11, "save device #11 not active")
    tb.press("1")
    tb.assert_line("ds_dev8", tb.screen_has("Save Device:    #8") and tb.read_u8(save_dev_addr) == 8, "save device #8 not active")
    tb.press("5")
    tb.assert_line("ds_done", tb.on_title(), "did not return to title after setup")
    tb.dump("after_disk_setup")
    tb.log("SCENARIO DONE")


SCENARIO_FUNCS = {
    "boot_title": scenario_boot_title,
    "priest_pray": scenario_priest_pray,
    "priest_map_area": scenario_priest_map_area,
    "help_overlay": scenario_help_overlay,
    "wizard_flow": scenario_wizard_flow,
    "wizard_summon_town": scenario_wizard_summon_town,
    "scroll_rune": scenario_scroll_rune,
    "balrog_victory": scenario_balrog_victory,
    "quaff_p3": scenario_quaff_p3,
    "scroll_objdet": scenario_scroll_objdet,
    "deep_objdet": scenario_deep_objdet,
    "scroll_map": scenario_scroll_map,
    "dungeon_descend": scenario_dungeon_descend,
    "death_flow": scenario_death_flow,
    "save_load": scenario_save_load,
    "mage_list": scenario_mage_list,
    "scroll_delta": scenario_scroll_delta,
    "save_slot_tracking": scenario_save_slot_tracking,
    "disk_setup": scenario_disk_setup,
}

SCENARIOS = tuple(SCENARIO_FUNCS) + ("save_reboot_load",)


def _populate_workdir(workdir: Path) -> None:
    for item in BUILD_CX16.iterdir():
        if item.is_file():
            dst = workdir / item.name
            if not dst.exists():
                shutil.copy2(item, dst)


def _run_save_reboot_load(x16emu: Path, rom: Path | None, workdir: Path, syms: dict[str, int]) -> tuple[list[str], int, int]:
    lines: list[str] = []
    asserts = 0
    failures = 0

    tb_a = X16Bench(x16emu, rom, workdir, syms)
    try:
        tb_a.start()
        tb_a.chargen("A")
        tb_a.shift("S")
        tb_a.assert_line("save_slot_prompt", tb_a.screen_has("Select Slot 1-4"), "save slot prompt did not appear")
        tb_a.press("1")
        title_ok = _finish_save_to_title(tb_a)
        tb_a.assert_line("save_completed", title_ok, "save did not complete")
    finally:
        tb_a.close()
    lines.extend(tb_a.output_lines)
    asserts += tb_a.asserts
    failures += tb_a.failures

    tb_b = X16Bench(x16emu, rom, workdir, syms)
    try:
        tb_b.start()
        tb_b.press("L")
        tb_b.assert_line("load_slots", tb_b.screen_has("Save Slots:"), "load did not show the slot list")
        tb_b.assert_line("slot_has_name", tb_b.screen_has("test"), "saved character name missing from slot list")
        tb_b.press("1")
        tb_b.assert_line("loaded", tb_b.screen_has("Welcome back to Moria8!"), "reboot load did not resume the saved game")
        tb_b.assert_line(
            "stats_restored",
            tb_b.screen_has("test") and tb_b.screen_has("Human"),
            "status line does not show the restored character",
        )
        tb_b.assert_line("host_marker", (workdir / "THE.GAME").is_file(), "THE.GAME missing on disk")
        tb_b.dump("after_reboot_load")
        tb_b.log("SCENARIO DONE")
    finally:
        tb_b.close()
    lines.extend(tb_b.output_lines)
    asserts += tb_b.asserts
    failures += tb_b.failures
    return lines, asserts, failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenario", nargs="?", default="boot_title", choices=SCENARIOS)
    parser.add_argument(
        "--x16emu",
        type=str,
        default=os.environ.get("X16EMU", "x16emu"),
    )
    parser.add_argument(
        "--rom",
        type=str,
        default=os.environ.get("X16ROM", ""),
    )
    args = parser.parse_args()

    x16emu_path = Path(args.x16emu)
    if x16emu_path.is_file():
        x16emu = x16emu_path
    else:
        which = shutil.which(args.x16emu)
        if which:
            x16emu = Path(which)
        else:
            print(f"error: x16emu not found ({args.x16emu})", file=sys.stderr)
            return 1

    rom = Path(args.rom) if args.rom else None

    sym_path = BUILD_CX16 / "main.sym"
    if not sym_path.is_file():
        print(f"error: {sym_path} missing (run make buildcx16)", file=sys.stderr)
        return 1
    syms = _load_symbols(sym_path)

    with tempfile.TemporaryDirectory(prefix=f"moria8_cx16_{args.scenario}_") as tmp:
        workdir = Path(tmp)
        _populate_workdir(workdir)

        def _on_alarm(signum: int, frame: object) -> None:
            raise TimeoutError(f"scenario {args.scenario} timed out (>25s)")

        signal.signal(signal.SIGALRM, _on_alarm)
        signal.alarm(25)
        try:
            if args.scenario == "save_reboot_load":
                lines, asserts, failures = _run_save_reboot_load(x16emu, rom, workdir, syms)
            else:
                tb = X16Bench(x16emu, rom, workdir, syms)
                try:
                    tb.start()
                    SCENARIO_FUNCS[args.scenario](tb)
                finally:
                    tb.close()
                lines = tb.output_lines
                asserts = tb.asserts
                failures = tb.failures
        finally:
            signal.alarm(0)

    for line in lines:
        if line.startswith("ASSERT "):
            print(line)
        elif line.startswith("RETRY EXHAUSTED"):
            failures += 1
            print(f"HARNESS {line}")
    print(f"RESULT {asserts} asserts {failures} failures")
    if "SCENARIO DONE" not in lines:
        print("HARNESS scenario did not print SCENARIO DONE")
        for line in lines[-20:]:
            print(f"HARNESS-OUT {line}")
        return 1
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
