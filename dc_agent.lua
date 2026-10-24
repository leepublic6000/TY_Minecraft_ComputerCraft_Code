-- TY Minecraft ComputerCraft Code - Data Centre Agent v1
-- Node-side agent: heartbeat + ONLY allowlisted GitHub app service management.
-- No arbitrary shell, no eval, no remote control of reactor settings.
local args = { ... }
local CFG_FILE = "dc_center.id"
local HEART = "ty.dc.v1:heart"
local CMD = "ty.dc.v1:command"
local REPLY = "ty.dc.v1:reply"
local REPO = "https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/"
local APPS = {
    [3] = { role = "PLANT", file = "mek_send.lua" },
    [4] = { role = "BASE", file = "mek_watch.lua" },
    [6] = { role = "POCKET", file = nil }, -- Pocket presence only. Pocket UI remains independent.
}
local myId = os.getComputerID()
local profile = APPS[myId] or { role = "GENERAL", file = nil }

local function savePair(id)
    local h = assert(fs.open(CFG_FILE, "w"))
    h.write(tostring(id))
    h.close()
end
local function loadPair()
    if not fs.exists(CFG_FILE) then return nil end
    local h = fs.open(CFG_FILE, "r")
    if not h then return nil end
    local n = tonumber(h.readAll())
    h.close()
    if n and n >= 0 and n == math.floor(n) then return n end
    return nil
end
if args[1] == "pair" then
    local id = tonumber(args[2])
    if not id or id < 0 or id ~= math.floor(id) or id == myId then
        error("Usage: dc_agent.lua pair <data-centre-computer-id>", 0)
    end
    savePair(id)
    print("Paired locally to data centre #" .. id .. ". Start: bg dc_agent.lua")
    return
elseif args[1] == "unpair" then
    if fs.exists(CFG_FILE) then fs.delete(CFG_FILE) end
    print("Pairing removed. Restart the agent to apply.")
    return
elseif args[1] ~= nil then
    error("Usage: dc_agent.lua [pair <id> | unpair]", 0)
end

local centerId = loadPair()
local state = "STOPPED"
local wanted = false
local restarting = false
local lastError = nil
local launchedAt = nil

local function openWireless()
    local found = false
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "modem") and peripheral.call(name, "isWireless") then
            rednet.open(name)
            found = true
        end
    end
    assert(found, "No Wireless/Ender Modem connected")
end
local function heartbeat()
    return {
        kind = "node", version = 1, id = myId,
        label = os.getComputerLabel() or ("Computer #" .. myId),
        role = profile.role, program = profile.file,
        state = state, pairedCenter = centerId,
        lastError = lastError, uptime = os.clock(),
        serviceStartedAt = launchedAt,
    }
end
local function respond(id, request, ok, message)
    rednet.send(id, {
        version = 1, requestId = request, ok = ok,
        message = message, status = heartbeat(),
    }, REPLY)
end
local function reactorSafeToInterrupt()
    if profile.role ~= "PLANT" then return true end
    local r = peripheral.find("fissionReactorLogicAdapter")
    if not r or type(r.getStatus) ~= "function" then
        return false, "Reactor status unavailable: remote stop/restart refused"
    end
    local ok, active = pcall(r.getStatus)
    if not ok or active ~= false then
        return false, "Reactor is running or state uncertain: remote stop/restart refused"
    end
    return true
end

