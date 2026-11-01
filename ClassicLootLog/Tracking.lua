ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local Compat = ns.Compat or {}
local getn = table.getn
local mod = math.mod or math.fmod

local function match(value, pattern)
    local first, last, captured = string.find(value, pattern)
    return captured
end

local function unitGUID(unit)
    if Compat.UnitGUIDSafe then return Compat.UnitGUIDSafe(unit) end
    if UnitGUID then return UnitGUID(unit) end
    if UnitExists then
        local exists, guid = UnitExists(unit)
        if exists and type(guid) == "string" then return guid end
    end
end
local Tracker = {}
Tracker.__index = Tracker
ns.Tracker = Tracker

local DISENCHANT = 13262
local CAST_TIMEOUT = 20
local RESULT_TIMEOUT = 10
local TAG_TIMEOUT = 1800
local DAMAGE_EVENTS = {
    SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true,
    SPELL_BUILDING_DAMAGE = true,
}

Tracker.LegacyEvents = {
    "CHAT_MSG_COMBAT_HOSTILE_DEATH", "CHAT_MSG_COMBAT_SELF_HITS",
    "CHAT_MSG_COMBAT_PET_HITS", "CHAT_MSG_COMBAT_PARTY_HITS",
    "CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS", "CHAT_MSG_SPELL_SELF_DAMAGE",
    "CHAT_MSG_SPELL_PET_DAMAGE", "CHAT_MSG_SPELL_PARTY_DAMAGE",
    "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS",
    "SPELLCAST_START", "SPELLCAST_STOP", "SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED",
    "SPELLCAST_DELAYED", "BAG_UPDATE",
}

local LEGACY_DAMAGE_EVENTS = {}
for _, eventName in ipairs(Tracker.LegacyEvents) do
    if string.find(eventName, "^CHAT_MSG_") and eventName ~= "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
        LEGACY_DAMAGE_EVENTS[eventName] = true
    end
end

-- Capture positions follow Blizzard's localized GlobalStrings, not an assumed
-- English word order. Defaults cover clients which omit a combat template.
local LEGACY_DAMAGE_FORMATS = {
    {"COMBATHITSELFOTHER", "You hit %s for %d.", 1, 0},
    {"COMBATHITCRITSELFOTHER", "You crit %s for %d.", 1, 0},
    {"COMBATHITSCHOOLSELFOTHER", "You hit %s for %d %s damage.", 1, 0},
    {"COMBATHITCRITSCHOOLSELFOTHER", "You crit %s for %d %s damage.", 1, 0},
    {"COMBATHITOTHEROTHER", "%s hits %s for %d.", 2, 1},
    {"COMBATHITCRITOTHEROTHER", "%s crits %s for %d.", 2, 1},
    {"COMBATHITSCHOOLOTHEROTHER", "%s hits %s for %d %s damage.", 2, 1},
    {"COMBATHITCRITSCHOOLOTHEROTHER", "%s crits %s for %d %s damage.", 2, 1},
    {"SPELLLOGSELFOTHER", "Your %s hits %s for %d.", 2, 0},
    {"SPELLLOGCRITSELFOTHER", "Your %s crits %s for %d.", 2, 0},
    {"SPELLLOGSCHOOLSELFOTHER", "Your %s hits %s for %d %s damage.", 2, 0},
    {"SPELLLOGCRITSCHOOLSELFOTHER", "Your %s crits %s for %d %s damage.", 2, 0},
    {"SPELLLOGOTHEROTHER", "%s's %s hits %s for %d.", 3, 1},
    {"SPELLLOGCRITOTHEROTHER", "%s's %s crits %s for %d.", 3, 1},
    {"SPELLLOGSCHOOLOTHEROTHER", "%s's %s hits %s for %d %s damage.", 3, 1},
    {"SPELLLOGCRITSCHOOLOTHEROTHER", "%s's %s crits %s for %d %s damage.", 3, 1},
    {"PERIODICAURADAMAGESELFOTHER", "%s suffers %d %s damage from your %s.", 1, 0},
    {"PERIODICAURADAMAGEOTHEROTHER", "%s suffers %d %s damage from %s's %s.", 1, 4},
    {"DAMAGESHIELDSELFOTHER", "You reflect %d %s damage to %s.", 3, 0},
    {"DAMAGESHIELDOTHEROTHER", "%s reflects %d %s damage to %s.", 4, 1},
}

