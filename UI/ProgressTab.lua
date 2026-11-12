local _, ns = ...

-- The Progress tab: how the character is coming along, measured only
-- against themselves.
--
-- Read top to bottom it's three things. The bests, four at most, to have
-- something to beat. A column for each day's DPS, to see which way it's
-- going. And, out of the way in the bottom right-hand corner of the
-- window, the button that forgets the lot.
--
-- A best is only worth having if it was earned, so each one can be left
-- out with a click when it was a fluke, and the next best takes its place
-- at once. Progress.lua decides what counts. This file only draws it.

local ProgressTab = {}
ns.ProgressTab = ProgressTab

local Kit = ns.Kit

-- The page is the window's inset, about 885 wide and 594 high. Down the
-- page, with all four bests showing, it's spent like this:
--
--   margin 10, the bests' header 24, gap 8        42
--   two rows of cards at 62, with 6 between      130
--   gap 10, the line on what counts 18            28
--   gap 18, the chart's header 24, gap 8          50
--   the chart                                    280
--   gap 10, the trend sentence 14                 24
--
-- That's 554, which leaves 40 clear above the bottom edge.
local PADDING = 14
local TOP_MARGIN = 10
local GAP = 8
local LINE_GAP = 10
local SECTION_GAP = 18

-- Bests sit two to a row, and there's room for two rows of them.
local MOST_BESTS = 4
local CARD_HEIGHT = 62
local CARD_GAP = 6

-- The line under the bests that says how many fights are left out.
local NOTE_HEIGHT = 18

local CHART_HEIGHT = 280

-- The days share the chart's width between them, up to a point: one or
-- two days with the whole width to themselves would be absurdly fat. A
-- column fills this much of its day's slot.
local WIDEST_SLOT = 120
local COLUMN_SHARE = 0.62

-- The chart's width when it's asked for before the window has been laid
-- out: the page less its padding.
local USUAL_CHART_WIDTH = 857

-- Room under the columns for the day and the level, and over the tallest
-- column for its figure.
local LABEL_ROOM = 32
local FIGURE_ROOM = 20
local TALLEST_COLUMN = CHART_HEIGHT - LABEL_ROOM - FIGURE_ROOM

local LEAVE_OUT_HELP = {
    "Stops this fight counting towards your bests and your day by day DPS. "
        .. "Your next best takes its place.",
    "To put it back, right-click the fight on the Fights tab.",
}

local WHAT_COUNTS = {
    "Very short fights are left out, and so are fights where much of the damage came from "
        .. "an item or some other effect.",
    "You can leave a fight out yourself, and put it back by right-clicking it on the "
        .. "Fights tab.",
}

local NO_FIGHTS = "No fights on record yet.\n\n"
    .. "Fight something on your own and your bests will appear here, "
    .. "with a column for each day's DPS."

local NONE_COUNTED = "None of your fights count towards your bests yet.\n\n"
    .. "Very short fights are left out, and so are fights where much of the damage came "
    .. "from an item or some other effect, and any you left out yourself. "
    .. "Fight something on your own for a little longer and it will appear here."

local ONE_DAY = "A good start: one day on record. "
    .. "Fight on another day and the two will be compared here."

local FORGET_HELP = "Deletes every fight, session and experiment kept for this character. "
    .. "It cannot be undone."

local FORGET_QUESTION = "Forget every fight, session and experiment kept for %s?\n\n"
    .. "This cannot be undone."

-- Columns darken towards the foot, so they stand on the baseline instead
-- of floating over it. The latest day is solid and the earlier ones are
-- let fall back a little.
local function ColumnShades(alpha)
    local r, g, b = unpack(Kit.BLUE)
    return CreateColor(r * 0.45, g * 0.45, b * 0.45, alpha), CreateColor(r, g, b, alpha)
end

local EARLIER_FOOT, EARLIER_TOP = ColumnShades(0.6)
local LATEST_FOOT, LATEST_TOP = ColumnShades(1)

local tab

-- What to call things ---------------------------------------------------------

local function FightsText(count)
    return count == 1 and "1 fight" or count .. " fights"
end

