#!/usr/bin/env python3
"""Atari 8-bit MAME smoke harness for moria8 (docs/ATARI8_MEMORY_CONTRACT.md).

Drives headless MAME (a800xl / a130xe) against build/moria8-atari8.atr:
generates a per-scenario Lua script that polls RAM sentinels and 40x25
SCREEN_RAM ($0800-$0BE7), injects keys into atari_kbdbuf / atari_kbdbuf_len,
and prints ASSERT lines. Enforces a strict 30-second host wall-clock timeout
per scenario (AGENTS.md Rule 8) with -nothrottle -seconds_to_run 120 emulated
time.

Suite:
  15 behavioral scenarios on a800xl (64 KB disk-overlay baseline)
  + 3 dedicated 130XE cache/SIO coexistence scenarios on a130xe.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from make_atr import build_blank_atr  # noqa: E402

ATR_IMAGE = ROOT / "build" / "moria8-atari8.atr"
SYM_PATH = ROOT / "build" / "atari8" / "main.sym"
MAME_OUTPUT_ROOT = ROOT / "build" / "atari8" / "mame"
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

HOST_TIMEOUT_SECONDS = 30
EMULATED_SECONDS_LIMIT = 180

SCREEN_RAM = 0x0800
ROW18_ADDR = SCREEN_RAM + 18 * 40
ROW23_ADDR = SCREEN_RAM + 23 * 40

FAST_SMOKE_SCENARIOS = (
    "boot_title",
    "chargen_town",
    "save_load",
)

A800XL_SCENARIOS = (
    "boot_title",
    "chargen_town",
    "dungeon_descend",
    "help_overlay",
    "ui_modals",
    "item_actions",
    "mage_list",
    "priest_pray",
    "priest_map_area",
    "scroll_map",
    "wizard_flow",
    "balrog_victory",
    "death_flow",
    "save_load",
    "disk_setup",
)

A130XE_SCENARIOS = (
    "xe_cache_verify",
    "town_to_dungeon_130xe",
    "save_load_130xe",
)

SCENARIOS = A800XL_SCENARIOS + A130XE_SCENARIOS


def parse_symbols(sym_path: Path) -> dict[str, int]:
    syms: dict[str, int] = {}
    if not sym_path.is_file():
        return syms
    label_re = re.compile(r"^\.label\s+([A-Za-z0-9_]+)\s*=\s*\$([0-9A-Fa-f]+)")
    for line in sym_path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = label_re.match(line.strip())
        if m:
            syms[m.group(1)] = int(m.group(2), 16)
    return syms


def build_lua_script(scenario: str, syms: dict[str, int], machine: str) -> str:
    kbdbuf = syms.get("atari_kbdbuf", 0x0D00)
    kbdbuf_len = syms.get("atari_kbdbuf_len", 0x0CFF)
    kbcode_table = syms.get("atari_kbcode_table", 0x1000)
    igk_char = syms.get("igk_char", 0x1080)
    # input_get_key, the window the playtester's bridge taps: a key is fed
    # only once the program reads the empty buffer from there. Without the
    # symbols every key wait fails (wait_for_key_poll), as it should.
    key_wait_start = syms.get("input_get_key", 0)
    key_wait_end = syms.get("igk_save_x", 1) - 1
    xe_present = syms.get("xe_present", 0x0D10)
    xe_slot_pop = syms.get("xe_slot_populated", 0x0D11)
    current_ovl = syms.get("current_overlay", 0x0D20)
    zp_px = syms.get("zp_player_x", 0x002B)
    zp_py = syms.get("zp_player_y", 0x002C)
    zp_mp = syms.get("zp_player_mp", 0x0031)
    zp_lvl = syms.get("zp_player_lvl", 0x0033)
    zp_dlvl = syms.get("zp_player_dlvl", 0x0034)
    zp_gflags = syms.get("zp_game_flags", 0x003C)
    player_data = syms.get("player_data", 0x1800)
    inv_item_id = syms.get("inv_item_id", 0x1900)
    inv_qty = syms.get("inv_qty", 0x1920)
    monster_table = syms.get("monster_table", 0x1A00)
    cr_level = syms.get("cr_level", 0x1B00)
    save_device = syms.get("save_device", 0x0D30)
    disk_setup_done = syms.get("disk_setup_done", 0x0D31)
    busy_addr = syms.get("generation_busy_active_api", 0x0D40)

    header = f"""
