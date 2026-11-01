-- Observed group loot messages and Vanilla roll events; Lua 5.0 compatible.
ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local GroupEvents = {}
GroupEvents.__index = GroupEvents
ns.GroupEvents = GroupEvents

local getn = table.getn
local GROUP_CHAT = {
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
}
GroupEvents.Events = {
    "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CHAT_MSG_LOOT", "CHAT_MSG_SYSTEM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
}

local function itemKey(link)
    if type(link) ~= "string" then return nil end
    local first, last, id = string.find(link, "item:(%d+)")
    return id
end

local function extractLink(message)
    if type(message) ~= "string" then return nil end
    local first, last, link = string.find(message, "(|c%x%x%x%x%x%x%x%x|Hitem:.-|h.-|h|r)")
    if not first then first, last, link = string.find(message, "(|Hitem:.-|h.-|h)") end
    if not first then return nil end
    local another = string.find(message, "|Hitem:", last + 1, true)
    if another then return nil, "multiple_items" end
    return link
end

local function plainName(name)
    if type(name) ~= "string" then return nil end
    name = string.gsub(name, "|c%x%x%x%x%x%x%x%x", "")
    name = string.gsub(name, "|r", "")
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name == "" then return nil end
    return name
end

local function playerName()
    return UnitName and UnitName("player") or nil
end

-- Blizzard 1.12 templates expand an item hyperlink into several %s/%d
-- arguments. Keep those capture positions, including positional %1$s forms.
local patternCache = {}
local function compileFormat(format)
    if patternCache[format] then return patternCache[format] end
    local parts, positions, position, nextArgument = {"^"}, {}, 1, 1
    while position <= string.len(format) do
        local character = string.sub(format, position, position)
        if character == "%" then
            local tail = string.sub(format, position)
            local first, last, explicit, kind = string.find(tail, "^%%(%d+)%$([sd])")
            local argument
            if first then
                argument = tonumber(explicit)
                position = position + last
            else
                kind = string.sub(format, position + 1, position + 1)
                if kind == "%" then
                    parts[getn(parts) + 1] = "%%"
                    position = position + 2
                elseif kind == "s" or kind == "d" then
                    argument = nextArgument
                    nextArgument = nextArgument + 1
                    position = position + 2
                else return nil end
            end
            if argument then
                positions[getn(positions) + 1] = argument
                parts[getn(parts) + 1] = kind == "d" and "(%d+)" or "(.-)"
            end
        else
            if string.find("^$().[]*+-?", character, 1, true) then character = "%" .. character end
            parts[getn(parts) + 1] = character
            position = position + 1
        end
    end
    parts[getn(parts) + 1] = "$"
    local result = {pattern = table.concat(parts), positions = positions}
    patternCache[format] = result
    return result
end

local function capture(message, format)
    if type(format) ~= "string" then return nil end
    local compiled = compileFormat(format)
    if not compiled then return nil end
    local captures = {string.find(message, compiled.pattern)}
    if not captures[1] then return nil end
    local values = {}
    for index, position in ipairs(compiled.positions) do values[position] = captures[index + 2] end
    return values
end

local function matchMessage(message, key, fallback)
    local result = capture(message, _G[key])
    if result then return result, true end
    return capture(message, fallback), false
end

function GroupEvents.New(db, callbacks)
    callbacks = callbacks or {}
    local self = setmetatable({db = db, callbacks = callbacks, pendingRolls = {}}, GroupEvents)
    self.model = ns.GroupLoot.New(db, callbacks)
    return self
end

function GroupEvents:Changed()
    if self.callbacks.onChange then self.callbacks.onChange() end
end

function GroupEvents:Now()
    return self.callbacks.now and self.callbacks.now() or (GetTime and GetTime() or 0)
end

function GroupEvents:Method()
    local method = GetLootMethod and GetLootMethod() or "unknown"
    if method == "needbeforegreed" then return "group" end
    if method == "group" or method == "master" then return method end
    return "unknown"
end

