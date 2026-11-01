-- Run unchanged in real Lua 5.0: Vanilla globals and APIs only.
local frames, chat, slots, bags = {}, {}, {}, {}
local clock, stamp = 100, 1700000000
local notices, vendorPrices = {}, {}
local lootMethod, partyCount, raidCount = "freeforall", 0, 0
local lootRolls = {}
local money, buybacks, merchantAction = 100000, {}, nil
local groupNames = {player = "Testplayer", pet = "Testpet", party1 = "Alice", party2 = "Bob", party3 = "Cara"}
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
function Widget:GetVerticalScroll() return self.scroll or 0 end
function Widget:SetVerticalScroll(value) self.scroll = value end
function Widget:GetVerticalScrollRange() return 500 end
function Widget:Enable() self.enabled = true end
function Widget:Disable() self.enabled = false end
function Widget:IsEnabled() return self.enabled ~= false end

UIParent = widget("Frame", "UIParent")
GameTooltip = widget("GameTooltip", "GameTooltip")
MerchantFrame = widget("Frame", "MerchantFrame")
MerchantFrame:Hide()
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
function UnitName(unit)
    if unit == "target" then return "Forest Wolf" end
    if unit == "player" or unit == "pet" then return groupNames[unit] end
    local first, last, party = string.find(unit or "", "^party(%d+)$")
    if party and tonumber(party) <= partyCount then return groupNames[unit] end
    return nil
end
function UnitIsDead(unit) return unit == "target" end
function UnitIsPlayer(unit) return unit == "player" end
function UnitCanAttack(first, second) return second == "target" end
function UnitIsFriend(first, second) return second ~= "target" end
function GetContainerNumSlots(bag) return table.getn(bags[bag] or {}) end
function GetContainerItemInfo(bag, index)
    local entry = bags[bag] and bags[bag][index]
    if entry then return entry.icon or "icon", entry.quantity, false, entry.quality, false, false, entry.link end
end
function GetContainerItemLink(bag, index)
    return bags[bag] and bags[bag][index] and bags[bag][index].link
end
function GetMoney() return money end
function UseContainerItem(bag, index, onSelf)
    if merchantAction then merchantAction(bag, index, onSelf) end
    return "native-use-return"
end
function BuybackItem(index)
    local entry = buybacks[index]
    if entry then
        bags[0] = bags[0] or {}
        bags[0][1] = {link = entry.link, name = entry.name, quantity = entry.quantity, icon = "icon", quality = 1}
        money = money - entry.price
        table.remove(buybacks, index)
    end
    return "native-buyback-return"
end
function GetNumBuybackItems() return table.getn(buybacks) end
function GetBuybackItemInfo(index)
    local entry = buybacks[index]
    if entry then return entry.name, "icon", entry.price, entry.quantity end
end
function GetBuybackItemLink(index) return buybacks[index] and buybacks[index].link end
function IsShiftKeyDown() return false end
function GetNumPartyMembers() return partyCount end
function GetNumRaidMembers() return raidCount end
function GetLootMethod() return lootMethod, 0, 0 end
function GetLootRollItemLink(rollID) return lootRolls[rollID] and lootRolls[rollID].link end
function GetLootRollItemInfo(rollID)
    local roll = lootRolls[rollID]
    if roll then return "icon", roll.name, roll.quantity or 1, roll.quality or 4, false, true, true end
end
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
assert(loadfile("ClassicLootLog/GroupLoot.lua"))()
assert(loadfile("ClassicLootLog/GroupEvents.lua"))()
assert(loadfile("ClassicLootLog/Finance.lua"))()
assert(loadfile("ClassicLootLog/Merchant.lua"))()
assert(loadfile("ClassicLootLog/Mini.lua"))()
assert(loadfile("ClassicLootLog/FileExport.lua"))()
assert(loadfile("ClassicLootLog/SavedLogs.lua"))()
assert(loadfile("ClassicLootLog/MinimapButton.lua"))()
assert(loadfile("ClassicLootLog/LogsPanel.lua"))()
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
    slots, bags = {}, {}
    money, buybacks, merchantAction = 100000, {}, nil
    MerchantFrame:Hide()
    if ns.App.merchant then ns.App.merchant:Reset() end
    lootMethod, partyCount, raidCount = "freeforall", 0, 0
    lootRolls = {}
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


