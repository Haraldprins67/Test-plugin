-- Behavioral smoke tests with a small WoW API substitute; no visual validation.
local ns, frames, editBoxes, timers = {}, {}, {}, {}
ClassicLootLogNS = ns
local clock, stamp, slots = 100, 1700000000, {}
local popup, chat = nil, {}
local combatLog, bags = {}, {}
local notices, vendorPrices = {}, {}
local lootMethod, partyCount, raidCount = "freeforall", 0, 0
local lootRolls = {}
local groupNames = {player = "Testspeler", pet = "Testpet", party1 = "Alice", party2 = "Bob", party3 = "Cara", raid1 = "Testspeler", raid2 = "Alice", raid3 = "Bob", raid4 = "Cara"}

local Widget = {}
local noops = {}
for method in ("SetPoint SetFrameStrata SetClampedToScreen SetMovable EnableMouse RegisterForDrag "
    .. "StartMoving StopMovingOrSizing SetBackdrop SetBackdropColor SetJustifyH SetTexture "
    .. "SetMultiLine SetAutoFocus SetFontObject SetMaxLetters UpdateScrollChildRect SetScrollChild "
    .. "SetFocus ClearFocus HighlightText SetOwner SetOrientation SetValueStep "
    .. "SetThumbTexture EnableMouseWheel"):gmatch("%S+") do
    noops[method] = function() end
end
Widget.__index = function(self, key)
    if Widget[key] then return Widget[key] end
    if noops[key] then return noops[key] end
    error("unmocked widget method/property: " .. key)
end

local function widget(kind, name, parent)
    local object = setmetatable({ kind = kind, name = name, parent = parent,
        scripts = {}, events = {}, shown = true, width = 600, height = 400,
        text = "", checked = false, value = 0, fontPath = "Fonts\\FRIZQT__.TTF", fontSize = 12, fontFlags = "" }, Widget)
    frames[#frames + 1] = object
    if name then _G[name] = object end
    if kind == "EditBox" then editBoxes[#editBoxes + 1] = object end
    return object
end

function Widget:SetScript(event, callback) self.scripts[event] = callback end
function Widget:GetScript(event) return self.scripts[event] end
function Widget:HookScript(event, callback)
    local previous = self.scripts[event]
    self.scripts[event] = function(...)
        if previous then previous(...) end
        callback(...)
    end
end
function Widget:RegisterEvent(event) self.events[event] = true end
function Widget:UnregisterEvent(event) self.events[event] = nil end
function Widget:Show()
    local wasShown = self.shown
    self.shown = true
    if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Widget:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Widget:IsShown() return self.shown end
function Widget:IsVisible() return self.shown end
function Widget:SetShown(value) if value then self:Show() else self:Hide() end end
function Widget:SetSize(width, height) self.width, self.height = width, height end
function Widget:SetWidth(width)
    local changed = self.width ~= width
    self.width = width
    if changed and self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, width, self.height) end
end
function Widget:SetHeight(height)
    local changed = self.height ~= height
    self.height = height
    if changed and self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, self.width, height) end
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
function Widget:SetText(text) self.text = text or "" end
function Widget:GetText() return self.text end
function Widget:GetStringHeight() return 16 end
function Widget:GetStringWidth() return #self.text * 6 end
function Widget:SetChecked(value) self.checked = value end
function Widget:GetChecked() return self.checked end
function Widget:Enable() self.enabled = true end
function Widget:Disable() self.enabled = false end
function Widget:IsEnabled() return self.enabled ~= false end
function Widget:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function Widget:GetValue() return self.value end
function Widget:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function Widget:GetMinMaxValues() return self.minimum or 0, self.maximum or 1 end
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
function Widget:GetVerticalScroll() return self.scroll or 0 end
function Widget:SetVerticalScroll(value) self.scroll = value end
function Widget:GetVerticalScrollRange() return 500 end
function Widget:GetTextInsets() return 0, 0, 0, 0 end
function Widget:SetHyperlink(value) self.hyperlink = value end

