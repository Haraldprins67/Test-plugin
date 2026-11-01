-- Deliberately uses Lua 5.0 syntax and the original 1.12 event/API contract.
local clock, stamp, bags, units = 0, 1700000000, {}, {}
ClassicLootLogNS = {Compat = {IsLegacy = true}}
UnitGUID, CombatLogGetCurrentEventInfo, C_Container = nil, nil, nil
GetLootSourceInfo, GetNumLootItems, GetSpellInfo = nil, nil, nil
NUM_BAG_SLOTS = 4
function GetTime() return clock end
function time() return stamp end
function UnitName(unit) return units[unit] and units[unit].name end
function UnitExists(unit)
    local entry = units[unit]
    if entry then return true, entry.guid end
end
function UnitIsPlayer(unit) return units[unit] and units[unit].player end
function UnitIsDead(unit) return units[unit] and units[unit].dead end
function UnitIsTappedByPlayer(unit) return units[unit] and units[unit].tapped end
function UnitIsFriend(_, unit) return units[unit] and units[unit].friendly end
function GetContainerNumSlots() return 4 end
function GetContainerItemLink(bag, slot)
    local entry = bags[bag .. ":" .. slot]
    return entry and entry.link
end
function GetContainerItemInfo(bag, slot)
    local entry = bags[bag .. ":" .. slot]
    if entry then return "icon", entry.quantity end
end
assert(loadfile("ClassicLootLog/Tracking.lua"))()
local Tracker = ClassicLootLogNS.Tracker
local tests = {}
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end
local function tracker(group)
    clock, bags = 0, {}
    units = {
        player = {name = "Tester", guid = "0x00000001", player = true},
        pet = {name = "Bear", guid = "0xF1400001"},
        party1 = {name = "Friend", guid = "0x00000002", player = true},
        partypet1 = {name = "Cat", guid = "0xF1400002"},
        raid1 = {name = "Raider", guid = "0x00000003", player = true},
    }
    local kills, disenchanted = {}, {}
    local instance = Tracker.New({
        includeGroup = group,
        onKill = function(guid, name) kills[table.getn(kills) + 1] = {guid = guid, name = name} end,
        onDisenchant = function(link, quantity)
            disenchanted[table.getn(disenchanted) + 1] = {link = link, quantity = quantity}
        end,
    })
    return instance, kills, disenchanted
end
local function item(slot, id, quantity)
    bags["0:" .. slot] = {link = "item:" .. id, quantity = quantity or 1}
end

tests["legacy damage and death use Octo target GUID and do not duplicate"] = function()
    local instance, kills = tracker(true)
    units.target = {name = "Wolf", guid = "0xF1300001"}
    instance:HandleEvent("CHAT_MSG_COMBAT_SELF_HITS", "You hit Wolf for 10.")
    equal(table.getn(kills), 0)
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "You have slain Wolf!")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf dies.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf dies.")
    equal(table.getn(kills), 1)
    equal(kills[1].guid, "0xF1300001")
end

tests["party raid and group pet damage count but nearby outsider damage does not"] = function()
    local instance, kills = tracker(true)
    instance:HandleEvent("CHAT_MSG_COMBAT_PARTY_HITS", "Friend hits Wolf for 10.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf dies.")
    instance:HandleEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE", "Raider's Fireball crits Boar for 22 Fire damage.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Boar dies.")
    instance:HandleEvent("CHAT_MSG_COMBAT_PARTY_HITS", "Cat hits Spider for 10.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Spider dies.")
    instance:HandleEvent("CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS", "Stranger hits Deer for 10.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Deer dies.")
    equal(table.getn(kills), 3)
end

tests["creature combat channels include group pets but reject unrelated creatures"] = function()
    local instance, kills = tracker(true)
    instance:HandleEvent("CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS", "Cat hits Wolf for 10.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf dies.")
    instance:HandleEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE", "Bear's Lightning Breath hits Boar for 12 Nature damage.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Boar dies.")
    instance:HandleEvent("CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS", "Strangerpet hits Deer for 10.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Deer dies.")
    equal(table.getn(kills), 2)
    equal(kills[1].name, "Wolf")
    equal(kills[2].name, "Boar")
end

tests["group disabled still includes own pet but excludes group contribution"] = function()
    local instance, kills = tracker(false)
    instance:HandleEvent("CHAT_MSG_COMBAT_PET_HITS", "Bear crits Wolf for 30.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf dies.")
    instance:HandleEvent("CHAT_MSG_COMBAT_PARTY_HITS", "Friend hits Boar for 10.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Boar dies.")
    equal(table.getn(kills), 1)
