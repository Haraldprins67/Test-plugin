-- Complete-log export behavior, written to execute unchanged on Lua 5.0.
ClassicLootLogNS = {}
dofile("ClassicLootLog/Core.lua")
dofile("ClassicLootLog/Value.lua")
dofile("ClassicLootLog/GroupLoot.lua")
dofile("ClassicLootLog/FileExport.lua")
local ns = ClassicLootLogNS
local FileExport, Core = ns.FileExport, ns.Core
local passed = 0

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, callback)
    WriteCustomFile, ReadCustomFile, ExportFile, ImportFile = nil, nil, nil, nil
    GetItemInfo, GetSellValue, SellValues = nil, nil, nil
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

local function dateFormatter(pattern, stamp)
    if pattern == "%Y-%m-%d" then return "2026-11-01" end
    if pattern == "%H-%M-%S" then return "04-05-06" end
    return "2026-11-01 04:05:06"
end

local function options(name)
    return {timestamp = 1700000000, clock = 60, player = name or "Testplayer", dateFormatter = dateFormatter}
end

local function fixture()
    local db = ns.Value.Initialize(Core.Initialize(nil, 0))
    Core.SetTimerEnabled(db, true, 0)
    for index = 1, 20 do
        Core.AddSnapshot(db, {{kind = "item", name = "Linen " .. index, link = "item:" .. (2589 + index),
            quantity = index, sourceGUID = "Creature-" .. index}}, 1700000000 + index, index)
    end
    Core.RecordMobKill(db, "Creature-export", "Export wolf", 1700000000, 60)
    local model = ns.GroupLoot.New(db, {now = function() return 60 end, time = function() return 1700000000 end})
    local entry = model:StartItem("|Hitem:18803:0:0|h[Export sword]|h", "master")
    model:AddBid(entry, "Alice", "MAX!")
    model:AddRoll(entry, "Alice", 91)
    model:AddRoll(entry, "Bob", 82)
    return db, model, entry
end

test("complete report includes hidden history statistics group details and mob kills", function()
    local db, model, entry = fixture()
    local report = FileExport.BuildReport(db, model, options())
    assert(string.find(report, "^Classic Loot Log export"))
    assert(string.find(report, "End Classic Loot Log export\n$"))
    assert(string.find(report, "Linen 1", 1, true))
    assert(string.find(report, "Linen 20", 1, true))
    assert(string.find(report, "Mobs per hour\t60.00", 1, true))
    assert(string.find(report, "Alice\tbid\tMAX", 1, true))
    assert(string.find(report, "Bob\t82", 1, true))
    assert(string.find(report, "Export wolf", 1, true))
    assert(string.find(report, "Unit vendor (copper)", 1, true))
    equal(entry.state, "open", "building a report must not archive active contexts")
    equal(table.getn(db.entries), 20)
end)

test("filename uses local date time and a sanitized Unicode player name", function()
    equal(FileExport.FileName(options("Ärthäs")), "2026-11-01_04-05-06_Ärthäs.txt")
    local name = FileExport.FileName(options("../../Bad:Name\\?*\n"))
    assert(not string.find(name, "[\\/:?*%c]"))
    assert(string.find(name, "^2026%-11%-01_04%-05%-06_"))
    assert(string.find(name, "%.txt$"))
    equal(FileExport.DesiredName(options("   ")), "2026-11-01_04-05-06_Unknown.txt")
end)

test("base64 encoding uses the standard ASCII alphabet and correct padding", function()
    equal(FileExport.Base64Encode(""), "")
    equal(FileExport.Base64Encode("f"), "Zg==")
    equal(FileExport.Base64Encode("fo"), "Zm8=")
    equal(FileExport.Base64Encode("foo"), "Zm9v")
    equal(FileExport.Base64Encode("foob"), "Zm9vYg==")
    equal(FileExport.Base64Encode("fooba"), "Zm9vYmE=")
    equal(FileExport.Base64Encode("foobar"), "Zm9vYmFy")
    equal(FileExport.Base64Encode("\000\255"), "AP8=")
    equal(FileExport.Base64Encode(nil), nil)
end)

test("missing native API queues a complete ASCII marker without claiming a disk write", function()
    local db, model = fixture()
    local result = FileExport.Save(db, model, options())
    equal(result.status, "queued")
    equal(result.provider, "SavedVariables")
    equal(result.verified, false)
    equal(result.rootWritten, false)
    equal(result.needsReload, true)
    equal(result.writeError, "file_api_missing")
    equal(db.pendingFileExports[1], result.payload)
    equal(result.payload, "CLLEXPORT1:" .. FileExport.Base64Encode(result.filename .. "\n" .. result.text))
    assert(not string.find(result.payload, "[^A-Za-z0-9+/=:]"))
end)

