ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
-- The manual ZIP and the launcher entry point share one running instance.
if ns.App then return end
local addonName = "ClassicLootLog"
local launcherAddonName = "Test-plugin"
local Compat = ns.Compat
local Core = ns.Core
local Tracker = ns.Tracker
local Value = ns.Value
local GroupEvents = ns.GroupEvents
local App = {}
ns.App = App

local COMMANDS = {
    {command = "/cll or /lootlog", description = "Open or close Classic Loot Log."},
    {command = "/cll show / hide", description = "Show or hide the main window."},
    {command = "/cll commands", description = "Open this command reference (also: /cll help)."},
    {command = "/cll group", description = "Open the party / raid loot tracker."},
    {command = "/cll stats", description = "Show item shares in the loot tab."},
    {command = "/cll reset", description = "Confirm clearing session loot, mobs and party / raid history."},
    {command = "/cll log", description = "Export the current tab; select another export with its buttons."},
    {command = "/cll timer [on|off]", description = "Start, pause or toggle the session stopwatch."},
    {command = "/cll scale [on|off]", description = "Enable, disable or toggle automatic text scaling."},
    {command = "/cll lock [on|off]", description = "Lock, unlock or toggle window resizing."},
    {command = "/cll price ID COPPER", description = "Set a manual vendor price per item, overriding SellValue."},
    {command = "/cll price ID clear", description = "Remove an override and resume SellValue/client price lookup."},
    {command = "/cll epic [on|off]", description = "Enable, disable or toggle purple-drop screen/chat notices."},
    {command = "/cll sound [on|off]", description = "Enable, disable or toggle the optional epic-drop sound."},
    {command = "/cll track ITEMLINK", description = "Start/focus a linked master-loot or EP/GP item before bids or /roll."},
    {command = "/cll focus LOG_ID", description = "Focus an open party / raid item by its numbered log entry."},
    {command = "/cll end", description = "Close the focused item without guessing a recipient."},
}

local ROWS = 13
local MAX_ROWS = 30
local ROW_HEIGHT = 25
local MIN_WIDTH, MAX_WIDTH = 680, 1280
local MIN_HEIGHT, MAX_HEIGHT = 430, 900
local activeFontGroup
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

local function toggleArgument(argument, current)
    if argument == "" then return not current end
    if argument == "on" or argument == "aan" then return true end
    if argument == "off" or argument == "uit" then return false end
    return nil
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

local function rememberFont(font)
    if not activeFontGroup or not font then return end
    local path, size, flags = font:GetFont()
    if path and size then
        activeFontGroup[table.getn(activeFontGroup) + 1] = { font = font, path = path, size = size, flags = flags or "" }
    end
end

local function place(region, parent, x, y, width)
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then region:SetWidth(width) end
end

local function label(parent, text, x, y, width, template)
    local font = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    font:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then font:SetWidth(width) end
    font:SetJustifyH("LEFT")
    font:SetText(text)
    rememberFont(font)
    return font
end

local function button(parent, text, width, x, y, onClick)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    Compat.SetSize(control, width, 25)
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    control:SetText(text)
    if activeFontGroup and control.GetFontString then rememberFont(control:GetFontString()) end
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
    frame.header = header
    local titleText = label(frame, title, 0, 0, 320, "GameFontNormalLarge")
    titleText:ClearAllPoints()
    titleText:SetPoint("CENTER", header, "CENTER", 0, 8)
    titleText:SetHeight(24)
    titleText:SetJustifyH("CENTER")
    frame.titleText = titleText
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
    self:UpdateTabControls()
    if self.tab == "commands" then self:RefreshCommands(); return end
    if self.tab == "group" then self:RefreshGroup(); return end
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
    local maxOffset = math.max(0, count - (self.visibleRows or ROWS))
    self.offset = math.min(self.offset or 0, maxOffset)
    self.scrollbar:SetMinMaxValues(0, maxOffset)
    self.scrollbar:SetValue(self.offset)
    self.status:SetText(self.view == "stats"
        and string.format("Original: %d  |  DE materials: %d", stats.totalQuantity, stats.totalMaterials)
        or string.format("%d loot entries  |  DE: %d", count, stats.totalDisenchanted))
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
        local entry = index <= (self.visibleRows or ROWS) and records[recordIndex] or nil
        row.entry = entry
        if entry and index <= (self.visibleRows or ROWS) then
            row.clock:SetText(entry.timestamp and date("%H:%M:%S", entry.timestamp) or "")
            row.elapsed:SetText(entry.elapsed ~= nil and Core.FormatElapsed(entry.elapsed) or "-")
            row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.item:SetText(entry.link and entry.link ~= "" and entry.link or entry.name or "Unknown loot")
            row.quantity:SetText(tostring(entry.quantity))
            row.vendor:SetText(ns.Value and ns.Value.GetEntryVendorText and ns.Value.GetEntryVendorText(self.db, entry) or "-")
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
    self.tab = "loot"
    self.view = view == "stats" and "stats" or "loot"
    self.offset = 0
    self:Refresh()
