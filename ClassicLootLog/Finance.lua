-- Gross drop estimates, confirmed vendor income and produced DE materials.
-- Kept independent of UI/client events and compatible with Lua 5.0.
ClassicLootLogNS = ClassicLootLogNS or {}
local ns = ClassicLootLogNS
local Finance = {}
ns.Finance = Finance

local floor, max = math.floor, math.max
local getn = table.getn
local mod = math.mod or math.fmod

local function finite(value)
    return type(value) == "number" and value == value and value - value == 0
end

local function positiveInteger(value)
    return finite(value) and max(0, floor(value)) or 0
end

local function text(value, fallback)
    if type(value) == "string" and value ~= "" then return value end
    return fallback or ""
end

function Finance.Initialize(db)
    db = type(db) == "table" and db or {}
    local data = type(db.finance) == "table" and db.finance or {}
    db.finance = data
    data.salesCopper = positiveInteger(data.salesCopper)
    data.buybackCopper = positiveInteger(data.buybackCopper)
    data.sales = type(data.sales) == "table" and data.sales or {}
    data.buybacks = type(data.buybacks) == "table" and data.buybacks or {}
    data.unconfirmed = type(data.unconfirmed) == "table" and data.unconfirmed or {}
    return db
end

function Finance.FormatMoneyAlways(amount)
    if not finite(amount) then return "Unknown" end
    local sign = amount < 0 and "-" or ""
    amount = floor(math.abs(amount))
    return sign .. string.format("%dg %ds %dc", floor(amount / 10000), mod(floor(amount / 100), 100), mod(amount, 100))
end

function Finance.Summary(db)
    db = Finance.Initialize(db)
    local data = db.finance
    local entries = type(db.entries) == "table" and db.entries or {}
    local itemStats = ns.Core.ItemStats({entries = entries})
    local summary = {
        dropCopper = 0, unknownDropUnits = 0, totalDropUnits = 0, knownDropUnits = 0,
        materialRows = itemStats.materialRows, totalMaterials = itemStats.totalMaterials,
        originalsDisenchanted = itemStats.totalDisenchanted,
        salesCopper = data.salesCopper, buybackCopper = data.buybackCopper,
        netSalesCopper = data.salesCopper - data.buybackCopper,
        unconfirmedSales = 0, unconfirmedBuybacks = 0,
        unconfirmedTransactions = getn(data.unconfirmed),
        sales = data.sales, buybacks = data.buybacks, unconfirmed = data.unconfirmed,
    }
    for _, entry in ipairs(entries) do
        if type(entry) == "table" and entry.kind == "item" and entry.origin ~= "disenchant" then
            local quantity = positiveInteger(entry.quantity)
            summary.totalDropUnits = summary.totalDropUnits + quantity
            local price = ns.Value.GetUnitPrice(db, entry.link)
            if finite(price) and price >= 0 then
                summary.dropCopper = summary.dropCopper + quantity * price
                summary.knownDropUnits = summary.knownDropUnits + quantity
            else
                summary.unknownDropUnits = summary.unknownDropUnits + quantity
            end
        end
    end
    for _, entry in ipairs(data.unconfirmed) do
        if type(entry) == "table" and entry.kind == "buyback" then
            summary.unconfirmedBuybacks = summary.unconfirmedBuybacks + 1
        else
            summary.unconfirmedSales = summary.unconfirmedSales + 1
        end
    end
    return summary
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

local function line(values)
    for index = 1, getn(values) do values[index] = exportText(values[index]) end
    return table.concat(values, "\t")
end

local function transactionLines(lines, title, entries)
    lines[getn(lines) + 1] = ""
    lines[getn(lines) + 1] = title
    lines[getn(lines) + 1] = "Timestamp\tItem\tQuantity\tActual copper\tActual value\tSource\tItem link"
    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local amount = positiveInteger(entry.copper)
            lines[getn(lines) + 1] = line({entry.timestamp or "", text(entry.name, "Unknown item"),
                positiveInteger(entry.quantity), amount, Finance.FormatMoneyAlways(amount), entry.source or "",
                text(entry.link)})
        end
    end
end

function Finance.Export(db)
    local summary = Finance.Summary(db)
    local lines = {
        "Finance statistic\tCopper / count\tFormatted value",
        line({"Known gross vendor value of original drops", summary.dropCopper, Finance.FormatMoneyAlways(summary.dropCopper)}),
        line({"Original drop units with unknown vendor price", summary.unknownDropUnits, ""}),
        line({"Original drop units", summary.totalDropUnits, ""}),
        line({"Confirmed gross vendor sales", summary.salesCopper, Finance.FormatMoneyAlways(summary.salesCopper)}),
        line({"Confirmed buybacks", summary.buybackCopper, Finance.FormatMoneyAlways(summary.buybackCopper)}),
        line({"Net confirmed vendor income", summary.netSalesCopper, Finance.FormatMoneyAlways(summary.netSalesCopper)}),
        line({"Unconfirmed sale transactions", summary.unconfirmedSales, ""}),
        line({"Unconfirmed buyback transactions", summary.unconfirmedBuybacks, ""}),
        line({"Disenchanted original item units", summary.originalsDisenchanted, ""}),
        line({"Produced disenchant material units", summary.totalMaterials, ""}),
        "Basis\tGross original-drop quantities retain disenchanted items; materials are listed separately. Sales are confirmed transactions, not estimated drop value.",
        "",
        "Produced disenchant material\tQuantity\tItem ID\tItem link",
    }
    for _, item in ipairs(summary.materialRows) do
        lines[getn(lines) + 1] = line({item.name, item.quantity, item.key, item.link or ""})
    end
    transactionLines(lines, "CONFIRMED VENDOR SALES", summary.sales)
    transactionLines(lines, "CONFIRMED BUYBACKS", summary.buybacks)
    lines[getn(lines) + 1] = ""
    lines[getn(lines) + 1] = "UNCONFIRMED TRANSACTIONS"
    lines[getn(lines) + 1] = "Timestamp\tKind\tItem\tQuantity\tReason\tItem link"
    for _, entry in ipairs(summary.unconfirmed) do
        if type(entry) == "table" then
            lines[getn(lines) + 1] = line({entry.timestamp or "", entry.kind or "sale", text(entry.name, "Unknown item"),
                positiveInteger(entry.quantity), entry.reason or "Unknown", entry.link or ""})
        end
    end
    return table.concat(lines, "\n")
end
