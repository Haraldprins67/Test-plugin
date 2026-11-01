-- Optional vendor-price providers and epic-drop notices; Lua 5.0 compatible.
ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local Value = {}
ns.Value = Value

local floor, max, min = math.floor, math.max, math.min
local mod = math.mod or math.fmod
local getn = table.getn

local function finite(value)
    return type(value) == "number" and value == value and value - value == 0
end

local function copper(value)
    if finite(value) and value >= 0 and floor(value) == value then return value end
    return nil
end

local function itemID(value)
    if type(value) == "number" then
        if finite(value) and value > 0 and floor(value) == value then return value end
    elseif type(value) == "string" then
        local first, last, captured = string.find(value, "item:(%d+)")
        local id = tonumber(captured or value)
        if finite(id) and id > 0 and floor(id) == id then return id end
    end
    return nil
end

local function ensureData(db)
    if type(db) ~= "table" then return nil end
    db.vendorPrices = type(db.vendorPrices) == "table" and db.vendorPrices or {}
    db.vendorOverrides = type(db.vendorOverrides) == "table" and db.vendorOverrides or {}
    db.vendorPriceSources = type(db.vendorPriceSources) == "table" and db.vendorPriceSources or {}
    if db.vendorSchema ~= 2 then
        -- Version 1.3 mixed user-entered and automatically cached values.
        -- Without provenance, preserve a saved value as a manual override
        -- rather than silently replacing a price the user may have chosen.
        for key, amount in pairs(db.vendorPrices) do
            local id, price = itemID(key), copper(amount)
            local source = db.vendorPriceSources[key]
            if id and price ~= nil and (source == nil or source == "saved" or source == "manual") then
                if db.vendorOverrides[id] == nil then db.vendorOverrides[id] = price end
                db.vendorPriceSources[id] = "manual"
            end
        end
        db.vendorSchema = 2
    end
    db.alerts = type(db.alerts) == "table" and db.alerts or {}
    if db.alerts.epic == nil then db.alerts.epic = true end
    if db.alerts.sound == nil then db.alerts.sound = false end
    db.alerts.epic = db.alerts.epic == true
    db.alerts.sound = db.alerts.sound == true
    return db
end

function Value.Initialize(db)
    db = ensureData(db) or ensureData({})
    -- Existing history is a baseline, never a fresh-drop notification batch.
    for _, entry in ipairs(db.entries or {}) do
        if type(entry) == "table" and entry.kind == "item" and entry.quality == 4
            and entry.origin ~= "disenchant" then
            entry.epicNotified = true
        end
    end
    return db
end

function Value.SetPrice(db, linkOrID, amount)
    db = ensureData(db)
    local id, price = itemID(linkOrID), copper(amount)
    if not db or not id or price == nil then return false end
    db.vendorOverrides[id] = price
    db.vendorPrices[id] = price
    db.vendorPriceSources[id] = "manual"
    return true
end

function Value.ClearPrice(db, linkOrID)
    db = ensureData(db)
    local id = itemID(linkOrID)
    if not db or not id then return false end
    db.vendorOverrides[id] = nil
    db.vendorOverrides[tostring(id)] = nil
    db.vendorPrices[id] = nil
    db.vendorPrices[tostring(id)] = nil
    db.vendorPriceSources[id] = nil
    db.vendorPriceSources[tostring(id)] = nil
    return true
end

function Value.RefreshPrices(db)
    db = ensureData(db)
    if not db then return end
    for key in pairs(db.vendorPrices) do
        local id = itemID(key)
        local manual = id and (copper(db.vendorOverrides[id]) or copper(db.vendorOverrides[tostring(id)]))
        if manual == nil then
            db.vendorPrices[key] = nil
            db.vendorPriceSources[key] = nil
        end
    end
end

function Value.ProviderName()
    if type(SellValues) == "table" then return "SellValue" end
    if type(GetSellValue) == "function" then return "GetSellValue" end
    return nil
end

