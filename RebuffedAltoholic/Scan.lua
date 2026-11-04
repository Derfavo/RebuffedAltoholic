local _, A = ...
local bankOpen, mailOpen, auctionOpen, guildOpen = false, false, false, false
local function schedule(key, fn, delay)
    if A.current then A.After("scan:" .. key, delay or .3, fn) end
end
function A.ScanCharacter()
    if not A.current then return end
    local c = A.current
    local class, token = UnitClass("player")
    c.class, c.classToken, c.level = class, token, UnitLevel("player")
    c.race, c.faction = UnitRace("player"), UnitFactionGroup("player")
    c.money, c.xp, c.xpMax, c.rest = GetMoney(), UnitXP("player"), UnitXPMax("player"), GetXPExhaustion() or 0
    c.guild = GetGuildInfo("player")
    c.zone, c.seen = GetRealZoneText(), time()
    c.stats = {health = UnitHealthMax("player"), mana = UnitPowerMax("player"), armor = select(2, UnitArmor("player")) or UnitArmor("player")}
    for i = 1, 5 do c.stats["stat" .. i] = select(2, UnitStat("player", i)) end
    A.Changed()
end
local function scanBags(first, last, includeKeyring)
    local entries, used, capacity = {}, 0, 0
    local function bag(id)
        local slots = GetContainerNumSlots(id) or 0
        capacity = capacity + slots
        for slot = 1, slots do
            local link = GetContainerItemLink(id, slot)
            if link then
                local _, count = GetContainerItemInfo(id, slot)
                local item = A.Item(link, count, slot, id)
                if item then entries[#entries + 1] = item; used = used + 1 end
            end
        end
    end
    for id = first, last do bag(id) end
    if includeKeyring then bag(KEYRING_CONTAINER or -2) end
    return entries, used, capacity
end
function A.ScanBags()
    local entries, used, capacity = scanBags(0, NUM_BAG_SLOTS or 4, true)
    A.current.bagUsed, A.current.bagCapacity = used, capacity
    A.Save("bags", entries)
end
function A.ScanBank()
    if not bankOpen then return end
    local entries, used, capacity = scanBags(5, 11)
    for slot = 1, GetContainerNumSlots(BANK_CONTAINER or -1) or 0 do
        capacity = capacity + 1
        local link = GetContainerItemLink(BANK_CONTAINER or -1, slot)
        if link then
            local _, count = GetContainerItemInfo(BANK_CONTAINER or -1, slot)
            local item = A.Item(link, count, slot, -1)
            if item then entries[#entries + 1] = item; used = used + 1 end
        end
    end
    A.current.bankUsed, A.current.bankCapacity = used, capacity
    A.Save("bank", entries)
end
function A.ScanEquipment()
    local entries, sum, counted, missing = {}, 0, 0, false
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local item = A.Item(link, GetInventoryItemCount("player", slot), slot)
            if item then
                entries[#entries + 1] = item
                local _, _, _, level = GetItemInfo(link)
                if slot ~= 4 and slot ~= 19 then
                    if level then sum = sum + level; counted = counted + 1 else missing = true end
                end
            end
        end
    end
    A.current.itemLevel = not missing and counted > 0 and math.floor(sum / counted + .5) or nil
    A.Save("equipment", entries)
end
function A.ScanMail()
    if not mailOpen then return end
    local items, messages = {}, {}
    local count = GetInboxNumItems()
    for index = 1, count do
        local _, _, sender, subject, money, cod, days = GetInboxHeaderInfo(index)
        messages[#messages + 1] = {name = subject or "", sender = sender, money = money or 0,
            cod = cod or 0, expires = days and time() + days * 86400}
        for slot = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
            local link = GetInboxItemLink(index, slot)
            if link then
                local _, _, amount = GetInboxItem(index, slot)
                local item = A.Item(link, amount, slot, index)
                if item then
                    item.sender, item.expires = sender, messages[#messages].expires
                    items[#items + 1] = item
                end
            end
        end
    end
    A.Save("messages", messages)
    A.Save("mail", items)
end
function A.ScanAuctions(kind)
    if not auctionOpen then return end
    local items = {}
    local count = GetNumAuctionItems(kind)
    for index = 1, count do
        local link = GetAuctionItemLink(kind, index)
        if link then
            local _, _, amount, _, _, _, bid, _, buyout, bidAmount, _, owner = GetAuctionItemInfo(kind, index)
            local item = A.Item(link, amount, index)
            if item then
                item.bid, item.buyout, item.owner = bidAmount or bid, buyout, owner
                item.timeLeft = GetAuctionItemTimeLeft(kind, index)
                items[#items + 1] = item
            end
        end
    end
    A.Save(kind == "owner" and "auctions" or "bids", items)
end
function A.ScanSkills()
    if not GetNumSkillLines then return end
    local skills, seen, collapsed = {}, {}, false
    for i = 1, GetNumSkillLines() do
        local name, header, expanded, rank, _, modifier, maxRank = GetSkillLineInfo(i)
        if header and not expanded then collapsed = true end
        if name and not header then skills[#skills + 1] = {name = name, rank = rank, maxRank = maxRank, modifier = modifier}; seen[name] = true end
    end
    if collapsed then for _, skill in ipairs(A.current.skills or {}) do if not seen[skill.name] then skills[#skills + 1] = skill end end end
    A.Save("skills", skills)
end
function A.ScanCrafts()
    if not GetTradeSkillLine or (IsTradeSkillLinked and IsTradeSkillLinked()) then return end
    local profession, rank, maxRank = GetTradeSkillLine()
    if not profession or profession == "UNKNOWN" then return end
    local recipes = {}
    for index = 1, GetNumTradeSkills() do
        local name, kind, available = GetTradeSkillInfo(index)
        if name and kind ~= "header" then
            local link = GetTradeSkillItemLink(index)
            local recipe = {name = name, kind = kind, available = available, realm = A.realm,
                link = link, id = A.Observe(link), recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(index), reagents = {}}
            for r = 1, GetTradeSkillNumReagents(index) do
                local reagentName, _, amount = GetTradeSkillReagentInfo(index, r)
                local reagentLink = GetTradeSkillReagentItemLink(index, r)
                recipe.reagents[#recipe.reagents + 1] = {name = reagentName, link = reagentLink, id = A.Observe(reagentLink), count = amount, realm = A.realm}
            end
            recipes[#recipes + 1] = recipe
        end
    end
    -- Profession filters can hide recipes. Merge observed recipes instead of
    -- treating a filtered view as proof that a learned recipe was forgotten.
    A.current.professions = A.current.professions or {}
    local old = A.current.professions[profession]
    local byName = {}
    for _, recipe in ipairs(old and old.recipes or {}) do byName[recipe.recipeLink or recipe.name] = recipe end
    for _, recipe in ipairs(recipes) do byName[recipe.recipeLink or recipe.name] = recipe end
    recipes = {}; for _, recipe in pairs(byName) do recipes[#recipes + 1] = recipe end
    table.sort(recipes, function(a,b) return a.name < b.name end)
    A.current.professions[profession] = {name = profession, rank = rank, maxRank = maxRank, recipes = recipes, seen = time()}
    A.current.sources.professions = time()
    A.Changed()
end
function A.ScanLegacyCrafts()
    if not GetCraftDisplaySkillLine or not GetNumCrafts then return end
    local profession, rank, maxRank = GetCraftDisplaySkillLine()
    if not profession then return end
    A.current.professions = A.current.professions or {}
    local byName = {}
    local old = A.current.professions[profession]
    for _, recipe in ipairs(old and old.recipes or {}) do byName[recipe.name] = recipe end
    for index = 1, GetNumCrafts() do
        local name, _, kind, available = GetCraftInfo(index)
        if name and kind ~= "header" then
            local link = GetCraftItemLink(index)
            local recipe = {name = name, kind = kind, available = available, link = link, id = A.Observe(link), reagents = {}, realm = A.realm}
            for r = 1, GetCraftNumReagents(index) do
                local n, _, amount = GetCraftReagentInfo(index, r)
                local reagentLink = GetCraftReagentItemLink(index, r)
                recipe.reagents[#recipe.reagents + 1] = {name = n, count = amount, link = reagentLink, id = A.Observe(reagentLink), realm = A.realm}
            end
            byName[name] = recipe
        end
    end
    local recipes = {}; for _, r in pairs(byName) do recipes[#recipes + 1] = r end
    table.sort(recipes, function(a,b) return a.name < b.name end)
    A.current.professions[profession] = {name = profession, rank = rank, maxRank = maxRank, recipes = recipes, seen = time()}
    A.current.sources.professions = time(); A.Changed()
end
function A.ScanQuests()
    local entries, seen, collapsed = {}, {}, false
    for i = 1, GetNumQuestLogEntries() do
        local title, level, tag, group, header, hidden, complete, daily, id = GetQuestLogTitle(i)
        if header and hidden then collapsed = true end
        if title and not header then
            entries[#entries + 1] = {name = title, level = level, tag = tag, group = group, complete = complete, daily = daily, id = id}
            seen[id or title] = true
        end
    end
    if collapsed then for _, quest in ipairs(A.current.quests or {}) do if not seen[quest.id or quest.name] then entries[#entries + 1] = quest end end end
    A.Save("quests", entries)
end
function A.ScanReputations()
    local entries = {}
    -- Never expand/collapse the user's reputation categories behind their back.
    local previous = {}; for _, r in ipairs(A.current.reputations or {}) do previous[r.name] = r end
    for i = 1, GetNumFactions() do
        local name, _, standing, bottom, top, value, _, _, header = GetFactionInfo(i)
        if name and not header then previous[name] = {name = name, standing = standing, value = value, bottom = bottom, top = top} end
    end
    for _, r in pairs(previous) do entries[#entries + 1] = r end
    table.sort(entries, function(a,b) return a.name < b.name end)
    A.Save("reputations", entries)
end
function A.ScanTalents()
    if not GetNumTalentGroups then return end
    local groups = {}
    local active = GetActiveTalentGroup()
    for group = 1, GetNumTalentGroups() do
        local tabs = {}
        for tab = 1, GetNumTalentTabs() do
            local name, _, points = GetTalentTabInfo(tab, false, false, group)
            local talents = {}
            for i = 1, GetNumTalents(tab) do
                local n, icon, tier, column, rank, maxRank = GetTalentInfo(tab, i, false, false, group)
                if n then talents[#talents + 1] = {name = n, icon = icon, tier = tier, column = column, rank = rank, maxRank = maxRank} end
            end
            tabs[#tabs + 1] = {name = name, points = points, talents = talents}
        end
        groups[group] = tabs
    end
    A.current.activeTalents = active
    A.Save("talents", groups)
end
function A.ScanSpells()
    local entries = {}
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, count = GetSpellTabInfo(tab)
        for slot = offset + 1, offset + count do
            local name, rank = GetSpellName(slot, BOOKTYPE_SPELL or "spell")
            if name then entries[#entries + 1] = {name = name, rank = rank, link = GetSpellLink(slot, BOOKTYPE_SPELL or "spell")} end
        end
    end
    A.Save("spells", entries)
end
function A.ScanCompanions()
    if not GetNumCompanions then return end
    local entries = {}
    for _, kind in ipairs({"MOUNT", "CRITTER"}) do
        for index = 1, GetNumCompanions(kind) do
            local id, name, spellID, icon = GetCompanionInfo(kind, index)
            entries[#entries + 1] = {id = id, name = name, spellID = spellID, icon = icon, kind = kind}
        end
    end
    A.Save("companions", entries)
end
function A.ScanCurrencies()
    if not GetCurrencyListSize then return end
    local byName = {}; for _, r in ipairs(A.current.currencies or {}) do byName[r.name] = r end
    for i = 1, GetCurrencyListSize() do
        local name, header, _, _, _, count, icon = GetCurrencyListInfo(i)
        if name and not header then byName[name] = {name = name, count = count, icon = icon} end
    end
    local entries = {}; for _, r in pairs(byName) do entries[#entries + 1] = r end
    A.Save("currencies", entries)
end
function A.ScanLockouts()
    if not GetNumSavedInstances then return end
    local entries = {}
    for i = 1, GetNumSavedInstances() do
        local name, id, reset, difficulty, locked, extended, _, raid, players = GetSavedInstanceInfo(i)
        if name and (locked or extended) then entries[#entries + 1] = {name = name, id = id, expires = time() + reset, difficulty = difficulty, raid = raid, players = players} end
    end
    A.Save("lockouts", entries)
end
function A.ScanAchievements()
    if not GetCategoryList then return end
    local categories, index = GetCategoryList(), 1
    local entries = {}
    local function batch()
        if not A.current then return end
        local remaining = 100
        while categories[index] and remaining > 0 do
            local category = categories[index]
            local count = GetCategoryNumAchievements(category)
            local start = A.achievementCursor or 1
            for i = start, math.min(count, start + remaining - 1) do
                local id, name, points, completed, month, day, year, _, _, icon = GetAchievementInfo(category, i)
                if id then entries[#entries + 1] = {id = id, name = name, points = points, completed = completed, month = month, day = day, year = year, icon = icon} end
            end
            local consumed = math.min(remaining, math.max(0, count - start + 1))
            remaining = remaining - consumed
            if start + consumed > count then index = index + 1; A.achievementCursor = nil
            else A.achievementCursor = start + consumed end
        end
        if categories[index] then A.After("achievements", .1, batch)
        else A.current.achievementPoints = GetTotalAchievementPoints(); A.Save("achievements", entries) end
    end
    A.achievementCursor = nil
    batch()
end
function A.ScanGuildBank()
    if not guildOpen then return end
    local guild = GetGuildInfo("player")
    if not guild then return end
    local key = A.realm .. "\031" .. guild
    local record = A.db.guilds[key] or {name = guild, realm = A.realm, tabs = {}}
    A.db.guilds[key] = record
    record.money, record.seen = GetGuildBankMoney(), time()
    local tab = GetCurrentGuildBankTab()
    local name, icon, viewable = GetGuildBankTabInfo(tab)
    if not viewable then return end
    local items = {}
    for slot = 1, 98 do
        local link = GetGuildBankItemLink(tab, slot)
        if link then
            local _, amount = GetGuildBankItemInfo(tab, slot)
            local item = A.Item(link, amount, slot, tab)
            if item then items[#items + 1] = item end
        end
    end
    record.tabs[tab] = {name = name, icon = icon, items = items, seen = time()}
    A.Changed()
end
function A.ScanLogin()
    A.ScanCharacter(); A.ScanBags(); A.ScanEquipment()
    local scans = {A.ScanSkills, A.ScanQuests, A.ScanReputations, A.ScanTalents, A.ScanSpells, A.ScanCompanions, A.ScanCurrencies, A.ScanLockouts}
    for i, fn in ipairs(scans) do A.After("login:" .. i, i * .2, fn) end
    A.After("login:achievements", 2, A.ScanAchievements)
    A.After("mailwarning", 4, function()
        local n = 0
        for _, c in pairs(A.db.characters) do
            for _, m in ipairs(c.messages or {}) do if m.expires and m.expires > time() and m.expires - time() < 3 * 86400 then n = n + 1 end end
        end
        if n > 0 then A.Say(A.Text("Post l\195\164uft bald ab: ", "Mail expiring soon: ") .. n) end
    end)
end
for _, event in ipairs({"PLAYER_MONEY", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "PLAYER_GUILD_UPDATE"}) do
    A.On(event, function() schedule("character", A.ScanCharacter) end)
end
A.On("TIME_PLAYED_MSG", function(total, level) if A.current then A.current.played, A.current.playedLevel = total, level; A.Changed() end end)
A.On("BAG_UPDATE", function() schedule("bags", A.ScanBags); if bankOpen then schedule("bank", A.ScanBank) end end)
A.On("PLAYER_EQUIPMENT_CHANGED", function() schedule("equipment", A.ScanEquipment) end)
A.On("UNIT_INVENTORY_CHANGED", function(unit) if unit == "player" then schedule("equipment", A.ScanEquipment) end end)
A.On("BANKFRAME_OPENED", function() bankOpen = true; schedule("bank", A.ScanBank) end)
A.On("BANKFRAME_CLOSED", function() bankOpen = false end)
A.On("PLAYERBANKSLOTS_CHANGED", function() if bankOpen then schedule("bank", A.ScanBank) end end)
A.On("MAIL_SHOW", function() mailOpen = true; schedule("mail", A.ScanMail) end)
A.On("MAIL_INBOX_UPDATE", function() if mailOpen then schedule("mail", A.ScanMail) end end)
A.On("MAIL_CLOSED", function() mailOpen = false end)
A.On("AUCTION_HOUSE_SHOW", function() auctionOpen = true end)
A.On("AUCTION_HOUSE_CLOSED", function() auctionOpen = false end)
A.On("AUCTION_OWNED_LIST_UPDATE", function() schedule("auctions", function() A.ScanAuctions("owner") end) end)
A.On("AUCTION_BIDDER_LIST_UPDATE", function() schedule("bids", function() A.ScanAuctions("bidder") end) end)
A.On("SKILL_LINES_CHANGED", function() schedule("skills", A.ScanSkills) end)
A.On("TRADE_SKILL_SHOW", function() schedule("crafts", A.ScanCrafts) end)
A.On("TRADE_SKILL_UPDATE", function() schedule("crafts", A.ScanCrafts) end)
A.On("CRAFT_SHOW", function() schedule("legacycrafts", A.ScanLegacyCrafts) end)
A.On("CRAFT_UPDATE", function() schedule("legacycrafts", A.ScanLegacyCrafts) end)
A.On("QUEST_LOG_UPDATE", function() schedule("quests", A.ScanQuests) end)
A.On("UPDATE_FACTION", function() schedule("reputations", A.ScanReputations) end)
for _, e in ipairs({"PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED"}) do A.On(e, function() schedule("talents", A.ScanTalents) end) end
A.On("SPELLS_CHANGED", function() schedule("spells", A.ScanSpells) end)
A.On("COMPANION_LEARNED", function() schedule("companions", A.ScanCompanions) end)
A.On("COMPANION_UPDATE", function() schedule("companions", A.ScanCompanions) end)
A.On("CURRENCY_DISPLAY_UPDATE", function() schedule("currencies", A.ScanCurrencies) end)
A.On("UPDATE_INSTANCE_INFO", function() schedule("lockouts", A.ScanLockouts) end)
A.On("ACHIEVEMENT_EARNED", function() schedule("achievements", A.ScanAchievements, 1) end)
A.On("GUILDBANKFRAME_OPENED", function() guildOpen = true; schedule("guildbank", A.ScanGuildBank, .5) end)
A.On("GUILDBANKFRAME_CLOSED", function() guildOpen = false end)
A.On("GUILDBANKBAGSLOTS_CHANGED", function() schedule("guildbank", A.ScanGuildBank) end)
A.On("GUILDBANK_UPDATE_MONEY", function() if guildOpen then schedule("guildbank", A.ScanGuildBank) end end)
A.On("MERCHANT_SHOW", function()
    if not A.db or not GetMerchantNumItems then return end
    for i = 1, GetMerchantNumItems() do A.Observe(GetMerchantItemLink(i)) end
end)
A.On("LOOT_OPENED", function()
    if not A.db or not GetNumLootItems then return end
    for i = 1, GetNumLootItems() do A.Observe(GetLootSlotLink(i)) end
end)
A.On("AUCTION_ITEM_LIST_UPDATE", function()
    if not A.db or not auctionOpen then return end
    for i = 1, GetNumAuctionItems("list") do A.Observe(GetAuctionItemLink("list", i)) end
end)
A.On("CHAT_MSG_LOOT", function(message)
    if not A.db or type(message) ~= "string" then return end
    for link in message:gmatch("|c%x+|Hitem:[^|]+|h%[[^%]]*%]|h|r") do A.Observe(link) end
end)
