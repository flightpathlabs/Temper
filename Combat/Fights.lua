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
--   avoidedBy how many attacks failed each way: MISS, DODGE, PARRY...
--   target    the name of what was targeted when it began
--   enemyLevel  that target's level, when the game would say
--   level     the player's level at the time
--   weapons   the player's skill with each weapon in hand (see Weapons.lua)
--   recording the number of the recording it belongs to, if any
--   gear      which of the character's gear sets it was fought in
--   timeline  what the player did, in order (see Hits.lua). Only kept
--             for the latest fights, since it's the bulk of a record
--   power     { kind, start, finish }: how full the player's mana, energy
--             or rage was at each end, as a share of the most it can be.
--             Usually absent: the game hides these more often than not
--   starved   how many times a skill was pressed without the mana, rage
--             or energy for it
--   sizes     how hard the blows landed, as far as could be worked out
--             (see Sizes.lua)
--   rest      seconds between the fight before ending and this one
--             beginning, when that was a pause and not a trip to town
--   spells    list of { id, name, kind, damage, casts, icon, rank, cost,
--             power }, biggest first; cost and power are what one use
--             cost at the time ("MANA", "ENERGY"...), when it cost anything
--   enemies   list of { name, damage }, one per enemy that was hurt

local Fights = {}
ns.Fights = Fights

-- A fight shorter than this is timed as this long, so that one lucky
-- opening shot doesn't read as a thousand damage per second.
local SHORTEST_FIGHT = 1

-- How many of the latest fights keep their timeline.
local TIMELINES_KEPT = 60

-- A gap between fights longer than this wasn't spent getting ready for
-- the next one.
local LONGEST_REST = 180

local IsSecret = issecretvalue or function()
    return false
end

-- The fight in progress: { start, at, target, grouped, recording }.
local current

-- When the last fight ended, on GetTime's clock, whether or not it was
-- worth saving.
local lastEnd

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

--- What the game knows about an ability beyond its name: its icon, its
--- rank, and what one use costs. Noted with the fight, since all three
--- change as the character levels.
local function Describe(spell)
    local id = spell.id
    if id == 0 then
        return
    end

    spell.icon = C_Spell.GetSpellTexture(id)

    local rank = C_Spell.GetSpellSubtext(id)
    if type(rank) == "string" and rank ~= "" then
        spell.rank = rank
    end

    local costs = C_Spell.GetSpellPowerCost(id)
    local first = costs and costs[1]
    if first and Readable(first.cost) and first.cost > 0 and type(first.name) == "string" then
        spell.cost = first.cost
        spell.power = first.name
    end
end

--- How full the player's mana, energy or rage is, as a share of the most
--- it can be. Nil if the game won't say.
---@return number|nil share, string|nil kind  e.g. 0.42, "MANA"
local function PowerNow()
    local kind, token = UnitPowerType("player")
    local now = Readable(UnitPower("player", kind))
    local most = Readable(UnitPowerMax("player", kind))
    if not now or not most or most <= 0 or type(token) ~= "string" then
        return nil
    end
    return math.floor(now / most * 100 + 0.5) / 100, token
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

            local spell = {
                id = id,
                name = ns.Sources.Name(id),
                kind = ns.Sources.Kind(id, isPet),
                damage = damage,
            }
            -- The details are a nicety. A refusal mustn't cost the fight.
            pcall(Describe, spell)
            table.insert(spells, spell)
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

-- A fight belongs to whichever recording was running when it began.
-- Pressing Record or Stop in the middle of one takes effect from the next.
--- How the player's mana, energy or rage stood at each end of the fight.
local function PowerSpent(began)
    local ok, finish, kind = pcall(PowerNow)
    if not ok or not finish or not began.power or kind ~= began.powerKind then
        return nil
    end
    return { kind = kind, start = began.power, finish = finish }
end

local function Save(fight, recording)
    if recording and ns.Recorder.StillKept(recording) then
        fight.recording = recording.number
    end
    fight.gear = ns.Gear.Current()

    local fights = ns.character.fights
    table.insert(fights, fight)
    while #fights > ns.MAX_FIGHTS do
        table.remove(fights, 1)
    end

    -- A timeline is most of what a fight weighs, and only the recent ones
    -- are ever looked at that closely.
    local fading = fights[#fights - TIMELINES_KEPT]
    if fading then
        fading.timeline = nil
    end

    -- Dropping the oldest fight may have emptied a recording.
    ns.Recorder.Tidy()

    -- Now we know for certain which abilities do damage, which is what
    -- the icon guesser needs to tell them from buffs and the like.
    ns.Guess.NoteDamaging(fight.spells)

    ns.Publish("FIGHTS_CHANGED")
end

ns.OnEvent("PLAYER_REGEN_DISABLED", function()
    ns.Hits.Begin()
    ns.Sizes.Begin()

    local target = UnitName("target")
    if IsSecret(target) then
        target = nil
    end

    local rest = lastEnd and GetTime() - lastEnd
    if rest and rest > LONGEST_REST then
        rest = nil
    end

    local okPower, power, powerKind = pcall(PowerNow)
    if not okPower then
        power, powerKind = nil, nil
    end

    -- The level of what's being fought, if it's an enemy at all: combat
    -- can start with a friend targeted. A skull-level enemy reports its
    -- level as -1, which tells us nothing.
    local enemyLevel
    local hostile = UnitCanAttack("player", "target")
    if not IsSecret(hostile) and hostile then
        enemyLevel = Readable(UnitLevel("target"))
        if enemyLevel and enemyLevel < 1 then
            enemyLevel = nil
        end
    end

    current = {
        start = GetTime(),
        at = GetServerTime(),
        target = target,
        enemyLevel = enemyLevel,
        rest = rest,
        power = power,
        powerKind = powerKind,
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
    lastEnd = GetTime()

    local tally, casts, timeline, blows = ns.Hits.Finish(began.start)

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

    local fight = {
        at = began.at,
        length = math.max(GetTime() - began.start, SHORTEST_FIGHT),
        damage = damage,
        hits = tally.hits,
        crits = tally.crits,
        glancing = tally.glancing,
        avoided = tally.avoided,
        avoidedBy = tally.avoidedBy,
        starved = tally.starved > 0 and tally.starved or nil,
        target = began.target,
        enemyLevel = began.enemyLevel,
        level = UnitLevel("player"),
        weapons = ns.Weapons.Skills(),
        timeline = timeline,
        rest = began.rest and math.floor(began.rest + 0.5),
        power = PowerSpent(began),
        spells = spells,
        enemies = enemies,
    }

    -- Sizing the blows is a nicety built on a figure the game might stop
    -- sharing. Whatever goes wrong with it mustn't cost the fight.
    local sized, sizes = pcall(ns.Sizes.Finish, blows, fight)
    fight.sizes = sized and sizes or nil

    Save(fight, began.recording)
end)
