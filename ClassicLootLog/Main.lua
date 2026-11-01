ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local addonName = "ClassicLootLog"
local Compat = ns.Compat
local Core = ns.Core
local Tracker = ns.Tracker
local App = {}
ns.App = App

local ROWS = 13
local ROW_HEIGHT = 25
local RESET_DIALOG = "CLASSICLOOTLOG_CONFIRM_RESET"
local eventFrame = CreateFrame("Frame")
local lootSession, lootSequence = nil, 0
local fallbackIdentities = {}

local function now()
    return GetTime()
end

local function say(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Classic Loot Log:|r " .. message)
    end
end

local function backdrop(frame)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        frame:SetBackdropColor(1, 1, 1, 1)
    end
end

local function label(parent, text, x, y, width, template)
    local font = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    font:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then font:SetWidth(width) end
    font:SetJustifyH("LEFT")
    font:SetText(text)
    return font
end

local function button(parent, text, width, x, y, onClick)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    Compat.SetSize(control, width, 25)
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    control:SetText(text)
    Compat.SetScript(control, "OnClick", onClick)
    return control
end

local function movableFrame(name, width, height, title)
    local frame = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    Compat.SetSize(frame, width, height)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    Compat.SetScript(frame, "OnDragStart", frame.StartMoving)
    Compat.SetScript(frame, "OnDragStop", frame.StopMovingOrSizing)
    backdrop(frame)
    local header = frame:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    Compat.SetSize(header, 360, 64)
    header:SetPoint("TOP", frame, "TOP", 0, 12)
    local titleText = label(frame, title, (width - 320) / 2, -14, 320, "GameFontNormalLarge")
    titleText:SetJustifyH("CENTER")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    table.insert(UISpecialFrames, name)
    frame:Hide()
    return frame
end

local function formatTimestamp(timestamp)
    return date("%Y-%m-%d %H:%M:%S", timestamp)
end

function App:Refresh()
    if not self.frame then return end
    local db = self.db
    local stats = Core.ItemStats(db)
    local percentages = {}
    for _, item in ipairs(stats.rows) do percentages[item.key] = item.percent end
    local records = db.entries
    if self.view == "stats" then
        records = {}
        for _, item in ipairs(stats.rows) do records[table.getn(records) + 1] = item end
        for _, item in ipairs(stats.materialRows) do
            local material = {}
            for key, value in pairs(item) do material[key] = value end
            material.isMaterial = true
            records[table.getn(records) + 1] = material
        end
    end
    local count = table.getn(records)
    local maxOffset = math.max(0, count - ROWS)
    self.offset = math.min(self.offset or 0, maxOffset)
    self.scrollbar:SetMinMaxValues(0, maxOffset)
    self.scrollbar:SetValue(self.offset)
    self.status:SetText(self.view == "stats"
        and string.format("Item share: quantity / %d original items  |  %d DE materials (separate)", stats.totalQuantity, stats.totalMaterials)
        or string.format("%d loot entries  |  Newest first  |  %d items disenchanted", count, stats.totalDisenchanted))
    self.empty:SetText(count == 0 and "No items in this view yet. Open a loot window to record drops." or "")
    self.timerButton:SetText(db.timer.enabled and "Timer: ON" or "Timer: OFF")
    self.viewButton:SetText(self.view == "stats" and "Loot list" or "Item shares")
    self:UpdateSessionStats()
    local selected
    for _, entry in ipairs(db.entries) do
        if entry.id == self.selectedEntryID then selected = entry; break end
    end
    self.selectionText:SetText(selected and string.format("Selected: #%d %s  |  DE: %d/%d", selected.id, selected.name, selected.disenchanted or 0, selected.quantity)
        or "Select an original item entry to adjust its disenchant count.")
    local canMark = selected and selected.kind == "item" and selected.origin ~= "disenchant"
    if canMark then self.markButton:Enable(); self.unmarkButton:Enable()
    else self.markButton:Disable(); self.unmarkButton:Disable() end
    for index, row in ipairs(self.rows) do
        local recordIndex = self.view == "stats" and (self.offset + index) or (count - self.offset - index + 1)
        local entry = records[recordIndex]
        row.entry = entry
        if entry then
            row.clock:SetText(entry.timestamp and date("%H:%M:%S", entry.timestamp) or "")
            row.elapsed:SetText(entry.elapsed ~= nil and Core.FormatElapsed(entry.elapsed) or "-")
            row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.item:SetText(entry.link and entry.link ~= "" and entry.link or entry.name or "Unknown loot")
            row.quantity:SetText(tostring(entry.quantity))
            local isMaterial = entry.origin == "disenchant" or entry.isMaterial
            local percent = not isMaterial and entry.kind ~= "money" and entry.kind ~= "currency"
                and percentages[entry.key or Core.ItemKey(entry.link, entry.name)] or nil
            row.percent:SetText(percent and string.format("%.1f%%", percent) or "-")
            row.processing:SetText(isMaterial and "DE material"
                or (entry.disenchanted or 0) > 0 and ("DE: " .. entry.disenchanted) or "-")
            row:Show()
        else
            row:Hide()
        end
    end
end

function App:UpdateSessionStats()
    local mobs = Core.MobStats(self.db, now())
    self.timerText:SetText("Session time: " .. Core.FormatElapsed(mobs.elapsed))
    self.mobText:SetText(string.format("Mobs: %d  |  Mobs/hour: %.1f  |  While timed: %d", mobs.total, mobs.perHour, mobs.timed))
end

function App:SetView(view)
    self.view = view == "stats" and "stats" or "loot"
    self.offset = 0
    self:Refresh()
end

function App:SelectEntry(entryID)
    self.selectedEntryID = entryID
    self:Refresh()
end

function App:MarkSelectedDisenchanted(quantity)
    for _, entry in ipairs(self.db.entries) do
        if entry.id == self.selectedEntryID then
            local marked = Core.MarkDisenchanted(self.db, entry.link, quantity or 1, now(), entry.id)
            if marked == 0 then say("Select an item that is not fully marked as disenchanted.") end
            self:Refresh()
            return marked
        end
    end
    say("Select an item entry in the loot list first.")
    return 0
end

function App:UnmarkSelectedDisenchanted(quantity)
    local restored = Core.UnmarkDisenchanted(self.db, self.selectedEntryID, quantity or 1)
    self:Refresh()
    return restored
end

function App:RequestReset()
    StaticPopup_Show(RESET_DIALOG)
end

function App:SetTimer(enabled)
    Core.SetTimerEnabled(self.db, enabled, now())
    self:Refresh()
end

function App:ShowExport(mode)
    if not self.exportFrame then
        local frame = movableFrame("ClassicLootLogExportFrame", 740, 470, "Export loot log")
        label(frame, "Ctrl+A, Ctrl+C: copy all text and save it outside WoW as .txt or .tsv.", 18, -52, 704)
        label(frame, "WoW also saves the full list on logout or /reload (SavedVariables).", 18, -74, 704)
        local scroll = CreateFrame("ScrollFrame", "ClassicLootLogExportScrollFrame", frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -104)
        scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -42, 48)
        local edit = CreateFrame("EditBox", "ClassicLootLogExportEditBox", scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(660)
        edit:SetHeight(300)
        edit:SetMaxLetters(0)
        Compat.SetScript(edit, "OnEscapePressed", function() frame:Hide() end)
        Compat.SetScript(edit, "OnTextChanged", function()
            scroll:UpdateScrollChildRect()
        end)
        scroll:SetScrollChild(edit)
        frame.edit = edit
        button(frame, "Select all", 140, 18, -432, function()
            edit:SetFocus()
            edit:HighlightText()
        end)
        button(frame, "Loot entries", 100, 170, -432, function() self:ShowExport("loot") end)
        button(frame, "Statistics", 110, 280, -432, function() self:ShowExport("stats") end)
        Compat.SetScript(frame, "OnHide", function() edit:ClearFocus() end)
        self.exportFrame = frame
    end
    self.exportFrame:Show()
    self.exportFrame.edit:SetText(mode == "stats" and Core.ExportSummary(self.db, now()) or Core.Export(self.db, formatTimestamp))
    self.exportFrame.edit:SetFocus()
    self.exportFrame.edit:HighlightText()
end

function App:CreateWindow()
    local frame = movableFrame("ClassicLootLogFrame", 900, 590, "Classic Loot Log")
    self.frame = frame
    button(frame, "Reset", 90, 18, -54, function() self:RequestReset() end)
    button(frame, "Export log", 140, 116, -54, function() self:ShowExport() end)
    self.timerButton = button(frame, "Timer: OFF", 120, 264, -54, function()
        self:SetTimer(not self.db.timer.enabled)
    end)
    self.timerText = label(frame, "", 404, -61, 340)
    self.viewButton = button(frame, "Item shares", 145, 737, -54, function()
        self:SetView(self.view == "stats" and "loot" or "stats")
    end)
    self.mobText = label(frame, "", 18, -94, 860, "GameFontNormal")
    self.status = label(frame, "", 18, -119, 860)
    label(frame, "Time", 18, -149, 70, "GameFontNormal")
    label(frame, "Timer", 100, -149, 80, "GameFontNormal")
    label(frame, "Loot", 202, -149, 350, "GameFontNormal")
    label(frame, "Qty", 574, -149, 60, "GameFontNormal")
    label(frame, "% items", 646, -149, 75, "GameFontNormal")
    label(frame, "Processing", 742, -149, 110, "GameFontNormal")
    self.empty = label(frame, "", 22, -187, 830)
    self.rows = {}
    for index = 1, ROWS do
        local row = CreateFrame("Button", nil, frame)
        Compat.SetSize(row, 844, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -170 - (index - 1) * ROW_HEIGHT)
        row.clock = label(row, "", 0, -6, 75)
        row.elapsed = label(row, "", 82, -6, 80)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        Compat.SetSize(row.icon, 20, 20)
        row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 158, -2)
        row.item = label(row, "", 184, -6, 350)
        row.quantity = label(row, "", 556, -6, 58)
        row.percent = label(row, "", 628, -6, 75)
        row.processing = label(row, "", 724, -6, 110)
        Compat.SetScript(row, "OnEnter", function(control)
            if control.entry and control.entry.link and control.entry.link ~= "" then
                GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
                Compat.TooltipItem(GameTooltip, control.entry.link)
                GameTooltip:Show()
            end
        end)
        Compat.SetScript(row, "OnLeave", function() GameTooltip:Hide() end)
        Compat.SetScript(row, "OnClick", function(control)
            if control.entry and control.entry.link and control.entry.link ~= "" and Compat.IsChatLinkModified() then
                Compat.InsertLink(control.entry.link)
            elseif control.entry and self.view ~= "stats" then
                self:SelectEntry(control.entry.id)
            end
        end)
        self.rows[index] = row
    end
    local slider = CreateFrame("Slider", nil, frame)
    slider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -171)
    Compat.SetSize(slider, 14, ROWS * ROW_HEIGHT)
    slider:SetOrientation("VERTICAL")
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    if not Compat.IsLegacy then slider:SetObeyStepOnDrag(true) end
    slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    Compat.SetScript(slider, "OnValueChanged", function(_, value)
        local offset = math.floor(value + 0.5)
        if self.offset ~= offset then
            self.offset = offset
            self:Refresh()
        end
    end)
    self.scrollbar = slider
    frame:EnableMouseWheel(true)
    Compat.SetScript(frame, "OnMouseWheel", function(_, delta)
        local stats = self.view == "stats" and Core.ItemStats(self.db)
        local count = stats and (table.getn(stats.rows) + table.getn(stats.materialRows)) or table.getn(self.db.entries)
        local maxOffset = math.max(0, count - ROWS)
        self.offset = math.max(0, math.min(maxOffset, (self.offset or 0) - delta * 3))
        self:Refresh()
    end)
    self.selectionText = label(frame, "", 18, -508, 860)
    self.markButton = button(frame, "Disenchanted +1", 130, 18, -533, function() self:MarkSelectedDisenchanted(1) end)
    self.unmarkButton = button(frame, "Undo DE -1", 130, 158, -533, function() self:UnmarkSelectedDisenchanted(1) end)
    label(frame, "Disenchanting is detected when possible. Use these buttons for corrections.", 302, -540, 575)
    label(frame, "Mobs/hour uses timed kills. Item % = item quantity / all original items.", 18, -570, 860)
    local updateElapsed = 0
    Compat.SetScript(frame, "OnUpdate", function(_, elapsed)
        updateElapsed = updateElapsed + elapsed
        if updateElapsed >= 0.25 then
            updateElapsed = 0
            self:UpdateSessionStats()
        end
    end)
