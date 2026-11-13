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
--
-- The search box over the list narrows it to the fights against an enemy
-- by that name. It only hides rows: whatever was selected stays selected,
-- and a run of fights with Shift held is a run of the rows on show.

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

-- Down the top of the panel: a gap, the search box, a gap and a rule, and
-- then the list. The box's border is drawn a little to the left of the
-- box itself, so the box starts that much further in to line its border
-- up with the rows.
local SEARCH_TOP = 6
local SEARCH_HEIGHT = 20
local SEARCH_GAP = 6
local SEARCH_BORDER = 5
local SEARCH_LETTERS = 40
local LIST_TOP = SEARCH_TOP + SEARCH_HEIGHT + SEARCH_GAP + 1
local SEARCH_PROMPT = "Search by enemy"
local NO_MATCH = "No fights match your search."

-- Inside a fight's row: where its name starts, how far in from the right
-- edge the length stops, and the small things beside the name.
local ROW_LEFT = 10
local ROW_RIGHT = 6
local BESIDE_NAME = 4
local MARK_SIZE = 14
local BEST_SIZE = 12

-- The game's own marks for an elite, a rare and a boss: the gold dragon
-- and the star its nameplates and damage meter show beside a creature's
-- name, and the skull its target frame and character sheet show for one
-- too strong to read. Found in the Forever client's nameplate, damage
-- meter and character sheet code.
local MARKS = {
    elite = { atlas = "nameplates-icon-elite-gold" },
    rare = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star" },
    boss = { file = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
}

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
    "Type in the box over the list to find the fights against an enemy.",
}

local tab

-- The fights being read, and the fights they're compared with: sets of
-- fights, the second nil when nothing is being compared. While `picking`,
-- clicks in the list choose the second set instead of the first.
local chosen = {}
local other
local picking = false

-- Every fight, newest first; the ones the list shows, in the same order;
-- and the last one clicked, for Shift-click to run from. The two lists are
-- the same unless something is typed in the search box.
local everyFight = {}
local order = {}
local lastClicked

-- What the search box holds, in lower case, or nil when it's empty.
local searchFor

local Refresh

-- Sets of fights -------------------------------------------------------------

local function Count(set)
    local count = 0
    for _ in pairs(set or {}) do
        count = count + 1
    end
    return count
end

--- The fights of a set as a list, newest first. Fights the search is
--- hiding are still in it.
local function ListOf(set)
    local list = {}
    for _, fight in ipairs(everyFight) do
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

--- Where a fight sits in the list as it's shown, or nil if it isn't.
local function PlaceOf(wanted)
    for place, fight in ipairs(order) do
        if fight == wanted then
            return place
        end
    end
end

--- Drops fights that have since been deleted from a set.
local function Prune(set)
    local kept = SetOf(everyFight)
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

--- What to call a fight and what to show beside its name (see Foes.lua).
--- A file that's new to an addon is only picked up when the game is
--- restarted, so until then a fight goes by what was targeted.
local function Describe(fight)
    if ns.Foes then
        return ns.Foes.Describe(fight)
    end
    return {
        title = fight.target or "Fight",
        level = fight.enemyLevel and tostring(fight.enemyLevel) or nil,
        group = false,
    }
end

