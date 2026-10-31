-- Moria8 playtest bridge for MAME (playtest/moria_playtest/mame.py, §21.3).
--
-- MAME's debugger cannot be resumed from Lua once a breakpoint stops it, and
-- its 6502 fetches opcodes past memory taps, so the input checkpoint is a data
-- read: the game's key wait polling its key source (the Apple IIe's keyboard
-- latch, the Atari's and BBC's key buffers). The read tap blocks the emulator
-- there and serves the driver over two FIFOs until it feeds a key, which the
-- tap then hands to the game as the value read.
--
-- Configuration, from the environment:
--   MORIA8_BRIDGE_IN, MORIA8_BRIDGE_OUT  FIFO paths (driver -> MAME, MAME -> driver)
--   MORIA8_BRIDGE_ITEMS  name=<device tag>/<save item>;...  RAM readable by name
--   MORIA8_BRIDGE_TAPS   kind,<read address>,<pc low>,<pc high>[,<buffer>];...
--                        latch: return the key with bit 7 set (Apple IIe $C000)
--                        buffer: store the key at <buffer> and a count of 1 at
--                        the address read (the game decrements it), return 1
--   MORIA8_BRIDGE_HANG   emulated seconds without a key wait before reporting
--   MORIA8_BRIDGE_BOOT   text typed one emulated second after start (the BBC's *EXEC !BOOT)
--
-- Lines from MAME: "S|H pc sp a x y time" at a key wait (S) or a hang (H);
-- "D <hex>" and "O" answer reads and writes. Lines from the driver:
-- "R <space> <hex address> <length>", "W <space> <hex address> <hex>",
-- "K <hex key>" (feed and run), "X" (exit).

local machine = manager.machine
local cpu = machine.devices[":maincpu"]
local program = cpu.spaces["program"]
local fin = assert(io.open(os.getenv("MORIA8_BRIDGE_IN"), "r"))
local fout = assert(io.open(os.getenv("MORIA8_BRIDGE_OUT"), "w"))
local hang_s = tonumber(os.getenv("MORIA8_BRIDGE_HANG") or "300")

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

local function reg(name) return cpu.state[name].value end

local function hex(data)
  return (data:gsub(".", function(c) return string.format("%02X", c:byte()) end))
end

local function unhex(text)
  return (text:gsub("..", function(h) return string.char(tonumber(h, 16)) end))
end

-- Report a stop and serve commands until a key is fed; nil on exit.
local function serve(kind)
  stopped = true
  fout:write(string.format("%s %04X %02X %02X %02X %02X %.6f\n", kind, reg("PC"), reg("SP") & 0xFF,
                           reg("A"), reg("X"), reg("Y"), machine.time:as_double()))
  fout:flush()
  while true do
    local line = fin:read("l")
    if line == nil then machine:exit() stopped = false return nil end
    local op, a, b, c = line:match("^(%u)%s*(%S*)%s*(%S*)%s*(%S*)")
    if op == "R" then
      fout:write("D " .. hex(spaces[a].read(tonumber(b, 16), tonumber(c))) .. "\n")
      fout:flush()
    elseif op == "W" then
      spaces[a].write(tonumber(b, 16), unhex(c))
      fout:write("O\n")
      fout:flush()
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

_G.moria8_taps = {}
for kind, addr, lo, hi, buffer in (os.getenv("MORIA8_BRIDGE_TAPS") or ""):gmatch(
    "(%a+),(%x+),(%x+),(%x+),?(%x*)") do
  addr, lo, hi = tonumber(addr, 16), tonumber(lo, 16), tonumber(hi, 16)
  buffer = tonumber(buffer, 16)
  local tap = program:install_read_tap(addr, addr, "moria8_" .. kind, function(offset, data, mask)
    local pc = reg("PC")
    if stopped or pc < lo or pc > hi then return end
    -- A buffer wait polls an empty buffer; a non-zero count is the game's own
    -- read-modify-write taking the key just fed (the Atari's dec).
    if kind == "buffer" and data ~= 0 then return end
    local key = serve("S")
    if key == nil then return end
    if kind == "latch" then return key | 0x80 end
    program:write_u8(buffer, key)
    program:write_u8(addr, 1)
    return 1
  end)
  table.insert(_G.moria8_taps, tap)
end

local boot_text = os.getenv("MORIA8_BRIDGE_BOOT") or ""

emu.register_periodic(function()
  if boot_text ~= "" and machine.time:as_double() > 1.0 then
    machine.natkeyboard:post(boot_text)
    boot_text = ""
  end
  if stopped or last_key_time == nil then return end
  if machine.time:as_double() - last_key_time > hang_s then
    serve("H")
  end
end)
