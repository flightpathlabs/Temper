local _, ns = ...

-- The healing panel: a second small frame, the twin of the fight panel in
-- Widget.lua, for what the player healed in the fight in progress or,
-- between fights, the last one.
--
-- It's off to begin with, and is popped out from the fight panel's menu
-- or the options. It's the same width and is laid out the same way as its
-- twin, so the two can sit side by side or stacked and read as a pair.
-- Click it for the Healing and defence tab, right-click for a short menu, drag it
-- anywhere.
--
-- During a fight the game lets an addon show its running healing but not
-- read it, exactly as it does for damage. So the two live figures are
-- passed straight from the game's tally to the text, each to a piece of
-- text of its own, and nothing is worked out from them. The moment the
-- fight ends, the panel switches to the exact figures from the saved
-- fight. Only healing done during a fight is in a tally: eating or
-- bandaging afterwards never reaches this panel.

local Kit = ns.Kit

-- The same measures as the fight panel, so the two line up. Three lines
-- share the main height: the title, the figures and a note.
local WIDTH = 220
local MAIN_HEIGHT = 64
local LINE_HEIGHT = 14
local BLOCK_GAP = 8
local LIVE_REFRESH_SECONDS = 0.5

-- Where it starts out. The fight panel starts at the left of the screen,
-- centred 60 below the middle, and with everything on it switched on,
-- buffs included, it reaches about 170 below. This one hangs by its top
-- edge just under that.
local START_X = 40
local START_Y = -178

-- The session's figures take at most this many lines.
local SESSION_LINES = 2

local MUTED = { 0.65, 0.65, 0.65 }
local ICON = "Interface\\AddOns\\Temper\\Media\\icon"

local TITLE = "Healing"
local IN_COMBAT = "|cffff4040In combat|r"

-- What the bottom line says when there's no healing to show for a fight.
-- It covers a fight from before healing was kept as well as one where
-- nothing was healed, since the two can't be told apart afterwards.
local NOTHING_RECORDED = "No healing recorded"

local widget

-- When the fight in progress began, on GetTime's clock; nil between fights.
local fightStart
local ticker

