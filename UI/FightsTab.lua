local _, ns = ...

-- The Fights tab: every fight down the left, the analysis of the selected
-- ones on the right.
--
-- Click a fight to read it. Shift-click selects a run of fights and
-- Ctrl-click adds one, and the analysis covers whatever is selected.
--
-- Comparing is a step the player is walked through, not a mode to
-- remember. "Compare with..." on the strip under the title bar asks them
-- to click the other fights. The page compares as soon as there's one,
-- and "Done" goes back to ordinary reading with the comparison still
-- showing, until "Stop comparing". The strip always says which of those
-- steps the player is at and what to do next.
--
-- Whichever of the two sets is older is the one changes are measured
-- from, whatever order they were clicked in, so green always means
-- "better than it used to be".

local FightsTab = {}
ns.FightsTab = FightsTab

local Kit = ns.Kit

-- The list sits in a sunken panel with its scroll bar. The panel shares
-- the window's own edge on three sides, so only its right-hand edge is
-- new: a line between the list and the page. Across the panel go an
-- edge, the rows, the scroll bar with a gap before it, and an edge.
local LIST_WIDTH = 270
local LIST_EDGE = 5
local SCROLL_BAR_GAP = 4
local SCROLL_BAR_WIDTH = 8
local PANEL_WIDTH = LIST_EDGE + LIST_WIDTH + SCROLL_BAR_GAP + SCROLL_BAR_WIDTH + LIST_EDGE
local FIGHT_HEIGHT = 40
local HEADER_HEIGHT = 26

-- The strip under the window's title bar, which starts clear of the
-- emblem in the corner, and the buttons on its right: one wide one as a
-- rule, two narrow ones while fights are being picked.
local STRIP_HEIGHT = 34
local STRIP_LEFT = 66
local STRIP_EDGE = 10
local WIDE_BUTTON = 120
local NARROW_BUTTON = 64
local BUTTON_GAP = 6

local NO_FIGHTS = "No fights on record yet.\n\n"
    .. "Fight something on your own and it will appear in the list. "
    .. "Press Start session first if you want a run of fights kept together.\n\n"
    .. "Your fights are kept on this computer and never shared."

local HELP_TITLE = "Selecting fights"
local HELP = {
    "Click a fight to read it.",
    "Shift-click to select a run of fights.",
    "Ctrl-click to add a fight, or to take one out.",
    "Click a session's heading to select all its fights.",
    "Right-click a fight or a heading to compare with it, delete it, or leave a fight out "
        .. "of your bests.",
}

local tab

-- The fights being read, and the fights they're compared with: sets of
-- fights, the second nil when nothing is being compared. While `picking`,
-- clicks in the list choose the second set instead of the first.
local chosen = {}
local other
local picking = false

-- Fights in the order the list shows them, newest first, and the last one
-- clicked, for Shift-click to run from.
local order = {}
local lastClicked

local Refresh

-- Sets of fights -------------------------------------------------------------

local function Count(set)
    local count = 0
    for _ in pairs(set or {}) do
        count = count + 1
    end
    return count
end

--- The fights of a set as a list, newest first.
local function ListOf(set)
    local list = {}
    for _, fight in ipairs(order) do
        if set[fight] then
            table.insert(list, fight)
        end
    end
    return list
end

local function SetOf(list)
    local set = {}
    for _, fight in ipairs(list) do
        set[fight] = true
    end
    return set
end

local function SameSet(a, b)
    if not a or not b or Count(a) ~= Count(b) then
        return false
    end
    for fight in pairs(a) do
        if not b[fight] then
            return false
        end
    end
    return true
end

--- Where a fight sits in the list, or nil if it's gone.
local function PlaceOf(wanted)
    for place, fight in ipairs(order) do
        if fight == wanted then
            return place
        end
    end
end

--- Drops fights that have since been deleted from a set.
local function Prune(set)
    local kept = SetOf(order)
    for fight in pairs(set) do
        if not kept[fight] then
            set[fight] = nil
        end
    end
