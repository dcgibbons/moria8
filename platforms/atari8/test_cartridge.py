#!/usr/bin/env python3
"""Atari 8-bit 128 KB MaxFlash (.car Type 41) cartridge test suite.

Drives headless MAME (a800xl / a130xe) against build/moria8-atari8.car:
  1. cold_boot_gameplay_legal_a800xl   (zero floppies: boot, legal A/L, Town/DL1, catalog names, ?/L state preservation)
  2. cold_boot_and_catalog_279_a130xe  (zero floppies: 130XE boot + 279-record dual byte-sum & zp_math preservation driver)
  3. disk_setup_guards_a800xl          (Program Disk TITLE.DAT guard & Q cancel on D1:)
  4. save_persistence_and_disk_interchange (Disk -> Cart D1: w/ 0 swaps & overwrite N/Y -> Disk bidirectional SAVE_VERSION)

Enforces strict 30-second host timeout per MAME invocation (AGENTS.md Rule 8)
and uses only project-relative output paths (AGENTS.md Rule 9).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import catalog_disk  # noqa: E402
import catalog_lore  # noqa: E402
import item_ids  # noqa: E402
from make_atr import build_blank_atr  # noqa: E402


LUA_ITEM_CONSTS = item_ids.lua_item_consts(
    "DAGGER",
    "MACE",
    "CLOAK",
    "RING_OF_LORDLY_PROTECTION_FIRE",
    "RING_OF_LORDLY_PROTECTION_ACID",
    "POTION_OF_RESTORE_STRENGTH",
    "SCROLL_OF_HOLY_CHANT",
)

CAR_IMAGE = ROOT / "build" / "moria8-atari8.car"
CART_SYM_PATH = ROOT / "build" / "atari8-cart" / "main.sym"
CAT_TEST_PRG = ROOT / "build" / "atari8-cart" / "catalog-test.prg"
DISK_IMAGE = ROOT / "build" / "moria8-atari8.atr"
DISK_SYM_PATH = ROOT / "build" / "atari8" / "main.sym"

MAME_OUTPUT_ROOT = ROOT / "build" / "test" / "atari8-cartridge" / "mame"
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
ROW23_ADDR = SCREEN_RAM + 23 * 40

SCENARIOS = (
    "cold_boot_gameplay_legal_a800xl",
    "cold_boot_and_catalog_279_a130xe",
    "disk_setup_guards_a800xl",
    "save_persistence_and_disk_interchange",
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


def sc_to_ascii(b: int) -> str:
    b &= 0x7F
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


def expected_catalog_checksums() -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    for base, ext in zip(catalog_disk.records(phase5=False), catalog_disk.ext_records()):
        rec = base + ext
        assert len(rec) == 57
        s1 = 0
        s2 = 0
        for b in rec:
            s1 = (s1 + b) & 0xFF
            s2 = (s2 + s1) & 0xFF
        out.append((s1, s2))
    return out


def _lua_common_header(
    syms: dict[str, int],
    *,
    save_atr_sync_path: Path | None = None,
    save_dunit: int = 0,
) -> str:
    kbdbuf = syms.get("atari_kbdbuf", 0x03CC)
    kbdbuf_len = syms.get("atari_kbdbuf_len", 0x03CB)
    key_wait_start = syms.get("input_get_key", 0)
    key_wait_end = syms.get("igk_save_x", 1) - 1
    zp_rng0 = syms.get("zp_rng_0", 0x001A)
    zp_px = syms.get("zp_player_x", 0x002B)
    zp_py = syms.get("zp_player_y", 0x002C)
    zp_hp_lo = syms.get("zp_player_hp_lo", 0x002D)
    zp_hp_hi = syms.get("zp_player_hp_hi", 0x002E)
    zp_lvl = syms.get("zp_player_lvl", 0x0033)
    zp_dlvl = syms.get("zp_player_dlvl", 0x0034)
    turn_lo = syms.get("zp_turn_lo", 0x0040)
    inv_item_id = syms.get("inv_item_id", 0)
    inv_qty = syms.get("inv_qty", 0)
    monster_table = syms.get("monster_table", 0)
    cr_level = syms.get("cr_level", 0)
    cat_slot_id_lo = syms.get("cat_slot_id_lo", 0)
    cat_slot_id_hi = syms.get("cat_slot_id_hi", 0)
    cr_name_lo = syms.get("cr_name_lo", 0)
    cr_name_hi = syms.get("cr_name_hi", 0)
    save_device = syms.get("save_device", 0)
    disk_mode = syms.get("disk_mode", 0)
    disk_setup_done = syms.get("disk_setup_done", 0)
    busy_addr = syms.get("generation_busy_active_api", 0)
    shuffles = syms.get("potion_shuffle", 0)
    id_known = syms.get("id_known_bits", 0)
    recall_data = syms.get("recall_data_start", 0)
    xe_present = syms.get("xe_present", 0x03D6)
    sio_sector_buf = syms.get("sio_sector_buf", 0)
    exit_sio = syms.get("ExitSio", 0)

    sio_sync_lua = ""
    if save_atr_sync_path is not None and save_dunit > 0:
        sync_lua_path = str(save_atr_sync_path).replace("\\", "\\\\")
        sio_sync_lua = f"""
local SIO_SECTOR_BUF_ADDR = 0x{sio_sector_buf:04X}
local EXIT_SIO_ADDR = 0x{exit_sio:04X}
local SAVE_DUNIT = {save_dunit}
local SAVE_ATR_SYNC_PATH = "{sync_lua_path}"
local dirty_sectors = {{}}
_G.harness_sio_writeback_tap = prog:install_read_tap(0x0303, 0x0303, "harness_sio_writeback",
    function(offset, data, mask)
        local pc = cpu.state["PC"].value
        if pc < EXIT_SIO_ADDR or pc >= EXIT_SIO_ADDR + 0x50 then return end
        if data ~= 0x01 then return end
        local dcomnd = prog:read_u8(0x0302)
        if dcomnd ~= 0x50 and dcomnd ~= 0x57 then return end
        if prog:read_u8(0x0300) ~= 0x31 or prog:read_u8(0x0301) ~= SAVE_DUNIT then return end
        local sec = prog:read_u8(0x030A) + prog:read_u8(0x030B) * 256
        if sec >= 1 and sec <= 1040 then
            local bytes = {{}}
            for i = 0, 127 do
                bytes[i + 1] = string.char(prog:read_u8(SIO_SECTOR_BUF_ADDR + i))
            end
            dirty_sectors[sec] = table.concat(bytes)
        end
    end)

local function flush_save_atr()
    local count = 0
    local f = assert(io.open(SAVE_ATR_SYNC_PATH, "r+b"))
    for sec, payload in pairs(dirty_sectors) do
        f:seek("set", 16 + (sec - 1) * 128)
        f:write(payload)
        count = count + 1
    end
    f:close()
    return count
end
"""

    return LUA_ITEM_CONSTS + f"""
