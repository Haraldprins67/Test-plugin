-- Observed party/raid loot data. Deliberately compatible with Lua 5.0.
ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local GroupLoot = {}
GroupLoot.__index = GroupLoot
ns.GroupLoot = GroupLoot

local getn, floor = table.getn, math.floor

local function finite(value)
    return type(value) == "number" and value == value and value - value == 0
end

local function text(value, fallback)
    return type(value) == "string" and value ~= "" and value or (fallback or "")
end

local function trim(value)
    value = type(value) == "string" and value or ""
    value = string.gsub(value, "^%s+", "")
    return (string.gsub(value, "%s+$", ""))
end

local function capture(value, pattern)
    local first, last, result = string.find(value, pattern)
    return result
end

local function playerKey(player)
    return string.lower(trim(player))
end

function GroupLoot.ItemKey(link)
    link = text(link)
    local id = capture(link, "item:(%d+)")
    if id then return "item:" .. tostring(tonumber(id)) end
    return "name:" .. string.lower(trim(link))
end

local function itemName(link)
    return capture(link, "|h%[(.-)%]|h") or capture(link, "%[(.-)%]") or link
end

local function methodName(method)
    method = string.lower(text(method, "unknown"))
    if method == "group" or method == "needbeforegreed" or method == "group loot" then return "group" end
    if method == "master" or method == "master loot" then return "master" end
    if method == "epgp" or method == "ep/gp" then return "epgp" end
    return "unknown"
end

function GroupLoot.Initialize(db)
    db.groupLoot = type(db.groupLoot) == "table" and db.groupLoot or {}
    local data = db.groupLoot
    data.entries = type(data.entries) == "table" and data.entries or {}
    data.unassigned = type(data.unassigned) == "table" and data.unassigned or {}
    local lastID = 0
    for _, entry in ipairs(data.entries) do
        if type(entry) == "table" then
            if finite(entry.id) then lastID = math.max(lastID, floor(entry.id)) end
            entry.choices = type(entry.choices) == "table" and entry.choices or {}
            entry.choiceOrder = type(entry.choiceOrder) == "table" and entry.choiceOrder or {}
            entry.rolls = type(entry.rolls) == "table" and entry.rolls or {}
            entry.rollHistory = type(entry.rollHistory) == "table" and entry.rollHistory or {}
            entry.bids = type(entry.bids) == "table" and entry.bids or {}
            entry.bidOrder = type(entry.bidOrder) == "table" and entry.bidOrder or {}
            entry.itemKey = entry.itemKey or GroupLoot.ItemKey(entry.link)
        end
    end
    data.nextID = finite(data.nextID) and math.max(lastID + 1, floor(data.nextID), 1) or lastID + 1
    return data
end

function GroupLoot.New(db, callbacks)
    assert(type(db) == "table", "GroupLoot requires a saved database")
    local data = GroupLoot.Initialize(db)
    -- An unresolved roll from a previous login must not claim a later item.
    for _, entry in ipairs(data.entries) do
        if type(entry) == "table" and entry.state == "open" then
            entry.state = "unassigned"
            entry.closeReason = "session_restored"
        end
    end
    return setmetatable({db = db, callbacks = callbacks or {}, activeID = nil}, GroupLoot)
end

function GroupLoot:Now()
    local value = self.callbacks.now and self.callbacks.now() or 0
    return finite(value) and value or 0
end

function GroupLoot:Timestamp()
    local value = self.callbacks.time and self.callbacks.time() or self:Now()
    return finite(value) and value or 0
end

function GroupLoot:Data()
    return GroupLoot.Initialize(self.db)
end

function GroupLoot:Entries()
    return self:Data().entries
end

function GroupLoot:GetUnassigned()
    return self:Data().unassigned
end

function GroupLoot:Get(context)
    local id = type(context) == "table" and context.id or context
    for _, entry in ipairs(self:Entries()) do
        if entry.id == id then return entry end
    end
    return nil
end

