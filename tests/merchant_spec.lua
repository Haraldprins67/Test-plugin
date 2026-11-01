-- Actual vendor transactions, runnable unchanged by genuine Lua 5.0.
ClassicLootLogNS = {}
local ns = ClassicLootLogNS
local clock, balance, bags, history, prices, timers = 0, 0, {}, {}, {}, {}
local shown, hasCursor, cursor, recordBuyback = false, false, nil, true
local partial, creditOverride, extraCost, suppressMutation = nil, nil, 0, false
local passed = 0

function GetTime() return clock end
function time() return 1700000000 + clock end
function GetMoney() return balance end
NUM_BAG_SLOTS = 4
C_Container = nil
MerchantFrame = {IsShown = function() return shown end}
function CursorHasItem() return hasCursor end
function GetContainerNumSlots() return 4 end
function GetContainerItemLink(bag, slot) local row = bags[bag .. ":" .. slot]; return row and row.link end
function GetContainerItemInfo(bag, slot)
    local row = bags[bag .. ":" .. slot]
    if row then return "icon", row.quantity end
end
function GetNumBuybackItems() return table.getn(history) end
function GetBuybackItemInfo(index)
    local row = history[index]
    if row then return row.name, "icon", row.copper, row.quantity end
end
function GetBuybackItemLink(index) return history[index] and history[index].link end
ns.Compat = {After = function(delay, callback) timers[table.getn(timers) + 1] = {at = clock + delay, callback = callback} end}
ns.Value = {GetUnitPrice = function(db, link)
    local first, last, id = string.find(link, "item:(%d+)")
    return prices[id]
end}
dofile("ClassicLootLog/Merchant.lua")
local Merchant = ns.Merchant

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function item(id, quantity)
    return {link = "|Hitem:" .. id .. ":0:0|h[Item " .. id .. "]|h", name = "Item " .. id,
        key = tostring(id), quantity = quantity}
end

local function put(slot, id, quantity) bags["0:" .. slot] = item(id, quantity) end

local function nativeSell(row, quantity)
    local price = creditOverride or (prices[row.key] or 17) * quantity
    balance = balance + price - extraCost
    if recordBuyback then
        table.insert(history, 1, {key = row.key, link = row.link, name = row.name,
            quantity = quantity, copper = price})
        if table.getn(history) > 12 then table.remove(history, 13) end
    end
end

local function installNatives()
    UseContainerItem = function(bag, slot, onSelf)
        if suppressMutation then return "native", onSelf end
        local key = bag .. ":" .. slot
        local row = bags[key]
        if row then
            local quantity = math.min(partial or row.quantity, row.quantity)
            nativeSell(row, quantity)
            row.quantity = row.quantity - quantity
            if row.quantity == 0 then bags[key] = nil end
        end
        return "native", onSelf
    end
    BuybackItem = function(index)
        local row = history[index]
        if row and not suppressMutation then
            balance = balance - row.copper - extraCost
            bags["0:4"] = item(row.key, row.quantity)
            table.remove(history, index)
        end
        return "buyback native"
    end
    PickupContainerItem = function(bag, slot)
        local key = bag .. ":" .. slot
        if hasCursor then
            bags[key], cursor, hasCursor = cursor, nil, false
        else
            cursor = bags[key]
            bags[key] = nil
            hasCursor = cursor ~= nil
        end
    end
    SplitContainerItem = function(bag, slot, quantity)
        local key = bag .. ":" .. slot
        local row = bags[key]
        if row and not hasCursor then
            quantity = math.min(quantity, row.quantity)
            cursor, hasCursor = item(row.key, quantity), true
            row.quantity = row.quantity - quantity
            if row.quantity == 0 then bags[key] = nil end
        end
    end
    PickupMerchantItem = function(index)
        if index == 0 and cursor then
            nativeSell(cursor, cursor.quantity)
            cursor, hasCursor = nil, false
        end
        return "merchant native"
    end
    SellCursorItem = nil
    ClearCursor = function()
        if cursor then bags["0:1"] = cursor end
        cursor, hasCursor = nil, false
    end
    DeleteCursorItem = function() cursor, hasCursor = nil, false end
end

local function tracker(saved)
    local db = saved or {}
    local observer = Merchant.New(db, {now = GetTime, time = time})
    observer:InstallHooks()
    shown = true
    observer:HandleEvent("MERCHANT_SHOW")
    return observer, db
end

