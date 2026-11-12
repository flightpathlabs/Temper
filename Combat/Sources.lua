local _, ns = ...

-- Where a line of damage came from.
--
-- The game's own tally names each source of damage by spell. That's enough
-- to sort them into the four things a player cares about: what they
-- pressed, what their weapon did by itself, what their pet did, and
-- everything else, which in practice is an item's effect.

local Sources = {}
ns.Sources = Sources

Sources.ORDER = { "skill", "auto", "pet", "other" }

Sources.LABELS = {
    skill = "Abilities",
    auto = "Auto attacks",
    pet = "Pet",
    other = "Items and other effects",
}

-- Wands fire through a spell called Shoot, which the client files under
-- skills. To the player it's an auto attack.
local ALSO_AUTO = {
    [5019] = true,
}

local function AskKind(spellID)
    if ALSO_AUTO[spellID] then
        return "auto"
    end
    if C_Spell.IsAutoAttackSpell(spellID) or C_Spell.IsRangedAutoAttackSpell(spellID) then
        return "auto"
    end
    if C_SpellBook.IsSpellKnown(spellID) or C_SpellBook.IsSpellInSpellBook(spellID) then
        return "skill"
    end
    return "other"
end

--- Sorts a damage source into "skill", "auto", "pet" or "other".
---@param spellID number  0 when the game couldn't name one
---@param fromPet boolean
---@return string
function Sources.Kind(spellID, fromPet)
    if fromPet then
        return "pet"
    end
    if spellID == 0 then
        return "other"
    end

    -- The client can refuse questions about spells it doesn't recognise.
    -- Something we can't place is, by definition, "other".
    local ok, kind = pcall(AskKind, spellID)
    return ok and kind or "other"
end

--- The name to show for a damage source.
---@param spellID number
---@return string
function Sources.Name(spellID)
    local name = spellID ~= 0 and C_Spell.GetSpellName(spellID)
    return name or "Other damage"
end
