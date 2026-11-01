-- Actual receipt accounting, executable unchanged under Lua 5.0.
ClassicLootLogNS = {}
dofile("ClassicLootLog/Core.lua")
dofile("ClassicLootLog/Money.lua")
local Core, Money = ClassicLootLogNS.Core, ClassicLootLogNS.Money
local passed = 0

local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, callback)
    LOOT_MONEY_SELF, YOU_LOOT_MONEY, ERR_AUTOLOOT_MONEY_S, LOOT_MONEY_SPLIT = nil, nil, nil, nil
    GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT, GOLD, SILVER, COPPER = nil, nil, nil, nil, nil, nil
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

local function tracker()
    local db = Core.Initialize(nil, 0)
    return Money.New(db), db
end

test("personal loot receipts combine all denominations into received copper", function()
    local observer, db = tracker()
    assert(observer:HandleEvent("CHAT_MSG_MONEY", "You loot 12 Gold, 34 Silver, 56 Copper."))
    equal(Money.Total(db), 123456)
    equal(db.lootMoney.sharedCopper, 0)
    equal(db.lootMoney.receipts, 1)
    equal(Money.Format(Money.Total(db)), "12g 34s 56c")
    equal(Money.Format(0), "0g 0s 0c")
end)

test("stock Vanilla receipt globals work without modern amount templates", function()
    YOU_LOOT_MONEY, ERR_AUTOLOOT_MONEY_S = "You loot %s", "You loot %s"
    GOLD, SILVER, COPPER = "Gold", "Silver", "Copper"
    local observer, db = tracker()
    observer:HandleEvent("CHAT_MSG_MONEY", "You loot 12 Copper")
    observer:HandleEvent("CHAT_MSG_MONEY", "You loot 9 Silver.")
    equal(Money.Total(db), 912)
end)

test("group receipts count the player's existing share exactly once without division", function()
    local observer, db = tracker()
    GetNumPartyMembers = function() return 4 end
    observer:HandleEvent("CHAT_MSG_MONEY", "Your share of the loot is 2 Gold, 7 Copper.")
    equal(Money.Total(db), 20007)
    equal(db.lootMoney.sharedCopper, 20007)
    observer:HandleEvent("CHAT_MSG_MONEY", "You loot 3 Copper.")
    equal(Money.Total(db), 20010)
    equal(db.lootMoney.sharedCopper, 20007)
end)

test("equal receipts from separate kills count even at the same event time", function()
    local observer, db = tracker()
    observer:HandleEvent("CHAT_MSG_MONEY", "Your share of the loot is 42 Copper.")
    observer:HandleEvent("CHAT_MSG_MONEY", "Your share of the loot is 42 Copper.")
    equal(Money.Total(db), 84)
    equal(db.lootMoney.receipts, 2)
end)

test("other players wallet deltas quests and sales are not loot receipts", function()
    local observer, db = tracker()
    equal(observer:HandleEvent("PLAYER_MONEY", "You loot 8 Gold."), false)
    equal(observer:HandleEvent("CHAT_MSG_SYSTEM", "You loot 8 Gold."), false)
    equal(observer:HandleEvent("CHAT_MSG_MONEY", "Alice loots 8 Gold."), false)
    equal(observer:HandleEvent("CHAT_MSG_MONEY", "You receive 8 Gold."), false)
    equal(observer:HandleEvent("CHAT_MSG_MONEY", "You sold something for 8 Gold."), false)
    equal(Money.Total(db), 0)
end)

test("localized positional receipt and denomination templates are parsed", function()
    LOOT_MONEY_SELF = "Du erbeutest %1$s."
    LOOT_MONEY_SPLIT = "Dein Anteil: %1$s."
    GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = "%1$d Goldstuecke", "%d Silberlinge", "%d Kupferlinge"
    local observer, db = tracker()
    observer:HandleEvent("CHAT_MSG_MONEY", "Du erbeutest 12 Goldstuecke, 34 Silberlinge, 56 Kupferlinge.")
    observer:HandleEvent("CHAT_MSG_MONEY", "Dein Anteil: 7 Silberlinge.")
    equal(Money.Total(db), 124156)
    equal(db.lootMoney.sharedCopper, 700)
end)