local function LastFight()
    local fights = ns.character.fights
    return fights[#fights]
end

--- "Healing", then what was fought or that a fight is on. Whatever follows
--- the word comes last, so that it's what gets cut short when there isn't
--- the room.
local function TitleText(after)
    if not after then
        return TITLE
    end
    return TITLE .. "  " .. after
end

--- "2 interrupts", or nothing when there were none.
local function InterruptsText(interrupts)
    return interrupts > 0 and ns.Count(interrupts, "interrupt") or ""
end

-- The main figures -----------------------------------------------------------

-- The game's running figures for this fight are passed to the text
-- without being looked at, as the fight panel passes its damage. Each is
-- run under pcall on its own: if the game won't hand one over, that one
-- shows a dash and the other carries on.

local function PutLiveHealing()
    local mine = C_DamageMeter.GetCombatSessionSourceFromType(
        Enum.DamageMeterSessionType.Current,
        Enum.DamageMeterType.HealingDone,
        UnitGUID("player")
    )
    widget.healed:SetText(AbbreviateNumbers(mine.totalAmount))
end

local function PutLiveRate()
    -- HPS is only given in the list of everyone healing in the fight, so
    -- find ourselves in it. Which entry is ours is never hidden. Until
    -- the first heal of a fight we may not be in the list at all.
    local everyone = C_DamageMeter.GetCombatSessionFromType(
        Enum.DamageMeterSessionType.Current,
        Enum.DamageMeterType.HealingDone
    )
    for _, source in ipairs(everyone.combatSources) do
        if source.isLocalPlayer then
            -- Rounded by the game, since we can't do sums on it ourselves.
            widget.hps:SetText(C_StringUtil.RoundToNearestString(source.amountPerSecond))
            return
        end
    end
    error("not in the fight's list yet")
end

local function ShowLive()
    widget.title:SetText(TitleText(IN_COMBAT))
    widget.time:SetText(ns.Duration(GetTime() - fightStart))

    if not pcall(PutLiveRate) then
        widget.hps:SetText("-")
    end
    if not pcall(PutLiveHealing) then
        widget.healed:SetText("-")
    end

    -- Nothing we count ourselves can be had while the fight lasts, so the
    -- bottom line only says what the figures are. A fight in a group is
    -- shown as it goes but never saved, and it's as well to say so.
    widget.note:SetText(IsInGroup() and "Not recorded in a group" or "This fight so far")
    widget.interrupts:SetText("")
end

--- Dashes where the figures go, and a few words in place of the note. A
--- nought here would read as something measured.
local function ShowNoFigures(why)
    widget.hps:SetText("-")
    widget.healed:SetText("-")
    widget.note:SetText(why)
end

local function ShowLast()
    local fight = LastFight()
    if not fight then
        widget.title:SetText(TITLE)
        widget.time:SetText("")
        widget.interrupts:SetText("")
        ShowNoFigures("No fights yet")
        return
    end

    -- Summed up by the same code as the Healing tab, so the two agree.
    local summary = ns.Healing.Of({ fight })

    widget.title:SetText(TitleText(fight.target and Kit.Colored(fight.target, MUTED)))
    widget.time:SetText(ns.Duration(fight.length))
    widget.interrupts:SetText(InterruptsText(summary.interrupts))

    if summary.healing <= 0 then
        ShowNoFigures(NOTHING_RECORDED)
        return
    end

    widget.hps:SetText(ns.Rate(summary.hps))
    widget.healed:SetText(ns.Number(summary.healing))

    -- How much of what the enemy did was healed back. It can pass 100%
    -- when the fight was begun already hurt.
    local healedBack = summary.healedBack
    widget.note:SetText(healedBack and ns.Percent(healedBack) .. " of damage taken" or "")
end

--- Redraws the part that changes while a fight is going on.
local function RefreshMain()
    if fightStart then
        ShowLive()
    else
        ShowLast()
    end
end

-- Under the main figures -------------------------------------------------------

--- Fills the session's figures, when they're switched on, and sets the
--- panel's height to fit them. The one setting governs this panel and the
--- fight panel alike.
local function RefreshSession()
    local lines = widget.lines
    local used = 0

    if ns.settings.widgetStats then
        local fights, name = ns.SessionSoFar()
        local summary = ns.Healing.Of(fights)

        lines[1].left:SetText(Kit.Colored(name, Kit.GOLD))
        lines[1].right:SetText(#fights == 1 and "1 fight" or #fights .. " fights")
        used = 1

        -- A session with no healing in it gets no second line, and so no
        -- noughts.
        if summary.healing > 0 then
            lines[2].left:SetText(
                Kit.Colored("Average", MUTED) .. " " .. ns.Rate(summary.hps) .. " HPS"
            )
            lines[2].right:SetText(ns.Number(summary.healing) .. " healed")
            used = 2
        end
    end

    widget.rule:SetShown(used > 0)
    for index, line in ipairs(lines) do
        line.left:SetShown(index <= used)
        line.right:SetShown(index <= used)
    end

    -- A little room under the last line, when there are any.
    local lower = used > 0 and BLOCK_GAP + used * LINE_HEIGHT + 6 or 0
    widget:SetHeight(MAIN_HEIGHT + lower)
end

--- Shows or hides our mark in the corner, and moves the title to suit. It
--- follows the fight panel's setting, so the pair's titles stay in line.
local function RefreshBranding()
    local branded = ns.settings.widgetBrand
    widget.mark:SetShown(branded)

    widget.title:ClearAllPoints()
    if branded then
        widget.title:SetPoint("LEFT", widget.mark, "RIGHT", 4, 0)
    else
        widget.title:SetPoint("TOPLEFT", 10, -9)
    end
    widget.title:SetPoint("RIGHT", widget.time, "LEFT", -6, 0)
end

local function Refresh()
    if not widget then
        return
    end

    widget:SetShown(ns.settings.healWidget)
    if not ns.settings.healWidget then
        return
    end

    RefreshBranding()
    RefreshMain()
    RefreshSession()
end

-- Menu and tooltip -----------------------------------------------------------

--- What a click on the panel opens. Looked up when it's clicked, since the
--- window is defined after this file.
local function OpenWindow()
    ns.ShowHealing()
end

local function ShowMenu(self)
    MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle(TITLE)
        root:CreateButton("Open Temper", OpenWindow)

        root:CreateDivider()
        root:CreateButton("Options", function()
            ns.OpenOptions()
        end)
        root:CreateButton("Hide this panel", function()
            ns.settings.healWidget = false
            ns.Publish("SETTINGS_CHANGED")
            ns.Print(
                "Healing panel hidden. It can be switched back on from the fight panel's "
                    .. "menu, or in Options > AddOns > %s.",
                ns.TITLE
            )
        end)
    end)
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(ns.TITLE)
    GameTooltip:AddLine(
        fightStart and "Your healing in this fight so far." or "Your healing in your last fight.",
        1,
        1,
        1,
        true
    )
    GameTooltip:AddLine("Only healing done during a fight is counted.", 1, 1, 1, true)
    GameTooltip:AddLine(
        "Click for the Healing and defence tab. Right-click for more. Drag to move.",
        0.6,
        0.6,
        0.6,
        true
    )
    GameTooltip:Show()
end

-- Building it -------------------------------------------------------------------

local function Create()
    -- The game's own tooltip border, as on the fight panel.
    widget = CreateFrame("Button", "TemperHealWidget", UIParent, "TooltipBackdropTemplate")
    widget:SetSize(WIDTH, MAIN_HEIGHT)
    widget:SetFrameStrata("LOW")
    widget:SetClampedToScreen(true)

    -- Back where it was last left, or just under where the fight panel
    -- starts.
    local place = ns.db.healWidget
    if type(place) == "table" and place.point then
        widget:SetPoint(place.point, UIParent, place.relativePoint or place.point, place.x, place.y)
    else
        widget:SetPoint("TOPLEFT", UIParent, "LEFT", START_X, START_Y)
    end

    widget:SetMovable(true)
    widget:RegisterForDrag("LeftButton")
    widget:SetScript("OnDragStart", widget.StartMoving)
    widget:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        ns.db.healWidget = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)

    widget:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    widget:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            ShowMenu(self)
        else
            OpenWindow()
        end
    end)
    widget:SetScript("OnEnter", ShowTooltip)
    widget:SetScript("OnLeave", GameTooltip_Hide)

    -- Everything hangs from the top edge, so that when the panel grows to
    -- hold the session's figures the main ones stay where they are.

    -- Top line: our mark, "Healing" and what was fought, and for how long.
    widget.mark = widget:CreateTexture(nil, "ARTWORK")
    widget.mark:SetTexture(ICON)
    widget.mark:SetSize(14, 14)
    widget.mark:SetPoint("TOPLEFT", 9, -8)

    -- The same faint cog as the fight panel has. It's a button of its
    -- own, so a click on it doesn't count as a click on the panel.
    local options = Kit.OptionsButton(widget, 12)
    options:SetPoint("TOPRIGHT", -8, -8)
    options:SetAlpha(0.7)

    widget.time = Kit.Text(widget, "GameFontHighlightSmall", "RIGHT")
    widget.time:SetPoint("RIGHT", options, "LEFT", -5, 0)
    widget.time:SetTextColor(unpack(MUTED))

    widget.title = Kit.Text(widget, "GameFontNormalSmall")

    -- Middle line: HPS in large figures, and the total at the other end.
    -- Each figure has its label as a separate piece of text, because a
    -- live figure can't be joined to anything.
    widget.hps = Kit.Text(widget, "GameFontHighlightLarge")
    widget.hps:SetPoint("TOPLEFT", 10, -26)

    local hpsLabel = Kit.Text(widget, "GameFontHighlightSmall")
    hpsLabel:SetPoint("BOTTOMLEFT", widget.hps, "BOTTOMRIGHT", 3, 1)
    hpsLabel:SetTextColor(unpack(MUTED))
    hpsLabel:SetText("HPS")

    local healedLabel = Kit.Text(widget, "GameFontHighlightSmall", "RIGHT")
    healedLabel:SetPoint("TOPRIGHT", -10, -31)
    healedLabel:SetTextColor(unpack(MUTED))
    healedLabel:SetText("healed")

    widget.healed = Kit.Text(widget, "GameFontHighlight", "RIGHT")
    widget.healed:SetPoint("BOTTOMRIGHT", healedLabel, "BOTTOMLEFT", -3, 0)

    -- Third line: how the healing stood against the damage taken, and at
    -- the right-hand end any interrupts. The note stops short of those,
    -- and is cut off with dots sooner than run into them.
    widget.interrupts = Kit.Text(widget, "GameFontHighlightSmall", "RIGHT")
    widget.interrupts:SetPoint("TOPRIGHT", -10, -45)
    widget.interrupts:SetTextColor(unpack(MUTED))

    widget.note = Kit.Text(widget, "GameFontHighlightSmall")
    widget.note:SetPoint("TOPLEFT", 10, -45)
    widget.note:SetPoint("RIGHT", widget.interrupts, "LEFT", -6, 0)
    widget.note:SetTextColor(unpack(MUTED))

    -- The session's figures: a ruled line, then the lines themselves, all
    -- made once in their places and shown as needed.
    widget.rule = widget:CreateTexture(nil, "ARTWORK")
    widget.rule:SetColorTexture(1, 1, 1, 0.12)
    widget.rule:SetHeight(1)
    widget.rule:SetPoint("TOPLEFT", 10, -(MAIN_HEIGHT + BLOCK_GAP / 2 - 1))
    widget.rule:SetPoint("TOPRIGHT", -10, -(MAIN_HEIGHT + BLOCK_GAP / 2 - 1))

    widget.lines = {}
    for index = 1, SESSION_LINES do
        local top = MAIN_HEIGHT + BLOCK_GAP + (index - 1) * LINE_HEIGHT

        local right = Kit.Text(widget, "GameFontHighlightSmall", "RIGHT")
        right:SetPoint("TOPRIGHT", -10, -top)

        local left = Kit.Text(widget, "GameFontHighlightSmall")
        left:SetPoint("TOPLEFT", 10, -top)
        left:SetPoint("RIGHT", right, "LEFT", -6, 0)

        widget.lines[index] = { left = left, right = right }
    end
end

ns.Subscribe("DATABASE_READY", function()
    Create()
    Refresh()
end)

ns.Subscribe("FIGHTS_CHANGED", Refresh)
ns.Subscribe("SETTINGS_CHANGED", Refresh)

-- A fight: keep the main figures ticking over while it lasts. These are
-- registered after the fight record's own handlers, so by the time the
-- second one runs the finished fight has already been saved.
ns.OnEvent("PLAYER_REGEN_DISABLED", function()
    fightStart = GetTime()
    Refresh()

    if ticker then
        ticker:Cancel()
    end
    ticker = C_Timer.NewTicker(LIVE_REFRESH_SECONDS, function()
        if widget and ns.settings.healWidget then
            RefreshMain()
        end
    end)
end)

ns.OnEvent("PLAYER_REGEN_ENABLED", function()
    fightStart = nil
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    Refresh()
end)
