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
--
-- The healing tally also says who each heal landed on. A healer's row is
-- one ability, and beside it the game names one target and how much that
-- target got. Its own meter shows a row as "Flash Heal (Tharic)" with the
-- row's whole amount, and has no way to show a second target, so a heal
-- cast on two people should arrive as two rows, one for each. The game's
-- notes don't quite promise that, though, so the amount given for the
-- named target is the one used, and anything over it counts as landing on
-- someone else. If a row does turn out to cover several targets, nothing
-- is counted as healing the player that didn't.
--
-- That's how the healing the player gave themselves is told from what
-- they gave their pet or anyone else, and how healing from other people is
-- found: it's in their rows, against the player's name. Fights in a group
-- aren't saved at all (see Fights.lua), so the other people are a
-- passer-by, or a friend outside the group, healing a player fighting on
-- their own.

local Tallies = {}
ns.Tallies = Tallies

-- The most enemy abilities kept for a fight's damage taken. A long fight
-- against several enemies can list dozens, and only the worst matter.
local MOST_SOURCES = 12

-- The most other people kept as having healed the player in a fight.
-- Fighting alone, it's rare to see more than one.
local MOST_HEALERS = 8

-- What to call healing, or a blow, that the game gives no name for.
local NAMELESS_HEALING = "Other healing"
local NAMELESS_ATTACK = "Attack"

-- What to call someone who healed the player when the game won't say who.
-- Healing.lua looks for the same word.
local SOMEONE = "Someone"

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

--- For sorting rows by amount, the largest first.
local function BiggestFirst(a, b)
    return a.amount > b.amount
end

-- Healing -------------------------------------------------------------------

--- True if a row of healing is the pet's. As with damage, a pet's healing
--- can arrive folded into its owner's rows, marked with the pet's name.
local function IsPetsRow(row, fromPet)
    return fromPet or ReadableText(row.creatureName) ~= nil
end

--- Adds one healer's rows from the game's tally to our list.
---@param heals table  { spells, byKey }: the list so far, and its abilities
---                    by whose they are and their spell, so that a heal
---                    that landed on two people is still one ability
local function AddHeals(heals, rows, fromPet, casts)
    if type(rows) ~= "table" then
        return
    end

    for _, row in ipairs(rows) do
        local id = Readable(row.spellID)
        local amount = Readable(row.totalAmount)

        if id and amount and amount > 0 then
            local isPet = IsPetsRow(row, fromPet)
            local key = (isPet and "pet" or "own") .. id
            local spell = heals.byKey[key]

            if spell then
                spell.amount = spell.amount + amount
            else
                spell = {
                    id = id,
                    name = SpellName(id) or NAMELESS_HEALING,
                    amount = amount,
                    casts = casts[id],
                    pet = isPet or nil,
                }
                -- Icon, rank and cost, noted as they are for an ability
                -- that does damage. They're a nicety: a refusal mustn't
                -- cost the rest.
                pcall(ns.Fights.Describe, spell)
                heals.byKey[key] = spell
                table.insert(heals.spells, spell)
            end
        end
    end
end

--- A character's name without the realm the game sometimes adds to it
--- ("Name-Realm"), so that one way of writing it matches the other.
local function ShortName(name)
    return name and (name:match("^[^-]+") or name)
end

--- Who a row of healing landed on, as far as the game says.
---@return string|nil name  nil when the game won't give it
---@return boolean isPet  true if the game says it landed on a pet
---@return number|nil amount  how much of the row landed on them (see the
---                           header); nil if that can't be read
local function Target(row)
    local total = Readable(row.totalAmount)
    if not total then
        return nil, false, nil
    end

    local details = row.combatSpellDetails
    if IsSecret(details) or type(details) ~= "table" then
        return nil, false, total
    end

    -- An amount that can't be read says nothing about how much of the row
    -- landed on that target, and the whole row mustn't be put down to it.
    local amount = Readable(details.amount)
    if amount and amount <= 0 then
        amount = nil
    elseif amount and amount > total then
        amount = total
    end
    local isPet = not IsSecret(details.isPet) and details.isPet == true
    return ShortName(ReadableText(details.unitName)), isPet, amount
end

--- Where the healing in some rows landed, added to `landed`. False if any
--- row doesn't say: a split with a guess in it would be no use.
---@param names table  { me, pet }: the player's name, and the pet's if
---                    there is one and the game gives it
local function AddLanded(landed, rows, fromPet, names)
    for _, row in ipairs(rows) do
        local total = Readable(row.totalAmount)
        if total and total > 0 then
            local name, isPet, amount = Target(row)
            if not amount then
                return false
            end

            if name and name == names.me then
                landed.onSelf = landed.onSelf + amount
                if IsPetsRow(row, fromPet) then
                    landed.petOnSelf = landed.petOnSelf + amount
                end
            elseif name and name == names.pet then
                landed.onPet = landed.onPet + amount
            elseif isPet and not (name and names.pet) then
                -- A pet, and nothing says it isn't this one: one that's
                -- died by the fight's end has no name to go by.
                landed.onPet = landed.onPet + amount
            elseif name then
                landed.onOthers = landed.onOthers + amount
            else
                return false
            end

            landed.onOthers = landed.onOthers + (total - amount)
        end
    end
    return true
end

