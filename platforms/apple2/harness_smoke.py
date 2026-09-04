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
  disk_setup_two_drive / disk_setup_swap: guided Disk Setup over a blank
               SAVE1 volume (created per run via AppleCommander); swap drives
               the single floppy through Lua image loads.
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
    local bootprog = 0
    for i = 1, WAIT_TENTHS do
        emu.wait(0.1)
        -- Boot progress line (boot.s): "MORIA8" at row 11 offset 4, count
        -- digit at offset 21. Track the highest digit seen.
        if prog:read_u8(0x05A8 + 4) == 0xCD and prog:read_u8(0x05A8 + 5) == 0xCF then
            local d = prog:read_u8(0x05A8 + 21)
            if d > bootprog then bootprog = d end
        end
        if prog:read_u8(ROW18_BASE + 14) == 0xA9 then
            ready = true
            break
        end
    end
    print(string.format("DUMP BOOTPROG %d", bootprog))
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

LUA_HELPERS = r"""
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
    if ch == "." then return keymap[".  >"] end
    if ch == "," then return keymap[",  <"] end
    if string.match(ch, "%d") then
        for name, field in pairs(keymap) do
            if string.sub(name, 1, 1) == ch then return field end
        end
    end
    return keymap[string.lower(ch) .. "  " .. string.upper(ch)]
end
local function press(ch)
    local f = findkey(ch)
    if not f then print("NOKEY " .. string.format("%q", ch)) return end
    f:set_value(1) emu.wait(0.03) f:set_value(0) emu.wait(0.12)
end
-- Longer hold/release for prompts reached right after disk activity: under
-- -nothrottle a 0.03 s hold can vanish inside a single emulated frame while
-- the drive spins, dropping the keypress entirely.
local function press_slow(ch)
    local f = findkey(ch)
    if not f then print("NOKEY " .. string.format("%q", ch)) return end
    f:set_value(1) emu.wait(0.2) f:set_value(0) emu.wait(0.2)
end
local function shift(ch)
    local s = keymap["Left Shift"]
    local f = findkey(ch)
    if not f then print("NOKEY " .. string.format("%q", ch)) return end
    s:set_value(1) emu.wait(0.02)
    f:set_value(1) emu.wait(0.03) f:set_value(0) emu.wait(0.02)
    s:set_value(0) emu.wait(0.12)
end
local function ctrl(ch)
    local c = keymap["Control"]
    local f = findkey(ch)
    if not f then print("NOKEY " .. string.format("%q", ch)) return end
    c:set_value(1) emu.wait(0.02)
    f:set_value(1) emu.wait(0.03) f:set_value(0) emu.wait(0.02)
    c:set_value(0) emu.wait(0.12)
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
local function wait_screen(txt, tries)
    for i = 1, (tries or 40) do
        emu.wait(0.5)
        if screen_has(txt) then return true end
    end
    return false
end
local function in_town()
    -- Town buildings give ~10 columns walled at both rows 2 and 3, while a
    -- dungeon room corner yields at most 2; require a clear majority so a
    -- room corner at the viewport top cannot false-positive as town.
    local n = 0
    for c = 0, 79 do
        if cell(2, c) == 0xA3 and cell(3, c) == 0xA3 then n = n + 1 end
    end
    return n >= 5
end
local function assert_line(name, ok, detail)
    if ok then
        print("ASSERT " .. name .. " PASS")
    else
        print("ASSERT " .. name .. " FAIL " .. (detail or ""))
    end
end

-- Enable wizard mode and open the wizard menu. The message system interposes
-- "-more-" prompts that swallow answers, so clear them between steps.
local function wizard_menu_open(tries)
    -- Patient version: after answering the WIZARD? prompt, wait for the menu
    -- to render before pressing ctrl+W again; a re-press while the menu is
    -- mid-render oscillates the prompt and starves the open.
    for i = 1, (tries or 12) do
        if screen_has("Q to cancel") then return true end
        if screen_has("-more-") then press(" ") emu.wait(0.6) end
        if screen_has("WIZARD?") then
            press("Y")
            for j = 1, 16 do
                emu.wait(0.25)
                if screen_has("Q to cancel") then return true end
            end
        else
            ctrl("W")
            emu.wait(1.2)
        end
    end
    return false
end
"""

LUA_CHARGEN = r"""
-- Title -> chargen -> town. CLASS_KEY substituted by the caller.
for i = 1, 300 do
    emu.wait(0.1)
    if prog:read_u8(0x550 + 14) == 0xA9 then break end
end
press_until("Choose your race", "N")
press_until("Roll Statistics", "A")
press_until("Choose your class", "\r")
press_until("Enter your name", "CLASS_KEY")
press("T") press("E") press("S") press("T")
press_until("Choose your sex", "\r")
for i = 1, 60 do
    press("A")
    emu.wait(0.3)
    press(" ")
    if in_town() then break end
end
assert_line("town_reached", in_town())
emu.wait(2)
"""

LUA_SCROLL_DELTA_BODY = r"""
-- Scroll-delta render path (dungeon_scroll_a2.s): after a 1-tile viewport
-- scroll, every cell outside the local redraw footprint must equal the
-- pre-scroll cell one column to its right (screen shifted left).
-- RNG is pinned post-chargen (zp_rng_0-3): new-game re-seeds from
-- input-loop timing counters, so the dungeon otherwise varies with
-- emulator speed and any rendering-performance change, and the strict
-- delta asserts are dungeon-sensitive. Level generation on is
-- deterministic.
prog:write_u8(0x1a, 0xDE) prog:write_u8(0x1b, 0xAD)
prog:write_u8(0x1c, 0xBE) prog:write_u8(0x1d, 0xEF)
local descended = false
for i = 1, 10 do
    press("l")
    emu.wait(1)
    shift(".")
    emu.wait(2)
    if screen_has("DL:1") then descended = true break end
end
assert_line("descended", descended, "status does not show DL:1")
local function wizard_menu_open(tries)
    -- Patient version: after answering the WIZARD? prompt, wait for the menu
    -- to render before pressing ctrl+W again; a re-press while the menu is
    -- mid-render oscillates the prompt and starves the open.
    for i = 1, (tries or 12) do
        if screen_has("Q to cancel") then return true end
        if screen_has("-more-") then press(" ") emu.wait(0.6) end
        if screen_has("WIZARD?") then
            press("Y")
            for j = 1, 16 do
                emu.wait(0.25)
                if screen_has("Q to cancel") then return true end
            end
        else
            ctrl("W")
            emu.wait(1.2)
        end
    end
    return false
end
-- Wizard teleport can strand the player in a sealed pocket or a corridor
-- trap where the fixed walk pattern never gains east ground; retry the
-- teleport until the landing allows at least 3 east steps out of 4.
local function east_mobile()
    local ok = 0
    for i = 1, 4 do
        local px = prog:read_u8(0x2b)
        press("l")
        emu.wait(0.7)
        if prog:read_u8(0x2b) > px then ok = ok + 1 end
        if screen_has("-more-") then press(" ") end
    end
    return ok >= 3
end
for t = 1, 10 do
    -- Pinned RNG makes every teleport land identically; re-seed per attempt
    -- so retries actually sample different destinations while the dungeon
    -- itself (already generated) stays fixed for the delta asserts.
    prog:write_u8(0x1a, 0xDE) prog:write_u8(0x1b, 0xAD + t)
    prog:write_u8(0x1c, 0xBE + t * 16) prog:write_u8(0x1d, 0xEF)
    wizard_menu_open()
    press("T")
    emu.wait(3)
    press("Q")
    emu.wait(2)
    if east_mobile() then break end
end
local function view_row(r) return string.sub(rowtext(r), 2, 79) end
local before = {}
local vx0 = prog:read_u8(0x60)
-- Greedy east-seek walk: accept the first of E/NE/SE/N/S that moves (no
-- west component, so east ground is never given up). A fixed direction
-- pattern can oscillate forever in a nook; the seek scrolls any open path.
local scrolled = false
local presses = 0
while presses < 250 and not scrolled do
    local p0 = prog:read_u8(0x2b) * 256 + prog:read_u8(0x2c)
    local advanced = false
    for _, d in ipairs({"l","u","n","k","j"}) do
        for r = 2, 19 do before[r] = view_row(r) end
        press(d)
        emu.wait(0.7)
        presses = presses + 1
        if screen_has("-more-") then press(" ") emu.wait(0.3) end
        if prog:read_u8(0x60) ~= vx0 then scrolled = true break end
        if prog:read_u8(0x2b) * 256 + prog:read_u8(0x2c) ~= p0 then
            advanced = true
            break
        end
    end
    if not advanced and not scrolled then break end
end
assert_line("scrolled", scrolled, "no horizontal scroll after east-seek walk")
local pvx = prog:read_u8(0x2b) - prog:read_u8(0x60)
local limit = math.max(1, pvx - 7)
local bad, checked = 0, 0
for r = 2, 19 do
    local a = view_row(r)
    for c = 1, limit do
        checked = checked + 1
        if string.sub(a, c, c) ~= string.sub(before[r], c+1, c+1) then
            bad = bad + 1
        end
    end
end
assert_line("delta_shift", bad == 0,
            bad .. " shifted cells mismatch of " .. checked)

-- V-scroll regression: a row copy that exceeds the 40-byte half-row
-- overflows into neighbouring (message/status) rows. After a vertical
-- scroll, no status text may leak outside the status rows.
local vy0 = prog:read_u8(0x61)
local vscrolled = false
local vdirs = {"k","j","k","k","j","k"}
for i = 1, 60 do
    press(vdirs[(i % #vdirs) + 1])
    emu.wait(0.7)
    if prog:read_u8(0x61) ~= vy0 then vscrolled = true break end
    if screen_has("-more-") then press(" ") end
end
local vleak = false
if vscrolled then
    for r = 0, 20 do
        local t = rowtext(r)
        if string.find(t, "MP:", 1, true) or string.find(t, "AU:", 1, true) then
            vleak = true
        end
    end
end
assert_line("v_no_status_leak", not vleak,
            "status text leaked outside status rows after vertical scroll")
print("SCENARIO DONE")
"""

