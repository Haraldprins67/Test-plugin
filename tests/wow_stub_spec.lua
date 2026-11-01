-- Behavioral smoke tests with a small WoW API substitute; no visual validation.
local ns, frames, editBoxes, timers = {}, {}, {}, {}
ClassicLootLogNS = ns
local clock, stamp, slots = 100, 1700000000, {}
local popup, chat = nil, {}
local combatLog, bags = {}, {}

local Widget = {}
local noops = {}
for method in ("SetPoint SetFrameStrata SetClampedToScreen SetMovable EnableMouse RegisterForDrag "
    .. "StartMoving StopMovingOrSizing SetBackdrop SetBackdropColor SetJustifyH SetTexture "
    .. "SetMultiLine SetAutoFocus SetFontObject SetMaxLetters UpdateScrollChildRect SetScrollChild "
    .. "SetFocus ClearFocus HighlightText SetOwner SetOrientation SetValueStep SetObeyStepOnDrag "
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
        text = "", checked = false, value = 0 }, Widget)
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
function Widget:SetWidth(width) self.width = width end
function Widget:SetHeight(height) self.height = height end
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
function Widget:CreateFontString(name) return widget("FontString", name, self) end
function Widget:CreateTexture(name) return widget("Texture", name, self) end
function Widget:GetVerticalScroll() return self.scroll or 0 end
function Widget:SetVerticalScroll(value) self.scroll = value end
function Widget:GetVerticalScrollRange() return 500 end
function Widget:GetTextInsets() return 0, 0, 0, 0 end
function Widget:SetHyperlink(value) self.hyperlink = value end

UIParent = widget("Frame", "UIParent")
GameTooltip = widget("GameTooltip", "GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) chat[#chat + 1] = message end }
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
function UnitName() return "Testspeler" end
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
    equal(ns.App.rows[13].entry.id, 8)
    ns.App.frame.scripts.OnMouseWheel(ns.App.frame, -1)
    equal(ns.App.offset, 3)
    equal(ns.App.rows[1].entry.id, 17)
    ns.App.scrollbar:SetValue(7)
    equal(ns.App.rows[1].entry.id, 13)
    equal(ns.App.rows[13].entry.id, 1)
    ns.App.frame.scripts.OnMouseWheel(ns.App.frame, -10)
    equal(ns.App.offset, 7)
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

print(string.format("%d WoW integration smoke tests passed", passed))
