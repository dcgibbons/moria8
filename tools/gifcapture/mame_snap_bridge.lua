-- Moria8 gameplay capture bridge for MAME (extends playtest/moria_playtest/mame_bridge.lua).
--
-- Keeps the exact FIFO protocol of mame_bridge.lua (R, W, K, X) and adds:
--   SNAP <relpath> [wait_frames]
--     Advances `wait_frames` completed video frames (default 2) while
--     input_get_key polls idly so the CRT/video chip finishes scanning out
--     the updated screen RAM, captures a tear-free PNG via screen:snapshot()
--     (or manager.machine.video:snapshot() fallback) at frame_done, and
--     responds "O" once the snapshot is written and the CPU re-enters the wait.
--     If wait_frames == 0, captures immediately without advancing frames.
--
-- Configuration, from the environment:
--   MORIA8_BRIDGE_IN, MORIA8_BRIDGE_OUT  FIFO paths (driver -> MAME, MAME -> driver)
--   MORIA8_BRIDGE_ITEMS  name=<device tag>/<save item>;...  RAM readable by name
--   MORIA8_BRIDGE_TAPS   kind,<read address>,<pc low>,<pc high>[,<buffer>];...
--   MORIA8_BRIDGE_HANG   emulated seconds without a key wait before reporting
--   MORIA8_BRIDGE_BOOT   text typed one emulated second after start (BBC *EXEC !BOOT)

local machine = manager.machine
local cpu = machine.devices[":maincpu"]
local program = cpu.spaces["program"]
local fin = assert(io.open(os.getenv("MORIA8_BRIDGE_IN"), "r"))
local fout = assert(io.open(os.getenv("MORIA8_BRIDGE_OUT"), "w"))
local hang_s = tonumber(os.getenv("MORIA8_BRIDGE_HANG") or "300")

local primary_screen = nil
for _, scr in pairs(machine.screens) do
  primary_screen = scr
  break
end

local spaces = {
  cpu = {
    read = function(addr, len) return program:read_range(addr, addr + len - 1, 8) end,
    write = function(addr, data)
      for i = 1, #data do program:write_u8(addr + i - 1, data:byte(i)) end
    end,
  },
}
for name, tag, item in (os.getenv("MORIA8_BRIDGE_ITEMS") or ""):gmatch("(%w+)=([^/;]+)/([^;]+)") do
  local it = emu.item(machine.devices[tag].items[item])
  spaces[name] = {
    read = function(addr, len) return it:read_block(addr, len) end,
    write = function(addr, data)
      for i = 1, #data do it:write(addr + i - 1, data:byte(i)) end
    end,
  }
end

local last_key_time = nil   -- the hang clock starts at the first key wait
local stopped = false
local pending_snap = nil    -- { path = string, frames = int }
local snap_done = false

local function reg(name) return cpu.state[name].value end

local function hex(data)
  return (data:gsub(".", function(c) return string.format("%02X", c:byte()) end))
end

local function unhex(text)
  return (text:gsub("..", function(h) return string.char(tonumber(h, 16)) end))
end

local function capture_now(relpath)
  if primary_screen ~= nil and relpath ~= nil and relpath ~= "" then
    primary_screen:snapshot(relpath)
  else
    machine.video:snapshot()
  end
end

-- Report a stop (or "O" after an async SNAP) and serve commands until a key
-- or async SNAP resumes execution; nil on exit or async SNAP continuation.
local function serve(kind)
  stopped = true
  if kind == "O" then
    fout:write("O\n")
  else
    fout:write(string.format("%s %04X %02X %02X %02X %02X %.6f\n", kind, reg("PC"), reg("SP") & 0xFF,
                             reg("A"), reg("X"), reg("Y"), machine.time:as_double()))
  end
  fout:flush()
  while true do
    local line = fin:read("l")
    if line == nil then machine:exit() stopped = false return nil end
    local op, a, b, c = line:match("^(%u+)%s*(%S*)%s*(%S*)%s*(%S*)")
    if op == "R" then
      fout:write("D " .. hex(spaces[a].read(tonumber(b, 16), tonumber(c))) .. "\n")
      fout:flush()
    elseif op == "W" then
      spaces[a].write(tonumber(b, 16), unhex(c))
      fout:write("O\n")
      fout:flush()
    elseif op == "SNAP" then
      local wait_frames = tonumber(b) or 2
      if wait_frames <= 0 then
        capture_now(a)
        fout:write("O\n")
        fout:flush()
      else
        pending_snap = { path = a, frames = wait_frames }
        last_key_time = machine.time:as_double()
        stopped = false
        return nil
      end
    elseif op == "K" then
      last_key_time = machine.time:as_double()
      stopped = false
      return tonumber(a, 16)
    else   -- "X" or anything unknown
      machine:exit()
      stopped = false
      return nil
    end
  end