function GroupLoot:StartItem(link, method, options)
    if type(link) ~= "string" or link == "" then return nil, "invalid_item" end
    options = type(options) == "table" and options or {}
    local data = self:Data()
    local key = GroupLoot.ItemKey(link)
    if options.rollID ~= nil then
        for _, entry in ipairs(data.entries) do
            if entry.state == "open" and entry.rollID ~= nil and tostring(entry.rollID) == tostring(options.rollID) then
                if entry.itemKey ~= key then return nil, "roll_id_conflict" end
                return entry, true
            end
        end
    end
    local normalized = methodName(method)
    local distribution = options.distributionMethod and methodName(options.distributionMethod) or normalized
    if distribution == "epgp" then distribution = "master" end
    local entry = {
        id = data.nextID, link = link, itemKey = key,
        name = text(options.name, itemName(link)), method = normalized,
        distributionMethod = distribution, sourceMethod = text(method, "unknown"),
        quantity = finite(options.quantity) and math.max(1, floor(options.quantity)) or 1,
        rollID = options.rollID,
        startedAt = finite(options.startedAt) and options.startedAt
            or (finite(options.timestamp) and options.timestamp or self:Timestamp()),
        state = "open", choices = {}, choiceOrder = {}, rolls = {}, rollHistory = {},
        bids = {}, bidOrder = {},
    }
    data.nextID = data.nextID + 1
    data.entries[getn(data.entries) + 1] = entry
    if options.select then self.activeID = entry.id end
    return entry, false
end

function GroupLoot:Select(context)
    local entry = self:Get(context)
    if not entry or entry.state ~= "open" then return false end
    self.activeID = entry.id
    return true
end

function GroupLoot:GetActive()
    local entry = self:Get(self.activeID)
    if entry and entry.state == "open" then return entry end
    return nil
end

function GroupLoot:ResolveContext(link, rollID)
    local key = type(link) == "string" and link ~= "" and GroupLoot.ItemKey(link) or nil
    local found
    for _, entry in ipairs(self:Entries()) do
        if entry.state == "open" and (not key or entry.itemKey == key)
            and (rollID == nil or (entry.rollID ~= nil and tostring(entry.rollID) == tostring(rollID))) then
            if found then return nil, "ambiguous" end
            found = entry
        end
    end
    if found then return found end
    return nil, "not_found"
end

local function choiceName(choice)
    choice = string.upper(trim(choice))
    if choice == "NEED" or choice == "GREED" or choice == "PASS" then return choice end
    return nil
end

function GroupLoot:SetChoice(context, player, choice)
    local entry, key, normalized = self:Get(context), playerKey(player), choiceName(choice)
    if not entry or entry.state ~= "open" then return false, "closed_context" end
    if key == "" or not normalized then return false, "invalid_choice" end
    local previous = entry.choices[key]
    if previous and previous.choice == normalized then return false, "duplicate" end
    if not previous then entry.choiceOrder[getn(entry.choiceOrder) + 1] = key end
    entry.choices[key] = {player = trim(player), choice = normalized, time = self:Timestamp()}
    for _, roll in ipairs(entry.rolls) do
        if roll.key == key then roll.choice = normalized end
    end
    return true
end

function GroupLoot:AddRoll(context, player, value, minimum, maximum, choice)
    local entry, key = self:Get(context), playerKey(player)
    if not entry or entry.state ~= "open" then return false, "closed_context" end
    minimum, maximum = minimum or 1, maximum or 100
    if key == "" or not finite(value) or not finite(minimum) or not finite(maximum)
        or value ~= floor(value) or minimum ~= floor(minimum) or maximum ~= floor(maximum)
        or minimum > maximum or value < minimum or value > maximum then
        return false, "invalid_roll"
    end
    local normalized = choiceName(choice)
    if normalized then self:SetChoice(entry, player, normalized) end
    normalized = normalized or (entry.choices[key] and entry.choices[key].choice) or "ROLL"
    local row = {player = trim(player), key = key, value = value, min = minimum,
        max = maximum, choice = normalized, time = self:Timestamp()}
    local history = {}
    for field, observed in pairs(row) do history[field] = observed end
    for index, previous in ipairs(entry.rolls) do
        if previous.key == key and previous.min == minimum and previous.max == maximum then
            if previous.value == value and previous.choice == normalized then return false, "duplicate" end
            entry.rolls[index] = row
            entry.rollHistory[getn(entry.rollHistory) + 1] = history
            return true
        end
    end
    entry.rolls[getn(entry.rolls) + 1] = row
    entry.rollHistory[getn(entry.rollHistory) + 1] = history
    return true
