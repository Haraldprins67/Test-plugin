-- Receipt recovery and snapshot reconciliation, unchanged under genuine Lua 5.0.
ClassicLootLogNS = {}
dofile("ClassicLootLog/Core.lua")
dofile("ClassicLootLog/LootReceipts.lua")
local Core, Receipts = ClassicLootLogNS.Core, ClassicLootLogNS.LootReceipts
local clock, stamp, passed = 10, 1700000000, 0
function GetTime() return clock end
function time() return stamp end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function link(id, name, color, suffix)
    return "|c" .. (color or "ff1eff00") .. "|Hitem:" .. id .. ":0:" .. (suffix or 0)
        .. ":0|h[" .. (name or "Green sword") .. "]|h|r"
end
local function message(item, count)
    return "You receive loot: " .. item .. (count and ("x" .. count) or "") .. "."
end
local function database()
    local db = Core.Initialize(nil, clock)
    return db, Receipts.New(db)
end
local function total(db)
    local count = 0
    for _, entry in ipairs(db.entries) do count = count + entry.quantity end
    return count
end
local function test(name, callback)
    LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE, GetItemInfo = nil, nil, nil
    clock, stamp = 10, 1700000000
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

test("uncached actual green receipts retain full name quality quantity and payload", function()
    local db, observer = database()
    local item = link(15210, "Green sword of the Bear", "ff1eff00", -12)
    local added, slot = observer:Record(message(item, 2))
    equal(added, 1)
    equal(slot.name, "Green sword of the Bear")
    equal(db.entries[1].quality, 2)
    equal(db.entries[1].quantity, 2)
    equal(db.entries[1].link, item)
    equal(db.entries[1].origin, "drop")
end)

test("snapshot then receipts count each actual item once and recover later missing stacks", function()
    local db, observer = database()
    local item = link(15210)
    Core.AddSnapshot(db, {{kind = "item", link = item, name = "Green sword", quantity = 2, sourceGUID = "corpse:one"}}, stamp, clock)
    observer:Record(message(item), {sourceGUID = "corpse:one"})
    observer:Record(message(item), {sourceGUID = "corpse:one"})
    equal(total(db), 2)
    observer:Record(message(item), {sourceGUID = "corpse:one"})
    equal(total(db), 3)
end)

test("receipt before a late native snapshot reconciles by the same source", function()
    local db, observer = database()
    local item = link(15210)
    observer:Record(message(item, 3), {sourceGUID = "corpse:late"})
    Core.AddSnapshot(db, {{kind = "item", link = item, name = "Green sword", quantity = 3, sourceGUID = "corpse:late"}}, stamp, clock)
    equal(table.getn(db.entries), 1)
    equal(total(db), 3)
end)

test("display color differences reconcile while random suffix payloads remain separate", function()
    local db, observer = database()
    local item = link(15210, "Sword of the Bear", "ff1eff00", -12)
    local raw = "|Hitem:15210:0:-12:0|h[Sword of the Bear]|h"
    Core.AddSnapshot(db, {{kind = "item", link = raw, name = "Sword of the Bear", quantity = 1, sourceGUID = "corpse:variants"}}, stamp, clock)
    observer:Record(message(item), {sourceGUID = "corpse:variants"})
    observer:Record(message(link(15210, "Sword of the Tiger", "ff1eff00", -13)), {sourceGUID = "corpse:variants"})
    equal(total(db), 2)
end)

test("all Classic dust types are recorded as materials only with a confirmed DE source", function()
    local db, observer = database()
    local ids = {10940, 11083, 11137, 11176, 16204}
    for _, id in ipairs(ids) do
        local item = link(id, id == 16204 and "Illusion Dust" or ("Dust " .. id), "ffffffff")
        observer:Record(message(item, 4), {sourceGUID = "cast:" .. id, origin = "disenchant"})
    end
    equal(Core.ItemStats(db).totalMaterials, 20)
    equal(Core.ItemStats(db).totalQuantity, 0)
    observer:Record(message(link(16204, "Illusion Dust", "ffffffff")), {sourceGUID = "corpse:dust"})
    equal(Core.ItemStats(db).totalMaterials, 20)
    equal(Core.ItemStats(db).totalQuantity, 1)
end)

