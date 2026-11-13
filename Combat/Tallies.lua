local _, ns = ...

-- The game's other tallies for a fight.
--
-- Alongside the damage dealt, the game tallies what else went on in each
-- fight: healing done, damage soaked up by shields, damage taken, casts
-- interrupted and effects dispelled. They're read the way the damage is
-- (see Fights.lua): the instant the fight is over, by asking each tally
-- for the player's own line in it.
--
-- The damage tally decides whether there's a fight to save at all. These
-- only add to one, so each is read by itself and under pcall. A tally
-- that's missing, empty or withheld leaves its own figure out and costs
-- nothing else.
--
-- Only the damage tally has been measured on this client. The rest are
-- read on the strength of the game's own meter, which asks for every one
-- of them in the same way.

local Tallies = {}
ns.Tallies = Tallies

-- The most enemy abilities kept for a fight's damage taken. A long fight
-- against several enemies can list dozens, and only the worst matter.
local MOST_SOURCES = 12

-- What to call healing, or a blow, that the game gives no name for.
local NAMELESS_HEALING = "Other healing"
local NAMELESS_ATTACK = "Attack"

local IsSecret = issecretvalue or function()
    return false
end

-- Reading what the game hands over ------------------------------------------

--- The value if it's a number we may read, otherwise nil.
local function Readable(value)
    if IsSecret(value) or type(value) ~= "number" then
        return nil
    end
    return value
end

--- The value if it's text we may read and there's some of it, otherwise nil.
local function ReadableText(value)
    if IsSecret(value) or type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

--- What the game calls a spell, or nil when it has no name for it.
local function SpellName(id)
    if id == 0 then
        return nil
    end
    local ok, name = pcall(C_Spell.GetSpellName, id)
    return ok and ReadableText(name) or nil
end

--- One fighter's line in one of the game's tallies for the fight that
--- just ended.
---@param tally string  the game's name for it: "HealingDone", "Absorbs"...
---@param guid string  whose line to ask for
local function LineFor(tally, guid)
    return C_DamageMeter.GetCombatSessionSourceFromType(
        Enum.DamageMeterSessionType.Current,
        Enum.DamageMeterType[tally],
        guid
    )
end

--- The pet's line in a tally, if it's listed there as a fighter in its
--- own right. When it isn't, whatever it did arrives folded into its
--- owner's line, and adding it again would count it twice.
local function PetLineFor(tally)
    local pet = UnitGUID("pet")
    if not pet or IsSecret(pet) then
        return nil
    end

    local everyone = C_DamageMeter.GetCombatSessionFromType(
        Enum.DamageMeterSessionType.Current,
        Enum.DamageMeterType[tally]
    )
    for _, source in ipairs(everyone.combatSources) do
        if not IsSecret(source.sourceGUID) and source.sourceGUID == pet then
            return LineFor(tally, pet)
        end
    end
    return nil
end

--- The player's own total in a tally, or nil when it's nothing.
local function OwnTotal(tally, me)
    local total = Readable(LineFor(tally, me).totalAmount)
    return total and total > 0 and total or nil
end

--- How many times the player did what a tally counts, such as cutting a
--- cast short. A pet does these at its owner's bidding, so its count is
--- the player's too.
local function TimesDone(tally, me)
    local times = Readable(LineFor(tally, me).totalAmount) or 0

    local pets = PetLineFor(tally)
    if pets then
        times = times + (Readable(pets.totalAmount) or 0)
    end
    return times > 0 and times or nil
end

local function BiggestFirst(a, b)
    return a.amount > b.amount
end

-- Healing -------------------------------------------------------------------

