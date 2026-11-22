#!/usr/bin/env python3
"""Acorn BBC Master 128 MAME smoke harness for moria8 (docs/BBCMASTER_MEMORY_CONTRACT.md).

Drives headless MAME (bbcm) against build/moria8-bbcmaster.ssd: generates a
per-scenario Lua script that polls RAM sentinels and 80x24 beeb_char_shadow
($3800-$3F7F in Shadow RAM LYNNE), injects keys into beeb_kbdbuf / beeb_kbdbuf_len,
and prints ASSERT lines. Enforces a strict 30-second host wall-clock timeout
per scenario (AGENTS.md Rule 8) with -nothrottle -seconds_to_run 180 emulated
time.

boot_title boots from the disk (*EXEC !BOOT: boot.s streams MORIA8P, about 75
emulated seconds of DFS reads). Every other scenario fast-boots: the entries of
the disk's own MORIA8P go where the loader's tables put them, and a stub at
&900 finishes as boot.s does (fast_boot_entries; --real-boot boots them all
from the disk). MAME's bbcm has no save states to start from a booted title.

Suite:
  19 behavioral scenarios on bbcm (128 KB BBC Master 128 with Sideways RAM cache).
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
import build_catalog  # noqa: E402
import catalog_lore  # noqa: E402  (the generated monster catalog's data)
import item_ids  # noqa: E402
from make_ssd import build_blank_ssd  # noqa: E402


LUA_ITEM_CONSTS = item_ids.lua_item_consts(
    "DAGGER",
    "MACE",
    "SCROLL_OF_IDENTIFY",
    "RING_OF_PROTECTION",
    "WAND_OF_LIGHTNING",
    "WAND_OF_STINKING_CLOUD",
    "SPELLBOOK_MAGICK_I",
    "HOLY_BOOK_OF_PRAYERS_CHANTS_AND_BLESSINGS",
    "CLOAK",
    "POTION_OF_GAIN_DEXTERITY",
    "POTION_OF_CHARISMA",
    "POTION_OF_RESTORE_INTELLIGENCE",
    "POTION_OF_CURE_CRITICAL_WOUNDS",
    "POTION_OF_NEUTRALIZE_POISON",
    "SCROLL_OF_MAGIC_MAPPING",
    "SCROLL_OF_RECHARGING",
    "SCROLL_OF_GENOCIDE",
    "RING_OF_RESIST_FIRE",
    "RING_OF_RESIST_COLD",
    "AMULET_OF_THE_MAGI",
    "GOLDEN_CROWN",
    "WAND_OF_FIRE_BOLTS",
    "WAND_OF_DRAIN_LIFE",
    "STAFF_OF_DARKNESS_L50",
)

SSD_IMAGE = ROOT / "build" / "moria8-bbcmaster.ssd"
SYM_PATH = ROOT / "build" / "bbcmaster" / "main.sym"
MAME_OUTPUT_ROOT = ROOT / "build" / "bbcmaster" / "mame"
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
EMULATED_SECONDS_LIMIT = 240

SCREEN_COLS = 80
SCREEN_ROWS = 24
CHAR_SHADOW_BASE = 0x3800
MAP_COLS = 198
MAP_ROWS = 66
MAP_BASE_ADDR = 0x8000
MAP_SWR_BANK = 0x05


def core_const(file: str, name: str) -> int:
    """A ``.const NAME = value`` from core/<file>."""
    match = re.search(rf"^\.const {name}\s*=\s*(\$?[0-9A-Fa-f]+)", (ROOT / "core" / file).read_text(), re.M)
    if match is None:
        raise KeyError(name)
    text = match.group(1)
    return int(text[1:], 16) if text.startswith("$") else int(text)

FAST_SMOKE_SCENARIOS = (
    "boot_title",
    "chargen_town",
    "save_load",
)

SCENARIOS = (
    "boot_title",
    "chargen_town",
    "dungeon_descend",
    "help_overlay",
    "ui_modals",
    "item_actions",
    "equip_flags",
    "mage_list",
    "priest_pray",
    "priest_map_area",
    "scroll_map",
    "wizard_flow",
    "balrog_victory",
    "death_flow",
    "save_load",
    "save_negative",
    "save_write_negative",
    "disk_setup",
    "acid_armour",
    "catalog_spawn",
)


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


def andy_mos_bytes() -> str:
    """The corpus bytes at ANDY $8800-$882F, where the MOS mode change keeps
    its ECF patterns (screen.s screen_init), as a Lua table."""
    data = (ROOT / "build" / "bbcmaster" / "beeb.huffdata").read_bytes()
    load = data[0] | data[1] << 8
    return "{" + ",".join(str(b) for b in data[2 + 0x8800 - load:2 + 0x8830 - load]) + "}"


LOADER_DEST = 0x0400        # boot.s relocates its loader here before streaming MORIA8P
FAST_BOOT_STUB = 0x0900     # MOS cassette/RS423 buffers: free, below MORIA8.RES at $0E00


def read_dfs_file(image: bytes, name: str) -> bytes:
    """One file of an Acorn DFS image (directory $), by name."""
    count = image[0x105] // 8
    for i in range(count):
        entry = image[8 + i * 8:16 + i * 8]
        if entry[:7].decode("ascii", "replace").rstrip() != name or (entry[7] & 0x7F) != ord("$"):
            continue
        info = image[0x108 + i * 8:0x110 + i * 8]
        length = info[4] | info[5] << 8 | ((info[6] >> 4) & 3) << 16
        start = info[7] | (info[6] & 3) << 8
        return image[start * 256:start * 256 + length]
    raise FileNotFoundError(f"{name} not in the DFS catalogue")


def fast_boot_entries(disk_path: Path, boot_sym_path: Path) -> list[tuple[int, int, bytes]]:
    """What boot.s's loader puts where: MORIA8P's entries in order, each with
    the bank and page the loader's own tables give (file_bank_table,
    file_hi_table in the relocated block of the MORIA8 file on this disk)."""
    image = disk_path.read_bytes()
    boot = read_dfs_file(image, "MORIA8")
    pak = read_dfs_file(image, "MORIA8P")
    syms = parse_symbols(boot_sym_path)
    block = syms["loader_src"] - syms["boot_start"]   # the relocated block's offset in MORIA8
    count = pak[0]
    banks = boot[block + syms["file_bank_table"] - LOADER_DEST:][:count]
    pages = boot[block + syms["file_hi_table"] - LOADER_DEST:][:count]
    entries, offset = [], 512
    for i in range(count):
        length = pak[2 + i * 2] | pak[3 + i * 2] << 8
        entries.append((banks[i], pages[i] << 8, pak[offset:offset + length]))
        offset += length
    if offset != len(pak) or len(banks) != count or len(pages) != count:
        raise ValueError(f"MORIA8P holds {len(pak)} bytes, its header {offset}")
    return entries


def build_lua_script(scenario: str, syms: dict[str, int]) -> str:
    kbdbuf = syms.get("beeb_kbdbuf", 0x1000)
    kbdbuf_len = syms.get("beeb_kbdbuf_len", 0x1001)
    current_ovl = syms.get("current_overlay", 0x0E10)
    zp_px = syms.get("zp_player_x", 0x002B)
    zp_py = syms.get("zp_player_y", 0x002C)
    zp_mp = syms.get("zp_player_mp", 0x0031)
    zp_lvl = syms.get("zp_player_lvl", 0x0033)
    zp_dlvl = syms.get("zp_player_dlvl", 0x0034)
    zp_gflags = syms.get("zp_game_flags", 0x003C)
    zp_hp = syms.get("zp_player_hp_lo", 0x002D)
    zp_poison = syms.get("zp_eff_poison", 0x0050)
    current_tier = syms.get("current_tier", 0x4BA5)
    zp_turn = syms.get("zp_turn_lo", 0x0040)
    player_data = syms.get("player_data", 0x2400)
    inv_item_id = syms.get("inv_item_id", 0x2500)
    inv_qty = syms.get("inv_qty", 0x2522)
    monster_table = syms.get("monster_table", 0x2600)
    mon_count = syms.get("zp_mon_count", 0)
    recall_query_sc = syms.get("recall_query_sc", 0)
    cr_level = syms.get("cr_level", 0x2700)
    cat_ids = "\n".join(f"local {name.upper()}_ADDR = 0x{syms.get(name, 0):04X}" for name in (
        "cat_slot_id_lo", "cat_slot_id_hi", "cr_name_lo", "cr_name_hi",
        "cat_id_lo", "cat_id_hi", "cat_ext_record", "beeb_mext_handle",
        "catalog_fetch_ext", "input_entropy_tick"))
    save_device = syms.get("save_device", 0x0E20)
    disk_setup_done = syms.get("disk_setup_done", 0x0E21)
    busy_addr = syms.get("generation_busy_active_api", 0x0E30)
    acccon_shadow = syms.get("beeb_acccon_shadow", 0x009D)
    acid_syms = "\n".join(f"local {name.upper()}_ADDR = 0x{syms.get(name, 0):04X}" for name in (
        "cr_atk0_type", "cr_atk0_dice", "cr_atk0_sides", "cr_atk1_type", "cr_spell_chance", "cr_speed",
        "inv_to_ac", "zp_player_ac", "player_pflags", "ovl_town_end", "auto_rest_active",
        "trap_count", "trap_x", "trap_y", "trap_type", "floor_item_count",
        "door_state_count", "door_state_x", "door_state_y", "door_state_val",
        "beeb_dfs_load_to_bank"))

    header = LUA_ITEM_CONSTS + f"""
local prog = manager.machine.devices[":maincpu"].spaces["program"]
local KBDBUF = 0x{kbdbuf:04X}
local KBDBUF_LEN = 0x{kbdbuf_len:04X}
local KEY_WAIT_START = 0x{syms.get("input_get_key", 0):04X}
local FAST_BOOT_STUB = 0x{FAST_BOOT_STUB:04X}
local KEY_WAIT_END = 0x{syms.get("igk_key", 0):04X}
local CURRENT_OVL = 0x{current_ovl:04X}
local PLAYER_X_ADDR = 0x{zp_px:04X}
local PLAYER_Y_ADDR = 0x{zp_py:04X}
local PLAYER_MP_ADDR = 0x{zp_mp:04X}
local PLAYER_LVL_ADDR = 0x{zp_lvl:04X}
local DLVL_ADDR = 0x{zp_dlvl:04X}
local GAME_FLAGS_ADDR = 0x{zp_gflags:04X}
local PLAYER_HP_ADDR = 0x{zp_hp:04X}
local POISON_ADDR = 0x{zp_poison:04X}
local TURN_ADDR = 0x{zp_turn:04X}
local CURRENT_TIER_ADDR = 0x{current_tier:04X}
local PLAYER_DATA_ADDR = 0x{player_data:04X}
local INV_ITEM_ID_ADDR = 0x{inv_item_id:04X}
local INV_QTY_ADDR = 0x{inv_qty:04X}
local INV_STRIDE = INV_QTY_ADDR - INV_ITEM_ID_ADDR   -- TOTAL_INV_SLOTS (34)
local MONSTER_TABLE_ADDR = 0x{monster_table:04X}
local MON_COUNT_ADDR = 0x{mon_count:04X}
local RECALL_QUERY_SC_ADDR = 0x{recall_query_sc:04X}
local CR_LEVEL_ADDR = 0x{cr_level:04X}
local SAVE_DEV_ADDR = 0x{save_device:04X}
local DISK_SETUP_DONE_ADDR = 0x{disk_setup_done:04X}
local BUSY_ADDR = 0x{busy_addr:04X}
local ACCCON_SHADOW_ADDR = 0x{acccon_shadow:04X}
local CHAR_SHADOW = 0x{CHAR_SHADOW_BASE:04X}
local MAP_BASE = 0x{MAP_BASE_ADDR:04X}
local MAP_COLS = {MAP_COLS}
local MAP_ROWS = {MAP_ROWS}
local MAP_BANK = 0x{MAP_SWR_BANK:02X}
{acid_syms}
{cat_ids}
local BALROG_ID = {catalog_lore.const("CATALOG_BALROG_ID")}
local RACE_PROPS_ADDR = 0x{syms.get("race_properties", 0):04X}
local CLASS_PROPS_ADDR = 0x{syms.get("class_properties", 0):04X}
local PL_RACE = {core_const("player.s", "PL_RACE")}
local PL_CLASS = {core_const("player.s", "PL_CLASS")}
local PL_MHP_LO = {core_const("player.s", "PL_MHP_LO")}
local PL_FLAGS = {core_const("player.s", "PL_FLAGS")}
local PLF_RESTING = {core_const("player.s", "PLF_RESTING")}
local RACE_PROP_SIZE = {core_const("tables.s", "RACE_PROP_SIZE")}
local CLASS_PROP_SIZE = {core_const("tables.s", "CLASS_PROP_SIZE")}
local IGGY_ID = {catalog_lore.const("CATALOG_IGGY_ID")}

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

local function can_read_shadow()
    return prog:read_u8(ACCCON_SHADOW_ADDR) == 0x01 and prog:read_u8(0x00F4) == 0x04
end

local function enter_shadow()
    local prev = prog:read_u8(0xFE34)
    prog:write_u8(0xFE34, prev | 0x04)
    return prev
end

local function leave_shadow(prev)
    prog:write_u8(0xFE34, prev)