function GroupEvents:IsGrouped()
    if GetNumRaidMembers and (GetNumRaidMembers() or 0) > 0 then return true end
    if GetNumPartyMembers and (GetNumPartyMembers() or 0) > 0 then return true end
    return UnitName and UnitName("party1") ~= nil or false
end

function GroupEvents:IsMember(name)
    name = plainName(name)
    if not name or not UnitName then return false end
    local lowered = string.lower(name)
    for _, unit in ipairs({"player", "party1", "party2", "party3", "party4"}) do
        local member = UnitName(unit)
        if member and string.lower(member) == lowered then return true end
    end
    for index = 1, 40 do
        local member = UnitName("raid" .. index)
        if member and string.lower(member) == lowered then return true end
    end
    return false
end

function GroupEvents:Select(contextID)
    local result = self.model:Select(contextID)
    if result then self:Changed() end
    return result
end

function GroupEvents:BeginItem(link, method)
    if not itemKey(link) then return nil end
    local existing, reason = self.model:ResolveContext(link)
    if existing then self.model:Select(existing.id); return existing end
    if reason == "ambiguous" then return nil, reason end
    local entry = self.model:StartItem(link, method or self:Method())
    if entry then self.model:Select(entry.id); self:Changed() end
    return entry
end

function GroupEvents:ObserveItem(link, name, quality, sourceToken)
    if not self:IsGrouped() or self:Method() == "unknown" or not itemKey(link) then return nil end
    if self:Method() == "master" and type(sourceToken) == "string" and sourceToken ~= "" then
        -- Identical master-loot items do not have native roll IDs. Keep their
        -- observed drop identities separate instead of merging by item ID.
        for _, candidate in ipairs(self.model:Entries()) do
            if candidate.observedSource == sourceToken and itemKey(candidate.link) == itemKey(link) then
                return candidate
            end
        end
        local placeholder = self.model:ResolveContext(link)
        if placeholder and placeholder.observedSource == nil
            and placeholder.distributionMethod == "master" then
            placeholder.observedSource = sourceToken
            self:Changed()
            return placeholder
        end
        local entry = self.model:StartItem(link, "master", {name = name, quality = quality})
        if entry then
            entry.observedSource = sourceToken
            self:Changed()
        end
        return entry
    end
    local existing, reason = self.model:ResolveContext(link)
    if existing then return existing end
    if reason == "ambiguous" then return nil, reason end
    local entry = self.model:StartItem(link, self:Method(), {name = name, quality = quality})
    if entry then self:Changed() end
    return entry
end

function GroupEvents:StartRoll(rollID, attempt)
    if rollID == nil then return end
    if not GetLootRollItemLink then return end
    local link = GetLootRollItemLink(rollID)
    if not link then
        if attempt < 5 and ns.Compat and ns.Compat.After and not self.pendingRolls[rollID] then
            local token = {}
            self.pendingRolls[rollID] = token
            ns.Compat.After(0.2, function()
                if self.pendingRolls[rollID] == token then
                    self.pendingRolls[rollID] = nil
                    self:StartRoll(rollID, attempt + 1)
                end
            end)
        end
        return
    end
    local icon, name, quantity, quality
    if GetLootRollItemInfo then icon, name, quantity, quality = GetLootRollItemInfo(rollID) end
    local existing = self.model:ResolveContext(link)
    local entry
    if existing and existing.rollID == nil and existing.distributionMethod == "group" then
        existing.rollID = rollID
        entry = existing
    else
        entry = self.model:StartItem(link, "group", {rollID = rollID, name = name, quality = quality})
    end
    if entry then
        entry.quantity = tonumber(quantity) or entry.quantity or 1
        entry.icon = icon or entry.icon
        self:Changed()
    end
end

function GroupEvents:ManualContext(link)
    if link then return self.model:ResolveContext(link) end
    local active = self.model:GetActive()
    if active then return active end
    local candidate
    for _, entry in ipairs(self.model:Entries()) do
        if entry.state == "open" then
            if candidate then return nil, "ambiguous" end
            candidate = entry
        end
    end
    return candidate