--- Where the player's and their pet's healing landed: on the player, on
--- the pet, or on anyone else.
---@param lines table  list of { rows, fromPet }, one per healer
---@return table|nil  { onSelf, onPet, onOthers, petOnSelf }; nil unless
---                   every row said who it landed on
local function WhereItLanded(lines)
    local names = {
        me = ShortName(ReadableText(UnitName("player"))),
        pet = ShortName(ReadableText(UnitName("pet"))),
    }
    if not names.me then
        return nil
    end

    local landed = { onSelf = 0, onPet = 0, onOthers = 0, petOnSelf = 0 }
    for _, line in ipairs(lines) do
        if type(line.rows) ~= "table" or not AddLanded(landed, line.rows, line.fromPet, names) then
            return nil
        end
    end

    if landed.onSelf + landed.onPet + landed.onOthers <= 0 then
        return nil
    end
    return landed
end

--- What the player and their pet healed, ability by ability, and where it
--- landed.
---@return table|nil  { total, spells, onSelf, onPet, onOthers, petOnSelf },
---                   spells biggest first. The four after them are only
---                   there when the game said where every heal landed
local function Healing(me, casts)
    local mine = LineFor("HealingDone", me)
    local total = Readable(mine.totalAmount)
    if not total then
        return nil
    end

    local heals = { spells = {}, byKey = {} }
    local lines = { { rows = mine.combatSpells, fromPet = false } }
    AddHeals(heals, mine.combatSpells, false, casts)

    local pets = PetLineFor("HealingDone")
    if pets then
        total = total + (Readable(pets.totalAmount) or 0)
        AddHeals(heals, pets.combatSpells, true, casts)
        table.insert(lines, { rows = pets.combatSpells, fromPet = true })
    end

    if total <= 0 then
        return nil
    end
    table.sort(heals.spells, BiggestFirst)
    local healing = { total = total, spells = heals.spells }

    -- Where it landed is read on its own. If the game won't say, the
    -- healing is kept without it.
    local read, landed = pcall(WhereItLanded, lines)
    if read and landed then
        healing.onSelf = landed.onSelf
        healing.onPet = landed.onPet
        healing.onOthers = landed.onOthers
        healing.petOnSelf = landed.petOnSelf > 0 and landed.petOnSelf or nil
    end
    return healing
end

-- Healing from other people -------------------------------------------------

--- How much of one other healer's healing landed on the player.
---@param source table  the healer's entry in the game's list of everyone
---@param me string  the player's name
---@return number|nil
local function HealingOnMe(source, me)
    -- Asked for by their GUID when the game gives it, or else by the kind
    -- of creature they are, as the game's own meter asks.
    local guid, creature = source.sourceGUID, Readable(source.sourceCreatureID)
    local line
    if guid and not IsSecret(guid) then
        line = LineFor("HealingDone", guid)
    elseif creature then
        line = C_DamageMeter.GetCombatSessionSourceFromType(
            Enum.DamageMeterSessionType.Current,
            Enum.DamageMeterType.HealingDone,
            nil,
            creature
        )
    else
        return nil
    end

    local amount = 0
    for _, row in ipairs(line.combatSpells or {}) do
        local name, _, onTarget = Target(row)
        if name and name == me and onTarget then
            amount = amount + onTarget
        end
    end
    return amount
end

--- Who else healed the player, and by how much: everyone in the healing
--- tally but the player and their pet, as far as their healing landed on
--- the player. The pet's healing on its owner is the player's own side.
---@return table|nil  list of { name, class, amount }, biggest first
local function HealedBy()
    local me = ShortName(ReadableText(UnitName("player")))
    if not me then
        return nil
    end
    local pet = UnitGUID("pet")
    if IsSecret(pet) then
        pet = nil
    end
    local petName = ReadableText(UnitName("pet"))

    local everyone = C_DamageMeter.GetCombatSessionFromType(
        Enum.DamageMeterSessionType.Current,
        Enum.DamageMeterType.HealingDone
    )

    local healers = {}
    for _, source in ipairs(everyone.combatSources) do
        -- The pet is known by its GUID, or failing that by its name.
        local guid, name = source.sourceGUID, ReadableText(source.name)
        local isPet = (pet ~= nil and not IsSecret(guid) and guid == pet)
            or (petName ~= nil and name == petName)

        if source.isLocalPlayer ~= true and not isPet then
            -- Each healer by themselves: one the game won't describe
            -- leaves out only that one.
            local read, amount = pcall(HealingOnMe, source, me)
            if read and amount and amount > 0 then
                table.insert(healers, {
                    name = name or SOMEONE,
                    class = ReadableText(source.classFilename),
                    amount = amount,
                })
            end
        end
    end

    if #healers == 0 then
        return nil
    end
    table.sort(healers, BiggestFirst)
    while #healers > MOST_HEALERS do
        table.remove(healers)
    end
    return healers
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
---                 healing     { total, spells, onSelf, onPet, onOthers,
---                             petOnSelf }
---                 healedBy    list of { name, class, amount }: other
---                             people's healing on the player
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
    Try("healedBy", HealedBy)
    Try("absorbed", OwnTotal, "Absorbs", me)
    Try("taken", Taken, me)
    Try("interrupts", TimesDone, "Interrupts", me)
    Try("dispels", TimesDone, "Dispels", me)

    return found
end
