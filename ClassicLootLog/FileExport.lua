-- Report formatting for copyable text and the in-addon archive; compatible with Lua 5.0.
ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local FileExport = {}
ns.FileExport = FileExport

local getn = table.getn

local function finite(value)
    return type(value) == "number" and value == value and value - value == 0
end

local function cleanText(value)
    value = tostring(value or "")
    value = string.gsub(value, "|c%x%x%x%x%x%x%x%x", "")
    value = string.gsub(value, "|r", "")
    value = string.gsub(value, "|H.-|h(.-)|h", "%1")
    value = string.gsub(value, "\\", "\\\\")
    value = string.gsub(value, "\t", "\\t")
    value = string.gsub(value, "\r", "\\r")
    return (string.gsub(value, "\n", "\\n"))
end

local function optionsTable(options)
    return type(options) == "table" and options or {}
end

local function timestamp(options)
    if finite(options.timestamp) then return options.timestamp end
    return type(time) == "function" and time() or 0
end

local function playerName(options)
    if type(options.player) == "string" and options.player ~= "" then return options.player end
    if type(UnitName) == "function" then return UnitName("player") or "Unknown" end
    return "Unknown"
end

local function formatter(options)
    if type(options.dateFormatter) == "function" then return options.dateFormatter end
    if type(date) == "function" then return date end
    if os and type(os.date) == "function" then return os.date end
    return function() return "Unknown" end
end

local function formatDate(options, pattern, stamp)
    local ok, value = pcall(formatter(options), pattern, stamp)
    if ok and type(value) == "string" and value ~= "" then return value end
    return "Unknown"
end

local function safePart(value)
    value = tostring(value or "")
    value = string.gsub(value, "[<>:\"/\\|?*%c]", "_")
    value = string.gsub(value, "[%. ]+$", "")
    value = string.gsub(value, "^[%. ]+", "")
    if string.len(value) > 64 then
        local ending = 64
        -- Do not split a UTF-8 player-name character at the byte limit.
        local following = string.byte(value, ending + 1)
        while ending > 0 and following and following >= 128 and following <= 191 do
            ending = ending - 1
            following = string.byte(value, ending + 1)
        end
        value = string.sub(value, 1, ending)
    end
    if value == "" then return "Unknown" end
    return value
end

function FileExport.FileName(options)
    options = optionsTable(options)
    local stamp = timestamp(options)
    return safePart(formatDate(options, "%Y-%m-%d", stamp)) .. "_"
        .. safePart(formatDate(options, "%H-%M-%S", stamp)) .. "_"
        .. safePart(playerName(options)) .. ".txt"
end

function FileExport.BuildReport(db, groupModel, options)
    if type(db) ~= "table" then return nil, "invalid_database" end
    options = optionsTable(options)
    local stamp = timestamp(options)
    local clock = finite(options.clock) and options.clock
        or (type(GetTime) == "function" and GetTime() or 0)
    local function dateTime(value)
        return formatDate(options, "%Y-%m-%d %H:%M:%S", value)
    end
    local lines = {
        "Classic Loot Log export\t1.8.2",
        "Logged by\t" .. cleanText(playerName(options)),
        "Exported\t" .. cleanText(dateTime(stamp)),
        "Scope\tAll currently retained records for this character, not only the visible tab.",
        "",
        "=== SESSION AND ITEM STATISTICS ===",
        ns.Value.AppendSummary(db, ns.Core.ExportSummary(db, clock)),
        "",
        "=== ALL LOOT ENTRIES ===",
        ns.Value.AppendExportColumns(db, ns.Core.Export(db, dateTime)),
        "",
        "=== PARTY / RAID LOOT, ROLLS AND BIDS ===",
    }
    if groupModel and type(groupModel.Export) == "function" then
        lines[getn(lines) + 1] = groupModel:Export()
    else
        lines[getn(lines) + 1] = "Party / raid exporter unavailable."
    end
    lines[getn(lines) + 1] = ""
    lines[getn(lines) + 1] = "=== FINANCES, VENDOR SALES AND DISENCHANT MATERIALS ==="
    if ns.Finance and ns.Finance.Export then lines[getn(lines) + 1] = ns.Finance.Export(db) end
    lines[getn(lines) + 1] = ""
    lines[getn(lines) + 1] = "=== RECEIVED LOOT MONEY ==="
    if ns.Money then
        local total = ns.Money.Total(db)
        lines[getn(lines) + 1] = "Received loot money\t" .. tostring(total) .. "\t" .. ns.Money.Format(total)
        local shared = ns.Money.Initialize(db).sharedCopper
        lines[getn(lines) + 1] = "Group share (included in total)\t" .. tostring(shared) .. "\t" .. ns.Money.Format(shared)
        lines[getn(lines) + 1] = "Basis\tPersonal loot money and your received share of group money; excludes vendor sales and unrelated balance changes."
    end
    lines[getn(lines) + 1] = ""
    lines[getn(lines) + 1] = "=== OBSERVED MOB KILLS ==="
    lines[getn(lines) + 1] = "Date/time\tSession time\tName\tGUID"
    local kills = type(db.mobs) == "table" and db.mobs.kills or {}
    for _, kill in ipairs(type(kills) == "table" and kills or {}) do
        lines[getn(lines) + 1] = table.concat({
            cleanText(dateTime(kill.timestamp)),
            kill.elapsed ~= nil and ns.Core.FormatElapsed(kill.elapsed) or "",
            cleanText(kill.name), cleanText(kill.guid),
        }, "\t")
    end
    lines[getn(lines) + 1] = ""
    lines[getn(lines) + 1] = "End Classic Loot Log export"
    return table.concat(lines, "\n") .. "\n"
end

-- Retained for migration fixtures from the previous queued-export format.
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function FileExport.Base64Encode(value)
    if type(value) ~= "string" then return nil end
    local encoded = {}
    for index = 1, string.len(value), 3 do
        local a, b, c = string.byte(value, index), string.byte(value, index + 1), string.byte(value, index + 2)
        local combined = a * 65536 + (b or 0) * 256 + (c or 0)
        local first = math.floor(combined / 262144)
        local second = math.mod(math.floor(combined / 4096), 64)
        local third = math.mod(math.floor(combined / 64), 64)
        local fourth = math.mod(combined, 64)
        encoded[getn(encoded) + 1] = string.sub(alphabet, first + 1, first + 1)
        encoded[getn(encoded) + 1] = string.sub(alphabet, second + 1, second + 1)
        encoded[getn(encoded) + 1] = b and string.sub(alphabet, third + 1, third + 1) or "="
        encoded[getn(encoded) + 1] = c and string.sub(alphabet, fourth + 1, fourth + 1) or "="
    end
    return table.concat(encoded)
end

FileExport.DesiredName = FileExport.FileName
