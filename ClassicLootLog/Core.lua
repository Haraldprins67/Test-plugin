ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local Core = {}
ns.Core = Core

local floor, max = math.floor, math.max
local getn, mod = table.getn, math.mod

local function match(value, pattern)
    local _, _, captured = string.find(value, pattern)
    return captured
end

local function number(value, fallback)
    if type(value) == "number" and value == value and value - value == 0 then
        return value
    end
    return fallback or 0
end

local function positiveInteger(value)
    return max(0, floor(number(value, 0)))
end

local function text(value, fallback)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return fallback or ""
end

function Core.Initialize(saved, now)
    local db = type(saved) == "table" and saved or {}
    db.entries = type(db.entries) == "table" and db.entries or {}
    db.seen = type(db.seen) == "table" and db.seen or {}
    db.timer = type(db.timer) == "table" and db.timer or {}
    db.timer.enabled = db.timer.enabled == true
    db.timer.elapsed = max(0, number(db.timer.elapsed))
    -- GetTime() belongs to the current login. Never count time spent offline.
    db.timer.startedAt = db.timer.enabled and number(now) or nil
    local lastID = 0
    for _, entry in ipairs(db.entries) do
        if type(entry) == "table" then
            lastID = max(lastID, positiveInteger(entry.id))
            entry.origin = entry.origin == "disenchant" and "disenchant" or "drop"
            entry.disenchanted = math.min(positiveInteger(entry.quantity), positiveInteger(entry.disenchanted))
        end
    end
    db.nextID = max(lastID + 1, positiveInteger(db.nextID), 1)
    db.mobs = type(db.mobs) == "table" and db.mobs or {}
    db.mobs.total = positiveInteger(db.mobs.total)
    db.mobs.timed = math.min(db.mobs.total, positiveInteger(db.mobs.timed))
    db.mobs.seen = type(db.mobs.seen) == "table" and db.mobs.seen or {}
    db.mobs.kills = type(db.mobs.kills) == "table" and db.mobs.kills or {}
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.width = math.min(1280, max(680, number(db.ui.width, 900)))
    db.ui.height = math.min(900, max(430, number(db.ui.height, 590)))
    db.ui.autoText = db.ui.autoText ~= false
    db.ui.locked = db.ui.locked == true
    db.version = 2
    return db
end

function Core.TimerElapsed(db, now)
    local timer = db.timer
    local elapsed = timer.elapsed
    if timer.enabled and timer.startedAt then
        elapsed = elapsed + max(0, number(now) - timer.startedAt)
    end
    return elapsed
end

function Core.CheckpointTimer(db, now)
    db.timer.elapsed = Core.TimerElapsed(db, now)
    db.timer.startedAt = db.timer.enabled and number(now) or nil
end

function Core.SetTimerEnabled(db, enabled, now)
    Core.CheckpointTimer(db, now)
    db.timer.enabled = enabled == true
    db.timer.startedAt = db.timer.enabled and number(now) or nil
end

function Core.FormatElapsed(seconds)
    seconds = positiveInteger(seconds)
    return string.format("%02d:%02d:%02d", floor(seconds / 3600), mod(floor(seconds / 60), 60), mod(seconds, 60))
end

function Core.Reset(db, now)
    db.entries = {}
    db.seen = {}
    db.nextID = 1
    db.timer.elapsed = 0
    db.timer.startedAt = db.timer.enabled and number(now) or nil
    db.mobs = { total = 0, timed = 0, seen = {}, kills = {} }
end

function Core.RecordMobKill(db, guid, name, timestamp, clock)
    if type(guid) ~= "string" or guid == "" or db.mobs.seen[guid] then return false end
    db.mobs.seen[guid] = true
    db.mobs.total = db.mobs.total + 1
    if db.timer.enabled then db.mobs.timed = db.mobs.timed + 1 end
    db.mobs.kills[getn(db.mobs.kills) + 1] = {
        guid = guid, name = text(name, guid), timestamp = number(timestamp),
        elapsed = db.timer.enabled and Core.TimerElapsed(db, clock) or nil,
    }
    return true
end

function Core.MobStats(db, clock)
    local elapsed = Core.TimerElapsed(db, clock)
    return {
        total = db.mobs.total, timed = db.mobs.timed, elapsed = elapsed,
        perHour = elapsed > 0 and db.mobs.timed * 3600 / elapsed or 0,
    }
end

function Core.ItemKey(link, name)
    local itemID = match(text(link), "item:(%d+)")
    if itemID then return "item:" .. tostring(tonumber(itemID)) end
    return "name:" .. text(name, "Unknown item")
end

