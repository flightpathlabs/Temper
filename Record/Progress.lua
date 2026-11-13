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

-- The bests page has room for this many. They're listed most telling
-- first, so cutting the list short loses the least.
local MOST_BESTS = 4

-- A fight where this much of the damage came from items and other effects
-- wasn't won by the character's own abilities. Set high, because some
-- abilities do their damage through an effect the game files separately.
local MOSTLY_NOT_OURS = 0.5

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
        return "Most of the damage came from an item or some other effect, not your abilities."
    end
    return nil
end

--- Marks a fight to be left out of bests and trends, or puts it back.
function Progress.SetIgnored(fight, ignored)
    fight.ignored = ignored or nil
    ns.Publish("FIGHTS_CHANGED")
end

--- The character's fights by day, oldest first, for the last days that
--- had any. Each day's DPS is its typical one (see Summary.Typical), so a
--- day isn't made by one lucky fight or a run of critters. A day of
--- nothing but easy fights has no typical figure and is left out.
---@return table  list of { day = "12 Nov", fights, seconds, level, and
---               dps, how, left from Summary.Typical }; fights and
---               seconds are of the fights that count, easy ones included
function Progress.ByDay()
    local days, byKey = {}, {}

    for _, fight in ipairs(ns.character.fights) do
        if not Progress.WhyNotCounted(fight) then
            local key = date("%Y%m%d", fight.at)
            local day = byKey[key]
            if not day then
                day = { day = date("%d %b", fight.at), fights = 0, seconds = 0, list = {} }
                byKey[key] = day
                table.insert(days, day)
            end

            day.fights = day.fights + 1
            day.seconds = day.seconds + fight.length
            day.level = fight.level or day.level
            table.insert(day.list, fight)
        end
    end

    local shown = {}
    for _, day in ipairs(days) do
        local typical = ns.Summary.Typical(day.list)
        day.list = nil
        if typical.dps then
            day.dps, day.how, day.left = typical.dps, typical.how, typical.left
            table.insert(shown, day)
        end
    end
    while #shown > MOST_DAYS do
        table.remove(shown, 1)
    end
    return shown
end

--- The character's bests among the fights that count.
---@return table  list of { title, value, detail, fight }, in a fixed order;
---               empty until there's a fight that counts
function Progress.Bests()
    local fastest, biggest, hardest, hardestFight, sharpest
    local hardestHit, hardestCrit

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

            local sizes = fight.sizes
            if sizes and sizes.biggest then
                if not hardestHit or sizes.biggest > hardestHit.sizes.biggest then
                    hardestHit = fight
                end
                local crit = sizes.biggestCrit
                if crit and (not hardestCrit or crit > hardestCrit.sizes.biggestCrit) then
                    hardestCrit = fight
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
        local detail = ("%s, %s"):format(ns.FightTitle(fight, "A fight"), date("%d %b", fight.at))
        if fight.level then
            detail = ("%s, level %d"):format(detail, fight.level)
        end
        table.insert(bests, { title = title, value = value, detail = detail, fight = fight })
    end

    if fastest then
        Add("Highest DPS", ns.Rate(fastest.damage / fastest.length), fastest)
    end
    -- Sizes of single blows are worked out, not read, so they say "about".
    local function Blow(size, spell)
        local name = spell and ns.Sources.Name(spell)
        if name then
            return ("About %s with %s"):format(ns.Number(size), name)
        end
        return "About " .. ns.Number(size)
    end
    if hardestCrit then
        local sizes = hardestCrit.sizes
        Add("Biggest critical hit", Blow(sizes.biggestCrit, sizes.biggestCritSpell), hardestCrit)
    end
    if hardestHit and hardestHit ~= hardestCrit then
        local sizes = hardestHit.sizes
        Add("Biggest hit", Blow(sizes.biggest, sizes.biggestSpell), hardestHit)
    end

    -- The hardest single use of an ability stands in for the biggest hit
    -- when no blow could be sized. With a biggest hit to show, it would
    -- only say much the same thing twice.
    if hardest and not hardestHit then
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

    while #bests > MOST_BESTS do
        table.remove(bests)
    end
    return bests
end
