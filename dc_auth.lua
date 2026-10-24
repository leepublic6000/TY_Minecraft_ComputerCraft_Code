-- TY Minecraft ComputerCraft Code - in-world player authentication v1
-- Runs INSIDE dc_center.lua on Computer #0. Chat Box UUID events are the
-- authoritative in-game player identifier; NOT an external identity provider.
-- WARNING: Rednet is not encrypted; bearer tokens can be observed/copied.
-- Intended only for a trusted private Minecraft world. Never expose as SSH.
local M = {}
local FILE = "ty_auth_state.json"
local AUDIT = "ty_auth_audit.jsonl"
local PROTOCOL = "ty.auth.v1:request"
local ANSWER = "ty.auth.v1:reply"
local OTP_TTL = 120000     -- milliseconds, user requested 2 minutes
local MAX_ATTEMPTS = 5
local SESSION_IDLE = 30 * 60 * 1000
local MAX_PENDING = 20
local MAX_INPUT = 128
local PUSH = "ty.auth.v1:2fa_push"
local recent = {}
local state, pending, sessions = nil, {}, {}
local claim = nil
local senderCallback, onRevoked = nil, nil

local function clock() return os.epoch("utc") end
local function validInt(n) return type(n)=="number" and n>=0 and n<65536 and n==math.floor(n) end
local function send(id, requestId, ok, message, extra)
    if not senderCallback then return end
    local resp = {v=1, rid=requestId, ok=ok, message=message}
    if extra then for k,v in pairs(extra) do resp[k]=v end end
    senderCallback(id, resp, ANSWER)
end
local function safeRead(file)
    if not fs.exists(file) then return nil end
    local f=fs.open(file,"r")
    if not f then return nil end
    local content=f.readAll(); f.close()
    return content
end
local function persist()
    local target=FILE..".tmp"
    local contents=textutils.serialiseJSON(state)
    if not contents then return false,"JSON encoding failed" end
    local h=fs.open(target,"w")
    if not h then return false,"Cannot open state tmp" end
    h.write(contents);h.close()
    if safeRead(target)~=contents then return false,"Temporary write mismatch" end
    local previous=FILE..".bak"
    local ok, err=pcall(function()
        if fs.exists(previous) then fs.delete(previous) end
        if fs.exists(FILE) then fs.copy(FILE,previous);fs.delete(FILE) end
        fs.move(target,FILE)
    end)
    if not ok then
        if not fs.exists(FILE) and fs.exists(previous) then pcall(fs.copy,previous,FILE) end
        return false,tostring(err)
    end
    return true
end
local function audit(uuid,dev,action,result)
    local h=fs.open(AUDIT,"a")
    if h then
        h.writeLine(textutils.serialiseJSON({time=clock(),uuid=uuid,device=dev,action=action,result=result}))
        h.close()
    end
end
-- math.random is not a CSPRNG. Tokens protect against accidental misuse on
-- trusted networks; they do not resist dedicated Rednet interception.
local seeded=false
local function randomDigits(n)
    if not seeded then
        local seed=clock()%2147483647+os.getComputerID()*7919+math.floor(os.clock()*1000)
        math.randomseed(seed);seeded=true
    end
    local result={}
    for i=1,n do result[i]=tostring(math.random(0,9)) end
    return table.concat(result)
end
local function randomHex(n)
    local digits="0123456789abcdef"
    local out={}
    for i=1,n do local j=math.random(1,16);out[i]=digits:sub(j,j) end
    return table.concat(out)
end
local function freshCode(len) randomDigits(1);return randomHex(len or 16) end
local function isUUID(uuid)
    return type(uuid)=="string" and #uuid>=32 and #uuid<=40 and uuid:match("^[%x%-]+$")~=nil
end
local function user(uuid)
    return state.players[uuid]
end
local function validateSession(sender, token, action)
    if type(token)~="string" or #token>100 then return nil,"Login required" end
    local sess=sessions[token]
    if not sess then return nil,"Session expired or invalid" end
    if sess.device~=sender then return nil,"Session bound to another computer" end
    if clock()-sess.last>SESSION_IDLE then
        sessions[token]=nil
        return nil,"Session expired or invalid"
    end
    local info=user(sess.uuid)
    if not info or info.revokedAt and info.revokedAt>sess.issued then
        sessions[token]=nil
        return nil,"Device access revoked"
    end
    if action and info.role~="admin" and action~="nodes" and action~="info" and action~="status" then
        return nil,"Permission denied"
    end
    sess.last=clock()
    return sess
end
local function newSession(uuid,device)
    local token=freshCode(48)
    sessions[token]={uuid=uuid,device=device,issued=clock(),last=clock()}
    audit(uuid,device,"session_open","ok")
    return token
