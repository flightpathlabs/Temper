local _, ns = ...

-- Decides what goes in the lane and what it looks like.
--
-- Also looks after Blizzard's own damage numbers: while the lane is
-- showing they'd say everything twice, so they're switched off, and put
-- back exactly as the player had them the moment the lane steps aside.

local Feed = {}
ns.Feed = Feed

local BLIZZARD_DAMAGE_TEXT = "floatingCombatTextCombatDamage_v2"

local GLANCING_SCALE = 0.85
local WORD_SCALE = 0.85

-- How much larger than an ordinary hit a critical one is drawn when the
-- setting for it is missing, as a percentage.
local USUAL_CRIT_SIZE = 140

local WHITE = { 1, 1, 1 }
local GREY = { 0.72, 0.72, 0.72 }

-- The colorBy setting.
local BY_KIND, MAGIC_ONLY = 1, 2

-- By kind of damage, the way the game itself once told them apart: a
-- swing of the weapon in white, an ability in yellow. A pet's blows are
-- the green its bars have in the analysis.
local KIND_COLORS = {
    auto = WHITE,
    ability = { 1, 0.88, 0.2 },
    pet = { 0.62, 0.9, 0.62 },
}

-- Magic by school, in colours close to the ones the game uses for them
-- elsewhere. Damage of two schools at once gets the general one.
local MAGIC = { 0.6, 0.78, 1 }
local SCHOOL_COLORS = {
    [2] = { 1, 0.96, 0.72 }, -- holy
    [4] = { 1, 0.5, 0.2 }, -- fire
    [8] = { 0.55, 1, 0.45 }, -- nature
    [16] = { 0.5, 0.85, 1 }, -- frost
    [32] = { 0.72, 0.6, 1 }, -- shadow
    [64] = { 1, 0.6, 1 }, -- arcane
}

-- Critical hits, by the critStyle setting. The third style isn't listed:
-- it keeps the hit's own colour and relies on size and the landing.
local CRIT_COLORS = {
    { 1, 0.82, 0 },
    { 1, 0.27, 0.2 },
}

--- True while the lane should be drawing: switched on, and nobody else
--- around whose hits would be mistaken for the player's.
local function Showing()
    return ns.settings.lane and not IsInGroup()
end

--- What kind of damage a hit was: "magic", "ability", "auto" or "pet".
local function KindOf(hit)
    if hit.kind then
        return hit.kind
    end
    if hit.pet then
        return "pet"
    end
    if hit.school and hit.school ~= 1 then
        return "magic"
    end

    -- Physical. A weapon's swing unless it was traced to something the
    -- player pressed, and shots and wands count as swings. A bleed that
    -- couldn't be put to an ability was still an ability's doing.
    local spell = hit.spell
    if spell == ns.Guess.TICK then
        return "ability"
    end
    if spell and spell ~= ns.Guess.MELEE_SWING and ns.Sources.Kind(spell) ~= "auto" then
        return "ability"
    end
    return "auto"
end

local function ColorFor(hit)
    local scheme = ns.settings.colorBy
    if scheme ~= BY_KIND and scheme ~= MAGIC_ONLY then
        return WHITE
    end

    local kind = KindOf(hit)
    if kind == "magic" then
        return SCHOOL_COLORS[hit.school] or MAGIC
    end
    return scheme == BY_KIND and KIND_COLORS[kind] or WHITE
end

local function LookFor(hit)
    local color = ColorFor(hit)

    local scale = 1
    if hit.crit then
        color = CRIT_COLORS[ns.settings.critStyle] or color
        scale = (tonumber(ns.settings.critSize) or USUAL_CRIT_SIZE) / 100
    elseif hit.glancing then
        scale = GLANCING_SCALE
    end

    return { r = color[1], g = color[2], b = color[3], scale = scale, crit = hit.crit }
end

-- Icons ---------------------------------------------------------------------
--
-- Every number gets one, when icons are on. A blow traced to an ability
-- has that ability's icon. A tick of something over time has a small dot
-- in the colour of its school, which sets ticks apart from blows at a
-- glance. A blow that couldn't be traced at all has a plain picture for
-- its school of damage, drawn faint, since it's a guess about a guess.

-- The game's own pictures for each school of magic, as its character
-- sheet shows them, by school.
local SCHOOL_ICON = "Interface\\PaperDollInfoFrame\\SpellSchoolIcon"
local SCHOOL_ICONS = { [2] = 2, [4] = 3, [8] = 4, [16] = 5, [32] = 6, [64] = 7 }

-- A bleed's dot, and how solid an untraced blow's picture is drawn.
local BLEED = { 0.85, 0.2, 0.15 }
local FAINT = 0.6

