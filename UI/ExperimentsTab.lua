local _, ns = ...

-- The Experiments tab: every experiment down the left, and on the right
-- either the page for the selected one or the form that starts a new one.
--
-- An experiment is a short task with someone to guide you through it, so
-- its page is a checklist of three steps rather than a table of figures:
-- win a few fights as you are, make your change, win the same number
-- again. The step the player is on is marked, and the one button they
-- have to click sits on the step that needs it. The verdict comes next as
-- soon as there's anything to say, with the figures it rests on under it,
-- and is only given a colour and an arrow when it's sure enough of itself
-- to deserve them.
--
-- The page and the form are built from the same pieces as the Fights page
-- and laid out the same way (see "Pages" in Kit.lua): a title on its line
-- at the top, and under it each part in a box of its own, so that moving
-- between the two tabs nothing jumps.
--
-- All the reckoning is in Record\Experiments.lua. This file only draws it.

local ExperimentsTab = {}
ns.ExperimentsTab = ExperimentsTab

local Kit = ns.Kit
local Experiments = ns.Experiments

local Paragraph = Kit.Paragraph
local Place, PlaceText = Kit.Place, Kit.PlaceText
local Inside, PlaceSection = Kit.Inside, Kit.PlaceSection

-- The list sits in a sunken panel with its scroll bar, laid out as on the
-- Fights tab so the two don't jump when switching between them. The panel
-- shares the window's own edge on three sides, so only its right-hand
-- edge is new: a line between the list and the page.
local LIST_WIDTH = 270
local LIST_EDGE = 4
local PANEL_WIDTH = 292
local ROW_HEIGHT = 40

-- Space between the right-hand side's edge and what's on it, and the room
-- kept clear down its right for the scroll bar. Both as on the Fights page.
local MARGIN = 14
local SCROLL_BAR_ROOM = 24

-- Down the top: the line the title stands on, with the small print to its
-- right, and where the sections start.
local TITLE_FOOT = 26
local TITLE_GAP = 12
local HEAD_HEIGHT = 32

-- How wide the page is when the window is its usual size. Only used if
-- it's filled before the game has worked out its real width.
local USUAL_WIDTH = 547

-- Space between one section and the next, between lines of text in one,
-- and above a button.
local SECTION_GAP = Kit.SECTION_GAP
local LINE_GAP = 6
local BUTTON_GAP = 8

-- A step of the checklist is an icon with its words starting this far in
-- to clear it: what to do, and a note under that. The middle step has the
-- button as well while it's wanted.
local STEP_ICON = 16
local STEP_INDENT = 26
local NOTE_GAP = 4
local STEP_GAP = 10
local CONTINUE_HEIGHT = 28

-- The verdict: its headline, with an arrow before it when it has earned
-- one, and under a rule the figures it rests on, a cell for each.
local HEADLINE_HEIGHT = 20
local HEADLINE_ARROW = 16
local HEADLINE_INDENT = 24
local RULE_GAP = 10
local FIGURES_HEIGHT = 44
local FIGURE_WIDTH = 110
local FIGURE_PADDING = 10
local FIGURE_VALUE_TOP = 15
local FIGURE_COUNT_TOP = 33
local FIGURE_ARROW = 12
local FIGURE_ARROW_GAP = 3

-- The form: the question box, whose border the template draws a little
-- outside it; the row the menu of sizes stands in; and the line of advice
-- with its icon.
local BOX_NUDGE = 5
local BOX_HEIGHT = 22
local SIZE_ROW = 28
local MENU_WIDTH = 140
local ADVICE_ICON = 20
local ADVICE_INDENT = 28

-- How many fights in each set the form offers.
local SIZES = { 3, 5, 8 }

local WHITE = { 1, 1, 1 }

local HELP = {
    "Click an experiment to read it.",
    "Right-click one to delete it.",
}

local NONE = "No experiments yet.\n\nExperiments are kept on this computer and never shared."

local IDEA = "No two fights go the same way, so one fight can't tell you whether a change "
    .. "helped. An experiment compares a few fights before the change with a few after it."

local SIZE_HINT = "More fights take longer and give a surer answer."

local READY = "It starts straight away. Your next fights are the first set."

local FAIRER = "The same kind of enemy each time makes it fairer."

-- Said under the steps while a set is being recorded. With the panel
-- switched off nothing on screen says when the set is finished, so the
-- player is told to look here for it.
local COUNTED_WITH_PANEL = "You can close this window: fights are counted as you win them, "
    .. "and the panel keeps count."
