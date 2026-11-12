local _, ns = ...

-- The Fights tab: every fight down the left, the analysis of the selected
-- ones on the right.
--
-- Click a fight to read it. Shift-click selects a run of fights and
-- Ctrl-click adds one, and the analysis covers whatever is selected.
--
-- To compare, one selection is kept as "Before" and another is read
-- against it. The strip above the analysis always says which of those
-- steps the player is at, so there's never a hidden mode to remember.

local FightsTab = {}
ns.FightsTab = FightsTab

local Kit = ns.Kit

local LIST_WIDTH = 270
local FIGHT_HEIGHT = 40
local HEADER_HEIGHT = 26
local HELP_HEIGHT = 76
local STRIP_HEIGHT = 44

local NO_FIGHTS = "No fights on record yet.\n\n"
    .. "Fight something on your own and it will appear in the list. "
    .. "Press Record first if you want a run of fights kept together."

local HELP = "Click a fight to read it. Shift-click selects a run of fights; Ctrl-click adds one. "
    .. "Right-click for more.\n"
    .. "These are yours alone. Nothing here is shared or posted."

local tab

-- What's selected, and what's kept as "Before": sets of fights.
local chosen = {}
local before

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

--- A title and subtitle for whatever is selected.
local function Heading(fights)
    local heading = { empty = "Select a fight on the left to read it." }
    if #order == 0 then
        heading.empty = NO_FIGHTS
    end
    if #fights == 0 then
        return heading
    end

    -- `fights` is newest first.
    local newest, oldest = fights[1], fights[#fights]

    if #fights == 1 then
        heading.title = newest.target or "Fight"
        heading.subtitle = date("%d %b %H:%M", newest.at)
    else
        heading.title = FightsText(#fights)
        heading.subtitle = ("%s to %s"):format(
            date("%d %b %H:%M", oldest.at),
            date("%H:%M", newest.at)
        )

        -- If they're exactly one recording, say so.
        local recording = newest.recording and ns.Recorder.Numbered(newest.recording)
        if recording and #ns.Recorder.FightsOf(recording) == #fights then
            local whole = true
            for _, fight in ipairs(fights) do
                whole = whole and fight.recording == recording.number
            end
            if whole then
                heading.title = "Recording " .. recording.number
                heading.recording = recording
            end
        end
    end

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
        local what = count == 1 and "this fight" or ("these %d fights"):format(count)

        root:CreateTitle(count == 1 and (fight.target or "Fight") or FightsText(count))
        root:CreateButton(("Keep %s as Before"):format(what), function()
            before = SetOf(ListOf(target))
            Refresh()
        end)

        -- Leaving a fluke out of the bests and trends is a one-fight thing.
        if count == 1 then
            if fight.ignored then
                root:CreateButton("Count it towards my bests again", function()
                    ns.Progress.SetIgnored(fight, false)
                end)
            else
                root:CreateButton("Leave it out of my bests", function()
                    ns.Progress.SetIgnored(fight, true)
                end)
            end
        end

        root:CreateButton(("Delete %s"):format(what), function()
            ns.Recorder.DeleteFights(target)
        end)
    end)
end

local function ShowRecordingMenu(row, recording)
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle("Recording " .. recording.number)
        root:CreateButton("Keep as Before", function()
            before = SetOf(ns.Recorder.FightsOf(recording))
            Refresh()
        end)
        root:CreateButton("Delete these fights", function()
            ns.Recorder.DeleteFights(SetOf(ns.Recorder.FightsOf(recording)))
        end)
    end)
end

local function OnRowClick(row, mouseButton)
    local data = row.data

    -- The "Not recorded" divider is only a label.
    if data.divider then
        return
    end

    if data.recording then
        if mouseButton == "RightButton" then
            ShowRecordingMenu(row, data.recording)
        else
            chosen = SetOf(ns.Recorder.FightsOf(data.recording))
            lastClicked = nil
            Refresh()
        end
        return
    end

    local fight = data.fight
    if mouseButton == "RightButton" then
        ShowFightMenu(row, fight)
        return
    end

    -- The list may have grown or shrunk since the last click, so the run
    -- is worked out from where the two fights are now.
    local from, to = PlaceOf(lastClicked), PlaceOf(fight)
    if IsShiftKeyDown() and from and to then
        chosen = {}
        for place = math.min(from, to), math.max(from, to) do
            chosen[order[place]] = true
        end
    elseif IsControlKeyDown() then
        -- Taking the last one out would leave nothing to read.
        if not (chosen[fight] and Count(chosen) == 1) then
            chosen[fight] = not chosen[fight] or nil
        end
        lastClicked = fight
    else
        chosen = { [fight] = true }
        lastClicked = fight
    end
    Refresh()
end