--- Adds one healer's rows from the game's tally to our list.
local function AddHeals(spells, rows, fromPet, casts)
    if type(rows) ~= "table" then
        return
    end

    for _, row in ipairs(rows) do
        local id = Readable(row.spellID)
        local amount = Readable(row.totalAmount)

        if id and amount and amount > 0 then
            -- As with damage, a pet's healing can arrive folded into its
            -- owner's rows, marked with the pet's name.
            local isPet = fromPet or ReadableText(row.creatureName) ~= nil

            local spell = {
                id = id,
                name = SpellName(id) or NAMELESS_HEALING,
                amount = amount,
                casts = casts[id],
                pet = isPet or nil,
            }
            -- Icon, rank and cost, noted as they are for an ability that
            -- does damage. They're a nicety: a refusal mustn't cost the rest.
            pcall(ns.Fights.Describe, spell)
            table.insert(spells, spell)
        end
    end
end

--- What the player and their pet healed, ability by ability.
---@return table|nil  { total, spells }, spells biggest first
local function Healing(me, casts)
    local mine = LineFor("HealingDone", me)
    local total = Readable(mine.totalAmount)
    if not total then
        return nil
    end

    local spells = {}
    AddHeals(spells, mine.combatSpells, false, casts)

    local pets = PetLineFor("HealingDone")
    if pets then
        total = total + (Readable(pets.totalAmount) or 0)
        AddHeals(spells, pets.combatSpells, true, casts)
    end

    if total <= 0 then
        return nil
    end
    table.sort(spells, BiggestFirst)
    return { total = total, spells = spells }
end

-- Damage taken --------------------------------------------------------------

--- Who struck a blow, when the game names them. In the tally of damage
--- taken each row is an enemy's ability, and the enemy is named beside it.
local function Attacker(row)
    local details = row.combatSpellDetails
    local name
    if not IsSecret(details) and type(details) == "table" then
        name = ReadableText(details.unitName)
    end
    return name or ReadableText(row.creatureName)
end

--- The damage the player took, and the enemy abilities that did it.
---@return table|nil  { total, avoidable, sources }, sources biggest first
local function Taken(me)
    local mine = LineFor("DamageTaken", me)
    local total = Readable(mine.totalAmount)
    if not total or total <= 0 then
        return nil
    end

    local sources = {}
    local marked = 0

    if type(mine.combatSpells) == "table" then
        for _, row in ipairs(mine.combatSpells) do
            local amount = Readable(row.totalAmount)

            if amount and amount > 0 then
                local id = Readable(row.spellID) or 0
                local avoidable = not IsSecret(row.isAvoidable) and row.isAvoidable == true
                if avoidable then
                    marked = marked + amount
                end

                table.insert(sources, {
                    id = id,
                    name = SpellName(id) or NAMELESS_ATTACK,
                    amount = amount,
                    avoidable = avoidable or nil,
                    from = Attacker(row),
                })
            end
        end
    end

    table.sort(sources, BiggestFirst)
    while #sources > MOST_SOURCES do
        table.remove(sources)
    end

    -- The game keeps a tally of just the avoidable damage. Where that one
    -- says nothing, the rows it marked in this one still add up.
    local read, avoidable = pcall(OwnTotal, "AvoidableDamageTaken", me)
    if not read or not avoidable then
        avoidable = marked > 0 and marked or nil
    end

    return { total = total, avoidable = avoidable, sources = sources }
end

-- All of them ---------------------------------------------------------------

--- Reads the game's other tallies for the fight that just ended. Call it
--- once the damage tally has shown there's a new fight to read.
---@param casts table|nil  times each spell was cast, by spell ID (see
---                        Hits.lua)
---@return table  the fields to add to the fight, each left out when the
---               game had nothing to say or wouldn't say it:
---                 healing     { total, spells }
---                 absorbed    damage soaked by the player's own shields
---                 taken       { total, avoidable, sources }
---                 interrupts  casts the player or their pet cut short
---                 dispels     effects they dispelled
function Tallies.Read(casts)
    local found = {}
    local me = UnitGUID("player")

    local function Try(field, reader, ...)
        local ok, value = pcall(reader, ...)
        if ok then
            found[field] = value
        end
    end

    Try("healing", Healing, me, casts or {})
    Try("absorbed", OwnTotal, "Absorbs", me)
    Try("taken", Taken, me)
    Try("interrupts", TimesDone, "Interrupts", me)
    Try("dispels", TimesDone, "Dispels", me)

    return found
end