end

function App:GetCommands()
    return COMMANDS
end

function App:SetTab(tab)
    if tab ~= "commands" and tab ~= "group" then tab = "loot" end
    self.tab, self.offset = tab, 0
    self:Layout()
end

function App:UpdateTabControls()
    local tab = self.tab or "loot"
    local function visible(control, show)
        if show then control:Show() else control:Hide() end
    end
    for key, control in pairs(self.tabButtons) do
        if key == tab then control:Disable() else control:Enable() end
    end
    visible(self.commandsPanel, tab == "commands")
    visible(self.groupPanel, tab == "group")
    visible(self.viewButton, tab == "loot")
    visible(self.empty, tab == "loot")
    visible(self.selectionText, tab == "loot")
    visible(self.markButton, tab == "loot")
    visible(self.unmarkButton, tab == "loot")
    visible(self.deHint, tab == "loot")
    for _, header in pairs(self.headers) do visible(header, tab == "loot") end
    if tab ~= "loot" then for _, row in ipairs(self.rows) do row:Hide() end end
    self.footer:SetText(tab == "group"
        and "Focus an item for unlinked bids or /roll. Need outranks Greed. A receipt confirms the recipient."
        or tab == "commands" and "Optional arguments in [brackets] may be omitted to toggle a setting. Prices are copper per item."
        or "Mobs/hour uses timed kills. Item % uses original items. Drag the lower-right corner to resize.")
end

function App:RefreshCommands()
    local visible = self.commandVisibleRows or 1
    self.offset = math.max(0, math.min(self.offset or 0, math.max(0, table.getn(COMMANDS) - visible)))
    self.scrollbar:SetMinMaxValues(0, math.max(0, table.getn(COMMANDS) - visible))
    self.scrollbar:SetValue(self.offset)
    self.status:SetText(tostring(table.getn(COMMANDS)) .. " commands")
    for index, row in ipairs(self.commandsRows) do
        local entry = index <= visible and COMMANDS[self.offset + index] or nil
        if entry then
            row.command:SetText(entry.command)
            row.description:SetText(entry.description)
            row:Show()
        else row:Hide() end
    end
    self:UpdateSessionStats()
end

local function methodLabel(entry, compact)
    local distribution = entry.distributionMethod == "master" and "Master loot"
        or entry.distributionMethod == "group" and "Group loot" or "Unknown"
    if entry.method == "epgp" and compact then
        return "EP/GP (" .. (entry.distributionMethod == "master" and "Master" or "Unknown") .. ")"
    end
    return entry.method == "epgp" and ("EP/GP / " .. distribution) or distribution
end

local function rollLabel(roll)
    if not roll then return "-" end
    return roll.player .. " " .. tostring(roll.value) .. (roll.choice ~= "ROLL" and (" " .. roll.choice) or "")
end

function App:SelectGroupEntry(id)
    local entry = self.groupAdapter.model:Get(id)
    if not entry then return false end
    self.selectedGroupID = id
    self.groupAdapter:Select(id)
    self:Refresh()
    return true
end

function App:BeginGroupItem(link)
    if not link or link == "" then
        for _, entry in ipairs(self.db.entries) do
            if entry.id == self.selectedEntryID then link = entry.link; break end
        end
    end
    if not link or link == "" or not string.find(link, "item:%d+") then
        say("Select a loot item first, or use /cll track followed by its item link.")
        return nil
    end
    local entry = self.groupAdapter:BeginItem(link)
    if entry then
        self.selectedGroupID = entry.id
        self:SetTab("group")
        self.frame:Show()
    end
    return entry
end

function App:EndGroupItem()
    local entry = self.groupAdapter.model:GetActive()
    if entry then
        self.groupAdapter.model:Close(entry, "closed_by_user")
        self:Refresh()
    else say("Select an open party / raid item first.") end
end