local COUNTED_WITHOUT_PANEL = "Fights are counted as you win them. Check back here to see "
    .. "when the set is done."

-- Said in place of a verdict while there isn't one, and after one given
-- before the second set is finished.
local NOT_YET = "It will appear here once there are fights in both sets."
local NOTHING_TO_COMPARE = "There aren't fights in both sets, so there's nothing to compare."
local MAY_CHANGE = "The second set is still being recorded, so this may change."

-- How far along a step is, for each state an experiment can be in.
local STEP_STATES = {
    before = { "recording", "later", "later" },
    change = { "done", "waiting", "later" },
    after = { "done", "done", "recording" },
    done = { "done", "done", "done" },
}

local STEP_ICONS = {
    done = "good",
    recording = "recording",
    waiting = "waiting",
    later = "ready",
}

-- The step in hand is gold, like a heading. Finished ones are plain.
local STEP_COLORS = {
    done = WHITE,
    recording = Kit.GOLD,
    waiting = Kit.GOLD,
    later = Kit.MUTED,
}

-- A finished experiment's verdict in a word or two, for its row in the list.
local VERDICT_WORDS = {
    clear = { better = "Better", worse = "Worse" },
    likely = { better = "Probably better", worse = "Probably worse" },
}

local tab

-- The experiment whose page is showing, and whether the form is showing in
-- its place. While the form is up nothing is selected.
local selected
local composing = false

-- The form's choice of how many fights in each set, kept between
-- experiments.
local fightsEachWay = Experiments.DEFAULT_SIZE

local Refresh

-- What to call things ---------------------------------------------------------

local function FightsText(count)
    return count == 1 and "1 fight" or count .. " fights"
end

local function Question(experiment)
    return experiment.question or ("Experiment %d"):format(experiment.number)
end

--- True if the experiment is still on the books, not deleted meanwhile.
local function StillKept(experiment)
    for _, candidate in ipairs(ns.character.experiments) do
        if candidate == experiment then
            return true
        end
    end
    return false
end

--- Whether a verdict points one way firmly enough to be given a colour and
--- an arrow. One that's too close to call gets neither, anywhere on the
--- tab, so that green, red and an arrow always mean something.
local function PointsOneWay(verdict)
    return verdict.direction ~= "same" and verdict.sureness ~= "unsure"
end

--- "+12%" or "-8%" with no colour of its own, for a change that hasn't
--- earned green or red.
local function PlainChangeText(change)
    local percent = math.floor(math.abs(change) * 100 + 0.5)
    if percent == 0 then
        return "no change"
    end
    return ("%s%d%%"):format(change > 0 and "+" or "-", percent)
end

--- Where an experiment stands, in a few words, for its row in the list.
---@return string text
---@return number|nil change  for the arrow, when the verdict points one way
local function Standing(experiment)
    local state = experiment.state
    if state == "change" then
        return Kit.Colored("Waiting for your change", Kit.GOLD)
    elseif state == "before" or state == "after" then
        -- While a set is being recorded, the state is the name of that set.
        return ("Recording the %s set: %d of %d"):format(
            state == "before" and "first" or "second",
            #Experiments.FightsOf(experiment, state),
            experiment.size
        )
    end

    local verdict = Experiments.Verdict(experiment)
    if not verdict then
        return Kit.Colored("Nothing to compare", Kit.MUTED)
    elseif not PointsOneWay(verdict) then
        -- No different, or no telling: the verdict's own headline, in grey.
        local headline = Experiments.InWords(verdict)
        return Kit.Colored(headline, Kit.MUTED)
    end

    local words = VERDICT_WORDS[verdict.sureness][verdict.direction]
    return words .. "  " .. Kit.ChangeText(verdict.change), verdict.change
end

--- Why a new experiment can't be started just now, and what to do about
--- it. Nil if one can.
local function WhyNotStart()
    local running = Experiments.Running()
    if running then
        return (
            '"%s" isn\'t finished yet, and only one experiment can run at a time. '
            .. "Finish it, or delete it, and then start this one."
        ):format(Question(running))
    end

    if ns.Recorder.Open() then
        return "A session is in progress. End it first with the End session button "
            .. "on the Fights tab."
    end
end

