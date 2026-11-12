local _, ns = ...

-- Puts two recordings side by side.
--
-- "Before" is the one being compared against, "after" the one being looked
-- at. Which was actually recorded first doesn't matter.

local Compare = {}
ns.Compare = Compare

--- What changed between two recordings.
---@param before table  a recording
---@param after table   a recording
---@return table comparison:
---   dps, perFight   each { before, after, change }, where change is a
---                   fraction of before, or nil
---   critRate        { before, after, points }, where points is how far
---                   the rate itself moved: 0.02 from 10% to 12%
---   abilities   by "kind..id": { before, after, change } of damage a second
---   gear        list from Gear.Diff, empty when either has no gear on record
---   levels      { before, after } when the player's level differs, else nil
function Compare.Between(before, after)
    local was, is = ns.Summary.Of(before), ns.Summary.Of(after)

    local function Pair(a, b)
        return { before = a, after = b, change = ns.Change(a, b) }
    end

    local comparison = {
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
        gear = ns.Gear.Diff(before.gear, after.gear),
    }

    -- Recordings differ in length, so abilities are compared by how much
    -- damage a second each one accounted for, not by their totals.
    local earlier = {}
    for _, ability in ipairs(was.abilities) do
        earlier[ability.kind .. ability.id] = was.seconds > 0 and ability.damage / was.seconds
    end
    for _, ability in ipairs(is.abilities) do
        local key = ability.kind .. ability.id
        local now = is.seconds > 0 and ability.damage / is.seconds or nil
        comparison.abilities[key] = Pair(earlier[key] or nil, now)
    end

    if before.level and after.level and before.level ~= after.level then
        comparison.levels = { before = before.level, after = after.level }
    end

    return comparison
end
