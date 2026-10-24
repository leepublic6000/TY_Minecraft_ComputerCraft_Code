-- TY Minecraft ComputerCraft Code / ATM10 8.3
-- Unified, role-aware installer and updater.
-- No arbitrary remote code execution, no automatic reactor shutdown.
local argv = { ... }
local ACTION = argv[1] or "help"
local ID = os.getComputerID()
local BASE_URL = "https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/"
local ROLES = {
    [0] = { name="DATA CENTRE", files={"dc_center.lua"} },
    [3] = { name="NUCLEAR PLANT", files={"dc_agent.lua", "mek_send.lua"} },
    [4] = { name="BASE", files={"dc_agent.lua", "mek_watch.lua"} },
    [6] = { name="POCKET", files={"dc_remote.lua", "mek_pocket.lua"} },
}
local role = ROLES[ID]
local COMMAND = "ty.dc.v1:command"
local REPLY = "ty.dc.v1:reply"
local DATA = "ty_mek_control_v1:data"
local requestNumber = 0

local function say(message)
    print("[TY] " .. message)
end
local function confirm(word, prompt)
    write(prompt .. " Type " .. word .. ": ")
    return read() == word
end
local function readFile(file)
    if not fs.exists(file) then return nil end
    local handle = fs.open(file, "r")
    if not handle then return nil, "Cannot open " .. file end
    local content = handle.readAll()
    handle.close()
    return content
end
local function writeFile(file, content)
    local handle = fs.open(file, "w")
    if not handle then error("Cannot write " .. file) end
    handle.write(content)
    handle.close()
end
local function safeDelete(file)
    if fs.exists(file) then fs.delete(file) end
end
local function getSource(file)
    if not http then return nil, "HTTP API unavailable" end
    local response, reason = http.get(BASE_URL .. file)
    if not response then return nil, "Download " .. file .. " failed: " .. tostring(reason) end
    local success, source = pcall(response.readAll)
    response.close()
    if not success or type(source) ~= "string" then
        return nil, "Could not read download: " .. file
    end
    if #source == 0 or #source > 200000 then
        return nil, "Unexpected download size for " .. file
    end
    local chunk, err = load(source, "@" .. file, "t", {})
    if not chunk then return nil, "Lua validation failed for " .. file .. ": " .. tostring(err) end
    return source