LUA_PRIEST_PRAY_BODY = r"""
-- Precondition: the priest carries the Beginners Handbook.
press("I")
emu.wait(2)
assert_line("book_present", screen_has("Beginners Handbook"),
            "Beginners Handbook missing from starting inventory")
dump("inventory")
press(" ")
emu.wait(1)

-- Regression: 'p' must offer the prayer-book prompt, not
-- "You have nothing there."
press("P")
emu.wait(3)
assert_line("pray_prompt", screen_has("Prayer book"),
            "'p' did not show the prayer-book prompt")
assert_line("no_nothing_there", not screen_has("You have nothing there."),
            "'p' printed \"You have nothing there.\" despite the book")

-- Full activation: select the only book ('a'), open the list with '?',
-- verify names/mana/level render (aux/overlay-safe), then pick prayer 'a'.
press("A")
emu.wait(3)
assert_line("pray_list", screen_has("Pray which?"),
            "book selection did not reach the prayer list")
shift("/")
emu.wait(3)
assert_line("list_title", screen_has("Prayer Book"),
            "'?' list overlay did not render")
assert_line("list_names", screen_has("Detect Evil") and screen_has("Bless"),
            "'?' list shows garbled prayer names/mana/level")
press("A")
emu.wait(3)
assert_line("pray_executed",
            not screen_has("Prayer Book") and not screen_has("Pray which?"),
            "prayer selection did not consume the turn")
dump("after_p")
print("SCENARIO DONE")
"""

LUA_MAP_AREA_BODY = r"""
-- Relocated-engine proof: Sense Surroundings (priest 22, Chants and
-- Blessings) must cast through tramp_eff_map_area (resident) ->
-- OVL_DEATH swap -> eff_map_area -> OVL.SPELL restore.
-- Poke the priest into a castable state (level 33 beats the 45% fail
-- chance; mana 50 covers the 11 cost; learnt mask bit 22; the book).
local pd = PLAYER_DATA_ADDR
prog:write_u8(pd + 19, 33)              -- PL_LEVEL
prog:write_u8(0x33, 33)                 -- zp_player_lvl mirror
prog:write_u8(pd + 37, 50)              -- PL_MANA (save copy)
prog:write_u8(0x31, 50)                 -- zp_player_mp (live mana)
prog:write_u8(pd + 63, prog:read_u8(pd + 63) | 0x40)  -- learnt bit 22
local gave_book = false
for i = 0, 30 do
    if prog:read_u8(INV_ITEM_ID_ADDR + i) == 0xff then
        prog:write_u8(INV_ITEM_ID_ADDR + i, 59)   -- Chants and Blessings
        prog:write_u8(INV_QTY_ADDR + i, 1)
        gave_book = true
        break
    end
end
assert_line("book_granted", gave_book, "no empty inventory slot for the book")

press("P")
emu.wait(3)
assert_line("pray_prompt", screen_has("Prayer book"),
            "'p' did not show the prayer-book prompt")
press("B")
emu.wait(3)
assert_line("pray_list", screen_has("Pray which?"),
            "book selection did not reach the prayer list")
shift("/")
emu.wait(3)
assert_line("list_names", screen_has("Sense Surroundings"),
            "'?' list missing Sense Surroundings")
press("A")
emu.wait(4)
if screen_has("-more-") then press(" ") emu.wait(1) end
assert_line("map_executed",
            not screen_has("Prayer Book") and not screen_has("Pray which?"),
            "prayer selection did not consume the turn")
-- Real-cast proof: pm_consume_mana wrote 50-11=39 to both mana mirrors
-- (the insufficient-mana faint path would have zeroed them; no cast would
-- leave 50). Regen may tick a point or two back by read time.
local mp_after = prog:read_u8(0x31)
local pl_after = prog:read_u8(pd + 37)
assert_line("map_mana_spent",
            mp_after >= 39 and mp_after <= 41 and pl_after >= 39 and pl_after <= 41,
            "mana mirrors not at 50-11 (+-regen): zp=" .. mp_after ..
            " save=" .. pl_after .. " (0 = faint path, 50 = no cast)")
assert_line("map_return", in_town(), "did not return to the town view")
dump("after_map_area")
print("SCENARIO DONE")
"""

LUA_HELP_BODY = r"""
-- Help overlay: '?' from the command loop must render the command reference
-- and return to the town view on 'q'.
shift("/")
emu.wait(3)
assert_line("help_open", screen_has("Command Reference"),
            "'?' did not open the help overlay")
press("Q")
emu.wait(2)
assert_line("help_close", in_town(), "help did not return to the town view")
dump("after_help")
print("SCENARIO DONE")
"""

LUA_WIZARD_BODY = r"""
-- Wizard mode: enable, open the menu, generate item 48, see it carried.
assert_line("wizard_menu", wizard_menu_open(), "wizard menu did not open")
press_until("ITEM", "G")
press("4") press("8") press("\r")
emu.wait(2)
assert_line("wizard_gain", screen_has("OK"), "item generation did not report OK")
press("I")
-- First inventory open cold-loads OVL.HELP from floppy; poll for the
-- rendered content instead of asserting on a fixed timer.
local inv_up = false
for i = 1, 200 do
    emu.wait(0.1)
    if screen_has("Inventory") then inv_up = true break end
end
assert_line("inventory_open", inv_up, "inventory screen did not render")
local book_seen = false
for i = 1, 200 do
    emu.wait(0.1)
    if screen_has("Beginners Handbook") then book_seen = true break end
end
assert_line("gain_in_inventory", book_seen,
            "generated item not in inventory")
press(" ")
emu.wait(1)
-- Regression: gain level loads OVL.SPELL for mana/spell learning while the
-- wizard continuation lives in OVL.MODAL; the trampoline must restore
-- OVL.MODAL or the message line prints overlay bytes.
assert_line("wizard_menu2", wizard_menu_open(), "wizard menu did not reopen")
press("X")
emu.wait(2)
if screen_has("-more-") then press(" ") emu.wait(1) end
assert_line("gain_level_msg", screen_has("Welcome to level"),
            "gain level printed garbage instead of the level-up message")
assert_line("gain_level_lv", screen_has("LV:2"),
            "status line did not advance to LV:2")
dump("after_wizard")
print("SCENARIO DONE")
"""