end

local CHOICES = {
    {"LOOT_ROLL_NEED", "%s has selected Need for: %s", "NEED", 1},
    {"LOOT_ROLL_NEED_SELF", "You have selected Need for: %s", "NEED", 0},
    {"LOOT_ROLL_GREED", "%s has selected Greed for: %s", "GREED", 1},
    {"LOOT_ROLL_GREED_SELF", "You have selected Greed for: %s", "GREED", 0},
    {"LOOT_ROLL_PASSED", "%s passed on: %s", "PASS", 1},
    {"LOOT_ROLL_PASSED_SELF", "You passed on: %s", "PASS", 0},
}
local ROLLS = {
    {"LOOT_ROLL_ROLLED_NEED", "Need Roll - %d for %s by %s", "NEED", 9, 3, 1},
    {"LOOT_ROLL_ROLLED_GREED", "Greed Roll - %d for %s by %s", "GREED", 9, 3, 1},
    {"LOOT_ROLL_ROLLED_NEED_SELF", "You roll a %d (Need) on: %s", "NEED", 0, 0, 1},
    {"LOOT_ROLL_ROLLED_GREED_SELF", "You roll a %d (Greed) on: %s", "GREED", 0, 0, 1},
    {"LOOT_ROLL_ROLLED", "%s rolls a %d on: %s", nil, 1, 1, 2},
    {"LOOT_ROLL_ROLLED_SELF", "You roll a %d on: %s", nil, 0, 0, 1},
}
local WINNERS = {
    {"LOOT_ROLL_WON_NO_SPAM_NEED", "%s won: %s |cff818181(Need - %d)|r", 1, "NEED", 2, 3},
    {"LOOT_ROLL_WON_NO_SPAM_GREED", "%s won: %s |cff818181(Greed - %d)|r", 1, "GREED", 2, 3},
    {"LOOT_ROLL_YOU_WON_NO_SPAM_NEED", "You won: %s |cff818181(Need - %d)|r", 0, "NEED", 1, 2},
    {"LOOT_ROLL_YOU_WON_NO_SPAM_GREED", "You won: %s |cff818181(Greed - %d)|r", 0, "GREED", 1, 2},
    {"LOOT_ROLL_WON", "%s won: %s", 1, nil, nil},
    {"LOOT_ROLL_YOU_WON", "You won: %s", 0, nil, nil},
}
local RECEIPTS = {
    {"LOOT_ITEM_MULTIPLE", "%s receives loot: %sx%d.", 1},
    {"LOOT_ITEM_SELF_MULTIPLE", "You receive loot: %sx%d.", 0},
    {"LOOT_ITEM", "%s receives loot: %s.", 1},
    {"LOOT_ITEM_SELF", "You receive loot: %s.", 0},
}