local prog = manager.machine.devices[":maincpu"].spaces["program"]
local KBDBUF = 0x{kbdbuf:04X}
local KBDBUF_LEN = 0x{kbdbuf_len:04X}
local KBCODE_TABLE = 0x{kbcode_table:04X}
local IGK_CHAR = 0x{igk_char:04X}
local KEY_WAIT_START = 0x{key_wait_start:04X}
local KEY_WAIT_END = 0x{key_wait_end:04X}
local XE_PRESENT = 0x{xe_present:04X}
local XE_SLOT_POP = 0x{xe_slot_pop:04X}
local CURRENT_OVL = 0x{current_ovl:04X}
local PLAYER_X_ADDR = 0x{zp_px:04X}
local PLAYER_Y_ADDR = 0x{zp_py:04X}
local PLAYER_MP_ADDR = 0x{zp_mp:04X}
local PLAYER_LVL_ADDR = 0x{zp_lvl:04X}
local DLVL_ADDR = 0x{zp_dlvl:04X}
local GAME_FLAGS_ADDR = 0x{zp_gflags:04X}
local PLAYER_DATA_ADDR = 0x{player_data:04X}
local INV_ITEM_ID_ADDR = 0x{inv_item_id:04X}
local INV_QTY_ADDR = 0x{inv_qty:04X}
local MONSTER_TABLE_ADDR = 0x{monster_table:04X}
local CR_LEVEL_ADDR = 0x{cr_level:04X}
local SAVE_DEV_ADDR = 0x{save_device:04X}
local DISK_SETUP_DONE_ADDR = 0x{disk_setup_done:04X}
local BUSY_ADDR = 0x{busy_addr:04X}
local SCREEN_RAM = 0x{SCREEN_RAM:04X}
local ROW18 = 0x{ROW18_ADDR:04X}
local ROW23 = 0x{ROW23_ADDR:04X}

local function wait_frames(n)
    for _ = 1, n do emu.wait(1/60) end
end

local function sc_to_ascii(b)
    b = b & 0x7F
    if b == 0x00 then return "@" end
    if b >= 0x01 and b <= 0x1A then return string.char(0x60 + b) end
    if b >= 0x1B and b <= 0x1F then return string.char(0x40 + b) end
    if b >= 0x20 and b <= 0x3F then return string.char(b) end
    if b == 0x40 then return "-" end
    if b >= 0x41 and b <= 0x5A then return string.char(b) end
    return "."
end

local function rowtext(r)
    local base = SCREEN_RAM + r * 40
    local chars = {{}}
    for c = 0, 39 do
        chars[c + 1] = sc_to_ascii(prog:read_u8(base + c))
    end
    return table.concat(chars)
end

local function screen_has(txt)
    for r = 0, 24 do
        if string.find(rowtext(r), txt, 1, true) then return true end
    end
    return false
end

local function assert_line(name, ok)
    print("ASSERT " .. (ok and "PASS " or "FAIL ") .. name)
end

-- key_polled: input_get_key has read the empty buffer since it was last
-- cleared. A modal prompt empties the buffer before it reads
-- (input_wait_release), so a key written as soon as the prompt's text shows
-- would be dropped. The tap is kept in a global, as the playtester's bridge
-- keeps its own: a tap Lua collects stops firing.
local cpu = manager.machine.devices[":maincpu"]
local key_polled = false
_G.harness_key_poll_tap = prog:install_read_tap(KBDBUF_LEN, KBDBUF_LEN, "harness_key_poll",
    function(offset, data, mask)
        if data ~= 0 then return end   -- the dequeue taking a key, not a wait
        local pc = cpu.state["PC"].value
        if pc >= KEY_WAIT_START and pc <= KEY_WAIT_END then key_polled = true end
    end)

-- wait_for_key_poll: until the program waits in input_get_key; a key fed any
-- earlier can be flushed, so not seeing the wait fails the scenario.
local function wait_for_key_poll(keys)
    key_polled = false
    for _ = 1, 300 do
        if key_polled then return end
        emu.wait(1/60)
    end
    assert_line("key_wait_seen_before_" .. keys, false)
end

local function send_key(petscii)
    for _ = 1, 300 do
        if prog:read_u8(KBDBUF_LEN) == 0 and prog:read_u8(0xD301) == 0xFE then break end
        emu.wait(1/60)
    end
    wait_for_key_poll(string.format("%02X", petscii))
    prog:write_u8(KBDBUF, petscii)
    prog:write_u8(KBDBUF_LEN, 1)
    for _ = 1, 300 do
        emu.wait(1/60)
        if prog:read_u8(KBDBUF_LEN) == 0 and prog:read_u8(0xD301) == 0xFE then break end
    end
    wait_frames(10)
end

