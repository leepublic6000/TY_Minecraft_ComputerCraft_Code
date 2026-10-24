-- TY in-game Pocket 2FA inbox. Run on TRUSTED Pocket #6 in another shell tab.
-- OTP is transported over unencrypted Rednet; trusted private worlds only.
if os.getComputerID()~=6 then error("Pocket #6 only",0) end
local opened=false
for _,side in ipairs(peripheral.getNames()) do
    if peripheral.hasType(side,"modem") and peripheral.call(side,"isWireless") then
        rednet.open(side);opened=true
    end
end
assert(opened,"Pocket modem missing")
local proto="ty.auth.v1:2fa_push"
print("TY Pocket 2FA inbox / #6")
print("Keep this tab open. Switch here for login codes.")
print("Do not share codes. Ctrl+T to stop.")
while true do
    local sender,msg=rednet.receive(proto)
    if sender==0 and type(msg)=="table" and msg.v==1
        and type(msg.otp)=="string" and msg.otp:match("^%d%d%d%d%d%d$") then
        print("Login requested by computer #"..tostring(msg.device))
        print("Player UUID ending: "..tostring(msg.uuidSuffix))
        print("2FA CODE: "..msg.otp)
        print("Enter this code on the requesting computer (valid up to 120s).")
    end
end
