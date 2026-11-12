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

    local comparison = {
        was = was,
        is = is,
        dps = Pair(was.dps, is.dps),
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

    local then_, now = Latest(before), Latest(after)
    local gearThen = then_ and ns.Gear.Set(then_.gear)
    local gearNow = now and ns.Gear.Set(now.gear)
    comparison.gearKnown = gearThen ~= nil and gearNow ~= nil
    comparison.gear = ns.Gear.Diff(gearThen, gearNow)

    if then_ and now and then_.level and now.level and then_.level ~= now.level then
        comparison.levels = { before = then_.level, after = now.level }
    end

    return comparison
end