--- What a step asks for and, for a set of fights that has been begun, how
--- far along it is: "1.  Win 5 fights as you are now.   3 of 5".
---@param index number  1, 2 or 3
---@param state string  a value from STEP_STATES
local function StepTitle(experiment, index, state)
    if index == 2 then
        return "2.  Make your change."
    end

    local title = index == 1 and "1.  Win %d fights as you are now." or "3.  Win %d more fights."
    title = title:format(experiment.size)
    if state == "later" then
        return title
    end

    -- The count stands out from the gold of the step in hand, and falls
    -- back once the step is finished.
    local fought = #Experiments.FightsOf(experiment, index == 1 and "before" or "after")
    local progress = ("%d of %d"):format(fought, experiment.size)
    return title .. "   " .. Kit.Colored(progress, state == "recording" and WHITE or Kit.MUTED)
end

--- The line under a step: a word of advice, or what to do about it.
local function StepNote(index, state)
    if index == 1 then
        return Kit.Colored(FAIRER, Kit.MUTED)
    elseif index == 3 or state == "later" then
        return ""
    end

    if state == "done" then
        return Kit.Colored("Done.", Kit.MUTED)
    elseif ns.Recorder.Open() then
        return "A session is in progress. End it on the Fights tab, then come back."
    end
    return "Swap the gear, change the build, whatever you're testing. Then click the button."
end

-- Starting and deleting -------------------------------------------------------

local function StartExperiment()
    local question = ns.CleanNote(tab.form.question:GetText())
        or ("Experiment %d"):format(ns.character.nextExperiment)

    local experiment = Experiments.Start(question, fightsEachWay)
    if not experiment then
        return
    end

    tab.form.question:SetText("")
    tab.form.question:ClearFocus()
    selected = experiment
    composing = false
    Refresh()
end

local function ConfirmDelete(experiment)
    local question = (
        'Delete the experiment "%s"?\n\n'
        .. "Its fights are kept. You'll still find them on the Fights tab."
    ):format(Question(experiment))

    Kit.Confirm(question, function()
        -- The dialog can sit open while things change behind it. Deleting
        -- one that's already gone could stop a recording that isn't its own.
        if StillKept(experiment) then
            Experiments.Delete(experiment)
        end
    end)
end

-- The list ---------------------------------------------------------------------

local function OnRowClick(row, mouseButton)
    local experiment = row.data.experiment

    if mouseButton == "RightButton" then
        MenuUtil.CreateContextMenu(row, function(_, root)
            root:CreateTitle(Question(experiment))
            root:CreateButton("Delete this experiment", function()
                ConfirmDelete(experiment)
            end)
        end)
        return
    end

    selected = experiment
    composing = false
    Refresh()
end

local function CreateRowWidgets(row)
    row.created = true
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", OnRowClick)

    -- The glow under the mouse and the band across the selected one, as
    -- on the Fights tab.
    Kit.DressRow(row)

    row.when = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.when:SetPoint("TOPRIGHT", -6, -7)
    row.when:SetTextColor(unpack(Kit.MUTED))

    row.title = Kit.Text(row, "GameFontNormal")
    row.title:SetPoint("TOPLEFT", 10, -6)
    row.title:SetPoint("TOPRIGHT", row.when, "TOPLEFT", -6, 1)

    row.arrow = Kit.Icon(row, 12)
    row.arrow:SetPoint("BOTTOMLEFT", 10, 5)

    row.detail = Kit.Text(row, "GameFontHighlightSmall")
end

local function FillRow(row, data)
    local experiment = data.experiment
    row.data = data

    row.title:SetText(Question(experiment))
    row.when:SetText(date("%d %b", experiment.startedAt))

    local standing, change = Standing(experiment)
    row.detail:SetText(standing)
    Kit.SetArrow(row.arrow, change)

    -- The words start where the arrow would be when there isn't one.
    row.detail:ClearAllPoints()
    row.detail:SetPoint("BOTTOMLEFT", row.arrow:IsShown() and 25 or 10, 6)
    row.detail:SetPoint("BOTTOMRIGHT", -6, 6)

    row.chosen:SetShown(experiment == selected)
end

--- The rows of the list: experiments, newest first.
local function BuildRows()
    local experiments = ns.character.experiments
    local rows = {}
    for index = #experiments, 1, -1 do
        table.insert(rows, { experiment = experiments[index] })
    end
    return rows
end

-- Laying out ---------------------------------------------------------------------

--- Notes a piece of the page, so that a fill can start by clearing every
--- piece away and then show only the ones it places.
local function Piece(page, piece)
    table.insert(page.pieces, piece)
    return piece
end

--- The width there is for the sections, on the page or the form.
local function WidthOf(frame)
    local width = frame:GetWidth()
    return width > 0 and width or USUAL_WIDTH
end

