-- TY Pocket Remote Shell: an interactive, screen-mirrored CraftOS shell.
-- Transport: Pocket #6 -> Centre #0 -> Target #3/#4 (or direct #0).
-- No SSH encryption/authentication: trusted private worlds ONLY.
local args={...}
local target=tonumber(args[1])
local authToken=args[2]
assert(target and target==math.floor(target) and (target==0 or target==3 or target==4),
    "Usage: dc_shell_client.lua <0|3|4>")
local center=0
local C_REQUEST="ty.rsh.v1:client"
local HOST_REQ="ty.rsh.v1:host"
local CLIENT_REPLY="ty.rsh.v1:client_reply"
local HOST_REPLY="ty.rsh.v1:host_reply"
local outgoing=target==0 and HOST_REQ or C_REQUEST
local incoming=target==0 and HOST_REPLY or CLIENT_REPLY
math.randomseed(os.epoch("utc")%10000000+os.getComputerID())
local sid=tostring(os.epoch("utc"))..":"..tostring(os.getComputerID())..":"..tostring(math.random(1000,9999))
local w,h=term.getSize()
local rw,rh=w,math.max(8,h-2)
local rows={}
local opened=false
local lastSeen=os.clock()
local status="CONNECTING..."
local cursorX,cursorY,cursorBlink=1,1,false
-- The running plant accepts complete command lines, not one Rednet packet
-- per keystroke. Other remote Shell modes keep their original event stream.
local liveMode=false
local draft,caret="",0
local nextLineSeq,pendingLine=0,nil
local inputNotice=nil

local function openRadio()
    for _,name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name,"modem") and peripheral.call(name,"isWireless") then
            rednet.open(name)
            return
        end
    end
    error("No wireless / Ender Modem on Pocket")
end
local function send(packet)
    packet.v=1;packet.sid=sid;packet.target=target;packet.auth=authToken
    return rednet.send(center,packet,outgoing)