test("same-second exports get distinct names and reset keeps queued reports", function()
    local db, model = fixture()
    local first = FileExport.Queue(db, model, options())
    local second = FileExport.Queue(db, model, options())
    equal(first.filename, "2026-11-01_04-05-06_Testplayer.txt")
    equal(second.filename, "2026-11-01_04-05-06_Testplayer-02.txt")
    Core.Reset(db, 60)
    local third = FileExport.Queue(db, model, options())
    equal(third.filename, "2026-11-01_04-05-06_Testplayer-03.txt")
    equal(table.getn(db.pendingFileExports), 3)
    assert(string.find(db.pendingFileExports[1], "^CLLEXPORT1:"))
end)

test("Octo custom-file writes stay sandboxed and verify the complete readback", function()
    local db, model = fixture()
    local files, calls = {}, 0
    WriteCustomFile = function(name, text)
        assert(not string.find(name, "[\\/%.]"), "native writer receives only a safe extensionless basename")
        calls = calls + 1
        files[name] = text
    end
    ReadCustomFile = function(name) return files[name] end
    local result = FileExport.Save(db, model, options())
    equal(result.status, "written")
    equal(result.verified, true)
    equal(result.provider, "WriteCustomFile")
    equal(result.path, "CustomData\\" .. result.bridgeFile)
    equal(result.target, "Lootlogs\\" .. result.filename)
    equal(result.requiresBridge, true)
    equal(result.rootWritten, false)
    equal(result.needsReload, false)
    equal(calls, 1)
    equal(files[result.bridgeFile], result.text)
    equal(db.pendingFileExports, nil)
end)

test("existing native bridge files are not overwritten after a counter reset", function()
    local db, model = fixture()
    local occupied = "ClassicLootLog_2026-11-01_04-05-06_Testplayer"
    local files = {[occupied] = "existing export"}
    WriteCustomFile = function(name, text) files[name] = text end
    ReadCustomFile = function(name) return files[name] end
    local result = FileExport.Save(db, model, options())
    equal(result.filename, "2026-11-01_04-05-06_Testplayer-02.txt")
    equal(files[occupied], "existing export")
    equal(result.verified, true)
end)

test("SuperWoW uses the verified import export pair without escaping its directory", function()
    local db, model = fixture()
    local files = {}
    ExportFile = function(name, text) files[name] = text end
    ImportFile = function(name) return files[name] end
    local result = FileExport.Save(db, model, options())
    equal(result.status, "written")
    equal(result.provider, "ExportFile")
    equal(result.path, "imports\\" .. result.bridgeFile .. ".txt")
    equal(result.pathVerified, false, "closed-source suffix behavior is not presented as independently verified")
    equal(result.requiresBridge, true)
    equal(files[result.bridgeFile], result.text)
end)

test("false thrown or unverified writes queue instead of reporting success", function()
    local db, model = fixture()
    WriteCustomFile = function() return false end
    local result = FileExport.Save(db, model, options())
    equal(result.status, "queued"); equal(result.writeError, "write_rejected")
    WriteCustomFile = function() error("permission denied") end
    result = FileExport.Save(db, model, options())
    equal(result.status, "queued"); equal(result.writeError, "write_failed")
    WriteCustomFile = function() end
    result = FileExport.Save(db, model, options())
    equal(result.status, "queued"); equal(result.writeError, "write_unverified")
    local written
    WriteCustomFile = function(name) written = name end
    ReadCustomFile = function(name) if name == written then return "partial report" end end
    result = FileExport.Save(db, model, options())
    equal(result.status, "queued"); equal(result.writeError, "readback_mismatch")
    ReadCustomFile = function() error("cannot read") end
    result = FileExport.Save(db, model, options())
    equal(result.status, "queued"); equal(result.writeError, "readback_failed")
    equal(result.verified, false)
    equal(table.getn(db.pendingFileExports), 5)
end)

test("invalid database input does not invoke native writers", function()
    local calls = 0
    WriteCustomFile = function() calls = calls + 1 end
    local result, reason = FileExport.Save(nil, nil, options())
    equal(result, nil); equal(reason, "invalid_database")
    equal(FileExport.BuildReport(nil, nil, options()), nil)
    equal(calls, 0)
end)

print(string.format("%d file-export tests passed", passed))