local prog = manager.machine.devices[":maincpu"].spaces["program"]
local cpu = manager.machine.devices[":maincpu"]
local KBDBUF = 0x{kbdbuf:04X}
local KBDBUF_LEN = 0x{kbdbuf_len:04X}
local KEY_WAIT_START = 0x{key_wait_start:04X}
local KEY_WAIT_END = 0x{key_wait_end:04X}
local RNG0_ADDR = 0x{zp_rng0:04X}
local PLAYER_X_ADDR = 0x{zp_px:04X}
local PLAYER_Y_ADDR = 0x{zp_py:04X}
local PLAYER_HP_LO_ADDR = 0x{zp_hp_lo:04X}
local PLAYER_HP_HI_ADDR = 0x{zp_hp_hi:04X}
local PLAYER_LVL_ADDR = 0x{zp_lvl:04X}
local DLVL_ADDR = 0x{zp_dlvl:04X}
local TURN_LO_ADDR = 0x{turn_lo:04X}
local INV_ITEM_ID_ADDR = 0x{inv_item_id:04X}
local INV_QTY_ADDR = 0x{inv_qty:04X}
local INV_STRIDE = INV_QTY_ADDR - INV_ITEM_ID_ADDR
local MONSTER_TABLE_ADDR = 0x{monster_table:04X}
local CR_LEVEL_ADDR = 0x{cr_level:04X}
local CAT_SLOT_ID_LO_ADDR = 0x{cat_slot_id_lo:04X}
local CAT_SLOT_ID_HI_ADDR = 0x{cat_slot_id_hi:04X}
local CR_NAME_LO_ADDR = 0x{cr_name_lo:04X}
local CR_NAME_HI_ADDR = 0x{cr_name_hi:04X}
local SAVE_DEV_ADDR = 0x{save_device:04X}
local DISK_MODE_ADDR = 0x{disk_mode:04X}
local DISK_SETUP_DONE_ADDR = 0x{disk_setup_done:04X}
local BUSY_ADDR = 0x{busy_addr:04X}
local SHUFFLES_ADDR = 0x{shuffles:04X}
local ID_KNOWN_ADDR = 0x{id_known:04X}
local RECALL_ADDR = 0x{recall_data:04X}
local XE_PRESENT_ADDR = 0x{xe_present:04X}
local SCREEN_RAM = 0x{SCREEN_RAM:04X}
local ROW23 = 0x{ROW23_ADDR:04X}
{sio_sync_lua}

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

local key_polled = false
_G.harness_key_poll_tap = prog:install_read_tap(KBDBUF_LEN, KBDBUF_LEN, "harness_key_poll",
    function(offset, data, mask)
        if data ~= 0 then return end
        local pc = cpu.state["PC"].value
        if pc >= KEY_WAIT_START and pc <= KEY_WAIT_END then key_polled = true end
    end)

local function wait_for_key_poll(label)
    key_polled = false
    for _ = 1, 300 do
        if key_polled then return true end
        emu.wait(1/60)
    end
    assert_line("key_wait_seen_before_" .. label, false)
    return false
end

local function send_key(petscii, post_frames)
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
    wait_frames(post_frames or 10)
end

local function wait_screen(txt, max_tenths)
    for _ = 1, (max_tenths or 80) do
        if screen_has(txt) then return true end
        emu.wait(0.1)
    end
    return screen_has(txt)
end

local function press_until(txt, key, tries)
    for _ = 1, (tries or 12) do
        if screen_has(txt) then return true end
        send_key(key)
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
            if prog:read_u8(base + c) == 0x23 then walls = walls + 1 end
        end
    end
    return walls >= 20
end

local function wait_title()
    for _ = 1, 1000 do
        emu.wait(0.1)
        if screen_has("N)ew") and screen_has("L)oad") then return true end
    end
    return false
end

local function start_new_game(class_key)
    if not wait_title() then
        assert_line("title_reached", false)
        manager.machine:exit()
        return false
    end
    press_until("Choose your race", 0x4E)
    press_until("Roll Statistics", 0x41)
    press_until("Choose your class", 0x0D)
    press_until("Enter your name", string.byte(class_key or "A"))
    send_key(0x54) -- 'T'
    send_key(0x45) -- 'E'
    send_key(0x53) -- 'S'
    send_key(0x54) -- 'T'
    press_until("Choose your sex", 0x0D)
    press_until("Character Info", 0x41)
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

local function descend_to_dl1()
    for _ = 1, 12 do
        local px = prog:read_u8(PLAYER_X_ADDR)
        local py = prog:read_u8(PLAYER_Y_ADDR)
        if (prog:read_u8(0xC100 + py * 80 + px) & 0xF0) ~= 0x90 then
            send_key(0x4C) -- 'L' east toward (32, 18)
            wait_frames(20)
            drain_more(2)
        end
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

local function inv_seed(slot, f)
    for k = 0, 7 do prog:write_u8(INV_ITEM_ID_ADDR + k * INV_STRIDE + slot, f[k + 1]) end
end

local function inv_field(slot, k)
    return prog:read_u8(INV_ITEM_ID_ADDR + k * INV_STRIDE + slot)
end
"""


def build_lua_script(
    scenario: str,
    syms: dict[str, int],
    *,
    catalog_prg_path: Path | None = None,
    state_in_path: Path | None = None,
    state_out_path: Path | None = None,
    save_atr_sync_path: Path | None = None,
    save_dunit: int = 0,
) -> str:
    header = _lua_common_header(syms, save_atr_sync_path=save_atr_sync_path, save_dunit=save_dunit)

    if scenario == "cold_boot_gameplay_legal_a800xl":
        count = catalog_lore.const("CATALOG_COUNT")
        levels = catalog_lore.field("cat_cr_level")
        names = [catalog_lore.name(cid) + [0] for cid in range(count)]
        body = """
local LEVELS = {CAT_LEVELS}
local NAMES = {CAT_NAMES}
local function slot_id(t)
    return prog:read_u8(CAT_SLOT_ID_LO_ADDR + t) + prog:read_u8(CAT_SLOT_ID_HI_ADDR + t) * 256
end

