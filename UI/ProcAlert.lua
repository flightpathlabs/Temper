local _, ns = ...

-- The ability alert: the icon of an ability that has just become the best
-- thing to press, a little below the middle of the screen, until it's used
-- or the moment passes. What counts, and when, is Combat\Procs.lua's to
-- say; this file only draws it.
--
-- It's off unless asked for, in the options. Each icon is a touch larger
-- than an action button, ringed with the game's own proc glow, with the
-- ability's name under it and, when the game lets a buff's time be read, a
-- sweep across it as that runs out. Several at once sit side by side.
--
-- It never takes a click: in a fight, a stray one on it would be a click
-- lost. It can be dragged only while Temper's options page shows a sample
-- of it, and it's kept there. Unlike the damage numbers it stays in a
-- group, since it's about the player's own next press and records
-- nothing.

local ProcAlert = {}
ns.ProcAlert = ProcAlert

local Kit = ns.Kit

-- An action button is 45 across.
local ICON_SIZE = 52
local SLOT_WIDTH = 84
local SLOT_GAP = 6
local NAME_GAP = 4
local SLOT_HEIGHT = ICON_SIZE + NAME_GAP + 12

-- The action bar's icon frame is a pixel wider than its icon, and the
-- cooldown inside it sits three in from each edge.
local FRAME_WIDTH = ICON_SIZE * 46 / 45
local SWEEP_INSET = 3

-- The game draws its proc glow 1.4 times the button it rings, and the
-- burst that opens it 150 across for a 45-pixel button.
local GLOW_SCALE = 1.4
local BURST_SIZE = ICON_SIZE * 150 / 45

-- Where it starts out: just below the middle of the screen, under the
-- player's character and clear of the damage numbers, which keep above.
local START_X = 0
local START_Y = -140

-- A sound for an alert is never played again for the same ability this
-- soon after the last, and two that come on together share one.
local SOUND_AGAIN_SECONDS = 2
local SOUND_APART_SECONDS = 0.3

-- The made-up alert shown while the options are open: a druid's
-- Clearcasting, with its time running out and starting again.
local SAMPLE_SPELL = 16870
local SAMPLE_NAME = "Clearcasting"
local SAMPLE_SECONDS = 15