--- Puts a piece that keeps its own width in its place: a button, say,
--- which Kit.Place would stretch to the width of the section.
---@param indent number|nil  how far in from the layout's left edge
local function PlaceFixed(layout, piece, gap, indent)
    layout.y = layout.y + gap

    piece:ClearAllPoints()
    piece:SetPoint("TOPLEFT", layout.frame, "TOPLEFT", layout.left + (indent or 0), -layout.y)
    piece:Show()

    layout.y = layout.y + piece:GetHeight()
end

--- Places text in line with the words of the steps, clear of their icons.
local function PlaceIndented(layout, text, gap, words)
    local indented = {
        frame = layout.frame,
        left = layout.left + STEP_INDENT,
        width = layout.width - STEP_INDENT,
        y = layout.y,
    }
    PlaceText(indented, text, gap, words)
    layout.y = indented.y
end

-- The steps --------------------------------------------------------------------

--- One line of the checklist: an icon for how far along it is, what to
--- do, and a note underneath.
local function CreateStep(section)
    local step = CreateFrame("Frame", nil, section)

    step.icon = Kit.Icon(step, STEP_ICON)
    step.icon:SetPoint("TOPLEFT")

    step.title = Kit.Text(step, "GameFontHighlight")
    step.title:SetPoint("TOPLEFT", STEP_INDENT, -1)

    step.note = Paragraph(step, "GameFontHighlightSmall")
    step.note:SetPoint("TOPLEFT", step.title, "BOTTOMLEFT", 0, -NOTE_GAP)

    return step
end

--- Fills a step in and makes it as tall as what's in it.
---@param width number  of the whole step, icon and all
---@param button table|nil  the button to show under the note, if any
local function FillStep(step, state, title, note, width, button)
    Kit.SetIcon(step.icon, STEP_ICONS[state])

    -- A step that hasn't been reached is greyed out rather than hidden, so
    -- the whole task can be seen from the start.
    local later = state == "later"
    step.icon:SetDesaturated(later)
    step.icon:SetAlpha(later and 0.5 or 1)

    local wordsWidth = width - STEP_INDENT
    step.title:SetWidth(wordsWidth)
    step.title:SetText(title)
    step.title:SetTextColor(unpack(STEP_COLORS[state]))
    local height = 1 + step.title:GetStringHeight()

    step.note:SetWidth(wordsWidth)
    step.note:SetText(note)
    step.note:SetShown(note ~= "")
    if note ~= "" then
        height = height + NOTE_GAP + step.note:GetStringHeight()
    end

    if button then
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", STEP_INDENT, -(height + BUTTON_GAP))
        height = height + BUTTON_GAP + CONTINUE_HEIGHT
    end

    step:SetHeight(math.max(STEP_ICON, height))
end

-- The verdict ------------------------------------------------------------------

--- The verdict in a line of large type, after an arrow when it has one.
local function CreateHeadline(section)
    local headline = CreateFrame("Frame", nil, section)
    headline:SetHeight(HEADLINE_HEIGHT)

    headline.arrow = Kit.Icon(headline, HEADLINE_ARROW)
    headline.arrow:SetPoint("LEFT")

    headline.text = Kit.Text(headline, "GameFontNormalLarge")
    return headline
end

--- One of the figures under the verdict: a small label, the figure, and
--- under it how many fights it's the average of. Every cell but the first
--- has a rule down its left, as in the row of figures on the Fights page.
---@param index number  1 for the cell on the left
local function CreateFigure(figures, index, label)
    local left = (index - 1) * FIGURE_WIDTH
    local cell = CreateFrame("Frame", nil, figures)
    cell:SetPoint("TOPLEFT", left, 0)
    cell:SetPoint("BOTTOMLEFT", left, 0)
    cell:SetWidth(FIGURE_WIDTH)

    cell.inset = 0
    if index > 1 then
        cell.inset = FIGURE_PADDING

        local rule = Kit.Rule(cell)
        rule:SetWidth(1)
        rule:SetPoint("TOPLEFT")
        rule:SetPoint("BOTTOMLEFT")
    end

    cell.label = Kit.Text(cell, "GameFontDisableSmall")
    cell.label:SetPoint("TOPLEFT", cell.inset, -2)
    cell.label:SetText(label)

    cell.arrow = Kit.Icon(cell, FIGURE_ARROW)
    cell.arrow:SetPoint("TOPLEFT", cell.inset, -(FIGURE_VALUE_TOP + 2))
    cell.arrow:Hide()

    cell.value = Kit.Text(cell, "GameFontHighlightMedium")

    cell.count = Kit.Text(cell, "GameFontHighlightSmall")
    cell.count:SetPoint("TOPLEFT", cell.inset, -FIGURE_COUNT_TOP)
    cell.count:SetTextColor(unpack(Kit.MUTED))

    return cell
