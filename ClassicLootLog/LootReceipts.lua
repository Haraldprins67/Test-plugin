-- Recover actual personal loot when auto-loot closes before slot data arrives.
-- A supplied corpse/window/cast source reconciles receipts with Core snapshots.
ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local LootReceipts = {}
LootReceipts.__index = LootReceipts
ns.LootReceipts = LootReceipts

local getn, floor = table.getn, math.floor
local compiledFormats = {}
local colors = {
    ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3,
    ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6, ff00ccff = 7,
}

local function quantity(value)
    value = tonumber(value)
    if type(value) == "number" and value == value and value > 0
        and value <= 2147483647 and value == floor(value) then return value end
end

local function itemPayload(link)
    if ns.Core and ns.Core.ItemPayload then return ns.Core.ItemPayload(link) end
    if type(link) ~= "string" then return nil end
    local _, _, payload = string.find(link, "|H(item:%-?%d+[^|]*)|h")
    if not payload then _, _, payload = string.find(link, "^(item:%d+[:%d%-]*)$") end
    return payload
end

LootReceipts.Payload = itemPayload
LootReceipts.Key = itemPayload

-- This is only a hint for linking a late receipt to a confirmed recent cast.
-- It never turns an ordinary dust drop into a disenchant result by itself.
local enchantingMaterials = {
    [10938] = true, [10939] = true, [10940] = true, [10978] = true,
    [10998] = true, [11082] = true, [11083] = true, [11084] = true,
    [11134] = true, [11135] = true, [11137] = true, [11138] = true,
    [11139] = true, [11174] = true, [11175] = true, [11176] = true,
    [11177] = true, [11178] = true, [14343] = true, [14344] = true,
    [16202] = true, [16203] = true, [16204] = true, [20725] = true,
}

function LootReceipts.IsEnchantMaterial(value)
    local id = tonumber(value)
    if not id and type(value) == "string" then
        local _, _, captured = string.find(value, "item:(%d+)")
        id = tonumber(captured)
    end
    return id ~= nil and enchantingMaterials[id] == true
end

-- Position captures distinguish a stack quantity from item-ID/suffix numbers
-- in expanded Vanilla formats, even if localized arguments are reordered.
local function compile(format)
    if type(format) ~= "string" or format == "" then return nil end
    if compiledFormats[format] then return compiledFormats[format] end
    local parts, numbers, strings, captures, position = {"^"}, {}, {}, 0, 1
    while position <= string.len(format) do
        local character = string.sub(format, position, position)
        if character == "%" then
            local _, last, argument, kind = string.find(string.sub(format, position), "^%%(%d+)%$([sd])")
            if last then position = position + last
            else kind = string.sub(format, position + 1, position + 1); position = position + 2 end
            if kind == "%" then parts[getn(parts) + 1] = "%%"
            elseif kind == "s" then
                parts[getn(parts) + 1] = "(.-)"
                captures = captures + 1
                strings[getn(strings) + 1] = captures
            elseif kind == "d" then
                parts[getn(parts) + 1] = "()(%-?%d+)"
                numbers[getn(numbers) + 1] = {position = captures + 1, value = captures + 2}
                captures = captures + 2
            else return nil end
        else
            if string.find("^$().[]*+-?", character, 1, true) then character = "%" .. character end
            parts[getn(parts) + 1] = character
            position = position + 1
        end
    end
    if captures > 30 then return nil end
    parts[getn(parts) + 1] = "$"
    local result = {pattern = table.concat(parts), numbers = numbers, strings = strings}
    compiledFormats[format] = result
    return result
end

local function matchReceipt(message, format, multiple, linkStart, linkEnd)
    local pattern = compile(format)
    if not pattern then return nil end
    local values = {string.find(message, pattern.pattern)}
    if not values[1] then return nil end
    for _, index in ipairs(pattern.strings) do
        local value = values[index + 2]
        if type(value) == "string" and string.find(value, "|Hitem:", 1, true) then
            -- The single-item template must not swallow an invalid stack
            -- suffix or trailing prose into its broad %s item substitution.
            local first = string.find(value, "^|c%x%x%x%x%x%x%x%x|Hitem:.-|h.-|h|r$")
                or string.find(value, "^|Hitem:.-|h.-|h$")
            if not first then return nil end
        end
    end
    local count
    for _, number in ipairs(pattern.numbers) do
        local start = values[number.position + 2]
        if start and (start < linkStart or start > linkEnd) then
            if count ~= nil then return nil end
            count = quantity(values[number.value + 2])
            if not count then return nil end
        end
    end
    if multiple then return count end
    return count == nil and 1 or nil