end
function M.configure(sendFunction, revokedCallback)
    senderCallback=sendFunction
    onRevoked=revokedCallback
    local contents=safeRead(FILE)
    if contents then
        local ok, obj=pcall(textutils.unserialiseJSON,contents)
        if not ok or type(obj)~="table" or type(obj.players)~="table" or type(obj.trusted)~="table" then
            error("Invalid authentication state. Repair ty_auth_state.json before starting.")
        end
        state=obj
    else
        state={version=1, enabled=false, players={}, trusted={}}
    end
end
function M.enabled() return state and state.enabled==true end
function M.authorize(sender, token, action)
    if not M.enabled() then return true,nil end
    return validateSession(sender,token,action)
end
function M.authorizedUser(sender,token,action)
    if not M.enabled() then return nil end
    local session=validateSession(sender,token,action)
    return session and session.uuid or nil
end
function M.accountCount()
    local total=0
    for _ in pairs(state.players) do total=total+1 end
    return total
end
function M.beginClaim(role)
    if role~="admin" and role~="viewer" then return false,"Role must be admin/viewer" end
    if M.accountCount()==0 and role~="admin" then return false,"First enrolled account must be admin" end
    local code=randomDigits(8)
    claim={expires=clock()+120000,code=code,role=role}
    return true,"In Minecraft chat enter: $tyclaim "..code.." (valid 120 seconds). Return here to confirm."
end
function M.confirmClaim()
    if not claim or not claim.uuid or clock()>claim.expires then return false,"No verified claim from Chat Box" end
    local candidate=claim
    claim=nil
    local old=state.players[candidate.uuid]
    state.players[candidate.uuid]={name=candidate.name,role=candidate.role}
    local ok,why=persist()
    if not ok then state.players[candidate.uuid]=old;return false,why end
    audit(candidate.uuid,0,"owner_claim","ok")
    return true,"Player registered ("..candidate.role.."): "..candidate.name.." (UUID suffix "..candidate.uuid:sub(-8)..")"
end
function M.enable()
    if M.accountCount()<1 then return false,"Register an admin with auth claim first" end
    if not peripheral.find("chat_box") then return false,"Chat Box missing; authentication not enabled" end
    state.enabled=true
    local ok,why=persist()
    if not ok then state.enabled=false;return false,why end
    audit(nil,0,"auth_enable","ok")
    return true,"Authentication enabled. Existing Pocket sessions must log in."
end
function M.status()
    return "Auth: "..(M.enabled() and "ENABLED" or "DISABLED")..", players: "..M.accountCount()..", pending: "..(function()local n=0;for _ in pairs(pending) do n=n+1 end;return n end)()
end
local function delivery(uuid,name,txt)
    local box=peripheral.find("chat_box")
    if not box then return false,"Chat Box disconnected" end
    local ok,sent,reason=pcall(box.sendMessage,txt,{player=name,prefix="TY"})
    if not ok then return false,tostring(sent) end
    if sent~=true then return false,tostring(reason or "Chat Box rejected message") end
    return true
end
function M.chat(uuid,name,msg,hidden)
    if not hidden or not isUUID(uuid) or type(name)~="string" or type(msg)~="string" then return end
    if msg:sub(1,1)=="$" then msg=msg:sub(2) end
    if claim and not claim.uuid and clock()<=claim.expires and msg=="tyclaim "..claim.code then
        claim.uuid=uuid;claim.name=name
        print("[TY AUTH] Claim detected from "..name.."; type 'auth confirm' at centre #0.")
        return
    end
    if msg=="tyrevokeall" then
        local u=user(uuid)
        if not u then return end
        local prev=state.trusted[uuid]
        local oldRevoked=u.revokedAt
        state.trusted[uuid]={}
        u.revokedAt=clock()
        local ok,why=persist()
        if not ok then state.trusted[uuid]=prev;u.revokedAt=oldRevoked;print("[TY AUTH] REVOKE FAILED: "..tostring(why));return end
        for token,session in pairs(sessions) do if session.uuid==uuid then sessions[token]=nil end end
        -- Invalidate all pending challenges (including those not bound to a UUID yet).
        -- This makes lost-device revocation effective against in-flight attempts.
        for id in pairs(pending) do pending[id]=nil end
        if onRevoked then
            local notified,notifyErr=pcall(onRevoked,uuid)
            if not notified then print("[TY AUTH] Active shell close failed: "..tostring(notifyErr)) end
        end
        audit(uuid,0,"revoke_all","ok")
        local sent,reason=delivery(uuid,name,"All TY in-world sessions/devices revoked. Login again to use them.")
        if not sent then print("[TY AUTH] Revoked, but chat reply failed: "..tostring(reason)) end
        return
    end
    local code=msg:match("^tylogin ([%x]+)$")
    if not code then return end
    for id,req in pairs(pending) do
        if req.stage=="chat" and req.challenge==code and clock()<req.expires then
            local account=user(uuid)
            if not account then
                audit(uuid,id,"login_player_unknown","deny")
                return
            end
            req.uuid=uuid;req.username=name;req.otp=randomDigits(6)
            req.stage="otp";req.expires=clock()+OTP_TTL
            local ok,reason
            if id==6 then
                ok,reason=delivery(uuid,name,"TY login code: "..req.otp.." (120 sec, max 5 attempts)")
            elseif (state.trusted[uuid] or {})["6"] then
                ok=senderCallback(6,{v=1,device=id,uuidSuffix=uuid:sub(-8),otp=req.otp,expires=req.expires},PUSH)
                reason=ok and nil or "Cannot send to trusted Pocket #6"
            else
                ok,reason=false,"No trusted Pocket #6; other computers require Pocket 2FA"
            end
            if not ok then
                pending[id]=nil
                print("[TY AUTH] OTP delivery failed: "..tostring(reason))
            else audit(uuid,id,"otp_issued","ok") end
            return
        end
    end
