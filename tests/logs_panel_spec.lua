-- Archive reading/copying using the Vanilla global callback convention.
local Widget = {}
Widget.__index = Widget
local scrollNames = {}

local function fire(control, script, a)
    local oldThis, oldArg1 = this, arg1
    this, arg1 = control, a
    if control.scripts[script] then control.scripts[script]() end
    this, arg1 = oldThis, oldArg1
end

function Widget:SetWidth(value) self.width = value end
function Widget:SetHeight(value) self.height = value end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:SetPoint(point, relative, relativePoint, x, y) self.anchor = {point, relative, relativePoint, x, y} end
function Widget:ClearAllPoints() self.anchor = nil end
function Widget:GetParent() return self.parent end
function Widget:SetJustifyH() end
function Widget:GetFont() return self.path, self.size, self.flags end
function Widget:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
function Widget:SetFontObject() end
function Widget:SetMultiLine() end
function Widget:SetAutoFocus() end
function Widget:SetMaxLetters() end
function Widget:SetScript(script, callback) self.scripts[script] = callback end
function Widget:SetText(text) self.text = text; fire(self, "OnTextChanged") end
function Widget:GetText() return self.text end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false; fire(self, "OnHide") end
function Widget:Enable() self.enabled = true end
function Widget:Disable() self.enabled = false end
function Widget:SetFocus() self.focus = true end
function Widget:ClearFocus() self.focus = false end
function Widget:HighlightText() self.highlighted = true end
function Widget:EnableMouseWheel(value) self.mouseWheel = value end
function Widget:SetScrollChild(child) self.child = child end
function Widget:UpdateScrollChildRect() self.updated = true end
function Widget:GetVerticalScroll() return self.offset or 0 end
function Widget:GetVerticalScrollRange() return math.max(0, self.child.height - self.height) end
function Widget:SetVerticalScroll(value) self.offset = value end
function Widget:CreateFontString()
    return CreateFrame("FontString", nil, self)
end
function Widget:GetFontString()
    if not self.fontString then self.fontString = self:CreateFontString() end
    return self.fontString
end

function CreateFrame(kind, name, parent, template)
    if template == "UIPanelScrollFrameTemplate" then
        assert(type(name) == "string" and name ~= "", "Vanilla scrollframes must be named")
        assert(not scrollNames[name], "Native scrollframe name reused")
        scrollNames[name] = true
    end
    return setmetatable({kind = kind, name = name, parent = parent, template = template,
        width = 900, height = 590, text = "", scripts = {}, shown = true,
        path = "Fonts\\FRIZQT__.TTF", size = 12, flags = ""}, Widget)
end
function GetBuildInfo() return "1.12.1" end
function date(pattern, stamp) return os.date(pattern, stamp) end
ChatFontNormal = {}
ClassicLootLogNS = {}
dofile("ClassicLootLog/Compat.lua")
dofile("ClassicLootLog/SavedLogs.lua")
dofile("ClassicLootLog/LogsPanel.lua")
local SavedLogs, LogsPanel = ClassicLootLogNS.SavedLogs, ClassicLootLogNS.LogsPanel

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.00001, "unexpected font size")
end
local passed = 0
local function test(name, callback)
    callback()
    passed = passed + 1
    print("PASS " .. name)
end
local function save(db, text, stamp)
    return SavedLogs.Save(db, text, {timestamp = stamp or 1700000000, player = "Testplayer", realm = "Testrealm"})
end

test("empty archive shows guidance and cannot select nonexistent text", function()
    local panel = LogsPanel.New(CreateFrame("Frame"), {})
    equal(panel.selectedID, nil)
    equal(panel.edit:GetText(), "")
    equal(panel.empty.shown, true)
    equal(panel.selectAllButton.enabled, false)
    equal(panel.archiveHeader:GetText(), "Saved logs (0)")
    fire(panel.selectAllButton, "OnClick", "LeftButton")
    equal(panel.edit.focus, nil)
end)

test("newest report opens first and older reports can be selected exactly", function()
    local db = {}
    local old = save(db, "Old report\tQty\nEssence\t3\n", 1700000000)
    local recent = save(db, "New report\nWinner\tPlayer\n", 1700000001)
    local panel = LogsPanel.New(CreateFrame("Frame"), db)
    equal(panel.selectedID, recent.id)
    equal(panel.rows[1].entry.id, recent.id)
    equal(panel.rows[2].entry.id, old.id)
    equal(panel.edit:GetText(), recent.text)
    fire(panel.rows[2], "OnClick", "LeftButton")
    equal(panel.selectedID, old.id)
    equal(panel.edit:GetText(), old.text)
    equal(panel.reportHeader:GetText(), old.title)
    equal(panel.empty.shown, false)
end)