local function groupLink(id, name)
    return "|cffa335ee|Hitem:" .. id .. ":0:0:0|h[" .. name .. "]|h|r"
end

test("Vanilla title is anchored inside its header and the Commands tab lists slash commands", function()
    reset()
    local title, header = ns.App.frame.titleText, ns.App.frame.header
    assert(header)
    equal(title.anchor[1], "CENTER")
    equal(title.anchor[2], header)
    equal(title.anchor[3], "CENTER")
    ns.App:Resize(680, 430)
    equal(title.anchor[1], "CENTER")
    equal(title.anchor[2], header)
    ns.App:Resize(900, 590)
    SlashCmdList.CLASSICLOOTLOG("commands")
    equal(ns.App.tab, "commands")
    local commands, text = ns.App:GetCommands(), ""
    assert(table.getn(commands) >= 15)
    for _, command in ipairs(commands) do
        assert(command.command and command.description)
        text = text .. command.command .. "\n"
    end
    assert(string.find(text, "/cll group", 1, true))
    assert(string.find(text, "/cll track", 1, true))
    assert(string.find(text, "/cll price", 1, true))
    ns.App:SetView("loot")
    equal(ns.App.tab, "loot")
end)

test("Vanilla group-loot messages populate need greed rankings and the actual loot recipient", function()
    reset()
    lootMethod, partyCount = "group", 3
    local link = groupLink(18803, "Vanilla group epic")
    lootRolls[901] = {link = link, name = "Vanilla group epic", quality = 4}
    dispatch("START_LOOT_ROLL", 901, 60000)
    dispatch("CHAT_MSG_LOOT", "Alice has selected Need for: " .. link)
    dispatch("CHAT_MSG_LOOT", "Bob has selected Greed for: " .. link)
    dispatch("CHAT_MSG_LOOT", "Cara has selected Need for: " .. link)
    dispatch("CHAT_MSG_LOOT", "Need Roll - 91 for " .. link .. " by Alice")
    dispatch("CHAT_MSG_LOOT", "Need Roll - 84 for " .. link .. " by Cara")
    dispatch("CHAT_MSG_LOOT", "Greed Roll - 99 for " .. link .. " by Bob")
    dispatch("CHAT_MSG_LOOT", "Alice receives loot: " .. link .. ".")
    local entries = ClassicLootLogDB.groupLoot.entries
    equal(table.getn(entries), 1)
    local entry = entries[1]
    equal(entry.recipient, "Alice")
    equal(entry.distributionMethod, "group")
    local rankings = ns.App.groupAdapter.model:Rankings(entry)
    equal(rankings.highest.player, "Alice")
    equal(rankings.highest.value, 91)
    equal(rankings.second.player, "Cara")
    equal(rankings.second.value, 84)
    SlashCmdList.CLASSICLOOTLOG("group")
    equal(ns.App.tab, "group")
    assert(string.find(ns.App.groupRows[1].winner:GetText(), "Alice", 1, true))
    assert(string.find(ns.App.groupRows[1].highest:GetText(), "91", 1, true))
    assert(string.find(ns.App.groupRows[1].second:GetText(), "84", 1, true))
end)

