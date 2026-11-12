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
-- the panel switches to the exact figures from the saved fight.

local WIDTH = 220
local HEIGHT = 64
local LIVE_REFRESH_SECONDS = 0.5

local MUTED = { 0.65, 0.65, 0.65 }
local ICON = "Interface\\AddOns\\Temper\\Media\\icon"

local widget

-- When the fight in progress began, on GetTime's clock; nil between fights.
local fightStart
local ticker

local function LastFight()
    local fights = ns.character.fights
    return fights[#fights]
end

--- "5 hits   1 crit (20%)   2 missed"
---@param live boolean  the fight is still going on
local function CountsText(hits, crits, avoided, live)
    if hits == 0 and avoided == 0 then
        -- A finished fight can have none: a pet's kill, or a damage-over-
        -- time effect finishing something off.
        return live and "No hits yet" or "No hits counted"
    end

    local text = ("%d %s"):format(hits, hits == 1 and "hit" or "hits")
    if hits > 0 then
        text = ("%s   %d crit"):format(text, crits)

        -- The percentage is the first thing to go when room is short.
        if not ns.Recorder.Open() then
            text = ("%s (%s)"):format(text, ns.Percent(crits / hits))
        end
    end
    if avoided > 0 then
        text = ("%s   %d missed"):format(text, avoided)
    end
    return text
end

--- A note of the recording or experiment in progress, or nothing.
local function RecordingText()
    local experiment = ns.Experiments.Running()
    if experiment and experiment.state == "change" then
        -- The first set is in. It's the player's turn, and this is the
        -- one place they're sure to see that.
        return "|cffffd100Your change, then click|r"
    end

    local recording = ns.Recorder.Open()
    if not recording then
        return ""
    end

    local fights = #ns.Recorder.FightsOf(recording)
    if experiment then
        return ("|cffff4040REC|r %d of %d"):format(fights, experiment.size)
    end
    return ("|cffff4040REC|r %d"):format(fights)
end

--- What a click on the panel opens: the experiment when it's waiting on
--- the player, otherwise the latest fight.
local function OpenWindow()
    local experiment = ns.Experiments.Running()
    if experiment and experiment.state == "change" then
        ns.ShowExperiments()
    else
        ns.ShowLatest()
    end
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
    -- Damage a second is only given in the list of everyone in the fight,
    -- so find ourselves in it. Which entry is ours is never hidden.
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
        return
    end

    widget.title:SetText(fight.target or "Last fight")
    widget.time:SetText(ns.Duration(fight.length))
    widget.dps:SetText(ns.Rate(fight.damage / fight.length))
    widget.damage:SetText(ns.Number(fight.damage))
    widget.counts:SetText(CountsText(fight.hits or 0, fight.crits or 0, fight.avoided or 0))
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
    widget.recording:SetText(RecordingText())
end

local function ShowMenu(self)
    MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle(ns.TITLE)
        root:CreateButton(ns.Recorder.Open() and "Stop recording" or "Record", function()
            ns.ToggleRecording()
        end)
        root:CreateButton("Open the window", OpenWindow)
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
    GameTooltip:AddLine(
        "Click for the full window. Right-click for more. Drag to move.",
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

    -- Middle line: damage a second in large figures, the total beside it.
    -- Each figure has its label as a separate piece of text, because a
    -- live figure can't be joined to anything.
    widget.dps = Label("GameFontHighlightLarge")
    widget.dps:SetPoint("TOPLEFT", mark, "BOTTOMLEFT", 1, -4)

    local dpsLabel = Label("GameFontHighlightSmall")
    dpsLabel:SetPoint("BOTTOMLEFT", widget.dps, "BOTTOMRIGHT", 3, 1)
    dpsLabel:SetTextColor(unpack(MUTED))
    dpsLabel:SetText("a second")

    local damageLabel = Label("GameFontHighlightSmall", "RIGHT")
    damageLabel:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -10, -31)
    damageLabel:SetTextColor(unpack(MUTED))
    damageLabel:SetText("damage")

    widget.damage = Label("GameFontHighlight", "RIGHT")
    widget.damage:SetPoint("BOTTOMRIGHT", damageLabel, "BOTTOMLEFT", -3, 0)

    -- Bottom line: hits and crits, and whether a recording is running.
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
