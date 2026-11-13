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
--
-- Some buffs the game keeps from addons during a fight, Clearcasting
-- among them, so Temper can't draw those itself when they matter. The
-- game offers a way round that in Blizzard_AuraContainer: a container an
-- addon may set up but never read, which draws a buff by its spell ID,
-- icon, name, time and all, whether or not the addon could see it. So
-- for each such buff on the player's list Temper sets up one of those, in
-- the alert's place and dressed like it, and the game draws the buff
-- there, in a fight and out of one. Temper's own alerts then sit to its
-- right. It's set up once, outside a fight, since the game won't let it
-- be touched while buffs are hidden, and is only shown or hidden after
-- that. It comes without a sound: the game would play one for it, but
-- only from a sound file, and the sounds below are the game's sound kits,
-- which the client gives no way to turn into files.

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
local function CreateGlowFrame(parent, icon)
    local glow = CreateFrame("Frame", nil, parent, "ActionButtonSpellAlertTemplate")
    glow:SetSize(ICON_SIZE * GLOW_SCALE, ICON_SIZE * GLOW_SCALE)
    glow:SetPoint("CENTER", icon)
    glow.ProcStartFlipbook:SetSize(BURST_SIZE, BURST_SIZE)
    return glow
end

local function CreatePulse(parent, icon)
    local pulse = parent:CreateTexture(nil, "OVERLAY", nil, 1)
    pulse:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    pulse:SetBlendMode("ADD")
    pulse:SetAllPoints(icon)

    local throb = pulse:CreateAnimationGroup()
    throb:SetLooping("BOUNCE")
    local fade = throb:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.15)
    fade:SetToAlpha(0.7)
    fade:SetDuration(0.6)
    return pulse, throb
end

local function BorrowGlow(slot)
    local glow = CreateGlowFrame(slot, slot.icon)

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
    local pulse, throb = CreatePulse(slot, slot.icon)
    pulse:Hide()

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

local function CreateSweep(parent, icon)
    local sweep = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    sweep:ClearAllPoints()
    sweep:SetPoint("TOPLEFT", icon, "TOPLEFT", SWEEP_INSET, -SWEEP_INSET)
    sweep:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -SWEEP_INSET, SWEEP_INSET)
    sweep:SetDrawEdge(false)
    sweep:SetDrawBling(false)
    sweep:SetHideCountdownNumbers(true)

    -- Darkening as the time goes, the way the game's own buffs do.
    sweep:SetReverse(true)
    sweep:SetSwipeColor(0, 0, 0, 0.55)
    return sweep
end

local function MaskIcon(parent, icon)
    local mask = parent:CreateMaskTexture()
    mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
end

--- The action bar's own round-cornered frame, and the mask that keeps the
--- icon's corners inside it.
local function FrameIcon(parent, icon)
    Attempt("mask", MaskIcon, parent, icon)
    local frame = parent:CreateTexture(nil, "OVERLAY")
    frame:SetAtlas("UI-HUD-ActionBar-IconFrame")
    frame:SetSize(FRAME_WIDTH, ICON_SIZE)
    frame:SetPoint("TOPLEFT", icon)
end

local function CreateName(parent, icon)
    local name = Kit.Text(parent, "GameFontHighlightSmall", "CENTER")
    name:SetPoint("TOP", icon, "BOTTOM", 0, -NAME_GAP)
    name:SetWidth(SLOT_WIDTH)
    return name
end

local function CreateSlot()
    local slot = CreateFrame("Frame", nil, holder)
    slot:SetSize(SLOT_WIDTH, SLOT_HEIGHT)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetSize(ICON_SIZE, ICON_SIZE)
    slot.icon:SetPoint("TOP")
    FrameIcon(slot, slot.icon)

    local made, sweep = pcall(CreateSweep, slot, slot.icon)
    slot.sweep = made and sweep or nil

    slot.name = CreateName(slot, slot.icon)

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

-- The game's own display -------------------------------------------------------

-- The container, once made, and how each buff given to it fared, by name:
-- "ready" once the game has a slot for it, "failed" if it refused.
local gameDisplay
local gameMade = false
local gameDrawn = {}

-- Set while a change to the container waits for the fight to end, and
-- whether the container is showing, as last set.
local gameWaiting = false
local gameShown = false

--- Whether the game is hiding buffs from addons now. While it is, the
--- container's slots refuse to be touched.
local function AurasHidden()
    if InCombatLockdown() then
        return true
    end
    local ok, hidden = pcall(C_Secrets.ShouldAurasBeSecret)
    return ok and hidden == true
end

--- The game's proc glow, played by the game whenever the slot shows its
--- buff. Only the looping part: the burst before it is started by a
--- script of its own, and the game runs no addon scripts on its slots.
local function GlowGameSlot(button, icon)
    local glow = CreateGlowFrame(button, icon)
    glow.ProcStartFlipbook:Hide()
    glow:Show()
    if pcall(button.AddAuraShownAnimation, button, glow.ProcLoop) then
        return
    end

    glow:Hide()
    local pulse, throb = CreatePulse(button, icon)
    pulse:SetAlpha(0)
    button:AddAuraShownAnimation(throb)
end

