-- TY Minecraft ComputerCraft Code - Data Centre Console v1
-- Interactive dashboard for approved node application lifecycle.
-- Rednet is not encrypted/authenticated; only use on trusted servers.
local HEART = "ty.dc.v1:heart"
local CMD = "ty.dc.v1:command"
local REPLY = "ty.dc.v1:reply"
local HOST = "ty.dc.v1:center"
-- Pocket remote management uses its own protocol. Only the trusted, verified
-- Pocket #6 may call this gateway. Rednet IDs are NOT cryptographic identities.
local REMOTE_REQ = "ty.dc.v1:remote_request"
local REMOTE_RESP = "ty.dc.v1:remote_response"
local REMOTE_ALLOWED = { [6] = true } -- legacy mode only, before auth enable
-- Authenticated Pocket #6 authorizes BASE #4 control-panel use. #4 still
-- enforces its own lease, while PLANT #3 retains all original control limits.
local PANEL_CMD = "ty.dc.v1:panel_command"
local PANEL_REPLY = "ty.dc.v1:panel_reply"
local PANEL_HEART = "ty.dc.v1:panel_heartbeat"
local PANEL_ACTIONS = {panel=true, unlock=true, lock=true}
local PANEL_HEART_PERIOD = 3
local panelGeneration = tostring(os.epoch("utc")) .. ":" .. tostring(os.getComputerID())
local panelLastHeart, panelOwnerUUID = -math.huge, nil
local auth = dofile("dc_auth.lua")
local AUTH_REQ = auth.protocol()
local known = { [6]="Pocket", [3]="Nuclear Plant", [4]="Base" }
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
    if type(packet) ~= "table" then return end
    if not auth.enabled() and not REMOTE_ALLOWED[client] then return end
    if type(packet.requestId) ~= "string" or #packet.requestId < 1
        or #packet.requestId > 48 or not packet.requestId:match("^[%w_:%-]+$")
        or type(packet.action) ~= "string" then return end
    local requestId, action = packet.requestId, packet.action
    local authorizedUUID=nil
    if auth.enabled() then
        local allowed, reason = auth.authorize(client,packet.auth,action)
        if not allowed then remoteRespond(client,requestId,false,reason or "Login required");return end
        authorizedUUID=allowed.uuid
        auth.audit(allowed.uuid,client,"remote:"..action,"accepted")
    end
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
    local panelAction = PANEL_ACTIONS[action]==true
    if not REMOTE_NODE_ACTIONS[action] and not panelAction then
        remoteRespond(client, requestId, false, "Action not allowed")
        return
    end
    if panelAction and (target~=4 or client~=6 or not auth.enabled()
        or not authorizedUUID) then
        remoteRespond(client,requestId,false,
            "Base panel requires authenticated admin Pocket #6 and target #4")
        return
    end
    if action ~= "status" and action ~= "panel" and packet.confirmed ~= true then
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
    if panelAction and (nodes[target].role~="BASE" or
        nodes[target].program~="mek_watch.lua") then
        remoteRespond(client,requestId,false,"Target is not the paired base monitor")
        return
    end
    local agentId = "pc:" .. client .. ":" .. requestId
    remotePending = {
        client=client, requestId=requestId, agentRequestId=agentId,
        target=target, started=os.clock(),
        kind=panelAction and "panel" or "agent",
        action=action, ownerUUID=authorizedUUID,
    }
    if panelAction and action=="unlock" then
        -- Remember the authorizing player even if the ACK is lost, so a
        -- later $tyrevokeall still attempts to revoke the lease.
        panelOwnerUUID=authorizedUUID
    end
    local sent = rednet.send(target, {
        version=1, requestId=agentId, action=action,
        generation=panelAction and panelGeneration or nil,
    }, panelAction and PANEL_CMD or CMD)
    if not sent then
        remotePending = nil
        remoteRespond(client, requestId, false, "Modem failed to send command")
    end
end
local function onRemoteAgentReply(sender, message)
    local p = remotePending
    if not p or p.kind~="agent" or sender ~= p.target or message.requestId ~= p.agentRequestId then
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
local function onPanelReply(sender,message)
    local p=remotePending
    if not p or p.kind~="panel" or sender~=4 or p.target~=4
        or type(message)~="table" or message.version~=1
        or message.requestId~=p.agentRequestId
        or message.generation~=panelGeneration
        or message.action~=p.action then return end
    remotePending=nil
    if message.ok==true and p.action=="unlock" then
        panelOwnerUUID=p.ownerUUID
    elseif message.ok==true and p.action=="lock" then
        panelOwnerUUID=nil
    end
    local seconds=tonumber(message.remainingSeconds) or 0
    seconds=math.max(0,math.min(300,math.floor(seconds)))
    remoteRespond(p.client,p.requestId,message.ok==true,
        tostring(message.message or "No panel reply"),
        {unlocked=message.unlocked==true,remainingSeconds=seconds})