test("review text supports copying while attempted edits leave snapshot intact", function()
    local db = {}
    local entry = save(db, "|cffa335eeEpic|r\t2\nUTF-8: \195\169\n")
    local panel = LogsPanel.New(CreateFrame("Frame"), db)
    fire(panel.selectAllButton, "OnClick", "LeftButton")
    equal(panel.edit.focus, true)
    equal(panel.edit.highlighted, true)
    panel.edit:SetText("accidentally typed text")
    equal(panel.edit:GetText(), entry.text)
    equal(SavedLogs.Get(db, entry.id).text, entry.text)
    fire(panel.edit, "OnEscapePressed")
    equal(panel.edit.focus, false)
end)

test("live refresh preserves selected report, text selection and reading position", function()
    local db = {}
    local old = save(db, string.rep("Loot line\n", 80))
    local panel = LogsPanel.New(CreateFrame("Frame"), db)
    panel.reportScroll:SetVerticalScroll(200)
    fire(panel.selectAllButton, "OnClick")
    save(db, "A newer snapshot")
    panel:Refresh()
    equal(panel.selectedID, old.id)
    equal(panel.reportScroll:GetVerticalScroll(), 200)
    equal(panel.edit.focus, true)
    equal(panel.edit.highlighted, true)
    panel:Layout(680, 430, 0.8)
    equal(panel.selectedID, old.id)
    equal(panel.reportScroll:GetVerticalScroll(), 200)
    equal(panel.edit.focus, true)
end)

test("all saved logs remain reachable in a scrolling list at minimum size", function()
    local db = {}
    local oldest
    for index = 1, 60 do oldest = oldest or save(db, "Oldest"); if index > 1 then save(db, "Report " .. index) end end
    local panel = LogsPanel.New(CreateFrame("Frame"), db)
    panel:Layout(680, 430, 0.8)
    equal(table.getn(panel.rows), 60)
    assert(panel.listChild:GetHeight() > panel.listScroll:GetHeight())
    fire(panel.listScroll, "OnMouseWheel", -1000)
    equal(panel.listScroll:GetVerticalScroll(), panel.listScroll:GetVerticalScrollRange())
    fire(panel.rows[60], "OnClick", "LeftButton")
    equal(panel.selectedID, oldest.id)
    equal(panel.edit:GetText(), "Oldest")
    fire(panel.listScroll, "OnMouseWheel", 1000)
    equal(panel.listScroll:GetVerticalScroll(), 0)
end)

test("reader scales fonts and gives long wrapped reports a scrollable extent", function()
    local db = {}
    save(db, string.rep("Very long loot report line with quantities and recipients ", 150))
    local panel = LogsPanel.New(CreateFrame("Frame"), db)
    panel:Layout(680, 430, 0.8)
    local narrowHeight = panel.edit:GetHeight()
    near(panel.edit.size, 9.6)
    near(panel.rows[1].text.size, 9.6)
    assert(narrowHeight > panel.reportScroll:GetHeight())
    assert(panel.reportScroll.anchor[4] + panel.reportScroll:GetWidth() < 680)
    panel:Layout(1280, 900, 0.8)
    assert(panel.edit:GetHeight() < narrowHeight)
    panel:Layout(1280, 900, 1.3)
    near(panel.edit.size, 15.6)
    near(panel.rows[1].text.size, 15.6)
end)

test("save button uses addon callback without any external program", function()
    local db, saves = {}, 0
    local panel
    panel = LogsPanel.New(CreateFrame("Frame"), db, {save = function()
        saves = saves + 1
        local entry = save(db, "Snapshot " .. saves)
        panel:Refresh(entry.id)
    end})
    fire(panel.saveButton, "OnClick", "LeftButton")
    equal(saves, 1)
    equal(panel.edit:GetText(), "Snapshot 1")
    equal(table.getn(SavedLogs.Entries(db)), 1)
end)

test("database replacement clears selection without exposing another character's report", function()
    local first = {}
    save(first, "First character")
    local panel = LogsPanel.New(CreateFrame("Frame"), first)
    panel.listScroll:SetVerticalScroll(100)
    panel:SetDatabase({})
    equal(panel.selectedID, nil)
    equal(panel.edit:GetText(), "")
    equal(panel.rows[1].shown, false)
    equal(panel.listScroll:GetVerticalScroll(), 0)
    equal(SavedLogs.Entries(first)[1].text, "First character")
end)

print(string.format("%d saved logs panel tests passed", passed))
