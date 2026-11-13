local _, ns = ...

-- How much of the harm coming at the player never reached them, and why.
--
-- The damage the player took is counted exactly, by the game's own tally
-- (see Tallies.lua). What was stopped before it got that far isn't counted
-- anywhere: the part of each blow that armour took off, the blows that
-- were dodged, parried or missed, what a shield blocked. Some of it can be
-- worked out. The character sheet says how much armour takes off a blow
-- from an enemy of a given level, and how much a shield blocks, and the
-- blows that failed are counted as they happen (see Hits.lua). Put
-- together, they make an estimate, and it's always called one.
--
-- The character's figures are read the moment a fight is over, since
-- they're what the fight was fought with and they change with gear and
-- level. Only those are saved with the fight. The sums are done each time
-- they're wanted, from what else the fight keeps.
--
-- Spells stay out of the sums. The game counts a resisted spell but not
-- how much of it was resisted, and armour, dodging and blocking only ever
-- touch physical blows.

local Mitigation = {}
ns.Mitigation = Mitigation

-- The game expects five points of Defence skill for each level of the
-- enemy. Each point short adds this much (in per cent) to the enemy's
-- chance of a critical hit, and takes it off their chance to miss and the
-- player's chances to dodge, parry and block. These are the sums the
-- character sheet's own Defence tooltip works from.
Mitigation.SKILL_PER_LEVEL = 5
Mitigation.COST_PER_POINT = 0.04

-- An enemy can only land a crushing blow once its weapon skill is this
-- far past the player's Defence. Beyond it, each point adds two in a
-- hundred, less fifteen. Defence above what the player's level allows
-- doesn't push it back. All three are the character sheet's figures.
local CRUSHING_FROM = 15
local CRUSHING_PER_POINT = 2
local CRUSHING_LESS = 15

-- With fewer blows than this landed, one big hit or one small one would
-- decide what an average blow was, and so what a dodge was worth.
local ENOUGH_LANDED = 5

-- The spell behind an ordinary melee swing, which is how the game's tally
-- of damage taken should list an enemy's plain attacks. A row that comes
-- with no spell, or one the game can't name, is called "Attack" by
-- Tallies.lua, and that's taken as a swing too: a plain attack is the one
-- thing an enemy does that isn't an ability.
local MELEE_SWING = 6603
local NAMELESS_ATTACK = "Attack"

-- The schools of magic, by the bit the game uses for each in a blow's
-- school, with the word for it and the resistance that guards against it
-- (Enum.Damageclass). Holy has no resistance. A spell of two schools at
-- once has a mask of its own and isn't named.
local SCHOOLS = {
    [2] = { word = "holy" },
    [4] = { word = "fire", resistance = 2 },
    [8] = { word = "nature", resistance = 3 },
    [16] = { word = "frost", resistance = 4 },
    [32] = { word = "shadow", resistance = 5 },
    [64] = { word = "arcane", resistance = 6 },
}

-- How much of a spell resistance turns aside on average: three quarters
-- of the resistance over five points for each level of whoever cast it.
-- That's the character sheet's own sum, which it shows for an enemy of
-- the player's level; here it's put to the level of the enemies fought.
-- It never turns aside more than three quarters.
local RESIST_SHARE = 0.75
local RESIST_PER_LEVEL = 5
local MOST_RESISTED = 0.75

local IsSecret = issecretvalue or function()
    return false
end

--- The value if it's a number we may read, otherwise nil.
local function Readable(value)
    if IsSecret(value) or type(value) ~= "number" then
        return nil
    end
    return value
end

-- Reading the character's figures -------------------------------------------

--- What the player's armour takes off a physical blow from an enemy of
--- the given level.
local function ReadArmour(found, attackerLevel)
    local _, effective = UnitArmor("player")
    effective = Readable(effective)
    if not effective or effective <= 0 then
        return
    end

    local cut = Readable(C_PaperDollInfo.GetArmorEffectiveness(effective, attackerLevel))
    -- Armour that took off the whole blow would make every sum below
    -- divide by nothing. The game never allows it, but a wrong answer
    -- shouldn't turn into a silly figure.
    if not cut or cut <= 0 or cut >= 1 then
        return
    end

    found.armour = effective
    found.armourCut = math.floor(cut * 1000 + 0.5) / 1000
