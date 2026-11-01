local ns = {}
ClassicLootLogNS = ns
assert(loadfile("ClassicLootLog/Core.lua"))("ClassicLootLog", ns)
local Core = ns.Core
local tests, passed = {}, 0

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function close(actual, expected)
    assert(math.abs(actual - expected) < 0.000001, tostring(actual) .. " differs from " .. expected)
end

local function add(db, guid, itemID, quantity, origin, name)
    return Core.AddSnapshot(db, {{ name = name or ("Item " .. itemID), link = "item:" .. itemID,
        quantity = quantity, kind = "item", origin = origin,
        sources = {{guid = guid, quantity = quantity}} }}, 1700000000, 10)
end

tests["version one migrates without losing loot or deduplication"] = function()
    local db = {version = 1, entries = {{id = 2, kind = "item", link = "item:1", quantity = 3}},
        seen = {["6:corpseitem:item:1"] = 3}, timer = {enabled = false, elapsed = 12}}
    Core.Initialize(db, 30)
    equal(db.version, 2)
    equal(db.entries[1].origin, "drop")
    equal(db.entries[1].disenchanted, 0)
    equal(#db.entries, 1)
    equal(Core.ItemStats(db).totalQuantity, 3)
    equal(db.mobs.total, 0)
    equal(add(db, "corpse", 1, 3), 0)
    equal(db.timer.elapsed, 12)
end

tests["mob kills deduplicate across checkpoints and reloads"] = function()
    local db = Core.Initialize(nil, 100)
    equal(Core.RecordMobKill(db, "Creature-1", "Wolf", 1000, 100), true)
    equal(Core.RecordMobKill(db, "Creature-1", "Wolf", 1001, 101), false)
    equal(Core.RecordMobKill(db, nil, "Wolf", 1001, 101), false)
    equal(db.mobs.total, 1)
    equal(db.mobs.timed, 0)
    Core.Initialize(db, 200)
    equal(Core.RecordMobKill(db, "Creature-1", "Wolf", 1002, 201), false)
    equal(#db.mobs.kills, 1)
    equal(db.mobs.kills[1].name, "Wolf")
end

tests["mobs per hour excludes paused kills and paused time"] = function()
    local db = Core.Initialize(nil, 0)
    Core.RecordMobKill(db, "a", "A", 1000, 0)
    close(Core.MobStats(db, 1).perHour, 0)
    Core.SetTimerEnabled(db, true, 10)
    Core.RecordMobKill(db, "b", "B", 1001, 20)
    Core.RecordMobKill(db, "c", "C", 1002, 30)
    close(Core.MobStats(db, 70).perHour, 120)
    Core.SetTimerEnabled(db, false, 70)
    Core.RecordMobKill(db, "d", "D", 1003, 100)
    local paused = Core.MobStats(db, 200)
    equal(paused.total, 4)
    equal(paused.timed, 2)
    equal(paused.elapsed, 60)
    close(paused.perHour, 120)
    Core.SetTimerEnabled(db, true, 200)
    Core.RecordMobKill(db, "e", "E", 1004, 260)
    close(Core.MobStats(db, 260).perHour, 90)
end

tests["new timer cannot divide by zero and malformed mob metadata is normalized"] = function()
    local db = Core.Initialize({mobs = {total = -1, timed = math.huge, seen = "bad", kills = false}}, 1)
    Core.SetTimerEnabled(db, true, 1)
    Core.RecordMobKill(db, "new", "New", 1000, 1)
    close(Core.MobStats(db, 1).perHour, 0)
    equal(type(db.mobs.seen), "table")
    equal(type(db.mobs.kills), "table")
    equal(Core.Initialize({mobs = {total = 2, timed = 10}}, 1).mobs.timed, 2)
end

tests["loot percentages aggregate link variants and exclude money currency and materials"] = function()
    local db = Core.Initialize(nil, 0)
    add(db, "a", 1, 3)
    Core.AddSnapshot(db, {{name = "Item 1", link = "|cffffffff|Hitem:1:0:0:0:0:0:99|h[Item 1]|h|r",
        kind = "item", quantity = 2, sourceGUID = "b"}}, 1000, 0)
    add(db, "c", 2, 5)
    add(db, "d", 3, 20, "disenchant")
    Core.AddSnapshot(db, {{kind = "money", name = "1 goud", quantity = 10000, sourceGUID = "e"},
        {kind = "currency", name = "Token", quantity = 100, sourceGUID = "e"}}, 1001, 0)
    local stats = Core.ItemStats(db)
    equal(stats.totalQuantity, 10)
    equal(stats.totalMaterials, 20)
    equal(#stats.rows, 2)
    equal(#stats.materialRows, 1)
    equal(stats.byKey["item:1"].quantity, 5)
    close(stats.byKey["item:1"].percent, 50)
    close(stats.byKey["item:2"].percent, 50)
    close(stats.materialRows[1].percent, 100)
    equal(stats.rows[1].key, "item:1")
    equal(Core.ItemKey("item:1:::::::::99"), "item:1")
end

tests["same item source can have both original drops and transformed materials"] = function()
    local db = Core.Initialize(nil, 0)
    equal(add(db, "shared", 1, 2), 1)
    equal(add(db, "shared", 1, 3, "disenchant"), 1)
    equal(add(db, "shared", 1, 3, "disenchant"), 0)
    equal(#db.entries, 2)
    equal(Core.ItemStats(db).totalQuantity, 2)
    equal(Core.ItemStats(db).totalMaterials, 3)
end

tests["marking originals uses newest entries and preserves original denominator"] = function()
    local db = Core.Initialize(nil, 0)
    add(db, "old", 1, 2)
    add(db, "new", 1, 3)
    add(db, "other", 2, 5)
    add(db, "material", 1, 8, "disenchant")
    equal(Core.MarkDisenchanted(db, "|Hitem:1:0:99|h[Item 1]|h", 4, 10), 4)
    equal(db.entries[1].disenchanted, 1)
    equal(db.entries[2].disenchanted, 3)
    equal(db.entries[4].disenchanted, 0)
    local stats = Core.ItemStats(db)
    equal(stats.totalDisenchanted, 4)
    equal(stats.totalQuantity, 10)
    close(stats.byKey["item:1"].percent, 50)
    equal(Core.MarkDisenchanted(db, "item:1", 100, 10), 1)
    equal(Core.MarkDisenchanted(db, "item:1", 1, 10), 0)
    equal(Core.MarkDisenchanted(db, "item:404", 1, 10), 0)
end

tests["selected entry marking cannot modify another source or invalid item"] = function()
    local db = Core.Initialize(nil, 0)
    add(db, "old", 1, 2)
    add(db, "new", 1, 3)
    equal(Core.MarkDisenchanted(db, "item:1", 10, 10, db.entries[1].id), 2)
    equal(db.entries[2].disenchanted, 0)
    equal(Core.MarkDisenchanted(db, "item:2", 1, 10, db.entries[2].id), 0)
    equal(Core.MarkDisenchanted(db, "", 1, 10), 0)
    equal(Core.MarkDisenchanted(db, "item:1", -1, 10), 0)
    equal(Core.MarkDisenchanted(db, "item:1", nil, 10), 1)
end

tests["unmarking corrects only the selected original and clamps to its marks"] = function()
    local db = Core.Initialize(nil, 0)
    add(db, "old", 1, 2)
    add(db, "new", 1, 3)
    add(db, "material", 2, 5, "disenchant")
    equal(Core.MarkDisenchanted(db, "item:1", 3, 1), 3)
    equal(Core.UnmarkDisenchanted(db, db.entries[2].id), 1)
    equal(db.entries[2].disenchanted, 2)
    equal(Core.UnmarkDisenchanted(db, db.entries[1].id, 100), 0)
    equal(Core.UnmarkDisenchanted(db, db.entries[3].id, 100), 0)
    equal(Core.UnmarkDisenchanted(db, db.entries[2].id, 100), 2)
    equal(Core.UnmarkDisenchanted(db, db.entries[2].id, 1), 0)
    equal(Core.UnmarkDisenchanted(db, nil), 0)
    equal(db.entries[2].disenchanted, 0)
    equal(Core.ItemStats(db).totalQuantity, 5)
    equal(Core.ItemStats(db).totalDisenchanted, 0)
end

tests["reset clears new counters and histories without changing stopwatch enablement"] = function()
    local db = Core.Initialize(nil, 0)
    Core.SetTimerEnabled(db, true, 0)
    add(db, "a", 1, 2)
    Core.MarkDisenchanted(db, "item:1", 1, 1)
    Core.RecordMobKill(db, "mob", "Wolf", 1000, 2)
    Core.Reset(db, 10)
    equal(db.mobs.total, 0)
    equal(db.mobs.timed, 0)
    equal(#db.mobs.kills, 0)
    equal(next(db.mobs.seen), nil)
    equal(Core.ItemStats(db).totalQuantity, 0)
    equal(Core.ItemStats(db).totalDisenchanted, 0)
    equal(db.timer.enabled, true)
    equal(Core.RecordMobKill(db, "mob", "Wolf", 1001, 11), true)
end

tests["exports retain transformations and include separate numeric summaries"] = function()
    local db = Core.Initialize(nil, 0)
    Core.SetTimerEnabled(db, true, 0)
    add(db, "a", 1, 1, nil, "Item\tOne")
    Core.MarkDisenchanted(db, "item:1", 1, 1)
    add(db, "b", 3, 2, "disenchant", "Dust\nNew")
    Core.RecordMobKill(db, "mob", "Wolf", 1000, 60)
    local log, summary = Core.Export(db), Core.ExportSummary(db, 60)
    equal(select(2, log:gsub("\n", "")), 2)
    assert(log:find("Origin\tDisenchanted", 1, true))
    assert(log:find("\tdrop\t1", 1, true))
    assert(log:find("\tdisenchant\t0", 1, true))
    assert(summary:find("Mobs per hour\t60.00", 1, true))
    assert(summary:find("Item\\tOne\t1\t100.00%\t1", 1, true))
    assert(summary:find("Dust\\nNew\t2\t100.00%", 1, true))
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
    tests[name]()
    passed = passed + 1
    print("PASS " .. name)
end
print(string.format("%d stats tests passed", passed))
