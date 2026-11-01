-- Passive, evidence-based vendor transactions; Lua 5.0 compatible.
ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local Merchant = {}
Merchant.__index = Merchant
ns.Merchant = Merchant

local getn = table.getn
local WAIT_SECONDS = 2
local hooks = {}

Merchant.Events = {"MERCHANT_SHOW", "MERCHANT_CLOSED", "PLAYER_MONEY", "BAG_UPDATE", "BAG_UPDATE_DELAYED"}

local function number(value)
    return type(value) == "number" and value == value and value - value == 0
end

local function nonnegative(value)
    return number(value) and value >= 0 and math.floor(value) == value
end

local function itemKey(link)
    if type(link) ~= "string" then return nil end
    local first, last, id = string.find(link, "item:(%d+)")
    return id
end

local function itemName(link)
    if type(link) ~= "string" then return "Unknown item" end
    local first, last, name = string.find(link, "%[([^%]]+)%]")
    return name or link
end

function Merchant.Initialize(db)
    db.finance = type(db.finance) == "table" and db.finance or {}
    local data = db.finance
    data.salesCopper = nonnegative(data.salesCopper) and data.salesCopper or 0
    data.buybackCopper = nonnegative(data.buybackCopper) and data.buybackCopper or 0
    data.sales = type(data.sales) == "table" and data.sales or {}
    data.buybacks = type(data.buybacks) == "table" and data.buybacks or {}
    data.unconfirmed = type(data.unconfirmed) == "table" and data.unconfirmed or {}
    return data
end

local function bagItem(bag, slot)
    local api = C_Container or {}
    local getLink = api.GetContainerItemLink or GetContainerItemLink
    local getInfo = api.GetContainerItemInfo or GetContainerItemInfo
    if type(getLink) ~= "function" or type(getInfo) ~= "function" then return nil end
    local link = getLink(bag, slot)
    local info, legacyCount = getInfo(bag, slot)
    local count
    if type(info) == "table" then
        link, count = link or info.hyperlink, info.stackCount
    else count = legacyCount end
    local id = itemKey(link)
    if not id or not number(count) or count <= 0 then return nil end
    return {key = id, link = link, name = itemName(link), quantity = math.floor(count)}
end

function Merchant.SnapshotBags()
    if ns.Tracker and type(ns.Tracker.SnapshotBags) == "function" then
        return ns.Tracker.SnapshotBags()
    end
    local api = C_Container or {}
    local slots = api.GetContainerNumSlots or GetContainerNumSlots
    if type(slots) ~= "function" then return nil end
    local result = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local size = slots(bag)
        if not number(size) then return nil end
        for index = 1, size do
            local item = bagItem(bag, index)
            if item then
                local row = result[item.key] or {link = item.link, quantity = 0}
                row.quantity = row.quantity + item.quantity
                result[item.key] = row
            end
        end
    end
    return result
end

local function money()
    if type(GetMoney) ~= "function" then return nil end
    local value = GetMoney()
    return nonnegative(value) and value or nil
end

local function buybackItem(index)
    if type(GetBuybackItemInfo) ~= "function" then return nil end
    local name, texture, price, quantity = GetBuybackItemInfo(index)
    if not name or not nonnegative(price) or not number(quantity) or quantity <= 0 then return nil end
    local link = type(GetBuybackItemLink) == "function" and GetBuybackItemLink(index) or nil
    return {key = itemKey(link), link = link, name = name, copper = price,
        quantity = math.floor(quantity), index = index}
end

local function buybacks()
    if type(GetNumBuybackItems) ~= "function" or type(GetBuybackItemInfo) ~= "function" then return nil end
    local result = {}
    for index = 1, GetNumBuybackItems() or 0 do
        local row = buybackItem(index)
        if row then result[getn(result) + 1] = row end
    end
    return result
end

local function signature(row)
    return tostring(row.key or ("name:" .. row.name)) .. ":" .. row.quantity .. ":" .. row.copper
end

local function differences(before, after)
    local counts, result = {}, {}
    for _, row in ipairs(before or {}) do
        local key = signature(row)
        counts[key] = (counts[key] or 0) + 1
    end
    for _, row in ipairs(after or {}) do
        local key = signature(row)
        if (counts[key] or 0) > 0 then counts[key] = counts[key] - 1
        else result[getn(result) + 1] = row end
    end
    return result
end

function Merchant.New(db, callbacks)
    Merchant.Initialize(db)
    return setmetatable({db = db, callbacks = callbacks or {}, open = false, token = 0}, Merchant)
end

function Merchant:Now()
    return self.callbacks.now and self.callbacks.now() or (GetTime and GetTime() or 0)
