local _, A = ...
local queue, attempts, cooldown, running = {}, {}, {}, false
local tooltip
local function resolved(id)
    A.Changed()
    for _, item in ipairs(A.current and A.current.equipment or {}) do
        if item.id == id and A.ScanEquipment then A.After("scan:equipment", .3, A.ScanEquipment); break end
    end
end
function A.ItemID(link)
    if type(link) == "number" then return link > 0 and link or nil end
    if type(link) ~= "string" then return end
    return tonumber(link:match("item:(%d+)"))
end
local function read(link)
    local n, full, quality, level, required, kind, subtype, stack, equip, texture, price = GetItemInfo(link)
    if not n then return end
    return {name = n, link = full or link, quality = quality, level = level, required = required,
        kind = kind, subtype = subtype, stack = stack, equip = equip, texture = texture, price = price}
end
local function pump()
    running = false
    if not A.db then return end
    local now = GetTime()
    for id, link in pairs(queue) do
        local data = read(link)
        if data then
            data.seen = A.items[id] and A.items[id].seen or time()
            A.items[id] = data
            queue[id], attempts[id] = nil, nil
            resolved(id)
        else
            attempts[id] = (attempts[id] or 0) + 1
            if attempts[id] <= 3 then
                -- Only request a real observed link. Never guess or enumerate IDs.
                if not tooltip then tooltip = CreateFrame("GameTooltip", "RebuffedAltoholicItemQuery", UIParent, "GameTooltipTemplate") end
                tooltip:SetOwner(UIParent, "ANCHOR_NONE")
                pcall(tooltip.SetHyperlink, tooltip, link)
                tooltip:Hide()
            else
                queue[id], attempts[id], cooldown[id] = nil, nil, now + 60
            end
        end
        break -- One cache request per tick, even when many new items arrive.
    end
    if next(queue) then running = true; A.After("items", .5, pump) end
end
function A.Observe(link)
    local id = A.ItemID(link)
    if not id or not A.db then return id end
    local entry = A.items[id]
    if not entry then
        entry = {link = link, seen = time()}
        A.items[id] = entry
    end
    -- Keep the exact link on each holding; this ID cache is only for discovery.
    local data = not entry.name and read(link)
    if data then data.seen = entry.seen; A.items[id] = data; entry = data end
    if not entry.name and not queue[id] and (cooldown[id] or 0) <= GetTime() then queue[id] = link end
    if next(queue) and not running then running = true; A.After("items", .5, pump) end
    return id
end
function A.Item(link, count, slot, bag)
    local id = A.Observe(link)
    if not id then return end
    return {id = id, link = link, count = tonumber(count) or 1, slot = slot, bag = bag, realm = A.realm}
end
function A.ItemInfo(item)
    local cache = item.realm and A.db.itemRealms[item.realm] or A.items
    return cache and cache[item.id]
end
function A.ItemName(item)
    local cached = item.id and A.ItemInfo(item)
    return item.name or (item.link and item.link:match("%[(.-)%]")) or (cached and cached.name)
        or ("Item #" .. tostring(item.id or "?"))
end
function A.EachHolding(char, callback)
    for _, source in ipairs({"bags", "bank", "equipment", "mail", "auctions", "bids"}) do
        for _, item in ipairs(char[source] or {}) do if item.id then callback(item, source) end end
    end
end
function A.Ownership()
    if A.ownership then return A.ownership end
    local result = {}
    for key, char in pairs(A.db.characters) do
        A.EachHolding(char, function(item, source)
            local entry = result[item.id] or {}; result[item.id] = entry
            entry[key] = entry[key] or {total = 0, sources = {}}
            entry[key].total = entry[key].total + item.count
            entry[key].sources[source] = (entry[key].sources[source] or 0) + item.count
        end)
    end
    A.ownership = result
    return result
end
local function enhance(tip)
    if not A.db or tip.rebuffedAltoholicBusy then return end
    local _, link = tip:GetItem()
    if not link then return end
    local id = A.Observe(link)
    if not id or tip.rebuffedAltoholicItem == link then return end
    tip.rebuffedAltoholicItem = link
    tip.rebuffedAltoholicBusy = true
    local holdings = A.Ownership()[id]
    local lines = 0
    for _, entry in ipairs(A.Characters(false)) do
        local h = holdings and holdings[entry.key]
        if h then
            if lines == 0 then tip:AddLine("RebuffedAltoholic", .34, .78, 1) end
            local parts = {}
            for _, source in ipairs({"bags", "bank", "equipment", "mail", "auctions", "bids"}) do
                if h.sources[source] then parts[#parts + 1] = (A.SourceLabel and A.SourceLabel(source) or source) .. " " .. h.sources[source] end
            end
            tip:AddDoubleLine(entry.char.name .. ": " .. h.total, table.concat(parts, ", "), 1, 1, 1, .7, .7, .7)
            lines = lines + 1
            if lines >= 12 then break end
        end
    end
    tip.rebuffedAltoholicBusy = nil
    -- Do not call Show/SetHyperlink here: Auctionator may rebuild the same tooltip.
end
A.On("PLAYER_LOGIN", function()
    for _, tip in ipairs({GameTooltip, ItemRefTooltip}) do
        tip:HookScript("OnTooltipSetItem", enhance)
        tip:HookScript("OnTooltipCleared", function(self) self.rebuffedAltoholicItem = nil end)
    end
end)
A.On("GET_ITEM_INFO_RECEIVED", function(id, success)
    if not A.db then return end
    if queue[id] then
        local entry = read(queue[id])
        if entry then
            entry.seen = A.items[id].seen
            A.items[id] = entry; queue[id], attempts[id] = nil, nil
            resolved(id)
        end
    end
end)
