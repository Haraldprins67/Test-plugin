-- An in-game archive reader. Saved text is data, never executed as Lua.
ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local Compat, SavedLogs = ns.Compat, ns.SavedLogs
local LogsPanel = {}
LogsPanel.__index = LogsPanel
ns.LogsPanel = LogsPanel

local serial = 0

local function place(region, parent, x, y, width, height)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then region:SetWidth(width) end
    if height then region:SetHeight(height) end
end

local function remember(self, region)
    local path, size, flags = region:GetFont()
    if path and size then
        self.fonts[table.getn(self.fonts) + 1] = {
            region = region, path = path, size = size, flags = flags or "",
        }
    end
end

local function label(self, parent, text)
    local region = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    region:SetJustifyH("LEFT")
    region:SetText(text or "")
    remember(self, region)
    return region
end

local function button(self, text, callback)
    local control = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    control:SetText(text)
    Compat.SetScript(control, "OnClick", callback)
    if control.GetFontString then remember(self, control:GetFontString()) end
    return control
end

local function scrollWheel(scroll)
    scroll:EnableMouseWheel(true)
    Compat.SetScript(scroll, "OnMouseWheel", function(_, delta)
        local limit = math.max(0, scroll:GetVerticalScrollRange())
        scroll:SetVerticalScroll(math.max(0, math.min(limit,
            scroll:GetVerticalScroll() - (tonumber(delta) or 0) * 36)))
    end)
end

-- Use a conservative bound for the wrapped report height. It only affects the
-- scrollable extent; the edit box itself handles actual font rendering/wrapping.
local function reportHeight(text, width, fontSize)
    local columns = math.max(1, math.floor(width / math.max(1, fontSize)))
    local lines, start = 0, 1
    while true do
        local ending = string.find(text, "\n", start, true)
        local length = (ending or (string.len(text) + 1)) - start
        lines = lines + math.max(1, math.ceil(length / columns))
        if not ending then break end
        start = ending + 1
    end
    return math.max(80, lines * (fontSize + 3) + 20)
end

function LogsPanel.New(parent, db, callbacks)
    serial = serial + 1
    local self = setmetatable({db = db, callbacks = callbacks or {}, rows = {},
        fonts = {}, text = "", scale = 1, listWidth = 230, reportWidth = 500}, LogsPanel)
    local frame = CreateFrame("Frame", nil, parent)
    self.frame = frame
    self.archiveHeader = label(self, frame, "Saved logs")
    self.reportHeader = label(self, frame, "Select a saved log to review it.")
    self.empty = label(self, frame, "No saved logs yet. Click Save log to archive the current session.")
    self.storageHint = label(self, frame, "Select all, Ctrl+C to copy. Saved on /reload or logout.")
    self.listScroll = CreateFrame("ScrollFrame", "ClassicLootLogSavedListScroll" .. serial,
        frame, "UIPanelScrollFrameTemplate")
    self.listChild = CreateFrame("Frame", nil, self.listScroll)
    Compat.SetSize(self.listChild, 230, 80)
    self.listScroll:SetScrollChild(self.listChild)
    scrollWheel(self.listScroll)
    self.reportScroll = CreateFrame("ScrollFrame", "ClassicLootLogSavedReportScroll" .. serial,
        frame, "UIPanelScrollFrameTemplate")
    self.edit = CreateFrame("EditBox", "ClassicLootLogSavedReportEdit" .. serial, self.reportScroll)
    self.edit:SetMultiLine(true)
    self.edit:SetAutoFocus(false)
    self.edit:SetFontObject(ChatFontNormal)
    self.edit:SetMaxLetters(0)
    Compat.SetSize(self.edit, 500, 80)
    remember(self, self.edit)
    self.reportScroll:SetScrollChild(self.edit)
    scrollWheel(self.reportScroll)
    Compat.SetScript(self.edit, "OnEscapePressed", function() self.edit:ClearFocus() end)
    Compat.SetScript(self.edit, "OnTextChanged", function()
        -- The reader permits selection/copying without changing the archive.
        if not self.settingText and self.edit:GetText() ~= self.text then self:RestoreText() end
        self.reportScroll:UpdateScrollChildRect()
    end)
    Compat.SetScript(frame, "OnHide", function() self.edit:ClearFocus() end)
    self.saveButton = button(self, "Save log", function()
        if self.callbacks.save then self.callbacks.save() end
    end)
    self.selectAllButton = button(self, "Select all", function()
        if self.selectedID then self.edit:SetFocus(); self.edit:HighlightText() end
    end)
    self:Layout(parent:GetWidth(), parent:GetHeight(), 1)
    self:Refresh()
    return self
