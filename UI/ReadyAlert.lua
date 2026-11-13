local _, ns = ...

-- The warning box: a few short lines just above the fight panel when
-- something would be better put right before a fight, each with a small
-- picture. What counts, and when, is Combat\Readiness.lua's to say; this
-- file only draws it.
--
-- It hangs from the panel, so it moves with it, is the same width and
-- wears the same border, grows with it when the panel is drawn large, and
-- it hides when the panel does. It grows a line at a time and goes away
-- when there's nothing to say. It never takes a click. It's quiet: the
-- one time it raises its voice is a fight begun with a fishing pole in
-- hand, when that line and the border turn red and the alert sound chosen
-- in the options plays once. A sample shows while Temper's options are
-- open (see Example.lua).

local ReadyAlert = {}
ns.ReadyAlert = ReadyAlert

local Kit = ns.Kit

-- The same measures as the panel's own lines, so the two read as one.
local LINE_HEIGHT = 14
local ICON_SIZE = 12
local ICON_GAP = 5
local SIDE = 10
local TOP_AND_BOTTOM = 7

-- The space between the box and the panel it sits on.
local GAP = 2

local SOFT = { 0.9, 0.9, 0.9 }
local URGENT = Kit.BAD

-- What the box says while the options are open, so its look can be
-- judged. The picture is the plain Fishing Pole's, by the classic game's
-- item ID, which couldn't be checked against this client's source. Should
-- the game not know it, the line wears the warning sign instead.
local SAMPLE_TEXT = "Fishing pole still in hand"
local SAMPLE_ITEM = 6256

-- The sound for a box that turns red, should the ability alert's own file
-- not be there to ask (straight after an update, before a restart).
local FALLBACK_SOUND = "MAP_PING"

local box
local rows = {}
local sampleShowing = false

-- The lines that asked for a sound and have had it, so one is played only
-- as such a line appears.
local sounded = {}

-- Sound -------------------------------------------------------------------------

--- Plays the alert sound chosen in the options, unless that's "No sound".
local function PlaySoundOnce()
    if ns.ProcAlert then
        ns.ProcAlert.Play(ns.settings.procSound)
        return
    end

    -- Only straight after an update, before the game is restarted.
    local kit = SOUNDKIT and SOUNDKIT[FALLBACK_SOUND]
    if kit then
        pcall(PlaySound, kit, "SFX")
    end
end

-- Lines ---------------------------------------------------------------------------

local function CreateRow(index)
    local top = TOP_AND_BOTTOM + (index - 1) * LINE_HEIGHT
    local row = {}

    row.icon = Kit.Icon(box, ICON_SIZE)
    row.icon:SetPoint("TOPLEFT", SIDE, -(top + 1))

    row.text = Kit.Text(box, "GameFontHighlightSmall")
    row.text:SetPoint("TOPLEFT", SIDE + ICON_SIZE + ICON_GAP, -top)
    row.text:SetPoint("RIGHT", -SIDE, 0)

    rows[index] = row
    return row
end

local function Fill(row, item)
    if item.icon then
        Kit.SetSpellIcon(row.icon, item.icon)
    else
        Kit.SetIcon(row.icon, "warning")
    end

    row.text:SetText(item.text)
    local color = item.urgent and URGENT or SOFT
    row.text:SetTextColor(color[1], color[2], color[3])

    row.icon:Show()
    row.text:Show()
end

local function SampleItem()
    local ok, _, _, _, _, icon = pcall(C_Item.GetItemInfoInstant, SAMPLE_ITEM)
    return {
        key = "sample",
        text = Kit.Colored("Example:", Kit.MUTED) .. " " .. SAMPLE_TEXT,
        icon = ok and icon or nil,
    }
end

-- Drawing -------------------------------------------------------------------------

--- What's to be shown now: the sample first, while there is one.
local function Wanted()
    local items = {}
    if sampleShowing and ns.settings.readyAlert then
        table.insert(items, SampleItem())
    end
    if ns.settings.readyAlert and ns.Readiness then
        for _, problem in ipairs(ns.Readiness.Problems()) do
            table.insert(items, problem)
        end
    end
    return items
end

--- Above the panel, or under it when the panel is so near the top of the
--- screen that there's no room above.
local function Place(height)
    local panel = box:GetParent()
    local top, screenTop = panel:GetTop(), UIParent:GetTop()

    -- A panel drawn large measures its edges at its own scale, and so does
    -- the box hanging from it, so both sides are brought to the screen's
    -- measure before they're compared.
    local roomAbove = not (top and screenTop)
        or (top + GAP + height) * panel:GetEffectiveScale()
            <= screenTop * UIParent:GetEffectiveScale()

    box:ClearAllPoints()
    if roomAbove then
        box:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, GAP)
        box:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, GAP)
    else
        box:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -GAP)
        box:SetPoint("TOPRIGHT", panel, "BOTTOMRIGHT", 0, -GAP)
    end
end

local function Redraw()
    if not box then
        return
    end

    local items = Wanted()
    local urgent, due = false, false
    local heard = {}

    for index, item in ipairs(items) do
        Fill(rows[index] or CreateRow(index), item)
        urgent = urgent or item.urgent

        if item.sound then
            heard[item.key] = true
            due = due or not sounded[item.key]
        end
    end
    sounded = heard

    for index = #items + 1, #rows do
        rows[index].icon:Hide()
        rows[index].text:Hide()
    end

    if urgent then
        box:SetBackdropBorderColor(URGENT[1], URGENT[2], URGENT[3], 1)
    else
        box:SetBackdropBorderColor(1, 1, 1, 1)
    end

    local height = 2 * TOP_AND_BOTTOM + #items * LINE_HEIGHT
    box:SetHeight(height)
    Place(height)
    box:SetShown(#items > 0)

    -- Not a sound for a box nobody can see, with the panel switched off
    -- or the interface hidden.
    if due and box:IsVisible() then
        PlaySoundOnce()
    end
end

-- Building it ----------------------------------------------------------------------

local function Create()
    local panel = ns.FightPanel and ns.FightPanel()
    if not panel then
        return
    end

    -- A child of the panel, so it goes wherever the panel goes and hides
    -- with it, with the game's tooltip border to match.
    box = CreateFrame("Frame", nil, panel, "TooltipBackdropTemplate")

    -- Dragged to the top of the screen, the panel leaves no room above it,
    -- and the box has to move below. Dragged back down, it goes back up.
    panel:HookScript("OnDragStop", function()
        Redraw()
    end)
    box:SetHeight(2 * TOP_AND_BOTTOM + LINE_HEIGHT)
    box:EnableMouse(false)
    box:Hide()
end

--- Shows the sample line while the options are open, or puts it away. It's
--- asked often, so does nothing unless the answer has changed.
---@param wanted boolean  true while the example in the options is showing
function ReadyAlert.Sample(wanted)
    wanted = wanted and box ~= nil and ns.settings.readyAlert or false
    if wanted == sampleShowing then
        return
    end
    sampleShowing = wanted
    Redraw()
end

-- The panel is made when the saved data is ready, by a handler that was
-- subscribed before this one, so it's there by now.
ns.Subscribe("DATABASE_READY", function()
    Create()
    Redraw()
end)

ns.Subscribe("READINESS_CHANGED", Redraw)
ns.Subscribe("SETTINGS_CHANGED", Redraw)
