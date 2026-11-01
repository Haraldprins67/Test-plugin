-- The vendor and notification suite is executable by genuine Lua 5.0.
ClassicLootLogNS = {}
dofile("ClassicLootLog/Value.lua")
local Value = ClassicLootLogNS.Value
local passed = 0

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, callback)
    GetItemInfo, GetSellValue, GetMerchantItemInfo = nil, nil, nil
    SellValues = nil
    UIErrorsFrame, DEFAULT_CHAT_FRAME, PlaySound = nil, nil, nil
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

local function entry(id, quantity, quality, origin)
    return { id = id, link = "|Hitem:" .. id .. ":0:0:0|h[Item " .. id .. "]|h",
        name = "Item " .. id, quantity = quantity, quality = quality or 1,
        kind = "item", origin = origin or "drop", disenchanted = 0 }
end

test("vendor prices remain unknown when the Vanilla client supplies no sell price", function()
    local db = Value.Initialize({entries = {}})
    GetItemInfo = function() return "Item", "item:1", 1, 1, 1, "Class", "Sub", 20, "", "icon" end
    -- A merchant's buy price is deliberately not used as a sell value.
    GetMerchantItemInfo = function() error("buy prices must not be queried") end
    equal(Value.GetUnitPrice(db, "item:1"), nil)
    equal(Value.GetEntryVendorText(db, entry(1, 3)), "Unknown")
    equal(Value.GetTotals({entries = {entry(1, 3)}}).unknownUnits, 3)
end)

test("native eleventh return is cached and known zero differs from missing data", function()
    local db = Value.Initialize({entries = {}})
    local calls = 0
    GetItemInfo = function(id)
        calls = calls + 1
        return "Item", "item:" .. id, 1, 1, 1, "Class", "Sub", 20, "", "icon", id == 1 and 0 or 12345
    end
    equal(Value.GetEntryVendorText(db, entry(1, 2)), "0c")
    equal(Value.GetEntryVendorText(db, entry(2, 2)), "2g 46s 90c")
    equal(Value.GetUnitPrice(db, "item:2"), 12345)
    equal(calls, 2)
end)

test("optional GetSellValue supplies prices and provider failures stay harmless", function()
    local db = Value.Initialize({entries = {}})
    GetItemInfo = function() error("uncached item") end
    GetSellValue = function(id) if id == 1 then return 42 end; error("unknown item") end
    equal(Value.GetUnitPrice(db, 1), 42)
    equal(Value.GetEntryVendorText(db, entry(1, 3)), "1s 26c")
    equal(Value.GetUnitPrice(db, 2), nil)
end)

test("SellValue item-string database supplies unit copper prices without stack inflation", function()
    -- This is the public SellValue_IDFromLink / SellValues storage contract.
    SellValues = {["item:1"] = 25, ["item:2"] = 0}
    local db = Value.Initialize({entries = {}})
    local price, source = Value.GetUnitPrice(db, "|Hitem:1:0:0|h[Cloth]|h")
    equal(price, 25)
    equal(source, "SellValue")
    equal(Value.ProviderName(), "SellValue")
    equal(Value.GetEntryVendorText(db, entry(1, 20)), "5s 0c")
    equal(Value.GetEntryVendorText(db, entry(2, 20)), "0c")
    equal(Value.GetEntryVendorText(db, entry(3, 20)), "Unknown")
    equal(SellValues["item:1"], 25, "integration must not rewrite SellValue data")
    equal(SellValues[1], nil)
end)

test("SellValue arriving after a native cache supersedes automatic prices and follows updates", function()
    local db = Value.Initialize({entries = {}})
    GetItemInfo = function() return "Item", "link", 1, 1, 1, "Class", "Sub", 1, "", "icon", 10 end
    equal(Value.GetUnitPrice(db, 1), 10)
    equal(db.vendorPriceSources[1], "client")
    SellValues = {["item:1"] = 30}
    equal(Value.GetUnitPrice(db, 1), 30)
    equal(db.vendorPriceSources[1], "SellValue")
    SellValues["item:1"] = 45
    equal(Value.GetUnitPrice(db, 1), 45)
    equal(db.vendorPrices[1], 45)
end)