--- A fight's figures, the one that matters most first: its damage per
--- second, then the rest set back.
local function FiguresText(fight)
    local dps = ns.Rate(fight.damage / fight.length) .. " DPS"
    local rest = ns.Number(fight.damage) .. " dmg"
    if fight.hits and fight.hits > 0 then
        rest = rest .. "   " .. ns.Percent(fight.crits / fight.hits) .. " crit"
    end

    -- A fight left out of the bests is set back altogether.
    if fight.ignored then
        return Kit.Colored(dps .. "   " .. rest, Kit.MUTED)
    end
    return dps .. "   " .. Kit.Colored(rest, Kit.MUTED)
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
    if #everyFight == 0 then
        heading.empty = NO_FIGHTS
    end
    if #fights == 0 then
        return heading
    end

    local newest, oldest = fights[1], fights[#fights]

    if #fights == 1 then
        heading.title = Describe(newest).title
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

-- Searching --------------------------------------------------------------------

--- True if a name has the search in it, whatever its case.
local function Contains(name)
    return type(name) == "string" and name:lower():find(searchFor, 1, true) ~= nil
end

--- True if the list should show a fight: when nothing is being searched
--- for, or when what it's called or any enemy in it has the search in its
--- name. Older fights have no list of enemies, but the game's own tally
--- of whom the player hurt is kept with every fight.
local function Matches(fight, described)
    if not searchFor then
        return true
    end
    if Contains(described.title) or Contains(fight.target) then
        return true
    end
    for _, foe in ipairs(fight.foes or {}) do
        if Contains(foe.name) then
            return true
        end
    end
    for _, enemy in ipairs(fight.enemies or {}) do
        if Contains(enemy.name) then
            return true
        end
    end
    return false
end

-- The list ---------------------------------------------------------------------

local function ShowFightMenu(row, fight)
    MenuUtil.CreateContextMenu(row, function(_, root)
        -- Acting on the whole selection when the fight is part of it, and
        -- on the one fight otherwise, is what people expect of a list.
        local target = chosen[fight] and chosen or { [fight] = true }
        local count = Count(target)
        local one = count == 1

        root:CreateTitle(one and Describe(fight).title or FightsText(count))

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

--- The fights a session's heading stands for: those of the session the
--- list is showing. With a search on, that may be only some of them, and
--- the heading's menu then acts on those alone, so that deleting from it
--- never takes fights the player can't see.
local function FightsUnder(data)
    return data.shown or ns.Recorder.FightsOf(data.recording)
end

local function ShowSessionMenu(row, data)
    local session = data.recording
    local fights = FightsUnder(data)
    local whole = #fights == #ns.Recorder.FightsOf(session)

    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle("Session " .. session.number)

        local compare = whole and "Compare with this session"
            or ("Compare with these %d fights"):format(#fights)
        root:CreateButton(compare, function()
            CompareWith(fights)
        end)

        local delete = whole and "Delete these fights" or ("Delete these %d fights"):format(#fights)
        root:CreateButton(delete, function()
            ns.Recorder.DeleteFights(SetOf(fights))
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

    -- Clicking in the list doesn't take the cursor out of the search box
    -- by itself, and the box would go on holding the movement keys.
    tab.search:ClearFocus()

    -- The "Other fights" divider is only a label.
    if data.divider then
        return
    end

    if data.recording then
        if mouseButton == "RightButton" then
            ShowSessionMenu(row, data)
            return
        end

        local fights = SetOf(FightsUnder(data))
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

--- Who a group was, for a row whose name only says how many: each kind of
--- enemy with how many there were, and its level and standing.
local function ShowFoesTooltip(row)
    local data = row.data
    local described = data and data.described
    if not described or not described.group or not data.fight.foes then
        return
    end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(described.title, 1, 1, 1)
    for _, foe in ipairs(data.fight.foes) do
        local name = foe.name or "Enemy"
        if foe.count > 1 then
            name = ("%s ×%d"):format(name, foe.count)
        end

        -- The game writes a level it hides as "??".
        local standing = "level " .. (foe.level or "??")
        local mark = ns.Foes and ns.Foes.MarkOf(foe.classification, foe.boss)
        if mark then
            standing = standing .. ", " .. ns.Foes.MARK_WORDS[mark]
        end
        Kit.TooltipFigure(name, standing)
    end
    GameTooltip:Show()
end

local function CreateRowWidgets(row)
    row.created = true
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnEnter", ShowFoesTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)

    -- The auction house's glow under the mouse and its band across a
    -- selected row.
    Kit.DressRow(row)

    -- A quiet band behind a session's heading, to set it off from the
    -- fights under it.
    row.band = row:CreateTexture(nil, "BACKGROUND")
    row.band:SetAllPoints()
    row.band:SetColorTexture(1, 1, 1, 0.06)

    -- A hairline along the foot of every row, in the colour the window's
    -- boxes are edged with, so the rows don't run together.
    row.rule = Kit.Rule(row)
    row.rule:SetHeight(1)

    -- A blue stripe down the left edge of a fight that's being compared
    -- with, and a word on the right to say what the stripe means.
    row.stripe = row:CreateTexture(nil, "BORDER")
    row.stripe:SetPoint("TOPLEFT")
    row.stripe:SetPoint("BOTTOMLEFT")
    row.stripe:SetWidth(3)
    row.stripe:SetColorTexture(Kit.BLUE[1], Kit.BLUE[2], Kit.BLUE[3], 1)

    row.title = Kit.Text(row, "GameFontNormal")

    -- Close behind the name, small: the enemy's level and its mark.
    row.level = Kit.Text(row, "GameFontHighlightSmall")
    row.level:SetPoint("BOTTOMLEFT", row.title, "BOTTOMRIGHT", BESIDE_NAME, 0)
    row.level:SetTextColor(unpack(Kit.MUTED))

    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetSize(MARK_SIZE, MARK_SIZE)

    -- On the right: how long a fight lasted, or how many fights a session
    -- holds.
    row.aside = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.aside:SetPoint("TOPRIGHT", -ROW_RIGHT, -7)
    row.aside:SetTextColor(unpack(Kit.MUTED))

    -- A star on a fight that holds one of the character's bests.
    row.best = Kit.Icon(row, BEST_SIZE, "best")
    row.best:SetPoint("RIGHT", row.aside, "LEFT", -4, 0)

    row.tag = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.tag:SetTextColor(unpack(Kit.MUTED))
    row.tag:SetText("compared")

    row.detail = Kit.Text(row, "GameFontHighlightSmall")
    row.detail:SetPoint("BOTTOMLEFT", ROW_LEFT, 6)
    row.detail:SetPoint("RIGHT", -ROW_RIGHT, 0)
end

--- A heading row: a session's name and how many fights it holds, or the
--- divider that marks where a session's fights stop. Set in a band with a
--- rule under it, and in white, apart from the gold of the fights' names.
local function FillHeading(row, data)
    row.title:SetFontObject("GameFontHighlight")
    row.title:SetPoint("LEFT", 6, 0)
    row.title:SetPoint("RIGHT", row.aside, "LEFT", -6, 0)
    row.title:SetWidth(0)
    row.detail:SetText("")
    row.band:Show()
    row.chosen:Hide()
    row.stripe:Hide()
    row.tag:Hide()
    row.best:Hide()
    row.level:Hide()
    row.mark:Hide()
    row.hover:SetAlpha(data.divider and 0 or 1)

    row.rule:ClearAllPoints()
    row.rule:SetPoint("BOTTOMLEFT")
    row.rule:SetPoint("BOTTOMRIGHT")

    if data.divider then
        row.title:SetText(Kit.Colored("Other fights", Kit.MUTED))
        row.aside:SetText("")
        return
    end

    local session = data.recording
    local title = ("Session %d"):format(session.number)
    if ns.Recorder.Open() == session then
        title = title .. "  " .. Kit.Colored("in progress", Kit.GOOD)
    end
    row.title:SetText(title)

    local count = FightsText(#ns.Recorder.FightsOf(session))
    if data.shown then
        count = ("%d of %s"):format(#data.shown, count)
    end
    row.aside:SetText(count)
end

--- Shows an elite, rare or boss mark, or hides it.
local function ShowMark(texture, mark)
    local art = MARKS[mark]
    if not art then
        texture:Hide()
        return
    end

    if art.atlas then
        texture:SetAtlas(art.atlas)
    else
        texture:SetTexture(art.file)
        texture:SetTexCoord(0, 1, 0, 1)
    end
    texture:Show()
end

local function FillRow(row, data)
    row.data = data
    row.title:ClearAllPoints()

    if not data.fight then
        FillHeading(row, data)
        return
    end

    local fight, described = data.fight, data.described
    local compared = other ~= nil and other[fight] == true

    row.title:SetFontObject("GameFontNormal")
    row.band:Hide()
    row.hover:SetAlpha(1)
    row.chosen:SetShown(chosen[fight] == true)
    row.stripe:SetShown(compared)
    row.best:SetShown(data.best == true)

    -- Between fights the rule stops short of the edges, as a divider in a
    -- list does.
    row.rule:ClearAllPoints()
    row.rule:SetPoint("BOTTOMLEFT", ROW_LEFT - 4, 0)
    row.rule:SetPoint("BOTTOMRIGHT", -ROW_RIGHT + 2, 0)

    -- Along the top, right to left: the length, the star, the tag.
    row.aside:SetText(ns.Duration(fight.length))
    local taken = row.aside:GetStringWidth()
    local edge = row.aside
    if data.best then
        taken = taken + 4 + BEST_SIZE
        edge = row.best
    end
    row.tag:SetShown(compared)
    if compared then
        row.tag:SetPoint("RIGHT", edge, "LEFT", -6, 0)
        taken = taken + 6 + row.tag:GetStringWidth()
    end

    -- From the left: the name, then its level and mark close behind it.
    -- The name has whatever room those leave, and is cut short to fit.
    row.level:SetText(described.level or "")
    row.level:SetShown(described.level ~= nil)
    local beside = described.level and BESIDE_NAME + row.level:GetStringWidth() or 0

    ShowMark(row.mark, described.mark)
    row.mark:ClearAllPoints()
    row.mark:SetPoint("LEFT", described.level and row.level or row.title, "RIGHT", BESIDE_NAME, 0)
    if described.mark then
        beside = beside + BESIDE_NAME + MARK_SIZE
    end

    row.title:SetPoint("TOPLEFT", ROW_LEFT, -6)
    row.title:SetText(described.title)
    local room = LIST_WIDTH - ROW_LEFT - ROW_RIGHT - taken - 6 - beside
    row.title:SetWidth(math.max(1, math.min(math.ceil(row.title:GetUnboundedStringWidth()), room)))

    row.detail:SetText(FiguresText(fight))
end

--- The rows of the list: fights newest first, with a heading above each
--- session's run of them and a divider where a run gives way to fights
--- that weren't part of a session. With a search on, only the fights that
--- match, and the headings of the sessions they're in.
local function BuildRows()
    local fights = ns.character.fights
    local rows = {}
    everyFight, order = {}, {}

    local holdsBest = {}
    for _, best in ipairs(ns.Progress.Bests()) do
        holdsBest[best.fight] = true
    end

    -- A session with no fights yet still wants its heading, so the
    -- player can see that Start session did something. A search can't
    -- have found anything in it.
    local open = ns.Recorder.Open()
    local headed = false
    if open and not searchFor and #ns.Recorder.FightsOf(open) == 0 then
        table.insert(rows, { recording = open })
        headed = true
    end

    -- Which session the rows being added belong to: a number, or false
    -- for none. Starts as nil so the first fight always counts as a change.
    -- With a search on, each heading notes the fights shown under it.
    local run, heading
    for index = #fights, 1, -1 do
        local fight = fights[index]
        local described = Describe(fight)
        table.insert(everyFight, fight)

        if Matches(fight, described) then
            local session = fight.recording and ns.Recorder.Numbered(fight.recording)
            local belongs = session and session.number or false

            if belongs ~= run then
                run = belongs
                heading = nil
                if session then
                    heading = { recording = session, shown = searchFor and {} or nil }
                    table.insert(rows, heading)
                    headed = true
                elseif headed then
                    table.insert(rows, { divider = true })
                end
            end
            if heading and heading.shown then
                table.insert(heading.shown, fight)
            end

            table.insert(order, fight)
            table.insert(rows, { fight = fight, described = described, best = holdsBest[fight] })
        end
    end
    return rows
end

--- Puts rows in the list, and says so when a search has found nothing.
---@param toTop boolean|nil  true to go back to the top, as when the search
---                          changes; otherwise the list stays where it was
local function ShowRows(rows, toTop)
    -- The game's two choices are true and false, so they can't be picked
    -- between with "and" and "or".
    local keep = ScrollBoxConstants.RetainScrollPosition
    if toTop then
        keep = ScrollBoxConstants.DiscardScrollPosition
    end
    tab.scrollBox:SetDataProvider(CreateDataProvider(rows), keep)
    tab.noMatch:SetShown(searchFor ~= nil and #order == 0)
end

--- Narrows the list as the player types. Nothing else on the page changes
--- with it, so only the list is redrawn.
local function OnSearchChanged(box)
    local text = strtrim(box:GetText() or ""):lower()
    local wanted = text ~= "" and text or nil
    if wanted == searchFor then
        return
    end
    searchFor = wanted

    if tab and tab:IsVisible() then
        ShowRows(BuildRows(), true)
    end
end

--- The search box over the list, in the game's own style: a magnifying
--- glass, a prompt while it's empty, and a cross to clear it. Enter and
--- Escape both let go of the keyboard, as the game's own search boxes do.
local function CreateSearchBox(panel)
    local box = CreateFrame("EditBox", nil, tab, "SearchBoxTemplate")
    box:SetHeight(SEARCH_HEIGHT)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", LIST_EDGE + SEARCH_BORDER, -SEARCH_TOP)
    box:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LIST_EDGE, -SEARCH_TOP)

    -- Opening the window mustn't swallow the player's movement keys.
    box:SetAutoFocus(false)
    box:SetMaxLetters(SEARCH_LETTERS)
    box.Instructions:SetText(SEARCH_PROMPT)

    -- Hooked, not set, so the template still shows and hides its prompt
    -- and its cross.
    box:HookScript("OnTextChanged", OnSearchChanged)

    -- A rule under it, to set it off from the list.
    local rule = Kit.Rule(panel)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", LIST_EDGE, -(LIST_TOP - 1))
    rule:SetPoint("TOPRIGHT", -LIST_EDGE, -(LIST_TOP - 1))

    return box
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

    -- Left: the search box and the list under it, framed the way the game
    -- frames its own.
    local panel = Kit.Inset(tab)
    panel:SetPoint("TOPLEFT")
    panel:SetPoint("BOTTOMLEFT")
    panel:SetWidth(PANEL_WIDTH)

    tab.search = CreateSearchBox(panel)

    local scrollBox = CreateFrame("Frame", nil, tab, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", panel, "TOPLEFT", LIST_EDGE, -LIST_TOP)
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

    -- Where the list would be, when a search finds nothing.
    tab.noMatch = Kit.Text(scrollBox, "GameFontHighlightSmall", "CENTER")
    tab.noMatch:SetPoint("TOP", 0, -16)
    tab.noMatch:SetTextColor(unpack(Kit.MUTED))
    tab.noMatch:SetText(NO_MATCH)
    tab.noMatch:Hide()

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
    -- and not with green and red figures nobody remembers asking for. A
    -- search goes the same way, so the list never comes back mysteriously
    -- short.
    tab:SetScript("OnHide", function()
        other = nil
        StopPicking()
        tab.search:ClearFocus()
        tab.search:SetText("")
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
    local newest = order[1] or everyFight[1]
    if not next(chosen) and newest then
        chosen = { [newest] = true }
        lastClicked = not picking and newest or nil
    end
    if #everyFight == 0 then
        StopPicking()
    end

    ShowRows(rows)

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
    ShowStripButtons(#everyFight > 1)

    tab.record:SetText(ns.Recorder.Open() and "End session" or "Start session")
end

--- Chooses what the tab shows the next time it's drawn. Any search is
--- cleared, so the fights asked for are there in the list to be seen.
---@param fights table  list of fights to read
---@param against table|nil  list of fights to compare them with; nil for
---                          no comparison
function FightsTab.Select(fights, against)
    chosen = SetOf(fights)
    other = against and #against > 0 and SetOf(against) or nil
    picking = false
    lastClicked = fights[1]
    if tab then
        tab.search:SetText("")
    end
    Refresh()
end