-- The choices of sound, in the order the options list them. These are a
-- few of the alert sounds the game itself offers for its cooldown alerts
-- (see Blizzard_CooldownViewer's CooldownViewerSoundAlertData.lua), made
-- to be heard over a fight. Each is named by the game's own words for it
-- where it has them, in the player's language.
ProcAlert.SOUNDS = {
    { label = "No sound" },
    { label = "Anvil Strike", kit = 316528, words = "CDMSND_IMPACTS_ANVIL_STRIKE" },
    { label = "Sword Shing", kit = 353421, words = "CDMSND_SHORT_SWORD_SHING" },
    { label = "Bell Strike", kit = 353392, words = "CDMSND_SHORT_BELL_STRIKE" },
    { label = "Metal Impact", kit = 353408, words = "CDMSND_SHORT_METAL_IMPACT" },
    { label = "Blades", kit = 353389, words = "CDMSND_SHORT_BLADES" },
    { label = "Triangle", kit = 353423, words = "CDMSND_SHORT_TRIANGLE" },
    { label = "Kalimba", kit = 353405, words = "CDMSND_SHORT_KALIMBA" },
    { label = "Synth Bleep", kit = 353402, words = "CDMSND_SHORT_SYNTH_BLEEP" },
    { label = "Chime Ascending", kit = 316447, words = "CDMSND_INSTRUMENTS_CHIME_ASCENDING" },
    { label = "Bell Ring", kit = 316493, words = "CDMSND_INSTRUMENTS_BELL_RING" },
    { label = "Low Thud", kit = 316531, words = "CDMSND_IMPACTS_LOW_THUD" },
    { label = "Warhorn", kit = 316723, words = "CDMSND_INSTRUMENTS_WARHORN" },
}

for _, sound in ipairs(ProcAlert.SOUNDS) do
    local words = sound.words and _G[sound.words]
    if type(words) == "string" and words ~= "" then
        sound.label = words
    end
end

--- Plays one of the sounds above at the game's main volume, so that an
--- effects volume turned down for spells doesn't bury it. Falls back to
--- the effects volume if the game won't play it the first way.
---@param choice number  a place in ProcAlert.SOUNDS
function ProcAlert.Play(choice)
    local sound = ProcAlert.SOUNDS[choice]
    if not sound or not sound.kit then
        return
    end

    local ok, willPlay = pcall(PlaySound, sound.kit, "Master")
    if not ok or not willPlay then
        pcall(PlaySound, sound.kit, "SFX")
    end
end

local holder
local hint

-- Slots on screen by the alert they show, and spare ones.
local showing = {}
local spare = {}

local sampleShowing = false
local sampleStart = 0
local sampleTicker

-- When each alert last sounded, and when any did.
local soundedAt = {}
local lastSound = -math.huge

-- The sound setting as last seen, so a change can be played as a preview.
local soundChoice

-- Anything the client has objected to, by what was being tried. Each is
-- tried once and then left alone. /temper check reads these out.
ProcAlert.complaints = {}

local function Attempt(what, method, ...)
    if ProcAlert.complaints[what] then
        return false
    end

    local ok, problem = pcall(method, ...)
    if not ok then
        ProcAlert.complaints[what] = tostring(problem)
    end
    return ok
end

-- Sound ------------------------------------------------------------------------

local function PlayChosen()
    ProcAlert.Play(ns.settings.procSound)
end

--- Sounds for alerts that have just come on, once between them.
---@param fresh table  list of keys of alerts that weren't showing before
local function Sound(fresh)
    local now = GetTime()
    local due = false
    for _, key in ipairs(fresh) do
        if now - (soundedAt[key] or -math.huge) >= SOUND_AGAIN_SECONDS then
            due = true
        end
        soundedAt[key] = now
    end

    if due and now - lastSound >= SOUND_APART_SECONDS then
        lastSound = now
        PlayChosen()
    end
end

-- The glow ---------------------------------------------------------------------

--- The game's own proc glow, the one its action buttons wear. It's a plain
--- frame of art and animation, borrowed for a frame of ours: nothing about
--- the action buttons themselves is touched.
local function BorrowGlow(slot)
    local glow = CreateFrame("Frame", nil, slot, "ActionButtonSpellAlertTemplate")
    glow:SetSize(ICON_SIZE * GLOW_SCALE, ICON_SIZE * GLOW_SCALE)
    glow:SetPoint("CENTER", slot.icon)
    glow.ProcStartFlipbook:SetSize(BURST_SIZE, BURST_SIZE)

    return {
        Start = function()
            glow:Show()
            glow.ProcStartAnim:Play()
        end,
        Stop = function()
            glow.ProcStartAnim:Stop()
            glow.ProcLoop:Stop()
            glow:Hide()
        end,
    }
end

--- A soft pulse of our own, for a client without the game's glow.
local function MakePulse(slot)
    local pulse = slot:CreateTexture(nil, "OVERLAY", nil, 1)
    pulse:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    pulse:SetBlendMode("ADD")
    pulse:SetAllPoints(slot.icon)
    pulse:Hide()

    local throb = pulse:CreateAnimationGroup()
    throb:SetLooping("BOUNCE")
    local fade = throb:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.15)
    fade:SetToAlpha(0.7)
    fade:SetDuration(0.6)

    return {
        Start = function()
            pulse:Show()
            throb:Play()
        end,
        Stop = function()
            throb:Stop()
            pulse:Hide()
        end,
    }
end

local function StartGlow(slot)
    if not Attempt("glow", slot.glow.Start) then
        pcall(slot.glow.Stop)
    end
end

-- Slots ------------------------------------------------------------------------