end

local function read_shadow_u8(addr)
    if not can_read_shadow() then return 0x20 end
    local prev = enter_shadow()
    local v = prog:read_u8(addr)
    leave_shadow(prev)
    return v
end

local function write_shadow_u8(addr, val)
    local prev = enter_shadow()
    prog:write_u8(addr, val)
    leave_shadow(prev)
end

local function read_map_u8(x, y)
    local rom = prog:read_u8(0x00F4)
    prog:write_u8(0xFE30, MAP_BANK)
    local v = prog:read_u8(MAP_BASE + y * MAP_COLS + x)
    prog:write_u8(0xFE30, rom)
    return v
end

local function write_map_u8(x, y, val)
    local rom = prog:read_u8(0x00F4)
    prog:write_u8(0xFE30, MAP_BANK)
    prog:write_u8(MAP_BASE + y * MAP_COLS + x, val)
    prog:write_u8(0xFE30, rom)
end

local function write_play_u8(addr, val)
    local rom = prog:read_u8(0x00F4)
    prog:write_u8(0xFE30, 0x04)
    prog:write_u8(addr, val)
    prog:write_u8(0xFE30, rom)
end

-- Removes every live monster (its map square's monster bit too), so nothing
-- on the level can see, disturb or reach the character.
local function clear_monsters()
    for i = 0, 31 do
        local b = MONSTER_TABLE_ADDR + i * 12
        if prog:read_u8(b + 2) ~= 0xFF then
            local x, y = prog:read_u8(b), prog:read_u8(b + 1)
            write_map_u8(x, y, read_map_u8(x, y) & 0xFE)
            prog:write_u8(b + 2, 0xFF)
        end
    end
    prog:write_u8(MON_COUNT_ADDR, 0)
end

local function rowtext(r)
    if not can_read_shadow() then return "" end
    local prev = enter_shadow()
    local base = CHAR_SHADOW + r * 80
    local chars = {{}}
    for c = 0, 79 do
        chars[c + 1] = sc_to_ascii(prog:read_u8(base + c))
    end
    leave_shadow(prev)
    return table.concat(chars)
end

local function screen_has(txt)
    if not can_read_shadow() then return false end
    local prev = enter_shadow()
    local found = false
    for r = 0, 23 do
        local base = CHAR_SHADOW + r * 80
        local chars = {{}}
        for c = 0, 79 do
            chars[c + 1] = sc_to_ascii(prog:read_u8(base + c))
        end
        if string.find(table.concat(chars), txt, 1, true) then
            found = true
            break
        end
    end
    leave_shadow(prev)
    return found
end

local function assert_line(name, ok)
    print("ASSERT " .. (ok and "PASS " or "FAIL ") .. name)
end

-- A heading can appear before typeahead is flushed. Observe an actual
-- input poll only while waiting to send a key; leave no tap installed idle.
local cpu = manager.machine.devices[":maincpu"]
local function send_key(petscii)
    local key_polled = false
    local poll = prog:install_read_tap(KBDBUF_LEN, KBDBUF_LEN, "harness_key_poll",
        function(offset, data, mask)
            if key_polled or data ~= 0 then return end
            local pc = cpu.state["PC"].value
            if pc >= KEY_WAIT_START and pc < KEY_WAIT_END then key_polled = true end
        end)
    for _ = 1, 1200 do                  -- 20 s: a cold DFS overlay/ITEMCAT burst can run that long
        if key_polled then break end
        emu.wait(1/60)
    end
    poll:remove()
    if not key_polled then assert_line("key_wait_seen", false) end
    for _ = 1, 300 do
        if prog:read_u8(KBDBUF_LEN) == 0 then break end
        emu.wait(1/60)
    end
    prog:write_u8(KBDBUF, petscii)
    prog:write_u8(KBDBUF_LEN, 1)
    for _ = 1, 300 do
        emu.wait(1/60)
        if prog:read_u8(KBDBUF_LEN) == 0 then break end
    end
    wait_frames(10)
end

local function send_int(n)
    local s = tostring(n)
    for i = 1, #s do send_key(string.byte(s, i)) end
    send_key(0x0D)
end

-- ITEMCAT page misses and cold overlay loads stream from the floppy at roughly
-- 0.3-0.5 emulated seconds per 256-byte DFS read, so a modal that names items
-- or swaps a cold overlay can take several seconds; every screen wait gets this
-- slack factor over its nominal limit (the 30 s host cap is unchanged).
local DFS_SLACK = 3
local function wait_screen(txt, max_tenths)
    for _ = 1, (max_tenths or 60) * DFS_SLACK do
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
    if not can_read_shadow() then return false end
    if prog:read_u8(DLVL_ADDR) ~= 0 then return false end
    if screen_has("Character") or screen_has("Inventory") or screen_has("Equipment") or screen_has("Command Reference") then
        return false
    end
    local prev = enter_shadow()
    local walls = 0
    for r = 2, 19 do
        local base = CHAR_SHADOW + r * 80
        for c = 1, 78 do
            if prog:read_u8(base + c) == 0x23 then
                walls = walls + 1
            end
        end
    end
    leave_shadow(prev)
    return walls >= 20
end

-- FAST_BOOT (run_scenario fills it): every scenario but boot_title starts
-- from the boot loader's result, not its 75 emulated seconds of DFS reads
-- (about 15 host seconds; help_overlay and item_actions took 26-28 of their
-- 30 alone and timed out in the parallel gate, 2026-11-13). As boot.s: shadow
-- Mode 7, MORIA8P's entries in their banks and MORIA8.RES at $0E00, ACCCON
-- $01, the filing-system ROM selected, then $0E00.
local FAST_BOOT = FAST_BOOT_TABLE
local booted = false
local function fast_boot()
    -- The stub: shadow Mode 7 (VDU 22,135), then it waits at $090A on the flag
    -- at $0920 while the payloads go in, so BASIC never runs again: run with
    -- HIMEM at $8000 its stack took MORIA8.RES's last bytes.
    local dfs = nil
    for bank = 0, 15 do
        prog:write_u8(0xFE30, bank)
        local title = ""
        for a = 0x8009, 0x800C do title = title .. string.char(prog:read_u8(a)) end
        if title:sub(1, 3) == "DFS" then dfs = bank end
    end
    prog:write_u8(0xFE30, prog:read_u8(0xF4))
    if dfs == nil then return false end
    local stub = {{0xA9, 0x16, 0x20, 0xEE, 0xFF,             -- VDU 22,
                   0xA9, 0x87, 0x20, 0xEE, 0xFF,             -- 135: shadow Mode 7, as boot.s
                   0xAD, 0x20, 0x09, 0xF0, 0xFB,             -- $090A: wait for the flag at $0920
                   0xA9, 0x01, 0x8D, 0x34, 0xFE,             -- ACCCON $01: shadow shown, Main RAM to the CPU
                   0xA9, dfs, 0x85, 0xF4, 0x8D, 0x30, 0xFE,  -- the filing-system ROM, as *RUN left it
                   0x4C, 0x00, 0x0E}}                        -- MORIA8.RES
    for i, b in ipairs(stub) do prog:write_u8(FAST_BOOT_STUB + i - 1, b) end
    prog:write_u8(FAST_BOOT_STUB + 0x20, 0)
    manager.machine.natkeyboard:post("*GO 900\\r")
    local parked = false
    for _ = 1, 500 do
        emu.wait(0.02)
        local pc = cpu.state["PC"].value
        if pc >= FAST_BOOT_STUB + 0x0A and pc < FAST_BOOT_STUB + 0x0F then parked = true break end
    end
    if not parked then return false end
    for _, e in ipairs(FAST_BOOT) do
        local f = io.open(e.path, "rb")
        local data = f:read("a")
        f:close()
        if e.bank ~= 0 then prog:write_u8(0xFE30, e.bank) end
        for i = 1, #data do prog:write_u8(e.addr + i - 1, data:byte(i)) end
        prog:write_u8(0xFE30, prog:read_u8(0xF4))
    end
    prog:write_u8(FAST_BOOT_STUB + 0x20, 1)
    return true
end
local function wait_title()
    emu.wait(1.0)
    if FAST_BOOT ~= nil and not booted then
        booted = true
        if not fast_boot() then return false end
    else
        manager.machine.natkeyboard:post("*EXEC !BOOT\\r")
    end
    for _ = 1, 1000 do
        emu.wait(0.1)
        if can_read_shadow() and screen_has("N)ew") and screen_has("L)oad") then
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

-- inv_seed(slot, fields): the 8 inventory fields of one slot
-- (id, qty, p1, to_hit, to_dam, to_ac, flags, ego).
local function inv_seed(slot, f)
    for k = 0, 7 do prog:write_u8(INV_ITEM_ID_ADDR + k * INV_STRIDE + slot, f[k + 1]) end
end
local function inv_field(slot, k)
    return prog:read_u8(INV_ITEM_ID_ADDR + k * INV_STRIDE + slot)
end

local function descend_to_dl1()
    for _ = 1, 12 do
        send_key(0x4C) -- 'L'
        wait_frames(20)
        drain_more(2)
        send_key(0x3E) -- '>'
        for step = 1, 240 do
            wait_frames(10)
            local dlvl = prog:read_u8(DLVL_ADDR)
            local busy = prog:read_u8(BUSY_ADDR)
            if dlvl == 1 and busy == 0 and screen_has("You descend") then
                return true
            end
            if step >= 4 and dlvl == 0 and busy == 0 then
                break
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
    -- Centred from its length: a hard-coded 35 left it off centre (2026-11-12).
    local menu = "N)ew  L)oad  D)isk Setup  A)bout"
    local start = math.floor((80 - #menu) / 2)
    assert_line("title_menu_centred", string.sub(rowtext(18), start + 1, start + #menu) == menu)
    wait_frames(30)
    local acccon = prog:read_u8(ACCCON_SHADOW_ADDR)
    assert_line("acccon_shadow_lynne", acccon == 0x01)
    local ula_shadow = prog:read_u8(0x0248)
    assert_line("ula_shadow_mode0", (ula_shadow & 0xFE) == 0x9C)
    local space_blank = true
    local bmp_blank = true
    local a_nonblank = 0
    for i = 0, 7 do
        if read_shadow_u8(0x3100 + i) ~= 0 then space_blank = false end
        if read_shadow_u8(0x4400 + i) ~= 0 then bmp_blank = false end
        a_nonblank = a_nonblank | read_shadow_u8(0x3208 + i)
    end
    assert_line("font_space_blank_and_a_valid", space_blank and bmp_blank and a_nonblank ~= 0)
    local romsel = prog:read_u8(0x00F4)
    assert_line("romsel_play_bank4", romsel == 0x04)
    assert_line("title_sysinfo_row", screen_has("D)isk Setup"))
    manager.machine.natkeyboard:post("d")
    assert_line("real_kbd_opens_disk_setup", wait_screen("DISK SETUP", 80))
    manager.machine.natkeyboard:post("q")
    assert_line("real_kbd_returns_title", wait_screen("D)isk Setup", 80))
    manager.machine:exit()
end
"""
    elif scenario == "save_load":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    -- Cloak (slot 32), Secondary weapon (slot 33), Page 1 item (slot 21), and LYNNE recall[278].
    inv_seed(21, {ITEM_SLOT_STAFF_OF_DARKNESS_L50, 1, 5, 0, 0, 0, 2, ITEM_PAGE_STAFF_OF_DARKNESS_L50})
    inv_seed(32, {ITEM_SLOT_CLOAK, 1, 0, 0, 0, 2, 2, ITEM_PAGE_CLOAK})
    inv_seed(33, {ITEM_SLOT_DAGGER, 1, 0, 3, 4, 0, 2, ITEM_PAGE_DAGGER | 6})
    write_shadow_u8(0x43D8, 0x5A)             -- BeebLynneAux $3F80 + 278 * 4 (recall[278] byte 0)
    send_key(0xD3) -- SHIFT+S (save & quit) -> prompts Disk Setup on first save
    assert_line("save_disk_setup_prompt", wait_screen("DISK SETUP", 80))
    send_key(0x32) -- 2) Pick save drive
    wait_screen("Save drive (0-3):", 60)
    send_key(0x31) -- '1' (:1 blank save disk)
    wait_screen("Save:    :1", 60)
    send_key(0x33) -- 3) Done
    assert_line("save_disk_init_prompt", wait_screen("Initialize this disk? (Y/N)", 80))
    send_key(0x59) -- 'Y' -> initialize blank Save Disk in :1
    assert_line("save_slot_prompt", wait_screen("Select Slot 1-4", 120))
    send_key(0x31) -- Slot 1
    for _ = 1, 300 do
        wait_frames(15)
        if screen_has("Overwrite?") then send_key(0x59) end
        if screen_has("-more-") or screen_has("saved") then send_key(0x20) end
        if screen_has("N)ew") and screen_has("L)oad") then break end
    end
    assert_line("title_after_save", screen_has("N)ew") and screen_has("L)oad"))
    inv_seed(21, {0xFF, 0, 0, 0, 0, 0, 0, 0}) -- only the load can bring them back
    inv_seed(32, {0xFF, 0, 0, 0, 0, 0, 0, 0})
    inv_seed(33, {0xFF, 0, 0, 0, 0, 0, 0, 0})
    write_shadow_u8(0x43D8, 0x00)
    send_key(0x4C) -- 'L' (load game)
    assert_line("load_slots_shown", wait_screen("Select Slot 1-4", 80))
    send_key(0x31) -- Slot 1
    for _ = 1, 300 do
        wait_frames(15)
        if prog:read_u8(PLAYER_X_ADDR) > 0 and screen_has("Welcome back") then break end
    end
    assert_line("save_load_resumed", prog:read_u8(PLAYER_X_ADDR) > 0)
    assert_line("save_load_secondary_restored",
        inv_field(21, 0) == ITEM_SLOT_STAFF_OF_DARKNESS_L50 and inv_field(21, 2) == 5
        and inv_field(21, 7) == ITEM_PAGE_STAFF_OF_DARKNESS_L50
        and inv_field(32, 0) == ITEM_SLOT_CLOAK and inv_field(32, 5) == 2 and inv_field(32, 6) == 2
        and inv_field(32, 7) == ITEM_PAGE_CLOAK
        and inv_field(33, 0) == ITEM_SLOT_DAGGER and inv_field(33, 3) == 3 and inv_field(33, 4) == 4
        and inv_field(33, 6) == 2 and inv_field(33, 7) == (ITEM_PAGE_DAGGER | 6) and inv_field(31, 0) == 0xFF)
    assert_line("save_load_recall_restored", read_shadow_u8(0x43D8) == 0x5A)
    manager.machine:exit()
end
"""
    elif scenario in ("save_negative", "save_write_negative"):
        ssd_setup_lua = """
    local save_drive = nil
    for _, image in pairs(manager.machine.images) do
        if image.filename == "LEGAL_SAVE_IMAGE" then save_drive = image end
    end
    assert_line("neg_save_drive_found", save_drive ~= nil)
    local function wait_fdc_idle()
        for _ = 1, 600 do
            if (prog:read_u8(0xFE28) & 0x80) == 0 then break end
            emu.wait(1/60)
        end
        wait_frames(8)
    end
    local function read_ssd()
        local f = assert(io.open("LEGAL_SAVE_IMAGE", "rb"))
        local data = f:read("a")
        f:close()
        return data
    end
    local function write_ssd(data)
        local f = assert(io.open("LEGAL_SAVE_IMAGE", "wb"))
        f:write(data)
        f:close()
    end
    local function patch_ssd(patches)
        local f = assert(io.open("LEGAL_SAVE_IMAGE", "r+b"))
        for _, p in ipairs(patches) do
            f:seek("set", p[1])
            f:write(p[2])
        end
        f:flush()
        f:close()
    end
    local function locate_save0()
        local ssd = read_ssd()
        local count8 = ssd:byte(0x105 + 1)
        for i = 0, (count8 // 8) - 1 do
            local off0 = 8 + i * 8 + 1
            local name = ssd:sub(off0, off0 + 6):gsub(" +$", "")
            local dir = ssd:byte(off0 + 7) & 0x7F
            if name == "SAVE0" and dir == 0x24 then
                local off1 = 0x108 + i * 8 + 1
                local b4, b5, b6, b7 = ssd:byte(off1 + 4, off1 + 7)
                local save_len = b4 + b5 * 256 + (((b6 >> 4) & 3) << 16)
                local start_sec = b7 + ((b6 & 3) << 8)
                return ssd, i, save_len, start_sec
            end
        end
        return ssd, nil, 0, 0
    end
    local function make_ssd_image(entries)
        local img = {}
        for i = 1, 800 * 256 do img[i] = 0 end
        local title = "M8SAVE"
        for i = 1, #title do img[i] = title:byte(i) end
        for idx0, e in ipairs(entries) do
            local idx = idx0 - 1
            local dir, name, length, start_sec, payload = e[1], e[2], e[3], e[4], e[5]
            local o0 = 8 + idx * 8
            for i = 1, 7 do img[o0 + i] = (i <= #name) and name:byte(i) or 0x20 end
            img[o0 + 8] = dir
            local o1 = 0x108 + idx * 8
            img[o1 + 5] = length & 0xFF; img[o1 + 6] = (length >> 8) & 0xFF
            local len_hi = (length >> 16) & 3
            local sec_hi = (start_sec >> 8) & 3
            img[o1 + 7] = (3 << 6) | (len_hi << 4) | (3 << 2) | sec_hi
            img[o1 + 8] = start_sec & 0xFF
            if payload then
                for i = 1, #payload do img[start_sec * 256 + i] = payload:byte(i) end
            end
        end
        img[0x105 + 1] = #entries * 8
        img[0x106 + 1] = (3 << 4) | 0x03
        img[0x107 + 1] = 0x20 -- 800 sectors
        local magic = "M8SAVE"
        for i = 1, #magic do img[2 * 256 + i] = magic:byte(i) end
        local chars = {}
        for i = 1, #img do chars[i] = string.char(img[i]) end
        return table.concat(chars)
    end
    local function init_drive1()
        local ok = start_new_game("A")
        assert_line("neg_chargen_town_ready", ok)
        send_key(0xD3) -- SHIFT+S -> Disk Setup
        assert_line("neg_disk_setup_prompt", wait_screen("DISK SETUP", 80))
        send_key(0x32)
        wait_screen("Save drive (0-3):", 60)
        send_key(0x31)
        wait_screen("Save:    :1", 60)
        send_key(0x33)
        assert_line("neg_init_prompt", wait_screen("Initialize this disk? (Y/N)", 80))
        send_key(0x59)
        assert_line("neg_slot_prompt", wait_screen("Select Slot 1-4", 120))
    end
"""
        if scenario == "save_write_negative":
            body = "function run()\n" + ssd_setup_lua + """
    init_drive1()
    wait_fdc_idle()
    save_drive:unload()
    local ssd_blank = read_ssd()
    -- 1. Full DFS .ssd leaving 17 free sectors so OSFIND $80 opens $.SAVE0 and
    --    save_write_map_banked hits Disk full mid-map.
    write_ssd(make_ssd_image({{0x24, "FILLER", 780 * 256, 20}, {0x24, "MORIAID", 6, 2}}))
    assert_line("neg_mount_wr_full", save_drive:load("LEGAL_SAVE_IMAGE") == nil)
    send_key(0x31)
    assert_line("neg_wr_full_rejected", wait_screen("Disk error!", 120) and not screen_has("Game saved!") and not screen_has("N)ew"))
    send_key(0x20)
    for _ = 1, 80 do
        if in_town() then break end
        emu.wait(0.1)
    end
    assert_line("neg_wr_full_recovery", in_town())

    -- 2. Locked $.SAVE0 ($80 dir bit) -> OSFIND $C0 raises DFS BRK ("Locked").
    wait_fdc_idle()
    save_drive:unload()
    write_ssd(make_ssd_image({{0xA4, "SAVE0", 64, 3, "MORIA01" .. string.char(0x22)}, {0x24, "MORIAID", 6, 2}}))
    assert_line("neg_mount_wr_locked", save_drive:load("LEGAL_SAVE_IMAGE") == nil)
    send_key(0xD3)
    assert_line("neg_wr_locked_slots", wait_screen("Select Slot 1-4", 80))
    send_key(0x31)
    assert_line("neg_wr_locked_overwrite", wait_screen("Overwrite?", 80))
    send_key(0x59)
    assert_line("neg_wr_locked_more", wait_screen("-more-", 80))
    send_key(0x20)
    assert_line("neg_wr_locked_rejected", wait_screen("Disk error!", 120) and not screen_has("Game saved!") and not screen_has("N)ew"))
    send_key(0x20)
    for _ = 1, 80 do
        if in_town() then break end
        emu.wait(0.1)
    end
    assert_line("neg_wr_locked_recovery", in_town())

    -- 3. Restore blank initialized :1 and verify clean save write still succeeds.
    wait_fdc_idle()
    save_drive:unload()
    write_ssd(ssd_blank)
    assert_line("neg_mount_wr_valid", save_drive:load("LEGAL_SAVE_IMAGE") == nil)
    send_key(0xD3)
    assert_line("neg_wr_valid_slots", wait_screen("Select Slot 1-4", 80))
    send_key(0x31)
    for _ = 1, 300 do
        wait_frames(15)
        if screen_has("Overwrite?") then send_key(0x59) end
        if screen_has("-more-") or screen_has("saved") then send_key(0x20) end
        if screen_has("N)ew") and screen_has("L)oad") then break end
    end
    assert_line("neg_title_after_save", screen_has("N)ew") and screen_has("L)oad"))
    wait_fdc_idle()
    save_drive:unload()
    local _, found_idx, save_len, start_sec = locate_save0()
    local ssd_after = read_ssd()
    local hdr_off = start_sec * 256
    assert_line("neg_save0_v22_located", found_idx ~= nil and ssd_after:byte(hdr_off + 7 + 1) == 0x22 and save_len > 1000)
    manager.machine:exit()
end
"""
        else:
            body = "function run()\n" + ssd_setup_lua + """
    init_drive1()
    send_key(0x31)
    for _ = 1, 300 do
        wait_frames(15)
        if screen_has("Overwrite?") then send_key(0x59) end
        if screen_has("-more-") or screen_has("saved") then send_key(0x20) end
        if screen_has("N)ew") and screen_has("L)oad") then break end
    end
    assert_line("neg_title_after_save", screen_has("N)ew") and screen_has("L)oad"))

    wait_fdc_idle()
    save_drive:unload()
    local ssd, found_idx, save_len, start_sec = locate_save0()
    local hdr_off = start_sec * 256
    local orig_ver = ssd:byte(hdr_off + 7 + 1)
    local orig_tail = ssd:byte(hdr_off + save_len)
    local sec1_off = 0x108 + (found_idx or 0) * 8
    local orig_l4, orig_l5, orig_l6 = ssd:byte(sec1_off + 4 + 1, sec1_off + 6 + 1)
    assert_line("neg_save0_v22_located", found_idx ~= nil and orig_ver == 0x22 and save_len > 1000)

    -- 2. Wrong Save version ($21 -> Unsupported save.)
    patch_ssd({{hdr_off + 7, string.char(0x21)}})
    assert_line("neg_mount_v21", save_drive:load("LEGAL_SAVE_IMAGE") == nil)
    send_key(0x4C)
    assert_line("neg_v21_slots", wait_screen("Select Slot 1-4", 80))
    send_key(0x31)
    assert_line("neg_v21_rejected", wait_screen("Unsupported save.", 100) and not in_town())
    send_key(0x20)
    assert_line("neg_v21_title_recovery", wait_screen("N)ew", 80) and screen_has("L)oad"))

    -- 3. Corrupt checksum at exact full file size (Save file corrupt!)
    wait_fdc_idle()
    save_drive:unload()
    patch_ssd({
        {hdr_off + 7, string.char(0x22)},
        {hdr_off + save_len - 1, string.char(orig_tail ~ 0xFF)},
    })
    assert_line("neg_mount_cksum", save_drive:load("LEGAL_SAVE_IMAGE") == nil)
    send_key(0x4C)
    assert_line("neg_cksum_slots", wait_screen("Select Slot 1-4", 80))
    send_key(0x31)
    assert_line("neg_cksum_rejected", wait_screen("Save file corrupt!", 120) and not in_town())
    send_key(0x20)
    assert_line("neg_cksum_title_recovery", wait_screen("N)ew", 80) and screen_has("L)oad"))

    -- 4. Truncated Save V2 ($22 header intact, DFS EOF at 64 bytes -> Save file corrupt!)
    wait_fdc_idle()
    save_drive:unload()
    patch_ssd({
        {hdr_off + save_len - 1, string.char(orig_tail)},
        {sec1_off + 4, string.char(0x40, 0x00, orig_l6 & 0xCF)},
    })
    assert_line("neg_mount_trunc", save_drive:load("LEGAL_SAVE_IMAGE") == nil)
    send_key(0x4C)
    assert_line("neg_trunc_slots", wait_screen("Select Slot 1-4", 80))
    send_key(0x31)
    assert_line("neg_trunc_rejected", wait_screen("Save file corrupt!", 100) and not in_town())
    send_key(0x20)
    assert_line("neg_trunc_title_recovery", wait_screen("N)ew", 80) and screen_has("L)oad"))

    -- 5. Restore valid Save V2 metadata and prove clean subsequent load succeeds
    wait_fdc_idle()
    save_drive:unload()
    patch_ssd({{sec1_off + 4, string.char(orig_l4, orig_l5, orig_l6)}})
    assert_line("neg_mount_valid", save_drive:load("LEGAL_SAVE_IMAGE") == nil)
    send_key(0x4C)
    assert_line("neg_valid_slots", wait_screen("Select Slot 1-4", 80))
    send_key(0x31)
    for _ = 1, 300 do
        wait_frames(15)
        if prog:read_u8(PLAYER_X_ADDR) > 0 and screen_has("Welcome back") then break end
    end
    assert_line("neg_valid_reload_ok", prog:read_u8(PLAYER_X_ADDR) > 0 and in_town())
    manager.machine:exit()
end
"""
    elif scenario == "chargen_town":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    -- A level-1 character's max HP is its race's and class's hit dice
    -- (player_calc_hp). 2026-11-16: every BBC character since 708f3df had
    -- 135: the OVL.UI swap behind player_con_hp_adj reloaded the start
    -- overlay, and beeb_overlay_try_cache left its name pointer's low byte
    -- ($87) in the zp_temp0 player_calc_hp kept the hit dice in.
    local race = prog:read_u8(PLAYER_DATA_ADDR + PL_RACE)
    local class = prog:read_u8(PLAYER_DATA_ADDR + PL_CLASS)
    local hit_dice = prog:read_u8(RACE_PROPS_ADDR + race * RACE_PROP_SIZE)
        + prog:read_u8(CLASS_PROPS_ADDR + class * CLASS_PROP_SIZE)
    local mhp = prog:read_u8(PLAYER_DATA_ADDR + PL_MHP_LO) + 256 * prog:read_u8(PLAYER_DATA_ADDR + PL_MHP_LO + 1)
    print(string.format("chargen max HP %d, hit dice %d", mhp, hit_dice))
    assert_line("chargen_max_hp_is_hit_dice", mhp == hit_dice)
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
    -- DL1's creatures come from the monster catalog (Bank 6): the first
    -- live monster's species slot holds a catalog id (2026-11-05; the tier
    -- era checked MONDB1 had loaded, after a disk without it named every
    -- creature "?").
    local species = false
    for i = 0, 31 do
        local t = prog:read_u8(MONSTER_TABLE_ADDR + i * 12 + 2)
        if t < 32 then species = prog:read_u8(CAT_SLOT_ID_HI_ADDR + t) ~= 0xFF break end
    end
    assert_line("catalog_species_loaded", species)
    -- Hurt, Ctrl+R auto-rests for many turns: the held-key probe's flags
    -- once cancelled it at once (M6 playtest, input_run_key_held). DL1 is
    -- the boot's random level, and a creature in view would end the rest:
    -- none is left to.
    clear_monsters()
    prog:write_u8(PLAYER_HP_ADDR, 1)
    prog:write_u8(PLAYER_HP_ADDR + 1, 0)
    local t0 = prog:read_u8(TURN_ADDR) | (prog:read_u8(TURN_ADDR + 1) << 8)
    send_key(0x12) -- Ctrl+R
    wait_frames(60)
    local t1 = prog:read_u8(TURN_ADDR) | (prog:read_u8(TURN_ADDR + 1) << 8)
    print("auto-rest turns: " .. ((t1 - t0) & 0xFFFF))
    assert_line("auto_rest_keeps_resting", ((t1 - t0) & 0xFFFF) >= 3)
    -- Wave 5.2 cold evictions: S4 ('?' drop in OVL_HELP), S3 (locked door pick
    -- swapping OVL_HELP -> OVL_CHEST -> OVL_HELP), and S2a+S2b (acid trap at X=1
    -- preserving X across tramp_trap_trigger and OVL_CHEST across tramp_item_recalc).
    write_play_u8(AUTO_REST_ACTIVE_ADDR, 0)
    prog:write_u8(PLAYER_DATA_ADDR + PL_FLAGS, prog:read_u8(PLAYER_DATA_ADDR + PL_FLAGS) & (~PLF_RESTING & 0xFF))
    prog:write_u8(PLAYER_HP_ADDR, 60)
    wait_frames(10)
    local px, py = prog:read_u8(PLAYER_X_ADDR), prog:read_u8(PLAYER_Y_ADDR)
    if px >= MAP_COLS - 2 then px = px - 2; prog:write_u8(PLAYER_X_ADDR, px) end
    write_map_u8(px, py, 0x00)
    send_key(0x44) -- 'D' (drop)
    assert_line("drop_prompt", wait_screen("Drop which item", 80))
    send_key(0x3F) -- '?' inventory list
    assert_line("drop_inv_list", wait_screen("Inventory", 80))
    send_key(0x41) -- 'A'
    assert_line("drop_completed", wait_screen("You drop", 80))
    wait_frames(20)
    drain_more(2)
    write_map_u8(px + 1, py, 0x80) -- TILE_DOOR_CLOSED
    prog:write_u8(DOOR_STATE_COUNT_ADDR, 1)
    prog:write_u8(DOOR_STATE_X_ADDR, px + 1)
    prog:write_u8(DOOR_STATE_Y_ADDR, py)
    prog:write_u8(DOOR_STATE_VAL_ADDR, 20)
    local turn_d = prog:read_u8(TURN_ADDR)
    send_key(0x4F) -- 'O' (open door)
    assert_line("door_open_dir", wait_screen("Direction?", 80))
    send_key(0x4C) -- 'L' (east)
    local saw_lock = wait_screen("lock.", 120)
    drain_more(2)
    assert_line("door_pick_returned", saw_lock and prog:read_u8(TURN_ADDR) ~= turn_d)
    prog:write_u8(DOOR_STATE_COUNT_ADDR, 0)
    write_map_u8(px + 1, py, 0x00) -- bare TILE_FLOOR
    prog:write_u8(TRAP_COUNT_ADDR, 2)
    prog:write_u8(TRAP_X_ADDR + 0, 0)
    prog:write_u8(TRAP_Y_ADDR + 0, 0)
    prog:write_u8(TRAP_TYPE_ADDR + 0, 0)
    prog:write_u8(TRAP_X_ADDR + 1, px + 1)
    prog:write_u8(TRAP_Y_ADDR + 1, py)
    prog:write_u8(TRAP_TYPE_ADDR + 1, 11) -- TRAP_ACID at index X=1
    send_key(0x4C) -- 'L': step onto acid trap
    wait_frames(40)
    drain_more(4)
    assert_line("acid_trap_triggered", prog:read_u8(PLAYER_X_ADDR) == px + 1
        and (read_map_u8(px + 1, py) & 0xF0) == 0xE0)
    local turn_t = prog:read_u8(TURN_ADDR)
    send_key(0x53) -- 'S' (search): play continues cleanly after trap
    wait_frames(40)
    assert_line("acid_trap_play_continues", prog:read_u8(TURN_ADDR) ~= turn_t)
    -- Regression: after an uncached overlay (OVL_CHEST = 10), consecutive '.'
    -- run commands must copy OVL_MODAL_MISC (9) from SWR Bank 5 once and never
    -- hit beeb_dfs_load_to_bank to reload the stale uncached current_overlay.
    assert_line("pre_run_uncached_ovl", prog:read_u8(CURRENT_OVL) == 10)
    local rx = math.max(2, math.min(MAP_COLS - 6, px + 1))
    local ry = math.max(2, math.min(MAP_ROWS - 3, py))
    prog:write_u8(PLAYER_X_ADDR, rx)
    prog:write_u8(PLAYER_Y_ADDR, ry)
    prog:write_u8(TRAP_COUNT_ADDR, 0)
    prog:write_u8(FLOOR_ITEM_COUNT_ADDR, 0)
    prog:write_u8(MON_COUNT_ADDR, 0)
    write_map_u8(rx - 1, ry, 0x10) -- TILE_WALL_H stops the return west run at rx
    write_map_u8(rx, ry, 0x00)
    write_map_u8(rx + 1, ry, 0x00)
    write_map_u8(rx + 2, ry, 0x00)
    write_map_u8(rx + 3, ry, 0x00)
    write_map_u8(rx + 4, ry, 0x10) -- TILE_WALL_H stops the east run at rx + 3
    for dy = -1, 1, 2 do
        for dx = -1, 4 do write_map_u8(rx + dx, ry + dy, 0x10) end
    end
    prog:write_u8(BEEB_DFS_LOAD_TO_BANK_ADDR, 0x38)     -- SEC (any DFS load prompts & stalls)
    prog:write_u8(BEEB_DFS_LOAD_TO_BANK_ADDR + 1, 0x60) -- RTS
    send_key(0x2E) -- '.' (run)
    send_key(0x4C) -- 'L' (east: rx -> rx + 3)
    wait_frames(60)
    assert_line("run_east_zero_dfs", prog:read_u8(PLAYER_X_ADDR) == rx + 3
        and prog:read_u8(CURRENT_OVL) == 9)
    send_key(0x2E) -- '.' (consecutive run)
    send_key(0x48) -- 'H' (west: rx + 3 -> rx)
    wait_frames(60)
    assert_line("run_west_zero_dfs", prog:read_u8(PLAYER_X_ADDR) == rx
        and prog:read_u8(CURRENT_OVL) == 9)
    manager.machine:exit()
end
"""
    elif scenario == "help_overlay":
        body = """
function run()
    io.stdout:setvbuf("no")
    assert_line("legal_title_ready", wait_title())
    local game_drive = nil
    for _, image in pairs(manager.machine.images) do
        if image.filename == "LEGAL_GAME_IMAGE" then game_drive = image end
        if image.filename == "LEGAL_SAVE_IMAGE" then image:unload() end
    end
    assert_line("legal_game_drive", game_drive ~= nil)
    local function legal_mount(path)
        -- DFS retains its catalogue while the drive is active. Model a
        -- physical disk change only after the drive indicator turns off.
        for _ = 1, 600 do
            if (prog:read_u8(0xfe28) & 0x80) == 0 then return game_drive:load(path) end
            emu.wait(1/60)
        end
        return "drive did not become idle"
    end
    assert_line("legal_mount_save", legal_mount("LEGAL_SAVE_IMAGE") == nil)
    send_key(0x41)
    local prompted = wait_screen("Insert program disk", 100)
    assert_line("legal_load_prompt", prompted)
    if not prompted then
        print(string.format("DIAG legal pc=%04x romsel=%02x ovl=%02x", cpu.state["PC"].value,
            prog:read_u8(0xf4), prog:read_u8(CURRENT_OVL)))
        manager.machine:exit()
        return
    end
    send_key(0x1B)
    assert_line("legal_load_cancel", wait_screen("N)ew", 100))
    send_key(0x41) -- Successful retry must retain the same caller snapshot.
    assert_line("legal_title_retry_prompt", wait_screen("Insert program disk", 100))
    local title_saved = {}
    for i = 0, 141 do title_saved[i] = prog:read_u8(LEGAL_SAVE_ADDR + i) end
    assert_line("legal_restore_program", legal_mount("LEGAL_GAME_IMAGE") == nil)
    send_key(0x20)
    assert_line("legal_title_entry", wait_screen("License & Source", 100))
    local title_stable = true
    for i = 0, 141 do
        if i ~= 0x17 and title_saved[i] ~= prog:read_u8(LEGAL_SAVE_ADDR + i) then title_stable = false end
    end
    assert_line("legal_successful_retry_snapshot", title_stable)
    send_key(0x51)
    assert_line("legal_title_return", wait_title())
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    send_key(0x3F) -- '?' (help)
    assert_line("help_opened", wait_screen("Command Reference", 80))
    assert_line("help_license_hint", screen_has("L:License"))
    send_key(0x20)
    assert_line("help_license_entry", wait_screen("L License / Source", 80))
    assert_line("legal_help_mount_save", legal_mount("LEGAL_SAVE_IMAGE") == nil)
    send_key(0x4C)
    assert_line("legal_help_load_prompt", wait_screen("Insert program disk", 100))
    local saved = {}
    for i = 0, 141 do saved[i] = prog:read_u8(LEGAL_SAVE_ADDR + i) end
    send_key(0x20) -- Retry while the program disk remains unavailable.
    assert_line("legal_retry_prompt", wait_screen("Insert program disk", 100))
    local stable = true
    for i = 0, 141 do
        if i ~= 0x17 and saved[i] ~= prog:read_u8(LEGAL_SAVE_ADDR + i) then stable = false end
    end
    assert_line("legal_retry_snapshot", stable)
    local checked, restored = false, true
    local cpu = manager.machine.devices[":maincpu"]
    local cancel_tap = prog:install_write_tap(2, 2, "legal_cancel_zp",
        function(offset, data, mask)
            local pc = cpu.state["PC"].value
            if checked or pc < LEGAL_CANCEL_START or pc >= LEGAL_CANCEL_END then return end
            checked = true
            -- Write taps run before the store; all other bytes are restored.
            for i = 0, 141 do
                if i ~= 0x17 and (i < 0x6a or i > 0x6c) then
                    local actual = (i == 0) and data or prog:read_u8(2 + i)
                    if actual ~= saved[i] then restored = false end
                end
            end
        end)
    send_key(0x1B)
    for _ = 1, 100 do
        if in_town() then break end
        emu.wait(0.1)
    end
    cancel_tap:remove()
    assert_line("legal_help_cancel_gameplay", in_town())
    assert_line("legal_cancel_zp", checked and restored)
    assert_line("legal_help_restore_program", legal_mount("LEGAL_GAME_IMAGE") == nil)
    send_key(0x3F)
    assert_line("help_reopened", wait_screen("Command Reference", 80))
    send_key(0x4C) -- 'L'
    assert_line("legal_menu", wait_screen("License & Source", 100))
    local notice_first = prog:read_u8(LEGAL_NOTICE_ADDR)
    prog:write_u8(LEGAL_NOTICE_ADDR, 0x58) -- request a file absent from this disk
    send_key(0x31)
    assert_line("legal_missing", wait_screen("Document read failed", 100))
    send_key(0x20)
    assert_line("legal_missing_return", wait_screen("1 License", 60))
    assert_line("legal_channel_closed", prog:read_u8(LEGAL_OPENED_ADDR) == 0)
    prog:write_u8(LEGAL_NOTICE_ADDR, notice_first)
    send_key(0x31)
    assert_line("legal_notice", wait_screen("MORIA8 LICENSE NOTICE", 100))
    send_key(0x52) -- restart
    assert_line("legal_restart", wait_screen("MORIA8 LICENSE NOTICE", 100))
    send_key(0x51)
    assert_line("legal_menu_again", wait_screen("1 License", 60))
    send_key(0x32)
    assert_line("legal_offer", wait_screen("MORIA8 SOURCE OFFER", 100))
    send_key(0x51)
    assert_line("legal_menu_final", wait_screen("1 License", 60))
    send_key(0x33) -- '3' System Info
    assert_line("legal_sysinfo_menu", wait_screen("Moria 8 - System Info", 100))
    send_key(0x51) -- 'Q'
    assert_line("legal_sysinfo_menu_back", wait_screen("1 License", 60))
    send_key(0x51)
    assert_line("legal_help_return", wait_screen("Command Reference", 100))
    send_key(0x51) -- 'Q'
    wait_frames(40)
    assert_line("help_closed", in_town())
    send_key(0x56) -- 'V' System Info
    assert_line("gameplay_sysinfo", wait_screen("Moria 8 - System Info", 100) and wait_screen("RNG:", 40) and screen_has("Turn 0  Town"))
    send_key(0x51) -- 'Q'
    wait_frames(40)
    assert_line("gameplay_sysinfo_close", in_town())
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
    -- Real keys through MOS: SHIFT+Q, Q let go with SHIFT still down, then a
    -- Y meanwhile (a shifted Y, which would say no). The prompt waits for
    -- SHIFT too, so the Y does not answer.
    local keys = manager.machine.ioport.ports
    local shift = keys[":kbd:COL0"].fields["SHIFT"]
    local q = keys[":kbd:COL0"].fields["q  Q"]
    local y = keys[":kbd:COL4"].fields["y  Y"]
    shift:set_value(1)
    q:set_value(1)
    wait_frames(6)
    q:set_value(0)
    wait_frames(6)
    y:set_value(1)
    wait_frames(6)
    y:set_value(0)
    wait_frames(6)
    shift:set_value(0)
    assert_line("shift_prompt_shown", wait_screen("Do you really want to quit?", 80))
    wait_frames(150)
    assert_line("shift_held_y_ignored", screen_has("Do you really want to quit?") and in_town())
    send_key(0x4E) -- 'N'
    wait_frames(40)
    assert_line("shift_declined", in_town() and not screen_has("Do you really want to quit?"))
    manager.machine:exit()
end
"""
    elif scenario == "item_actions":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    -- The Huffman corpus in ANDY survives the MOS mode change, whose VDU
    -- workspace (ECF patterns) is $8800-$882F (screen_init, 2026-11-06).
    local rom = prog:read_u8(0x00F4)
    prog:write_u8(0xFE30, 0x84)
    local intact = true
    for i, b in ipairs(ANDY_MOS_BYTES) do
        if prog:read_u8(0x8800 + i - 1) ~= b then intact = false end
    end
    prog:write_u8(0xFE30, rom)
    assert_line("andy_corpus_intact", intact)
    prog:write_u8(PLAYER_DATA_ADDR + 24, 14)   -- PL_DEX_BASE
    prog:write_u8(PLAYER_DATA_ADDR + 30, 14)   -- PL_DEX_CUR
    prog:write_u8(PLAYER_DATA_ADDR + 26, 13)   -- PL_CHR_BASE
    prog:write_u8(PLAYER_DATA_ADDR + 32, 13)   -- PL_CHR_CUR
    assert_line("wizard_open", wizard_menu_open())
    press_until("ITEM", 0x47) -- 'G'
    send_int(ITEM_POTION_OF_GAIN_DEXTERITY)
    assert_line("wizard_gain_ok", wait_screen("OK", 60))
    send_key(0x51) -- 'Q' (quaff)
    assert_line("quaff_prompt", wait_screen("Quaff which potion", 80))
    send_key(0x41) -- 'A'
    assert_line("quaff_gain_dex", wait_screen("more limber!", 80) and prog:read_u8(PLAYER_DATA_ADDR + 30) == 15)
    drain_more(4)
    wait_frames(30)

    inv_seed(0, {ITEM_SLOT_POTION_OF_CHARISMA, 1, 0, 0, 0, 0, 0, ITEM_PAGE_POTION_OF_CHARISMA})
    send_key(0x51) -- 'Q'
    assert_line("quaff_chr_prompt", wait_screen("Quaff which potion", 80))
    send_key(0x41) -- 'A'
    assert_line("quaff_gain_chr", wait_screen("ain't you cute!", 80) and prog:read_u8(PLAYER_DATA_ADDR + 32) == 14)
    drain_more(4)
    wait_frames(30)

    prog:write_u8(PLAYER_HP_ADDR, 1)
    prog:write_u8(PLAYER_DATA_ADDR + 33, 1)
    prog:write_u8(POISON_ADDR, 5)
    inv_seed(0, {ITEM_SLOT_POTION_OF_CURE_CRITICAL_WOUNDS, 1, 0, 0, 0, 0, 0, ITEM_PAGE_POTION_OF_CURE_CRITICAL_WOUNDS})
    send_key(0x51) -- 'Q'
    assert_line("quaff_ccw_prompt", wait_screen("Quaff which potion", 80))
    send_key(0x41) -- 'A'
    local ccw_msg = wait_screen("You feel better.", 80 * DFS_SLACK)
    drain_more(4)
    wait_frames(60)
    drain_more(4)
    assert_line("quaff_ccw", ccw_msg and prog:read_u8(PLAYER_HP_ADDR) > 1 and prog:read_u8(POISON_ADDR) == 0)

    prog:write_u8(POISON_ADDR, 5)
    inv_seed(0, {ITEM_SLOT_POTION_OF_NEUTRALIZE_POISON, 1, 0, 0, 0, 0, 0, ITEM_PAGE_POTION_OF_NEUTRALIZE_POISON})
    send_key(0x51) -- 'Q'
    assert_line("quaff_neut_prompt", wait_screen("Quaff which potion", 80))
    send_key(0x41) -- 'A'
    assert_line("quaff_neutralize", wait_screen("You feel better.", 80) and prog:read_u8(POISON_ADDR) == 0)
    drain_more(4)
    wait_frames(30)

    -- Restore Intelligence (eff_item_extended.s ee_op_restore !eer_single):
    -- player_calc_stats swaps overlays on BBC Master and reloads OVL.HOME/OVL.SPELL,
    -- which wiped eff_ext_tmp to 0 (STAT_STR) before the hardware-stack fix.
    prog:write_u8(PLAYER_DATA_ADDR + 21, 16)   -- PL_STR_BASE
    prog:write_u8(PLAYER_DATA_ADDR + 27, 10)   -- PL_STR_CUR (drained)
    prog:write_u8(PLAYER_DATA_ADDR + 22, 16)   -- PL_INT_BASE
    prog:write_u8(PLAYER_DATA_ADDR + 28, 10)   -- PL_INT_CUR (drained)
    inv_seed(0, {ITEM_SLOT_POTION_OF_RESTORE_INTELLIGENCE, 1, 0, 0, 0, 0, 0, ITEM_PAGE_POTION_OF_RESTORE_INTELLIGENCE})
    send_key(0x51) -- 'Q'
    assert_line("quaff_rest_int_prompt", wait_screen("Quaff which potion", 80))
    send_key(0x41) -- 'A'
    local rest_msg = wait_screen("You feel your strength return.", 160)
    drain_more(4)
    wait_frames(60)
    drain_more(4)
    assert_line("quaff_restore_int_only",
        rest_msg and prog:read_u8(PLAYER_DATA_ADDR + 28) == 16 and prog:read_u8(PLAYER_DATA_ADDR + 27) == 10)
    -- SHIFT+X ($D8): a cursed primary is refused with no turn; uncursed, the
    -- swap takes one turn and reports both slots (VMS switch_weapon).
    drain_more(4)
    wait_frames(60)                          -- the quaff's own turn ends first
    inv_seed(22, {ITEM_SLOT_MACE, 1, 0, 1, 0, 0, 3, ITEM_PAGE_MACE})
    inv_seed(33, {ITEM_SLOT_DAGGER, 1, 0, 3, 4, 0, 2, ITEM_PAGE_DAGGER | 6})
    local turn0 = prog:read_u8(TURN_ADDR)
    send_key(0xD8)
    assert_line("exchange_cursed_refused",
        wait_screen("You cannot remove it, it is cursed!", 60)
        and inv_field(22, 0) == ITEM_SLOT_MACE and (inv_field(22, 7) & ITEM_PAGE_BIT) == ITEM_PAGE_MACE
        and inv_field(33, 0) == ITEM_SLOT_DAGGER and (inv_field(33, 7) & ITEM_PAGE_BIT) == ITEM_PAGE_DAGGER
        and prog:read_u8(TURN_ADDR) == turn0)
    prog:write_u8(INV_ITEM_ID_ADDR + 6 * INV_STRIDE + 22, 2) -- lift the curse
    send_key(0xD8)
    assert_line("exchange_report",
        wait_screen("Secondary: Mace (+1,+0)", 60)
        and screen_has("Primary: Dagger (Defender) (+3,+4)"))
    wait_frames(20)
    assert_line("exchange_swapped",
        inv_field(22, 0) == ITEM_SLOT_DAGGER and inv_field(22, 3) == 3 and inv_field(22, 7) == (ITEM_PAGE_DAGGER | 6)
        and inv_field(33, 0) == ITEM_SLOT_MACE and inv_field(33, 3) == 1 and inv_field(33, 6) == 2
        and inv_field(33, 7) == ITEM_PAGE_MACE
        and inv_field(32, 0) == 0xFF and inv_field(31, 0) == 0xFF)
    assert_line("exchange_one_turn", prog:read_u8(TURN_ADDR) == (turn0 + 1) % 256)
    -- A Wand of Stinking Cloud aimed at nothing: the Phase 3 router runs it
    -- in the death overlay and must return to the resident caller with no
    -- OVL.ITEMS load first (2026-11-06: the build queue's panic, the load
    -- evicting the router before its rts). The game goes on: a search takes
    -- its turn.
    drain_more(4)
    inv_seed(0, {ITEM_SLOT_WAND_OF_STINKING_CLOUD, 1, 5, 0, 0, 0, 0, ITEM_PAGE_WAND_OF_STINKING_CLOUD})
    send_key(0x41) -- 'A' (aim)
    assert_line("aim_prompt", wait_screen("Aim which wand", 80))
    send_key(0x41) -- 'A'
    assert_line("aim_direction", wait_screen("Direction?", 80))
    send_key(0x4C) -- 'L'
    wait_frames(30)
    drain_more(1)                            -- "Direction? -more-"
    -- Missed, or a townsperson was in its path: either way the wand worked.
    local cloud = false
    for _ = 1, 80 * DFS_SLACK do
        if screen_has("The cloud dissipates.") or screen_has("looks confused") then
            cloud = true break
        end
        emu.wait(0.1)
    end
    if not cloud then
        for r = 0, 3 do print("DIAG row " .. r .. ": " .. rowtext(r)) end
    end
    assert_line("cloud_dissipates", cloud)
    drain_more(4)
    local turn1 = prog:read_u8(TURN_ADDR)
    send_key(0x53) -- 'S' (search)
    wait_frames(60)
    assert_line("play_goes_on", in_town() and prog:read_u8(TURN_ADDR) ~= turn1)
    -- The VMS Wands of Fire Bolts and Drain Life, MON-031: the
    -- death overlay's router runs them in OVL.SPELL through
    -- irs_re_compact_call. Aimed at nothing, each takes its turn (a charge
    -- spent) and play goes on.
    clear_monsters()
    for _, w in ipairs({
        {ITEM_WAND_OF_FIRE_BOLTS, ITEM_SLOT_WAND_OF_FIRE_BOLTS, ITEM_PAGE_WAND_OF_FIRE_BOLTS},
        {ITEM_WAND_OF_DRAIN_LIFE, ITEM_SLOT_WAND_OF_DRAIN_LIFE, ITEM_PAGE_WAND_OF_DRAIN_LIFE},
    }) do
        local id, slot_lo, page_bit = w[1], w[2], w[3]
        drain_more(4)
        inv_seed(0, {slot_lo, 1, 5, 0, 0, 0, 0, page_bit})
        local turn_w = prog:read_u8(TURN_ADDR)
        send_key(0x41) -- 'A' (aim)
        assert_line("aim_prompt_" .. id, wait_screen("Aim which wand", 80))
        send_key(0x41) -- 'A'
        assert_line("aim_direction_" .. id, wait_screen("Direction?", 80))
        send_key(0x4C) -- 'L'
        for _ = 1, 400 * DFS_SLACK do
            if screen_has("-more-") or (in_town() and prog:read_u8(TURN_ADDR) ~= turn_w) then break end
            emu.wait(1/60)
        end
        drain_more(4)
        for _ = 1, 400 * DFS_SLACK do
            if in_town() and prog:read_u8(TURN_ADDR) ~= turn_w then break end
            if screen_has("-more-") then drain_more(2) else emu.wait(1/60) end
        end
        assert_line("wand_returns_" .. id, in_town() and prog:read_u8(TURN_ADDR) ~= turn_w
            and inv_field(0, 2) == 4)
    end
    -- A Scroll of Recharging on an empty wand, through the '?' list: the
    -- spell overlay's picker returns the slot in X, which the trampoline's
    -- OVL.SPELL reload clobbered, so another slot was recharged, named or
    -- "eaten", or a stale ego swapped OVL.ITEMS in under the spell overlay
    -- and the BRK panic hung the game (BBC build queue, 2026-11-12).
    drain_more(4)
    inv_seed(0, {ITEM_SLOT_WAND_OF_LIGHTNING, 1, 0, 0, 0, 0, 0, ITEM_PAGE_WAND_OF_LIGHTNING})
    inv_seed(1, {ITEM_SLOT_SCROLL_OF_RECHARGING, 1, 0, 0, 0, 0, 0, ITEM_PAGE_SCROLL_OF_RECHARGING})
    local turn_r = prog:read_u8(TURN_ADDR)
    send_key(0x52) -- 'R' (read)
    assert_line("recharge_read_prompt", wait_screen("Read which scroll", 80))
    send_key(0x41) -- 'A'
    assert_line("recharge_prompt", wait_screen("Recharge which item", 80))
    send_key(0x3F) -- '?': the list
    wait_frames(30)
    send_key(0x41) -- 'A': the wand
    local glows = wait_screen("glows briefly", 80)
    if not glows then
        for r = 0, 3 do print("DIAG row " .. r .. ": " .. rowtext(r)) end
    end
    assert_line("recharge_glows", glows)
    drain_more(4)
    assert_line("recharge_charged", inv_field(0, 0) == ITEM_SLOT_WAND_OF_LIGHTNING
        and (inv_field(0, 7) & ITEM_PAGE_BIT) == ITEM_PAGE_WAND_OF_LIGHTNING
        and inv_field(0, 2) > 0)
    send_key(0x53) -- 'S' (search)
    wait_frames(60)
    assert_line("recharge_play_goes_on", in_town() and prog:read_u8(TURN_ADDR) ~= turn_r)
    -- A Scroll of Genocide reads its letter through recall_key_to_screen_code,
    -- which lived in the recall view's overlay: with SPELL loaded the call ran
    -- SPELL's bytes there, a stray store into the play slot that hung a later
    -- level-up (2026-11-07). The letter must reach recall_query_sc.
    drain_more(4)
    prog:write_u8(RECALL_QUERY_SC_ADDR, 0)
    inv_seed(1, {ITEM_SLOT_SCROLL_OF_GENOCIDE, 1, 0, 0, 0, 0, 0, ITEM_PAGE_SCROLL_OF_GENOCIDE})
    send_key(0x52) -- 'R' (read)
    assert_line("genocide_read_prompt", wait_screen("Read which scroll", 80))
    send_key(0x41) -- 'A'
    assert_line("genocide_type_prompt", wait_screen("Type?", 80))
    send_key(0x4A) -- 'J'
    wait_frames(60)
    assert_line("genocide_letter_read", prog:read_u8(RECALL_QUERY_SC_ADDR) == 0x0A)
    -- A Scroll of Identify asks which item (2026-11-06: the BBC build
    -- queue's two Identify reads showed a blank prompt).
    drain_more(4)
    inv_seed(1, {ITEM_SLOT_SCROLL_OF_IDENTIFY, 1, 0, 0, 0, 0, 0, ITEM_PAGE_SCROLL_OF_IDENTIFY})
    send_key(0x52) -- 'R' (read)
    assert_line("read_prompt", wait_screen("Read which scroll", 80))
    send_key(0x41) -- 'A'
    local identify = wait_screen("Identify which item", 80)
    assert_line("identify_prompt", identify)
    send_key(0x1B) -- ESC: no item
    -- A store buy: the town overlay's copy of the weight-limit body
    -- (inv_add_carried) had no rts and ran past the overlay's end into stale
    -- bytes, a BRK in the stat labels: every BBC build-queue run's first buy
    -- panicked with "P43" (2026-11-15). The Weaponsmith's door is (39, 6).
    -- (OVL.HOME's and OVL.ITEMS's copies lacked it too; the items one ran
    -- into player_adjust_equipment_stat, which returns at once for a pack
    -- slot.)
    drain_more(4)
    wait_frames(30)
    local function pack_count()
        local n = 0
        for slot = 0, 21 do if inv_field(slot, 0) ~= 0xFF then n = n + 1 end end
        return n
    end
    for slot = 0, 21 do inv_seed(slot, {0xFF, 0, 0, 0, 0, 0, 0, 0}) end
    prog:write_u8(PLAYER_DATA_ADDR + 43, 0x50)   -- PL_GOLD: 50,000
    prog:write_u8(PLAYER_DATA_ADDR + 44, 0xC3)
    prog:write_u8(PLAYER_DATA_ADDR + 45, 0x00)
    prog:write_u8(PLAYER_X_ADDR, 39)
    prog:write_u8(PLAYER_Y_ADDR, 7)
    send_key(0x4B) -- 'K': north, onto the door
    assert_line("store_entered", wait_screen("B)uy", 200))
    -- BRKs past the town overlay's end in the Bank 4 window: a body that
    -- runs past it panics there, not on whatever stale bytes are left.
    assert_line("store_window_banked", can_read_shadow())
    for a = OVL_TOWN_END_ADDR, 0xBFFF do prog:write_u8(a, 0x00) end
    send_key(0x42) -- 'B'
    assert_line("buy_prompt", wait_screen("Buy which item", 80))
    send_key(0x41) -- 'A'
    -- The first item depends on the seed: a dear one is haggled over ("Your
    -- offer?"), a cheap one sold at its price ("Buy? (Y/N)"); the Apple IIe's
    -- 2 gp Iron Shot failed the offer-only step (2026-11-16).
    local offer, fixed = false, false
    for _ = 1, 80 * DFS_SLACK do
        if screen_has("Your offer?") then offer = true break end
        if screen_has("Buy? (Y/N)") then fixed = true break end
        emu.wait(0.1)
    end
    assert_line("buy_asks", offer or fixed)
    local ask = nil
    for r = 0, 23 do
        local n = rowtext(r):match("Asks (%d+) gp") or rowtext(r):match("Price: (%d+) gp")
        if n then ask = n end
    end
    assert_line("buy_ask_read", ask ~= nil)
    if offer then
        for i = 1, #(ask or "") do send_key(ask:byte(i)) end
        send_key(0x0D)
    else
        send_key(0x59) -- 'Y'
    end
    local bought = false
    for _ = 1, 100 * DFS_SLACK do
        if pack_count() == 1 and screen_has("B)uy") and screen_has("Gold: " .. (50000 - tonumber(ask or 0))) then
            bought = true break
        end
        emu.wait(0.1)
    end
    if not bought then
        print(string.format("DIAG pc %04X romsel %02X", cpu.state["PC"].value, prog:read_u8(0x00F4)))
    end
    assert_line("buy_carried", bought)
    send_key(0x51) -- 'Q': leave the store
    local turn_b = prog:read_u8(TURN_ADDR)
    wait_frames(60)
    drain_more(4)
    send_key(0x53) -- 'S' (search)
    wait_frames(60)
    assert_line("buy_play_goes_on", in_town() and prog:read_u8(TURN_ADDR) ~= turn_b)
    manager.machine:exit()
end
""".replace("ANDY_MOS_BYTES", andy_mos_bytes())
    elif scenario == "equip_flags":
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    -- Wearing a ring or amulet rebuilds the equipment flags (player_pflags)
    -- at once: on the compact play slot they stayed stale until the next
    -- stats rebuild (2026-11-08 review). Resist Fire sets $01, a Ring of
    -- Protection worn over it clears it, the Amulet of the Magi sets See
    -- Invisible ($08) and Free Action ($10).
    local function wear_slot_a(slot_lo, page_bit, what)
        drain_more(4)
        wait_frames(30)
        inv_seed(0, {slot_lo, 1, 0, 0, 0, 0, 2, page_bit})
        send_key(0x57) -- 'W' (wear)
        assert_line(what .. "_wear_prompt", wait_screen("Wear which item", 80))
        send_key(0x41) -- 'A'
        assert_line(what .. "_worn", wait_screen("You are wearing", 80))
    end
    prog:write_u8(INV_ITEM_ID_ADDR + 7 * INV_STRIDE + 22, inv_field(22, 7) & ITEM_PAGE_BIT)
    prog:write_u8(PLAYER_PFLAGS_ADDR, 0)
    wear_slot_a(ITEM_SLOT_RING_OF_RESIST_FIRE, ITEM_PAGE_RING_OF_RESIST_FIRE, "resist_fire_ring")
    assert_line("resist_fire_flag", prog:read_u8(PLAYER_PFLAGS_ADDR) & 0x01 == 0x01)
    -- Two ring hands (VMS moria.inc:528, 2026-11-08): the left hand next,
    -- then a third ring replaces the left-hand one
    wear_slot_a(ITEM_SLOT_RING_OF_RESIST_COLD, ITEM_PAGE_RING_OF_RESIST_COLD, "resist_cold_ring")
    assert_line("both_resist_flags", prog:read_u8(PLAYER_PFLAGS_ADDR) & 0x03 == 0x03)
    wear_slot_a(ITEM_SLOT_RING_OF_PROTECTION, ITEM_PAGE_RING_OF_PROTECTION, "protection_ring")
    assert_line("left_ring_replaced", prog:read_u8(PLAYER_PFLAGS_ADDR) & 0x03 == 0x01)
    wear_slot_a(ITEM_SLOT_AMULET_OF_THE_MAGI, ITEM_PAGE_AMULET_OF_THE_MAGI, "magi_amulet")
    assert_line("free_action_flag", prog:read_u8(PLAYER_PFLAGS_ADDR) & 0x18 == 0x18)
    -- A Golden Crown of the Magi (MON-030; INT +2, ego 14) through this
    -- port's own player_adjust_equipment_stat: worn, INT +2 and fire, cold
    -- and acid resisted ($23); taken off, INT back.
    local PL_INT_CUR = 28
    local int0 = prog:read_u8(PLAYER_DATA_ADDR + PL_INT_CUR)
    drain_more(4)
    wait_frames(30)
    inv_seed(0, {ITEM_SLOT_GOLDEN_CROWN, 1, 2, 0, 0, 3, 2, ITEM_PAGE_GOLDEN_CROWN | 14})
    send_key(0x57) -- 'W' (wear)
    assert_line("magi_crown_wear_prompt", wait_screen("Wear which item", 80))
    send_key(0x41) -- 'A'
    assert_line("magi_crown_worn", wait_screen("You are wearing", 80))
    assert_line("magi_crown_int", prog:read_u8(PLAYER_DATA_ADDR + PL_INT_CUR) == int0 + 2)
    assert_line("magi_crown_flags", prog:read_u8(PLAYER_PFLAGS_ADDR) & 0x23 == 0x23)
    -- Take it off: the equipment letters count the worn slots before the head.
    drain_more(4)
    wait_frames(30)
    local head_letter = 0
    for slot = 22, 24 do if inv_field(slot, 0) ~= 0xFF then head_letter = head_letter + 1 end end
    send_key(0x54) -- 'T' (take off)
    assert_line("magi_crown_takeoff_prompt", wait_screen("Take off which item", 80))
    send_key(0x41 + head_letter)
    assert_line("magi_crown_taken_off", wait_screen("You take off", 80))
    assert_line("magi_crown_int_restored", prog:read_u8(PLAYER_DATA_ADDR + PL_INT_CUR) == int0)
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
    -- The book prompt's '?' list from a second book: the list's overlay
    -- must give way to the caller's again (2026-11-15: the Atari's cast came
    -- back into OVL_HELP's bytes). A level 1 Mage knows no Magick I spell.
    send_key(0x1B)
    wait_frames(60)
    drain_more(4)
    local free = nil
    for slot = 0, 21 do if inv_field(slot, 0) == 0xFF then free = slot break end end
    inv_seed(free, {ITEM_SLOT_SPELLBOOK_MAGICK_I, 1, 0, 0, 0, 0, 2, ITEM_PAGE_SPELLBOOK_MAGICK_I})
    send_key(0x4D) -- 'M' (cast)
    assert_line("cast_book2_prompt", wait_screen("Spell book (a-b)?", 80))
    send_key(0x3F) -- '?': the book list
    assert_line("cast_book_list", wait_screen("Magick I", 200))
    send_key(0x42) -- 'B'
    assert_line("cast_book2_refused", wait_screen("You don't know that spell.", 200))
    drain_more(4)
    local turn_c = prog:read_u8(TURN_ADDR)
    send_key(0x53) -- 'S' (search)
    wait_frames(60)
    assert_line("cast_book2_play_goes_on", in_town() and prog:read_u8(TURN_ADDR) ~= turn_c)
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
            prog:write_u8(INV_ITEM_ID_ADDR + i, ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_CHANTS_AND_BLESSINGS)
            prog:write_u8(INV_QTY_ADDR + i, 1)
            prog:write_u8(INV_ITEM_ID_ADDR + 7 * INV_STRIDE + i, ITEM_PAGE_HOLY_BOOK_OF_PRAYERS_CHANTS_AND_BLESSINGS)
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
    send_int(ITEM_SCROLL_OF_MAGIC_MAPPING)
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
    local dirs = {
        {1, 0, 0x4C},  -- 'L' east
        {-1, 0, 0x48}, -- 'H' west
        {0, 1, 0x4A},  -- 'J' south
        {0, -1, 0x4B}, -- 'K' north
    }
    for _ = 1, 20 do
        drain_more(4)
        if (prog:read_u8(GAME_FLAGS_ADDR) & 0x04) == 0x04 then break end
        local px = prog:read_u8(PLAYER_X_ADDR)
        local py = prog:read_u8(PLAYER_Y_ADDR)
        local atk_key = 0x4C
        for _, d in ipairs(dirs) do
            local cx, cy, k = px + d[1], py + d[2], d[3]
            local mbyte = read_map_u8(cx, cy)
            if (mbyte & 0xF0) == 0 then
                for i = 1, 31 do
                    local b = mt + i * 12
                    if prog:read_u8(b + 0) == cx and prog:read_u8(b + 1) == cy then
                        prog:write_u8(b + 2, 0xFF)
                    end
                end
                local ox = prog:read_u8(base + 0)
                local oy = prog:read_u8(base + 1)
                if ox < MAP_COLS and oy < MAP_ROWS then
                    write_map_u8(ox, oy, read_map_u8(ox, oy) & 0xFE)
                end
                prog:write_u8(base + 0, cx)
                prog:write_u8(base + 1, cy)
                prog:write_u8(base + 2, 0)  -- species slot 0, made the Balrog's:
                prog:write_u8(CAT_SLOT_ID_LO_ADDR, BALROG_ID & 0xFF)
                prog:write_u8(CAT_SLOT_ID_HI_ADDR, BALROG_ID >> 8)
                prog:write_u8(base + 3, 1)  -- 1 HP
                prog:write_u8(base + 4, 0)
                prog:write_u8(base + 8, 0xFF)
                prog:write_u8(base + 10, 0) -- MX_FLEE_LO = 0
                prog:write_u8(base + 11, 0) -- MX_FLEE_HI = 0
                prog:write_u8(PLAYER_DATA_ADDR + 40, 127)
                write_map_u8(cx, cy, read_map_u8(cx, cy) | 0x01)
                atk_key = k
                break
            end
        end
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
    assert_line("retire_pick_drive", wait_screen("Save drive (0-3):", 60))
    send_key(0x31) -- '1' (:1 blank save disk)
    assert_line("retire_save_d1", wait_screen("Save:    :1", 60))
    send_key(0x33) -- '3) Done'
    assert_line("retire_no_marker", wait_screen("No Save Disk marker found.", 80))
    send_key(0x59) -- 'Y' (initialize :1 and continue to winner screen)
    assert_line("retire_winner_screen", wait_screen("* Total Winner *", 150))
    manager.machine:exit()
end
"""
    elif scenario == "acid_armour":
        # A monster's acid damages worn armour and recalculates AC through the
        # items overlay (MON-015): player_recalc_equipment lives in OVL_ITEMS
        # here, and a direct call ran whatever overlay was loaded (the X16
        # dropped the player into the town at (31, 18), M7 queue 2026-11-02).
        body = """
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    local dl1 = descend_to_dl1()
    assert_line("descended_dl1", dl1)
    drain_more(4)
    local mt = MONSTER_TABLE_ADDR
    local base = nil
    for i = 0, 31 do
        if prog:read_u8(mt + i * 12 + 2) ~= 0xFF then base = mt + i * 12 break end
    end
    assert_line("monster_found", base ~= nil)
    local kind = prog:read_u8(base + 2)
    local px0 = prog:read_u8(PLAYER_X_ADDR)
    local py0 = prog:read_u8(PLAYER_Y_ADDR)
    local mx, my = nil, nil
    for _, c in ipairs({{px0 + 1, py0}, {px0 - 1, py0}, {px0, py0 + 1}, {px0, py0 - 1}}) do
        if (read_map_u8(c[1], c[2]) & 0xF1) == 0 then mx, my = c[1], c[2] break end
    end
    assert_line("acid_spot", mx ~= nil)
    local ox, oy = prog:read_u8(base + 0), prog:read_u8(base + 1)
    write_map_u8(ox, oy, read_map_u8(ox, oy) & 0xFE)
    prog:write_u8(base + 0, mx)
    prog:write_u8(base + 1, my)
    write_map_u8(mx, my, read_map_u8(mx, my) | 0x01)
    prog:write_u8(base + 3, 200)                -- HP: it outlasts the test
    prog:write_u8(base + 4, 0)
    prog:write_u8(base + 5, 0x01)               -- MF_AWAKE
    prog:write_u8(base + 7, 0)
    prog:write_u8(CR_ATK0_TYPE_ADDR + kind, 6)  -- ATK_ACID 1d2
    prog:write_u8(CR_ATK0_DICE_ADDR + kind, 1)
    prog:write_u8(CR_ATK0_SIDES_ADDR + kind, 2)
    prog:write_u8(CR_ATK1_TYPE_ADDR + kind, 0)
    prog:write_u8(CR_SPELL_CHANCE_ADDR + kind, 0)
    prog:write_u8(CR_SPEED_ADDR + kind, 1)
    prog:write_u8(CR_LEVEL_ADDR + kind, 40)     -- its blows land
    prog:write_u8(PLAYER_DATA_ADDR + 40, 127)
    local function wait_turn_idle()
        local polled = false
        local tap = prog:install_read_tap(KBDBUF_LEN, KBDBUF_LEN, "acid_idle_poll",
            function(offset, data, mask)
                if polled or data ~= 0 then return end
                local pc = cpu.state["PC"].value
                if pc >= KEY_WAIT_START and pc < KEY_WAIT_END then polled = true end
            end)
        for _ = 1, 1200 do
            if polled then break end
            emu.wait(1/60)
        end
        tap:remove()
    end
    local body = INV_TO_AC_ADDR + 23            -- EQUIP_BODY: the warrior's only armour
    local to_ac0 = prog:read_u8(body)
    local ac0 = prog:read_u8(ZP_PLAYER_AC_ADDR)
    for _ = 1, 40 do
        send_key(0x53)                          -- 's' search (PETSCII): a turn passes
        wait_turn_idle()
        for _ = 1, 6 do
            if not screen_has("-more-") then break end
            send_key(0x20)
            wait_turn_idle()
        end
        if prog:read_u8(body) ~= to_ac0 then break end
    end
    local drop = (to_ac0 - prog:read_u8(body)) & 0xFF
    local ac1 = prog:read_u8(ZP_PLAYER_AC_ADDR)
    if ac1 ~= ((ac0 - drop) & 0xFF) then
        print("DIAG acid: ac0=" .. ac0 .. " ac1=" .. ac1 .. " to_ac0=" .. to_ac0 .. " to_ac1=" .. prog:read_u8(body) .. " drop=" .. drop)
    end
    assert_line("acid_damaged", drop >= 1 and drop <= 3)
    assert_line("acid_ac_recalc", ac1 == ((ac0 - drop) & 0xFF))
    assert_line("acid_in_place", prog:read_u8(PLAYER_X_ADDR) == px0 and prog:read_u8(PLAYER_Y_ADDR) == py0
                and prog:read_u8(DLVL_ADDR) == 1)
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
    -- One blow from death: the death flow is under test, not the fight; from
    -- full HP the summoned creature took 62 emulated seconds (2026-11-13).
    prog:write_u8(PLAYER_HP_ADDR, 1)
    prog:write_u8(PLAYER_HP_ADDR + 1, 0)
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
    assert_line("death_pick_drive", wait_screen("Save drive (0-3):", 60))
    send_key(0x31) -- '1' (:1 blank save disk)
    assert_line("death_save_d1", wait_screen("Save:    :1", 60))
    send_key(0x33) -- '3) Done'
    assert_line("death_no_marker", wait_screen("No Save Disk marker found.", 80))
    send_key(0x59) -- 'Y' (initialize :1 and continue to death screen)
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
    assert_line("disk_setup_pick_prompt", wait_screen("Save drive (0-3):", 60))
    send_key(0x51) -- 'Q' (cancel drive pick back to Disk Setup menu)
    assert_line("cancel_pick_returned_menu", wait_screen("1) Same as program", 60))
    send_key(0x31) -- '1) Same as program' (:0)
    assert_line("insert_save_prompt", wait_screen("Insert a separate Save Disk", 60))
    send_key(0x20) -- SPACE with Program Disk still in :0
    assert_line("prog_disk_rejected", wait_screen("Program disk cannot hold saves.", 80))
    send_key(0x51) -- 'Q' (cancel back to Disk Setup menu)
    assert_line("disk_setup_reopened", wait_screen("DISK SETUP", 60))
    send_key(0x32) -- '2) Pick save drive'
    wait_screen("Save drive (0-3):", 60)
    send_key(0x31) -- '1' (:1)
    assert_line("save_d1_selected", wait_screen("Save:    :1", 60))
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
    elif scenario == "catalog_spawn":
        # The monster catalog (2026-11-05): DL1 holds VMS's population (198x66,
        # no area scale), every live species was fetched from Bank 6 (its level
        # and its name in the Bank 4 pool match the catalog's), and from DL50 one
        # awake Evil Iggy or Balrog joins the level (VMS place_win_monster).
        count = catalog_lore.const("CATALOG_COUNT")
        levels = catalog_lore.field("cat_cr_level")
        names = [catalog_lore.name(cid) + [0] for cid in range(count)]
        ext_raw = build_catalog.ext_row_major_bytes(
            build_catalog.load_spec(build_catalog.DEFAULT_SPEC_PATH)["creatures"]
        )
        ext_rows = [list(ext_raw[cid * 8 : cid * 8 + 8]) for cid in range(count)]
        body = """
local LEVELS = {CAT_LEVELS}
local NAMES = {CAT_NAMES}
local EXT_ROWS = {CAT_EXT_ROWS}
local function slot_id(t)
    return prog:read_u8(CAT_SLOT_ID_LO_ADDR + t) + prog:read_u8(CAT_SLOT_ID_HI_ADDR + t) * 256
end
local function install_fetch_ext_hook()
    local cfe_lo = CATALOG_FETCH_EXT_ADDR & 0xFF
    local cfe_hi = (CATALOG_FETCH_EXT_ADDR >> 8) & 0xFF
    local iet_lo = INPUT_ENTROPY_TICK_ADDR & 0xFF
    local iet_hi = (INPUT_ENTROPY_TICK_ADDR >> 8) & 0xFF
    local hook = {
        0xAD, 0x60, 0x09,             -- lda $0960
        0xF0, 0x0A,                   -- beq !pass+ (+10 -> $094F)
        0xDA, 0x5A,                   -- phx : phy
        0x20, cfe_lo, cfe_hi,         -- jsr catalog_fetch_ext
        0x9C, 0x60, 0x09,             -- stz $0960
        0x7A, 0xFA,                   -- ply : plx
        0x4C, iet_lo, iet_hi          -- !pass: jmp input_entropy_tick
    }
    prog:write_u8(0x0960, 0)
    for i, b in ipairs(hook) do prog:write_u8(0x0940 + i - 1, b) end
    local patched = false
    local tap = prog:install_read_tap(KBDBUF_LEN, KBDBUF_LEN, "patch_cfe",
        function(offset, data, mask)
            if patched or data ~= 0 then return end
            local pc = cpu.state["PC"].value
            if pc >= KEY_WAIT_START + 5 and pc < KEY_WAIT_END then
                prog:write_u8(KEY_WAIT_START + 3, 0x40)
                prog:write_u8(KEY_WAIT_START + 4, 0x09)
                patched = true
            end
        end)
    for _ = 1, 300 do
        if patched then break end
        emu.wait(1/60)
    end
    tap:remove()
    return patched
end
local function remove_fetch_ext_hook()
    local restored = false
    local tap = prog:install_read_tap(KBDBUF_LEN, KBDBUF_LEN, "unpatch_cfe",
        function(offset, data, mask)
            if restored or data ~= 0 then return end
            local pc = cpu.state["PC"].value
            if pc >= KEY_WAIT_START + 5 and pc < KEY_WAIT_END then
                prog:write_u8(KEY_WAIT_START + 3, INPUT_ENTROPY_TICK_ADDR & 0xFF)
                prog:write_u8(KEY_WAIT_START + 4, (INPUT_ENTROPY_TICK_ADDR >> 8) & 0xFF)
                restored = true
            end
        end)
    for _ = 1, 300 do
        if restored then break end
        emu.wait(1/60)
    end
    tap:remove()
end
local function call_fetch_ext(cid)
    for k = 0, 7 do prog:write_u8(CAT_EXT_RECORD_ADDR + k, 0xA5) end
    prog:write_u8(CAT_ID_LO_ADDR, cid & 0xFF)
    prog:write_u8(CAT_ID_HI_ADDR, (cid >> 8) & 0xFF)
    prog:write_u8(0x0960, 1)
    for _ = 1, 600 do
        if prog:read_u8(0x0960) == 0 then break end
        emu.wait(1/60)
    end
    if prog:read_u8(0x0960) ~= 0 then return false end
    local want = EXT_ROWS[cid + 1]
    for k = 1, 8 do
        if prog:read_u8(CAT_EXT_RECORD_ADDR + k - 1) ~= want[k] then
            print(string.format("DIAG monext cid=%d byte %d got=%02X want=%02X", cid, k - 1,
                prog:read_u8(CAT_EXT_RECORD_ADDR + k - 1), want[k]))
            return false
        end
    end
    return prog:read_u8(0x00F4) == 0x04 and prog:read_u8(ACCCON_SHADOW_ADDR) == 0x01
end
function run()
    local ok = start_new_game("A")
    assert_line("chargen_town_ready", ok)
    assert_line("dlvl_1_reached", descend_to_dl1())
    local mt = MONSTER_TABLE_ADDR
    local count, types = 0, {}
    for i = 0, 31 do
        local t = prog:read_u8(mt + i * 12 + 2)
        if t ~= 0xFF then count = count + 1 types[t] = true end
    end
    print("DIAG DL1 monsters: " .. count)
    assert_line("cat_population", count >= 15)
    local loaded, fields, names, low = true, true, true, false
    for t, _ in pairs(types) do
        if t >= 32 or prog:read_u8(CAT_SLOT_ID_HI_ADDR + t) == 0xFF then
            loaded = false
        else
            local cid = slot_id(t)
            if LEVELS[cid + 1] < 8 then low = true end
            if prog:read_u8(CR_LEVEL_ADDR + t) ~= LEVELS[cid + 1] then
                fields = false
                print("DIAG slot " .. t .. " id " .. cid .. " level " .. prog:read_u8(CR_LEVEL_ADDR + t))
            end
            local ptr = prog:read_u8(CR_NAME_LO_ADDR + t) + prog:read_u8(CR_NAME_HI_ADDR + t) * 256
            local want = NAMES[cid + 1]
            for k = 1, #want do
                if prog:read_u8(ptr + k - 1) ~= want[k] then
                    names = false
                    print("DIAG slot " .. t .. " id " .. cid .. " name byte " .. k)
                    break
                end
            end
        end
    end
    assert_line("cat_slots_loaded", loaded)
    assert_line("cat_fields", fields)
    assert_line("cat_names", names)
    assert_line("cat_low_levels", low)
    assert_line("wizard_open", wizard_menu_open())
    assert_line("wizard_dlvl_prompt", press_until("DLVL", 0x4C))
    send_key(0x35) -- '5'
    send_key(0x30) -- '0'
    send_key(0x0D)
    -- Settled: DL50, generation not busy and its screen gone, three checks
    -- in a row (the level number changes before generation starts).
    local settled = 0
    for _ = 1, 200 * DFS_SLACK do
        wait_frames(10)
        drain_more(2)
        if prog:read_u8(DLVL_ADDR) == 50 and prog:read_u8(BUSY_ADDR) == 0 and not screen_has("GENERATING") then
            settled = settled + 1
            if settled >= 3 then break end
        else
            settled = 0
        end
    end
    assert_line("cat_dl50", prog:read_u8(DLVL_ADDR) == 50)
    local winners, awake, seen = 0, false, ""
    for i = 0, 31 do
        local b = mt + i * 12
        local t = prog:read_u8(b + 2)
        if t < 32 then
            local cid = slot_id(t)
            seen = seen .. " " .. cid
            if cid == IGGY_ID or cid == BALROG_ID then
                winners = winners + 1
                awake = (prog:read_u8(b + 5) & 0x01) == 1 and prog:read_u8(b + 7) == 0
            end
        end
    end
    print("DIAG DL50 win creatures: " .. winners .. " ids:" .. seen)
    assert_line("cat_win_creature", winners == 1)
    assert_line("cat_win_awake", awake)
    -- Verify live DFS MONEXT + catalog_fetch_ext (< $3000) across boundary species
    -- (0, 31, 32, 256, IGGY_ID, BALROG_ID) and handle close/reopen across LICENSE stream open.
    assert_line("monext_hook_installed", install_fetch_ext_hook())
    local ext_ok = true
    for _, cid in ipairs({0, 31, 32, 256, IGGY_ID, BALROG_ID}) do
        if not call_fetch_ext(cid) then ext_ok = false break end
    end
    assert_line("monext_boundary_fetches", ext_ok and prog:read_u8(BEEB_MEXT_HANDLE_ADDR) ~= 0)
    remove_fetch_ext_hook()
    send_key(0x3F) -- '?' (Help)
    assert_line("monext_help_open", wait_screen("Command Reference", 80))
    send_key(0x4C) -- 'L' (Legal)
    assert_line("monext_legal_open", wait_screen("License & Source", 100))
    send_key(0x31) -- '1' (License stream open -> closes beeb_mext_handle via beeb_close_icat_in_mos)
    assert_line("monext_license_open", wait_screen("MORIA8 LICENSE NOTICE", 100))
    assert_line("monext_handle_closed_on_stream", prog:read_u8(BEEB_MEXT_HANDLE_ADDR) == 0)
    send_key(0x51) -- 'Q'
    wait_screen("1 License", 60)
    send_key(0x51) -- 'Q'
    wait_screen("Command Reference", 80)
    send_key(0x51) -- 'Q'
    wait_frames(30)
    assert_line("monext_hook_reinstalled", install_fetch_ext_hook())
    assert_line("monext_reopened_after_stream", call_fetch_ext(BALROG_ID) and prog:read_u8(BEEB_MEXT_HANDLE_ADDR) ~= 0)
    remove_fetch_ext_hook()
    manager.machine:exit()
end
""".replace("{CAT_LEVELS}", "{" + ",".join(map(str, levels)) + "}").replace(
            "{CAT_NAMES}", "{" + ",".join("{" + ",".join(map(str, n)) + "}" for n in names) + "}").replace(
            "{CAT_EXT_ROWS}", "{" + ",".join("{" + ",".join(map(str, r)) + "}" for r in ext_rows) + "}")
    else:
        raise ValueError(f"Unknown scenario: {scenario}")

    body = body.replace("LEGAL_SAVE_ADDR", hex(syms.get("legal_zp_save", 0)))
    body = body.replace("LEGAL_CANCEL_START", hex(syms.get("legal_cancel_restore", 0)))
    body = body.replace("LEGAL_CANCEL_END", hex(syms.get("legal_cancel_return", 0)))
    body = body.replace("LEGAL_NOTICE_ADDR", hex(syms.get("legal_notice_filename", 0)))
    body = body.replace("LEGAL_OPENED_ADDR", hex(syms.get("legal_opened", 0)))
    body = body.replace("\n    manager.machine:exit()\nend\n", '\n    print("SCENARIO_DONE")\n    manager.machine:exit()\nend\n', 1)
    return header + body + "\nco = coroutine.create(run)\ncoroutine.resume(co)\n"


def run_scenario(
    scenario: str,
    rompath: str,
    disk_path: Path,
    sym_path: Path,
    mame_bin: str = "mame",
    machine: str = "bbcm",
    real_boot: bool = False,
) -> bool:
    syms = parse_symbols(sym_path)
    lua_code = build_lua_script(scenario, syms)
    fast = not real_boot and scenario != "boot_title"   # boot_title keeps the disk boot covered

    for output_dir in MAME_OUTPUT_DIRS.values():
        output_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_ssd = Path(tmpdir) / "work.ssd"
        shutil.copy2(disk_path, tmp_ssd)
        tmp_save_ssd = Path(tmpdir) / "save.ssd"
        build_blank_ssd(tmp_save_ssd)
        lua_path = Path(tmpdir) / "scenario.lua"
        lua_code = lua_code.replace("LEGAL_GAME_IMAGE", str(tmp_ssd)).replace("LEGAL_SAVE_IMAGE", str(tmp_save_ssd))
        table = "nil"
        if fast:
            rows = []
            for i, (bank, addr, data) in enumerate(fast_boot_entries(disk_path, sym_path.parent / "boot.sym")):
                payload = Path(tmpdir) / f"boot{i}.bin"
                payload.write_bytes(data)
                rows.append(f'{{bank = 0x{bank:02X}, addr = 0x{addr:04X}, path = "{payload}"}}')
            table = "{" + ", ".join(rows) + "}"
        lua_code = lua_code.replace("FAST_BOOT_TABLE", table)
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
            str(tmp_ssd),
            "-flop2",
            str(tmp_save_ssd),
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
            stdout, stderr = proc.communicate()
            for line in ((stdout or "") + (stderr or "")).splitlines()[-20:]:
                print(f"[{machine}:{scenario}] DIAG timeout: {line}", file=sys.stderr)
            print(
                f"[{machine}:{scenario}] FAIL: host timeout ({HOST_TIMEOUT_SECONDS}s)",
                file=sys.stderr,
            )
            return False

        out = (stdout or "") + (stderr or "")
        passes = 0
        fails = 0
        completed = False
        for line in out.splitlines():
            if line.startswith("DIAG "):
                print(f"[{machine}:{scenario}] {line}", file=sys.stderr)
            elif line.startswith("ASSERT PASS "):
                passes += 1
            elif line.startswith("ASSERT FAIL "):
                fails += 1
                print(f"[{machine}:{scenario}] {line}", file=sys.stderr)
            elif line.strip() == "SCENARIO_DONE":
                completed = True

        if fails > 0 or passes == 0 or not completed:
            for line in out.splitlines():
                if line.startswith("DIAG "):
                    print(f"[{machine}:{scenario}] {line}", file=sys.stderr)
            if passes == 0 and out.strip():
                print(out.strip(), file=sys.stderr)
            if not completed and fails == 0:
                print(
                    f"[{machine}:{scenario}] FAIL: scenario did not reach SCENARIO_DONE (emulated time limit {EMULATED_SECONDS_LIMIT}s)",
                    file=sys.stderr,
                )
            print(
                f"[{machine}:{scenario}] FAIL (passes={passes}, fails={fails})",
                file=sys.stderr,
            )
            return False

        print(f"[{machine}:{scenario}] PASS ({passes} assertions)")
        return True


def selftest() -> int:
    assert HOST_TIMEOUT_SECONDS <= 30, "AGENTS.md Rule 8 requires timeout <= 30s"
    assert len(SCENARIOS) == 20, f"Expected 20 bbcm scenarios, got {len(SCENARIOS)}"
    syms = parse_symbols(SYM_PATH)
    if syms:
        assert syms.get("zp_player_x") == 0x002B, f"zp_player_x != $002B: {syms.get('zp_player_x')}"
        assert syms.get("zp_player_y") == 0x002C, f"zp_player_y != $002C: {syms.get('zp_player_y')}"
        assert syms.get("zp_player_dlvl") == 0x0034, f"zp_player_dlvl != $0034: {syms.get('zp_player_dlvl')}"
        assert "beeb_kbdbuf" in syms, "beeb_kbdbuf missing from main.sym"
        assert "beeb_kbdbuf_len" in syms, "beeb_kbdbuf_len missing from main.sym"
        assert "catalog_fetch_ext" in syms and syms["catalog_fetch_ext"] < 0x3000, (
            f"catalog_fetch_ext missing or >= $3000: {syms.get('catalog_fetch_ext')}"
        )
        assert "cat_ext_record" in syms and syms["cat_ext_record"] + 8 <= 0x3000, (
            f"cat_ext_record missing or straddles $3000: {syms.get('cat_ext_record')}"
        )
    if SSD_IMAGE.is_file():
        expected_monext = build_catalog.ext_row_major_bytes(
            build_catalog.load_spec(build_catalog.DEFAULT_SPEC_PATH)["creatures"]
        )
        actual_monext = read_dfs_file(SSD_IMAGE.read_bytes(), "MONEXT")
        assert actual_monext == expected_monext, (
            f"MONEXT on {SSD_IMAGE.name} mismatch: {len(actual_monext)} B vs {len(expected_monext)} B"
        )
    for sc in SCENARIOS:
        lua = build_lua_script(sc, syms)
        assert "assert_line(" in lua and "coroutine.resume" in lua and "SCENARIO_DONE" in lua
        assert "PLAYER_X_ADDR = 0x002B" in lua
        assert "DLVL_ADDR = 0x0034" in lua
    print("BBC Master 128 harness_smoke.py self-test: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenario", nargs="?", default="boot_title", choices=SCENARIOS)
    parser.add_argument("--rompath", default=os.environ.get("BBCMROMS", ""))
    parser.add_argument("--disk", type=Path, default=SSD_IMAGE)
    parser.add_argument("--sym", type=Path, default=SYM_PATH)
    parser.add_argument("--mame", default="mame")
    parser.add_argument("--machine", default="bbcm", choices=("bbcm",))
    parser.add_argument("--fast-smoke", "--fast", dest="fast_smoke", action="store_true")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--real-boot", action="store_true",
                        help="boot every scenario from the disk (slow), not boot_title alone")
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    if not args.rompath:
        print(
            "error: BBCMROMS env var or --rompath required",
            file=sys.stderr,
        )
        return 1

    if not args.disk.is_file():
        print(
            f"error: disk image missing: {args.disk} (run make diskbbcmaster)",
            file=sys.stderr,
        )
        return 1

    if args.fast_smoke:
        for sc in FAST_SMOKE_SCENARIOS:
            if not run_scenario(sc, args.rompath, args.disk, args.sym, args.mame, args.machine, args.real_boot):
                return 1
        return 0

    if args.all:
        for sc in SCENARIOS:
            if not run_scenario(sc, args.rompath, args.disk, args.sym, args.mame, args.machine, args.real_boot):
                return 1
        return 0

    ok = run_scenario(
        args.scenario, args.rompath, args.disk, args.sym, args.mame, args.machine, args.real_boot
    )
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