--- Sets a hit's icon, or its dot, on its look.
local function GiveIcon(look, hit)
    if not ns.settings.icons then
        return
    end

    if hit.tick then
        look.dot = SCHOOL_COLORS[hit.school] or (hit.school == 1 and BLEED) or MAGIC
        return
    end

    local spell = hit.spell
    if spell and spell ~= ns.Guess.TICK then
        look.icon = C_Spell.GetSpellTexture(spell)
        if look.icon then
            return
        end
    end

    -- Untraced. A spell's school has a picture of its own; a physical blow
    -- has the plain weapon swing's.
    local index = SCHOOL_ICONS[hit.school]
    if index then
        look.icon = SCHOOL_ICON .. index
    else
        look.icon = C_Spell.GetSpellTexture(ns.Guess.MELEE_SWING)
    end
    look.iconAlpha = FAINT
end

--- Puts one hit in the lane.
---@param stand table|nil  a frame to pin it to instead of a nameplate
local function Draw(hit, stand)
    if hit.avoided then
        if ns.settings.showMisses then
            -- The game's own words for these, in the player's language.
            local word = CombatFeedbackText and CombatFeedbackText[hit.avoided] or hit.avoided
            local look = { r = GREY[1], g = GREY[2], b = GREY[3], scale = WORD_SCALE }

            -- No icon, but its place kept, so that beside a nameplate the
            -- word lines up with the numbers in the column.
            look.slot = ns.settings.icons
            ns.Lane.Show(word, look, hit.unit, stand)
        end
        return
    end

    local look = LookFor(hit)
    GiveIcon(look, hit)
    ns.Lane.Show(hit.amount, look, hit.unit, stand)
end

ns.Subscribe("TARGET_HIT", function(hit)
    if Showing() then
        Draw(hit)
    end
end)

-- Made-up hits for the example in the options: a plausible run of a
-- fight with one of everything in it. The spells are only there for
-- their icons, and one the client doesn't know simply has none.
local SAMPLES = {
    { amount = 41, kind = "auto", school = 1, spell = 6603 },
    { amount = 88, kind = "ability", school = 1, spell = 78 },
    { amount = 38, kind = "auto", school = 1, spell = 6603 },
    { amount = 124, kind = "magic", school = 4, spell = 133 },
    { amount = 97, kind = "auto", school = 1, spell = 6603, crit = true },
    { avoided = "DODGE" },
    { amount = 14, kind = "ability", school = 1, tick = true },
    { amount = 44, kind = "auto", school = 1, spell = 6603 },
    { amount = 22, kind = "magic", school = 8, tick = true },
    { amount = 31, kind = "magic", school = 32 },
    { amount = 213, kind = "ability", school = 1, spell = 78, crit = true },
}
local nextSample = 0

--- Shows the next made-up hit.
---@param stand table  the frame to pin it to
function Feed.ShowSample(stand)
    nextSample = nextSample % #SAMPLES + 1
    Draw(SAMPLES[nextSample], stand)
end

-- Blizzard's numbers ---------------------------------------------------------

-- True while it's us holding Blizzard's numbers off, this session.
local hiding = false

-- Whether "off" found in the game's setting can be taken as the player's
-- own choice. Not at first: straight after login it might be our doing,
-- left behind when the game closed badly.
local offIsTheirs = false

--- Puts Blizzard's numbers back the way the player had them.
local function PutBack()
    local db = ns.db

    -- If they're on, the player switched them on in the game's options
    -- while we had them off. That's their choice now; leave it be.
    if GetCVar(BLIZZARD_DAMAGE_TEXT) == "0" and db.blizzardDamageText then
        SetCVar(BLIZZARD_DAMAGE_TEXT, db.blizzardDamageText)
    end
    hiding = false
end

--- Switches Blizzard's damage numbers off while the lane is showing, and
--- back to the player's own setting when it isn't.
local function LookAfterBlizzardNumbers()
    local db = ns.db
    local wantHidden = Showing() and ns.settings.hideBlizzardNumbers

    if wantHidden and not hiding then
        -- What the player has it set to is remembered in the saved data
        -- and kept there, so it survives the game closing badly while the
        -- numbers are off. "0" found at login could be that, so then it
        -- only counts as the player's choice if there's nothing on record.
        local theirs = GetCVar(BLIZZARD_DAMAGE_TEXT)
        if theirs ~= "0" or offIsTheirs or db.blizzardDamageText == nil then
            db.blizzardDamageText = theirs or "1"
        end

        SetCVar(BLIZZARD_DAMAGE_TEXT, "0")
        hiding = true
    elseif not wantHidden and hiding then
        PutBack()
    end

    -- From here on, whenever we aren't hiding them, the setting is
    -- whatever the player has made it.
    offIsTheirs = true
end

ns.Subscribe("DATABASE_READY", LookAfterBlizzardNumbers)
ns.Subscribe("SETTINGS_CHANGED", LookAfterBlizzardNumbers)
ns.OnEvent("GROUP_ROSTER_UPDATE", LookAfterBlizzardNumbers)

-- The game saves that setting when it closes. Put the player's own value
-- back first, so that with Temper switched off or removed their
-- damage numbers are as they left them.
ns.OnEvent("PLAYER_LOGOUT", function()
    if ns.db and hiding then
        PutBack()
    end
end)
