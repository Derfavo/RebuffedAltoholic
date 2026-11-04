local _, A = ...
local T = A.Text
local ROWS, HEIGHT = 15, 27
local rows, navButtons, tabButtons = {}, {}, {}
local list, offset, section, view = {}, 0, "summary", "characters"
local query, allRealms, qualityFilter = "", false, nil
local upgradeFilter
local title, subtitle, status, totalLabel, charButton, searchBox, allButton, qualityButton, scroll
local labels = {
    characters = {"Charaktere", "Characters"}, bags = {"Taschen", "Bags"}, bank = {"Bank", "Bank"},
    equipment = {"Ausr\195\188stung", "Equipment"}, mail = {"Post: Gegenst\195\164nde", "Mail: items"}, messages = {"Postfach", "Mailbox"},
    auctions = {"Auktionen", "Auctions"}, bids = {"Gebote", "Bids"}, skills = {"Fertigkeiten", "Skills"},
    professions = {"Berufe & Rezepte", "Professions & recipes"}, quests = {"Quests", "Quests"}, reputations = {"Ruf", "Reputations"},
    talents = {"Talente", "Talents"}, spells = {"Zauber", "Spells"}, companions = {"Reittiere & Begleiter", "Mounts & companions"},
    currencies = {"Abzeichen", "Currencies"}, achievements = {"Erfolge", "Achievements"}, lockouts = {"Raidsperren", "Raid lockouts"},
    stats = {"Werte", "Statistics"}, activity = {"Aktivit\195\164t", "Activity"}, bagUsage = {"Taschenbelegung", "Bag usage"},
    money = {"Gold & Erfahrung", "Gold & experience"}, compare = {"Ausr\195\188stungsvergleich", "Compare equipment"},
    calendar = {"Termine", "Calendar"}, known = {"Bekannte Items", "Known items"}, holdings = {"Gegenst\195\164nde", "Items"},
    recipes = {"Rezepte suchen", "Find recipes"}, guilds = {"Gildenbank", "Guild bank"}, sharing = {"Account-Freigabe", "Account sharing"},
}
function A.SourceLabel(key)
    local l = labels[key]
    return l and T(l[1], l[2]) or key
end
local function nameOf(c)
    return (c.name or "?") .. (c.imported and (" [" .. c.imported .. "]") or "")
        .. (allRealms and (" - " .. (c.realm or "?")) or "")
