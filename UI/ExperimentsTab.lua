local _, ns = ...

-- The Experiments tab: every experiment down the left, and on the right
-- either the page for the selected one or the form that starts a new one.
--
-- An experiment is a short task with someone to guide you through it, so
-- its page is a checklist of three steps rather than a table of figures:
-- win a few fights as you are, make your change, win the same number
-- again. The step the player is on is marked, and the one button they
-- have to click sits on the step that needs it. The verdict appears
-- underneath as soon as there's anything to say, and is only given a
-- colour and an arrow when it's sure enough of itself to deserve them.
--
-- All the reckoning is in Record\Experiments.lua. This file only draws it.

local ExperimentsTab = {}
ns.ExperimentsTab = ExperimentsTab

local Kit = ns.Kit
local Experiments = ns.Experiments

-- The list sits in a sunken panel with its scroll bar, laid out as on the
-- Fights tab so the two don't jump when switching between them. The panel
-- shares the window's own edge on three sides, so only its right-hand
-- edge is new: a line between the list and the page.
local LIST_WIDTH = 270
local LIST_EDGE = 4
local PANEL_WIDTH = 292
local ROW_HEIGHT = 40

local STEP_HEIGHT = 42
local CONTINUE_HEIGHT = 28
local QUESTION_WIDTH = 320
local TILE_WIDTH = 170

-- The verdict's heading sits this far under the steps, and further when
-- the line about fights being counted is showing between them.
local VERDICT_GAP = 12
local COUNTED_ROOM = 20

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

local FAIRER = "The same kind of enemy each time makes it fairer."

-- Said under the steps while a set is being recorded. With the panel
-- switched off nothing on screen says when the set is finished, so the
-- player is told to look here for it.
local COUNTED_WITH_PANEL = "You can close this window: fights are counted as you win them, "
    .. "and the panel keeps count."
local COUNTED_WITHOUT_PANEL = "Fights are counted as you win them. Check back here to see "
    .. "when the set is done."

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

-- Pieces of the right-hand side ----------------------------------------------

--- Text that runs on to as many lines as it needs. Anchor its left and
--- right edges, or give it a width, so it knows where to wrap.
local function Paragraph(parent, font, justify)
    local text = Kit.Text(parent, font, justify)
    text:SetWordWrap(true)
    text:SetJustifyV("TOP")
    text:SetSpacing(3)
    return text
end

--- Puts a region under another, the same width. Doing it again moves it.
local function PlaceBelow(region, above, gap)
    region:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)
    region:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -gap)
end

--- One line of the checklist: an icon for how far along it is, what to
--- do, and a note underneath.
local function CreateStep(parent)
    local step = CreateFrame("Frame", nil, parent)
    step:SetHeight(STEP_HEIGHT)

    step.icon = Kit.Icon(step, 16)
    step.icon:SetPoint("TOPLEFT", 0, -3)

    step.title = Kit.Text(step, "GameFontHighlight")
    step.title:SetPoint("TOPLEFT", 26, -4)
    step.title:SetPoint("TOPRIGHT", 0, -4)

    step.note = Kit.Text(step, "GameFontHighlightSmall")
    PlaceBelow(step.note, step.title, 4)

    return step
end

local function FillStep(step, state, title, note)
    Kit.SetIcon(step.icon, STEP_ICONS[state])

    -- A step that hasn't been reached is greyed out rather than hidden, so
    -- the whole task can be seen from the start.
    local later = state == "later"
    step.icon:SetDesaturated(later)
    step.icon:SetAlpha(later and 0.5 or 1)

    step.title:SetText(title)
    step.title:SetTextColor(unpack(STEP_COLORS[state]))
    step.note:SetText(note)
end

--- One set's DPS in large type, with the number of fights it's the
--- average of underneath, where the kit's tile would put a change.
local function CreateSetTile(parent)
    local tile = Kit.Tile(parent)
    tile:SetWidth(TILE_WIDTH)

    tile.count = Kit.Text(tile, "GameFontHighlightSmall")
    tile.count:SetPoint("TOPLEFT", tile.value, "BOTTOMLEFT", 0, -3)
    tile.count:SetTextColor(unpack(Kit.MUTED))

    return tile
