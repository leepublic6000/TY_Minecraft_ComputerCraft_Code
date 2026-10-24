-- TY Remote Shell Host / CC:Tweaked. Run in its own Multishell tab.
-- A real, isolated CraftOS shell: screen buffer and events stay inside this tab.
-- Rednet is NOT authenticated; use only in a trusted private game world.
local arg = {...}
local id = os.getComputerID()
local CENTER, POCKET = 0, 6
local REQ, RESP = "ty.rsh.v1:host", "ty.rsh.v1:host_reply"
local ENABLE = "dc_shell_enabled.flag"
local HOOK = "startup/ty_shell_host.lua"
local MARK = "-- TY_RSH_HOST_V1"
local MAX_W, MAX_H = 51, 25
local session, shellThread, waiting, buffer, screenPrevious, cursorPrevious
local nextFrame = 0

local function content(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local t = f.readAll(); f.close(); return t
end
local function enabled()
    return content(ENABLE) == "enabled\n"
end
local function stoppedReactor()
    if id ~= 3 then return true end
    local r = peripheral.find("fissionReactorLogicAdapter")
    if not r or type(r.getStatus) ~= "function" then return false end
    local ok, active = pcall(r.getStatus)
    return ok and active == false
end
local function configuredStartup()
    local s=content(HOOK)
    return s and s:sub(1,#MARK)==MARK or false
end
local function confirm(word)
    write("Type " .. word .. " to confirm: ")
    return read() == word
end
if arg[1] == "enable" then
    assert(id==0 or id==3 or id==4,"Only centre/plant/base computers may host remote shells")
    if id == 3 then
        assert(stoppedReactor(),"PLANT LOCK: reactor must be confirmed STOPPED")
        print("WARNING: full Shell can bypass reactor control policy; maintenance only.")
        if not confirm("PLANT") then print("Cancelled"); return end
    else
        if not confirm("ENABLE") then print("Cancelled"); return end
    end
    if fs.exists(HOOK) and not configuredStartup() then
        error("Another startup/ty_shell_host.lua already exists; not overwritten")
    end
    if fs.exists("startup") and not fs.isDir("startup") then
        error("startup is not a directory; resolve before enabling")
    end
    if not fs.exists("startup") then fs.makeDir("startup") end
    local app = "dc_shell_host.lua"
    local program = MARK .. "\n" ..
        "if os.getComputerID() ~= " .. id .. " then return end\n" ..
        "if not fs.exists(" .. string.format("%q",app) .. ") then return end\n" ..
        "if shell.openTab then shell.openTab(" .. string.format("%q",app) .. ") end\n"
    if not configuredStartup() then
        local f=assert(fs.open(HOOK,"w")); f.write(program); f.close()
    end
    local f=assert(fs.open(ENABLE,"w")); f.write("enabled\n"); f.close()
    print("Remote host ENABLED for next boot. Now run: bg dc_shell_host.lua")
    return
elseif arg[1] == "disable" then
    if not confirm("DISABLE") then return end
    if configuredStartup() then fs.delete(HOOK) end
    if fs.exists(ENABLE) then fs.delete(ENABLE) end
    print("Disabled. Current host will close on its next check.")
    return
elseif arg[1] == "status" then
    print("Computer #" .. id .. ": " .. (enabled() and "ENABLED" or "DISABLED"))
    print("Boot hook: " .. tostring(configuredStartup()))
    print("Reactor permitted: " .. tostring(stoppedReactor()))
    return
elseif arg[1] ~= nil then
    error("Usage: dc_shell_host.lua [enable | disable | status]")
end
assert(enabled(),"Remote host is DISABLED. Locally run: dc_shell_host.lua enable")
assert(id==0 or id==3 or id==4,"Remote shell host is not allowed on this computer")

local function openRadio()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name,"modem") and peripheral.call(name,"isWireless") then
            rednet.open(name); return
        end
    end
    error("Wireless/Ender modem missing")
end
local senderID = id==0 and POCKET or CENTER
local function response(packet)
    packet.v=1
    packet.target=id
    rednet.send(senderID,packet,RESP)
end
local function closeSession(reason)
    if session then response({kind="closed", sid=session.sid,reason=reason or "closed"}) end
    session, shellThread, waiting, buffer, screenPrevious, cursorPrevious = nil,nil,nil,nil,nil,nil
end
local function resumeShell(...)
    if not shellThread or coroutine.status(shellThread)=="dead" then return end
    local ev=select(1,...)
    if ev and waiting and ev~=waiting then return end
    local old=term.current()
    term.redirect(buffer)
    local ok, nextFilter = coroutine.resume(shellThread,...)
    term.redirect(old)
    if not ok then
        closeSession("Shell error: " .. tostring(nextFilter):sub(1,130))
    elseif coroutine.status(shellThread)=="dead" then
        closeSession("Remote shell exited")
    else
        waiting=nextFilter
    end
end
local function startSession(packet)
    local w = math.max(16,math.min(MAX_W,math.floor(packet.w or 26)))
    local h = math.max(8,math.min(MAX_H,math.floor(packet.h or 16)))
    buffer=window.create(term.current(),1,1,w,h,false)
    session={sid=packet.sid,opened=os.clock(),last=os.clock(),w=w,h=h}
    -- IMPORTANT: inherit the current parent shell: an isolated top-level shell
    -- with no parent would rerun /rom/startup.lua and duplicate startup services.
    assert(type(shell)=="table" and type(shell.run)=="function",
        "A parent Shell API is required; run this in a CraftOS shell tab")
    shellThread=coroutine.create(function()
        -- Suppress multishell access inside the remote session so remote
        -- programs do not create visible tabs on the controlled computer.
        os.run({shell=shell, multishell=false}, "/rom/programs/shell.lua")
    end)
    waiting=nil
    screenPrevious={}
    cursorPrevious=""
    resumeShell()
    if session then response({kind="opened",sid=session.sid,w=w,h=h}) end
end
local INPUTS={key=true,key_up=true,char=true,paste=true,mouse_click=true,
    mouse_up=true,mouse_drag=true,mouse_scroll=true}
local function inject(packet)
    if type(packet.event)~="string" or not INPUTS[packet.event] then return end
    if type(packet.args)~="table" or #packet.args>4 then return end
    local a=packet.args
    if packet.event=="char" or packet.event=="paste" then
        if type(a[1])~="string" or #a[1]>1024 then return end
    elseif packet.event=="key" or packet.event=="key_up" then
        if type(a[1])~="number" or a[1]<1 or a[1]>1000 then return end
    else
        for i=1,#a do
            if type(a[i])~="number" or a[i]<-1000 or a[i]>1000 then return end
        end
    end
    resumeShell(packet.event,table.unpack(a))
end
local function handle(packet)
    if type(packet)~="table" or packet.v~=1 or type(packet.kind)~="string"
        or type(packet.sid)~="string" or #packet.sid>70
        or not packet.sid:match("^[%w_:%-]+$") then return end
    if packet.kind=="open" then
        if not stoppedReactor() then
            response({kind="error",sid=packet.sid,reason="PLANT LOCK: reactor must be STOPPED"});return
        end
        if session then
            response({kind="error",sid=packet.sid,reason="Remote shell is busy"});return
        end
        if type(packet.w)~="number" or type(packet.h)~="number" then return end
        startSession(packet)
        return
    end
    if not session or packet.sid~=session.sid then return end
    session.last=os.clock()
    if packet.kind=="close" then closeSession("Client disconnected")
    elseif packet.kind=="input" then inject(packet)
    elseif packet.kind=="ping" then response({kind="pong",sid=session.sid}) end
end
local function sendFrame()
    if not session or not buffer then return end
    local changes={}
    for y=1,session.h do
        local text,fg,bg=buffer.getLine(y)
        if type(text)~="string" then return end
        local packed=text .. fg .. bg
        if packed~=screenPrevious[y] then
            changes[#changes+1]={y,text,fg,bg}
            screenPrevious[y]=packed
        end
    end
    local x,y=buffer.getCursorPos()
    local blink=buffer.getCursorBlink()
    local cursor=tostring(x)..":"..tostring(y)..":"..tostring(blink)
    if #changes>0 or cursorPrevious~=cursor then
        response({kind="frame",sid=session.sid,lines=changes,x=x,y=y,blink=blink,w=session.w,h=session.h})
        cursorPrevious=cursor
    end
end
openRadio()
print("TY Remote Shell Host #"..id.." | Ctrl+T to stop")
print("Centre: #0, operator: Pocket #6; trusted private world ONLY")
if id==3 then print("Plant shells operate ONLY while reactor reports STOPPED") end
local tick=os.startTimer(0.3)
while true do
    local event,a,b,c=os.pullEventRaw()
    if event=="terminate" then closeSession("Host stopped"); break end
    if event=="rednet_message" and a==senderID and c==REQ then
        handle(b)
    elseif event=="timer" and a==tick then
        if not enabled() then closeSession("Remote host disabled"); break end
        if session and id==3 and not stoppedReactor() then
            closeSession("Plant reactor no longer stopped")
        elseif session and os.clock()-session.last>45 then
            closeSession("Remote session expired")
        else
            sendFrame()
        end
        tick=os.startTimer(0.3)
    elseif shellThread and session then
        -- Only events from this local computer (timers, HTTP, Rednet etc.).
        -- Remote keyboard events are resumed DIRECTLY, never os.queueEvent()'d
        -- into other Multishell tabs (which run the plant and base services).
        if event~="char" and event~="key" and event~="key_up" and event~="paste"
            and event~="mouse_click" and event~="mouse_up" and event~="mouse_drag"
            and event~="mouse_scroll" and event~="terminate" then
            resumeShell(event,a,b,c)
        end
    end
end