function run()
    assert_line("boot_title_menu", wait_title())
    assert_line("portb_game_ram", prog:read_u8(0xD301) == 0xFE)
    assert_line("trig3_disabled", prog:read_u8(0xD013) == 0x00)
    assert_line("gintlk_disabled", prog:read_u8(0x03FA) == 0x00)
    assert_line("cart_defaults",
        prog:read_u8(SAVE_DEV_ADDR) == 8
        and prog:read_u8(DISK_MODE_ADDR) == 2
        and prog:read_u8(DISK_SETUP_DONE_ADDR) == 0)
    assert_line("cart_banner_row23", string.find(rowtext(23), "ATARI XL/XE  CARTRIDGE", 1, true) ~= nil)

    -- Exercise Title A (About) -> 1 (LICENSE to End.) -> 2 (SOURCE-OFFER to End.) with zero floppies.
    send_key(0x41) -- 'A'
    assert_line("title_legal_menu", wait_screen("License & Source", 80))
    send_key(0x31) -- '1' License
    assert_line("license_notice_opened", wait_screen("MORIA8 LICENSE NOTICE", 80))
    local lic_end = false
    for _ = 1, 60 do
        if screen_has("End.") then lic_end = true break end
        send_key(0x20, 4)
    end
    assert_line("license_reached_end", lic_end)
    send_key(0x51) -- 'Q'
    assert_line("legal_menu_after_license", wait_screen("License & Source", 80))
    send_key(0x32) -- '2' Source Offer
    assert_line("source_offer_opened", wait_screen("MORIA8 SOURCE OFFER", 80))
    local off_end = false
    for _ = 1, 20 do
        if screen_has("End.") then off_end = true break end
        send_key(0x20, 4)
    end
    assert_line("source_offer_reached_end", off_end)
    send_key(0x51) -- 'Q' back to legal menu
    wait_screen("License & Source", 60)
    send_key(0x33) -- '3' System Info on cartridge (800XL = 64KB RAM)
    assert_line("cart_sysinfo_title_menu",
        wait_screen("Moria 8 - System Info", 80)
        and screen_has("Atari XL/XE")
        and screen_has("Cartridge")
        and screen_has("64KB RAM"))
    send_key(0x51) -- 'Q' back to legal menu
    assert_line("cart_sysinfo_title_menu_back", wait_screen("1 License", 60))
    send_key(0x51) -- 'Q' back to title
    assert_line("title_returned_after_legal", wait_title())

    -- Start new game (exercises OVL.STA + OVL.CHS store init) and verify town step.
    assert_line("chargen_town_ready", start_new_game("A"))
    local tx0 = prog:read_u8(PLAYER_X_ADDR)
    local ty0 = prog:read_u8(PLAYER_Y_ADDR)
    for _, k in ipairs({0x4C, 0x48, 0x4A, 0x4B}) do
        send_key(k)
        wait_frames(15)
        if prog:read_u8(PLAYER_X_ADDR) ~= tx0 or prog:read_u8(PLAYER_Y_ADDR) ~= ty0 then break end
    end
    assert_line("town_moved", prog:read_u8(PLAYER_X_ADDR) ~= tx0 or prog:read_u8(PLAYER_Y_ADDR) ~= ty0)

    -- Step onto Home door (51, 16) to exercise OVL.HOM from MaxFlash CAR ROM.
    local hx, hy = prog:read_u8(PLAYER_X_ADDR), prog:read_u8(PLAYER_Y_ADDR)
    for i = 0, 31 do
        local base = MONSTER_TABLE_ADDR + i * 12
        if prog:read_u8(base + 2) ~= 0xFF and prog:read_u8(base + 0) == 51 and prog:read_u8(base + 1) == 16 then
            prog:write_u8(base + 2, 0xFF)
            local ma = 0xC100 + 16 * 80 + 51
            prog:write_u8(ma, prog:read_u8(ma) & 0xFE)
        end
    end
    prog:write_u8(PLAYER_X_ADDR, 51)
    prog:write_u8(PLAYER_Y_ADDR, 17)
    send_key(0x4B) -- 'K' north onto Home door (51, 16)
    assert_line("cart_home_overlay_open", wait_screen("Home", 80))
    send_key(0x51) -- 'Q' exit Home back to Town
    wait_frames(40)
    assert_line("cart_home_overlay_closed", in_town() and not screen_has("Home"))
    prog:write_u8(PLAYER_X_ADDR, hx)
    prog:write_u8(PLAYER_Y_ADDR, hy)

    -- Descend to DL1 (exercises OVL.GEN + ROM catalog_fetch_record) and check all spawned monster records.
    assert_line("dlvl_1_reached", descend_to_dl1() and prog:read_u8(DLVL_ADDR) == 1)
    local mt = MONSTER_TABLE_ADDR
    local mcount, types = 0, {}
    for i = 0, 31 do
        local t = prog:read_u8(mt + i * 12 + 2)
        if t ~= 0xFF then mcount = mcount + 1 types[t] = true end
    end
    assert_line("dl1_monsters_spawned", mcount >= 5)
    local loaded, fields, names = true, true, true
    for t, _ in pairs(types) do
        if t >= 32 or prog:read_u8(CAT_SLOT_ID_HI_ADDR + t) == 0xFF then
            loaded = false
        else
            local cid = slot_id(t)
            if prog:read_u8(CR_LEVEL_ADDR + t) ~= LEVELS[cid + 1] then fields = false end
            local ptr = prog:read_u8(CR_NAME_LO_ADDR + t) + prog:read_u8(CR_NAME_HI_ADDR + t) * 256
            local want = NAMES[cid + 1]
            for k = 1, #want do
                if prog:read_u8(ptr + k - 1) ~= want[k] then names = false break end
            end
        end
    end
    assert_line("dl1_catalog_records_valid", loaded and fields and names)

    -- Record turn, RNG ($1A..$1D), coords, HP before ? -> L -> Q,Q,Q and verify exact preservation.
    local turn_before = prog:read_u8(TURN_LO_ADDR)
    local rng_before = {prog:read_u8(RNG0_ADDR), prog:read_u8(RNG0_ADDR + 1), prog:read_u8(RNG0_ADDR + 2), prog:read_u8(RNG0_ADDR + 3)}
    local px_before = prog:read_u8(PLAYER_X_ADDR)
    local py_before = prog:read_u8(PLAYER_Y_ADDR)
    local hp_lo_before = prog:read_u8(PLAYER_HP_LO_ADDR)
    local hp_hi_before = prog:read_u8(PLAYER_HP_HI_ADDR)

    send_key(0x3F) -- '?'
    assert_line("help_opened", wait_screen("Command Reference", 80) and screen_has("L:License"))
    send_key(0x4C) -- 'L' from Help
    assert_line("help_legal_menu", wait_screen("License & Source", 80))
    send_key(0x31) -- '1' License
    assert_line("help_license_shown", wait_screen("MORIA8 LICENSE NOTICE", 80))
    send_key(0x51) -- 'Q' to legal menu
    wait_screen("License & Source", 60)
    send_key(0x51) -- 'Q' to Help
    assert_line("returned_to_help", wait_screen("Command Reference", 80))
    send_key(0x51) -- 'Q' to DL1 gameplay
    for _ = 1, 80 do
        emu.wait(0.1)
        if not screen_has("Command Reference") and prog:read_u8(DLVL_ADDR) == 1 then break end
    end
    local preserved = prog:read_u8(DLVL_ADDR) == 1
        and prog:read_u8(TURN_LO_ADDR) == turn_before
        and prog:read_u8(PLAYER_X_ADDR) == px_before
        and prog:read_u8(PLAYER_Y_ADDR) == py_before
        and prog:read_u8(PLAYER_HP_LO_ADDR) == hp_lo_before
        and prog:read_u8(PLAYER_HP_HI_ADDR) == hp_hi_before
        and prog:read_u8(RNG0_ADDR) == rng_before[1]
        and prog:read_u8(RNG0_ADDR + 1) == rng_before[2]
        and prog:read_u8(RNG0_ADDR + 2) == rng_before[3]
        and prog:read_u8(RNG0_ADDR + 3) == rng_before[4]
    assert_line("help_legal_gameplay_state_preserved", preserved)

    send_key(0xD6) -- SHIFT+V System Info from cartridge gameplay (800XL = 64KB RAM)
    assert_line("cart_gameplay_sysinfo",
        wait_screen("Moria 8 - System Info", 80)
        and screen_has("Cartridge")
        and screen_has("64KB RAM")
        and screen_has("RNG:"))
    send_key(0x51) -- 'Q' back to DL1
    wait_frames(30)
    assert_line("cart_gameplay_sysinfo_close", not screen_has("Moria 8 - System Info") and prog:read_u8(DLVL_ADDR) == 1)
    manager.machine:exit()