--- Dresses a slot the game has made like one of ours: the icon in the
--- action bar's frame, the sweep, the name under it and the glow. Each
--- piece is handed to the game, which fills it in from the buff itself.
local function DressGameSlot(button)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    button:ClearAllPoints()
    button:SetPoint("TOP", gameDisplay, "CENTER", 0, SLOT_HEIGHT / 2)

    -- Clicks pass through it, as through ours. If the game won't have
    -- that, a click on it does nothing: it can't cancel the buff unless
    -- asked to.
    pcall(button.EnableMouse, button, false)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    FrameIcon(button, icon)
    button:SetIcon(icon)

    local made, sweep = pcall(CreateSweep, button, icon)
    if made then
        button:SetDurationCooldown(sweep)
    end

    button:SetSpellName(CreateName(button, icon))
    Attempt("glow on the game's display", GlowGameSlot, button, icon)
end

--- Gives the game one buff to draw, by its spell IDs.
local function AddGameSlot(buff)
    local include = {}
    for _, id in ipairs(buff.ids) do
        include[id] = true
    end

    local button = gameDisplay:AddAuraSlot(buff.name, "HELPFUL", {
        candidateFilters = { includeSpellIDs = include },
    })
    DressGameSlot(button)
end

local function CreateGameDisplay(buffs)
    gameDisplay = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    gameDisplay:SetFrameStrata("MEDIUM")
    gameDisplay:SetPoint("CENTER", holder, "CENTER")

    -- Left alone, it would show Edit Mode's made-up buffs while that's
    -- open, and so none of the player's. That's no reason to go without.
    pcall(gameDisplay.SetEditModePreviewEnabled, gameDisplay, false)
    gameDisplay:SetUnit("player")

    for _, buff in ipairs(buffs) do
        local what = "use of the game's display for " .. buff.name
        if Attempt(what, AddGameSlot, buff) then
            gameDrawn[buff.name] = "ready"
        else
            -- Whatever half of it was made is put away.
            gameDrawn[buff.name] = "failed"
            pcall(gameDisplay.SetAuraSlotEnabled, gameDisplay, buff.name, false)
        end
    end
end

--- Makes the container the first time the alert is on outside a fight,
--- if the player has any buff the game hides.
local function MakeGameDisplay()
    gameMade = true
    local buffs = ns.Procs.HiddenInFights()
    if not buffs[1] then
        return
    end

    if not Attempt("use of the game's display", CreateGameDisplay, buffs) then
        for _, buff in ipairs(buffs) do
            gameDrawn[buff.name] = "failed"
        end
        if gameDisplay then
            pcall(gameDisplay.Hide, gameDisplay)
        end
        gameDisplay = nil
    end
end

--- Shows the game's display while the alert is on and hides it while
--- it's off, once no fight is in the way.
local function ApplyGameDisplay()
    local wanted = ns.settings.procAlert and true or false
    if not wanted and not gameMade then
        gameWaiting = false
        return
    end
    if AurasHidden() then
        gameWaiting = true
        return
    end
    gameWaiting = false

    if not gameMade then
        MakeGameDisplay()
    end
    if
        gameDisplay
        and Attempt("use of the game's display", gameDisplay.SetShown, gameDisplay, wanted)
    then
        gameShown = wanted
    end
end

--- Whether the game is drawing a buff in the alert's first place, so that
--- Temper's own alerts should sit beside it.
local function GameHasFirstPlace()
    if not gameDisplay or not gameShown or not ns.settings.procAlert then
        return false
    end

    -- Only for a buff the player can get: one whose talent they haven't
    -- learned would leave the first place empty for good.
    for _, buff in ipairs(ns.Procs.HiddenInFights()) do
        if buff.known and gameDrawn[buff.name] == "ready" then
            return true
        end
    end
    return false
end

--- How a buff the game hides in a fight fares with the game's display:
--- "ready", "failed", "waiting" for a fight to end, or nil while the alert
--- is off and nothing has been tried.
---@param name string
function ProcAlert.GameDrawing(name)
    if not ns.settings.procAlert then
        return nil
    end
    if gameDrawn[name] == "ready" and not gameShown then
        return gameWaiting and "waiting" or nil
    end
    return gameDrawn[name] or (gameWaiting and "waiting" or nil)
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

    -- Each in its place, counted out from the middle. Two alerts sit either
    -- side of where one sat. While the game draws a buff in the first
    -- place, ours keep to its right, so that it never moves: it can't be
    -- touched in a fight. The sample, showing what the game would draw
    -- there, takes that place itself.
    local step = SLOT_WIDTH + SLOT_GAP
    local count = math.max(1, #items)
    local first = -(count - 1) / 2
    if GameHasFirstPlace() then
        first = sampleShowing and 0 or 1
        count = 1
    end

    -- Sized to the row about its middle, so that all of it can be dragged.
    holder:SetWidth(count * SLOT_WIDTH + (count - 1) * SLOT_GAP)

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
        slot:SetPoint("TOP", holder, "TOP", (first + index - 1) * step, 0)
    end

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
    ApplyGameDisplay()
    Redraw()
end)

ns.Subscribe("PROCS_CHANGED", Redraw)

-- Choosing a sound in the options plays it, so it can be judged.
ns.Subscribe("SETTINGS_CHANGED", function()
    if soundChoice ~= nil and ns.settings.procSound ~= soundChoice then
        PlayChosen()
    end
    soundChoice = ns.settings.procSound
    ApplyGameDisplay()
    Redraw()
end)

-- The alert switched on or off during a fight reaches the game's display
-- once the fight is over.
-- The game can keep buffs hidden for a moment after a fight, or for other
-- reasons altogether, and says when it stops.
local function TryAgain()
    if gameWaiting then
        ApplyGameDisplay()
        Redraw()
    end
end
ns.OnEvent("PLAYER_REGEN_ENABLED", TryAgain)
ns.OnEvent("ADDON_RESTRICTION_STATE_CHANGED", TryAgain)
