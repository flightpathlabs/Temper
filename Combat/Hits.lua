local _, ns = ...

-- Every blow that lands on an enemy the player is fighting, as it happens.
--
-- Forever closes the combat log to addons. What it still reports, for any
-- unit on screen, is that something struck it: whether that was a hit or a
-- miss, whether it was critical, and which school of damage it was. The
-- amount arrives too, but as a value we may put on screen and nothing
-- else. It can't be read, compared, added up or saved.
--
-- The event doesn't say who struck the blow. Alone, it can only have been
-- the player or their pet, which is why Temper keeps to solo play. Even
-- alone there may be strangers fighting nearby, so a blow is only taken
-- as ours if it lands on the player's target or on an enemy that has the
-- player on its threat list.
--
-- This file passes each blow on for the lane to draw, and keeps a log of
-- blows and casts from which a finished fight gets its counts and its
-- timeline.
--
-- The same event reports what lands on the player: heals, enemy attacks
-- that hit or were avoided, and spells. There's no doubt whose those are, so
-- they go straight into the log. They're only ever counted: never drawn,
-- never taken for a blow of the player's own.

local Hits = {}
ns.Hits = Hits

-- A fight is only announced after its first blow has been reported, so
-- the counts reach back this far before the announcement.
local LEAD_SECONDS = 2

-- A last tick of damage can be reported just after a fight is called
-- over. Anything this soon after one fight isn't the start of the next.
local STRAGGLER_SECONDS = 0.75

-- The most a fight's timeline will hold. A long fight keeps its start.
local MAX_TIMELINE = 120

-- Ways an attack can fail to hurt. Anything else the event reports about
-- an enemy (heals, energy gains) isn't ours to count.
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

-- A wound that arrives with one of these did no damage at all: the whole
-- blow was soaked up. (A blow that's only partly blocked says so with a
-- flag of its own.) The amount would settle it, but we can't read that.
local SOAKED = {
    ABSORB = true,
    BLOCK = true,
    RESIST = true,
}

-- The school of an ordinary blow, as the event gives it: a mask of one bit
-- per school, and this is the physical one (Enum.Damageclass.MaskPhysical).
local PHYSICAL = 1

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
    return entry
end

-- What lands on the player -------------------------------------------------

--- Logs a heal or an enemy's attack on the player, as "HEAL", "WOUND",
--- "MAGIC" or the way the attack was avoided. Anything else reported about
--- the player (mana and energy gains, mostly) is let go.
---
--- Only physical blows count as attacks that landed: they're the ones
--- that could have been dodged, parried or blocked. A spell, a tick of
--- damage over time or a Life Tap couldn't, and counting them would make
--- the share avoided look worse than the player's defence really is. They
--- are counted, though, apart and by school, since that's the only way to
--- tell how much of what hurt the player was magic (see Mitigation.lua).
local function NoteOnPlayer(action, flag, school)
    if action == "HEAL" then
        Remember({ onPlayer = "HEAL", crit = flag == "CRITICAL" })
    elseif action == "WOUND" and school ~= nil and school ~= PHYSICAL then
        -- Marked as resisted, a spell may have been turned aside in full or
        -- only in part. The amount would say which, and it can't be read,
        -- so it's counted as a resist and as a spell of its school either way.
        Remember({ onPlayer = "MAGIC", school = school, resisted = flag == "RESIST" })
    elseif action == "WOUND" then
        Remember({
            onPlayer = SOAKED[flag] and flag or "WOUND",
            crit = flag == "CRITICAL",
            crushing = flag == "CRUSHING",
            partBlocked = flag == "BLOCK_REDUCED",
        })
    elseif AVOIDED[action] then
        Remember({ onPlayer = action })
    end
end

-- Whose blow is it? --------------------------------------------------------

--- An answer from the game that may be withheld: the value, or `otherwise`.
local function Plain(value, otherwise)
    if IsSecret(value) then
        return otherwise
    end
    return value
end

local function HasNameplate(unit)
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    return ok and plate ~= nil
end

--- True if a blow reported on this unit should be taken as the player's.
local function IsOurs(unit)
    if type(unit) ~= "string" then
        return false
    end

    -- Blows on a friend the player happens to have targeted are somebody
    -- else's doing. If the game won't say, assume an enemy.
    if not Plain(UnitCanAttack("player", unit), true) then
        return false
    end

    if unit == "target" then
        -- A target with a nameplate has every blow reported twice: here,
        -- and under the nameplate's own name. The nameplate's is the one
        -- to keep, as long as the game will tell us which nameplate is
        -- the target's.
        local canTell = not IsSecret(UnitIsUnit("target", "target"))
        return not (canTell and HasNameplate("target"))
    end

    if unit:sub(1, 9) ~= "nameplate" then
        return false
    end
    if Plain(UnitIsUnit(unit, "target"), false) then
        return true
    end

    -- Any other enemy counts if it has the player on its threat list.
    -- A stranger's fight nearby won't.
    return ns.settings.allEnemies and Plain(UnitThreatSituation("player", unit), nil) ~= nil
end

