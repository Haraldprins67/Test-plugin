-- Real Lua 5.0-compatible event adapter scenarios.
ClassicLootLogNS = {}
local clock, method, rollLinks, timers, notifications = 100, "group", {}, {}, 0
local units = {player = "Alice", party1 = "Bob", raid1 = "Carol"}
function GetTime() return clock end
function time() return 1700000000 + clock end
function UnitName(unit) return units[unit] end
function GetNumPartyMembers() return 1 end
function GetNumRaidMembers() return 1 end
function GetLootMethod() return method end
function GetLootRollItemLink(id) return rollLinks[id] end
function GetLootRollItemInfo(id) return "icon", "Item " .. id, 1, 4 end
ClassicLootLogNS.Compat = {After = function(delay, callback) timers[table.getn(timers) + 1] = callback end}
dofile("ClassicLootLog/GroupLoot.lua")
dofile("ClassicLootLog/GroupEvents.lua")
local Events = ClassicLootLogNS.GroupEvents
local passed = 0

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, callback)
    clock, method, rollLinks, timers, notifications = 100, "group", {}, {}, 0
    LOOT_ROLL_ROLLED_NEED, LOOT_ROLL_WON_NO_SPAM_NEED = nil, nil
    RANDOM_ROLL_RESULT = nil
    callback()
    passed = passed + 1
    print("PASS " .. name)
end
local function link(id)
    return "|cffa335ee|Hitem:" .. tostring(id) .. ":0:0:0|h[Item " .. tostring(id) .. "]|h|r"
end
local function tracker()
    local db = {}
    return Events.New(db, {now = GetTime, time = time, onChange = function() notifications = notifications + 1 end}), db
end

test("native group rolls record need greed choices ranking and receipt-confirmed winner", function()
    local events = tracker()
    rollLinks[10] = link(100)
    events:HandleEvent("START_LOOT_ROLL", 10, 60000)
    events:HandleEvent("START_LOOT_ROLL", 10, 60000)
    equal(table.getn(events.model:Entries()), 1)
    local entry = events.model:Entries()[1]
    events:HandleEvent("CHAT_MSG_LOOT", "Alice has selected Need for: " .. link(100))
    events:HandleEvent("CHAT_MSG_LOOT", "Bob has selected Greed for: " .. link(100))
    events:HandleEvent("CHAT_MSG_LOOT", "Need Roll - 81 for " .. link(100) .. " by Alice")
    events:HandleEvent("CHAT_MSG_LOOT", "Greed Roll - 99 for " .. link(100) .. " by Bob")
    events:HandleEvent("CHAT_MSG_LOOT", "Alice won: " .. link(100))
    equal(entry.observedWinner, "Alice")
    equal(entry.recipient, nil)
    local ranks = events.model:Rankings(entry.id)
    equal(ranks.highest.player, "Alice")
    equal(ranks.highest.value, 81)
    equal(ranks.second.player, "Bob")
    events:HandleEvent("CHAT_MSG_LOOT", "Alice receives loot: " .. link(100) .. ".")
    equal(entry.recipient, "Alice")
    equal(entry.state, "awarded")
    equal(entry.distributionMethod, "group")
    assert(notifications > 0)
end)

test("expanded and positional Vanilla templates retain actor and roll capture positions", function()
    local events = tracker()
    LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s|Hitem:%d:%d:%d:%d|h[%s]|h%s by %s"
    LOOT_ROLL_WON_NO_SPAM_NEED = "%1$s won: %3$s|Hitem:%4$d:%5$d:%6$d:%7$d|h[%8$s]|h%9$s |cff818181(Need - %2$d)|r"
    rollLinks[20] = link(200)
    events:HandleEvent("START_LOOT_ROLL", 20)
    events:HandleEvent("CHAT_MSG_LOOT", "Need Roll - 73 for " .. link(200) .. " by Bob")
    events:HandleEvent("CHAT_MSG_LOOT", "Bob won: " .. link(200) .. " |cff818181(Need - 73)|r")
    local entry = events.model:Entries()[1]
    equal(entry.rolls[1].player, "Bob")
    equal(entry.rolls[1].value, 73)
    equal(entry.observedWinner, "Bob")
    equal(entry.observedWinnerRoll, 73)
end)

test("master loot manual rolls retain highest second and actual recipient independently", function()
    method = "master"
    local events = tracker()
    local entry = events:BeginItem(link(300))
    events:HandleEvent("CHAT_MSG_SYSTEM", "Alice rolls 50 (1-100)")
    events:HandleEvent("CHAT_MSG_SYSTEM", "Bob rolls 95 (1-100)")
    events:HandleEvent("CHAT_MSG_SYSTEM", "Carol rolls 75 (1-100)")
    events:HandleEvent("CHAT_MSG_SYSTEM", "Outsider rolls 100 (1-100)")
    local ranks = events.model:Rankings(entry)
    equal(ranks.highest.player, "Bob")
    equal(ranks.second.player, "Carol")
    events:HandleEvent("CHAT_MSG_LOOT", "Carol receives loot: " .. link(300) .. ".")
    equal(entry.recipient, "Carol")
    equal(entry.distributionMethod, "master")
    equal(table.getn(entry.rolls), 3)
end)

