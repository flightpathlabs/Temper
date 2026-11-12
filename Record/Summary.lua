local _, ns = ...

-- Adds a set of fights up into the figures the analysis shows.
--
-- Nothing here is saved. A summary is worked out from the fights each time
-- it's wanted, so there's only ever one copy of the truth.

local Summary = {}
ns.Summary = Summary

-- What to call each resource in a sentence.
local POWER_WORDS = {
    MANA = "mana",
    ENERGY = "energy",
    RAGE = "rage",
    FOCUS = "focus",
}

--- The everyday word for a resource: "mana" for "MANA".
function Summary.PowerWord(power)
    return POWER_WORDS[power] or (power and power:lower()) or "resource"
end

local function NewSplit()
    return { fights = 0, damage = 0, seconds = 0, dps = 0 }
end

local function AddToSplit(split, fight)
    split.fights = split.fights + 1
    split.damage = split.damage + fight.damage
    split.seconds = split.seconds + fight.length
end

local function FinishSplit(split)
    if split.seconds > 0 then
        split.dps = split.damage / split.seconds
    end
end

--- Sums up a set of fights.
---@param fights table  list of fights, in any order
---@return table summary:
---   fights, damage, seconds, dps
---   hits, crits, glancing, avoided
---   avoidedBy   attacks that failed each way: MISS, DODGE, PARRY...
---   level, enemyLevel, weapons   as they were in the newest fight
---   critRate    crits as a share of hits; nil without a single hit
---   avoidRate   attacks that missed or were avoided, as a share of all
---               attacks; nil without a single attack
---   abilities   list, biggest first, of:
---                 id, name, kind, icon, rank   what it is
---                 damage, share                what it did
---                 casts, perCast               uses, and damage per use;
---                                              only for skills whose
---                                              casts were seen
---                 cost, power                  what one use costs
---                 perCost                      damage per point of that
---   kinds       damage by kind of source: skill, auto, pet, other
---   best        { name, damage } for the hardest single use of a skill
---   single      fights against one enemy: { fights, damage, seconds, dps }
---   several     fights against more than one, likewise
function Summary.Of(fights)
    local summary = {
        fights = 0,
        damage = 0,
        seconds = 0,
        dps = 0,
        hits = 0,
        crits = 0,
        glancing = 0,
        avoided = 0,
        avoidedBy = {},
        abilities = {},
        kinds = { skill = 0, auto = 0, pet = 0, other = 0 },
        single = NewSplit(),
        several = NewSplit(),
    }

    -- Abilities by spell and kind, so a pet's Claw and a druid's Claw
    -- don't end up on one line.
    local byKey = {}

    -- The newest fight speaks for the set on things that are true of a
    -- moment: the player's level, the enemy's, and their weapon skills.
    local newest

    for _, fight in ipairs(fights or {}) do
        summary.fights = summary.fights + 1
        summary.damage = summary.damage + fight.damage
        summary.seconds = summary.seconds + fight.length
        summary.hits = summary.hits + (fight.hits or 0)
        summary.crits = summary.crits + (fight.crits or 0)
        summary.glancing = summary.glancing + (fight.glancing or 0)
        summary.avoided = summary.avoided + (fight.avoided or 0)
        for way, times in pairs(fight.avoidedBy or {}) do
            summary.avoidedBy[way] = (summary.avoidedBy[way] or 0) + times
        end

        if not newest or (fight.at or 0) > (newest.at or 0) then
            newest = fight
        end

        if fight.enemies and #fight.enemies > 1 then
            AddToSplit(summary.several, fight)
        else
            AddToSplit(summary.single, fight)
        end

        for _, spell in ipairs(fight.spells or {}) do
            local key = spell.kind .. spell.id
            local ability = byKey[key]
            if not ability then
                ability = { id = spell.id, name = spell.name, kind = spell.kind, damage = 0 }
                byKey[key] = ability
                table.insert(summary.abilities, ability)
            end

            ability.damage = ability.damage + spell.damage
            summary.kinds[spell.kind] = (summary.kinds[spell.kind] or 0) + spell.damage

            -- Icon, rank and cost as they were in whichever fight is read
            -- last. Sets are usually close together in time, so they agree.
            ability.icon = spell.icon or ability.icon
            ability.rank = spell.rank or ability.rank
            if spell.cost then
                ability.cost, ability.power = spell.cost, spell.power
            end

            -- Casts are only counted for skills. An auto attack is switched
            -- on once and swings many times, so its "casts" mean nothing.
            -- Damage per use is worked out over the fights where the casts
            -- were seen, in case some fight's weren't.
            local casts = spell.kind == "skill" and spell.casts
            if casts then
                ability.casts = (ability.casts or 0) + casts
                ability.castDamage = (ability.castDamage or 0) + spell.damage
            end

            -- A skill used once in a fight did all its damage in that one
            -- use. It's the nearest thing to "biggest hit" the game lets
            -- an addon know for certain.
            if casts == 1 and (not summary.best or spell.damage > summary.best.damage) then
                summary.best = { name = spell.name, damage = spell.damage }
            end
        end
    end

    if newest then
        summary.level = newest.level
        summary.enemyLevel = newest.enemyLevel
        summary.weapons = newest.weapons
    end

    if summary.seconds > 0 then
        summary.dps = summary.damage / summary.seconds
    end
    if summary.hits > 0 then
        summary.critRate = summary.crits / summary.hits
    end
    if summary.hits + summary.avoided > 0 then
        summary.avoidRate = summary.avoided / (summary.hits + summary.avoided)
    end
    FinishSplit(summary.single)
    FinishSplit(summary.several)

    for _, ability in ipairs(summary.abilities) do
        ability.share = summary.damage > 0 and ability.damage / summary.damage or 0
        if ability.casts and ability.casts > 0 then
            ability.perCast = ability.castDamage / ability.casts
            if ability.cost then
                ability.perCost = ability.perCast / ability.cost
            end
        end
    end
    table.sort(summary.abilities, function(a, b)
        return a.damage > b.damage
    end)

    return summary
end