end

-- Normalize only a complete bid token, optionally accompanied by an item link.
-- Broad substring matching would turn normal conversation into EPGP bids.
function GroupLoot.NormalizeBid(message)
    if type(message) ~= "string" then return nil end
    local value = string.gsub(message, "|c%x%x%x%x%x%x%x%x", "")
    value = string.gsub(value, "|r", "")
    value = string.gsub(value, "|H.-|h.-|h", "")
    value = string.lower(value)
    local accents = {
        ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
        ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
        ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
        ["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i",
        ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ä"] = "a",
        ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a",
    }
    for character, replacement in pairs(accents) do value = string.gsub(value, character, replacement) end
    value = string.gsub(value, "3", "e")
    value = string.gsub(value, "1", "i")
    value = string.gsub(value, "4", "a")
    value = string.gsub(value, "[%s%p]", "")
    if value == "min" or value == "minimum" or value == "minimal" or value == "minbid" or value == "bidmin"
        or string.find(value, "^m+i+n+$") then return "MIN" end
    if value == "need" or value == "needbid" or value == "bidneed"
        or string.find(value, "^n+e+d+$") then return "NEED" end
    if value == "max" or value == "maximum" or value == "maximal" or value == "maxbid" or value == "bidmax"
        or string.find(value, "^m+a+x+$") then return "MAX" end
    return nil
end

function GroupLoot:AddBid(context, player, message)
    local entry, key = self:Get(context), playerKey(player)
    if not entry or entry.state ~= "open" then return false, "closed_context" end
    if entry.distributionMethod == "group" then return false, "group_roll_context" end
    local kind = GroupLoot.NormalizeBid(message)
    if key == "" or not kind then return false, "invalid_bid" end
    local previous = entry.bids[key]
    if previous and previous.kind == kind and previous.raw == message then return false, "duplicate" end
    if not previous then entry.bidOrder[getn(entry.bidOrder) + 1] = key end
    entry.bids[key] = {player = trim(player), kind = kind, raw = message, time = self:Timestamp()}
    entry.method = "epgp"
    return true
end

local function priority(entry, roll)
    if entry.distributionMethod ~= "group" then return 1 end
    local choice = entry.choices[roll.key] and entry.choices[roll.key].choice or roll.choice
    if choice == "NEED" then return 3 end
    if choice == "GREED" then return 2 end
    if choice == "PASS" then return 0 end
    return 1
end

local function rankedGroup(entry, rows, minimum, maximum)
    table.sort(rows, function(a, b)
        local ap, bp = priority(entry, a), priority(entry, b)
        if ap ~= bp then return ap > bp end
        if a.value ~= b.value then return a.value > b.value end
        return a.key < b.key
    end)
    local group = {min = minimum, max = maximum, rows = rows, highest = rows[1], second = rows[2], ties = {}, tiePlayers = {}}
    for _, row in ipairs(rows) do
        if group.highest and priority(entry, row) == priority(entry, group.highest) and row.value == group.highest.value then
            group.ties[getn(group.ties) + 1] = row
            group.tiePlayers[getn(group.tiePlayers) + 1] = row.player
        end
    end
    group.tied = getn(group.ties) > 1
    return group
end

function GroupLoot:Rankings(context, options)
    local entry = self:Get(context)
    if not entry then return {ties = {}, tiePlayers = {}, rangeGroups = {}, tied = false} end
    options = type(options) == "table" and options or {}
    local byRange, groups = {}, {}
    local uncertain = false
    for _, roll in ipairs(entry.rolls) do
        if priority(entry, roll) > 0 then
            local key = tostring(roll.min) .. ":" .. tostring(roll.max)
            local group = byRange[key]
            if not group then
                group = {min = roll.min, max = roll.max, rows = {}}
                byRange[key], groups[getn(groups) + 1] = group, group
            end
            group.rows[getn(group.rows) + 1] = roll
            if entry.distributionMethod == "group" and priority(entry, roll) == 1 then uncertain = true end
        end
    end
    table.sort(groups, function(a, b)
        if a.min ~= b.min then return a.min < b.min end
        return a.max < b.max
    end)
    local result = {min = options.min or 1, max = options.max or 100,
        rangeGroups = {}, ties = {}, tiePlayers = {}, tied = false, uncertain = uncertain}
    for _, range in ipairs(groups) do
        local group = rankedGroup(entry, range.rows, range.min, range.max)
        result.rangeGroups[getn(result.rangeGroups) + 1] = group
        if group.min == result.min and group.max == result.max then
            result.highest, result.second = group.highest, group.second
            result.tied, result.ties, result.tiePlayers = group.tied, group.ties, group.tiePlayers
        end
    end
    -- A single custom /roll range has a meaningful top two. Only fall back
    -- when no range was explicitly requested; unlike ranges stay separate.
    if not result.highest and options.min == nil and options.max == nil and getn(result.rangeGroups) == 1 then
        local group = result.rangeGroups[1]
        result.min, result.max = group.min, group.max
        result.highest, result.second = group.highest, group.second
        result.tied, result.ties, result.tiePlayers = group.tied, group.ties, group.tiePlayers
    end
    result.mixedRanges = getn(groups) > 1
    return result
end

function GroupLoot:RecordObservedWinner(context, player, choice, value)
    local entry = self:Get(context)
    if not entry or entry.state ~= "open" or playerKey(player) == "" then return false end
    entry.observedWinner = trim(player)
    entry.observedWinnerChoice = choiceName(choice)
    entry.observedWinnerRoll = finite(value) and value or nil
    return true
end

function GroupLoot:RecordUnassigned(link, recipient, reason, options)
    options = type(options) == "table" and options or {}
    local data = self:Data()
    data.unassigned[getn(data.unassigned) + 1] = {
        link = text(link), itemKey = GroupLoot.ItemKey(link), recipient = trim(recipient),
        reason = reason, timestamp = finite(options.timestamp) and options.timestamp or self:Timestamp(),
        contextID = options.contextID, rollID = options.rollID, source = options.source,
    }
end

function GroupLoot:Award(link, recipient, options)
    options = type(options) == "table" and options or {}
    local key = playerKey(recipient)
    if key == "" then return nil, "invalid_recipient" end
    local entry, reason
    if options.contextID ~= nil then
        entry = self:Get(options.contextID)
        if not entry then reason = "not_found" end
    elseif options.rollID ~= nil then
        entry, reason = self:ResolveContext(link, options.rollID)
        if not entry and reason == "not_found" then
            for _, candidate in ipairs(self:Entries()) do
                if candidate.state == "awarded" and candidate.rollID ~= nil
                    and tostring(candidate.rollID) == tostring(options.rollID)
                    and candidate.itemKey == GroupLoot.ItemKey(link) then
                    if entry then entry, reason = nil, "ambiguous"; break end
                    entry = candidate
                end
            end
        end
    else
        entry, reason = self:ResolveContext(link)
    end
    if entry and entry.itemKey ~= GroupLoot.ItemKey(link) then entry, reason = nil, "item_mismatch" end
    if entry and entry.state == "awarded" then
        if playerKey(entry.recipient) == key then return entry, "duplicate" end
        entry, reason = nil, "already_awarded"
    elseif entry and entry.state ~= "open" then
        entry, reason = nil, "closed_context"
    end
    if not entry then
        reason = reason or "not_found"
        self:RecordUnassigned(link, recipient, reason, options)
        return nil, reason
    end
    entry.recipient, entry.winner = trim(recipient), trim(recipient)
    local bid = entry.bids[key]
    entry.winnerBid = bid and bid.kind or nil
    entry.winnerBidRaw = bid and bid.raw or nil
    entry.awardedAt = finite(options.timestamp) and options.timestamp or self:Timestamp()
    entry.state = "awarded"
    if self.activeID == entry.id then self.activeID = nil end
    return entry
end

function GroupLoot:Close(context, reason)
    local entry = self:Get(context)
    if not entry or entry.state ~= "open" then return false end
    entry.state, entry.closeReason = "unassigned", reason or "closed"
    if self.activeID == entry.id then self.activeID = nil end
    return true
end

function GroupLoot:Reset()
    self.db.groupLoot = {entries = {}, unassigned = {}, nextID = 1}
    self.activeID = nil
end

local function exportText(value)
    value = tostring(value or "")
    value = string.gsub(value, "|c%x%x%x%x%x%x%x%x", "")
    value = string.gsub(value, "|r", "")
    value = string.gsub(value, "|H.-|h(.-)|h", "%1")
    value = string.gsub(value, "\\", "\\\\")
    value = string.gsub(value, "\t", "\\t")
    value = string.gsub(value, "\r", "\\r")
    return (string.gsub(value, "\n", "\\n"))
end

local function exportLine(values)
    for index = 1, getn(values) do values[index] = exportText(values[index]) end
    return table.concat(values, "\t")
end

function GroupLoot:Export()
    local lines = {"ID\tItem\tItem ID\tLoot method\tDistribution method\tState\tRecipient\tWinning bid\tObserved winner\tHighest roller\tHighest roll\tHighest choice\tSecond roller\tSecond roll\tSecond choice\tTied highest\tRange"}
    for _, entry in ipairs(self:Entries()) do
        local ranks = self:Rankings(entry)
        local highest, second = ranks.highest or {}, ranks.second or {}
        lines[getn(lines) + 1] = exportLine({entry.id, entry.name, entry.itemKey,
            entry.method, entry.distributionMethod, entry.state, entry.recipient or "", entry.winnerBid or "",
            entry.observedWinner or "", highest.player or "", highest.value or "", highest.choice or "",
            second.player or "", second.value or "", second.choice or "", table.concat(ranks.tiePlayers, ", "),
            tostring(ranks.min) .. "-" .. tostring(ranks.max)})
    end
    lines[getn(lines) + 1] = ""
    lines[getn(lines) + 1] = "Entry ID\tPlayer\tRecord\tChoice/Bid\tRoll\tMin\tMax\tRaw"
    for _, entry in ipairs(self:Entries()) do
        for _, key in ipairs(entry.choiceOrder) do
            local choice = entry.choices[key]
            if choice then lines[getn(lines) + 1] = exportLine({entry.id, choice.player, "choice", choice.choice, "", "", "", ""}) end
        end
        for _, roll in ipairs(entry.rolls) do
            lines[getn(lines) + 1] = exportLine({entry.id, roll.player, "roll", roll.choice,
                roll.value, roll.min, roll.max, ""})
        end
        for _, key in ipairs(entry.bidOrder) do
            local bid = entry.bids[key]
            if bid then lines[getn(lines) + 1] = exportLine({entry.id, bid.player, "bid", bid.kind, "", "", "", bid.raw}) end
        end
    end
    lines[getn(lines) + 1] = ""
    lines[getn(lines) + 1] = "Unassigned item\tRecipient\tReason\tTimestamp"
    for _, receipt in ipairs(self:GetUnassigned()) do
        lines[getn(lines) + 1] = exportLine({receipt.link, receipt.recipient, receipt.reason, receipt.timestamp})
    end
    return table.concat(lines, "\n")
end