local function flush()
    local iterations = 0
    while table.getn(timers) > 0 do
        iterations = iterations + 1
        assert(iterations < 30, "vendor reconciliation must stop")
        local pending = timers
        timers = {}
        for _, task in ipairs(pending) do
            clock = math.max(clock, task.at)
            task.callback()
        end
    end
end

local function test(name, callback)
    clock, balance, bags, history, prices, timers = 0, 1000, {}, {}, {}, {}
    shown, hasCursor, cursor, recordBuyback = false, false, nil, true
    partial, creditOverride, extraCost, suppressMutation = nil, nil, 0, false
    installNatives()
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

test("right-click stack sale records actual buyback proceeds and preserves native returns", function()
    put(1, 1, 4); prices["1"] = 25
    local observer, db = tracker()
    local first, second = UseContainerItem(0, 1, true)
    equal(first, "native"); equal(second, true)
    observer:HandleEvent("BAG_UPDATE"); observer:HandleEvent("PLAYER_MONEY"); flush()
    equal(db.finance.salesCopper, 100)
    equal(db.finance.sales[1].quantity, 4)
    equal(db.finance.sales[1].source, "buyback_record")
    equal(db.finance.buybackCopper, 0)
    equal(table.getn(db.finance.unconfirmed), 0)
end)

test("fresh buyback evidence confirms unknown price and auto-repair offset without guessing", function()
    put(1, 2, 3); creditOverride, extraCost = 123, 500
    local observer, db = tracker()
    UseContainerItem(0, 1); flush()
    equal(balance, 623)
    equal(db.finance.salesCopper, 123)
    equal(db.finance.sales[1].quantity, 3)
end)

test("known prices require an exact money match when buyback evidence is unavailable", function()
    put(1, 1, 4); prices["1"], recordBuyback = 10, false
    local observer, db = tracker()
    UseContainerItem(0, 1); observer:HandleEvent("PLAYER_MONEY"); flush()
    equal(db.finance.salesCopper, 40)
    equal(db.finance.sales[1].source, "matched_money_and_price")
end)

test("unknown prices or mixed money gains cannot become confirmed vendor income", function()
    put(1, 1, 4); prices["1"], recordBuyback = 10, false
    local observer, db = tracker()
    UseContainerItem(0, 1); balance = balance + 300; flush()
    equal(db.finance.salesCopper, 0)
    equal(table.getn(db.finance.unconfirmed), 1)
    put(1, 2, 2); creditOverride = 80
    UseContainerItem(0, 1); flush()
    equal(db.finance.salesCopper, 0)
    equal(table.getn(db.finance.unconfirmed), 2)
end)

test("unrelated money, deletion and failed item actions never count as vendor sales", function()
    put(1, 1, 3); prices["1"] = 10
    local observer, db = tracker()
    balance = balance + 200; bags["0:1"] = nil
    observer:HandleEvent("PLAYER_MONEY"); observer:HandleEvent("BAG_UPDATE"); flush()
    equal(db.finance.salesCopper, 0)
    put(1, 1, 3); suppressMutation = true
    UseContainerItem(0, 1); flush()
    equal(db.finance.salesCopper, 0)
    equal(table.getn(db.finance.unconfirmed), 1)
end)

test("rapid batched sale intents are reconciled once without counting repairs as lost sales", function()
    put(1, 1, 2); put(2, 2, 3)
    prices["1"], prices["2"] = 10, 20
    local observer, db = tracker()
    -- Real autosell calls may update synchronously before the queued events.
    UseContainerItem(0, 1); UseContainerItem(0, 2); balance = balance - 200
    observer:HandleEvent("PLAYER_MONEY"); observer:HandleEvent("BAG_UPDATE"); flush()
    equal(db.finance.salesCopper, 80)
    equal(table.getn(db.finance.sales), 2)
    observer:HandleEvent("PLAYER_MONEY"); flush()
    equal(db.finance.salesCopper, 80)
end)

test("partial observed sale records only removed units", function()
    put(1, 1, 10); prices["1"], partial = 7, 4
    local observer, db = tracker()
    UseContainerItem(0, 1); flush()
    equal(db.finance.salesCopper, 28)
    equal(db.finance.sales[1].quantity, 4)
    equal(bags["0:1"].quantity, 6)
end)