end

tests["pet and group damage use their own targets before an unrelated same-name target"] = function()
    for _, source in ipairs({"pet", "party1", "partypet1"}) do
        local instance, kills = tracker(true)
        units.target = {name = "Wolf", guid = "0xF1300999"}
        local token = source == "pet" and "pettarget" or source .. "target"
        units[token] = {name = "Wolf", guid = "0xF1300111"}
        instance:HandleEvent("CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS", UnitName(source) .. " hits Wolf for 10.")
        units[token].dead = true
        instance:HandleEvent("UNIT_HEALTH", token)
        equal(table.getn(kills), 1)
        equal(kills[1].guid, "0xF1300111")
    end
end

tests["periodic damage requires own or group source and PvP targets are excluded"] = function()
    local instance, kills = tracker(true)
    instance:HandleEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "Wolf suffers 5 Shadow damage from your Corruption.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf dies.")
    instance:HandleEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "Boar suffers 8 Shadow damage from Friend's Corruption.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Boar dies.")
    instance:HandleEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "Deer suffers 8 Shadow damage from Stranger's Corruption.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Deer dies.")
    units.target = {name = "Enemyplayer", guid = "0x00000009", player = true}
    instance:HandleEvent("CHAT_MSG_COMBAT_SELF_HITS", "You hit Enemyplayer for 20.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "You have slain Enemyplayer!")
    equal(table.getn(kills), 2)
end

tests["different same-name GUIDs and consecutive direct kills remain separate"] = function()
    local instance, kills = tracker(true)
    units.target = {name = "Wolf", guid = "0xF1300001"}
    instance:HandleEvent("CHAT_MSG_COMBAT_SELF_HITS", "You hit Wolf for 10.")
    units.target = {name = "Wolf", guid = "0xF1300002"}
    instance:HandleEvent("CHAT_MSG_COMBAT_SELF_HITS", "You hit Wolf for 10.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf dies.")
    units.target = {name = "Wolf", guid = "0xF1300001"}
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf dies.")
    equal(table.getn(kills), 2)
    units.target = nil
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "You have slain Boar!")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "You have slain Boar!")
    equal(table.getn(kills), 4)
    assert(kills[3].guid ~= kills[4].guid)
end

tests["same-name different GUID deaths are not merged across message kinds"] = function()
    local instance, kills = tracker(true)
    units.target = {name = "Wolf", guid = "0xF1300101"}
    instance:HandleEvent("CHAT_MSG_COMBAT_SELF_HITS", "You hit Wolf for 10.")
    units.target.dead = true
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "You have slain Wolf!")
    equal(table.getn(kills), 1)
    units.target = {name = "Wolf", guid = "0xF1300102"}
    instance:HandleEvent("CHAT_MSG_COMBAT_PARTY_HITS", "Friend hits Wolf for 10.")
    units.target.dead = true
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf dies.")
    equal(table.getn(kills), 2, "two known mob GUIDs must count even in the same frame")
    equal(kills[1].guid, "0xF1300101")
    equal(kills[2].guid, "0xF1300102")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf is slain by Friend!")
    equal(table.getn(kills), 2, "the second message for the same corpse is still a duplicate")
end

tests["same-name party credit followed by another personal kill counts both GUIDs"] = function()
    local instance, kills = tracker(true)
    units.target = {name = "Boar", guid = "0xF1300201", dead = true}
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Boar is slain by Friend!")
    equal(table.getn(kills), 1)
    units.target = {name = "Boar", guid = "0xF1300202", dead = true}
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "You have slain Boar!")
    equal(table.getn(kills), 2)
    equal(kills[1].guid, "0xF1300201")
    equal(kills[2].guid, "0xF1300202")
end

tests["seen target corpse cannot consume another live same-name mob participation"] = function()
    local instance, kills = tracker(true)
    units.target = {name = "Wolf", guid = "0xF1300301"}
    instance:HandleEvent("CHAT_MSG_COMBAT_SELF_HITS", "You hit Wolf for 10.")
    units.target = {name = "Wolf", guid = "0xF1300302"}
    instance:HandleEvent("CHAT_MSG_COMBAT_PARTY_HITS", "Friend hits Wolf for 10.")
    units.party1target = {name = "Wolf", guid = "0xF1300302", dead = false}
    units.target = {name = "Wolf", guid = "0xF1300301", dead = true}
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "You have slain Wolf!")
    clock = 0.3
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf dies.")
    equal(table.getn(kills), 1, "a delayed duplicate must not consume another mob's damage record")
    units.target = {name = "Wolf", guid = "0xF1300302", dead = true}
    units.party1target.dead = true
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf dies.")
    equal(table.getn(kills), 2)
    equal(kills[2].guid, "0xF1300302")
