local _, ns = ...

-- Every blow that lands on the player's target, as it happens.
--
-- Forever closes the combat log to addons. What it still reports, for any
-- unit on screen, is that something struck it: whether that was a hit or a
-- miss, whether it was critical, and which school of damage it was. The
-- amount arrives too, but as a value we may put on screen and nothing
-- else. It can't be read, compared, added up or saved.
--
-- The event doesn't say who struck the blow. Alone, it can only have been
-- the player or their pet, which is why Temper keeps to solo play.
--
-- This file passes each blow on for the lane to draw, and keeps count of
-- hits, crits and casts for the fight record.

local Hits = {}
ns.Hits = Hits

-- A fight is only announced after its first blow has been reported, so
-- the counts reach back this far before the announcement.
local LEAD_SECONDS = 2

-- A last tick of damage can be reported just after a fight is called
-- over. Anything this soon after one fight isn't the start of the next.
local STRAGGLER_SECONDS = 0.75

-- A wound that arrives with one of these did no damage at all: the whole
-- blow was soaked up. (A blow that's only partly blocked says so with a
-- flag of its own.) The amount would settle it, but we can't read that.
local SOAKED = {
    ABSORB = true,
    BLOCK = true,
    RESIST = true,
}

-- Ways an attack can fail to hurt. Anything else the event reports about
-- the target (heals, energy gains) isn't ours to count.
local AVOIDED = {
    MISS = true,
    DODGE = true,
    PARRY = true,
    BLOCK = true,
    RESIST = true,
    ABSORB = true,
    IMMUNE = true,
    DEFLECT = true,
    REFLECT = true,
    EVADE = true,
}

local IsSecret = issecretvalue or function()
    return false
end

-- What has happened since the last fight ended, oldest first. Each entry
-- holds only what we're allowed to keep.
local log = {}
local fighting = false

-- When the last fight was counted up.
local lastFinish = 0

local function Remember(entry)
    entry.time = GetTime()
    table.insert(log, entry)

    -- Between fights, only the last couple of seconds can matter.
    if not fighting then
        while log[1] and log[1].time < entry.time - LEAD_SECONDS do
            table.remove(log, 1)
        end
    end
end

ns.OnEvent("UNIT_COMBAT", function(unit, action, flag, amount, school)
    if IsSecret(unit) or unit ~= "target" then
        return
    end
    if IsSecret(action) or IsSecret(flag) then
        return
    end

    -- Blows landing on a friend the player happens to have targeted are
    -- somebody else's doing.
    local hostile = UnitCanAttack("player", "target")
    if not IsSecret(hostile) and not hostile then
        return
    end

    local hit = { action = action, flag = flag }
    if not IsSecret(school) then
        hit.school = school
    end

    if action == "WOUND" and SOAKED[flag] then
        hit.avoided = flag
    elseif action == "WOUND" then
        hit.amount = amount
        hit.crit = flag == "CRITICAL"
        hit.glancing = flag == "GLANCING"
    elseif AVOIDED[action] then
        hit.avoided = action
    else
        return
    end

    if hit.avoided then
        Remember({ avoided = true })
    else
        Remember({ hit = true, crit = hit.crit, glancing = hit.glancing })
    end

    ns.Publish("TARGET_HIT", hit)
end)

-- The player's own casts, and their pet's. A cast is the one thing about
-- an ability we can count exactly, which makes damage per cast the fairest
-- way to compare an ability between two fights.
ns.OnEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if IsSecret(unit) or IsSecret(spellID) then
        return
    end
    if unit == "player" or unit == "pet" then
        Remember({ cast = spellID })
    end
end)

--- Marks the start of a fight, so the log stops forgetting.
function Hits.Begin()
    fighting = true
end

--- Counts up a fight and clears the log for the next one.
---@param startTime number  when the fight began, on GetTime's clock
---@return table tally  { hits, crits, glancing, avoided }
---@return table casts  times each spell was cast, by spell ID
function Hits.Finish(startTime)
    local tally = { hits = 0, crits = 0, glancing = 0, avoided = 0 }
    local casts = {}

    local earliest = math.max(startTime - LEAD_SECONDS, lastFinish + STRAGGLER_SECONDS)
    for _, entry in ipairs(log) do
        if entry.time >= earliest then
            if entry.cast then
                casts[entry.cast] = (casts[entry.cast] or 0) + 1
            elseif entry.avoided then
                tally.avoided = tally.avoided + 1
            elseif entry.hit then
                tally.hits = tally.hits + 1
                if entry.crit then
                    tally.crits = tally.crits + 1
                end
                if entry.glancing then
                    tally.glancing = tally.glancing + 1
                end
            end
        end
    end

    log = {}
    fighting = false
    lastFinish = GetTime()
    return tally, casts
end
