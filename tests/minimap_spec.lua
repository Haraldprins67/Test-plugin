-- Minimap gestures exercised through the Vanilla global callback contract.
local Widget = {}
Widget.__index = Widget
function Widget:SetWidth(value) self.width = value end
function Widget:SetHeight(value) self.height = value end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:SetPoint(point, parent, relative, x, y)
    self.point, self.parent, self.relative, self.x, self.y = point, parent, relative, x, y
end
function Widget:ClearAllPoints() self.point = nil end
function Widget:SetFrameStrata() end
function Widget:SetFrameLevel() end
function Widget:GetFrameLevel() return 3 end
function Widget:EnableMouse() end
function Widget:RegisterForClicks(value) self.clicks = value end
function Widget:RegisterForDrag(value) self.dragButton = value end
function Widget:SetHighlightTexture() end
function Widget:SetTexture(value) self.texture = value end
function Widget:SetTexCoord() end
function Widget:SetScript(name, callback) self.scripts[name] = callback end
function Widget:Show() self.shown = true end
function Widget:GetCenter() return 100, 100 end
function Widget:GetEffectiveScale() return 2 end
function Widget:CreateTexture()
    return setmetatable({}, Widget)
end
local frameCount = 0
function CreateFrame(kind, name, parent)
    frameCount = frameCount + 1
    return setmetatable({kind = kind, name = name, parent = parent, scripts = {}}, Widget)
end
function GetBuildInfo() return "1.12.1" end
local control, shift, cursorX, cursorY = false, false, 200, 200
function IsControlKeyDown() return control end
function IsShiftKeyDown() return shift end
function GetCursorPosition() return cursorX, cursorY end
Minimap = CreateFrame("Frame", "Minimap")
Minimap:SetWidth(140)
Minimap:SetHeight(140)
local originalMinimap = Minimap

ClassicLootLogNS = {}
dofile("ClassicLootLog/Compat.lua")
dofile("ClassicLootLog/Core.lua")
dofile("ClassicLootLog/MinimapButton.lua")
local Launcher, Core = ClassicLootLogNS.MinimapButton, ClassicLootLogNS.Core
local passed = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end
local function close(actual, expected)
    assert(math.abs(actual - expected) < 0.0001, tostring(actual) .. " is not near " .. tostring(expected))
end
local function fire(launcher, eventName, button)
    this, arg1 = launcher.frame, button
    launcher.frame.scripts[eventName]()
    this, arg1 = nil, nil
end
local function click(launcher, button)
    fire(launcher, "OnMouseDown", button)
    fire(launcher, "OnMouseUp", button)
    fire(launcher, "OnClick", button)
end
local function test(name, callback)
    control, shift, cursorX, cursorY = false, false, 200, 200
    Minimap, GameTooltip, IsMouseButtonDown = originalMinimap, nil, nil
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

test("normal left clicks toggle CLL while right clicks do nothing", function()
    local toggles = 0
    local launcher = Launcher.New({}, {toggle = function() toggles = toggles + 1 end})
    equal(launcher.frame.shown, true)
    equal(launcher.frame.clicks, "LeftButtonUp")
    click(launcher, "LeftButton")
    click(launcher, "LeftButton")
    click(launcher, "RightButton")
    equal(toggles, 2)
end)

test("dragging requires both Ctrl and Shift plus the left button", function()
    local db = {}
    local launcher = Launcher.New(db)
    local original = db.ui.minimapAngle
    control = true
    cursorX = 400
    fire(launcher, "OnMouseDown", "LeftButton")
    fire(launcher, "OnDragStart", "LeftButton")
    fire(launcher, "OnUpdate")
    equal(launcher.dragging, nil)
    equal(db.ui.minimapAngle, original)
    control, shift = false, true
    fire(launcher, "OnMouseDown", "LeftButton")
    fire(launcher, "OnDragStart", "LeftButton")
    equal(db.ui.minimapAngle, original)
    control = true
    fire(launcher, "OnMouseDown", "RightButton")
    fire(launcher, "OnDragStart", "RightButton")
    equal(db.ui.minimapAngle, original)
end)