test("Vanilla master-loot slash rolls and EPGP bids retain method and receipt-confirmed winner", function()
    reset()
    lootMethod, partyCount = "master", 3
    local link = groupLink(18809, "Vanilla master epic")
    local entry = ns.App.groupAdapter:BeginItem(link, "master")
    ns.App:SelectGroupEntry(entry.id)
    dispatch("CHAT_MSG_SYSTEM", "Alice rolls 61 (1-100)")
    dispatch("CHAT_MSG_SYSTEM", "Bob rolls 89 (1-100)")
    dispatch("CHAT_MSG_LOOT", "Bob receives loot: " .. link .. ".")
    equal(entry.recipient, "Bob")
    equal(entry.distributionMethod, "master")
    local rankings = ns.App.groupAdapter.model:Rankings(entry)
    equal(rankings.highest.player, "Bob")
    equal(rankings.second.player, "Alice")
    link = groupLink(18816, "Vanilla EPGP epic")
    entry = ns.App.groupAdapter:BeginItem(link, "master")
    ns.App:SelectGroupEntry(entry.id)
    dispatch("CHAT_MSG_PARTY", "m.A.X!", "Alice")
    dispatch("CHAT_MSG_PARTY", "n33d", "Bob")
    dispatch("CHAT_MSG_PARTY", "m i n", "Cara")
    dispatch("CHAT_MSG_LOOT", "Cara receives loot: " .. link .. ".")
    equal(entry.method, "epgp")
    equal(entry.distributionMethod, "master")
    equal(entry.recipient, "Cara")
    equal(entry.winnerBid, "MIN")
    ns.App:SetTab("group")
    assert(string.find(ns.App.groupRows[1].winner:GetText(), "Cara", 1, true))
    assert(string.find(ns.App.groupRows[1].bid:GetText(), "MIN", 1, true))
    ns.App:ShowExport("group")
    assert(string.find(ns.App.exportFrame.edit:GetText(), "Cara", 1, true))
end)

test("Vanilla slash sl toggles a separate three-metric view without opening the main frame", function()
    reset()
    ns.App.frame:Hide()
    ns.App.mini:Hide()
    equal(SLASH_CLASSICLOOTLOGMINI1, "/sl")
    assert(type(SlashCmdList.CLASSICLOOTLOGMINI) == "function")
    SlashCmdList.CLASSICLOOTLOGMINI("")
    equal(ns.App.mini.frame:IsShown(), true)
    equal(ns.App.frame:IsShown(), false)
    equal(ClassicLootLogDB.ui.miniVisible, true)
    local count = 0
    for _, object in ipairs(frames) do
        if rawget(object, "parent") == ns.App.mini.frame and object.kind == "FontString" then count = count + 1 end
    end
    equal(count, 3)
    SlashCmdList.CLASSICLOOTLOGMINI("")
    equal(ns.App.mini.frame:IsShown(), false)
    equal(ClassicLootLogDB.ui.miniVisible, false)
end)

test("Vanilla mini window refreshes via global OnUpdate arguments while the full UI stays hidden", function()
    reset()
    clock = 5000
    ns.App.frame:Hide()
    ns.App.mini:Show()
    SlashCmdList.CLASSICLOOTLOG("timer on")
    ns.Core.RecordMobKill(ClassicLootLogDB, "mini-vanilla-timed", "Wolf", stamp, clock)
    tick(60)
    assert(string.find(ns.App.mini.mobsPerHour:GetText(), "60.0", 1, true))
    assert(string.find(ns.App.mini.timer:GetText(), "00:01:00", 1, true))
    equal(ns.App.mini.kills:GetText(), "Kills: 1")
    SlashCmdList.CLASSICLOOTLOG("timer off")
    ns.Core.RecordMobKill(ClassicLootLogDB, "mini-vanilla-paused", "Wolf", stamp, clock)
    tick(60)
    assert(string.find(ns.App.mini.mobsPerHour:GetText(), "60.0", 1, true))
    assert(string.find(ns.App.mini.timer:GetText(), "paused", 1, true))
    equal(ns.App.mini.kills:GetText(), "Kills: 2")
    SlashCmdList.CLASSICLOOTLOG("reset")
    popup.OnAccept()
    tick(0.3)
    equal(ns.App.mini.kills:GetText(), "Kills: 0")
    assert(string.find(ns.App.mini.timer:GetText(), "00:00:00", 1, true))
    equal(ns.App.frame:IsShown(), false)
    equal(ns.App.mini.frame:IsShown(), true)
    ns.App.mini:Hide()
end)