-- type_ahead: keys typed together while the program waits for one, as a
-- fast typist's would be queued by the keyboard IRQ.
local function type_ahead(keys)
    wait_for_key_poll("type_ahead")
    for i, k in ipairs(keys) do prog:write_u8(KBDBUF + i - 1, k) end
    prog:write_u8(KBDBUF_LEN, #keys)
    wait_frames(30)
end

local function wait_screen(txt, max_tenths)
    for _ = 1, (max_tenths or 60) do
        if screen_has(txt) then return true end
        emu.wait(0.1)
    end
    return screen_has(txt)
end

local function press_until(txt, petscii, tries)
    for _ = 1, (tries or 12) do
        if screen_has(txt) then return true end
        send_key(petscii)
        if wait_screen(txt, 50) then return true end
    end
    return screen_has(txt)
end

local function drain_more(max_presses)
    for _ = 1, (max_presses or 8) do
        if not screen_has("-more-") then break end
        send_key(0x20)
        wait_frames(20)
    end
end

local function in_town()
    if prog:read_u8(DLVL_ADDR) ~= 0 then return false end
    if screen_has("Character") or screen_has("Inventory") or screen_has("Equipment") or screen_has("Command Reference") then
        return false
    end
    local walls = 0
    for r = 2, 20 do
        local base = SCREEN_RAM + r * 40
        for c = 1, 38 do
            if prog:read_u8(base + c) == 0x23 then
                walls = walls + 1
            end
        end
    end
    return walls >= 20
end

local function wait_title()
    for _ = 1, 1000 do
        emu.wait(0.1)
        if screen_has("N)ew") and screen_has("L)oad") then
            return true
        end
    end
    return false
end

local function start_new_game(class_key)
    if not wait_title() then
        assert_line("title_reached", false)
        manager.machine:exit()
        return false
    end
    press_until("Choose your race", 0x4E) -- 'N'
    press_until("Roll Statistics", 0x41)  -- 'A' (Human)
    press_until("Choose your class", 0x0D) -- RETURN (accept stats)
    press_until("Enter your name", string.byte(class_key or "A"))
    send_key(0x54) -- 'T'
    send_key(0x45) -- 'E'
    send_key(0x53) -- 'S'
    send_key(0x54) -- 'T'
    press_until("Choose your sex", 0x0D)
    press_until("Character Info", 0x41) -- 'A' (Male)
    for _ = 1, 200 do
        if screen_has("Character Info") then send_key(0x20) end
        wait_frames(20)
        drain_more(2)
        if in_town() and prog:read_u8(PLAYER_X_ADDR) > 0 and prog:read_u8(PLAYER_Y_ADDR) > 0 then
            return true
        end
    end
    return false
end

local function wizard_menu_open(tries)
    for _ = 1, (tries or 12) do
        if screen_has("Q to cancel") then return true end
        drain_more(2)
        if screen_has("WIZARD?") then
            send_key(0x59) -- 'Y'
            if wait_screen("Q to cancel", 60) then return true end
        else
            send_key(0x17) -- CTRL+W
            wait_frames(30)
            if screen_has("WIZARD?") then
                send_key(0x59)
                if wait_screen("Q to cancel", 60) then return true end
            end
            if wait_screen("Q to cancel", 60) then return true end
        end
    end
    return false
end

local function descend_to_dl1()
    for _ = 1, 12 do
        send_key(0x4C) -- 'L'
        wait_frames(20)
        drain_more(2)
        send_key(0x3E) -- '>'
        for _ = 1, 60 do
            wait_frames(10)
            if prog:read_u8(DLVL_ADDR) == 1 and prog:read_u8(BUSY_ADDR) == 0 and not screen_has("GENERATING") then
                return true
            end
        end
    end
    return prog:read_u8(DLVL_ADDR) == 1
end
"""

    if scenario == "boot_title":
        body = """
function run()
    local ok = wait_title()
    assert_line("boot_title_menu", ok)
    local portb = prog:read_u8(0xD301)
    assert_line("portb_game_ram", portb == 0xFE)
    local chbase = prog:read_u8(0x02F4)
    assert_line("chbase_0400", chbase == 0x04 and prog:read_u8(0x0402) ~= 0)
    local stairs_up = prog:read_u8(KBCODE_TABLE + 0x60) == 0x3C
    local stairs_dn = prog:read_u8(KBCODE_TABLE + 0x62) == 0x3E
    local tunnel_plus = prog:read_u8(KBCODE_TABLE + 0x4F) == 0x2B and prog:read_u8(KBCODE_TABLE + 0x77) == 0x2B
    assert_line("kbcode_pc_shifted_stairs_and_plus", stairs_up and stairs_dn and tunnel_plus)
    local brk_field = manager.machine.ioport.ports[":keyboard.0"].fields["Break"]
    brk_field:set_value(1)
    wait_frames(4)
    brk_field:set_value(0)
    wait_frames(4)
    assert_line("mame_backspace_break_queues_del", prog:read_u8(IGK_CHAR) == 0x14)
    manager.machine:exit()
end
"""
    elif scenario == "xe_cache_verify":
        expected_xe = 1 if machine == "a130xe" else 0
        body = f"""
function run()
    local ok = wait_title()
    assert_line("boot_title_menu", ok)
    local xe = prog:read_u8(XE_PRESENT)
    assert_line("xe_detect_{machine}", xe == {expected_xe})
    if {expected_xe} == 1 then
        -- All 15 slots (0..9 overlays, 10..13 monster tiers, 14 TITLE.DAT) must have bit 7 set
        local all_slots_hot = true
        for slot = 0, 14 do
            if (prog:read_u8(XE_SLOT_POP + slot) & 0x80) == 0 then
                all_slots_hot = false
                break
            end
        end
        assert_line("xe_all_15_slots_preloaded", all_slots_hot)
    end
    manager.machine:exit()
end
"""
    elif scenario == "town_to_dungeon_130xe":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("town_130xe_ready", ok)
    assert_line("xe_active", prog:read_u8(XE_PRESENT) == 1)
    local dl1 = descend_to_dl1()
    assert_line("dungeon_130xe_dl1", dl1)
    manager.machine:exit()
end
"""
    elif scenario in ("save_load", "save_load_130xe"):
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    send_key(0xD3) -- SHIFT+S (save & quit) -> prompts Disk Setup on first save
    assert_line("save_disk_setup_prompt", wait_screen("DISK SETUP", 80))
    send_key(0x33) -- 3) Done (default Save: D2:)
    assert_line("save_disk_init_prompt", wait_screen("Initialize this disk? (Y/N)", 80))
    send_key(0x59) -- 'Y' -> initialize blank Save Disk in D2:
    assert_line("save_slot_prompt", wait_screen("Select Slot 1-4", 120))
    send_key(0x31) -- Slot 1
    for _ = 1, 300 do
        wait_frames(15)
        if screen_has("Overwrite?") then send_key(0x59) end
        if screen_has("-more-") or screen_has("saved") then send_key(0x20) end
        if screen_has("N)ew") and screen_has("L)oad") then break end
    end
    assert_line("title_after_save", screen_has("N)ew") and screen_has("L)oad"))
    send_key(0x4C) -- 'L' (load game)
    assert_line("load_slots_shown", wait_screen("Select Slot 1-4", 80))
    send_key(0x31) -- Slot 1
    for _ = 1, 300 do
        wait_frames(15)
        if prog:read_u8(PLAYER_X_ADDR) > 0 and screen_has("Welcome back") then break end
    end
    assert_line("save_load_resumed", prog:read_u8(PLAYER_X_ADDR) > 0)
    manager.machine:exit()
