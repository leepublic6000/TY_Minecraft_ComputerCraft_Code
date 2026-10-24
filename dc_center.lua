-- TY Minecraft ComputerCraft Code - Data Centre Console v1
-- Interactive dashboard for approved node application lifecycle.
-- Rednet is not encrypted/authenticated; only use on trusted servers.
local HEART = "ty.dc.v1:heart"
local CMD = "ty.dc.v1:command"
local REPLY = "ty.dc.v1:reply"
local HOST = "ty.dc.v1:center"
-- Pocket remote management uses its own protocol. Only the trusted, verified
-- Pocket #2 may call this gateway. Rednet IDs are NOT cryptographic identities.
local REMOTE_REQ = "ty.dc.v1:remote_request"
local REMOTE_RESP = "ty.dc.v1:remote_response"
local REMOTE_ALLOWED = { [2] = true }
local known = { [2]="Pocket", [3]="Nuclear Plant", [4]="Base" }
local nodes = {}
local pendingId, pendingTarget, pendingReply = nil, nil, nil
local nonce = 0
local remotePending = nil -- ONE remote node command at a time; local console remains available
local consoleBusy = false -- Serialise confirmations and commands from local + Pocket

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
-- The Pocket sees the SAME node state used by the local dc> console.
-- Read-only requests are handled immediately. Mutation requests are forwarded
-- as fixed allowlisted actions to the existing dc_agent.lua on each node.
local function remoteRespond(client, requestId, ok, message, data)
    rednet.send(client, {
        version=1, requestId=requestId, ok=ok,
        message=message, data=data,
    }, REMOTE_RESP)
end
local function remoteNodes()
    local result = {}
    for _, id in ipairs(orderedIDs()) do
        local node = nodes[id]
        result[#result+1] = {
            id=id, label=(node and node.label or known[id] or "unknown"):sub(1,40),
            online=not not online(id), state=node and tostring(node.state) or "--",
            paired=node ~= nil and node.pairedCenter == os.getComputerID(),
        }
    end
    return result
end
local function remoteInfo(id)
    local n = nodes[id]
    if not n then return nil end
    return {
        id=id, label=n.label, online=not not online(id),
        role=n.role, program=n.program, state=n.state,
        pairedCenter=n.pairedCenter, lastError=n.lastError,
        lastSeenSeconds=math.floor(os.clock()-n.seen),
    }
end
local REMOTE_NODE_ACTIONS = {
    status=true, update=true, start=true, stop=true, restart=true,
}
local function onRemoteRequest(client, packet)
    if not REMOTE_ALLOWED[client] then return end
    if type(packet.requestId) ~= "string" or #packet.requestId < 1
        or #packet.requestId > 48 or not packet.requestId:match("^[%w_:%-]+$")
        or type(packet.action) ~= "string" then return end
    local requestId, action = packet.requestId, packet.action
    if action == "nodes" then
        remoteRespond(client, requestId, true, "Nodes listed", remoteNodes())
        return
    end
    local target = packet.target
    if type(target) ~= "number" or target < 0 or target ~= math.floor(target)
        or target >= 65500 then
        remoteRespond(client, requestId, false, "Valid target computer ID required")
        return
    end
    if action == "info" then
        local info = remoteInfo(target)
        if not info then
            remoteRespond(client, requestId, false, "No heartbeat from #" .. target)
        else
            remoteRespond(client, requestId, true, "Last known node status", info)
        end
        return
    end
    if not REMOTE_NODE_ACTIONS[action] then
        remoteRespond(client, requestId, false, "Action not allowed")
        return
    end
    if action ~= "status" and packet.confirmed ~= true then
        remoteRespond(client, requestId, false, "Confirmation required")
        return
    end
    if remotePending or pendingId or consoleBusy then
        remoteRespond(client, requestId, false, "Data centre busy with another command")
        return
    end
    if not online(target) then
        remoteRespond(client, requestId, false, "Node #" .. target .. " OFFLINE")
        return
    end
    if nodes[target].pairedCenter ~= os.getComputerID() then
        remoteRespond(client, requestId, false, "Node #" .. target .. " not paired to centre")
        return
    end
    local agentId = "pc:" .. client .. ":" .. requestId
    remotePending = {
        client=client, requestId=requestId, agentRequestId=agentId,
        target=target, started=os.clock(),
    }
    local sent = rednet.send(target, {
        version=1, requestId=agentId, action=action,
    }, CMD)
    if not sent then
        remotePending = nil
        remoteRespond(client, requestId, false, "Modem failed to send command")
    end
end
local function onRemoteAgentReply(sender, message)
    local p = remotePending
    if not p or sender ~= p.target or message.requestId ~= p.agentRequestId then
        return false
    end
    remotePending = nil
    if type(message.status) == "table" then
        local st = message.status
        -- Keep local centre's node summary current after the agent ACK.
        nodes[sender] = {
            seen=os.clock(), label=tostring(st.label or "Unknown"):sub(1,80),
            role=tostring(st.role or "Unknown"):sub(1,30),
            state=tostring(st.state or "--"), program=st.program,
            pairedCenter=st.pairedCenter, lastError=st.lastError,
        }
    end
    remoteRespond(p.client, p.requestId, message.ok == true,
        tostring(message.message or "No message"), remoteInfo(sender))
    return true
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
            elseif proto == REPLY and type(msg.requestId) == "string" then
                onRemoteAgentReply(id, msg)
            elseif proto == REMOTE_REQ then
                onRemoteRequest(id, msg)
            end
        end
        if remotePending and os.clock() - remotePending.started >= 9 then
            local p = remotePending
            remotePending = nil
            remoteRespond(p.client, p.requestId, false,
                "No agent ACK within 9 seconds; execution state UNKNOWN. Use info.")
        end
    end
end
local function sendCommand(id, action)
    if remotePending then print("Pocket command in progress; retry shortly"); return end
    if not online(id) then print("#" .. id .. " OFFLINE; no agent heartbeat"); return end
    if nodes[id].pairedCenter ~= os.getComputerID() then
        print("#" .. id .. " is not paired with this data centre")
        return
    end
    consoleBusy = true
    if action ~= "status" then
        write("Confirm " .. action .. " on #" .. id .. ": type YES > ")
        if read() ~= "YES" then
            consoleBusy = false
            print("Cancelled")
            return
        end
    end
    nonce = nonce + 1
    local req = tostring(os.epoch("utc")) .. ":" .. tostring(nonce)
    pendingId, pendingTarget, pendingReply = req, id, nil
    if not rednet.send(id, {version=1, requestId=req, action=action}, CMD) then
        pendingId, pendingTarget = nil, nil
        consoleBusy = false
        print("Failed to send"); return
    end
    for _=1,80 do
        local answer = pendingReply
        if answer and answer.id == id then
            pendingId, pendingTarget, pendingReply = nil, nil, nil
            consoleBusy = false
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
    consoleBusy = false
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