UIParent = widget("Frame", "UIParent")
GameTooltip = widget("GameTooltip", "GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) chat[#chat + 1] = message end }
UIErrorsFrame = { AddMessage = function(_, message) notices[#notices + 1] = message end }
UISpecialFrames, SlashCmdList, StaticPopupDialogs = {}, {}, {}
BackdropTemplateMixin = {}
ChatFontNormal = {}
ITEM_QUALITY_COLORS = { [0] = { r = .6, g = .6, b = .6 }, [1] = { r = 1, g = 1, b = 1 },
    [2] = { r = .1, g = 1, b = .1 }, [3] = { r = .1, g = .4, b = 1 } }
LOOT_SLOT_ITEM, LOOT_SLOT_MONEY, LOOT_SLOT_CURRENCY = 1, 2, 3
ACCEPT, CANCEL, YES, NO, CLOSE = "OK", "Annuleren", "Ja", "Nee", "Sluiten"
function CreateFrame(kind, name, parent) return widget(kind, name, parent) end
function GetBuildInfo() return "1.15.9", "70576", "", 11509 end
function GetTime() return clock end
function time() return stamp end
function date(pattern, value) return os.date(pattern, value or stamp) end
function GetNumLootItems() return #slots end
function GetLootSlotInfo(index)
    local slot = slots[index]
    return slot.icon, slot.name, slot.quantity, slot.currencyID, slot.quality, false, false
end
function GetLootSlotLink(index) return slots[index].link end
function GetItemInfo(link)
    local id = tostring(link):match("item:(%d+)") or tostring(link):match("^(%d+)$")
    return "Test item", link, 1, 1, 1, "Miscellaneous", "Junk", 20, "", 134400, vendorPrices[tonumber(id)]
end
function GetLootSlotType(index) return slots[index].kind or LOOT_SLOT_ITEM end
function GetLootSourceInfo(index) return unpack(slots[index].sources or {}) end
function UnitGUID(unit)
    return ({ target = "Creature-0-target", player = "Player-1", pet = "Pet-1" })[unit]
end
function CombatLogGetCurrentEventInfo() return unpack(combatLog) end
function GetContainerNumSlots(bag) return #(bags[bag] or {}) end
function GetContainerItemLink(bag, index)
    return bags[bag] and bags[bag][index] and bags[bag][index].link
end
function GetContainerItemInfo(bag, index)
    local entry = bags[bag] and bags[bag][index]
    if entry then return entry.icon, entry.quantity, false, entry.quality, false, false, entry.link end
end
C_Container = {
    GetContainerNumSlots = GetContainerNumSlots,
    GetContainerItemLink = GetContainerItemLink,
    GetContainerItemInfo = function(bag, index)
        local entry = bags[bag] and bags[bag][index]
        if entry then
            return { iconFileID = entry.icon, stackCount = entry.quantity,
                hyperlink = entry.link, quality = entry.quality }
        end
    end,
}
NUM_BAG_SLOTS = 4
function UnitName(unit)
    if unit == "player" or unit == "pet" then return groupNames[unit] end
    local party = type(unit) == "string" and tonumber(unit:match("^party(%d+)$"))
    if party and party <= partyCount then return groupNames[unit] end
    local raid = type(unit) == "string" and tonumber(unit:match("^raid(%d+)$"))
    if raid and raid <= raidCount then return groupNames[unit] end
    return nil
end
function GetNumPartyMembers() return partyCount end
function GetNumRaidMembers() return raidCount end
function GetLootMethod() return lootMethod, 0, 0 end
function GetLootRollItemLink(rollID) return lootRolls[rollID] and lootRolls[rollID].link end
function GetLootRollItemInfo(rollID)
    local roll = lootRolls[rollID]
    if roll then return roll.icon or 132889, roll.name, roll.quantity or 1, roll.quality or 4, false, true, true end
end
function GetRealmName() return "Testrealm" end
function IsModifiedClick() return false end
function IsShiftKeyDown() return false end
function ChatEdit_InsertLink() return false end
function SetItemRef() end
function StaticPopup_Show(name)
    assert(StaticPopupDialogs[name], "reset popup must be registered")
    popup = { name = name, definition = StaticPopupDialogs[name] }
    return widget("Frame")
end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }

local function dispatch(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

local function flushTimers()
    local iterations = 0
    while #timers > 0 do
        iterations = iterations + 1
        assert(iterations < 20, "loot retries must be bounded")
        local pending = timers
        timers = {}
        for _, callback in ipairs(pending) do callback() end
    end
    return iterations
end

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end

local function item(guid, quantity)
    return { name = "Linnen doek", icon = 132889, quantity = quantity, quality = 1,
        link = "|cffffffff|Hitem:2589::::::::|h[Linnen doek]|h|r", sources = {guid, quantity} }
end

assert(loadfile("ClassicLootLog/Compat.lua"))()
assert(loadfile("ClassicLootLog/Core.lua"))("ClassicLootLog", ns)
assert(loadfile("ClassicLootLog/Tracking.lua"))("ClassicLootLog", ns)
assert(loadfile("ClassicLootLog/Value.lua"))()
assert(loadfile("ClassicLootLog/GroupLoot.lua"))()
assert(loadfile("ClassicLootLog/GroupEvents.lua"))()
assert(loadfile("ClassicLootLog/Main.lua"))("ClassicLootLog", ns)
local passed = 0
local function test(name, callback)
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

test("addon initializes persistent database on its own ADDON_LOADED", function()
    ClassicLootLogDB = nil
    dispatch("ADDON_LOADED", "OtherAddon")
    equal(ClassicLootLogDB, nil)
    dispatch("ADDON_LOADED", "ClassicLootLog")
    assert(type(ClassicLootLogDB) == "table")
    assert(type(ns.App) == "table")
    equal(#ClassicLootLogDB.entries, 0)
    equal(ClassicLootLogDB.timer.enabled, false)
    assert(type(SlashCmdList.CLASSICLOOTLOG) == "function")
    equal(SLASH_CLASSICLOOTLOG1, "/cll")
end)

test("loot events capture source quantities exactly once", function()
    slots = { item("Creature-1", 3) }
    dispatch("LOOT_READY")
    dispatch("LOOT_OPENED")
    flushTimers()
    equal(#ClassicLootLogDB.entries, 1)
    equal(ClassicLootLogDB.entries[1].quantity, 3)
    equal(ClassicLootLogDB.entries[1].name, "Linnen doek")
    dispatch("LOOT_CLOSED")
    dispatch("LOOT_READY")
    dispatch("LOOT_OPENED")
    flushTimers()
    equal(#ClassicLootLogDB.entries, 1, "reopening the same corpse")
    dispatch("LOOT_CLOSED")
    slots = { item("Creature-2", 2) }
    dispatch("LOOT_READY")
    dispatch("LOOT_OPENED")
    flushTimers()
    equal(#ClassicLootLogDB.entries, 2)
    equal(ClassicLootLogDB.entries[2].quantity, 2)
end)

test("timer command annotates drops and pauses without counting idle time", function()
    clock = 200
    SlashCmdList.CLASSICLOOTLOG("timer")
    equal(ClassicLootLogDB.timer.enabled, true)
    clock = 215
    dispatch("LOOT_CLOSED")
    slots = { item("Creature-3", 1) }
    dispatch("LOOT_OPENED")
    flushTimers()
    equal(ClassicLootLogDB.entries[3].elapsed, 15)
    SlashCmdList.CLASSICLOOTLOG("timer")
    equal(ClassicLootLogDB.timer.enabled, false)
    equal(ns.Core.TimerElapsed(ClassicLootLogDB, 300), 15)
end)

test("log command exposes every record in copyable export text", function()
    SlashCmdList.CLASSICLOOTLOG("log")
    local found
    for _, box in ipairs(editBoxes) do
        local text = box:GetText()
        if text:find("Date/time", 1, true) then found = text end
    end
    assert(found, "export edit box must contain TSV")
    assert(found:find("Linnen doek", 1, true))
    equal(select(2, found:gsub("\n", "")), #ClassicLootLogDB.entries)
    assert(found:find("00:00:15", 1, true))
end)

test("reset requires confirmation before deleting loot and session time", function()
    local before = #ClassicLootLogDB.entries
    SlashCmdList.CLASSICLOOTLOG("reset")
    equal(#ClassicLootLogDB.entries, before)
    assert(popup and type(popup.definition.OnAccept) == "function")
    popup.definition.OnAccept()
    equal(#ClassicLootLogDB.entries, 0)
    equal(next(ClassicLootLogDB.seen), nil)
    equal(ns.Core.TimerElapsed(ClassicLootLogDB, clock), 0)
end)

test("logout checkpoints active timer for persistence without offline time", function()
    clock = 300
    SlashCmdList.CLASSICLOOTLOG("timer")
    clock = 307
    dispatch("PLAYER_LOGOUT")
    equal(ClassicLootLogDB.timer.enabled, true)
    equal(ClassicLootLogDB.timer.elapsed, 7)
    ns.Core.Initialize(ClassicLootLogDB, 5000)
    equal(ns.Core.TimerElapsed(ClassicLootLogDB, 5002), 9)
end)

local function resetSession()
    dispatch("LOOT_CLOSED")
    timers = {}
    ns.Core.SetTimerEnabled(ClassicLootLogDB, false, clock)
    ns.Core.Reset(ClassicLootLogDB, clock)
    if ns.App.tracker then ns.App.tracker:Reset() end
    if ns.App.SetView then ns.App:SetView("loot") end
    ns.App.selectedEntryID = nil
    bags, combatLog = {}, {}
    lootMethod, partyCount, raidCount = "freeforall", 0, 0
    lootRolls = {}
    if ns.App.groupAdapter then
        ClassicLootLogDB.groupLoot = {}
        ns.App.groupAdapter:Reset()
    end
    ns.App.offset = 0
    ns.App:Refresh()
end

test("item links resolving after LOOT_READY do not create a second identity", function()
    resetSession()
    slots = { item("Creature-delayed-link", 2) }
    local link = slots[1].link
    slots[1].link = nil
    dispatch("LOOT_READY")
    equal(#ClassicLootLogDB.entries, 0, "uncached item must wait for its link")
    slots[1].link = link
    dispatch("LOOT_OPENED")
    flushTimers()
    equal(#ClassicLootLogDB.entries, 1)
    equal(ClassicLootLogDB.entries[1].quantity, 2)
end)

test("incomplete names defer only missing loot while preserving valid drops", function()
    resetSession()
    slots = { item("Creature-ready", 1), item("Creature-delayed-name", 3) }
    slots[2].name = nil
    dispatch("LOOT_READY")
    equal(#ClassicLootLogDB.entries, 1)
    equal(ClassicLootLogDB.entries[1].quantity, 1)
    slots[2].name = "Linnen doek"
    flushTimers()
    equal(#ClassicLootLogDB.entries, 2)
    dispatch("LOOT_OPENED")
    equal(#ClassicLootLogDB.entries, 2)
end)

test("closing the loot window cancels its delayed capture", function()
    resetSession()
    slots = { item("Creature-closed", 1) }
    slots[1].name = nil
    dispatch("LOOT_READY")
    dispatch("LOOT_CLOSED")
    slots[1].name = "Linnen doek"
    flushTimers()
    equal(#ClassicLootLogDB.entries, 0)
end)

test("LOOT_SLOT_CHANGED captures newly available data without duplicate rows", function()
    resetSession()
    slots = { item("Creature-changed", 1) }
    slots[1].name = nil
    dispatch("LOOT_OPENED")
    slots[1].name = "Linnen doek"
    dispatch("LOOT_SLOT_CHANGED", 1)
    equal(#ClassicLootLogDB.entries, 1)
    flushTimers()
    equal(#ClassicLootLogDB.entries, 1)
end)

test("list scrolling reaches the oldest records while export retains every row", function()
    resetSession()
    slots = {}
    for index = 1, 20 do slots[index] = item("Creature-scroll-" .. index, index) end
    dispatch("LOOT_OPENED")
    equal(#ClassicLootLogDB.entries, 20)
    equal(ns.App.rows[1].entry.id, 20)
    local visible = ns.App.visibleRows
    assert(visible > 0 and visible < 20)
    equal(ns.App.rows[visible].entry.id, 20 - visible + 1)
    ns.App.frame.scripts.OnMouseWheel(ns.App.frame, -1)
    equal(ns.App.offset, 3)
    equal(ns.App.rows[1].entry.id, 17)
    local maxOffset = 20 - visible
    ns.App.scrollbar:SetValue(maxOffset)
    equal(ns.App.rows[1].entry.id, visible)
    equal(ns.App.rows[visible].entry.id, 1)
    ns.App.frame.scripts.OnMouseWheel(ns.App.frame, -10)
    equal(ns.App.offset, maxOffset)
    ns.App.frame.scripts.OnMouseWheel(ns.App.frame, 10)
    equal(ns.App.offset, 0)
    SlashCmdList.CLASSICLOOTLOG("log")
    equal(select(2, ns.App.exportFrame.edit:GetText():gsub("\n", "")), 20)
end)

test("money and currencies display labels and export without empty hyperlinks", function()
    resetSession()
    slots = {
        { name = "1 goud 50 zilver", quantity = 15000, kind = LOOT_SLOT_MONEY,
            sources = {"Creature-money", 15000} },
        { name = "Heldenpunten", quantity = 2, kind = LOOT_SLOT_CURRENCY,
            sources = {"Creature-currency", 2} },
    }
    dispatch("LOOT_OPENED")
    equal(#ClassicLootLogDB.entries, 2)
    equal(ClassicLootLogDB.entries[1].kind, "money")
    equal(ClassicLootLogDB.entries[2].kind, "currency")
    equal(ns.App.rows[1].item:GetText(), "Heldenpunten")
    equal(ns.App.rows[2].item:GetText(), "1 goud 50 zilver")
    GameTooltip.hyperlink = nil
    ns.App.rows[2].scripts.OnEnter(ns.App.rows[2])
    equal(rawget(GameTooltip, "hyperlink"), nil)
    SlashCmdList.CLASSICLOOTLOG("log")
    local exported = ns.App.exportFrame.edit:GetText()
    assert(exported:find("1 goud 50 zilver", 1, true))
    assert(exported:find("Heldenpunten", 1, true))
end)

test("cleared loot slots are skipped without retries", function()
    resetSession()
    slots = { { kind = 0 }, item("Creature-still-lootable", 2) }
    dispatch("LOOT_OPENED")
    equal(#ClassicLootLogDB.entries, 1)
    equal(ClassicLootLogDB.entries[1].quantity, 2)
    equal(#timers, 0, "cleared slots must not be mistaken for cache misses")
end)

test("permanently unavailable item data exhausts a bounded retry budget", function()
    resetSession()
    slots = { item("Creature-never-cached", 1) }
    slots[1].name, slots[1].link = nil, nil
    dispatch("LOOT_READY")
    equal(#ClassicLootLogDB.entries, 0)
    equal(flushTimers(), 5, "five delayed retries after the initial attempt")
    equal(#timers, 0)
    equal(#ClassicLootLogDB.entries, 0)
end)

test("item data resolving on a later retry is eventually captured once", function()
    resetSession()
    slots = { item("Creature-second-retry", 4) }
    local link = slots[1].link
    slots[1].link = nil
    dispatch("LOOT_OPENED")
    equal(#timers, 1)
    local firstRetry = table.remove(timers, 1)
    firstRetry()
    equal(#ClassicLootLogDB.entries, 0)
    equal(#timers, 1, "an unresolved first retry must schedule another attempt")
    slots[1].link = link
    equal(flushTimers(), 1)
    equal(#ClassicLootLogDB.entries, 1)
    equal(ClassicLootLogDB.entries[1].quantity, 4)
    dispatch("LOOT_SLOT_CHANGED", 1)
    equal(#ClassicLootLogDB.entries, 1)
end)

test("source metadata appearing late preserves the window fallback identity", function()
    resetSession()
    slots = { item("Creature-late-source", 3) }
    slots[1].sources = {}
    dispatch("LOOT_READY")
    equal(#ClassicLootLogDB.entries, 1)
    equal(ClassicLootLogDB.entries[1].quantity, 3)
    local originalSource = ClassicLootLogDB.entries[1].source
    assert(originalSource:find("window:", 1, true))
    slots[1].sources = {"Creature-late-source", 3}
    dispatch("LOOT_OPENED")
    dispatch("LOOT_SLOT_CHANGED", 1)
    flushTimers()
    equal(#ClassicLootLogDB.entries, 1, "late metadata must not create another source")
    equal(ClassicLootLogDB.entries[1].source, originalSource)
end)

test("zero-quantity money metadata preserves each corpse identity and labels", function()
    resetSession()
    for index = 1, 2 do
        dispatch("LOOT_CLOSED")
        slots = { { name = index .. " zilver", quantity = 0, kind = LOOT_SLOT_MONEY,
            sources = {"Creature-zero-money-" .. index, 0} } }
        dispatch("LOOT_OPENED")
        equal(#ClassicLootLogDB.entries, index)
        equal(ClassicLootLogDB.entries[index].source, "Creature-zero-money-" .. index)
        equal(ClassicLootLogDB.entries[index].quantity, 1)
        equal(ns.App.rows[1].item:GetText(), index .. " zilver")
        dispatch("LOOT_CLOSED")
        dispatch("LOOT_OPENED")
        equal(#ClassicLootLogDB.entries, index, "reopening money with zero metadata")
    end
    equal(ClassicLootLogDB.entries[1].kind, "money")
    equal(ClassicLootLogDB.entries[2].kind, "money")
end)

local function combat(event, sourceGUID, destinationGUID, name, sourceFlags)
    combatLog = { stamp, event, false, sourceGUID or "", "Source", sourceFlags or 1, 0,
        destinationGUID, name or "Testmob", 2112, 0 }
    dispatch("COMBAT_LOG_EVENT_UNFILTERED")
end

local function kill(sourceGUID, destinationGUID, sourceFlags)
    combat("SWING_DAMAGE", sourceGUID, destinationGUID, nil, sourceFlags)
    combat("UNIT_DIED", "", destinationGUID)
end

test("combat integration counts personal and pet NPC deaths but not unrelated or player deaths", function()
    resetSession()
    combat("SWING_DAMAGE", "Player-1", "Creature-integration-1")
    equal(ns.Core.MobStats(ClassicLootLogDB, clock).total, 0)
    combat("UNIT_DIED", "", "Creature-integration-1")
    combat("UNIT_DIED", "", "Creature-integration-1")
    kill("Pet-1", "Creature-integration-2")
    kill("Player-other", "Creature-unrelated")
    kill("Player-1", "Player-pvp-target")
    equal(ns.Core.MobStats(ClassicLootLogDB, clock).total, 2)
    equal(ns.Core.MobStats(ClassicLootLogDB, clock).timed, 0)
end)

test("party and raid kills count while a shared mob is never counted twice", function()
    resetSession()
    kill("Player-party-member", "Creature-party-mob", 2)
    kill("Pet-raid-member", "Creature-raid-mob", 4)
    combat("SWING_DAMAGE", "Player-party-member", "Creature-shared", nil, 2)
    combat("SPELL_DAMAGE", "Player-1", "Creature-shared")
    combat("UNIT_DIED", "", "Creature-shared")
    combat("UNIT_DESTROYED", "", "Creature-shared")
    kill("Player-outsider", "Creature-unrelated-group", 8)
    equal(ns.Core.MobStats(ClassicLootLogDB, clock).total, 3)
    assert(ns.App.mobText:GetText():find("Mobs: 3", 1, true))
end)

test("mobs per hour uses only kills made while the stopwatch runs", function()
    resetSession()
    clock = 1000
    SlashCmdList.CLASSICLOOTLOG("timer aan")
    clock = 1060
    kill("Player-1", "Creature-timed-1")
    equal(ns.Core.MobStats(ClassicLootLogDB, clock).perHour, 60)
    SlashCmdList.CLASSICLOOTLOG("timer uit")
    clock = 1400
    kill("Player-1", "Creature-paused")
    local stats = ns.Core.MobStats(ClassicLootLogDB, clock)
    equal(stats.total, 2)
    equal(stats.timed, 1)
    equal(stats.perHour, 60)
    SlashCmdList.CLASSICLOOTLOG("timer aan")
    clock = 1460
    kill("Pet-1", "Creature-timed-2")
    stats = ns.Core.MobStats(ClassicLootLogDB, clock)
    equal(stats.total, 3)
    equal(stats.timed, 2)
    equal(stats.perHour, 60)
    assert(ns.App.mobText:GetText():find("Mobs/hour: 60.0", 1, true))
end)

test("statistics view calculates item shares from quantities and combines matching item IDs", function()
    resetSession()
    local other = item("Creature-other-item", 7)
    other.link, other.name = "|cff1eff00|Hitem:2592::::::::|h[Wollen stof]|h|r", "Wollen stof"
    local variant = item("Creature-one-linen", 1)
    variant.link = "|cffffffff|Hitem:2589:0:0:0:0:0:0:0:60|h[Linnen doek]|h|r"
    slots = { item("Creature-two-linen", 2), variant, other }
    dispatch("LOOT_OPENED")
    ns.App:SetView("stats")
    local stats = ns.Core.ItemStats(ClassicLootLogDB)
    equal(stats.totalQuantity, 10)
    equal(stats.rows[1].quantity, 7)
    equal(stats.rows[1].percent, 70)
    equal(stats.rows[2].quantity, 3)
    equal(stats.rows[2].percent, 30)
    assert(ns.App.rows[1].percent:GetText():find("70", 1, true))
    assert(ns.App.rows[2].percent:GetText():find("30", 1, true))
    ns.App:SetView("loot")
    equal(ns.App.rows[1].entry.id, 3)
end)

test("selecting a loot row allows reversible disenchant correction without changing its drop percentage", function()
    resetSession()
    local other = item("Creature-other-mark", 7)
    other.link, other.name = "item:2592", "Wollen stof"
    slots = { item("Creature-mark-original", 3), other }
    dispatch("LOOT_OPENED")
    local row = ns.App.rows[2]
    row.scripts.OnClick(row)
    equal(ns.App.selectedEntryID, 1)
    assert(ns.App.markButton:IsEnabled())
    equal(ns.App:MarkSelectedDisenchanted(1), 1)
    equal(ClassicLootLogDB.entries[1].disenchanted, 1)
    equal(ClassicLootLogDB.entries[1].quantity, 3)
    local stats = ns.Core.ItemStats(ClassicLootLogDB)
    equal(stats.totalQuantity, 10)
    equal(stats.byKey["item:2589"].percent, 30)
    equal(stats.byKey["item:2589"].disenchanted, 1)
    equal(ns.App:UnmarkSelectedDisenchanted(1), 1)
    equal(ClassicLootLogDB.entries[1].disenchanted, 0)
    equal(ns.App:UnmarkSelectedDisenchanted(1), 0)
end)

local function disenchantItem(guid, quantity)
    local entry = item(guid, quantity)
    entry.name, entry.link, entry.quality = "Testzwaard", "item:15210", 2
    return entry
end

local function material(guid, quantity)
    local entry = item(guid, quantity)
    entry.name, entry.link = "Vreemd stof", "item:10940"
    return entry
end

test("successful disenchant marks the consumed original and separates materials from drop percentages", function()
    resetSession()
    local original = disenchantItem("Creature-de-original", 1)
    slots = { original }
    dispatch("LOOT_OPENED")
    dispatch("LOOT_CLOSED")
    bags[0] = { original }
    dispatch("UNIT_SPELLCAST_SENT", "player", "", "Cast-de-1", 13262)
    bags[0] = {}
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-de-1", 13262)
    dispatch("BAG_UPDATE_DELAYED")
    equal(ClassicLootLogDB.entries[1].disenchanted, 1)
    slots = { material("Item-de-result", 2) }
    dispatch("LOOT_READY")
    dispatch("LOOT_OPENED")
    flushTimers()
    equal(#ClassicLootLogDB.entries, 2)
    equal(ClassicLootLogDB.entries[2].origin, "disenchant")
    equal(ClassicLootLogDB.entries[2].quantity, 2)
    equal(ns.App.rows[1].processing:GetText(), "DE material")
    equal(ns.App.rows[1].percent:GetText(), "-")
    ns.App.rows[1].scripts.OnClick(ns.App.rows[1])
    assert(not ns.App.markButton:IsEnabled(), "DE materials cannot be marked as original drops")
    local stats = ns.Core.ItemStats(ClassicLootLogDB)
    equal(stats.totalQuantity, 1)
    equal(stats.totalMaterials, 2)
    equal(stats.totalDisenchanted, 1)
    equal(stats.rows[1].percent, 100)
    ns.App:SetView("stats")
    equal(ns.App.rows[1].quantity:GetText(), "1")
    equal(ns.App.rows[2].processing:GetText(), "DE material")
    ns.App:ShowExport("stats")
    assert(ns.App.exportFrame.edit:GetText():find("Testzwaard", 1, true))
    assert(ns.App.exportFrame.edit:GetText():find("Vreemd stof", 1, true))
    ns.App:ShowExport("loot")
    local exported = ns.App.exportFrame.edit:GetText()
    assert(exported:find("Origin\tDisenchanted", 1, true))
    assert(exported:find("disenchant", 1, true))
end)

test("disenchant loot arriving before spell success waits rather than polluting the drop denominator", function()
    resetSession()
    dispatch("UNIT_SPELLCAST_SENT", "player", "", "Cast-de-ordering", 13262)
    slots = { material("Item-de-early", 3) }
    dispatch("LOOT_READY")
    equal(#ClassicLootLogDB.entries, 0)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-de-ordering", 13262)
    flushTimers()
    equal(#ClassicLootLogDB.entries, 1)
    equal(ClassicLootLogDB.entries[1].origin, "disenchant")
    equal(ns.Core.ItemStats(ClassicLootLogDB).totalQuantity, 0)
    equal(ns.Core.ItemStats(ClassicLootLogDB).totalMaterials, 3)
end)

test("a failed disenchant does not mark items or misclassify a later corpse", function()
    resetSession()
    local original = disenchantItem("Creature-de-failed-original", 1)
    slots = { original }
    dispatch("LOOT_OPENED")
    dispatch("LOOT_CLOSED")
    bags[0] = { original }
    dispatch("UNIT_SPELLCAST_SENT", "player", "", "Cast-de-failed", 13262)
    dispatch("UNIT_SPELLCAST_FAILED", "player", "Cast-de-failed", 13262)
    slots = { item("Creature-after-failed-de", 2) }
    dispatch("LOOT_OPENED")
    flushTimers()
    equal(ClassicLootLogDB.entries[1].disenchanted, 0)
    equal(ClassicLootLogDB.entries[2].origin, "drop")
    equal(ns.Core.ItemStats(ClassicLootLogDB).totalQuantity, 3)
end)

test("resizing reflows columns and scales text while preserving saved window settings", function()
    resetSession()
    ns.App:SetSizeLocked(false)
    ns.App:SetAutoText(true)
    ns.App:Resize(900, 590)
    local path, baselineFont = ns.App.rows[1].item:GetFont()
    local baselineWidth = ns.App.rows[1].item:GetWidth()
    local baselineVisible = ns.App.visibleRows
    assert(baselineVisible > 1)
    ns.App:Resize(680, 430)
    local _, smallFont = ns.App.rows[1].item:GetFont()
    assert(smallFont < baselineFont, "automatic text must shrink with a narrower window")
    assert(ns.App.rows[1].item:GetWidth() < baselineWidth, "item column must reflow")
    assert(ns.App.visibleRows < baselineVisible)
    equal(ClassicLootLogDB.ui.width, 680)
    equal(ClassicLootLogDB.ui.height, 430)
    ns.App:Resize(1280, 900)
    local _, largeFont = ns.App.rows[1].item:GetFont()
    assert(largeFont > baselineFont)
    assert(ns.App.visibleRows > baselineVisible)
    ns.App:Resize(10, 10)
    equal(ns.App.frame:GetWidth(), 680)
    equal(ns.App.frame:GetHeight(), 430)
    ns.App:SetAutoText(false)
    local _, fixedSmallFont = ns.App.rows[1].item:GetFont()
    equal(fixedSmallFont, baselineFont)
    ns.App:Resize(1280, 900)
    local _, fixedLargeFont = ns.App.rows[1].item:GetFont()
    equal(fixedLargeFont, baselineFont)
    ns.Core.Initialize(ClassicLootLogDB, clock)
    equal(ClassicLootLogDB.ui.width, 1280)
    equal(ClassicLootLogDB.ui.height, 900)
    equal(ClassicLootLogDB.ui.autoText, false)
    SlashCmdList.CLASSICLOOTLOG("scale off")
    equal(ClassicLootLogDB.ui.autoText, false, "explicit OFF must not act like a toggle")
    ns.Core.Reset(ClassicLootLogDB, clock)
    equal(ClassicLootLogDB.ui.width, 1280, "loot reset must preserve window dimensions")
    equal(ClassicLootLogDB.ui.height, 900)
    equal(ClassicLootLogDB.ui.autoText, false)
    ns.App:SetAutoText(true)
    ns.App:Resize(900, 590)
end)

test("size locking disables the resize grip and unlocking enables native drag sizing", function()
    resetSession()
    ns.App:SetSizeLocked(true)
    SlashCmdList.CLASSICLOOTLOG("lock on")
    equal(ClassicLootLogDB.ui.locked, true, "explicit ON must preserve an already locked state")
    ns.Core.Initialize(ClassicLootLogDB, clock)
    equal(ClassicLootLogDB.ui.locked, true, "size locking must survive saved-state initialization")
    equal(ns.App.frame.resizable, false)
    equal(ns.App.resizeGrip:IsShown(), false)
    ns.App.frame.sizing = false
    ns.App.resizeGrip.scripts.OnMouseDown(ns.App.resizeGrip, "LeftButton")
    equal(ns.App.frame.sizing, false)
    ns.App:SetSizeLocked(false)
    equal(ns.App.frame.resizable, true)
    equal(ns.App.resizeGrip:IsShown(), true)
    ns.App.resizeGrip.scripts.OnMouseDown(ns.App.resizeGrip, "LeftButton")
    equal(ns.App.frame.sizing, "BOTTOMRIGHT")
    ns.App.resizeGrip.scripts.OnMouseUp(ns.App.resizeGrip, "LeftButton")
    equal(ns.App.frame.sizing, false)
    equal(ClassicLootLogDB.ui.locked, false)
end)

test("scrolling still reaches every record after growing or shrinking the visible row count", function()
    resetSession()
    slots = {}
    for index = 1, 50 do slots[index] = item("Creature-resize-scroll-" .. index, 1) end
    dispatch("LOOT_OPENED")
    ns.App:Resize(900, 590)
    ns.App.scrollbar:SetValue(50 - ns.App.visibleRows)
    equal(ns.App.rows[ns.App.visibleRows].entry.id, 1)
    ns.App:Resize(900, 900)
    equal(ns.App.offset, 50 - ns.App.visibleRows, "offset must clamp when more rows become visible")
    equal(ns.App.rows[ns.App.visibleRows].entry.id, 1)
    ns.App:Resize(680, 430)
    ns.App.scrollbar:SetValue(50 - ns.App.visibleRows)
    equal(ns.App.rows[ns.App.visibleRows].entry.id, 1)
    equal(rawget(ns.App.rows[ns.App.visibleRows + 1], "entry"), nil)
    ns.App:Resize(900, 590)
end)

test("vendor column separates unknown and zero prices and excludes destroyed original units", function()
    resetSession()
    vendorPrices = {[2589] = 75, [2592] = 0}
    ClassicLootLogDB.vendorPrices = {}
    local zero = item("Creature-vendor-zero", 2)
    zero.link, zero.name = "item:2592", "No value item"
    local unknown = item("Creature-vendor-unknown", 1)
    unknown.link, unknown.name = "item:15210", "Unknown sword"
    slots = {item("Creature-vendor-cloth", 3), zero, unknown}
    dispatch("LOOT_OPENED")
    equal(ns.App.rows[1].vendor:GetText(), "Unknown")
    equal(ns.App.rows[2].vendor:GetText(), "0c")
    equal(ns.App.rows[3].vendor:GetText(), "2s 25c")
    SlashCmdList.CLASSICLOOTLOG("price 15210 500")
    equal(ns.App.rows[1].vendor:GetText(), "5s 0c")
    ns.App:SelectEntry(1)
    equal(ns.App:MarkSelectedDisenchanted(1), 1)
    equal(ns.App.rows[3].vendor:GetText(), "1s 50c")
    local totals = ns.Value.GetTotals(ClassicLootLogDB)
    equal(totals.knownCopper, 650)
    equal(totals.unknownUnits, 0)
    SellValues = {["item:2589"] = 100}
    dispatch("ADDON_LOADED", "SellValue")
    equal(ns.App.rows[3].vendor:GetText(), "2s 0c", "SellValue loaded later must refresh displayed prices")
    equal(ns.App.rows[1].vendor:GetText(), "5s 0c", "SellValue refresh must preserve an explicit manual override")
    SellValues["item:2589"] = 110
    dispatch("MERCHANT_SHOW")
    flushTimers()
    equal(ns.App.rows[3].vendor:GetText(), "2s 20c", "newly learned merchant prices must refresh the column")
    SellValues = nil
    vendorPrices = {}
end)

test("epic notifications fire only for new original purple drops and respect the alert switch", function()
    resetSession()
    ClassicLootLogDB.alerts.epic = true
    local before = #notices
    local epic = item("Creature-purple", 2)
    epic.link, epic.name, epic.quality = "item:873", "Purple weapon", 4
    local rare = item("Creature-blue", 1)
    rare.quality = 3
    local legendary = item("Creature-orange", 1)
    legendary.quality = 5
    slots = {epic, rare, legendary}
    dispatch("LOOT_OPENED")
    equal(#notices, before + 1)
    assert(notices[#notices]:find("EPIC LOOT", 1, true))
    assert(notices[#notices]:find("x2", 1, true))
    dispatch("LOOT_CLOSED")
    dispatch("LOOT_OPENED")
    equal(#notices, before + 1, "reopening a corpse must not notify twice")
    dispatch("LOOT_CLOSED")
    ClassicLootLogDB.alerts.epic = false
    epic = item("Creature-purple-muted", 1)
    epic.quality = 4
    slots = {epic}
    dispatch("LOOT_OPENED")
    equal(#notices, before + 1)
    ClassicLootLogDB.alerts.epic = true
    dispatch("LOOT_SLOT_CHANGED", 1)
    equal(#notices, before + 1, "reenabling alerts must not replay muted drops")
    dispatch("LOOT_CLOSED")
    dispatch("UNIT_SPELLCAST_SENT", "player", "", "Cast-purple-material", 13262)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-purple-material", 13262)
    epic = item("Item-purple-material", 1)
    epic.quality = 4
    slots = {epic}
    dispatch("LOOT_OPENED")
    equal(ClassicLootLogDB.entries[#ClassicLootLogDB.entries].origin, "disenchant")
    equal(#notices, before + 1, "DE results are not original epic drops")
    resetSession()
    epic = item("Creature-purple-after-reset", 1)
    epic.quality = 4
    slots = {epic}
    dispatch("LOOT_OPENED")
    equal(#notices, before + 2, "resettable row IDs must not suppress fresh drops")
end)


local function groupLink(id, name)
    return "|cffa335ee|Hitem:" .. id .. ":0:0:0|h[" .. name .. "]|h|r"
end

local function groupEntry()
    local entries = ClassicLootLogDB.groupLoot.entries
    return entries[#entries]
end

local function ranks(entry)
    return ns.App.groupAdapter.model:Rankings(entry)
end

test("title stays centered in its decorative header when the window is resized", function()
    local title, header = ns.App.frame.titleText, ns.App.frame.header
    assert(header, "decorative title header must be retained for its text anchor")
    equal(title.anchor[1], "CENTER")
    equal(title.anchor[2], header)
    equal(title.anchor[3], "CENTER")
    equal(title.anchor[4], 0)
    ns.App:Resize(680, 430)
    equal(title.anchor[2], header)
    equal(title.anchor[1], "CENTER")
    ns.App:Resize(1280, 900)
    equal(title.anchor[2], header)
    equal(title.anchor[1], "CENTER")
    ns.App:Resize(900, 590)
end)

test("Commands tab exposes a complete documented command list and returns to the loot view", function()
    resetSession()
    SlashCmdList.CLASSICLOOTLOG("commands")
    equal(ns.App.tab, "commands")
    local commands = ns.App:GetCommands()
    assert(#commands >= 15, "the command reference must include old and new commands")
    local all = {}
    for _, entry in ipairs(commands) do
        assert(type(entry.command) == "string" and entry.command ~= "")
        assert(type(entry.description) == "string" and entry.description ~= "")
        all[#all + 1] = entry.command
    end
    local text = table.concat(all, "\n")
    for _, name in ipairs({"timer", "price", "epic", "sound", "scale", "lock", "commands", "group", "track"}) do
        assert(text:find("/cll " .. name, 1, true), "missing command reference: " .. name)
    end
    assert(ns.App.commandsRows[1].command:GetText() ~= "")
    ns.App:SetTab("group")
    equal(ns.App.tab, "group")
    ns.App:SetView("stats")
    equal(ns.App.tab, "loot")
    equal(ns.App.view, "stats")
    ns.App:SetView("loot")
end)

test("group loot tracks choices and shows the two highest eligible need rolls plus the actual recipient", function()
    resetSession()
    lootMethod, partyCount = "group", 3
    local link = groupLink(18803, "Group loot test")
    lootRolls[701] = {link = link, name = "Group loot test", quality = 4}
    dispatch("START_LOOT_ROLL", 701, 60000)
    dispatch("CHAT_MSG_LOOT", "Alice has selected Need for: " .. link)
    dispatch("CHAT_MSG_LOOT", "Bob has selected Greed for: " .. link)
    dispatch("CHAT_MSG_LOOT", "Cara has selected Need for: " .. link)
    dispatch("CHAT_MSG_LOOT", "Need Roll - 81 for " .. link .. " by Alice")
    dispatch("CHAT_MSG_LOOT", "Need Roll - 75 for " .. link .. " by Cara")
    dispatch("CHAT_MSG_LOOT", "Greed Roll - 99 for " .. link .. " by Bob")
    dispatch("CHAT_MSG_LOOT", "Alice won: " .. link)
    local entry = groupEntry()
    assert(not entry.recipient, "a roll announcement is not yet an observed item receipt")
    dispatch("CHAT_MSG_LOOT", "Alice receives loot: " .. link .. ".")
    equal(entry.recipient, "Alice")
    equal(entry.distributionMethod, "group")
    local ranking = ranks(entry)
    equal(ranking.highest.player, "Alice")
    equal(ranking.highest.value, 81)
    equal(ranking.second.player, "Cara")
    equal(ranking.second.value, 75)
    SlashCmdList.CLASSICLOOTLOG("group")
    equal(ns.App.tab, "group")
    local row = ns.App.groupRows[1]
    assert(row.method:GetText():lower():find("group", 1, true))
    assert(row.winner:GetText():find("Alice", 1, true))
    assert(row.highest:GetText():find("81", 1, true))
    assert(row.second:GetText():find("75", 1, true))
    ns.App:SelectGroupEntry(entry.id)
    local detail = ns.App.groupDetail:GetText():lower()
    assert(detail:find("bob", 1, true))
    assert(detail:find("greed", 1, true))
    ns.App:ShowExport("group")
    local exported = ns.App.exportFrame.edit:GetText()
    assert(exported:find("Alice", 1, true))
    assert(exported:find("81", 1, true))
    assert(exported:find("75", 1, true))
end)

test("master loot attaches slash-roll results to a selected item and retains the distribution method", function()
    resetSession()
    lootMethod, partyCount = "master", 3
    local link = groupLink(18809, "Master loot test")
    local entry = ns.App.groupAdapter:BeginItem(link, "master")
    assert(entry)
    ns.App:SelectGroupEntry(entry.id)
    dispatch("CHAT_MSG_SYSTEM", "Alice rolls 62 (1-100)")
    dispatch("CHAT_MSG_SYSTEM", "Bob rolls 88 (1-100)")
    dispatch("CHAT_MSG_SYSTEM", "Cara rolls 41 (1-100)")
    dispatch("CHAT_MSG_LOOT", "Bob receives loot: " .. link .. ".")
    equal(entry.recipient, "Bob")
    equal(entry.method, "master")
    equal(entry.distributionMethod, "master")
    local ranking = ranks(entry)
    equal(ranking.highest.player, "Bob")
    equal(ranking.highest.value, 88)
    equal(ranking.second.player, "Alice")
    equal(ranking.second.value, 62)
    ns.App:SetTab("group")
    assert(ns.App.groupRows[1].method:GetText():lower():find("master", 1, true))
    assert(ns.App.groupRows[1].highest:GetText():find("Bob", 1, true))
    assert(ns.App.groupRows[1].second:GetText():find("Alice", 1, true))
end)

test("EPGP records flexible bid spellings and resolves the winning bid from the observed recipient", function()
    resetSession()
    lootMethod, partyCount = "master", 3
    local link = groupLink(18816, "EPGP test")
    local entry = ns.App.groupAdapter:BeginItem(link, "master")
    ns.App:SelectGroupEntry(entry.id)
    dispatch("CHAT_MSG_PARTY", "!m.A.x", "Alice")
    dispatch("CHAT_MSG_PARTY", "n33d", "Bob")
    dispatch("CHAT_MSG_PARTY", "m i n", "Cara")
    dispatch("CHAT_MSG_PARTY", "MAX", "Outsider")
    dispatch("CHAT_MSG_LOOT", "Cara receives loot: " .. link .. ".")
    equal(entry.method, "epgp")
    equal(entry.distributionMethod, "master")
    equal(entry.recipient, "Cara")
    equal(entry.winnerBid, "MIN")
    assert(not entry.bids.Outsider and not entry.bids.outsider, "nonmembers cannot inject a winning bid")
    equal(#entry.bidOrder, 3)
    ns.App:SetTab("group")
    local row = ns.App.groupRows[1]
    assert(row.method:GetText():lower():find("ep", 1, true))
    assert(row.winner:GetText():find("Cara", 1, true))
    assert(row.bid:GetText():find("MIN", 1, true))
    ns.App:SelectGroupEntry(entry.id)
    local detail = ns.App.groupDetail:GetText()
    assert(detail:find("Alice", 1, true))
    assert(detail:find("MAX", 1, true))
    assert(detail:find("Bob", 1, true))
    assert(detail:find("NEED", 1, true))
end)

test("simultaneous identical item rolls keep ambiguous receipts unassigned", function()
    resetSession()
    lootMethod, partyCount = "group", 3
    local link = groupLink(19375, "Identical items")
    lootRolls[801] = {link = link, name = "Identical items"}
    lootRolls[802] = {link = link, name = "Identical items"}
    dispatch("START_LOOT_ROLL", 801, 60000)
    dispatch("START_LOOT_ROLL", 802, 60000)
    equal(#ClassicLootLogDB.groupLoot.entries, 2)
    dispatch("CHAT_MSG_LOOT", "Bob receives loot: " .. link .. ".")
    local data = ClassicLootLogDB.groupLoot
    equal(#data.unassigned, 1)
    assert(not data.entries[1].recipient and not data.entries[2].recipient)
    ns.App:SetTab("group")
    assert(ns.App.groupStatus:GetText():lower():find("unassigned", 1, true))
end)

print(string.format("%d WoW integration smoke tests passed", passed))