end

function App:Toggle()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Refresh()
        self.frame:Show()
    end
end

function App:CaptureLoot()
    if not self.db then return end
    if not lootSession then
        lootSequence = lootSequence + 1
        lootSession = "window:" .. tostring(time()) .. ":" .. tostring(lootSequence)
        fallbackIdentities = {}
    end
    if self.tracker and self.tracker:IsDisenchantPending() then return false end
    local context = self.tracker and self.tracker:GetLootContext()
    local slots, complete = {}, true
    for index = 1, GetNumLootItems() do
        local icon, name, quantity, quality = Compat.GetLootSlotInfo(index)
        local slotType = Compat.LootSlotType(index)
        local link = GetLootSlotLink(index)
        -- Cache misses must not change an item's identity from its name to a
        -- link later. Keep the other valid drops, including during auto-loot.
        if slotType == 0 then
            -- Cleared slots can remain visible while auto-loot is running.
        elseif not name or name == "" or (slotType == (LOOT_SLOT_ITEM or 1) and (not link or link == "")) then
            complete = false
        else
            quantity = tonumber(quantity) or 1
            if quantity <= 0 then quantity = 1 end
            local sources = Compat.GetLootSources(index)
            for _, source in ipairs(sources) do
                if source.quantity <= 0 then source.quantity = quantity end
            end
            if table.getn(sources) == 0 and UnitIsDead and UnitIsDead("target") then
                local corpseGUID = Compat.UnitGUIDSafe("target")
                if corpseGUID then sources[1] = { guid = corpseGUID, quantity = quantity } end
            end
            local kind = slotType == (LOOT_SLOT_MONEY or 2) and "money"
                or slotType == (LOOT_SLOT_CURRENCY or 3) and "currency" or "item"
            local identity = kind == "money" and kind or kind .. ":" .. (link or name)
            if table.getn(sources) == 0 then fallbackIdentities[identity] = true end
            slots[table.getn(slots) + 1] = {
                icon = icon, name = name, quantity = quantity, quality = quality,
                link = link, sources = sources, kind = kind, identity = identity,
            }
        end
    end
    -- If metadata appears late, keep using this window's original identity.
    -- Use it for every matching slot so identical stacks still aggregate.
    for _, slot in ipairs(slots) do
        if context then
            slot.origin = "disenchant"
            slot.sourceLabel = "Disenchant"
            slot.sources = { { guid = context.sourceGUID, quantity = slot.quantity } }
        elseif fallbackIdentities[slot.identity] then
            slot.sources = { { guid = lootSession, quantity = slot.quantity } }
        end
    end
    local added = Core.AddSnapshot(self.db, slots, time(), now())
    if added > 0 then self:Refresh() end
    return complete
