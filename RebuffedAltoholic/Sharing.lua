local _, A = ...
local PREFIX, LIMIT = "RBFALT1", 4 * 1024 * 1024
local pending, requested, lastRequest = {}, {}, {}
local incoming, outgoing, serial
local function validName(name)
    return type(name) == "string" and #name > 0 and #name <= 64 and not name:find("[%s%c|]")
end
-- A bounded data format, not executable Lua. Never deserialize with loadstring.
local function encode(value, depth, seen)
    depth, seen = depth or 0, seen or {}
    if depth > 20 then error("Account data is nested too deeply") end
    local kind = type(value)
    if kind == "nil" then return "z" end
    if kind == "boolean" then return value and "b1" or "b0" end
    if kind == "number" then return "n" .. tostring(value) .. ";" end
    if kind == "string" then return "s" .. #value .. ":" .. value end
    if kind ~= "table" or seen[value] then error("Unsupported account data") end
    seen[value] = true
    local parts, count = {}, 0
    for key, child in pairs(value) do
        count = count + 1
        parts[#parts + 1] = encode(key, depth + 1, seen)
        parts[#parts + 1] = encode(child, depth + 1, seen)
    end
    seen[value] = nil
    return "t" .. count .. ":" .. table.concat(parts)
end
local function decode(payload)
    if type(payload) ~= "string" or #payload > LIMIT then error("Invalid account data size") end
    local cursor, nodes = 1, 0
    local function numberUntil(delimiter)
        local ending = payload:find(delimiter, cursor, true)
        if not ending or ending - cursor > 30 then error("Invalid account data length") end
        local number = tonumber(payload:sub(cursor, ending - 1)); cursor = ending + 1
        if not number or number ~= number or number == math.huge or number == -math.huge then error("Invalid account number") end
        return number
    end
    local function read(depth)
        nodes = nodes + 1
        if depth > 20 or nodes > 400000 then error("Account data is too complex") end
        local tag = payload:sub(cursor, cursor); cursor = cursor + 1
        if tag == "z" then return nil end
        if tag == "b" then
            local bit = payload:sub(cursor, cursor); cursor = cursor + 1
            if bit ~= "0" and bit ~= "1" then error("Invalid account boolean") end
            return bit == "1"
        end
        if tag == "n" then return numberUntil(";") end
        if tag == "s" then
            local length = numberUntil(":")
            if length < 0 or length % 1 ~= 0 or cursor + length - 1 > #payload then error("Invalid account string") end
            local result = payload:sub(cursor, cursor + length - 1); cursor = cursor + length
            return result
        end
        if tag == "t" then
            local count = numberUntil(":")
            if count < 0 or count > 200000 or count % 1 ~= 0 then error("Invalid account table") end
            local result = {}
            for i = 1, count do
                local key = read(depth + 1)
                if type(key) ~= "number" and type(key) ~= "string" then error("Invalid account key") end
                result[key] = read(depth + 1)
            end
            return result
        end
        error("Invalid account data tag")
    end
    local result = read(0)
    if cursor ~= #payload + 1 then error("Unexpected account data suffix") end
    return result
end
A.EncodeAccount, A.DecodeAccount = encode, decode
local function send(message, target)
    if #message > 240 then return end
    SendAddonMessage(PREFIX, message, "WHISPER", target)
end
function A.RequestAccount(name)
    A.Init()
    if not validName(name) then A.Say(A.Text("Nutze /ralt request Name", "Use /ralt request Name")); return end
    local key = name:lower()
    if (lastRequest[key] or -100) + 30 > GetTime() then return end
    lastRequest[key], requested[key] = GetTime(), GetTime() + 120
    send("Q", name)
    A.Say(A.Text("Account-Anfrage gesendet an ", "Account request sent to ") .. name)
end
local function export()
    local characters, items = {}, {}
    for key, char in pairs(A.db.characters) do
        if char.realm == A.realm and not char.imported then
            characters[key] = char
            A.EachHolding(char, function(item) if A.items[item.id] then items[item.id] = A.items[item.id] end end)
            for _, p in pairs(char.professions or {}) do
                for _, r in ipairs(p.recipes) do if r.id then items[r.id] = A.items[r.id] end end
            end
        end
    end
    return {schema = 1, realm = A.realm, characters = characters, items = items}
end
local function nextPacket()
    local transaction = outgoing
    if not transaction then return end
    local start = (transaction.index - 1) * 180 + 1
    send("D\t" .. transaction.id .. "\t" .. transaction.index .. "\t" .. transaction.payload:sub(start, start + 179), transaction.target)
    transaction.index = transaction.index + 1
    if transaction.index <= transaction.count then A.After("share-send", .1, nextPacket)
    else outgoing = nil; A.Say(A.Text("Account-Daten gesendet.", "Account data sent.")) end
end
function A.AcceptAccount(name)
    if not A.db or not validName(name) then return end
    local key = name:lower()
    if not pending[key] or GetTime() > pending[key] then
        A.Say(A.Text("Keine aktuelle Anfrage von diesem Spieler.", "No current request from this player.")); return
    end
    if outgoing then A.Say(A.Text("Es l\195\164uft bereits eine \195\156bertragung.", "A transfer is already running.")); return end
    local ok, payload = pcall(encode, export())
    if not ok or #payload > LIMIT then A.Say(A.Text("Account-Daten sind zu gro\195\159.", "Account data is too large.")); return end
    pending[key] = nil
    serial = (serial or 0) + 1
    local id = tostring(time()) .. "-" .. serial
    outgoing = {target = name, payload = payload, id = id, index = 1, count = math.ceil(#payload / 180)}
    send("B\t" .. id .. "\t" .. outgoing.count .. "\t" .. #payload, name)
    A.After("share-send", .1, nextPacket)
end
local function import(payload, sender)
    local ok, data = pcall(decode, payload)
    if not ok or type(data) ~= "table" or data.schema ~= 1 or type(data.realm) ~= "string"
        or type(data.characters) ~= "table" or type(data.items) ~= "table" then return false end
    -- Validate the entire shape before touching saved data. Imported objects may
    -- only contain the same bounded scalar/table records as a local snapshot.
    local count = 0
    for key, char in pairs(data.characters) do
        count = count + 1
        if count > 100 or type(key) ~= "string" or type(char) ~= "table"
            or type(char.name) ~= "string" or char.realm ~= data.realm or type(char.sources) ~= "table" then return false end
        if #char.name > 64 or #char.realm > 128 or char.name:find("[%c|]") or char.realm:find("[%c|]") then return false end
        for _, field in ipairs({"money", "level", "xp", "xpMax", "rest", "seen", "bagUsed", "bagCapacity", "bankUsed", "bankCapacity", "itemLevel", "activeTalents", "played", "achievementPoints"}) do
            if char[field] ~= nil and type(char[field]) ~= "number" then return false end
        end
        for _, field in ipairs({"class", "classToken", "race", "faction", "guild", "zone"}) do
            if char[field] ~= nil and type(char[field]) ~= "string" then return false end
        end
        for _, source in ipairs({"bags", "bank", "equipment", "mail", "auctions", "bids"}) do
            if char[source] then
                if type(char[source]) ~= "table" then return false end
                for _, item in pairs(char[source]) do
                    if type(item) ~= "table" or type(item.id) ~= "number" or type(item.link) ~= "string"
                        or item.id <= 0 or type(item.count) ~= "number" or item.count < 0
                        or not item.link:find("item:" .. item.id, 1, true) then return false end
                    for _, field in ipairs({"slot", "bag", "expires", "bid", "buyout"}) do
                        if item[field] ~= nil and type(item[field]) ~= "number" then return false end
                    end
                end
            end
        end
        local fields = {
            messages = {"money", "expires", "cod"}, skills = {"rank", "maxRank"},
            reputations = {"value", "bottom", "top", "standing"}, currencies = {"count"},
            achievements = {"id", "points"}, lockouts = {"expires"},
            quests = {}, spells = {}, companions = {},
        }
        for source, numbers in pairs(fields) do
            if char[source] ~= nil then
                if type(char[source]) ~= "table" then return false end
                for _, record in pairs(char[source]) do
                    if type(record) ~= "table" or type(record.name) ~= "string" then return false end
                    for _, field in ipairs(numbers) do if type(record[field]) ~= "number" then return false end end
                end
            end
        end
        if char.stats ~= nil then
            if type(char.stats) ~= "table" then return false end
            for _, value in pairs(char.stats) do if type(value) ~= "number" then return false end end
        end
        if char.talents ~= nil then
            if type(char.talents) ~= "table" then return false end
            for _, tabs in pairs(char.talents) do
                if type(tabs) ~= "table" then return false end
                for _, tab in pairs(tabs) do
                    if type(tab) ~= "table" or type(tab.name) ~= "string" or type(tab.points) ~= "number" or type(tab.talents) ~= "table" then return false end
                    for _, talent in pairs(tab.talents) do
                        if type(talent) ~= "table" or type(talent.name) ~= "string" or type(talent.rank) ~= "number" or type(talent.maxRank) ~= "number" or type(talent.tier) ~= "number" then return false end
                    end
                end
            end
        end
        if char.professions ~= nil then
            if type(char.professions) ~= "table" then return false end
            for _, p in pairs(char.professions) do
                if type(p) ~= "table" or type(p.name) ~= "string" or type(p.recipes) ~= "table" then return false end
                for _, field in ipairs({"rank", "maxRank", "seen"}) do if p[field] ~= nil and type(p[field]) ~= "number" then return false end end
                for _, recipe in pairs(p.recipes) do
                    if type(recipe) ~= "table" or type(recipe.name) ~= "string" or type(recipe.reagents) ~= "table" then return false end
                    for _, reagent in pairs(recipe.reagents) do
                        if type(reagent) ~= "table" or type(reagent.name) ~= "string" or type(reagent.count) ~= "number" then return false end
                    end
                end
            end
        end
    end
    for id, info in pairs(data.items) do
        if type(id) ~= "number" or type(info) ~= "table" then return false end
        for _, field in ipairs({"name", "link", "kind", "subtype", "equip"}) do if info[field] ~= nil and type(info[field]) ~= "string" then return false end end
        if info.texture ~= nil and type(info.texture) ~= "string" and type(info.texture) ~= "number" then return false end
        for _, field in ipairs({"level", "quality", "seen"}) do if info[field] ~= nil and type(info[field]) ~= "number" then return false end end
    end
    for key, char in pairs(data.characters) do
        char.imported = sender
        A.EachHolding(char, function(item) item.realm = data.realm end)
        for _, p in pairs(char.professions or {}) do
            for _, recipe in ipairs(p.recipes) do
                recipe.realm = data.realm
                for _, reagent in ipairs(recipe.reagents) do reagent.realm = data.realm end
            end
        end
        A.db.characters["@" .. sender:lower() .. "\031" .. key] = char
    end
    A.db.itemRealms[data.realm] = A.db.itemRealms[data.realm] or {}
    for id, info in pairs(data.items) do
        if not A.db.itemRealms[data.realm][id] then A.db.itemRealms[data.realm][id] = info end
    end
    A.db.imports[sender] = {realm = data.realm, seen = time()}
    A.Changed()
    A.Say(A.Text("Account-Daten empfangen von ", "Account data received from ") .. sender)
    return true
end
A.ImportAccount = import
A.On("CHAT_MSG_ADDON", function(prefix, message, channel, sender)
    if prefix ~= PREFIX or channel ~= "WHISPER" or not A.db or not validName(sender) or type(message) ~= "string" then return end
    local key, now = sender:lower(), GetTime()
    if message == "Q" then
        if pending[key] and pending[key] > now then return end
        pending[key] = now + 120
        A.Say(sender .. A.Text(" fragt deine Charakterdaten an. Freigeben: /ralt accept ", " requests your character data. Approve: /ralt accept ") .. sender)
        return
    end
    local id, count, length = message:match("^B\t([%d%-]+)\t(%d+)\t(%d+)$")
    if id then
        if not requested[key] or now > requested[key] or #id > 40 then return end
        count, length = tonumber(count), tonumber(length)
        if length < 1 or length > LIMIT or count ~= math.ceil(length / 180) then return end
        if incoming and incoming.expires > now then return end
        incoming = {sender = key, id = id, count = count, length = length, chunks = {}, received = 0, expires = now + 3600}
        requested[key] = nil
        return
    end
    local packetID, index, chunk = message:match("^D\t([%d%-]+)\t(%d+)\t(.*)$")
    local t = incoming
    if not packetID or not t or t.sender ~= key or t.id ~= packetID or now > t.expires then return end
    index = tonumber(index)
    if index < 1 or index > t.count or #chunk > 180 then return end
    if not t.chunks[index] then t.chunks[index] = chunk; t.received = t.received + 1 end
    if t.received == t.count then
        local payload = table.concat(t.chunks)
        incoming = nil
        if #payload == t.length then import(payload, sender) end
    end
end)
A.On("CHAT_MSG_SYSTEM", function(message)
    if outgoing and ERR_CHAT_PLAYER_NOT_FOUND_S and message == string.format(ERR_CHAT_PLAYER_NOT_FOUND_S, outgoing.target) then
        outgoing = nil; A.Cancel("share-send")
        A.Say(A.Text("\195\156bertragung beendet: Empf\195\164nger offline.", "Transfer stopped: recipient offline."))
    end
end)