end

-- The page for one experiment -------------------------------------------------

local function CreatePage(parent)
    local page = CreateFrame("Frame", nil, parent)

    page.title = Kit.Text(page, "GameFontNormalLarge")
    page.title:SetPoint("TOPLEFT", 14, -8)
    page.title:SetPoint("TOPRIGHT", -14, -8)

    page.subtitle = Kit.Text(page, "GameFontHighlightSmall")
    page.subtitle:SetTextColor(unpack(Kit.MUTED))
    PlaceBelow(page.subtitle, page.title, 3)

    local stepsHeader = Kit.Header(page, "What to do")
    PlaceBelow(stepsHeader, page.subtitle, 14)

    page.steps = {}
    for index = 1, 3 do
        local step = CreateStep(page)
        if index == 1 then
            PlaceBelow(step, stepsHeader, 6)
        else
            PlaceBelow(step, page.steps[index - 1], 0)
        end
        page.steps[index] = step
    end

    -- The one thing the player has to click, on the step that asks for it.
    page.continue = Kit.Button(page.steps[2], "Change made: continue", 200, function()
        if selected then
            Experiments.Continue(selected)
        end
    end)
    page.continue:SetHeight(CONTINUE_HEIGHT)
    page.continue:SetPoint("BOTTOMLEFT", 26, 6)

    -- Under the steps while a set is being recorded: whether the window
    -- has to stay open for it. In line with the words of the steps.
    page.counted = Kit.Text(page, "GameFontHighlightSmall")
    page.counted:SetPoint("TOPLEFT", page.steps[3], "BOTTOMLEFT", 26, -2)
    page.counted:SetPoint("RIGHT", page.steps[3], "RIGHT")
    page.counted:SetTextColor(unpack(Kit.MUTED))

    -- FillPage moves this down out of that line's way when it's showing.
    page.verdictHeader = Kit.Header(page, "The verdict")
    PlaceBelow(page.verdictHeader, page.steps[3], VERDICT_GAP)

    -- Said in place of a verdict while there isn't one.
    page.pending = Paragraph(page, "GameFontHighlight")
    page.pending:SetTextColor(unpack(Kit.MUTED))
    PlaceBelow(page.pending, page.verdictHeader, 8)

    -- Everything that belongs to a verdict, to show and hide as one.
    local verdict = CreateFrame("Frame", nil, page)
    verdict:SetPoint("TOPLEFT", page.verdictHeader, "BOTTOMLEFT")
    verdict:SetPoint("BOTTOMRIGHT", -14, 8)
    page.verdict = verdict

    verdict.arrow = Kit.Icon(verdict, 18)
    verdict.arrow:SetPoint("TOPLEFT", 0, -10)

    verdict.headline = Kit.Text(verdict, "GameFontNormalHuge")

    verdict.detail = Paragraph(verdict, "GameFontHighlight")
    verdict.detail:SetPoint("TOPLEFT", 0, -38)
    verdict.detail:SetPoint("TOPRIGHT", 0, -38)

    local figuresHeader = Kit.Header(verdict, "DPS")
    PlaceBelow(figuresHeader, verdict.detail, 14)

    verdict.before = CreateSetTile(verdict)
    verdict.before:SetPoint("TOPLEFT", figuresHeader, "BOTTOMLEFT", 0, -8)

    verdict.after = CreateSetTile(verdict)
    verdict.after:SetPoint("TOPLEFT", verdict.before, "TOPRIGHT", 20, 0)

    -- The change stands beside the figure it brought about. FillVerdict
    -- places the words, which move up when there's no arrow.
    verdict.changeArrow = Kit.Icon(verdict, 12)
    verdict.changeArrow:SetPoint("LEFT", verdict.after.value, "RIGHT", 10, 0)

    verdict.change = Kit.Text(verdict, "GameFontHighlight")

    verdict.compare = Kit.Button(verdict, "Compare the two sets", 180, function()
        if selected then
            ns.ShowFights(
                Experiments.FightsOf(selected, "after"),
                Experiments.FightsOf(selected, "before")
            )
        end
    end)
    verdict.compare:SetPoint("TOPLEFT", verdict.before, "BOTTOMLEFT", 0, -12)

    return page