local function safeUpdate()
    local file = profile.file
    if not file then return false, "No approved application on this computer" end
    if wanted or state == "RUNNING" or state == "RESTARTING" then
        return false, "STOP service before updating"
    end
    if not http then return false, "HTTP API disabled" end
    local url = REPO .. file -- fixed per-node allowlist. No remote URL/path arguments.
    local handle, reason = http.get(url)
    if not handle then return false, "Download failed: " .. tostring(reason) end
    local content = handle.readAll()
    handle.close()
    if type(content) ~= "string" or #content == 0 or #content > 200000 then
        return false, "Download size invalid"
    end
    local chunk, syntaxError = load(content, "@" .. file, "t", {})
    if not chunk then return false, "Downloaded Lua syntax invalid: " .. tostring(syntaxError) end
    local tmp, bak = file .. ".new", file .. ".bak"
    local ok, err = pcall(function()
        if fs.exists(tmp) then fs.delete(tmp) end
        local h = assert(fs.open(tmp, "w"), "Cannot open temporary file")
        h.write(content)
        h.close()
        if fs.exists(file) then
            if fs.exists(bak) then fs.delete(bak) end
            fs.copy(file, bak)
            fs.delete(file)
        end
        fs.move(tmp, file)
    end)
    if not ok then
        if not fs.exists(file) and fs.exists(bak) then pcall(fs.copy, bak, file) end
        return false, "File replace failed: " .. tostring(err)
    end
    return true, "Updated " .. file .. " (previous version: " .. bak .. ")"
end

local function handleCommand(sender, packet)
    if not centerId or sender ~= centerId then return end
    if type(packet) ~= "table" or packet.version ~= 1
        or type(packet.requestId) ~= "string" or #packet.requestId > 80
        or type(packet.action) ~= "string" then return end
    local action, req = packet.action, packet.requestId
    if action == "status" then
        respond(sender, req, true, "Status returned")
        return
    end
    if not profile.file then
        respond(sender, req, false, "This node is monitoring-only")
        return
    end
    if action == "update" then
        local ok, msg = safeUpdate()
        respond(sender, req, ok, msg)
    elseif action == "start" then
        if wanted or state == "RUNNING" then
            respond(sender, req, false, "Service already running or starting")
        elseif not fs.exists(profile.file) then
            respond(sender, req, false, "File missing; use update first")
        else
            wanted = true
            lastError = nil
            os.queueEvent("ty_dc_wake")
            respond(sender, req, true, "Start requested; check node status")
        end
    elseif action == "stop" or action == "restart" then
        if not wanted and state ~= "RUNNING" then
            if action == "restart" and fs.exists(profile.file) then
                wanted = true
                os.queueEvent("ty_dc_wake")
                respond(sender, req, true, "Service not running; start requested")
            else
                respond(sender, req, false, "Service is not running")
            end
            return
        end
        local safe, reason = reactorSafeToInterrupt()
        if not safe then respond(sender, req, false, reason); return end
        restarting = action == "restart"
        wanted = false
        os.queueEvent("ty_dc_stop")
        respond(sender, req, true, action .. " requested; confirm via heartbeat")
    else
        respond(sender, req, false, "Unknown action")
    end
end

local function network()
    local timer = os.startTimer(0)
    while true do
        local event, a, b, c = os.pullEvent()
        if event == "timer" and a == timer then
            rednet.broadcast(heartbeat(), HEART)
            timer = os.startTimer(3)
        elseif event == "rednet_message" and c == CMD then
            handleCommand(a, b)
        end
    end
end
local function service()
    while true do
        if not wanted then os.pullEvent("ty_dc_wake") end
        if wanted then
            local file = profile.file
            if not file or not fs.exists(file) then
                state = "ERROR"
                lastError = "Approved program missing"
                wanted = false
            else
                state = "RUNNING"
                launchedAt = os.clock()
                local outcome = nil
                local function runApp()
                    local ok, result = pcall(shell.run, file)
                    if not ok then outcome = tostring(result)
                    elseif result == false then outcome = "Application returned false" end
                end
                local function waitStop()
                    while wanted and not restarting do os.pullEvent("ty_dc_stop") end
                end
                parallel.waitForAny(runApp, waitStop)
                state = outcome and "ERROR" or "STOPPED"
                lastError = outcome
                wanted = restarting
                restarting = false
                if wanted then os.queueEvent("ty_dc_wake") end
            end
        end
    end
end

openWireless()
print("TY Data Centre Agent | #" .. myId .. " / " .. profile.role)
print("Pairing: " .. (centerId and ("#" .. centerId) or "NONE (monitor-only)"))
print("Approved app: " .. tostring(profile.file))
print("Control is allowlisted; reactor safety interlock stays independent.")
parallel.waitForAll(network, service)
