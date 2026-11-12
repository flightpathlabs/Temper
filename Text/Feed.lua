local _, ns = ...

-- Decides what goes in the lane and what it looks like.
--
-- Also looks after Blizzard's own damage numbers: while the lane is
-- showing they'd say everything twice, so they're switched off, and put
-- back exactly as the player had them the moment the lane steps aside.

local Feed = {}
ns.Feed = Feed

local BLIZZARD_DAMAGE_TEXT = "floatingCombatTextCombatDamage_v2"

local CRIT_SCALE = 1.3
local GLANCING_SCALE = 0.85
local WORD_SCALE = 0.7

local WHITE = { 1, 1, 1 }
local GREY = { 0.72, 0.72, 0.72 }

-- Spell damage by school, in colours close to the ones the game uses for
-- them elsewhere. Physical damage isn't listed and stays white.
local SCHOOL_COLORS = {
    [2] = { 1, 0.9, 0.5 }, -- holy
    [4] = { 1, 0.5, 0.2 }, -- fire
    [8] = { 0.55, 1, 0.45 }, -- nature
    [16] = { 0.5, 0.85, 1 }, -- frost
    [32] = { 0.72, 0.6, 1 }, -- shadow
    [64] = { 1, 0.6, 1 }, -- arcane
}

-- Critical hits, by the critStyle setting. The third style keeps the
-- hit's own colour and relies on size alone.
local CRIT_COLORS = {
    { 1, 0.82, 0 },
    { 1, 0.27, 0.2 },
}

--- True while the lane should be drawing: switched on, and nobody else
--- around whose hits would be mistaken for the player's.
local function Showing()
    return ns.settings.lane and not IsInGroup()
end

local function LookFor(hit)
    local color = WHITE
    if ns.settings.schoolColors and SCHOOL_COLORS[hit.school] then
        color = SCHOOL_COLORS[hit.school]
    end

    local scale = 1
    if hit.crit then
        color = CRIT_COLORS[ns.settings.critStyle] or color
        scale = CRIT_SCALE
    elseif hit.glancing then
        scale = GLANCING_SCALE
    end

    return { r = color[1], g = color[2], b = color[3], scale = scale, crit = hit.crit }
end

--- The icon of the ability a hit most likely was, if icons are wanted and
--- there's a guess to be had.
local function IconFor(hit)
    if not ns.settings.icons then
        return nil
    end

    return hit.spell and C_Spell.GetSpellTexture(hit.spell)
end

ns.Subscribe("TARGET_HIT", function(hit)
    if not Showing() then
        return
    end

    if hit.avoided then
        if ns.settings.showMisses then
            -- The game's own words for these, in the player's language.
            local word = CombatFeedbackText and CombatFeedbackText[hit.avoided] or hit.avoided
            local look = { r = GREY[1], g = GREY[2], b = GREY[3], scale = WORD_SCALE }
            ns.Lane.Show(word, look, hit.unit)
        end
        return
    end

    local look = LookFor(hit)
    look.icon = IconFor(hit)
    ns.Lane.Show(hit.amount, look, hit.unit)
end)

-- Made-up hits for the options preview: plausible amounts, and the
-- auto-attack icon when icons are switched on.
local SAMPLES = { 41, 38, 12, 97, 44 }
local nextSample = 0

--- Shows one made-up hit.
---@param crit boolean  make this one a critical hit
function Feed.ShowSample(crit)
    nextSample = nextSample % #SAMPLES + 1

    local look = LookFor({ crit = crit, school = 1 })
    if ns.settings.icons then
        look.icon = C_Spell.GetSpellTexture(6603)
    end
    ns.Lane.Show(crit and 97 or SAMPLES[nextSample], look)
end

-- Blizzard's numbers ---------------------------------------------------------

-- True while it's us holding Blizzard's numbers off, this session.
local hiding = false

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
        -- numbers are off. "0" found here could be that, so it only
        -- counts as the player's choice when there's nothing on record.
        local theirs = GetCVar(BLIZZARD_DAMAGE_TEXT)
        if theirs ~= "0" or db.blizzardDamageText == nil then
            db.blizzardDamageText = theirs or "1"
        end

        SetCVar(BLIZZARD_DAMAGE_TEXT, "0")
        hiding = true
    elseif not wantHidden and hiding then
        PutBack()
    end
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