local formatCache = {}
local function combatPattern(format)
    if formatCache[format] then return formatCache[format] end
    local parts, index, length = {"^"}, 1, string.len(format)
    while index <= length do
        local char = string.sub(format, index, index)
        if char == "%" then
            local nextChar = string.sub(format, index + 1, index + 1)
            if nextChar == "s" then
                parts[getn(parts) + 1] = "(.-)"
            elseif nextChar == "d" then
                parts[getn(parts) + 1] = "(%d+)"
            elseif nextChar == "%" then
                parts[getn(parts) + 1] = "%%"
            else
                -- Unsupported positional format: do not guess the target.
                return nil
            end
            index = index + 2
        else
            if string.find("^$().[]*+-?", char, 1, true) then char = "%" .. char end
            parts[getn(parts) + 1] = char
            index = index + 1
        end
    end
    local pattern = table.concat(parts)
    formatCache[format] = pattern
    return pattern
end

local function captureFormat(message, key, fallback)
    local format = _G[key] or fallback
    if type(format) ~= "string" then return nil end
    local pattern = combatPattern(format)
    if not pattern then return nil end
    local first, last, a, b, c, d, e = string.find(message, pattern)
    if first then return {a, b, c, d, e} end
end

function Tracker:IsGroupName(name)
    if not UnitName or not name then return false end
    if name == UnitName("player") or name == UnitName("pet") then return true end
    if not self.callbacks.includeGroup then return false end
    for index = 1, 4 do
        if name == UnitName("party" .. index) or name == UnitName("partypet" .. index) then return true end
    end
    for index = 1, 40 do
        if name == UnitName("raid" .. index) or name == UnitName("raidpet" .. index) then return true end
    end
    return false
end

function Tracker:LegacyMobIdentity(name)
    if not UnitName then return nil, false end
    local units = {"target", "pettarget"}
    if self.callbacks.includeGroup then
        for index = 1, 4 do units[getn(units) + 1] = "party" .. index .. "target" end
        for index = 1, 40 do units[getn(units) + 1] = "raid" .. index .. "target" end
    end
    for _, unit in ipairs(units) do
        if UnitName(unit) == name then
            if UnitIsPlayer and UnitIsPlayer(unit) then return nil, true end
            local guid = unitGUID(unit)
            if guid then return guid, false end
        end
    end
    return nil, false
end

function Tracker:TagLegacyName(name)
    if not name or name == "" then return end
    local guid, isPlayer = self:LegacyMobIdentity(name)
    if isPlayer or self:IsGroupName(name) then return end
    local list = self.legacyNames[name] or {}
    list[guid or "name"] = {at = self:Now(), guid = guid}
    self.legacyNames[name] = list
end

function Tracker:LegacyDeath(name, direct, kind)
    if not name or name == "" then return end
    local guid, isPlayer = self:LegacyMobIdentity(name)
    if isPlayer or self:IsGroupName(name) then return end
    local list = self.legacyNames[name]
    local tag, tagKey
    if list then
        if guid and list[guid] then tag, tagKey = list[guid], guid end
        if not tag then
            for key, candidate in pairs(list) do
                if self:Now() - candidate.at <= TAG_TIMEOUT then tag, tagKey = candidate, key; break end
            end
        end
    end
    if not direct and not tag then return end
    local recent = self.legacyDeaths[name]
    if recent and recent.kind ~= kind and self:Now() - recent.at < 0.25 then return end
    guid = tag and tag.guid or guid
    if guid and self.legacySeen[guid] then return end
    if list and tagKey then
        list[tagKey] = nil
        if not next(list) then self.legacyNames[name] = nil end
    end
    if guid then
        self.legacySeen[guid] = true
    else
        self.sequence = self.sequence + 1
        guid = "legacy-kill:" .. tostring(time()) .. ":" .. tostring(self.sequence)
    end
    self.legacyDeaths[name] = {at = self:Now(), kind = kind}
    if self.callbacks.onKill then self.callbacks.onKill(guid, name, time(), self:Now()) end
