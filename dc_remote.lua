-- TY Minecraft ComputerCraft Code - Pocket Data Centre Remote
-- Pocket #6 talks to data centre #0, which manages paired node agents.
-- All actions are fixed allowlisted commands; this is NOT an arbitrary SSH shell.
-- Rednet does not authenticate sender IDs. Use only on trusted game networks.

local CENTRE_ID = 0
local REQUEST = "ty.dc.v1:remote_request"
local RESPONSE = "ty.dc.v1:remote_response"
-- Read-only presence beacon for the data-centre's local Advanced Monitor.
-- It means this authenticated PDC app is active, NOT Pocket power state.
local PRESENCE = "ty.dc.v1:pocket_presence"
local TIMEOUT = 12
local CHANGES = { update=true, start=true, stop=true, restart=true,
                  unlock=true, lock=true }
local ACTIONS = { nodes=true, info=true, status=true, update=true,
                  start=true, stop=true, restart=true,
                  panel=true, unlock=true, lock=true }
local sequence = 0
local AUTH_REQUEST="ty.auth.v1:request"
local AUTH_REPLY="ty.auth.v1:reply"
local CREDENTIAL="ty_device_key.json"
local authSession=nil
local authRequired=false
local authSupported=false
local currentUUID=nil
local function savedCredential()
    if not fs.exists(CREDENTIAL) then return nil end
    local h=fs.open(CREDENTIAL,"r")
    if not h then return nil end
    local data=h.readAll();h.close()
    local ok,obj=pcall(textutils.unserialiseJSON,data)
    if ok and type(obj)=="table" and type(obj.secret)=="string" then return obj.secret end
    return nil
end
local function saveCredential(secret)
    local h=assert(fs.open(CREDENTIAL..".tmp","w"))
    h.write(textutils.serialiseJSON({secret=secret,computer=os.getComputerID()}));h.close()
    if fs.exists(CREDENTIAL) then fs.delete(CREDENTIAL) end
    fs.move(CREDENTIAL..".tmp",CREDENTIAL)
end

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

local function authCall(action, payload, timeout)
    sequence=sequence+1
    local rid=tostring(os.epoch("utc"))..":"..tostring(sequence)
    local data={v=1,rid=rid,action=action,session=authSession}
    for k,v in pairs(payload or {}) do data[k]=v end
    if not rednet.send(CENTRE_ID,data,AUTH_REQUEST) then return nil,"No open modem" end
    local deadline=os.clock()+(timeout or 5)
    while os.clock()<deadline do
        local sender,msg=rednet.receive(AUTH_REPLY,deadline-os.clock())
        if sender==CENTRE_ID and type(msg)=="table" and msg.v==1 and msg.rid==rid then
            return msg
        end
    end
    return nil,"Auth centre not responding"
end
local function doLogin()
    if not authSupported then print("Auth gateway unavailable; centre needs update");return false end
    local begun,err=authCall("begin")
    if not begun or not begun.ok then print("LOGIN: "..tostring(begun and begun.message or err));return false end
    print("Type in Minecraft CHAT:")
    print("$tylogin "..tostring(begun.challenge))
    print("Wait for private code (or Pocket #6 2FA on other computers).")
    write("Six-digit code > ")
    local code=read() or ""
    local verified,why=authCall("verify",{code=code})
    if not verified or not verified.ok then
        print("LOGIN FAILED: "..tostring(verified and verified.message or why));return false
    end
    authSession=verified.session
    currentUUID=verified.uuid
    print("Logged in as "..tostring(currentUUID):sub(-8).." / "..tostring(verified.role))
    if os.getComputerID()==6 then
        write("Trust Pocket #6 until revoked? YES/no > ")
        if string.upper(read() or "") == "YES" then
            local trusted,reason=authCall("trust")
            if trusted and trusted.ok and trusted.secret then
                saveCredential(trusted.secret)
                print("Pocket trusted until $tyrevokeall in Minecraft chat")
            else print("Trust failed: "..tostring(trusted and trusted.message or reason)) end
        end
    end
    return true
