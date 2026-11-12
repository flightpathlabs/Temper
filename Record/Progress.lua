local _, ns = ...

-- How the character is coming along, measured only against themselves.
--
-- Two views of the same fights: day by day, to see the trend, and the best
-- of them, to have something to beat. A fight can be a fluke (a barrel of
-- explosives, a quest item that does the work), so some are left out by
-- rule and any can be left out by hand.

local Progress = {}
ns.Progress = Progress

-- A fight shorter than this is over before it means anything.
local SHORTEST_COUNTED = 6

-- A fight where this much of the damage came from items and other effects
-- wasn't won by the character's own skills.
local MOSTLY_NOT_OURS = 0.25

local MOST_DAYS = 14

--- Why a fight doesn't count towards bests and trends, or nil if it does.
---@return string|nil reason  fit to show the player
function Progress.WhyNotCounted(fight)
    if fight.ignored then
        return "You asked for this one to be left out."
    end
    if fight.length < SHORTEST_COUNTED then
        return "Too short to mean much."
    end

    local other = 0
    for _, spell in ipairs(fight.spells or {}) do
        if spell.kind == "other" then
            other = other + spell.damage
        end
    end
    if fight.damage > 0 and other / fight.damage >= MOSTLY_NOT_OURS then
        return "Much of the damage came from an item or some other effect, not your skills."
    end
    return nil
end

--- Marks a fight to be left out of bests and trends, or puts it back.
function Progress.SetIgnored(fight, ignored)
    fight.ignored = ignored or nil
    ns.Publish("FIGHTS_CHANGED")
end

--- The character's fights by day, oldest first, for the last days that
--- had any.
---@return table  list of { day = "12 Nov", fights, seconds, dps, level }
function Progress.ByDay()
    local days, byKey = {}, {}

    for _, fight in ipairs(ns.character.fights) do
        if not Progress.WhyNotCounted(fight) then
            local key = date("%Y%m%d", fight.at)
            local day = byKey[key]
            if not day then
                day = { day = date("%d %b", fight.at), fights = 0, damage = 0, seconds = 0 }
                byKey[key] = day
                table.insert(days, day)
            end

            day.fights = day.fights + 1
            day.damage = day.damage + fight.damage
            day.seconds = day.seconds + fight.length
            day.level = fight.level or day.level
        end
    end

    for _, day in ipairs(days) do
        day.dps = day.damage / day.seconds
    end
    while #days > MOST_DAYS do
        table.remove(days, 1)
    end
    return days
end

--- The character's bests among the fights that count.
---@return table  list of { title, value, detail, fight }, in a fixed order;
---               empty until there's a fight that counts
function Progress.Bests()
    local fastest, biggest, hardest, hardestFight, sharpest

    for _, fight in ipairs(ns.character.fights) do
        if not Progress.WhyNotCounted(fight) then
            if not fastest or fight.damage / fight.length > fastest.damage / fastest.length then
                fastest = fight
            end
            if not biggest or fight.damage > biggest.damage then
                biggest = fight
            end

            -- Crit rate only means something over a fair number of hits.
            if (fight.hits or 0) >= 8 then
                local rate = fight.crits / fight.hits
                if not sharpest or rate > sharpest.crits / sharpest.hits then
                    sharpest = fight
                end
            end

            for _, spell in ipairs(fight.spells or {}) do
                local once = spell.kind == "skill" and spell.casts == 1
                if once and (not hardest or spell.damage > hardest.damage) then
                    hardest, hardestFight = spell, fight
                end
            end
        end
    end

    local bests = {}
    local function Add(title, value, fight)
        local detail = ("%s, %s"):format(fight.target or "A fight", date("%d %b", fight.at))
        if fight.level then
            detail = ("%s, level %d"):format(detail, fight.level)
        end
        table.insert(bests, { title = title, value = value, detail = detail, fight = fight })
    end

    if fastest then
        Add("Most damage a second", ns.Rate(fastest.damage / fastest.length), fastest)
    end
    if hardest then
        Add(
            "Hardest single use",
            ("%s with %s"):format(ns.Number(hardest.damage), hardest.name),
            hardestFight
        )
    end
    if biggest then
        Add("Most damage in a fight", ns.Number(biggest.damage), biggest)
    end
    if sharpest and sharpest.crits > 0 then
        Add("Most critical hits", ns.Percent(sharpest.crits / sharpest.hits), sharpest)
    end
    return bests
end
