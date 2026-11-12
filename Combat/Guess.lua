local _, ns = ...

-- Works out which ability a blow was.
--
-- The game reports that something hit an enemy, or missed it, and what
-- school of damage it was. It doesn't say what. It does report the
-- player's casts and announces each swing of their weapon, so a blow can
-- usually be traced: to the cast just before it of an ability known to do
-- that kind of damage, or to a swing.
--
-- "Known" is learned by watching. Each time a blow is traced to an
-- ability its school is counted, and the school seen most often is taken
-- as that ability's. One early mistake is soon outvoted.
--
-- Only abilities the game's own tally has shown to do damage are
-- considered, so a buff cast just before a swing isn't taken for the
-- swing. That does mean a brand new ability can't be traced until the
-- fight it's first used in is over.
--
-- It stays a guess. Two things landing at once can be told apart only by
-- their school, so anything built on this says "about" and "probably".
-- It's used for the icon beside a number, for saying whether each cast in
-- a fight landed, and for putting a name to the hardest blows.

local Guess = {}
ns.Guess = Guess

-- How long after a cast its blow can land. Arrows and spells take a
-- moment to fly.
local FLIGHT_SECONDS = 1.6

-- A blow that lands this soon after a cast was that cast: a strike with
-- the weapon lands the instant it's used.
local SAME_MOMENT = 0.15

-- How long after a swing is announced its blow can land.
local SWING_SECONDS = 1.2

-- How long a damage-over-time effect might keep ticking after its cast.
local TICKING_SECONDS = 30

-- An ability seen doing one school this many times isn't going to turn
-- out to be something else.
local SURE_AFTER = 3

local PHYSICAL = 1

-- The spell behind an ordinary melee swing.
Guess.MELEE_SWING = 6603

-- The player's recent casts, oldest first. These are the same tables the
-- fight's log holds (see Hits.lua): { cast = spellID, time = ... }.
local casts = {}

-- Melee swings announced and not yet matched to a blow, as the times they
-- were announced. `swingsAnnounced` records that this client tells us
-- about swings at all, since the rules lean on it.
local swings = {}
local swingsAnnounced = false

--- The school an ability has most often been seen to do, and how many
--- times; nil if it hasn't been seen doing any.
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
    return usual, most
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

--- Takes note of a melee swing being announced.
function Guess.NoteSwing()
    swingsAnnounced = true
    table.insert(swings, GetTime())
end

--- Uses up the oldest swing that's still waiting for its blow.
---@return boolean  true if there was one
local function TakeSwing(now)
    while swings[1] and now - swings[1] > SWING_SECONDS do
        table.remove(swings, 1)
    end
    if swings[1] then
        table.remove(swings, 1)
        return true
    end
    return false
end

--- A cast still waiting for its blow that fits a blow of this school.
---@return table|nil known    one of an ability known for the school
---@return table|nil unknown  one of an ability not yet seen doing any
local function WaitingCasts(school, now)
    local damaging = ns.character.schools
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
    return known, unknown
end

--- The ability whose effect is most likely still ticking, for a blow that
--- no cast or swing explains.
local function StillTicking(school)
    local damaging = ns.character.schools

    for index = #casts, 1, -1 do
        local spell = casts[index].cast
        if damaging[spell] and UsualSchool(spell) == school then
            return spell
        end
    end

    -- Nothing is known for this school. The likeliest culprit is the last
    -- thing cast that we aren't yet sure about, and this is how an effect
    -- that only ever ticks gets its school learned.
    for index = #casts, 1, -1 do
        local spell = casts[index].cast
        if damaging[spell] then
            local _, times = UsualSchool(spell)
            if (times or 0) < SURE_AFTER then
                Learn(spell, school)
                return spell
            end
        end
    end
    return nil
end

--- The ability a blow of this school most likely was.
---@param school number|nil  the blow's school of damage
---@return number|nil spellID  nil when there's no telling; with a pet
---                            out, that may well have been the pet
---@return table|nil cast  the log's entry for the cast it's traced to; nil
---                        for a weapon swing or an effect still ticking
function Guess.Match(school)
    if not school or not ns.character then
        return nil
    end

    local now = GetTime()
    local known, unknown = WaitingCasts(school, now)

    local function Claim(cast)
        cast.matched = true
        Learn(cast.cast, school)
        return cast.cast, cast
    end

    if known then
        return Claim(known)
    end

    if school ~= PHYSICAL then
        -- A spell. An ability we know nothing about that was cast a
        -- moment ago is the obvious candidate.
        if unknown then
            return Claim(unknown)
        end
        return StillTicking(school)
    end

    -- A physical blow: a swing of the weapon, unless something else fits
    -- better. A strike lands the instant it's used.
    if unknown and now - unknown.time <= SAME_MOMENT then
        return Claim(unknown)
    end
    if TakeSwing(now) then
        return Guess.MELEE_SWING
    end

    -- No swing was announced for it. If swings are being announced, it
    -- wasn't one, so an untried ability gets the credit. Failing that it
    -- was most likely a pet.
    if unknown then
        return Claim(unknown)
    end
    if swingsAnnounced and UnitExists("pet") then
        return nil
    end
    return Guess.MELEE_SWING
end