end

emu.register_frame_done(function()
  if pending_snap ~= nil then
    pending_snap.frames = pending_snap.frames - 1
    if pending_snap.frames <= 0 then
      capture_now(pending_snap.path)
      pending_snap = nil
      snap_done = true
    end
  end
end)

_G.moria8_taps = {}
for kind, addr, lo, hi, buffer in (os.getenv("MORIA8_BRIDGE_TAPS") or ""):gmatch(
    "(%a+),(%x+),(%x+),(%x+),?(%x*)") do
  addr, lo, hi = tonumber(addr, 16), tonumber(lo, 16), tonumber(hi, 16)
  buffer = tonumber(buffer, 16)
  local tap = program:install_read_tap(addr, addr, "moria8_" .. kind, function(offset, data, mask)
    local pc = reg("PC")
    if stopped or pending_snap ~= nil or pc < lo or pc > hi then return end
    -- A buffer wait polls an empty buffer; a non-zero count is the game's own
    -- read-modify-write taking the key just fed (the Atari's dec).
    if kind == "buffer" and data ~= 0 then return end
    local key
    if snap_done then
      snap_done = false
      key = serve("O")
    else
      key = serve("S")
    end
    if key == nil then return end
    if kind == "latch" then return key | 0x80 end
    program:write_u8(buffer, key)
    program:write_u8(addr, 1)
    return 1
  end)
  table.insert(_G.moria8_taps, tap)
end

local fastboot_manifest = os.getenv("MORIA8_BBC_FASTBOOT") or ""
local boot_text = (fastboot_manifest == "") and (os.getenv("MORIA8_BRIDGE_BOOT") or "") or ""
local fb_state = (fastboot_manifest ~= "") and "wait_boot" or "none"
local FAST_BOOT_STUB = 0x0900

local function bbc_fastboot_install()
  local dfs = nil
  for bank = 0, 15 do
    program:write_u8(0xFE30, bank)
    local t = ""
    for a = 0x8009, 0x800C do t = t .. string.char(program:read_u8(a)) end
    if t:sub(1, 3) == "DFS" then dfs = bank end
  end
  program:write_u8(0xFE30, program:read_u8(0x00F4))
  if dfs == nil then
    fb_state = "none"
    return
  end
  local stub = {
    0xA9, 0x16, 0x20, 0xEE, 0xFF,             -- VDU 22,
    0xA9, 0x87, 0x20, 0xEE, 0xFF,             -- 135: shadow Mode 7
    0xAD, 0x20, 0x09, 0xF0, 0xFB,             -- $090A: wait for $0920 != 0
    0xA9, 0x01, 0x8D, 0x34, 0xFE,             -- ACCCON $01: shadow shown, Main RAM
    0xA9, dfs, 0x85, 0xF4, 0x8D, 0x30, 0xFE,  -- filing-system ROM selected
    0x4C, 0x00, 0x0E                          -- jmp MORIA8.RES ($0E00)
  }
  for i, b in ipairs(stub) do program:write_u8(FAST_BOOT_STUB + i - 1, b) end
  program:write_u8(FAST_BOOT_STUB + 0x20, 0)
  machine.natkeyboard:post("*GO 900\r")
  fb_state = "wait_park"
end

local function bbc_fastboot_load()
  local f = assert(io.open(fastboot_manifest, "r"))
  for line in f:lines() do
    local b_hex, a_hex, path = line:match("^(%x+)%s+(%x+)%s+(.+)$")
    if b_hex then
      local bank = tonumber(b_hex, 16)
      local addr = tonumber(a_hex, 16)
      local pf = assert(io.open(path, "rb"))
      local data = pf:read("*a")
      pf:close()
      if bank ~= 0 then program:write_u8(0xFE30, bank) end
      for i = 1, #data do program:write_u8(addr + i - 1, data:byte(i)) end
      program:write_u8(0xFE30, program:read_u8(0x00F4))
    end
  end
  f:close()
  program:write_u8(FAST_BOOT_STUB + 0x20, 1)
  fb_state = "none"
end

emu.register_periodic(function()
  if fb_state == "wait_boot" and machine.time:as_double() > 1.0 then
    bbc_fastboot_install()
  elseif fb_state == "wait_park" then
    local pc = reg("PC")
    if pc >= FAST_BOOT_STUB + 0x0A and pc < FAST_BOOT_STUB + 0x0F then
      bbc_fastboot_load()
    end
  elseif fb_state == "none" and boot_text ~= "" and machine.time:as_double() > 1.0 then
    machine.natkeyboard:post(boot_text)
    boot_text = ""
  end
  if stopped or pending_snap ~= nil or last_key_time == nil then return end
  if machine.time:as_double() - last_key_time > hang_s then
    serve("H")
  end
end)
