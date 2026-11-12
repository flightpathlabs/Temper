local _, ns = ...

-- The widget: a small panel that's always up, with the figures from the
-- fight in progress or, between fights, the last one.
--
-- Click it for the full window, right-click for a short menu, drag it
-- anywhere. It's on to begin with and can be turned off.
--
-- During a fight the game lets an addon show its running damage but not
-- read it. So the two live figures are passed straight from the game's
-- tally to the text, and everything we work out ourselves (the timer, the
-- hits and the crits) is shown beside them. The moment the fight ends,
-- the panel switches to the exact figures from the saved fight, with an
-- arrow to say how its DPS stands beside the player's own recent fights.

local Kit = ns.Kit

local WIDTH = 220
local HEIGHT = 64
local LIVE_REFRESH_SECONDS = 0.5

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

local function Refresh()
    if not widget then
        return
    end

    widget:SetShown(ns.settings.widget)
    if not ns.settings.widget then
        return
    end

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

local function ShowMenu(self)
    MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle(ns.TITLE)
        root:CreateButton(ns.Recorder.Open() and "End session" or "Start session", function()
            ns.ToggleRecording()
        end)
        root:CreateButton("Open Temper", OpenWindow)
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

local function Label(font, justify)
    local label = widget:CreateFontString(nil, "ARTWORK", font)
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(false)
    return label
end

local function Create()
    -- The game's own tooltip border, so it looks like it belongs.
    widget = CreateFrame("Button", "TemperWidget", UIParent, "TooltipBackdropTemplate")
    widget:SetSize(WIDTH, HEIGHT)
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

    -- Three lines share the 64 of height: the title from 8 down to 22, the
    -- figures from 26 to 42, and the counts from 45 to 55, which leaves 9
    -- under them. Across, each line keeps 10 clear at both ends.

    -- Top line: our mark, what was fought, and for how long.
    local mark = widget:CreateTexture(nil, "ARTWORK")
    mark:SetTexture(ICON)
    mark:SetSize(14, 14)
    mark:SetPoint("TOPLEFT", 9, -8)

    widget.time = Label("GameFontHighlightSmall", "RIGHT")
    widget.time:SetPoint("TOPRIGHT", -10, -9)
    widget.time:SetTextColor(unpack(MUTED))

    widget.title = Label("GameFontNormalSmall")
    widget.title:SetPoint("LEFT", mark, "RIGHT", 4, 0)
    widget.title:SetPoint("RIGHT", widget.time, "LEFT", -6, 0)

    -- Middle line: DPS in large figures with its arrow, and the total at
    -- the other end. Each figure has its label as a separate piece of
    -- text, because a live figure can't be joined to anything.
    widget.dps = Label("GameFontHighlightLarge")
    widget.dps:SetPoint("TOPLEFT", mark, "BOTTOMLEFT", 1, -4)

    local dpsLabel = Label("GameFontHighlightSmall")
    dpsLabel:SetPoint("BOTTOMLEFT", widget.dps, "BOTTOMRIGHT", 3, 1)
    dpsLabel:SetTextColor(unpack(MUTED))
    dpsLabel:SetText("DPS")

    widget.arrow = Kit.Icon(widget, 12)
    widget.arrow:SetPoint("LEFT", dpsLabel, "RIGHT", 4, 0)
    widget.arrow:Hide()

    local damageLabel = Label("GameFontHighlightSmall", "RIGHT")
    damageLabel:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -10, -31)
    damageLabel:SetTextColor(unpack(MUTED))
    damageLabel:SetText("damage")

    widget.damage = Label("GameFontHighlight", "RIGHT")
    widget.damage:SetPoint("BOTTOMRIGHT", damageLabel, "BOTTOMLEFT", -3, 0)

    -- Bottom line: hits and crits, and at the right-hand end whether a
    -- session is being recorded. The counts stop short of that, and are
    -- cut off with dots sooner than run into it.
    widget.recording = Label("GameFontHighlightSmall", "RIGHT")
    widget.recording:SetPoint("BOTTOMRIGHT", -10, 9)

    widget.counts = Label("GameFontHighlightSmall")
    widget.counts:SetPoint("BOTTOMLEFT", 10, 9)
    widget.counts:SetPoint("RIGHT", widget.recording, "LEFT", -6, 0)
    widget.counts:SetTextColor(unpack(MUTED))
end

ns.Subscribe("DATABASE_READY", function()
    Create()
    Refresh()
end)

ns.Subscribe("FIGHTS_CHANGED", Refresh)
ns.Subscribe("EXPERIMENTS_CHANGED", Refresh)
ns.Subscribe("SETTINGS_CHANGED", Refresh)

-- A fight: keep the panel ticking over while it lasts. These are
-- registered after the fight record's own handlers, so by the time the
-- second one runs the finished fight has already been saved.
ns.OnEvent("PLAYER_REGEN_DISABLED", function()
    fightStart = GetTime()
    Refresh()

    if ticker then
        ticker:Cancel()
    end
    ticker = C_Timer.NewTicker(LIVE_REFRESH_SECONDS, Refresh)
end)

ns.OnEvent("PLAYER_REGEN_ENABLED", function()
    fightStart = nil
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    Refresh()
end)
