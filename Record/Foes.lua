local _, ns = ...

-- What a fight was against, in words: a name for the list, the enemy's
-- level, and whether it was elite, rare or a boss.
--
-- Fights saved since enemies were first looked at carry a list of the
-- kinds of enemy struck (see Combat\Fights.lua). Older ones only know the
-- name and level of what was targeted as the fight began, so everything
-- here falls back to those. Nothing here is saved: it's worked out from
-- the fight each time it's wanted.
--
-- Also here: whether a fight was against something so weak it shouldn't
-- count, a critter or an enemy the game would give no experience for.
-- Fights like that flatter the damage figures, so averages leave them out.

local Foes = {}
ns.Foes = Foes

-- The marks a fight's enemies can earn, from the game's words for a
-- creature's standing. A rare elite is marked as an elite: being elite is
-- what makes the fight harder.
local MARKS = {
    worldboss = "boss",
    elite = "elite",
    rareelite = "elite",
    rare = "rare",
}

-- When enemies earn different marks, the fight takes the highest.
local MARK_RANK = { boss = 3, elite = 2, rare = 1 }

-- What to call each mark. The game has its own word for elite, and none
-- for the others outside of sentences.
Foes.MARK_WORDS = {
    elite = ELITE or "Elite",
    rare = "Rare",
    boss = "Boss",
}

-- Creatures the game counts as lesser: critters, and the weaker mobs that
-- come in packs.
local LESSER = {
    minus = true,
    trivial = true,
}

-- Levels this close together read better as a range ("25-27") than as an
-- average.
local NARROW_SPREAD = 2

-- The classic game's rule for which creatures give no experience, for
-- fights saved before the game's own figure was noted with them: below
-- level 6 every creature is worth something; up to 39, a creature is grey
-- at the player's level less a tenth of it less five, and below; from 40,
-- at the player's level less a fifth of it less one, and below.
local GREY_FROM_LEVEL = 6
local LATE_GREY_LEVEL = 40

--- The highest creature level the classic rule greys out for a player of
--- this level, or nil if none is grey.
local function ClassicGreyLevel(level)
    if level < GREY_FROM_LEVEL then
        return nil
    elseif level < LATE_GREY_LEVEL then
        return level - math.floor(level / 10) - 5
    end
    return level - math.floor(level / 5) - 1
end

--- The highest creature level that was grey to the player in this fight,
--- or nil if none was or it can't be told. The game's own figure, noted
--- with the fight, is the one its nameplates go by: a creature is grey when
--- it's more than that many levels below the player.
local function GreyLevel(fight)
    local level = fight.level
    if type(level) ~= "number" then
        return nil
    end
    if type(fight.greyRange) == "number" then
        return level - fight.greyRange - 1
    end
    return ClassicGreyLevel(level)
end

--- The mark for a creature's standing, or nil for an ordinary one.
---@param classification string|nil  the game's word, e.g. "rareelite"
---@param boss boolean|nil  true if the game called it a boss
function Foes.MarkOf(classification, boss)
    if boss then
        return "boss"
    end
    return MARKS[classification]
end

--- The higher of two marks.
local function Higher(a, b)
    if not a then
        return b
    end
    if b and MARK_RANK[b] > MARK_RANK[a] then
        return b
    end
    return a
end

--- The fight's list of enemies, if it has one worth reading.
local function FoesOf(fight)
    local foes = fight.foes
    if type(foes) == "table" and foes[1] then
        return foes
    end
    return nil
end

--- How to put the levels of a group: "25" when they're all one level,
--- "25-27" when they're close, "avg 25" when they're spread out. Nil when
--- the game hid every one of them.
local function LevelText(foes)
    local lowest, highest
    local sum, counted = 0, 0
    for _, foe in ipairs(foes) do
        if foe.level then
            lowest = math.min(lowest or foe.level, foe.level)
            highest = math.max(highest or foe.level, foe.level)
            sum = sum + foe.level * foe.count
            counted = counted + foe.count
        end
    end

    if not lowest then
        return nil
    elseif lowest == highest then
        return tostring(lowest)
    elseif highest - lowest <= NARROW_SPREAD then
        return ("%d-%d"):format(lowest, highest)
    end
    return ("avg %d"):format(math.floor(sum / counted + 0.5))
end

--- The one name every enemy in the fight had, if they all had the same.
local function SharedName(foes)
    local name = foes[1].name
    for _, foe in ipairs(foes) do
        if not foe.name or foe.name ~= name then
            return nil
        end
    end
    return name
end

--- What to call a fight and what to show beside it.
---@return table  { title, level, mark, group }: title is the boss's name if
---               there was a boss; the one enemy's name if there was one;
---               "Greater Tarantula ×3" for several of one kind; "Group of
---               4" for a mix. level is "25", "25-27" or "avg 25", or nil
---               when it isn't known; mark is "elite", "rare", "boss" or
---               nil; group is true when there was more than one enemy
function Foes.Describe(fight)
    local fallback = fight.target or "Fight"
    local foes = FoesOf(fight)

    if not foes then
        return {
            title = fallback,
            level = fight.enemyLevel and tostring(fight.enemyLevel) or nil,
            mark = MARKS[fight.classification],
            group = false,
        }
    end

    local total, mark, boss = 0, nil, nil
    for _, foe in ipairs(foes) do
        total = total + foe.count
        local foeMark = Foes.MarkOf(foe.classification, foe.boss)
        mark = Higher(mark, foeMark)
        if foeMark == "boss" and not boss then
            boss = foe
        end
    end

    -- The game may have refused to say how strong every one of them was.
    -- The target's standing, read as the fight began, is better than
    -- nothing.
    mark = mark or MARKS[fight.classification]

    local described = { mark = mark, group = total > 1 }

    -- A boss is what the fight was about, whatever came with it.
    if boss then
        described.title = boss.name or fallback
        described.level = boss.level and tostring(boss.level) or nil
        return described
    end

    local shared = SharedName(foes)
    if total == 1 then
        described.title = foes[1].name or fallback
    elseif shared then
        described.title = ("%s ×%d"):format(shared, total)
    else
        described.title = ("Group of %d"):format(total)
    end
    described.level = LevelText(foes)
    return described
end

--- True if an enemy of this standing and level was too weak to count.
local function Weak(classification, level, greyLevel)
    if LESSER[classification] then
        return true
    end
    return level ~= nil and greyLevel ~= nil and level <= greyLevel
end

--- True for a fight against nothing but lesser creatures, or enemies so
--- far below the player that the game would give no experience for them.
--- False whenever it can't be told: an enemy whose level was hidden, or a
--- fight that doesn't say who it was against, is taken as one that counts.
function Foes.IsTrivial(fight)
    local greyLevel = GreyLevel(fight)
    local foes = FoesOf(fight)

    if not foes then
        return Weak(fight.classification, fight.enemyLevel, greyLevel)
    end

    for _, foe in ipairs(foes) do
        if not Weak(foe.classification, foe.level, greyLevel) then
            return false
        end
    end
    return true
end
