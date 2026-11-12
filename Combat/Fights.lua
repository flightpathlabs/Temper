local _, ns = ...

-- One record per fight.
--
-- A fight runs from the moment the game says the player is in combat to
-- the moment it says they aren't. The game keeps its own tally of damage
-- for each fight, ability by ability, and lets addons read it the instant
-- the fight is over. That tally is where every damage figure in Temper
-- comes from. The counts of hits, crits and casts come from Hits.lua.
--
-- A saved fight looks like this:
--
--   at        when it began, as server time
--   length    seconds in combat
--   damage    everything the player and their pet dealt
--   hits, crits, glancing, avoided   blows on the target, counted
--   target    the name of what was targeted when it began
--   level     the player's level at the time
--   spells    list of { id, name, kind, damage, casts }, biggest first
--   enemies   list of { name, damage }, one per enemy that was hurt

local Fights = {}
ns.Fights = Fights

-- A fight shorter than this is timed as this long, so that one lucky
-- opening shot doesn't read as a thousand damage per second.
local SHORTEST_FIGHT = 1

local IsSecret = issecretvalue or function()
    return false
end

-- The fight in progress: { start, at, target, grouped, recording }.
local current

-- The game numbers its tallies. This is the number of the last one we
-- saved, so the same fight is never saved twice.
local lastTally

--- The value if it's a number we may read, otherwise nil.
local function Readable(value)
    if IsSecret(value) or type(value) ~= "number" then
        return nil
    end
    return value
end

--- Adds one source's rows from the game's tally to our list.
local function AddSpells(spells, rows, fromPet)
    if type(rows) ~= "table" then
        return
    end

    for _, row in ipairs(rows) do
        local id = Readable(row.spellID)
        local damage = Readable(row.totalAmount)

        if id and damage and damage > 0 then
            -- A pet's damage can also arrive folded into its owner's rows,
            -- marked with the pet's name.
            local creature = row.creatureName
            local isPet = fromPet
                or (not IsSecret(creature) and type(creature) == "string" and creature ~= "")

            table.insert(spells, {
                id = id,
                name = ns.Sources.Name(id),
                kind = ns.Sources.Kind(id, isPet),
                damage = damage,
            })
        end
    end
end

--- The number of the newest tally the game is holding, or nil.
local function NewestTally()
    local newest
    for _, session in ipairs(C_DamageMeter.GetAvailableCombatSessions()) do
        local id = Readable(session.sessionID)
        if id and (not newest or id > newest) then
            newest = id
        end
    end
    return newest
end

--- Reads the fight that just ended out of the game's damage tally.
--- Run under pcall: on a client or in a place where the tally is withheld,
--- any line here may fail, and the right response is to keep nothing.
---@return number|nil damage  nil when the figures couldn't be read, or
---                           when there's no new tally to read
---@return table spells
---@return table enemies
local function ReadTally()
    local session = Enum.DamageMeterSessionType.Current
    local dealt = Enum.DamageMeterType.DamageDone
    local taken = Enum.DamageMeterType.EnemyDamageTaken

    -- A fight in which the player hurt nothing may leave the game still
    -- showing the one before. That one's already on record.
    local newest = NewestTally()
    if newest and newest == lastTally then
        return nil
    end

    local me = UnitGUID("player")
    local mine = C_DamageMeter.GetCombatSessionSourceFromType(session, dealt, me)
    local damage = Readable(mine.totalAmount)
    if not damage then
        return nil
    end

    local spells = {}
    AddSpells(spells, mine.combatSpells, false)

    -- A pet may be listed as a fighter in its own right. Only then is its
    -- damage added, or it would be counted twice.
    local pet = UnitGUID("pet")
    if pet and not IsSecret(pet) then
        local everyone = C_DamageMeter.GetCombatSessionFromType(session, dealt)
        for _, source in ipairs(everyone.combatSources) do
            if not IsSecret(source.sourceGUID) and source.sourceGUID == pet then
                local theirs = C_DamageMeter.GetCombatSessionSourceFromType(session, dealt, pet)
                damage = damage + (Readable(theirs.totalAmount) or 0)
                AddSpells(spells, theirs.combatSpells, true)
            end
        end
    end

    local enemies = {}
    local hurt = C_DamageMeter.GetCombatSessionFromType(session, taken)
    for _, source in ipairs(hurt.combatSources) do
        local amount = Readable(source.totalAmount)
        if amount and amount > 0 then
            local name = source.name
            if IsSecret(name) or type(name) ~= "string" then
                name = "Enemy"
            end
            table.insert(enemies, { name = name, damage = amount })
        end
    end

    lastTally = newest
    return damage, spells, enemies
end

--- True if the recording is still in the list, not deleted meanwhile.
local function StillKept(recording)
    for _, candidate in ipairs(ns.character.recordings) do
        if candidate == recording then
            return true
        end
    end
    return false
end

-- A fight belongs to whichever recording was running when it began.
-- Pressing Record or Stop in the middle of one takes effect from the next.
local function Save(fight, recording)
    if recording and StillKept(recording) then
        table.insert(recording.fights, fight)
    else
        local recent = ns.character.recent
        table.insert(recent, fight)
        while #recent > ns.RECENT_FIGHTS do
            table.remove(recent, 1)
        end
    end

    ns.Publish("FIGHT_SAVED", fight)
    ns.Publish("RECORDINGS_CHANGED")
end

ns.OnEvent("PLAYER_REGEN_DISABLED", function()
    ns.Hits.Begin()

    local target = UnitName("target")
    if IsSecret(target) then
        target = nil
    end

    current = {
        start = GetTime(),
        at = GetServerTime(),
        target = target,
        grouped = IsInGroup(),
        recording = ns.Recorder.Open(),
    }
end)

--- True while a fight that belongs to this recording is still going on.
function Fights.BelongsTo(recording)
    return current ~= nil and current.recording == recording
end

-- The game starts its numbering again when its tallies are cleared.
ns.OnEvent("DAMAGE_METER_RESET", function()
    lastTally = nil
end)

ns.OnEvent("PLAYER_REGEN_ENABLED", function()
    if not current then
        return
    end
    local began = current
    current = nil

    local tally, casts = ns.Hits.Finish(began.start)

    -- With anyone else around, the hits on the target aren't all ours.
    if began.grouped or IsInGroup() or not ns.character then
        return
    end

    local ok, damage, spells, enemies = pcall(ReadTally)
    if not ok or not damage or damage <= 0 then
        return
    end

    for _, spell in ipairs(spells) do
        spell.casts = casts[spell.id]
    end
    table.sort(spells, function(a, b)
        return a.damage > b.damage
    end)

    Save({
        at = began.at,
        length = math.max(GetTime() - began.start, SHORTEST_FIGHT),
        damage = damage,
        hits = tally.hits,
        crits = tally.crits,
        glancing = tally.glancing,
        avoided = tally.avoided,
        target = began.target,
        level = UnitLevel("player"),
        spells = spells,
        enemies = enemies,
    }, began.recording)
end)
