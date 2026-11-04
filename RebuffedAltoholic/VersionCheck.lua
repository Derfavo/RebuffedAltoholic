local addonName = ...
local manager = _G.RebuffedVersionChecks
if not manager then
    manager = {addons = {}, installed = {}, pending = {}, lastSent = {}, candidates = {}, notified = {}}
    _G.RebuffedVersionChecks = manager
    local prefix, frame, elapsed = "RBFVER1", CreateFrame("Frame"), 0
    local function parse(value)
        if type(value) ~= "string" or #value > 11 then return end
        local a,b,c = value:match("^(%d+)%.(%d+)%.(%d+)$")
        a,b,c = tonumber(a),tonumber(b),tonumber(c)
        if a and a <= 999 and b <= 999 and c <= 999 then return a,b,c end
    end
    local function newer(a,b)
        local x,y,z = parse(a)
        local i,j,k = parse(b)
        return x and i and (x > i or x == i and (y > j or y == j and z > k)) or false
    end
    manager.newer = newer
    local function database(name)
        local key = name .. "VersionDB"
        if type(_G[key]) ~= "table" then _G[key] = {} end
        return _G[key]
    end
    local function validDate(value)
        return type(value) == "string" and value:match("^%d%d%d%d%d%d%d%d$")
            and tonumber(value) >= 20000101 and tonumber(value) <= tonumber(date("%Y%m%d"))
    end
    local function report(name, all)
        local current = GetAddOnMetadata(name,"Version") or "0.0.0"
        local saved = database(name)
        local german = GetLocale() == "deDE"
        local url = "https://github.com/Derfavo/" .. name .. "/releases/latest"
        if newer(saved.latest,current) and validDate(saved.release) then
            if all or manager.notified[name] ~= saved.latest then
                local text = german and "%s: Neuere Version %s erkannt (installiert: %s). Download: %s"
                    or "%s: Newer version %s detected (installed: %s). Download: %s"
                DEFAULT_CHAT_FRAME:AddMessage("|cffffc040" .. string.format(text,name,saved.latest,current,url) .. "|r")
                manager.notified[name] = saved.latest
            end
        elseif all then
            DEFAULT_CHAT_FRAME:AddMessage(name .. ": " .. current .. (german and " | keine neuere Version bei anderen Spielern bestätigt" or " | no newer version confirmed by other players") .. " | " .. url)
        end
    end
    local function available(channel)
        if channel == "GUILD" then
            local member = IsInGuild and IsInGuild()
            -- Some 3.3.5 compatibility APIs return 0 instead of false. Also wait
            -- for the player's guild name so a stale login flag cannot send.
            if member ~= true and member ~= 1 then return false end
            local name = GetGuildInfo and GetGuildInfo("player")
            return type(name) == "string" and name:find("%S") ~= nil
        end
        if channel == "RAID" then return GetNumRaidMembers() > 0 end
        return channel == "PARTY" and GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0
    end
    local function send(channel, query)
        if not SendAddonMessage or not available(channel) then return end
        local now = GetTime()
        if manager.lastSent[channel] and now - manager.lastSent[channel] < 30 then return end
        manager.lastSent[channel] = now
        if query then SendAddonMessage(prefix,"Q",channel) end
        for _,name in ipairs(manager.addons) do
            local version = GetAddOnMetadata(name,"Version")
            local release = GetAddOnMetadata(name,"X-Release-Date")
            if parse(version) and validDate(release) then
                SendAddonMessage(prefix,"V\t" .. name .. "\t" .. version .. "\t" .. release,channel)
            end
        end
    end
    local function queue(channel, query)
        if not available(channel) then return end
        manager.pending[channel] = manager.pending[channel] or query and "query" or "reply"
        if query then manager.pending[channel] = "query" end
        elapsed = 0
        frame:SetScript("OnUpdate",function(self, delta)
            elapsed = elapsed + delta
            if elapsed < 3 then return end
            self:SetScript("OnUpdate",nil)
            for target,kind in pairs(manager.pending) do
                manager.pending[target] = nil
                send(target,kind == "query")
            end
        end)
    end
    local function discover()
        queue("GUILD",true)
        queue(GetNumRaidMembers() > 0 and "RAID" or "PARTY",true)
    end
    local function receive(message, channel, sender)
        if not available(channel) or type(message) ~= "string" or #message > 128
            or type(sender) ~= "string" or sender == "" then return end
        local short = sender:match("^[^-]+")
        if short and short:lower() == (UnitName("player") or ""):lower() then return end
        if message == "Q" then queue(channel,false); return end
        local name,version,release = message:match("^V\t([%w]+)\t([%d%.]+)\t(%d+)$")
        if not manager.installed[name] or not newer(version,GetAddOnMetadata(name,"Version")) or not validDate(release) then return end
        local saved = database(name)
        if saved.latest and not newer(version,saved.latest) then return end
        local candidates = manager.candidates[name] or {count = 0}
        manager.candidates[name] = candidates
        local key = version .. ":" .. release
        local candidate = candidates[key]
        if not candidate then
            if candidates.count >= 8 then return end
            candidate = {senders = {}, count = 0}
            candidates[key] = candidate; candidates.count = candidates.count + 1
        end
        local identity = sender:lower()
        if candidate.senders[identity] then return end
        candidate.senders[identity] = true; candidate.count = candidate.count + 1
        -- Like the installed DBM, require two independent players before warning.
        if candidate.count >= 2 then
            saved.latest, saved.release = version, release
            manager.candidates[name] = nil
            report(name,false)
        end
    end
    manager.receive = receive
    for _,event in ipairs({"PLAYER_LOGIN","PARTY_MEMBERS_CHANGED","RAID_ROSTER_UPDATE","PLAYER_GUILD_UPDATE","CHAT_MSG_ADDON"}) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent",function(self,event,a,b,c,d)
        if event == "CHAT_MSG_ADDON" then
            if a == prefix then receive(b,c,d) end
        elseif event == "PLAYER_LOGIN" then
            for _,name in ipairs(manager.addons) do report(name,false) end
            discover()
        else discover() end
    end)
    if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(prefix) end
    SLASH_REBUFFEDUPDATES1 = "/rebuffedupdates"
    SlashCmdList.REBUFFEDUPDATES = function() for _,name in ipairs(manager.addons) do report(name,true) end end
end
if not manager.installed[addonName] then
    manager.installed[addonName] = true
    manager.addons[#manager.addons + 1] = addonName
end
