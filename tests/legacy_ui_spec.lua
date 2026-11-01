-- Run unchanged in real Lua 5.0: Vanilla globals and APIs only.
local frames, chat, slots = {}, {}, {}
local clock, stamp = 100, 1700000000
local notices, vendorPrices = {}, {}
local targetGUID, popup = "0xF130000001000001", nil
local fire
local Widget = {}
local noops = {}
local allowed = {
    "SetPoint", "SetFrameStrata", "SetClampedToScreen", "SetMovable",
    "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
    "SetBackdropColor", "SetJustifyH", "SetTexture", "SetMultiLine",
    "SetAutoFocus", "SetFontObject", "SetMaxLetters", "UpdateScrollChildRect",
    "SetScrollChild", "SetFocus", "ClearFocus", "HighlightText", "SetOwner",
    "SetOrientation", "SetValueStep", "SetThumbTexture", "EnableMouseWheel",
}
for _, name in ipairs(allowed) do noops[name] = function() end end
local unavailable = { SetSize = true, SetObeyStepOnDrag = true }
Widget.__index = function(object, key)
    if unavailable[key] then return nil end
    if Widget[key] then return Widget[key] end
    if noops[key] then return noops[key] end
    error("Vanilla mock has no widget method/property: " .. tostring(key))
end

local function widget(kind, name, parent, template)
    local result = setmetatable({ kind = kind, name = name, parent = parent,
        template = template, scripts = {}, events = {}, shown = true,
        width = 600, height = 400, text = "", value = 0, fontPath = "Fonts\\FRIZQT__.TTF", fontSize = 12, fontFlags = "" }, Widget)
    frames[table.getn(frames) + 1] = result
    if name then _G[name] = result end
    return result
end

fire = function(object, script, a, b, c, d)
    local previousThis, previousEvent = this, event
    local previous1, previous2, previous3, previous4 = arg1, arg2, arg3, arg4
    this, event = object, nil
    arg1, arg2, arg3, arg4 = a, b, c, d
    if object.scripts[script] then object.scripts[script]() end
    this, event = previousThis, previousEvent
    arg1, arg2, arg3, arg4 = previous1, previous2, previous3, previous4
end

function Widget:SetScript(script, callback) self.scripts[script] = callback end
function Widget:GetScript(script) return self.scripts[script] end
function Widget:RegisterEvent(name) self.events[name] = true end
function Widget:UnregisterEvent(name) self.events[name] = nil end
function Widget:SetWidth(value)
    local changed = self.width ~= value
    self.width = value
    if changed then fire(self, "OnSizeChanged", value, self.height) end
end
function Widget:SetHeight(value)
    local changed = self.height ~= value
    self.height = value
    if changed then fire(self, "OnSizeChanged", self.width, value) end
end
function Widget:SetPoint(point, relative, relativePoint, x, y)
    self.anchor = { point, relative, relativePoint, x, y }
end
function Widget:ClearAllPoints() self.anchor = nil end
function Widget:SetResizable(value) self.resizable = value end
function Widget:SetMinResize(width, height) self.minWidth, self.minHeight = width, height end
function Widget:SetMaxResize(width, height) self.maxWidth, self.maxHeight = width, height end
function Widget:StartSizing(direction) self.sizing = direction end
function Widget:StopMovingOrSizing() self.sizing = false end
function Widget:GetFont() return self.fontPath, self.fontSize, self.fontFlags end
function Widget:SetFont(path, size, flags) self.fontPath, self.fontSize, self.fontFlags = path, size, flags end
function Widget:SetScale(scale) self.scale = scale end
function Widget:GetScale() return self.scale or 1 end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:SetText(value) self.text = tostring(value or "") end
function Widget:GetText() return self.text end
function Widget:GetName() return self.name end
function Widget:GetParent() return self.parent end
function Widget:CreateFontString(name, layer, template)
    local font = widget("FontString", name, self)
    if template == "GameFontNormalLarge" then font.fontSize = 16 end
    return font
end
function Widget:CreateTexture(name) return widget("Texture", name, self) end
function Widget:GetFontString()
    local font = rawget(self, "buttonFont")
    if not font then
        font = widget("FontString", nil, self)
        self.buttonFont = font
    end
    return font
end
function Widget:SetAllPoints(relative) self.allPoints = relative end
function Widget:SetBackdrop(value) self.backdrop = value end
function Widget:SetHyperlink(value) self.hyperlink = value end
function Widget:IsShown() return self.shown end
function Widget:IsVisible() return self.shown end
function Widget:Show()
    local previous = self.shown
    self.shown = true
    if not previous then fire(self, "OnShow") end
end
function Widget:Hide()
    local previous = self.shown
    self.shown = false
    if previous then fire(self, "OnHide") end