end

function Tracker:HandleLegacyCombat(eventName, message)
    if type(message) ~= "string" then return end
    if eventName == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
        local killed = captureFormat(message, "SELFKILLOTHER", "You have slain %s!")
        if killed then self:LegacyDeath(killed[1], true, "self"); return end
        killed = captureFormat(message, "PARTYKILLOTHER", "%s is slain by %s!")
        if killed then
            if self:IsGroupName(killed[2]) then self:LegacyDeath(killed[1], true, "party") end
            return
        end
        killed = captureFormat(message, "UNITDIESOTHER", "%s dies.")
        if killed then self:LegacyDeath(killed[1], false, "death") end
    elseif LEGACY_DAMAGE_EVENTS[eventName] then
        for _, definition in ipairs(LEGACY_DAMAGE_FORMATS) do
            local captures = captureFormat(message, definition[1], definition[2])
            if captures and (definition[4] == 0 or self:IsGroupName(captures[definition[4]])) then
                self:TagLegacyName(captures[definition[3]])
                return
            end
        end
    end
end

local function itemKey(link)
    return type(link) == "string" and match(link, "item:(%d+)") or nil
end

local function creature(guid)
    return type(guid) == "string" and string.find(guid, "^Creature%-") ~= nil
end

local function affiliationFlag(flags, flag)
    -- Affiliation constants are individual powers of two. Arithmetic works in
    -- standalone Lua 5.1 too, without depending on WoW's global bit library.
    return type(flags) == "number" and mod(math.floor(flags / flag), 2) == 1
end

-- Count bag contents by item ID, so moving an item between slots or bags does
-- not look like a destroyed item. Bank contents are deliberately excluded.
function Tracker.SnapshotBags()
    local api = C_Container or {}
    local getSlots = api.GetContainerNumSlots or GetContainerNumSlots
    local getLink = api.GetContainerItemLink or GetContainerItemLink
    local getInfo = api.GetContainerItemInfo or GetContainerItemInfo
    if not getSlots or not getLink or not getInfo then return nil end
    local result = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local count = getSlots(bag)
        if type(count) ~= "number" then return nil end
        for slot = 1, count do
            local info, legacyCount = getInfo(bag, slot)
            local link = getLink(bag, slot)
            local quantity
            if type(info) == "table" then
                link = link or info.hyperlink
                quantity = info.stackCount
            else
                quantity = legacyCount
            end
            if info and not link then return nil end
            if link then
                local key = itemKey(link)
                if not key then return nil end
                local entry = result[key] or { link = link, quantity = 0 }
                entry.quantity = entry.quantity + math.max(1, tonumber(quantity) or 1)
                result[key] = entry
            end
        end
    end
    return result
end

function Tracker.New(callbacks)
    return setmetatable({ callbacks = callbacks or {}, tags = {}, lastPrune = 0,
        sequence = 0, lootOpen = false, legacyNames = {}, legacySeen = {}, legacyDeaths = {} }, Tracker)
end

function Tracker:Now()
    return self.callbacks.now and self.callbacks.now() or GetTime()
end

function Tracker:Reset()
    self.tags = {}
    self.legacyNames, self.legacySeen, self.legacyDeaths = {}, {}, {}
    self.cast = nil
    self.context = nil
    self.lootOpen = false