end

--- How much the player's shield takes off a blow it blocks. Only read
--- when something was blocked: without a shield there's nothing to say.
local function ReadShield(found, defence)
    local blocks = (defence.partBlocked or 0) + (defence.avoidedBy.BLOCK or 0)
    if blocks == 0 then
        return
    end

    local value = Readable(GetShieldBlock())
    if value and value > 0 then
        found.blockValue = value
    end
end

--- The player's Defence skill: what they've trained it to, and that with
--- whatever their gear and race add, as the character sheet shows it.
local function ReadDefence(found)
    local base, modifier = UnitDefenseSkill("player")
    base, modifier = Readable(base), Readable(modifier)
    if not base then
        return
    end

    found.defenceBase = base
    found.defence = math.max(0, base + (modifier or 0))
end

--- The player's resistance to each school of magic that hit them.
local function ReadResistances(found, defence)
    for mask in pairs(defence.schools or {}) do
        local school = SCHOOLS[mask]
        if school and school.resistance then
            local _, _, effective = UnitResistance("player", school.resistance)
            effective = Readable(effective)
            if effective then
                found.resistances = found.resistances or {}
                found.resistances[mask] = effective
            end
        end
    end
end

--- Reads the figures the fight that just ended was fought with. Call it
--- once the fight is out of combat, when the game lets them be read.
---@param fight table  the fight being saved, with its level, enemyLevel
---                    and defence already in place
---@return table|nil  the fields of a fight's mitigation, each left out
---                   when the game wouldn't say; nil when it said nothing:
---                     armour       the player's armour
---                     armourCut    the share of a physical blow from the
---                                  fight's enemy that it takes off
---                     blockValue   what the shield takes off a blocked blow
---                     defence      Defence skill, with gear and race
---                     defenceBase  Defence skill as trained
---                     resistances  resistance by school, for each school
---                                  that hit the player
function Mitigation.Read(fight)
    local found = {}
    local defence = fight.defence or { avoidedBy = {} }

    -- Each figure by itself: one the game withholds costs only itself.
    pcall(ReadArmour, found, fight.enemyLevel or fight.level)
    pcall(ReadShield, found, defence)
    pcall(ReadDefence, found)
    pcall(ReadResistances, found, defence)

    if next(found) == nil then
        return nil
    end
    return found
end

-- Working it out ------------------------------------------------------------

--- True if a row of the tally of damage taken is an enemy's melee swing.
local function IsSwing(source)
    return source.id == MELEE_SWING or source.id == 0 or source.name == NAMELESS_ATTACK
end

--- How much of the damage the player took was physical, as far as can
--- honestly be told.
---
--- The tally of damage taken names each enemy ability but not its school.
--- Two things are certain: an enemy's swing is physical, and when not one
--- spell landed on the player, all of it was. Past that there's only the
--- count of physical blows against spells, and a count says nothing about
--- size: a tick of poison and a fireball are one each. Splitting the rest
--- of the damage by that count would be a guess passed off as a figure.
--- So when spells landed too, only the swings are counted as physical,
--- and everything worked out from this leans low, which is the right way
--- for an estimate of what went well to lean.
local function Physical(fight)
    local taken = fight.taken
    if not taken then
        return 0
    end
    if fight.defence.magic == 0 then
        return taken.total or 0
    end

    local physical = 0
    for _, source in ipairs(taken.sources or {}) do
        if IsSwing(source) then
            physical = physical + source.amount
        end
    end
    return physical
end

