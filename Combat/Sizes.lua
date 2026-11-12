local _, ns = ...

-- How hard each blow landed, worked out from threat.
--
-- The game hides the size of a hit from addons. It doesn't hide how much
-- an enemy hates the player, and alone, that figure goes up by the damage
-- of each blow. So the steps in it give the sizes of the blows.
--
-- It's an estimate, for three reasons, and everything built on it says
-- "about":
--
--   The figure is only sent about once a second. Two blows landing close
--   together arrive as one step, and there's no telling how it divides.
--   Those blows are left unsized.
--
--   The blow that kills gets no step at all: a dead enemy hates nobody.
--   When it's the only blow unaccounted for, it's the fight's total less
--   everything else.
--
--   Some classes and stances earn more or less threat than the damage
--   they do. Each fight is checked against something known for certain (a
--   skill used once, whose damage the game's tally gives exactly), and
--   the sizes are scaled to agree, or thrown away if they can't be made to.
--
-- Only the player's target is followed. If the game ever starts hiding
-- threat, every reading here comes back empty and nothing is sized.

local Sizes = {}
ns.Sizes = Sizes

-- A step in threat can be announced a moment before the blow that caused
-- it, or up to a second or so after.
local EARLY_SECONDS = 0.25

-- How far a fight's threat may disagree with its damage before the two
-- are taken to be measuring different things.
local LOOSEST_SCALE, TIGHTEST_SCALE = 0.5, 2

local IsSecret = issecretvalue or function()
    return false
end

-- Steps in the player's threat on their target during this fight, oldest
-- first: { time, gain }.
local steps = {}
local lastThreat

--- The player's threat on their target, or nil if there's none or the
--- game won't say.
local function Threat()
    local ok, _, _, _, _, raw = pcall(UnitDetailedThreatSituation, "player", "target")
    if not ok or IsSecret(raw) or type(raw) ~= "number" then
        return nil
    end
    return raw
end

ns.OnEvent("UNIT_THREAT_LIST_UPDATE", function(unit)
    if IsSecret(unit) or unit ~= "target" then
        return
    end

    local threat = Threat()
    if threat and lastThreat and threat > lastThreat then
        table.insert(steps, { time = GetTime(), gain = threat - lastThreat })
    end
    lastThreat = threat
end)

-- A new target starts from wherever its threat already stands, so the
-- first reading on it isn't mistaken for one enormous blow.
ns.OnEvent("PLAYER_TARGET_CHANGED", function()
    lastThreat = Threat()
end)

--- Forgets the steps, ready for the next fight.
function Sizes.Begin()
    steps = {}
    lastThreat = Threat() or 0
end

--- Gives each blow the step it caused, where that's clear.
---@param blows table  the fight's blows on the target, oldest first:
---                    { time, crit, spell }; each gains a `size` if it
---                    could be told
---@return number sized  how much threat was matched to single blows
---@return number gained  how much threat was gained in all
local function Match(blows)
    local sized, gained = 0, 0
    local nextBlow = 1

    for _, step in ipairs(steps) do
        gained = gained + step.gain

        -- Every blow up to this step that hasn't been explained yet.
        local first = nextBlow
        while blows[nextBlow] and blows[nextBlow].time <= step.time + EARLY_SECONDS do
            nextBlow = nextBlow + 1
        end

        if nextBlow - first == 1 then
            blows[first].size = step.gain
            sized = sized + step.gain
        end
    end

    return sized, gained, nextBlow
end

--- How threat compares with damage in this fight, from a skill used once:
--- the game's tally says exactly what it did, and if its blow was sized
--- we have the same thing in threat.
---@return number|nil scale  damage for each point of threat
local function ScaleFrom(blows, spells)
    local once = {}
    for _, spell in ipairs(spells) do
        if spell.kind == "skill" and spell.casts == 1 then
            once[spell.id] = spell.damage
        end
    end

    for _, blow in ipairs(blows) do
        local damage = blow.size and once[blow.spell]
        if damage and blow.size > 0 then
            return damage / blow.size
        end
    end
    return nil
end

--- Sizes a finished fight's blows and sums up what was learned.
---@param blows table  from Hits.Finish: blows on the target, oldest first
---@param fight table  the fight being saved; needs damage, spells, enemies
---@return table|nil sizes:
---   hits, total            ordinary hits that could be sized, and their sum
---   crits, critTotal       the same for critical hits
---   biggest, biggestSpell  the hardest hit of either kind, and what it
---                          probably was
---   biggestCrit, biggestCritSpell
--- nil if nothing could be sized, or the figures didn't hold together.
function Sizes.Finish(blows, fight)
    if #steps == 0 or #blows == 0 then
        return nil
    end

    local _, gained, nextBlow = Match(blows)

    -- Threat and damage only measure the same thing if all of the damage
    -- went into the one enemy being watched.
    local oneEnemy = fight.enemies and #fight.enemies == 1
    local hasPet = false
    for _, spell in ipairs(fight.spells) do
        hasPet = hasPet or spell.kind == "pet"
    end

    local scale = ScaleFrom(blows, fight.spells) or 1
    if scale < LOOSEST_SCALE or scale > TIGHTEST_SCALE then
        return nil
    end

    -- The killing blow: the one blow after the last step, when everything
    -- else is accounted for.
    local unexplained = #blows - nextBlow + 1
    if oneEnemy and not hasPet and unexplained == 1 then
        local rest = fight.damage - gained * scale
        if rest > 0 then
            blows[#blows].size = rest / scale
        end
    end

    local sizes = { hits = 0, total = 0, crits = 0, critTotal = 0 }
    for _, blow in ipairs(blows) do
        if blow.size then
            local damage = math.floor(blow.size * scale + 0.5)

            if blow.crit then
                sizes.crits = sizes.crits + 1
                sizes.critTotal = sizes.critTotal + damage
                if not sizes.biggestCrit or damage > sizes.biggestCrit then
                    sizes.biggestCrit, sizes.biggestCritSpell = damage, blow.spell
                end
            else
                sizes.hits = sizes.hits + 1
                sizes.total = sizes.total + damage
            end

            if not sizes.biggest or damage > sizes.biggest then
                sizes.biggest, sizes.biggestSpell = damage, blow.spell
            end
        end
    end

    -- No single blow can have done more than the whole fight. If one
    -- seems to have, the threat was measuring something else.
    if not sizes.biggest or sizes.biggest > fight.damage + 1 then
        return nil
    end
    return sizes
end
