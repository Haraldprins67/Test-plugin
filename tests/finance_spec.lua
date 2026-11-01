-- Financial behavior executable unchanged in the real Lua 5.0 interpreter.
ClassicLootLogNS = {}
dofile("ClassicLootLog/Core.lua")
dofile("ClassicLootLog/Value.lua")
dofile("ClassicLootLog/Finance.lua")
local Core, Value, Finance = ClassicLootLogNS.Core, ClassicLootLogNS.Value, ClassicLootLogNS.Finance
local passed = 0

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, callback)
    SellValues, GetSellValue, GetItemInfo = nil, nil, nil
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

local function database()
    local db = Core.Initialize(nil, 0)
    Value.Initialize(db)
    return db
end

local function add(db, id, quantity, origin, name, source)
    Core.AddSnapshot(db, {{kind = "item", link = "item:" .. id,
        name = name or ("Item " .. id), quantity = quantity, origin = origin,
        sourceGUID = source or ("source:" .. id)}}, 1700000000, 0)
    return db.entries[table.getn(db.entries)]
end

test("old histories acquire an empty ledger without losing price or UI preferences", function()
    local db = database()
    add(db, 1, 3)
    db.ui.width = 1000
    Value.SetPrice(db, 1, 13)
    local overrides = db.vendorOverrides
    Finance.Initialize(db)
    equal(db.finance.salesCopper, 0)
    equal(db.finance.buybackCopper, 0)
    equal(table.getn(db.finance.sales), 0)
    equal(db.vendorOverrides, overrides)
    equal(db.ui.width, 1000)
    equal(table.getn(db.entries), 1)
    equal(Finance.Summary(db).dropCopper, 39)
end)

test("gross original drops retain disenchanted units and exclude materials money and currency", function()
    local db = database()
    local original = add(db, 1, 3)
    original.disenchanted = 2
    add(db, 2, 5, "disenchant", "Lesser Magic Essence")
    Core.AddSnapshot(db, {{kind = "money", name = "1 gold", quantity = 10000, sourceGUID = "money"},
        {kind = "currency", name = "Token", quantity = 10, sourceGUID = "currency"}}, 1700000000, 0)
    Value.SetPrice(db, 1, 100)
    Value.SetPrice(db, 2, 20)
    local summary = Finance.Summary(db)
    equal(summary.dropCopper, 300)
    equal(summary.totalDropUnits, 3)
    equal(summary.originalsDisenchanted, 2)
    equal(summary.totalMaterials, 5)
    equal(summary.materialRows[1].name, "Lesser Magic Essence")
    equal(Value.GetTotals(db).knownCopper, 200)
    equal(summary.salesCopper, 0, "estimated loot never becomes actual sales")
end)

test("missing prices remain explicit while known zero prices are complete", function()
    local db = database()
    add(db, 1, 3)
    add(db, 2, 2)
    Value.SetPrice(db, 1, 0)
    local summary = Finance.Summary(db)
    equal(summary.dropCopper, 0)
    equal(summary.knownDropUnits, 3)
    equal(summary.unknownDropUnits, 2)
    equal(summary.totalDropUnits, 5)
    SellValues = {["item:2"] = 45}
    summary = Finance.Summary(db)
    equal(summary.dropCopper, 90)
    equal(summary.unknownDropUnits, 0)
end)

test("produced material counts group item IDs and do not subtract sold or disenchanted flags", function()
    local db = database()
    add(db, 10938, 2, "disenchant", "Lesser Magic Essence", "cast:1")
    Core.AddSnapshot(db, {{kind = "item", name = "Lesser Magic Essence", quantity = 3,
        link = "|cff1eff00|Hitem:10938:0:99|h[Lesser Magic Essence]|h|r", origin = "disenchant",
        sourceGUID = "cast:2"}}, 1700000000, 0)
    add(db, 10940, 7, "disenchant", "Strange Dust")
    add(db, 10978, 1, "disenchant", "Small Glimmering Shard")
    db.entries[1].disenchanted = 2
    db.finance = {salesCopper = 50, sales = {{quantity = 2, link = "item:10938", copper = 50}}}
    local summary = Finance.Summary(db)
    equal(summary.totalMaterials, 13)
    equal(table.getn(summary.materialRows), 3)
    local quantities = {}
    for _, row in ipairs(summary.materialRows) do quantities[row.key] = row.quantity end
    equal(quantities["item:10938"], 5)
    equal(quantities["item:10940"], 7)
    equal(quantities["item:10978"], 1)
    equal(summary.dropCopper, 0)
end)