test("localized Vanilla denomination words need no amount-format globals", function()
    YOU_LOOT_MONEY = "Vous recevez %s"
    LOOT_MONEY_SPLIT = "Votre part est %s."
    GOLD, SILVER, COPPER = "Or", "Argent", "Cuivre"
    local observer, db = tracker()
    observer:HandleEvent("CHAT_MSG_MONEY", "Vous recevez 3 Or, 12 Argent, 9 Cuivre")
    observer:HandleEvent("CHAT_MSG_MONEY", "Votre part est 7 Cuivre.")
    equal(Money.Total(db), 31216)
end)

test("known coin textures and color codes preserve received money amounts", function()
    local observer, db = tracker()
    observer:HandleEvent("CHAT_MSG_MONEY", "You loot |cffffff001|r|TInterface\\MoneyFrame\\UI-GoldIcon:0|t 2|TInterface\\MoneyFrame\\UI-SilverIcon:0|t 3|TInterface\\MoneyFrame\\UI-CopperIcon:0|t.")
    equal(Money.Total(db), 10203)
end)

test("malformed or incomplete amounts cannot produce partial false totals", function()
    local observer, db = tracker()
    local messages = {"You loot -1 Gold.", "You loot 1.5 Gold.", "You loot 7 Gold and a quest reward.",
        "You loot 1 Gold, 2 Gold.", "You loot 1 Gold,.", "You loot Copper.", "You loot 0 Copper.",
        "Your share of the loot is 99999999999999999999999 Gold.", "You loot 1 Golden Sword."}
    for _, message in ipairs(messages) do equal(observer:HandleEvent("CHAT_MSG_MONEY", message), false) end
    equal(Money.Total(db), 0)
    equal(db.lootMoney.receipts, 0)
end)

test("received money persists without inferring historic corpse totals or starting wallet", function()
    local db = Core.Initialize(nil, 0)
    db.entries[1] = {kind = "money", quantity = 50000, name = "5 Gold"}
    Money.Initialize(db)
    equal(Money.Total(db), 0)
    local observer = Money.New(db)
    observer:HandleEvent("CHAT_MSG_MONEY", "You loot 16 Silver.")
    local nextLogin = Money.New(db)
    equal(Money.Total(db), 1600)
    nextLogin:HandleEvent("CHAT_MSG_MONEY", "Your share of the loot is 6 Copper.")
    equal(Money.Total(db), 1606)
    equal(db.lootMoney.receipts, 2)
end)

test("receipts count while paused and both database and tracker resets clear one session", function()
    local changed = 0
    local db = Core.Initialize(nil, 0)
    local observer = Money.New(db, {onChange = function() changed = changed + 1 end})
    equal(db.timer.enabled, false)
    observer:HandleEvent("CHAT_MSG_MONEY", "Your share of the loot is 6 Copper.")
    equal(Money.Total(db), 6)
    equal(changed, 1)
    Money.Reset(db)
    equal(Money.Total(db), 0)
    observer:HandleEvent("CHAT_MSG_MONEY", "You loot 2 Silver.")
    observer:Reset()
    equal(Money.Total(db), 0)
    equal(db.lootMoney.sharedCopper, 0)
    equal(db.lootMoney.receipts, 0)
    equal(changed, 3)
end)

test("invalid saved counter fields are repaired without changing other character data", function()
    local db = {lootMoney = {copper = -2, sharedCopper = 300, receipts = 0 / 0}, ui = {locked = true}}
    Money.Initialize(db)
    equal(Money.Total(db), 0)
    equal(db.lootMoney.sharedCopper, 0)
    equal(db.lootMoney.receipts, 0)
    equal(db.ui.locked, true)
end)

print(tostring(passed) .. " loot money tests passed")
