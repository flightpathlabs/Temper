local _, ns = ...

-- The panel: a small frame that's always up, with the figures from the
-- fight in progress or, between fights, the last one.
--
-- Click it for the full window, right-click for a short menu, drag it
-- anywhere. The cog in its corner opens the options. It's on to begin
-- with and can be turned off. Under the main figures it can carry two
-- more things, each of which can be switched off from its menu or the
-- options: the last few fights, and a few figures for the session so far.
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

-- The last fight is set against the player's average over this many of
-- the counted fights before it, and against nothing if there are fewer
-- than a handful: one or two fights are no yardstick.
local REFERENCE_FIGHTS = 10
local FEWEST_TO_GO_BY = 3

local MUTED = { 0.65, 0.65, 0.65 }
local ICON = "Interface\\AddOns\\Temper\\Media\\icon"

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
-- tooltip; nil when there's no comparison to make.
local reference

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

--- How the last fight's DPS compares with the player's own average over
--- the counted fights before it. The average is all their damage over all
--- their seconds, so a long fight weighs more than a short one.
---@return number|nil change  0.12 for twelve per cent above; nil when
---                           there's too little to go by
---@return number|nil fights  how many earlier fights it was set against
local function AgainstEarlierFights()
    local fights = ns.character.fights
    local last = fights[#fights]

    -- A fight that doesn't count, being a fluke or over in a moment, would
    -- only be flattered by the comparison.
    if not last or ns.Progress.WhyNotCounted(last) then
        return nil
    end

    local damage, seconds, counted = 0, 0, 0
    for index = #fights - 1, 1, -1 do
        local fight = fights[index]
        if not ns.Progress.WhyNotCounted(fight) then
            damage = damage + fight.damage
            seconds = seconds + fight.length
            counted = counted + 1
            if counted == REFERENCE_FIGHTS then
                break
            end
        end
    end

    -- Fights that count are never without length, but nothing here is
    -- divided by a length of time that hasn't been looked at first.
    if counted < FEWEST_TO_GO_BY or seconds <= 0 then
        return nil
    end
    return ns.Change(damage / seconds, last.damage / last.length), counted
end

--- "Its DPS was 12% above your last ten fights."
local function ReferenceText(change, fights)
    local howMany = fights == REFERENCE_FIGHTS and "ten" or tostring(fights)
    local percent = math.floor(math.abs(change) * 100 + 0.5)
    if percent == 0 then
        return ("Its DPS was level with your last %s fights."):format(howMany)
    end

    return ("Its DPS was %d%% %s your last %s fights."):format(
        percent,
        change > 0 and "above" or "below",
        howMany
    )
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
    reference = nil

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
        reference = nil
        return
    end

    widget.title:SetText(fight.target or "Last fight")
    widget.time:SetText(ns.Duration(fight.length))
    widget.dps:SetText(ns.Rate(fight.damage / fight.length))
    widget.damage:SetText(ns.Number(fight.damage))
    widget.counts:SetText(CountsText(fight.hits or 0, fight.crits or 0, fight.avoided or 0))

    local change, fights = AgainstEarlierFights()
    Kit.SetArrow(widget.arrow, change)
    reference = change and ReferenceText(change, fights) or nil
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
end

-- Under the main figures -------------------------------------------------------

--- The fights the "session" figures cover, and what to call them: the
--- session in progress if the player started one, otherwise everything
--- since they logged in.
local function SessionSoFar()
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

--- Lays out the recent fights and the session's figures, whichever are
--- switched on, and sets the panel's height to fit them.
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
                Kit.Colored(fight.target or "Fight", MUTED),
                ns.Rate(fight.damage / fight.length) .. " DPS"
            )
        end
    end

    if ns.settings.widgetStats then
        local session, name = SessionSoFar()
        local summary = ns.Summary.Of(session)

        Rule()
        Line(
            Kit.Colored(name, Kit.GOLD),
            summary.fights == 1 and "1 fight" or summary.fights .. " fights"
        )
        if summary.fights > 0 then
            local crit = summary.critRate and ns.Percent(summary.critRate) .. " crit" or ""
            Line(Kit.Colored("Average", MUTED) .. " " .. ns.Rate(summary.dps) .. " DPS", crit)

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
        AddToggle(root, "Recent fights", "widgetRecent", 2, 1)
        AddToggle(root, "Session figures", "widgetStats", true, false)
        AddToggle(root, "The Temper icon", "widgetBrand", true, false)

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

local function Create()
    -- The game's own tooltip border, so it looks like it belongs.
    widget = CreateFrame("Button", "TemperWidget", UIParent, "TooltipBackdropTemplate")
    widget:SetSize(WIDTH, MAIN_HEIGHT)
    widget:SetFrameStrata("LOW")
    widget:SetClampedToScreen(true)

    -- Back where it was last left, or out of the way on the left.
    local place = ns.db.widget
    if type(place) == "table" and place.point then
        widget:SetPoint(place.point, UIParent, place.relativePoint or place.point, place.x, place.y)
    else
        widget:SetPoint("LEFT", UIParent, "LEFT", 40, -60)
    end

    widget:SetMovable(true)
    widget:RegisterForDrag("LeftButton")
    widget:SetScript("OnDragStart", widget.StartMoving)
    widget:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        ns.db.widget = { point = point, relativePoint = relativePoint, x = x, y = y }
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

    widget.time = Label("GameFontHighlightSmall", "RIGHT")
    widget.time:SetPoint("RIGHT", options, "LEFT", -5, 0)
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
    for index = 1, 2 do
        local rule = widget:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(1, 1, 1, 0.12)
        rule:SetHeight(1)
        widget.rules[index] = rule
    end
end

ns.Subscribe("DATABASE_READY", function()
    loggedInAt = GetServerTime()
    Create()
    Refresh()
end)

ns.Subscribe("FIGHTS_CHANGED", Refresh)
ns.Subscribe("EXPERIMENTS_CHANGED", Refresh)
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
