-- Mini session UI behavior using only the old Vanilla script contract.
local clock = 100
local frames, texts = {}, {}
local Widget = {}
Widget.__index = Widget

function Widget:SetWidth(value) self.width = value end
function Widget:SetHeight(value) self.height = value end
function Widget:SetPoint() end
function Widget:SetFrameStrata() end
function Widget:SetClampedToScreen() end
function Widget:SetMovable() end
function Widget:EnableMouse() end
function Widget:RegisterForDrag() end
function Widget:StartMoving() self.moving = true end
function Widget:StopMovingOrSizing() self.moving = false end
function Widget:SetBackdrop(value) self.backdrop = value end
function Widget:SetJustifyH() end
function Widget:SetText(value) self.text = value end
function Widget:GetText() return self.text end
function Widget:SetScript(name, callback) self.scripts[name] = callback end
function Widget:IsShown() return self.shown end
function Widget:Show() self.shown = true end
function Widget:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then
        this = self
        self.scripts.OnHide()
        this = nil
    end
end
function Widget:CreateFontString()
    local text = setmetatable({text = ""}, Widget)
    texts[table.getn(texts) + 1] = text
    return text
end

function CreateFrame(kind, name, parent)
    local frame = setmetatable({kind = kind, name = name, parent = parent,
        scripts = {}, shown = true}, Widget)
    frames[table.getn(frames) + 1] = frame
    return frame
end
function GetTime() return clock end
function GetBuildInfo() return "1.12.1" end
UIParent = CreateFrame("Frame", "UIParent")

ClassicLootLogNS = {}
dofile("ClassicLootLog/Compat.lua")
dofile("ClassicLootLog/Core.lua")
dofile("ClassicLootLog/Mini.lua")
local Core, Mini = ClassicLootLogNS.Core, ClassicLootLogNS.Mini
local passed = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, callback)
    clock = 100
    callback()
    passed = passed + 1
    print("PASS " .. name)
end
local function tick(mini, elapsed)
    clock = clock + elapsed
    this, arg1 = mini.frame, elapsed
    mini.frame.scripts.OnUpdate()
    this, arg1 = nil, nil
end

test("mini window contains only three metrics and starts hidden", function()
    local before = table.getn(texts)
    local db = Core.Initialize(nil, clock)
    local mini = Mini.New(db)
    equal(table.getn(texts) - before, 3)
    equal(mini.frame:IsShown(), false)
    equal(db.ui.miniVisible, false)
    equal(mini.frame.width, 238)
    equal(mini.kills:GetText(), "Kills: 0")
    equal(mini.timer:GetText(), "Time: 00:00:00 (paused)")
    equal(mini.mobsPerHour:GetText(), "Mobs/hour: 0.0")
end)

test("mini metrics refresh while the separate main window is hidden", function()
    local main = CreateFrame("Frame", "Main")
    main:Hide()
    local db = Core.Initialize(nil, clock)
    local mini = Mini.New(db)
    mini:Show()
    Core.SetTimerEnabled(db, true, clock)
    clock = 160
    Core.RecordMobKill(db, "Creature-mini", "Wolf", 1700000000, clock)
    tick(mini, 0.25)
    equal(main:IsShown(), false)
    equal(mini.frame:IsShown(), true)
    equal(mini.kills:GetText(), "Kills: 1")
    equal(mini.timer:GetText(), "Time: 00:01:00")
    equal(mini.mobsPerHour:GetText(), "Mobs/hour: 59.8")
end)

test("paused kills affect the counter without inflating the hourly rate", function()
    local db = Core.Initialize(nil, clock)
    Core.SetTimerEnabled(db, true, clock)
    clock = 160
    Core.RecordMobKill(db, "timed", "Wolf", 1, clock)
    Core.SetTimerEnabled(db, false, clock)
    Core.RecordMobKill(db, "paused", "Wolf", 2, clock)
    local mini = Mini.New(db)
    mini:Show()
    tick(mini, 100)
    equal(mini.kills:GetText(), "Kills: 2")
    equal(mini.timer:GetText(), "Time: 00:01:00 (paused)")
    equal(mini.mobsPerHour:GetText(), "Mobs/hour: 60.0")
    Core.SetTimerEnabled(db, true, clock)
    tick(mini, 60)
    equal(mini.timer:GetText(), "Time: 00:02:00")
    equal(mini.mobsPerHour:GetText(), "Mobs/hour: 30.0")
end)

test("reset is immediately reflected without resetting mini preferences", function()
    local db = Core.Initialize(nil, clock)
    local mini = Mini.New(db)
    mini:Show()
    Core.SetTimerEnabled(db, true, clock)
    Core.RecordMobKill(db, "reset", "Wolf", 1, clock)
    Core.Reset(db, clock)
    mini:Refresh()
    equal(db.ui.miniVisible, true)
    equal(mini.kills:GetText(), "Kills: 0")
    equal(mini.timer:GetText(), "Time: 00:00:00")
    equal(mini.mobsPerHour:GetText(), "Mobs/hour: 0.0")
end)

test("toggle and close save visibility while hidden ticks do not refresh", function()
    local db = Core.Initialize(nil, clock)
    local mini = Mini.New(db)
    mini:Toggle()
    equal(db.ui.miniVisible, true)
    equal(mini.frame:IsShown(), true)
    mini:Toggle()
    equal(db.ui.miniVisible, false)
    Core.RecordMobKill(db, "hidden", "Wolf", 1, clock)
    tick(mini, 1)
    equal(mini.kills:GetText(), "Kills: 0")
    mini:Show()
    equal(mini.kills:GetText(), "Kills: 1")
    mini.frame:Hide()
    equal(db.ui.miniVisible, false)
end)

test("saved visibility and a replacement database remain supported", function()
    local first = Core.Initialize({ui = {miniVisible = true}}, clock)
    local mini = Mini.New(first, {now = function() return clock end})
    equal(mini.frame:IsShown(), true)
    equal(first.ui.miniVisible, true)
    local second = Core.Initialize(nil, clock)
    Core.RecordMobKill(second, "replacement", "Wolf", 1, clock)
    mini:SetDatabase(second)
    equal(mini.frame:IsShown(), false)
    equal(mini.kills:GetText(), "Kills: 1")
    equal(first.ui.miniVisible, true)
end)

print(string.format("%d mini UI tests passed", passed))