end

local function metadata(link)
    local _, _, name = string.find(link, "|h%[(.-)%]|h")
    if not name then _, _, name = string.find(link, "|h(.-)|h") end
    local _, _, color = string.find(link, "|c(%x%x%x%x%x%x%x%x)")
    local quality = color and colors[string.lower(color)] or nil
    local icon, cachedName, cachedQuality
    if type(GetItemInfo) == "function" then
        local ok, value, cachedLink, rarity, level, required, class, subclass, maxStack, equip, texture = pcall(GetItemInfo, link)
        if ok then cachedName, cachedQuality, icon = value, rarity, texture end
    end
    if quality == nil and type(cachedQuality) == "number" then quality = cachedQuality end
    return name or cachedName or "Unknown item", quality or 0,
        icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function LootReceipts.Parse(message)
    if type(message) ~= "string" then return nil end
    local first, last, link = string.find(message, "(|c%x%x%x%x%x%x%x%x|Hitem:.-|h.-|h|r)")
    if not first then first, last, link = string.find(message, "(|Hitem:.-|h.-|h)") end
    if not first or not itemPayload(link) or string.find(message, "|Hitem:", last + 1, true) then return nil end
    local count = matchReceipt(message, LOOT_ITEM_SELF_MULTIPLE, true, first, last)
        or matchReceipt(message, "You receive loot: %sx%d.", true, first, last)
        or matchReceipt(message, LOOT_ITEM_SELF, false, first, last)
        or matchReceipt(message, "You receive loot: %s.", false, first, last)
    if not count then return nil end
    local name, quality, icon = metadata(link)
    return {kind = "item", link = link, name = name, quality = quality, icon = icon, quantity = count}
end

function LootReceipts.New(db, callbacks)
    return setmetatable({db = db, callbacks = callbacks or {}, received = {}, sequence = 0}, LootReceipts)
end

function LootReceipts:Now()
    return self.callbacks.now and self.callbacks.now() or (GetTime and GetTime() or 0)
end

function LootReceipts:Timestamp()
    return self.callbacks.time and self.callbacks.time() or (time and time() or 0)
end

function LootReceipts:RecordSlot(slot, options)
    if type(slot) ~= "table" or not itemPayload(slot.link) or not quantity(slot.quantity)
        or (slot.kind ~= nil and slot.kind ~= "item") then return nil end
    options = type(options) == "table" and options or {}
    local source = options.sourceGUID
    if type(source) ~= "string" or source == "" then
        self.sequence = self.sequence + 1
        source = "receipt:" .. tostring(self:Timestamp()) .. ":" .. tostring(self.db.nextID) .. ":" .. self.sequence
    end
    local origin = options.origin == "disenchant" and "disenchant" or "drop"
    local key = origin .. ":" .. string.len(source) .. ":" .. source .. ":" .. itemPayload(slot.link)
    local count = (self.received[key] or 0) + slot.quantity
    self.received[key] = count
    -- A multi-source loot window cannot assign each receipt to a corpse. Its
    -- already-observed total supplies credits; only the received excess is new.
    local observed = tonumber(options.observedQuantity) or 0
    if observed ~= observed or observed < 0 or observed - observed ~= 0 then observed = 0 end
    observed = floor(observed)
    local outstanding = count - observed
    if outstanding <= 0 then return 0 end
    local observation = {}
    for field, value in pairs(slot) do observation[field] = value end
    observation.kind, observation.origin = "item", origin
    observation.sourceGUID, observation.sources = source, nil
    observation.sourceLabel = options.sourceLabel or (origin == "disenchant" and "Disenchant" or "Received loot")
    observation.quantity = outstanding
    local first = getn(self.db.entries) + 1
    local added = ns.Core.AddSnapshot(self.db, {observation}, self:Timestamp(), self:Now())
    if added > 0 and self.callbacks.onAdded then self.callbacks.onAdded(first, added) end
    return added
end

function LootReceipts:Record(message, options)
    local slot = LootReceipts.Parse(message)
    if not slot then return nil end
    return self:RecordSlot(slot, options), slot
end

function LootReceipts:Reset()
    self.received = {}
end