test("buying an item back records the actual debit separately from gross sale income", function()
    put(1, 1, 5); prices["1"] = 10
    local observer, db = tracker()
    UseContainerItem(0, 1); flush()
    equal(BuybackItem(1), "buyback native")
    observer:HandleEvent("PLAYER_MONEY"); observer:HandleEvent("BAG_UPDATE"); flush()
    equal(db.finance.salesCopper, 50)
    equal(db.finance.buybackCopper, 50)
    equal(db.finance.buybacks[1].quantity, 5)
    equal(db.finance.salesCopper - db.finance.buybackCopper, 0)
end)

test("late events can complete a final sale after the merchant frame closes", function()
    put(1, 1, 3); prices["1"], recordBuyback, suppressMutation = 10, false, true
    local observer, db = tracker()
    UseContainerItem(0, 1)
    shown = false; observer:HandleEvent("MERCHANT_CLOSED")
    clock = 0.1; observer:Reconcile(false)
    equal(db.finance.salesCopper, 0)
    bags["0:1"], balance = nil, 1030
    observer:HandleEvent("PLAYER_MONEY"); flush()
    equal(db.finance.salesCopper, 30)
end)

test("reset cancels pending callbacks and reload never treats starting money as revenue", function()
    put(1, 1, 3); prices["1"] = 10
    local observer, db = tracker({finance = {salesCopper = 99, sales = {}, buybacks = {}, unconfirmed = {}}})
    equal(db.finance.salesCopper, 99)
    observer:HandleEvent("PLAYER_MONEY"); flush()
    equal(db.finance.salesCopper, 99)
    UseContainerItem(0, 1); observer:Reset(); flush()
    equal(db.finance.salesCopper, 0)
    equal(table.getn(db.finance.sales), 0)
    equal(observer.pending, nil)
end)

test("normal drag and split drag to the merchant use the old cursor sale path", function()
    put(1, 1, 10); prices["1"] = 3
    local observer, db = tracker()
    SplitContainerItem(0, 1, 4)
    equal(PickupMerchantItem(0), "merchant native")
    flush()
    equal(db.finance.salesCopper, 12)
    equal(db.finance.sales[1].quantity, 4)
    PickupContainerItem(0, 1); PickupMerchantItem(0); flush()
    equal(db.finance.salesCopper, 30)
    equal(db.finance.sales[2].quantity, 6)
end)

test("cancelled or moved cursor items never become vendor transactions", function()
    put(1, 1, 4); prices["1"] = 10
    local observer, db = tracker()
    PickupContainerItem(0, 1); ClearCursor(); flush()
    equal(db.finance.salesCopper, 0)
    PickupContainerItem(0, 1); PickupContainerItem(0, 2); flush()
    equal(db.finance.salesCopper, 0)
    equal(table.getn(db.finance.unconfirmed), 0)
end)

test("deferred batch money and bag events reconcile after both states are available", function()
    put(1, 1, 2); put(2, 2, 3)
    prices["1"], prices["2"], suppressMutation = 10, 20, true
    local observer, db = tracker()
    UseContainerItem(0, 1); UseContainerItem(0, 2)
    balance = balance + 80
    observer:HandleEvent("PLAYER_MONEY")
    observer:Reconcile(false)
    equal(db.finance.salesCopper, 0)
    bags["0:1"], bags["0:2"] = nil, nil
    history = {
        {link = item(2, 3).link, name = "Item 2", quantity = 3, copper = 60},
        {link = item(1, 2).link, name = "Item 1", quantity = 2, copper = 20},
    }
    observer:HandleEvent("BAG_UPDATE"); flush()
    equal(db.finance.salesCopper, 80)
    equal(table.getn(db.finance.sales), 2)
end)

test("nested container hooks do not double count the same native sale", function()
    put(1, 1, 4); prices["1"] = 10
    local native = UseContainerItem
    C_Container = {UseContainerItem = native}
    UseContainerItem = function(bag, slot, onSelf) return C_Container.UseContainerItem(bag, slot, onSelf) end
    local observer, db = tracker()
    observer:InstallHooks()
    UseContainerItem(0, 1); flush()
    equal(db.finance.salesCopper, 40)
    equal(table.getn(db.finance.sales), 1)
    C_Container = nil
end)

test("observer failures never block the original merchant action", function()
    put(1, 1, 4); prices["1"] = 10
    local observer, db = tracker()
    observer.ObserveSale = function() error("Simulated addon observation failure") end
    equal(UseContainerItem(0, 1), "native")
    equal(balance, 1040)
    equal(observer.lastError, "observer_failed")
    equal(db.finance.salesCopper, 0)
end)

print(string.format("%d merchant transaction tests passed", passed))