end
function Widget:SetValue(value)
    self.value = value
    fire(self, "OnValueChanged", value)
end
function Widget:GetValue() return self.value end
function Widget:SetMinMaxValues(low, high) self.minimum, self.maximum = low, high end
function Widget:GetMinMaxValues() return self.minimum or 0, self.maximum or 1 end
function Widget:Enable() self.enabled = true end
function Widget:Disable() self.enabled = false end
function Widget:IsEnabled() return self.enabled ~= false end

UIParent = widget("Frame", "UIParent")
GameTooltip = widget("GameTooltip", "GameTooltip")
ChatFrameEditBox = widget("EditBox", "ChatFrameEditBox")
function ChatFrameEditBox:Insert(text) self.text = self.text .. text end
DEFAULT_CHAT_FRAME = { AddMessage = function(object, text) chat[table.getn(chat) + 1] = text end }
UIErrorsFrame = { AddMessage = function(object, text) notices[table.getn(notices) + 1] = text end }
UISpecialFrames, SlashCmdList, StaticPopupDialogs = {}, {}, {}
ChatFontNormal = {}
NUM_BAG_SLOTS = 4
LOOT_SLOT_ITEM, LOOT_SLOT_MONEY, LOOT_SLOT_CURRENCY = 1, 2, 3
function CreateFrame(kind, name, parent, template)
    if template == "UIPanelScrollFrameTemplate" then
        assert(type(name) == "string" and name ~= "", "Vanilla scroll templates require a global frame name")
    end
    return widget(kind, name, parent, template)
end
-- Private clients can report a custom version while retaining Vanilla APIs.
-- In particular the slider below deliberately has no SetObeyStepOnDrag method.
function GetBuildInfo() return "1.18.0", "OctoWoW custom build", "" end
function GetTime() return clock end
function time() return stamp end
function date(pattern, value) return os.date(pattern, value or stamp) end
function GetNumLootItems() return table.getn(slots) end
function GetLootSlotInfo(index)
    local slot = slots[index]
    return slot.icon, slot.name, slot.quantity, slot.quality
end
function GetLootSlotLink(index) return slots[index].link end
function GetItemInfo(link)
    local first, last, id = string.find(tostring(link), "item:(%d+)")
    if not id then first, last, id = string.find(tostring(link), "^(%d+)$") end
    return "Test item", link, 1, 1, 1, "Miscellaneous", "Junk", 20, "", "icon", vendorPrices[tonumber(id)]
end
function LootSlotIsItem(index) return slots[index].kind ~= "money" and slots[index].name ~= nil end
function LootSlotIsCoin(index) return slots[index].kind == "money" end
function UnitExists(unit)
    if unit == "target" then return 1, targetGUID end
    if unit == "player" then return 1, "0x0000000000000001" end
end
-- A backported GUID helper does not imply modern loot or widget APIs.
function UnitGUID(unit)
    local exists, guid = UnitExists(unit)
    return exists and guid or nil
end
function UnitName(unit) if unit == "target" then return "Forest Wolf" end; return "Testplayer" end
function UnitIsDead(unit) return unit == "target" end
function UnitIsPlayer(unit) return unit == "player" end
function UnitCanAttack(first, second) return second == "target" end
function UnitIsFriend(first, second) return second ~= "target" end
function GetContainerNumSlots() return 0 end
function GetContainerItemInfo() return nil end
function GetContainerItemLink() return nil end
function IsShiftKeyDown() return false end
function GetNumPartyMembers() return 0 end
function GetNumRaidMembers() return 0 end
function StaticPopup_Show(name)
    assert(StaticPopupDialogs[name], "reset dialog must be registered")
    popup = StaticPopupDialogs[name]
end

local function dispatch(name, a, b, c, d)
    local previousThis, previousEvent = this, event
    local previous1, previous2, previous3, previous4 = arg1, arg2, arg3, arg4
    for index = 1, table.getn(frames) do
        local frame = frames[index]
        if frame.events[name] and frame.scripts.OnEvent then
            this, event = frame, name
            arg1, arg2, arg3, arg4 = a, b, c, d
            frame.scripts.OnEvent()
        end
    end
    this, event = previousThis, previousEvent
    arg1, arg2, arg3, arg4 = previous1, previous2, previous3, previous4
end

local function tick(elapsed)
    clock = clock + elapsed
    for index = 1, table.getn(frames) do
        local frame = frames[index]
        if frame.shown and frame.scripts.OnUpdate then fire(frame, "OnUpdate", elapsed) end
    end
end

local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function item(quantity, id, name)
    return { icon = "Interface\\Icons\\INV_Fabric_Linen_01", name = name or "Linen Cloth",
        link = "|cffffffff|Hitem:" .. (id or 2589) .. ":0:0:0|h[" .. (name or "Linen Cloth") .. "]|h|r",
        quantity = quantity, quality = 2 }