end
local function writeAt(x,y,msg,color)
    local width,height=term.getSize()
    if y<1 or y>height then return end
    term.setCursorPos(x,y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(color or colors.white)
    term.write(tostring(msg):sub(1,math.max(0,width-x+1)))
end
local function draw()
    local width,height=term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    writeAt(1,1,"Remote #"..target.." "..status,opened and colors.lime or colors.orange)
    writeAt(math.max(1,width-2),1,"[X]",colors.red)
    for y=1,math.min(rh,height-2) do
        local line=rows[y]
        if line and #line[1]==rw and #line[2]==rw and #line[3]==rw then
            term.setCursorPos(1,y+1)
            term.blit(line[1],line[2],line[3])
        end
    end
    if liveMode and opened then
        local foot=pendingLine and ("SENDING "..pendingLine.tries.."/3")
            or (inputNotice or "LOCAL TYPING / ENTER SENDS")
        writeAt(1,height,foot,colors.lightGray)
        -- Overlay locally edited text at the remote prompt cursor. The
        -- server still owns command output and screen scrollback.
        if #draft>0 and cursorY>=1 and cursorY<=rh
            and cursorX>=1 and cursorX<=rw then
            local width=rw-cursorX+1
            local first=math.max(1,caret-width+2)
            local visible=draft:sub(first,first+width-1)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.setCursorPos(cursorX,cursorY+1)
            term.write(string.rep(" ",width))
            term.setCursorPos(cursorX,cursorY+1)
            term.write(visible)
            term.setCursorPos(cursorX+caret-(first-1),cursorY+1)
            term.setCursorBlink(not not opened)
        else
            term.setCursorBlink(opened and cursorBlink)
        end
    else
        writeAt(1,height,"Tap [X] or F10: detach",colors.lightGray)
        if cursorY>=1 and cursorY<=rh and cursorX>=1 and cursorX<=rw then
            term.setCursorPos(cursorX,cursorY+1)
            term.setCursorBlink(opened and cursorBlink)
        end
    end
end
local function applyFrame(packet)
    if type(packet.lines)~="table" then return end
    if packet.w~=rw or packet.h~=rh then return end
    for _,rec in ipairs(packet.lines) do
        if type(rec)=="table" and type(rec[1])=="number" and
            type(rec[2])=="string" and type(rec[3])=="string" and type(rec[4])=="string"
            and rec[1]>=1 and rec[1]<=rh and
            #rec[2]==rw and #rec[3]==rw and #rec[4]==rw then
            rows[rec[1]]={rec[2],rec[3],rec[4]}
        end
    end
    cursorX=type(packet.x)=="number" and packet.x or cursorX
    cursorY=type(packet.y)=="number" and packet.y or cursorY
    cursorBlink=packet.blink==true
    draw()
end
local function message(e,a,b,c)
    if e~="rednet_message" or a~=center or c~=incoming or type(b)~="table"
        or b.v~=1 or b.target~=target or b.sid~=sid then return end
    lastSeen=os.clock()
    if b.kind=="opened" then
        opened=true
        liveMode=b.mode=="live" and target==3
        status=liveMode and "LIVE LIMITED" or "FULL SHELL"
        draw()
    elseif b.kind=="frame" then applyFrame(b)
    elseif b.kind=="line_ack" and liveMode then
        if pendingLine and b.seq==pendingLine.seq then
            pendingLine=nil
            draft,caret="",0
            inputNotice=nil
            draw()
        end
    elseif b.kind=="line_reject" and liveMode then
        if pendingLine and b.seq==pendingLine.seq then
            pendingLine=nil
            inputNotice=tostring(b.reason or "REJECTED"):sub(1,30)
            draw()
        end
    elseif b.kind=="error" or b.kind=="closed" then
        status=tostring(b.reason or b.kind):sub(1,45)
        opened=false
        draw()
        return true
    end
end
local function editLocal(text)
    if pendingLine or type(text)~="string" or #text==0 then return end
    if text:find("[%c]") or #draft+#text>80 then
        inputNotice="INPUT LIMIT: 80 CHARS"
        draw()
        return
    end
    draft=draft:sub(1,caret)..text..draft:sub(caret+1)
    caret=caret+#text
    inputNotice=nil
    draw()
end
local function submitLocal()
    if pendingLine then return end
    nextLineSeq=nextLineSeq+1
    local packet={kind="line",seq=nextLineSeq,line=draft}
    if not send(packet) then
        inputNotice="SEND FAILED / RETRY ENTER"
        draw()
        return
    end
    pendingLine={seq=nextLineSeq,line=draft,tries=1,at=os.clock()}
    inputNotice=nil
    draw()
end
local function handleLocalKey(event,key)
    if pendingLine then return end
    if event=="char" or event=="paste" then
        editLocal(key)
        return
    end
    if event~="key" then return end
    if key==keys.enter or key==keys.numPadEnter then
        submitLocal()
    elseif key==keys.backspace and caret>0 then
        draft=draft:sub(1,caret-1)..draft:sub(caret+1)
        caret=caret-1
        draw()
    elseif key==keys.delete and caret<#draft then
        draft=draft:sub(1,caret)..draft:sub(caret+2)
        draw()
    elseif key==keys.left then
        caret=math.max(0,caret-1)
        draw()
    elseif key==keys.right then
        caret=math.min(#draft,caret+1)
        draw()
    elseif key==keys.home then
        caret=0
        draw()
    elseif key==keys["end"] then
        caret=#draft
        draw()
    end
end
openRadio()
-- Session IDs are correlation values, NOT authentication credentials.
print("Connecting to remote Shell on #"..target.." via #0...")
if not send({kind="open",w=rw,h=rh}) then
    error("Rednet send failed: confirm Pocket modem is open")
end
draw()
local refresh=os.startTimer(1)
while true do
    local e,a,b,c=os.pullEventRaw()
    if e=="terminate" then break end
    if message(e,a,b,c) then break end
    if e=="key" and a==keys.f10 then break end
    if e=="mouse_click" and c==1 and b>=w-2 then break end
    if e=="timer" and a==refresh then
        if not opened and os.clock()-lastSeen>10 then
            status="TIMEOUT (no open ACK)"
            draw()
            break
        end
        if opened then
            if os.clock()-lastSeen>15 then status="NETWORK STALE";draw() end
            if liveMode and pendingLine and os.clock()-pendingLine.at>=2 then
                if pendingLine.tries<3 then
                    send({kind="line",seq=pendingLine.seq,line=pendingLine.line})
                    pendingLine.tries=pendingLine.tries+1
                    pendingLine.at=os.clock()
                    draw()
                else
                    inputNotice="NO ACK / OUTCOME UNKNOWN"
                    status="NO LINE ACK"
                    draw()
                end
            end
            send({kind="ping"})
        end
        refresh=os.startTimer(2)
    elseif opened and liveMode then
        handleLocalKey(e,a)
    elseif opened then
        if e=="key" or e=="key_up" then
            send({kind="input",event=e,args={a,b}})
        elseif e=="char" or e=="paste" then
            if type(a)=="string" then
                for i=1,#a,900 do
                    send({kind="input",event=e,args={a:sub(i,i+899)}})
                end
            end
        elseif e=="mouse_click" or e=="mouse_drag" or e=="mouse_up" then
            if type(c)=="number" and c>=2 and c<=rh+1 then
                send({kind="input",event=e,args={a,b,c-1}})
            end
        elseif e=="mouse_scroll" then
            if type(c)=="number" and c>=2 and c<=rh+1 then
                send({kind="input",event=e,args={a,b,c-1}})
            end
        end
    end
end
send({kind="close"})
term.setCursorBlink(false)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
print("Remote Shell detached from #"..target)