local function sellValuePrice(id)
    if type(SellValues) ~= "table" then return nil end
    -- CapnBry/Greenman/Improved SellValue uses SellValues["item:2589"].
    -- Its merchant scan divides stack money by stackCount before saving, so
    -- this is already the copper price of ONE item. Never multiply it here.
    local price = copper(SellValues["item:" .. tostring(id)])
    -- Numeric keys are accepted for compatible forks of the same database.
    if price == nil then price = copper(SellValues[id]) end
    if price == nil then price = copper(SellValues[tostring(id)]) end
    return price
end

function Value.GetUnitPrice(db, linkOrID)
    db = ensureData(db)
    local id = itemID(linkOrID)
    if not id then return nil end
    if db then
        local manual = copper(db.vendorOverrides[id])
        if manual == nil then manual = copper(db.vendorOverrides[tostring(id)]) end
        if manual ~= nil then return manual, "manual" end
    end

    -- Check the live SellValue table before automatic caches. Custom-server
    -- prices can change when SellValue learns them at a merchant, and the
    -- provider may also load after this addon has already cached a price.
    local price = sellValuePrice(id)
    if price ~= nil then
        if db then
            db.vendorPrices[id] = price
            db.vendorPriceSources[id] = "SellValue"
        end
        return price, "SellValue"
    end

    if db then
        local cached = copper(db.vendorPrices[id])
        if cached == nil then cached = copper(db.vendorPrices[tostring(id)]) end
        if cached ~= nil then
            return cached, db.vendorPriceSources[id] or db.vendorPriceSources[tostring(id)] or "saved"
        end
    end

    local source
    if type(GetItemInfo) == "function" then
        -- Vanilla normally has no sell-price return. Use it only when a
        -- client extension (or newer client) actually supplies return 11.
        local ok, name, link, quality, level, required, class, subclass,
            stackSize, equipSlot, icon, sellPrice = pcall(GetItemInfo, id)
        if ok then price = copper(sellPrice) end
        if price ~= nil then source = "client" end
    end
    if price == nil and type(GetSellValue) == "function" then
        -- Optional Vanilla price-library API; no dependency is required.
        local ok, sellPrice = pcall(GetSellValue, id)
        if ok then price = copper(sellPrice) end
        if price ~= nil then source = "library" end
    end
    if price ~= nil and db then
        db.vendorPrices[id] = price
        db.vendorPriceSources[id] = source
    end
    return price, source
end

function Value.FormatMoney(amount)
    amount = copper(amount)
    if amount == nil then return "Unknown" end
    local gold = floor(amount / 10000)
    local silver = mod(floor(amount / 100), 100)
    local coins = mod(amount, 100)
    if gold > 0 then return string.format("%dg %ds %dc", gold, silver, coins) end
    if silver > 0 then return string.format("%ds %dc", silver, coins) end
    return string.format("%dc", coins)
end

local function remainingQuantity(entry)
    local quantity = finite(entry.quantity) and max(0, floor(entry.quantity)) or 0
    if entry.origin ~= "disenchant" and not entry.isMaterial then
        local destroyed = finite(entry.disenchanted) and max(0, floor(entry.disenchanted)) or 0
        quantity = quantity - min(quantity, destroyed)
    end
    return quantity
end

function Value.GetEntryVendorValue(db, entry)
    if type(entry) ~= "table" or (entry.kind and entry.kind ~= "item") then return nil, 0 end
    local quantity = remainingQuantity(entry)
    if quantity == 0 then return 0, 0 end
    local price = Value.GetUnitPrice(db, entry.link or entry.key)
    if price == nil then return nil, quantity end
    return quantity * price, 0
end

function Value.GetEntryVendorText(db, entry)
    if type(entry) ~= "table" or (entry.kind and entry.kind ~= "item") then return "-" end
    local amount = Value.GetEntryVendorValue(db, entry)
    return Value.FormatMoney(amount)
end

