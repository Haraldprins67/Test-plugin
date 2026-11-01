-- Mini session UI behavior using only the old Vanilla script contract.
local clock = 100
local frames, texts = {}, {}
local Widget = {}
Widget.__index = Widget

function Widget:SetWidth(value) self.width = value end
function Widget:SetHeight(value) self.height = value end
function Widget:SetPoint(point, parent, relativePoint, x, y)
    self.point, self.parent, self.relativePoint, self.x, self.y = point, parent, relativePoint, x, y
end
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
dofile("ClassicLootLog/Finance.lua")
dofile("ClassicLootLog/Money.lua")
dofile("ClassicLootLog/Mini.lua")
local Core, Mini, Money = ClassicLootLogNS.Core, ClassicLootLogNS.Mini, ClassicLootLogNS.Money
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

test("compact window includes received loot money and starts hidden", function()
    local before = table.getn(texts)
    local db = Core.Initialize(nil, clock)
    local mini = Mini.New(db)
    equal(table.getn(texts) - before, 4)
    equal(mini.frame:IsShown(), false)
    equal(db.ui.miniVisible, false)
    equal(mini.frame.width, 270)
    equal(mini.kills:GetText(), "Kills: 0")
    equal(mini.timer:GetText(), "Time: 00:00:00 (paused)")
    equal(mini.mobsPerHour:GetText(), "Mobs/hour: 0.0")
    equal(mini.money:GetText(), "Loot money: 0g 0s 0c")
    assert(-mini.money.y + mini.money.height <= mini.frame.height - 12,
        "received money must remain inside the compact frame's bottom border")
end)

test("mini metrics refresh while the separate main window is hidden", function()
    local main = CreateFrame("Frame", "Main")
    main:Hide()
    local db = Core.Initialize(nil, clock)
    local receipts = Money.New(db)
    local mini = Mini.New(db)
    mini:Show()
    Core.SetTimerEnabled(db, true, clock)
    clock = 160
    Core.RecordMobKill(db, "Creature-mini", "Wolf", 1700000000, clock)
    receipts:HandleEvent("CHAT_MSG_MONEY", "You loot 1 Gold, 2 Silver, 3 Copper.")
    tick(mini, 0.25)
    equal(main:IsShown(), false)
    equal(mini.frame:IsShown(), true)
    equal(mini.kills:GetText(), "Kills: 1")
    equal(mini.timer:GetText(), "Time: 00:01:00")
    equal(mini.mobsPerHour:GetText(), "Mobs/hour: 59.8")
    equal(mini.money:GetText(), "Loot money: 1g 2s 3c")
end)

test("paused kills affect the counter without inflating the hourly rate", function()
    local db = Core.Initialize(nil, clock)
    Core.SetTimerEnabled(db, true, clock)
    clock = 160
    Core.RecordMobKill(db, "timed", "Wolf", 1, clock)
    Core.SetTimerEnabled(db, false, clock)
    Core.RecordMobKill(db, "paused", "Wolf", 2, clock)
    local mini = Mini.New(db)
    local receipts = Money.New(db)
    mini:Show()
    receipts:HandleEvent("CHAT_MSG_MONEY", "Your share of the loot is 2 Silver, 7 Copper.")
    tick(mini, 100)
    equal(mini.kills:GetText(), "Kills: 2")
    equal(mini.timer:GetText(), "Time: 00:01:00 (paused)")
    equal(mini.mobsPerHour:GetText(), "Mobs/hour: 60.0")
    equal(mini.money:GetText(), "Loot money: 0g 2s 7c")
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
    local receipts = Money.New(db)
    receipts:HandleEvent("CHAT_MSG_MONEY", "You loot 3 Gold.")
    mini:Refresh()
    equal(mini.money:GetText(), "Loot money: 3g 0s 0c")
    Core.Reset(db, clock)
    Money.Reset(db)
    mini:Refresh()
    equal(db.ui.miniVisible, true)
    equal(mini.kills:GetText(), "Kills: 0")
    equal(mini.timer:GetText(), "Time: 00:00:00")
    equal(mini.mobsPerHour:GetText(), "Mobs/hour: 0.0")
    equal(mini.money:GetText(), "Loot money: 0g 0s 0c")
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
    local receipts = Money.New(first)
    receipts:HandleEvent("CHAT_MSG_MONEY", "Your share of the loot is 4 Gold, 5 Copper.")
    Core.Initialize(first, clock + 10)
    local mini = Mini.New(first, {now = function() return clock end})
    equal(mini.frame:IsShown(), true)
    equal(first.ui.miniVisible, true)
    equal(mini.money:GetText(), "Loot money: 4g 0s 5c")
    local second = Core.Initialize(nil, clock)
    Core.RecordMobKill(second, "replacement", "Wolf", 1, clock)
    mini:SetDatabase(second)
    equal(mini.frame:IsShown(), false)
    equal(mini.kills:GetText(), "Kills: 1")
    equal(mini.money:GetText(), "Loot money: 0g 0s 0c")
    equal(first.ui.miniVisible, true)
end)

print(string.format("%d mini UI tests passed", passed))