end

local function FillVerdict(page, experiment)
    local verdict = Experiments.Verdict(experiment)
    local finished = experiment.state == "done"

    -- A verdict can be given while the second set is still coming in, as
    -- long as it's labelled as one that may yet change.
    local soFar = verdict ~= nil and not finished
    page.verdictHeader.title:SetText(soFar and "The verdict so far" or "The verdict")
    page.verdict:SetShown(verdict ~= nil)
    page.pending:SetShown(verdict == nil)

    if not verdict then
        page.pending:SetText(
            finished and "There aren't fights in both sets, so there's nothing to compare."
                or "It will appear here once there are fights in both sets."
        )
        return
    end

    local widgets = page.verdict
    local headline, detail = Experiments.InWords(verdict)
    if soFar then
        detail = detail .. " The second set is still being recorded, so this may change."
    end

    -- Green or red and an arrow for a verdict that points one way. White
    -- for one that's sure there's no difference, and grey for one that
    -- can't tell.
    local firm = PointsOneWay(verdict)
    local color = WHITE
    if firm then
        color = verdict.direction == "better" and Kit.GOOD or Kit.BAD
    elseif verdict.sureness == "unsure" then
        color = Kit.MUTED
    end

    Kit.SetArrow(widgets.arrow, firm and verdict.change or nil)

    -- The headline starts where the arrow would be when there isn't one.
    local indent = widgets.arrow:IsShown() and 24 or 0
    widgets.headline:ClearAllPoints()
    widgets.headline:SetPoint("TOPLEFT", indent, -9)
    widgets.headline:SetPoint("TOPRIGHT", 0, -9)
    widgets.headline:SetText(headline)
    widgets.headline:SetTextColor(unpack(color))
    widgets.detail:SetText(detail)

    widgets.before:Set("Before", ns.Rate(verdict.before))
    widgets.before.count:SetText(FightsText(verdict.fightsBefore))
    widgets.after:Set("After", ns.Rate(verdict.after))
    widgets.after.count:SetText(FightsText(verdict.fightsAfter))

    -- The change is held to the same rule as the headline: the percentage
    -- is always there to read, but only a firm one is coloured.
    Kit.SetArrow(widgets.changeArrow, firm and verdict.change or nil)
    widgets.change:ClearAllPoints()
    if widgets.changeArrow:IsShown() then
        widgets.change:SetPoint("LEFT", widgets.changeArrow, "RIGHT", 3, 0)
    else
        widgets.change:SetPoint("LEFT", widgets.after.value, "RIGHT", 10, 0)
    end
    widgets.change:SetText(
        firm and Kit.ChangeText(verdict.change)
            or Kit.Colored(PlainChangeText(verdict.change), Kit.MUTED)
    )
end

local function FillPage(page, experiment)
    page.title:SetText(Question(experiment))
    page.subtitle:SetText(
        ("Started %s   %s in each set"):format(
            date("%d %b %H:%M", experiment.startedAt),
            FightsText(experiment.size)
        )
    )

    local states = STEP_STATES[experiment.state] or STEP_STATES.done
    for index, step in ipairs(page.steps) do
        local state = states[index]
        FillStep(step, state, StepTitle(experiment, index, state), StepNote(index, state))
    end

    -- The middle step grows to make room for its button while it's wanted.
    -- With a session in progress the second set can't begin, and the note
    -- under the step says so.
    local waiting = experiment.state == "change"
    page.steps[2]:SetHeight(waiting and STEP_HEIGHT + CONTINUE_HEIGHT + 8 or STEP_HEIGHT)
    page.continue:SetShown(waiting)
    page.continue:SetEnabled(not ns.Recorder.Open())

    local recording = experiment.state == "before" or experiment.state == "after"
    page.counted:SetShown(recording)
    page.counted:SetText(ns.settings.widget and COUNTED_WITH_PANEL or COUNTED_WITHOUT_PANEL)
    PlaceBelow(
        page.verdictHeader,
        page.steps[3],
        recording and VERDICT_GAP + COUNTED_ROOM or VERDICT_GAP
    )

    FillVerdict(page, experiment)