function App:RefreshGroup()
    local model = self.groupAdapter.model
    local entries, unassigned = model:Entries(), model:GetUnassigned()
    local visible = self.groupVisibleRows or 1
    self.offset = math.max(0, math.min(self.offset or 0, math.max(0, table.getn(entries) - visible)))
    self.scrollbar:SetMinMaxValues(0, math.max(0, table.getn(entries) - visible))
    self.scrollbar:SetValue(self.offset)
    self.groupStatus:SetText(string.format("%d items | Unassigned: %d", table.getn(entries), table.getn(unassigned)))
    for index, row in ipairs(self.groupRows) do
        local entry = index <= visible and entries[table.getn(entries) - self.offset - index + 1] or nil
        row.entry = entry
        if entry then
            local ranks = model:Rankings(entry)
            row.item:SetText("#" .. entry.id .. " " .. entry.link)
            row.method:SetText(methodLabel(entry, true))
            row.winner:SetText(entry.recipient or (entry.observedWinner and (entry.observedWinner .. " (roll)")) or "Pending")
            row.highest:SetText(rollLabel(ranks.highest))
            row.second:SetText(rollLabel(ranks.second))
            row.bid:SetText(entry.winnerBid or "-")
            row:Show()
        else row:Hide() end
    end
    local entry = model:Get(self.selectedGroupID)
    local lines = {}
    if entry then
        local ranks = model:Rankings(entry)
        lines[1] = "#" .. entry.id .. " " .. entry.link .. " | " .. methodLabel(entry) .. " | " .. entry.state
        lines[2] = "Recipient: " .. (entry.recipient or "Not confirmed") .. " | Winning bid: " .. (entry.winnerBid or "Unknown")
        lines[3] = "Highest eligible: " .. rollLabel(ranks.highest) .. " | Second: " .. rollLabel(ranks.second)
        local active = model:GetActive()
        lines[table.getn(lines) + 1] = "Unlinked bids / /roll focus: " .. (active and ("#" .. active.id .. " " .. active.name) or "Only a unique open item; otherwise select an open item first.")
        if ranks.mixedRanges then lines[table.getn(lines) + 1] = "Different /roll ranges are ranked separately:" end
        if ranks.mixedRanges or (ranks.highest and (ranks.min ~= 1 or ranks.max ~= 100)) then
            for _, range in ipairs(ranks.rangeGroups) do
                lines[table.getn(lines) + 1] = "Range " .. range.min .. "-" .. range.max .. ": " .. rollLabel(range.highest) .. " | Second: " .. rollLabel(range.second)
            end
        end
        if ranks.tied then lines[table.getn(lines) + 1] = "Tied highest: " .. table.concat(ranks.tiePlayers, ", ") end
        if ranks.uncertain then lines[table.getn(lines) + 1] = "Some Need/Greed choices were not observed; ranking may be incomplete." end
        for _, key in ipairs(entry.choiceOrder) do
            local choice = entry.choices[key]
            lines[table.getn(lines) + 1] = choice.player .. ": " .. choice.choice
        end
        for _, roll in ipairs(entry.rolls) do
            lines[table.getn(lines) + 1] = roll.player .. ": " .. tostring(roll.value) .. " (" .. roll.min .. "-" .. roll.max .. ") " .. roll.choice
        end
        for _, key in ipairs(entry.bidOrder) do
            local bid = entry.bids[key]
            lines[table.getn(lines) + 1] = bid.player .. ": " .. bid.kind .. " | " .. bid.raw
        end
        if table.getn(entry.rolls) == 0 and table.getn(entry.bidOrder) == 0 then
            lines[table.getn(lines) + 1] = "Waiting for observed rolls, bids or the loot receipt."
        end
    else
        lines[1] = "Select an item above to inspect choices, all rolls and bids."
        lines[2] = "Click Track selected loot or use /cll track ITEMLINK before unlinked /rolls or EP/GP bids."
    end
    if table.getn(unassigned) > 0 then
        lines[table.getn(lines) + 1] = "Unassigned receipts (no unique matching item; see export):"
        for _, receipt in ipairs(unassigned) do
            lines[table.getn(lines) + 1] = (receipt.recipient or "Unknown") .. " received " .. receipt.link .. " | " .. (receipt.reason or "Unknown")
        end
    end
    self.groupDetail:SetText(table.concat(lines, "\n"))
    local detailHeight = math.max(110, table.getn(lines) * 32 * (self.textScale or 1))
    self.groupDetail:SetHeight(detailHeight)
    self.groupDetailChild:SetHeight(detailHeight)
    self.groupDetailScroll:UpdateScrollChildRect()
    self:UpdateSessionStats()
end

