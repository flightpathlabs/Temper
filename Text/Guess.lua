local _, ns = ...

-- Guesses which ability a hit was, for the icon beside its number.
--
-- The game reports that something hit the target and what school of
-- damage it was. It doesn't say what. It does report the player's casts,
-- so a hit can usually be traced to one: the cast just before it, of an
-- ability known to do that kind of damage.
--
-- "Known" is learned by watching. Each time a hit follows a cast, the pair
-- is noted, and after a few fights the common pairing wins out over the
-- odd coincidence. Only abilities the game's own tally has shown to do
-- damage are considered, so a buff cast just before a swing isn't taken
-- for the swing. That does mean a brand new ability gets no icon until
-- the fight it's first used in is over.
--
-- It stays a guess: two things landing at once can be told apart only by
-- their school.

local Guess = {}
ns.Guess = Guess

-- How long after a cast its hit can land. Arrows and spells take a moment
-- to fly.
local FLIGHT_SECONDS = 1.6

-- How long a damage-over-time effect might keep ticking after its cast.
local TICKING_SECONDS = 30

local PHYSICAL = 1
local AUTO_ATTACK = 6603

-- The player's recent casts, oldest first: { spell, time, matched }.
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

ns.Subscribe("PLAYER_CAST", function(spell)
    if not ns.character then
        return
    end

    local now = GetTime()
    table.insert(casts, { spell = spell, time = now })
    while casts[1] and casts[1].time < now - TICKING_SECONDS do
        table.remove(casts, 1)
    end
end)

--- The ability a hit of this school most likely was.
---@param school number|nil  the hit's school of damage
---@return number|nil spellID
function Guess.For(school)
    if not school or not ns.character then
        return nil
    end
    local now = GetTime()

    -- A cast still waiting for its hit, of an ability known for this
    -- school. Failing that, one we know nothing about yet: this hit is
    -- how we find out.
    local known, unknown
    local damaging = ns.character.schools
    for _, cast in ipairs(casts) do
        local waiting = not cast.matched and now - cast.time <= FLIGHT_SECONDS
        if waiting and damaging[cast.spell] then
            local usual = UsualSchool(cast.spell)
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
        Learn(cast.spell, school)
        return cast.spell
    end

    -- Nothing was cast for it. A physical blow is the weapon swinging.
    if school == PHYSICAL then
        return AUTO_ATTACK
    end

    -- Anything else is an effect still ticking: the most recent cast of
    -- something known for this school.
    for index = #casts, 1, -1 do
        if damaging[casts[index].spell] and UsualSchool(casts[index].spell) == school then
            return casts[index].spell
        end
    end
    return nil
end