end

-- Dedicated remote-terminal gateway. The operator must be Pocket #6.
-- This channel is UNAUTHENTICATED: use only in a trusted/private world.
local SHELL_CLIENT = "ty.rsh.v1:client"
local SHELL_HOST = "ty.rsh.v1:host"
local SHELL_HOST_REPLY = "ty.rsh.v1:host_reply"
local SHELL_CLIENT_REPLY = "ty.rsh.v1:client_reply"
local terminalSessions = {} -- target -> {sid, client, last}
local function shellError(client, sid, target, reason)
    rednet.send(client,{v=1,kind="error",sid=sid,target=target,reason=reason},SHELL_CLIENT_REPLY)
end
local function onShellClient(client, packet)
    if type(packet)~="table" or packet.v~=1 then return end
    local target=packet.target
    if target~=3 and target~=4 then return end
    -- Plant remote sessions are NEVER available in legacy ID-only mode.
    -- An admin session from the verified Pocket #6 is required even if
    -- the reactor is stopped. Keep #4's existing legacy behaviour.
    if target==3 and (client~=6 or not auth.enabled()) then
        if type(packet.sid)=="string" then
            shellError(client,packet.sid,target,"Plant #3 requires verified Pocket #6 admin login")
        end
        return
    end
    if not auth.enabled() and not REMOTE_ALLOWED[client] then return end
    local authorized = nil
    if auth.enabled() then
        local grant, reason=auth.authorize(client,packet.auth,"shell")
        if not grant then
            -- Reject a revoked/expired session and close its live host promptly.
            local active=terminalSessions[target]
            if active and active.client==client and active.sid==packet.sid then
                rednet.send(target,{v=1,kind="close",sid=active.sid,target=target},SHELL_HOST)
                terminalSessions[target]=nil
            end
            if type(packet.sid)=="string" then
                shellError(client,packet.sid,target,reason or "Login required")
            end
            return
        end
        authorized=grant.uuid
    end
    local sid=packet.sid
    if type(sid)~="string" or #sid<5 or #sid>70
        or not sid:match("^[%w_:%-]+$") then return end
    local kind=packet.kind
    if kind~="open" and kind~="close" and kind~="input" and kind~="line"
        and kind~="ping" then return end
    -- Complete command lines are only allowed for authenticated Pocket #6
    -- to the running-plant limited console. No arbitrary command routing.
    if kind=="line" then
        if target~=3 or type(packet.seq)~="number"
            or packet.seq<1 or packet.seq>100000000
            or packet.seq~=math.floor(packet.seq)
            or type(packet.line)~="string" or #packet.line>80
            or packet.line:find("[%c]") then
            shellError(client,sid,target,"Invalid restricted command line")
            return
        end
    end
    local ses=terminalSessions[target]
    if kind=="open" then
        if ses and os.clock()-ses.last<45 then
            shellError(client,sid,target,"Node has an active shell session");return
        end
        if not online(target) or nodes[target].pairedCenter~=os.getComputerID() then
            shellError(client,sid,target,"Node is OFFLINE or not paired");return
        end
        if type(packet.w)~="number" or type(packet.h)~="number"
            or packet.w<16 or packet.w>51 or packet.h<8 or packet.h>25 then
            shellError(client,sid,target,"Invalid terminal size");return
        end
        terminalSessions[target]={sid=sid,client=client,last=os.clock(),uuid=authorized}
        if authorized then auth.audit(authorized,client,"shell_open:"..target,"accepted") end
    else
        if not ses or ses.client~=client or ses.sid~=sid then return end
        ses.last=os.clock()
        if kind=="input" then
            if type(packet.args)~="table" or #packet.args>4 then return end
            if type(packet.event)~="string" or #packet.event>20 then return end
        end
    end
    -- Forward ONLY the transport allowlist. Never pass client-supplied
    -- privilege flags, bearer tokens or arbitrary fields to the host.
    local forwarded={v=1,kind=kind,sid=sid,target=target}
    if kind=="open" then
        forwarded.w=packet.w
        forwarded.h=packet.h
        if target==3 then forwarded.verifiedAdmin=(authorized~=nil) end
    elseif kind=="input" then
        forwarded.event=packet.event
        forwarded.args=packet.args
    elseif kind=="line" then
        forwarded.seq=packet.seq
        forwarded.line=packet.line
    end
    local sent=rednet.send(target,forwarded,SHELL_HOST)
    if not sent then
        terminalSessions[target]=nil
        shellError(client,sid,target,"Could not send to node")
    elseif kind=="close" then
        if ses and ses.uuid then auth.audit(ses.uuid,client,"shell_close:"..target,"closed") end
        terminalSessions[target]=nil
    end
