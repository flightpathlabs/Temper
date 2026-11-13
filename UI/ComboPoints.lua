local _, ns = ...

-- Combo points: a row of small pips just under the target's nameplate,
-- lit as a rogue, or a druid in cat form, builds them up.
--
-- Under the nameplate because everything else is above it or beside it.
-- The damage numbers rise from its top or from its sides, whichever side
-- and distance they're set to, and the game puts the enemy's name, its
-- debuffs and any raid mark above the health bar. The bottom of a
-- nameplate is where the enemy's cast bar shows, so the pips sit just
-- below that, where nothing else is drawn.
--
-- The game may keep the count from addons, so it's never read to light
-- the pips. Each pip is a status bar of its own spanning one point: the
-- first runs from none to one, the second from one to two, and so on.
-- The count is handed to every one of them, and the game draws each full
-- once the count has reached its point and empty before that. So the row
-- lights up to the count without Temper knowing what the count is. When
-- the count can be read, the row also goes away out of a fight once the
-- points are spent, as the game's own does on the target's portrait. When
-- it can't, the empty pips stay while there's an enemy targeted.
--
-- The row is pinned to the nameplate the way the damage numbers are (see
-- Text\Lane.lua): it follows the enemy without our doing anything, and is
-- only ever moved by its offsets, never measured. With no nameplate there
-- is no row. Pips somewhere else on the screen would only confuse.
--
-- It's updated when the game says the points, the target or its nameplate
-- changed, never every frame, and it shows in a group too, since it's
-- only about the player's own next press.

local ComboPoints = {}
ns.ComboPoints = ComboPoints

-- The classes that build combo points, as the game names classes in
-- English whatever the language. A druid only does in cat form.
local BUILDERS = { ROGUE = true, DRUID = true }

-- As many pips as the game says the player can hold, five if it won't
-- say, and never more than this, whatever it says.
local USUAL_PIPS = 5
local MOST_PIPS = 10

-- The game's own pip, as on the target's portrait: a frame 20 across,
-- with 4 between pips, drawn at 0.6 of its size there.
local PIP_SIZE = 20
local SPACING = 4
local SCALE = 0.6

-- The space between the bottom of the nameplate and the row.
local GAP = 2

-- The game's combo point art, by part: a soft shadow below, the empty
-- socket, the lit socket and the gem that fills it. The shadow sits a
-- little low, as the game draws it.
local ART = {
    shadow = "uf-roguecp-bg-shadow",
    empty = "uf-roguecp-bg-dis",
    socket = "uf-roguecp-bg",
    gem = "uf-roguecp-icon-red",
}
local SHADOW_DROP = 4

-- Should the game not have that art: a plain white disc, which the game
-- keeps for cutting portraits round, tinted. Lit in the game's colour for
-- combo points, or this, its value, if the game hasn't one to ask.
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local DOT_SIZE = 10
local EMPTY_DOT = { 0.12, 0.12, 0.12, 0.85 }
local LIT_DOT = { 1, 0.96, 0.41 }

-- A nameplate can vanish between being found and being pinned to, which
-- is no reason to give up on nameplates. This many refusals in a row,
-- with no success between them, is.
local REFUSALS_ALLOWED = 3

local IsSecret = issecretvalue or function()
    return false
end

local row
local pips = {}
local shown = 0

-- The nameplate the row is pinned to, while it is.
local pinnedTo

local refusals = 0

-- For /temper check: the game's own words when it wouldn't pin the row
-- often enough to give up, wouldn't give the count at all, or wouldn't
-- draw it. Any one of them and the row stays hidden for the session.
ComboPoints.refusal = nil
ComboPoints.unreadable = nil
ComboPoints.undrawable = nil

-- Also for /temper check: whether the plain dots stand in for the game's
-- art, and whether the game has been seen keeping the count hidden.
ComboPoints.plainArt = false
ComboPoints.seenHidden = false

--- Asks something that may be refused. Nothing if it was, or if the
--- answer is one we may not read.
local function Read(method, ...)
    if not method then
        return nil
    end

    local ok, value = pcall(method, ...)
    if not ok or IsSecret(value) then
        return nil
    end
    return value
end

-- Who and what -----------------------------------------------------------------------

--- The player's class, as the game names it in English, if it will say.
local function PlayerClass()
    local ok, _, class = pcall(UnitClass, "player")
    if not ok or IsSecret(class) then
        return nil
    end
    return class
