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

-- How long one use of a skill keeps the player busy, when we can't know
-- better: the pause the game enforces between most abilities.
local BUSY_SECONDS = 1.5

-- The most entries a timeline holds (see Combat\Hits.lua).
local FULL_TIMELINE = 120

-- Outcomes of a cast, as the timeline records them, that count as landing.
local LANDED = { HIT = true, CRIT = true, GLANCE = true }

--- The everyday word for a resource: "mana" for "MANA".
---@param power string|nil  the game's token for it
function Summary.PowerWord(power)
    return POWER_WORDS[power] or (power and power:lower()) or "resource"
end

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

-- A split is the fights against one enemy, or those against several, added
-- up apart from the rest so the two can be set side by side.
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

-- The typical fight -----------------------------------------------------------

-- All the damage over all the time is a fair figure for one fight, but
-- over many it's easily thrown. A few seconds on a critter can do more
-- damage a second than a long fight with something that hits back, and
-- one lucky fight can lift a whole evening. So a set of fights is also
-- given a typical figure, worked out in two steps.
--
-- First, fights that would only mislead are left out: those that don't
-- count towards bests (left out by hand, over in under six seconds, or
-- won mostly by an item; see Progress.WhyNotCounted), and those against
-- critters or enemies so far below the player that the game gives no
-- experience for them (Foes.IsTrivial).
--
-- Then each fight that's left is taken at its own DPS, long or short, and
-- from three fights up the highest and the lowest are set aside before
-- the rest are averaged: one from each end, and from twenty fights up a
-- tenth from each end. With three or four fights that leaves the middle
-- one or two, which is the median. With one or two fights there's nothing
-- to set aside, and the figure is just their average.

-- From this many fights up, the highest and lowest are set aside.
local FEWEST_TO_TRIM = 3

-- The share set aside from each end, once that comes to more than one.
local TRIMMED_FROM_EACH_END = 0.1

-- Fewer fights than this and "the earlier half" is one or two fights.
local FEWEST_FOR_A_TREND = 6

--- The rule in a sentence, for a tooltip beside any typical figure.
Summary.TYPICAL_RULE = "Very short fights, fights won mostly by an item, fights against "
    .. "critters or enemies far below your level, and any you left out aren't counted. "
    .. "From three fights up, the highest and lowest of the rest are set aside, so one "
    .. "fluke can't tip it."

--- Whether a fight goes towards a typical figure. Progress and Foes both
--- load after this file, so they're looked up when they're wanted.
local function GoesTowardsTypical(fight)
    if (fight.length or 0) <= 0 then
        return false
    end

    local progress = ns.Progress
    if progress and progress.WhyNotCounted(fight) then
        return false
    end

    -- Foes is missing only straight after an update, until the game is
    -- restarted and finds the new file.
    local foes = ns.Foes
    if foes and foes.IsTrivial and foes.IsTrivial(fight) then
        return false
    end
    return true
end

-- Experiments measure how far fights stray from the typical figure, over
-- the same fights it went by.
Summary.GoesTowardsTypical = GoesTowardsTypical

--- The average of a list of DPS figures once the extremes are set aside.
---@param rates table  one figure per fight; sorted here
---@return number|nil dps  nil for an empty list
---@return string how  how it was reached, for a tooltip
---@return number trimmed  how many were set aside from each end
local function MiddleAverage(rates)
    local count = #rates
    if count == 0 then
        return nil, "no fights", 0
    end
    table.sort(rates)

    local trimmed = 0
    if count >= FEWEST_TO_TRIM then
        trimmed = math.max(1, math.floor(count * TRIMMED_FROM_EACH_END))
    end

    local total = 0
    for index = 1 + trimmed, count - trimmed do
        total = total + rates[index]
    end
    local kept = count - 2 * trimmed

    local how
    if count == 1 then
        how = "1 fight"
    elseif trimmed == 0 then
        how = ("average of %d fights"):format(count)
    elseif kept == 1 then
        how = ("median of %d fights"):format(count)
    else
        how = ("middle %d of %d fights"):format(kept, count)
    end
    return total / kept, how, trimmed
end

--- A typical DPS across a set of fights: see the top of this section for
--- how it's reached.
---@param fights table|nil  list of fights, in any order
---@return table typical:
---   dps       the figure; nil when no fight is left to go by
---   counted   how many fights it went by
---   left      how many were left out before that; counted + left is
---             every fight in the set
---   trimmed   of those counted, how many were set aside from each end
---   how       a few words for a tooltip: "middle 8 of 10 fights"
function Summary.Typical(fights)
    local rates, left = {}, 0
    for _, fight in ipairs(fights or {}) do
        if GoesTowardsTypical(fight) then
            table.insert(rates, fight.damage / fight.length)
        else
            left = left + 1
        end
    end

    local dps, how, trimmed = MiddleAverage(rates)
    return { dps = dps, counted = #rates, left = left, trimmed = trimmed, how = how }
end

--- The DPS a set of fights is shown by: its typical figure when there are
--- several fights and any of them count, and otherwise all the damage over
--- all the time, which for a single fight is simply its own DPS.
---@param summary table  from Summary.Of
---@return number dps
---@return boolean typical  true when it's the typical figure
function Summary.DpsOf(summary)
    if summary.fights > 1 and summary.typical.dps then
        return summary.typical.dps, true
    end
    return summary.dps, false
end

--- Typical DPS in the earlier and the later half of a set of fights. Only
--- the fights that go towards a typical figure are halved, so that a run
--- of critters at one end can't make a trend of its own.
---@return table|nil  { early, late }; nil with too few fights to halve
local function Trend(fights)
    local ordered = {}
    for _, fight in ipairs(fights or {}) do
        if GoesTowardsTypical(fight) then
            table.insert(ordered, fight)
        end
    end
    if #ordered < FEWEST_FOR_A_TREND then
        return nil
    end
    table.sort(ordered, function(a, b)
        return (a.at or 0) < (b.at or 0)
    end)

    local half = math.floor(#ordered / 2)
    local function Typical(from, to)
        local rates = {}
        for index = from, to do
            table.insert(rates, ordered[index].damage / ordered[index].length)
        end
        return (MiddleAverage(rates))
    end

    return { early = Typical(1, half), late = Typical(#ordered - half + 1, #ordered) }
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
---   resource    what the player fights with: "MANA", "ENERGY"...
---   typical     from Summary.Typical: a DPS that leaves out flukes and
---               easy fights; dps is the plain total over the total time
---   trend       { early, late }: typical DPS in the earlier and later
---               half of the fights, when there are enough to halve;
---               else nil
---   starved     times an ability was tried without the mana or energy
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

            -- A very long fight's timeline stops when it's full. Only the
            -- part that was written down can be said to be watched.
            local watched = fight.length
            local last = fight.timeline[#fight.timeline]
            if #fight.timeline >= FULL_TIMELINE and last then
                watched = math.min(watched, last.t + BUSY_SECONDS)
            end

            summary.watched = summary.watched + watched
            summary.idle = summary.idle + math.max(watched - busy, 0)
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

    summary.typical = Summary.Typical(fights)
    summary.trend = Trend(fights)

    if newest then
        summary.resource = newest.resource
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
