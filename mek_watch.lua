-- TY Minecraft ComputerCraft Code / ATM10 8.3
-- BASE COMPUTER: larger monitor shows all data; smaller monitor is a
-- touch-operated manual control panel. Latest complete sample is saved as JSON.

local CFG = {
    plant_id = 3,                -- Verified plant computer ID
    data_monitor = "left",       -- Verified large monitor: 71 x 33
    control_monitor = "right",   -- Verified control monitor: 29 x 33
    stale_seconds = 5,
    save_seconds = 10,
}
local TELEMETRY = "ty_mek_control_v1:data"
local COMMAND = "ty_mek_control_v1:command"
local REPLY = "ty_mek_control_v1:reply"
local OUTPUT_FILE = "mek_latest.json"

local LOGIC_MODES = { "DISABLED", "TEMPERATURE", "CRITICAL_WASTE_LEVEL", "DAMAGED", "DEPLETED", "ACTIVATION" }
local DUMP_MODES = { "IDLE", "DUMPING_EXCESS", "DUMPING" }

local function openModems()
    local n = 0
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "modem") and peripheral.call(name, "isWireless") then
            rednet.open(name)
            n = n + 1
        end
    end
    assert(n > 0, "No modem: attach a Wireless/Ender Modem")
end

local function chooseMonitors()
    local monitors = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "monitor") then
            local m = peripheral.wrap(name)
            m.setTextScale(0.5)
            local w, h = m.getSize()
            monitors[#monitors + 1] = { name=name, monitor=m, area=w*h }
        end
    end
    assert(#monitors >= 2, "Need TWO visible monitor peripherals (left and right)")
    table.sort(monitors, function(a,b)
        if a.area == b.area then return a.name < b.name end
        return a.area > b.area
    end)
    local function byName(n)
        if not n then return nil end
        for _, v in ipairs(monitors) do if v.name == n then return v end end
        error("Configured monitor is missing: " .. tostring(n))
    end
    local left = byName(CFG.data_monitor) or monitors[1]
    local right = byName(CFG.control_monitor)
    if not right then
        for _, v in ipairs(monitors) do
            if v.name ~= left.name then right = v; break end
        end
    end
    assert(left.name ~= right.name, "Data and control monitors cannot be the same")
    return left, right
end

local data, control
local latest, plantId, receivedAt
local lastSaveAt = -math.huge
local lastAck, ackAt, pendingCommand, confirmCandidate
local view = "OVERVIEW"
local page = 1
local controlsPage = "REACTOR"
local burnDraft, burnDirty = nil, false
local logicDraft, logicDirty = nil, false
local dataZones, controlZones = {}, {}
local saveError

local function live()
    return latest and receivedAt and os.clock() - receivedAt < CFG.stale_seconds
end
local function device(kind)
    return latest and latest.devices and latest.devices[kind]
end
local function value(kind, method)
    local d = device(kind)
    return d and d.values and d.values[method]
end
local function policy()
    return (latest and latest.controlPolicy) or {}
end
local function count(t)
    local n=0
    for _ in pairs(t or {}) do n=n+1 end
    return n
end

local function nfmt(n, digits)
    if type(n) ~= "number" then return "--" end
    if math.abs(n) >= 1000000 then return string.format("%.3g", n) end
    if math.abs(n) >= 1000 then return string.format("%.1f", n) end
    return string.format("%." .. tostring(digits or 2) .. "f", n)
end
local function stringify(path, x)
    if type(x) == "number" then
        if path:match("Temperature$") then return nfmt(x,2) .. " C" end
        if path:match("FilledPercentage$") then return nfmt(x*100,2) .. "%" end
        if x == math.floor(x) then return tostring(x) end
        return string.format("%.4f", x)
    end
    if type(x) == "boolean" then return x and "TRUE" or "FALSE" end
    if x == nil then return "--" end
    return tostring(x)
end
local function keys(t)
    local list={}
    for k in pairs(t or {}) do list[#list+1]=k end
    table.sort(list, function(a,b) return tostring(a)<tostring(b) end)
    return list
end
local function flatten(path, x, lines)
    if type(x) ~= "table" then
        lines[#lines+1] = path .. " = " .. stringify(path,x)
        return
    end
    if next(x) == nil then lines[#lines+1] = path .. " = {}"; return end
    for _,k in ipairs(keys(x)) do
        flatten(path .. "." .. tostring(k),x[k],lines)
    end
end
local function overviewRows()
    local r={
        "REACTOR / FISSION",
        "Connected: " .. tostring(device("reactor") and device("reactor").present or false),
        "Formed: " .. stringify("isFormed",value("reactor","isFormed")),
        "Active: " .. stringify("getStatus",value("reactor","getStatus")),
        "Core: " .. stringify("getTemperature",value("reactor","getTemperature")),
        "Damage: " .. stringify("getDamagePercent",value("reactor","getDamagePercent")) .. "%",
        "Burn set: " .. stringify("getBurnRate",value("reactor","getBurnRate")) .. " mB/t",
        "Burn actual: " .. stringify("getActualBurnRate",value("reactor","getActualBurnRate")) .. " mB/t",
        "Fuel: " .. stringify("getFuelFilledPercentage",value("reactor","getFuelFilledPercentage")),
        "Coolant: " .. stringify("getCoolantFilledPercentage",value("reactor","getCoolantFilledPercentage")),
        "Heated: " .. stringify("getHeatedCoolantFilledPercentage",value("reactor","getHeatedCoolantFilledPercentage")),
        "Waste: " .. stringify("getWasteFilledPercentage",value("reactor","getWasteFilledPercentage")),
        "",
        "TURBINE / INDUSTRIAL",
        "Connected: " .. tostring(device("turbine") and device("turbine").present or false),
        "Formed: " .. stringify("isFormed",value("turbine","isFormed")),
        "Production: " .. stringify("getProductionRate",value("turbine","getProductionRate")) .. " energy/t",
        "Steam in: " .. stringify("getLastSteamInputRate",value("turbine","getLastSteamInputRate")) .. " mB/t",
        "Flow: " .. stringify("getFlowRate",value("turbine","getFlowRate")) .. " mB/t",
        "Steam: " .. stringify("getSteamFilledPercentage",value("turbine","getSteamFilledPercentage")),
        "Dumping: " .. stringify("getDumpingMode",value("turbine","getDumpingMode")),
        "",
        "Energy units depend on Mekanism settings.",
        "Use REACTOR/TURBINE tabs for every returned field.",
    }
    return r
end
local function detailRows(kind)
    local d = device(kind)
    if not d then return {"No data from " .. kind} end
    local lines = {
        string.upper(kind) .. " | peripheral=" .. tostring(d.name),
        "Present=" .. tostring(d.present) .. " Reads=" .. tostring(d.reads),
    }
    for _, k in ipairs(keys(d.values)) do flatten(k,d.values[k],lines) end
    if #lines == 2 then lines[#lines+1]="No readable values" end
    return lines
end
local function diagnosticRows()
    local lines={}
    for _,kind in ipairs({"reactor","turbine"}) do
        local d=device(kind)
        lines[#lines+1]=string.upper(kind) .. " ERRORS"
        if not d then
            lines[#lines+1]="No device data received"
        elseif count(d.errors)==0 then
            lines[#lines+1]="No read errors"
        else
            for _, k in ipairs(keys(d.errors)) do
                lines[#lines+1] = k .. ": " .. tostring(d.errors[k])
            end
        end
    end
    return lines
end
local function methodRows()
    local lines={}
    for _,kind in ipairs({"reactor","turbine"}) do
        lines[#lines+1]=string.upper(kind) .. " ADVERTISED METHODS"
        local d=device(kind)
        if d and d.methods then
            for _, m in ipairs(d.methods) do lines[#lines+1]=m end
        end
    end
    return lines
end
local function linesForView()
    if view == "REACTOR" then return detailRows("reactor") end
    if view == "TURBINE" then return detailRows("turbine") end
    if view == "ERRORS" then return diagnosticRows() end
    if view == "METHODS" then return methodRows() end
    return overviewRows()
end

local function writeAt(mon, x,y,s,fg,bg)
    local w,h=mon.getSize()
    if y<1 or y>h or x<1 or x>w then return end
    mon.setCursorPos(x,y)
    mon.setTextColor(fg or colors.white)
    mon.setBackgroundColor(bg or colors.black)
    mon.write(tostring(s):sub(1,w-x+1))
    mon.setBackgroundColor(colors.black)
end
local function button(mon,zones,x,y,w,label,bg,action,enabled)
    local W,H=mon.getSize()
    if y<1 or y>H or x>W then return end
    x=math.max(1,x); w=math.min(w,W-x+1)
    if w<1 then return end
    local str=tostring(label)
    if #str>w then str=str:sub(1,w) end
    local lead=math.floor((w-#str)/2)
    writeAt(mon,x,y,string.rep(" ",lead)..str..string.rep(" ",w-lead-#str),
        enabled==false and colors.lightGray or colors.white,
        enabled==false and colors.gray or (bg or colors.blue))
    if enabled~=false and action then
        zones[#zones+1]={x1=x,x2=x+w-1,y=y,fn=action}
    end
end
local function wrappedRows(lines,width)
    local arr={}
    width=math.max(1,width)
    for _,str in ipairs(lines) do
        if #str==0 then arr[#arr+1]="" end
        for p=1,#str,width do
            arr[#arr+1]=str:sub(p,p+width-1)
        end
    end
    return arr
end

local function drawData()
    local m=data.monitor
    m.setBackgroundColor(colors.black); m.clear()
    dataZones={}
    local w,h=m.getSize()
    writeAt(m,1,1,"TY / MEKANISM - COMPLETE TELEMETRY",colors.cyan)
    local link=not latest and "WAITING" or (live() and "LIVE" or "STALE / OFFLINE")
    writeAt(m,1,2,"LINK: "..link.."  Plant #"..tostring(plantId or "--").."  Fission+Turbine",
        live() and colors.lime or colors.red)
    local tabs={"OVERVIEW","REACTOR","TURBINE","ERRORS","METHODS"}
    local x=1
    for _,tab in ipairs(tabs) do
        local this=tab
        button(m,dataZones,x,3,#tab+2,tab,view==tab and colors.blue or colors.gray,function()
            view=this; page=1
        end,true)
        x=x+#tab+3
    end
    local body=wrappedRows(linesForView(),w)
    local perPage=math.max(1,h-5)
    local pages=math.max(1,math.ceil(#body/perPage))
    page=math.max(1,math.min(page,pages))
    for yy=5,h-1 do
        local index=(page-1)*perPage+(yy-5)+1
        if body[index] then
            writeAt(m,1,yy,body[index],colors.white)
        end
    end
    button(m,dataZones,1,h,math.max(3,math.floor(w/4)),"< PREV",colors.blue,function() page=math.max(1,page-1) end,true)
    writeAt(m,math.max(1,math.floor(w/2)-5),h,tostring(page).."/"..tostring(pages),colors.cyan)
    button(m,dataZones,math.max(1,w-math.floor(w/4)+1),h,math.floor(w/4),"NEXT >",colors.blue,
        function() page=math.min(pages,page+1) end,true)
end

local function actionAllowed(action)
    if not live() then return false end
    if not policy().paired then return false end
    local trusted = false
    for _, id in ipairs(policy().controllerIds or {}) do
        if id == os.getComputerID() then trusted = true; break end
    end
    if not trusted then return false end
    local kind=(action=="setDumpingMode") and "turbine" or "reactor"
    local d=device(kind)
    if not d or not d.present or d.values.isFormed~=true then return false end
    if action=="activate" then return policy().activate==true end
    if action=="setBurnRate" then return type(policy().burnRateCap)=="number" end
    if action=="setLogicMode" then return policy().logicMode==true end
    if action=="setDumpingMode" then return policy().turbineMode==true end
    return action=="scram"
end

local function requestCommand(action, desired)
    if not actionAllowed(action) then
        lastAck="LOCKED / OFFLINE / NOT FORMED"; ackAt=os.clock(); return
    end
    if pendingCommand and action~="scram" then
        lastAck="WAITING FOR PREVIOUS ACK"; ackAt=os.clock(); return
    end
    local now=os.clock()
    local requiresConfirm=action~="scram"
    local signature=action .. "|" .. tostring(desired)
    if requiresConfirm and (not confirmCandidate
        or confirmCandidate.signature~=signature
        or now-confirmCandidate.at>8) then
        confirmCandidate={signature=signature,at=now}
        lastAck="Tap SAME action again to confirm"; ackAt=now
        return
    end
    confirmCandidate=nil
    local id=plantId
    if not id then lastAck="Plant not discovered"; ackAt=now; return end
    local reqId=math.floor(os.epoch("utc") * 10) + math.random(1,9)
    local sent=rednet.send(id,{
        requestId=reqId, issuedUtcMs=os.epoch("utc"),
        action=action, value=desired
    },COMMAND)
    if sent then
        pendingCommand={id=reqId,action=action,at=now}
        lastAck="SENT "..action.." - awaiting readback"
    else
        lastAck="SEND FAILED - no delivery guarantee"
    end
    ackAt=now
end

local function nextLogic(step)
    local current=logicDraft or value("reactor","getLogicMode") or LOGIC_MODES[1]
    local index=1
    for i,v in ipairs(LOGIC_MODES) do if v==current then index=i;break end end
    logicDraft=LOGIC_MODES[((index-1+step)%#LOGIC_MODES)+1]
    logicDirty=true;confirmCandidate=nil
end

local function shiftBurn(amount)
    local current=burnDraft or value("reactor","getBurnRate")
    if type(current)~="number" then return end
    local cap=policy().burnRateCap or value("reactor","getMaxBurnRate") or current
    if type(cap)~="number" then cap=current end
    burnDraft=math.max(0.1,math.min(cap,math.floor((current+amount)*10+0.5)/10))
    burnDirty=true;confirmCandidate=nil
end

local function drawControl()
    local m=control.monitor
    m.setBackgroundColor(colors.black); m.clear()
    controlZones={}
    local w,h=m.getSize()
    local full=math.max(1,w)
    local half=math.floor((full-1)/2)
    writeAt(m,1,1,"TY / REMOTE CONTROL",colors.cyan)
    local link=not latest and "WAITING" or (live() and "LIVE" or "OFFLINE")
    writeAt(m,1,2,"Link: "..link.." | #"..tostring(plantId or "--"),live() and colors.lime or colors.red)
    button(m,controlZones,1,3,half,"REACTOR",controlsPage=="REACTOR" and colors.blue or colors.gray,
        function() controlsPage="REACTOR"; confirmCandidate=nil end,true)
    button(m,controlZones,half+2,3,full-half-1,"TURBINE",controlsPage=="TURBINE" and colors.blue or colors.gray,
        function() controlsPage="TURBINE"; confirmCandidate=nil end,true)
    if controlsPage=="REACTOR" then
        writeAt(m,1,5,"Status: "..stringify("getStatus",value("reactor","getStatus")))
        writeAt(m,1,6,"Temp: "..stringify("getTemperature",value("reactor","getTemperature")))
        writeAt(m,1,7,"Burn: "..stringify("getBurnRate",value("reactor","getBurnRate")) .. " mB/t")
        writeAt(m,1,8,"Actual: "..stringify("getActualBurnRate",value("reactor","getActualBurnRate")))
        writeAt(m,1,9,"Max: "..stringify("getMaxBurnRate",value("reactor","getMaxBurnRate")) .. "  Cap:" .. tostring(policy().burnRateCap or "LOCKED"))
        writeAt(m,1,11,"SET BURN: "..nfmt(burnDraft or value("reactor","getBurnRate"),1))
        local en=actionAllowed("setBurnRate")
        local fourth=math.floor((full-3)/4)
        button(m,controlZones,1,12,fourth,"-10",colors.gray,function()shiftBurn(-10) end,en)
        button(m,controlZones,fourth+2,12,fourth,"-1",colors.gray,function()shiftBurn(-1) end,en)
        button(m,controlZones,fourth*2+3,12,fourth,"+1",colors.gray,function()shiftBurn(1) end,en)
        button(m,controlZones,fourth*3+4,12,full-fourth*3-3,"+10",colors.gray,function()shiftBurn(10) end,en)
        button(m,controlZones,1,13,half,"-0.1",colors.gray,function()shiftBurn(-0.1) end,en)
        button(m,controlZones,half+2,13,full-half-1,"+0.1",colors.gray,function()shiftBurn(0.1) end,en)
        button(m,controlZones,1,15,full,"APPLY BURN RATE",colors.orange,function()
            requestCommand("setBurnRate",burnDraft or value("reactor","getBurnRate"))
        end,en)
        button(m,controlZones,1,17,half,"ACTIVATE",colors.orange,function()
            requestCommand("activate")
        end,actionAllowed("activate"))
        button(m,controlZones,half+2,17,full-half-1,"SCRAM / STOP",colors.red,function()
            requestCommand("scram")
        end,actionAllowed("scram"))
        writeAt(m,1,19,"Logic: "..tostring(value("reactor","getLogicMode") or "--"))
        writeAt(m,1,20,"New: "..tostring(logicDraft or value("reactor","getLogicMode") or "--"))
        local le=actionAllowed("setLogicMode")
        button(m,controlZones,1,21,half,"< MODE",colors.gray,function()nextLogic(-1) end,le)
        button(m,controlZones,half+2,21,full-half-1,"MODE >",colors.gray,function()nextLogic(1) end,le)
        button(m,controlZones,1,22,full,"APPLY LOGIC MODE",colors.orange,function()
            requestCommand("setLogicMode",logicDraft or value("reactor","getLogicMode"))
        end,le)
        writeAt(m,1,24,"Start/Logic may be locked at plant.",colors.lightGray)
    else
        writeAt(m,1,5,"Production: "..stringify("getProductionRate",value("turbine","getProductionRate")))
        writeAt(m,1,6,"Flow: "..stringify("getFlowRate",value("turbine","getFlowRate")) .. " mB/t")
        writeAt(m,1,7,"Steam: "..stringify("getSteamFilledPercentage",value("turbine","getSteamFilledPercentage")))
        writeAt(m,1,8,"Current: "..tostring(value("turbine","getDumpingMode") or "--"))
        local en=actionAllowed("setDumpingMode")
        writeAt(m,1,10,"STEAM DUMPING MODE",colors.yellow)
        button(m,controlZones,1,12,full,"IDLE",colors.green,function()
            requestCommand("setDumpingMode",DUMP_MODES[1]) end,en)
        button(m,controlZones,1,14,full,"DUMPING_EXCESS",colors.orange,function()
            requestCommand("setDumpingMode",DUMP_MODES[2]) end,en)
        button(m,controlZones,1,16,full,"DUMPING (DISCARD)",colors.red,function()
            requestCommand("setDumpingMode",DUMP_MODES[3]) end,en)
        writeAt(m,1,19,"WARNING: Dumped steam loses",colors.yellow)
        writeAt(m,1,20,"recycled water in closed loop.",colors.yellow)
        writeAt(m,1,22,"Turbine mode may be locked",colors.lightGray)
        writeAt(m,1,23,"by plant safety settings.",colors.lightGray)
    end
    if h>=26 then
        writeAt(m,1,h-3,"Double-tap changes; SCRAM once.",colors.lightGray)
        local info=lastAck or "No commands issued"
        local msg=info:sub(1,full)
        writeAt(m,1,h-2,msg, (lastAck and lastAck:match("FAILED|LOCKED|NO ACK|did not match")) and colors.red or colors.cyan)
        if #info>full then writeAt(m,1,h-1,info:sub(full+1,2*full),colors.cyan) end
    end
end

local function touch(zones,x,y)
    for _,z in ipairs(zones) do
        if y==z.y and x>=z.x1 and x<=z.x2 then
            z.fn();return true
        end
    end
    return false
end

local function saveLatest()
    if not latest then return end
    local document={
        format="ty_mek_control_v1",savedUtcMs=os.epoch("utc"),
        senderId=plantId,liveAtSave=not not live(),
        sample=latest,lastCommandReply=lastAck,
    }
    local ok,err=pcall(function()
        local content=textutils.serializeJSON(document)
        local handle=assert(fs.open(OUTPUT_FILE,"w"))
        handle.write(content);handle.close()
    end)
    if ok then lastSaveAt=os.clock();saveError=nil
    else saveError=tostring(err);print("JSON error: "..saveError) end
end

openModems()
data,control=chooseMonitors()
print("TY Mekanism base computer #"..os.getComputerID())
print("Left(data): "..data.name.." Right(control): "..control.name)
print("Plant ID lock: "..tostring(CFG.plant_id))
print("Control: touch twice to confirm, except immediate SCRAM")
print("Latest JSON: "..OUTPUT_FILE.."; press S in computer to save")
local timer=os.startTimer(0)
drawData();drawControl()
while true do
    local event,a,b,c=os.pullEvent()
    if event=="rednet_message" and c==TELEMETRY and type(b)=="table"
        and b.version==1 and type(b.devices)=="table" then
        if (not CFG.plant_id or a==CFG.plant_id) and (not plantId or a==plantId) then
            plantId=a;latest=b;receivedAt=os.clock()
            if not burnDirty then burnDraft=value("reactor","getBurnRate") end
            if not logicDirty then logicDraft=value("reactor","getLogicMode") end
            if os.clock()-lastSaveAt>=CFG.save_seconds then saveLatest() end
            drawData();drawControl()
        end
    elseif event=="rednet_message" and c==REPLY and type(b)=="table" then
        if a==plantId and pendingCommand and b.requestId==pendingCommand.id then
            lastAck=(b.success and "CONFIRMED: " or "ERROR: ") .. tostring(b.message)
            ackAt=os.clock()
            if b.success then
                if pendingCommand.action=="setBurnRate" then burnDirty=false end
                if pendingCommand.action=="setLogicMode" then logicDirty=false end
            end
            pendingCommand=nil;saveLatest();drawControl()
        end
    elseif event=="monitor_touch" then
        if a==data.name then
            touch(dataZones,b,c);drawData()
        elseif a==control.name then
            touch(controlZones,b,c);drawControl()
        end
    elseif event=="monitor_resize" then
        if a==data.name or a==control.name then drawData();drawControl() end
    elseif event=="key" and a==keys.s then
        saveLatest();print("Saved "..OUTPUT_FILE)
    elseif event=="timer" and a==timer then
        if pendingCommand and os.clock()-pendingCommand.at>6 then
            lastAck="NO ACK - action status UNKNOWN"
            ackAt=os.clock();pendingCommand=nil
        end
        if confirmCandidate and os.clock()-confirmCandidate.at>8 then confirmCandidate=nil end
        if latest and os.clock()-lastSaveAt>=CFG.save_seconds then saveLatest() end
        timer=os.startTimer(1)
        drawData();drawControl()
    end
end