end

local function captureWithRetry(attempt)
    if App:CaptureLoot() == false and attempt < 5 then
        local session = lootSession
        Compat.After(0.2, function()
            if lootSession == session then captureWithRetry(attempt + 1) end
        end)
    end
end

function App:Initialize()
    if self.db then return end
    ClassicLootLogDB = Core.Initialize(ClassicLootLogDB, now())
    self.db = ClassicLootLogDB
    self.tracker = Tracker.New({
        includeGroup = true,
        now = now,
        onKill = function(guid, name, timestamp, clock)
            if Core.RecordMobKill(self.db, guid, name, timestamp, clock) then self:Refresh() end
        end,
        onDisenchant = function(link, quantity, clock)
            local marked = Core.MarkDisenchanted(self.db, link, quantity, clock)
            if marked > 0 then self:Refresh() end
        end,
    })
    StaticPopupDialogs[RESET_DIALOG] = {
        text = "Reset all loot, mob counts, disenchant marks and session time?",
        button1 = "Reset", button2 = "Cancel",
        OnAccept = function()
            Core.Reset(self.db, now())
            self.tracker:Reset()
            lootSession = nil
            self.selectedEntryID = nil
            self.offset = 0
            if self.exportFrame then self.exportFrame:Hide() end
            self:Refresh()
            say("Loot, mob counts, disenchant marks and timer reset.")
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    self:CreateWindow()
    self:Refresh()
    SLASH_CLASSICLOOTLOG1 = "/cll"
    SLASH_CLASSICLOOTLOG2 = "/lootlog"
    SlashCmdList.CLASSICLOOTLOG = function(message)
        local first, last, command, argument = string.find(string.lower(message or ""), "^%s*(%S*)%s*(.-)%s*$")
        if command == "" or command == "show" then
            if command == "show" then self:Refresh(); self.frame:Show() else self:Toggle() end
        elseif command == "hide" then self.frame:Hide()
        elseif command == "reset" then self:RequestReset()
        elseif command == "log" then self:ShowExport()
        elseif command == "stats" or command == "statistieken" then
            self:SetView("stats")
            self.frame:Show()
        elseif command == "timer" then
            if argument == "on" or argument == "aan" then self:SetTimer(true)
            elseif argument == "off" or argument == "uit" then self:SetTimer(false)
            elseif argument == "" then self:SetTimer(not self.db.timer.enabled)
            else say("Usage: /cll timer [on|off].") end
        else say("Commands: /cll, /cll stats, /cll reset, /cll log, /cll timer [on|off].") end
    end
    say("Loaded. Type /cll to open the loot list.")
end

Compat.RegisterEvent(eventFrame, "ADDON_LOADED")
Compat.RegisterEvent(eventFrame, "PLAYER_LOGOUT")
Compat.RegisterEvent(eventFrame, "LOOT_READY")
Compat.RegisterEvent(eventFrame, "LOOT_OPENED")
Compat.RegisterEvent(eventFrame, "LOOT_SLOT_CHANGED")
Compat.RegisterEvent(eventFrame, "LOOT_CLOSED")
Compat.RegisterEvent(eventFrame, "COMBAT_LOG_EVENT_UNFILTERED")
Compat.RegisterEvent(eventFrame, "UNIT_SPELLCAST_SENT")
Compat.RegisterEvent(eventFrame, "UNIT_SPELLCAST_START")
Compat.RegisterEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED")
Compat.RegisterEvent(eventFrame, "UNIT_SPELLCAST_FAILED")
Compat.RegisterEvent(eventFrame, "UNIT_SPELLCAST_INTERRUPTED")
Compat.RegisterEvent(eventFrame, "UNIT_SPELLCAST_STOP")
Compat.RegisterEvent(eventFrame, "BAG_UPDATE_DELAYED")
Compat.RegisterEvent(eventFrame, "LOOT_SLOT_CLEARED")
for _, eventName in ipairs(Tracker.LegacyEvents or {}) do
    Compat.RegisterEvent(eventFrame, eventName)
end
Compat.SetScript(eventFrame, "OnEvent", function(_, event, a, b, c, d)
    if App.tracker then App.tracker:HandleEvent(event, a, b, c, d) end
    if event == "ADDON_LOADED" then
        local name = a
        if name == addonName then App:Initialize() end
    elseif event == "PLAYER_LOGOUT" then
        if App.db then Core.CheckpointTimer(App.db, now()) end
    elseif event == "LOOT_CLOSED" then
        lootSession = nil
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" or ((event == "LOOT_SLOT_CHANGED" or event == "LOOT_SLOT_CLEARED") and lootSession) then
        captureWithRetry(0)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if App.tracker and App.tracker:IsLootOpen() then captureWithRetry(0) end
    elseif event == "SPELLCAST_STOP" or event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
        if App.tracker and App.tracker:IsLootOpen() then captureWithRetry(0) end
    end
end)