LUA_BALROG_BODY = r"""
-- Descend to DL:1 first, verified against zp_player_dlvl (the status line
-- can show DL:1 transiently before generation finishes).
local descended = false
for i = 1, 12 do
    press("L")
    emu.wait(1)
    shift(".")
    emu.wait(2)
    if prog:read_u8(DLVL_ADDR) == 1 then descended = true break end
end
assert_line("descended", descended, "zp_player_dlvl never reached 1")
-- dlvl flips before generation finishes; the dungeon monster spawn happens
-- at the END and rewrites the table. Wait for the busy flag to clear AND the
-- "GENERATING..." screen to disappear: the busy flag can deassert before the
-- final spawn phase, and poking mid-generation gets wiped by the table
-- rewrite.
local settled = false
for i = 1, 120 do
    emu.wait(0.5)
    if prog:read_u8(DLVL_ADDR) == 1 and prog:read_u8(BUSY_ADDR) == 0
       and not screen_has("GENERATING") then
        settled = true break
    end
end
emu.wait(1)
assert_line("gen_settled", settled,
            "dlvl=" .. prog:read_u8(DLVL_ADDR) ..
            " busy=" .. prog:read_u8(BUSY_ADDR))

-- Balrog victory flow (deterministic, no wizard): take the first live
-- monster slot, relocate it to an adjacent floor tile (aux map occupied flag
-- set via the aux RAM item handle), rewrite it as a 1-HP stunned Balrog,
-- bump-attack until dead, then verify the winner flag and that save is
-- blocked with the retirement notice.
local mt = MONSTER_TABLE_ADDR

-- Force main-RAM banking before pokes: modal/overlay returns can leave
-- RAMRD/RAMWRT pointing at aux ($C003/$C005 select aux; $C002/$C004 main).
prog:write_u8(0xc002, 0)
prog:write_u8(0xc004, 0)

local slot = -1
local base = 0
for i = 0, 31 do
    local b = mt + i * 12
    if prog:read_u8(b + 2) ~= 0xff then slot = i base = b break end
end
assert_line("monster_found", slot >= 0, "no live monster on DL:1")

-- Relocate to an adjacent floor tile (A2 map stride is 198 columns).
local px0 = prog:read_u8(PLAYER_X_ADDR)
local py0 = prog:read_u8(PLAYER_Y_ADDR)
local mx, my = px0 + 1, py0
local cand = {{px0+1, py0}, {px0-1, py0}, {px0, py0+1}, {px0, py0-1}}
for _, c in ipairs(cand) do
    local a = 0x0800 + c[2]*198 + c[1]
    if aux:read(a) & 0xf0 == 0 then mx, my = c[1], c[2] break end
end
prog:write_u8(base + 0, mx)
prog:write_u8(base + 1, my)
local ma = 0x0800 + my*198 + mx
aux:write(ma, aux:read(ma) | 0x01)
assert_line("flag_set", aux:read(ma) & 0x01 == 1, "aux byte=" .. aux:read(ma))

prog:write_u8(base + 2, 56)       -- MX_TYPE = Balrog (CREATURE_BALROG)
prog:write_u8(base + 3, 1)        -- MX_HP_LO
prog:write_u8(base + 4, 0)        -- MX_HP_HI
prog:write_u8(base + 8, 0xff)     -- MX_STUN: never acts
prog:write_u8(CR_LEVEL_ADDR + 56, 100) -- cr_level[Balrog] = 100 (win guard)
-- A level-1 warrior cannot hit a Balrog's AC; boost to-hit only (a level
-- poke desyncs the level-up thresholds against the Balrog XP award).
prog:write_u8(PLAYER_DATA_ADDR + 40, 127)  -- PL_TOHIT
assert_line("poke_landed", prog:read_u8(base + 2) == 56,
            "immediate readback=" .. prog:read_u8(base + 2) ..
            " hp=" .. prog:read_u8(base + 3) ..
            " stun=" .. prog:read_u8(base + 8))

-- Bump-attack the Balrog until dead. Layout-robust: re-locate the Balrog's
-- slot each try (coords go stale after trap teleports and spawn recycling),
-- re-relocate it adjacent whenever the player is not adjacent (teleport
-- traps can dislocate the player far away), and dismiss message prompts.
local dirkey = function(dx, dy)
    if dx > 0 and dy > 0 then return "n" end
    if dx > 0 and dy < 0 then return "u" end
    if dx < 0 and dy > 0 then return "b" end
    if dx < 0 and dy < 0 then return "y" end
    if dx > 0 then return "l" end
    if dx < 0 then return "h" end
    if dy > 0 then return "j" end
    return "k"
end
local find_balrog = function()
    for i = 0, 31 do
        local b = mt + i * 12
        if prog:read_u8(b + 2) == 56 then return b end
    end
    return nil
end
local place_adjacent = function(b)
    local px = prog:read_u8(PLAYER_X_ADDR)
    local py = prog:read_u8(PLAYER_Y_ADDR)
    local cand = {{px+1, py}, {px-1, py}, {px, py+1}, {px, py-1},
                  {px+1, py+1}, {px-1, py-1}, {px+1, py-1}, {px-1, py+1}}
    for _, c in ipairs(cand) do
        local a = 0x0800 + c[2]*198 + c[1]
        if aux:read(a) & 0xf0 == 0 then
            local oa = 0x0800 + prog:read_u8(b + 1)*198 + prog:read_u8(b + 0)
            aux:write(oa, aux:read(oa) & 0xfe)
            prog:write_u8(b + 0, c[1])
            prog:write_u8(b + 1, c[2])
            aux:write(a, aux:read(a) | 0x01)
            return c[1], c[2]
        end
    end
    return nil
end
local dead = false
for tries = 1, 24 do
    if screen_has("-more-") then press(" ") emu.wait(0.4) end
    local b = find_balrog()
    if not b then
        -- Slot emptied or recycled; the winner flag is authoritative.
        dead = prog:read_u8(GAME_FLAGS_ADDR) & 0x04 == 0x04
        break
    end
    base = b
    local px = prog:read_u8(PLAYER_X_ADDR)
    local py = prog:read_u8(PLAYER_Y_ADDR)
    local bx = prog:read_u8(b + 0)
    local by = prog:read_u8(b + 1)
    if math.abs(px - bx) > 1 or math.abs(py - by) > 1 then
        local nx, ny = place_adjacent(b)
        if not nx then break end
        mx, my = nx, ny
        bx, by = nx, ny
    else
        mx, my = bx, by
    end
    press(dirkey(bx - px, by - py))
    emu.wait(0.8)
    if screen_has("-more-") then press(" ") emu.wait(0.4) end
    if prog:read_u8(b + 2) == 0xff then dead = true break end
end
local slotdump = "slots:"
for i = 0, 7 do
    local b = mt + i * 12
    local t = prog:read_u8(b + 2)
    if t ~= 0xff then
        slotdump = slotdump .. " [" .. i .. "]t" .. t ..
               "@" .. prog:read_u8(b) .. "," .. prog:read_u8(b + 1) ..
               "hp" .. prog:read_u8(b + 3)
    end
end
assert_line("balrog_killed", dead,
            slotdump .. " type=" .. prog:read_u8(base + 2) ..
            " hp=" .. prog:read_u8(base + 3) ..
            " px=" .. prog:read_u8(PLAYER_X_ADDR) ..
            " py=" .. prog:read_u8(PLAYER_Y_ADDR) ..
            " mx=" .. mx .. " my=" .. my ..
            " tile=" .. aux:read(ma) ..
            " dlvl=" .. prog:read_u8(DLVL_ADDR))
assert_line("winner_flag", prog:read_u8(GAME_FLAGS_ADDR) & 0x04 == 0x04,
            "GAME_FLAG_WINNER not set after Balrog kill")

-- Post-kill message prompts: the -more- marker is not always visible on A2,
-- so press space slowly a few times to drain pending dismissals.
for i = 1, 4 do
    press_slow(" ")
    emu.wait(1)
end

-- Save must be blocked with the retirement notice. Use the proven
-- Left-Shift + S field pattern from the save scenarios. The A2
-- return-to-gameplay redraw erases the message row quickly, so the block is
-- proven by the save flow never proceeding: no slot picker, game alive.
local sft = keymap["Left Shift"]
local skey = findkey("S")
local blocked = false
for attempt = 1, 5 do
    if screen_has("-more-") then press(" ") emu.wait(0.5) end
    sft:set_value(1) emu.wait(0.02)
    skey:set_value(1) emu.wait(0.03) skey:set_value(0) emu.wait(0.02)
    sft:set_value(0) emu.wait(0.12)
    local picker = false
    for i = 1, 15 do
        emu.wait(0.2)
        if screen_has("Winner: Shift+Q") then blocked = true break end
        if screen_has("Select Slot") then picker = true break end
        if screen_has("Disk Setup") then picker = true break end
    end
    if blocked or picker then break end
    press(" ")
    emu.wait(0.5)
end
if not blocked then
    blocked = not picker and screen_has("DL:1")
end
assert_line("save_blocked", blocked, "save flow proceeded or game lost")
dump("after_balrog")
print("SCENARIO DONE")
"""


