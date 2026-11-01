-- This suite deliberately uses only Lua 5.0 syntax and standard functions.
ClassicLootLogNS = {}
dofile("ClassicLootLog/Core.lua")
local Core = ClassicLootLogNS.Core
local passed = 0

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function check(name, callback)
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

local function slot(guid, quantity, link, origin)
    return {
        name = "Linen Cloth", link = link or "item:2589", quantity = quantity,
        quality = 1, kind = "item", origin = origin,
        sources = {{ guid = guid, quantity = quantity }},
    }
end

check("Lua 5.0 core loads through a shared global namespace", function()
    equal(type(Core), "table")
    equal(type(Core.AddSnapshot), "function")
    equal(Core.FormatElapsed(3661), "01:01:01")
    equal(Core.FormatElapsed(100 * 3600), "100:00:00")
    equal(Core.ItemKey("|cffffffff|Hitem:2589:0:0:0|h[Linen Cloth]|h|r"), "item:2589")
    equal(Core.ItemKey(nil, "Fallback"), "name:Fallback")
end)

check("Lua 5.0 snapshots aggregate stacks and preserve corpse deduplication", function()
    local db = Core.Initialize(nil, 0)
    equal(Core.AddSnapshot(db, {slot("corpse", 3), slot("corpse", 4)}, 1000, 0), 1)
    equal(db.entries[1].quantity, 7)
    equal(Core.AddSnapshot(db, {slot("corpse", 4)}, 1001, 1), 0)
    equal(Core.AddSnapshot(db, {slot("corpse", 7)}, 1002, 2), 0)
    equal(table.getn(db.entries), 1)
    equal(Core.AddSnapshot(db, {slot("corpse-new", 2)}, 1003, 3), 1)
end)

check("loot identity ignores display formatting while keeping random suffix variants", function()
    local db = Core.Initialize(nil, 0)
    local green = "|cff1eff00|Hitem:15210:0:0:0|h[Green sword]|h|r"
    equal(Core.AddSnapshot(db, {slot("green-corpse", 1, green)}, 1000, 0), 1)
    equal(Core.AddSnapshot(db, {slot("green-corpse", 1, "item:15210")}, 1001, 1), 0)
    equal(Core.AddSnapshot(db, {slot("green-corpse", 1, "|Hitem:15210:0:0:0|h[Renamed sword]|h")}, 1002, 2), 0)
    equal(Core.AddSnapshot(db, {slot("green-corpse", 1, "item:15210:0:123:0")}, 1003, 3), 1)
    equal(Core.AddSnapshot(db, {slot("green-corpse", 1, "item:15210:0:456:0")}, 1004, 4), 1)
end)

check("old saved histories retain source deduplication after item identity normalization", function()
    local link = "|cff1eff00|Hitem:15210:0:0:0|h[Old green sword]|h|r"
    local source = "old-corpse"
    local legacyKey = string.len(source) .. ":" .. source .. "item:" .. link
    local db = Core.Initialize({entries = {{id = 1, kind = "item", link = link, source = source, quantity = 2}},
        seen = {[legacyKey] = 2}}, 0)
    equal(Core.AddSnapshot(db, {slot(source, 2, "item:15210")}, 1001, 1), 0)
    equal(Core.AddSnapshot(db, {slot(source, 3, link)}, 1002, 2), 1)
    equal(db.entries[2].quantity, 1)
    equal(db.seen[legacyKey], 2)
end)

check("Lua 5.0 timer and mob rates exclude paused time and kills", function()
    local db = Core.Initialize(nil, 0)
    Core.RecordMobKill(db, "untimed", "Wolf", 1000, 1)
    Core.SetTimerEnabled(db, true, 10)
    Core.RecordMobKill(db, "timed", "Wolf", 1001, 70)
    equal(Core.RecordMobKill(db, "timed", "Wolf", 1001, 70), false)
    equal(Core.MobStats(db, 70).perHour, 60)
    Core.SetTimerEnabled(db, false, 70)
    Core.RecordMobKill(db, "paused", "Wolf", 1002, 100)
    equal(Core.MobStats(db, 500).perHour, 60)
    equal(Core.MobStats(db, 500).total, 3)
    equal(Core.MobStats(db, 500).timed, 1)
    Core.SetTimerEnabled(db, true, 500)
    Core.CheckpointTimer(db, 510)
    Core.Initialize(db, 5000)
    equal(Core.TimerElapsed(db, 5005), 75)
end)

check("Lua 5.0 percentages retain originals and separate disenchant materials", function()
    local db = Core.Initialize(nil, 0)
    Core.AddSnapshot(db, {slot("a", 3), slot("b", 7, "item:2592")}, 1000, 0)
    Core.AddSnapshot(db, {slot("de", 20, "item:10940", "disenchant")}, 1001, 1)
    local stats = Core.ItemStats(db)
    equal(stats.totalQuantity, 10)
    equal(stats.totalMaterials, 20)
    equal(stats.byKey["item:2589"].percent, 30)
    equal(Core.MarkDisenchanted(db, "item:2589", 2, 2, db.entries[1].id), 2)
    equal(Core.ItemStats(db).totalQuantity, 10)
    equal(Core.ItemStats(db).totalDisenchanted, 2)
    equal(Core.UnmarkDisenchanted(db, db.entries[1].id, 1), 1)
    equal(Core.ItemStats(db).totalDisenchanted, 1)
end)

check("Lua 5.0 exports use English headings and preserve item identifiers", function()
    local db = Core.Initialize(nil, 0)
    local original = slot("corpse", 1, "|cffffffff|Hitem:2589:0:0:0|h[Linen Cloth]|h|r")
    original.name = "Linen\tCloth\nTest"
    Core.AddSnapshot(db, {original}, 1000, 0)
    Core.MarkDisenchanted(db, "item:2589", 1, 1)
    local log = Core.Export(db, function(stamp) return "date=" .. stamp end)
    assert(string.find(log, "Date/time", 1, true))
    assert(string.find(log, "Origin\tDisenchanted", 1, true))
    assert(string.find(log, "Linen\\tCloth\\nTest", 1, true))
    assert(string.find(log, "item:2589:0:0:0", 1, true))
    assert(string.find(log, "\tdrop\t1", 1, true))
    local summary = Core.ExportSummary(db, 0)
    assert(string.find(summary, "Mobs per hour\t0.00", 1, true))
    -- Summary records have the documented number of fields, no gsub count.
    assert(string.find(summary, "100.00%\t1\titem:2589\n", 1, true))
end)

check("Lua 5.0 reset clears counters and keeps enabled timer running", function()
    local db = Core.Initialize(nil, 0)
    Core.SetTimerEnabled(db, true, 0)
    Core.AddSnapshot(db, {slot("corpse", 1)}, 1000, 1)
    Core.RecordMobKill(db, "corpse", "Wolf", 1001, 2)
    Core.Reset(db, 10)
    equal(table.getn(db.entries), 0)
    equal(db.mobs.total, 0)
    equal(db.timer.enabled, true)
    equal(Core.TimerElapsed(db, 15), 5)
end)

print(string.format("%d Lua 5.0 core tests passed", passed))