end
function M.handle(sender,p)
    if not validInt(sender) or type(p)~="table" or p.v~=1 or type(p.rid)~="string" or #p.rid>60 or type(p.action)~="string" then return end
    local rid,action=p.rid,p.action
    if action=="config" then
        return send(sender,rid,true,"Authentication configuration",{enabled=M.enabled()})
    elseif action=="begin" then
        if not M.enabled() then return send(sender,rid,false,"Auth disabled; centre admin must enable first") end
        local n=0
        for k,req in pairs(pending) do
            if clock()>req.expires then pending[k]=nil else n=n+1 end
        end
        if n>=MAX_PENDING then return send(sender,rid,false,"Too many pending logins") end
        local last=recent[sender] or 0
        if clock()-last<10000 then return send(sender,rid,false,"Wait before another login request") end
        recent[sender]=clock()
        local challenge=freshCode(8)
        pending[sender]={stage="chat",challenge=challenge,expires=clock()+OTP_TTL,attempts=0}
        return send(sender,rid,true,"Type this in Minecraft chat: $tylogin "..challenge,{challenge=challenge})
    elseif action=="verify" then
        local req=pending[sender]
        if not req or req.stage~="otp" or clock()>req.expires then
            pending[sender]=nil;return send(sender,rid,false,"Login expired or not ready")
        end
        req.attempts=req.attempts+1
        if req.attempts>MAX_ATTEMPTS or type(p.code)~="string"
            or not p.code:match("^%d%d%d%d%d%d$") or p.code~=req.otp then
            if req.attempts>=MAX_ATTEMPTS then pending[sender]=nil end
            audit(req.uuid,sender,"otp_attempt","deny")
            return send(sender,rid,false,"Wrong code, attempts left "..math.max(0,MAX_ATTEMPTS-req.attempts))
        end
        local token=newSession(req.uuid,sender)
        pending[sender]=nil
        return send(sender,rid,true,"Signed in",{session=token,uuid=req.uuid,role=user(req.uuid).role})
    elseif action=="resume" then
        if type(p.secret)~="string" or #p.secret~=48 then return send(sender,rid,false,"No stored device credential") end
        for uuid,devices in pairs(state.trusted) do
            if devices[tostring(sender)]==p.secret and user(uuid) then
                local token=newSession(uuid,sender)
                return send(sender,rid,true,"Trusted device signed in",{session=token,uuid=uuid,role=user(uuid).role})
            end
        end
        return send(sender,rid,false,"Device not trusted or revoked")
    elseif action=="trust" then
        if sender~=6 then return send(sender,rid,false,"Only Pocket #6 can be trusted for 2FA") end
        local session=validateSession(sender,p.session)
        if not session then return send(sender,rid,false,"Login required") end
        local uuid=session.uuid
        local secret=freshCode(48)
        state.trusted[uuid]=state.trusted[uuid] or {}
        local previous=state.trusted[uuid][tostring(sender)]
        state.trusted[uuid][tostring(sender)]=secret
        local ok,reason=persist()
        if not ok then state.trusted[uuid][tostring(sender)]=previous;return send(sender,rid,false,reason) end
        audit(uuid,sender,"device_trust","ok")
        return send(sender,rid,true,"Device trusted until revoked",{secret=secret})
    elseif action=="logout" then
        local sess=sessions[p.session]
        if sess and sess.device==sender then sessions[p.session]=nil;audit(sess.uuid,sender,"logout","ok") end
        return send(sender,rid,true,"Logged out")
    elseif action=="status" then
        local sess=validateSession(sender,p.session)
        return send(sender,rid,not not sess,sess and "Authenticated" or "Not authenticated")
    end
end
function M.protocol() return PROTOCOL end
function M.audit(uuid,dev,action,result) audit(uuid,dev,action,result) end
function M.revokeSessions(uuid)
    for token,sess in pairs(sessions) do if sess.uuid==uuid then sessions[token]=nil end end
end
return M
