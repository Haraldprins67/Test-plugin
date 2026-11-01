-- Saved report snapshots and migration execute unchanged with Vanilla Lua 5.0.
ClassicLootLogNS = {}
dofile("ClassicLootLog/Core.lua")
dofile("ClassicLootLog/Value.lua")
dofile("ClassicLootLog/FileExport.lua")
dofile("ClassicLootLog/SavedLogs.lua")
local ns = ClassicLootLogNS
local Core, SavedLogs, FileExport = ns.Core, ns.SavedLogs, ns.FileExport
local passed = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, callback)
    callback()
    passed = passed + 1
    print("PASS " .. name)
end
local function dateFormatter(pattern)
    if pattern == "%Y-%m-%d" then return "2026-11-01" end
    if pattern == "%H-%M-%S" then return "04-05-06" end
    return "2026-11-01 04:05:06"
end
local function options()
    return {timestamp = 1700000000, clock = 60, player = "Ärthäs", realm = "OctoWoW",
        dateFormatter = dateFormatter}
end
local function queued(filename, report)
    return "CLLEXPORT1:" .. FileExport.Base64Encode(filename .. "\n" .. report)
end

test("saving a report needs no file APIs or external program", function()
    WriteCustomFile = function() error("must not write a file") end
    ExportFile = function() error("must not write a file") end
    local db = Core.Initialize(nil, 0)
    local entry = SavedLogs.Save(db, "a complete report\n", options())
    equal(entry.id, 1)
    equal(entry.title, "2026-11-01_04-05-06_Ärthäs")
    equal(entry.text, "a complete report\n")
    equal(entry.player, "Ärthäs")
    equal(entry.realm, "OctoWoW")
    equal(entry.timestamp, 1700000000)
    equal(db.pendingFileExports, nil)
end)

test("saved snapshots survive session resets and later loot changes", function()
    local db = ns.Value.Initialize(Core.Initialize(nil, 0))
    Core.AddSnapshot(db, {{kind = "item", name = "Linen Cloth", link = "item:2589", quantity = 2,
        sourceGUID = "Creature-first"}}, 1700000000, 60)
    local report = FileExport.BuildReport(db, nil, options())
    local entry = SavedLogs.Save(db, report, options())
    Core.Reset(db, 60)
    Core.AddSnapshot(db, {{kind = "item", name = "Copper Ore", link = "item:2770", quantity = 7,
        sourceGUID = "Creature-second"}}, 1700000060, 120)
    equal(SavedLogs.Get(db, entry.id).text, report)
    assert(string.find(entry.text, "Linen Cloth", 1, true))
    assert(not string.find(entry.text, "Copper Ore", 1, true))
    equal(table.getn(SavedLogs.Entries(db)), 1)
end)

test("same-second snapshots have separate names and stable newest-first IDs", function()
    local db = {}
    local first = SavedLogs.Save(db, "first", options())
    local second = SavedLogs.Save(db, "second", options())
    local third = SavedLogs.Save(db, "third", options())
    equal(second.title, first.title .. "-02")
    equal(third.title, first.title .. "-03")
    local entries = SavedLogs.Entries(db)
    equal(entries[1], third)
    equal(entries[3], first)
    equal(db.savedLogs.entries[1], first, "reading must not reorder persistent entries")
    table.remove(entries, 1)
    equal(table.getn(SavedLogs.Entries(db)), 3, "returned list is independent")
end)

test("deleting one saved log leaves other reports and IDs intact", function()
    local db = {}
    local first = SavedLogs.Save(db, "first", options())
    local second = SavedLogs.Save(db, "second", options())
    local third = SavedLogs.Save(db, "third", options())
    equal(SavedLogs.Delete(db, second.id), true)
    equal(SavedLogs.Get(db, second.id), nil)
    equal(SavedLogs.Delete(db, second.id), false)
    equal(SavedLogs.Get(db, third.id), third)
    equal(SavedLogs.Get(db, first.id), first)
    local fourth = SavedLogs.Save(db, "fourth", options())
    equal(fourth.id, 4)
    assert(fourth.title ~= first.title and fourth.title ~= third.title)
end)