--- How many of the character's fights are being left out, in a sentence.
--- Only shown when at least one fight counts, so there are always two or
--- more fights to talk about once any is left out.
local function CountedText(fights)
    local leftOut, byHand = 0, 0
    for _, fight in ipairs(fights) do
        if ns.Progress.WhyNotCounted(fight) then
            leftOut = leftOut + 1
            if fight.ignored then
                byHand = byHand + 1
            end
        end
    end

    if leftOut == 0 then
        if #fights == 1 then
            return "Your one fight so far counts."
        end
        return ("All %d of your fights count at the moment."):format(#fights)
    end

    local text = ("%d of your %d fights %s not counted at the moment"):format(
        leftOut,
        #fights,
        leftOut == 1 and "is" or "are"
    )
    if byHand == leftOut then
        return text .. ", left out by you."
    elseif byHand > 0 then
        return ("%s, %d of them left out by you."):format(text, byHand)
    end
    return text .. "."
end

--- The lines of a column's tooltip.
local function DayLines(day)
    local lines = {
        FightsText(day.fights),
        ns.Duration(day.seconds) .. " of fighting",
        ns.Rate(day.dps) .. " DPS",
    }
    if day.level then
        table.insert(lines, "Level " .. day.level)
    end
    return lines
end

--- The latest day set against the one before it, in a sentence.
---@param days table  from Progress.ByDay; at least one day
---@return string text
---@return number|nil change  the figure behind it, for the arrow
local function Trend(days)
    local latest, earlier = days[#days], days[#days - 1]
    if not earlier then
        return ONE_DAY
    end

    -- A day on which nothing landed leaves nothing to measure from.
    local change = ns.Change(earlier.dps, latest.dps)
    if not change then
        return ("%s DPS on %s."):format(ns.Rate(latest.dps), latest.day)
    end

    local percent = math.floor(math.abs(change) * 100 + 0.5)
    local verdict
    if percent == 0 then
        verdict = "Level with"
    elseif change > 0 then
        verdict = Kit.Colored(("Up %d%%"):format(percent), Kit.GOOD) .. " on"
    else
        verdict = Kit.Colored(("Down %d%%"):format(percent), Kit.BAD) .. " on"
    end

    -- The day before is the last day there was a fight, which needn't be
    -- yesterday, so both days are named.
    local text = ("%s the day before: %s DPS on %s, %s on %s."):format(
        verdict,
        ns.Rate(latest.dps),
        latest.day,
        ns.Rate(earlier.dps),
        earlier.day
    )

    -- A level gained explains a good deal of any rise.
    if latest.level and earlier.level and latest.level ~= earlier.level then
        text = ("%s You were level %d then and are level %d now."):format(
            text,
            earlier.level,
            latest.level
        )
    end
    return text, change
end

-- The bests ---------------------------------------------------------------------

local function LeaveOut(fight)
    ns.Progress.SetIgnored(fight, true)
end

--- Left-click reads the fight behind a best. Right-click offers to leave
--- it out, for anyone who looks for that in a menu before they notice the
--- words in the corner.
local function OnCardClick(card, mouseButton)
    local best = card.best

    if mouseButton == "RightButton" then
        MenuUtil.CreateContextMenu(card, function(_, root)
            root:CreateTitle(best.title)
            root:CreateButton("Don't count this fight", function()
                LeaveOut(best.fight)
            end)
        end)
        return
    end

    ns.ShowFights({ best.fight })
end

--- The small print in a card's corner that leaves its fight out. It's
--- grey until the mouse is on it, so four of them don't shout over the
--- figures they sit beside.
local function CreateLeaveOutLink(card)
    local link = CreateFrame("Button", nil, card)

    local label = Kit.Text(link, "GameFontDisableSmall")
    label:SetPoint("CENTER")
    label:SetText("Leave out")

    link:SetFontString(label)
    link:SetNormalFontObject("GameFontDisableSmall")
    link:SetHighlightFontObject("GameFontHighlightSmall")
    link:SetSize(label:GetStringWidth() + 8, 18)
    link:SetScript("OnClick", function()
        LeaveOut(card.best.fight)
    end)

    Kit.Tooltip(link, "Leave this fight out", function()
        return LEAVE_OUT_HELP
    end)
    return link
end

--- One best: a star, what it's the best of, the figure in large type, and
--- which fight it was. Click it to read the fight.
local function CreateCard(index)
    local card = CreateFrame("Button", nil, tab.bests)
    card:SetHeight(CARD_HEIGHT)
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card:SetScript("OnClick", OnCardClick)

    -- Odd ones take the left half of the row, even ones the right.
    local row = math.floor((index - 1) / 2)
    local top = -row * (CARD_HEIGHT + CARD_GAP)
    if index % 2 == 1 then
        card:SetPoint("TOPLEFT", tab.bests, "TOPLEFT", 0, top)
        card:SetPoint("TOPRIGHT", tab.bests, "TOP", -CARD_GAP / 2, top)
    else
        card:SetPoint("TOPLEFT", tab.bests, "TOP", CARD_GAP / 2, top)
        card:SetPoint("TOPRIGHT", tab.bests, "TOPRIGHT", 0, top)
    end

    local fill = card:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(1, 1, 1, 0.04)

    local hover = card:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.06)

    local star = Kit.Icon(card, 22, "best")
    star:SetPoint("LEFT", 12, 0)

    card.link = CreateLeaveOutLink(card)
    card.link:SetPoint("BOTTOMRIGHT", -6, 4)

    card.title = Kit.Text(card, "GameFontDisableSmall")
    card.title:SetPoint("TOPLEFT", 46, -8)
    card.title:SetPoint("RIGHT", -10, 0)

    card.value = Kit.Text(card, "GameFontNormalHuge")
    card.value:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
    card.value:SetPoint("RIGHT", -10, 0)

    card.detail = Kit.Text(card, "GameFontHighlightSmall")
    card.detail:SetPoint("BOTTOMLEFT", 46, 8)
    card.detail:SetPoint("RIGHT", card.link, "LEFT", -8, 0)
    card.detail:SetTextColor(unpack(Kit.MUTED))

    tab.cards[index] = card
    return card
end

---@param bests table  from Progress.Bests; the first few are shown
local function FillBests(bests)
    local showing = math.min(#bests, MOST_BESTS)

    for index = 1, showing do
        local best = bests[index]
        local card = tab.cards[index] or CreateCard(index)
        card.best = best
        card.title:SetText(best.title)
        card.value:SetText(best.value)
        card.detail:SetText(best.detail)
        card:Show()
    end

    -- Cards are kept and reused, so any beyond today's bests are put away,
    -- along with their hold on a fight that may since have been deleted.
    for index = showing + 1, #tab.cards do
        tab.cards[index].best = nil
        tab.cards[index]:Hide()
    end

    -- Everything below is hung from the bottom of this, so it moves up
    -- when there's only one row of bests.
    local rows = math.max(math.ceil(showing / 2), 1)
    tab.bests:SetHeight(rows * CARD_HEIGHT + (rows - 1) * CARD_GAP)
end

-- Day by day -------------------------------------------------------------------

--- One day of the chart: a slot the full height of the chart, so there's
--- plenty to hover over, with the column standing in it. How wide it is
--- and where it stands depend on how many days there are, so that's left
--- to FillChart.
local function CreateColumn(index)
    local column = CreateFrame("Button", nil, tab.chart)

    local hover = column:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("TOPLEFT")
    hover:SetPoint("BOTTOMRIGHT", 0, LABEL_ROOM)
    hover:SetColorTexture(1, 1, 1, 0.06)

    -- White, so that the gradient set on it later is the only colour.
    column.bar = column:CreateTexture(nil, "ARTWORK")
    column.bar:SetPoint("BOTTOM", 0, LABEL_ROOM)
    column.bar:SetColorTexture(1, 1, 1, 1)

    column.figure = Kit.Text(column, "GameFontHighlightSmall", "CENTER")
    column.figure:SetPoint("BOTTOM", column.bar, "TOP", 0, 4)

    column.day = Kit.Text(column, "GameFontHighlightSmall", "CENTER")
    column.day:SetPoint("TOP", column, "BOTTOM", 0, LABEL_ROOM - 5)

    column.level = Kit.Text(column, "GameFontNormalSmall", "CENTER")
    column.level:SetPoint("TOP", column.day, "BOTTOM", 0, -3)

    -- A faint line down the left of a day that began at a new level.
    column.step = column:CreateTexture(nil, "BORDER")
    column.step:SetPoint("TOPLEFT")
    column.step:SetPoint("BOTTOMLEFT", 0, LABEL_ROOM)
    column.step:SetWidth(1)
    column.step:SetColorTexture(Kit.GOLD[1], Kit.GOLD[2], Kit.GOLD[3], 0.35)

    tab.columns[index] = column
    return column
end

---@param days table  from Progress.ByDay; at least one day
local function FillChart(days)
    local peak = 0
    for _, day in ipairs(days) do
        peak = math.max(peak, day.dps)
    end

    -- The days share the width between them. When the slots are as wide
    -- as they're allowed to be and there's width left over, the group
    -- stands in the middle of it.
    local width = tab.chart:GetWidth()
    width = width > 0 and width or USUAL_CHART_WIDTH
    local slot = math.floor(math.min(width / #days, WIDEST_SLOT))
    local left = math.floor((width - slot * #days) / 2)

    -- The level as of the day before, to tell when it changes.
    local level

    for index, day in ipairs(days) do
        local column = tab.columns[index] or CreateColumn(index)
        local latest = index == #days

        column:ClearAllPoints()
        column:SetPoint("BOTTOMLEFT", left + (index - 1) * slot, 0)
        column:SetSize(slot, CHART_HEIGHT)
        column.bar:SetWidth(math.floor(slot * COLUMN_SHARE))

        -- Every day gets at least a sliver, so a poor day isn't mistaken
        -- for a day not played, and a chart of nothing but days without
        -- damage has no peak to divide by.
        local share = peak > 0 and day.dps / peak or 0
        column.bar:SetHeight(math.max(share * TALLEST_COLUMN, 1))
        column.bar:SetGradient(
            "VERTICAL",
            latest and LATEST_FOOT or EARLIER_FOOT,
            latest and LATEST_TOP or EARLIER_TOP
        )

        column.figure:SetText(ns.Rate(day.dps))
        column.day:SetText(day.day)
        if latest then
            column.figure:SetTextColor(1, 1, 1)
            column.day:SetTextColor(1, 1, 1)
        else
            column.figure:SetTextColor(unpack(Kit.MUTED))
            column.day:SetTextColor(unpack(Kit.MUTED))
        end

        -- The level is written under the first day and again under each
        -- day it's different, with a line to mark the step.
        local changed = day.level ~= nil and day.level ~= level
        column.level:SetText(changed and ("level %d"):format(day.level) or "")
        column.step:SetShown(changed and level ~= nil)
        level = day.level or level

        Kit.Tooltip(column, day.day, function()
            return DayLines(day)
        end)
        column:Show()
    end

    for index = #days + 1, #tab.columns do
        tab.columns[index]:Hide()
    end
end

local function FillTrend(days)
    local text, change = Trend(days)
    tab.trend:SetText(text)

    -- With no arrow to show, a clock stands in for "give it time", so the
    -- words always start in the same place.
    Kit.SetArrow(tab.trendIcon, change)
    if not tab.trendIcon:IsShown() then
        Kit.SetIcon(tab.trendIcon, "clock")
        tab.trendIcon:Show()
    end
end

-- The tab -------------------------------------------------------------------------

local function Refresh()
    if not tab or not tab:IsVisible() then
        return
    end

    local fights = ns.character.fights
    local days = ns.Progress.ByDay()

    -- Bests and days are drawn from the same fights, the ones that count,
    -- so when there are no days there are no bests either.
    local nothing = #days == 0
    tab.content:SetShown(not nothing)
    tab.empty:SetShown(nothing)
    if nothing then
        tab.empty.text:SetText(#fights == 0 and NO_FIGHTS or NONE_COUNTED)
        return
    end

    FillBests(ns.Progress.Bests())
    tab.counted:SetText(CountedText(fights))
    FillChart(days)
    FillTrend(days)
end

local function AskToForget()
    local name = ns.character.name or "this character"
    Kit.Confirm(FORGET_QUESTION:format(name), ns.Recorder.ForgetEverything)
end

--- A section heading with a quiet word at its right-hand end saying what
--- the section is or what can be done with it.
local function CreateSection(parent, title, caption)
    local header = Kit.Header(parent, title)

    local hint = Kit.Text(header, "GameFontDisableSmall", "RIGHT")
    hint:SetPoint("TOPRIGHT", 0, -4)
    hint:SetText(caption)

    return header
end

--- What's shown until a fight counts: a picture and a few words on what
--- will appear here and how to make it.
local function CreateEmptyState()
    local empty = CreateFrame("Frame", nil, tab)
    empty:SetAllPoints()

    local icon = Kit.Icon(empty, 40, "combat")
    icon:SetPoint("CENTER", 0, 50)

    empty.text = Kit.Text(empty, "GameFontHighlight", "CENTER")
    empty.text:SetPoint("TOP", icon, "BOTTOM", 0, -14)
    empty.text:SetWidth(440)
    empty.text:SetWordWrap(true)
    empty.text:SetSpacing(3)
    empty.text:SetTextColor(unpack(Kit.MUTED))

    return empty
end

--- Builds the tab.
---@param parent table  the window's inset, which the tab fills
---@param window table  the window itself, whose bottom edge the button sits on
function ProgressTab.Create(parent, window)
    tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()
    tab.cards = {}
    tab.columns = {}

    tab.empty = CreateEmptyState()

    local content = CreateFrame("Frame", nil, tab)
    content:SetAllPoints()
    tab.content = content

    -- Top: the bests. The cards are made as they're first needed.
    local bestsHeader = CreateSection(content, "Your bests", "Click one to read the fight.")
    bestsHeader:SetPoint("TOPLEFT", PADDING, -TOP_MARGIN)
    bestsHeader:SetPoint("RIGHT", -PADDING, 0)

    tab.bests = CreateFrame("Frame", nil, content)
    tab.bests:SetPoint("TOPLEFT", bestsHeader, "BOTTOMLEFT", 0, -GAP)
    tab.bests:SetPoint("RIGHT", -PADDING, 0)
    tab.bests:SetHeight(CARD_HEIGHT)

    -- Under them: how many fights are left out, with the rules that leave
    -- them out a mouse-over away.
    local note = CreateFrame("Frame", nil, content)
    note:SetPoint("TOPLEFT", tab.bests, "BOTTOMLEFT", 0, -LINE_GAP)
    note:SetPoint("RIGHT", -PADDING, 0)
    note:SetHeight(NOTE_HEIGHT)

    local whatCounts = Kit.HelpButton(note, "Which fights count", WHAT_COUNTS)
    whatCounts:SetPoint("LEFT")

    tab.counted = Kit.Text(note, "GameFontHighlightSmall")
    tab.counted:SetPoint("LEFT", whatCounts, "RIGHT", 6, 0)
    tab.counted:SetPoint("RIGHT")
    tab.counted:SetTextColor(unpack(Kit.MUTED))

    -- Middle: a column a day.
    local daysHeader =
        CreateSection(content, "DPS, day by day", "One column for each day you fought.")
    daysHeader:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -SECTION_GAP)
    daysHeader:SetPoint("RIGHT", -PADDING, 0)

    tab.chart = CreateFrame("Frame", nil, content)
    tab.chart:SetPoint("TOPLEFT", daysHeader, "BOTTOMLEFT", 0, -GAP)
    tab.chart:SetPoint("RIGHT", -PADDING, 0)
    tab.chart:SetHeight(CHART_HEIGHT)

    local backing = tab.chart:CreateTexture(nil, "BACKGROUND")
    backing:SetPoint("TOPLEFT")
    backing:SetPoint("BOTTOMRIGHT", 0, LABEL_ROOM)
    backing:SetColorTexture(1, 1, 1, 0.03)

    local baseline = tab.chart:CreateTexture(nil, "BORDER")
    baseline:SetPoint("BOTTOMLEFT", 0, LABEL_ROOM - 1)
    baseline:SetPoint("BOTTOMRIGHT", 0, LABEL_ROOM - 1)
    baseline:SetHeight(1)
    baseline:SetColorTexture(Kit.MUTED[1], Kit.MUTED[2], Kit.MUTED[3], 0.6)

    -- And the upshot of the chart in a sentence.
    tab.trendIcon = Kit.Icon(content, 14)
    tab.trendIcon:SetPoint("TOPLEFT", tab.chart, "BOTTOMLEFT", 0, -LINE_GAP)

    tab.trend = Kit.Text(content, "GameFontHighlight")
    tab.trend:SetPoint("LEFT", tab.trendIcon, "RIGHT", 6, 0)
    tab.trend:SetPoint("RIGHT", -PADDING, 0)

    -- Bottom: forgetting everything, on the window's own edge. It has the
    -- right-hand corner to itself, because the left is where the other
    -- tabs keep the button that starts something, and this is no button
    -- to click by habit. Its warning runs up to it from the left.
    local forget = Kit.Button(tab, "Forget everything", 140, AskToForget)
    forget:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -8, 4)

    local forgetHelp = Kit.Text(tab, "GameFontHighlightSmall", "RIGHT")
    forgetHelp:SetPoint("RIGHT", forget, "LEFT", -10, 0)
    forgetHelp:SetTextColor(unpack(Kit.MUTED))
    forgetHelp:SetText(FORGET_HELP)

    tab.Refresh = Refresh
    return tab
end