end

tests["observed tagged mob death is recovered when its combat death line is missing"] = function()
    local instance, kills = tracker(true)
    units.target = {name = "Wolf", guid = "0xF1300401"}
    instance:HandleEvent("CHAT_MSG_COMBAT_SELF_HITS", "You hit Wolf for 10.")
    units.target.dead = true
    instance:HandleEvent("UNIT_HEALTH", "target")
    equal(table.getn(kills), 1)
    equal(kills[1].guid, "0xF1300401")
    instance:HandleEvent("UNIT_FLAGS", "target")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "You have slain Wolf!")
    clock = 1
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf dies.")
    equal(table.getn(kills), 1, "health and combat messages describe the same corpse")
end

tests["combat death followed by observed unit death counts a GUID once"] = function()
    local instance, kills = tracker(true)
    units.party1target = {name = "Boar", guid = "0xF1300402"}
    instance:HandleEvent("CHAT_MSG_COMBAT_PARTY_HITS", "Friend hits Boar for 10.")
    units.party1target.dead = true
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Boar is slain by Friend!")
    instance:HandleEvent("UNIT_HEALTH", "party1target")
    equal(table.getn(kills), 1)
    equal(kills[1].guid, "0xF1300402")
end

tests["cached group tap recovers targeted deaths without guessing from old corpses"] = function()
    local instance, kills = tracker(true)
    units.target = {name = "Wolf", guid = "0xF1300501", tapped = true}
    instance:HandleEvent("PLAYER_TARGET_CHANGED")
    units.target.dead = true
    instance:HandleEvent("UNIT_HEALTH", "target")
    equal(table.getn(kills), 1)
    units.target = {name = "Old corpse", guid = "0xF1300502", tapped = true, dead = true}
    instance:HandleEvent("PLAYER_TARGET_CHANGED")
    instance:HandleEvent("UNIT_FLAGS", "target")
    equal(table.getn(kills), 1)
end

tests["unit fallback rejects outsider taps players friendly NPCs and missing GUIDs"] = function()
    local instance, kills = tracker(true)
    units.target = {name = "Outsider mob", guid = "0xF1300601"}
    units.pettarget = {name = "Player", guid = "0x00000099", player = true, tapped = true}
    units.party1target = {name = "Friendly NPC", guid = "0xF1300602", friendly = true, tapped = true}
    units.raid1target = {name = "Unknown identity", tapped = true}
    instance:HandleEvent("UNIT_TARGET", "party1")
    for _, unit in ipairs({"target", "pettarget", "party1target", "raid1target"}) do units[unit].dead = true end
    instance:HandleEvent("UNIT_HEALTH", "target")
    equal(table.getn(kills), 0)
end

tests["unit fallback counts own pet damage while group observation is disabled"] = function()
    local instance, kills = tracker(false)
    units.pettarget = {name = "Wolf", guid = "0xF1300701"}
    units.party1target = {name = "Boar", guid = "0xF1300702", tapped = true}
    instance:HandleEvent("CHAT_MSG_COMBAT_PET_HITS", "Bear hits Wolf for 10.")
    instance:HandleEvent("UNIT_TARGET", "party1")
    units.pettarget.dead, units.party1target.dead = true, true
    instance:HandleEvent("UNIT_FLAGS", "pettarget")
    equal(table.getn(kills), 1)
    equal(kills[1].guid, "0xF1300701")
end

tests["two observed same-name group targets dying together remain separate"] = function()
    local instance, kills = tracker(true)
    units.target = {name = "Wolf", guid = "0xF1300801", tapped = true}
    units.party1target = {name = "Wolf", guid = "0xF1300802", tapped = true}
    instance:HandleEvent("UNIT_TARGET", "party1")
    units.target.dead, units.party1target.dead = true, true
    instance:HandleEvent("UNIT_HEALTH", "target")
    equal(table.getn(kills), 2)
    assert(kills[1].guid ~= kills[2].guid)
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf dies.")
    equal(table.getn(kills), 2)
end

