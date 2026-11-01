local ns = {}
assert(loadfile("ClassicLootLog/Tracking.lua"))("ClassicLootLog", ns)
local Tracker = ns.Tracker
local clock, stamp, combat, bags = 0, 1700000000, {}, {}
NUM_BAG_SLOTS = 4
function GetTime() return clock end
function time() return stamp end
function UnitGUID(unit)
    if unit == "player" then return "Player-1" end
    if unit == "pet" then return "Pet-1" end
end
function CombatLogGetCurrentEventInfo() return unpack(combat) end
local function key(bag, slot) return bag .. ":" .. slot end
C_Container = {
    GetContainerNumSlots = function() return 4 end,
    GetContainerItemLink = function(bag, slot)
        return bags[key(bag, slot)] and bags[key(bag, slot)].link
    end,
    GetContainerItemInfo = function(bag, slot) return bags[key(bag, slot)] end,
}
local function setBag(slot, id, quantity, bag)
    bags[key(bag or 0, slot)] = { link = "|Hitem:" .. id .. ":0:0|h[Item " .. id .. "]|h", stackCount = quantity or 1 }
end
local function damage(event, source, dest, name, flags)
    combat = {clock, event, false, source, "Attacker", flags or 0, 0, dest, name or "Mob", 0, 0}