end

--- True for a character of a class that builds combo points, in any form.
function ComboPoints.ForThisClass()
    return BUILDERS[PlayerClass() or ""] == true
end

--- True while the player has combo points to build: a rogue always, a
--- druid only in cat form, which the game tells by the druid's power
--- being energy, as its own combo point bar does.
local function Building()
    local class = PlayerClass()
    if not BUILDERS[class or ""] then
        return false
    end

    if class == "DRUID" then
        return Read(UnitPowerType, "player") == Enum.PowerType.Energy
    end
    return true
end

--- True for a target combo points can be built on. If the game won't say,
--- it's taken as an enemy and alive, as the damage numbers take it.
local function FitTarget()
    if Read(UnitExists, "target") ~= true then
        return false
    end
    return Read(UnitCanAttack, "player", "target") ~= false and Read(UnitIsDead, "target") ~= true
end

local function TargetPlate()
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
    return ok and plate or nil
end

--- How many pips to show: as many points as the player can hold.
local function PipCount()
    local most = Read(UnitPowerMax, "player", Enum.PowerType.ComboPoints)
    if type(most) == "number" and most >= 1 then
        return math.min(math.floor(most), MOST_PIPS)
    end
    return USUAL_PIPS
end

--- The points on the target, as the game gives them: a plain number, one
--- we may only hand on, or nothing if it won't say at all.
local function Count()
    local asked, count = pcall(GetComboPoints, "player", "target")
    if asked and (IsSecret(count) or type(count) == "number") then
        return count
    end

    -- The way the game's own druid bar asks, should the first be refused.
    local askedPower, power = pcall(UnitPower, "player", Enum.PowerType.ComboPoints)
    if askedPower and (IsSecret(power) or type(power) == "number") then
        return power
    end

    if not asked then
        ComboPoints.unreadable = tostring(count)
    elseif not askedPower then
        ComboPoints.unreadable = tostring(power)
    else
        ComboPoints.unreadable = "it gave no count"
    end
    return nil
end

-- Building the row -----------------------------------------------------------------------

local function Scaled(size)
    return size * SCALE
end

--- The size the game draws a piece of its art at, if it has that piece.
local function ArtSize(atlas)
    local info = Read(C_Texture and C_Texture.GetAtlasInfo, atlas)
    if type(info) ~= "table" or not info.width or not info.height then
        return nil
    end
    return info.width, info.height
end

local function HaveArt()
    return ArtSize(ART.empty) ~= nil and ArtSize(ART.socket) ~= nil and ArtSize(ART.gem) ~= nil
end

--- A status bar that's full once the count reaches `point`, and empty
--- below it. It starts empty.
local function NewBar(parent, point)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetMinMaxValues(point - 1, point)
    bar:SetValue(point - 1)
    return bar
end

--- A pip in the game's own art. The lit socket is a bar, and the gem a
--- bar on top of it, so both light together.
local function NewGemPip(pip, point)
    local width, height = ArtSize(ART.shadow)
    if width then
        local shadow = pip:CreateTexture(nil, "BACKGROUND")
        shadow:SetAtlas(ART.shadow)
        shadow:SetSize(Scaled(width), Scaled(height))
        shadow:SetPoint("CENTER", 0, -Scaled(SHADOW_DROP))
    end

    local empty = pip:CreateTexture(nil, "BACKGROUND", nil, 1)
    empty:SetAtlas(ART.empty)
    width, height = ArtSize(ART.empty)
    empty:SetSize(Scaled(width), Scaled(height))
    empty:SetPoint("CENTER")

    local socket = NewBar(pip, point)
    socket:SetStatusBarTexture(ART.socket)
    width, height = ArtSize(ART.socket)
    socket:SetSize(Scaled(width), Scaled(height))
    socket:SetPoint("CENTER")

    local gem = NewBar(socket, point)
    gem:SetStatusBarTexture(ART.gem)
    width, height = ArtSize(ART.gem)
    gem:SetSize(Scaled(width), Scaled(height))
    gem:SetPoint("CENTER", pip, "CENTER")

    pip.bars = { socket, gem }
end