test("legacy queued exports migrate byte-for-byte and become reviewable", function()
    local report = "Classic Loot Log export\t1.6.0\nLogged by\tÄrthäs\nExported\t2026-11-01 04:05:06\n"
        .. "=== ALL LOOT ENTRIES ===\n[Essence]\t3\nEnd Classic Loot Log export\n"
    local filename = "2026-11-01_04-05-06_Ärthäs.txt"
    local db = {pendingFileExports = {queued(filename, report)}}
    SavedLogs.Initialize(db)
    local entry = SavedLogs.Entries(db)[1]
    equal(entry.text, report)
    equal(entry.title, "2026-11-01_04-05-06_Ärthäs")
    equal(entry.player, "Ärthäs")
    equal(entry.legacyFilename, filename)
    equal(db.pendingFileExports, nil)
end)

test("reinitializing and repeated queued payloads cannot duplicate migrated logs", function()
    local payload = queued("2026-11-01_04-05-06_Test.txt", "original\n")
    local db = {pendingFileExports = {payload, payload}}
    SavedLogs.Initialize(db)
    SavedLogs.Initialize(db)
    equal(table.getn(SavedLogs.Entries(db)), 1)
    db.pendingFileExports = {payload}
    SavedLogs.Initialize(db)
    equal(table.getn(SavedLogs.Entries(db)), 1)
    equal(db.pendingFileExports, nil)
end)

test("different queued report contents are kept even with matching filenames", function()
    local db = {pendingFileExports = {
        queued("old.txt", "first snapshot\n"), queued("old.txt", "second snapshot\n")}}
    SavedLogs.Initialize(db)
    local entries = SavedLogs.Entries(db)
    equal(table.getn(entries), 2)
    equal(entries[1].text, "second snapshot\n")
    equal(entries[2].text, "first snapshot\n")
end)

test("damaged payloads stay available while valid legacy exports migrate", function()
    local malformed = {"unrelated", "CLLEXPORT1:Zg=", "CLLEXPORT1:Zg=A", "CLLEXPORT1:Zh==",
        "CLLEXPORT1:Zm9=", "CLLEXPORT1:Zg==AAAA", queued("empty.txt", ""),
        "CLLEXPORT1:" .. FileExport.Base64Encode("missing separator")}
    local pending = {}
    for _, payload in ipairs(malformed) do pending[table.getn(pending) + 1] = payload end
    pending[table.getn(pending) + 1] = queued("valid.txt", "kept\n")
    local db = {pendingFileExports = pending}
    SavedLogs.Initialize(db)
    equal(table.getn(SavedLogs.Entries(db)), 1)
    equal(table.getn(db.pendingFileExports), table.getn(malformed))
    for index, payload in ipairs(malformed) do equal(db.pendingFileExports[index], payload) end
end)

test("base64 migration preserves padding binary bytes and Unicode report text", function()
    local db = {pendingFileExports = {}}
    for length = 1, 9 do
        local text = string.rep("x", length) .. "\000\255Ärthäs\n"
        db.pendingFileExports[length] = queued("binary-" .. length .. ".txt", text)
    end
    SavedLogs.Initialize(db)
    for length = 1, 9 do
        equal(SavedLogs.Get(db, length).text, string.rep("x", length) .. "\000\255Ärthäs\n")
    end
    equal(db.pendingFileExports, nil)
end)

test("old schema IDs are repaired and new records never overwrite an existing log", function()
    local db = {savedLogs = {nextID = 1, entries = {
        {id = 8, text = "oldest", title = "oldest"},
        {id = 8, text = "duplicate id"},
        {text = "missing id"},
    }}}
    SavedLogs.Initialize(db)
    equal(SavedLogs.Get(db, 8).text, "oldest")
    equal(SavedLogs.Get(db, 9).text, "duplicate id")
    equal(SavedLogs.Get(db, 10).text, "missing id")
    equal(SavedLogs.Save(db, "new", options()).id, 11)
    equal(table.getn(SavedLogs.Entries(db)), 4)
end)

test("invalid requests leave valid saved logs intact", function()
    local db = {}
    local entry = SavedLogs.Save(db, "valid", options())
    equal(SavedLogs.Save(db, nil), nil)
    equal(SavedLogs.Save(db, ""), nil)
    equal(SavedLogs.Save(nil, "valid"), nil)
    equal(table.getn(SavedLogs.Entries(nil)), 0)
    equal(SavedLogs.Get(db, 999), nil)
    equal(SavedLogs.Get(db, entry.id).text, "valid")
end)

print("Passed " .. passed .. " saved-log tests")
