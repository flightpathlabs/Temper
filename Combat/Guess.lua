local _, ns = ...

-- Works out which ability a blow was.
--
-- The game reports that something hit an enemy, or missed it, and what
-- school of damage it was. It doesn't say what. It does report the
-- player's casts, so a blow can usually be traced to one: the cast just
-- before it, of an ability known to do that kind of damage.
--
-- "Known" is learned by watching. Each time a blow follows a cast, the
-- pair is noted, and after a few fights the common pairing wins out over
-- the odd coincidence. Only abilities the game's own tally has shown to do
-- damage are considered, so a buff cast just before a swing isn't taken
-- for the swing. That does mean a brand new ability can't be matched until
-- the fight it's first used in is over.
--
-- It stays a guess. Two things landing at once can be told apart only by
-- their school, so anything built on this says "about" and "probably".
-- It's used for the icon beside a number, and for saying whether each
-- cast in a fight landed.

local Guess = {}
ns.Guess = Guess

-- How long after a cast its blow can land. Arrows and spells take a
-- moment to fly.
local FLIGHT_SECONDS = 1.6

-- How long a damage-over-time effect might keep ticking after its cast.
local TICKING_SECONDS = 30

local PHYSICAL = 1

-- The spell behind an ordinary melee swing.
Guess.MELEE_SWING = 6603

-- The player's recent casts, oldest first. These are the same tables the
-- fight's log holds (see Hits.lua): { cast = spellID, time = ... }.
local casts = {}

--- The school an ability has most often been seen to do, or nil.
local function UsualSchool(spell)
    local seen = ns.character.schools[spell]
    if not seen then
        return nil
    end

    local usual, most = nil, 0
    for school, times in pairs(seen) do
        if times > most then
            usual, most = school, times
        end
    end
    return usual
end

local function Learn(spell, school)
    local seen = ns.character.schools[spell]
    seen[school] = (seen[school] or 0) + 1
end

--- Takes note of the abilities a finished fight showed doing damage.
---@param spells table  the fight's spell rows
function Guess.NoteDamaging(spells)
    local schools = ns.character.schools
    for _, spell in ipairs(spells or {}) do
        if spell.id ~= 0 and spell.kind ~= "pet" then
            schools[spell.id] = schools[spell.id] or {}
        end
    end
end

--- Takes note of a cast, so a later blow can be traced to it.
---@param cast table  the log's entry for it: { cast = spellID, time = ... }
function Guess.NoteCast(cast)
    table.insert(casts, cast)
    while casts[1] and casts[1].time < cast.time - TICKING_SECONDS do
        table.remove(casts, 1)
    end
end

--- The ability a blow of this school most likely was.
---@param school number|nil  the blow's school of damage
---@return number|nil spellID
---@return table|nil cast  the log's entry for the cast it's traced to; nil
---                        for a weapon swing or an effect still ticking
function Guess.Match(school)
    if not school or not ns.character then
        return nil
    end
    local now = GetTime()
    local damaging = ns.character.schools

    -- A cast still waiting for its blow, of an ability known for this
    -- school. Failing that, one we know nothing about yet: this blow is
    -- how we find out.
    local known, unknown
    for _, cast in ipairs(casts) do
        local waiting = not cast.matched and now - cast.time <= FLIGHT_SECONDS
        if waiting and damaging[cast.cast] then
            local usual = UsualSchool(cast.cast)
            if usual == school then
                known = known or cast
            elseif usual == nil then
                unknown = unknown or cast
            end
        end
    end

    local cast = known or unknown
    if cast then
        cast.matched = true
        Learn(cast.cast, school)
        return cast.cast, cast
    end

    -- Nothing was cast for it. A physical blow is the weapon swinging.
    if school == PHYSICAL then
        return Guess.MELEE_SWING
    end

    -- Anything else is an effect still ticking: the most recent cast of
    -- something known for this school.
    for index = #casts, 1, -1 do
        local spell = casts[index].cast
        if damaging[spell] and UsualSchool(spell) == school then
            return spell
        end
    end
    return nil
end
