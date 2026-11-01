-- Run from the repository root: lua5.1 tests/core_spec.lua
local ns = {}
assert(loadfile("ClassicLootLog/Core.lua"))("ClassicLootLog", ns)
local Core = ns.Core
local tests, passed = {}, 0

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function slot(guid, quantity, link)
    return {
        name = "Linnen doek", link = link or "item:2589", quantity = quantity,
        quality = 1, kind = "item", sources = {{ guid = guid, quantity = quantity }},
    }
end

tests["initialization repairs malformed metadata and excludes offline time"] = function()
    local db = Core.Initialize({ entries = {{ id = 7 }}, seen = "bad", nextID = -1,
        timer = { enabled = true, elapsed = 12, startedAt = -1000 } }, 500)
    equal(db.nextID, 8)
    equal(type(db.seen), "table")
    equal(Core.TimerElapsed(db, 505), 17)
    equal(Core.Initialize(nil, 0).timer.enabled, false)
    equal(Core.Initialize({ timer = { elapsed = math.huge } }, 0).timer.elapsed, 0)
end

tests["reopening and partial loot cannot duplicate an observed stack"] = function()
    local db = Core.Initialize(nil, 0)
    equal(Core.AddSnapshot(db, {slot("corpse-1", 5)}, 1000, 0), 1)
    equal(Core.AddSnapshot(db, {slot("corpse-1", 5)}, 1001, 1), 0)
    equal(Core.AddSnapshot(db, {slot("corpse-1", 2)}, 1002, 2), 0)
    equal(Core.AddSnapshot(db, {}, 1003, 3), 0)
    equal(Core.AddSnapshot(db, {slot("corpse-1", 5)}, 1004, 4), 0)
    equal(#db.entries, 1)
    equal(db.entries[1].quantity, 5)
end

tests["same items in multiple slots are aggregated before deduplication"] = function()
    local db = Core.Initialize(nil, 0)
    equal(Core.AddSnapshot(db, {slot("corpse", 3), slot("corpse", 4)}, 1000, 0), 1)
    equal(db.entries[1].quantity, 7)
    equal(Core.AddSnapshot(db, {slot("corpse", 4)}, 1001, 1), 0)
    equal(Core.AddSnapshot(db, {slot("corpse", 4), slot("corpse", 3)}, 1002, 2), 0)
    equal(Core.AddSnapshot(db, {slot("corpse", 5), slot("corpse", 4)}, 1003, 3), 1)
    equal(db.entries[2].quantity, 2)
end

tests["different sources and different items remain distinct"] = function()
    local db = Core.Initialize(nil, 0)
    local shared = slot("corpse-a", 2)
    shared.quantity = 5
    shared.sources[2] = { guid = "corpse-b", quantity = 3 }
    equal(Core.AddSnapshot(db, {shared}, 1000, 0), 2)
    equal(db.entries[1].quantity, 2)
    equal(db.entries[2].quantity, 3)
    equal(Core.AddSnapshot(db, {slot("corpse-b", 3)}, 1001, 1), 0)
    equal(Core.AddSnapshot(db, {slot("corpse-b", 1, "item:2592")}, 1002, 2), 1)
    equal(#db.entries, 3)
end

tests["missing source metadata supports an explicit caller fallback"] = function()
    local db = Core.Initialize(nil, 0)
    local observed = { name = "Linnen doek", quantity = 2, sourceGUID = "window-1" }
    equal(Core.AddSnapshot(db, {observed}, 1000, 0), 1)
    equal(Core.AddSnapshot(db, {observed}, 1001, 1), 0)
    observed.sourceGUID = "window-2"
    equal(Core.AddSnapshot(db, {observed}, 1002, 2), 1)
    equal(Core.AddSnapshot(db, {{ quantity = -1 }, false}, 1003, 3), 0)
end

tests["money amounts and currency names do not change stable identities"] = function()
    local db = Core.Initialize(nil, 0)
    local money = { kind = "money", name = "1 goud", quantity = 10000, sourceGUID = "corpse" }
    local currency = { kind = "currency", name = "Token", link = "currency:1", quantity = 2, sourceGUID = "corpse" }
    equal(Core.AddSnapshot(db, {money, currency}, 1000, 0), 2)
    money.name, money.quantity = "20 zilver", 2000
    currency.name = "Token (cached)"
    equal(Core.AddSnapshot(db, {money, currency}, 1001, 1), 0)
    equal(db.entries[1].quantity, 10000)
    equal(db.entries[2].kind, "currency")
end

tests["timer pauses, resumes, checkpoints and annotates only enabled drops"] = function()
    local db = Core.Initialize(nil, 100)
    Core.AddSnapshot(db, {slot("a", 1)}, 1000, 105)
    equal(db.entries[1].elapsed, nil)
    Core.SetTimerEnabled(db, true, 110)
    Core.AddSnapshot(db, {slot("b", 1)}, 1001, 115)
    equal(db.entries[2].elapsed, 5)
    Core.SetTimerEnabled(db, false, 120)
    equal(Core.TimerElapsed(db, 1000), 10)
    Core.SetTimerEnabled(db, true, 1000)
    Core.CheckpointTimer(db, 1004)
    equal(db.timer.elapsed, 14)
    equal(Core.TimerElapsed(db, 1006), 16)
    Core.Initialize(db, 5000)
    equal(Core.TimerElapsed(db, 5002), 16)
    equal(Core.FormatElapsed(3661), "01:01:01")
    equal(Core.FormatElapsed(100 * 3600), "100:00:00")
end

tests["reset clears records and identities and restarts enabled timer"] = function()
    local db = Core.Initialize(nil, 100)
    Core.SetTimerEnabled(db, true, 100)
    Core.AddSnapshot(db, {slot("a", 1)}, 1000, 110)
    Core.Reset(db, 120)
    equal(#db.entries, 0)
    equal(next(db.seen), nil)
    equal(db.nextID, 1)
    equal(db.timer.enabled, true)
    equal(Core.TimerElapsed(db, 125), 5)
    equal(Core.AddSnapshot(db, {slot("a", 1)}, 1010, 125), 1)
    equal(db.entries[1].id, 1)
    Core.SetTimerEnabled(db, false, 126)
    Core.Reset(db, 130)
    equal(Core.TimerElapsed(db, 200), 0)
    equal(db.timer.enabled, false)
end

tests["export has all rows, readable links and escaped control characters"] = function()
    local db = Core.Initialize(nil, 0)
    local entry = slot("a", 3)
    entry.link = "|cffffffff|Hitem:2589::::::::|h[Linnen doek]|h|r"
    entry.name = "Linnen\tdoek\nmet\\tekst"
    entry.sourceLabel = "Bron\rtest"
    Core.AddSnapshot(db, {entry, slot("b", 2)}, 1000, 0)
    local exported = Core.Export(db, function(stamp) return "tijd=" .. stamp end)
    equal(select(2, exported:gsub("\n", "")), 2)
    assert(exported:find("tijd=1000", 1, true))
    assert(exported:find("Linnen\\tdoek\\nmet\\\\tekst", 1, true))
    assert(exported:find("Bron\\rtest", 1, true))
    assert(exported:find("item:2589::::::::", 1, true))
    assert(not exported:find("|Hitem", 1, true))
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
    tests[name]()
    passed = passed + 1
    print("PASS " .. name)
end
print(string.format("%d core tests passed", passed))
