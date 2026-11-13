local _, ns = ...

-- Adds up the other side of a set of fights: what the player healed, what
-- they took, and what they did about it.
--
-- It's to healing and defence what Summary.lua is to damage. Like a
-- summary, nothing here is saved: it's worked out from the fights each
-- time it's wanted. The few sentences there are to say about it are here
-- too, since these figures are all they read. They follow the rules in
-- Findings.lua: one plain sentence each, and only when the figures clearly
-- support it.
--
-- Fights saved before Temper recorded any of this carry none of it. They
-- count as fights given but not as fights tracked, so a page can tell
-- "nothing was healed" from "nothing was written down".

local Healing = {}
ns.Healing = Healing

-- How many sentences at most.
local MOST = 3

-- Healing has to come to this much of the damage taken before the two are
-- worth setting side by side, and to this much before that's good news.
local HEALED_BACK_WORTH_MENTIONING = 0.1
local MUCH_HEALED_BACK = 0.5

-- How much of the damage taken the game has to mark as avoidable before
-- it's worth a sentence.
local MUCH_AVOIDABLE = 0.15

-- How much more healing one ability has to give for its cost than another
-- before it's worth suggesting the cost be spent there instead, and how
-- many times each has to have been used before what it gives counts.
local CLEARLY_BETTER_VALUE = 1.2
local FEWEST_USES = 3

-- Adding up -------------------------------------------------------------------

--- True if a fight carries any of the figures added up here.
local function IsTracked(fight)
    return fight.healing ~= nil
        or fight.absorbed ~= nil
        or fight.taken ~= nil
        or fight.interrupts ~= nil
        or fight.dispels ~= nil
        or fight.defence ~= nil
end

--- Adds one fight's healing, ability by ability.
---@param byKey table  the abilities met so far, so each gets one line
local function AddHealing(summary, byKey, healing)
    summary.healing = summary.healing + (healing.total or 0)

    for _, spell in ipairs(healing.spells or {}) do
        -- By spell and by whose it is, so a pet's heal and the player's
        -- own of the same name don't end up on one line.
        local key = (spell.pet and "pet" or "own") .. spell.id
        local ability = byKey[key]
        if not ability then
            ability = { id = spell.id, name = spell.name, pet = spell.pet, healing = 0 }
            byKey[key] = ability
            table.insert(summary.abilities, ability)
        end

        ability.healing = ability.healing + spell.amount

        -- Icon, rank and cost as they were in whichever fight is read last.
        ability.icon = spell.icon or ability.icon
        ability.rank = spell.rank or ability.rank
        if spell.cost then
            ability.cost, ability.power = spell.cost, spell.power
        end

        -- Healing per use is worked out over the fights where the casts
        -- were seen, in case some fight's weren't.
        if spell.casts then
            ability.casts = (ability.casts or 0) + spell.casts
            ability.castHealing = (ability.castHealing or 0) + spell.amount
        end
    end
end

--- Adds one fight's damage taken, enemy ability by enemy ability.
---@param byKey table  the enemy abilities met so far
local function AddTaken(summary, byKey, taken)
    summary.taken = summary.taken + (taken.total or 0)
    if taken.avoidable then
        summary.avoidable = (summary.avoidable or 0) + taken.avoidable
    end

    for _, source in ipairs(taken.sources or {}) do
        -- Two kinds of enemy can share an ability. Each keeps its own line.
        local key = source.id .. source.name .. (source.from or "")
        local blow = byKey[key]
        if not blow then
            blow = { id = source.id, name = source.name, from = source.from, amount = 0 }
            byKey[key] = blow
            table.insert(summary.hurtBy, blow)
        end

        blow.amount = blow.amount + source.amount
        blow.avoidable = blow.avoidable or source.avoidable
    end
end

--- Adds one fight's count of what landed on the player.
local function AddDefence(summary, defence)
    summary.heals = summary.heals + (defence.heals or 0)
    summary.healCrits = summary.healCrits + (defence.healCrits or 0)
    summary.struck = summary.struck + (defence.struck or 0)
    summary.avoided = summary.avoided + (defence.avoided or 0)
    for way, times in pairs(defence.avoidedBy or {}) do
        summary.avoidedBy[way] = (summary.avoidedBy[way] or 0) + times
    end
end

