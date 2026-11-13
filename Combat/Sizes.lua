local _, ns = ...

-- How hard each blow landed, worked out from threat.
--
-- The game hides the size of a hit from addons. It doesn't hide how much
-- an enemy hates the player, and alone, that figure goes up by the damage
-- of each blow. So the steps in it give the sizes of the blows.
--
-- It's an estimate, and it's built to say nothing sooner than say
-- something wrong:
--
--   The figure is only sent about once a second. Two blows landing close
--   together arrive as one step, and there's no telling how it divides.
--   Those blows are left unsized, and so is the blow after any step that
--   couldn't be explained.
--
--   The blow that kills gets no step at all: a dead enemy hates nobody.
--   It's left unsized too. Guessing it from what's left over would pin
--   every bit of damage we failed to follow on one blow.
--
--   Some classes and stances earn more or less threat than the damage
--   they do. A blow that can be checked (an ability used once, landing
--   once, whose damage the game's tally gives exactly) shows the ratio,
--   which is remembered for the character and used to scale the rest.
--   It starts at one for one and moves a little with each reading, so a
--   single wrong one can't throw everything out.
--
-- Only the player's target is followed. If the game ever starts hiding
-- threat, every reading here comes back empty and nothing is sized.

local Sizes = {}
ns.Sizes = Sizes

-- A step in threat can be announced a moment before the blow that caused
-- it, or up to a second or so after.
local EARLY_SECONDS = 0.05

-- A fight's first blow, and the step it causes, come before the game says
-- the fight has begun.
local LEAD_SECONDS = 2

-- A ratio of damage to threat outside this range isn't a class's threat
-- modifier. It's a sign the two figures weren't measuring the same blow.
local LOWEST_RATIO, HIGHEST_RATIO = 0.6, 1.6

-- How far above an ability's usual blow one blow of it can be and still
-- be believed. Hits vary, and a critical hit is double or so; anything
-- beyond that is two blows mistaken for one.
local HIT_STRETCH = 1.6
local CRIT_STRETCH = 3

-- How much of a new reading of that ratio to believe, against what's been
-- seen before.
local LEARNING_RATE = 0.3

-- Room for rounding when sized blows are held up against the game's tally:
-- a little over the tally is still believed.
local TALLY_MARGIN = 1.05

local IsSecret = issecretvalue or function()
    return false
end

-- Recent steps in the player's threat on their target, oldest first:
-- { time, gain }.
local steps = {}
local lastThreat = 0

-- Steps from before this moment are of no use to the fight in progress.
local keepFrom = 0

--- The player's threat on their target: nil if the game won't say, 0 if
--- they have none.
local function Threat()
    local ok, _, _, _, _, raw = pcall(UnitDetailedThreatSituation, "player", "target")
    if not ok or IsSecret(raw) then
        return nil
    end
    return type(raw) == "number" and raw or 0
end

ns.OnEvent("UNIT_THREAT_LIST_UPDATE", function(unit)
    if IsSecret(unit) or unit ~= "target" then
        return
    end

    local threat = Threat()
    if not threat then
        return
    end

    local now = GetTime()
    if threat > lastThreat then
        table.insert(steps, { time = now, gain = threat - lastThreat })
    end
    lastThreat = threat

    -- Nothing older than a fight's lead-in can matter to the next fight.
    -- (During a fight Begin has already set the cut-off, below.)
    while steps[1] and steps[1].time < keepFrom and steps[1].time < now - LEAD_SECONDS do
        table.remove(steps, 1)
    end
end)

-- A new target starts from wherever its threat already stands, so the
-- first reading on it isn't mistaken for one enormous blow.
ns.OnEvent("PLAYER_TARGET_CHANGED", function()
    lastThreat = Threat() or 0
end)

--- Marks the start of a fight. Steps from the moments just before it are
--- kept: the opening blow comes before the fight is announced.
function Sizes.Begin()
    keepFrom = GetTime() - LEAD_SECONDS
    while steps[1] and steps[1].time < keepFrom do
        table.remove(steps, 1)
    end
end

--- Gives each blow the step it caused, where that's beyond doubt.
---@param blows table  the fight's blows on the target, oldest first:
---                    { time, crit, spell }; each gains a `size`, in
---                    threat, if it could be told
local function Match(blows)
    local nextBlow = 1
    local doubtful = false

    for _, step in ipairs(steps) do
        -- Every blow up to this step that hasn't been explained yet.
        local first = nextBlow
        while blows[nextBlow] and blows[nextBlow].time <= step.time + EARLY_SECONDS do
            nextBlow = nextBlow + 1
        end
        local explained = nextBlow - first

        if explained == 1 and not doubtful then
            blows[first].size = step.gain
        end

        -- A step that didn't belong to exactly one blow means something
        -- went unaccounted for (threat with no blow behind it, or two
        -- blows we couldn't split), so the next step may be carrying more
        -- than it seems to.
        doubtful = explained ~= 1
    end
end

--- How many of the fight's blows were traced to each ability.
local function BlowsBySpell(blows)
    local counts = {}
    for _, blow in ipairs(blows) do
        if blow.spell then
            counts[blow.spell] = (counts[blow.spell] or 0) + 1
        end
    end
    return counts
end

--- How this fight's damage compares with its threat, from a blow that can
--- be checked: an ability used once that landed once, so the game's tally
--- for it is the damage of that one blow.
---@return number|nil ratio  damage for each point of threat
local function CheckedRatio(blows, spells)
    local counts = BlowsBySpell(blows)

    local best, bestDamage
    for _, spell in ipairs(spells) do
        local once = spell.kind == "skill" and spell.casts == 1 and counts[spell.id] == 1

        -- The bigger the blow, the less a point of rounding matters.
        if once and (not bestDamage or spell.damage > bestDamage) then
            for _, blow in ipairs(blows) do
                if blow.spell == spell.id and blow.size and blow.size > 0 then
                    best, bestDamage = spell.damage / blow.size, spell.damage
                end
            end
        end
    end

    if best and best >= LOWEST_RATIO and best <= HIGHEST_RATIO then
        return best
    end
    return nil
end

--- Sizes a finished fight's blows and sums up what was learned.
---@param blows table  from Hits.Finish: blows on the target, oldest first
---@param fight table  the fight being saved; needs damage and spells
---@return table|nil sizes:
---   hits, total            ordinary hits that could be sized, and their sum
---   crits, critTotal       the same for critical hits
---   biggest, biggestSpell  the hardest hit of either kind, and what it
---                          probably was
---   biggestCrit, biggestCritSpell
--- nil if nothing could be sized, or the figures didn't hold together.
function Sizes.Finish(blows, fight)
    if #steps == 0 or #blows == 0 or not ns.character then
        return nil
    end
    Match(blows)

    -- Settle how damage compares with threat for this character, leaning
    -- on what earlier fights showed and nudged by this one if it can say.
    local character = ns.character
    local checked = CheckedRatio(blows, fight.spells)
    if checked then
        local known = character.threatRatio or 1
        character.threatRatio = known + (checked - known) * LEARNING_RATE
    end
    local ratio = character.threatRatio or 1

    -- What the game's tally says each ability did in all. No one blow of
    -- an ability can have done more than that.
    local totals = {}
    for _, spell in ipairs(fight.spells) do
        if spell.kind ~= "pet" then
            totals[spell.id] = (totals[spell.id] or 0) + spell.damage
        end
    end

    local counts = BlowsBySpell(blows)

    --- The most one blow of an ability could plausibly have done: a good
    --- deal more than its usual blow, and more again for a critical hit,
    --- but never more than everything that ability did.
    local function Ceiling(blow)
        local total = blow.spell and totals[blow.spell]
        if not total then
            return nil
        end
        local usual = total / (counts[blow.spell] or 1)
        local stretch = blow.crit and CRIT_STRETCH or HIT_STRETCH
        return math.min(usual * stretch, total * TALLY_MARGIN) + 1
    end

    local sizes = { hits = 0, total = 0, crits = 0, critTotal = 0 }
    for _, blow in ipairs(blows) do
        local damage = blow.size and math.floor(blow.size * ratio + 0.5)
        local most = Ceiling(blow)

        if damage and not (most and damage > most) then
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

    -- The blows we sized can't add up to more than the whole fight, and
    -- no one of them to more than everything. If they seem to, threat was
    -- measuring something else and none of it can be trusted.
    local sized = sizes.total + sizes.critTotal
    if not sizes.biggest or sized > fight.damage * TALLY_MARGIN + 2 then
        return nil
    end
    return sizes
end