end

-- The form that starts one ----------------------------------------------------

local function CreateForm(parent)
    local form = CreateFrame("Frame", nil, parent)

    form.title = Kit.Text(form, "GameFontNormalLarge")
    form.title:SetPoint("TOPLEFT", 14, -8)
    form.title:SetPoint("TOPRIGHT", -14, -8)
    form.title:SetText("New experiment")

    local idea = Paragraph(form, "GameFontHighlight")
    PlaceBelow(idea, form.title, 10)
    idea:SetText(IDEA)

    local questionLabel = Kit.Text(form, "GameFontNormal")
    questionLabel:SetText("What are you trying?")
    PlaceBelow(questionLabel, idea, 24)

    -- The box's border is drawn a little outside it, hence the nudge right.
    form.question = CreateFrame("EditBox", nil, form, "InputBoxInstructionsTemplate")
    form.question:SetSize(QUESTION_WIDTH, 22)
    form.question:SetPoint("TOPLEFT", questionLabel, "BOTTOMLEFT", 6, -6)
    form.question:SetAutoFocus(false)
    form.question:SetMaxLetters(ns.NOTE_LENGTH)
    form.question:SetScript("OnEnterPressed", StartExperiment)

    -- The template leaves room on the left for a search icon we don't have.
    form.question.Instructions:SetAllPoints()
    form.question.Instructions:SetText("For example: New bow")

    local sizeLabel = Kit.Text(form, "GameFontNormal")
    sizeLabel:SetText("How many fights in each set?")
    sizeLabel:SetPoint("TOPLEFT", form.question, "BOTTOMLEFT", -6, -20)

    form.size = CreateFrame("DropdownButton", nil, form, "WowStyle1DropdownTemplate")
    form.size:SetWidth(140)
    form.size:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -6)
    form.size:SetupMenu(function(_, root)
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

    local sizeHint = Kit.Text(form, "GameFontHighlightSmall")
    sizeHint:SetPoint("LEFT", form.size, "RIGHT", 14, 0)
    sizeHint:SetTextColor(unpack(Kit.MUTED))
    sizeHint:SetText("More fights take longer and give a surer answer.")

    -- The button and the line under it share a strip that runs to the
    -- right edge of the form, which gives the line somewhere to wrap.
    local strip = CreateFrame("Frame", nil, form)
    strip:SetPoint("TOPLEFT", form.size, "BOTTOMLEFT", 0, -26)
    strip:SetPoint("BOTTOMRIGHT", -14, 8)

    form.start = Kit.Button(strip, "Start the experiment", 180, StartExperiment)
    form.start:SetPoint("TOPLEFT")

    -- Under the button: what happens next or, if it can't start, why not.
    form.adviceIcon = Kit.Icon(strip, 20)
    form.adviceIcon:SetPoint("TOPLEFT", 0, -34)

    form.advice = Paragraph(strip, "GameFontHighlight")
    form.advice:SetPoint("TOPLEFT", 28, -37)
    form.advice:SetPoint("TOPRIGHT", 0, -37)

    return form
end

local function FillForm(form)
    local reason = WhyNotStart()
    form.start:SetEnabled(reason == nil)

    Kit.SetIcon(form.adviceIcon, reason and "warning" or "tip")
    form.advice:SetText(reason or "It starts straight away. Your next fights are the first set.")
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
    tab.page = CreatePage(tab)
    tab.form = CreateForm(tab)
    for _, side in ipairs({ tab.page, tab.form }) do
        side:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, -6)
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
