-- TY Minecraft ComputerCraft Code / ATM10 8.3
-- PLANT COMPUTER: discover Fission Reactor + Industrial Turbine,
-- broadcast every readable, zero-argument method, and handle an explicit
-- whitelist of remote commands. Never automates a safety shutdown.

local CFG = {
    sample_seconds = 1,
    trusted_base_id = 4,          -- Verified base computer ID
    trusted_pocket_id = 2,        -- Verified Advanced Pocket Computer ID
    max_allowed_burn_rate = nil,  -- REQUIRED for setBurnRate: your VERIFIED safe limit (mB/t)
    allow_remote_activate = false,
    allow_remote_logic_mode = false,
    allow_remote_turbine_mode = false,
}

local TELEMETRY = "ty_mek_control_v1:data"
local COMMAND = "ty_mek_control_v1:command"
local REPLY = "ty_mek_control_v1:reply"

local LOGIC_MODES = {
    ACTIVATION=true, CRITICAL_WASTE_LEVEL=true, DAMAGED=true,
    DEPLETED=true, DISABLED=true, TEMPERATURE=true,
}
local DUMP_MODES = { IDLE=true, DUMPING_EXCESS=true, DUMPING=true }

local function openModems()
    local count = 0
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "modem") and peripheral.call(name, "isWireless") then
            rednet.open(name)
            count = count + 1
        end
    end
    assert(count > 0, "Attach a modem (Wireless/Ender for distant base)")
end

local function contains(methods, value)
    for _, v in ipairs(methods) do
        if v == value then return true end
    end
    return false
end

local function findDevice(typ, requiredMethods)
    local direct = peripheral.find(typ)
    if direct then return peripheral.getName(direct) end
    -- In case a modpack exposes the device under another peripheral type.
    for _, name in ipairs(peripheral.getNames()) do
        local ok, methods = pcall(peripheral.getMethods, name)
        if ok and type(methods) == "table" then
            local match = true
            for _, required in ipairs(requiredMethods) do
                if not contains(methods, required) then match = false; break end
            end
            if match then return name end
        end
    end
    return nil
end

local function findReactor()
    return findDevice("fissionReactorLogicAdapter", {
        "getBurnRate", "getWaste", "getTemperature", "setBurnRate"
    })
end

local function findTurbine()
    return findDevice("turbineValve", {
        "getProductionRate", "getDumpingMode", "getSteam", "setDumpingMode"
    })
end

local function isGetter(method)
    return method:match("^get%u") ~= nil
        or method:match("^is%u") ~= nil
        or method:match("^has%u") ~= nil
        or method:match("^can%u") ~= nil
end

local function portable(value, visited, depth)
    local k = type(value)
    if k == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return tostring(value)
        end
        return value
    end
    if k == "string" or k == "boolean" then return value end
    if k ~= "table" then return tostring(value) end
    if depth >= 12 then return "<max depth>" end
    if visited[value] then return "<recursive table>" end
    visited[value] = true
    local plain = {}
    for key, entry in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            plain[key] = portable(entry, visited, depth + 1)
        end
    end
    visited[value] = nil
    return plain
end

local function capture(name)
    local out = { present=name ~= nil, name=name, values={}, errors={}, methods={}, reads=0 }
    if not name then
        out.errors._connection = "Peripheral not found (check cable and valve/adapter)"
        return out
    end
    local ok, methods = pcall(peripheral.getMethods, name)
    if not ok or type(methods) ~= "table" then
        out.errors._methods = tostring(methods)
        return out
    end
    table.sort(methods)
    out.methods = methods
    for _, method in ipairs(methods) do
        if isGetter(method) then
            local success, value = pcall(peripheral.call, name, method)
            if not success then
                out.errors[method] = tostring(value)
            elseif value == nil then
                out.errors[method] = "Returned nil"
            else
                local cleaned = portable(value, {}, 0)
                -- Convert absolute temperatures only; not heat/flow rates.
                if type(cleaned) == "number" and method:match("Temperature$") then
                    cleaned = cleaned - 273.15
                end
                out.values[method] = cleaned
                out.reads = out.reads + 1
            end
        end
    end
    return out
end

local function status()
    return {
        version=1, sampleUtcMs=os.epoch("utc"), temperatureUnit="C",
        plantId=os.getComputerID(),
        devices={reactor=capture(findReactor()), turbine=capture(findTurbine())},
        controlPolicy={
            paired=type(CFG.trusted_base_id) == "number" or type(CFG.trusted_pocket_id) == "number",
            controllerIds={ CFG.trusted_base_id, CFG.trusted_pocket_id },
            burnRateCap=CFG.max_allowed_burn_rate,
            activate=CFG.allow_remote_activate,
            logicMode=CFG.allow_remote_logic_mode,
            turbineMode=CFG.allow_remote_turbine_mode,
        },
    }
end

local function read(name, method)
    local ok, value = pcall(peripheral.call, name, method)
    if ok then return value end
    return nil
end

