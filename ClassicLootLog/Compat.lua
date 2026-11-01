-- This file intentionally uses Lua 5.0 syntax for the OctoWoW 1.12 client.
ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local Compat = {}
ns.Compat = Compat

local getn = table.getn
local version
if GetBuildInfo then version = GetBuildInfo() end
-- Private clients can report a newer/custom build while still exposing the
-- Vanilla API. Prefer the available loot functions over that display label.
local legacyVersion = type(version) == "string" and string.find(version, "^1%.12") ~= nil
local modernLoot = type(GetLootSlotType) == "function"
local legacyLoot = not modernLoot and (type(LootSlotIsItem) == "function" or type(LootSlotIsCoin) == "function")
local missingModernAPIs = not modernLoot and type(UnitGUID) ~= "function" and type(CombatLogGetCurrentEventInfo) ~= "function"
Compat.IsLegacy = legacyVersion or legacyLoot or missingModernAPIs
Compat.ClientVersion = version or "unknown"

function Compat.Match(value, pattern)
    if type(value) ~= "string" then return nil end
    local first, last, capture = string.find(value, pattern)
    return capture
end

function Compat.UnitGUIDSafe(unit)
    if UnitGUID then
        local guid = UnitGUID(unit)
        if type(guid) == "string" and guid ~= "" then return guid end
    end
    if UnitExists then
        local exists, guid = UnitExists(unit)
        if exists and type(guid) == "string" and guid ~= "" then return guid end
    end
    return nil
end

function Compat.SetSize(widget, width, height)
    widget:SetWidth(width)
    widget:SetHeight(height)
end

-- Vanilla passes script arguments through global this/event/arg1..arg9.
-- Newer clients pass them directly. Normalize both forms without vararg
-- expressions, which are not understood by the Lua 5.0 parser.
function Compat.SetScript(widget, script, callback)
    if callback == nil then widget:SetScript(script, nil); return end
    widget:SetScript(script, function(first, a, b, c, d, e, f, g, h, i, j)
        if first == widget then
            return callback(widget, a, b, c, d, e, f, g, h, i, j)
        end
        if script == "OnEvent" then
            return callback(widget, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
        elseif script == "OnValueChanged" then
            local value = arg1
            if value == nil and widget.GetValue then value = widget:GetValue() end
            return callback(widget, value, arg2)
        end
        return callback(widget, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    end)
end

function Compat.RegisterEvent(frame, name)
    -- Some private clients reject newer events. Keep the supported events
    -- running instead of aborting addon initialization on an unknown one.
    return pcall(frame.RegisterEvent, frame, name)
end

local timerFrame
local timers = {}
function Compat.After(delay, callback)
    if type(callback) ~= "function" then return end
    delay = math.max(0, tonumber(delay) or 0)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, callback)
        return
    end
    if not timerFrame then
        timerFrame = CreateFrame("Frame")
        Compat.SetScript(timerFrame, "OnUpdate", function()
            local current = GetTime()
            local pending = timers
            timers = {}
            for index = 1, getn(pending) do
                local timer = pending[index]
                if timer.at <= current then
                    timer.callback()
                else
                    timers[getn(timers) + 1] = timer
                end
            end
            if getn(timers) == 0 then timerFrame:Hide() end
        end)
        timerFrame:Hide()
    end
    timers[getn(timers) + 1] = { at = GetTime() + delay, callback = callback }
    timerFrame:Show()
end

function Compat.GetLootSlotInfo(slot)
    local icon, name, quantity, fourth, fifth = GetLootSlotInfo(slot)
    if Compat.IsLegacy then return icon, name, quantity, fourth end
    return icon, name, quantity, fifth
end

function Compat.LootSlotType(slot)
    if GetLootSlotType then return GetLootSlotType(slot) end
    if LootSlotIsItem and LootSlotIsItem(slot) then return 1 end
    if LootSlotIsCoin and LootSlotIsCoin(slot) then return 2 end
    local link = GetLootSlotLink and GetLootSlotLink(slot)
    if link and link ~= "" then return 1 end
    local icon, name = GetLootSlotInfo(slot)
    if name and name ~= "" then return 2 end
    return 0
end

function Compat.GetLootSources(slot)
    local result = {}
    if not GetLootSourceInfo then return result end
    local raw = { GetLootSourceInfo(slot) }
    for index = 1, getn(raw), 2 do
        local guid, quantity = raw[index], raw[index + 1]
        if type(guid) == "string" and type(quantity) == "number" then
            result[getn(result) + 1] = { guid = guid, quantity = quantity }
        end
    end
    return result
end

function Compat.IsChatLinkModified()
    if IsModifiedClick then return IsModifiedClick("CHATLINK") end
    return IsShiftKeyDown and IsShiftKeyDown()
end

function Compat.InsertLink(link)
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
    if ChatFrameEditBox then
        ChatFrameEditBox:Show()
        ChatFrameEditBox:Insert(link)
        return true
    end
    return false
end

function Compat.TooltipItem(tooltip, link)
    if not tooltip or not tooltip.SetHyperlink or type(link) ~= "string" or link == "" then return false end
    local payload = Compat.Match(link, "|H(.-)|h") or link
    return pcall(tooltip.SetHyperlink, tooltip, payload)
end