--- About how much one fight's armour, dodging and blocking stopped.
---@return table|nil  nil for a fight saved before the spells that hit the
---                   player were counted, since without them nothing can
---                   be said of which damage was physical. Otherwise:
---   taken       the damage that got through
---   physical    how much of that is known to have been physical
---   absorbed    what the player's own shields soaked up (exact)
---   armour      about how much more physical damage there would have
---               been without armour; nil when the game didn't say
---   armourCut   the share armour took off each physical blow
---   avoided     about what the blows dodged, parried and missed would
---               have done; nil with too few blows landed to tell
---   blocked     about what the shield blocked; nil with no shield
---   coming      all of those added up: the harm that came at the player
---   estimated   true when any of armour, avoided and blocked came to
---               more than nothing
function Mitigation.Estimate(fight)
    local defence = fight.defence
    if not defence or defence.magic == nil then
        return nil
    end

    local saved = fight.mitigation or {}
    local by = defence.avoidedBy or {}
    local estimate = {
        taken = fight.taken and fight.taken.total or 0,
        physical = Physical(fight),
        absorbed = fight.absorbed or 0,
    }
    local physical = estimate.physical

    -- Armour takes its share off each blow, and what got through is the
    -- rest. So what it took off is what got through, times its share over
    -- the rest.
    local cut = saved.armourCut
    if cut and physical > 0 then
        estimate.armour = physical * cut / (1 - cut)
        estimate.armourCut = cut
    end

    -- A blow that didn't land would have done what a blow that did land
    -- did, on average. That average is after armour, as the dodged blow
    -- would have been.
    local landed = defence.struck or 0
    local average = landed >= ENOUGH_LANDED and physical > 0 and physical / landed or nil
    if average then
        local turned = (by.DODGE or 0) + (by.PARRY or 0) + (by.MISS or 0)
        estimate.avoided = turned * average
    end

    -- A blow the shield only partly blocked lost exactly the shield's
    -- block. One blocked in full was no bigger than that, and may have
    -- been smaller, so it's counted as whichever is less.
    local value = saved.blockValue
    if value then
        local whole = by.BLOCK or 0
        estimate.blocked = (defence.partBlocked or 0) * value
            + whole * math.min(value, average or value)
    end

    estimate.coming = estimate.taken
        + estimate.absorbed
        + (estimate.armour or 0)
        + (estimate.avoided or 0)
        + (estimate.blocked or 0)
    -- Nothing worked out to have stopped anything is no estimate at all:
    -- with the armour hidden and not a blow dodged, "nothing was stopped"
    -- would be the one thing certainly not true.
    estimate.estimated = (estimate.armour or 0) > 0
        or (estimate.avoided or 0) > 0
        or (estimate.blocked or 0) > 0
    return estimate
end

-- Defence skill and resistance ----------------------------------------------

--- The chance of a crushing blow from an enemy of one level against a
--- player of another, by the character sheet's sum.
---@param defence number  the player's Defence skill, with gear and race
---@return number  a share, 0 to 1
function Mitigation.CrushingChance(enemyLevel, playerLevel, defence)
    local counted = math.min(defence, playerLevel * Mitigation.SKILL_PER_LEVEL)
    local gap = enemyLevel * Mitigation.SKILL_PER_LEVEL - counted
    if gap < CRUSHING_FROM then
        return 0
    end
    return math.min(gap * CRUSHING_PER_POINT - CRUSHING_LESS, 100) / 100
end

--- What a school of magic is called, or nil for one of two schools at
--- once, which has no plain name.
---@param mask number  the school as a blow reports it
---@return string|nil  e.g. "fire"
function Mitigation.SchoolWord(mask)
    local school = SCHOOLS[mask]
    return school and school.word
end

--- True if the player can wear resistance to a school.
---@param mask number  the school as a blow reports it
---@return boolean
function Mitigation.Resistible(mask)
    local school = SCHOOLS[mask]
    return school ~= nil and school.resistance ~= nil
end

--- How much of a spell a resistance turns aside on average, by the
--- character sheet's sum.
---@param resistance number  the player's resistance to the spell's school
---@param casterLevel number  the level of whoever cast it
---@return number  a share, 0 to 1
function Mitigation.ResistedShare(resistance, casterLevel)
    if casterLevel <= 0 then
        return 0
    end
    local share = RESIST_SHARE * resistance / (casterLevel * RESIST_PER_LEVEL)
    return math.max(0, math.min(share, MOST_RESISTED))
end
