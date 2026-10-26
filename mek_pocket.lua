-- TY Minecraft ComputerCraft Code / ATM10 8.3
-- POCKET COMPUTER #6: full READ-ONLY reactor/turbine telemetry.
-- Only the verified dc_remote.lua admin app may unlock BASE #4's panel.
-- Reactor control commands originate from BASE #4, never this Pocket viewer.

local CFG = {
    plant_id = 3,
    stale_seconds = 5,
}
local DATA = "ty_mek_control_v1:data"
local PAGES = { "SUMMARY", "REACTOR", "TURBINE", "ERRORS", "METHODS", "ACCESS" }
local currentPage, scroll = 1, 0
local latest, receivedAt = nil, nil
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
    if page == "ACCESS" then
        return {
            "POCKET #6 / ACCESS",
            "Direct plant control: DISABLED",
            "Reactor controls: BASE #4 only",
            "Pocket is read-only telemetry",
            "and admin panel authorization.",
            "",
            "To unlock BASE touch panel:",
            "Q: return to CraftOS",
            "Run dc_remote.lua",
            "pdc> auth",
            "pdc> panel 4",
            "pdc> unlock 4",
            "pdc> lock 4",
            "",
            "Plant policy remains separate:",
            "BURN CAP: " .. format("cap",policy().burnRateCap),
            "SCRAM: " .. format("scram",policy().scram),
            "ACTIVATE: " .. format("activate",policy().activate),
            "LOGIC: " .. format("logic",policy().logicMode),
            "TURBINE: " .. format("turbine",policy().turbineMode),
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
    write(4, "4:ERR 5:API 6:ACCESS", colors.yellow)
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
    end
    write(height-2, "P:UP  N:DOWN  Q:EXIT", colors.lightGray)
    write(height-1, "VIEW-ONLY / ADMIN: dc_remote", colors.cyan)
    write(height, tostring(scroll+1) .. "/" .. tostring(maxScroll+1) .. " | 6=Access", colors.gray)
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
        end
    elseif event == "key" then
        if a == keys.q then break end
        if a >= keys.one and a <= keys.six then
            currentPage = a - keys.one + 1
            scroll = 0
        elseif a == keys.n or a == keys.pageDown then scroll = scroll + 7
        elseif a == keys.p or a == keys.pageUp then scroll = scroll - 7 end
        draw()
    elseif event == "mouse_click" then
        for _, zone in ipairs(touchZones) do
            if c == zone.y and b >= zone.x1 and b <= zone.x2 then
                if zone.fn then zone.fn() end
                break
            end
        end
        draw()
    elseif event == "mouse_scroll" then
        scroll = scroll + a * 3
        draw()
    elseif event == "timer" and a == tick then
        tick = os.startTimer(1)
        draw()
    end
end
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
print("TY Pocket Client stopped")
