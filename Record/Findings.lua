local _, ns = ...

-- Says in words what the figures show.
--
-- Each finding is one plain sentence about something a player could act
-- on. There are only ever a few: a page of observations is as hard to use
-- as a page of numbers. Nothing is said unless the figures clearly
-- support it, and what's only an estimate is worded as one.
--
-- The sentences use the same few words as the rest of the addon: DPS,
-- ability, use, fight, session. "Skill" is kept for weapon skill, which is
-- what the game itself means by it.
--
-- A finding also says what kind of news it is, so the page can put the
-- right picture beside it: "good" for something going well, "warning" for
-- something costing damage, "tip" for something worth knowing or trying.

local Findings = {}
ns.Findings = Findings

-- How many sentences at most: this many about a comparison, and this many
-- in all.
local MOST_ABOUT_CHANGE = 2
local MOST = 3

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

-- An ability has to have been traced this many times before its failures
-- mean anything, and to fail this often before they're worth a sentence.
local ENOUGH_TRACED = 5
local OFTEN_FAILS = 0.3

-- Time with no ability in use is only worth a sentence once there's this
-- much fighting to judge by, and once it's this big a share of it.
local ENOUGH_WATCHED = 20
local MUCH_TIME_WITHOUT_AN_ABILITY = 0.3

-- How full mana, energy or rage was when a fight ended, as a share of
-- the most it can be.
local PLENTY_LEFT = 0.4
local NEARLY_EMPTY = 0.15
local EMPTY = 0.1

-- Pauses between fights are worth a sentence once they add up to this
-- much of the time spent fighting.
-- How much more one ability has to give for its cost than another before
-- it's worth suggesting the cost be spent there instead.
local CLEARLY_BETTER_VALUE = 1.2

-- How far DPS has to move between the earlier and later half of a set of
-- fights before it's called a trend.
local TREND_WORTH_MENTIONING = 0.1

-- Shares the way people say them. How each use of an ability went is an
-- estimate, and "2 in 5" claims no more precision than that.
local ROUGHLY = {
    { 1 / 3, "1 in 3" },
    { 2 / 5, "2 in 5" },
    { 1 / 2, "half the" },
    { 3 / 5, "3 in 5" },
    { 2 / 3, "2 in 3" },
    { 3 / 4, "3 in 4" },
    { 9 / 10, "9 in 10" },
}

--- The everyday fraction nearest to a share: "2 in 5" for 0.42.
local function Roughly(share)
    local nearest
    for _, fraction in ipairs(ROUGHLY) do
        if not nearest or math.abs(fraction[1] - share) < math.abs(nearest[1] - share) then
            nearest = fraction
        end
    end
    return nearest[2]
end

--- A share to the nearest five in a hundred: "40%" for 0.42. For figures
--- too rough to quote to the last per cent.
local function RoundPercent(share)
    return ("%d%%"):format(math.floor(share * 20 + 0.5) * 5)
end

-- Reaching for an ability without the mana or energy for it this many
-- times is a habit worth knowing about; once or twice is just a fight.
local STARVED_OFTEN = 3

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

--- The ability whose contribution moved most each way since the earlier
--- fights.
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

--- The ability that most often fails to land, if it fails often enough to
--- be worth a sentence. Auto attacks are left to the sentences about
--- misses and dodges, which count every attack exactly.
---@return table|nil ability
---@return number|nil share  of its traced uses that failed
local function LeastReliable(summary)
    local worst, worstShare
    for _, ability in ipairs(summary.abilities) do
        local traced = (ability.landed or 0) + (ability.failed or 0)

        if ability.kind == "skill" and traced >= ENOUGH_TRACED then
            local share = ability.failed / traced
            if share >= OFTEN_FAILS and (not worst or share > worstShare) then
                worst, worstShare = ability, share
            end
        end
    end
    return worst, worstShare
end

--- The share of the fighting that had no ability in use, when there's
--- enough of both to be worth a sentence.
---@return number|nil
local function TimeWithoutAnAbility(summary)
    if summary.watched < ENOUGH_WATCHED or summary.presses == 0 then
        return nil
    end

    local share = summary.idle / summary.watched
    return share >= MUCH_TIME_WITHOUT_AN_ABILITY and share or nil
end