test("confirmed gross sales buybacks and uncertain records remain separate", function()
    local db = database()
    db.finance = {
        salesCopper = 12345, buybackCopper = 345,
        sales = {{timestamp = 1700000000, link = "item:1", name = "Sword", quantity = 3, copper = 12345}},
        buybacks = {{timestamp = 1700000001, link = "item:1", name = "Sword", quantity = 1, copper = 345}},
        unconfirmed = {{kind = "sale", quantity = 1, reason = "mixed_money_change"},
            {kind = "buyback", quantity = 1, reason = "bag_not_confirmed"}},
    }
    local summary = Finance.Summary(db)
    equal(summary.salesCopper, 12345)
    equal(summary.buybackCopper, 345)
    equal(summary.netSalesCopper, 12000)
    equal(summary.actualSalesCopper, 12000)
    equal(summary.unconfirmedSales, 1)
    equal(summary.unconfirmedBuybacks, 1)
    equal(summary.unconfirmedTransactions, 2)
    equal(summary.totalDropUnits, 0, "sold inventory need not appear in the drop log")
    equal(Finance.FormatMoneyAlways(summary.netSalesCopper), "1g 20s 0c")
end)

test("all denominations and negative net income format without inventing unknown values", function()
    equal(Finance.FormatMoneyAlways(0), "0g 0s 0c")
    equal(Finance.FormatMoneyAlways(10001), "1g 0s 1c")
    equal(Finance.FormatMoneyAlways(101), "0g 1s 1c")
    equal(Finance.FormatMoneyAlways(-101), "-0g 1s 1c")
    equal(Finance.FormatMoneyAlways(nil), "Unknown")
    equal(Finance.FormatMoneyAlways(1 / 0), "Unknown")
    local db = Finance.Initialize({finance = {salesCopper = -1, buybackCopper = 10}})
    equal(Finance.Summary(db).netSalesCopper, -10)
    equal(Finance.Summary(db).actualSalesCopper, -10)
end)

test("actual vendor sales correct confirmed buybacks without erasing gross history", function()
    local db = database()
    db.finance = {salesCopper = 10050, buybackCopper = 50,
        sales = {{quantity = 1, copper = 50}, {quantity = 1, copper = 10000}},
        buybacks = {{quantity = 1, copper = 50}},
        unconfirmed = {{kind = "buyback", quantity = 1, copper = 10000}},
    }
    local summary = Finance.Summary(db)
    equal(summary.actualSalesCopper, 10000)
    equal(summary.salesCopper, 10050)
    equal(summary.buybackCopper, 50)
    equal(table.getn(summary.sales), 2)
    equal(summary.unconfirmedBuybacks, 1)
    local report = Finance.Export(db)
    assert(string.find(report, "Actual vendor sales (after buybacks)\t10000\t1g 0s 0c", 1, true))
    assert(string.find(report, "Confirmed gross vendor sales\t10050\t1g 0s 50c", 1, true))
    assert(string.find(report, "Confirmed buybacks\t50\t0g 0s 50c", 1, true))
end)

test("malformed financial metadata is normalized without changing existing records", function()
    local rows = {{quantity = 1, copper = 20}}
    local db = Finance.Initialize({finance = {salesCopper = 0 / 0, buybackCopper = 1 / 0,
        sales = rows, buybacks = false, unconfirmed = "bad"}})
    equal(db.finance.salesCopper, 0)
    equal(db.finance.buybackCopper, 0)
    equal(db.finance.sales, rows)
    equal(table.getn(db.finance.buybacks), 0)
    equal(table.getn(db.finance.unconfirmed), 0)
    equal(Finance.Summary(db).totalDropUnits, 0)
end)

test("financial export includes actual ledgers and escaped material and uncertainty fields", function()
    local db = database()
    add(db, 1, 2, nil, "Sword\tblue")
    add(db, 10938, 4, "disenchant", "Essence\nMagic")
    Value.SetPrice(db, 1, 105)
    db.finance = {salesCopper = 205, buybackCopper = 0,
        sales = {{timestamp = 123, link = "|Hitem:9:0|h[Boots]|h", name = "Boots\tLeather",
            quantity = 1, copper = 205, source = "money_and_bag"}},
        unconfirmed = {{timestamp = 124, kind = "sale", name = "Lost\nItem", quantity = 1,
            reason = "mixed\tmoney", link = "item:10"}},
    }
    local exported = Finance.Export(db)
    assert(string.find(exported, "Known gross vendor value of original drops\t210\t0g 2s 10c", 1, true))
    assert(string.find(exported, "Confirmed gross vendor sales\t205\t0g 2s 5c", 1, true))
    assert(string.find(exported, "Essence\\nMagic\t4\titem:10938", 1, true))
    assert(string.find(exported, "Boots\\tLeather\t1\t205", 1, true))
    assert(string.find(exported, "Lost\\nItem\t1\tmixed\\tmoney", 1, true))
    assert(not string.find(exported, "|Hitem:", 1, true))
end)

print(string.format("%d finance model tests passed", passed))
