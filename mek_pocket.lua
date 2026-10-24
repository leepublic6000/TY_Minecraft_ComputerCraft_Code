-- TY Minecraft ComputerCraft Code / ATM10 8.3
-- POCKET COMPUTER #2: read the full reactor/turbine telemetry and send
-- optional manual commands to plant #3. No automatic reactor control.

local CFG = {
    plant_id = 3,
    stale_seconds = 5,
}
local DATA = "ty_mek_control_v1:data"
local COMMAND = "ty_mek_control_v1:command"
local REPLY = "ty_mek_control_v1:reply"
local PAGES = { "SUMMARY", "REACTOR", "TURBINE", "ERRORS", "METHODS", "CONTROL" }
local DUMP_MODES = { "IDLE", "DUMPING_EXCESS", "DUMPING" }
local LOGIC_MODES = {
    "DISABLED", "TEMPERATURE", "CRITICAL_WASTE_LEVEL",
    "DAMAGED", "DEPLETED", "ACTIVATION"
}
local currentPage, scroll = 1, 0
local latest, receivedAt, pending, notice = nil, nil, nil, "Waiting for plant"
local touchZones = {}

local function openModem()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "modem") and peripheral.call(name, "isWireless") then
            rednet.open(name)
            return name
        end
    end
    error("Attach Wireless/Ender Modem to the pocket computer")
end

local function live()
    return latest ~= nil and receivedAt ~= nil
        and (os.clock() - receivedAt) < CFG.stale_seconds
end
local function device(kind)
    return latest and latest.devices and latest.devices[kind]
end
local function value(kind, method)
    local d = device(kind)
    return d and d.values and d.values[method]
end
local function policy()
    return (latest and latest.controlPolicy) or {}
end
local function trusted()
    for _, id in ipairs(policy().controllerIds or {}) do
        if id == os.getComputerID() then return true end
    end
    return false
end
local function can(action)
    if not live() or not trusted() then return false end
    local kind = action == "setDumpingMode" and "turbine" or "reactor"
    local d = device(kind)
    if not d or not d.present or not d.values or d.values.isFormed ~= true then
        return false
    end
    if action == "scram" then return true end
    if action == "activate" then return policy().activate == true end
    if action == "setBurnRate" then return type(policy().burnRateCap) == "number" end
    if action == "setLogicMode" then return policy().logicMode == true end
    if action == "setDumpingMode" then return policy().turbineMode == true end
    return false