LUA_QUAFF_P3_BODY = r"""
-- Wizard-generate a Phase 3 potion (Restoration, 97), quaff it, and verify
-- the effect message prints. Regression for the Apple IIe Phase 3 potion
-- overlay swap (resident trampoline into OVL.SPELL).
assert_line("wizard_menu", wizard_menu_open(), "wizard menu did not open")
press_until("ITEM", "G")
press("9") press("7") press("\r")
emu.wait(2)
assert_line("wizard_gain", screen_has("OK"), "item generation did not report OK")
press(" ")
emu.wait(1)
press("q")
emu.wait(1)
assert_line("quaff_prompt", screen_has("Quaff which potion"), "quaff prompt did not open")
press("a")
local quaff_msg = false
for i = 1, 100 do
    emu.wait(0.1)
    if screen_has("strength return") then quaff_msg = true break end
end
assert_line("quaff_msg", quaff_msg, "quaff effect message missing")
print("SCENARIO DONE")
"""



LUA_SCROLL_OBJDET_BODY = r"""
-- Wizard-generate a Scroll of Object Detection (103), read it, and verify
-- the effect runs and reports (no poison/death misdispatch). Regression for
-- the Apple IIe new-owner Phase 3 scroll handlers calling OVL.SPELL helpers
-- from OVL.DEATH (wild jump into uninitialized window memory).
assert_line("wizard_menu", wizard_menu_open(), "wizard menu did not open")
press_until("ITEM", "G")
press("1") press("0") press("3") press("\r")
emu.wait(2)
assert_line("wizard_gain", screen_has("OK"), "item generation did not report OK")
press(" ")
emu.wait(1)
press("r")
emu.wait(1)
assert_line("read_prompt", screen_has("Read which scroll"), "read prompt did not open")
press("a")
local od_msg = false
for i = 1, 100 do
    emu.wait(0.1)
    if screen_has("sense treasure") then od_msg = true break end
end
assert_line("od_msg", od_msg, "object detection message missing")
assert_line("od_not_dead", not screen_has("slain"), "object detection slew the player")
if screen_has("-more-") then press(" ") emu.wait(1) end
assert_line("od_no_stray", not screen_has("tasted terrible"), "stray poison message after object detection")
print("SCENARIO DONE")
"""

LUA_SCROLL_MAP_BODY = r"""
-- Wizard-generate a Scroll of Magic Mapping (102), read it, and verify the
-- effect runs and reports. Companion to scroll_objdet (spell-overlay helper).
assert_line("wizard_menu", wizard_menu_open(), "wizard menu did not open")
press_until("ITEM", "G")
press("1") press("0") press("2") press("\r")
emu.wait(2)
assert_line("wizard_gain", screen_has("OK"), "item generation did not report OK")
press(" ")
emu.wait(1)
press("r")
emu.wait(1)
assert_line("read_prompt", screen_has("Read which scroll"), "read prompt did not open")
press("a")
local map_msg = false
for i = 1, 100 do
    emu.wait(0.1)
    if screen_has("map grow clearer") then map_msg = true break end
end
assert_line("map_msg", map_msg, "magic mapping message missing")
assert_line("map_not_dead", not screen_has("slain"), "magic mapping slew the player")
print("SCENARIO DONE")
"""

LUA_SCROLL_RUNE_BODY = r"""
-- Wizard-generate a Scroll of Rune of Protection (105), read it, and verify
-- the effect runs: the glyph is created and its message prints. Regression
-- for the Apple IIe Phase 3 scroll overlay swaps (resident router/trampoline).
assert_line("wizard_menu", wizard_menu_open(), "wizard menu did not open")
press_until("ITEM", "G")
press("1") press("0") press("5") press("\r")
emu.wait(2)
assert_line("wizard_gain", screen_has("OK"), "item generation did not report OK")
press(" ")
emu.wait(1)
press("r")
emu.wait(1)
assert_line("read_prompt", screen_has("Read which scroll"), "read prompt did not open")
press("a")
emu.wait(3)
assert_line("no_balrog", not screen_has("Balrog"), "Balrog appeared after rune scroll")
assert_line("rune_msg", screen_has("strange rune"), "rune effect message missing")
assert_line("rune_glyph", prog:read_u8(GLYPHADDR) == 1,
            "rune of protection did not create its glyph")
dump("after_rune")
print("SCENARIO DONE")
"""

LUA_DUNGEON_BODY = r"""
-- The player spawns left of the town stairs (classic Moria): step east onto
-- them, then descend. Retries the step+descend pair because transitions eat
-- pending keys. Dungeon level 1 must render and accept movement.
local descended = false
for i = 1, 10 do
    press("L")
    emu.wait(1)
    shift(".")
    emu.wait(2)
    if screen_has("DL:1") then descended = true break end
end
assert_line("descended", descended, "status does not show DL:1")
assert_line("dungeon_render", not in_town(), "town map still visible after descent")
press("L") emu.wait(1)
press("L") emu.wait(1)
assert_line("move_ok", screen_has("DL:1"), "dungeon view lost after movement")
dump("after_descend")
print("SCENARIO DONE")
"""



LUA_DEEP_OBJDET_BODY = r"""
-- Descend, wizard-jump deep, summon a monster, read object detection, and
-- capture the message sequence (repro for the stray poison message).
for i = 1, 10 do
    press("L")
    emu.wait(1)
    shift(".")
    emu.wait(2)
    if screen_has("DL:1") then break end
end
wizard_menu_open()
press_until("DLVL", "L")
press("1") press("0") press("\r")
emu.wait(5)
wizard_menu_open()
press("S")
emu.wait(2)
wizard_menu_open()
press_until("ITEM", "G")
press("1") press("0") press("3") press("\r")
emu.wait(2)
press(" ")
emu.wait(1)
press("r")
emu.wait(1)
press("a")
local od_msg = false
for i = 1, 100 do
    if screen_has("-more-") then press(" ") end
    emu.wait(0.1)
    if screen_has("sense treasure") then od_msg = true break end
end
assert_line("od_msg", od_msg, "object detection message missing")
assert_line("od_not_dead", not screen_has("slain"), "object detection slew the player")
assert_line("od_no_terrible", not screen_has("tasted terrible"), "stray poison message appeared")
print("SCENARIO DONE")
"""