function Value.GetTotals(db)
    local total = { knownCopper = 0, unknownUnits = 0 }
    for _, entry in ipairs(type(db) == "table" and db.entries or {}) do
        local amount, unknown = Value.GetEntryVendorValue(db, entry)
        if amount ~= nil then total.knownCopper = total.knownCopper + amount end
        total.unknownUnits = total.unknownUnits + unknown
    end
    return total
end

local function splitLines(text)
    local lines, start = {}, 1
    while true do
        local first, last = string.find(text, "\n", start, true)
        if not first then
            lines[getn(lines) + 1] = string.sub(text, start)
            return lines
        end
        lines[getn(lines) + 1] = string.sub(text, start, first - 1)
        start = last + 1
    end
end

function Value.AppendExportColumns(db, baseTSV)
    if type(baseTSV) ~= "string" then return "" end
    local lines = splitLines(baseTSV)
    lines[1] = lines[1] .. "\tUnit vendor (copper)\tRemaining vendor (copper)\tRemaining quantity"
    for index = 2, getn(lines) do
        local entry = type(db) == "table" and type(db.entries) == "table" and db.entries[index - 1]
        local unit, amount, quantity = "-", "-", "-"
        if type(entry) == "table" and (not entry.kind or entry.kind == "item") then
            local price = Value.GetUnitPrice(db, entry.link or entry.key)
            local total = Value.GetEntryVendorValue(db, entry)
            unit = price ~= nil and tostring(price) or "Unknown"
            amount = total ~= nil and tostring(total) or "Unknown"
            quantity = tostring(remainingQuantity(entry))
        end
        lines[index] = lines[index] .. "\t" .. unit .. "\t" .. amount .. "\t" .. quantity
    end
    return table.concat(lines, "\n")
end

function Value.AppendSummary(db, baseSummary)
    local totals = Value.GetTotals(db)
    return (type(baseSummary) == "string" and baseSummary or "")
        .. "\n\nVendor estimate\tValue"
        .. "\nKnown remaining vendor value (copper)\t" .. tostring(totals.knownCopper)
        .. "\nKnown remaining vendor value\t" .. Value.FormatMoney(totals.knownCopper)
        .. "\nRemaining item units with unknown vendor price\t" .. tostring(totals.unknownUnits)
        .. "\nBasis\tObserved item quantities minus disenchanted originals, plus disenchant materials; not current inventory."
end

local function notify(message, entry, callbacks)
    if callbacks and type(callbacks.notify) == "function" then
        callbacks.notify(message, entry)
    else
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage(message, 0.64, 0.21, 0.93)
        end
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("|cffa335ee" .. message .. "|r")
        end
    end
end

function Value.NotifyEntries(db, firstIndex, callbacks)
    db = ensureData(db)
    if not db or type(db.entries) ~= "table" then return 0 end
    -- Omitting a boundary must never replay the entire saved history.
    local index = finite(firstIndex) and max(1, floor(firstIndex)) or getn(db.entries) + 1
    local count = 0
    while index <= getn(db.entries) do
        local entry = db.entries[index]
        if type(entry) == "table" and entry.kind == "item" and entry.quality == 4
            and entry.origin ~= "disenchant" and not entry.epicNotified then
            -- Stored on the entry object, rather than its resettable numeric
            -- ID, so reset/new sessions can notify item #1 again.
            entry.epicNotified = true
            if db.alerts.epic then
                local item = entry.link and entry.link ~= "" and entry.link or entry.name or "Unknown epic item"
                local quantity = finite(entry.quantity) and max(0, floor(entry.quantity)) or 0
                local message = "EPIC LOOT: " .. item .. " x" .. tostring(quantity)
                notify(message, entry, callbacks)
                if db.alerts.sound then
                    if callbacks and type(callbacks.sound) == "function" then callbacks.sound(entry)
                    elseif type(PlaySound) == "function" then pcall(PlaySound, "RaidWarning") end
                end
                count = count + 1
            end
        end
        index = index + 1
    end
    return count
end
