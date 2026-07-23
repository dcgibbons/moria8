#!/usr/bin/env python3
"""Apple IIe MAME smoke harness for moria8 (docs/APPLE2_PORT.md, Test Harness).

Drives headless MAME (apple2ee) against build/moria8-apple2.po: generates a
per-scenario Lua script that polls RAM sentinels and prints ASSERT lines,
runs MAME, and parses the results. RAM-contract asserts only, never pixels.

Requires:
  A2ROMS  env var or --rompath: directory containing apple2ee.zip
  build/moria8-apple2.po (make diskapple2)

Scenarios:
  boot_title   ProDOS boot -> title screen: menu string bytes in both text
               halves at row 18, sysinfo row content, aux title-art presence.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PO_IMAGE = ROOT / "build" / "moria8-apple2.po"
MAME_OUTPUT_ROOT = ROOT / "build" / "apple2" / "mame"
MAME_OUTPUT_DIRS = {
    "cfg": MAME_OUTPUT_ROOT / "cfg",
    "nvram": MAME_OUTPUT_ROOT / "nvram",
    "input": MAME_OUTPUT_ROOT / "inp",
    "state": MAME_OUTPUT_ROOT / "sta",
    "snapshot": MAME_OUTPUT_ROOT / "snap",
    "diff": MAME_OUTPUT_ROOT / "diff",
    "comment": MAME_OUTPUT_ROOT / "comments",
    "share": MAME_OUTPUT_ROOT / "share",
}

# Row 18 text-page base: $400 + (18&7)*$80 + (18>>3)*$28 = $550.
# Menu "N)ew  L)oad  D)isk Setup" starts at column 28 (main.s title_draw_menu).
# Even columns live in the aux half, odd columns in the main half; each half
# row holds 40 bytes, so column c maps to half-row offset c>>1.
ROW18_BASE = 0x550
MENU_START_COL = 28

# Expected Apple display codes for "N)ew  L)oad  D)isk Setup".
MENU_EXPECTED = [
    0xCE, 0xA9, 0xE5, 0xF7, 0xA0, 0xA0, 0xCC, 0xA9, 0xEF, 0xE1, 0xE4, 0xA0,
    0xA0, 0xC4, 0xA9, 0xE9, 0xF3, 0xEB, 0xA0, 0xD3, 0xE5, 0xF4, 0xF5, 0xF0,
]

LUA_BOOT_TITLE = r"""
function run()
    local prog = manager.machine.devices[":maincpu"].spaces["program"]
    -- Poll for the menu to appear (the port may go through several
    -- crash-reboot cycles before the title flow completes).
    local ready = false
    for i = 1, WAIT_TENTHS do
        emu.wait(0.1)
        if prog:read_u8(ROW18_BASE + 14) == 0xA9 then
            ready = true
            break
        end
    end
    if not ready then print("DUMP TIMEOUT") end
    local s = "DUMP MAIN "
    for a = ROW18_BASE, ROW18_BASE + 39 do
        s = s .. string.format("%02X", prog:read_u8(a))
    end
    print(s)
    local ram = emu.item(manager.machine.devices[":aux:ext80"].items["0/m_ram"])
    s = "DUMP AUX "
    for a = ROW18_BASE, ROW18_BASE + 39 do
        s = s .. string.format("%02X", ram:read(a))
    end
    print(s)
    s = "DUMP AUXR0 "
    for a = 0x0400, 0x0427 do
        s = s .. string.format("%02X", ram:read(a))
    end
    print(s)
    local nonzero = 0
    for a = 0x0800, 0x0bff do
        if ram:read(a) ~= 0 then nonzero = nonzero + 1 end
    end
    print("DUMP MAP " .. nonzero)
    s = "DUMP MAINR0 "
    for a = 0x0400, 0x0427 do
        s = s .. string.format("%02X", prog:read_u8(a))
    end
    print(s)
    s = "DUMP MAINR23 "
    local base23 = 0x400 + (23 % 8) * 0x80 + math.floor(23 / 8) * 0x28
    for a = base23, base23 + 39 do
        s = s .. string.format("%02X", prog:read_u8(a))
    end
    print(s)