LUA_DEATH_BODY = r"""
-- Death flow: step onto the stairs, descend, wizard-jump deep, summon a
-- monster, rest until dead.
for i = 1, 10 do
    press("L")
    emu.wait(1)
    shift(".")
    emu.wait(2)
    if screen_has("DL:1") then break end
end
if not wizard_menu_open() then print("ASSERT died FAIL wizard menu did not open") end
press_until("DLVL", "L")
press("1") press("0") press("\r")
-- A2 generation of a DL:10 level takes ~30 s; a fixed wait returns while the
-- machine is still generating and the wizard reopen then fails. Wait for the
-- banner to actually clear before summoning.
for i = 1, 120 do
    emu.wait(0.5)
    if not screen_has("GENERATING") then break end
end
-- 'S' summons an adjacent monster on the current (deep) level.
if not wizard_menu_open() then print("ASSERT died FAIL wizard menu did not reopen") end
press("S")
emu.wait(2)
local died = false
-- disk_mode/disk_setup_done (main.vs) drive the state machine: the setup
-- menu stays on screen during prepare's slow disk work, so pixels alone
-- cannot distinguish "awaiting input" from "busy". The first death in a
-- session passes through Disk Setup before the score IO: open the pick
-- screen, choose /SAVE1 (drive 2), Done. Once setup commits, press space
-- each pass: the post-setup score flow has message prompts whose -more-
-- marker is not always visible, and the check-first ordering still catches
-- the death screen before any key can dismiss it.
local DISK_MODE = 0x0a05
local DISK_DONE = 0x0a06
for i = 1, 120 do
    if screen_has("You have died") then died = true break end
    if screen_has("R) Rescan") then
        press_slow("2")
    elseif screen_has("Initialize this disk?") then
        press_slow("Y")
    elseif prog:read_u8(DISK_DONE) ~= 0 then
        press(" ")
    elseif screen_has("Pick save drive") and prog:read_u8(DISK_MODE) == 0 then
        if screen_has("/SAVE1") then press_slow("3") else press_slow("2") end
    elseif prog:read_u8(DISK_MODE) == 0 then
        press("5")
    end
    emu.wait(1)
end
assert_line("died", died, "death screen did not appear")
dump("after_death")
print("SCENARIO DONE")
"""


LUA_MAGE_LIST_BODY = r"""
-- Mage spell list: 'm', the only book, '?' list — names must be the mage
-- catalog's (regression: token-aliased name read from the wrong bank).
press("M")
emu.wait(3)
assert_line("cast_prompt", screen_has("Spell book") or screen_has("Cast"),
            "no cast book prompt")
press("A")
emu.wait(3)
assert_line("cast_list", screen_has("Cast which?"),
            "book selection did not reach the cast list")
shift("/")
emu.wait(3)
assert_line("list_title", screen_has("Mage Book"),
            "mage list title missing")
assert_line("name_mm", screen_has("Magic Missile"), "Magic Missile missing")
assert_line("name_dm", screen_has("Detect Monsters"),
            "Detect Monsters missing/garbled")
assert_line("name_pd", screen_has("Phase Door"), "Phase Door missing")
assert_line("no_priest_names", not screen_has("Protect"),
            "priest name leaked into mage list")
dump("mage_list")
print("SCENARIO DONE")
"""

LUA_SAVE_LOAD_BODY = r"""
-- Save-and-quit then reload: the full storage roundtrip through the slot UI.
-- The first save in a session passes through Disk Setup (menu -> game disk ->
-- possible marker init) before the slot prompt appears.
local s = keymap["Left Shift"]
local f = findkey("S")
s:set_value(1) emu.wait(0.02)
f:set_value(1) emu.wait(0.03) f:set_value(0) emu.wait(0.02)
s:set_value(0)
local prompt_ok = false
-- Strict parity: saves go to a separate disk (SAVE1 in drive 2). Drive the
-- setup once: open the pick screen, choose /SAVE1, Done, init the marker.
-- disk_mode (main.vs $0a05) gates menu answers while prepare is busy.
local DISK_MODE = 0x0a05
for i = 1, 90 do
    emu.wait(0.5)
    if screen_has("R) Rescan") then
        press_slow("2")
    elseif screen_has("Initialize this disk?") then
        press_slow("Y")
    elseif screen_has("Select Slot 1-4") then
        prompt_ok = true
        break
    elseif screen_has("Pick save drive") and prog:read_u8(DISK_MODE) == 0 then
        if screen_has("/SAVE1") then press_slow("3") else press_slow("2") end
    end
end
assert_line("save_slot_prompt", prompt_ok, "save slot prompt did not appear")
press("1")
local started = false
for i = 1, 12 do
    emu.wait(0.5)
    if screen_has("Saving game") then started = true break end
    if screen_has("Overwrite?") then press("Y") end
end
assert_line("saving_msg", started, "save did not start")
local title_ok = false
for i = 1, 90 do
    emu.wait(0.5)
    if screen_has("Overwrite?") then press("Y") end
    if screen_has("-more-") then press(" ") end
    if prog:read_u8(0x550 + 14) == 0xA9 then title_ok = true break end
end
assert_line("save_completed", title_ok, "save did not complete")
assert_line("title_after_save", title_ok,
            "did not return to title after save-and-quit")
press("L")
local slots_ok = false
for i = 1, 20 do
    emu.wait(0.5)
    if screen_has("Save Slots:") then slots_ok = true break end
end
assert_line("load_slots", slots_ok, "load did not show the slot list")
local name_ok = false
for i = 1, 10 do
    emu.wait(0.3)
    if screen_has("test") then name_ok = true break end
end
assert_line("slot_has_name", name_ok,
            "saved character name missing from slot list")
-- Regression: eff_invuln_timer ($6f) is not persisted; a stale nonzero
-- value on load granted phantom invulnerability (Balrog hits, no damage).
prog:write_u8(0x6f, 0xC1)
press("1")
local loaded = false
for i = 1, 30 do
    emu.wait(0.5)
    if screen_has("Welcome back to Moria8!") then loaded = true break end
end
assert_line("loaded", loaded, "load did not resume the saved game")
assert_line("stats_restored", screen_has("test") and screen_has("Human"),
            "status line does not show the restored character")
assert_line("invuln_cleared", prog:read_u8(0x6f) == 0,
            "eff_invuln_timer not cleared on load: " .. prog:read_u8(0x6f))
dump("after_load")
print("SCENARIO DONE")
"""
LUA_DISK_SETUP_TWO_DRIVE_BODY = r"""
-- Disk Setup, two drives: pick the blank SAVE1 volume from the ON_LINE pick
-- list, initialize its marker, and return to title. Host-side check verifies
-- MORIA8.ID landed on the second disk image.
for i = 1, 300 do
    emu.wait(0.1)
    if prog:read_u8(0x550 + 14) == 0xA9 then break end
end
press("D")
assert_line("ds_menu", wait_screen("Pick save drive"),
            "disk setup menu did not appear")
assert_line("ds_program_vol", screen_has("Program: /MORIA8"),
            "program volume summary missing")
assert_line("ds_save_default", screen_has("Save:     (S6,D1)"),
            "default selection is not one-drive on the program unit")
press("2")
assert_line("ds_pick_list", wait_screen("/SAVE1"), "save volume not listed")
assert_line("ds_pick_unit", screen_has("(S6,D2)"),
            "save volume not shown on slot 6 drive 2")
press("2")
assert_line("ds_save_vol", wait_screen("Save:    /SAVE1"),
            "save volume summary did not update")
press("3")
assert_line("ds_init_prompt", wait_screen("Initialize this disk?"),
            "marker init prompt missing")
press("Y")
local back = false
for i = 1, 40 do
    emu.wait(0.5)
    if prog:read_u8(0x550 + 14) == 0xA9 then back = true break end
end
assert_line("ds_done", back, "did not return to title after setup")
dump("after_ds_two_drive")
print("SCENARIO DONE")
"""

