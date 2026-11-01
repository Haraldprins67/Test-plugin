-- Character-local report snapshots, stored by WoW with the addon's SavedVariables.
-- This module does not write files or require a patched client. Lua 5.0 compatible.
ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local SavedLogs = {}
ns.SavedLogs = SavedLogs

local getn, floor = table.getn, math.floor
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local values = {}
for index = 1, string.len(alphabet) do
    values[string.sub(alphabet, index, index)] = index - 1
end

local function finite(value)
    return type(value) == "number" and value == value and value - value == 0
end

local function positiveID(value)
    return finite(value) and value >= 1 and value == floor(value)
end

local function stringValue(value, fallback)
    return type(value) == "string" and value ~= "" and value or fallback
end

local function now()
    if type(time) == "function" then return time() end
    if os and type(os.time) == "function" then return os.time() end
    return 0
end

local function playerName(options)
    if stringValue(options.player) then return options.player end
    if type(UnitName) == "function" then return UnitName("player") or "Unknown" end
    return "Unknown"
end

local function titleFor(options)
    if ns.FileExport and type(ns.FileExport.FileName) == "function" then
        local filename = ns.FileExport.FileName(options)
        return (string.gsub(filename, "%.txt$", ""))
    end
    local formatter = options.dateFormatter or date or (os and os.date)
    local stamp = tostring(options.timestamp)
    if type(formatter) == "function" then
        local ok, formatted = pcall(formatter, "%Y-%m-%d_%H-%M-%S", options.timestamp)
        if ok and type(formatted) == "string" then stamp = formatted end
    end
    return stamp .. "_" .. options.player
end

-- Strict decoding avoids turning damaged or unrelated SavedVariables into logs.
-- Invalid legacy exports stay in pendingFileExports so their bytes are preserved.
local function decode(payload)
    if type(payload) ~= "string" or string.sub(payload, 1, 11) ~= "CLLEXPORT1:" then return nil end
    local encoded = string.sub(payload, 12)
    local length = string.len(encoded)
    if length == 0 or math.mod(length, 4) ~= 0 then return nil end
    local result = {}
    for index = 1, length, 4 do
        local first = values[string.sub(encoded, index, index)]
        local second = values[string.sub(encoded, index + 1, index + 1)]
        local thirdChar = string.sub(encoded, index + 2, index + 2)
        local fourthChar = string.sub(encoded, index + 3, index + 3)
        local third, fourth = values[thirdChar], values[fourthChar]
        local last = index + 3 == length
        if first == nil or second == nil then return nil end
        if thirdChar == "=" then
            if not last or fourthChar ~= "=" or math.mod(second, 16) ~= 0 then return nil end
        elseif third == nil then return nil end
        if fourthChar == "=" then
            if not last or (third ~= nil and math.mod(third, 4) ~= 0) then return nil end
        elseif fourth == nil or third == nil then return nil end
        local combined = first * 262144 + second * 4096 + (third or 0) * 64 + (fourth or 0)
        local chunk = string.char(floor(combined / 65536))
        if third ~= nil then chunk = chunk .. string.char(math.mod(floor(combined / 256), 256)) end
        if fourth ~= nil then chunk = chunk .. string.char(math.mod(combined, 256)) end
        result[getn(result) + 1] = chunk
    end
    return table.concat(result)
end

local function append(archive, report, options, title)
    local entry = {
        id = archive.nextID, title = title or titleFor(options), text = report,
        timestamp = options.timestamp, player = options.player, realm = options.realm,
    }
    archive.nextID = archive.nextID + 1
    archive.entries[getn(archive.entries) + 1] = entry
    return entry
end

local function legacyOptions(filename, report)
    local _, _, year, month, day, hour, minute, second, name = string.find(filename,
        "^(%d%d%d%d)%-(%d%d)%-(%d%d)_(%d%d)%-(%d%d)%-(%d%d)_(.+)%.txt$")
    local _, _, loggedBy = string.find(report, "\nLogged by\t([^\n\r]+)")
    local stamp = 0
    local converter = type(time) == "function" and time or (os and os.time)
    if year and type(converter) == "function" then
        local ok, value = pcall(converter, {year = tonumber(year), month = tonumber(month),
            day = tonumber(day), hour = tonumber(hour), min = tonumber(minute), sec = tonumber(second)})
        if ok and finite(value) then stamp = value end
    end
    return {timestamp = stamp, player = loggedBy or name or "Unknown", realm = ""}
