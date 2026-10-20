do local h = io.open("STARTFILE","w") if h then h:write("1") h:close() end end
-- RPC driver: polls CMDFILE for one-line commands, answers in RESPFILE.
local CMD, RESP = "CMDFILE", "RESPFILE"
local prog = manager.machine.devices[":maincpu"].spaces["program"]
local aux = emu.item(manager.machine.devices[":aux:ext80"].items["0/m_ram"])
local keymap = {}
for tag, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do keymap[name] = field end
end
local function findkey(ch)
    if ch == "RET" then return keymap["Return"] end
    if ch == "SPC" then return keymap["Space"] end
    if ch == "ESC" then return keymap["Esc"] end
    if ch == "?" then return keymap["/  ?"] end
    if ch == "/" then return keymap["/  ?"] end
    if ch == "." then return keymap[".  >"] end
    if ch == "," then return keymap[",  <"] end
    if ch == "+" then return keymap["=  +"] end
    if ch == "#" then return keymap["3  #"] end
    if string.match(ch, "%d") then
        for name, field in pairs(keymap) do
            if string.sub(name, 1, 1) == ch then return field end
        end
    end
    return keymap[string.lower(ch) .. "  " .. string.upper(ch)]
end
local function tap(mod, ch)
    local f = findkey(ch)
    if not f then return false end
    local m = mod and keymap[mod]
    if m then m:set_value(1) emu.wait(0.03) end
    f:set_value(1) emu.wait(0.06) f:set_value(0) emu.wait(0.03)
    if m then m:set_value(0) end
    emu.wait(0.05)
    return true
end
local function rowbase(r) return 0x400 + (r % 8) * 0x80 + math.floor(r / 8) * 0x28 end
local function cell(r, c)
    local base = rowbase(r)
    if c % 2 == 0 then return aux:read(base + math.floor(c / 2)) end
    return prog:read_u8(base + math.floor(c / 2))
end
local function asc(b)
    if b >= 0x80 then b = b - 0x80 end
    if b < 0x20 then b = b + 0x40 end   -- inverse/flash uppercase
    if b >= 0x7f then return "." end
    return string.char(b)
end
local function rowtext(r)
    local t = {}
    for c = 0, 79 do t[#t+1] = asc(cell(r, c)) end
    return table.concat(t)
end
local function screen()
    local t = {}
    for r = 0, 23 do t[#t+1] = rowtext(r) end
    return table.concat(t, "\n")
end
local function snap() manager.machine.video:snapshot() end
local function respond(s)
    local f = io.open(RESP .. ".tmp", "w"); f:write(s .. "\nEND\n"); f:close()
    os.rename(RESP .. ".tmp", RESP)
end
local function handle(line)
    local cmd, a, b, c = string.match(line, "^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)")
    if cmd == "KEY" then
        local ok = tap(nil, a); respond(ok and "ok" or "NOKEY")
    elseif cmd == "SHIFT" then
        respond(tap("Left Shift", a) and "ok" or "NOKEY")
    elseif cmd == "CTRL" then
        respond(tap("Control", a) and "ok" or "NOKEY")
    elseif cmd == "TEXT" then
        respond(screen())
    elseif cmd == "SNAP" then            -- SNAP n step
        local n, step = tonumber(a), tonumber(b)
        for i = 1, n do emu.wait(step) snap() end
        respond("ok")
    elseif cmd == "STEP" then            -- STEP key maxw step [shift]: press, snapshot until screen changes
        local before = screen()
        local ok
        if c == "S" then ok = tap("Left Shift", a) else ok = tap(nil, a) end
        local maxw, step = tonumber(b), 1/10
        local t = 0
        snap()
        while t < maxw do
            emu.wait(step) snap() t = t + step
            if screen() ~= before and t > 0.12 then break end
        end
        respond("ok")
    elseif cmd == "WAIT" then            -- WAIT secs
        emu.wait(tonumber(a)) respond("ok")
    elseif cmd == "ZP" then
        respond(prog:read_u8(0x2b) .. " " .. prog:read_u8(0x2c))
    elseif cmd == "TIME" then
        respond(tostring(emu.time()))
    elseif cmd == "QUIT" then
        respond("bye") manager.machine:exit()
    else
        respond("BADCMD " .. line)
    end
end
function run()
        while true do
        local f = io.open(CMD, "r")
        if f then
            local line = f:read("*l"); f:close(); os.remove(CMD)
            if line then handle(line) end
        else
            os.execute("sleep 0.01")
        end
    end
end
co = coroutine.create(run)
coroutine.resume(co)