end

function Merchant:Timestamp()
    return self.callbacks.time and self.callbacks.time() or (time and time() or 0)
end

function Merchant:Data()
    return Merchant.Initialize(self.db)
end

function Merchant:Changed()
    if self.callbacks.onChange then self.callbacks.onChange() end
end

function Merchant:IsOpen()
    if MerchantFrame and MerchantFrame.IsShown then return MerchantFrame:IsShown() end
    return self.open
end

function Merchant:Schedule(delay, force)
    if not self.pending or self.scheduled then return end
    if not ns.Compat or type(ns.Compat.After) ~= "function" then return end
    self.scheduled = true
    local token = self.token
    ns.Compat.After(delay or 0.2, function()
        if self.token ~= token then return end
        self.scheduled = false
        if not self.pending then return end
        self:Reconcile(force)
        if self.pending then self:Schedule(0.2, false) end
    end)
end

function Merchant:StartPending(kind)
    if self.pending then
        self:Reconcile(false)
        if self.pending and self.pending.kind ~= kind then self:Reconcile(true) end
    end
    if not self.pending then
        local inventory, balance = Merchant.SnapshotBags(), money()
        if not inventory or balance == nil then return nil end
        self.pending = {kind = kind, bags = inventory, money = balance,
            buybacks = buybacks(), intents = {}, startedAt = self:Now()}
    end
    return self.pending
end

function Merchant:ObserveSale(bag, slot)
    if not self:IsOpen() then return end
    if type(CursorHasItem) == "function" and CursorHasItem() then return end
    if type(SpellIsTargeting) == "function" and SpellIsTargeting() then return end
    local item = bagItem(bag, slot)
    if not item then return end
    local pending = self:StartPending("sale")
    if not pending then return end
    local last = pending.intents[getn(pending.intents)]
    local currentMoney = money()
    -- A global wrapper may call the C_Container wrapper. That is one action.
    if last and last.bag == bag and last.slot == slot and last.key == item.key
        and last.quantity == item.quantity and last.observedMoney == currentMoney then return end
    item.bag, item.slot, item.observedMoney = bag, slot, currentMoney
    if ns.Value and ns.Value.GetUnitPrice then item.unitPrice = ns.Value.GetUnitPrice(self.db, item.link) end
    pending.intents[getn(pending.intents) + 1] = item
    self:Schedule(0.2, false)
end

function Merchant:ObserveBuyback(index)
    if not self:IsOpen() then return end
    local item = buybackItem(index)
    if not item or not item.key then return end
    local pending = self:StartPending("buyback")
    if not pending then return end
    pending.intents[getn(pending.intents) + 1] = item
    self:Schedule(0.2, false)
end

function Merchant:ObservePickup(bag, slot, splitQuantity)
    if not self:IsOpen() then self.cursor = nil; return end
    if type(CursorHasItem) == "function" and CursorHasItem() then
        -- Placing or swapping an existing cursor item is not a sale intent.
        self.cursor = nil
        return
    end
    local item = bagItem(bag, slot)
    if not item then self.cursor = nil; return end
    local available = item.quantity
    local quantity = splitQuantity and tonumber(splitQuantity) or item.quantity
    if not number(quantity) or quantity <= 0 then return end
    quantity = math.min(item.quantity, math.floor(quantity))
    -- Global and namespaced container wrappers can call one another.
    if self.cursor and self.cursor.bag == bag and self.cursor.slot == slot
        and self.cursor.available == item.quantity and self.cursor.quantity == quantity
        and self.cursor.money == money() then return end
    if self.pending then
        self:Reconcile(false)
        if self.pending then self:Reconcile(true) end
    end
    local inventory, balance = Merchant.SnapshotBags(), money()
    if not inventory or balance == nil then self.cursor = nil; return end
    item.quantity = quantity
    if ns.Value and ns.Value.GetUnitPrice then item.unitPrice = ns.Value.GetUnitPrice(self.db, item.link) end
    self.cursor = {bag = bag, slot = slot, available = available,
        quantity = quantity, item = item, bags = inventory, money = balance,
        buybacks = buybacks(), startedAt = self:Now()}
end

function Merchant:ObserveCursorSale()
    local cursor = self.cursor
    self.cursor = nil
    if not cursor or not self:IsOpen() then return end
    if type(CursorHasItem) == "function" and not CursorHasItem() then return end
    if self.pending then
        self:Reconcile(false)
        if self.pending then self:Reconcile(true) end
    end
    self.pending = {kind = "sale", bags = cursor.bags, money = cursor.money,
        buybacks = cursor.buybacks, intents = {cursor.item}, startedAt = self:Now()}
    self:Schedule(0.2, false)