LUA_DISK_SETUP_SWAP_BODY = r"""
-- Disk Setup, one-drive swap: no second drive, so the save disk is selected
-- by physically swapping and rescanning. Exercises the pick-list rescan, the
-- program-media rejection, the insert-save prompt, marker init, and the
-- program-disk restore prompt. SAVE_IMAGE/GAME_IMAGE substituted by the host.
local flop1 = nil
for tag, img in pairs(manager.machine.images) do
    if string.find(tag, "diskiing:0:525") then flop1 = img end
end
for i = 1, 300 do
    emu.wait(0.1)
    if prog:read_u8(0x550 + 14) == 0xA9 then break end
end
press("D")
assert_line("sw_menu", wait_screen("Pick save drive"),
            "disk setup menu did not appear")
press("2")
assert_line("sw_only_game", wait_screen("/MORIA8") and not screen_has("/SAVE1"),
            "pick list should show only the game volume before the swap")
flop1:load("SAVE_IMAGE")
emu.wait(1)
press("R")
assert_line("sw_rescan", wait_screen("/SAVE1"),
            "rescan did not find the swapped save disk")
press("1")
assert_line("sw_save_vol", wait_screen("Save:    /SAVE1"),
            "save volume summary did not update")
-- Done with the game disk re-inserted: program-media rejection must fire.
flop1:load("GAME_IMAGE")
emu.wait(1)
press("3")
assert_line("sw_prog_reject", wait_screen("Program disk cannot hold saves."),
            "program-media rejection missing")
press(" ")
-- While the game disk stays mounted the rejection alternates with the
-- insert prompt, which cancels back to the menu on Q.
assert_line("sw_insert_alt", wait_screen("Insert save disk"),
            "rejection did not alternate to the insert prompt")
press("Q")
assert_line("sw_menu_escape", wait_screen("Pick save drive"),
            "Q did not return to the menu")
-- Done again with the game disk still mounted: same rejection, then swap.
press("3")
assert_line("sw_reject_sticky", wait_screen("Program disk cannot hold saves."),
            "rejection did not persist with the game disk mounted")
press(" ")
assert_line("sw_insert_save", wait_screen("Insert save disk"),
            "insert-save prompt missing")
flop1:load("SAVE_IMAGE")
emu.wait(1)
press(" ")
assert_line("sw_init_prompt", wait_screen("Initialize this disk?"),
            "marker init prompt missing")
press("Y")
assert_line("sw_restore", wait_screen("Insert program disk"),
            "program-disk restore prompt missing")
flop1:load("GAME_IMAGE")
emu.wait(1)
press(" ")
local back = false
for i = 1, 40 do
    emu.wait(0.5)
    if prog:read_u8(0x550 + 14) == 0xA9 then back = true break end
end
assert_line("sw_done", back, "did not return to title after swap setup")
dump("after_ds_swap")
print("SCENARIO DONE")
"""
LUA_DISK_SETUP_ADOPT_BODY = r"""
-- Disk Setup, media changed after selection: the configured SAVE1 volume is
-- replaced by a different formatted disk (SAVE2), then by unreadable media.
-- Commodore semantics: the prepare flow adopts the inserted ProDOS volume
-- and offers init; unreadable media gets the init offer whose init fails
-- with the classified detail line. SAVE_IMAGE/SAVE2_IMAGE/BLANK_IMAGE and
-- GAME_IMAGE substituted by the host.
local flop2 = nil
for tag, img in pairs(manager.machine.images) do
    if string.find(tag, "diskiing:1:525") then flop2 = img end
end
for i = 1, 300 do
    emu.wait(0.1)
    if prog:read_u8(0x550 + 14) == 0xA9 then break end
end
press("D")
assert_line("ad_menu", wait_screen("Pick save drive"),
            "disk setup menu did not appear")
press("2")
assert_line("ad_pick", wait_screen("/SAVE1"), "SAVE1 not listed")
press("2")
assert_line("ad_save_vol", wait_screen("Save:    /SAVE1"),
            "save volume summary did not update")
-- Swap the selected disk for a different formatted one, then Done.
flop2:load("SAVE2_IMAGE")
emu.wait(1)
press("3")
assert_line("ad_init_offer", wait_screen("Initialize this disk?"),
            "init not offered for the inserted volume")
press("Y")
local back = false
for i = 1, 40 do
    emu.wait(0.5)
    if prog:read_u8(0x550 + 14) == 0xA9 then back = true break end
end
assert_line("ad_commit", back, "did not return to title after adopting SAVE2")
-- Phase 2: unreadable media on the save unit. Setup runs again (D), Done
-- with a zeroed disk in drive 2: init is offered, init fails, the
-- classified failure screen shows, and the flow returns to the menu.
press("D")
assert_line("ad_menu2", wait_screen("Pick save drive"),
            "menu did not reappear for phase 2")
assert_line("ad_save_vol2", screen_has("Save:    /SAVE2"),
            "adopted volume missing from the summary")
flop2:load("BLANK_IMAGE")
emu.wait(2)
press("3")
assert_line("ad_init_offer2", wait_screen("Initialize this disk?", 80),
            "init not offered for unreadable media")
press("Y")
assert_line("ad_init_fail", wait_screen("Could not initialize disk.", 80),
            "init failure screen missing for unreadable media")
assert_line("ad_init_detail", screen_has("Check the disk and try again."),
            "generic detail line missing")
press(" ")
assert_line("ad_back_to_menu", wait_screen("Pick save drive"),
            "did not return to the menu after init failure")
-- Phase 3: unreadable media must still be listed/selectable as a drive
-- (Commodore parity); selecting it leads to the same honest init failure.
press("2")
assert_line("ad_np_listed", wait_screen("<not ProDOS>"),
            "unreadable disk not listed in the pick screen")
assert_line("ad_np_unit", screen_has("(S6,D2)"),
            "unreadable disk shown without its unit")
press("2")
press("3")
assert_line("ad_np_offer", wait_screen("Initialize this disk?", 80),
            "init not offered for the selected unreadable drive")
press("Y")
assert_line("ad_np_fail", wait_screen("Could not initialize disk.", 80),
            "init failure screen missing for selected unreadable drive")
press(" ")
assert_line("ad_np_menu", wait_screen("Pick save drive"),
            "did not return to the menu after unreadable init failure")
press("Q")
local home = false
for i = 1, 40 do
    emu.wait(0.5)
    if prog:read_u8(0x550 + 14) == 0xA9 then home = true break end
end
assert_line("ad_quit", home, "did not return to title after Q")
dump("after_ds_adopt")
print("SCENARIO DONE")
"""
LUA_REBOOT_SAVE_BODY = r"""
-- Session A of save_reboot_load: chargen, then save slot 1 to the SAVE1
-- volume in drive 2 (same setup flow as save_load).
local s = keymap["Left Shift"]
local f = findkey("S")
s:set_value(1) emu.wait(0.02)
f:set_value(1) emu.wait(0.03) f:set_value(0) emu.wait(0.02)
s:set_value(0)
local prompt_ok = false
local DISK_MODE = 0x0a05
for i = 1, 90 do
    emu.wait(0.5)
    if screen_has("R) Rescan") then
        press_slow("2")
    elseif screen_has("Initialize this disk?") then
        press_slow("Y")
    elseif screen_has("Select Slot 1-4") then prompt_ok = true break
    elseif screen_has("Pick save drive") and prog:read_u8(DISK_MODE) == 0 then
        if screen_has("/SAVE1") then press_slow("3") else press_slow("2") end
    end
end
assert_line("save_slot_prompt", prompt_ok, "save slot prompt did not appear")
press("1")
local started = false
for i = 1, 12 do
    emu.wait(0.5)
    if screen_has("Saving game") then started = true break end
    if screen_has("Overwrite?") then press("Y") end
end
assert_line("saving_msg", started, "save did not start")
local title_ok = false
for i = 1, 90 do
    emu.wait(0.5)
    if screen_has("Overwrite?") then press("Y") end
    if screen_has("-more-") then press(" ") end
    if prog:read_u8(0x550 + 14) == 0xA9 then title_ok = true break end
end
assert_line("save_completed", title_ok, "save did not complete")
print("SCENARIO DONE")
"""