end
"""
    elif scenario == "chargen_town":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    local x0 = prog:read_u8(PLAYER_X_ADDR)
    local y0 = prog:read_u8(PLAYER_Y_ADDR)
    for _, k in ipairs({0x4C, 0x48, 0x4A, 0x4B}) do
        send_key(k)
        wait_frames(25)
        if prog:read_u8(PLAYER_X_ADDR) ~= x0 or prog:read_u8(PLAYER_Y_ADDR) ~= y0 then break end
    end
    assert_line("town_step_moved", prog:read_u8(PLAYER_X_ADDR) ~= x0 or prog:read_u8(PLAYER_Y_ADDR) ~= y0)
    manager.machine:exit()
end
"""
    elif scenario == "dungeon_descend":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    local dl1 = descend_to_dl1()
    assert_line("dlvl_1_reached", dl1 and prog:read_u8(DLVL_ADDR) == 1)
    assert_line("not_in_town", not in_town())
    manager.machine:exit()
end
"""
    elif scenario == "help_overlay":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    send_key(0x3F) -- '?' (help)
    assert_line("help_opened", wait_screen("Command Reference", 80))
    send_key(0x51) -- 'Q'
    wait_frames(40)
    assert_line("help_closed", in_town())
    manager.machine:exit()
end
"""
    elif scenario == "ui_modals":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    send_key(0x49) -- 'I' (inventory)
    assert_line("inventory_modal", wait_screen("Inventory", 80))
    send_key(0x20)
    wait_frames(40)
    send_key(0x45) -- 'E' (equipment)
    assert_line("equipment_modal", wait_screen("Equipment", 80))
    send_key(0x20)
    wait_frames(40)
    send_key(0xC3) -- SHIFT+C (character sheet)
    assert_line("charsheet_modal", wait_screen("Character", 80))
    send_key(0x20)
    wait_frames(40)
    assert_line("ui_modals_returned", in_town())
    -- SHIFT+Q with a 'Y' typed right after it: the prompt drops the Y (a
    -- move), so the question waits; 'N' then plays on.
    type_ahead({0xD1, 0x59})
    assert_line("quit_prompt_shown", wait_screen("Do you really want to quit?", 80))
    wait_frames(150)   -- time for a quit to leave the town screen
    assert_line("typed_ahead_y_ignored", screen_has("Do you really want to quit?") and in_town())
    send_key(0x4E) -- 'N'
    wait_frames(40)
    assert_line("quit_declined", in_town() and not screen_has("Do you really want to quit?"))
    -- Rollover, on POKEY's own scan: SHIFT+Q, then Y pressed while Q is
    -- still down, and Q let go first. POKEY reports the Y once the Q is up;
    -- the prompt waits for every key to come up before it listens, so the Y
    -- does not answer.
    local keys = manager.machine.ioport.ports
    local shift = keys[":fake"].fields["Shift"]
    local q = keys[":keyboard.5"].fields["q  Q"]
    local y = keys[":keyboard.5"].fields["y  Y"]
    wait_for_key_poll("rollover")
    shift:set_value(1)
    q:set_value(1)
    wait_frames(6)
    y:set_value(1)
    wait_frames(6)
    q:set_value(0)
    shift:set_value(0)
    wait_frames(6)
    y:set_value(0)
    assert_line("rollover_prompt_shown", wait_screen("Do you really want to quit?", 80))
    wait_frames(150)
    assert_line("rollover_y_ignored", screen_has("Do you really want to quit?") and in_town())
    send_key(0x4E) -- 'N'
    wait_frames(40)
    assert_line("rollover_declined", in_town() and not screen_has("Do you really want to quit?"))
    manager.machine:exit()
