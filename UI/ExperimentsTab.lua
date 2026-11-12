local _, ns = ...

-- The Experiments tab: every experiment down the left, and on the right
-- either the page for the selected one or the form that starts a new one.
--
-- An experiment is a short task with someone to guide you through it, so
-- its page is a checklist of three steps rather than a table of figures:
-- fight a few as you are, make your change, fight the same number again.
-- The step the player is on is marked, and the one button they have to
-- press sits on the step that needs it. The verdict appears underneath as
-- soon as there's anything to say.
--
-- All the reckoning is in Record\Experiments.lua. This file only draws it.

local ExperimentsTab = {}
ns.ExperimentsTab = ExperimentsTab

local Kit = ns.Kit
local Experiments = ns.Experiments

local LIST_WIDTH = 270
local ROW_HEIGHT = 40
local HELP_HEIGHT = 76
local STEP_HEIGHT = 42
local CONTINUE_HEIGHT = 28
local QUESTION_WIDTH = 320

-- How many fights each way the form offers.
local SIZES = { 3, 5, 8 }

local WHITE = { 1, 1, 1 }

local HELP = "Click an experiment to read it. Right-click to delete it.\n"
    .. "These are yours alone. Nothing here is shared or posted."

local IDEA = "One fight can't tell you whether a new weapon or a different build is better, "
    .. "because no two fights go the same way. An experiment can. It records a few fights "
    .. "as you are, waits while you make your change, then records the same number again "
    .. "and tells you what the difference was and how far to trust it."

local IDEA_IN_SHORT = "An experiment records a few fights before a change and the same "
    .. "number after it, then tells you what difference the change made."

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

-- The form's choice of how many fights each way, kept between experiments.
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
--- an arrow. One that's too close to call gets neither, so that a green
--- arrow always means something.
local function PointsOneWay(verdict)
    return verdict.direction ~= "same" and verdict.sureness ~= "unsure"
end

--- Where an experiment stands, in a few words, for its row in the list.
---@return string text
---@return number|nil change  for the arrow, when the verdict points one way
local function Standing(experiment)
    local state = experiment.state
    if state == "change" then
        return Kit.Colored("Waiting for your change", Kit.GOLD)
    elseif state == "before" or state == "after" then
        -- While a set is being recorded, the state is the name of its side.
        return ("Recording the %s set: %d of %d"):format(
            state == "before" and "first" or "second",
            #Experiments.FightsOf(experiment, state),
            experiment.size
        )
    end

    local verdict = Experiments.Verdict(experiment)
    if not verdict then
        return Kit.Colored("Nothing to compare", Kit.MUTED)
    elseif verdict.direction == "same" then
        return Kit.Colored("No real difference", Kit.MUTED)
    elseif not PointsOneWay(verdict) then
        return "Too close to call  " .. Kit.ChangeText(verdict.change)
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
        return "A recording is in progress. Stop it first with the Stop recording button "
            .. "on the Fights tab."
    end
end

--- The line under a step: how far along it is, or what to do about it.
---@param index number  1, 2 or 3
---@param state string  a value from STEP_STATES
local function StepNote(experiment, index, state)
    if state == "later" then
        return ""
    end

    if index == 2 then
        if state == "done" then
            return Kit.Colored("Done.", Kit.MUTED)
        elseif ns.Recorder.Open() then
            return "A recording is in progress. Stop it on the Fights tab, then come back."
        end
        return "Swap the gear, change the build, whatever you're testing. Then press the button."
    end

    local fought = #Experiments.FightsOf(experiment, index == 1 and "before" or "after")
    if state == "recording" then
        return ("%s  Fights are counted automatically, so you can close this window."):format(
            Kit.Colored(("%d of %d fought."):format(fought, experiment.size), Kit.GOLD)
        )
    end
    return Kit.Colored(FightsText(fought) .. " recorded.", Kit.MUTED)
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

    row.fill = row:CreateTexture(nil, "BACKGROUND")
    row.fill:SetAllPoints()

    -- A gold stripe down the left edge of the selected one, as on the
    -- Fights tab.
    row.stripe = row:CreateTexture(nil, "BORDER")
    row.stripe:SetPoint("TOPLEFT")
    row.stripe:SetPoint("BOTTOMLEFT")
    row.stripe:SetWidth(3)
    row.stripe:SetColorTexture(Kit.GOLD[1], Kit.GOLD[2], Kit.GOLD[3], 1)

    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.06)

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

    local isSelected = experiment == selected
    row.stripe:SetShown(isSelected)
    if isSelected then
        row.fill:SetColorTexture(Kit.GOLD[1], Kit.GOLD[2], Kit.GOLD[3], 0.14)
    else
        row.fill:SetColorTexture(0, 0, 0, 0)
    end
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
--- right edges so it knows where to wrap.
local function Paragraph(parent, font)
    local text = Kit.Text(parent, font)
    text:SetWordWrap(true)
    text:SetJustifyV("TOP")
    text:SetSpacing(3)
    return text
end