tests["reset and expiry cannot turn an old observed corpse into a fresh kill"] = function()
    for _, resetFirst in ipairs({true, false}) do
        local instance, kills = tracker(true)
        units.target = {name = "Wolf", guid = "0xF1300901", tapped = true}
        instance:HandleEvent("PLAYER_TARGET_CHANGED")
        if resetFirst then instance:Reset() else clock = 1801 end
        units.target.dead = true
        instance:HandleEvent("UNIT_HEALTH", "target")
        equal(table.getn(kills), 0)
    end
end

tests["optional tap API may be absent without losing positively tagged unit deaths"] = function()
    local tap = UnitIsTappedByPlayer
    UnitIsTappedByPlayer = nil
    local instance, kills = tracker(true)
    units.target = {name = "Wolf", guid = "0xF1301001"}
    instance:HandleEvent("CHAT_MSG_COMBAT_SELF_HITS", "You hit Wolf for 10.")
    units.target.dead = true
    instance:HandleEvent("UNIT_HEALTH", "target")
    equal(table.getn(kills), 1)
    UnitIsTappedByPlayer = tap
end

tests["localized templates and expired participation are handled conservatively"] = function()
    local instance, kills = tracker(true)
    COMBATHITSELFOTHER, UNITDIESOTHER = "Je raakt %s voor %d.", "%s sterft."
    instance:HandleEvent("CHAT_MSG_COMBAT_SELF_HITS", "Je raakt Wolf voor 10.")
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Wolf sterft.")
    instance:HandleEvent("CHAT_MSG_COMBAT_SELF_HITS", "Je raakt Boar voor 10.")
    clock = 1801
    instance:HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Boar sterft.")
    equal(table.getn(kills), 1)
    COMBATHITSELFOTHER, UNITDIESOTHER = nil, nil
end

tests["legacy disenchant waits for cast completion and identifies one consumed item"] = function()
    local instance, kills, disenchanted = tracker(true)
    item(1, 100)
    item(2, 200, 4)
    instance:HandleEvent("SPELLCAST_START", "Disenchant", 3000)
    assert(instance:IsDisenchantPending())
    instance:HandleEvent("SPELLCAST_STOP")
    assert(instance:IsDisenchantPending())
    clock = 3
    bags["0:1"] = nil
    instance:HandleEvent("SPELLCAST_STOP")
    instance:HandleEvent("LOOT_OPENED")
    equal(instance:GetLootContext().origin, "disenchant")
    equal(table.getn(disenchanted), 1)
    equal(disenchanted[1].link, "item:100")
    equal(disenchanted[1].quantity, 1)
    instance:HandleEvent("BAG_UPDATE", 0)
    equal(table.getn(disenchanted), 1)
    instance:HandleEvent("LOOT_CLOSED")
    instance:HandleEvent("LOOT_OPENED")
    equal(instance:GetLootContext(), nil)
end

tests["legacy failed and interrupted casts cannot mark or claim later loot"] = function()
    for _, failure in ipairs({"SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED"}) do
        local instance, kills, disenchanted = tracker(true)
        item(1, 100)
        instance:HandleEvent("SPELLCAST_START", "Disenchant", 3000)
        clock = 1
        instance:HandleEvent(failure)
        bags["0:1"] = nil
        instance:HandleEvent("SPELLCAST_STOP")
        instance:HandleEvent("BAG_UPDATE", 0)
        instance:HandleEvent("LOOT_OPENED")
        equal(instance:GetLootContext(), nil)
        equal(table.getn(disenchanted), 0)
    end
end

tests["delayed legacy cast and late bag update preserve result context"] = function()
    local instance, kills, disenchanted = tracker(true)
    item(1, 100)
    instance:HandleEvent("SPELLCAST_START", "Disenchant", 3000)
    instance:HandleEvent("SPELLCAST_DELAYED", 1000)
    clock = 3
    instance:HandleEvent("SPELLCAST_STOP")
    assert(instance:IsDisenchantPending())
    instance:HandleEvent("LOOT_OPENED")
    equal(instance:GetLootContext(), nil)
    clock = 4
    instance:HandleEvent("SPELLCAST_STOP")
    equal(instance:GetLootContext().origin, "disenchant")
    instance:HandleEvent("LOOT_CLOSED")
    bags["0:1"] = nil
    instance:HandleEvent("BAG_UPDATE", 0)
    equal(table.getn(disenchanted), 1)
end

local names = {}
for name in pairs(tests) do names[table.getn(names) + 1] = name end
table.sort(names)
for _, name in ipairs(names) do tests[name](); print("PASS " .. name) end
print(table.getn(names) .. " legacy tracking tests passed")