end
"""
    elif scenario == "item_actions":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    assert_line("wizard_open", wizard_menu_open())
    press_until("ITEM", 0x47) -- 'G'
    send_key(0x39) -- '9'
    send_key(0x37) -- '7' (Potion of Restoration)
    send_key(0x0D)
    assert_line("wizard_gain_ok", wait_screen("OK", 60))
    send_key(0x51) -- 'Q' (quaff)
    assert_line("quaff_prompt", wait_screen("Quaff which potion", 80))
    send_key(0x41) -- 'A'
    assert_line("quaff_effect", wait_screen("strength return", 80))
    manager.machine:exit()
end
"""
    elif scenario == "mage_list":
        body = """
function run()
    local ok = start_new_game("B")
    assert_line("chargen_mage_ready", ok)
    send_key(0x4D) -- 'M' (cast)
    assert_line("cast_book_prompt", wait_screen("Spell book", 80) or screen_has("Cast"))
    send_key(0x41) -- 'A'
    assert_line("cast_which_prompt", wait_screen("Cast which?", 80))
    send_key(0x3F) -- '?'
    assert_line("mage_book_title", wait_screen("Mage Book", 80))
    assert_line("mage_spell_mm", wait_screen("Magic Missile", 20))
    manager.machine:exit()
end
"""
    elif scenario == "priest_pray":
        body = """
function run()
    local ok = start_new_game("C")
    assert_line("chargen_priest_ready", ok)
    send_key(0x50) -- 'P' (pray)
    assert_line("pray_book_prompt", wait_screen("Prayer book", 80))
    send_key(0x41) -- 'A'
    assert_line("pray_which_prompt", wait_screen("Pray which?", 80))
    send_key(0x3F) -- '?'
    assert_line("priest_book_title", wait_screen("Prayer Book", 80))
    assert_line("priest_names", wait_screen("Bless", 20) and screen_has("Detect Evil"))
    send_key(0x41) -- 'A'
    wait_frames(80)
    drain_more(4)
    assert_line("pray_executed", not screen_has("Pray which?"))
    manager.machine:exit()
end
"""
    elif scenario == "priest_map_area":
        body = """
function run()
    local ok = start_new_game("C")
    assert_line("chargen_priest_ready", ok)
    prog:write_u8(PLAYER_DATA_ADDR + 19, 33)
    prog:write_u8(PLAYER_LVL_ADDR, 33)
    prog:write_u8(PLAYER_DATA_ADDR + 37, 50)
    prog:write_u8(PLAYER_MP_ADDR, 50)
    prog:write_u8(PLAYER_DATA_ADDR + 63, prog:read_u8(PLAYER_DATA_ADDR + 63) | 0x40)
    for i = 0, 30 do
        if prog:read_u8(INV_ITEM_ID_ADDR + i) == 0xFF then
            prog:write_u8(INV_ITEM_ID_ADDR + i, 59)
            prog:write_u8(INV_QTY_ADDR + i, 1)
            break
        end
    end
    send_key(0x50) -- 'P'
    wait_screen("Prayer book", 80)
    send_key(0x42) -- 'B'
    wait_screen("Pray which?", 80)
    send_key(0x3F) -- '?'
    assert_line("sense_surroundings_listed", wait_screen("Sense Surroundings", 80))
    send_key(0x41) -- 'A'
    for _ = 1, 200 do
        emu.wait(0.1)
        if screen_has("-more-") then send_key(0x20) end
        if prog:read_u8(PLAYER_DATA_ADDR + 37) < 50 then break end
    end
    local mp_after = prog:read_u8(PLAYER_DATA_ADDR + 37)
    assert_line("map_mana_spent", mp_after >= 39 and mp_after <= 41)
    manager.machine:exit()
end
"""
    elif scenario == "scroll_map":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    assert_line("wizard_open", wizard_menu_open())
    press_until("ITEM", 0x47) -- 'G'
    send_key(0x31) -- '1'
    send_key(0x30) -- '0'
    send_key(0x32) -- '2' (Scroll of Magic Mapping)
    send_key(0x0D)
    assert_line("wizard_gain_ok", wait_screen("OK", 80))
    send_key(0x52) -- 'R' (read scroll)
    assert_line("read_prompt", wait_screen("Read which scroll", 80))
    send_key(0x41) -- 'A'
    assert_line("map_scroll_msg", wait_screen("map grow clearer", 150))
    manager.machine:exit()