test("explicit manual overrides stay authoritative over SellValue until cleared", function()
    local db = Value.Initialize({entries = {}})
    SellValues = {["item:1"] = 30}
    equal(Value.GetUnitPrice(db, 1), 30)
    equal(Value.SetPrice(db, 1, 70), true)
    SellValues["item:1"] = 45
    equal(Value.GetUnitPrice(db, 1), 70)
    Value.RefreshPrices(db)
    equal(Value.GetUnitPrice(db, 1), 70)
    equal(Value.SetPrice(db, 1, 0), true)
    Value.RefreshPrices(db)
    equal(Value.GetUnitPrice(db, 1), 0)
    equal(Value.ClearPrice(db, 1), true)
    equal(Value.GetUnitPrice(db, 1), 45)
end)

test("legacy cached values with unknown provenance migrate without losing a possible user override", function()
    SellValues = {["item:1"] = 99, ["item:2"] = 88}
    local db = Value.Initialize({entries = {}, vendorPrices = {[1] = 12, ["2"] = 0}})
    equal(db.vendorSchema, 2)
    equal(Value.GetUnitPrice(db, 1), 12)
    equal(Value.GetUnitPrice(db, 2), 0)
    Value.RefreshPrices(db)
    equal(Value.GetUnitPrice(db, 1), 12)
    Value.ClearPrice(db, 1)
    equal(Value.GetUnitPrice(db, 1), 99)
end)

test("price refresh removes automatic caches but preserves saved manual prices", function()
    local db = Value.Initialize({entries = {}})
    GetItemInfo = function(id)
        return "Item", "link", 1, 1, 1, "Class", "Sub", 1, "", "icon", id * 10
    end
    Value.SetPrice(db, 1, 7)
    equal(Value.GetUnitPrice(db, 2), 20)
    Value.RefreshPrices(db)
    equal(db.vendorPrices[1], 7)
    equal(db.vendorPrices[2], nil)
    equal(db.vendorPriceSources[2], nil)
    SellValues = {["item:2"] = 25}
    equal(Value.GetUnitPrice(db, 2), 25)
    equal(Value.GetUnitPrice(db, 1), 7)
end)

test("compatible SellValue key variants and invalid provider values stay safe", function()
    local db = Value.Initialize({entries = {}})
    SellValues = {[1] = 15, ["2"] = 20, ["item:3"] = -10, ["item:4"] = 1 / 0}
    equal(Value.GetUnitPrice(db, 1), 15)
    equal(Value.GetUnitPrice(db, 2), 20)
    equal(Value.GetUnitPrice(db, 3), nil)
    equal(Value.GetUnitPrice(db, 4), nil)
    SellValues = "invalid provider table"
    GetSellValue = function(id) if id == 5 then return 7 end end
    equal(Value.ProviderName(), "GetSellValue")
    equal(Value.GetUnitPrice(db, 5), 7)
end)

test("manual prices validate copper override providers and clear cleanly", function()
    local db = Value.Initialize({entries = {}})
    GetItemInfo = function() return "Item", "link", 1, 1, 1, "Class", "Sub", 1, "", "icon", 50 end
    equal(Value.SetPrice(db, "item:10", 123), true)
    equal(Value.GetUnitPrice(db, "|cffffffff|Hitem:10:0|h[Item]|h|r"), 123)
    equal(Value.SetPrice(db, 10, -1), false)
    equal(Value.SetPrice(db, 10, 1.5), false)
    equal(Value.SetPrice(db, "not an item", 20), false)
    equal(Value.SetPrice(db, 0, 20), false)
    equal(Value.SetPrice(db, 10, 0 / 0), false)
    equal(Value.SetPrice(db, 10, 1 / 0), false)
    equal(Value.GetUnitPrice(db, 10), 123)
    equal(Value.ClearPrice(db, 10), true)
    equal(Value.GetUnitPrice(db, 10), 50)
    equal(Value.ClearPrice(db, "bad"), false)
end)