--- Sums up the healing and defence in a set of fights.
---@param fights table|nil  list of fights, in any order
---@return table summary:
---   fights      how many fights were given
---   tracked     how many of them had any of this written down; fights
---               saved before Temper recorded it have none
---   seconds     how long the tracked fights lasted in all
---   healing, hps   healing done, and healing per second of those fights
---   absorbed    damage soaked up by the player's own shields
---   taken       damage the player took
---   avoidable   how much of that the game marks as avoidable; nil if it
---               never said
---   healedBack  healing as a share of the damage taken; nil when none was
---   abilities   list, biggest first, of:
---                 id, name, icon, rank, pet   what it is, and whether
---                                             it's the pet's
---                 healing, share              what it did
---                 casts, perCast              uses, and healing per use;
---                                             only where casts were seen
---                 cost, power                 what one use costs
---                 perCost                     healing per point of that
---   hurtBy      list, biggest first, of the enemy abilities that did the
---               damage: id, name, from (the enemy's name, if known),
---               amount, share, avoidable. A fight keeps only its worst
---               few, so these needn't add up to all that was taken
---   heals, healCrits   heals that landed on the player, counted
---   critRate    critical heals as a share of them; nil without a heal
---   struck, avoided    enemy attacks that landed, and that didn't
---   avoidedBy   how many were avoided each way: DODGE, PARRY, BLOCK...
---   avoidRate   attacks avoided as a share of all attacks; nil without
---               a single attack
---   interrupts, dispels   casts interrupted and effects dispelled
function Healing.Of(fights)
    local summary = {
        fights = 0,
        tracked = 0,
        seconds = 0,
        healing = 0,
        hps = 0,
        absorbed = 0,
        taken = 0,
        abilities = {},
        hurtBy = {},
        heals = 0,
        healCrits = 0,
        struck = 0,
        avoided = 0,
        avoidedBy = {},
        interrupts = 0,
        dispels = 0,
    }

    local abilities, blows = {}, {}

    for _, fight in ipairs(fights or {}) do
        summary.fights = summary.fights + 1

        if IsTracked(fight) then
            summary.tracked = summary.tracked + 1
            summary.seconds = summary.seconds + (fight.length or 0)
            summary.absorbed = summary.absorbed + (fight.absorbed or 0)
            summary.interrupts = summary.interrupts + (fight.interrupts or 0)
            summary.dispels = summary.dispels + (fight.dispels or 0)

            if fight.healing then
                AddHealing(summary, abilities, fight.healing)
            end
            if fight.taken then
                AddTaken(summary, blows, fight.taken)
            end
            if fight.defence then
                AddDefence(summary, fight.defence)
            end
        end
    end

    if summary.seconds > 0 then
        summary.hps = summary.healing / summary.seconds
    end
    if summary.taken > 0 then
        summary.healedBack = summary.healing / summary.taken
    end
    if summary.heals > 0 then
        summary.critRate = summary.healCrits / summary.heals
    end
    if summary.struck + summary.avoided > 0 then
        summary.avoidRate = summary.avoided / (summary.struck + summary.avoided)
    end

    for _, ability in ipairs(summary.abilities) do
        ability.share = summary.healing > 0 and ability.healing / summary.healing or 0
        if ability.casts and ability.casts > 0 then
            ability.perCast = ability.castHealing / ability.casts
            if ability.cost then
                ability.perCost = ability.perCast / ability.cost
            end
        end
    end
    table.sort(summary.abilities, function(a, b)
        return a.healing > b.healing
    end)

    for _, blow in ipairs(summary.hurtBy) do
        blow.share = summary.taken > 0 and blow.amount / summary.taken or 0
    end
    table.sort(summary.hurtBy, function(a, b)
        return a.amount > b.amount
    end)

    return summary
end

-- Saying what it shows ------------------------------------------------------------

--- True if a heal's healing for its cost is worth comparing: the player
--- paid for it, and it's been used often enough to go by. One lucky
--- critical heal shouldn't be enough to recommend it. A pet pays for its
--- heals out of its own, which is nothing the player can spend.
local function Comparable(ability)
    return ability.perCost ~= nil and not ability.pet and (ability.casts or 0) >= FEWEST_USES
end

--- The healing ability that gives most and least for what it costs, among
--- the player's own that cost the same resource. Needs two to mean
--- anything.
local function BestValue(summary)
    -- Compare within whichever resource most of them use.
    local counts, common = {}, nil
    for _, ability in ipairs(summary.abilities) do
        if Comparable(ability) then
            counts[ability.power] = (counts[ability.power] or 0) + 1
            if not common or counts[ability.power] > counts[common] then
                common = ability.power
            end
        end
    end

    local best, worst
    for _, ability in ipairs(summary.abilities) do
        if Comparable(ability) and ability.power == common then
            if not best or ability.perCost > best.perCost then
                best = ability
            end
            if not worst or ability.perCost < worst.perCost then
                worst = ability
            end
        end
    end

    if best and worst and best ~= worst then
        return best, worst
    end
end

--- What to call an ability in a sentence that also names another. Two
--- ranks of one heal share a name, and it's common to keep both on the
--- bars, so then the rank goes in too.
local function NameBeside(ability, other)
    if ability.name == other.name and ability.rank then
        return ("%s (%s)"):format(ability.name, ability.rank)
    end
    return ability.name
end

--- The enemy ability that did the most damage of those the game marks as
--- avoidable.
local function WorstAvoidable(summary)
    for _, blow in ipairs(summary.hurtBy) do
        if blow.avoidable then
            -- One the game gave no name for is no use named.
            return blow.id and blow.id ~= 0 and blow or nil
        end
    end
end

--- A few sentences about the healing and defence in a set of fights.
---@param summary table  from Healing.Of
---@return table  list of { kind = "good", "warning" or "tip", text = the
---               sentence }, most useful first; empty when there's
---               nothing worth saying
function Healing.Findings(summary)
    local found = {}
    local function Say(kind, text, ...)
        if #found < MOST then
            table.insert(found, { kind = kind, text = text:format(...) })
        end
    end

    if not summary or summary.tracked == 0 then
        return found
    end

    local these = summary.fights == 1 and "this fight" or "these fights"

    -- First, how the healing stood against the damage taken.
    local back = summary.healedBack
    if back and back >= 1 then
        Say(
            "good",
            "You healed as much in %s as the damage you took: %s healed, %s taken.",
            these,
            ns.Number(summary.healing),
            ns.Number(summary.taken)
        )
    elseif back and back >= HEALED_BACK_WORTH_MENTIONING then
        Say(
            back >= MUCH_HEALED_BACK and "good" or "tip",
            "You healed back %s of the damage you took in %s: %s of %s.",
            ns.Percent(back),
            these,
            ns.Number(summary.healing),
            ns.Number(summary.taken)
        )
    end

    -- Then damage that needn't have been taken. Which abilities count is
    -- the game's own judgement, so the sentence says whose it is.
    local avoidable = summary.avoidable
    local share = avoidable and summary.taken > 0 and math.min(avoidable / summary.taken, 1)
    if share and share >= MUCH_AVOIDABLE then
        local worst = WorstAvoidable(summary)
        if worst then
            Say(
                "warning",
                "%s of the damage you took in %s was from abilities the game marks as "
                    .. "avoidable, most of all %s.",
                ns.Percent(share),
                these,
                worst.name
            )
        else
            Say(
                "warning",
                "%s of the damage you took in %s was from abilities the game marks as avoidable.",
                ns.Percent(share),
                these
            )
        end
    end

    -- Then what a heal's cost buys, where one gives clearly more for its
    -- mana than another: that's a choice the player can make.
    local best, worst = BestValue(summary)
    if best and best.perCost >= worst.perCost * CLEARLY_BETTER_VALUE then
        local resource = ns.Summary.PowerWord(best.power)
        Say(
            "tip",
            "%s costs %d %s for about %s healing. The same %s spent on %s would heal about %s.",
            NameBeside(worst, best),
            worst.cost,
            resource,
            ns.Number(worst.perCast),
            resource,
            NameBeside(best, worst),
            ns.Number(worst.cost * best.perCost)
        )
    end

    -- Last, what went well.
    local interrupts, dispels = summary.interrupts, summary.dispels
    if interrupts > 0 and dispels > 0 then
        Say(
            "good",
            "You interrupted %s and dispelled %s in %s.",
            ns.Count(interrupts, "cast"),
            ns.Count(dispels, "effect"),
            these
        )
    elseif interrupts > 0 then
        Say("good", "You interrupted %s in %s.", ns.Count(interrupts, "cast"), these)
    elseif dispels > 0 then
        Say("good", "You dispelled %s in %s.", ns.Count(dispels, "effect"), these)
    end

    return found
end