test("raid EP GP bids bind the actual recipient's normalized bid", function()
    method = "master"
    local events = tracker()
    events:HandleEvent("CHAT_MSG_RAID_WARNING", link(400), "Alice")
    events:HandleEvent("CHAT_MSG_RAID", "MiN", "Alice")
    events:HandleEvent("CHAT_MSG_RAID", "nEeD", "Bob")
    events:HandleEvent("CHAT_MSG_RAID", "M.A.X", "Carol")
    events:HandleEvent("CHAT_MSG_RAID", "MAX", "Outsider")
    events:HandleEvent("CHAT_MSG_RAID", "need healing", "Carol")
    local entry = events.model:Entries()[1]
    equal(entry.bids.alice.kind, "MIN")
    equal(entry.bids.bob.kind, "NEED")
    equal(entry.bids.carol.kind, "MAX")
    events:HandleEvent("CHAT_MSG_LOOT", "Bob receives loot: " .. link(400) .. ".")
    equal(entry.method, "epgp")
    equal(entry.distributionMethod, "master")
    equal(entry.winner, "Bob")
    equal(entry.winnerBid, "NEED")
end)

test("concurrent identical items never receive guessed chat rolls or recipient bids", function()
    local events, db = tracker()
    rollLinks[1], rollLinks[2] = link(500), link(500)
    events:HandleEvent("START_LOOT_ROLL", 1)
    events:HandleEvent("START_LOOT_ROLL", 2)
    equal(table.getn(events.model:Entries()), 2)
    events:HandleEvent("CHAT_MSG_LOOT", "Need Roll - 88 for " .. link(500) .. " by Bob")
    events:HandleEvent("CHAT_MSG_LOOT", "Bob receives loot: " .. link(500) .. ".")
    equal(table.getn(events.model:Entries()[1].rolls), 0)
    equal(table.getn(events.model:Entries()[2].rolls), 0)
    equal(events.model:Entries()[1].recipient, nil)
    equal(events.model:Entries()[2].recipient, nil)
    equal(table.getn(db.groupLoot.unassigned), 1)
    equal(db.groupLoot.unassigned[1].reason, "ambiguous")
end)

test("multiple master announcements require selection before unlinked rolls or bids", function()
    method = "master"
    local events = tracker()
    events:HandleEvent("CHAT_MSG_RAID_WARNING", link(600), "Alice")
    events:HandleEvent("CHAT_MSG_RAID_WARNING", link(601), "Alice")
    events:HandleEvent("CHAT_MSG_SYSTEM", "Bob rolls 92 (1-100)")
    events:HandleEvent("CHAT_MSG_RAID", "NEED", "Bob")
    local first, second = events.model:Entries()[1], events.model:Entries()[2]
    equal(table.getn(first.rolls), 0)
    equal(table.getn(second.rolls), 0)
    equal(first.bids.bob, nil)
    events:Select(first.id)
    events:HandleEvent("CHAT_MSG_SYSTEM", "Bob rolls 92 (1-100)")
    events:HandleEvent("CHAT_MSG_RAID", "NEED", "Bob")
    equal(table.getn(first.rolls), 1)
    equal(first.bids.bob.kind, "NEED")
    equal(second.bids.bob, nil)
end)

test("linked bids identify their item while unrelated chatter and multiple links do not", function()
    method = "master"
    local events = tracker()
    local first = events:ObserveItem(link(700), "First", 4)
    local second = events:ObserveItem(link(701), "Second", 4)
    events:HandleEvent("CHAT_MSG_RAID", "M A X " .. link(701), "Carol")
    equal(second.bids.carol.kind, "MAX")
    equal(first.bids.carol, nil)
    events:HandleEvent("CHAT_MSG_RAID", "I need this " .. link(700), "Bob")
    events:HandleEvent("CHAT_MSG_RAID", "NEED " .. link(700) .. " " .. link(701), "Bob")
    equal(first.bids.bob, nil)
    equal(second.bids.bob, nil)
end)

test("cancelled delayed roll data cannot open a later item context", function()
    local events = tracker()
    events:HandleEvent("START_LOOT_ROLL", 900)
    equal(table.getn(timers), 1)
    events:HandleEvent("CANCEL_LOOT_ROLL", 900)
    rollLinks[900] = link(900)
    timers[1]()
    equal(table.getn(events.model:Entries()), 0)
end)

test("observed loot placeholders bind to a native roll instead of duplicating", function()
    local events = tracker()
    local entry = events:ObserveItem(link(1000), "Observed item", 4)
    rollLinks[1000] = link(1000)
    events:HandleEvent("START_LOOT_ROLL", 1000)
    equal(table.getn(events.model:Entries()), 1)
    equal(entry.rollID, 1000)
    equal(events:ObserveItem(link(1000), "Observed item", 4), entry)
end)

test("identical master drops retain separate source identities and ambiguous receipts", function()
    method = "master"
    local events, db = tracker()
    local first = events:ObserveItem(link(1100), "Identical item", 4, "corpse-one:entry-one")
    local second = events:ObserveItem(link(1100), "Identical item", 4, "corpse-two:entry-two")
    assert(first.id ~= second.id)
    equal(table.getn(events.model:Entries()), 2)
    equal(events:ObserveItem(link(1100), "Identical item", 4, "corpse-one:entry-one"), first)
    equal(table.getn(events.model:Entries()), 2)
    events:HandleEvent("CHAT_MSG_LOOT", "Bob receives loot: " .. link(1100) .. ".")
    equal(first.recipient, nil)
    equal(second.recipient, nil)
    equal(table.getn(db.groupLoot.unassigned), 1)
    equal(db.groupLoot.unassigned[1].reason, "ambiguous")
end)

test("a unique master announcement placeholder adopts its first observed source", function()
    method = "master"
    local events = tracker()
    events:HandleEvent("CHAT_MSG_RAID_WARNING", link(1200), "Alice")
    local placeholder = events.model:Entries()[1]
    equal(placeholder.observedSource, nil)
    equal(events:ObserveItem(link(1200), "Observed item", 4, "corpse-three:entry-three"), placeholder)
    equal(placeholder.observedSource, "corpse-three:entry-three")
    equal(table.getn(events.model:Entries()), 1)
end)

print(string.format("%d group event tests passed", passed))
