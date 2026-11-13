local _, ns = ...

-- The panel: a small frame that's always up, with the figures from the
-- fight in progress or, between fights, the last one.
--
-- Click it for the full window, right-click for a short menu, drag it
-- anywhere. In its top corner, a stopwatch starts and ends a session and
-- a cog opens the options. It's on to begin
-- with and can be turned off. Under the main figures it can carry three
-- more things, each of which can be switched off from its menu or the
-- options: the last few fights, a few figures for the session so far, and
-- a row of small icons for the buffs worth having up, each lit while it's
-- on (what's on is Combat\Readiness.lua's to say). The warning box that
-- sits above the panel is a frame of its own (see ReadyAlert.lua).
--
-- The panels come in two sizes, normal and large, one setting for both.
-- Large is the same panel drawn a quarter bigger with SetScale, rather
-- than a second layout: the game draws text at the size it ends up on
-- screen, so it stays sharp, and whatever hangs from the panel (the
-- warning box, the buff icons) grows with it without being told.
--
-- During a fight the game lets an addon show its running damage but not
-- read it. So the two live figures are passed straight from the game's
-- tally to the text, and everything we work out ourselves (the timer, the
-- hits and the crits) is shown beside them. The moment the fight ends,
-- the panel switches to the exact figures from the saved fight, with an
-- arrow to say how its DPS stands beside the player's own recent fights.

local Kit = ns.Kit

local WIDTH = 220
local LIVE_REFRESH_SECONDS = 0.5

-- Where it starts out: by its left edge, near the left of the screen and
-- a little below the middle. The healing panel's start is worked out from
-- this, so the two would need changing together.
local START_X = 40
local START_Y = -60

-- How large each choice of the size setting draws the panels.
local PANEL_SCALES = { 1, 1.25 }
local SIZE_NAMES = { "Normal", "Large" }

-- The main figures take this much height. Three lines share it: the title
-- from 8 down to 22, the figures from 26 to 42, the counts from 45 to 55.
local MAIN_HEIGHT = 64

-- The lines under the main figures: how tall each is, and the space
-- above a block of them, which holds a ruled line.
local LINE_HEIGHT = 14
local BLOCK_GAP = 8

-- How many earlier fights each choice of the "recent fights" setting
-- shows. The first choice is none.
local RECENT_COUNTS = { 0, 3, 5 }
local MOST_RECENT = 5

-- The buff icons along the bottom: how big, how far apart, how many there
-- can be, and how faint one is while its buff isn't on. A full row is
-- 8 x 18 + 7 x 5 = 179 wide, inside the 200 between the panel's margins.
local BUFF_SIZE = 18
local BUFF_GAP = 5
local MOST_BUFFS = 8
local BUFF_DIM = 0.35

-- The last fight is set against the player's typical DPS over this many
-- of the fights before it that count, and against nothing if there are
-- fewer than a handful: one or two fights are no yardstick.
local REFERENCE_FIGHTS = 10
local FEWEST_TO_GO_BY = 3

local MUTED = { 0.65, 0.65, 0.65 }
local ICON = "Interface\\AddOns\\Temper\\Media\\icon"

-- The stopwatch the game's own clock offers for timing things, which is
-- what a session is. Drawn faint and grey while no session is running,
-- and in full colour while one is.
local STOPWATCH = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local STOPWATCH_SIZE = 13
local STOPWATCH_IDLE = 0.55

-- What the bottom line says while an experiment is waiting on the player.
local YOUR_TURN = "|cffffd100Make your change, then click here|r"

local widget

-- When the fight in progress began, on GetTime's clock; nil between fights.
local fightStart
local ticker

-- When the character logged in, as server time. Fights since then are
-- "this session" when the player hasn't started one of their own.
local loggedInAt = 0

-- How the last fight compares with the ones before it, in words for the
-- tooltip, and what it was set against; nil when there's no comparison
-- to make.
local reference, referenceHow