end

ClassicLootLogNS = {}
assert(loadfile("ClassicLootLog/Compat.lua"))()
assert(loadfile("ClassicLootLog/Core.lua"))()
assert(loadfile("ClassicLootLog/Tracking.lua"))()
assert(loadfile("ClassicLootLog/Value.lua"))()
assert(loadfile("ClassicLootLog/Main.lua"))()
local ns = ClassicLootLogNS
local passed = 0
local function test(name, callback)
    callback()
    passed = passed + 1
    print("PASS " .. name)
end
local function reset()
    dispatch("LOOT_CLOSED")
    SlashCmdList.CLASSICLOOTLOG("reset")
    assert(popup)
    popup.OnAccept()
    ns.App:SetView("loot")
    if ClassicLootLogDB.timer.enabled then SlashCmdList.CLASSICLOOTLOG("timer off") end
    slots = {}
end

test("custom-version Octo client initializes without modern slider methods", function()
    equal(ns.Compat.IsLegacy, true)
    equal(ns.Compat.ClientVersion, "1.18.0")
    dispatch("ADDON_LOADED", "DifferentAddon")
    equal(ClassicLootLogDB, nil)
    dispatch("ADDON_LOADED", "Test-plugin")
    assert(ClassicLootLogDB and ns.App.frame)
    equal(SLASH_CLASSICLOOTLOG1, "/cll")
    assert(string.find(ns.App.timerButton:GetText(), "OFF", 1, true))
    assert(ns.App.frame.backdrop)
    assert(string.find(ns.App.frame.backdrop.edgeFile, "DialogBox", 1, true))
end)

test("launcher and manual copies share one App without replacing the active database", function()
    local app, database, count = ns.App, ClassicLootLogDB, table.getn(frames)
    assert(loadfile("ClassicLootLog/Main.lua"))()
    equal(ns.App, app)
    equal(table.getn(frames), count)
    ClassicLootLogDB = { entries = {} }
    dispatch("ADDON_LOADED", "ClassicLootLog")
    equal(ns.App, app)
    equal(ClassicLootLogDB, database)
    equal(ns.App.db, database)
end)

test("Vanilla loot uses fourth-return quality and extended target GUID deduplication", function()
    slots = { item(3) }
    dispatch("LOOT_OPENED")
    equal(table.getn(ClassicLootLogDB.entries), 1)
    equal(ClassicLootLogDB.entries[1].quantity, 3)
    equal(ClassicLootLogDB.entries[1].quality, 2)
    dispatch("LOOT_CLOSED")
    dispatch("LOOT_OPENED")
    equal(table.getn(ClassicLootLogDB.entries), 1)
    dispatch("LOOT_CLOSED")
    targetGUID = "0xF130000001000002"
    dispatch("LOOT_OPENED")
    equal(table.getn(ClassicLootLogDB.entries), 2)
end)

test("Vanilla coin APIs preserve money labels without modern slot-type APIs", function()
    reset()
    targetGUID = "0xF130000001000003"
    slots = { { name = "12 Copper", quantity = 0, quality = 0, kind = "money" } }
    dispatch("LOOT_OPENED")
    equal(ClassicLootLogDB.entries[1].kind, "money")
    equal(ns.App.rows[1].item:GetText(), "12 Copper")
end)

test("Vanilla global arg1 drives stopwatch updates and paused time stays excluded", function()
    reset()
    SlashCmdList.CLASSICLOOTLOG("show")
    SlashCmdList.CLASSICLOOTLOG("timer on")
    tick(5)
    targetGUID = "0xF130000001000004"
    slots = { item(1) }
    dispatch("LOOT_OPENED")
    equal(ClassicLootLogDB.entries[1].elapsed, 5)
    assert(string.find(ns.App.timerText:GetText(), "00:00:05", 1, true))
    SlashCmdList.CLASSICLOOTLOG("timer off")
    tick(10)
    equal(ns.Core.TimerElapsed(ClassicLootLogDB, clock), 5)
end)

test("Vanilla stats selection and DE correction preserve original item shares", function()
    reset()
    targetGUID = "0xF130000001000005"
    slots = { item(3), item(7, 2592, "Wool Cloth") }
    dispatch("LOOT_OPENED")
    ns.App:SetView("stats")
    equal(ns.Core.ItemStats(ClassicLootLogDB).totalQuantity, 10)
    equal(ns.App.rows[1].percent:GetText(), "70.0%")
    ns.App:SetView("loot")
    fire(ns.App.rows[1], "OnClick", "LeftButton")
    equal(ns.App:MarkSelectedDisenchanted(1), 1)
    equal(ns.Core.ItemStats(ClassicLootLogDB).totalDisenchanted, 1)
    equal(ns.App:UnmarkSelectedDisenchanted(1), 1)
    ns.App:ShowExport()
    assert(string.find(ns.App.exportFrame.edit:GetText(), "Date/time", 1, true))
    ns.App:ShowExport("stats")
    assert(string.find(ns.App.exportFrame.edit:GetText(), "Mobs per hour", 1, true))
end)