local function CreateRowWidgets(row)
    row.created = true
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", OnRowClick)

    row.fill = row:CreateTexture(nil, "BACKGROUND")
    row.fill:SetAllPoints()

    -- A stripe down the left edge: gold for selected, blue for Before.
    row.stripe = row:CreateTexture(nil, "BORDER")
    row.stripe:SetPoint("TOPLEFT")
    row.stripe:SetPoint("BOTTOMLEFT")
    row.stripe:SetWidth(3)

    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.06)

    row.title = Kit.Text(row, "GameFontNormal")

    row.when = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.when:SetPoint("TOPRIGHT", -6, -7)
    row.when:SetTextColor(unpack(Kit.MUTED))

    -- A star on a fight that holds one of the character's bests.
    row.best = Kit.Icon(row, 12, "best")
    row.best:SetPoint("RIGHT", row.when, "LEFT", -4, 0)

    row.detail = Kit.Text(row, "GameFontHighlightSmall")
    row.detail:SetPoint("BOTTOMLEFT", 10, 6)
    row.detail:SetPoint("RIGHT", -6, 0)
end

--- A heading row: a recording's name and how many fights it holds, or the
--- divider that marks where the recorded fights stop.
local function FillHeading(row, data)
    row.title:SetPoint("LEFT", 6, 0)
    row.title:SetPoint("RIGHT", row.when, "LEFT", -6, 0)
    row.detail:SetText("")
    row.fill:SetColorTexture(1, 1, 1, 0.05)
    row.stripe:Hide()
    row.best:Hide()
    row.hover:SetAlpha(data.divider and 0 or 1)

    if data.divider then
        row.title:SetText(Kit.Colored("Not recorded", Kit.MUTED))
        row.when:SetText("")
        return
    end

    local recording = data.recording
    local title = ("Recording %d"):format(recording.number)
    if ns.Recorder.Open() == recording then
        title = title .. "  " .. Kit.Colored("recording now", Kit.BAD)
    end
    row.title:SetText(title)
    row.when:SetText(FightsText(#ns.Recorder.FightsOf(recording)))
end

local function FillRow(row, data)
    row.data = data
    row.title:ClearAllPoints()

    if not data.fight then
        FillHeading(row, data)
        return
    end

    local fight = data.fight
    row.hover:SetAlpha(1)
    row.best:SetShown(data.best == true)
    row.title:SetPoint("TOPLEFT", 10, -6)
    row.title:SetPoint("RIGHT", data.best and row.best or row.when, "LEFT", -6, 0)
    row.title:SetText(fight.target or "Fight")
    row.when:SetText(date("%H:%M", fight.at))

    local detail = ("%s dmg   %s dps   %s   %s crit"):format(
        ns.Number(fight.damage),
        ns.Rate(fight.damage / fight.length),
        ns.Duration(fight.length),
        CritText(fight)
    )
    row.detail:SetText(fight.ignored and Kit.Colored(detail, Kit.MUTED) or detail)

    local isBefore = before and before[fight]
    if chosen[fight] then
        row.fill:SetColorTexture(Kit.GOLD[1], Kit.GOLD[2], Kit.GOLD[3], 0.14)
    elseif isBefore then
        row.fill:SetColorTexture(Kit.BLUE[1], Kit.BLUE[2], Kit.BLUE[3], 0.12)
    else
        row.fill:SetColorTexture(0, 0, 0, 0)
    end

    local stripe = (isBefore and Kit.BLUE) or (chosen[fight] and Kit.GOLD) or nil
    row.stripe:SetShown(stripe ~= nil)
    if stripe then
        row.stripe:SetColorTexture(stripe[1], stripe[2], stripe[3], 1)
    end
end

--- The rows of the list: fights newest first, with a heading above each
--- recording's run of them and a divider where a run gives way to fights
--- that weren't recorded.
local function BuildRows()
    local fights = ns.character.fights
    local rows = {}
    order = {}

    local holdsBest = {}
    for _, best in ipairs(ns.Progress.Bests()) do
        holdsBest[best.fight] = true
    end

    -- A recording with no fights yet still wants its heading, so the
    -- player can see that Record did something.
    local open = ns.Recorder.Open()
    local headed = false
    if open and #ns.Recorder.FightsOf(open) == 0 then
        table.insert(rows, { recording = open })
        headed = true
    end

    -- Which recording the rows being added belong to: a number, or false
    -- for none. Starts as nil so the first fight always counts as a change.
    local run
    for index = #fights, 1, -1 do
        local fight = fights[index]
        local recording = fight.recording and ns.Recorder.Numbered(fight.recording)
        local belongs = recording and recording.number or false

        if belongs ~= run then
            run = belongs
            if recording then
                table.insert(rows, { recording = recording })
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

-- The strip above the analysis --------------------------------------------------

--- Says where the player is in reading or comparing, and what to do next.
local function StripText(selected, kept)
    if selected == 0 then
        return "Nothing selected.", "Click a fight in the list to read it."
    end
    if not before then
        return ("Reading %s."):format(FightsText(selected)),
            "To compare: press Keep as Before below, then select the fights to set against them."
    end

    if SameSet(chosen, before) then
        return Kit.Colored(("%s kept as Before."):format(FightsText(kept)), Kit.BLUE),
            "Now select the fights to compare with them. Changes will show in green and red."
    end
    return ("Reading %s against %s."):format(
        FightsText(selected),
        Kit.Colored(("%d kept as Before"):format(kept), Kit.BLUE)
    ),
        "Green is up since Before, red is down. Select other fights to compare those instead."
end

--- Builds the tab.
---@param parent table  the window's inset, which the tab fills
---@param window table  the window itself, whose bottom edge the buttons sit on
function FightsTab.Create(parent, window)
    tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()

    -- Left: the list, with a line of help under it.
    local scrollBox = CreateFrame("Frame", nil, tab, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 6, -6)
    scrollBox:SetPoint("BOTTOMLEFT", 6, HELP_HEIGHT)
    scrollBox:SetWidth(LIST_WIDTH)

    local scrollBar = CreateFrame("EventFrame", nil, tab, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

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

    local help = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", scrollBox, "BOTTOMLEFT", 4, -8)
    help:SetWidth(LIST_WIDTH)
    help:SetJustifyH("LEFT")
    help:SetJustifyV("TOP")
    help:SetSpacing(3)
    help:SetTextColor(unpack(Kit.MUTED))
    help:SetText(HELP)

    -- Right, top: where things stand and what to do next, in two lines
    -- that have the full width to themselves.
    local strip = CreateFrame("Frame", nil, tab)
    strip:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 24, 0)
    strip:SetPoint("RIGHT", -6, 0)
    strip:SetHeight(STRIP_HEIGHT)
    tab.strip = strip

    local backing = strip:CreateTexture(nil, "BACKGROUND")
    backing:SetAllPoints()
    backing:SetColorTexture(1, 1, 1, 0.04)

    strip.status = Kit.Text(strip, "GameFontNormal")
    strip.status:SetPoint("TOPLEFT", 10, -7)
    strip.status:SetPoint("RIGHT", -10, 0)

    strip.next = Kit.Text(strip, "GameFontHighlightSmall")
    strip.next:SetPoint("TOPLEFT", strip.status, "BOTTOMLEFT", 0, -4)
    strip.next:SetPoint("RIGHT", -10, 0)
    strip.next:SetTextColor(0.75, 0.75, 0.75)

    -- Right, below: the analysis.
    tab.card = ns.Card.Create(tab)
    tab.card:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -4)
    tab.card:SetPoint("BOTTOMRIGHT", -4, 4)

    -- Along the bottom of the window, where the game's own windows keep
    -- their buttons: Record on the left, the two that compare on the right.
    tab.record = Kit.Button(tab, "Record", 120, function()
        ns.ToggleRecording()
    end)
    tab.record:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 8, 4)

    tab.keep = Kit.Button(tab, "Keep as Before", 130, function()
        before = SetOf(ListOf(chosen))
        Refresh()
    end)
    tab.keep:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -8, 4)

    tab.stop = Kit.Button(tab, "Stop comparing", 130, function()
        before = nil
        Refresh()
    end)
    tab.stop:SetPoint("RIGHT", tab.keep, "LEFT", -6, 0)

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
    if before then
        Prune(before)
        if Count(before) == 0 then
            before = nil
        end
    end
    if Count(chosen) == 0 and order[1] then
        chosen = { [order[1]] = true }
        lastClicked = order[1]
    end

    tab.scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)

    local selected = ListOf(chosen)
    local comparing = before and not SameSet(chosen, before)
    ns.Card.Fill(tab.card, selected, comparing and ListOf(before) or nil, Heading(selected))

    local status, nextStep = StripText(#selected, Count(before))
    tab.strip.status:SetText(status)
    tab.strip.next:SetText(nextStep)

    tab.keep:SetEnabled(#selected > 0)
    tab.stop:SetShown(before ~= nil)
    tab.record:SetText(ns.Recorder.Open() and "Stop recording" or "Record")
end

--- Chooses what the tab shows the next time it's drawn.
---@param fights table  list of fights to select
---@param against table|nil  list of fights to keep as Before; nil clears it
function FightsTab.Select(fights, against)
    chosen = SetOf(fights)
    lastClicked = fights[1]
    before = against and #against > 0 and SetOf(against) or nil
    Refresh()
end