-- What the session's average went by, in a few words for the tooltip;
-- nil when it's a plain average or isn't showing.
local sessionHow

local function LastFight()
    local fights = ns.character.fights
    return fights[#fights]
end

--- "18 hits   2 crits   3 avoided". Avoided rather than missed, because
--- it takes in dodges, parries and the rest.
---@param live boolean  the fight is still going on
local function CountsText(hits, crits, avoided, live)
    if hits == 0 and avoided == 0 then
        -- A finished fight can have none: a pet's kill, or a damage-over-
        -- time effect finishing something off.
        return live and "No hits yet" or "No hits counted"
    end

    local text = ("%d %s"):format(hits, hits == 1 and "hit" or "hits")
    if hits > 0 then
        text = ("%s   %d %s"):format(text, crits, crits == 1 and "crit" or "crits")
    end
    if avoided > 0 then
        text = ("%s   %d avoided"):format(text, avoided)
    end
    return text
end

--- True while an experiment has its first set and is waiting for the
--- player to make their change.
local function WaitingOnPlayer()
    local experiment = ns.Experiments.Running()
    return experiment ~= nil and experiment.state == "change"
end

--- "REC 3", or "REC 3 of 5" in an experiment, while a session is being
--- recorded. Nothing otherwise.
local function RecordingText()
    local recording = ns.Recorder.Open()
    if not recording then
        return ""
    end

    local fights = #ns.Recorder.FightsOf(recording)
    local experiment = ns.Experiments.Running()
    if experiment then
        return ("|cffff4040REC|r %d of %d"):format(fights, experiment.size)
    end
    return ("|cffff4040REC|r %d"):format(fights)
end

--- What a click on the panel opens: the experiment when it's waiting on
--- the player, otherwise the latest fight.
local function OpenWindow()
    if WaitingOnPlayer() then
        ns.ShowExperiments()
    else
        ns.ShowLatest()
    end
end

-- Something to read the last fight against ------------------------------------

--- The typical DPS over some fights, by the rule in Record\Summary.lua:
--- extremes and quick fights against critters left out. It's asked
--- carefully, being new: if it's missing or goes wrong, the panel falls
--- back on a plain average rather than going blank.
---@return table|nil  { dps, counted, left, how }; nil when there's none
local function TypicalOf(fights)
    if not ns.Summary.Typical then
        return nil
    end

    local ok, typical = pcall(ns.Summary.Typical, fights)
    if ok and type(typical) == "table" and type(typical.dps) == "number" and typical.dps > 0 then
        return typical
    end
    return nil
end

--- Whether a fight is better left out of a comparison: one that doesn't
--- count, being a fluke or over in a moment, or one against critters and
--- the like, which only flatters the figures. Telling a critter apart is
--- Record\Foes.lua's to do, and straight after an update it isn't there.
local function LeftOut(fight)
    if ns.Progress.WhyNotCounted(fight) then
        return true
    end

    local Foes = ns.Foes
    if not (Foes and Foes.IsTrivial) then
        return false
    end
    local ok, trivial = pcall(Foes.IsTrivial, fight)
    return ok and trivial == true
end

--- How the last fight's DPS compares with the player's own over the
--- counted fights before it: their typical DPS where that can be had,
--- and otherwise all their damage over all their seconds.
---@return number|nil change  0.12 for twelve per cent above; nil when
---                           there's too little to go by
---@return number|nil fights  how many earlier fights were looked at
---@return table|nil typical  the typical figure it was set against, from
---                           TypicalOf; nil when it was the plain average
local function AgainstEarlierFights()
    local fights = ns.character.fights
    local last = fights[#fights]

    if not last or LeftOut(last) then
        return nil
    end

    local earlier = {}
    for index = #fights - 1, 1, -1 do
        local fight = fights[index]
        if not LeftOut(fight) then
            table.insert(earlier, fight)
            if #earlier == REFERENCE_FIGHTS then
                break
            end
        end
    end
    if #earlier < FEWEST_TO_GO_BY then
        return nil
    end

    local lastRate = last.damage / last.length
    local typical = TypicalOf(earlier)
    if typical then
        return ns.Change(typical.dps, lastRate), #earlier, typical
    end

    local damage, seconds = 0, 0
    for _, fight in ipairs(earlier) do
        damage = damage + fight.damage
        seconds = seconds + fight.length
    end

    -- Fights that count are never without length, but nothing here is
    -- divided by a length of time that hasn't been looked at first.
    if seconds <= 0 then
        return nil
    end
    return ns.Change(damage / seconds, lastRate), #earlier
end

--- "Its DPS was 12% above your recent fights." When the plain average is
--- all there is to go by, "your last ten fights" instead, since that's
--- what it is.
local function ReferenceText(change, fights, typical)
    local against = "your recent fights"
    if not typical then
        local howMany = fights == REFERENCE_FIGHTS and "ten" or tostring(fights)
        against = ("your last %s fights"):format(howMany)
    end

    local percent = math.floor(math.abs(change) * 100 + 0.5)
    if percent == 0 then
        return ("Its DPS was level with %s."):format(against)
    end
    return ("Its DPS was %d%% %s %s."):format(percent, change > 0 and "above" or "below", against)
end

--- The few words a typical figure comes with ("middle 8 of 10 fights"),
--- or nil when there are none to show.
local function HowOf(typical)
    local how = typical and typical.how
    if type(how) == "string" and how ~= "" then
        return how
    end
    return nil
end

-- The main figures -----------------------------------------------------------

-- The game's running figures for this fight are passed to the text
-- without being looked at. Each is run under pcall on its own: if the
-- game won't hand one over, that one shows a dash and the rest carry on.

local function PutLiveDamage()
    local mine = C_DamageMeter.GetCombatSessionSourceFromType(
        Enum.DamageMeterSessionType.Current,
        Enum.DamageMeterType.DamageDone,
        UnitGUID("player")
    )
    widget.damage:SetText(AbbreviateNumbers(mine.totalAmount))
end

local function PutLiveRate()
    -- DPS is only given in the list of everyone in the fight, so find
    -- ourselves in it. Which entry is ours is never hidden.
    local everyone = C_DamageMeter.GetCombatSessionFromType(
        Enum.DamageMeterSessionType.Current,
        Enum.DamageMeterType.DamageDone
    )
    for _, source in ipairs(everyone.combatSources) do
        if source.isLocalPlayer then
            -- Rounded by the game, since we can't do sums on it ourselves.
            widget.dps:SetText(C_StringUtil.RoundToNearestString(source.amountPerSecond))
            return
        end
    end
    error("not in the fight's list yet")
end

local function ShowLive()
    widget.title:SetText("|cffff4040In combat|r")
    widget.time:SetText(ns.Duration(GetTime() - fightStart))

    if not pcall(PutLiveRate) then
        widget.dps:SetText("-")
    end
    if not pcall(PutLiveDamage) then
        widget.damage:SetText("-")
    end

    -- The live figures can't be compared with anything, so the arrow
    -- waits for the fight to end.
    widget.arrow:Hide()
    reference, referenceHow = nil, nil

    -- With other people about, the hits on the target aren't all ours.
    if IsInGroup() then
        widget.counts:SetText("")
    else
        local tally = ns.Hits.Live(fightStart)
        widget.counts:SetText(CountsText(tally.hits, tally.crits, tally.avoided, true))
    end
end

local function ShowLast()
    local fight = LastFight()
    if not fight then
        widget.title:SetText(ns.TITLE)
        widget.time:SetText("")
        widget.dps:SetText("-")
        widget.damage:SetText("-")
        widget.counts:SetText("No fights yet")
        widget.arrow:Hide()
        reference, referenceHow = nil, nil
        return
    end

    widget.title:SetText(ns.FightTitle(fight, "Last fight"))
    widget.time:SetText(ns.Duration(fight.length))
    widget.dps:SetText(ns.Rate(fight.damage / fight.length))
    widget.damage:SetText(ns.Number(fight.damage))
    widget.counts:SetText(CountsText(fight.hits or 0, fight.crits or 0, fight.avoided or 0))

    local change, fights, typical = AgainstEarlierFights()
    Kit.SetArrow(widget.arrow, change)
    reference = change and ReferenceText(change, fights, typical) or nil
    referenceHow = change and HowOf(typical) or nil
end

--- Redraws the part that changes while a fight is going on.
local function RefreshMain()
    if fightStart then
        ShowLive()
    else
        ShowLast()
    end

    -- An experiment with its first set in is waiting on the player, and
    -- this is the one place they're sure to see that, so it's given the
    -- whole of the bottom line.
    if WaitingOnPlayer() then
        widget.counts:SetText(YOUR_TURN)
        widget.recording:SetText("")
    else
        widget.recording:SetText(RecordingText())
    end

    local running = ns.Recorder.Open() ~= nil
    widget.stopwatch.face:SetDesaturated(not running)
    widget.stopwatch:SetAlpha(running and 1 or STOPWATCH_IDLE)
end

-- Under the main figures -------------------------------------------------------

--- The fights the "session" figures cover, and what to call them: the
--- session in progress if the player started one, otherwise everything
--- since they logged in. The healing panel goes by the same rule.
---@return table fights  list of fights, oldest first
---@return string name  "Session 3" or "This session"
function ns.SessionSoFar()
    local recording = ns.Recorder.Open()
    if recording then
        return ns.Recorder.FightsOf(recording), "Session " .. recording.number
    end

    local fights = {}
    for _, fight in ipairs(ns.character.fights) do
        if fight.at >= loggedInAt then
            table.insert(fights, fight)
        end
    end
    return fights, "This session"
end

--- Fills one line of the lower part: text at the left, text at the right.
local function SetLine(line, top, left, right)
    line.left:ClearAllPoints()
    line.left:SetPoint("TOPLEFT", 10, -top)
    line.left:SetPoint("RIGHT", line.right, "LEFT", -6, 0)
    line.left:SetText(left)

    line.right:ClearAllPoints()
    line.right:SetPoint("TOPRIGHT", -10, -top)
    line.right:SetText(right or "")

    line.left:Show()
    line.right:Show()
end

--- Shows one buff icon: in full colour while its buff is on, grey and
--- faint while it isn't.
local function ShowBuff(icon, slot)
    Kit.SetSpellIcon(icon.face, slot.icon)
    icon.face:SetDesaturated(not slot.lit)
    icon:SetAlpha(slot.lit and 1 or BUFF_DIM)
    icon.key = slot.key
    icon:Show()
end

--- The buffs to show along the bottom, when they're switched on. Their
--- file is one the game only finds when it starts, so straight after an
--- update there are none.
local function BuffSlots()
    if not ns.settings.widgetBuffs or not ns.Readiness then
        return {}
    end
    return ns.Readiness.Slots()
end

--- Lays out the recent fights, the session's figures and the buffs,
--- whichever are switched on, and sets the panel's height to fit them.
local function RefreshLower()
    local lines, rules = widget.lines, widget.rules
    local used, ruled = 0, 0
    local top = MAIN_HEIGHT

    local function Rule()
        ruled = ruled + 1
        local rule = rules[ruled]
        rule:ClearAllPoints()
        rule:SetPoint("TOPLEFT", 10, -(top + BLOCK_GAP / 2 - 1))
        rule:SetPoint("RIGHT", -10, 0)
        rule:Show()
        top = top + BLOCK_GAP
    end

    local function Line(left, right)
        used = used + 1
        SetLine(lines[used], top, left, right)
        top = top + LINE_HEIGHT
    end

    -- The few fights before the one in the main figures, newest first.
    local fights = ns.character.fights
    local wanted = RECENT_COUNTS[ns.settings.widgetRecent] or 0
    local shown = math.min(wanted, #fights - 1)
    if shown > 0 then
        Rule()
        for back = 1, shown do
            local fight = fights[#fights - back]
            Line(
                Kit.Colored(ns.FightTitle(fight, "Fight"), MUTED),
                ns.Rate(fight.damage / fight.length) .. " DPS"
            )
        end
    end

    sessionHow = nil
    if ns.settings.widgetStats then
        local session, name = ns.SessionSoFar()
        local summary = ns.Summary.Of(session)

        Rule()
        Line(
            Kit.Colored(name, Kit.GOLD),
            summary.fights == 1 and "1 fight" or summary.fights .. " fights"
        )
        if summary.fights > 0 then
            -- The typical DPS, so a few quick kills of critters don't lift
            -- it. A session with nothing in it to go by, only critters
            -- say, shows its plain average: it's still what happened.
            local typical = TypicalOf(session)
            local dps = typical and typical.dps or summary.dps
            sessionHow = HowOf(typical)

            local crit = summary.critRate and ns.Percent(summary.critRate) .. " crit" or ""
            Line(Kit.Colored("Average", MUTED) .. " " .. ns.Rate(dps) .. " DPS", crit)

            -- The size of a blow is worked out, not read, hence "about".
            local sizes = summary.sizes
            if sizes and sizes.biggest then
                Line(
                    Kit.Colored("Biggest hit", MUTED) .. " about " .. ns.Number(sizes.biggest),
                    sizes.biggestCrit == sizes.biggest and "a crit" or ""
                )
            end
        end
    end

    -- One row of icons, left to right, under everything else.
    local buffs = BuffSlots()
    local shownBuffs = math.min(#buffs, MOST_BUFFS)
    if shownBuffs > 0 then
        Rule()
        for index = 1, shownBuffs do
            local icon = widget.buffs[index]
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", 10 + (index - 1) * (BUFF_SIZE + BUFF_GAP), -top)
            ShowBuff(icon, buffs[index])
        end
        top = top + BUFF_SIZE
    end
    for index = shownBuffs + 1, #widget.buffs do
        widget.buffs[index]:Hide()
        widget.buffs[index].key = nil
    end

    -- The row can shift under a resting mouse (a weapon equipped adds an
    -- icon), and the tooltip has to follow what's under it now.
    for index = 1, shownBuffs do
        local icon = widget.buffs[index]
        if GameTooltip:IsOwned(icon) then
            icon:GetScript("OnEnter")(icon)
        end
    end

    for index = used + 1, #lines do
        lines[index].left:Hide()
        lines[index].right:Hide()
    end
    for index = ruled + 1, #rules do
        rules[index]:Hide()
    end

    -- A little room under the last line, when there are any.
    widget:SetHeight(top > MAIN_HEIGHT and top + 6 or MAIN_HEIGHT)
end

-- The size of the panels --------------------------------------------------------

-- Both panels go by these, so they're shared from here; the healing panel
-- is made after this one.

--- How large the panels are to be drawn: 1 at the normal size.
function ns.PanelScale()
    return PANEL_SCALES[ns.settings.widgetSize] or 1
end

--- Draws a panel at the size it's to be and puts it where it was left.
--- A frame's offsets are measured at its own scale, so a place is kept as
--- it would be at the normal size, which is how places were always kept,
--- and the scale is divided out here, as the game's Edit Mode does. A
--- change of size then leaves the corner the panel is held by where the
--- player put it, and the panel grows or shrinks away from it. Being
--- clamped to the screen, it's kept on it.
---@param place table|nil  as saved: { point, relativePoint, x, y }
---@param default table  the same, for a panel that has never been moved
function ns.PlacePanel(panel, place, default)
    if type(place) ~= "table" or not place.point then
        place = default
    end

    local scale = ns.PanelScale()
    panel:SetScale(scale)
    panel:ClearAllPoints()
    panel:SetPoint(
        place.point,
        UIParent,
        place.relativePoint or place.point,
        (place.x or 0) / scale,
        (place.y or 0) / scale
    )
end

--- Where a panel has just been dragged to, kept as it would be at the
--- normal size (see PlacePanel).
function ns.PanelPlace(panel)
    local scale = panel:GetScale()
    local point, _, relativePoint, x, y = panel:GetPoint(1)
    return { point = point, relativePoint = relativePoint, x = x * scale, y = y * scale }
end

--- Adds the choice of size to a panel's menu. The one setting governs
--- both panels, so they stay a pair.
function ns.AddPanelSizes(root)
    root:CreateTitle("Size of the panels")
    for size, label in ipairs(SIZE_NAMES) do
        root:CreateRadio(label, function()
            return ns.settings.widgetSize == size
        end, function()
            ns.settings.widgetSize = size
            ns.Publish("SETTINGS_CHANGED")
        end)
    end
end

--- Where this panel starts out, before it's ever moved.
local function StartingPlace()
    return { point = "LEFT", relativePoint = "LEFT", x = START_X, y = START_Y }
end

--- Shows or hides our mark in the corner, and moves the title to suit.
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

    -- A new size: drawn at it, and put back where it was left.
    if widget:GetScale() ~= ns.PanelScale() then
        ns.PlacePanel(widget, ns.db.widget, StartingPlace())
    end

    widget:SetShown(ns.settings.widget)
    if not ns.settings.widget then
        return
    end

    RefreshBranding()
    RefreshMain()
    RefreshLower()
end

-- Menu and tooltip -----------------------------------------------------------

--- Adds a tick box to the menu for one of the panel's own settings.
local function AddToggle(root, label, key, on, off)
    root:CreateCheckbox(label, function()
        return ns.settings[key] ~= off
    end, function()
        ns.settings[key] = ns.settings[key] == off and on or off
        ns.Publish("SETTINGS_CHANGED")
    end)
end

local function ShowMenu(self)
    MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle(ns.TITLE)
        root:CreateButton(ns.Recorder.Open() and "End session" or "Start session", function()
            ns.ToggleRecording()
        end)
        root:CreateButton("Open Temper", OpenWindow)

        root:CreateDivider()
        root:CreateTitle("Show on this panel")
        AddToggle(root, "Recent fights", "widgetRecent", 3, 1)
        AddToggle(root, "Session figures", "widgetStats", true, false)
        AddToggle(root, "The Temper icon", "widgetBrand", true, false)

        -- The buffs and the warning box come from files the game only
        -- finds when it starts, so straight after an update there's
        -- nothing for their ticks to switch.
        if ns.Readiness then
            AddToggle(root, "Buffs along the bottom", "widgetBuffs", true, false)
        end

        -- The healing panel and the warning box are frames of their own
        -- (see HealWidget.lua and ReadyAlert.lua), so they sit apart from
        -- what's shown on this one.
        root:CreateDivider()
        AddToggle(root, "Healing panel", "healWidget", true, false)
        if ns.Readiness and ns.ReadyAlert then
            AddToggle(root, "Warn me when I'm not ready", "readyAlert", true, false)
        end

        root:CreateDivider()
        ns.AddPanelSizes(root)

        root:CreateDivider()
        root:CreateButton("Options", function()
            ns.OpenOptions()
        end)
        root:CreateButton("Hide this panel", function()
            ns.settings.widget = false
            ns.Publish("SETTINGS_CHANGED")
            ns.Print("Panel hidden. It can be switched back on in Options > AddOns > %s.", ns.TITLE)
        end)
    end)
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(ns.TITLE)
    GameTooltip:AddLine(fightStart and "This fight so far." or "Your last fight.", 1, 1, 1, true)
    if reference then
        GameTooltip:AddLine(reference, 1, 1, 1, true)
        if referenceHow then
            GameTooltip:AddLine(("Set against: %s."):format(referenceHow), 0.6, 0.6, 0.6, true)
        end
    end
    if sessionHow then
        GameTooltip:AddLine(("Session average: %s."):format(sessionHow), 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine(
        "Click to open Temper. Right-click for more. Drag to move.",
        0.6,
        0.6,
        0.6,
        true
    )
    GameTooltip:Show()
end

-- Building it -------------------------------------------------------------------

local function Label(font, justify)
    local label = widget:CreateFontString(nil, "ARTWORK", font)
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(false)
    return label
end

--- What the stopwatch says when the mouse is over it.
local function StopwatchTooltip()
    local recording = ns.Recorder.Open()
    if not recording then
        return {
            "Click to start a session. Your fights from now on are kept together, "
                .. "so they can be read and compared as one.",
        }
    end

    local fights = #ns.Recorder.FightsOf(recording)
    return {
        ("Session %d is running: %s so far."):format(recording.number, ns.Count(fights, "fight")),
        "Click to end it and read it.",
    }
end

--- The stopwatch in the corner, which starts and ends a session.
local function CreateStopwatch()
    local button = CreateFrame("Button", nil, widget)
    button:SetSize(STOPWATCH_SIZE, STOPWATCH_SIZE)

    -- Trimmed a touch, as the game does, to lose the icon's own border.
    button.face = button:CreateTexture(nil, "ARTWORK")
    button.face:SetTexture(STOPWATCH)
    button.face:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.face:SetAllPoints()

    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetTexture(STOPWATCH)
    glow:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.4)
    glow:SetAllPoints()

    button:SetScript("OnClick", function()
        ns.ToggleRecording()
    end)
    Kit.Tooltip(button, "Session", StopwatchTooltip)
    return button
end

--- What a buff icon's tooltip says: what it is, and whether it's on.
local function ShowBuffTooltip(self)
    if not self.key or not ns.Readiness then
        return
    end
    local title, lines = ns.Readiness.Tooltip(self.key)
    if not title then
        return
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    for _, line in ipairs(lines) do
        local color = line.hint and Kit.MUTED or { 1, 1, 1 }
        GameTooltip:AddLine(line.text, color[1], color[2], color[3], true)
    end
    GameTooltip:Show()
end

--- One buff icon along the bottom. It answers the mouse for its tooltip,
--- but lets clicks and drags through to the panel under it.
local function CreateBuff()
    local icon = CreateFrame("Frame", nil, widget)
    icon:SetSize(BUFF_SIZE, BUFF_SIZE)
    icon:Hide()

    icon.face = icon:CreateTexture(nil, "ARTWORK")
    icon.face:SetAllPoints()

    icon:EnableMouse(true)
    pcall(icon.SetMouseClickEnabled, icon, false)
    icon:SetScript("OnEnter", ShowBuffTooltip)
    icon:SetScript("OnLeave", GameTooltip_Hide)
    return icon
end

local function Create()
    -- The game's own tooltip border, so it looks like it belongs.
    widget = CreateFrame("Button", "TemperWidget", UIParent, "TooltipBackdropTemplate")
    widget:SetSize(WIDTH, MAIN_HEIGHT)
    widget:SetFrameStrata("LOW")
    widget:SetClampedToScreen(true)

    -- Back where it was last left, or out of the way on the left, at the
    -- size chosen.
    ns.PlacePanel(widget, ns.db.widget, StartingPlace())

    widget:SetMovable(true)
    widget:RegisterForDrag("LeftButton")
    widget:SetScript("OnDragStart", widget.StartMoving)
    widget:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.db.widget = ns.PanelPlace(self)
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
    -- hold more lines the main figures stay where they are.

    -- Top line: our mark, what was fought, and for how long.
    widget.mark = widget:CreateTexture(nil, "ARTWORK")
    widget.mark:SetTexture(ICON)
    widget.mark:SetSize(14, 14)
    widget.mark:SetPoint("TOPLEFT", 9, -8)

    -- A small cog in the corner for the options, kept faint so the panel
    -- stays quiet.
    local options = Kit.OptionsButton(widget, 12)
    options:SetPoint("TOPRIGHT", -8, -8)
    options:SetAlpha(0.7)

    widget.stopwatch = CreateStopwatch()
    widget.stopwatch:SetPoint("RIGHT", options, "LEFT", -4, 0)

    widget.time = Label("GameFontHighlightSmall", "RIGHT")
    widget.time:SetPoint("RIGHT", widget.stopwatch, "LEFT", -5, 0)
    widget.time:SetTextColor(unpack(MUTED))

    widget.title = Label("GameFontNormalSmall")

    -- Middle line: DPS in large figures with its arrow, and the total at
    -- the other end. Each figure has its label as a separate piece of
    -- text, because a live figure can't be joined to anything.
    widget.dps = Label("GameFontHighlightLarge")
    widget.dps:SetPoint("TOPLEFT", 10, -26)

    local dpsLabel = Label("GameFontHighlightSmall")
    dpsLabel:SetPoint("BOTTOMLEFT", widget.dps, "BOTTOMRIGHT", 3, 1)
    dpsLabel:SetTextColor(unpack(MUTED))
    dpsLabel:SetText("DPS")

    widget.arrow = Kit.Icon(widget, 12)
    widget.arrow:SetPoint("LEFT", dpsLabel, "RIGHT", 4, 0)
    widget.arrow:Hide()

    local damageLabel = Label("GameFontHighlightSmall", "RIGHT")
    damageLabel:SetPoint("TOPRIGHT", -10, -31)
    damageLabel:SetTextColor(unpack(MUTED))
    damageLabel:SetText("damage")

    widget.damage = Label("GameFontHighlight", "RIGHT")
    widget.damage:SetPoint("BOTTOMRIGHT", damageLabel, "BOTTOMLEFT", -3, 0)

    -- Third line: hits and crits, and at the right-hand end whether a
    -- session is being recorded. The counts stop short of that, and are
    -- cut off with dots sooner than run into it.
    widget.recording = Label("GameFontHighlightSmall", "RIGHT")
    widget.recording:SetPoint("TOPRIGHT", -10, -45)

    widget.counts = Label("GameFontHighlightSmall")
    widget.counts:SetPoint("TOPLEFT", 10, -45)
    widget.counts:SetPoint("RIGHT", widget.recording, "LEFT", -6, 0)
    widget.counts:SetTextColor(unpack(MUTED))

    -- Lines for the lower part, made once and filled as needed: the most
    -- recent fights there can be, and three for the session.
    widget.lines, widget.rules = {}, {}
    for index = 1, MOST_RECENT + 3 do
        widget.lines[index] = {
            left = Label("GameFontHighlightSmall"),
            right = Label("GameFontHighlightSmall", "RIGHT"),
        }
    end
    for index = 1, 3 do
        local rule = widget:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(1, 1, 1, 0.12)
        rule:SetHeight(1)
        widget.rules[index] = rule
    end

    widget.buffs = {}
    for index = 1, MOST_BUFFS do
        widget.buffs[index] = CreateBuff()
    end
end

--- The panel's frame, for what hangs from it (the warning box above it).
--- nil until the saved data is ready.
function ns.FightPanel()
    return widget
end

ns.Subscribe("DATABASE_READY", function()
    loggedInAt = GetServerTime()
    Create()
    Refresh()
end)

ns.Subscribe("FIGHTS_CHANGED", Refresh)
ns.Subscribe("EXPERIMENTS_CHANGED", Refresh)
ns.Subscribe("SETTINGS_CHANGED", Refresh)
ns.Subscribe("READINESS_CHANGED", Refresh)

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
        if widget and ns.settings.widget then
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
