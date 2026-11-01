local _, ns = ...
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

local function itemKey(link)
    return type(link) == "string" and link:match("item:(%d+)") or nil
end

local function creature(guid)
    return type(guid) == "string" and guid:match("^Creature%-") ~= nil
end

local function affiliationFlag(flags, flag)
    -- Affiliation constants are individual powers of two. Arithmetic works in
    -- standalone Lua 5.1 too, without depending on WoW's global bit library.
    return type(flags) == "number" and math.floor(flags / flag) % 2 == 1
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
        sequence = 0, lootOpen = false }, Tracker)
end

function Tracker:Now()
    return self.callbacks.now and self.callbacks.now() or GetTime()
end

function Tracker:Reset()
    self.tags = {}
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
        self.lastPrune = clock
    end
end

function Tracker:HandleCombatLog()
    if not CombatLogGetCurrentEventInfo then return end
    self:Expire()
    local _, event, _, sourceGUID, _, sourceFlags, _, destGUID, destName = CombatLogGetCurrentEventInfo()
    if not creature(destGUID) then return end
    if DAMAGE_EVENTS[event] then
        local player = UnitGUID("player")
        local pet = UnitGUID("pet")
        local group = self.callbacks.includeGroup
            and (affiliationFlag(sourceFlags, 0x2) or affiliationFlag(sourceFlags, 0x4))
        if sourceGUID and ((player and sourceGUID == player) or (pet and sourceGUID == pet) or group) then
            self.tags[destGUID] = { at = self:Now(), name = destName }
        end
    elseif event == "UNIT_DIED" or event == "UNIT_DESTROYED" then
        local tagged = self.tags[destGUID]
        self.tags[destGUID] = nil
        if tagged and self:Now() - tagged.at <= TAG_TIMEOUT and self.callbacks.onKill then
            self.callbacks.onKill(destGUID, destName or tagged.name or "Onbekende mob", time(), self:Now())
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
                for index = 1, #sources, 2 do
                    if creature(sources[index]) or (type(sources[index]) == "string" and sources[index]:match("^GameObject%-")) then
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

function Tracker:HandleEvent(event, ...)
    self:Expire()
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:HandleCombatLog()
    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit, target, castGUID, spellID = ...
        if unit == "player" and spellID == DISENCHANT then self:StartCast(castGUID, target) end
    elseif event == "UNIT_SPELLCAST_START" then
        local unit, castGUID, spellID = ...
        if unit == "player" and spellID == DISENCHANT then self:StartCast(castGUID) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellID = ...
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
        local unit, castGUID, spellID = ...
        if unit == "player" and spellID == DISENCHANT and self.cast and self.cast.guid == castGUID then
            self.cast = nil
        end
    elseif event == "BAG_UPDATE_DELAYED" then
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