end

local function aggregate(intents)
    local byKey, ordered = {}, {}
    for _, item in ipairs(intents) do
        local row = byKey[item.key]
        if not row then
            row = {key = item.key, link = item.link, name = item.name,
                quantity = 0, expected = 0, known = true}
            byKey[item.key], ordered[getn(ordered) + 1] = row, row
        end
        row.quantity = row.quantity + item.quantity
        local expected = item.copper
        if expected == nil and item.unitPrice ~= nil then expected = item.unitPrice * item.quantity end
        if nonnegative(expected) then row.expected = row.expected + expected
        else row.known = false end
    end
    return byKey, ordered
end

function Merchant:Unconfirmed(item, kind, reason, quantity)
    local data = self:Data()
    data.unconfirmed[getn(data.unconfirmed) + 1] = {
        timestamp = self:Timestamp(), kind = kind, link = item.link, name = item.name,
        quantity = quantity or item.quantity, reason = reason,
    }
end

function Merchant:Record(item, kind, quantity, amount, source)
    local data = self:Data()
    local key = kind == "sale" and "sales" or "buybacks"
    local total = kind == "sale" and "salesCopper" or "buybackCopper"
    data[total] = data[total] + amount
    data[key][getn(data[key]) + 1] = {timestamp = self:Timestamp(),
        link = item.link, name = item.name, quantity = quantity, copper = amount, source = source}
end

function Merchant:Reconcile(force)
    local pending = self.pending
    if not pending then return false end
    local after, balance = Merchant.SnapshotBags(), money()
    local expired = force or self:Now() - pending.startedAt >= WAIT_SECONDS
    if not after or balance == nil then
        if not expired then return false end
        for _, item in ipairs(pending.intents) do self:Unconfirmed(item, pending.kind, "missing_inventory_or_money") end
        self.pending = nil
        self:Changed()
        return false
    end
    local byKey, ordered = aggregate(pending.intents)
    local fresh = pending.kind == "sale" and differences(pending.buybacks, buybacks())
        or differences(buybacks(), pending.buybacks)
    local evidence = {}
    for _, row in ipairs(fresh) do
        local id = row.key
        if not id then
            for candidate, item in pairs(byKey) do
                if item.name == row.name then
                    if id then id = nil; break end
                    id = candidate
                end
            end
        end
        if id and byKey[id] then
            local sums = evidence[id] or {quantity = 0, copper = 0}
            sums.quantity, sums.copper = sums.quantity + row.quantity, sums.copper + row.copper
            evidence[id] = sums
        end
    end
    local decisions, complete, expectedTotal, allKnown = {}, true, 0, true
    for _, item in ipairs(ordered) do
        local old = pending.bags[item.key] and pending.bags[item.key].quantity or 0
        local current = after[item.key] and after[item.key].quantity or 0
        local changed = pending.kind == "sale" and old - current or current - old
        changed = math.max(0, changed)
        local quantity = math.min(changed, item.quantity)
        local proof = evidence[item.key]
        local decision = {item = item, quantity = quantity}
        if changed > item.quantity then
            decision.reason = "conflicting_inventory_change"
        elseif quantity > 0 and proof and proof.quantity == quantity then
            if pending.kind == "sale" or balance - pending.money <= -proof.copper then
                decision.copper, decision.source = proof.copper, "buyback_record"
            end
        end
        if quantity == 0 or quantity ~= item.quantity then complete = false end
        if decision.copper == nil then
            if item.known and quantity > 0 and quantity == item.quantity and not decision.reason then
                decision.expected = item.expected
            else allKnown = false end
        end
        expectedTotal = expectedTotal + (decision.copper or decision.expected or 0)
        decisions[getn(decisions) + 1] = decision
    end
    local delta = balance - pending.money
    local sign = pending.kind == "sale" and 1 or -1
    local exactMoney = allKnown and expectedTotal > 0 and expectedTotal * sign == delta
    local allConfirmed = complete
    for _, decision in ipairs(decisions) do
        if decision.copper == nil and decision.expected ~= nil and exactMoney then
            decision.copper, decision.source = decision.expected, "matched_money_and_price"
        end
        if decision.copper == nil then allConfirmed = false end
    end
    if not expired and not allConfirmed then return false end
    self.pending = nil
    for _, decision in ipairs(decisions) do
        if decision.copper ~= nil then
            self:Record(decision.item, pending.kind, decision.quantity, decision.copper, decision.source)
        else
            self:Unconfirmed(decision.item, pending.kind, decision.reason or
                (decision.quantity == 0 and "sale_not_observed" or "unmatched_money_or_price"))
        end
    end
    self:Changed()
    return allConfirmed