end

local function migrate(db, archive)
    if type(db.pendingFileExports) ~= "table" then return end
    local remaining = {}
    for _, payload in ipairs(db.pendingFileExports) do
        local decoded = decode(payload)
        local separator = decoded and string.find(decoded, "\n", 1, true)
        local filename = separator and string.sub(decoded, 1, separator - 1)
        local report = separator and string.sub(decoded, separator + 1)
        if filename and filename ~= "" and report and report ~= "" then
            local exists = false
            for _, entry in ipairs(archive.entries) do
                if type(entry) == "table" and entry.legacyFilename == filename and entry.text == report then
                    exists = true
                    break
                end
            end
            if not exists then
                local title = string.gsub(filename, "%.txt$", "")
                local entry = append(archive, report, legacyOptions(filename, report), title)
                entry.legacyFilename = filename
            end
        else
            remaining[getn(remaining) + 1] = payload
        end
    end
    db.pendingFileExports = getn(remaining) > 0 and remaining or nil
end

function SavedLogs.Initialize(db)
    if type(db) ~= "table" then return nil, "invalid_database" end
    local archive = type(db.savedLogs) == "table" and db.savedLogs or {}
    db.savedLogs = archive
    archive.entries = type(archive.entries) == "table" and archive.entries or {}
    local used, largest = {}, 0
    for _, entry in ipairs(archive.entries) do
        if type(entry) == "table" and positiveID(entry.id) then largest = math.max(largest, entry.id) end
    end
    local nextID = positiveID(archive.nextID) and archive.nextID or 1
    nextID = math.max(nextID, largest + 1)
    for _, entry in ipairs(archive.entries) do
        if type(entry) == "table" and type(entry.text) == "string" then
            if not positiveID(entry.id) or used[entry.id] then entry.id = nextID; nextID = nextID + 1 end
            used[entry.id] = true
            entry.timestamp = finite(entry.timestamp) and entry.timestamp or 0
            entry.player = stringValue(entry.player, "Unknown")
            entry.realm = type(entry.realm) == "string" and entry.realm or ""
            entry.title = stringValue(entry.title, "Saved log " .. entry.id)
        end
    end
    archive.nextID, archive.version = nextID, 1
    migrate(db, archive)
    return archive
end

function SavedLogs.Save(db, report, options)
    if type(report) ~= "string" or report == "" then return nil, "invalid_report" end
    local archive, reason = SavedLogs.Initialize(db)
    if not archive then return nil, reason end
    options = type(options) == "table" and options or {}
    local realm = stringValue(options.realm)
    if not realm and type(GetRealmName) == "function" then realm = GetRealmName() end
    local metadata = {timestamp = finite(options.timestamp) and options.timestamp or now(),
        player = playerName(options), realm = realm or "", dateFormatter = options.dateFormatter}
    local title = titleFor(metadata)
    -- Multiple snapshots in the same second remain distinguishable in the tab.
    local sequence, titles = 1, {}
    for _, entry in ipairs(archive.entries) do
        if type(entry) == "table" and type(entry.title) == "string" then titles[entry.title] = true end
    end
    local candidate = title
    while titles[candidate] do
        sequence = sequence + 1
        candidate = title .. "-" .. string.format("%02d", sequence)
    end
    return append(archive, report, metadata, candidate)
end

function SavedLogs.Entries(db)
    local archive = SavedLogs.Initialize(db)
    local result = {}
    if not archive then return result end
    for _, entry in ipairs(archive.entries) do
        if type(entry) == "table" and type(entry.text) == "string" then result[getn(result) + 1] = entry end
    end
    table.sort(result, function(a, b) return a.id > b.id end)
    return result
end

function SavedLogs.Get(db, id)
    local archive = SavedLogs.Initialize(db)
    if not archive then return nil end
    for _, entry in ipairs(archive.entries) do
        if type(entry) == "table" and entry.id == id and type(entry.text) == "string" then return entry end
    end
    return nil
end

function SavedLogs.Delete(db, id)
    local archive = SavedLogs.Initialize(db)
    if not archive then return false end
    for index, entry in ipairs(archive.entries) do
        if type(entry) == "table" and entry.id == id then table.remove(archive.entries, index); return true end
    end
    return false
end
