local _, ns = ...

-- Adds a set of fights up into the figures the analysis shows.
--
-- Nothing here is saved. A summary is worked out from the fights each time
-- it's wanted, so there's only ever one copy of the truth.

local Summary = {}
ns.Summary = Summary

-- What to call each resource in a sentence.
local POWER_WORDS = {
    MANA = "mana",
    ENERGY = "energy",
    RAGE = "rage",
    FOCUS = "focus",
}

--- The everyday word for a resource: "mana" for "MANA".
function Summary.PowerWord(power)
    return POWER_WORDS[power] or (power and power:lower()) or "resource"
end

-- How long one use of a skill keeps the player busy, when we can't know
-- better: the pause the game enforces between most abilities.
local BUSY_SECONDS = 1.5

-- Outcomes of a cast, as the timeline records them, that count as landing.
local LANDED = { HIT = true, CRIT = true, GLANCE = true }

--- How long one use of a spell takes: the length of its cast bar if it
--- has one, and the usual pause between abilities if not. Remembered, so
--- the game is only asked once per spell.
local busyFor = {}
local function BusySeconds(id)
    if not busyFor[id] then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        local cast = ok and info and tonumber(info.castTime) or 0
        busyFor[id] = math.max(cast / 1000, BUSY_SECONDS)
    end
    return busyFor[id]
end

--- Whether a spell in a timeline is an auto attack, remembered so the game
--- is only asked once per spell.
local autoAttacks = {}
local function IsAutoAttack(id)
    if autoAttacks[id] == nil then
        autoAttacks[id] = ns.Sources.Kind(id, false) == "auto"
    end
    return autoAttacks[id]
end

--- Goes through one fight's timeline for how the time was spent and how
--- each ability fared.
---@param outcomes table  running count by "kind..id": { landed, failed }
---@return number busy   seconds with a skill in use
---@return number presses  skills used
local function ReadTimeline(fight, outcomes)
    local busy, presses, busyUntil = 0, 0, 0

    for _, item in ipairs(fight.timeline) do
        local auto = IsAutoAttack(item.id)

        if not auto then
            presses = presses + 1

            -- A cast is logged when it goes off, so a spell with a cast bar
            -- was keeping the player busy for that long beforehand. Two
            -- skills in quick succession overlap; count the time once.
            local takes = BusySeconds(item.id)
            local began = item.t - (takes - BUSY_SECONDS)
            local from = math.max(began, busyUntil, 0)
            local to = math.min(math.max(began, 0) + takes, fight.length)
            if to > from then
                busy = busy + (to - from)
                busyUntil = to
            end
        end

        if item.r then
            local key = (auto and "auto" or "skill") .. item.id
            local outcome = outcomes[key]
            if not outcome then
                outcome = { landed = 0, failed = 0 }
                outcomes[key] = outcome
            end
            if LANDED[item.r] then
                outcome.landed = outcome.landed + 1
            else
                outcome.failed = outcome.failed + 1
            end
        end
    end
    return busy, presses
end

local function NewSplit()
    return { fights = 0, damage = 0, seconds = 0, dps = 0 }
end

local function AddToSplit(split, fight)
    split.fights = split.fights + 1
    split.damage = split.damage + fight.damage
    split.seconds = split.seconds + fight.length
end

local function FinishSplit(split)
    if split.seconds > 0 then
        split.dps = split.damage / split.seconds
    end
end