end
""".replace("{CAT_LEVELS}", "{" + ",".join(map(str, levels)) + "}").replace(
            "{CAT_NAMES}", "{" + ",".join("{" + ",".join(map(str, n)) + "}" for n in names) + "}"
        )

    elif scenario == "cold_boot_and_catalog_279_a130xe":
        prg_bytes = catalog_prg_path.read_bytes() if catalog_prg_path and catalog_prg_path.is_file() else b"\x00\xC4"
        load_addr = prg_bytes[0] | (prg_bytes[1] << 8)
        payload = prg_bytes[2:]
        want = expected_catalog_checksums()
        lua_payload = "{" + ",".join(str(b) for b in payload) + "}"
        lua_want = "{" + ",".join(f"{{{s1},{s2}}}" for s1, s2 in want) + "}"
        body = f"""
local LOAD_ADDR = 0x{load_addr:04X}
local PAYLOAD = {lua_payload}
local WANT = {lua_want}

function run()
    assert_line("boot_title_menu_130xe", wait_title())
    assert_line("portb_game_ram", prog:read_u8(0xD301) == 0xFE)
    assert_line("trig3_disabled", prog:read_u8(0xD013) == 0x00)
    assert_line("cart_banner_row23", string.find(rowtext(23), "ATARI XL/XE  CARTRIDGE", 1, true) ~= nil)
    assert_line("cart_130xe_detected", prog:read_u8(XE_PRESENT_ADDR) == 1)
    send_key(0x41) -- 'A' About
    assert_line("cart_130xe_legal_menu", wait_screen("License & Source", 80))
    send_key(0x33) -- '3' System Info
    assert_line("cart_130xe_sysinfo",
        wait_screen("Moria 8 - System Info", 80)
        and screen_has("Atari XL/XE")
        and screen_has("Cartridge")
        and screen_has("128KB RAM"))
    send_key(0x51) -- 'Q' back to legal menu
    wait_screen("1 License", 60)
    send_key(0x51) -- 'Q' back to title
    assert_line("cart_130xe_title_restored", wait_title())
    assert_line("catalog_prg_load_c400", LOAD_ADDR == 0xC400)

    -- Synchronize on main-thread key wait (PORTB == $FE) before jumping into $C400.
    wait_for_key_poll("catalog_test")
    assert_line("portb_ram_before_exec", prog:read_u8(0xD301) == 0xFE)
    for i = 1, #PAYLOAD do
        prog:write_u8(LOAD_ADDR + i - 1, PAYLOAD[i])
    end
    prog:write_u8(0xC7F0, 0)
    cpu.state["PC"].value = LOAD_ADDR

    local status = 0
    for _ = 1, 200 do
        wait_frames(1)
        status = prog:read_u8(0xC7F0)
        if status ~= 0 then break end
    end
    assert_line("catalog_279_driver_passed", status == 1)

    local all_match = true
    for idx = 1, #WANT do
        local base = 0xC800 + (idx - 1) * 2
        local s1 = prog:read_u8(base)
        local s2 = prog:read_u8(base + 1)
        if s1 ~= WANT[idx][1] or s2 ~= WANT[idx][2] then
            all_match = false
            print(string.format("DIAG rec %d got (%02X,%02X) want (%02X,%02X)", idx - 1, s1, s2, WANT[idx][1], WANT[idx][2]))
            break
        end
    end
    assert_line("catalog_279_dual_checksums_match", all_match)
    manager.machine:exit()
end
"""

    elif scenario == "disk_setup_guards_a800xl":
        body = """
function run()
    assert_line("title_ready", wait_title())
    send_key(0x44) -- 'D' Disk Setup
    assert_line("disk_setup_cart_wording", wait_screen("DISK SETUP", 80) and screen_has("1) Use D1: for saves"))
    assert_line("not_disk_wording", not screen_has("Same as program"))
    send_key(0x51) -- 'Q' cancel
    assert_line("cancel_returns_title", wait_title() and prog:read_u8(DISK_SETUP_DONE_ADDR) == 0)

    -- Program Disk (containing TITLE.DAT) in D1: must be rejected by "1) Use D1: for saves".
    send_key(0x44) -- 'D'
    assert_line("disk_setup_reopened", wait_screen("1) Use D1: for saves", 80))
    send_key(0x31) -- '1'
    assert_line("prog_disk_rejected", wait_screen("Program disk cannot hold saves.", 100))
    send_key(0x51) -- 'Q' out of error to Disk Setup menu
    assert_line("back_to_disk_setup_menu", wait_screen("DISK SETUP", 80))
    send_key(0x51) -- 'Q' back to Title
    assert_line("returned_title_clean", wait_title() and prog:read_u8(DISK_SETUP_DONE_ADDR) == 0)
    manager.machine:exit()
end
"""

    elif scenario == "interchange_disk_save":
        assert state_out_path is not None
        out_path_lua = str(state_out_path).replace("\\", "\\\\")
        body = f"""
