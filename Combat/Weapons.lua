local _, ns = ...

-- How practised the character is with the weapons in hand.
--
-- Forever has weapon skills. A character who picks up a kind of weapon
-- they've barely used misses more, is dodged and parried more, and crits
-- less, until the skill catches up with their level. The game shows the
-- skill on the character sheet; this reads the same figures, so a fight
-- can be told "that's why you were missing".

local Weapons = {}
ns.Weapons = Weapons

-- The game expects five points of weapon skill for each level of the
-- enemy, and each point short costs this much (in per cent) off the chance
-- to hit, and adds it to the enemy's chance to dodge and to parry. These
-- are the figures the game's own skills window works from.
Weapons.SKILL_PER_LEVEL = 5
Weapons.COST_PER_POINT = 0.04

local MAIN_HAND, OFF_HAND, RANGED = 16, 17, 18

local SLOTS = {
    { MAIN_HAND, "melee" },
    { OFF_HAND, "melee" },
    { RANGED, "ranged" },
}

local UNARMED = 162

-- A druid in an animal form fights with a skill of its own, whatever
-- they're holding.
local FERAL = 3014

--- Which skill each kind of weapon trains, by the game's own numbers.
local function SkillFor(subclass)
    local kinds = Enum.ItemWeaponSubclass
    local skills = {
        [kinds.Sword1H] = 43,
        [kinds.Axe1H] = 44,
        [kinds.Bows] = 45,
        [kinds.Guns] = 46,
        [kinds.Mace1H] = 54,
        [kinds.Sword2H] = 55,
        [kinds.Staff] = 136,
        [kinds.Mace2H] = 160,
        [kinds.Axe2H] = 172,
        [kinds.Dagger] = 173,
        [kinds.Thrown] = 176,
        [kinds.Crossbow] = 226,
        [kinds.Wand] = 228,
        [kinds.Polearm] = 229,
        [kinds.Unarmed] = UNARMED,
    }
    return skills[subclass]
end

local function InAnimalForm()
    local _, class = UnitClass("player")
    return class == "DRUID" and GetShapeshiftForm() ~= 0
end

local function Read()
    local skills = {}
    local feral = InAnimalForm()

    for _, slot in ipairs(SLOTS) do
        local item = GetInventoryItemID("player", slot[1])
        local skill

        if feral then
            -- Claws and teeth: one skill, counted once, and no bow.
            skill = slot[1] == MAIN_HAND and FERAL or nil
        elseif item then
            local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(item)
            if class == Enum.ItemClass.Weapon then
                skill = SkillFor(subclass)
            end
        elseif slot[1] == MAIN_HAND then
            skill = UNARMED
        end

        local info = skill and C_SkillInfo.GetSkillLineInfoByID(skill)
        if info and type(info.rank) == "number" and type(info.name) == "string" then
            table.insert(skills, {
                use = slot[2],
                name = info.name,
                -- What counts in a fight is the skill with any bonus from
                -- race or gear added on, as the game's own window shows it.
                rank = info.rank + (tonumber(info.modifier) or 0),
                cap = tonumber(info.maxRank),
            })
        end
    end
    return skills
end

--- The character's skill with each weapon they're holding.
---@return table  list of { use = "melee" or "ranged", name = "Swords",
---               rank = 42, cap = 50 }; empty on a client without weapon
---               skills, or if the game won't say
function Weapons.Skills()
    local ok, skills = pcall(Read)
    return ok and skills or {}
end