--- True if a blow on this enemy was plainly somebody else's. Only a blow
--- on the player's target needs asking: any other enemy is only looked at
--- in the first place if it has the player on its threat list (IsOurs).
---
--- The game doesn't say whose a blow was, so this goes by what it does
--- say. An enemy that has neither the player nor their pet on its threat
--- list isn't fighting them, and a blow on it that nothing the player has
--- just done could have landed belongs to whoever is fighting it: a
--- stranger, on an enemy the player has only selected. The opening blow of
--- the player's own pull may come before the game puts them on the list,
--- which is why their own swing or cast just before it keeps it theirs.
--- Once the player is on the list, every blow is taken as theirs, as
--- before: in a fight of their own there's no telling one person's blow
--- from another's.
local function SomebodyElses(unit)
    local mine = Plain(UnitThreatSituation("player", unit), true)
    local pets = UnitExists("pet") and Plain(UnitThreatSituation("pet", unit), true)
    if mine ~= nil or (pets ~= nil and pets ~= false) then
        return false
    end
    return not ns.Guess.ActedJustNow()
end

ns.OnEvent("UNIT_COMBAT", function(unit, action, flag, amount, school)
    if IsSecret(unit) or IsSecret(action) or IsSecret(flag) then
        return
    end

    -- What lands on the player is counted and nothing more.
    if unit == "player" then
        NoteOnPlayer(action, flag, not IsSecret(school) and school or nil)
        return
    end

    if not ns.settings or not IsOurs(unit) then
        return
    end

    local hit = { unit = unit, action = action, flag = flag }
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

    -- Somebody else's, plainly: drawn as such, if at all, and never
    -- counted as the player's or traced to one of their abilities.
    if SomebodyElses(unit) then
        hit.stranger = true
        ns.Publish("TARGET_HIT", hit)
        return
    end

    -- How it went, in one word, for the cast it's traced to.
    local outcome = hit.avoided or (hit.crit and "CRIT") or (hit.glancing and "GLANCE") or "HIT"

    local spell, cast, tick = ns.Guess.Match(hit.school)
    hit.spell = spell
    hit.tick = tick
    if cast then
        cast.result = outcome
    end

    -- A blow with nothing to explain it, when there's a pet out, is the
    -- pet's. It's still drawn, but it isn't the player's to count: a pet
    -- that crits a lot shouldn't flatter its owner's crit rate.
    local fromPet = not spell and hit.school == PHYSICAL
    hit.pet = fromPet

    if fromPet then
        Remember({ pet = true })
    elseif hit.avoided then
        Remember({ avoided = hit.avoided })
    else
        -- A tick that couldn't be put to an ability is drawn as one, but
        -- has no ability to be written down against.
        Remember({
            hit = true,
            crit = hit.crit,
            glancing = hit.glancing,
            spell = spell ~= ns.Guess.TICK and spell or nil,
            onTarget = unit == "target" or Plain(UnitIsUnit(unit, "target"), false),
        })
    end

    -- A swing of the weapon has no cast to hang its outcome on, so it
    -- gets a place in the timeline of its own.
    if spell == ns.Guess.MELEE_SWING and not cast then
        log[#log].swing = outcome
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

    if unit == "player" then
        ns.Guess.NoteCast(Remember({ cast = spellID, mine = true }))
        ns.Publish("PLAYER_CAST", spellID)
    elseif unit == "pet" then
        Remember({ cast = spellID })
    end
end)

-- The game announces each swing of a weapon as it begins. Knowing a swing
-- is on its way is what tells a weapon's blow from an ability's, and
-- knowing that swings are announced at all is what lets a blow with no
-- swing behind it be put down to a pet.
ns.OnEvent("PLAYER_SWING", function(_, swingType)
    if not IsSecret(swingType) then
        ns.Guess.NoteSwing(swingType == Enum.PlayerSwingType.Ranged)
    end
end)

-- The game says so when a skill is pressed without the mana, rage or
-- energy for it. How full those are is hidden, so this is the only sign
-- of running dry there is.
local STARVED = {}
for _, name in ipairs({ "MANA", "RAGE", "ENERGY", "FOCUS" }) do
    local code = _G["LE_GAME_ERR_OUT_OF_" .. name]
    if code then
        STARVED[code] = true
    end
end

ns.OnEvent("UI_ERROR_MESSAGE", function(errorType)
    if fighting and not IsSecret(errorType) and STARVED[errorType] then
        Remember({ starved = true })
    end
end)

-- Counting up -----------------------------------------------------------------

--- How far back a fight's count reaches: a little before it was announced,
--- but never into the tail of the fight before.
local function Earliest(startTime)
    return math.max(startTime - LEAD_SECONDS, lastFinish + STRAGGLER_SECONDS)
end

--- Adds one thing that landed on the player to the count of them.
---@param began number  when the fight was announced
local function CountOnPlayer(defence, entry, began)
    local what = entry.onPlayer

    if what == "HEAL" then
        -- The blow that starts a fight comes before the fight is
        -- announced. A heal that does was topping up between fights, and
        -- the game's own tally of healing leaves it out as well.
        if entry.time >= began then
            defence.heals = defence.heals + 1
            if entry.crit then
                defence.healCrits = defence.healCrits + 1
            end
        end
    elseif what == "WOUND" then
        defence.struck = defence.struck + 1
        if entry.crit then
            defence.crits = defence.crits + 1
        elseif entry.crushing then
            defence.crushing = defence.crushing + 1
        elseif entry.partBlocked then
            defence.partBlocked = defence.partBlocked + 1
        end
    elseif what == "MAGIC" then
        defence.magic = defence.magic + 1
        defence.schools[entry.school] = (defence.schools[entry.school] or 0) + 1
        if entry.resisted then
            defence.resisted = defence.resisted + 1
        end
    else
        defence.avoided = defence.avoided + 1
        defence.avoidedBy[what] = (defence.avoidedBy[what] or 0) + 1
    end
end

--- Counts everything in the log from `earliest` on. Casts are counted
--- from `earliestCast`, which can be sooner: a last tick of damage from
--- the fight before mustn't be counted twice, but a cast made the moment
--- that fight ended belongs to this one.
---@param began number  when the fight was announced, on GetTime's clock
---@return table tally  { hits, crits, glancing, avoided, avoidedBy,
---                     starved, defence }, where avoidedBy counts each way
---                     of missing by the game's word for it (MISS, DODGE,
---                     PARRY and so on) and starved is how often a skill
---                     was pressed without the mana or energy for it.
---                     defence is the other side of the fight: { heals,
---                     healCrits, struck, crits, crushing, partBlocked,
---                     avoided, avoidedBy, magic, schools, resisted }, the
---                     heals that landed on the player and how many were
---                     critical; the enemy blows that landed, how many of
---                     those were critical, crushing or partly blocked, and
---                     the attacks that didn't land; and the spells that hit
---                     the player, counted by school (the event's mask, so
---                     4 is fire), with how many were marked as resisted
---@return table casts  times each spell was cast, by spell ID
local function Count(earliest, earliestCast, began)
    local tally = { hits = 0, crits = 0, glancing = 0, avoided = 0, avoidedBy = {}, starved = 0 }
    local defence = {
        heals = 0,
        healCrits = 0,
        struck = 0,
        crits = 0,
        crushing = 0,
        partBlocked = 0,
        avoided = 0,
        avoidedBy = {},
        magic = 0,
        schools = {},
        resisted = 0,
    }
    local casts = {}
    tally.defence = defence

    for _, entry in ipairs(log) do
        if entry.cast and entry.time >= earliestCast then
            casts[entry.cast] = (casts[entry.cast] or 0) + 1
        end

        -- A pet's blow is in the log but isn't the player's to count.
        if entry.time >= earliest then
            if entry.onPlayer then
                CountOnPlayer(defence, entry, began)
            elseif entry.starved then
                tally.starved = tally.starved + 1
            elseif entry.avoided then
                tally.avoided = tally.avoided + 1
                tally.avoidedBy[entry.avoided] = (tally.avoidedBy[entry.avoided] or 0) + 1
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
    return tally, casts
