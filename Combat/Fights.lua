local _, ns = ...

-- One record per fight.
--
-- A fight runs from the moment the game says the player is in combat to
-- the moment it says they aren't. The game keeps its own tally of damage
-- for each fight, ability by ability, and lets addons read it the instant
-- the fight is over. That tally is where every damage figure in Temper
-- comes from. The counts of hits, crits and casts come from Hits.lua.
-- Healing, damage taken and the like come from the game's other tallies
-- (see Tallies.lua). They only add to a fight: one is still only saved
-- when the player dealt damage.
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
--   resource  what the player fights with: "MANA", "ENERGY", "RAGE"...
--   starved   how many times an ability was tried without enough of it
--   sizes     how hard the blows landed, as far as could be worked out
--             (see Sizes.lua)
--   rest      seconds between the fight before ending and this one
--             beginning, when that was a pause and not a trip to town
--   spells    list of { id, name, kind, damage, casts, icon, rank, cost,
--             power }, biggest first; cost and power are what one use
--             cost at the time ("MANA", "ENERGY"...), when it cost anything
--   enemies   list of { name, damage }, one per enemy that was hurt
--
-- and, each only when there was something to record and the game would
-- say (so never on a fight saved before Temper looked at these):
--
--   healing   { total, spells }: what the player and their pet healed.
--             spells is a list of { id, name, amount, casts, icon, rank,
--             cost, power, pet }, biggest first, with pet set on the
--             pet's own healing. Since others' healing was first looked
--             for, it can also hold onSelf, onPet and onOthers: where all
--             that healing landed, on the player, on their pet and on
--             anyone else, with petOnSelf the pet's part of onSelf. Only
--             when the game said where every heal landed
--   healedBy  list of { name, class, amount }: other people who healed the
--             player, and how much of their healing landed on them; the
--             eight biggest, biggest first. name is "Someone" when the
--             game wouldn't give it, and class is the game's word for
--             theirs ("PRIEST"), when it has one. Fights in a group aren't
--             saved, so this is a passer-by, or a friend from outside the
--             group, healing a player fighting on their own
--   absorbed  damage soaked up by the player's own shields
--   taken     { total, avoidable, sources }: the damage the player took.
--             sources is a list of { id, name, amount, avoidable, from },
--             one per enemy ability, the twelve biggest, biggest first;
--             from is the enemy's name when the game gives one. avoidable
--             marks what the game says could have been avoided, and is
--             how much of the total that came to
--   interrupts  casts the player or their pet interrupted
--   dispels   effects they dispelled
--   defence   { heals, healCrits, struck, avoided, avoidedBy }: heals that
--             landed on the player and how many were critical; enemy
--             blows that landed, and attacks that didn't, by each way.
--             Counted as they happened (see Hits.lua). On every fight
--             saved since healing was first recorded, even when all are
--             nothing, which is what tells those fights from older ones.
--             Since mitigation was first worked out it also holds crits,
--             crushing and partBlocked (of the blows that landed), and
--             magic, schools and resisted (spells that hit the player,
--             by school). magic being there marks those fights
--   mitigation  { armour, armourCut, blockValue, defence, defenceBase,
--             resistances }: what the player fought with, read as the
--             fight ended: their armour and the share of a blow from the
--             fight's enemy it takes off, what their shield blocks, their
--             Defence skill with and without bonuses, and their resistance
--             to each school of magic that hit them. Each only when the
--             game would say (see Mitigation.lua, which also does the
--             sums: nothing worked out from these is saved)
--   classification  the target's standing as the fight began, in the game's
--             own words: "normal", "elite", "rare", "rareelite",
--             "worldboss", "minus" (a lesser creature) or "trivial". Only
--             when the target was an enemy
--   foes      list of { name, level, classification, count, boss }: the
--             enemies the player struck, one entry for each kind (the same
--             name, level and classification), with how many of that kind
--             there were; the biggest group first. level is nil when the
--             game hid it (a skull), name when it withheld it, and boss is
--             set on one the game calls a boss (see Hits.lua for how each
--             enemy is told apart and counted once)
--   greyRange how many levels below the player an enemy could be before
--             the game showed its level in grey, as worth no experience,
--             at the player's level then (see Record\Foes.lua)

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

-- The fight in progress: { start, at, target, enemyLevel, classification,
-- rest, power, powerKind, grouped, recording }.
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

--- What a reading of the game gives, or nil if it fails.
local function Try(read)
    local ok, value = pcall(read)
    if ok then
        return value
    end
    return nil
end

--- What the game knows about an ability beyond its name: its icon, its
--- rank, and what one use costs. Noted with the fight, since all three
--- change as the character levels. Healing abilities are described the
--- same way (see Tallies.lua).
---@param spell table  a row of a fight's spells; gains icon, rank, and
---                    cost and power when the game gives them
function Fights.Describe(spell)
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

--- Which resource the player fights with: "MANA", "ENERGY", "RAGE"...
--- The game says this even when it won't say how full it is.
local function PowerKind()
    local _, token = UnitPowerType("player")
    if IsSecret(token) or type(token) ~= "string" then
        return nil
    end
    return token
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