--- A few sentences about a set of fights.
---@param summary table  from Summary.Of
---@param comparison table|nil  from Compare.Between, when comparing
---@return table  list of { kind = "good", "warning" or "tip", text = the
---               sentence }, most useful first
function Findings.For(summary, comparison)
    local found = {}
    local most = MOST
    local function Say(kind, text, ...)
        if #found < most then
            table.insert(found, { kind = kind, text = text:format(...) })
        end
    end

    local one = summary.fights == 1
    local these = one and "this fight" or "these fights"

    -- First, when comparing: the verdict, and one sentence more. From
    -- very few fights that's the caution, which matters more than any
    -- detail. Otherwise it's the ability that moved most, starting with
    -- the one that moved the way the DPS did, since that's what drove it.
    if comparison and comparison.dps.change then
        most = MOST_ABOUT_CHANGE

        local change = comparison.dps.change
        local percent = math.floor(math.abs(change) * 100 + 0.5)
        if percent == 0 then
            Say("tip", "Overall, your DPS is the same as in the earlier fights.")
        elseif change > 0 then
            Say("good", "Overall, your DPS is %d%% higher than in the earlier fights.", percent)
        else
            Say("warning", "Overall, your DPS is %d%% lower than in the earlier fights.", percent)
        end

        if summary.fights < FAIR_SAMPLE or comparison.was.fights < FAIR_SAMPLE then
            Say("tip", "That's from very few fights. Three or more on each side is a fairer test.")
        end

        local gain, loss = BiggestMoves(comparison)
        local mover = change < 0 and (loss or gain) or (gain or loss)
        if mover and mover.change > 0 then
            Say("good", "%s gained the most, up %s.", mover.name, ns.Percent(mover.change))
        elseif mover then
            Say("warning", "%s lost the most, down %s.", mover.name, ns.Percent(-mover.change))
        end

        most = MOST
    end

    -- Then whatever is holding the damage back, worst first.
    local weapon = WeakestWeapon(summary)
    if weapon then
        Say(
            "warning",
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
            Say("warning", "%s of your attacks missed outright.", ns.Percent(missed))
        end
        if turned >= MANY_DODGES_AND_PARRIES then
            Say("warning", "%s of your attacks were dodged or parried.", ns.Percent(turned))
        end
    end

    local unreliable, failing = LeastReliable(summary)
    if unreliable then
        Say(
            "warning",
            "About %s uses of %s failed to land: missed, dodged, parried or resisted.",
            Roughly(failing),
            unreliable.name
        )
    end

    -- Time with no ability in use isn't a fault in itself: plenty of
    -- characters fight mostly with their weapon. So this says what was
    -- seen and, where the resource bar gives a hint, what it suggests.
    local power = summary.power
    local word = power and ns.Summary.PowerWord(power.kind)
    local unused = TimeWithoutAnAbility(summary)
    local ranDry = false

    if unused and power and power.finish >= PLENTY_LEFT then
        Say(
            "tip",
            "About %s of your time in %s had no ability in use, and you finished with "
                .. "plenty of %s left. There may have been room to use more.",
            RoundPercent(unused),
            these,
            word
        )
    elseif unused and power and power.finish <= NEARLY_EMPTY then
        ranDry = true
        Say(
            "tip",
            "About %s of your time in %s had no ability in use. You finished nearly out "
                .. "of %s, so running dry is the likely reason.",
            RoundPercent(unused),
            these,
            word
        )
    elseif unused then
        Say(
            "tip",
            "About %s of your time in %s had no ability in use.",
            RoundPercent(unused),
            these
        )
    end

    if summary.hits > 0 and summary.glancing / summary.hits >= MANY_GLANCING then
        Say(
            "warning",
            "%s of your hits were glancing blows, which do less damage. They come with "
                .. "fighting enemies above your level.",
            ns.Percent(summary.glancing / summary.hits)
        )
    end

    if summary.enemyLevel and summary.level and summary.enemyLevel - summary.level >= 3 then
        Say(
            "tip",
            "These enemies were %d levels above you. Expect misses and resists to ease "
                .. "off as that gap closes.",
            summary.enemyLevel - summary.level
        )
    end

    -- Mana comes back slowly, so ending on none means the next fight
    -- starts short or waits. Energy and rage are there to be spent, and
    -- ending on none of those is the aim: that's said further down, with
    -- what's going well. Either way it's only said once.
    local empty = power and power.finish <= EMPTY and not ranDry
    if empty and power.kind == "MANA" then
        Say(
            "warning",
            "You finished %s with almost no mana left. A longer fight might have run dry.",
            these
        )
    end

    -- The game hides how much mana is left, but it does say so each time
    -- an ability is tried without enough. Only mana is worth a word:
    -- energy and rage are meant to run out.
    if summary.resource == "MANA" and summary.starved >= STARVED_OFTEN then
        Say("warning", "You ran short of mana %d times in %s.", summary.starved, these)
    end

    -- How DPS moved across the fights themselves, when there are enough
    -- of them for the two halves to mean something.
    local trend = summary.trend
    local moved = trend and ns.Change(trend.early, trend.late)
    if moved and math.abs(moved) >= TREND_WORTH_MENTIONING then
        Say(
            moved > 0 and "good" or "tip",
            "Your DPS %s over %s: %s in the earlier half, %s in the later.",
            moved > 0 and "rose" or "fell",
            these,
            ns.Rate(trend.early),
            ns.Rate(trend.late)
        )
    end

    -- Then what an ability's cost buys. Where one gives clearly more for
    -- its mana or energy than another, say what the difference comes to
    -- in damage: that's a choice the player can make.
    local best, worst = BestValue(summary)
    if best and best.perCost >= worst.perCost * CLEARLY_BETTER_VALUE then
        local resource = ns.Summary.PowerWord(best.power)
        Say(
            "tip",
            "%s costs %d %s for about %s damage. The same %s spent on %s would do about %s.",
            worst.name,
            worst.cost,
            resource,
            ns.Number(worst.perCast),
            resource,
            best.name,
            ns.Number(worst.cost * best.perCost)
        )
    elseif best then
        Say(
            "good",
            "%s and %s give about the same for their %s: %.1f and %.1f damage per point.",
            best.name,
            worst.name,
            ns.Summary.PowerWord(best.power),
            best.perCost,
            worst.perCost
        )
    end

    -- The page shows the biggest hit itself when one could be sized. This
    -- is the next best thing for fights where none could.
    local sized = summary.sizes and summary.sizes.biggest
    if summary.best and not sized then
        Say(
            "good",
            "Hardest single use: %s for %s.",
            summary.best.name,
            ns.Number(summary.best.damage)
        )
    end

    if empty and power.kind ~= "MANA" then
        Say(
            "good",
            "You finished %s with almost no %s left, so little of it went unused.",
            these,
            word
        )
    end

    return found
end
