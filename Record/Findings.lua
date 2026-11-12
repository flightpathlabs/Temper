local _, ns = ...

-- Says in words what the figures show.
--
-- Each finding is one plain sentence about something a player could act
-- on. There are only ever a few: a page of observations is as hard to use
-- as a page of numbers. Nothing is said unless the figures clearly
-- support it.

local Findings = {}
ns.Findings = Findings

-- How many sentences at most: this many about a comparison, and this many
-- in all.
local MOST_ABOUT_CHANGE = 3
local MOST = 4

-- An ability has to account for this much of the damage before a change
-- in it is worth a sentence.
local WORTH_MENTIONING = 0.05

-- With fewer fights than this on either side, one lucky crit can decide
-- a comparison.
local FAIR_SAMPLE = 3

-- A weapon skill has to be this far short of what the enemy calls for
-- before it's costing enough to mention. Fifteen points is a little under
-- two attacks in a hundred lost to misses, dodges and parries together.
local SKILL_GAP_WORTH_MENTIONING = 15

-- The spell behind an ordinary melee swing. Any other auto attack is a
-- bow, gun or wand.
local MELEE_SWING = 6603

-- Shares of attacks at which a way of failing is worth pointing out.
local MANY_MISSES = 0.1
local MANY_DODGES_AND_PARRIES = 0.12
local MANY_GLANCING = 0.15

--- The ability that gives most and least damage for what it costs, among
--- those that cost the same resource. Needs two to mean anything.
local function BestValue(summary)
    -- A character can have abilities that cost different things. Compare
    -- within whichever resource most of them use.
    local counts, common = {}, nil
    for _, ability in ipairs(summary.abilities) do
        if ability.perCost then
            counts[ability.power] = (counts[ability.power] or 0) + 1
            if not common or counts[ability.power] > counts[common] then
                common = ability.power
            end
        end
    end

    local best, worst
    for _, ability in ipairs(summary.abilities) do
        if ability.perCost and ability.power == common then
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

--- The ability whose contribution moved most each way since "before".
local function BiggestMoves(comparison)
    local gain, loss
    for _, ability in ipairs(comparison.is.abilities) do
        local pair = comparison.abilities[ability.kind .. ability.id]
        local change = pair and pair.change

        if change and ability.share >= WORTH_MENTIONING then
            if change > 0 and (not gain or change > gain.change) then
                gain = { name = ability.name, change = change }
            elseif change < 0 and (not loss or change < loss.change) then
                loss = { name = ability.name, change = change }
            end
        end
    end
    return gain, loss
end

--- Which kinds of weapon did any damage in these fights. A bow carried
--- but never fired has no bearing on how the fights went.
local function WeaponsUsed(summary)
    local used = {}
    for _, ability in ipairs(summary.abilities) do
        if ability.kind == "auto" then
            used[ability.id == MELEE_SWING and "melee" or "ranged"] = true
        end
    end
    return used
end

--- The weapon in use whose skill is furthest behind what these enemies
--- call for, if it could still be trained higher.
---@return table|nil  { name, rank, wanted, cost }, cost being roughly the
---                   share of attacks it's losing
local function WeakestWeapon(summary)
    if not summary.enemyLevel then
        return nil
    end

    local used = WeaponsUsed(summary)
    local wanted = summary.enemyLevel * ns.Weapons.SKILL_PER_LEVEL
    local weakest

    for _, weapon in ipairs(summary.weapons or {}) do
        local gap = wanted - weapon.rank
        local canImprove = not weapon.cap or weapon.rank < weapon.cap

        if used[weapon.use] and canImprove and gap >= SKILL_GAP_WORTH_MENTIONING then
            if not weakest or gap > weakest.gap then
                weakest = {
                    name = weapon.name,
                    rank = weapon.rank,
                    wanted = wanted,
                    gap = gap,
                    use = weapon.use,
                }
            end
        end
    end

    if weakest then
        -- Each point short comes off the chance to hit. In melee it also
        -- goes on to the enemy's chance to dodge and to parry; a shot can
        -- only miss.
        local ways = weakest.use == "melee" and 3 or 1
        weakest.cost = weakest.gap * ns.Weapons.COST_PER_POINT * ways / 100
    end
    return weakest
