-- Complete-report formatting, written to execute unchanged on Lua 5.0.
ClassicLootLogNS = {}
dofile("ClassicLootLog/Core.lua")
dofile("ClassicLootLog/Value.lua")
dofile("ClassicLootLog/GroupLoot.lua")
dofile("ClassicLootLog/Finance.lua")
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
    assert(string.find(report, "^Classic Loot Log export\t1%.7%.0"))
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

test("complete report contains the confirmed vendor ledger and produced materials", function()
    local db, model = fixture()
    ns.Finance.Initialize(db)
    db.finance.salesCopper = 12345
    db.finance.buybackCopper = 321
    db.finance.sales = {{timestamp = 1700000000, link = "item:2590", name = "Sold Linen", quantity = 2, copper = 12345}}
    Core.AddSnapshot(db, {{kind = "item", name = "Lesser Magic Essence", link = "item:10938",
        quantity = 3, origin = "disenchant", sourceGUID = "disenchant:1"}}, 1700000000, 60)
    local report = FileExport.BuildReport(db, model, options())
    assert(string.find(report, "Confirmed gross vendor sales\t12345\t1g 23s 45c", 1, true))
    assert(string.find(report, "Produced disenchant material units\t3", 1, true))
    assert(string.find(report, "Lesser Magic Essence", 1, true))
    assert(string.find(report, "Sold Linen", 1, true))
end)

test("building a report needs no file APIs and leaves queued exports untouched", function()
    local db, model = fixture()
    local pending = {"existing legacy queued log"}
    db.pendingFileExports = pending
    local function forbidden() error("report generation must not call filesystem APIs") end
    WriteCustomFile, ReadCustomFile, ExportFile, ImportFile = forbidden, forbidden, forbidden, forbidden
    local report = FileExport.BuildReport(db, model, options())
    assert(string.find(report, "Linen 20", 1, true))
    equal(db.pendingFileExports, pending)
    equal(table.getn(db.pendingFileExports), 1)
    equal(FileExport.Save, nil)
    equal(FileExport.Queue, nil)
end)

test("logger and mob fields cannot inject report rows or retain WoW formatting", function()
    local db, model = fixture()
    db.mobs.kills[1].name = "|cffa335ee|Hitem:1|h[Purple wolf]|h|r\tTab\nRow\rReturn\\Path"
    local report = FileExport.BuildReport(db, model, options("Name\tHeader\nFake"))
    assert(string.find(report, "Logged by\tName\\tHeader\\nFake\n", 1, true))
    assert(string.find(report, "[Purple wolf]\\tTab\\nRow\\rReturn\\\\Path", 1, true))
    assert(not string.find(report, "|cffa335ee", 1, true))
    assert(not string.find(report, "\nFake\n", 1, true))
end)

test("missing group history and a failing date formatter leave a readable report", function()
    local db = fixture()
    local opts = options()
    opts.dateFormatter = function() error("date unavailable") end
    local report = FileExport.BuildReport(db, nil, opts)
    assert(string.find(report, "Exported\tUnknown", 1, true))
    assert(string.find(report, "Party / raid exporter unavailable.", 1, true))
    assert(string.find(report, "End Classic Loot Log export\n", 1, true))
    equal(FileExport.FileName(opts), "Unknown_Unknown_Testplayer.txt")
end)

test("filename truncation preserves a complete multibyte player character", function()
    local name = string.rep("a", 63) .. "Ärthäs"
    local result = FileExport.FileName(options(name))
    equal(result, "2026-11-01_04-05-06_" .. string.rep("a", 63) .. ".txt")
end)

test("invalid database input returns an explicit formatter error", function()
    local result, reason = FileExport.BuildReport(nil, nil, options())
    equal(result, nil)
    equal(reason, "invalid_database")
end)

print(string.format("%d report-format tests passed", passed))
