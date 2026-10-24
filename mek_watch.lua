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

-- CC:Tweaked can only scale text in 0.5 increments. Pick the largest readable
-- scale that still has enough character cells for the responsive layouts.
local function fitScale(mon, minWidth, minHeight)
    local current = mon.getTextScale()
    local width, height = mon.getSize()
    local physicalW, physicalH = width * current, height * current
    local best = 0.5
    for step = 5, 1, -1 do
        local candidate = step * 0.5
        if math.floor(physicalW / candidate) >= minWidth
            and math.floor(physicalH / candidate) >= minHeight then
            best = candidate
            break
        end
    end
    if current ~= best then mon.setTextScale(best) end
    width, height = mon.getSize()
    -- The monitor's character rounding can differ from the estimate.
    while best > 0.5 and (width < minWidth or height < minHeight) do
        best = best - 0.5
        mon.setTextScale(best)
        width, height = mon.getSize()
    end
    return best
end

local data, control
local latest, plantId, receivedAt
local lastSaveAt = -math.huge
local lastAck, ackAt, pendingCommand, confirmCandidate
local view = "OVERVIEW"
local page = 1
local controlsPage = "CORE"
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
local function button(mon,zones,x,y,w,label,bg,action,enabled,height)
    local W,H=mon.getSize()
    if y<1 or y>H or x>W then return end
    x=math.max(1,x)
    w=math.min(w,W-x+1)
    if w<1 then return end
    local lastY=math.min(H,y+math.max(1,math.floor(height or 1))-1)
    local background=enabled==false and colors.gray or (bg or colors.blue)
    local foreground=enabled==false and colors.lightGray or colors.white
    local blank=string.rep(" ",w)
    for row=y,lastY do writeAt(mon,x,row,blank,foreground,background) end
    local str=tostring(label):sub(1,w)
    local lead=math.floor((w-#str)/2)
    local centerY=math.floor((y+lastY)/2)
    writeAt(mon,x,centerY,string.rep(" ",lead)..str,foreground,background)
    if enabled~=false and action then
        zones[#zones+1]={x1=x,x2=x+w-1,y1=y,y2=lastY,fn=action}
    end
end

local function sectionHeader(mon,x,y,width,label)
    writeAt(mon,x,y,string.rep(" ",width),colors.white,colors.blue)
    local cut=tostring(label):sub(1,width)
    writeAt(mon,x+math.floor((width-#cut)/2),y,cut,colors.white,colors.blue)
end

local function cellText(mon,x,y,width,label,foreground)
    if width<1 then return end
    writeAt(mon,x,y,tostring(label):sub(1,width),foreground or colors.white)
end

local function fraction(kind,method)
    local n=value(kind,method)
    if type(n)~="number" or n~=n then return nil end
    return math.max(0,math.min(1,n))
end

local function fractionText(n)
    return n and (nfmt(n*100,1).."%") or "--"
end

local function progressBar(mon,x,y,width,n,activeColor)
    if width<3 then return end
    local inner=width-2
    local filled=n and math.floor(n*inner+0.5) or 0
    local bar="["..string.rep("=",filled)..string.rep("-",inner-filled).."]"
    writeAt(mon,x,y,bar,n and (activeColor or colors.lime) or colors.gray)
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
    m.setBackgroundColor(colors.black)
    m.clear()
    dataZones={}
    local w,h=m.getSize()
    local link=not latest and "WAIT" or (live() and "LIVE" or "OFFLINE")
    writeAt(m,1,1,string.rep(" ",w),colors.white,colors.blue)
    writeAt(m,2,1,"TY  /  MEKANISM DASHBOARD",colors.white,colors.blue)
    writeAt(m,1,2,string.rep(" ",w),colors.lightGray,colors.gray)
    writeAt(m,2,2,"PLANT #"..tostring(plantId or CFG.plant_id).."   LINK "..link,
        live() and colors.lime or colors.orange,colors.gray)

    local tabs={
        {"HOME","OVERVIEW"},{"CORE","REACTOR"},{"TURB","TURBINE"},
        {"ERROR","ERRORS"},{"API","METHODS"},
    }
    for index,item in ipairs(tabs) do
        local x=1+math.floor((index-1)*w/#tabs)
        local nextX=math.floor(index*w/#tabs)+1
        local tab=item[2]
        button(m,dataZones,x,3,nextX-x,item[1],
            view==tab and colors.blue or colors.gray,
            function() view=tab; page=1 end,true)
    end

    local canShowCards=view=="OVERVIEW" and w>=34 and h>=16
    if canShowCards then
        local col=math.floor((w-3)/2)
        local leftX,rightX=2,w-col
        cellText(m,2,4,w-2,"LIVE STATUS / READOUT",colors.cyan)
        sectionHeader(m,leftX,5,col,"FISSION REACTOR")
        sectionHeader(m,rightX,5,col,"TURBINE + TANKS")
        local function line(x,row,text,fg)
            cellText(m,x,row,col,text,fg)
        end
        local formedR=value("reactor","isFormed")
        local activeR=value("reactor","getStatus")
        local formedT=value("turbine","isFormed")
        local function yn(x)
            if x==true then return "YES" end
            if x==false then return "NO" end
            return "--"
        end
        local fuel=fraction("reactor","getFuelFilledPercentage")
        local coolant=fraction("reactor","getCoolantFilledPercentage")
        local steam=fraction("turbine","getSteamFilledPercentage")
        local waste=fraction("reactor","getWasteFilledPercentage")
        line(leftX,6,"FORMED "..yn(formedR),formedR==true and colors.lime or colors.orange)
        line(leftX,7,"ACTIVE "..yn(activeR),activeR==true and colors.lime or colors.lightGray)
        line(leftX,8,"CORE "..stringify("getTemperature",value("reactor","getTemperature")))
        line(leftX,9,"DAMAGE "..nfmt(value("reactor","getDamagePercent"),2).."%")
        line(leftX,10,"BURN "..nfmt(value("reactor","getBurnRate"),2).." mB/t")
        line(leftX,11,"ACTUAL "..nfmt(value("reactor","getActualBurnRate"),2).." mB/t")
        line(leftX,12,"FUEL "..fractionText(fuel),colors.cyan)
        progressBar(m,leftX,13,col,fuel,colors.lime)
        line(leftX,14,"COOLANT "..fractionText(coolant),colors.cyan)
        progressBar(m,leftX,15,col,coolant,colors.lightBlue)

        line(rightX,6,"FORMED "..yn(formedT),formedT==true and colors.lime or colors.orange)
        line(rightX,7,"OUTPUT "..nfmt(value("turbine","getProductionRate"),1).." e/t")
        line(rightX,8,"FLOW "..nfmt(value("turbine","getFlowRate"),1).." mB/t")
        line(rightX,9,"INLET "..nfmt(value("turbine","getLastSteamInputRate"),1).." mB/t")
        line(rightX,10,"DUMP "..tostring(value("turbine","getDumpingMode") or "--"))
        line(rightX,11,"STEAM "..fractionText(steam),colors.cyan)
        progressBar(m,rightX,12,col,steam,colors.lightBlue)
        line(rightX,13,"HEATED "..fractionText(fraction("reactor","getHeatedCoolantFilledPercentage")))
        line(rightX,14,"WASTE "..fractionText(waste),colors.cyan)
        progressBar(m,rightX,15,col,waste,colors.orange)
        writeAt(m,1,h,string.rep(" ",w),colors.lightGray,colors.gray)
        writeAt(m,2,h,"TAP CORE/TURB FOR ALL READINGS",colors.white,colors.gray)
        return
    end

    -- All original API values, diagnostics and method names remain pageable.
    local title=({OVERVIEW="SUMMARY",REACTOR="FISSION / ALL VALUES",
        TURBINE="TURBINE / ALL VALUES",ERRORS="READ ERRORS",
        METHODS="EXPOSED METHODS"})[view] or view
    cellText(m,2,4,w-2,title,colors.cyan)
    local body=wrappedRows(linesForView(),math.max(1,w-2))
    local perPage=math.max(1,h-5)
    local pages=math.max(1,math.ceil(#body/perPage))
    page=math.max(1,math.min(page,pages))
    for yy=5,h-1 do
        local index=(page-1)*perPage+(yy-5)+1
        if body[index] then
            cellText(m,2,yy,w-2,body[index],colors.white)
        end
    end
    local third=math.max(1,math.floor(w/3))
    button(m,dataZones,1,h,third,"< PREV",colors.blue,
        function() page=math.max(1,page-1) end,page>1)
    button(m,dataZones,w-third+1,h,third,"NEXT >",colors.blue,
        function() page=math.min(pages,page+1) end,page<pages)
    local counter=tostring(page).."/"..tostring(pages)
    writeAt(m,math.max(1,math.floor((w-#counter)/2)+1),h,counter,colors.cyan)
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
    if action=="scram" then return policy().scram==true end
    return false
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
    m.setBackgroundColor(colors.black)
    m.clear()
    controlZones={}
    local w,h=m.getSize()
    local half=math.floor(w/2)
    local link=not latest and "WAIT" or (live() and "LIVE" or "OFFLINE")
    writeAt(m,1,1,string.rep(" ",w),colors.white,colors.blue)
    writeAt(m,1,1,"TY / CONTROL",colors.white,colors.blue)
    writeAt(m,1,2,string.rep(" ",w),colors.lightGray,colors.gray)
    writeAt(m,1,2,"#"..tostring(plantId or CFG.plant_id).." "..link,
        live() and colors.lime or colors.orange,colors.gray)

    local function changeTab(tab)
        controlsPage=tab
        confirmCandidate=nil
    end
    for _,tab in ipairs({
        {"CORE",1,3,half},{"BURN",half+1,3,w-half},
        {"LOGIC",1,4,half},{"TURB",half+1,4,w-half},
    }) do
        local selected=controlsPage==tab[1]
        local name=tab[1]
        button(m,controlZones,tab[2],tab[3],tab[4],name,
            selected and colors.blue or colors.gray,
            function() changeTab(name) end,true)
    end

    -- Divide the remaining height into ten proportional bands. Buttons use
    -- every character row within their band, with matching touch rectangles.
    local startY,endY=5,h-2
    local bodyHeight=math.max(1,endY-startY+1)
    local function bandBounds(index)
        local y1=startY+math.floor((index-1)*bodyHeight/10)
        local y2=startY+math.floor(index*bodyHeight/10)-1
        return y1,math.max(y1,y2)
    end
    local function bandText(index,caption,fg)
        local y1,y2=bandBounds(index)
        local yy=math.floor((y1+y2)/2)
        cellText(m,1,yy,w,caption,fg)
    end
    local function wholeButton(first,last,label,color,fn,enabled)
        local y1=bandBounds(first)
        local _,y2=bandBounds(last)
        button(m,controlZones,1,y1,w,label,color,fn,enabled,y2-y1+1)
    end
    local function splitButtons(index,leftLabel,rightLabel,leftFn,rightFn,enabled)
        local y1,y2=bandBounds(index)
        button(m,controlZones,1,y1,half,leftLabel,colors.gray,leftFn,enabled,y2-y1+1)
        button(m,controlZones,half+1,y1,w-half,rightLabel,colors.gray,rightFn,enabled,y2-y1+1)
    end
    local function nn(kind,method,digits)
        return nfmt(value(kind,method),digits)
    end
    local function capText()
        return type(policy().burnRateCap)=="number" and nfmt(policy().burnRateCap,1) or "LOCKED"
    end

    if controlsPage=="CORE" then
        local running=value("reactor","getStatus")
        bandText(1,"FISSION STATUS",colors.cyan)
        bandText(2,"STATE "..(running==true and "RUN" or (running==false and "STOP" or "--")),
            running==true and colors.lime or colors.orange)
        bandText(3,"TEMP "..nn("reactor","getTemperature",1).." C")
        bandText(4,"BURN "..nn("reactor","getBurnRate",2))
        bandText(5,"DAMAGE "..nn("reactor","getDamagePercent",1).."%")
        bandText(6,"CAP "..capText(),colors.lightGray)
        wholeButton(7,8,"ACTIVATE",colors.orange,function()
            requestCommand("activate")
        end,actionAllowed("activate"))
        wholeButton(9,10,"SCRAM / STOP",colors.red,function()
            requestCommand("scram")
        end,actionAllowed("scram"))
    elseif controlsPage=="BURN" then
        local en=actionAllowed("setBurnRate")
        bandText(1,"BURN RATE",colors.cyan)
        bandText(2,"LIVE "..nn("reactor","getBurnRate",2))
        bandText(3,"SET  "..nfmt(burnDraft or value("reactor","getBurnRate"),2),colors.yellow)
        bandText(4,"CAP  "..capText(),colors.lightGray)
        splitButtons(5,"-10","+10",function()shiftBurn(-10) end,function()shiftBurn(10) end,en)
        splitButtons(6,"-1","+1",function()shiftBurn(-1) end,function()shiftBurn(1) end,en)
        splitButtons(7,"-0.1","+0.1",function()shiftBurn(-0.1) end,function()shiftBurn(0.1) end,en)
        wholeButton(8,10,"APPLY BURN",colors.orange,function()
            requestCommand("setBurnRate",burnDraft or value("reactor","getBurnRate"))
        end,en)
    elseif controlsPage=="LOGIC" then
        local current=tostring(value("reactor","getLogicMode") or "--")
        local drafted=tostring(logicDraft or value("reactor","getLogicMode") or "--")
        local limit=math.max(1,w-4)
        bandText(1,"REACTOR LOGIC",colors.cyan)
        bandText(2,"NOW "..current:sub(1,limit))
        bandText(3,"    "..current:sub(limit+1))
        bandText(4,"SET "..drafted:sub(1,limit),colors.yellow)
        bandText(5,"    "..drafted:sub(limit+1),colors.yellow)
        local en=actionAllowed("setLogicMode")
        wholeButton(6,6,"< PREVIOUS",colors.gray,function()nextLogic(-1) end,en)
        wholeButton(7,7,"NEXT MODE >",colors.gray,function()nextLogic(1) end,en)
        wholeButton(8,10,"APPLY LOGIC",colors.orange,function()
            requestCommand("setLogicMode",logicDraft or value("reactor","getLogicMode"))
        end,en)
    else
        local en=actionAllowed("setDumpingMode")
        bandText(1,"TURBINE / H2O",colors.cyan)
        bandText(2,"OUT "..nn("turbine","getProductionRate",1).." e/t")
        bandText(3,"FLOW "..nn("turbine","getFlowRate",1))
        bandText(4,"STEAM "..fractionText(fraction("turbine","getSteamFilledPercentage")))
        bandText(5,"DUMP->H2O LOSS",colors.orange)
        bandText(6,tostring(value("turbine","getDumpingMode") or "--"),colors.yellow)
        wholeButton(7,7,"IDLE",colors.green,function()
            requestCommand("setDumpingMode",DUMP_MODES[1]) end,en)
        wholeButton(8,8,"EXCESS",colors.orange,function()
            requestCommand("setDumpingMode",DUMP_MODES[2]) end,en)
        wholeButton(9,10,"DUMP / LOSS",colors.red,function()
            requestCommand("setDumpingMode",DUMP_MODES[3]) end,en)
    end

    -- Reserve the bottom two rows for the persistent command result.
    local info=lastAck or "2-TAP / SCRAM 1"
    if confirmCandidate then info="TAP SAME AGAIN TO CONFIRM" end
    local alert=lastAck and lastAck:match("FAILED|LOCKED|NO ACK|ERROR|did not match")
    writeAt(m,1,h-1,string.rep(" ",w),colors.white,colors.gray)
    writeAt(m,1,h,string.rep(" ",w),colors.white,colors.gray)
    writeAt(m,1,h-1,info:sub(1,w),alert and colors.orange or colors.cyan,colors.gray)
    writeAt(m,1,h,info:sub(w+1,2*w),alert and colors.orange or colors.white,colors.gray)
end

local function touch(zones,x,y)
    for _,z in ipairs(zones) do
        if y>=(z.y1 or z.y) and y<=(z.y2 or z.y)
            and x>=z.x1 and x<=z.x2 then
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
local dataScale=fitScale(data.monitor,34,16)
local controlScale=fitScale(control.monitor,14,16)
print("TY Mekanism base computer #"..os.getComputerID())
print("Dashboard scale: "..tostring(dataScale).." | Control scale: "..tostring(controlScale))
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
        if a==data.name then fitScale(data.monitor,34,16) end
        if a==control.name then fitScale(control.monitor,14,16) end
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