--- A pip as a plain dot: a dark one, and a bar of the lit colour over it.
local function NewDotPip(pip, point)
    local empty = pip:CreateTexture(nil, "BACKGROUND")
    empty:SetTexture(DISC)
    empty:SetVertexColor(EMPTY_DOT[1], EMPTY_DOT[2], EMPTY_DOT[3], EMPTY_DOT[4])
    empty:SetAllPoints()

    local lit = PowerBarColor and PowerBarColor.COMBO_POINTS
    local bar = NewBar(pip, point)
    bar:SetStatusBarTexture(DISC)
    if lit then
        bar:SetStatusBarColor(lit.r, lit.g, lit.b)
    else
        bar:SetStatusBarColor(LIT_DOT[1], LIT_DOT[2], LIT_DOT[3])
    end
    bar:SetAllPoints()

    pip.bars = { bar }
end

local function PipSize()
    return ComboPoints.plainArt and DOT_SIZE or Scaled(PIP_SIZE)
end

local function PipStep()
    return ComboPoints.plainArt and DOT_SIZE + SPACING or Scaled(PIP_SIZE + SPACING)
end

local function NewPip(point)
    local pip = CreateFrame("Frame", nil, row)
    pip:SetSize(PipSize(), PipSize())
    pip:SetPoint("LEFT", (point - 1) * PipStep(), 0)

    if ComboPoints.plainArt then
        NewDotPip(pip, point)
    else
        NewGemPip(pip, point)
    end

    pips[point] = pip
    return pip
end

