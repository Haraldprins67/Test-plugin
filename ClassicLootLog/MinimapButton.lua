-- A dependency-free minimap launcher using the Vanilla mouse/script APIs.
ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local Compat = ns.Compat
local MinimapButton = {}
MinimapButton.__index = MinimapButton
ns.MinimapButton = MinimapButton

local function settings(db)
    db.ui = type(db.ui) == "table" and db.ui or {}
    local angle = tonumber(db.ui.minimapAngle)
    if not angle or angle ~= angle or angle < -100000000 or angle > 100000000 then
        angle = 225
    end
    db.ui.minimapAngle = math.mod(angle, 360)
    return db.ui
end

local function modifiersHeld()
    return IsControlKeyDown and IsShiftKeyDown
        and IsControlKeyDown() and IsShiftKeyDown()
end

-- math.atan2 is available in Vanilla, but custom clients need not provide it.
local function angleFor(x, y)
    if x == 0 then
        if y > 0 then return 90 end
        if y < 0 then return 270 end
        return nil
    end
    local angle = math.atan(y / x) * 180 / math.pi
    if x < 0 then angle = angle + 180 end
    if angle < 0 then angle = angle + 360 end
    return angle
end

function MinimapButton.New(db, callbacks)
    if not Minimap or type(CreateFrame) ~= "function" then return nil end
    local self = setmetatable({db = db, callbacks = callbacks or {}}, MinimapButton)
    settings(db)
    local frame = CreateFrame("Button", "ClassicLootLogMinimapButton", Minimap)
    self.frame = frame
    Compat.SetSize(frame, 31, 31)
    frame:SetFrameStrata("MEDIUM")
    if frame.SetFrameLevel and Minimap.GetFrameLevel then
        frame:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    end
    frame:EnableMouse(true)
    frame:RegisterForClicks("LeftButtonUp")
    frame:RegisterForDrag("LeftButton")
    frame:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = frame:CreateTexture(nil, "BACKGROUND")
    Compat.SetSize(icon, 20, 20)
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -5)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    local border = frame:CreateTexture(nil, "OVERLAY")
    Compat.SetSize(border, 54, 54)
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    Compat.SetScript(frame, "OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        self.suppressClick = false
        if modifiersHeld() then self:BeginDrag() end
    end)
    Compat.SetScript(frame, "OnDragStart", function(_, button)
        if button == "LeftButton" and modifiersHeld() then self:BeginDrag() end
    end)
    Compat.SetScript(frame, "OnMouseUp", function(_, button)
        if button == "LeftButton" then self:StopDrag() end
    end)
    Compat.SetScript(frame, "OnDragStop", function() self:StopDrag() end)
    Compat.SetScript(frame, "OnHide", function() self:StopDrag() end)
    Compat.SetScript(frame, "OnUpdate", function()
        if not self.dragging then return end
        if not modifiersHeld() or (IsMouseButtonDown and not IsMouseButtonDown("LeftButton")) then
            self:StopDrag()
            return
        end
        self:UpdateDragPosition()
    end)
    Compat.SetScript(frame, "OnClick", function(_, button)
        if button ~= "LeftButton" then return end
        if self.suppressClick then self.suppressClick = false; return end
        if modifiersHeld() then return end
        if self.callbacks.toggle then self.callbacks.toggle() end
    end)
    Compat.SetScript(frame, "OnEnter", function()
        if not GameTooltip or self.dragging then return end
        GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
        GameTooltip:AddLine("Classic Loot Log", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click to open or close CLL.", 1, 1, 1)
        GameTooltip:AddLine("Hold Ctrl + Shift and drag with the left mouse button to move.", 1, 1, 1)
        GameTooltip:Show()
    end)
    Compat.SetScript(frame, "OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    self:RefreshPosition()
    frame:Show()
    return self
end

function MinimapButton:RefreshPosition()
    local angle = settings(self.db).minimapAngle * math.pi / 180
    local width = tonumber(Minimap:GetWidth()) or 140
    local height = tonumber(Minimap:GetHeight()) or width
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * (width / 2 + 8), math.sin(angle) * (height / 2 + 8))
end

function MinimapButton:UpdateDragPosition()
    if not GetCursorPosition then return end
    local centerX, centerY = Minimap:GetCenter()
    if not centerX or not centerY then return end
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap.GetEffectiveScale and Minimap:GetEffectiveScale() or 1
    if not scale or scale <= 0 then scale = 1 end
    local angle = angleFor(cursorX / scale - centerX, cursorY / scale - centerY)
    if angle then
        settings(self.db).minimapAngle = angle
        self:RefreshPosition()
    end
end

function MinimapButton:BeginDrag()
    self.dragging = true
    self.suppressClick = true
    if GameTooltip then GameTooltip:Hide() end
    self:UpdateDragPosition()
end

function MinimapButton:StopDrag()
    self.dragging = false
end

function MinimapButton:SetDatabase(db)
    self.db = db
    self:StopDrag()
    self:RefreshPosition()
end