end

-- Comparing --------------------------------------------------------------------

--- Starts the choosing of fights to compare with. The last fight clicked
--- was one of those being read, so a Shift-click mustn't run from it.
local function StartPicking()
    picking = true
    lastClicked = nil
end

--- Ends the choosing, leaving whatever was picked in place.
local function StopPicking()
    if picking then
        picking = false
        lastClicked = nil
    end
end

--- Compares with a set of fights outright, as the menus do.
---@param fights table  list of fights
local function CompareWith(fights)
    other = SetOf(fights)
    StopPicking()
    Refresh()
end

--- The button on the strip: whichever of "Compare with...", "Done" and
--- "Stop comparing" it reads at the time.
local function OnCompareClick()
    if picking then
        StopPicking()
    elseif other then
        other = nil
    else
        StartPicking()
    end
    Refresh()
end

local function OnCancelClick()
    other = nil
    StopPicking()
    Refresh()
end

-- What to call things ---------------------------------------------------------

local function CritText(fight)
    if not fight.hits or fight.hits == 0 then
        return "-"
    end
    return ns.Percent(fight.crits / fight.hits)
end

local function FightsText(count)
    return count == 1 and "1 fight" or count .. " fights"
end

--- The session a list of fights makes up, if they're exactly one whole
--- session and nothing else.
local function WholeSession(fights)
    local first = fights[1]
    local session = first and first.recording and ns.Recorder.Numbered(first.recording)
    if not session or #ns.Recorder.FightsOf(session) ~= #fights then
        return nil
    end

    for _, fight in ipairs(fights) do
        if fight.recording ~= session.number then
            return nil
        end
    end
    return session
end