--- What the game calls the target's standing: "elite", "rare" and so on.
--- Nil if it won't say.
local function Classification()
    local classification = UnitClassification("target")
    if IsSecret(classification) or type(classification) ~= "string" or classification == "" then
        return nil
    end
    return classification
end

--- How far below the player an enemy can be before the game greys its
--- level out. The nameplates colour levels by the same number.
local function GreyRange()
    return Readable(C_QuestLog.GetTrivialRange())
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
            pcall(Fights.Describe, spell)
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

--- Notes the number of the newest tally as one that's been dealt with.
local function NoteLatestTally()
    local ok, newest = pcall(NewestTally)
    if ok and newest then
        lastTally = newest
    end
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

--- How the player's mana, energy or rage stood at each end of the fight.
local function PowerSpent(began)
    local ok, finish, kind = pcall(PowerNow)
    if not ok or not finish or not began.power or kind ~= began.powerKind then
        return nil
    end
    return { kind = kind, start = began.power, finish = finish }
end

--- Adds to a fight what the game's other tallies say of it: healing,
--- damage taken and the rest. None of it is certain to be there, and
--- whatever goes wrong in the reading mustn't cost the fight.
local function AddOtherTallies(fight, casts)
    -- The game only picks up a file that's new to an addon when it's
    -- restarted. After an update and a reload, Tallies.lua isn't there yet.
    local tallies = ns.Tallies
    if not tallies then
        return
    end

    local ok, found = pcall(tallies.Read, casts)
    if not ok or type(found) ~= "table" then
        return
    end

    fight.healing = found.healing
    fight.healedBy = found.healedBy
    fight.absorbed = found.absorbed
    fight.taken = found.taken
    fight.interrupts = found.interrupts
    fight.dispels = found.dispels
end

--- Notes what the player fought with: armour, shield, Defence skill and
--- resistances. The game may hide any of them, and like the tallies
--- above, none of it is worth losing the fight over.
local function AddMitigation(fight)
    -- Missing straight after an update, until the game is restarted.
    local mitigation = ns.Mitigation
    if not mitigation then
        return
    end

    local ok, found = pcall(mitigation.Read, fight)
    if ok and type(found) == "table" then
        fight.mitigation = found
    end
end

--- Keeps a finished fight with the character's others, and lets the rest
--- of the addon know.
---@param recording table|nil  the recording that was running when it began
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

    -- The level and standing of what's being fought, if it's an enemy at
    -- all: combat can start with a friend targeted. A skull-level enemy
    -- reports its level as -1, which tells us nothing.
    local enemyLevel, classification
    local hostile = UnitCanAttack("player", "target")
    if not IsSecret(hostile) and hostile then
        enemyLevel = Readable(UnitLevel("target"))
        if enemyLevel and enemyLevel < 1 then
            enemyLevel = nil
        end
        classification = Try(Classification)
    end

    current = {
        start = GetTime(),
        at = GetServerTime(),
        target = target,
        enemyLevel = enemyLevel,
        classification = classification,
        rest = rest,
        power = power,
        powerKind = powerKind,
        grouped = IsInGroup(),

        -- A fight belongs to whichever session was running when it
        -- began, even if that session is ended before the fight is. One
        -- started mid-fight begins with the next.
        recording = ns.Recorder.Open(),
    }
end)

--- True while a fight that belongs to this recording is still going on.
---@param recording table
---@return boolean
function Fights.BelongsTo(recording)
    return current ~= nil and current.recording == recording
end

-- Whatever tallies the game is holding at login are from before; none of
-- them is a fight still to be saved.
ns.Subscribe("DATABASE_READY", NoteLatestTally)

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

    local tally, casts, timeline, blows, foes = ns.Hits.Finish(began.start)

    -- With anyone else around, the hits on the target aren't all ours.
    -- The game still made a tally for the fight, so note its number: a
    -- later fight in which nothing is hurt mustn't be mistaken for it.
    if began.grouped or IsInGroup() or not ns.character then
        NoteLatestTally()
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
        classification = began.classification,
        foes = foes and foes[1] and foes or nil,
        level = UnitLevel("player"),
        greyRange = Try(GreyRange),
        weapons = ns.Weapons.Skills(),
        resource = Try(PowerKind),
        timeline = timeline,
        rest = began.rest and math.floor(began.rest + 0.5),
        power = PowerSpent(began),
        spells = spells,
        enemies = enemies,
        -- Kept even when every count is nothing. Its being there is what
        -- marks a fight as one in which healing was looked for.
        defence = tally.defence,
    }

    AddOtherTallies(fight, casts)
    AddMitigation(fight)

    -- Sizing the blows is a nicety built on a figure the game might stop
    -- sharing. Whatever goes wrong with it mustn't cost the fight.
    local sized, sizes = pcall(ns.Sizes.Finish, blows, fight)
    fight.sizes = sized and sizes or nil

    Save(fight, began.recording)
end)