end

--- What the player did, in order: each cast and each swing of the weapon,
--- with how it went where that could be traced.
---@return table  list of { t = seconds into the fight, id = spell,
---               r = "HIT", "CRIT", "GLANCE", "MISS", "DODGE"... or nil
---               when no blow was traced to it }
local function Timeline(earliest, startTime)
    local timeline = {}

    for _, entry in ipairs(log) do
        if entry.time >= earliest and #timeline < MAX_TIMELINE then
            local t = math.floor((entry.time - startTime) * 10 + 0.5) / 10

            if entry.cast and entry.mine then
                table.insert(timeline, { t = t, id = entry.cast, r = entry.result })
            elseif entry.swing then
                table.insert(timeline, { t = t, id = ns.Guess.MELEE_SWING, r = entry.swing })
            end
        end
    end
    return timeline
end

--- The blows that landed on the player's target, oldest first, for
--- working out how hard each one hit (see Sizes.lua).
---@return table  list of { time, crit, spell }
local function Blows(earliest)
    local blows = {}
    for _, entry in ipairs(log) do
        if entry.hit and entry.onTarget and entry.time >= earliest then
            table.insert(blows, { time = entry.time, crit = entry.crit, spell = entry.spell })
        end
    end
    return blows
end

--- Marks the start of a fight, so the log stops forgetting.
function Hits.Begin()
    fighting = true
end

--- The count so far for a fight that's still going on.
---@param startTime number  when the fight began, on GetTime's clock
function Hits.Live(startTime)
    return Count(Earliest(startTime), startTime - LEAD_SECONDS, startTime)
end

--- Counts up a fight and clears the log for the next one.
---@param startTime number  when the fight began, on GetTime's clock
---@return table tally, table casts  as from Count
---@return table timeline  as from Timeline
---@return table blows  as from Blows
function Hits.Finish(startTime)
    local earliest = Earliest(startTime)
    local tally, casts = Count(earliest, startTime - LEAD_SECONDS, startTime)
    local timeline = Timeline(earliest, startTime)
    local blows = Blows(earliest)

    log = {}
    fighting = false
    lastFinish = GetTime()
    return tally, casts, timeline, blows
end