end

co = coroutine.create(run)
coroutine.resume(co)
"""

LUA_PRIEST_PRAY = r"""
local prog = manager.machine.devices[":maincpu"].spaces["program"]
local aux = emu.item(manager.machine.devices[":aux:ext80"].items["0/m_ram"])
local keymap = {}
for tag, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do keymap[name] = field end
end

local function findkey(ch)
    if ch == "\r" then return keymap["Return"] end
    if ch == " " then return keymap["Space"] end
    if ch == "?" then return keymap["/  ?"] end
    if ch == "/" then return keymap["/  ?"] end
    return keymap[string.lower(ch) .. "  " .. string.upper(ch)]
end
local function press(ch)
    local f = findkey(ch)
    if not f then print("NOKEY " .. string.format("%q", ch)) return end
    f:set_value(1) emu.wait(0.03) f:set_value(0) emu.wait(0.12)
end
local function shift(ch)
    local s = keymap["Left Shift"]
    local f = findkey(ch)
    if not f then print("NOKEY " .. string.format("%q", ch)) return end
    s:set_value(1) emu.wait(0.02)
    f:set_value(1) emu.wait(0.03) f:set_value(0) emu.wait(0.02)
    s:set_value(0) emu.wait(0.12)
end

local function rowbase(r) return 0x400 + (r % 8) * 0x80 + math.floor(r / 8) * 0x28 end
local function cell(r, c)
    local base = rowbase(r)
    if c % 2 == 0 then return aux:read(base + math.floor(c / 2)) end
    return prog:read_u8(base + math.floor(c / 2))
end
local function asc(b)
    if b >= 0x80 then b = b - 0x80 end
    if b < 0x20 or b >= 0x7f then return "." end
    return string.char(b)
end
local function rowtext(r)
    local line = ""
    for c = 0, 79 do line = line .. asc(cell(r, c)) end
    return line
end
local function screen_has(txt)
    for r = 0, 23 do
        if string.find(rowtext(r), txt, 1, true) then return true end
    end
    return false
end
local function dump(tag)
    print("SCREEN " .. tag)
    for r = 0, 23 do print(string.format("ROW %02d %s", r, rowtext(r))) end
end
local function press_until(txt, ch, tries)
    for i = 1, (tries or 12) do
        press(ch)
        emu.wait(0.4)
        if screen_has(txt) then return true end
    end
    print("RETRY EXHAUSTED for: " .. txt)
    return false
end
local function in_town()
    for c = 0, 79 do
        if cell(2, c) == 0xA3 and cell(3, c) == 0xA3 then return true end
    end
    return false
end

-- Title -> chargen -> priest -> town (each step retries its key until the
-- next screen appears; transitions eat pending keys via strobe clear).
for i = 1, 300 do
    emu.wait(0.1)
    if prog:read_u8(0x550 + 14) == 0xA9 then break end
end
press_until("Choose your race", "N")
press_until("Roll Statistics", "A")
press_until("Choose your class", "\r")
press_until("Enter your name", "C")
press("T") press("E") press("S") press("T")
press_until("Choose your sex", "\r")
for i = 1, 60 do
    press("A")
    emu.wait(0.3)
    press(" ")
    if in_town() then break end
end
if not in_town() then print("NO TOWN") end
emu.wait(2)

-- Precondition: the priest carries the Beginners Handbook.
press("I")
emu.wait(2)
if screen_has("Beginners Handbook") then print("BOOK PRESENT") else print("BOOK MISSING") end
dump("inventory")
press(" ")
emu.wait(1)

-- Failing scenario: 'p' must offer the prayer-book prompt, not
-- "You have nothing there."
press("P")
emu.wait(3)
if screen_has("Prayer book") then print("PRAY PROMPT SHOWN") else print("PRAY PROMPT ABSENT") end
if screen_has("You have nothing there.") then print("NOTHING THERE SHOWN") end