local function identity(slot)
    local kind = text(slot.kind, "item")
    if kind == "money" then
        return "money"
    end
    if kind == "item" then
        return kind .. ":" .. text(slot.link, text(slot.name, "Unknown item"))
    end
    return kind .. ":" .. text(slot.link, text(slot.name, kind))
end

local function addObservation(observed, ordered, slot, guid, quantity)
    if quantity <= 0 then
        return
    end
    -- Length-prefix the GUID so caller-provided strings cannot collide.
    -- Keep version-1 drop keys valid, while separating transformed materials.
    local origin = slot.origin == "disenchant" and "disenchant:" or ""
    local key = origin .. string.len(guid) .. ":" .. guid .. identity(slot)
    local row = observed[key]
    if not row then
        row = { key = key, slot = slot, guid = guid, quantity = 0 }
        observed[key] = row
        ordered[getn(ordered) + 1] = row
    end
    row.quantity = row.quantity + quantity
end

function Core.AddSnapshot(db, slots, timestamp, clock)
    local observed, ordered = {}, {}
    for _, slot in ipairs(slots or {}) do
        if type(slot) == "table" then
            local quantity = positiveInteger(slot.quantity)
            local allocated = 0
            for _, source in ipairs(type(slot.sources) == "table" and slot.sources or {}) do
                if type(source) == "table" and type(source.guid) == "string" and source.guid ~= "" then
                    local amount = positiveInteger(source.quantity)
                    addObservation(observed, ordered, slot, source.guid, amount)
                    allocated = allocated + amount
                end
            end
            if allocated == 0 then
                addObservation(observed, ordered, slot, text(slot.sourceGUID, "__unknown"), quantity)
            end
        end
    end

    local added = 0
    for _, observation in ipairs(ordered) do
        local previous = positiveInteger(db.seen[observation.key])
        if observation.quantity > previous then
            local slot = observation.slot
            local entry = {
                id = db.nextID,
                timestamp = number(timestamp),
                elapsed = db.timer.enabled and Core.TimerElapsed(db, clock) or nil,
                link = text(slot.link),
                name = text(slot.name, "Unknown item"),
                icon = slot.icon,
                quantity = observation.quantity - previous,
                quality = positiveInteger(slot.quality),
                kind = text(slot.kind, "item"),
                origin = slot.origin == "disenchant" and "disenchant" or "drop",
                disenchanted = 0,
                source = observation.guid,
                sourceLabel = text(slot.sourceLabel, observation.guid),
            }
            db.entries[getn(db.entries) + 1] = entry
            db.nextID = db.nextID + 1
            db.seen[observation.key] = observation.quantity
            added = added + 1
        end
    end
    return added
end

function Core.MarkDisenchanted(db, itemLink, quantity, clock, entryID)
    if type(itemLink) ~= "string" or itemLink == "" then return 0 end
    local remaining = quantity == nil and 1 or positiveInteger(quantity)
    if remaining == 0 then return 0 end
    local key, marked = Core.ItemKey(itemLink), 0
    for index = getn(db.entries), 1, -1 do
        local entry = db.entries[index]
        if type(entry) == "table" and entry.kind == "item" and entry.origin ~= "disenchant"
            and (entryID == nil or entry.id == entryID)
            and Core.ItemKey(entry.link, entry.name) == key then
            local previous = positiveInteger(entry.disenchanted)
            local available = max(0, positiveInteger(entry.quantity) - previous)
            local amount = math.min(remaining, available)
            if amount > 0 then
                entry.disenchanted = previous + amount
                entry.disenchantedElapsed = db.timer.enabled and Core.TimerElapsed(db, clock) or nil
                remaining, marked = remaining - amount, marked + amount
            end
            if remaining == 0 or entryID ~= nil then break end
        end
    end
    return marked
end

function Core.UnmarkDisenchanted(db, entryID, quantity)
    local requested = quantity == nil and 1 or positiveInteger(quantity)
    if requested == 0 or entryID == nil then return 0 end
    for index = getn(db.entries), 1, -1 do
        local entry = db.entries[index]
        if type(entry) == "table" and entry.id == entryID and entry.kind == "item" and entry.origin ~= "disenchant" then
            local removed = math.min(requested, positiveInteger(entry.disenchanted))
            entry.disenchanted = positiveInteger(entry.disenchanted) - removed
            if entry.disenchanted == 0 then entry.disenchantedElapsed = nil end
            return removed
        end
    end
    return 0
end