--- Puts a region under another, the same width.
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

    -- The one thing the player has to press, on the step that asks for it.
    page.continue = Kit.Button(
        page.steps[2],
        "I've made my change: start the second set",
        340,
        function()
            if selected then
                Experiments.Continue(selected)
            end
        end
    )
    page.continue:SetHeight(CONTINUE_HEIGHT)
    page.continue:SetPoint("BOTTOMLEFT", 26, 6)

    page.verdictHeader = Kit.Header(page, "The verdict")
    PlaceBelow(page.verdictHeader, page.steps[3], 12)

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

    local figuresHeader = Kit.Header(verdict, "Damage a second")
    PlaceBelow(figuresHeader, verdict.detail, 14)

    verdict.before = Kit.Tile(verdict)
    verdict.before:SetPoint("TOPLEFT", figuresHeader, "BOTTOMLEFT", 0, -8)
    verdict.before:SetWidth(170)

    verdict.after = Kit.Tile(verdict)
    verdict.after:SetPoint("TOPLEFT", verdict.before, "TOPRIGHT", 20, 0)
    verdict.after:SetWidth(170)

    verdict.compare = Kit.Button(verdict, "See the fights side by side", 220, function()
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
            finished and "There aren't fights on both sides, so there's nothing to compare."
                or "It will appear here once you've fought on both sides of your change."
        )
        return
    end

    local widgets = page.verdict
    local headline, detail = Experiments.InWords(verdict)
    if soFar then
        detail = detail .. " The second set is still being recorded, so this may change."
    end

    local firm = PointsOneWay(verdict)
    local color = WHITE
    if firm then
        color = verdict.direction == "better" and Kit.GOOD or Kit.BAD
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

    widgets.before:Set(
        ("Before (%s)"):format(FightsText(verdict.fightsBefore)),
        ns.Rate(verdict.before)
    )
    widgets.after:Set(
        ("After (%s)"):format(FightsText(verdict.fightsAfter)),
        ns.Rate(verdict.after),
        Kit.ChangeText(verdict.change),
        verdict.change
    )
end

local function FillPage(page, experiment)
    page.title:SetText(Question(experiment))
    page.subtitle:SetText(
        ("Started %s   %s each way"):format(
            date("%d %b %H:%M", experiment.startedAt),
            FightsText(experiment.size)
        )
    )

    local titles = {
        ("1.  Fight %d enemies as you are now."):format(experiment.size),
        "2.  Make your change.",
        ("3.  Fight %d more."):format(experiment.size),
    }
    local states = STEP_STATES[experiment.state] or STEP_STATES.done
    for index, step in ipairs(page.steps) do
        FillStep(step, states[index], titles[index], StepNote(experiment, index, states[index]))
    end

    -- The middle step grows to make room for its button while it's wanted.
    -- With a recording open the second set can't begin, and the note under
    -- the step says so.
    local waiting = experiment.state == "change"
    page.steps[2]:SetHeight(waiting and STEP_HEIGHT + CONTINUE_HEIGHT + 8 or STEP_HEIGHT)
    page.continue:SetShown(waiting)
    page.continue:SetEnabled(not ns.Recorder.Open())

    FillVerdict(page, experiment)
end

-- The form that starts one ----------------------------------------------------

local function CreateForm(parent)
    local form = CreateFrame("Frame", nil, parent)

    form.title = Kit.Text(form, "GameFontNormalLarge")
    form.title:SetPoint("TOPLEFT", 14, -8)
    form.title:SetPoint("TOPRIGHT", -14, -8)
    form.title:SetText("New experiment")

    form.idea = Paragraph(form, "GameFontHighlight")
    PlaceBelow(form.idea, form.title, 10)

    local questionLabel = Kit.Text(form, "GameFontNormal")
    questionLabel:SetText("What are you trying?")
    PlaceBelow(questionLabel, form.idea, 24)

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
    sizeLabel:SetText("How many fights each way?")
    sizeLabel:SetPoint("TOPLEFT", form.question, "BOTTOMLEFT", -6, -20)

    form.size = CreateFrame("DropdownButton", nil, form, "WowStyle1DropdownTemplate")
    form.size:SetWidth(120)
    form.size:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -6)
    form.size:SetupMenu(function(_, root)
        local function IsChosen(size)
            return size == fightsEachWay
        end
        local function Choose(size)
            fightsEachWay = size
        end
        for _, size in ipairs(SIZES) do
            root:CreateRadio(FightsText(size), IsChosen, Choose, size)
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

---@param first boolean  true when there are no experiments yet
local function FillForm(form, first)
    form.idea:SetText(first and IDEA or IDEA_IN_SHORT)

    local reason = WhyNotStart()
    form.start:SetEnabled(reason == nil)

    Kit.SetIcon(form.adviceIcon, reason and "warning" or "tip")
    form.advice:SetText(
        reason or "Recording starts straight away. Your next fights are the first set."
    )
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

    tab.none = Kit.Text(tab, "GameFontHighlight", "CENTER")
    tab.none:SetPoint("TOP", scrollBox, "TOP", 0, -24)
    tab.none:SetWidth(LIST_WIDTH - 20)
    tab.none:SetTextColor(unpack(Kit.MUTED))
    tab.none:SetText("No experiments yet.")

    local help = Paragraph(tab, "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", scrollBox, "BOTTOMLEFT", 4, -8)
    help:SetWidth(LIST_WIDTH)
    help:SetTextColor(unpack(Kit.MUTED))
    help:SetText(HELP)

    -- Right: the page and the form share the space, one showing at a time.
    tab.page = CreatePage(tab)
    tab.form = CreateForm(tab)
    for _, side in ipairs({ tab.page, tab.form }) do
        side:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 24, 0)
        side:SetPoint("BOTTOMRIGHT", -4, 4)
    end

    -- Along the bottom of the window, where the Fights tab keeps its
    -- buttons too: the one that begins something on the left, the one that
    -- acts on what's selected on the right.
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
        FillForm(tab.form, #experiments == 0)
    else
        FillPage(tab.page, selected)
    end
end
