-- TY Minecraft ComputerCraft Code - Pocket Data Centre Remote
-- Pocket #6 talks to data centre #0, which manages paired node agents.
-- All actions are fixed allowlisted commands; this is NOT an arbitrary SSH shell.
-- Rednet does not authenticate sender IDs. Use only on trusted game networks.

local CENTRE_ID = 0
local REQUEST = "ty.dc.v1:remote_request"
local RESPONSE = "ty.dc.v1:remote_response"
local TIMEOUT = 12
local CHANGES = { update=true, start=true, stop=true, restart=true }
local ACTIONS = { nodes=true, info=true, status=true, update=true,
                  start=true, stop=true, restart=true }
local sequence = 0

local function connect()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "modem")
            and peripheral.call(name, "isWireless") then
            rednet.open(name)
            return name
        end
    end
    error("No Wireless/Ender Modem on this Pocket Computer")
end

local function callCentre(action, target, confirmed)
    sequence = sequence + 1
    local requestId = tostring(os.epoch("utc")) .. ":" .. tostring(sequence)
    local packet = {
        version=1, requestId=requestId,
        action=action, target=target, confirmed=confirmed == true,
    }
    if not rednet.send(CENTRE_ID, packet, REQUEST) then
        return nil, "Cannot send: no open modem"
    end
    local deadline = os.clock() + TIMEOUT
    repeat
        local remaining = deadline - os.clock()
        if remaining <= 0 then break end
        local sender, reply = rednet.receive(RESPONSE, remaining)
        if sender == CENTRE_ID and type(reply) == "table"
            and reply.version == 1 and reply.requestId == requestId then
            return reply
        end
    until false
    return nil, "No data centre reply; outcome UNKNOWN, use info before retrying"
end

local function showNodes(rows)
    if type(rows) ~= "table" then print("No node list received"); return end
    for _, item in ipairs(rows) do
        local link = item.online and "ONLINE" or "OFFLINE"
        local pair = item.paired and "YES" or "NO"
        print("#" .. tostring(item.id) .. " " .. tostring(item.label))
        print("  " .. link .. " / " .. tostring(item.state) .. " / Paired " .. pair)
    end
end
local function showInfo(data)
    if type(data) ~= "table" then return end
    print("#" .. tostring(data.id) .. " " .. tostring(data.label))
    print("Link: " .. (data.online and "ONLINE" or "OFFLINE"))
    print("Role: " .. tostring(data.role))
    print("Program: " .. tostring(data.program))
    print("Service: " .. tostring(data.state))
    print("Centre: " .. tostring(data.pairedCenter))
    print("Seen: " .. tostring(data.lastSeenSeconds) .. " sec ago")
    if data.lastError then print("Error: " .. tostring(data.lastError)) end
end
local function help()
    print("nodes          list all nodes")
    print("info <id>      show node status")
    print("status <id>    request fresh status")
    print("shell <id>     open full remote CraftOS terminal")
    print("update <id>    update node app")
    print("start <id>     start node app")
    print("stop <id>      stop node app")
    print("restart <id>   restart node app")
    print("help           show help")
    print("exit           close remote")
end

print("TY Pocket Data Centre Remote")
print("Pocket #" .. os.getComputerID() .. " -> Centre #" .. CENTRE_ID)
print("Modem: " .. connect())
print("For approved programs only; no reactor control bypass")
help()
while true do
    write("pdc> ")
    local line = read()
    if type(line) ~= "string" then break end
    local action, arg = line:match("^%s*(%S+)%s*(%S*)")
    if action == "exit" or action == "quit" then
        break
    elseif action == "help" then
        help()
    elseif action == "shell" then
        local target = tonumber(arg)
        if target~=0 and target~=3 and target~=4 then
            print("Usage: shell <0|3|4>")
        elseif fs.exists("dc_shell_client.lua") then
            print("Remote shell is high-privilege; private worlds only.")
            shell.run("dc_shell_client.lua", tostring(target))
        else
            print("dc_shell_client.lua missing: run ty.lua install on Pocket")
        end
    elseif action and ACTIONS[action] then
        local target = nil
        if action ~= "nodes" then
            target = tonumber(arg)
            if not target or target < 0 or target ~= math.floor(target) then
                print("Usage: " .. action .. " <computer-id>")
                target = nil
            end
        end
        if action == "nodes" or target then
            local confirmed = false
            local proceed = true
            if CHANGES[action] then
                write("Confirm " .. action .. " on #" .. target .. ": type YES > ")
                confirmed = (string.upper((read() or "")) == "YES")
                if not confirmed then
                    print("Cancelled")
                    proceed = false
                end
            end
            if proceed then
                local reply, err = callCentre(action, target, confirmed)
                if not reply then
                    print("ERROR: " .. err)
                elseif not reply.ok then
                    print("REJECTED: " .. tostring(reply.message))
                else
                    if action == "nodes" then
                        showNodes(reply.data)
                    elseif action == "info" then
                        showInfo(reply.data)
                    else
                        print("OK: " .. tostring(reply.message))
                        if reply.data and type(reply.data) == "table" then
                            print("State: " .. tostring(reply.data.state))
                        end
                    end
                end
            end
        end
    elseif action then
        print("Unknown command; type help")
    end
end
print("Pocket remote closed")