local function aggregateItem(rows, byKey, entry, quantity)
    local key = Core.ItemKey(entry.link, entry.name)
    local row = byKey[key]
    if not row then
        row = {
            key = key, name = text(entry.name, "Unknown item"), link = text(entry.link), icon = entry.icon,
            quantity = 0, disenchanted = 0, materials = 0, percent = 0,
        }
        byKey[key], rows[getn(rows) + 1] = row, row
    end
    row.quantity = row.quantity + quantity
    row.disenchanted = row.disenchanted + math.min(quantity, positiveInteger(entry.disenchanted))
    return row
end

function Core.ItemStats(db)
    local stats = {
        rows = {}, materialRows = {}, byKey = {}, materialByKey = {},
        totalQuantity = 0, totalMaterials = 0, totalDisenchanted = 0,
    }
    for _, entry in ipairs(db.entries) do
        if type(entry) == "table" and entry.kind == "item" then
            local quantity = positiveInteger(entry.quantity)
            if entry.origin == "disenchant" then
                aggregateItem(stats.materialRows, stats.materialByKey, entry, quantity)
                stats.totalMaterials = stats.totalMaterials + quantity
            else
                aggregateItem(stats.rows, stats.byKey, entry, quantity)
                stats.totalQuantity = stats.totalQuantity + quantity
                stats.totalDisenchanted = stats.totalDisenchanted + math.min(quantity, positiveInteger(entry.disenchanted))
            end
        end
    end
    local function sortAndPercent(rows, total)
        for _, row in ipairs(rows) do row.percent = total > 0 and row.quantity * 100 / total or 0 end
        table.sort(rows, function(a, b)
            if a.quantity ~= b.quantity then return a.quantity > b.quantity end
            return a.key < b.key
        end)
    end
    sortAndPercent(stats.rows, stats.totalQuantity)
    sortAndPercent(stats.materialRows, stats.totalMaterials)
    return stats
end

local function exportText(value)
    value = tostring(value or "")
    value = string.gsub(value, "|c%x%x%x%x%x%x%x%x", "")
    value = string.gsub(value, "|r", "")
    value = string.gsub(value, "|H.-|h(.-)|h", "%1")
    value = string.gsub(value, "\\", "\\\\")
    value = string.gsub(value, "\t", "\\t")
    value = string.gsub(value, "\r", "\\r")
    value = string.gsub(value, "\n", "\\n")
    return value
end

function Core.Export(db, timestampFormatter)
    local lines = { "ID\tDate/time\tSession time\tType\tItem\tQuantity\tQuality\tSource\tItem link\tOrigin\tDisenchanted" }
    for _, entry in ipairs(db.entries) do
        local stamp = timestampFormatter and timestampFormatter(entry.timestamp) or tostring(entry.timestamp)
        local values = {
            entry.id,
            stamp,
            entry.elapsed ~= nil and Core.FormatElapsed(entry.elapsed) or "",
            entry.kind,
            entry.name,
            entry.quantity,
            entry.quality,
            entry.sourceLabel or entry.source,
            match(text(entry.link), "|H(.-)|h") or entry.link,
            entry.origin == "disenchant" and "disenchant" or "drop",
            positiveInteger(entry.disenchanted),
        }
        for i = 1, 11 do
            values[i] = exportText(values[i])
        end
        lines[getn(lines) + 1] = table.concat(values, "\t")
    end
    return table.concat(lines, "\n")
end

function Core.ExportSummary(db, clock)
    local mobs, items = Core.MobStats(db, clock), Core.ItemStats(db)
    local lines = {
        "Statistic\tValue",
        "Total mobs\t" .. mobs.total,
        "Mobs with timer running\t" .. mobs.timed,
        "Active session time\t" .. Core.FormatElapsed(mobs.elapsed),
        "Mobs per hour\t" .. string.format("%.2f", mobs.perHour),
        "Original drop item quantity\t" .. items.totalQuantity,
        "Disenchanted original items\t" .. items.totalDisenchanted,
        "Disenchant materials\t" .. items.totalMaterials,
        "",
        "Item\tQuantity\tLoot share\tDisenchanted\tItem ID",
    }
    for _, row in ipairs(items.rows) do
        lines[getn(lines) + 1] = table.concat({exportText(row.name), row.quantity,
            string.format("%.2f%%", row.percent), row.disenchanted, exportText(row.key)}, "\t")
    end
    lines[getn(lines) + 1] = ""
    lines[getn(lines) + 1] = "Disenchant material\tQuantity\tMaterial share\tItem ID"
    for _, row in ipairs(items.materialRows) do
        lines[getn(lines) + 1] = table.concat({exportText(row.name), row.quantity,
            string.format("%.2f%%", row.percent), exportText(row.key)}, "\t")
    end
    return table.concat(lines, "\n")
end
