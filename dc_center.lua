-- TY Minecraft ComputerCraft Code - Data Centre Console v1
-- Interactive dashboard for approved node application lifecycle.
-- Rednet is not encrypted/authenticated; only use on trusted servers.
local HEART = "ty.dc.v1:heart"
local CMD = "ty.dc.v1:command"
local REPLY = "ty.dc.v1:reply"
local HOST = "ty.dc.v1:center"
local known = { [2]="Pocket", [3]="Nuclear Plant", [4]="Base" }
local nodes = {}
local pendingId, pendingTarget, pendingReply = nil, nil, nil
local nonce = 0

local function openWireless()
    local found = false
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "modem") and peripheral.call(name, "isWireless") then
            rednet.open(name)
            found = true
        end
    end
    assert(found, "No Wireless/Ender Modem. Attach one to this computer.")
end
local function orderedIDs()
    local used, all = {}, {}
    for id in pairs(known) do used[id] = true; all[#all+1] = id end
    for id in pairs(nodes) do if not used[id] then all[#all+1] = id end end
    table.sort(all)
    return all
end
local function online(id)
    return nodes[id] and os.clock() - nodes[id].seen < 12
end
local function listNodes()
    print("ID  Name            Link     Service  Paired")
    for _, id in ipairs(orderedIDs()) do
        local node = nodes[id]
        local label = (node and node.label or known[id] or "unknown"):sub(1,15)
        local link = online(id) and "ONLINE" or "OFFLINE"
        local state = node and tostring(node.state) or "--"
        local paired = node and (node.pairedCenter == os.getComputerID()) and "YES" or "NO"
        print(string.format("%-3d %-15s %-8s %-8s %s", id, label, link, state, paired))
    end
end
local function showInfo(id)
    local n = nodes[id]
    if not n then print("No agent heartbeat from #" .. id); return end
    print("Computer #" .. id .. ": " .. n.label)
    print("Link: " .. (online(id) and "ONLINE" or "OFFLINE"))
    print("Role: " .. tostring(n.role) .. "; Program: " .. tostring(n.program))
    print("Service: " .. tostring(n.state))
    print("Paired to centre: " .. tostring(n.pairedCenter))
    print("Last seen: " .. math.floor(os.clock() - n.seen) .. " seconds ago")
    if n.lastError then print("Last error: " .. tostring(n.lastError)) end
end
local function receiveLoop()
    while true do
        local id, msg, proto = rednet.receive(nil, 1)
        if id and type(msg) == "table" and msg.version == 1 then
            if proto == HEART and msg.kind == "node" and msg.id == id
                and type(msg.label) == "string" and type(msg.role) == "string"
                and type(msg.state) == "string" then
                nodes[id] = {
                    seen=os.clock(), label=msg.label:sub(1,80), role=msg.role:sub(1,30),
                    state=msg.state, program=msg.program,
                    pairedCenter=msg.pairedCenter, lastError=msg.lastError,
                }
            elseif proto == REPLY and id == pendingTarget
                and type(msg.requestId) == "string" and msg.requestId == pendingId then
                pendingReply = { id=id, ok=msg.ok == true, message=msg.message, status=msg.status }
            end
        end
    end
end
local function sendCommand(id, action)
    if not online(id) then print("#" .. id .. " OFFLINE; no agent heartbeat"); return end
    if nodes[id].pairedCenter ~= os.getComputerID() then
        print("#" .. id .. " is not paired with this data centre")
        return
    end
    if action ~= "status" then
        write("Confirm " .. action .. " on #" .. id .. ": type YES > ")
        if read() ~= "YES" then print("Cancelled"); return end
    end
    nonce = nonce + 1
    local req = tostring(os.epoch("utc")) .. ":" .. tostring(nonce)
    pendingId, pendingTarget, pendingReply = req, id, nil
    if not rednet.send(id, {version=1, requestId=req, action=action}, CMD) then
        pendingId, pendingTarget = nil, nil
        print("Failed to send"); return
    end
    for _=1,80 do
        local answer = pendingReply
        if answer and answer.id == id then
            pendingId, pendingTarget, pendingReply = nil, nil, nil
            print((answer.ok and "OK: " or "REJECTED: ") .. tostring(answer.message))
            if answer.status then
                nodes[id] = {
                    seen=os.clock(), label=tostring(answer.status.label),
                    role=answer.status.role, program=answer.status.program,
                    state=answer.status.state, pairedCenter=answer.status.pairedCenter,
                    lastError=answer.status.lastError,
                }
            end
            return
        end
        sleep(0.1)
    end
    pendingId, pendingTarget, pendingReply = nil, nil, nil
    print("No ACK within 8 seconds. Execution status UNKNOWN; use info before retrying.")
end
local function help()
    print("nodes          - List computers and agent state")
    print("info <id>      - Show last known status")
    print("status <id>    - Ask agent for fresh status")
    print("update <id>    - Download its fixed GitHub program (when stopped)")
    print("start <id>     - Start approved program")
    print("stop <id>      - Stop approved program (plant guarded)")
    print("restart <id>   - Restart approved program (plant guarded)")
    print("help           - Show commands")
    print("exit           - Exit console")
end
local function consoleLoop()
    print("TY Data Centre | Computer #" .. os.getComputerID())
    print("Known: plant #3, base #4, pocket #2")
    print("Nodes require dc_agent.lua and local pairing to accept controls.")
    help()
    while true do
        write("dc> ")
        local line = read()
        local cmd, arg = line:match("^%s*(%S+)%s*(%S*)")
        if cmd == "exit" or cmd == "quit" then
            return
        elseif cmd == "help" then help()
        elseif cmd == "nodes" then listNodes()
        elseif cmd == "info" then
            local id=tonumber(arg)
            if id then showInfo(id) else print("Usage: info <id>") end
        elseif cmd == "status" or cmd == "update" or cmd == "start"
            or cmd == "stop" or cmd == "restart" then
            local id = tonumber(arg)
            if id and id == math.floor(id) and id >= 0 then
                sendCommand(id, cmd)
            else print("Usage: " .. cmd .. " <computer-id>") end
        elseif cmd and #cmd > 0 then
            print("Unknown command: " .. cmd .. " (type help)")
        end
    end
end
openWireless()
rednet.host(HOST, "ty-dc")
parallel.waitForAny(receiveLoop, consoleLoop)
rednet.unhost(HOST)
