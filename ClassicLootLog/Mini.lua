-- Three session metrics in a separate Vanilla-compatible movable window.
ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local Core, Compat = ns.Core, ns.Compat
local Mini = {}
Mini.__index = Mini
ns.Mini = Mini

local function settings(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.miniVisible = db.ui.miniVisible == true
    return db.ui
end

local function metric(frame, y)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, y)
    text:SetWidth(196)
    text:SetHeight(20)
    text:SetJustifyH("LEFT")
    return text
end

function Mini.New(db, callbacks)
    local self = setmetatable({db = db, callbacks = callbacks or {}, elapsed = 0}, Mini)
    local visible = settings(db).miniVisible
    local frame = CreateFrame("Frame", "ClassicLootLogMiniFrame", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    self.frame = frame
    Compat.SetSize(frame, 238, 112)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    Compat.SetScript(frame, "OnDragStart", frame.StartMoving)
    Compat.SetScript(frame, "OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = {left = 11, right = 12, top = 12, bottom = 11},
        })
    end
    self.mobsPerHour = metric(frame, -17)
    self.timer = metric(frame, -44)
    self.kills = metric(frame, -71)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    Compat.SetScript(frame, "OnHide", function()
        settings(self.db).miniVisible = false
        frame:StopMovingOrSizing()
    end)
    Compat.SetScript(frame, "OnUpdate", function(_, elapsed)
        if not frame:IsShown() then return end
        self.elapsed = self.elapsed + math.max(0, tonumber(elapsed) or 0)
        if self.elapsed >= 0.25 then
            self.elapsed = 0
            self:Refresh()
        end
    end)
    frame:Hide()
    self:Refresh()
    if visible then self:Show() end
    return self
end

function Mini:Now()
    return self.callbacks.now and self.callbacks.now() or GetTime()
end

function Mini:Refresh()
    local stats = Core.MobStats(self.db, self:Now())
    self.mobsPerHour:SetText(string.format("Mobs/hour: %.1f", stats.perHour))
    self.timer:SetText("Time: " .. Core.FormatElapsed(stats.elapsed)
        .. (self.db.timer.enabled and "" or " (paused)"))
    self.kills:SetText("Kills: " .. tostring(stats.total))
end

function Mini:Show()
    settings(self.db).miniVisible = true
    self.elapsed = 0
    self:Refresh()
    self.frame:Show()
end

function Mini:Hide()
    settings(self.db).miniVisible = false
    self.frame:Hide()
end

function Mini:Toggle()
    if self.frame:IsShown() then self:Hide() else self:Show() end
end

function Mini:SetDatabase(db)
    local visible = settings(db).miniVisible
    self.db = db
    if visible then self:Show() else self:Hide(); self:Refresh() end
end
