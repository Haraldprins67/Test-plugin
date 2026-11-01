-- Count money actually received as loot, including the player's group share.
-- Corpse totals and wallet changes are deliberately not receipts. Lua 5.0.
ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local Money = {}
Money.__index = Money
ns.Money = Money
Money.Events = {"CHAT_MSG_MONEY"}

local getn, floor = table.getn, math.floor

local function integer(value)
    return type(value) == "number" and value == value and value - value == 0
        and value >= 0 and floor(value) or 0
end

function Money.Initialize(db)
    if type(db) ~= "table" then return nil end
    local data = type(db.lootMoney) == "table" and db.lootMoney or {}
    db.lootMoney = data
    data.copper = integer(data.copper)
    data.sharedCopper = math.min(data.copper, integer(data.sharedCopper))
    data.receipts = integer(data.receipts)
    data.version = 1
    return data
end

function Money.Total(db)
    local data = Money.Initialize(db)
    return data and data.copper or 0
end

function Money.Reset(target)
    local tracker = getmetatable(target) == Money and target or nil
    local db = tracker and tracker.db or target
    if type(db) == "table" then
        db.lootMoney = {copper = 0, sharedCopper = 0, receipts = 0, version = 1}
    end
    if tracker and tracker.callbacks.onChange then tracker.callbacks.onChange() end
end

function Money.Format(amount)
    if ns.Finance and ns.Finance.FormatMoneyAlways then return ns.Finance.FormatMoneyAlways(amount) end
    amount = integer(amount)
    return string.format("%dg %ds %dc", floor(amount / 10000), math.mod(floor(amount / 100), 100), math.mod(amount, 100))
end

local function plain(value)
    value = string.gsub(value, "|c%x%x%x%x%x%x%x%x", "")
    return (string.gsub(value, "|r", ""))
end

-- Only one substitution is meaningful for money: %s in a receipt, %d in
-- a denomination. Positional %1$s / %1$d templates are supported as well.
local function pattern(format, expected, complete)
    if type(format) ~= "string" or format == "" then return nil end
    local parts, position, substitutions = {"^"}, 1, 0
    while position <= string.len(format) do
        local character = string.sub(format, position, position)
        if character == "%" then
            local _, last, explicit, kind = string.find(string.sub(format, position), "^%%(%d+)%$([sd])")
            if last then
                if tonumber(explicit) ~= 1 then return nil end
                position = position + last
            else
                kind = string.sub(format, position + 1, position + 1)
                position = position + 2
            end
            if kind == "%" then parts[getn(parts) + 1] = "%%"
            elseif kind == expected then
                substitutions = substitutions + 1
                parts[getn(parts) + 1] = kind == "d" and "(%d+)" or "(.-)"
            else return nil end
        elseif character == " " then
            parts[getn(parts) + 1] = "%s*"
            position = position + 1
        else
            if string.find("^$().[]*+-?", character, 1, true) then character = "%" .. character end
            parts[getn(parts) + 1] = character
            position = position + 1
        end
    end
    if substitutions ~= 1 then return nil end
    if complete then parts[getn(parts) + 1] = "$" end
    return table.concat(parts)
end

local function capture(message, format)
    local expression = pattern(format, "s", true)
    if not expression then return nil end
    local _, _, amount = string.find(message, expression)
    if amount then return amount end
    -- Stock Vanilla omits the full stop from YOU_LOOT_MONEY while some
    -- compatible clients append one to the chat event itself.
    if string.sub(message, -1) == "." then
        _, _, amount = string.find(string.sub(message, 1, -2), expression)
    end
    return amount
end

local denominations = {
    {amount = "GOLD_AMOUNT", word = "GOLD", fallback = "gold", copper = 10000, short = "g"},
    {amount = "SILVER_AMOUNT", word = "SILVER", fallback = "silver", copper = 100, short = "s"},
    {amount = "COPPER_AMOUNT", word = "COPPER", fallback = "copper", copper = 1, short = "c"},
}

function Money.ParseAmount(value)
    if type(value) ~= "string" then return nil end
    value = string.lower(plain(value))
    -- Patched/newer clients may render money with inline coin textures.
    for _, denomination in ipairs(denominations) do
        value = string.gsub(value, "|t[^|]-ui%-" .. denomination.fallback .. "icon[^|]-|t", " " .. denomination.fallback)
    end
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    value = string.gsub(value, "%.$", "")
    local total, seen, matched = 0, {}, false
    while value ~= "" do
        local consumed, amount, denominationIndex
        for index, denomination in ipairs(denominations) do
            local formats = {}
            local localizedAmount = _G[denomination.amount]
            if type(localizedAmount) == "string" then formats[getn(formats) + 1] = plain(localizedAmount) end
            local localizedWord = _G[denomination.word]
            if type(localizedWord) == "string" and localizedWord ~= "" then
                formats[getn(formats) + 1] = "%d " .. plain(localizedWord)
            end
            formats[getn(formats) + 1] = "%d " .. denomination.fallback
            formats[getn(formats) + 1] = "%d " .. denomination.short
            for _, format in ipairs(formats) do
                local expression = pattern(string.lower(format), "d", false)
                local first, last, number
                if expression then first, last, number = string.find(value, expression) end
                if first then
                    consumed, amount, denominationIndex = last, tonumber(number), index
                    break
                end
            end
            if consumed then break end
        end
        if not consumed or seen[denominationIndex] or not amount or amount > 900000000000 then return nil end
        seen[denominationIndex], matched = true, true
        total = total + amount * denominations[denominationIndex].copper
        if total > 9007199254740991 then return nil end
        value = string.sub(value, consumed + 1)
        if value ~= "" then
            -- The entire amount must be composed of denominations and their
            -- separators. A decimal, negative sign or extra sentence is invalid.
            local first, last = string.find(value, "^%s*,?%s*")
            if not first or last == 0 then return nil end
            value = string.sub(value, last + 1)
            if value == "" then return nil end
        end
    end
    return matched and total or nil
end

function Money.ParseReceipt(message)
    if type(message) ~= "string" then return nil end
    message = plain(message)
    local split = capture(message, LOOT_MONEY_SPLIT) or capture(message, "Your share of the loot is %s.")
    if split then return Money.ParseAmount(split), true end
    local personal = capture(message, LOOT_MONEY_SELF) or capture(message, YOU_LOOT_MONEY)
        or capture(message, ERR_AUTOLOOT_MONEY_S) or capture(message, "You loot %s.")
        or capture(message, "You loot %s")
    if personal then return Money.ParseAmount(personal), false end
    return nil
end

function Money.New(db, callbacks)
    Money.Initialize(db)
    return setmetatable({db = db, callbacks = callbacks or {}}, Money)
end

function Money:HandleEvent(eventName, message)
    if eventName ~= "CHAT_MSG_MONEY" then return false end
    local amount, shared = Money.ParseReceipt(message)
    if not amount or amount <= 0 then return false end
    local data = Money.Initialize(self.db)
    if not data then return false end
    data.copper = data.copper + amount
    if shared then data.sharedCopper = data.sharedCopper + amount end
    data.receipts = data.receipts + 1
    if self.callbacks.onChange then self.callbacks.onChange() end
    return true, amount
end