test("remaining vendor totals exclude destroyed originals and include their materials", function()
    local a, materials, unknown = entry(1, 3), entry(2, 5, 1, "disenchant"), entry(3, 4)
    a.disenchanted = 2
    local db = Value.Initialize({entries = {a, materials, unknown, {kind = "money", quantity = 10000}}})
    Value.SetPrice(db, 1, 100)
    Value.SetPrice(db, 2, 10)
    equal(Value.GetEntryVendorText(db, a), "1s 0c")
    equal(Value.GetEntryVendorText(db, materials), "50c")
    equal(Value.GetEntryVendorText(db, db.entries[4]), "-")
    local totals = Value.GetTotals(db)
    equal(totals.knownCopper, 150)
    equal(totals.unknownUnits, 4)
    unknown.disenchanted = 4
    equal(Value.GetEntryVendorText(db, unknown), "0c")
    equal(Value.GetTotals(db).unknownUnits, 0)
end)

test("grouped material rows and malformed cached prices are handled conservatively", function()
    local db = Value.Initialize({entries = {}, vendorPrices = {[1] = -10, ["2"] = 25}})
    equal(Value.GetUnitPrice(db, 1), nil)
    equal(Value.GetUnitPrice(db, 2), 25)
    local material = {key = "item:2", quantity = 4, isMaterial = true, disenchanted = 2}
    equal(Value.GetEntryVendorText(db, material), "1s 0c")
    equal(Value.FormatMoney(nil), "Unknown")
    equal(Value.FormatMoney(10001), "1g 0s 1c")
    equal(Value.FormatMoney(101), "1s 1c")
end)

test("vendor export keeps every existing row and distinguishes unknown zero and DE quantities", function()
    local original, knownZero, unknown, material = entry(1, 3), entry(2, 2), entry(3, 4), entry(4, 5, 1, "disenchant")
    original.disenchanted = 1
    local db = Value.Initialize({entries = {original, knownZero, unknown, material, {kind = "money", quantity = 100}}})
    Value.SetPrice(db, 1, 50)
    Value.SetPrice(db, 2, 0)
    Value.SetPrice(db, 4, 10)
    local base = "ID\tItem\n1\tOriginal\n2\tZero\n3\tUnknown\n4\tMaterial\n5\tMoney"
    local exported = Value.AppendExportColumns(db, base)
    local changed, count = string.gsub(exported, "\n", "")
    equal(count, 5)
    assert(string.find(exported, "ID\tItem\tUnit vendor (copper)\tRemaining vendor (copper)\tRemaining quantity", 1, true))
    assert(string.find(exported, "1\tOriginal\t50\t100\t2", 1, true))
    assert(string.find(exported, "2\tZero\t0\t0\t2", 1, true))
    assert(string.find(exported, "3\tUnknown\tUnknown\tUnknown\t4", 1, true))
    assert(string.find(exported, "4\tMaterial\t10\t50\t5", 1, true))
    assert(string.find(exported, "5\tMoney\t-\t-\t-", 1, true))
    unknown.disenchanted = 4
    exported = Value.AppendExportColumns(db, base)
    assert(string.find(exported, "3\tUnknown\tUnknown\t0\t0", 1, true))
    local empty = Value.AppendExportColumns({entries = {}}, "ID\tItem")
    changed, count = string.gsub(empty, "\n", "")
    equal(count, 0)
end)