end

---@param count string  what goes under the figure; "" for nothing
---@param change number|nil  for the arrow before the figure, if it has one
local function FillFigure(cell, value, count, change)
    Kit.SetArrow(cell.arrow, change)

    -- With no arrow the figure starts where it would have been.
    local indent = cell.arrow:IsShown() and FIGURE_ARROW + FIGURE_ARROW_GAP or 0
    cell.value:ClearAllPoints()
    cell.value:SetPoint("TOPLEFT", cell.inset + indent, -FIGURE_VALUE_TOP)
    cell.value:SetText(value)
    cell.count:SetText(count)
end

--- The figures the verdict rests on, in a row, with the button that opens
--- the two sets side by side at the end of it.
local function CreateFigures(section)
    local figures = CreateFrame("Frame", nil, section)
    figures:SetHeight(FIGURES_HEIGHT)

    figures.before = CreateFigure(figures, 1, "DPS before")
    figures.after = CreateFigure(figures, 2, "DPS after")
    figures.change = CreateFigure(figures, 3, "Change")

    figures.compare = Kit.Button(figures, "Compare the two sets", 180, function()
        if selected then
            ns.ShowFights(
                Experiments.FightsOf(selected, "after"),
                Experiments.FightsOf(selected, "before")
            )
        end
    end)
    figures.compare:SetPoint("RIGHT")

    return figures
end

---@param firm boolean  true if the verdict points one way, from PointsOneWay
local function FillHeadline(headline, words, verdict, firm)
    -- Green or red and an arrow for a verdict that points one way. White
    -- for one that's sure there's no difference, and grey for one that
    -- can't tell.
    local color = WHITE
    if firm then
        color = verdict.direction == "better" and Kit.GOOD or Kit.BAD
    elseif verdict.sureness == "unsure" then
        color = Kit.MUTED
    end

    Kit.SetArrow(headline.arrow, firm and verdict.change or nil)

    -- The words start where the arrow would be when there isn't one.
    local indent = headline.arrow:IsShown() and HEADLINE_INDENT or 0
    headline.text:ClearAllPoints()
    headline.text:SetPoint("LEFT", indent, 0)
    headline.text:SetPoint("RIGHT")
    headline.text:SetText(words)
    headline.text:SetTextColor(unpack(color))
end

local function FillFigures(figures, verdict, firm)
    FillFigure(figures.before, ns.Rate(verdict.before), FightsText(verdict.fightsBefore))
    FillFigure(figures.after, ns.Rate(verdict.after), FightsText(verdict.fightsAfter))

    -- The change is held to the same rule as the headline: the percentage
    -- is always there to read, but only a firm one is coloured.
    if firm then
        FillFigure(figures.change, Kit.ChangeText(verdict.change), "", verdict.change)
    else
        local plain = Kit.Colored(PlainChangeText(verdict.change), Kit.MUTED)
        FillFigure(figures.change, plain, "")
    end
end

-- The page for one experiment -------------------------------------------------