local function CreateSweep(slot)
    local sweep = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    sweep:ClearAllPoints()
    sweep:SetPoint("TOPLEFT", slot.icon, "TOPLEFT", SWEEP_INSET, -SWEEP_INSET)
    sweep:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT", -SWEEP_INSET, SWEEP_INSET)
    sweep:SetDrawEdge(false)
    sweep:SetDrawBling(false)
    sweep:SetHideCountdownNumbers(true)

    -- Darkening as the time goes, the way the game's own buffs do.
    sweep:SetReverse(true)
    sweep:SetSwipeColor(0, 0, 0, 0.55)
    return sweep
end

local function MaskIcon(slot)
    local mask = slot:CreateMaskTexture()
    mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
    mask:SetAllPoints(slot.icon)
    slot.icon:AddMaskTexture(mask)
end

local function CreateSlot()
    local slot = CreateFrame("Frame", nil, holder)
    slot:SetSize(SLOT_WIDTH, SLOT_HEIGHT)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetSize(ICON_SIZE, ICON_SIZE)
    slot.icon:SetPoint("TOP")

    -- The action bar's own round-cornered frame, and the mask that keeps
    -- the icon's corners inside it.
    Attempt("mask", MaskIcon, slot)
    slot.frame = slot:CreateTexture(nil, "OVERLAY")
    slot.frame:SetAtlas("UI-HUD-ActionBar-IconFrame")
    slot.frame:SetSize(FRAME_WIDTH, ICON_SIZE)
    slot.frame:SetPoint("TOPLEFT", slot.icon)

    local made, sweep = pcall(CreateSweep, slot)
    slot.sweep = made and sweep or nil

    slot.name = Kit.Text(slot, "GameFontHighlightSmall", "CENTER")
    slot.name:SetPoint("TOP", slot.icon, "BOTTOM", 0, -NAME_GAP)
    slot.name:SetWidth(SLOT_WIDTH)

    local borrowed, glow = pcall(BorrowGlow, slot)
    slot.glow = borrowed and glow or MakePulse(slot)
    return slot
end

local function ClearSweep(slot)
    if slot.sweep then
        pcall(slot.sweep.Clear, slot.sweep)
    end
end

--- Starts a buff's sweep, or takes it away when there's no time to show.
local function SetSweep(slot, expires, duration)
    if not slot.sweep or slot.expires == expires then
        return
    end
    slot.expires = expires

    if expires and duration then
        Attempt("sweep", slot.sweep.SetCooldown, slot.sweep, expires - duration, duration)
    else
        ClearSweep(slot)
    end
end

local function Fill(slot, item)
    Kit.SetSpellIcon(slot.icon, item.icon)
    slot.name:SetText(item.name)
    SetSweep(slot, item.expires, item.duration)
end

local function Release(key)
    local slot = showing[key]
    showing[key] = nil
    pcall(slot.glow.Stop)
    slot.expires = nil
    ClearSweep(slot)
    slot:Hide()
    table.insert(spare, slot)
end

-- Drawing ----------------------------------------------------------------------

local function SampleItem()
    local now = GetTime()
    if now - sampleStart >= SAMPLE_SECONDS then
        sampleStart = now
    end

    local name = C_Spell.GetSpellName(SAMPLE_SPELL)
    return {
        key = "sample",
        name = name or SAMPLE_NAME,
        icon = C_Spell.GetSpellTexture(SAMPLE_SPELL),
        expires = sampleStart + SAMPLE_SECONDS,
        duration = SAMPLE_SECONDS,
    }
end

--- What's to be shown now: the sample first, while there is one.
local function Wanted()
    local items = ns.Procs.Active()
    if sampleShowing then
        local made, sample = pcall(SampleItem)
        if made then
            table.insert(items, 1, sample)
        end
    end
    return items
end