--- Makes the row as long as the player's points. Only done while the row
--- is pinned to nothing, so its size can be set without the game minding.
local function Lay(count)
    if count == shown then
        return
    end
    shown = count

    for point = 1, math.max(count, #pips) do
        local pip = pips[point] or NewPip(point)
        pip:SetShown(point <= count)
    end
    row:SetSize(count * PipStep() - (PipStep() - PipSize()), PipSize())
end

local function Create()
    -- A frame of our own, sitting under the game's windows like the
    -- damage numbers, and hidden with the rest of the interface.
    row = CreateFrame("Frame", nil, UIParent)
    row:SetFrameStrata("LOW")
    row:EnableMouse(false)
    row:Hide()

    ComboPoints.plainArt = not HaveArt()
end

-- Pinning ------------------------------------------------------------------------------

local function Unpin()
    pinnedTo = nil
    row:Hide()
    row:ClearAllPoints()
end

--- Pins the row under a nameplate. If the game won't have it, the row
--- stays hidden; if it keeps refusing, nameplates are left alone.
local function Pin(plate)
    local ok, problem = pcall(row.SetPoint, row, "TOP", plate, "BOTTOM", 0, -GAP)
    if ok then
        refusals = 0
        pinnedTo = plate
        return
    end

    Unpin()
    refusals = refusals + 1
    if refusals >= REFUSALS_ALLOWED then
        ComboPoints.refusal = tostring(problem)
    end
end

-- Drawing ------------------------------------------------------------------------------

--- Hands the count to the pips to draw, and shows the row unless the
--- points are known to be spent outside a fight.
local function Draw()
    if not pinnedTo or ComboPoints.undrawable then
        return
    end

    local count = Count()
    if count == nil then
        Unpin()
        return
    end

    for point = 1, shown do
        for _, bar in ipairs(pips[point].bars) do
            local ok, problem = pcall(bar.SetValue, bar, count)
            if not ok then
                ComboPoints.undrawable = tostring(problem)
                Unpin()
                return
            end
        end
    end

    if IsSecret(count) then
        ComboPoints.seenHidden = true
        row:Show()
        return
    end
    row:SetShown(count > 0 or InCombatLockdown())
end

--- Works out afresh whether the row belongs on screen, and where.
local function Refresh()
    if not row or not ns.settings then
        return
    end

    Unpin()
    local given = ComboPoints.refusal or ComboPoints.unreadable or ComboPoints.undrawable
    if given or not ns.settings.comboPoints or not Building() or not FitTarget() then
        return
    end

    local plate = TargetPlate()
    if not plate then
        return
    end

    Lay(PipCount())
    Pin(plate)
    Draw()
end

--- The nameplate a unit has just been given or is losing, and whether that
--- unit is the target. Either can be nil when the game won't say.
local function PlateOf(unit)
    if IsSecret(unit) or type(unit) ~= "string" then
        return nil, nil
    end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    return ok and plate or nil, Read(UnitIsUnit, unit, "target")
end

--- The game takes nameplates back and hands them out again to other
--- enemies, so a nameplate coming along may be the target's, or may be
--- the very one the row is pinned to, now some other enemy's. Unless it's
--- plainly another enemy's on another nameplate, the row is worked out
--- again.
local function OnPlateAdded(unit)
    local plate, isTarget = PlateOf(unit)
    if pinnedTo and plate and plate ~= pinnedTo and isTarget ~= true then
        return
    end
    Refresh()
end

--- A nameplate is going. If it's the one the row is pinned to, or the game
--- won't say which it is, the row comes off before the game hands that
--- nameplate to some other enemy. It's looked at again a moment later,
--- once the nameplate has gone.
local function OnPlateRemoved(unit)
    if not pinnedTo then
        return
    end

    local plate = PlateOf(unit)
    if plate and plate ~= pinnedTo then
        return
    end

    Unpin()
    C_Timer.After(0, Refresh)
end

-- For /temper check ---------------------------------------------------------------------

--- How the combo points are getting on with the game, as lines of text
--- for /temper check. Nothing for a class without combo points.
---@return table  list of strings
function ComboPoints.CheckLines()
    local lines = {}
    if not ns.settings or not ComboPoints.ForThisClass() then
        return lines
    end

    if not ns.settings.comboPoints then
        table.insert(
            lines,
            (
                "Combo points under your target are off. They can be switched on in "
                .. "Options > AddOns > %s."
            ):format(ns.TITLE)
        )
        return lines
    end

    if ComboPoints.undrawable then
        table.insert(
            lines,
            "The game wouldn't let Temper draw your combo points, so they aren't shown: "
                .. ComboPoints.undrawable
        )
    elseif ComboPoints.unreadable then
        table.insert(
            lines,
            "The game wouldn't give Temper your combo points, so they aren't shown: "
                .. ComboPoints.unreadable
        )
    elseif ComboPoints.refusal then
        table.insert(
            lines,
            "The game wouldn't pin your combo points to your target's nameplate, so they "
                .. "aren't shown: "
                .. ComboPoints.refusal
        )
    else
        local line = "Combo points show under your target's nameplate."
        if ComboPoints.seenHidden then
            line = line
                .. " The game keeps the count from addons at times, so Temper hands it "
                .. "to the game to draw, and the empty pips stay while you have an enemy "
                .. "targeted."
        end
        if not GetCVarBool("nameplateShowEnemies") then
            line = line .. " Enemy nameplates are switched off, so there's nothing to show them on."
        end
        table.insert(lines, line)
    end

    if ComboPoints.plainArt then
        table.insert(lines, "The game's combo point art wasn't found, so plain dots stand in.")
    end
    return lines
end

-- Events -------------------------------------------------------------------------------

ns.Subscribe("DATABASE_READY", function()
    Create()
    Refresh()
end)
ns.Subscribe("SETTINGS_CHANGED", Refresh)

ns.OnEvent("PLAYER_ENTERING_WORLD", Refresh)
ns.OnEvent("PLAYER_TARGET_CHANGED", Refresh)
ns.OnEvent("NAME_PLATE_UNIT_ADDED", OnPlateAdded)
ns.OnEvent("NAME_PLATE_UNIT_REMOVED", OnPlateRemoved)

-- Points moved to a new target keep their count, so no power event comes
-- with that, only this one.
ns.OnEvent("COMBO_TARGET_CHANGED", Draw)

-- Spent points stay up through a fight and go once it's over.
ns.OnEvent("PLAYER_REGEN_DISABLED", Draw)
ns.OnEvent("PLAYER_REGEN_ENABLED", Draw)

-- Our own frame for the player's power, registered for the player alone.
-- The shared one would hear about every nameplate's as well. A change in
-- the count only needs drawing; a change in how many can be held, or in
-- the kind of power (a druid shifting in or out of cat form), needs the
-- row worked out again.
local POWER_EVENTS =
    { "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }

local powerWatch = CreateFrame("Frame")
for _, event in ipairs(POWER_EVENTS) do
    pcall(powerWatch.RegisterUnitEvent, powerWatch, event, "player")
end
powerWatch:SetScript("OnEvent", function(_, event)
    if event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
        Draw()
    else
        Refresh()
    end
end)