test("Ctrl Shift left drag follows the cursor using the minimap UI scale", function()
    local db = {}
    local launcher = Launcher.New(db)
    control, shift = true, true
    cursorX, cursorY = 400, 200
    fire(launcher, "OnMouseDown", "LeftButton")
    equal(launcher.dragging, true)
    close(db.ui.minimapAngle, 0)
    close(launcher.frame.x, 78)
    close(launcher.frame.y, 0)
    cursorX, cursorY = 200, 400
    fire(launcher, "OnUpdate")
    close(db.ui.minimapAngle, 90)
    close(launcher.frame.x, 0)
    close(launcher.frame.y, 78)
end)

test("releasing a drag never toggles CLL and the following click works", function()
    local toggles = 0
    local launcher = Launcher.New({}, {toggle = function() toggles = toggles + 1 end})
    control, shift = true, true
    cursorX, cursorY = 0, 200
    fire(launcher, "OnMouseDown", "LeftButton")
    control, shift = false, false
    fire(launcher, "OnMouseUp", "LeftButton")
    fire(launcher, "OnClick", "LeftButton")
    equal(launcher.dragging, false)
    equal(toggles, 0)
    click(launcher, "LeftButton")
    equal(toggles, 1)
end)

test("releasing a modifier ends movement even before mouse release", function()
    local db = {}
    local launcher = Launcher.New(db)
    control, shift, cursorX = true, true, 400
    fire(launcher, "OnMouseDown", "LeftButton")
    close(db.ui.minimapAngle, 0)
    shift, cursorX, cursorY = false, 200, 400
    fire(launcher, "OnUpdate")
    equal(launcher.dragging, false)
    close(db.ui.minimapAngle, 0)
    fire(launcher, "OnMouseUp", "LeftButton")
    fire(launcher, "OnClick", "LeftButton")
end)

test("optional mouse state also ends a drag when left is released", function()
    local launcher = Launcher.New({})
    control, shift = true, true
    cursorX = 400
    fire(launcher, "OnMouseDown", "LeftButton")
    IsMouseButtonDown = function(button) equal(button, "LeftButton"); return false end
    fire(launcher, "OnUpdate")
    equal(launcher.dragging, false)
end)

test("dragged angles survive session reset and are restored on reload", function()
    local db = Core.Initialize(nil, 100)
    local launcher = Launcher.New(db)
    control, shift = true, true
    cursorX, cursorY = 200, 0
    fire(launcher, "OnMouseDown", "LeftButton")
    fire(launcher, "OnMouseUp", "LeftButton")
    close(db.ui.minimapAngle, 270)
    Core.Reset(db, 120)
    close(db.ui.minimapAngle, 270)
    local restored = Launcher.New(db)
    close(restored.frame.x, 0)
    close(restored.frame.y, -78)
end)

test("missing minimap does not break addon initialization", function()
    Minimap = nil
    local before = frameCount
    equal(Launcher.New({}), nil)
    equal(frameCount, before)
end)

test("invalid saved positions recover and replacement database is respected", function()
    local db = {ui = {minimapAngle = "invalid"}}
    local launcher = Launcher.New(db)
    equal(db.ui.minimapAngle, 225)
    local replacement = {ui = {minimapAngle = 1080}}
    launcher:SetDatabase(replacement)
    equal(replacement.ui.minimapAngle, 0)
    close(launcher.frame.x, 78)
    close(launcher.frame.y, 0)
    equal(db.ui.minimapAngle, 225)
end)

test("tooltip describes the gesture in English and hides during dragging", function()
    local lines = {}
    GameTooltip = {
        SetOwner = function() end,
        AddLine = function(_, text) lines[table.getn(lines) + 1] = text end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
    }
    local launcher = Launcher.New({})
    fire(launcher, "OnEnter")
    equal(GameTooltip.shown, true)
    equal(table.getn(lines), 3)
    assert(string.find(lines[3], "Ctrl %+ Shift"))
    control, shift = true, true
    fire(launcher, "OnMouseDown", "LeftButton")
    equal(GameTooltip.shown, false)
end)

print(string.format("%d minimap tests passed", passed))