local function write_state(tbl)
    local parts = {{}}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            parts[#parts + 1] = string.format('"%s":[%s]', k, table.concat(v, ","))
        else
            parts[#parts + 1] = string.format('"%s":%d', k, v)
        end
    end
    local f = assert(io.open("{out_path_lua}", "w"))
    f:write("{{" .. table.concat(parts, ",") .. "}}")
    f:close()
end

function run()
    assert_line("subA_chargen_town_ready", start_new_game("A"))
    inv_seed(32, {{ITEM_SLOT_CLOAK, 1, 0, 0, 0, 1, 0, ITEM_PAGE_CLOAK}})
    inv_seed(33, {{ITEM_SLOT_DAGGER, 1, 0, 3, 4, 0, 2, ITEM_PAGE_DAGGER | 6}})
    prog:write_u8(ID_KNOWN_ADDR + (ITEM_RING_OF_LORDLY_PROTECTION_FIRE >> 3),
        prog:read_u8(ID_KNOWN_ADDR + (ITEM_RING_OF_LORDLY_PROTECTION_FIRE >> 3)) | (1 << (ITEM_RING_OF_LORDLY_PROTECTION_FIRE & 7)))
    prog:write_u8(ID_KNOWN_ADDR + (ITEM_POTION_OF_RESTORE_STRENGTH >> 3),
        prog:read_u8(ID_KNOWN_ADDR + (ITEM_POTION_OF_RESTORE_STRENGTH >> 3)) | (1 << (ITEM_POTION_OF_RESTORE_STRENGTH & 7)))
    if RECALL_ADDR ~= 0 then
        prog:write_u8(RECALL_ADDR + 5, 0x5A)
        prog:write_u8(RECALL_ADDR + 1110, 0xA5)
    end
    local shuf = {{}}
    for i = 0, 173 do shuf[#shuf + 1] = prog:read_u8(SHUFFLES_ADDR + i) end
    local known = {{}}
    for i = 0, 46 do known[#known + 1] = prog:read_u8(ID_KNOWN_ADDR + i) end
    local cloak = {{}}
    for k = 0, 7 do cloak[#cloak + 1] = inv_field(32, k) end
    local sec = {{}}
    for k = 0, 7 do sec[#sec + 1] = inv_field(33, k) end
    local rec = {{
        RECALL_ADDR ~= 0 and prog:read_u8(RECALL_ADDR + 5) or 0,
        RECALL_ADDR ~= 0 and prog:read_u8(RECALL_ADDR + 1110) or 0,
    }}
    write_state({{
        px = prog:read_u8(PLAYER_X_ADDR),
        py = prog:read_u8(PLAYER_Y_ADDR),
        lvl = prog:read_u8(PLAYER_LVL_ADDR),
        hp_lo = prog:read_u8(PLAYER_HP_LO_ADDR),
        hp_hi = prog:read_u8(PLAYER_HP_HI_ADDR),
        cloak = cloak,
        sec = sec,
        shuf = shuf,
        known = known,
        rec = rec,
    }})

    send_key(0xD3) -- Shift+S -> Disk Setup
    assert_line("subA_disk_setup", wait_screen("DISK SETUP", 80))
    send_key(0x33) -- '3' Done (default Save: D2:)
    assert_line("subA_init_prompt", wait_screen("Initialize this disk? (Y/N)", 80))
    send_key(0x59) -- 'Y'
    assert_line("subA_slot_prompt", wait_screen("Select Slot 1-4", 120))
    send_key(0x31) -- Slot 1
    for _ = 1, 300 do
        wait_frames(15)
        if screen_has("Overwrite?") then send_key(0x59) end
        if screen_has("-more-") or screen_has("saved") then send_key(0x20) end
        if screen_has("N)ew") and screen_has("L)oad") then break end
    end
    assert_line("subA_title_after_disk_save", screen_has("N)ew") and screen_has("L)oad"))
    assert_line("subA_flushed_save_sectors", flush_save_atr() >= 55)
    manager.machine:exit()
end
"""

    elif scenario == "interchange_cart_load_and_save":
        assert state_in_path is not None and state_out_path is not None
        in_state = json.loads(state_in_path.read_text(encoding="utf-8"))
        cloak_lua = "{" + ",".join(map(str, in_state["cloak"])) + "}"
        sec_lua = "{" + ",".join(map(str, in_state["sec"])) + "}"
        shuf_lua = "{" + ",".join(map(str, in_state["shuf"])) + "}"
        known_lua = "{" + ",".join(map(str, in_state["known"])) + "}"
        rec_lua = "{" + ",".join(map(str, in_state["rec"])) + "}"
        out_path_lua = str(state_out_path).replace("\\", "\\\\")
        body = f"""
local EXPECT_PX = {in_state["px"]}
local EXPECT_PY = {in_state["py"]}
local EXPECT_LVL = {in_state["lvl"]}
local EXPECT_HP_LO = {in_state["hp_lo"]}
local EXPECT_HP_HI = {in_state["hp_hi"]}
local EXPECT_CLOAK = {cloak_lua}
local EXPECT_SEC = {sec_lua}
local EXPECT_SHUF = {shuf_lua}
local EXPECT_KNOWN = {known_lua}
local EXPECT_REC = {rec_lua}

local function write_state(tbl)
    local parts = {{}}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            parts[#parts + 1] = string.format('"%s":[%s]', k, table.concat(v, ","))
        else
            parts[#parts + 1] = string.format('"%s":%d', k, v)
        end
    end
    local f = assert(io.open("{out_path_lua}", "w"))
    f:write("{{" .. table.concat(parts, ",") .. "}}")
    f:close()
end

function run()
    assert_line("subB_cart_title", wait_title())
    local saw_insert_prompt = false
    local function check_no_insert()
        if screen_has("Insert") then saw_insert_prompt = true end
    end

    send_key(0x4C) -- 'L' Load -> triggers Disk Setup
    assert_line("subB_disk_setup", wait_screen("DISK SETUP", 80))
    send_key(0x31) -- '1) Use D1: for saves' (save.atr already has MORIA8.ID!)
    local slots_ok = wait_screen("Select Slot 1-4", 120)
    if not slots_ok then
        print(string.format("DIAG save_dev=%d disk_mode=%d disk_setup_done=%d pc=%04X",
            prog:read_u8(SAVE_DEV_ADDR), prog:read_u8(DISK_MODE_ADDR),
            prog:read_u8(DISK_SETUP_DONE_ADDR), cpu.state["PC"].value))
        for r = 0, 24 do
            local t = rowtext(r)
            if string.match(t, "%S") then print(string.format("DIAG R%02d: %s", r, t)) end
        end
    end
    assert_line("subB_load_slots", slots_ok)
    check_no_insert()
    assert_line("subB_d1_single_drive_flags",
        prog:read_u8(SAVE_DEV_ADDR) == 8
        and prog:read_u8(DISK_MODE_ADDR) == 2
        and prog:read_u8(DISK_SETUP_DONE_ADDR) == 1)

    send_key(0x31) -- Slot 1
    for _ = 1, 300 do
        wait_frames(15)
        check_no_insert()
        if prog:read_u8(PLAYER_X_ADDR) > 0 and screen_has("Welcome back") then break end
    end
    assert_line("subB_cart_loaded_disk_save",
        prog:read_u8(PLAYER_X_ADDR) == EXPECT_PX
        and prog:read_u8(PLAYER_Y_ADDR) == EXPECT_PY
        and prog:read_u8(PLAYER_LVL_ADDR) == EXPECT_LVL
        and prog:read_u8(PLAYER_HP_LO_ADDR) == EXPECT_HP_LO
        and prog:read_u8(PLAYER_HP_HI_ADDR) == EXPECT_HP_HI)

    local ok_restored = INV_STRIDE == 34 and RECALL_ADDR ~= 0
    for k = 1, 8 do
        if inv_field(32, k - 1) ~= EXPECT_CLOAK[k] then ok_restored = false end
        if inv_field(33, k - 1) ~= EXPECT_SEC[k] then ok_restored = false end
    end
    for i = 1, 174 do
        if prog:read_u8(SHUFFLES_ADDR + i - 1) ~= EXPECT_SHUF[i] then ok_restored = false end
    end
    for i = 1, 47 do
        if prog:read_u8(ID_KNOWN_ADDR + i - 1) ~= EXPECT_KNOWN[i] then ok_restored = false end
    end
    if RECALL_ADDR == 0 or prog:read_u8(RECALL_ADDR + 5) ~= EXPECT_REC[1] or prog:read_u8(RECALL_ADDR + 1110) ~= EXPECT_REC[2] then
        ok_restored = false
    end
    assert_line("subB_state_matches_subA", ok_restored)
    assert_line("subB_trig3_gintlk_clean_after_load",
        prog:read_u8(0xD013) == 0 and prog:read_u8(0x03FA) == 0)

    -- Mutate slot 33 + known bits + recall, save with Overwrite cancel 'N' first, then confirm 'Y'.
    inv_seed(33, {{ITEM_SLOT_MACE, 1, 0, 1, 2, 0, 2, ITEM_PAGE_MACE}})
    prog:write_u8(ID_KNOWN_ADDR + (ITEM_RING_OF_LORDLY_PROTECTION_ACID >> 3),
        prog:read_u8(ID_KNOWN_ADDR + (ITEM_RING_OF_LORDLY_PROTECTION_ACID >> 3)) | (1 << (ITEM_RING_OF_LORDLY_PROTECTION_ACID & 7)))
    prog:write_u8(ID_KNOWN_ADDR + (ITEM_SCROLL_OF_HOLY_CHANT >> 3),
        prog:read_u8(ID_KNOWN_ADDR + (ITEM_SCROLL_OF_HOLY_CHANT >> 3)) | (1 << (ITEM_SCROLL_OF_HOLY_CHANT & 7)))
    if RECALL_ADDR ~= 0 then prog:write_u8(RECALL_ADDR + 5, 0x3C) end
    local shuf2, known2, cloak2, sec2 = {{}}, {{}}, {{}}, {{}}
    for i = 0, 173 do shuf2[#shuf2 + 1] = prog:read_u8(SHUFFLES_ADDR + i) end
    for i = 0, 46 do known2[#known2 + 1] = prog:read_u8(ID_KNOWN_ADDR + i) end
    for k = 0, 7 do cloak2[#cloak2 + 1] = inv_field(32, k) end
    for k = 0, 7 do sec2[#sec2 + 1] = inv_field(33, k) end
    local rec2 = {{
        RECALL_ADDR ~= 0 and prog:read_u8(RECALL_ADDR + 5) or 0,
        RECALL_ADDR ~= 0 and prog:read_u8(RECALL_ADDR + 1110) or 0,
    }}
    write_state({{
        px = prog:read_u8(PLAYER_X_ADDR),
        py = prog:read_u8(PLAYER_Y_ADDR),
        cloak = cloak2,
        sec = sec2,
        shuf = shuf2,
        known = known2,
        rec = rec2,
    }})

    send_key(0xD3) -- Shift+S -> Select Slot 1-4
    assert_line("subB_save_slot_prompt_1", wait_screen("Select Slot 1-4", 80))
    check_no_insert()
    send_key(0x31) -- Slot 1
    assert_line("subB_overwrite_prompt_1", wait_screen("Overwrite?", 80))
    send_key(0x4E) -- 'N' cancel overwrite
    for _ = 1, 80 do
        emu.wait(0.1)
        check_no_insert()
        if in_town() then break end
    end
    assert_line("subB_overwrite_cancel_returned_town", in_town())

    send_key(0xD3) -- Shift+S again
    assert_line("subB_save_slot_prompt_2", wait_screen("Select Slot 1-4", 80))
    check_no_insert()
    send_key(0x31) -- Slot 1
    assert_line("subB_overwrite_prompt_2", wait_screen("Overwrite?", 80))
    send_key(0x59) -- 'Y' confirm overwrite
    for _ = 1, 300 do
        wait_frames(15)
        check_no_insert()
        if screen_has("-more-") or screen_has("saved") then send_key(0x20) end
        if screen_has("N)ew") and screen_has("L)oad") then break end
    end
    assert_line("subB_title_after_cart_save", screen_has("N)ew") and screen_has("L)oad"))
    assert_line("subB_zero_swap_prompts", not saw_insert_prompt)
    assert_line("subB_trig3_gintlk_clean_after_save",
        prog:read_u8(0xD013) == 0 and prog:read_u8(0x03FA) == 0)
    assert_line("subB_flushed_save_sectors", flush_save_atr() >= 55)
    manager.machine:exit()
end
"""

    elif scenario == "interchange_disk_reload":
        assert state_in_path is not None
        in_state = json.loads(state_in_path.read_text(encoding="utf-8"))
        cloak_lua = "{" + ",".join(map(str, in_state["cloak"])) + "}"
        sec_lua = "{" + ",".join(map(str, in_state["sec"])) + "}"
        shuf_lua = "{" + ",".join(map(str, in_state["shuf"])) + "}"
        known_lua = "{" + ",".join(map(str, in_state["known"])) + "}"
        rec_lua = "{" + ",".join(map(str, in_state["rec"])) + "}"
        body = f"""
local EXPECT_PX = {in_state["px"]}
local EXPECT_PY = {in_state["py"]}
local EXPECT_CLOAK = {cloak_lua}
local EXPECT_SEC = {sec_lua}
local EXPECT_SHUF = {shuf_lua}
local EXPECT_KNOWN = {known_lua}
local EXPECT_REC = {rec_lua}

function run()
    assert_line("subC_disk_title", wait_title())
    send_key(0x44) -- 'D' Disk Setup
    assert_line("subC_disk_setup", wait_screen("DISK SETUP", 80))
    send_key(0x33) -- '3' Done (default Save: D2:, already has MORIA8.ID)
    assert_line("subC_returned_title", wait_title())

    send_key(0x4C) -- 'L' Load
    assert_line("subC_load_slots", wait_screen("Select Slot 1-4", 80))
    send_key(0x31) -- Slot 1
    for _ = 1, 300 do
        wait_frames(15)
        if prog:read_u8(PLAYER_X_ADDR) > 0 and screen_has("Welcome back") then break end
    end
    assert_line("subC_disk_loaded_cart_save",
        prog:read_u8(PLAYER_X_ADDR) == EXPECT_PX and prog:read_u8(PLAYER_Y_ADDR) == EXPECT_PY)

    local ok_restored = INV_STRIDE == 34 and RECALL_ADDR ~= 0
    for k = 1, 8 do
        if inv_field(32, k - 1) ~= EXPECT_CLOAK[k] then ok_restored = false end
        if inv_field(33, k - 1) ~= EXPECT_SEC[k] then ok_restored = false end
    end
    for i = 1, 174 do
        if prog:read_u8(SHUFFLES_ADDR + i - 1) ~= EXPECT_SHUF[i] then ok_restored = false end
    end
    for i = 1, 47 do
        if prog:read_u8(ID_KNOWN_ADDR + i - 1) ~= EXPECT_KNOWN[i] then ok_restored = false end
    end
    if RECALL_ADDR == 0 or prog:read_u8(RECALL_ADDR + 5) ~= EXPECT_REC[1] or prog:read_u8(RECALL_ADDR + 1110) ~= EXPECT_REC[2] then
        ok_restored = false
    end
    assert_line("subC_state_matches_subB", ok_restored)
    manager.machine:exit()
end
"""
    elif scenario == "interchange_cart_negative":
        body = """
function run()
    local flop1 = nil
    for _, image in pairs(manager.machine.images) do
        if image.filename == "V21_ATR" then flop1 = image end
    end
    assert_line("cart_neg_flop1_found", flop1 ~= nil)
    assert_line("cart_neg_title", wait_title())

    -- 1. Wrong version ($21 -> Unsupported save.) via D1: Disk Setup -> Slot 1
    send_key(0x4C) -- 'L'
    assert_line("cart_neg_disk_setup", wait_screen("DISK SETUP", 80))
    send_key(0x31) -- '1) Use D1: for saves'
    assert_line("cart_neg_v21_slots", wait_screen("Select Slot 1-4", 120))
    send_key(0x31) -- Slot 1
    assert_line("cart_neg_v21_rejected", wait_screen("Unsupported save.", 100) and not in_town())
    send_key(0x20)
    assert_line("cart_neg_v21_title_recovery", wait_title())

    -- 2. Truncated Save V2 (64 B -> Save file corrupt!)
    assert_line("cart_neg_mount_trunc", flop1:load("TRUNC_ATR") == nil)
    send_key(0x4C)
    assert_line("cart_neg_trunc_slots", wait_screen("Select Slot 1-4", 100))
    send_key(0x31)
    assert_line("cart_neg_trunc_rejected", wait_screen("Save file corrupt!", 100) and not in_town())
    send_key(0x20)
    assert_line("cart_neg_trunc_title_recovery", wait_title())

    -- 3. Corrupt checksum at full byte count (-> Save file corrupt!)
    assert_line("cart_neg_mount_cksum", flop1:load("CKSUM_ATR") == nil)
    send_key(0x4C)
    assert_line("cart_neg_cksum_slots", wait_screen("Select Slot 1-4", 100))
    send_key(0x31)
    assert_line("cart_neg_cksum_rejected", wait_screen("Save file corrupt!", 120) and not in_town())
    send_key(0x20)
    assert_line("cart_neg_cksum_title_recovery", wait_title())

    -- 4. Restore valid Save V2 ATR and verify clean load recovery
    assert_line("cart_neg_mount_valid", flop1:load("VALID_ATR") == nil)
    send_key(0x4C)
    assert_line("cart_neg_valid_slots", wait_screen("Select Slot 1-4", 100))
    send_key(0x31)
    for _ = 1, 300 do
        wait_frames(15)
        if prog:read_u8(PLAYER_X_ADDR) > 0 and screen_has("Welcome back") then break end
    end
    assert_line("cart_neg_valid_reload_ok", prog:read_u8(PLAYER_X_ADDR) > 0 and in_town())
    manager.machine:exit()
end
"""
    else:
        raise ValueError(f"Unknown Lua scenario: {scenario}")

    return header + body + "\nco = coroutine.create(run)\ncoroutine.resume(co)\n"


def mutate_atr_save(src_atr: Path, dst_atr: Path, mode: str) -> None:
    """Copy a DOS 2.5 save ATR and corrupt SAVE0.SAV ('v21', 'trunc', or 'cksum')."""
    data = bytearray(src_atr.read_bytes())
    atr_hdr = 16
    sec_sz = 128
    start_sec = None
    for idx in range(64):
        dir_sec = 361 + (idx // 8)
        ent_off = atr_hdr + (dir_sec - 1) * sec_sz + (idx % 8) * 16
        flags = data[ent_off]
        if flags == 0:
            break
        if flags & 0x80:
            continue
        if data[ent_off + 5 : ent_off + 16] == b"SAVE0   SAV":
            start_sec = data[ent_off + 3] | (data[ent_off + 4] << 8)
            break
    if not start_sec:
        raise AssertionError(f"SAVE0   SAV not found in {src_atr}")

    chain: list[tuple[int, int]] = []
    sec = start_sec
    seen: set[int] = set()
    while sec != 0:
        if sec in seen:
            raise AssertionError(f"Cycle in SAVE0   SAV chain at sector {sec}")
        seen.add(sec)
        sec_off = atr_hdr + (sec - 1) * sec_sz
        cnt = data[sec_off + 0x7D]
        next_sec = ((data[sec_off + 0x7E] & 0x03) << 8) | data[sec_off + 0x7F]
        chain.append((sec, cnt))
        sec = next_sec

    sec0_off = atr_hdr + (start_sec - 1) * sec_sz
    if data[sec0_off : sec0_off + 8] != b"MORIA01\x22":
        raise AssertionError(f"Expected MORIA01\\x22 header in {src_atr}, got {data[sec0_off : sec0_off + 8]!r}")

    if mode == "v21":
        data[sec0_off + 7] = 0x21
    elif mode == "trunc":
        data[sec0_off + 0x7D] = 64
        data[sec0_off + 0x7E] &= 0xFC
        data[sec0_off + 0x7F] = 0
    elif mode == "cksum":
        last_sec, last_cnt = chain[-1]
        if last_cnt == 0:
            raise AssertionError(f"Empty tail sector {last_sec} in {src_atr}")
        last_off = atr_hdr + (last_sec - 1) * sec_sz + last_cnt - 1
        data[last_off] ^= 0xFF
    else:
        raise ValueError(f"Unknown mutation mode: {mode}")

    dst_atr.write_bytes(bytes(data))


def _run_mame(
    label: str,
    machine: str,
    rompath: str,
    mame_bin: str,
    lua_code: str,
    *,
    car_path: Path | None = None,
    flop1_path: Path | None = None,
    flop2_path: Path | None = None,
) -> bool:
    for output_dir in MAME_OUTPUT_DIRS.values():
        output_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmpdir:
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
        ]
        if car_path is not None:
            cmd.extend(["-cart1", str(car_path)])
        if flop1_path is not None:
            cmd.extend(["-flop1", str(flop1_path)])
        if flop2_path is not None:
            cmd.extend(["-flop2", str(flop2_path)])
        cmd.extend(
            [
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
        )

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
                f"[{label}] FAIL: host timeout ({HOST_TIMEOUT_SECONDS}s)",
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
                print(f"[{label}] {line}", file=sys.stderr)

        if fails > 0 or passes == 0:
            for line in out.splitlines():
                if line.startswith("DIAG "):
                    print(f"[{label}] {line}", file=sys.stderr)
            if passes == 0 and out.strip():
                print(out.strip(), file=sys.stderr)
            print(
                f"[{label}] FAIL (passes={passes}, fails={fails})",
                file=sys.stderr,
            )
            return False

        print(f"[{label}] PASS ({passes} assertions)")
        return True


def run_scenario(
    scenario: str,
    rompath: str,
    car_path: Path,
    cart_sym_path: Path,
    catalog_prg_path: Path,
    disk_path: Path,
    disk_sym_path: Path,
    mame_bin: str = "mame",
) -> bool:
    cart_syms = parse_symbols(cart_sym_path)
    disk_syms = parse_symbols(disk_sym_path)

    if scenario == "cold_boot_gameplay_legal_a800xl":
        lua_code = build_lua_script(scenario, cart_syms)
        return _run_mame(
            f"a800xl:{scenario}",
            "a800xl",
            rompath,
            mame_bin,
            lua_code,
            car_path=car_path,
        )

    if scenario == "cold_boot_and_catalog_279_a130xe":
        if not catalog_prg_path.is_file():
            print(f"error: catalog test binary missing: {catalog_prg_path}", file=sys.stderr)
            return False
        lua_code = build_lua_script(scenario, cart_syms, catalog_prg_path=catalog_prg_path)
        return _run_mame(
            f"a130xe:{scenario}",
            "a130xe",
            rompath,
            mame_bin,
            lua_code,
            car_path=car_path,
        )

    if scenario == "disk_setup_guards_a800xl":
        if not disk_path.is_file():
            print(f"error: disk image missing: {disk_path}", file=sys.stderr)
            return False
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_atr = Path(tmpdir) / "prog.atr"
            shutil.copy2(disk_path, tmp_atr)
            lua_code = build_lua_script(scenario, cart_syms)
            return _run_mame(
                f"a800xl:{scenario}",
                "a800xl",
                rompath,
                mame_bin,
                lua_code,
                car_path=car_path,
                flop1_path=tmp_atr,
            )

    if scenario == "save_persistence_and_disk_interchange":
        if not disk_path.is_file():
            print(f"error: disk image missing: {disk_path}", file=sys.stderr)
            return False
        if not disk_syms:
            print(f"error: disk symbols missing: {disk_sym_path}", file=sys.stderr)
            return False
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_dir = Path(tmpdir)
            tmp_prog = tmp_dir / "prog.atr"
            tmp_save = tmp_dir / "save.atr"
            shutil.copy2(disk_path, tmp_prog)
            build_blank_atr(tmp_save)
            state_a = tmp_dir / "state_a.json"
            state_b = tmp_dir / "state_b.json"

            lua_a = build_lua_script(
                "interchange_disk_save",
                disk_syms,
                state_out_path=state_a,
                save_atr_sync_path=tmp_save,
                save_dunit=2,
            )
            if not _run_mame(
                "a800xl:interchange_disk_save",
                "a800xl",
                rompath,
                mame_bin,
                lua_a,
                flop1_path=tmp_prog,
                flop2_path=tmp_save,
            ):
                return False

            lua_b = build_lua_script(
                "interchange_cart_load_and_save",
                cart_syms,
                state_in_path=state_a,
                state_out_path=state_b,
                save_atr_sync_path=tmp_save,
                save_dunit=1,
            )
            if not _run_mame(
                "a800xl:interchange_cart_load_and_save",
                "a800xl",
                rompath,
                mame_bin,
                lua_b,
                car_path=car_path,
                flop1_path=tmp_save,
            ):
                return False

            lua_c = build_lua_script("interchange_disk_reload", disk_syms, state_in_path=state_b)
            if not _run_mame(
                "a800xl:interchange_disk_reload",
                "a800xl",
                rompath,
                mame_bin,
                lua_c,
                flop1_path=tmp_prog,
                flop2_path=tmp_save,
            ):
                return False

            tmp_v21 = tmp_dir / "save_v21.atr"
            tmp_trunc = tmp_dir / "save_trunc.atr"
            tmp_cksum = tmp_dir / "save_cksum.atr"
            mutate_atr_save(tmp_save, tmp_v21, "v21")
            mutate_atr_save(tmp_save, tmp_trunc, "trunc")
            mutate_atr_save(tmp_save, tmp_cksum, "cksum")
            lua_neg = (
                build_lua_script("interchange_cart_negative", cart_syms)
                .replace("V21_ATR", str(tmp_v21))
                .replace("TRUNC_ATR", str(tmp_trunc))
                .replace("CKSUM_ATR", str(tmp_cksum))
                .replace("VALID_ATR", str(tmp_save))
            )
            if not _run_mame(
                "a800xl:interchange_cart_negative",
                "a800xl",
                rompath,
                mame_bin,
                lua_neg,
                car_path=car_path,
                flop1_path=tmp_v21,
            ):
                return False
            return True

    raise ValueError(f"Unknown scenario: {scenario}")


def selftest() -> int:
    assert HOST_TIMEOUT_SECONDS <= 30, "AGENTS.md Rule 8 requires timeout <= 30s"
    assert parse_symbols(Path("nonexistent_sym_file")) == {}
    assert sc_to_ascii(0x00) == "@" and sc_to_ascii(0x01) == "a" and sc_to_ascii(0x40) == "-" and sc_to_ascii(0x41) == "A"

    sums = expected_catalog_checksums()
    assert len(sums) == catalog_lore.const("CATALOG_COUNT") == 279

    syms = parse_symbols(CART_SYM_PATH)
    for sc in ("cold_boot_gameplay_legal_a800xl", "cold_boot_and_catalog_279_a130xe", "disk_setup_guards_a800xl"):
        lua = build_lua_script(sc, syms, catalog_prg_path=CAT_TEST_PRG)
        assert "_G.harness_key_poll_tap" in lua
        assert "assert_line(" in lua and "coroutine.resume" in lua

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        st_a = tmp / "a.json"
        st_b = tmp / "b.json"
        st_a.write_text(
            json.dumps(
                {
                    "px": 10,
                    "py": 12,
                    "lvl": 1,
                    "hp_lo": 20,
                    "hp_hi": 0,
                    "cloak": [item_ids.ITEM_SLOT_CLOAK] + [0] * 6 + [item_ids.ITEM_PAGE_CLOAK],
                    "sec": [1] * 8,
                    "shuf": [2] * 174,
                    "known": [3] * 47,
                    "rec": [4, 5],
                }
            ),
            encoding="utf-8",
        )
        sync_atr = tmp / "save.atr"
        for sc, dunit in (("interchange_disk_save", 2), ("interchange_cart_load_and_save", 1)):
            lua = build_lua_script(
                sc,
                syms,
                state_in_path=st_a,
                state_out_path=st_b,
                save_atr_sync_path=sync_atr,
                save_dunit=dunit,
            )
            assert "_G.harness_key_poll_tap" in lua and "assert_line(" in lua
            assert "_G.harness_sio_writeback_tap" in lua
        lua_reload = build_lua_script("interchange_disk_reload", syms, state_in_path=st_a, state_out_path=st_b)
        assert "_G.harness_key_poll_tap" in lua_reload and "assert_line(" in lua_reload
        lua_neg = build_lua_script("interchange_cart_negative", syms)
        assert "_G.harness_key_poll_tap" in lua_neg and "assert_line(" in lua_neg

        from make_atr import AtrBuilder
        builder = AtrBuilder()
        builder.add_file("MORIA8.ID", b"M8SAVE")
        payload_v22 = b"MORIA01\x22" + (b"\x5a" * 300)
        builder.add_file("SAVE0.SAV", payload_v22)
        synth = tmp / "synth.atr"
        synth.write_bytes(builder.to_bytes())
        v21_atr = tmp / "v21.atr"
        trunc_atr = tmp / "trunc.atr"
        cksum_atr = tmp / "cksum.atr"
        mutate_atr_save(synth, v21_atr, "v21")
        mutate_atr_save(synth, trunc_atr, "trunc")
        mutate_atr_save(synth, cksum_atr, "cksum")
        # Locate start sector of SAVE0   SAV
        raw_synth = synth.read_bytes()
        s_sec = None
        for idx in range(64):
            eo = 16 + (361 + idx // 8 - 1) * 128 + (idx % 8) * 16
            if raw_synth[eo + 5 : eo + 16] == b"SAVE0   SAV":
                s_sec = raw_synth[eo + 3] | (raw_synth[eo + 4] << 8)
                break
        assert s_sec is not None
        s0 = 16 + (s_sec - 1) * 128
        assert v21_atr.read_bytes()[s0 + 7] == 0x21
        assert trunc_atr.read_bytes()[s0 + 0x7D] == 64
        assert (trunc_atr.read_bytes()[s0 + 0x7E] & 3) == 0 and trunc_atr.read_bytes()[s0 + 0x7F] == 0
        # Walk chain to verify tail checksum byte flipped
        c = s_sec
        while True:
            co = 16 + (c - 1) * 128
            nxt = ((raw_synth[co + 0x7E] & 3) << 8) | raw_synth[co + 0x7F]
            if nxt == 0:
                tail = co + raw_synth[co + 0x7D] - 1
                assert cksum_atr.read_bytes()[tail] == (raw_synth[tail] ^ 0xFF)
                break
            c = nxt

    print("Atari 8-bit test_cartridge.py self-test: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--rompath", default=os.environ.get("ATARI8ROMS", ""))
    parser.add_argument("--car", type=Path, default=CAR_IMAGE)
    parser.add_argument("--sym", type=Path, default=CART_SYM_PATH)
    parser.add_argument("--catalog-test", type=Path, default=CAT_TEST_PRG)
    parser.add_argument("--disk", type=Path, default=DISK_IMAGE)
    parser.add_argument("--disk-sym", type=Path, default=DISK_SYM_PATH)
    parser.add_argument("--mame", default=os.environ.get("MAME", "mame"))
    parser.add_argument("--scenario", choices=SCENARIOS, default=None)
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    if not args.rompath:
        print("WARNING: ATARI8ROMS not set; skipping Atari 8-bit MAME cartridge runtime suite")
        return 0

    if not args.car.is_file():
        print(f"error: cartridge image missing: {args.car} (run make cartridgeatari8)", file=sys.stderr)
        return 1

    targets = (args.scenario,) if args.scenario else SCENARIOS
    for sc in targets:
        ok = run_scenario(
            sc,
            args.rompath,
            args.car,
            args.sym,
            args.catalog_test,
            args.disk,
            args.disk_sym,
            args.mame,
        )
        if not ok:
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