end
local function callCentre(action, target, confirmed)
    sequence = sequence + 1
    local requestId = tostring(os.epoch("utc")) .. ":" .. tostring(sequence)
    local packet = {
        version=1, requestId=requestId,
        action=action, target=target, confirmed=confirmed == true, auth=authSession,
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
    print("login          verify player via Chat Box + OTP")
    print("auth           check current login status")
    print("logout         end current login session")
    print("nodes          list all nodes")
    print("info <id>      show node status")
    print("status <id>    request fresh status")
    print("shell <id>     #3: verified live admin or stopped full Shell")
    print("panel 4        base touch-control lock status")
    print("unlock 4       admin grants base control for 5 min")
    print("lock 4         admin locks base control NOW")
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
local config=authCall("config")
if config and config.ok then
    authSupported=true
    authRequired=config.enabled==true
    print("Player authentication: "..(authRequired and "REQUIRED" or "NOT YET ENABLED"))
    if authRequired then
        local secret=savedCredential()
        if secret and os.getComputerID()==6 then
            local res=authCall("resume",{secret=secret})
            if res and res.ok then
                authSession=res.session;currentUUID=res.uuid
                print("Trusted device login restored")
            end
        end
        if not authSession then print("Type 'login' to authenticate") end
    end
else
    print("Auth gateway unavailable: LEGACY MODE, no verified player identity")
end
print("For approved programs only; no reactor control bypass")
help()
local function remoteConsole()
while true do
    write("pdc> ")
    local line = read()
    if type(line) ~= "string" then break end
    local action, arg = line:match("^%s*(%S+)%s*(%S*)")
    if action == "exit" or action == "quit" then
        break
    elseif action == "help" then
        help()
    elseif action == "login" then
        doLogin()
    elseif action == "auth" then
        local r=authCall("status")
        print(r and r.message or "Auth centre unavailable")
    elseif action == "logout" then
        if authSession then authCall("logout") end
        authSession=nil;currentUUID=nil
        print("Logged out. Device trust (if selected) remains until $tyrevokeall.")
    elseif action == "shell" then
        local target = tonumber(arg)
        if target~=0 and target~=3 and target~=4 then
            print("Usage: shell <0|3|4>")
        elseif target==3 and (not authRequired or not authSession or os.getComputerID()~=6) then
            print("Plant #3 requires verified admin Pocket #6 and centre auth enabled.")
            print("Type login (or restore trusted Pocket session) first.")
        elseif fs.exists("dc_shell_client.lua") then
            print("Remote access is for trusted private worlds only.")
            if target==3 then print("RUNNING plant: restricted maintenance; STOPPED: full Shell.") end
            shell.run("dc_shell_client.lua", tostring(target), authSession or "")
        else
            print("dc_shell_client.lua missing: run ty.lua install on Pocket")
        end
    elseif action and ACTIONS[action] then
        local panelAction=(action=="panel" or action=="unlock" or action=="lock")
        if panelAction and (os.getComputerID()~=6 or not authRequired or not authSession) then
            print("Base panel requires signed-in admin on Pocket #6.")
            print("Use login first (auth must be enabled at data centre #0).")
        else
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
                local word=(action=="unlock" and "UNLOCK")
                    or (action=="lock" and "LOCK") or "YES"
                write("Confirm "..action.." on #"..target..": type "..word.." > ")
                confirmed=(read()==word)
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
                    elseif panelAction then
                        print("OK: "..tostring(reply.message))
                        local data=reply.data
                        if type(data)=="table" then
                            print("Base panel: "..(data.unlocked==true and "UNLOCKED" or "LOCKED"))
                            print("Lease remaining: "..tostring(data.remainingSeconds or 0).." sec")
                        end
                    else
                        print("OK: " .. tostring(reply.message))
                        if reply.data and type(reply.data) == "table" then
                            print("State: " .. tostring(reply.data.state))
                        end
                    end
                end
            end
        end
        end -- authenticated Pocket panel-access gate
    elseif action then
        print("Unknown command; type help")
    end
end
end
local function presenceBeacon()
    -- This is deliberately not an agent/service heartbeat. Do not make the
    -- centre claim the Pocket is online unless the authenticated app reports.
    while true do
        if os.getComputerID()==6 and authRequired and authSession then
            rednet.send(CENTRE_ID,{version=1,kind="pdc_alive",
                auth=authSession},PRESENCE)
        end
        sleep(3)
    end
end
if os.getComputerID()==6 then
    parallel.waitForAny(remoteConsole,presenceBeacon)
else
    remoteConsole()
end
print("Pocket remote closed")