end
local function newTracker()
    clock, bags = 0, {}
    local kills, disenchanted = {}, {}
    local tracker = Tracker.New({
        now = function() return clock end,
        onKill = function(guid, name, timestamp, at)
            kills[#kills + 1] = {guid = guid, name = name, timestamp = timestamp, at = at}
        end,
        onDisenchant = function(link, quantity, at)
            disenchanted[#disenchanted + 1] = {link = link, quantity = quantity, at = at}
        end,
    })
    return tracker, kills, disenchanted
end
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local tests = {}

tests["only player and pet damage followed by NPC death counts"] = function()
    local tracker, kills = newTracker()
    for _, source in ipairs({"Player-1", "Pet-1"}) do
        local guid = "Creature-" .. source
        damage("SPELL_DAMAGE", source, guid, "Wolf")
        tracker:HandleCombatLog()
        damage("UNIT_DIED", nil, guid, "Wolf")
        tracker:HandleCombatLog()
        tracker:HandleCombatLog()
    end
    equal(#kills, 2)
    equal(kills[1].name, "Wolf")
    equal(kills[1].timestamp, stamp)
    damage("SPELL_DAMAGE", "Player-other", "Creature-other")
    tracker:HandleCombatLog()
    damage("UNIT_DIED", nil, "Creature-other")
    tracker:HandleCombatLog()
    damage("SPELL_DAMAGE", "Player-1", "Player-enemy")
    tracker:HandleCombatLog()
    damage("UNIT_DIED", nil, "Player-enemy")
    tracker:HandleCombatLog()
    equal(#kills, 2)
end

tests["periodic damage counts while unrelated or expired deaths do not"] = function()
    local tracker, kills = newTracker()
    damage("UNIT_DIED", nil, "Creature-unrelated")
    tracker:HandleEvent("COMBAT_LOG_EVENT_UNFILTERED")
    damage("SPELL_PERIODIC_DAMAGE", "Player-1", "Creature-dot")
    tracker:HandleCombatLog()
    clock = 2
    damage("UNIT_DIED", nil, "Creature-dot")
    tracker:HandleCombatLog()
    equal(#kills, 1)
    damage("SWING_DAMAGE", "Player-1", "Creature-expired")
    tracker:HandleCombatLog()
    clock = 1900
    damage("UNIT_DIED", nil, "Creature-expired")
    tracker:HandleCombatLog()
    equal(#kills, 1)
    equal(next(tracker.tags), nil)
end

tests["optional party and raid participation counts each mob once"] = function()
    local tracker, kills = newTracker()
    tracker.callbacks.includeGroup = true
    damage("SPELL_DAMAGE", "Player-party", "Creature-mixed", "Shared wolf", 0x502)
    tracker:HandleCombatLog()
    damage("SWING_DAMAGE", "Pet-party", "Creature-mixed", "Shared wolf", 0x1102)
    tracker:HandleCombatLog()
    damage("SPELL_DAMAGE", "Player-1", "Creature-mixed", "Shared wolf", 0x501)
    tracker:HandleCombatLog()
    damage("UNIT_DIED", nil, "Creature-mixed")
    tracker:HandleCombatLog()
    tracker:HandleCombatLog()
    equal(#kills, 1)
    damage("SPELL_PERIODIC_DAMAGE", "Player-raid", "Creature-raid", "Raid mob", 0x504)
    tracker:HandleCombatLog()
    damage("UNIT_DIED", nil, "Creature-raid")
    tracker:HandleCombatLog()
    equal(#kills, 2)
    damage("SPELL_DAMAGE", "Player-outsider", "Creature-outsider", "Unrelated", 0x508)
    tracker:HandleCombatLog()
    damage("UNIT_DIED", nil, "Creature-outsider")
    tracker:HandleCombatLog()
    equal(#kills, 2)
end

tests["group flags are ignored when group counting is disabled"] = function()
    local tracker, kills = newTracker()
    damage("SPELL_DAMAGE", "Player-party", "Creature-party", "Party mob", 0x502)
    tracker:HandleCombatLog()
    damage("UNIT_DIED", nil, "Creature-party")
    tracker:HandleCombatLog()
    equal(#kills, 0)
end

tests["successful disenchant binds once and identifies a consumed bag item"] = function()
    local tracker, _, disenchanted = newTracker()
    setBag(1, 100, 1)
    setBag(2, 200, 5)
    tracker:HandleEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-1", 13262)
    assert(tracker:IsDisenchantPending())
    tracker:HandleEvent("UNIT_SPELLCAST_START", "player", "Cast-1", 13262)
    tracker:HandleEvent("UNIT_SPELLCAST_STOP", "player", "Cast-1", 13262)
    bags["0:1"] = nil
    setBag(3, 300, 2)
    tracker:HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 13262)
    tracker:HandleEvent("LOOT_READY")
    local context = tracker:GetLootContext()
    equal(context.origin, "disenchant")
    assert(context.sourceGUID:match("^disenchant:"))
    equal(context.itemLink, disenchanted[1].link)
    equal(#disenchanted, 1)
    equal(disenchanted[1].quantity, 1)
    tracker:HandleEvent("BAG_UPDATE_DELAYED")
    equal(#disenchanted, 1)
    tracker:HandleEvent("LOOT_OPENED")
    equal(tracker:GetLootContext(), context)
    tracker:HandleEvent("LOOT_CLOSED")
    tracker:HandleEvent("LOOT_READY")
    equal(tracker:GetLootContext(), nil)
end

tests["loot opening before spell success waits for confirmed context"] = function()
    local tracker = newTracker()
    setBag(1, 100)
    tracker:HandleEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-early", 13262)
    tracker:HandleEvent("LOOT_READY")
    equal(tracker:GetLootContext(), nil)
    assert(tracker:IsDisenchantPending())
    tracker:HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-early", 13262)
    equal(tracker:GetLootContext().origin, "disenchant")
    equal(tracker:IsDisenchantPending(), false)
end

tests["failed interrupted foreign and expired casts never claim later loot"] = function()
    local tracker, _, disenchanted = newTracker()
    setBag(1, 100)
    tracker:HandleEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-failed", 13262)
    tracker:HandleEvent("UNIT_SPELLCAST_FAILED", "player", "Cast-failed", 13262)
    tracker:HandleEvent("LOOT_READY")
    equal(tracker:GetLootContext(), nil)
    tracker:HandleEvent("LOOT_CLOSED")
    tracker:HandleEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-interrupt", 13262)
    tracker:HandleEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-interrupt", 13262)
    equal(tracker:IsDisenchantPending(), false)
    tracker:HandleEvent("UNIT_SPELLCAST_SENT", "party1", "", "Cast-foreign", 13262)
    tracker:HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-foreign", 13262)
    equal(tracker:IsDisenchantPending(), false)
    tracker:HandleEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-expire", 13262)
    clock = 21
    equal(tracker:IsDisenchantPending(), false)
    tracker:HandleEvent("LOOT_OPENED")
    equal(tracker:GetLootContext(), nil)
    equal(#disenchanted, 0)
end

tests["late bag changes after closing loot infer once without rebinding"] = function()
    local tracker, _, disenchanted = newTracker()
    setBag(1, 100)
    tracker:HandleEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-late", 13262)
    tracker:HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-late", 13262)
    tracker:HandleEvent("LOOT_READY")
    tracker:HandleEvent("LOOT_CLOSED")
    bags["0:1"] = nil
    tracker:HandleEvent("BAG_UPDATE_DELAYED")
    equal(#disenchanted, 1)
    tracker:HandleEvent("BAG_UPDATE_DELAYED")
    equal(#disenchanted, 1)
    tracker:HandleEvent("LOOT_OPENED")
    equal(tracker:GetLootContext(), nil)
end

tests["bag moves are ignored and multiple removed items stay ambiguous"] = function()
    local tracker, _, disenchanted = newTracker()
    setBag(1, 100)
    setBag(2, 200)
    tracker:HandleEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-ambiguous", 13262)
    tracker:HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-ambiguous", 13262)
    bags["0:1"] = nil
    setBag(1, 100, 1, 1)
    tracker:HandleEvent("BAG_UPDATE_DELAYED")
    equal(#disenchanted, 0)
    bags["1:1"], bags["0:2"] = nil, nil
    tracker:HandleEvent("BAG_UPDATE_DELAYED")
    equal(#disenchanted, 0)
    setBag(2, 200)
    tracker:HandleEvent("BAG_UPDATE_DELAYED")
    equal(#disenchanted, 0, "ambiguous snapshots must never guess later")
end

tests["missing bag APIs preserve material context without guessing originals"] = function()
    local tracker, _, disenchanted = newTracker()
    local api = C_Container
    C_Container = nil
    tracker:HandleEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-no-api", 13262)
    tracker:HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-no-api", 13262)
    tracker:HandleEvent("LOOT_OPENED")
    equal(tracker:GetLootContext().origin, "disenchant")
    equal(#disenchanted, 0)
    C_Container = api
end

tests["legacy container API counts stacks and reset clears transient state"] = function()
    local tracker, kills = newTracker()
    local api = C_Container
    C_Container = nil
    GetContainerNumSlots = function() return 2 end
    GetContainerItemLink = function(bag, slot)
        if bag == 0 then return "item:100" end
    end
    GetContainerItemInfo = function(bag)
        if bag == 0 then return 1, 3 end
    end
    equal(Tracker.SnapshotBags()["100"].quantity, 6)
    tracker:HandleEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-reset", 13262)
    damage("SPELL_DAMAGE", "Player-1", "Creature-reset")
    tracker:HandleCombatLog()
    tracker:Reset()
    equal(tracker:IsDisenchantPending(), false)
    equal(tracker:GetLootContext(), nil)
    damage("UNIT_DIED", nil, "Creature-reset")
    tracker:HandleCombatLog()
    equal(#kills, 0)
    GetContainerNumSlots, GetContainerItemLink, GetContainerItemInfo = nil, nil, nil
    C_Container = api
end

tests["a real corpse after disenchant success stays regular loot"] = function()
    for _, guid in ipairs({ "Creature-actual-corpse", "GameObject-chest" }) do
        local tracker = newTracker()
        tracker:HandleEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-corpse", 13262)
        tracker:HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-corpse", 13262)
        GetNumLootItems = function() return 1 end
        GetLootSourceInfo = function() return guid, 1 end
        tracker:HandleEvent("LOOT_READY")
        equal(tracker:GetLootContext(), nil)
        tracker:HandleEvent("LOOT_CLOSED")
        GetLootSourceInfo = function() return "Item-late", 1 end
        tracker:HandleEvent("LOOT_READY")
        equal(tracker:GetLootContext(), nil, "a rejected context must not rebind later")
        GetNumLootItems, GetLootSourceInfo = nil, nil
    end
end

tests["success without a precast snapshot cannot guess a later removed item"] = function()
    local tracker, _, disenchanted = newTracker()
    setBag(1, 100)
    tracker:HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-no-snapshot", 13262)
    bags["0:1"] = nil
    tracker:HandleEvent("BAG_UPDATE_DELAYED")
    equal(#disenchanted, 0)
    tracker:HandleEvent("LOOT_READY")
    equal(tracker:GetLootContext().origin, "disenchant")
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
    tests[name]()
    print("PASS " .. name)
end
print(#names .. " tracking tests passed")