function App:CreateExtraTabs(frame)
    self.tabButtons = {
        loot = button(frame, "Loot", 90, 18, -112, function() self:SetTab("loot") end),
        commands = button(frame, "Commands", 120, 116, -112, function() self:SetTab("commands") end),
        group = button(frame, "Party / Raid", 140, 244, -112, function() self:SetTab("group") end),
    }
    self.commandsPanel = CreateFrame("Frame", nil, frame)
    self.groupPanel = CreateFrame("Frame", nil, frame)
    self.groupStatus = self.status
    self.commandHeaders = {
        command = label(self.commandsPanel, "Command", 18, -149, 220, "GameFontNormal"),
        description = label(self.commandsPanel, "Description", 250, -149, 600, "GameFontNormal"),
    }
    self.commandsRows, self.groupRows, self.groupHeaders = {}, {}, {}
    local headings = {item = "Item", method = "Method", winner = "Recipient", highest = "Highest eligible", second = "Second eligible", bid = "Bid"}
    for key, text in pairs(headings) do self.groupHeaders[key] = label(self.groupPanel, text, 18, -149, 100, "GameFontNormal") end
    for index = 1, MAX_ROWS do
        local command = CreateFrame("Frame", nil, self.commandsPanel)
        command.command = label(command, "", 0, -4, 220)
        command.description = label(command, "", 230, -4, 600)
        self.commandsRows[index] = command
        local row = CreateFrame("Button", nil, self.groupPanel)
        for key in pairs(headings) do row[key] = label(row, "", 0, -4, 100) end
        Compat.SetScript(row, "OnClick", function(control)
            if control.entry then self:SelectGroupEntry(control.entry.id) end
        end)
        Compat.SetScript(row, "OnEnter", function(control)
            if control.entry then
                GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
                Compat.TooltipItem(GameTooltip, control.entry.link)
                GameTooltip:Show()
            end
        end)
        Compat.SetScript(row, "OnLeave", function() GameTooltip:Hide() end)
        self.groupRows[index] = row
    end
    self.groupDetailScroll = CreateFrame("ScrollFrame", "ClassicLootLogGroupDetailScroll", self.groupPanel, "UIPanelScrollFrameTemplate")
    self.groupDetailChild = CreateFrame("Frame", nil, self.groupDetailScroll)
    Compat.SetSize(self.groupDetailChild, 600, 110)
    self.groupDetail = label(self.groupDetailChild, "", 0, 0, 800)
    self.groupDetailScroll:SetScrollChild(self.groupDetailChild)
    self.trackItemButton = button(self.groupPanel, "Track selected loot", 170, 18, -533, function() self:BeginGroupItem() end)
    self.endItemButton = button(self.groupPanel, "Close focused item", 170, 198, -533, function() self:EndGroupItem() end)
end

function App:LayoutExtraTabs(width, height, scale, rowHeight)
    for _, panel in ipairs({self.commandsPanel, self.groupPanel}) do
        Compat.SetSize(panel, width, height)
        panel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
    end
    local commandHeight = math.floor(38 * scale + 0.5)
    self.commandVisibleRows = math.max(1, math.min(MAX_ROWS, math.floor((height - 265) / commandHeight)))
    local commandWidth = math.min(250 * scale, width * 0.4)
    place(self.commandHeaders.command, self.commandsPanel, 18, -149, commandWidth)
    place(self.commandHeaders.description, self.commandsPanel, 32 + commandWidth, -149, width - commandWidth - 78)
    for index, row in ipairs(self.commandsRows) do
        Compat.SetSize(row, width - 56, commandHeight)
        place(row, self.commandsPanel, 18, -170 - (index - 1) * commandHeight)
        place(row.command, row, 0, -4, commandWidth)
        place(row.description, row, commandWidth + 14, -4, width - commandWidth - 78)
        row.command:SetHeight(commandHeight - 6)
        row.description:SetHeight(commandHeight - 6)
    end
    self.groupVisibleRows = math.max(1, math.min(MAX_ROWS, math.floor((height - 400) / rowHeight)))
    local usable = width - 56
    local sizes = {method = 100 * scale, winner = 95 * scale, highest = 115 * scale, second = 115 * scale, bid = 45 * scale}
    local itemWidth = usable - sizes.method - sizes.winner - sizes.highest - sizes.second - sizes.bid - 40
    local positions = {item = 0, method = itemWidth + 8}
    positions.winner = positions.method + sizes.method + 8
    positions.highest = positions.winner + sizes.winner + 8
    positions.second = positions.highest + sizes.highest + 8
    positions.bid = positions.second + sizes.second + 8
    sizes.item = itemWidth
    for key, header in pairs(self.groupHeaders) do place(header, self.groupPanel, 18 + positions[key], -149, sizes[key]) end
    for index, row in ipairs(self.groupRows) do
        Compat.SetSize(row, usable, rowHeight)
        place(row, self.groupPanel, 18, -170 - (index - 1) * rowHeight)
        for key in pairs(self.groupHeaders) do
            place(row[key], row, positions[key], -4, sizes[key])
            row[key]:SetHeight(math.max(1, rowHeight - 6))
        end
    end
    self.groupDetailScroll:SetPoint("TOPLEFT", self.groupPanel, "TOPLEFT", 20, -178 - self.groupVisibleRows * rowHeight)
    self.groupDetailScroll:SetPoint("BOTTOMRIGHT", self.groupPanel, "BOTTOMRIGHT", -42, 98)
    self.groupDetailChild:SetWidth(width - 70)
    self.groupDetail:SetWidth(width - 70)
    place(self.trackItemButton, self.groupPanel, 18, -height + 57, 170)
    place(self.endItemButton, self.groupPanel, 198, -height + 57, 170)
    local rows = self.tab == "commands" and self.commandVisibleRows or self.tab == "group" and self.groupVisibleRows or self.visibleRows
    local step = self.tab == "commands" and commandHeight or rowHeight
    self.scrollbar:SetHeight(rows * step)
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
    mode = mode or (self.tab == "group" and "group" or self.tab == "commands" and "commands" or "loot")
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
        button(frame, "Party / Raid", 110, 400, -432, function() self:ShowExport("group") end)
        button(frame, "Commands", 100, 520, -432, function() self:ShowExport("commands") end)
        Compat.SetScript(frame, "OnHide", function() edit:ClearFocus() end)
        self.exportFrame = frame
    end
    self.exportFrame:Show()
    local exported
    if mode == "group" then
        exported = self.groupAdapter.model:Export()
    elseif mode == "commands" then
        local lines = {"Command\tDescription"}
        for _, entry in ipairs(COMMANDS) do lines[table.getn(lines) + 1] = entry.command .. "\t" .. entry.description end
        exported = table.concat(lines, "\n")
    elseif mode == "stats" then
        exported = Value.AppendSummary(self.db, Core.ExportSummary(self.db, now()))
    else
        exported = Value.AppendExportColumns(self.db, Core.Export(self.db, formatTimestamp))
    end
    self.exportFrame.edit:SetText(exported)
    self.exportFrame.edit:SetFocus()
    self.exportFrame.edit:HighlightText()