local function Redraw()
    if not holder then
        return
    end

    local items = Wanted()
    local wanted = {}
    for _, item in ipairs(items) do
        wanted[item.key] = true
    end
    for key in pairs(showing) do
        if not wanted[key] then
            Release(key)
        end
    end

    local fresh = {}
    for index, item in ipairs(items) do
        local slot = showing[item.key]
        if not slot then
            slot = table.remove(spare) or CreateSlot()
            showing[item.key] = slot
            slot:Show()
            StartGlow(slot)
            if item.key ~= "sample" then
                table.insert(fresh, item.key)
            end
        end
        Fill(slot, item)

        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", holder, "TOPLEFT", (index - 1) * (SLOT_WIDTH + SLOT_GAP), 0)
    end

    -- Sized to what it holds, about its middle, so that a second alert
    -- puts the pair either side of where one sat.
    local count = math.max(1, #items)
    holder:SetWidth(count * SLOT_WIDTH + (count - 1) * SLOT_GAP)
    holder:SetShown(#items > 0)

    if fresh[1] then
        Sound(fresh)
    end
end

-- Building it --------------------------------------------------------------------

local function SavePlace(self)
    self:StopMovingOrSizing()

    -- Kept by its middle, so it grows evenly either way from there.
    local x, y = self:GetCenter()
    local middleX, middleY = UIParent:GetCenter()
    ns.db.procAlert = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = x - middleX,
        y = y - middleY,
    }
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "CENTER", ns.db.procAlert.x, ns.db.procAlert.y)
end

local function Create()
    holder = CreateFrame("Frame", "TemperProcAlert", UIParent)
    holder:SetSize(SLOT_WIDTH, SLOT_HEIGHT)
    holder:SetFrameStrata("MEDIUM")
    holder:SetClampedToScreen(true)
    holder:Hide()

    local place = ns.db.procAlert
    if type(place) == "table" and place.point then
        holder:SetPoint(place.point, UIParent, place.relativePoint or place.point, place.x, place.y)
    else
        holder:SetPoint("CENTER", UIParent, "CENTER", START_X, START_Y)
    end

    -- Movable, but only takes the mouse while the sample is up.
    holder:SetMovable(true)
    holder:EnableMouse(false)
    holder:RegisterForDrag("LeftButton")
    holder:SetScript("OnDragStart", function(self)
        if sampleShowing then
            self:StartMoving()
        end
    end)
    holder:SetScript("OnDragStop", SavePlace)

    hint = Kit.Text(holder, "GameFontDisableSmall", "CENTER")
    hint:SetPoint("TOP", holder, "BOTTOM", 0, -2)
    hint:SetText("Drag me where you like")
    hint:Hide()
end

--- Shows the sample alert while the options are open, or puts it away. It's
--- asked often, so does nothing unless the answer has changed.
---@param wanted boolean  true while the example in the options is showing
function ProcAlert.Sample(wanted)
    wanted = wanted and holder ~= nil and ns.settings.procAlert or false
    if wanted == sampleShowing then
        return
    end
    sampleShowing = wanted

    -- In front of the Options window while there, and clickable so it can
    -- be placed. Back under the game's windows, and click-through, after.
    holder:SetFrameStrata(wanted and "DIALOG" or "MEDIUM")
    holder:EnableMouse(wanted)
    hint:SetShown(wanted)

    if sampleTicker then
        sampleTicker:Cancel()
        sampleTicker = nil
    end
    if wanted then
        sampleStart = 0
        sampleTicker = C_Timer.NewTicker(SAMPLE_SECONDS, Redraw)
    elseif holder:IsDragging() then
        SavePlace(holder)
    end
    Redraw()
end

ns.Subscribe("DATABASE_READY", function()
    Create()
    soundChoice = ns.settings.procSound
    Redraw()
end)

ns.Subscribe("PROCS_CHANGED", Redraw)

-- Choosing a sound in the options plays it, so it can be judged.
ns.Subscribe("SETTINGS_CHANGED", function()
    if soundChoice ~= nil and ns.settings.procSound ~= soundChoice then
        PlayChosen()
    end
    soundChoice = ns.settings.procSound
    Redraw()
end)