end
local function keysSorted(t)
    local result = {}
    for k in pairs(t or {}) do result[#result+1] = k end
    table.sort(result, function(a,b) return tostring(a) < tostring(b) end)
    return result
end
local function format(path, x)
    if type(x) == "number" then
        if path:match("Temperature$") then return string.format("%.2f C", x) end
        if path:match("FilledPercentage$") then return string.format("%.1f%%", x*100) end
        if x == math.floor(x) then return tostring(x) end
        return string.format("%.3f", x)
    end
    if type(x) == "boolean" then return x and "TRUE" or "FALSE" end
    if x == nil then return "--" end
    return tostring(x)
end
local function flatten(path, x, output)
    if type(x) ~= "table" then
        output[#output+1] = path .. " = " .. format(path, x)
    elseif next(x) == nil then
        output[#output+1] = path .. " = {}"
    else
        for _, key in ipairs(keysSorted(x)) do
            flatten(path .. "." .. tostring(key), x[key], output)
        end
    end
end
local function rows()
    local page = PAGES[currentPage]
    if page == "SUMMARY" then
        return {
            "REACTOR / FISSION",
            "Formed: " .. format("isFormed", value("reactor", "isFormed")),
            "Running: " .. format("getStatus", value("reactor", "getStatus")),
            "Temp: " .. format("getTemperature", value("reactor", "getTemperature")),
            "Damage: " .. format("getDamagePercent", value("reactor", "getDamagePercent")) .. "%",
            "Burn: " .. format("getBurnRate", value("reactor", "getBurnRate")) .. " mB/t",
            "Actual: " .. format("getActualBurnRate", value("reactor", "getActualBurnRate")) .. " mB/t",
            "Fuel: " .. format("getFuelFilledPercentage", value("reactor", "getFuelFilledPercentage")),
            "Coolant: " .. format("getCoolantFilledPercentage", value("reactor", "getCoolantFilledPercentage")),
            "Heated: " .. format("getHeatedCoolantFilledPercentage", value("reactor", "getHeatedCoolantFilledPercentage")),
            "Waste: " .. format("getWasteFilledPercentage", value("reactor", "getWasteFilledPercentage")),
            "", "TURBINE / INDUSTRIAL",
            "Formed: " .. format("isFormed", value("turbine", "isFormed")),
            "Production: " .. format("getProductionRate", value("turbine", "getProductionRate")),
            "Flow: " .. format("getFlowRate", value("turbine", "getFlowRate")),
            "Steam: " .. format("getSteamFilledPercentage", value("turbine", "getSteamFilledPercentage")),
            "Dump: " .. format("getDumpingMode", value("turbine", "getDumpingMode")),
        }
    end
    if page == "CONTROL" then
        return {
            "MANUAL CONTROLS", "Current burn: " .. format("getBurnRate", value("reactor", "getBurnRate")),
            "Plant cap: " .. format("cap", policy().burnRateCap),
            "R: Set burn rate (mB/t)", "A: Activate reactor", "S: SCRAM reactor",
            "D: Turbine dump mode", "L: Reactor logic mode", "",
            "Controls: " .. (trusted() and "PAIRED" or "NOT PAIRED"),
            "ACTIVATE: " .. (can("activate") and "READY" or "LOCKED"),
            "SET BURN: " .. (can("setBurnRate") and "READY" or "LOCKED"),
            "TURBINE: " .. (can("setDumpingMode") and "READY" or "LOCKED"),
            "LOGIC: " .. (can("setLogicMode") and "READY" or "LOCKED"),
            "SCRAM: " .. (can("scram") and "READY" or "OFFLINE"),
            "", "Commands require text confirmation.",
            "No automatic control enabled.",
        }
    end
    local output = {}
    if page == "ERRORS" or page == "METHODS" then
        for _, kind in ipairs({ "reactor", "turbine" }) do
            local d = device(kind)
            output[#output+1] = kind:upper() .. " " .. page
            if not d then
                output[#output+1] = "No device data"
            elseif page == "METHODS" then
                for _, method in ipairs(d.methods or {}) do output[#output+1] = method end
            else
                local errs = d.errors or {}
                if next(errs) == nil then output[#output+1] = "No read errors" end
                for _, key in ipairs(keysSorted(errs)) do
                    output[#output+1] = tostring(key) .. ": " .. tostring(errs[key])
                end
            end
        end
    else
        local kind = page:lower()
        local d = device(kind)
        output[#output+1] = kind:upper() .. " / ALL READ VALUES"
        if not d then output[#output+1] = "No device data"
        else
            output[#output+1] = "Peripheral: " .. tostring(d.name)
            for _, key in ipairs(keysSorted(d.values)) do flatten(key, d.values[key], output) end
        end
    end
    return output
end
local function write(y, text, color)
    local width, height = term.getSize()
    if y < 1 or y > height then return end
    term.setCursorPos(1, y)
    term.setTextColor(color or colors.white)
    term.write(tostring(text):sub(1, width))
end
local function draw()
    term.setBackgroundColor(colors.black)
    term.clear()
    touchZones = {}
    local width, height = term.getSize()
    write(1, "TY MEK | POCKET #" .. CFG.plant_id, colors.cyan)
    write(2, "LINK: " .. (live() and "LIVE" or "OFFLINE") .. "  " .. PAGES[currentPage], live() and colors.lime or colors.red)
    write(3, "1:SUM 2:REAC 3:TURB", colors.yellow)
    write(4, "4:ERR 5:API 6:CTRL", colors.yellow)
    local function selectTab(index)
        currentPage = index
        scroll = 0
    end
    for _, zone in ipairs({
        {3,1,6,1}, {3,7,14,2}, {3,15,23,3},
        {4,1,6,4}, {4,7,13,5}, {4,14,23,6}
    }) do
        touchZones[#touchZones+1] = {
            y=zone[1], x1=zone[2], x2=zone[3],
            fn=function() selectTab(zone[4]) end
        }
    end
    local body = rows()
    local expanded = {}
    for _, line in ipairs(body) do
        if #line == 0 then expanded[#expanded+1] = ""
        else
            for start=1,#line,width do
                expanded[#expanded+1] = line:sub(start,start+width-1)
            end
        end
    end
    local visible = math.max(1, height - 7)
    local maxScroll = math.max(0, #expanded - visible)
    scroll = math.min(math.max(0,scroll),maxScroll)
    for y=5,height-3 do
        local row = scroll + y - 4
        local line = expanded[row]
        if line then write(y,line,colors.white) end
        if currentPage == 6 and line then
            local key = ({
                ["R: Set burn rate (mB/t)"]=keys.r,
                ["A: Activate reactor"]=keys.a,
                ["S: SCRAM reactor"]=keys.s,
                ["D: Turbine dump mode"]=keys.d,
                ["L: Reactor logic mode"]=keys.l,
            })[line]
            if key then
                touchZones[#touchZones+1] = {y=y,x1=1,x2=width,key=key}
            end
        end
    end
    write(height-2, "P:UP  N:DOWN  Q:EXIT", colors.lightGray)
    if pending then
        write(height-1, "WAIT: " .. pending.action, colors.orange)
    else
        write(height-1, (notice or ""):sub(1,width), colors.cyan)
    end
    write(height, tostring(scroll+1) .. "/" .. tostring(maxScroll+1) .. " | 6=Control", colors.gray)
end

local function ask(title, choices)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1,1)
    print(title)
    if choices then for i, choice in ipairs(choices) do print(i .. ") " .. choice) end end
    term.write("> ")
    return read()
end
local function command(action, parameter)
    if not can(action) then notice = "LOCKED / OFFLINE"; return end
    if pending then notice = "Wait for previous ACK"; return end
    local expected = action == "scram" and "SCRAM" or "YES"
    local answer = ask("Confirm " .. action .. "? Type " .. expected)
    if answer ~= expected then notice = "Cancelled"; return end
    if not live() then notice = "Connection stale - cancelled"; return end
    local id = math.floor(os.epoch("utc") * 10) + math.random(1,9)
    local transmitted = rednet.send(CFG.plant_id, {
        requestId=id, issuedUtcMs=os.epoch("utc"), action=action, value=parameter
    }, COMMAND)
    if transmitted then
        pending = { id=id, action=action, at=os.clock() }
        notice = "Command sent; waiting ACK"
    else notice = "Send failed - check modem" end
end
local function controlKey(code)
    if code == keys.r then
        if not can("setBurnRate") then notice="BURN LOCKED"; return end
        local raw = ask("Enter rate in mB/t")
        local proposed = tonumber(raw)
        local cap = policy().burnRateCap
        local max = value("reactor","getMaxBurnRate")
        if not proposed or proposed ~= proposed or proposed <= 0
            or proposed == math.huge or proposed == -math.huge
            or type(cap) ~= "number" or proposed > cap
            or type(max) ~= "number" or proposed > max then
            notice = "Invalid / above plant cap"; return
        end
        command("setBurnRate", proposed)
    elseif code == keys.a then command("activate")
    elseif code == keys.s then command("scram")
    elseif code == keys.d then
        if not can("setDumpingMode") then notice="TURBINE LOCKED"; return end
        local index = tonumber(ask("Turbine dump mode",DUMP_MODES))
        if index and DUMP_MODES[index] then command("setDumpingMode",DUMP_MODES[index])
        else notice="Cancelled" end
    elseif code == keys.l then
        if not can("setLogicMode") then notice="LOGIC LOCKED"; return end
        local index = tonumber(ask("Reactor logic mode",LOGIC_MODES))
        if index and LOGIC_MODES[index] then command("setLogicMode",LOGIC_MODES[index])
        else notice="Cancelled" end
    end
end

print("TY Pocket Client #" .. os.getComputerID())
print("Wireless modem: " .. openModem())
local tick = os.startTimer(1)
draw()
while true do
    local event, a, b, c = os.pullEvent()
    if event == "rednet_message" and a == CFG.plant_id then
        if c == DATA and type(b) == "table" and b.version == 1
            and type(b.devices) == "table" then
            latest = b
            receivedAt = os.clock()
            draw()
        elseif c == REPLY and type(b) == "table" and pending
            and b.requestId == pending.id then
            notice = (b.success and "OK: " or "ERROR: ") .. tostring(b.message)
            pending = nil
            draw()
        end
    elseif event == "key" then
        if a == keys.q then break end
        if a >= keys.one and a <= keys.six then
            currentPage = a - keys.one + 1
            scroll = 0
        elseif a == keys.n or a == keys.pageDown then scroll = scroll + 7
        elseif a == keys.p or a == keys.pageUp then scroll = scroll - 7
        elseif currentPage == 6 then controlKey(a) end
        draw()
    elseif event == "mouse_click" then
        for _, zone in ipairs(touchZones) do
            if c == zone.y and b >= zone.x1 and b <= zone.x2 then
                if zone.fn then zone.fn() end
                if zone.key then controlKey(zone.key) end
                break
            end
        end
        draw()
    elseif event == "mouse_scroll" then
        scroll = scroll + a * 3
        draw()
    elseif event == "timer" and a == tick then
        if pending and os.clock() - pending.at > 6 then
            notice = "NO ACK - state UNKNOWN"
            pending = nil
        end
        tick = os.startTimer(1)
        draw()
    end
end
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
print("TY Pocket Client stopped")