end

function App:Layout()
    if not self.frame or self.layouting then return end
    self.layouting = true
    local frame = self.frame
    local width = math.max(MIN_WIDTH, math.min(MAX_WIDTH, frame:GetWidth()))
    local height = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, frame:GetHeight()))
    if frame:GetWidth() ~= width then frame:SetWidth(width) end
    if frame:GetHeight() ~= height then frame:SetHeight(height) end
    local settings = self.db.ui
    settings.width, settings.height = width, height
    local textScale = settings.autoText and math.max(0.8, math.min(1.3, width / 900)) or 1
    self.textScale = textScale
    for _, style in ipairs(self.fonts) do
        style.font:SetFont(style.path, style.size * textScale, style.flags)
    end
    local rowHeight = math.floor(ROW_HEIGHT * textScale + 0.5)
    self.visibleRows = math.max(1, math.min(MAX_ROWS, math.floor((height - 265) / rowHeight)))
    local usable = width - 56
    local clockWidth = 70 * textScale
    local elapsedX, elapsedWidth = clockWidth + 8, 75 * textScale
    local iconX = elapsedX + elapsedWidth + 8
    local iconSize = 20 * textScale
    local itemX = iconX + iconSize + 6
    local processingWidth, vendorWidth = 90 * textScale, 100 * textScale
    local percentWidth, quantityWidth = 55 * textScale, 40 * textScale
    local processingX = usable - processingWidth
    local vendorX = processingX - 8 - vendorWidth
    local percentX = vendorX - 8 - percentWidth
    local quantityX = percentX - 8 - quantityWidth
    local itemWidth = math.max(70, quantityX - itemX - 8)
    local top = 170
    frame.titleText:SetWidth(math.min(320, width - 80))
    frame.titleText:SetHeight(24 * textScale)
    place(self.resetButton, frame, 18, -54, 84)
    place(self.exportButton, frame, 108, -54, 106)
    place(self.timerButton, frame, 220, -54, 106)
    place(self.timerText, frame, 340, -61, math.max(150, width - 480))
    place(self.viewButton, frame, width - 133, -54, 115)
    place(self.mobText, frame, 18, -94, width - 36)
    place(self.status, frame, 400, -119, width - 418)
    self.status:SetHeight(20 * textScale)
    place(self.headers.clock, frame, 18, -149, clockWidth)
    place(self.headers.elapsed, frame, 18 + elapsedX, -149, elapsedWidth)
    place(self.headers.item, frame, 18 + itemX, -149, itemWidth)
    place(self.headers.quantity, frame, 18 + quantityX, -149, quantityWidth)
    place(self.headers.percent, frame, 18 + percentX, -149, percentWidth)
    place(self.headers.vendor, frame, 18 + vendorX, -149, vendorWidth)
    place(self.headers.processing, frame, 18 + processingX, -149, processingWidth)
    place(self.empty, frame, 22, -187, width - 60)
    for index, row in ipairs(self.rows) do
        Compat.SetSize(row, usable, rowHeight)
        place(row, frame, 18, -top - (index - 1) * rowHeight)
        place(row.clock, row, 0, -6, clockWidth)
        place(row.elapsed, row, elapsedX, -6, elapsedWidth)
        Compat.SetSize(row.icon, iconSize, iconSize)
        place(row.icon, row, iconX, -2)
        place(row.item, row, itemX, -6, itemWidth)
        place(row.quantity, row, quantityX, -6, quantityWidth)
        place(row.percent, row, percentX, -6, percentWidth)
        place(row.vendor, row, vendorX, -6, vendorWidth)
        place(row.processing, row, processingX, -6, processingWidth)
        -- Narrow columns must clip long names instead of wrapping into the
        -- next loot row; the full item remains available in its tooltip.
        for _, text in ipairs({row.clock, row.elapsed, row.item, row.quantity, row.percent, row.vendor, row.processing}) do
            text:SetHeight(math.max(1, rowHeight - 8))
        end
    end
    self.scrollbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -171)
    self.scrollbar:SetHeight(self.visibleRows * rowHeight)
    place(self.selectionText, frame, 18, -height + 82, math.max(260, width - 350))
    self.selectionText:SetHeight(18 * textScale)
    place(self.autoTextButton, frame, width - 304, -height + 88, 146)
    place(self.lockButton, frame, width - 150, -height + 88, 132)
    place(self.markButton, frame, 18, -height + 57, 130)
    place(self.unmarkButton, frame, 158, -height + 57, 130)
    place(self.deHint, frame, 302, -height + 50, width - 320)
    place(self.footer, frame, 18, -height + 28, width - 55)
    self.autoTextButton:SetText(settings.autoText and "Auto text: ON" or "Auto text: OFF")
    self.lockButton:SetText(settings.locked and "Size: LOCKED" or "Size: UNLOCKED")
    if frame.SetResizable then frame:SetResizable(not settings.locked) end
    if settings.locked then self.resizeGrip:Hide() else self.resizeGrip:Show() end
    self:LayoutExtraTabs(width, height, textScale, rowHeight)
    self.layouting = false
    self:Refresh()