end

function Tracker:Expire()
    local clock = self:Now()
    local cast = self.cast
    if cast and clock - (cast.succeededAt or cast.startedAt) > (cast.succeededAt and RESULT_TIMEOUT or CAST_TIMEOUT) then
        self.cast = nil
        -- A context already bound to an open window remains stable until close.
    end
    if clock - self.lastPrune >= 30 then
        for guid, tagged in pairs(self.tags) do
            if clock - tagged.at > TAG_TIMEOUT then self.tags[guid] = nil end
        end
        for name, list in pairs(self.legacyNames) do
            for key, tagged in pairs(list) do
                if clock - tagged.at > TAG_TIMEOUT then list[key] = nil end
            end
            if not next(list) then self.legacyNames[name] = nil end
        end
        self.lastPrune = clock
    end
end

function Tracker:HandleCombatLog()
    if not CombatLogGetCurrentEventInfo then return end
    self:Expire()
    local _, event, _, sourceGUID, _, sourceFlags, _, destGUID, destName = CombatLogGetCurrentEventInfo()
    if not creature(destGUID) then return end
    if DAMAGE_EVENTS[event] then
        local player = unitGUID("player")
        local pet = unitGUID("pet")
        local group = self.callbacks.includeGroup
            and (affiliationFlag(sourceFlags, 2) or affiliationFlag(sourceFlags, 4))
        if sourceGUID and ((player and sourceGUID == player) or (pet and sourceGUID == pet) or group) then
            self.tags[destGUID] = { at = self:Now(), name = destName }
        end
    elseif event == "UNIT_DIED" or event == "UNIT_DESTROYED" then
        local tagged = self.tags[destGUID]
        self.tags[destGUID] = nil
        if tagged and self:Now() - tagged.at <= TAG_TIMEOUT and self.callbacks.onKill then
            self.callbacks.onKill(destGUID, destName or tagged.name or "Unknown mob", time(), self:Now())
        end
    end
end

function Tracker:StartCast(castGUID, target)
    if self.cast and self.cast.guid == castGUID then return end
    self.sequence = self.sequence + 1
    self.cast = {
        guid = castGUID,
        sourceGUID = "disenchant:" .. tostring(time()) .. ":" .. tostring(self.sequence) .. ":" .. tostring(castGUID or "unknown"),
        startedAt = self:Now(),
        before = Tracker.SnapshotBags(),
        targetLink = itemKey(target) and target or nil,
    }
end

function Tracker:BindLootContext()
    local cast = self.cast
    if not self.context and cast and cast.succeededAt and not cast.lootConsumed then
        -- A corpse source is positive evidence of regular loot. In particular,
        -- don't label a quickly opened corpse as materials after a DE window
        -- that the client never delivered to us.
        if GetNumLootItems and GetLootSourceInfo then
            for slot = 1, GetNumLootItems() do
                local sources = { GetLootSourceInfo(slot) }
                for index = 1, getn(sources), 2 do
                    if creature(sources[index]) or (type(sources[index]) == "string" and string.find(sources[index], "^GameObject%-")) then
                        cast.lootConsumed = true
                        return
                    end
                end
            end
        end
        self.context = { origin = "disenchant", sourceGUID = cast.sourceGUID, itemLink = cast.itemLink }
        cast.lootConsumed = true
    end
end

function Tracker:InferDisenchantedItem()
    local cast = self.cast
    if not cast or not cast.succeededAt or cast.inferred or cast.ambiguous or not cast.before then return end
    local after = Tracker.SnapshotBags()
    if not after then return end
    local removed, total = nil, 0
    for key, entry in pairs(cast.before) do
        local difference = entry.quantity - (after[key] and after[key].quantity or 0)
        if difference > 0 then
            total = total + difference
            removed = entry
        end
    end
    if total > 1 then
        -- Selling, trading, or another removal at the same time is ambiguous.
        -- Never guess which recorded drop was destroyed.
        cast.ambiguous = true
    elseif total == 1 then
        cast.inferred = true
        cast.itemLink = removed.link
        if self.context and self.context.sourceGUID == cast.sourceGUID then
            self.context.itemLink = removed.link
        end
        if self.callbacks.onDisenchant then self.callbacks.onDisenchant(removed.link, 1, self:Now()) end
    end
