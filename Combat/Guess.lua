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
-- Effects that tick (a bleed, a damage-over-time spell) are the hardest.
-- A tick arrives long after its cast with nothing to mark it out. A spell's
-- tick has its school to go on. A bleed is physical, like a swing, so it's
-- told from one by there being no swing on its way when it lands. An
-- ability seen ticking like that is remembered as one that ticks. A tick
-- that can't be put to any ability is still known for a tick, and is
-- shown as one rather than passed off as a swing.
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

-- What a blow is put down to when it was plainly a tick of something, but
-- of what can't be told. Not a spell: nothing should look it up as one.
Guess.TICK = "TICK"

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

--- The abilities seen ticking, by spell, as how many ticks were put down
--- to each. Kept with the character, since it doesn't change.
local function Ticking()
    local character = ns.character
    if type(character.ticking) ~= "table" then
        character.ticking = {}
    end
    return character.ticking
end

-- An ability is taken to tick once it's been seen doing so this often.
-- Once could be a mistake, and would stick: from then on it isn't allowed
-- to claim a blow that comes a little after its cast.
local TICKS_AFTER = 2

local function Ticks(spell)
    return (Ticking()[spell] or 0) >= TICKS_AFTER
end

-- The last blow traced to a cast, so that the other enemies caught by
-- the same strike (Cleave, Whirlwind, Swipe) can be put down to it too.
local lastClaim = { time = 0 }

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

--- Takes note of a weapon swing being announced.
---@param ranged boolean  a shot, which arrives as a cast of its own and
---                       needs no place in the queue of swings
function Guess.NoteSwing(ranged)
    swingsAnnounced = true
    if not ranged then
        table.insert(swings, GetTime())
    end
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
---@return table|nil unknown  one of an ability we aren't yet sure about
local function WaitingCasts(school, now)
    local damaging = ns.character.schools
    local known, unknown

    for _, cast in ipairs(casts) do
        -- An ability that only ticks has no blow of its own on the way.
        -- Left in, its cast would claim the next swing that came along.
        local age = now - cast.time
        local flying = age <= (Ticks(cast.cast) and SAME_MOMENT or FLIGHT_SECONDS)
        if not cast.matched and flying and damaging[cast.cast] then
            local usual, times = UsualSchool(cast.cast)
            if usual == school then
                -- Of two that fit, one used this very moment is likelier
                -- than one that's been in the air a while.
                if not known or now - cast.time <= SAME_MOMENT then
                    known = cast
                end
            elseif (times or 0) < SURE_AFTER then
                -- Seen doing something else, but not often enough to be
                -- sure of. It stays a candidate, so that one early
                -- mistake can be outvoted.
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
    -- thing cast that has never been seen doing damage of any kind, and
    -- this is how an effect that only ever ticks gets its school learned.
    -- An ability already seen doing something else is left alone: its
    -- own blows will settle what it is.
    for index = #casts, 1, -1 do
        local spell = casts[index].cast
        if damaging[spell] and UsualSchool(spell) == nil then
            Learn(spell, school)
            return spell
        end
    end
    return nil
end

--- The physical ability most likely still ticking, for a blow that came
--- with no swing and no cast to explain it. One already seen ticking is
--- the first choice. Failing that, the last physical ability cast that
--- hasn't been seen to land a blow of its own yet, which is how a bleed
--- gets found out the first time.
local function StillBleeding(now)
    local ticking = Ticking()

    for index = #casts, 1, -1 do
        local spell = casts[index].cast
        if Ticks(spell) and now - casts[index].time <= TICKING_SECONDS then
            ticking[spell] = ticking[spell] + 1
            return spell
        end
    end

    for index = #casts, 1, -1 do
        local cast = casts[index]
        local usual = UsualSchool(cast.cast)
        local physical = usual == nil or usual == PHYSICAL
        local recent = now - cast.time <= TICKING_SECONDS
        if recent and not cast.matched and physical and ns.character.schools[cast.cast] then
            ticking[cast.cast] = (ticking[cast.cast] or 0) + 1
            Learn(cast.cast, PHYSICAL)
            return cast.cast
        end
    end
    return nil
end

--- The ability a blow of this school most likely was.
---@param school number|nil  the blow's school of damage
---@return number|string|nil spellID  nil when there's no telling; with a
---                            pet out, that may well have been the pet.
---                            Guess.TICK when it was plainly a tick of
---                            something, but of what can't be said
---@return table|nil cast  the log's entry for the cast it's traced to; nil
---                        for a weapon swing or an effect still ticking
---@return boolean|nil tick  true when it was a tick of something over time
function Guess.Match(school)
    if not school or not ns.character then
        return nil
    end

    local now = GetTime()
    local known, unknown = WaitingCasts(school, now)

    local function Claim(cast)
        cast.matched = true
        Learn(cast.cast, school)
        lastClaim.spell, lastClaim.time = cast.cast, now
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
        local ticking = StillTicking(school)
        -- Only a tick if something was found still ticking. A spell
        -- nothing explains is just an untraced blow.
        return ticking, nil, ticking ~= nil
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
    -- wasn't one, so an untried ability gets the credit. Failing that, a
    -- bleed still running, and failing that, a pet.
    if unknown then
        return Claim(unknown)
    end
    if not swingsAnnounced then
        return Guess.MELEE_SWING
    end

    -- Another enemy caught by the strike that's just landed.
    if now - lastClaim.time <= SAME_MOMENT then
        return lastClaim.spell
    end

    -- With a pet out, a blow nothing explains is far likelier to be the
    -- pet's than a bleed's. Taking it for a bleed would also teach a
    -- spell that's yet to tick (a Serpent Sting, say) that it bleeds.
    if UnitExists("pet") then
        return nil
    end

    return StillBleeding(now) or Guess.TICK, nil, true
end