end
"""
    elif scenario == "wizard_flow":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    assert_line("wizard_open", wizard_menu_open())
    send_key(0x58) -- 'X' (gain experience/level)
    for _ = 1, 150 do
        emu.wait(0.1)
        if screen_has("-more-") then send_key(0x20) end
        if prog:read_u8(PLAYER_LVL_ADDR) >= 2 then break end
    end
    assert_line("gain_level_lv2", screen_has("LV:2") or prog:read_u8(PLAYER_LVL_ADDR) >= 2)
    manager.machine:exit()
end
"""
    elif scenario == "balrog_victory":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    local dl1 = descend_to_dl1()
    assert_line("descended_dl1", dl1)
    local mt = MONSTER_TABLE_ADDR
    local base = mt
    for i = 0, 31 do
        local b = mt + i * 12
        if prog:read_u8(b + 2) ~= 0xFF then base = b break end
    end
    local px = prog:read_u8(PLAYER_X_ADDR)
    local py = prog:read_u8(PLAYER_Y_ADDR)
    local mx, my = px + 1, py
    local dirs = {
        {1, 0, 0x4C},  -- 'L' east
        {-1, 0, 0x48}, -- 'H' west
        {0, 1, 0x4A},  -- 'J' south
        {0, -1, 0x4B}, -- 'K' north
    }
    local atk_key = 0x4C
    for _, d in ipairs(dirs) do
        local cx, cy, k = px + d[1], py + d[2], d[3]
        local mbyte = prog:read_u8(0xC100 + cy * 80 + cx)
        if (mbyte & 0xF0) == 0 then
            mx, my, atk_key = cx, cy, k
            break
        end
    end
    local ox = prog:read_u8(base + 0)
    local oy = prog:read_u8(base + 1)
    if ox < 80 and oy < 48 then
        local oaddr = 0xC100 + oy * 80 + ox
        prog:write_u8(oaddr, prog:read_u8(oaddr) & 0xFE)
    end
    prog:write_u8(base + 0, mx)
    prog:write_u8(base + 1, py + (my - py))
    prog:write_u8(base + 2, 56) -- CREATURE_BALROG
    prog:write_u8(base + 3, 1)  -- 1 HP
    prog:write_u8(base + 4, 0)
    prog:write_u8(base + 8, 0xFF) -- Stunned
    prog:write_u8(CR_LEVEL_ADDR + 56, 100)
    prog:write_u8(PLAYER_DATA_ADDR + 40, 127)
    local map_addr = 0xC100 + my * 80 + mx
    prog:write_u8(map_addr, prog:read_u8(map_addr) | 0x01)
    for _ = 1, 16 do
        send_key(atk_key)
        wait_frames(30)
        drain_more(4)
        if (prog:read_u8(GAME_FLAGS_ADDR) & 0x04) == 0x04 then break end
    end
    assert_line("balrog_winner_flag", (prog:read_u8(GAME_FLAGS_ADDR) & 0x04) == 0x04)
    send_key(0xD1) -- Shift+Q (retire after Balrog victory)
    assert_line("retire_veni_vidi", wait_screen("Veni, Vidi, Vici!", 100))
    send_key(0x20) -- SPACE -> triggers Disk Setup before High-Score / Winner screen
    assert_line("retire_disk_setup_open", wait_screen("DISK SETUP", 100))
    send_key(0x32) -- '2) Pick save drive'
    assert_line("retire_pick_drive", wait_screen("Save drive (1-4):", 60))
    send_key(0x32) -- '2' (D2: blank save disk)
    assert_line("retire_save_d2", wait_screen("Save:    D2:", 60))
    send_key(0x33) -- '3) Done'
    assert_line("retire_no_marker", wait_screen("No Save Disk marker found.", 80))
    send_key(0x59) -- 'Y' (initialize D2: and continue to winner screen)
    assert_line("retire_winner_screen", wait_screen("* Total Winner *", 150))
    manager.machine:exit()