end

--- A few sentences about a set of fights.
---@param summary table  from Summary.Of
---@param comparison table|nil  from Compare.Between, when comparing
---@return table  list of strings, most useful first
function Findings.For(summary, comparison)
    local found = {}
    local most = MOST
    local function Say(text, ...)
        if #found < most then
            table.insert(found, text:format(...))
        end
    end

    -- First, when comparing: the verdict, and what drove it.
    if comparison and comparison.dps.change then
        most = MOST_ABOUT_CHANGE

        local change = comparison.dps.change
        local percent = math.floor(math.abs(change) * 100 + 0.5)
        if percent == 0 then
            Say("Overall, your damage a second is the same as before.")
        elseif change > 0 then
            Say("Overall, you did %d%% more damage a second than before.", percent)
        else
            Say("Overall, you did %d%% less damage a second than before.", percent)
        end

        if summary.fights < FAIR_SAMPLE or comparison.was.fights < FAIR_SAMPLE then
            Say("That's from very few fights. Three or more on each side is a fairer test.")
        end

        local gain, loss = BiggestMoves(comparison)
        if gain then
            Say("%s gained the most, up %s.", gain.name, ns.Percent(gain.change))
        end
        if loss then
            Say("%s lost the most, down %s.", loss.name, ns.Percent(-loss.change))
        end

        most = MOST
    end

    -- Then whatever is holding the damage back, worst first.
    local weapon = WeakestWeapon(summary)
    if weapon then
        Say(
            "Your %s skill is %d; level %d enemies call for %d. That costs about %s of "
                .. "your attacks. It rises with use.",
            weapon.name,
            weapon.rank,
            summary.enemyLevel,
            weapon.wanted,
            ns.Percent(weapon.cost)
        )
    end

    local attacks = summary.hits + summary.avoided
    local by = summary.avoidedBy
    if attacks > 0 then
        local missed = (by.MISS or 0) / attacks
        local turned = ((by.DODGE or 0) + (by.PARRY or 0)) / attacks

        if missed >= MANY_MISSES and not weapon then
            Say("%s of your attacks missed outright.", ns.Percent(missed))
        end
        if turned >= MANY_DODGES_AND_PARRIES then
            Say(
                "%s of your attacks were dodged or parried. Enemies can't parry what "
                    .. "comes from behind them.",
                ns.Percent(turned)
            )
        end
    end

    if summary.hits > 0 and summary.glancing / summary.hits >= MANY_GLANCING then
        Say(
            "%s of your hits were glancing blows, which do less damage. They come with "
                .. "fighting enemies above your level.",
            ns.Percent(summary.glancing / summary.hits)
        )
    end

    if summary.enemyLevel and summary.level and summary.enemyLevel - summary.level >= 3 then
        Say(
            "These enemies were %d levels above you. Expect misses and resists to ease "
                .. "off as that gap closes.",
            summary.enemyLevel - summary.level
        )
    end

    -- Then what's working well.
    local best, worst = BestValue(summary)
    if best then
        Say(
            "Best value for %s: %s, %.1f damage a point. %s gives %.1f.",
            ns.Summary.PowerWord(best.power),
            best.name,
            best.perCost,
            worst.name,
            worst.perCost
        )
    end

    if summary.best then
        Say("Hardest single use: %s for %s.", summary.best.name, ns.Number(summary.best.damage))
    end

    if summary.damage > 0 and summary.kinds.auto / summary.damage >= 0.5 then
        Say("More than half your damage came from auto attacks.")
    end

    return found
end