test("Vanilla save-all archives all tabs and opens the saved report without a file patch", function()
    reset()
    stamp = 1700000000
    targetGUID = "0xF13000000100E001"
    slots = {item(2, 2589, "Export Linen")}
    dispatch("LOOT_OPENED")
    local context = ns.App.groupAdapter.model:StartItem(groupLink(18809, "Export Party Item"), "master", {select = true})
    ns.App.groupAdapter.model:AddBid(context, "Bob", "NEED")
    ns.App.groupAdapter.model:Award(context.link, "Bob", {contextID = context.id})
    ns.App:SetTab("commands")
    WriteCustomFile, ReadCustomFile, ExportFile, ImportFile = nil, nil, nil, nil
    local before = table.getn(ns.SavedLogs.Entries(ClassicLootLogDB))
    local saved = ns.App:SaveAllLogs()
    assert(saved and saved.id and saved.text)
    assert(string.find(saved.title, "_Testplayer", 1, true))
    assert(string.find(saved.title, "^%d%d%d%d%-%d%d%-%d%d_%d%d%-%d%d%-%d%d_"))
    equal(table.getn(ns.SavedLogs.Entries(ClassicLootLogDB)), before + 1)
    equal(ns.App.tab, "logs")
    assert(ns.App.savedLogsPanel.frame:IsShown())
    equal(ns.App.savedLogsPanel.selectedID, saved.id)
    equal(ns.App.savedLogsPanel.edit:GetText(), saved.text)
    assert(string.find(saved.text, "Export Linen", 1, true))
    assert(string.find(saved.text, "Export Party Item", 1, true))
    assert(string.find(saved.text, "Bob", 1, true))
    assert(string.find(saved.text, "NEED", 1, true))
    equal(ClassicLootLogDB.pendingFileExports, nil)
end)

test("Vanilla archived reports survive reset and reopen unchanged through the Saved Logs tab", function()
    reset()
    targetGUID = "0xF13000000100E002"
    slots = {item(4, 2589, "Preserved Linen")}
    dispatch("LOOT_OPENED")
    local function forbidden() error("saving inside the addon must not use a file API") end
    WriteCustomFile, ReadCustomFile, ExportFile, ImportFile = forbidden, forbidden, forbidden, forbidden
    local saved = ns.App:SaveAllLogs()
    local text = saved.text
    reset()
    equal(table.getn(ClassicLootLogDB.entries), 0)
    equal(ns.SavedLogs.Get(ClassicLootLogDB, saved.id).text, text)
    local nextLog = ns.App:SaveAllLogs()
    assert(nextLog.id ~= saved.id)
    assert(nextLog.title ~= saved.title)
    equal(saved.text, text)
    assert(string.find(saved.text, "Preserved Linen", 1, true))
    assert(not string.find(nextLog.text, "Preserved Linen", 1, true))
    ns.App.frame:Hide()
    SlashCmdList.CLASSICLOOTLOG("logs")
    equal(ns.App.tab, "logs")
    equal(ns.App.frame:IsShown(), true)
    local found = false
    for _, row in ipairs(ns.App.savedLogsPanel.rows) do
        if rawget(row, "entry") and row.entry.id == saved.id then
            fire(row, "OnClick", "LeftButton")
            found = true
        end
    end
    assert(found, "the archived report must remain selectable after a session reset")
    equal(ns.App.savedLogsPanel.selectedID, saved.id)
    equal(ns.App.savedLogsPanel.edit:GetText(), text)
    ns.App.savedLogsPanel.reportScroll:SetVerticalScroll(53)
    ns.App:Refresh()
    equal(ns.App.savedLogsPanel.reportScroll:GetVerticalScroll(), 53)
    ns.App.savedLogsPanel.edit:SetText("An accidental edit")
    fire(ns.App.savedLogsPanel.edit, "OnTextChanged")
    equal(ns.App.savedLogsPanel.edit:GetText(), text)
    equal(ns.SavedLogs.Get(ClassicLootLogDB, saved.id).text, text)
    ns.App:Resize(680, 430)
    equal(ns.App.savedLogsPanel.edit:GetText(), text)
    ns.App:Resize(900, 590)
    WriteCustomFile, ReadCustomFile, ExportFile, ImportFile = nil, nil, nil, nil
end)