end
local function localFiles()
    if not role then return nil end
    local names = {}
    for _, name in ipairs(role.files) do names[#names+1] = name end
    names[#names+1] = "ty.lua" -- Keep the updater itself up to date.
    return names
end
local function printLocal()
    if not role then
        say("Unknown computer #" .. ID .. "; no role selected. No files changed.")
        return
    end
    say("Computer #" .. ID .. " / " .. role.name)
    for _, name in ipairs(localFiles()) do
        local exists = fs.exists(name) and not fs.isDir(name)
        print("  " .. name .. ": " .. (exists and (tostring(fs.getSize(name)) .. " bytes") or "MISSING"))
    end
    if ID == 3 then say("Plant settings are not automatically migrated between versions.") end
    if ID == 3 or ID == 4 then
        local center, err = readFile("dc_center.id")
        say("Agent pairing file: " .. (center and ("#" .. center:gsub("%s", "")) or ("none (" .. tostring(err or "not installed") .. ")")))
    end
end
local function plantIsSafe()
    if ID ~= 3 then return true end
    local r = peripheral.find("fissionReactorLogicAdapter")
    if not r or type(r.getStatus) ~= "function" then
        return false, "Reactor status is unavailable"
    end
    local ok, running = pcall(r.getStatus)
    if not ok or running ~= false then
        return false, "Reactor is running or its state is unknown"
    end
    return true
end
local function cleanStaged(pending)
    for _, item in ipairs(pending) do
        pcall(safeDelete, item.name .. ".tynew")
        pcall(safeDelete, item.name .. ".tybak_new")
    end
end
local function localUpdate(kind)
    if not role then
        say("No installation profile for computer #" .. ID)
        return false
    end
    local names = localFiles()
    say(kind .. " on #" .. ID .. " (" .. role.name .. ")")
    local downloads = {}
    for _, name in ipairs(names) do
        local source, err = getSource(name)
        if not source then say("ABORT: " .. err); return false end
        if fs.exists(name) and (fs.isDir(name) or fs.isReadOnly(name)) then
            say("ABORT: target is a directory or read-only: " .. name)
            return false
        end
        local current, readError = readFile(name)
        if fs.exists(name) and current == nil then
            say("ABORT: " .. tostring(readError or ("Cannot read " .. name)))
            return false
        end
        if current ~= source then
            downloads[#downloads+1] = {name=name, content=source, old=current ~= nil}
            say("Update needed: " .. name)
        end
    end
    if #downloads == 0 then say("Up to date; no files changed."); return true end
    if kind == "check" then
        say("" .. #downloads .. " file(s) need updating; check made no changes.")
        return true
    end
    if ID == 3 then
        local safe, reason = plantIsSafe()
        if not safe then
            say("ABORT: " .. reason .. ". No nuclear code was changed.")
            return false
        end
        local hasPlant = false
        for _, item in ipairs(downloads) do
            if item.name == "mek_send.lua" and item.old then hasPlant = true end
        end
        if hasPlant and not confirm("REPLACE", "Plant code may contain LOCAL safety settings!") then
            say("Cancelled: existing safety settings left intact.")
            return false
        end
    end
    if not confirm("YES", "Install/replace " .. #downloads .. " file(s) on #" .. ID .. "?") then
        say("Cancelled; no files changed.")
        return false
    end
    -- Stage all verified files and backups before altering any installed file.
    local staged, ok, err = {}, true, nil
    for _, item in ipairs(downloads) do
        staged[#staged+1] = item
        local result, problem = pcall(function()
            local tmp, backTmp = item.name .. ".tynew", item.name .. ".tybak_new"
            safeDelete(tmp)
            safeDelete(backTmp)
            writeFile(tmp, item.content)
            local check = assert(readFile(tmp), "Cannot reread staged source")
            assert(check == item.content, "Staged file mismatch")
            if item.old then fs.copy(item.name, backTmp) end
        end)
        if not result then ok, err = false, tostring(problem); break end
    end
    if not ok then
        cleanStaged(staged)
        say("ABORT: staging failed: " .. err .. ". Installed files unchanged.")
        return false
    end
    -- A failed commit restores its original file and any earlier files changed in this run.
    local touched = {}
    for _, item in ipairs(downloads) do
        touched[#touched+1] = item
        local success, problem = pcall(function()
            local bak, bakTmp, tmp = item.name .. ".tybak", item.name .. ".tybak_new", item.name .. ".tynew"
            if item.old then
                safeDelete(bak)
                fs.move(bakTmp, bak)
            end
            item.replacementStarted = true
            safeDelete(item.name)
            fs.move(tmp, item.name)
            assert(readFile(item.name) == item.content, "Installed content verification failed")
        end)
        if not success then
            say("ERROR while installing " .. item.name .. ": " .. tostring(problem))
            local recovered = true
            for i=#touched,1,-1 do
                local changed = touched[i]
                local restoreOK, restoreErr = pcall(function()
                    if changed.replacementStarted then
                        local bak = changed.name .. ".tybak"
                        if changed.old then
                            assert(fs.exists(bak), "Backup missing for " .. changed.name)
                            safeDelete(changed.name)
                            fs.copy(bak, changed.name)
                        else
                            safeDelete(changed.name)
                        end
                    end
                end)
                if not restoreOK then recovered = false; say("RESTORE FAILED: " .. tostring(restoreErr)) end
            end
            cleanStaged(downloads)
            say(recovered and "Changes rolled back; check files before retrying." or "Manual recovery needed from .tybak files.")
            return false
        end
        say("Installed: " .. item.name .. (item.old and " (backup: .tybak)" or ""))
    end
    cleanStaged(downloads)
    if (ID == 3 or ID == 4) and not fs.exists("dc_center.id") then
        say("Node not paired. Run: dc_agent.lua pair 0")
    end
    say("Files updated. Running programs are NOT automatically restarted.")
    if ID == 0 then say("Restart dc_center.lua in its console when ready.") end
    if ID == 3 then say("Re-check reactor safety configuration before starting the new version.") end
    return true
end

local function openRadio()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name,"modem") and peripheral.call(name,"isWireless") then
            rednet.open(name)
            return true
        end
    end
    say("Wireless or Ender Modem not found")
    return false
end
local function nodeRequest(id, action, timeout)
    requestNumber = requestNumber + 1
    local requestId = "ty:" .. tostring(ID) .. ":" .. tostring(os.epoch("utc")) .. ":" .. requestNumber
    if not rednet.send(id,{version=1,requestId=requestId,action=action},COMMAND) then
        return nil,"No open modem"
    end
    local deadline = os.clock() + (timeout or 9)
    repeat
        local seconds = deadline - os.clock()
        if seconds <= 0 then break end
        local sender, reply = rednet.receive(REPLY, seconds)
        if sender == id and type(reply) == "table" and reply.version == 1
            and reply.requestId == requestId then
            return reply
        end
    until false
    return nil, "NO ACK - remote outcome UNKNOWN"
end
local function waitState(id, wanted, maxChecks)
    for _=1,maxChecks do
        local ans = nodeRequest(id,"status",5)
        if ans and ans.ok and ans.status and ans.status.state == wanted then return true end
        sleep(0.6)
    end
    return false
end
local function fleetBase()
    local id = 4
    local status, err = nodeRequest(id, "status", 7)
    if not status or not status.ok or type(status.status) ~= "table" then
        say("#4 SKIP: " .. tostring(err or (status and status.message) or "No agent status"))
        return false
    end
    local info = status.status
    if info.role ~= "BASE" or info.pairedCenter ~= 0 or info.program ~= "mek_watch.lua" then
        say("#4 SKIP: unexpected agent role, pairing, or program")
        return false
    end
    local initiallyRunning = info.state == "RUNNING"
    if initiallyRunning then
        local stopped, reason = nodeRequest(id, "stop", 7)
        if not stopped or not stopped.ok then
            say("#4 SKIP: stop failed (" .. tostring(reason or (stopped and stopped.message)) .. ")")
            return false
        end
        if not waitState(id, "STOPPED", 5) then
            say("#4 STOP state unconfirmed; no update attempted")
            return false
        end
    elseif info.state ~= "STOPPED" then
        say("#4 SKIP: current service state " .. tostring(info.state))
        return false
    end
    local reply, failure = nodeRequest(id, "update", 15)
    if not reply or not reply.ok then
        say("#4 update failed: " .. tostring(failure or (reply and reply.message)))
        if initiallyRunning then say("Check service status and start it manually if necessary") end
        return false
    end
    say("#4 " .. tostring(reply.message))
    if initiallyRunning then
        local started, reason = nodeRequest(id, "start", 8)
        if not started or not started.ok then
            say("#4 START uncertain: " .. tostring(reason or (started and started.message)))
            return false
        end
        if not waitState(id,"RUNNING",5) then
            say("#4 RUNNING unconfirmed; check using data centre info 4")
            return false
        end
        say("#4 restarted; agent reports RUNNING")
    end
    return true
end

local function fleet()
    if ID ~= 0 then say("Fleet management is available only on data centre #0");return false end
    if not openRadio() then return false end
    say("Fleet update uses the existing paired node agents.")
    say("Nuclear plant #3 is NEVER auto-stopped or updated in bulk.")
    say("Base #4 may be briefly stopped and restarted.")
    if not confirm("FLEET", "Proceed with remote base update?") then
        say("Cancelled.");return false
    end
    local ok = fleetBase()
    say("#3 (plant) unchanged; use existing manual centre commands after safety checks.")
    return ok
end
local function help()
    say("One updater for ATM10 CC:Tweaked computers")
    print("Computer: #" .. ID .. "; role: " .. (role and role.name or "UNKNOWN"))
    print("  ty.lua status   - files installed on this computer")
    print("  ty.lua check    - compare with GitHub without writing")
    print("  ty.lua install  - install role files and updater")
    print("  ty.lua update   - update role files and updater")
    print("  ty.lua fleet   - centre #0 safely remote-update base #4")
    print("  ty.lua all     - centre #0 local update + remote base update")
    print("  ty.lua help    - display these instructions")
    print("No auto-start / no auto-SCRAM / no safety lock changes.")
end
if ACTION == "help" then
    help()
elseif ACTION == "status" then
    printLocal()
elseif ACTION == "check" then
    localUpdate("check")
elseif ACTION == "install" or ACTION == "update" then
    localUpdate(ACTION)
elseif ACTION == "fleet" then
    fleet()
elseif ACTION == "all" then
    if ID ~= 0 then
        say("Unified centre update is only available on computer #0")
    elseif localUpdate("update") then
        fleet()
    else
        say("Remote update skipped because local update did not finish")
    end
else
    say("Unknown command " .. tostring(ACTION))
    help()
end