local function safeNumber(n)
    return type(n) == "number" and n == n
        and n ~= math.huge and n ~= -math.huge
end

local function commandResult(request)
    if type(request.action) ~= "string" then return false, "Invalid action" end
    local action, value = request.action, request.value
    local target = (action == "setDumpingMode") and findTurbine() or findReactor()
    if not target then return false, "Target adapter/valve not connected" end
    if read(target, "isFormed") ~= true then
        return false, "Multiblock is not formed"
    end

    local method, readback, wanted
    if action == "scram" then
        method, readback, wanted = "scram", "getStatus", false
    elseif action == "activate" then
        if not CFG.allow_remote_activate then return false, "Remote activation locked at plant" end
        method, readback, wanted = "activate", "getStatus", true
    elseif action == "setBurnRate" then
        if not safeNumber(CFG.max_allowed_burn_rate) or CFG.max_allowed_burn_rate <= 0 then
            return false, "Set plant max_allowed_burn_rate before remote burn control"
        end
        if not safeNumber(value) or value <= 0 then
            return false, "Burn rate must be a finite positive number"
        end
        local machineMax = read(target, "getMaxBurnRate")
        if not safeNumber(machineMax) then return false, "Cannot read reactor maximum" end
        if value > machineMax or value > CFG.max_allowed_burn_rate then
            return false, "Requested burn rate exceeds a limit"
        end
        method, readback, wanted = "setBurnRate", "getBurnRate", value
    elseif action == "setLogicMode" then
        if not CFG.allow_remote_logic_mode then return false, "Remote logic-mode editing locked at plant" end
        if not LOGIC_MODES[value] then return false, "Invalid FissionReactorLogic value" end
        method, readback, wanted = "setLogicMode", "getLogicMode", value
    elseif action == "setDumpingMode" then
        if not CFG.allow_remote_turbine_mode then return false, "Remote dumping control locked at plant" end
        if not DUMP_MODES[value] then return false, "Invalid turbine GasMode value" end
        method, readback, wanted = "setDumpingMode", "getDumpingMode", value
    else
        return false, "Command is not on the allowlist"
    end

    local available = peripheral.getMethods(target)
    if not contains(available, method) or not contains(available, readback) then
        return false, "Method unavailable: " .. method
    end
    local ok, err
    if action == "scram" or action == "activate" then
        ok, err = pcall(peripheral.call, target, method)
    else
        ok, err = pcall(peripheral.call, target, method, wanted)
    end
    if not ok then return false, "Peripheral call failed: " .. tostring(err) end

    -- A successful call is not proof that the requested setting took effect.
    sleep(0.15)
    local actual = read(target, readback)
    local confirmed
    if type(wanted) == "number" and type(actual) == "number" then
        confirmed = math.abs(wanted - actual) < 0.001
    else
        confirmed = actual == wanted
    end
    if not confirmed then
        return false, "Call returned but readback did not match (actual=" .. tostring(actual) .. ")"
    end
    return true, "Confirmed " .. action .. " = " .. tostring(actual)
end

local recentRequests = {}
local requestOrder = {}
local function processCommand(sender, message)
    -- Rednet sender IDs can be spoofed; use only in a trusted game/network.
    if sender ~= CFG.trusted_base_id and sender ~= CFG.trusted_pocket_id then return end
    if type(message) ~= "table" or type(message.requestId) ~= "number"
        or type(message.issuedUtcMs) ~= "number" then return end
    local delta = os.epoch("utc") - message.issuedUtcMs
    if delta < -2000 or delta > 5000 then return end
    local requestId = tostring(message.requestId)
    if recentRequests[requestId] then return end
    recentRequests[requestId] = true
    requestOrder[#requestOrder + 1] = requestId
    if #requestOrder > 64 then
        recentRequests[table.remove(requestOrder, 1)] = nil
    end
    local ok, success, explanation = pcall(commandResult, message)
    if not ok then success, explanation = false, tostring(success) end
    local reply = {
        requestId=message.requestId, success=success,
        message=explanation, atUtcMs=os.epoch("utc"),
    }
    rednet.send(sender, reply, REPLY)
    print(string.format("Control from #%d: %s -> %s (%s)",
        sender, tostring(message.action), tostring(success), tostring(explanation)))
end

openModems()
print("TY Mekanism plant computer #" .. os.getComputerID())
print("Authorized controller IDs: " .. tostring(CFG.trusted_base_id) .. ", " .. tostring(CFG.trusted_pocket_id))
print("Sensors: " .. tostring(findReactor()) .. " / " .. tostring(findTurbine()))
print("Use independent Mekanism/redstone reactor safety protection.")
local timer = os.startTimer(0)
while true do
    local event, a, b, c = os.pullEvent()
    if event == "timer" and a == timer then
        local snapshot = status()
        rednet.broadcast(snapshot, TELEMETRY)
        timer = os.startTimer(CFG.sample_seconds)
    elseif event == "rednet_message" and c == COMMAND then
        processCommand(a, b)
    end
end