end
"""
    elif scenario == "death_flow":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    local dl1 = descend_to_dl1()
    assert_line("descended_dl1", dl1)
    assert_line("wizard_open", wizard_menu_open())
    press_until("DLVL", 0x4C) -- 'L'
    send_key(0x31)
    send_key(0x30)
    send_key(0x0D)
    for _ = 1, 150 do
        emu.wait(0.1)
        if prog:read_u8(DLVL_ADDR) == 10 and prog:read_u8(BUSY_ADDR) == 0 and not screen_has("GENERATING") then break end
    end
    drain_more(4)
    assert_line("wizard_open2", wizard_menu_open())
    send_key(0x53) -- 'S' (summon monster)
    for _ = 1, 80 do
        emu.wait(0.1)
        if screen_has("OK") or screen_has("FAIL") then break end
    end
    drain_more(4)
    local slain = false
    for _ = 1, 200 do
        if screen_has("You have been slain") or screen_has("DISK SETUP") then slain = true break end
        if screen_has("-more-") then send_key(0x20) else send_key(0x35) end
        wait_frames(20)
    end
    assert_line("player_slain", slain)
    if not screen_has("DISK SETUP") then
        send_key(0x20) -- SPACE -> triggers Disk Setup before Death / High-Score screen
    end
    assert_line("death_disk_setup_open", wait_screen("DISK SETUP", 100))
    send_key(0x32) -- '2) Pick save drive'
    assert_line("death_pick_drive", wait_screen("Save drive (1-4):", 60))
    send_key(0x32) -- '2' (D2: blank save disk)
    assert_line("death_save_d2", wait_screen("Save:    D2:", 60))
    send_key(0x33) -- '3) Done'
    assert_line("death_no_marker", wait_screen("No Save Disk marker found.", 80))
    send_key(0x59) -- 'Y' (initialize D2: and continue to death screen)
    assert_line("player_died", wait_screen("* You have died *", 150))
    manager.machine:exit()
end
"""
    elif scenario == "disk_setup":
        body = """
function run()
    local ok = wait_title()
    assert_line("title_ready", ok)
    send_key(0x44) -- 'D' (Disk Setup)
    assert_line("disk_setup_open", wait_screen("DISK SETUP", 80))
    send_key(0x32) -- '2) Pick save drive'
    assert_line("disk_setup_pick_prompt", wait_screen("Save drive (1-4):", 60))
    send_key(0x51) -- 'Q' (cancel drive pick back to Disk Setup menu)
    assert_line("cancel_pick_returned_menu", wait_screen("1) Same as program", 60))
    send_key(0x31) -- '1) Same as program' (D1:)
    assert_line("insert_save_prompt", wait_screen("Insert a separate Save Disk", 60))
    send_key(0x20) -- SPACE with Program Disk still in D1:
    assert_line("prog_disk_rejected", wait_screen("Program disk cannot hold saves.", 80))
    send_key(0x51) -- 'Q' (cancel back to Disk Setup menu)
    assert_line("disk_setup_reopened", wait_screen("DISK SETUP", 60))
    send_key(0x32) -- '2) Pick save drive'
    wait_screen("Save drive (1-4):", 60)
    send_key(0x32) -- '2' (D2:)
    assert_line("save_d2_selected", wait_screen("Save:    D2:", 60))
    send_key(0x33) -- '3) Done'
    assert_line("no_marker_prompt", wait_screen("No Save Disk marker found.", 80))
    assert_line("init_ask_prompt", screen_has("Initialize this disk? (Y/N)"))
    send_key(0x59) -- 'Y'
    assert_line("returned_title", wait_screen("N)ew", 120) and screen_has("L)oad"))
    assert_line("save_dev_9", prog:read_u8(SAVE_DEV_ADDR) == 9)
    assert_line("disk_setup_done_1", prog:read_u8(DISK_SETUP_DONE_ADDR) == 1)
    manager.machine:exit()
end
"""
    else:
        raise ValueError(f"Unknown scenario: {scenario}")

    return header + body + "\nco = coroutine.create(run)\ncoroutine.resume(co)\n"


