local _, ns = ...

-- Puts two sets of fights side by side.
--
-- "Before" is the set being compared against, "after" the set being looked
-- at. Which was actually fought first doesn't matter.

local Compare = {}
ns.Compare = Compare

--- The newest fight in a set, which stands for it when asking what gear
--- or level the set was fought at.
local function Latest(fights)
    local latest
    for _, fight in ipairs(fights) do
        if not latest or (fight.at or 0) > (latest.at or 0) then
            latest = fight
        end
    end
    return latest
end

--- What changed between two sets of fights.
---@param before table  list of fights
---@param after table   list of fights
---@return table comparison:
---   was, is         the two summaries
---   dps, perFight   each { before, after, change }, where change is a
---                   fraction of before, or nil
---                   dps is each set's as the page shows it (see
---                   Summary.DpsOf), and also has typicalBefore and
---                   typicalAfter, true where that's a typical figure,
---                   and fightsBefore and fightsAfter, how many fights
---                   each figure went by
---   critRate        { before, after, points }, where points is how far
---                   the rate itself moved: 0.02 from 10% to 12%
---   abilities       by "kind..id": { before, after, change } of damage a
---                   second
---   gear            list from Gear.Diff
---   gearKnown       false when either set has no gear on record
---   levels          { before, after } when the player's level differs
function Compare.Between(before, after)
    local was, is = ns.Summary.Of(before), ns.Summary.Of(after)

    local function Pair(a, b)
        return { before = a, after = b, change = ns.Change(a, b) }
    end

    -- DPS is compared the way each set is shown, typical where it has a
    -- typical figure, so the arrow agrees with the figures beside it.
    local dpsBefore, typicalBefore = ns.Summary.DpsOf(was)
    local dpsAfter, typicalAfter = ns.Summary.DpsOf(is)
    local dps = Pair(dpsBefore, dpsAfter)
    dps.typicalBefore, dps.typicalAfter = typicalBefore, typicalAfter
    dps.fightsBefore = typicalBefore and was.typical.counted or was.fights
    dps.fightsAfter = typicalAfter and is.typical.counted or is.fights

    local comparison = {
        was = was,
        is = is,
        dps = dps,
        critRate = {
            before = was.critRate,
            after = is.critRate,
            points = was.critRate and is.critRate and (is.critRate - was.critRate) or nil,
        },
        perFight = Pair(
            was.fights > 0 and was.damage / was.fights or nil,
            is.fights > 0 and is.damage / is.fights or nil
        ),
        abilities = {},
    }

    -- Sets differ in length, so abilities are compared by how much damage
    -- a second each one accounted for, not by their totals.
    local earlier = {}
    for _, ability in ipairs(was.abilities) do
        earlier[ability.kind .. ability.id] = was.seconds > 0 and ability.damage / was.seconds
    end
    for _, ability in ipairs(is.abilities) do
        local key = ability.kind .. ability.id
        local now = is.seconds > 0 and ability.damage / is.seconds or nil
        comparison.abilities[key] = Pair(earlier[key] or nil, now)
    end

    local lastBefore, lastAfter = Latest(before), Latest(after)
    local gearThen = lastBefore and ns.Gear.Set(lastBefore.gear)
    local gearNow = lastAfter and ns.Gear.Set(lastAfter.gear)
    comparison.gearKnown = gearThen ~= nil and gearNow ~= nil
    comparison.gear = ns.Gear.Diff(gearThen, gearNow)

    local levelThen = lastBefore and lastBefore.level
    local levelNow = lastAfter and lastAfter.level
    if levelThen and levelNow and levelThen ~= levelNow then
        comparison.levels = { before = levelThen, after = levelNow }
    end

    return comparison
end