function GroupEvents:HandleLootMessage(message)
    local link = extractLink(message)
    if not link then return end
    for _, definition in ipairs(RECEIPTS) do
        local values = matchMessage(message, definition[1], definition[2])
        if values then
            local receiver = definition[3] == 0 and playerName() or plainName(values[definition[3]])
            if receiver and self:IsMember(receiver) and (self:IsGrouped() or getn(self.model:Entries()) > 0) then
                self.model:Award(link, receiver, {source = "loot_receipt"})
                self:Changed()
            end
            return
        end
    end
    for _, definition in ipairs(CHOICES) do
        local values = matchMessage(message, definition[1], definition[2])
        if values then
            local player = definition[4] == 0 and playerName() or plainName(values[definition[4]])
            if player and self:IsMember(player) then
                local entry, reason = self.model:ResolveContext(link)
                if not entry and reason ~= "ambiguous" then entry = self.model:StartItem(link, "group") end
                if entry then self.model:SetChoice(entry.id, player, definition[3]); self:Changed() end
            end
            return
        end
    end
    for _, definition in ipairs(ROLLS) do
        local values, native = matchMessage(message, definition[1], definition[2])
        if values then
            local actorIndex = native and definition[4] or definition[5]
            local player = actorIndex == 0 and playerName() or plainName(values[actorIndex])
            local entry = self.model:ResolveContext(link)
            if entry and player and self:IsMember(player) then
                self.model:AddRoll(entry.id, player, tonumber(values[definition[6]]), 1, 100, definition[3])
                self:Changed()
            end
            return
        end
    end
    for _, definition in ipairs(WINNERS) do
        local values, native = matchMessage(message, definition[1], definition[2])
        if values then
            local player = definition[3] == 0 and playerName() or plainName(values[definition[3]])
            local valueIndex = native and definition[5] or definition[6]
            local result = valueIndex and tonumber(values[valueIndex]) or nil
            local entry = self.model:ResolveContext(link)
            if entry and player and self:IsMember(player) then
                self.model:RecordObservedWinner(entry.id, player, definition[4], result)
                self:Changed()
            end
            return
        end
    end
    local values = matchMessage(message, "LOOT_ROLL_START", "Rolling started on: %s")
    if values then
        local entry, reason = self.model:ResolveContext(link)
        if not entry and reason ~= "ambiguous" then self.model:StartItem(link, "group"); self:Changed() end
        return
    end
    values = matchMessage(message, "LOOT_ROLL_ALL_PASSED", "Everyone passed on: %s")
    if values then
        local entry = self.model:ResolveContext(link)
        if entry then entry.state, entry.resolution = "unassigned", "all_passed"; self:Changed() end
    end
end

function GroupEvents:HandlePartyMessage(event, message, sender)
    sender = plainName(sender)
    if not sender or not self:IsMember(sender) or type(message) ~= "string" then return end
    local link, issue = extractLink(message)
    if issue then return end
    local entry, reason = self:ManualContext(link)
    local bid = ns.GroupLoot.NormalizeBid(message)
    if link and not entry and reason ~= "ambiguous" then
        local lower = string.lower(message)
        local remainder = string.gsub(message, "|c%x%x%x%x%x%x%x%x|Hitem:.-|h.-|h|r", "")
        remainder = string.gsub(remainder, "|Hitem:.-|h.-|h", "")
        remainder = string.gsub(remainder, "%s", "")
        local announcement = event == "CHAT_MSG_RAID_WARNING" or bid ~= nil or remainder == ""
            or string.find(lower, "%f[%a]roll%f[%A]") or string.find(lower, "%f[%a]bid%f[%A]")
            or string.find(lower, "ep/gp", 1, true) or string.find(lower, "epgp", 1, true)
        -- A linked announcement identifies that item, but must not silently
        -- select the newest of several concurrent items for later /rolls.
        if announcement then
            entry = self.model:StartItem(link, self:Method())
            if entry then self:Changed() end
        end
    end
    if entry and bid then
        if self.model:AddBid(entry.id, sender, message) then self:Changed() end
    end
end

function GroupEvents:HandleEvent(event, a, b, c, d)
    if event == "START_LOOT_ROLL" then
        self:StartRoll(a, 0)
    elseif event == "CANCEL_LOOT_ROLL" then
        self.pendingRolls[a] = nil
    elseif event == "CHAT_MSG_LOOT" and type(a) == "string" then
        self:HandleLootMessage(a)
    elseif event == "CHAT_MSG_SYSTEM" and type(a) == "string" then
        local values = matchMessage(a, "RANDOM_ROLL_RESULT", "%s rolls %d (%d-%d)")
        if values then
            local name = plainName(values[1])
            local entry = self:ManualContext()
            if entry and entry.distributionMethod == "master" and name and self:IsMember(name) then
                if self.model:AddRoll(entry.id, name, tonumber(values[2]), tonumber(values[3]), tonumber(values[4])) then self:Changed() end
            end
        end
    elseif GROUP_CHAT[event] then
        self:HandlePartyMessage(event, a, b)
    end
end

function GroupEvents:Reset()
    self.pendingRolls = {}
    self.model = ns.GroupLoot.New(self.db, self.callbacks)
end
