local name, A = ...
_G.RebuffedAltoholic = A
A.name, A.version = name, "1.0.0"
A.de = GetLocale() == "deDE"
function A.Text(de, en) return A.de and de or en end
function A.Say(message) DEFAULT_CHAT_FRAME:AddMessage("|cff57c8ffRebuffedAltoholic:|r " .. message) end
local events, jobs, clock = {}, {}, 0
local frame = CreateFrame("Frame")
A.frame = frame
function A.On(event, callback)
    if not events[event] then
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then return end
        events[event] = {}
    end
    events[event][#events[event] + 1] = callback
end
function A.After(key, seconds, callback)
    jobs[key] = {at = clock + seconds, fn = callback}
    frame:SetScript("OnUpdate", function(self, elapsed)
        clock = clock + elapsed
        local ready = {}
        for k, job in pairs(jobs) do
            if job.at <= clock then jobs[k] = nil; ready[#ready + 1] = job.fn end
        end
        for _, fn in ipairs(ready) do
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
        if not next(jobs) then self:SetScript("OnUpdate", nil) end
    end)
end
function A.Cancel(key) jobs[key] = nil end
function A.Changed()
    A.ownership = nil
    if A.window and A.window:IsShown() then A.After("refresh", .15, A.Refresh) end
end
function A.Init()
    if A.db then return end
    if type(RebuffedAltoholicDB) ~= "table" then RebuffedAltoholicDB = {} end
    local db = RebuffedAltoholicDB
    db.characters = type(db.characters) == "table" and db.characters or {}
    db.itemRealms = type(db.itemRealms) == "table" and db.itemRealms or {}
    db.guilds = type(db.guilds) == "table" and db.guilds or {}
    db.options = type(db.options) == "table" and db.options or {}
    db.imports = type(db.imports) == "table" and db.imports or {}
    db.schema = 1
    A.db = db
    A.realm = GetRealmName() or "Unknown"
    db.itemRealms[A.realm] = db.itemRealms[A.realm] or {}
    A.items = db.itemRealms[A.realm]
    A.key = A.realm .. "\031" .. UnitName("player")
    db.characters[A.key] = db.characters[A.key] or {}
    A.current = db.characters[A.key]
    A.current.name, A.current.realm = UnitName("player"), A.realm
    A.current.sources = A.current.sources or {}
end
function A.Save(source, data)
    if not A.current then return end
    A.current[source] = data
    A.current.sources[source] = time()
    A.Changed()
end
function A.Characters(allRealms)
    local result = {}
    for key, char in pairs(A.db.characters) do
        if allRealms or char.realm == A.realm then result[#result + 1] = {key = key, char = char} end
    end
    table.sort(result, function(a, b)
        if a.char.realm ~= b.char.realm then return a.char.realm < b.char.realm end
        return (a.char.name or a.key):lower() < (b.char.name or b.key):lower()
    end)
    return result
end
function A.Money(amount)
    amount = math.floor(tonumber(amount) or 0)
    return string.format("%dg %ds %dc", math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100)
end
function A.Age(stamp)
    if not stamp then return A.Text("Noch nicht erfasst", "Not recorded yet") end
    local hours = math.max(0, math.floor((time() - stamp) / 3600))
    if hours < 1 then return A.Text("vor kurzem", "recently") end
    if hours < 24 then return hours .. "h" end
    return math.floor(hours / 24) .. A.Text(" Tage", " days")
end
function A.CurrentCharacter()
    local record = A.selected and A.db.characters[A.selected]
    return record or A.current
end
frame:SetScript("OnEvent", function(self, event, ...)
    for _, callback in ipairs(events[event] or {}) do
        local ok, err = pcall(callback, ...)
        if not ok then geterrorhandler()(err) end
    end
end)
A.On("PLAYER_LOGIN", function()
    A.Init()
    if A.CreateMinimap then A.CreateMinimap() end
    if A.ScanLogin then A.ScanLogin() end
end)
A.On("PLAYER_LOGOUT", function()
    if A.ScanCharacter and A.current then A.ScanCharacter() end
end)