test("summary export includes known remaining vendor totals and explicit unknown units", function()
    local original = entry(1, 3)
    original.disenchanted = 2
    local db = Value.Initialize({entries = {original, entry(2, 2, 1, "disenchant"), entry(3, 4)}})
    Value.SetPrice(db, 1, 100)
    Value.SetPrice(db, 2, 25)
    local base = "Statistic\tValue\nMobs total\t10"
    local exported = Value.AppendSummary(db, base)
    equal(string.sub(exported, 1, string.len(base)), base)
    assert(string.find(exported, "Known remaining vendor value (copper)\t150", 1, true))
    assert(string.find(exported, "Known remaining vendor value\t1s 50c", 1, true))
    assert(string.find(exported, "Remaining item units with unknown vendor price\t4", 1, true))
    assert(string.find(exported, "not current inventory.", 1, true))
end)

test("only new epic originals notify once and a reset ID can notify again", function()
    local db = Value.Initialize({entries = {}})
    local messages = {}
    local callbacks = {notify = function(message, row) messages[table.getn(messages) + 1] = message end}
    db.entries = {entry(1, 1, 3), entry(2, 2, 4), entry(3, 1, 5), entry(4, 3, 4, "disenchant")}
    equal(Value.NotifyEntries(db, 1, callbacks), 1)
    equal(table.getn(messages), 1)
    assert(string.find(messages[1], "EPIC LOOT:", 1, true))
    assert(string.find(messages[1], "x2", 1, true))
    equal(Value.NotifyEntries(db, 1, callbacks), 0)
    db.entries = {entry(1, 1, 4)}
    equal(Value.NotifyEntries(db, 1, callbacks), 1)
    equal(table.getn(messages), 2)
end)

test("initialization and omitted batch boundaries never replay saved epic history", function()
    local db = Value.Initialize({entries = {entry(1, 1, 4)}})
    local calls = 0
    local callbacks = {notify = function() calls = calls + 1 end}
    equal(Value.NotifyEntries(db, 1, callbacks), 0)
    db.entries[2] = entry(2, 1, 4)
    equal(Value.NotifyEntries(db, nil, callbacks), 0)
    equal(Value.NotifyEntries(db, 2, callbacks), 1)
    equal(calls, 1)
end)

test("disabled epic alerts stay silent and toggling on does not replay them", function()
    local db = Value.Initialize({entries = {}, alerts = {epic = false}})
    db.entries[1] = entry(1, 1, 4)
    local calls = 0
    local callbacks = {notify = function() calls = calls + 1 end}
    equal(Value.NotifyEntries(db, 1, callbacks), 0)
    db.alerts.epic = true
    equal(Value.NotifyEntries(db, 1, callbacks), 0)
    db.entries[2] = entry(2, 1, 4)
    equal(Value.NotifyEntries(db, 2, callbacks), 1)
    equal(calls, 1)
end)

test("default epic notices use purple screen and chat messages with optional safe sound", function()
    local db = Value.Initialize({entries = {}})
    local screen, chat, sounds = {}, {}, 0
    UIErrorsFrame = {AddMessage = function(self, message, r, g, b) screen = {message, r, g, b} end}
    DEFAULT_CHAT_FRAME = {AddMessage = function(self, message) chat[1] = message end}
    PlaySound = function(name) equal(name, "RaidWarning"); sounds = sounds + 1 end
    db.entries[1] = entry(1, 1, 4)
    equal(Value.NotifyEntries(db, 1), 1)
    equal(sounds, 0)
    assert(string.find(screen[1], "EPIC LOOT:", 1, true))
    equal(screen[2], 0.64)
    assert(string.find(chat[1], "|cffa335ee", 1, true))
    db.alerts.sound = true
    db.entries[2] = entry(2, 1, 4)
    equal(Value.NotifyEntries(db, 2), 1)
    equal(sounds, 1)
    PlaySound = function() error("client lacks this sound") end
    db.entries[3] = entry(3, 1, 4)
    equal(Value.NotifyEntries(db, 3), 1)
end)

print(string.format("%d vendor and epic-alert tests passed", passed))