end
local function add(left, middle, right, data)
    list[#list + 1] = {left = tostring(left or ""), middle = tostring(middle or ""), right = tostring(right or ""), data = data}
end
local function itemRow(item, middle, right, extra)
    local name = A.ItemName(item)
    local cache = A.ItemInfo(item)
    local texture = item.icon or (cache and cache.texture)
    if texture then name = "|T" .. texture .. ":18|t " .. name end
    local color = cache and cache.quality and ITEM_QUALITY_COLORS[cache.quality]
    if color then name = color.hex .. name .. "|r" end
    add(name, middle or ("x" .. (item.count or 1)), right or (cache and cache.level and "iLvl " .. cache.level or ""),
        {link = item.link, item = item, extra = extra})
end
local function expiration(stamp)
    if not stamp then return "" end
    local remaining = stamp - time()
    if remaining <= 0 then return T("Abgelaufen", "Expired") end
    return math.floor(remaining / 86400) .. "d " .. math.floor(remaining / 3600) % 24 .. "h"
end
local function matches(text) return query == "" or tostring(text or ""):lower():find(query, 1, true) ~= nil end
local function itemMatches(item)
    local info = A.ItemInfo(item) or {}
    if upgradeFilter and (info.equip ~= upgradeFilter.equip or not info.level or info.level <= upgradeFilter.level) then return false end
    return (not qualityFilter or info.quality == qualityFilter)
        and (matches(A.ItemName(item)) or matches(item.id) or (item.link and matches(item.link:match("item:[^|]+"))))
end
local function equipment(char)
    local bySlot = {}
    for _, item in ipairs(char.equipment or {}) do bySlot[item.slot] = item end
    return bySlot
end
local function sourceNote(c, key)
    return T("Stand: ", "Recorded: ") .. A.Age(c.sources and c.sources[key])
end
local function buildSummary()
    local characters, total, levels = A.Characters(allRealms), 0, 0
    for _, entry in ipairs(characters) do
        local c = entry.char
        total = total + (c.money or 0); levels = levels + (c.level or 0)
        if view == "characters" then
            add(nameOf(c), (c.level or "?") .. " " .. (c.class or "") .. "  " .. (c.race or ""),
                A.Money(c.money) .. "  |  " .. A.Age(c.seen), {character = entry.key})
        elseif view == "bagUsage" then
            add(nameOf(c), (c.bagUsed or 0) .. "/" .. (c.bagCapacity or "?") .. " " .. T("Taschen", "bags"),
                (c.bankUsed or "?") .. "/" .. (c.bankCapacity or "?") .. " " .. T("Bank", "bank"), {character = entry.key})
        elseif view == "activity" then
            add(nameOf(c), T("Post ", "Mail ") .. #(c.messages or {}) .. " | " .. T("Auktionen ", "Auctions ") .. #(c.auctions or {}),
                T("Zuletzt: ", "Last seen: ") .. A.Age(c.seen), {character = entry.key})
        elseif view == "money" then
            add(nameOf(c), A.Money(c.money), "XP " .. (c.xp or 0) .. "/" .. (c.xpMax or 0) .. " | Rest " .. (c.rest or 0), {character = entry.key})
        elseif view == "skills" then
            for _, skill in ipairs(c.skills or {}) do add(nameOf(c), skill.name, skill.rank .. "/" .. skill.maxRank, {character = entry.key}) end
        elseif view == "compare" then
            local selected = equipment(A.CurrentCharacter())
            for _, item in ipairs(c.equipment or {}) do
                local other = selected[item.slot]
                local info, otherInfo = A.ItemInfo(item), other and A.ItemInfo(other)
                local delta = info and info.level and otherInfo and otherInfo.level and info.level - otherInfo.level
                itemRow(item, nameOf(c) .. " / " .. T("Platz ", "Slot ") .. item.slot,
                    delta and string.format("%+d iLvl", delta) or "", T("Vergleich zum ausgew\195\164hlten Charakter", "Compared with the selected character"))
            end
        elseif view == "calendar" then
            for _, m in ipairs(c.messages or {}) do
                if m.expires and m.expires > time() then add(nameOf(c), T("Post: ", "Mail: ") .. m.name, expiration(m.expires)) end
            end
            for _, lockout in ipairs(c.lockouts or {}) do
                if lockout.expires > time() then add(nameOf(c), lockout.name, expiration(lockout.expires)) end
            end
        end
    end
    totalLabel:SetText(#characters .. T(" Charaktere | ", " characters | ") .. A.Money(total))
end
local function buildCharacter()
    local c = A.CurrentCharacter()
    if not c then return end
    if view == "equipment" or view == "bags" or view == "bank" or view == "mail" or view == "auctions" or view == "bids" then
        for _, item in ipairs(c[view] or {}) do
            local where = item.bag and (T("Beh\195\164lter ", "Container ") .. item.bag .. ":" .. (item.slot or "?"))
                or (T("Platz ", "Slot ") .. (item.slot or "?"))
            local right = item.expires and expiration(item.expires) or item.buyout and A.Money(item.buyout)
            itemRow(item, "x" .. item.count .. "  " .. where, right)
        end
    elseif view == "messages" then
        for _, m in ipairs(c.messages or {}) do add(m.name, m.sender, expiration(m.expires) .. "  " .. A.Money(m.money)) end
    elseif view == "professions" then
        local professions = {}; for _, p in pairs(c.professions or {}) do professions[#professions + 1] = p end
        table.sort(professions, function(a,b) return a.name < b.name end)
        for _, p in ipairs(professions) do
            add("|cffffd100" .. p.name .. "|r", (p.rank or "?") .. "/" .. (p.maxRank or "?"), A.Age(p.seen))
            for _, r in ipairs(p.recipes) do
                local parts = {}; for _, reagent in ipairs(r.reagents) do parts[#parts + 1] = (reagent.count or 0) .. " " .. A.ItemName(reagent) end
                if r.id then itemRow(r, p.name, r.kind, table.concat(parts, ", "))
                else add(r.name, p.name, r.kind, {link = r.recipeLink, extra = table.concat(parts, ", ")}) end
            end
        end
    elseif view == "quests" then
        for _, q in ipairs(c.quests or {}) do add(q.name, "Lv " .. (q.level or "?"), q.complete == 1 and T("Fertig", "Complete") or q.daily and T("T\195\164glich", "Daily") or q.tag) end
    elseif view == "reputations" then
        for _, r in ipairs(c.reputations or {}) do
            local standing = _G["FACTION_STANDING_LABEL" .. (r.standing or 4)] or r.standing
            add(r.name, standing, (r.value - r.bottom) .. "/" .. (r.top - r.bottom))
        end
    elseif view == "skills" then
        for _, skill in ipairs(c.skills or {}) do add(skill.name, skill.rank .. "/" .. skill.maxRank, skill.modifier or "") end
    elseif view == "talents" then
        for group, tabs in ipairs(c.talents or {}) do
            add("|cffffd100" .. T("Skillung ", "Talent group ") .. group .. "|r", group == c.activeTalents and T("Aktiv", "Active") or "")
            for _, tab in ipairs(tabs) do
                add(tab.name, tab.points or 0)
                for _, talent in ipairs(tab.talents) do
                    if talent.rank > 0 then add("   " .. talent.name, talent.rank .. "/" .. talent.maxRank, T("Reihe ", "Tier ") .. talent.tier) end
                end
            end
        end
    elseif view == "spells" then
        for _, spell in ipairs(c.spells or {}) do add(spell.name, spell.rank, "", {link = spell.link}) end
    elseif view == "companions" then
        for _, pet in ipairs(c.companions or {}) do
            add(pet.name, pet.kind == "MOUNT" and T("Reittier", "Mount") or T("Begleiter", "Companion"), "", {link = pet.spellID and "spell:" .. pet.spellID})
        end
    elseif view == "currencies" then
        for _, currency in ipairs(c.currencies or {}) do add(currency.name, currency.count or 0) end
    elseif view == "achievements" then
        for _, achievement in ipairs(c.achievements or {}) do
            add(achievement.name, (achievement.points or 0) .. T(" Punkte", " points"), achievement.completed and T("Erreicht", "Complete") or T("Offen", "Incomplete"))
        end
    elseif view == "lockouts" then
        for _, lockout in ipairs(c.lockouts or {}) do add(lockout.name, (lockout.players or "?") .. " | " .. (lockout.difficulty or "?"), expiration(lockout.expires)) end
    elseif view == "stats" then
        local statNames = {"STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT"}
        for i, key in ipairs(statNames) do add(_G[key] or key, c.stats and c.stats["stat" .. i] or "?") end
        for _, key in ipairs({"health", "mana", "armor"}) do add(key, c.stats and c.stats[key] or "?") end
        add(T("Spielzeit", "Time played"), c.played and math.floor(c.played / 3600) .. "h" or T("Nutze /played zum Erfassen", "Use /played to record"))
        add("iLvl", c.itemLevel or "?")
        add(T("Erfolgspunkte", "Achievement points"), c.achievementPoints or "?")
    end
    totalLabel:SetText(nameOf(c) .. " | " .. sourceNote(c, view))
end
local function buildSearch()
    local total = 0
    if view == "known" then
        local items = {}
        for realm, catalog in pairs(A.db.itemRealms) do
            if allRealms or realm == A.realm then
                for id, info in pairs(catalog) do
                    local item = {id = id, link = info.link, realm = realm}
                    if itemMatches(item) then items[#items + 1] = item end
                end
            end
        end
        table.sort(items, function(a,b) return A.ItemName(a) < A.ItemName(b) end)
        for _, item in ipairs(items) do itemRow(item, "#" .. item.id); total = total + 1 end
    else
        for _, entry in ipairs(A.Characters(allRealms)) do
            local c = entry.char
            if view == "recipes" then
                for _, p in pairs(c.professions or {}) do
                    for _, recipe in ipairs(p.recipes) do
                        if matches(recipe.name) or (recipe.id and matches(recipe.id)) then
                            if recipe.id then itemRow(recipe, nameOf(c), p.name)
                            else add(recipe.name, nameOf(c), p.name, {link = recipe.recipeLink}) end
                            total = total + 1
                        end
                    end
                end
            else
                A.EachHolding(c, function(item, source)
                    if itemMatches(item) then
                        itemRow(item, nameOf(c), A.SourceLabel(source) .. " x" .. item.count)
                        total = total + item.count
                    end
                end)
            end
        end
        if view == "holdings" then
            for _, g in pairs(A.db.guilds) do
                if allRealms or g.realm == A.realm then
                    for _, tab in pairs(g.tabs) do
                        for _, item in ipairs(tab.items) do
                            if itemMatches(item) then itemRow(item, g.name, (tab.name or "") .. " x" .. item.count); total = total + item.count end
                        end
                    end
                end
            end
        end
    end
    totalLabel:SetText(total .. T(" Treffer / Einheiten", " matches / units"))
end
local function buildGuilds()
    local guilds = {}; for _, g in pairs(A.db.guilds) do if allRealms or g.realm == A.realm then guilds[#guilds + 1] = g end end
    table.sort(guilds, function(a,b) return a.name < b.name end)
    for _, g in ipairs(guilds) do
        add("|cffffd100" .. g.name .. "|r", g.realm, A.Money(g.money))
        for tabID = 1, 6 do
            local tab = g.tabs[tabID]
            if tab then
                add("   " .. tabID .. " - " .. (tab.name or ""), T("Stand: ", "Recorded: ") .. A.Age(tab.seen))
                for _, item in ipairs(tab.items) do itemRow(item, g.name .. " / " .. tabID, "x" .. item.count) end
            end
        end
    end
    totalLabel:SetText(T("Besuchte Gildenbankf\195\164cher; gespeicherter Stand", "Visited guild bank tabs; saved snapshots"))
end
local function buildSharing()
    add(T("Anderen Account anfragen", "Request another account"), T("/ralt request Name", "/ralt request Name"))
    add(T("Freigabe best\195\164tigen", "Approve a request"), T("/ralt accept Name", "/ralt accept Name"))
    add(T("Empfangene Accounts", "Received accounts"), T("Im Charaktermen\195\188 ausw\195\164hlbar", "Select from the character menu"))
    for sender, record in pairs(A.db.imports) do add(sender, record.realm, A.Age(record.seen)) end
    totalLabel:SetText(T("Daten werden nur nach manueller Anfrage und Best\195\164tigung geteilt.", "Data is shared only after a manual request and approval."))
end
function A.RenderRows()
    offset = math.max(0, math.min(offset, math.max(0, #list - ROWS)))
    for i, row in ipairs(rows) do
        local record = list[offset + i]
        row.record = record
        if record then
            row.left:SetText(record.left); row.middle:SetText(record.middle); row.right:SetText(record.right)
            row:Show()
        else row:Hide() end
    end
    status:SetText((#list > 0 and (offset + 1) or 0) .. "-" .. math.min(offset + ROWS, #list) .. "/" .. #list)
    if scroll then scroll:SetMinMaxValues(0, math.max(0, #list - ROWS)); scroll:SetValue(offset) end
end
function A.Refresh()
    if not A.window or not A.db or not A.window:IsShown() then return end
    list = {}
    if section == "summary" then
        if view == "sharing" then buildSharing() else buildSummary() end
    elseif section == "characters" then buildCharacter()
    elseif section == "search" then buildSearch()
    else buildGuilds() end
    -- Search box also filters detail tables without modifying their saved data.
    if section ~= "search" and query ~= "" then
        local filtered = {}
        for _, record in ipairs(list) do
            if matches(record.left) or matches(record.middle) or matches(record.right) then filtered[#filtered + 1] = record end
        end
        list = filtered
    end
    title:SetText(A.SourceLabel(view))
    local selected = A.CurrentCharacter()
    charButton:SetText(selected and nameOf(selected) or "-")
    subtitle:SetText(upgradeFilter
        and T("Bekannte Items f\195\188r diesen Platz mit h\195\182herem Itemlevel; keine Skillungsbewertung.", "Known items for this slot with higher item level; no specialization scoring.")
        or T("Zuletzt gespeicherte Daten | Item-Hover f\195\188r Details", "Saved snapshots | Hover an item for details"))
    A.RenderRows()
end
local navigation = {
    summary = {"characters", "bagUsage", "activity", "money", "skills", "compare", "calendar", "sharing"},
    characters = {"equipment", "bags", "bank", "mail", "messages", "auctions", "bids", "professions", "skills", "quests", "reputations", "talents", "spells", "companions", "currencies", "achievements", "lockouts", "stats"},
    search = {"holdings", "recipes", "known"}, guild = {"guilds"},
}
local function switchSection(key)
    section, view, offset = key, navigation[key][1], 0
    upgradeFilter = nil
    for i, b in ipairs(navButtons) do
        b.key = navigation[key][i]
        if b.key then b:SetText(A.SourceLabel(b.key)); b:Show() else b:Hide() end
    end
    A.Refresh()
end
function A.FindUpgrades(item)
    local info = A.ItemInfo(item)
    if not info or not info.level or not info.equip or info.equip == "" then return end
    switchSection("search")
    view, query, offset = "known", "", 0
    searchBox:SetText("")
    upgradeFilter = {equip = info.equip, level = info.level}
    A.Refresh()
    subtitle:SetText(T("Bekannte Items f\195\188r diesen Platz mit h\195\182herem Itemlevel; keine Skillungsbewertung.", "Known items for this slot with higher item level; no specialization scoring."))
end
local function button(parent, text, width, point, x, y, callback)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22); b:SetPoint(point, parent, point, x, y); b:SetText(text)
    b:SetScript("OnClick", callback)
    return b
end
local function font(parent, object, point, x, y, width)
    local text = parent:CreateFontString(nil, "OVERLAY", object)
    text:SetPoint(point, parent, point, x, y)
    text:SetJustifyH("LEFT")
    if width then text:SetWidth(width) end
    return text
end
local function showRowTooltip(self)
    local r, tip = self.record, GameTooltip
    if not r then return end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    if r.data and r.data.link then
        local ok = pcall(tip.SetHyperlink, tip, r.data.link)
        if not ok then tip:SetText(r.left) end
    else tip:SetText(r.left) end
    if r.data and r.data.extra and r.data.extra ~= "" then tip:AddLine(r.data.extra, 1, 1, 1, true) end
    if section == "characters" and view == "equipment" and r.data and r.data.item then
        tip:AddLine(T("Rechtsklick: Items mit h\195\182herem Itemlevel suchen", "Right-click: find items with higher item level"), .34, .78, 1, true)
    end
    if not r.data or not r.data.link then
        if r.middle ~= "" then tip:AddLine(r.middle, 1, 1, 1, true) end
        if r.right ~= "" then tip:AddLine(r.right, .7, .7, .7, true) end
    end
    tip:Show()
end
function A.CreateWindow()
    if A.window then return end
    A.Init()
    local w = CreateFrame("Frame", "RebuffedAltoholicWindow", UIParent)
    A.window = w
    w:SetSize(1000, 620)
    w:SetScale(math.min(1, (UIParent:GetWidth() - 40) / 1000, (UIParent:GetHeight() - 40) / 620))
    w:SetPoint("CENTER"); w:SetFrameStrata("DIALOG"); w:SetClampedToScreen(true)
    w:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 32, edgeSize = 16, insets = {left = 4, right = 4, top = 4, bottom = 4}})
    w:EnableMouse(true); w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        A.db.options.position = {point = point, relative = relative, x = x, y = y}
    end)
    local position = A.db.options.position
    if position then w:ClearAllPoints(); w:SetPoint(position.point, UIParent, position.relative, position.x, position.y) end
    font(w, "GameFontNormalLarge", "TOPLEFT", 18, -16):SetText("RebuffedAltoholic")
    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() w:Hide() end)
    UISpecialFrames[#UISpecialFrames + 1] = "RebuffedAltoholicWindow"
    local tabNames = {{"summary", T("\195\156bersicht", "Summary")}, {"characters", T("Charaktere", "Characters")}, {"guild", T("Gildenbank", "Guild bank")}, {"search", T("Suche", "Search")}}
    for i, tab in ipairs(tabNames) do
        local key = tab[1]
        tabButtons[i] = button(w, tab[2], 130, "TOPLEFT", 16 + (i - 1) * 134, -47, function() switchSection(key) end)
    end
    charButton = button(w, "", 235, "TOPRIGHT", -18, -47, function(self)
        local menu = {{text = T("Charakter ausw\195\164hlen", "Select character"), isTitle = true, notCheckable = true}}
        for _, entry in ipairs(A.Characters(allRealms)) do
            local key = entry.key
            menu[#menu + 1] = {text = nameOf(entry.char), checked = key == (A.selected or A.key), func = function() A.selected = key; offset = 0; A.Refresh() end}
        end
        if not A.charMenu then A.charMenu = CreateFrame("Frame", "RebuffedAltoholicCharacterMenu", UIParent, "UIDropDownMenuTemplate") end
        EasyMenu(menu, A.charMenu, self, 0, 0, "MENU")
    end)
    searchBox = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
    searchBox:SetSize(250, 22); searchBox:SetPoint("TOPLEFT", 199, -82); searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function(self)
        query = self:GetText():lower(); offset = 0
        A.After("search", .15, A.Refresh)
    end)
    font(w, "GameFontHighlightSmall", "TOPLEFT", 465, -86):SetText(T("Name oder Item-ID", "Name or item ID"))
    allButton = button(w, T("Realm: Aktuell", "Realm: Current"), 145, "TOPRIGHT", -176, -80, function(self)
        allRealms = not allRealms
        self:SetText(allRealms and T("Realm: Alle", "Realm: All") or T("Realm: Aktuell", "Realm: Current"))
        offset = 0; A.Refresh()
    end)
    qualityButton = button(w, T("Qualit\195\164t: Alle", "Quality: All"), 150, "TOPRIGHT", -18, -80, function(self)
        qualityFilter = qualityFilter == nil and 0 or qualityFilter < 7 and qualityFilter + 1 or nil
        self:SetText(qualityFilter and (_G["ITEM_QUALITY" .. qualityFilter .. "_DESC"] or tostring(qualityFilter)) or T("Qualit\195\164t: Alle", "Quality: All"))
        section, view, offset = "search", "holdings", 0
        for i, b in ipairs(navButtons) do b.key = navigation.search[i]; if b.key then b:SetText(A.SourceLabel(b.key)); b:Show() else b:Hide() end end
        A.Refresh()
    end)
    title = font(w, "GameFontNormal", "TOPLEFT", 195, -119, 750)
    subtitle = font(w, "GameFontHighlightSmall", "TOPLEFT", 195, -139, 750)
    for i = 1, 18 do
        local b = button(w, "", 165, "TOPLEFT", 17, -82 - (i - 1) * 27, function(self)
            view, offset, upgradeFilter = self.key, 0, nil; A.Refresh()
        end)
        navButtons[i] = b
    end
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, w)
        row:SetSize(760, HEIGHT); row:SetPoint("TOPLEFT", 195, -165 - (i - 1) * HEIGHT)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.left = font(row, "GameFontHighlightSmall", "LEFT", 4, 0, 315)
        row.middle = font(row, "GameFontHighlightSmall", "LEFT", 326, 0, 225)
        row.right = font(row, "GameFontHighlightSmall", "LEFT", 557, 0, 198)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnEnter", showRowTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self, mouse)
            local data = self.record and self.record.data
            if not data then return end
            if data.character then
                A.selected = data.character; switchSection("characters")
            elseif data.link then
                if mouse == "RightButton" and section == "characters" and view == "equipment" and data.item then A.FindUpgrades(data.item)
                elseif IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink(data.link)
                else SetItemRef(data.link:match("|H(.-)|h") or data.link, data.link, mouse, DEFAULT_CHAT_FRAME) end
            end
        end)
        rows[i] = row
    end
    scroll = CreateFrame("Slider", "RebuffedAltoholicScroll", w, "UIPanelScrollBarTemplate")
    scroll:SetPoint("TOPRIGHT", -25, -182); scroll:SetPoint("BOTTOMRIGHT", -25, 77)
    scroll:SetWidth(16); scroll:SetValueStep(1); scroll:SetMinMaxValues(0, 0)
    scroll:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + .5)
        if value ~= offset then offset = value; A.RenderRows() end
    end)
    w:EnableMouseWheel(true)
    w:SetScript("OnMouseWheel", function(self, delta) offset = offset - delta * 3; A.RenderRows() end)
    totalLabel = font(w, "GameFontNormalSmall", "BOTTOMLEFT", 195, 36, 730)
    status = font(w, "GameFontHighlightSmall", "BOTTOMRIGHT", -35, 15, 110)
    button(w, T("Eigene Daten aktualisieren", "Refresh current character"), 205, "BOTTOMLEFT", 18, 12, function()
        A.ScanLogin(); offset = 0; A.Refresh()
    end)
    font(w, "GameFontDisableSmall", "BOTTOMLEFT", 238, 18, 580):SetText(T("Bank, Post, Berufe und AH zum Erfassen \195\182ffnen.", "Open bank, mail, professions and AH to record their contents."))
    w:SetScript("OnShow", A.Refresh)
    switchSection("summary")
    w:Hide()
end
function A.Toggle()
    A.CreateWindow()
    if A.window:IsShown() then A.window:Hide() else A.window:Show(); A.Refresh() end
end
function A.CreateMinimap()
    if A.minimap then return end
    local b = CreateFrame("Button", "RebuffedAltoholicMinimap", Minimap)
    A.minimap = b
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    local icon = b:CreateTexture(nil, "BACKGROUND"); icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 0)
    local border = b:CreateTexture(nil, "OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local function position()
        local angle = math.rad(A.db.options.minimapAngle or 220)
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
    end
    position()
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function() A.Toggle() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition(); local cx, cy = Minimap:GetCenter(); local scale = Minimap:GetEffectiveScale()
            A.db.options.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
            position()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("RebuffedAltoholic")
        GameTooltip:AddLine(T("Klicken: \195\182ffnen | Ziehen: verschieben", "Click: open | Drag: move"), 1, 1, 1); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
SLASH_REBUFFEDALTOHOLIC1 = "/ralt"
SLASH_REBUFFEDALTOHOLIC2 = "/rebuffedaltoholic"
SlashCmdList.REBUFFEDALTOHOLIC = function(message)
    local command, value = message:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "search" then
        A.CreateWindow(); A.window:Show(); searchBox:SetText(value); switchSection("search")
    elseif command == "request" and A.RequestAccount then A.RequestAccount(value)
    elseif command == "accept" and A.AcceptAccount then A.AcceptAccount(value)
    else A.Toggle() end
end
-- Expose the view model for focused client-independent verification.
function A.ViewRows() return list end