test("Vanilla Finances tab shows gross gold silver copper and material totals", function()
    reset()
    ns.Value.SetPrice(ClassicLootLogDB, 2589, 100)
    targetGUID = "0xF13000FINANCE001"
    slots = {item(3, 2589, "Finance Linen")}
    dispatch("LOOT_OPENED")
    ns.Core.MarkDisenchanted(ClassicLootLogDB, "item:2589", 1, clock)
    ns.Core.AddSnapshot(ClassicLootLogDB, {
        {kind = "item", origin = "disenchant", link = "item:10978", name = "Small Glimmering Shard", quantity = 2, sourceGUID = "finance-shard"},
        {kind = "item", origin = "disenchant", link = "item:10939", name = "Greater Magic Essence", quantity = 3, sourceGUID = "finance-essence"},
    }, stamp, clock)
    SlashCmdList.CLASSICLOOTLOG("finance")
    equal(ns.App.tab, "finance")
    assert(ns.App.financePanel:IsShown())
    equal(ns.Finance.Summary(ClassicLootLogDB).dropCopper, 300)
    equal(ns.Finance.Summary(ClassicLootLogDB).totalMaterials, 5)
    assert(string.find(ns.App.financeDropValue:GetText(), "0g 3s 0c", 1, true))
    local foundShard, foundEssence = false, false
    for _, row in ipairs(ns.App.financeMaterialRows) do
        if row:IsShown() then
            if string.find(row.item:GetText(), "Small Glimmering Shard", 1, true) then foundShard = row.quantity:GetText() == "2" end
            if string.find(row.item:GetText(), "Greater Magic Essence", 1, true) then foundEssence = row.quantity:GetText() == "3" end
        end
    end
    assert(foundShard and foundEssence)
end)

test("Vanilla sale hooks confirm real income through old money and bag events", function()
    reset()
    clock = 7000
    ns.Value.SetPrice(ClassicLootLogDB, 2589, 100)
    bags[0] = {{link = "item:2589", name = "Linen Cloth", quantity = 2, icon = "icon", quality = 1}}
    MerchantFrame:Show()
    dispatch("MERCHANT_SHOW")
    merchantAction = function(bag, index)
        local sold = bags[bag][index]
        buybacks = {{name = sold.name, link = sold.link, quantity = sold.quantity, price = 200}}
        bags[bag][index] = nil
        money = money + 200
    end
    equal(UseContainerItem(0, 1), "native-use-return")
    dispatch("BAG_UPDATE", 0)
    dispatch("PLAYER_MONEY")
    tick(0.3)
    equal(ns.Finance.Summary(ClassicLootLogDB).salesCopper, 200)
    money = money + 500
    dispatch("PLAYER_MONEY")
    tick(0.3)
    equal(ns.Finance.Summary(ClassicLootLogDB).salesCopper, 200)
    ns.App:SetTab("finance")
    assert(string.find(ns.App.financeSalesValue:GetText(), "0g 2s 0c", 1, true))
    equal(BuybackItem(1), "native-buyback-return")
    dispatch("PLAYER_MONEY")
    dispatch("BAG_UPDATE", 0)
    tick(0.3)
    equal(ns.Finance.Summary(ClassicLootLogDB).buybackCopper, 200)
    equal(ns.Finance.Summary(ClassicLootLogDB).netSalesCopper, 0)
    MerchantFrame:Hide()
    dispatch("MERCHANT_CLOSED")
    merchantAction = nil
end)

print(passed .. " legacy UI tests passed")