--- Sums up a set of fights.
---@param fights table  list of fights, in any order
---@return table summary:
---   fights, damage, seconds, dps
---   hits, crits, glancing, avoided
---   avoidedBy   attacks that failed each way: MISS, DODGE, PARRY...
---   level, enemyLevel, weapons   as they were in the newest fight
---   critRate    crits as a share of hits; nil without a single hit
---   avoidRate   attacks that missed or were avoided, as a share of all
---               attacks; nil without a single attack
---   abilities   list, biggest first, of:
---                 id, name, kind, icon, rank   what it is
---                 damage, share                what it did
---                 casts, perCast               uses, and damage per use;
---                                              only for skills whose
---                                              casts were seen
---                 cost, power                  what one use costs
---                 perCost                      damage per point of that
---                 landed, failed               how many uses hit and
---                                              how many missed or were
---                                              avoided, as far as could
---                                              be traced: an estimate
---   watched     seconds of fighting for which a timeline was kept, and
---   idle        how many of them had no skill in use
---   presses     skills used in that time
---   power       { kind, finish, fights }: how full mana, energy or rage
---               was at the end of a fight, on average; nil if unknown
---   rested      { fights, rest, seconds, damage, perMinute }: for fights
---               whose rest beforehand is known, the damage a minute once
---               that rest is counted
---   starved     times a skill was pressed without the mana or energy
---   sizes       how hard blows landed, where that could be worked out;
---               all of it an estimate. nil if none could be:
---                 hits, total, crits, critTotal   blows sized, and sums
---                 averageHit, averageCrit         the usual size of each
---                 biggest, biggestSpell           the hardest, and what
---                 biggestCrit, biggestCritSpell   it probably was
---   kinds       damage by kind of source: skill, auto, pet, other
---   best        { name, damage } for the hardest single use of a skill
---   single      fights against one enemy: { fights, damage, seconds, dps }
---   several     fights against more than one, likewise
function Summary.Of(fights)
    local summary = {
        fights = 0,
        damage = 0,
        seconds = 0,
        dps = 0,
        hits = 0,
        crits = 0,
        glancing = 0,
        avoided = 0,
        avoidedBy = {},
        watched = 0,
        idle = 0,
        presses = 0,
        starved = 0,
        abilities = {},
        kinds = { skill = 0, auto = 0, pet = 0, other = 0 },
        single = NewSplit(),
        several = NewSplit(),
    }

    -- Abilities by spell and kind, so a pet's Claw and a druid's Claw
    -- don't end up on one line.
    local byKey = {}

    -- The newest fight speaks for the set on things that are true of a
    -- moment: the player's level, the enemy's, and their weapon skills.
    local newest

    local outcomes = {}
    local sizes = { hits = 0, total = 0, crits = 0, critTotal = 0 }
    local power = { finish = 0, fights = 0 }
    local rested = { fights = 0, rest = 0, seconds = 0, damage = 0 }

    for _, fight in ipairs(fights or {}) do
        summary.fights = summary.fights + 1
        summary.damage = summary.damage + fight.damage
        summary.seconds = summary.seconds + fight.length
        summary.hits = summary.hits + (fight.hits or 0)
        summary.crits = summary.crits + (fight.crits or 0)
        summary.glancing = summary.glancing + (fight.glancing or 0)
        summary.avoided = summary.avoided + (fight.avoided or 0)
        for way, times in pairs(fight.avoidedBy or {}) do
            summary.avoidedBy[way] = (summary.avoidedBy[way] or 0) + times
        end

        if not newest or (fight.at or 0) > (newest.at or 0) then
            newest = fight
        end

        if fight.timeline then
            local busy, presses = ReadTimeline(fight, outcomes)
            summary.watched = summary.watched + fight.length
            summary.idle = summary.idle + math.max(fight.length - busy, 0)
            summary.presses = summary.presses + presses
        end

        if fight.power then
            power.kind = fight.power.kind
            power.finish = power.finish + fight.power.finish
            power.fights = power.fights + 1
        end

        summary.starved = summary.starved + (fight.starved or 0)

        local sized = fight.sizes
        if sized then
            sizes.hits = sizes.hits + sized.hits
            sizes.total = sizes.total + sized.total
            sizes.crits = sizes.crits + sized.crits
            sizes.critTotal = sizes.critTotal + sized.critTotal

            if sized.biggest and (not sizes.biggest or sized.biggest > sizes.biggest) then
                sizes.biggest, sizes.biggestSpell = sized.biggest, sized.biggestSpell
            end
            if sized.biggestCrit and sized.biggestCrit > (sizes.biggestCrit or 0) then
                sizes.biggestCrit, sizes.biggestCritSpell =
                    sized.biggestCrit, sized.biggestCritSpell
            end
        end

        if fight.rest then
            rested.fights = rested.fights + 1
            rested.rest = rested.rest + fight.rest
            rested.seconds = rested.seconds + fight.length
            rested.damage = rested.damage + fight.damage
        end

        if fight.enemies and #fight.enemies > 1 then
            AddToSplit(summary.several, fight)
        else
            AddToSplit(summary.single, fight)
        end

        for _, spell in ipairs(fight.spells or {}) do
            local key = spell.kind .. spell.id
            local ability = byKey[key]
            if not ability then
                ability = { id = spell.id, name = spell.name, kind = spell.kind, damage = 0 }
                byKey[key] = ability
                table.insert(summary.abilities, ability)
            end

            ability.damage = ability.damage + spell.damage
            summary.kinds[spell.kind] = (summary.kinds[spell.kind] or 0) + spell.damage

            -- Icon, rank and cost as they were in whichever fight is read
            -- last. Sets are usually close together in time, so they agree.
            ability.icon = spell.icon or ability.icon
            ability.rank = spell.rank or ability.rank
            if spell.cost then
                ability.cost, ability.power = spell.cost, spell.power
            end

            -- Casts are only counted for skills. An auto attack is switched
            -- on once and swings many times, so its "casts" mean nothing.
            -- Damage per use is worked out over the fights where the casts
            -- were seen, in case some fight's weren't.
            local casts = spell.kind == "skill" and spell.casts
            if casts then
                ability.casts = (ability.casts or 0) + casts
                ability.castDamage = (ability.castDamage or 0) + spell.damage
            end

            -- A skill used once in a fight did all its damage in that one
            -- use. It's the nearest thing to "biggest hit" the game lets
            -- an addon know for certain.
            if casts == 1 and (not summary.best or spell.damage > summary.best.damage) then
                summary.best = { name = spell.name, damage = spell.damage }
            end
        end
    end

    if sizes.biggest then
        sizes.averageHit = sizes.hits > 0 and sizes.total / sizes.hits or nil
        sizes.averageCrit = sizes.crits > 0 and sizes.critTotal / sizes.crits or nil
        summary.sizes = sizes
    end

    if power.fights > 0 then
        power.finish = power.finish / power.fights
        summary.power = power
    end
    if rested.fights > 0 then
        rested.perMinute = rested.damage / ((rested.seconds + rested.rest) / 60)
        summary.rested = rested
    end

    if newest then
        summary.level = newest.level
        summary.enemyLevel = newest.enemyLevel
        summary.weapons = newest.weapons
    end

    if summary.seconds > 0 then
        summary.dps = summary.damage / summary.seconds
    end
    if summary.hits > 0 then
        summary.critRate = summary.crits / summary.hits
    end
    if summary.hits + summary.avoided > 0 then
        summary.avoidRate = summary.avoided / (summary.hits + summary.avoided)
    end
    FinishSplit(summary.single)
    FinishSplit(summary.several)

    for _, ability in ipairs(summary.abilities) do
        local outcome = outcomes[ability.kind .. ability.id]
        if outcome then
            ability.landed, ability.failed = outcome.landed, outcome.failed
        end

        ability.share = summary.damage > 0 and ability.damage / summary.damage or 0
        if ability.casts and ability.casts > 0 then
            ability.perCast = ability.castDamage / ability.casts
            if ability.cost then
                ability.perCost = ability.perCast / ability.cost
            end
        end
    end
    table.sort(summary.abilities, function(a, b)
        return a.damage > b.damage
    end)

    return summary
end