local function CreatePage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page.pieces = {}

    -- Fixed at the top: the question, and on the same line, small and to
    -- the right, when it was started. The title is given its width when
    -- it's filled, as whatever the small print beside it leaves.
    page.title = Kit.Text(page, "GameFontNormalLarge")
    page.title:SetPoint("BOTTOMLEFT", page, "TOPLEFT", MARGIN, -TITLE_FOOT)

    -- Smaller type sits a little lower on its line, so it's raised to
    -- stand level with the title.
    page.subtitle = Kit.Text(page, "GameFontHighlightSmall", "RIGHT")
    page.subtitle:SetPoint("BOTTOMRIGHT", page, "TOPRIGHT", -SCROLL_BAR_ROOM, 1 - TITLE_FOOT)
    page.subtitle:SetTextColor(unpack(Kit.MUTED))

    -- The rest scrolls, should it ever need to. The template brings its
    -- own scroll bar, which stays out of sight while everything fits.
    page.scroll = CreateFrame("ScrollFrame", nil, page, "ScrollFrameTemplate")
    page.scroll:SetPoint("TOPLEFT", MARGIN, -HEAD_HEIGHT)
    page.scroll:SetPoint("BOTTOMRIGHT", -SCROLL_BAR_ROOM, 8)
    page.scroll.ScrollBar:SetHideIfUnscrollable(true)

    local body = CreateFrame("Frame", nil, page.scroll)
    body:SetSize(USUAL_WIDTH, 1)
    page.scroll:SetScrollChild(body)
    page.body = body

    -- A section's contents belong to the section, so they're drawn over
    -- its fill and go when it goes.
    local steps = Piece(page, Kit.Section(body, "What to do"))
    page.stepsSection = steps
    page.steps = {}
    for index = 1, 3 do
        page.steps[index] = Piece(page, CreateStep(steps))
    end

    -- The one thing the player has to click, on the step that asks for it.
    page.continue = Kit.Button(page.steps[2], "Change made: continue", 200, function()
        if selected then
            Experiments.Continue(selected)
        end
    end)
    page.continue:SetHeight(CONTINUE_HEIGHT)

    -- Under the steps while a set is being recorded: whether the window
    -- has to stay open for it.
    page.counted = Piece(page, Paragraph(steps, "GameFontHighlightSmall"))
    page.counted:SetTextColor(unpack(Kit.MUTED))

    local verdict = Piece(page, Kit.Section(body, "The verdict"))
    page.verdictSection = verdict

    -- Said in place of a verdict while there isn't one.
    page.pending = Piece(page, Paragraph(verdict, "GameFontHighlight"))
    page.pending:SetTextColor(unpack(Kit.MUTED))

    page.headline = Piece(page, CreateHeadline(verdict))
    page.detail = Piece(page, Paragraph(verdict, "GameFontHighlight"))

    page.rule = Piece(page, Kit.Rule(verdict))
    page.rule:SetHeight(1)

    page.figures = Piece(page, CreateFigures(verdict))

    return page
end

--- The question, and on the same line, small and to the right, when it
--- was started and how big its sets are.
---@param width number  of the page, which the two share
local function ShowTitle(page, experiment, width)
    page.subtitle:SetText(
        ("Started %s   %s in each set"):format(
            date("%d %b %H:%M", experiment.startedAt),
            FightsText(experiment.size)
        )
    )

    -- A long question is cut short before it runs into the small print.
    page.title:SetWidth(width - page.subtitle:GetStringWidth() - TITLE_GAP)
    page.title:SetText(Question(experiment))
end

--- The three steps, and under them, while a set is being recorded, a line
--- on whether the window has to stay open for it.
local function PlaceSteps(page, layout, experiment)
    local section = page.stepsSection
    local inside = Inside(layout, section)
    local states = STEP_STATES[experiment.state] or STEP_STATES.done

    -- The middle step makes room for its button while it's wanted. With a
    -- session in progress the second set can't begin, and the note under
    -- the step says so.
    local waiting = experiment.state == "change"
    page.continue:SetShown(waiting)
    page.continue:SetEnabled(not ns.Recorder.Open())

    local gap = 0
    for index, step in ipairs(page.steps) do
        local state = states[index]
        local button = index == 2 and waiting and page.continue or nil
        local title, note = StepTitle(experiment, index, state), StepNote(index, state)
        FillStep(step, state, title, note, inside.width, button)
        Place(inside, step, gap)
        gap = STEP_GAP
    end

    if experiment.state == "before" or experiment.state == "after" then
        local words = ns.settings.widget and COUNTED_WITH_PANEL or COUNTED_WITHOUT_PANEL
        PlaceIndented(inside, page.counted, STEP_GAP, words)
    end

    PlaceSection(layout, section, inside)
end

--- The verdict and why it can or can't be trusted, then the figures it
--- rests on. Until there are fights in both sets, a line saying so.
local function PlaceVerdict(page, layout, experiment)
    local verdict = Experiments.Verdict(experiment)
    local finished = experiment.state == "done"

    local section = page.verdictSection
    local inside = Inside(layout, section)

    -- A verdict can be given while the second set is still coming in, as
    -- long as it's labelled as one that may yet change.
    local soFar = verdict ~= nil and not finished
    section.title:SetText(soFar and "The verdict so far" or "The verdict")

    if not verdict then
        PlaceText(inside, page.pending, 0, finished and NOTHING_TO_COMPARE or NOT_YET)
        PlaceSection(layout, section, inside)
        return
    end

    local headline, detail = Experiments.InWords(verdict)
    if soFar then
        detail = detail .. " " .. MAY_CHANGE
    end

    local firm = PointsOneWay(verdict)
    FillHeadline(page.headline, headline, verdict, firm)
    Place(inside, page.headline, 0)
    PlaceText(inside, page.detail, LINE_GAP, detail)

    Place(inside, page.rule, RULE_GAP, 1)
    FillFigures(page.figures, verdict, firm)
    Place(inside, page.figures, RULE_GAP)

    PlaceSection(layout, section, inside)