end

function LogsPanel:RestoreText()
    self.settingText = true
    self.edit:SetText(self.text)
    self.settingText = false
end

function LogsPanel:UpdateReportSize()
    local size = self.reportFontSize or 12
    self.edit:SetWidth(self.reportWidth)
    self.edit:SetHeight(math.max(self.viewportHeight or 80,
        reportHeight(self.text, self.reportWidth, size)))
    self.reportScroll:UpdateScrollChildRect()
end

function LogsPanel:Select(id)
    local entry = SavedLogs.Get(self.db, id)
    self:Refresh(entry and entry.id or nil)
end

function LogsPanel:Refresh(selectedID)
    local entries = SavedLogs.Entries(self.db)
    local selected = SavedLogs.Get(self.db, selectedID or self.selectedID)
    if not selected then selected = entries[1] end
    local id = selected and selected.id or nil
    local changed = self.selectedID ~= id or self.text ~= (selected and selected.text or "")
    self.selectedID = id
    self.text = selected and selected.text or ""
    self.archiveHeader:SetText("Saved logs (" .. tostring(table.getn(entries)) .. ")")
    self.reportHeader:SetText(selected and selected.title or "Select a saved log to review it.")
    if selected then self.empty:Hide(); self.selectAllButton:Enable()
    else self.empty:Show(); self.selectAllButton:Disable() end
    local rowHeight = 44 * self.scale
    for index, entry in ipairs(entries) do
        local row = self.rows[index]
        if not row then
            row = CreateFrame("Button", nil, self.listChild)
            row.text = label(self, row, "")
            local style = self.fonts[table.getn(self.fonts)]
            if style and style.region == row.text then
                row.text:SetFont(style.path, style.size * self.scale, style.flags)
            end
            Compat.SetScript(row, "OnClick", function(control) self:Select(control.entryID) end)
            self.rows[index] = row
        end
        row.entryID, row.entry = entry.id, entry
        place(row, self.listChild, 0, -(index - 1) * rowHeight, self.listWidth, rowHeight)
        place(row.text, row, 3, -4, self.listWidth - 8, rowHeight - 8)
        row.text:SetText((entry.id == id and "> " or "") .. entry.title)
        row:Show()
    end
    for index = table.getn(entries) + 1, table.getn(self.rows) do self.rows[index]:Hide() end
    self.listChild:SetHeight(math.max(self.viewportHeight or 80, table.getn(entries) * rowHeight))
    self.listScroll:UpdateScrollChildRect()
    if changed then
        self:RestoreText()
        self.edit:ClearFocus()
        self.reportScroll:SetVerticalScroll(0)
    end
    self:UpdateReportSize()
end

function LogsPanel:Layout(width, height, scale)
    scale = tonumber(scale) or 1
    self.scale = math.max(0.5, scale)
    Compat.SetSize(self.frame, width, height)
    place(self.frame, self.frame:GetParent(), 0, 0)
    for _, style in ipairs(self.fonts) do
        style.region:SetFont(style.path, style.size * self.scale, style.flags)
        if style.region == self.edit then self.reportFontSize = style.size * self.scale end
    end
    self.listWidth = math.max(160, math.min(280, width * 0.28))
    local reportX = 18 + self.listWidth + 40
    self.reportWidth = math.max(120, width - reportX - 48)
    self.viewportHeight = math.max(60, height - 271)
    place(self.archiveHeader, self.frame, 18, -149, self.listWidth, 20)
    place(self.reportHeader, self.frame, reportX, -149, self.reportWidth, 20)
    place(self.listScroll, self.frame, 18, -173, self.listWidth, self.viewportHeight)
    self.listChild:SetWidth(self.listWidth)
    place(self.reportScroll, self.frame, reportX, -173, self.reportWidth, self.viewportHeight)
    place(self.empty, self.frame, reportX + 5, -184, self.reportWidth - 10, 72)
    place(self.saveButton, self.frame, 18, -height + 57, 130, 25)
    place(self.selectAllButton, self.frame, 158, -height + 57, 120, 25)
    place(self.storageHint, self.frame, 290, -height + 50, math.max(80, width - 310), 20)
    self:UpdateReportSize()
    if self.entriesReady then self:Refresh() end
    self.entriesReady = true
end

function LogsPanel:SetDatabase(db)
    self.db, self.selectedID = db, nil
    self.listScroll:SetVerticalScroll(0)
    self:Refresh()
end