test("equal unsourced receipts represent separate actual drops", function()
    local db, observer = database()
    local receipt = message(link(15210))
    observer:Record(receipt)
    observer:Record(receipt)
    equal(total(db), 2)
    assert(db.entries[1].source ~= db.entries[2].source)
end)

test("multi-source credits cover observed loot before recovered receipt quantities", function()
    local db, observer = database()
    local item = link(15210)
    Core.AddSnapshot(db, {{kind = "item", link = item, name = "Green sword", quantity = 3,
        sources = {{guid = "corpse:a", quantity = 1}, {guid = "corpse:b", quantity = 2}}}}, stamp, clock)
    local options = {sourceGUID = "window:multi", observedQuantity = 3}
    equal(observer:Record(message(item, 2), options), 0)
    equal(observer:Record(message(item), options), 0)
    equal(total(db), 3)
    equal(observer:Record(message(item, 2), options), 1)
    equal(total(db), 5)
    equal(db.entries[3].quantity, 2)
end)

test("enchant-material hints include all Classic families but never classify ordinary drops", function()
    local ids = {10938, 10939, 10940, 10978, 10998, 11082, 11083, 11084,
        11134, 11135, 11137, 11138, 11139, 11174, 11175, 11176,
        11177, 11178, 14343, 14344, 16202, 16203, 16204, 20725}
    for _, id in ipairs(ids) do assert(Receipts.IsEnchantMaterial(link(id))) end
    equal(Receipts.IsEnchantMaterial("16204"), true)
    equal(Receipts.IsEnchantMaterial(10940), true)
    equal(Receipts.IsEnchantMaterial(15210), false)
    equal(Receipts.IsEnchantMaterial(nil), false)
end)

test("localized reordered and expanded item-link templates preserve stack counts", function()
    local db, observer = database()
    LOOT_ITEM_SELF_MULTIPLE = "Du erhaeltst %2$d x %1$s."
    observer:Record("Du erhaeltst 12 x " .. link(16204, "Illusion Dust", "ffffffff") .. ".")
    equal(total(db), 12)
    LOOT_ITEM_SELF_MULTIPLE = "Loot: |c%s|Hitem:%d:%d:%d:%d|h[%s]|h|rx%d."
    observer:Record("Loot: " .. link(15210, "Suffix sword", "ff1eff00", -19) .. "x3.")
    equal(total(db), 15)
end)

test("other recipients rolls crafted items pushed rewards and malformed receipts are ignored", function()
    local db, observer = database()
    local item = link(15210)
    local messages = {"Alice receives loot: " .. item .. ".", "You create: " .. item .. ".",
        "You receive item: " .. item .. ".", "You won: " .. item, "You receive loot: " .. item .. "x0.",
        "You receive loot: " .. item .. "x-2.", "You receive loot: 1 Gold.",
        "You receive loot: " .. item .. " and " .. item .. "."}
    for _, receipt in ipairs(messages) do equal(observer:Record(receipt), nil) end
    equal(total(db), 0)
end)

test("available item metadata supplies an icon without losing receipt item variants", function()
    local db, observer = database()
    GetItemInfo = function() return "Base Sword", nil, 1, 1, 1, "Weapon", "Sword", 1, "", "SwordIcon" end
    observer:Record(message(link(15210, "Sword of Agility")))
    equal(db.entries[1].name, "Sword of Agility")
    equal(db.entries[1].quality, 2)
    equal(db.entries[1].icon, "SwordIcon")
end)

test("callbacks only announce new rows and reset clears per-source receipt totals", function()
    local db = Core.Initialize(nil, clock)
    local called, first = 0, nil
    local observer = Receipts.New(db, {onAdded = function(index, added) called = called + added; first = index end})
    local item = link(15210)
    Core.AddSnapshot(db, {{kind = "item", link = item, quantity = 2, sourceGUID = "corpse:reset"}}, stamp, clock)
    observer:Record(message(item), {sourceGUID = "corpse:reset"})
    equal(called, 0)
    Core.Reset(db, clock)
    observer:Reset()
    observer:Record(message(item), {sourceGUID = "corpse:reset"})
    equal(called, 1)
    equal(first, 1)
    equal(total(db), 1)
end)

print(tostring(passed) .. " loot receipt tests passed")