end

local function FillPage(page, experiment)
    local width = WidthOf(page.scroll)
    ShowTitle(page, experiment, width)

    for _, piece in ipairs(page.pieces) do
        piece:Hide()
    end

    local layout = { frame = page.body, left = 0, width = width, y = 0 }

    PlaceSteps(page, layout, experiment)
    PlaceVerdict(page, layout, experiment)

    page.body:SetSize(width, layout.y + SECTION_GAP)

    -- Another experiment starts at the top. A redraw of the same one, as
    -- when a fight ends while the page is open, leaves the reader where
    -- they were.
    if page.shown ~= experiment then
        page.scroll:SetVerticalScroll(0)
    end
    page.shown = experiment
end

-- The form that starts one ----------------------------------------------------

--- The box for what's being tried. Its border runs the width of the
--- section once it's placed.
local function CreateQuestionBox(section)
    local box = CreateFrame("EditBox", nil, section, "InputBoxInstructionsTemplate")
    box:SetHeight(BOX_HEIGHT)
    box:SetAutoFocus(false)
    box:SetMaxLetters(ns.NOTE_LENGTH)
    box:SetScript("OnEnterPressed", StartExperiment)

    -- The template leaves room on the left for a search icon we don't have.
    box.Instructions:SetAllPoints()
    box.Instructions:SetText("For example: New bow")

    return box
end

--- The menu of how many fights go in each set, with a word on choosing
--- beside it.
local function CreateSizeRow(section)
    local row = CreateFrame("Frame", nil, section)
    row:SetHeight(SIZE_ROW)

    local menu = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    menu:SetWidth(MENU_WIDTH)
    menu:SetPoint("LEFT")
    menu:SetupMenu(function(_, root)
        local function IsChosen(size)
            return size == fightsEachWay
        end
        local function Choose(size)
            fightsEachWay = size
        end
        for _, size in ipairs(SIZES) do
            root:CreateRadio(("%d fights each"):format(size), IsChosen, Choose, size)
        end
    end)

    local hint = Kit.Text(row, "GameFontHighlightSmall")
    hint:SetPoint("LEFT", menu, "RIGHT", 14, 0)
    hint:SetTextColor(unpack(Kit.MUTED))
    hint:SetText(SIZE_HINT)

    return row
end

--- What happens next or, if it can't start, why not, after an icon.
local function CreateAdvice(section)
    local advice = CreateFrame("Frame", nil, section)

    advice.icon = Kit.Icon(advice, ADVICE_ICON)
    advice.icon:SetPoint("TOPLEFT")

    advice.text = Paragraph(advice, "GameFontHighlight")
    advice.text:SetPoint("TOPLEFT", ADVICE_INDENT, -3)

    return advice
end

local function CreateForm(parent)
    local form = CreateFrame("Frame", nil, parent)

    form.title = Kit.Text(form, "GameFontNormalLarge")
    form.title:SetPoint("BOTTOMLEFT", form, "TOPLEFT", MARGIN, -TITLE_FOOT)
    form.title:SetText("New experiment")

    -- The sections stand where the page's do. The form is short enough
    -- not to need scrolling, so it doesn't.
    local body = CreateFrame("Frame", nil, form)
    body:SetPoint("TOPLEFT", MARGIN, -HEAD_HEIGHT)
    body:SetPoint("BOTTOMRIGHT", -SCROLL_BAR_ROOM, 8)
    form.body = body

    form.ideaSection = Kit.Section(body, "How it works")
    form.idea = Paragraph(form.ideaSection, "GameFontHighlight")

    form.questionSection = Kit.Section(body, "What are you trying?")
    form.question = CreateQuestionBox(form.questionSection)

    form.sizeSection = Kit.Section(body, "How many fights in each set?")
    form.sizeRow = CreateSizeRow(form.sizeSection)

    form.startSection = Kit.Section(body, "What happens next")
    form.advice = CreateAdvice(form.startSection)
    form.start = Kit.Button(form.startSection, "Start the experiment", 180, StartExperiment)

    return form
end

local function PlaceIdea(form, layout)
    local inside = Inside(layout, form.ideaSection)
    PlaceText(inside, form.idea, 0, IDEA)
    PlaceSection(layout, form.ideaSection, inside)
end

local function PlaceQuestion(form, layout)
    local inside = Inside(layout, form.questionSection)

    -- The box's border is drawn a little outside it, hence the nudge right.
    form.question:SetWidth(inside.width - BOX_NUDGE)
    PlaceFixed(inside, form.question, 0, BOX_NUDGE)

    PlaceSection(layout, form.questionSection, inside)