LUA_REBOOT_LOAD_BODY = r"""
-- Session B of save_reboot_load: cold boot, then load the session-A save.
-- Regression: title_load_game must not call play-slot code before
-- a2_require_play has loaded the play payload (cold-boot crash).
for i = 1, 300 do
    emu.wait(0.1)
    if prog:read_u8(0x550 + 14) == 0xA9 then break end
end
press("L")
local DISK_MODE = 0x0a05
local slots_ok = false
for i = 1, 90 do
    emu.wait(0.5)
    if screen_has("R) Rescan") then
        press_slow("2")
    elseif screen_has("Initialize this disk?") then
        press_slow("Y")
    elseif screen_has("Save Slots:") then slots_ok = true break
    elseif screen_has("Pick save drive") and prog:read_u8(DISK_MODE) == 0 then
        if screen_has("/SAVE1") then press_slow("3") else press_slow("2") end
    end
end
assert_line("load_slots", slots_ok, "load did not show the slot list")
local name_ok = false
for i = 1, 10 do
    emu.wait(0.3)
    if screen_has("test") then name_ok = true break end
end
assert_line("slot_has_name", name_ok,
            "saved character name missing from slot list")
press("1")
local loaded = false
for i = 1, 40 do
    emu.wait(0.5)
    if screen_has("Welcome back to Moria8!") then loaded = true break end
end
assert_line("loaded", loaded, "reboot load did not resume the saved game")
assert_line("stats_restored", screen_has("test") and screen_has("Human"),
            "status line does not show the restored character")
dump("after_load")
print("SCENARIO DONE")
"""
LUA_SLOT_TRACKING_BODY = r"""
-- Save-slot tracking: save slot 2, return to title, load slot 2, then save
-- again — the in-game save slot menu must mark the loaded slot with '*'.
-- Regression: save_slot_index must live outside the OVL.STORAGE window or
-- the marker is forgotten across the overlay swap.
local s = keymap["Left Shift"]
local f = findkey("S")
local function shift_s()
    s:set_value(1) emu.wait(0.02)
    f:set_value(1) emu.wait(0.03) f:set_value(0) emu.wait(0.02)
    s:set_value(0) emu.wait(0.12)
end
local DISK_MODE = 0x0a05
local function drive_setup_to_slots()
    for i = 1, 90 do
        emu.wait(0.5)
        if screen_has("R) Rescan") then
            press_slow("2")
        elseif screen_has("Initialize this disk?") then
            press_slow("Y")
        elseif screen_has("Select Slot 1-4") then return true
        elseif screen_has("Pick save drive") and prog:read_u8(DISK_MODE) == 0 then
            if screen_has("/SAVE1") then press_slow("3") else press_slow("2") end
        end
    end
    return false
end
shift_s()
assert_line("st_slot_prompt", drive_setup_to_slots(),
            "save slot prompt did not appear")
press("2")
local title_ok = false
for i = 1, 90 do
    emu.wait(0.5)
    if screen_has("Overwrite?") then press("Y") end
    if screen_has("-more-") then press(" ") end
    if prog:read_u8(0x550 + 14) == 0xA9 then title_ok = true break end
end
assert_line("st_saved", title_ok, "save to slot 2 did not complete")
press("L")
local slots_ok = false
for i = 1, 40 do
    emu.wait(0.5)
    if screen_has("Save Slots:") then slots_ok = true break end
end
assert_line("st_load_slots", slots_ok, "load did not show the slot list")
press("2")
local loaded = false
for i = 1, 40 do
    emu.wait(0.5)
    if screen_has("Welcome back to Moria8!") then loaded = true break end
end
assert_line("st_loaded", loaded, "load from slot 2 did not resume")
-- Descend to dungeon level 1: overlay and tier loads evict OVL.STORAGE from
-- the window. The loaded-slot marker must still survive to the next save.
local descended = false
for i = 1, 10 do
    press("L")
    emu.wait(1)
    shift(".")
    emu.wait(2)
    if screen_has("DL:1") then descended = true break end
end
assert_line("st_descended", descended, "did not descend after load")
shift_s()
local marked = false
for i = 1, 40 do
    emu.wait(0.5)
    if screen_has("Select Slot 1-4") then
        marked = screen_has("2) *")
        break
    end
end
assert_line("st_marker", marked,
            "loaded slot not marked with '*' in the save menu")
press("2")
local saved2 = false
for i = 1, 90 do
    emu.wait(0.5)
    if screen_has("Overwrite?") then press("Y") end
    if screen_has("-more-") then press(" ") end
    if prog:read_u8(0x550 + 14) == 0xA9 then saved2 = true break end
end
assert_line("st_resaved", saved2, "re-save to slot 2 did not complete")
dump("after_slot_tracking")
print("SCENARIO DONE")
"""


def _chargen_body(class_key: str) -> str:
    return LUA_HELPERS + LUA_CHARGEN.replace("CLASS_KEY", class_key)


def priest_pray_lua() -> str:
    return _chargen_body("C") + LUA_PRIEST_PRAY_BODY


def priest_map_area_lua() -> str:
    return (_chargen_body("C") + LUA_MAP_AREA_BODY
            ).replace("PLAYER_DATA_ADDR", hex(_sym_addr("player_data"))
            ).replace("INV_ITEM_ID_ADDR", hex(_sym_addr("inv_item_id"))
            ).replace("INV_QTY_ADDR", hex(_sym_addr("inv_qty")))


def help_overlay_lua() -> str:
    return _chargen_body("A") + LUA_HELP_BODY


def wizard_flow_lua() -> str:
    return _chargen_body("A") + LUA_WIZARD_BODY



def _balrog_symbols(body: str) -> str:
    return (body
            .replace("MONSTER_TABLE_ADDR", hex(_sym_addr("monster_table")))
            .replace("CR_LEVEL_ADDR", hex(_sym_addr("cr_level")))
            .replace("PLAYER_X_ADDR", hex(_sym_addr("zp_player_x")))
            .replace("PLAYER_Y_ADDR", hex(_sym_addr("zp_player_y")))
            .replace("GAME_FLAGS_ADDR", hex(_sym_addr("zp_game_flags")))
            .replace("PLAYER_DATA_ADDR", hex(_sym_addr("player_data")))
            .replace("CMB_TYPE_ADDR", hex(_sym_addr("cmb_type")))
            .replace("MSGFLAGS_ADDR", hex(_sym_addr("zp_msg_flags")))
            .replace("DLVL_ADDR", hex(_sym_addr("zp_player_dlvl")))
            .replace("BUSY_ADDR", hex(_sym_addr("generation_busy_active_api"))))





def balrog_victory_lua() -> str:
    return _chargen_body("A") + _balrog_symbols(LUA_BALROG_BODY)


def quaff_p3_lua() -> str:
    return _chargen_body("A") + LUA_QUAFF_P3_BODY


def _sym_addr(name: str) -> int:
    for line in (ROOT / "build" / "apple2" / "main.vs").read_text().splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "al" and parts[2] == "." + name:
            return int(parts[1][2:], 16)
    raise KeyError(name)


def deep_objdet_lua() -> str:
    return _chargen_body("A") + LUA_DEEP_OBJDET_BODY


def scroll_objdet_lua() -> str:
    return _chargen_body("A") + LUA_SCROLL_OBJDET_BODY


def scroll_map_lua() -> str:
    return _chargen_body("A") + LUA_SCROLL_MAP_BODY


def scroll_rune_lua() -> str:
    body = LUA_SCROLL_RUNE_BODY.replace("GLYPHADDR", hex(_sym_addr("glyph_active")))
    return _chargen_body("A") + body


def dungeon_descend_lua() -> str:
    return _chargen_body("A") + LUA_DUNGEON_BODY


def death_flow_lua() -> str:
    return _chargen_body("A") + LUA_DEATH_BODY


def save_load_lua() -> str:
    return _chargen_body("A") + LUA_SAVE_LOAD_BODY


def mage_list_lua() -> str:
    return _chargen_body("B") + LUA_MAGE_LIST_BODY


def disk_setup_two_drive_lua() -> str:
    return LUA_HELPERS + LUA_DISK_SETUP_TWO_DRIVE_BODY


def disk_setup_swap_lua() -> str:
    return (LUA_HELPERS + LUA_DISK_SETUP_SWAP_BODY)


def disk_setup_adopt_lua() -> str:
    return (LUA_HELPERS + LUA_DISK_SETUP_ADOPT_BODY)


def save_slot_tracking_lua() -> str:
    return _chargen_body("A") + LUA_SLOT_TRACKING_BODY


def scroll_delta_lua() -> str:
    return _chargen_body("A") + LUA_SCROLL_DELTA_BODY