-- Full activation: select the only book ('a'), open the list with '?',
-- verify names/mana/level render (aux/overlay-safe), then pick prayer 'a'.
press("A")
emu.wait(3)
if screen_has("Pray which?") then print("PRAY LIST SHOWN") else print("PRAY LIST ABSENT") end
shift("/")
emu.wait(3)
if screen_has("Prayer Book") then print("LIST TITLE OK") else print("LIST TITLE MISSING") end
if screen_has("Detect Evil") and screen_has("Bless") then
    print("LIST NAMES OK")
else
    print("LIST NAMES GARBLED")
end
press("A")
emu.wait(3)
if not screen_has("Prayer Book") and not screen_has("Pray which?") then
    print("PRAYER EXECUTED")
else
    print("PRAYER STUCK")
end
dump("after_p")
print("SCENARIO DONE")
"""

SCENARIOS = ("boot_title", "priest_pray")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenario", nargs="?", default="boot_title",
                        choices=SCENARIOS)
    parser.add_argument("--rompath", default=os.environ.get("A2ROMS", ""))
    parser.add_argument("--seconds", type=float, default=20.0)
    parser.add_argument("--mame", default="mame")
    parser.add_argument("--image", type=Path, default=PO_IMAGE)
    args = parser.parse_args()

    if not args.rompath:
        print("error: A2ROMS env var or --rompath required (Apple IIe ROMs "
              "are not redistributable)", file=sys.stderr)
        return 1
    if not args.image.is_file():
        print(f"error: disk image missing: {args.image} (run make diskapple2)",
              file=sys.stderr)
        return 1

    if args.scenario == "priest_pray" and args.seconds == 20.0:
        args.seconds = 240.0

    if args.scenario == "priest_pray":
        lua = LUA_PRIEST_PRAY
    else:
        table = "local MENU_EXPECTED = {%s}\n" % ",".join(
            str(b) for b in MENU_EXPECTED)
        lua = table + (
            LUA_BOOT_TITLE
            .replace("WAIT_TENTHS", str(int(args.seconds * 10)))
            .replace("MENU_START_COL", str(MENU_START_COL))
            .replace("ROW18_BASE", str(ROW18_BASE))
        )

    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
        f.write(lua)
        lua_path = f.name

    for output_dir in MAME_OUTPUT_DIRS.values():
        output_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        args.mame, "apple2ee",
        "-rompath", args.rompath,
        "-cfg_directory", str(MAME_OUTPUT_DIRS["cfg"]),
        "-nvram_directory", str(MAME_OUTPUT_DIRS["nvram"]),
        "-input_directory", str(MAME_OUTPUT_DIRS["input"]),
        "-state_directory", str(MAME_OUTPUT_DIRS["state"]),
        "-snapshot_directory", str(MAME_OUTPUT_DIRS["snapshot"]),
        "-diff_directory", str(MAME_OUTPUT_DIRS["diff"]),
        "-comment_directory", str(MAME_OUTPUT_DIRS["comment"]),
        "-share_directory", str(MAME_OUTPUT_DIRS["share"]),
        "-flop1", str(args.image),
        "-autoboot_script", lua_path,
        "-video", "none",
        "-sound", "none",
        "-nothrottle",
        "-seconds_to_run", str(args.seconds + 5),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True,
                          timeout=max(300, args.seconds + 60))
    out = proc.stdout + proc.stderr

    if args.scenario == "priest_pray":
        failures = 0
        asserts = 0

        def check(name, ok, detail=""):
            nonlocal failures, asserts
            asserts += 1
            if not ok:
                failures += 1
            print(f"ASSERT {name} {'PASS' if ok else 'FAIL ' + detail}")

        if "NOKEY" in out:
            missing = [l for l in out.splitlines() if l.startswith("NOKEY")]
            check("keys_mapped", False, "; ".join(missing[:3]))
        else:
            check("keys_mapped", True)
        check("town_reached", "NO TOWN" not in out and "SCREEN" in out)
        check("book_present", "BOOK PRESENT" in out,
              "Beginners Handbook missing from starting inventory")
        check("pray_prompt", "PRAY PROMPT SHOWN" in out,
              "'p' did not show the prayer-book prompt")
        check("no_nothing_there", "NOTHING THERE SHOWN" not in out,
              "'p' printed \"You have nothing there.\" despite the book")
        check("pray_list", "PRAY LIST SHOWN" in out,
              "book selection did not reach the prayer list")
        check("list_title", "LIST TITLE OK" in out,
              "'?' list overlay did not render")
        check("list_names", "LIST NAMES OK" in out,
              "'?' list shows garbled prayer names/mana/level")
        check("pray_executed", "PRAYER EXECUTED" in out,
              "prayer selection did not consume the turn")
        print(f"RESULT {asserts} asserts {failures} failures")
        return 0 if failures == 0 else 1

    dumps = {}
    map_nonzero = -1
    timed_out = False
    for line in out.splitlines():
        if line.startswith("DUMP MAINR0 "):
            dumps["main_row0"] = bytes.fromhex(line[12:])
        elif line.startswith("DUMP MAINR23 "):
            dumps["main_row23"] = bytes.fromhex(line[13:])
        elif line.startswith("DUMP MAIN "):
            dumps["main"] = bytes.fromhex(line[10:])
        elif line.startswith("DUMP AUXR0 "):
            dumps["aux_row0"] = bytes.fromhex(line[11:])
        elif line.startswith("DUMP AUX "):
            dumps["aux"] = bytes.fromhex(line[9:])
        elif line.startswith("DUMP MAP "):
            map_nonzero = int(line[9:])
        elif line.startswith("DUMP TIMEOUT"):
            timed_out = True

    failures = 0
    asserts = 0

    def check(name, ok, detail=""):
        nonlocal failures, asserts
        asserts += 1
        if not ok:
            failures += 1
        print(f"ASSERT {name} {'PASS' if ok else 'FAIL ' + detail}")

    if "main" not in dumps:
        print("error: harness produced no dumps (MAME/Lua failure)")
        print(out[-2000:])
        return 1

    check("menu_reached", not timed_out, f"no menu after {args.seconds}s")

    # Menu string "N)ew  L)oad  D)isk Setup" starts at column 28; each half
    # row holds 40 bytes at half-row offset col>>1.
    for half_name, parity in (("main", 1), ("aux", 0)):
        if half_name not in dumps:
            check(f"menu_{half_name}_half", False, "dump unavailable")
            continue
        half = dumps[half_name]
        bad = [
            (MENU_START_COL + i, half[(MENU_START_COL + i) >> 1], want)
            for i, want in enumerate(MENU_EXPECTED)
            if (MENU_START_COL + i) % 2 == parity
            and half[(MENU_START_COL + i) >> 1] != want
        ]
        check(f"menu_{half_name}_half", not bad,
              "".join(f" [col{c}: got{g:02X} want{w:02X}]" for c, g, w in bad[:6]))

    if map_nonzero >= 0:
        check("aux_title_art", map_nonzero > 32, f"nonzero={map_nonzero}")

    # Row 0 must be clean in both halves (gates the art-render bug class:
    # garbage rows from main-RAM reads of the aux art source).
    row0_main = dumps.get("main_row0")
    row0_aux = dumps.get("aux_row0")
    if row0_main is not None and row0_aux is not None:
        check("row0_clean",
              all(b == 0xA0 for b in row0_main) and all(b == 0xA0 for b in row0_aux),
              f"main[0:8]={row0_main[:8].hex()} aux[0:8]={row0_aux[:8].hex()}")

    # Sysinfo row (23) must contain the detected machine label, and the
    # ProDOS version when KVERSION is plausible. Screen bytes are Apple
    # display codes: normal video = ASCII | $80.
    def decode(bs):
        return "".join(chr(b - 0x80) if 0xA0 <= b <= 0xFE else "?" for b in bs)

    sysinfo = dumps.get("main_row23")
    if sysinfo is not None:
        text = decode(sysinfo)
        # Main half holds odd screen columns: "APPLE IIe" -> "PL I",
        # "PRODOS" -> "POO", version "." -> "."
        check("sysinfo_label", "PL I" in text, f"row23={text!r}")
        check("sysinfo_prodos", "POO" in text and "." in text, f"row23={text!r}")

    print(f"RESULT {asserts} asserts {failures} failures")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