end
local function onShellHostReply(sender,packet)
    if sender~=3 and sender~=4 then return end
    local ses=terminalSessions[sender]
    if not ses or type(packet)~="table" or packet.v~=1
        or packet.sid~=ses.sid or packet.target~=sender then return end
    ses.last=os.clock()
    rednet.send(ses.client,packet,SHELL_CLIENT_REPLY)
    if packet.kind=="closed" or packet.kind=="error" then
        terminalSessions[sender]=nil
    end
end

local function receiveLoop()
    while true do
        local id, msg, proto = rednet.receive(nil, 1)
        if id and proto==SHELL_CLIENT then onShellClient(id,msg)
        elseif id and proto==SHELL_HOST_REPLY then onShellHostReply(id,msg)
        elseif id and proto==AUTH_REQ then auth.handle(id,msg)
        end
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
            elseif proto == PANEL_REPLY and id==4 then
                onPanelReply(id,msg)
            elseif proto == REMOTE_REQ then
                onRemoteRequest(id, msg)
            end
        end
        -- Heartbeat is bound to this centre-process generation. A restarted
        -- or unreachable centre causes BASE #4 to automatically re-lock.
        if auth.enabled() and online(4) and nodes[4].pairedCenter==os.getComputerID()
            and os.clock()-panelLastHeart>=PANEL_HEART_PERIOD then
            panelLastHeart=os.clock()
            rednet.send(4,{version=1,generation=panelGeneration},PANEL_HEART)
        end
        if remotePending and os.clock() - remotePending.started >= 9 then
            local p = remotePending
            remotePending = nil
            remoteRespond(p.client, p.requestId, false,
                p.kind=="panel" and
                "No panel ACK; lock state UNKNOWN. Query panel 4 before retrying."
                or "No agent ACK within 9 seconds; execution state UNKNOWN. Use info.")
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
    print("auth claim     - Start admin enrollment (locally only)")
    print("auth enroll    - Add a read-only player (locally only)")
    print("auth confirm   - Approve player claim (locally only)")
    print("auth enable    - Turn on login gate once Pocket is updated")
    print("auth status    - Display authentication state")
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
    print("Known: plant #3, base #4, pocket #6")
    print("Nodes require dc_agent.lua and local pairing to accept controls.")
    help()
    while true do
        write("dc> ")
        local line = read()
        local cmd, arg = line:match("^%s*(%S+)%s*(%S*)")
        if cmd == "exit" or cmd == "quit" then
            return
        elseif cmd == "help" then help()
        elseif cmd == "auth" then
            local ok,message
            if arg=="claim" then ok,message=auth.beginClaim("admin")
            elseif arg=="enroll" then ok,message=auth.beginClaim("viewer")
            elseif arg=="confirm" then ok,message=auth.confirmClaim()
            elseif arg=="enable" then ok,message=auth.enable()
            elseif arg=="status" then print(auth.status());ok=true
            else print("auth claim|enroll|confirm|enable|status");ok=true end
            if message then print((ok and "OK: " or "ERROR: ")..message) end
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
local function onAuthRevoke(uuid)
    -- Revoke an active base-panel lease when its granting admin is revoked.
    -- Base also re-locks on lease expiry, missing centre heartbeat or reboot.
    if panelOwnerUUID==uuid then
        panelOwnerUUID=nil
        rednet.send(4,{
            version=1,requestId="revoke:"..tostring(os.epoch("utc")),
            action="lock",generation=panelGeneration,
        },PANEL_CMD)
    end
    for target,ses in pairs(terminalSessions) do
        if ses.uuid==uuid then
            rednet.send(target,{v=1,kind="close",sid=ses.sid,target=target},SHELL_HOST)
            shellError(ses.client,ses.sid,target,"Player devices revoked")
            terminalSessions[target]=nil
        end
    end
end
local function authChatLoop()
    while true do
        local _,uuid,name,message,hidden=os.pullEvent("chat")
        auth.chat(uuid,name,message,hidden)
    end
end
openWireless()
auth.configure(function(id,packet,protocol) return rednet.send(id,packet,protocol) end,onAuthRevoke)
rednet.host(HOST, "ty-dc")
parallel.waitForAny(receiveLoop, consoleLoop, authChatLoop)
rednet.unhost(HOST)