SCENARIO_LUA = {
    "priest_pray": priest_pray_lua,
    "priest_map_area": priest_map_area_lua,
    "help_overlay": help_overlay_lua,
    "wizard_flow": wizard_flow_lua,
    "scroll_rune": scroll_rune_lua,
    "balrog_victory": balrog_victory_lua,
    "quaff_p3": quaff_p3_lua,
    "scroll_objdet": scroll_objdet_lua,
    "deep_objdet": deep_objdet_lua,
    "scroll_map": scroll_map_lua,
    "dungeon_descend": dungeon_descend_lua,
    "death_flow": death_flow_lua,
    "save_load": save_load_lua,
    "mage_list": mage_list_lua,
    "scroll_delta": scroll_delta_lua,
    "disk_setup_two_drive": disk_setup_two_drive_lua,
    "disk_setup_swap": disk_setup_swap_lua,
    "disk_setup_adopt": disk_setup_adopt_lua,
    "save_slot_tracking": save_slot_tracking_lua,
}

# Scenarios that exercise a separate save disk (blank ProDOS image, volume
# SAVE1, created fresh per run); two_drive/adopt/save_load/death_flow mount
# it as -flop2, swap loads it into flop1 from Lua.
SAVE_DISK_SCENARIOS = ("disk_setup_two_drive", "disk_setup_swap",
                       "disk_setup_adopt", "save_load", "death_flow",
                       "save_reboot_load", "save_slot_tracking")
FLOP2_SCENARIOS = ("disk_setup_two_drive", "disk_setup_adopt",
                   "save_load", "death_flow", "save_slot_tracking")
SAVE_IMAGE = ROOT / "build" / "apple2" / "save1.po"
SAVE2_IMAGE = ROOT / "build" / "apple2" / "save2.po"
BLANK_IMAGE = ROOT / "build" / "apple2" / "blank.po"
AC_BIN = ROOT / "tools" / "applecommander" / "ac"
# Host-side proofs: scenario -> (image, required file).
HOST_MARKER_IMAGES = {
    "disk_setup_two_drive": (SAVE_IMAGE, "MORIA8.ID"),
    "disk_setup_swap": (SAVE_IMAGE, "MORIA8.ID"),
    "disk_setup_adopt": (SAVE2_IMAGE, "MORIA8.ID"),
    "save_load": (SAVE_IMAGE, "THE.GAME"),
    "save_reboot_load": (SAVE_IMAGE, "THE.GAME"),
    "save_slot_tracking": (SAVE_IMAGE, "THE.GAME2"),
}

SCENARIOS = ("boot_title",) + tuple(SCENARIO_LUA) + ("save_reboot_load",)


def _run_mame(args, lua, flop2):
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
    ]
    if flop2:
        cmd += ["-flop2", str(SAVE_IMAGE)]
    cmd += [
        "-autoboot_script", lua_path,
        "-video", "none",
        "-sound", "none",
        "-nothrottle",
        "-seconds_to_run", str(args.seconds + 5),
    ]
    # Homebrew MAME on macOS opens an app window even with -video none.
    # SDL's dummy video driver prevents window creation entirely, so the
    # harness never takes focus or interrupts the user.
    env = os.environ.copy()
    env["SDL_VIDEODRIVER"] = "dummy"
    env["SDL_AUDIODRIVER"] = "dummy"
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, env=env)
    try:
        stdout, stderr = proc.communicate(timeout=max(300, args.seconds + 60))
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
    return (stdout or "") + (stderr or "")


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

    if args.scenario != "boot_title" and args.seconds == 20.0:
        args.seconds = 240.0
    if args.scenario == "boot_title" and args.seconds == 20.0:
        # Boot goes through crash-reboot cycles before the title flow
        # completes; 20 s is marginal on a cold start.
        args.seconds = 30.0

    if args.scenario == "save_reboot_load":
        lua = None
    elif args.scenario != "boot_title":
        lua = SCENARIO_LUA[args.scenario]()
        lua = lua.replace("SAVE2_IMAGE", str(SAVE2_IMAGE))
        lua = lua.replace("BLANK_IMAGE", str(BLANK_IMAGE))
        lua = lua.replace("SAVE_IMAGE", str(SAVE_IMAGE))
        lua = lua.replace("GAME_IMAGE", str(args.image))
    else:
        table = "local MENU_EXPECTED = {%s}\n" % ",".join(
            str(b) for b in MENU_EXPECTED)
        lua = table + (
            LUA_BOOT_TITLE
            .replace("WAIT_TENTHS", str(int(args.seconds * 10)))
            .replace("MENU_START_COL", str(MENU_START_COL))
            .replace("ROW18_BASE", str(ROW18_BASE))
        )

    if args.scenario in SAVE_DISK_SCENARIOS:
        # Fresh blank SAVE1 volume every run for determinism.
        SAVE_IMAGE.unlink(missing_ok=True)
        mk = subprocess.run([str(AC_BIN), "-pro140", str(SAVE_IMAGE), "SAVE1"],
                            capture_output=True, text=True)
        if mk.returncode != 0:
            print(f"error: could not create save image: {mk.stderr}",
                  file=sys.stderr)
            return 1
    if args.scenario == "disk_setup_adopt":
        # SAVE1 (initial selection), SAVE2 (adoption target), and a zeroed
        # image that ProDOS cannot read at all.
        for path, vol in ((SAVE_IMAGE, "SAVE1"), (SAVE2_IMAGE, "SAVE2")):
            path.unlink(missing_ok=True)
            mk = subprocess.run([str(AC_BIN), "-pro140", str(path), vol],
                                capture_output=True, text=True)
            if mk.returncode != 0:
                print(f"error: could not create save image: {mk.stderr}",
                      file=sys.stderr)
                return 1
        BLANK_IMAGE.write_bytes(bytes(143360))

    if args.scenario == "save_reboot_load":
        # Session A: save to SAVE1. Session B: cold boot, load it back.
        lua_a = _chargen_body("A") + LUA_REBOOT_SAVE_BODY
        lua_b = LUA_HELPERS + LUA_REBOOT_LOAD_BODY
        out = _run_mame(args, lua_a, True)
        out += _run_mame(args, lua_b, True)
    else:
        out = _run_mame(args, lua, args.scenario in FLOP2_SCENARIOS)

    if args.scenario != "boot_title":
        failures = 0
        asserts = 0
        seen = set()
        for line in out.splitlines():
            if not line.startswith("ASSERT "):
                continue
            body = line[7:]
            name, _, verdict = body.partition(" ")
            asserts += 1
            seen.add(name)
            if not verdict.startswith("PASS"):
                failures += 1
            print(line)
        for line in out.splitlines():
            if line.startswith(("NOKEY", "RETRY EXHAUSTED", "NO TOWN")):
                failures += 1
                print(f"HARNESS {line}")
        if args.scenario in HOST_MARKER_IMAGES:
            # Host-side proof: the file landed on the save volume image
            # (not the game disk).
            image, want = HOST_MARKER_IMAGES[args.scenario]
            ls = subprocess.run([str(AC_BIN), "-l", str(image)],
                                capture_output=True, text=True)
            ok = want in ls.stdout
            asserts += 1
            if not ok:
                failures += 1
            print(f"ASSERT host_marker {'PASS' if ok else 'FAIL'}")
        print(f"RESULT {asserts} asserts {failures} failures")
        # A scenario that never prints its completion marker stalled mid-flow;
        # assert counts alone cannot prove completion.
        if "SCENARIO DONE" not in out:
            print("HARNESS scenario did not print SCENARIO DONE (stalled)")
            tail = [l for l in out.splitlines() if l.strip()][-15:]
            for l in tail:
                print(f"HARNESS-OUT {l}")
            return 1
        if asserts == 0:
            # A scenario that produces no asserts did not run its script at
            # all (Lua load/runtime error, boot failure). Never pass silently:
            # show the harness output tail so the cause is visible.
            tail = [l for l in out.splitlines() if l.strip()][-15:]
            for l in tail:
                print(f"HARNESS-OUT {l}")
            return 1
        return 0 if failures == 0 else 1

    dumps = {}
    map_nonzero = -1
    bootprog = 0
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
        elif line.startswith("DUMP BOOTPROG "):
            bootprog = int(line[14:])
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

    # Boot progress line must have ticked at least once (0xB1 = '1').
    check("boot_progress", bootprog >= 0xB1,
          f"max count digit={bootprog:#04x}")

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