end

local function PlaceSize(form, layout)
    local inside = Inside(layout, form.sizeSection)
    Place(inside, form.sizeRow, 0)
    PlaceSection(layout, form.sizeSection, inside)
end

--- The advice, and under it the button.
---@param reason string|nil  why it can't start, from WhyNotStart
local function PlaceStart(form, layout, reason)
    local inside = Inside(layout, form.startSection)

    local advice = form.advice
    Kit.SetIcon(advice.icon, reason and "warning" or "tip")
    advice.text:SetWidth(inside.width - ADVICE_INDENT)
    advice.text:SetText(reason or READY)
    advice:SetHeight(math.max(ADVICE_ICON, advice.text:GetStringHeight() + 3))
    Place(inside, advice, 0)

    form.start:SetEnabled(reason == nil)
    PlaceFixed(inside, form.start, BUTTON_GAP)

    PlaceSection(layout, form.startSection, inside)
end

local function FillForm(form)
    local layout = { frame = form.body, left = 0, width = WidthOf(form.body), y = 0 }

    PlaceIdea(form, layout)
    PlaceQuestion(form, layout)
    PlaceSize(form, layout)
    PlaceStart(form, layout, WhyNotStart())
end

-- The tab ---------------------------------------------------------------------

--- Builds the tab.
---@param parent table  the window's inset, which the tab fills
---@param window table  the window itself, whose bottom edge the buttons sit on
function ExperimentsTab.Create(parent, window)
    tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()

    -- Coming back to the tab, the experiment in progress is what's wanted,
    -- not a form that was left open the last time.
    tab:SetScript("OnShow", function()
        composing = false
    end)

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
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

    local view = CreateScrollBoxListLinearView()
    -- Rows are plain buttons rather than an XML template, so the list has
    -- to be told how tall they are.
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, data)
        if not row.created then
            CreateRowWidgets(row)
        end
        FillRow(row, data)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    tab.scrollBox = scrollBox

    tab.none = Paragraph(tab, "GameFontHighlight", "CENTER")
    tab.none:SetPoint("TOP", scrollBox, "TOP", 0, -24)
    tab.none:SetWidth(LIST_WIDTH - 20)
    tab.none:SetTextColor(unpack(Kit.MUTED))
    tab.none:SetText(NONE)

    -- Right: the page and the form share the space, one showing at a time.
    -- They stand where the Fights tab's page does.
    tab.page = CreatePage(tab)
    tab.form = CreateForm(tab)
    for _, side in ipairs({ tab.page, tab.form }) do
        side:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, -4)
        side:SetPoint("BOTTOMRIGHT", -4, 4)
    end

    -- Along the bottom of the window, where the Fights tab keeps its
    -- buttons too: the one that begins something on the left, with how
    -- the list works a mouse-over away beside it, and the one that acts
    -- on what's selected on the right.
    tab.new = Kit.Button(tab, "New experiment", 140, function()
        selected = nil
        composing = true
        Refresh()

        -- Ready to type, unless the form is saying it can't start one.
        if tab.form.start:IsEnabled() then
            tab.form.question:SetFocus()
        end
    end)
    tab.new:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 8, 4)

    local help = Kit.HelpButton(tab, "Experiments", HELP)
    help:SetPoint("LEFT", tab.new, "RIGHT", 8, 0)

    tab.delete = Kit.Button(tab, "Delete this experiment", 180, function()
        if selected then
            ConfirmDelete(selected)
        end
    end)
    tab.delete:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -8, 4)

    tab.Refresh = Refresh
    return tab
end

function Refresh()
    if not tab or not tab:IsVisible() then
        return
    end

    local experiments = ns.character.experiments

    -- The selected one may have been deleted since the last time round.
    if selected and not StillKept(selected) then
        selected = nil
    end

    -- With no experiments there's nothing to show but the form. Otherwise,
    -- with nothing chosen, show the one in progress, or failing that the
    -- latest.
    local showForm = composing or #experiments == 0
    if not showForm and not selected then
        selected = Experiments.Running() or experiments[#experiments]
    end

    tab.scrollBox:SetDataProvider(
        CreateDataProvider(BuildRows()),
        ScrollBoxConstants.RetainScrollPosition
    )
    tab.none:SetShown(#experiments == 0)

    tab.form:SetShown(showForm)
    tab.page:SetShown(not showForm)
    tab.delete:SetShown(not showForm)

    if showForm then
        FillForm(tab.form)
    else
        FillPage(tab.page, selected)
    end
end