end

function App:SetAutoText(enabled)
    self.db.ui.autoText = enabled == true
    self:Layout()
end

function App:SetSizeLocked(locked)
    self.db.ui.locked = locked == true
    if self.isResizing then
        self.frame:StopMovingOrSizing()
        self.isResizing = false
    end
    self:Layout()
end

function App:Resize(width, height)
    if not self.frame then return end
    width = math.max(MIN_WIDTH, math.min(MAX_WIDTH, tonumber(width) or self.frame:GetWidth()))
    height = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, tonumber(height) or self.frame:GetHeight()))
    self.layouting = true
    Compat.SetSize(self.frame, width, height)
    self.layouting = false
    self:Layout()
end

function App:CreateWindow()
    self.db.ui = self.db.ui or { width = 900, height = 590, autoText = true, locked = false }
    local settings = self.db.ui
    self.fonts = {}
    activeFontGroup = self.fonts
    local frame = movableFrame("ClassicLootLogFrame", settings.width or 900, settings.height or 590, "Classic Loot Log")
    self.frame = frame
    if frame.SetMinResize then frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT) end
    if frame.SetMaxResize then frame:SetMaxResize(MAX_WIDTH, MAX_HEIGHT) end
    self.resetButton = button(frame, "Reset", 84, 18, -54, function() self:RequestReset() end)
    self.exportButton = button(frame, "Export log", 106, 108, -54, function() self:ShowExport() end)
    self.timerButton = button(frame, "Timer: OFF", 106, 220, -54, function()
        self:SetTimer(not self.db.timer.enabled)
    end)
    self.timerText = label(frame, "", 340, -61, 190)
    self.viewButton = button(frame, "Item shares", 115, 737, -54, function()
        self:SetView(self.view == "stats" and "loot" or "stats")
    end)
    self.mobText = label(frame, "", 18, -94, 860, "GameFontNormal")
    self.status = label(frame, "", 18, -119, 860)
    self.headers = {
        clock = label(frame, "Time", 18, -149, 70, "GameFontNormal"),
        elapsed = label(frame, "Timer", 100, -149, 80, "GameFontNormal"),
        item = label(frame, "Loot", 202, -149, 340, "GameFontNormal"),
        quantity = label(frame, "Qty", 574, -149, 40, "GameFontNormal"),
        percent = label(frame, "% items", 646, -149, 55, "GameFontNormal"),
        vendor = label(frame, "Vendor", 700, -149, 100, "GameFontNormal"),
        processing = label(frame, "Processing", 800, -149, 90, "GameFontNormal"),
    }
    self.empty = label(frame, "", 22, -187, 830)
    self.rows = {}
    for index = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row.clock = label(row, "", 0, -6, 75)
        row.elapsed = label(row, "", 82, -6, 80)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.item = label(row, "", 184, -6, 340)
        row.quantity = label(row, "", 556, -6, 40)
        row.percent = label(row, "", 628, -6, 55)
        row.vendor = label(row, "", 700, -6, 100)
        row.processing = label(row, "", 800, -6, 90)
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
    Compat.SetSize(slider, 14, ROWS * ROW_HEIGHT)
    slider:SetOrientation("VERTICAL")
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
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
        local count, visible
        if self.tab == "commands" then count, visible = table.getn(COMMANDS), self.commandVisibleRows
        elseif self.tab == "group" then count, visible = table.getn(self.groupAdapter.model:Entries()), self.groupVisibleRows
        else
            local stats = self.view == "stats" and Core.ItemStats(self.db)
            count = stats and (table.getn(stats.rows) + table.getn(stats.materialRows)) or table.getn(self.db.entries)
            visible = self.visibleRows or ROWS
        end
        local maxOffset = math.max(0, count - visible)
        self.offset = math.max(0, math.min(maxOffset, (self.offset or 0) - delta * 3))
        self:Refresh()
    end)
    self.selectionText = label(frame, "", 18, -508, 550)
    self.autoTextButton = button(frame, "Auto text: ON", 146, 596, -502, function()
        self:SetAutoText(not self.db.ui.autoText)
    end)
    self.lockButton = button(frame, "Size: UNLOCKED", 132, 750, -502, function()
        self:SetSizeLocked(not self.db.ui.locked)
    end)
    self.markButton = button(frame, "Disenchanted +1", 130, 18, -533, function() self:MarkSelectedDisenchanted(1) end)
    self.unmarkButton = button(frame, "Undo DE -1", 130, 158, -533, function() self:UnmarkSelectedDisenchanted(1) end)
    self.deHint = label(frame, "Use the DE buttons to correct marked items.", 302, -540, 575)
    self.footer = label(frame, "Mobs/hour uses timed kills. Item % uses original items. Drag the lower-right corner to resize.", 18, -570, 845)
    local grip = CreateFrame("Button", nil, frame)
    Compat.SetSize(grip, 20, 20)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    grip:EnableMouse(true)
    local gripTexture = grip:CreateTexture(nil, "ARTWORK")
    gripTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    gripTexture:SetAllPoints(grip)
    Compat.SetScript(grip, "OnMouseDown", function(_, mouseButton)
        if (not mouseButton or mouseButton == "LeftButton") and not self.db.ui.locked and frame.StartSizing then
            self.isResizing = true
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    Compat.SetScript(grip, "OnMouseUp", function()
        frame:StopMovingOrSizing()
        self.isResizing = false
        self:Layout()
    end)
    self.resizeGrip = grip
    self:CreateExtraTabs(frame)
    Compat.SetScript(frame, "OnSizeChanged", function()
        self:Layout()
    end)
    Compat.SetScript(frame, "OnHide", function()
        if self.isResizing then frame:StopMovingOrSizing(); self.isResizing = false end
    end)
    local updateElapsed = 0
    Compat.SetScript(frame, "OnUpdate", function(_, elapsed)
        updateElapsed = updateElapsed + elapsed
        if updateElapsed >= 0.25 then
            updateElapsed = 0
            self:UpdateSessionStats()
        end
    end)
    activeFontGroup = nil
    self:Layout()
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
    local firstNewEntry = table.getn(self.db.entries) + 1
    local added = Core.AddSnapshot(self.db, slots, time(), now())
    if added > 0 then
        Value.NotifyEntries(self.db, firstNewEntry)
        -- Native roll IDs identify Group Loot independently. Master Loot has
        -- no such event, so attach newly observed originals to their source.
        if self.groupAdapter:Method() == "master" then
            for index = firstNewEntry, table.getn(self.db.entries) do
                local entry = self.db.entries[index]
                if entry.kind == "item" and entry.origin ~= "disenchant" then
                    self.groupAdapter:ObserveItem(entry.link, entry.name, entry.quality, tostring(entry.source) .. ":" .. entry.id)
                end
            end
        end
        self:Refresh()
    end
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
    Value.Initialize(self.db)
    self.groupAdapter = GroupEvents.New(self.db, {
        now = now, time = time,
        onChange = function() self:Refresh() end,
    })
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
            self.db.groupLoot = {}
            self.groupAdapter:Reset()
            lootSession = nil
            self.selectedEntryID = nil
            self.selectedGroupID = nil
            self.offset = 0
            if self.exportFrame then self.exportFrame:Hide() end
            self:Refresh()
            say("Loot, mobs, party / raid history, disenchant marks and timer reset.")
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    self:CreateWindow()
    self:Refresh()
    SLASH_CLASSICLOOTLOG1 = "/cll"
    SLASH_CLASSICLOOTLOG2 = "/lootlog"
    SlashCmdList.CLASSICLOOTLOG = function(message)
        local first, last, command, rawArgument = string.find(message or "", "^%s*(%S*)%s*(.-)%s*$")
        command = string.lower(command)
        local argument = string.lower(rawArgument)
        if command == "" or command == "show" then
            if command == "show" then self:Refresh(); self.frame:Show() else self:Toggle() end
        elseif command == "hide" then self.frame:Hide()
        elseif command == "reset" then self:RequestReset()
        elseif command == "log" then self:ShowExport()
        elseif command == "commands" or command == "help" then
            self:SetTab("commands"); self.frame:Show()
        elseif command == "group" or command == "raid" then
            self:SetTab("group"); self.frame:Show()
        elseif command == "track" then
            self:BeginGroupItem(rawArgument ~= "" and rawArgument or nil)
        elseif command == "focus" then
            local entry = self.groupAdapter.model:Get(tonumber(argument))
            if entry and entry.state == "open" then self:SelectGroupEntry(entry.id)
            else say("Use /cll focus followed by an open party / raid log ID.") end
        elseif command == "end" then
            self:EndGroupItem()
        elseif command == "stats" or command == "statistieken" then
            self:SetView("stats")
            self.frame:Show()
        elseif command == "timer" then
            if argument == "on" or argument == "aan" then self:SetTimer(true)
            elseif argument == "off" or argument == "uit" then self:SetTimer(false)
            elseif argument == "" then self:SetTimer(not self.db.timer.enabled)
            else say("Usage: /cll timer [on|off].") end
        elseif command == "price" then
            local start, finish, item, amount = string.find(argument, "^(%d+)%s+(%S+)$")
            if item and amount == "clear" and Value.ClearPrice(self.db, tonumber(item)) then
                say("Automatic vendor pricing restored for item " .. item .. ".")
                self:Refresh()
            elseif item and Value.SetPrice(self.db, tonumber(item), tonumber(amount)) then
                say("Vendor price for item " .. item .. ": " .. Value.FormatMoney(tonumber(amount)) .. " each.")
                self:Refresh()
            else say("Usage: /cll price <item ID> <copper per item|clear>.") end
        elseif command == "epic" or command == "sound" then
            local key = command == "epic" and "epic" or "sound"
            local enabled = toggleArgument(argument, self.db.alerts[key])
            if enabled == nil then
                say("Usage: /cll " .. command .. " [on|off].")
            else
                self.db.alerts[key] = enabled
                say((command == "epic" and "Epic alerts: " or "Alert sound: ") .. (enabled and "ON" or "OFF"))
            end
        elseif command == "scale" or command == "lock" then
            local current = self.db.ui.locked
            if command == "scale" then current = self.db.ui.autoText end
            local enabled = toggleArgument(argument, current)
            if enabled == nil then
                say("Usage: /cll " .. command .. " [on|off].")
            elseif command == "scale" then self:SetAutoText(enabled)
            else self:SetSizeLocked(enabled) end
        else say("Type /cll commands for every command and /cll group for party / raid loot.") end
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
Compat.RegisterEvent(eventFrame, "MERCHANT_SHOW")
for _, eventName in ipairs(GroupEvents.Events) do Compat.RegisterEvent(eventFrame, eventName) end
for _, eventName in ipairs(Tracker.LegacyEvents or {}) do
    Compat.RegisterEvent(eventFrame, eventName)
end
Compat.SetScript(eventFrame, "OnEvent", function(_, event, a, b, c, d)
    if App.tracker then App.tracker:HandleEvent(event, a, b, c, d) end
    if App.groupAdapter then App.groupAdapter:HandleEvent(event, a, b, c, d) end
    if event == "ADDON_LOADED" then
        local name = a
        if name == addonName or name == launcherAddonName then
            if App.db then
                -- Loading a second addon folder can replace a SavedVariables
                -- global. Keep the existing live database and event handlers.
                ClassicLootLogDB = App.db
                if App.loadedAddon ~= name then
                    say("Two addon copies are enabled. Keep one copy enabled to use a single saved history.")
                end
            else
                App.loadedAddon = name
                App:Initialize()
            end
        elseif name == "SellValue" and App.db then
            Value.RefreshPrices(App.db)
            App:Refresh()
        end
    elseif event == "MERCHANT_SHOW" and App.db then
        Compat.After(0, function()
            Value.RefreshPrices(App.db)
            App:Refresh()
        end)
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