def run_scenario(
    scenario: str,
    rompath: str,
    disk_path: Path,
    sym_path: Path,
    mame_bin: str = "mame",
    machine: str = "a800xl",
) -> bool:
    syms = parse_symbols(sym_path)
    lua_code = build_lua_script(scenario, syms, machine)

    for output_dir in MAME_OUTPUT_DIRS.values():
        output_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_atr = Path(tmpdir) / "work.atr"
        shutil.copy2(disk_path, tmp_atr)
        tmp_save_atr = Path(tmpdir) / "save.atr"
        build_blank_atr(tmp_save_atr)
        lua_path = Path(tmpdir) / "scenario.lua"
        lua_path.write_text(lua_code, encoding="utf-8")

        cmd = [
            mame_bin,
            machine,
            "-rompath",
            rompath,
            "-cfg_directory",
            str(MAME_OUTPUT_DIRS["cfg"]),
            "-nvram_directory",
            str(MAME_OUTPUT_DIRS["nvram"]),
            "-input_directory",
            str(MAME_OUTPUT_DIRS["input"]),
            "-state_directory",
            str(MAME_OUTPUT_DIRS["state"]),
            "-snapshot_directory",
            str(MAME_OUTPUT_DIRS["snapshot"]),
            "-diff_directory",
            str(MAME_OUTPUT_DIRS["diff"]),
            "-comment_directory",
            str(MAME_OUTPUT_DIRS["comment"]),
            "-share_directory",
            str(MAME_OUTPUT_DIRS["share"]),
            "-flop1",
            str(tmp_atr),
            "-flop2",
            str(tmp_save_atr),
            "-autoboot_script",
            str(lua_path),
            "-video",
            "none",
            "-sound",
            "none",
            "-nothrottle",
            "-seconds_to_run",
            str(EMULATED_SECONDS_LIMIT),
        ]

        env = os.environ.copy()
        env["SDL_VIDEODRIVER"] = "dummy"
        env["SDL_AUDIODRIVER"] = "dummy"

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        try:
            stdout, stderr = proc.communicate(timeout=HOST_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            print(
                f"[{machine}:{scenario}] FAIL: host timeout ({HOST_TIMEOUT_SECONDS}s)",
                file=sys.stderr,
            )
            return False

        out = (stdout or "") + (stderr or "")
        passes = 0
        fails = 0
        for line in out.splitlines():
            if line.startswith("ASSERT PASS "):
                passes += 1
            elif line.startswith("ASSERT FAIL "):
                fails += 1
                print(f"[{machine}:{scenario}] {line}", file=sys.stderr)

        if fails > 0 or passes == 0:
            if passes == 0 and out.strip():
                print(out.strip(), file=sys.stderr)
            print(
                f"[{machine}:{scenario}] FAIL (passes={passes}, fails={fails})",
                file=sys.stderr,
            )
            return False

        print(f"[{machine}:{scenario}] PASS ({passes} assertions)")
        return True


def selftest() -> int:
    assert HOST_TIMEOUT_SECONDS <= 30, "AGENTS.md Rule 8 requires timeout <= 30s"
    assert len(A800XL_SCENARIOS) == 15, f"Expected 15 a800xl scenarios, got {len(A800XL_SCENARIOS)}"
    assert len(A130XE_SCENARIOS) == 3, f"Expected 3 a130xe scenarios, got {len(A130XE_SCENARIOS)}"
    syms = parse_symbols(SYM_PATH)
    if syms:
        assert syms.get("zp_player_x") == 0x002B, f"zp_player_x != $002B: {syms.get('zp_player_x')}"
        assert syms.get("zp_player_y") == 0x002C, f"zp_player_y != $002C: {syms.get('zp_player_y')}"
        assert syms.get("zp_player_dlvl") == 0x0034, f"zp_player_dlvl != $0034: {syms.get('zp_player_dlvl')}"
    for sc in A800XL_SCENARIOS:
        lua_xl = build_lua_script(sc, syms, "a800xl")
        assert "assert_line(" in lua_xl and "coroutine.resume" in lua_xl
        assert "PLAYER_X_ADDR = 0x002B" in lua_xl
        assert "DLVL_ADDR = 0x0034" in lua_xl
    for sc in A130XE_SCENARIOS:
        lua_xe = build_lua_script(sc, syms, "a130xe")
        assert "assert_line(" in lua_xe and "coroutine.resume" in lua_xe
    print("Atari 8-bit harness_smoke.py self-test: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenario", nargs="?", default="boot_title", choices=SCENARIOS)
    parser.add_argument("--rompath", default=os.environ.get("ATARI8ROMS", ""))
    parser.add_argument("--disk", type=Path, default=ATR_IMAGE)
    parser.add_argument("--sym", type=Path, default=SYM_PATH)
    parser.add_argument("--mame", default="mame")
    parser.add_argument("--machine", default="a800xl", choices=("a800xl", "a130xe"))
    parser.add_argument("--fast-smoke", "--fast", dest="fast_smoke", action="store_true")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    if not args.rompath:
        print(
            "error: ATARI8ROMS env var or --rompath required",
            file=sys.stderr,
        )
        return 1

    if not args.disk.is_file():
        print(
            f"error: disk image missing: {args.disk} (run make diskatari8)",
            file=sys.stderr,
        )
        return 1

    if args.fast_smoke:
        for sc in FAST_SMOKE_SCENARIOS:
            if not run_scenario(sc, args.rompath, args.disk, args.sym, args.mame, "a800xl"):
                return 1
        return 0

    if args.all:
        for sc in A800XL_SCENARIOS:
            if not run_scenario(sc, args.rompath, args.disk, args.sym, args.mame, "a800xl"):
                return 1
        for sc in A130XE_SCENARIOS:
            if not run_scenario(sc, args.rompath, args.disk, args.sym, args.mame, "a130xe"):
                return 1
        return 0

    machine = "a130xe" if args.scenario in A130XE_SCENARIOS else args.machine
    ok = run_scenario(
        args.scenario, args.rompath, args.disk, args.sym, args.mame, machine
    )
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