end

function Merchant:InstallHooks()
    Merchant.active = self
    local function observe(method, a, b, c)
        local active = Merchant.active
        if active then
            -- A passive accounting failure must never prevent the player's
            -- original merchant action from executing.
            local ok = pcall(active[method], active, a, b, c)
            if not ok then active.lastError = "observer_failed" end
        end
    end
    local function wrapUse(original)
        return function(bag, slot, onSelf)
            observe("ObserveSale", bag, slot)
            if onSelf ~= nil then return original(bag, slot, onSelf) end
            return original(bag, slot)
        end
    end
    if type(UseContainerItem) == "function" and UseContainerItem ~= hooks.use then
        hooks.use = wrapUse(UseContainerItem)
        UseContainerItem = hooks.use
    end
    if C_Container and type(C_Container.UseContainerItem) == "function" and C_Container.UseContainerItem ~= hooks.container then
        hooks.container = wrapUse(C_Container.UseContainerItem)
        C_Container.UseContainerItem = hooks.container
    end
    if type(BuybackItem) == "function" and BuybackItem ~= hooks.buyback then
        local original = BuybackItem
        hooks.buyback = function(index)
            observe("ObserveBuyback", index)
            return original(index)
        end
        BuybackItem = hooks.buyback
    end
    local function wrapPickup(original, split)
        if split then
            return function(bag, slot, quantity)
                observe("ObservePickup", bag, slot, quantity)
                return original(bag, slot, quantity)
            end
        end
        return function(bag, slot)
            observe("ObservePickup", bag, slot)
            return original(bag, slot)
        end
    end
    if type(PickupContainerItem) == "function" and PickupContainerItem ~= hooks.pickup then
        hooks.pickup = wrapPickup(PickupContainerItem, false)
        PickupContainerItem = hooks.pickup
    end
    if type(SplitContainerItem) == "function" and SplitContainerItem ~= hooks.split then
        hooks.split = wrapPickup(SplitContainerItem, true)
        SplitContainerItem = hooks.split
    end
    if C_Container then
        if type(C_Container.PickupContainerItem) == "function" and C_Container.PickupContainerItem ~= hooks.containerPickup then
            hooks.containerPickup = wrapPickup(C_Container.PickupContainerItem, false)
            C_Container.PickupContainerItem = hooks.containerPickup
        end
        if type(C_Container.SplitContainerItem) == "function" and C_Container.SplitContainerItem ~= hooks.containerSplit then
            hooks.containerSplit = wrapPickup(C_Container.SplitContainerItem, true)
            C_Container.SplitContainerItem = hooks.containerSplit
        end
    end
    if type(PickupMerchantItem) == "function" and PickupMerchantItem ~= hooks.merchantPickup then
        local original = PickupMerchantItem
        hooks.merchantPickup = function(index)
            -- Vanilla MerchantFrame.xml uses this exact call to sell the
            -- cursor. Other indices are ordinary merchant item interactions.
            if index == 0 then observe("ObserveCursorSale") end
            return original(index)
        end
        PickupMerchantItem = hooks.merchantPickup
    end
    if type(SellCursorItem) == "function" and SellCursorItem ~= hooks.sellCursor then
        local original = SellCursorItem
        hooks.sellCursor = function()
            observe("ObserveCursorSale")
            return original()
        end
        SellCursorItem = hooks.sellCursor
    end
    if type(ClearCursor) == "function" and ClearCursor ~= hooks.clear then
        local original = ClearCursor
        hooks.clear = function()
            if Merchant.active then Merchant.active.cursor = nil end
            return original()
        end
        ClearCursor = hooks.clear
    end
    if type(DeleteCursorItem) == "function" and DeleteCursorItem ~= hooks.delete then
        local original = DeleteCursorItem
        hooks.delete = function()
            if Merchant.active then Merchant.active.cursor = nil end
            return original()
        end
        DeleteCursorItem = hooks.delete
    end
end

function Merchant:HandleEvent(event)
    if event == "MERCHANT_SHOW" then
        self.open = true
        self:InstallHooks()
    elseif event == "MERCHANT_CLOSED" then
        self.open = false
        self.cursor = nil
        -- The last bag/money event can arrive after the merchant closes.
        self:Schedule(0.05, false)
    elseif event == "PLAYER_MONEY" or event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
        self:Schedule(0.2, false)
    end
end

function Merchant:Reset()
    self.token = self.token + 1
    self.pending, self.scheduled = nil, false
    self.cursor = nil
    self.db.finance = {salesCopper = 0, buybackCopper = 0, sales = {}, buybacks = {}, unconfirmed = {}}
    self:Changed()
end