end

function Tracker:IsLootOpen()
    return self.lootOpen
end

function Tracker:IsDisenchantPending()
    self:Expire()
    return self.cast ~= nil and self.cast.succeededAt == nil
end

function Tracker:GetLootContext()
    self:Expire()
    return self.context
end

function Tracker:HandleEvent(event, a, b, c, d)
    self:Expire()
    if Compat.IsLegacy and (LEGACY_DAMAGE_EVENTS[event] or event == "CHAT_MSG_COMBAT_HOSTILE_DEATH") then
        self:HandleLegacyCombat(event, a)
    elseif Compat.IsLegacy and event == "SPELLCAST_START" then
        local disenchantName = GetSpellInfo and GetSpellInfo(DISENCHANT) or "Disenchant"
        if a == disenchantName then
            self:StartCast("legacy-cast:" .. tostring(self:Now()))
            self.cast.legacy = true
            self.cast.duration = math.max(0, tonumber(b) or 0) / 1000
        end
    elseif Compat.IsLegacy and event == "SPELLCAST_DELAYED" then
        if self.cast and self.cast.legacy and not self.cast.succeededAt then
            self.cast.duration = (self.cast.duration or 0) + math.max(0, tonumber(a) or 0) / 1000
        end
    elseif Compat.IsLegacy and event == "SPELLCAST_STOP" then
        local cast = self.cast
        if cast and cast.legacy and self:Now() - cast.startedAt + 0.2 >= (cast.duration or 0) then
            cast.succeededAt = self:Now()
            if self.lootOpen then self:BindLootContext() end
            self:InferDisenchantedItem()
        end
    elseif Compat.IsLegacy and (event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED") then
        if self.cast and self.cast.legacy then
            if self.context and self.context.sourceGUID == self.cast.sourceGUID then self.context = nil end
            self.cast = nil
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:HandleCombatLog()
    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit, target, castGUID, spellID = a, b, c, d
        if unit == "player" and spellID == DISENCHANT then self:StartCast(castGUID, target) end
    elseif event == "UNIT_SPELLCAST_START" then
        local unit, castGUID, spellID = a, b, c
        if unit == "player" and spellID == DISENCHANT then self:StartCast(castGUID) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellID = a, b, c
        if unit == "player" and spellID == DISENCHANT then
            if not self.cast or self.cast.guid ~= castGUID then
                self:StartCast(castGUID)
                -- A success-only event cannot supply a trustworthy before
                -- snapshot: the item may already have been consumed.
                self.cast.before = nil
            end
            self.cast.succeededAt = self:Now()
            if self.lootOpen then self:BindLootContext() end
            self:InferDisenchantedItem()
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unit, castGUID, spellID = a, b, c
        if unit == "player" and spellID == DISENCHANT and self.cast and self.cast.guid == castGUID then
            self.cast = nil
        end
    elseif event == "BAG_UPDATE_DELAYED" or (Compat.IsLegacy and event == "BAG_UPDATE") then
        self:InferDisenchantedItem()
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        self.lootOpen = true
        self:BindLootContext()
    elseif event == "LOOT_CLOSED" then
        self.lootOpen = false
        self.context = nil
        -- Keep the pre-cast snapshot until the bag removal is observed, but
        -- never attach the same cast to a later, unrelated corpse window.
        if self.cast and self.cast.succeededAt then self.cast.lootConsumed = true end
    end
    -- UNIT_SPELLCAST_STOP is intentionally a no-op: it also fires on success.
end