--- What to call a set of fights in a sentence: "Session 3", or else how
--- many there are.
---@param fights table  list of fights
---@param earlier boolean|nil  true to say "5 earlier", for the older of
---                             two sets being compared
local function SetName(fights, earlier)
    local session = WholeSession(fights)
    if session then
        return "Session " .. session.number
    elseif not earlier then
        return FightsText(#fights)
    end
    return #fights == 1 and "1 earlier" or #fights .. " earlier"
end

--- The same with the time of its newest fight, to tell two sets apart:
--- "5 fights (12 Nov 14:05)". A session's number does that by itself.
local function DatedName(fights, earlier)
    local name = SetName(fights, earlier)
    if WholeSession(fights) then
        return name
    end
    return ("%s (%s)"):format(name, date("%d %b %H:%M", fights[1].at))
end

--- A title and subtitle for the fights on the page.
---@param fights table  list of fights, newest first
local function Heading(fights)
    local heading = { empty = "Select a fight on the left to read it." }
    if #order == 0 then
        heading.empty = NO_FIGHTS
    end
    if #fights == 0 then
        return heading
    end

    local newest, oldest = fights[1], fights[#fights]

    if #fights == 1 then
        heading.title = newest.target or "Fight"
        heading.subtitle = date("%d %b %H:%M", newest.at)
    else
        heading.title = SetName(fights)
        heading.subtitle = ("%s to %s"):format(
            date("%d %b %H:%M", oldest.at),
            date("%H:%M", newest.at)
        )
    end

    -- The card keeps a note for a whole session, and needs to know which.
    heading.recording = WholeSession(fights)

    if newest.level then
        heading.subtitle = heading.subtitle .. "   level " .. newest.level
    end
    return heading
end

-- The list ---------------------------------------------------------------------

local function ShowFightMenu(row, fight)
    MenuUtil.CreateContextMenu(row, function(_, root)
        -- Acting on the whole selection when the fight is part of it, and
        -- on the one fight otherwise, is what people expect of a list.
        local target = chosen[fight] and chosen or { [fight] = true }
        local count = Count(target)
        local one = count == 1

        root:CreateTitle(one and (fight.target or "Fight") or FightsText(count))

        local compare = one and "Compare with this"
            or ("Compare with these %d fights"):format(count)
        root:CreateButton(compare, function()
            CompareWith(ListOf(target))
        end)

        -- Leaving a fluke out of the bests and trends is a one-fight thing.
        if one then
            if fight.ignored then
                root:CreateButton("Count towards my bests again", function()
                    ns.Progress.SetIgnored(fight, false)
                end)
            else
                root:CreateButton("Don't count towards my bests", function()
                    ns.Progress.SetIgnored(fight, true)
                end)
            end
        end

        local delete = one and "Delete this fight" or ("Delete these %d fights"):format(count)
        root:CreateButton(delete, function()
            ns.Recorder.DeleteFights(target)
        end)
    end)
end

local function ShowSessionMenu(row, session)
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle("Session " .. session.number)
        root:CreateButton("Compare with this session", function()
            CompareWith(ns.Recorder.FightsOf(session))
        end)
        root:CreateButton("Delete these fights", function()
            ns.Recorder.DeleteFights(SetOf(ns.Recorder.FightsOf(session)))
        end)
    end)
end

--- What a click on a fight makes of a set of them: the one fight, a run
--- of fights with Shift held, or the set with that fight added or taken
--- out with Ctrl held.
---@param set table|nil  the set as it stands
---@param keepOne boolean  true if Ctrl-click mustn't take the last one out
---@return table set
local function AfterClick(set, fight, keepOne)
    -- The list may have grown or shrunk since the last click, so the run
    -- is worked out from where the two fights are now.
    local from, to = PlaceOf(lastClicked), PlaceOf(fight)
    if IsShiftKeyDown() and from and to then
        local run = {}
        for place = math.min(from, to), math.max(from, to) do
            run[order[place]] = true
        end
        return run
    end

    lastClicked = fight
    if IsControlKeyDown() and set then
        if not (keepOne and set[fight] and Count(set) == 1) then
            set[fight] = not set[fight] or nil
        end
        return set
    end
    return { [fight] = true }
end

local function OnRowClick(row, mouseButton)
    local data = row.data

    -- The "Other fights" divider is only a label.
    if data.divider then
        return
    end

    if data.recording then
        if mouseButton == "RightButton" then
            ShowSessionMenu(row, data.recording)
            return
        end

        local fights = SetOf(ns.Recorder.FightsOf(data.recording))
        if picking then
            other = fights
        else
            chosen = fights
        end
        lastClicked = nil
        Refresh()
        return
    end

    local fight = data.fight
    if mouseButton == "RightButton" then
        ShowFightMenu(row, fight)
        return
    end

    -- Taking the last fight out of what's being read would leave nothing
    -- to read. Taking the last one out of a comparison is only a change
    -- of mind.
    if picking then
        other = AfterClick(other, fight, false)
    else
        chosen = AfterClick(chosen, fight, true)
    end
    Refresh()
end

local function CreateRowWidgets(row)
    row.created = true
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", OnRowClick)

    -- The auction house's glow under the mouse and its band across a
    -- selected row.
    Kit.DressRow(row)

    -- A quiet band behind a session's heading, to set it off from the
    -- fights under it.
    row.band = row:CreateTexture(nil, "BACKGROUND")
    row.band:SetAllPoints()
    row.band:SetColorTexture(1, 1, 1, 0.05)

    -- A blue stripe down the left edge of a fight that's being compared
    -- with, and a word on the right to say what the stripe means.
    row.stripe = row:CreateTexture(nil, "BORDER")
    row.stripe:SetPoint("TOPLEFT")
    row.stripe:SetPoint("BOTTOMLEFT")
    row.stripe:SetWidth(3)
    row.stripe:SetColorTexture(Kit.BLUE[1], Kit.BLUE[2], Kit.BLUE[3], 1)

    row.title = Kit.Text(row, "GameFontNormal")

    row.when = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.when:SetPoint("TOPRIGHT", -6, -7)
    row.when:SetTextColor(unpack(Kit.MUTED))

    -- A star on a fight that holds one of the character's bests.
    row.best = Kit.Icon(row, 12, "best")
    row.best:SetPoint("RIGHT", row.when, "LEFT", -4, 0)

    row.tag = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.tag:SetTextColor(unpack(Kit.MUTED))
    row.tag:SetText("compared")

    row.detail = Kit.Text(row, "GameFontHighlightSmall")
    row.detail:SetPoint("BOTTOMLEFT", 10, 6)
    row.detail:SetPoint("RIGHT", -6, 0)
end

--- A heading row: a session's name and how many fights it holds, or the
--- divider that marks where a session's fights stop.
local function FillHeading(row, data)
    row.title:SetPoint("LEFT", 6, 0)
    row.title:SetPoint("RIGHT", row.when, "LEFT", -6, 0)
    row.detail:SetText("")
    row.band:Show()
    row.chosen:Hide()
    row.stripe:Hide()
    row.tag:Hide()
    row.best:Hide()
    row.hover:SetAlpha(data.divider and 0 or 1)

    if data.divider then
        row.title:SetText(Kit.Colored("Other fights", Kit.MUTED))
        row.when:SetText("")
        return
    end

    local session = data.recording
    local title = ("Session %d"):format(session.number)
    if ns.Recorder.Open() == session then
        title = title .. "  " .. Kit.Colored("in progress", Kit.GOOD)
    end
    row.title:SetText(title)
    row.when:SetText(FightsText(#ns.Recorder.FightsOf(session)))
end

local function FillRow(row, data)
    row.data = data
    row.title:ClearAllPoints()

    if not data.fight then
        FillHeading(row, data)
        return
    end

    local fight = data.fight
    local compared = other ~= nil and other[fight] == true

    row.band:Hide()
    row.hover:SetAlpha(1)
    row.chosen:SetShown(chosen[fight] == true)
    row.stripe:SetShown(compared)
    row.best:SetShown(data.best == true)

    -- Along the top, right to left: the time, the star, the tag. The
    -- name has whatever is left.
    local edge = data.best and row.best or row.when
    row.tag:SetShown(compared)
    if compared then
        row.tag:SetPoint("RIGHT", edge, "LEFT", -6, 0)
        edge = row.tag
    end

    row.title:SetPoint("TOPLEFT", 10, -6)
    row.title:SetPoint("RIGHT", edge, "LEFT", -6, 0)
    row.title:SetText(fight.target or "Fight")
    row.when:SetText(date("%H:%M", fight.at))

    local detail = ("%s dmg   %s DPS   %s   %s crit"):format(
        ns.Number(fight.damage),
        ns.Rate(fight.damage / fight.length),
        ns.Duration(fight.length),
        CritText(fight)
    )
    row.detail:SetText(fight.ignored and Kit.Colored(detail, Kit.MUTED) or detail)
end

--- The rows of the list: fights newest first, with a heading above each
--- session's run of them and a divider where a run gives way to fights
--- that weren't part of a session.
local function BuildRows()
    local fights = ns.character.fights
    local rows = {}
    order = {}

    local holdsBest = {}
    for _, best in ipairs(ns.Progress.Bests()) do
        holdsBest[best.fight] = true
    end

    -- A session with no fights yet still wants its heading, so the
    -- player can see that Start session did something.
    local open = ns.Recorder.Open()
    local headed = false
    if open and #ns.Recorder.FightsOf(open) == 0 then
        table.insert(rows, { recording = open })
        headed = true
    end

    -- Which session the rows being added belong to: a number, or false
    -- for none. Starts as nil so the first fight always counts as a change.
    local run
    for index = #fights, 1, -1 do
        local fight = fights[index]
        local session = fight.recording and ns.Recorder.Numbered(fight.recording)
        local belongs = session and session.number or false

        if belongs ~= run then
            run = belongs
            if session then
                table.insert(rows, { recording = session })
                headed = true
            elseif headed then
                table.insert(rows, { divider = true })
            end
        end

        table.insert(order, fight)
        table.insert(rows, { fight = fight, best = holdsBest[fight] })
    end
    return rows
end

-- The strip under the title bar -------------------------------------------------

--- Says where the player is in reading or comparing, and what to do next.
---@param selected table  the fights being read, as a list
---@param newer table  the fights on the page
---@param older table|nil  the fights they're measured against, if any
---@return string status, string nextStep
local function StripText(selected, newer, older)
    if picking then
        return "Now click the fights to compare with.",
            "Click one, Shift-click a run, or click a session's heading. Then press Done."
    end
    if #selected == 0 then
        return "Nothing selected.", "Click a fight in the list to read it."
    end

    if older then
        -- Whichever set carries the blue stripe in the list is named in
        -- blue here.
        local newerName, olderName = DatedName(newer), DatedName(older, true)
        if newer == selected then
            olderName = Kit.Colored(olderName, Kit.BLUE)
        else
            newerName = Kit.Colored(newerName, Kit.BLUE)
        end
        return ("Comparing %s with %s."):format(newerName, olderName),
            "Green is up since the earlier fights, red is down."
    end

    -- The fights being read are the very ones set aside to compare with,
    -- as after "Compare with this" on the selection.
    if other then
        return Kit.Colored("These are the fights to compare with.", Kit.BLUE),
            "Now click other fights to read them against these."
    end

    return ("Reading %s."):format(SetName(selected)),
        "To see what changed, press Compare with... and pick other fights."
end

--- Puts the right button, or pair of them, on the strip, and ends the
--- strip's two lines short of them.
---@param canCompare boolean  false when there's nothing to compare with
local function ShowStripButtons(canCompare)
    local compare, cancel = tab.compare, tab.cancel

    if picking then
        compare:SetText("Done")
        compare:SetEnabled(other ~= nil)
    elseif other then
        compare:SetText("Stop comparing")
        compare:SetEnabled(true)
    else
        compare:SetText("Compare with...")
        compare:SetEnabled(canCompare)
    end
    compare:SetWidth(picking and NARROW_BUTTON or WIDE_BUTTON)
    cancel:SetShown(picking)

    local leftmost = picking and cancel or compare
    tab.strip.status:SetPoint("RIGHT", leftmost, "LEFT", -STRIP_EDGE, 0)
    tab.strip.next:SetPoint("RIGHT", leftmost, "LEFT", -STRIP_EDGE, 0)
end

--- Builds the tab.
---@param parent table  the window's inset, which the tab fills
---@param window table  the window itself, whose bottom edge the buttons sit on
function FightsTab.Create(parent, window)
    tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()

    -- Left: the list, framed the way the game frames its own.
    local panel = Kit.Inset(tab)
    panel:SetPoint("TOPLEFT")
    panel:SetPoint("BOTTOMLEFT")
    panel:SetWidth(PANEL_WIDTH)

    local scrollBox = CreateFrame("Frame", nil, tab, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", panel, "TOPLEFT", LIST_EDGE, -LIST_EDGE)
    scrollBox:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LIST_EDGE, LIST_EDGE)
    scrollBox:SetWidth(LIST_WIDTH)

    local scrollBar = CreateFrame("EventFrame", nil, tab, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", SCROLL_BAR_GAP, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", SCROLL_BAR_GAP, 0)

    local view = CreateScrollBoxListLinearView()
    -- Rows are plain buttons rather than an XML template, so the list has
    -- to be told how tall each kind is.
    view:SetElementExtentCalculator(function(_, data)
        return data.fight and FIGHT_HEIGHT or HEADER_HEIGHT
    end)
    view:SetElementInitializer("Button", function(row, data)
        if not row.created then
            CreateRowWidgets(row)
        end
        FillRow(row, data)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    tab.scrollBox = scrollBox

    -- In the window's own strip under the title bar, clear of the emblem
    -- in its corner: where things stand and what to do next in two lines,
    -- and the button that takes the next step. It belongs to this tab and
    -- goes when the tab does.
    local strip = CreateFrame("Frame", nil, tab)
    strip:SetPoint("TOPLEFT", window, "TOPLEFT", STRIP_LEFT, -24)
    strip:SetPoint("RIGHT", window, "RIGHT", -6, 0)
    strip:SetHeight(STRIP_HEIGHT)
    tab.strip = strip

    tab.compare = Kit.Button(strip, "Compare with...", WIDE_BUTTON, OnCompareClick)
    tab.compare:SetPoint("RIGHT", -STRIP_EDGE, 0)

    tab.cancel = Kit.Button(strip, "Cancel", NARROW_BUTTON, OnCancelClick)
    tab.cancel:SetPoint("RIGHT", tab.compare, "LEFT", -BUTTON_GAP, 0)
    tab.cancel:Hide()

    -- Both lines stop short of the buttons; ShowStripButtons says where.
    strip.status = Kit.Text(strip, "GameFontNormal")
    strip.status:SetPoint("TOPLEFT", 0, -3)

    strip.next = Kit.Text(strip, "GameFontHighlightSmall")
    strip.next:SetPoint("TOPLEFT", strip.status, "BOTTOMLEFT", 0, -3)
    strip.next:SetTextColor(0.75, 0.75, 0.75)

    -- Right of the list: the analysis.
    tab.card = ns.Card.Create(tab)
    tab.card:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, -4)
    tab.card:SetPoint("BOTTOMRIGHT", -4, 4)

    -- Along the bottom of the window, where the game's own windows keep
    -- their buttons: the session button, and beside it how the list works
    -- for anyone who wants to be told.
    tab.record = Kit.Button(tab, "Start session", 120, function()
        ns.ToggleRecording()
    end)
    tab.record:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 8, 4)

    local help = Kit.HelpButton(tab, HELP_TITLE, HELP)
    help:SetPoint("LEFT", tab.record, "RIGHT", 8, 0)

    -- A comparison belongs to a sitting. Closing the window or turning to
    -- another tab ends it, so the next visit starts with plain reading
    -- and not with green and red figures nobody remembers asking for.
    tab:SetScript("OnHide", function()
        other = nil
        StopPicking()
    end)

    tab.Refresh = Refresh
    return tab
end

function Refresh()
    if not tab or not tab:IsVisible() then
        return
    end

    local rows = BuildRows()

    -- Hold on to the choices across a rebuild of the list, minus anything
    -- that has since been deleted. With nothing chosen, show the latest.
    Prune(chosen)
    if other then
        Prune(other)
        if not next(other) then
            other = nil
        end
    end
    if not next(chosen) and order[1] then
        chosen = { [order[1]] = true }
        lastClicked = not picking and order[1] or nil
    end
    if #order == 0 then
        StopPicking()
    end

    tab.scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)

    -- The page shows the newer of the two sets, measured against the
    -- older. Compared with themselves, fights have nothing to show.
    local selected = ListOf(chosen)
    local newer, older = selected, nil
    if other and not SameSet(chosen, other) then
        older = ListOf(other)
        if (older[1].at or 0) > (newer[1].at or 0) then
            newer, older = older, newer
        end
    end
    ns.Card.Fill(tab.card, newer, older, Heading(newer))

    local status, nextStep = StripText(selected, newer, older)
    tab.strip.status:SetText(status)
    tab.strip.next:SetText(nextStep)
    ShowStripButtons(#order > 1)

    tab.record:SetText(ns.Recorder.Open() and "End session" or "Start session")
end

--- Chooses what the tab shows the next time it's drawn.
---@param fights table  list of fights to read
---@param against table|nil  list of fights to compare them with; nil for
---                          no comparison
function FightsTab.Select(fights, against)
    chosen = SetOf(fights)
    other = against and #against > 0 and SetOf(against) or nil
    picking = false
    lastClicked = fights[1]
    Refresh()
end
