-- TY Chat Box diagnostic for ATM10 8.3 / Advanced Peripherals 0.8.
-- READ-ONLY player identity probe. No login, pairing, or privileges granted.
-- Run on Data Centre #0 from a separate Shell tab.
local function findChatBox()
    local box = peripheral.find("chat_box")
    if box then return box, peripheral.getName(box) end
    return nil
end

local function listConnected()
    print("Connected peripherals:")
    local names = peripheral.getNames()
    table.sort(names)
    for _, name in ipairs(names) do
        print(" - " .. name .. " : " .. tostring(peripheral.getType(name)))
    end
end

print("TY Chat Box diagnostic (read only)")
print("Computer: #" .. os.getComputerID())
local box, name = findChatBox()
if not box then
    print("RESULT: CHAT_BOX_NOT_FOUND")
    print("Install Chat Box adjacent to #0 OR attach it with Wired Modems + Networking Cable.")
    print("For wired peripherals, right-click the modem to connect the peripheral.")
    listConnected()
    return
end
print("Chat Box found at " .. name)
print("This checks only Minecraft in-world Chat Box events; no server administration.")
print("Type $typrobe in Minecraft CHAT near the Chat Box to test hidden event delivery.")
print("Type Ctrl+T to stop. Only a matching hidden probe receives a private reply.")
local lastReply = {}
local function processChat(uuid, username, message, isHidden)
    if type(uuid) ~= "string" or #uuid < 16 or type(username) ~= "string"
        or type(message) ~= "string" or type(isHidden) ~= "boolean" then
        print("Ignored chat event with missing/invalid player identity")
        return
    end
    if message ~= "typrobe" and message ~= "$typrobe" then return end
    if not isHidden then
        print("Probe message was NOT hidden; no login feature should be enabled yet.")
        return
    end
    local now = os.clock()
    if lastReply[uuid] and now - lastReply[uuid] < 5 then return end
    lastReply[uuid] = now
    print("Hidden event OK: " .. username .. " (UUID suffix " .. uuid:sub(-8) .. ")")
    local ok, result, errorMessage = pcall(box.sendMessage,
        "TY chat validation: received hidden message. This is NOT a login.",
        { player = username, prefix = "TY" })
    if not ok or result ~= true then
        print("Private reply FAILED: " .. tostring(ok and errorMessage or result))
        print("Check Chat Box cooldown and target-player messaging settings.")
    else
        print("Private reply submitted for " .. username)
    end
end
while true do
    local _, uuid, username, message, hidden = os.pullEvent("chat")
    processChat(uuid, username, message, hidden)
end