test("fallback delayed callbacks run through Vanilla OnUpdate globals", function()
    local calls = 0
    ns.Compat.After(0.2, function() calls = calls + 1 end)
    tick(0.1)
    equal(calls, 0)
    tick(0.2)
    equal(calls, 1)
    tick(1)
    equal(calls, 1)
end)

test("Vanilla reset requires confirmation and clears loot and mob counters", function()
    ns.Core.RecordMobKill(ClassicLootLogDB, "test-kill", "Wolf", stamp, clock)
    local before = table.getn(ClassicLootLogDB.entries)
    SlashCmdList.CLASSICLOOTLOG("reset")
    equal(table.getn(ClassicLootLogDB.entries), before)
    popup.OnAccept()
    equal(table.getn(ClassicLootLogDB.entries), 0)
    equal(ns.Core.MobStats(ClassicLootLogDB, clock).total, 0)
end)

test("Vanilla resizing reflows text and columns and the size lock controls its grip", function()
    reset()
    ns.App:SetSizeLocked(false)
    ns.App:SetAutoText(true)
    ns.App:Resize(900, 590)
    local path, baseFont = ns.App.rows[1].item:GetFont()
    local baseWidth = ns.App.rows[1].item:GetWidth()
    ns.App:Resize(680, 430)
    local smallPath, smallFont = ns.App.rows[1].item:GetFont()
    assert(smallFont < baseFont)
    assert(ns.App.rows[1].item:GetWidth() < baseWidth)
    equal(ClassicLootLogDB.ui.width, 680)
    equal(ClassicLootLogDB.ui.height, 430)
    ns.App:SetAutoText(false)
    local fixedPath, fixedFont = ns.App.rows[1].item:GetFont()
    equal(fixedFont, baseFont)
    ns.App:Resize(1280, 900)
    fixedPath, fixedFont = ns.App.rows[1].item:GetFont()
    equal(fixedFont, baseFont)
    ns.App:SetSizeLocked(true)
    equal(ns.App.resizeGrip:IsShown(), false)
    ns.App.frame.sizing = false
    fire(ns.App.resizeGrip, "OnMouseDown", "LeftButton")
    equal(ns.App.frame.sizing, false)
    ns.App:SetSizeLocked(false)
    fire(ns.App.resizeGrip, "OnMouseDown", "LeftButton")
    equal(ns.App.frame.sizing, "BOTTOMRIGHT")
    fire(ns.App.resizeGrip, "OnMouseUp", "LeftButton")
    equal(ns.App.frame.sizing, false)
    ns.App:SetAutoText(true)
    ns.App:Resize(900, 590)
end)

test("Vanilla vendor display supports known and manually supplied prices", function()
    reset()
    vendorPrices = {[2589] = 75}
    ClassicLootLogDB.vendorPrices = {}
    targetGUID = "0xF130000001000020"
    slots = {item(2), item(1, 15210, "Sword")}
    dispatch("LOOT_OPENED")
    equal(ns.App.rows[1].vendor:GetText(), "Unknown")
    equal(ns.App.rows[2].vendor:GetText(), "1s 50c")
    SlashCmdList.CLASSICLOOTLOG("price 15210 500")
    equal(ns.App.rows[1].vendor:GetText(), "5s 0c")
    ns.App:SelectEntry(ClassicLootLogDB.entries[1].id)
    equal(ns.App:MarkSelectedDisenchanted(1), 1)
    equal(ns.App.rows[2].vendor:GetText(), "75c")
    vendorPrices = {}
end)

test("Vanilla epic quality from the fourth loot return creates one purple-drop notification", function()
    reset()
    ClassicLootLogDB.alerts.epic = true
    local before = table.getn(notices)
    targetGUID = "0xF130000001000021"
    local epic = item(1, 873, "Epic Weapon")
    epic.quality = 4
    slots = {epic}
    dispatch("LOOT_OPENED")
    equal(table.getn(notices), before + 1)
    assert(string.find(notices[table.getn(notices)], "EPIC LOOT", 1, true))
    dispatch("LOOT_CLOSED")
    dispatch("LOOT_OPENED")
    equal(table.getn(notices), before + 1)
    dispatch("LOOT_CLOSED")
    ClassicLootLogDB.alerts.epic = false
    targetGUID = "0xF130000001000022"
    dispatch("LOOT_OPENED")
    equal(table.getn(notices), before + 1)
    ClassicLootLogDB.alerts.epic = true
end)

print(passed .. " legacy UI tests passed")
