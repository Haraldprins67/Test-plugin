-- This suite is also executable by a real Lua 5.0 interpreter.
local passed = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, callback)
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

local frames = {}
local clock = 0
local function frame()
    local item = { scripts = {}, shown = false }
    function item:SetScript(name, callback) self.scripts[name] = callback end
    function item:SetWidth(value) self.width = value end
    function item:SetHeight(value) self.height = value end
    function item:Show() self.shown = true end
    function item:Hide() self.shown = false end
    function item:RegisterEvent(name)
        if name == "UNSUPPORTED" then error("unknown event") end
        self.registered = name
    end
    function item:GetValue() return self.value end
    frames[table.getn(frames) + 1] = item
    return item
end

function CreateFrame() return frame() end
function GetTime() return clock end
local function loadCompat(version)
    ClassicLootLogNS = {}
    GetBuildInfo = function() return version end
    dofile("ClassicLootLog/Compat.lua")
    return ClassicLootLogNS.Compat
end

test("client version distinguishes vanilla from current Classic Era", function()
    UnitGUID = nil
    CombatLogGetCurrentEventInfo = nil
    equal(loadCompat("1.12.1").IsLegacy, true)
    equal(loadCompat("1.15.9").IsLegacy, false)
    equal(loadCompat(nil).IsLegacy, true)
    UnitGUID = function() return "Player-modern" end
    equal(loadCompat(nil).IsLegacy, false)
end)

test("legacy script globals become normalized callback arguments", function()
    local compat = loadCompat("1.12.1")
    local widget = frame()
    local seen = {}
    compat.SetScript(widget, "OnEvent", function(self, name, a, b, c)
        seen.self, seen.name, seen.a, seen.b, seen.c = self, name, a, b, c
    end)
    this, event, arg1, arg2, arg3 = widget, "LOOT_OPENED", "first", 2, true
    widget.scripts.OnEvent()
    equal(seen.self, widget)
    equal(seen.name, "LOOT_OPENED")
    equal(seen.a, "first")
    equal(seen.b, 2)
    equal(seen.c, true)
    compat.SetScript(widget, "OnUpdate", function(self, elapsed) seen.elapsed = elapsed end)
    arg1 = 0.25
    widget.scripts.OnUpdate()
    equal(seen.elapsed, 0.25)
    compat.SetScript(widget, "OnValueChanged", function(self, value) seen.value = value end)
    arg1, widget.value = nil, 4
    widget.scripts.OnValueChanged()
    equal(seen.value, 4)
    this, event, arg1, arg2, arg3 = nil, nil, nil, nil, nil
end)

test("modern explicit script parameters are preserved", function()
    local compat = loadCompat("1.15.9")
    local widget, observed = frame(), {}
    compat.SetScript(widget, "OnEvent", function(self, name, a, b, c, d)
        observed = { self, name, a, b, c, d }
    end)
    widget.scripts.OnEvent(widget, "UNIT_SPELLCAST_SENT", "player", "item", "cast", 13262)
    equal(observed[1], widget)
    equal(observed[2], "UNIT_SPELLCAST_SENT")
    equal(observed[6], 13262)
    compat.SetScript(widget, "OnEvent", nil)
    equal(widget.scripts.OnEvent, nil)
end)

test("legacy-safe sizing event registration and GUID access avoid newer APIs", function()
    local compat = loadCompat("1.12.1")
    local widget = frame()
    compat.SetSize(widget, 700, 500)
    equal(widget.width, 700)
    equal(widget.height, 500)
    equal(compat.RegisterEvent(widget, "LOOT_OPENED"), true)
    equal(compat.RegisterEvent(widget, "UNSUPPORTED"), false)
    UnitGUID = nil
    UnitExists = function(unit) return true, "0xF130000001000001" end
    equal(compat.UnitGUIDSafe("target"), "0xF130000001000001")
    UnitGUID = function() return "Creature-modern" end
    equal(compat.UnitGUIDSafe("target"), "Creature-modern")
    UnitGUID, UnitExists = nil, nil
end)

test("loot adapters normalize quality slot type and source pairs", function()
    local compat = loadCompat("1.12.1")
    GetLootSlotInfo = function() return "icon", "Item", 2, 3 end
    local icon, name, quantity, quality = compat.GetLootSlotInfo(1)
    equal(icon, "icon"); equal(name, "Item"); equal(quantity, 2); equal(quality, 3)
    GetLootSlotType = nil
    LootSlotIsItem = function(slot) return slot == 1 end
    LootSlotIsCoin = function(slot) return slot == 2 end
    equal(compat.LootSlotType(1), 1)
    equal(compat.LootSlotType(2), 2)
    compat = loadCompat("1.15.9")
    GetLootSlotInfo = function() return "icon", "Item", 2, 0, 4 end
    icon, name, quantity, quality = compat.GetLootSlotInfo(1)
    equal(quality, 4)
    GetLootSourceInfo = function() return "Creature-one", 2, "Creature-two", 3 end
    local sources = compat.GetLootSources(1)
    equal(table.getn(sources), 2)
    equal(sources[2].guid, "Creature-two")
    equal(sources[2].quantity, 3)
    GetLootSourceInfo = nil
    equal(table.getn(compat.GetLootSources(1)), 0)
end)

test("deferred callbacks run on old OnUpdate and can enqueue another timer", function()
    C_Timer = nil
    local compat = loadCompat("1.12.1")
    clock = 100
    local calls = 0
    compat.After(0.2, function()
        calls = calls + 1
        compat.After(0.2, function() calls = calls + 1 end)
    end)
    local timer = frames[table.getn(frames)]
    this, arg1 = timer, 0.1
    clock = 100.1
    timer.scripts.OnUpdate()
    equal(calls, 0)
    clock = 100.21
    timer.scripts.OnUpdate()
    equal(calls, 1)
    clock = 100.42
    timer.scripts.OnUpdate()
    equal(calls, 2)
    equal(timer.shown, false)
    this, arg1 = nil, nil
    local nativeCalled
    C_Timer = { After = function(delay, callback) nativeCalled = delay; callback() end }
    compat.After(1, function() calls = calls + 1 end)
    equal(nativeCalled, 1)
    equal(calls, 3)
    C_Timer = nil
end)

test("chat link and tooltip helpers accept vanilla APIs", function()
    local compat = loadCompat("1.12.1")
    IsModifiedClick, ChatEdit_InsertLink = nil, nil
    IsShiftKeyDown = function() return true end
    equal(compat.IsChatLinkModified(), true)
    local edit = frame()
    function edit:Insert(value) self.text = value end
    ChatFrameEditBox = edit
    equal(compat.InsertLink("item:2589"), true)
    equal(edit.shown, true)
    equal(edit.text, "item:2589")
    local tooltip = {}
    function tooltip:SetHyperlink(link) self.link = link end
    equal(compat.TooltipItem(tooltip, "|cffffffff|Hitem:2589:0|h[Linen Cloth]|h|r"), true)
    equal(tooltip.link, "item:2589:0")
    equal(compat.Match("Linen Cloth dies.", "^(.-) dies%.$"), "Linen Cloth")
end)

print(string.format("%d compatibility tests passed", passed))
