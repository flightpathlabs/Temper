local _, ns = ...

-- The Healing tab: what the player healed, what hurt them, and how the
-- two compare.
--
-- It has no list of its own. Picking fights out one by one is what the
-- Fights tab is for. The question here is a broader one, "how am I holding
-- up?", so the choice is between a few ready-made sets of fights: the last
-- one, this session, the last ten, everything. The menu for that sits in
-- the strip under the title bar, with a line beside it saying what the set
-- came to. When the player comes here from the Fights page, the fights
-- they were reading there are offered too, and chosen.
--
-- The page is built from the same pieces as the Fights page and laid out
-- the same way (see "Pages" in Kit.lua), so the two read as one. A row of
-- figures runs across the top. Under it, healing and harm stand side by
-- side, where the healing came from on the left and what did the hurting
-- on the right, so one can be weighed against the other at a glance. Then
-- come the counts of blows and heals, and the advice.
--
-- All the reckoning is in Record\Healing.lua. This file only draws it.

local HealingTab = {}
ns.HealingTab = HealingTab

local Kit = ns.Kit

local LOGO = "Interface\\AddOns\\Temper\\Media\\logo"

-- The strip under the window's title bar, which starts clear of the
-- emblem in the corner: the menu, and beside it what its choice came to.
local STRIP_HEIGHT = 34
local STRIP_LEFT = 66
local STRIP_EDGE = 10
local MENU_WIDTH = 180
local MENU_GAP = 12

-- Space between the tab's edge and what's on it, and the room kept clear
-- down the right-hand side for the scroll bar.
local MARGIN = 14
local TOP_MARGIN = 10
local SCROLL_BAR_ROOM = 24

-- How wide the page is when the window is its usual size. Only used if
-- the tab is filled before the game has worked out its real width.
local USUAL_WIDTH = 852

-- Space between the two columns of bars, between one bar and the next,
-- and between lines of text in a section.
local COLUMN_GAP = Kit.SECTION_GAP
local BAR_GAP = 3
local LINE_GAP = 6

-- The most bars in a column. Anything beyond shares the last one.
local MAX_BARS = 6

-- Healing in the green the game shows it in, and harm in a red that can't
-- be taken for it.
local HEALING_COLOR = { 0.3, 0.78, 0.5 }
local HARM_COLOR = { 0.82, 0.36, 0.3 }

-- The sets of fights the menu offers, and how many "the last few" is.
local SCOPES = {
    { key = "last", label = "Last fight" },
    { key = "session", label = "This session" },
    { key = "recent", label = "Last 10 fights" },
    { key = "all", label = "Everything on record" },
}
local RECENT_FIGHTS = 10

-- The extra choice for fights brought over from the Fights page. Only on
-- the menu once there are some.
local CHOSEN = { key = "chosen", label = "Chosen on the Fights tab" }

local NO_FIGHTS = "No fights on record yet.\n\n"
    .. "Fight something on your own and what you healed, and what hurt you, "
    .. "will appear here.\n\n"
    .. "Your fights are kept on this computer and never shared."

local NONE_THIS_SESSION = "No fights this session yet.\n\n"
    .. "Fight something on your own and it will appear here, "
    .. "or pick other fights from the menu above."

-- Said of fights that carry no record of healing: every fight from before
-- this was added.
local NO_RECORD = "Temper has no record of healing for %s.\n\n"
    .. "It only began keeping one lately, so earlier fights have none. "
    .. "Your next fights will show here."

local NOTHING_HAPPENED = "No healing was done and no damage was taken in %s.\n\n"
    .. "Only healing done during a fight is counted."

local NOTHING_STANDS_OUT = "Nothing stands out in %s."

local FOOTNOTE = "Only healing done during a fight is counted, so eating or bandaging "
    .. "between fights isn't here."

local AVOIDABLE = "The game marks some enemy abilities as avoidable: ones that can be "
    .. "stepped out of, interrupted or otherwise not taken."
local THIS_IS_AVOIDABLE = "The game marks this as damage that can be avoided."

local ABSORBED = "Damage your own shields soaked up, so it never reached your health."
local EVERY_HEAL = "Every heal that landed on you is counted, whatever it came from."

-- The game's words for the ways an attack can fail, as we'd say them of
-- an enemy's.
local AVOIDED_WAYS = {
    { "DODGE", "dodged" },
    { "PARRY", "parried" },
    { "BLOCK", "blocked" },
    { "MISS", "missed" },
    { "RESIST", "resisted" },
    { "ABSORB", "absorbed" },
    { "DEFLECT", "deflected" },
    { "REFLECT", "reflected" },
    { "EVADE", "evaded" },
    { "IMMUNE", "had no effect" },
}

local tab

-- Which set of fights the page covers. Kept for as long as the game is
-- running and no longer: the last fight is the right place to start.
local scope = "last"

-- The fights last brought over from the Fights page, if any.
local chosen

local Refresh

-- Which fights ------------------------------------------------------------------

--- The fights one of the menu's choices covers.
---@param choice string  a key of SCOPES
---@return table fights
---@return string|nil name  what the set is called, if it has a name
local function FightsIn(choice)
    local fights = ns.character.fights
    if choice == CHOSEN.key and chosen then
        return chosen
    elseif choice == "all" then
        return fights
    elseif choice == "session" then
        -- What counts as the session is the panel's rule (see Widget.lua),
        -- so the two can't disagree. Only a session the player started
        -- has a name: the other kind is just what the menu already says.
        local started = ns.Recorder.Open()
        return ns.SessionSoFar(), started and "Session " .. started.number or nil
    end

    local latest = {}
    local count = choice == "recent" and RECENT_FIGHTS or 1
    for index = math.max(#fights - count + 1, 1), #fights do
        table.insert(latest, fights[index])
    end
    return latest
end

-- What the page says ------------------------------------------------------------

local function FightsText(count)
    return count == 1 and "1 fight" or count .. " fights"
end

local function These(count)
    return count == 1 and "this fight" or "these fights"
end

--- What the chosen set came to, for the line beside the menu:
--- "3 fights, 2m 10s of fighting".
---@param name string|nil  what the set is called, if it has a name
---@param summary table  from Healing.Of
local function CameToText(fights, name, summary)
    local text = "No fights yet"
    if #fights > 0 then
        local seconds = 0
        for _, fight in ipairs(fights) do
            seconds = seconds + fight.length
        end
        text = ("%s, %s of fighting"):format(FightsText(#fights), ns.Duration(seconds))
    end
    if name then
        text = ("%s: %s"):format(name, text)
    end

    -- Fights from before healing was recorded are in the set but not in
    -- the figures, and the reader should know that.
    if summary.tracked > 0 and summary.tracked < #fights then
        local caveat = ("Healing was recorded in %d of them."):format(summary.tracked)
        text = text .. "   " .. Kit.Colored(caveat, Kit.MUTED)
    end
    return text
end

--- What to say in place of the page when there's nothing to put on it.
--- Nil when there is.
local function WhyEmpty(fights, summary)
    if #ns.character.fights == 0 then
        return NO_FIGHTS
    elseif #fights == 0 then
        -- Only "this session" can come up empty with fights on record.
        return NONE_THIS_SESSION
    elseif summary.tracked == 0 then
        return NO_RECORD:format(These(#fights))
    end

    -- Fights with a record, and not one figure in it above nothing.
    local healed = summary.healing + summary.heals
    local harmed = summary.taken + summary.absorbed + summary.struck + summary.avoided
    if healed + harmed + summary.interrupts + summary.dispels == 0 then
        return NOTHING_HAPPENED:format(These(#fights))
    end
end

--- ": 3 dodged, 2 parried, 1 missed", to follow a count of the enemy's
--- attacks that failed. Nothing when the ways they failed weren't noted.
local function WaysText(summary)
    local ways = {}
    local counted = 0
    for _, way in ipairs(AVOIDED_WAYS) do
        local times = summary.avoidedBy[way[1]]
        if times and times > 0 then
            table.insert(ways, ("%d %s"):format(times, way[2]))
            counted = counted + times
        end
    end

    if counted == 0 then
        return ""
    elseif counted < summary.avoided then
        table.insert(ways, ("%d some other way"):format(summary.avoided - counted))
    end
    return ": " .. table.concat(ways, ", ")
end

--- How the enemy's attacks fared, in a sentence. Nil when none were seen.
local function AttacksText(summary)
    local struck, avoided = summary.struck, summary.avoided
    if struck + avoided == 0 then
        return nil
    end

    -- Only blows that could have been avoided are counted (see Hits.lua),
    -- so these are blows, not every bit of harm.
    local landed = struck == 1 and "1 enemy blow landed on you"
        or ("%d enemy blows landed on you"):format(struck)
    if avoided == 0 then
        return landed .. ", and none were dodged, parried, blocked or missed."
    elseif struck == 0 then
        return ("No enemy blow landed on you%s."):format(WaysText(summary))
    end

    return ("%s and %d didn't%s. That's %s of them avoided."):format(
        landed,
        avoided,
        WaysText(summary),
        ns.Percent(summary.avoidRate)
    )
end

--- How many heals landed and how many were critical, in a sentence. Nil
--- when none were seen.
local function HealsText(summary)
    local heals, crits = summary.heals, summary.healCrits
    if heals == 0 then
        return nil
    end

    local landed = heals == 1 and "1 heal landed on you" or ("%d heals landed on you"):format(heals)
    if crits == 0 then
        return landed .. ", and none were critical."
    end
    return ("%s, and %d %s critical."):format(landed, crits, crits == 1 and "was" or "were")
end

--- The lines of the section on blows and heals. Empty when neither was
--- counted.
local function DefenceLines(summary)
    local lines = {}
    for _, Sentence in ipairs({ AttacksText, HealsText }) do
        local line = Sentence(summary)
        if line then
            table.insert(lines, line)
        end
    end
    return lines
end

-- The figures --------------------------------------------------------------------

-- Each figure in the row is a table of the kind Kit.StatRow shows: a
-- label and a value, and what lies behind it for its tooltip.

--- For several fights, how many there were and what a figure came to in
--- each of them on average, for its tooltip. Nothing for one fight.
local function PerFight(summary, total)
    if summary.tracked < 2 then
        return {}
    end
    return {
        { "Fights", ns.Number(summary.tracked) },
        { "A fight, on average", ns.Number(total / summary.tracked) },
    }
end

local function HealingStat(summary)
    return {
        label = "Healing",
        value = ns.Number(summary.healing),
        title = "Healing done",
        figures = PerFight(summary, summary.healing),
    }
end

local function RateStat(summary)
    return {
        label = "HPS",
        value = ns.Rate(summary.hps),
        title = "Healing per second",
        figures = {
            { "Healing", ns.Number(summary.healing) },
            { "Time fighting", ns.Duration(summary.seconds) },
        },
    }
end

local function TakenStat(summary)
    local stat = {
        label = "Damage taken",
        value = ns.Number(summary.taken),
        figures = PerFight(summary, summary.taken),
    }

    -- How much of it could have been avoided is the game's own call, and
    -- it doesn't always make one.
    local avoidable = summary.avoidable
    if avoidable and avoidable > 0 and summary.taken > 0 then
        local share = ns.Percent(avoidable / summary.taken)
        table.insert(stat.figures, { "Avoidable", ("%s (%s)"):format(ns.Number(avoidable), share) })
        stat.note = AVOIDABLE
    end
    return stat
end

--- Healing as a share of the damage taken. A dash when none was.
local function HealedBackStat(summary)
    local stat = {
        label = "Healed back",
        value = "-",
        title = "Damage healed back",
        figures = {},
    }

    if summary.healedBack then
        stat.value = ns.Percent(summary.healedBack)
        stat.figures = {
            { "Healing", ns.Number(summary.healing) },
            { "Damage taken", ns.Number(summary.taken) },
        }
    end
    return stat
end

local function CritStat(summary)
    local stat = {
        label = "Heal crit",
        value = summary.critRate and ns.Percent(summary.critRate) or "-",
        title = "Critical heals",
        figures = {},
    }

    if summary.heals > 0 then
        local heals = summary.heals == 1 and "1 heal" or summary.heals .. " heals"
        table.insert(stat.figures, { "Critical", ("%d of %s"):format(summary.healCrits, heals) })
        stat.note = EVERY_HEAL
    end
    return stat
end

--- Adds a plain count to the row, if there's anything to count.
---@param note string|nil  a sentence for its tooltip; none, and it has no
---                        tooltip
local function AddCount(stats, label, count, note)
    if count > 0 then
        table.insert(stats, { label = label, value = ns.Number(count), figures = {}, note = note })
    end
end

--- The figures for the row, left to right. Healing always comes first.
--- The last three are only there when they're above nothing.
local function StatsFor(summary)
    local stats = {
        HealingStat(summary),
        RateStat(summary),
        TakenStat(summary),
        HealedBackStat(summary),
        CritStat(summary),
    }

    AddCount(stats, "Absorbed", summary.absorbed, ABSORBED)
    AddCount(stats, "Interrupts", summary.interrupts)
    AddCount(stats, "Dispels", summary.dispels)
    return stats
end

-- The bars ----------------------------------------------------------------------

--- The icon of an enemy's ability. What hurt the player is recorded
--- without one, so the game is asked, once for each ability. It can
--- refuse questions about spells it doesn't recognise, and then the bar
--- gets the kit's question mark.
local icons = {}
local function IconOf(id)
    if not id or id == 0 then
        return nil
    end

    if icons[id] == nil then
        local ok, icon = pcall(C_Spell.GetSpellTexture, id)
        icons[id] = ok and icon or false
    end
    return icons[id] or nil
end

--- What a healing ability did, in a tooltip of our own, as the Fights
--- page does for one that deals damage.
local function ShowHealingTooltip(bar)
    local ability = bar.about
    if not ability then
        return
    end

    GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
    GameTooltip:SetText(ability.name, 1, 1, 1)
    if ability.rank then
        GameTooltip:AddLine(ability.rank, Kit.MUTED[1], Kit.MUTED[2], Kit.MUTED[3])
    end
    if ability.pet then
        GameTooltip:AddLine("Cast by your pet", Kit.MUTED[1], Kit.MUTED[2], Kit.MUTED[3])
    end

    Kit.TooltipFigure(
        "Healing",
        ("%s (%s)"):format(ns.Number(ability.healing), ns.Percent(ability.share))
    )
    if ability.casts and ability.perCast then
        Kit.TooltipFigure(
            ("Used %d %s"):format(ability.casts, ability.casts == 1 and "time" or "times"),
            ns.Rate(ability.perCast) .. " healing per use"
        )
    end
    if ability.cost and ability.perCost then
        local power = ns.Summary.PowerWord(ability.power)
        Kit.TooltipFigure(
            ("Costs %d %s"):format(ability.cost, power),
            ("%.1f healing per point"):format(ability.perCost)
        )
    end
    GameTooltip:Show()
end

--- What an enemy's ability did to the player, and whose it was.
local function ShowHarmTooltip(bar)
    local source = bar.about
    if not source then
        return
    end

    GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
    GameTooltip:SetText(source.name, 1, 1, 1)
    if source.from then
        GameTooltip:AddLine("From " .. source.from, Kit.MUTED[1], Kit.MUTED[2], Kit.MUTED[3])
    end

    Kit.TooltipFigure(
        "Damage",
        ("%s (%s)"):format(ns.Number(source.amount), ns.Percent(source.share))
    )
    if source.avoidable then
        GameTooltip:AddLine(THIS_IS_AVOIDABLE, Kit.GOLD[1], Kit.GOLD[2], Kit.GOLD[3], true)
    end
    GameTooltip:Show()
end

---@param share number  how full the bar is, 0 to 1
local function FillHealingBar(bar, ability, share)
    local name = ability.name
    if ability.rank then
        name = name .. "  " .. Kit.Colored(ability.rank, Kit.MUTED)
    end
    if ability.pet then
        name = name .. "  " .. Kit.Colored("pet", Kit.MUTED)
    end

    local figures = ("%s  %s"):format(ns.Number(ability.healing), ns.Percent(ability.share))
    bar:Set(ability.icon, name, figures, share, HEALING_COLOR)
end

---@param share number  how full the bar is, 0 to 1
local function FillHarmBar(bar, source, share)
    local name = source.name
    if source.from then
        name = name .. "  " .. Kit.Colored(source.from, Kit.MUTED)
    end

    -- The word goes with the figures, where a long name can't push it
    -- out of sight.
    local figures = ("%s  %s"):format(ns.Number(source.amount), ns.Percent(source.share))
    if source.avoidable then
        figures = Kit.Colored("avoidable", Kit.GOLD) .. "  " .. figures
    end
    bar:Set(IconOf(source.id), name, figures, share, HARM_COLOR)
end

--- Every row of a list from `first` on, added up into one.
---@param amount string  the name of the figure the rows are measured by
local function EverythingElse(rows, first, amount)
    local rest = { name = "Everything else", share = 0, [amount] = 0 }
    for index = first, #rows do
        rest[amount] = rest[amount] + rows[index][amount]
        rest.share = rest.share + rows[index].share
    end
    return rest
end

--- A bar for each of the biggest rows of a column. The biggest gets a
--- full bar and the others are drawn against it.
---@param column table  from CreateColumn, with its rows
---@param inside table  the layout for the column's section
local function PlaceBars(column, inside)
    local rows, amount = column.rows, column.amount
    local biggest = rows[1][amount]
    local gap = 0

    for index, bar in ipairs(column.bars) do
        local row = rows[index]

        -- Any rows beyond the last bar share it.
        if index == MAX_BARS and #rows > MAX_BARS then
            row = EverythingElse(rows, MAX_BARS, amount)
        end

        bar.about = row
        if row then
            local share = biggest > 0 and math.min(row[amount] / biggest, 1) or 0
            column.Fill(bar, row, share)
            Kit.Place(inside, bar, gap)
            gap = BAR_GAP
        end
    end
end

-- Laying out ---------------------------------------------------------------------

--- Notes a piece of the page, so that a fill can start by clearing every
--- piece away and then show only the ones it places.
local function Piece(piece)
    table.insert(tab.pieces, piece)
    return piece
end

--- The width there is for the page.
local function PageWidth()
    local width = tab.scroll:GetWidth()
    return width > 0 and width or USUAL_WIDTH
end

--- Healing and harm, side by side. When there's only one of the two it
--- has the width of the page to itself.
local function PlaceColumns(layout, summary)
    tab.healing.rows = summary.abilities
    tab.harm.rows = summary.hurtBy

    local columns = {}
    for _, column in ipairs({ tab.healing, tab.harm }) do
        if #column.rows > 0 then
            table.insert(columns, column)
        end
    end
    if #columns == 0 then
        return
    end

    local width = math.floor((layout.width - (#columns - 1) * COLUMN_GAP) / #columns)
    local foot = 0
    for index, column in ipairs(columns) do
        column.layout = {
            frame = layout.frame,
            left = layout.left + (index - 1) * (width + COLUMN_GAP),
            width = width,
            y = layout.y,
        }
        column.inside = Kit.Inside(column.layout, column.section)
        PlaceBars(column, column.inside)
        foot = math.max(foot, column.inside.y)
    end

    -- Both boxes end where the longer of the two does, so the row has a
    -- level foot, and the page carries on from under it.
    for _, column in ipairs(columns) do
        column.inside.y = foot
        Kit.PlaceSection(column.layout, column.section, column.inside)
        layout.y = column.layout.y
    end
end

--- The blows and heals that were counted, a sentence for each. Left out
--- when neither was.
local function PlaceDefence(layout, summary)
    local lines = DefenceLines(summary)
    if #lines == 0 then
        return
    end

    local section = tab.defenceSection
    local inside = Kit.Inside(layout, section)

    local gap = 0
    for index, line in ipairs(lines) do
        Kit.PlaceText(inside, tab.defenceLines[index], gap, line)
        gap = LINE_GAP
    end

    Kit.PlaceSection(layout, section, inside)
end

--- One row per finding. With no findings the section says so in a line
--- of its own, as on the Fights page.
local function PlaceFindings(layout, summary)
    local section = tab.findingsSection
    local inside = Kit.Inside(layout, section)

    local findings = ns.Healing.Findings(summary)
    if #findings == 0 then
        local these = These(summary.fights)
        findings = { { kind = "tip", text = NOTHING_STANDS_OUT:format(these) } }
    end

    Kit.PlaceFindings(inside, tab.findings, findings)
    Kit.PlaceSection(layout, section, inside)
end

-- Building ---------------------------------------------------------------------

--- The menu of which fights to cover and the line beside it, in the
--- window's own strip under the title bar. They belong to this tab and go
--- when the tab does.
local function CreateStrip(window)
    local strip = CreateFrame("Frame", nil, tab)
    strip:SetPoint("TOPLEFT", window, "TOPLEFT", STRIP_LEFT, -24)
    strip:SetPoint("RIGHT", window, "RIGHT", -6, 0)
    strip:SetHeight(STRIP_HEIGHT)

    local menu = CreateFrame("DropdownButton", nil, strip, "WowStyle1DropdownTemplate")
    menu:SetWidth(MENU_WIDTH)
    menu:SetPoint("LEFT")
    menu:SetupMenu(function(_, root)
        local function IsChosen(key)
            return key == scope
        end
        local function Choose(key)
            scope = key
            Refresh()
        end
        for _, choice in ipairs(SCOPES) do
            root:CreateRadio(choice.label, IsChosen, Choose, choice.key)
        end
        if chosen then
            root:CreateRadio(CHOSEN.label, IsChosen, Choose, CHOSEN.key)
        end
    end)
    strip.menu = menu

    strip.cameTo = Kit.Text(strip, "GameFontHighlight")
    strip.cameTo:SetPoint("LEFT", menu, "RIGHT", MENU_GAP, 0)
    strip.cameTo:SetPoint("RIGHT", -STRIP_EDGE, 0)

    return strip
end

local function CreateBar(section, ShowTooltip)
    local bar = Kit.Bar(section)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", ShowTooltip)
    bar:SetScript("OnLeave", GameTooltip_Hide)
    return bar
end

--- One of the two columns of bars: a section, the bars in it, and how a
--- bar is filled from a row of the summary.
---@param amount string  the name of the figure a row is measured by
---@param Fill fun(bar: table, row: table, share: number)
---@return table column  { section, bars, amount, Fill }. Each time the
---                      page is filled it's given its rows as well, and
---                      the layouts that say where it stands
local function CreateColumn(title, amount, Fill, ShowTooltip)
    local column = { amount = amount, Fill = Fill, bars = {} }

    -- A section's contents belong to the section, so they're drawn over
    -- its fill and go when it goes.
    column.section = Piece(Kit.Section(tab.page, title))
    for index = 1, MAX_BARS do
        column.bars[index] = Piece(CreateBar(column.section, ShowTooltip))
    end
    return column
end

--- Builds the tab.
---@param parent table  the window's inset, which the tab fills
---@param window table  the window itself, whose strip the menu sits in
function HealingTab.Create(parent, window)
    tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()
    tab.pieces = {}

    tab.strip = CreateStrip(window)

    -- Fixed at the top: the figures.
    tab.stats = Kit.StatRow(tab)
    tab.stats:SetPoint("TOPLEFT", MARGIN, -TOP_MARGIN)
    tab.stats:SetPoint("TOPRIGHT", -SCROLL_BAR_ROOM, -TOP_MARGIN)
    tab.stats:Hide()

    -- Shown in place of everything else when there's nothing to put on
    -- the page, as on the Fights page.
    tab.empty = Kit.Paragraph(tab, "GameFontHighlight", "CENTER")
    tab.empty:SetPoint("CENTER", 0, -60)
    tab.empty:SetWidth(400)
    tab.empty:SetTextColor(unpack(Kit.MUTED))

    tab.logo = tab:CreateTexture(nil, "ARTWORK")
    tab.logo:SetTexture(LOGO)
    tab.logo:SetSize(320, 160)
    tab.logo:SetPoint("BOTTOM", tab.empty, "TOP", 0, 6)

    -- The rest scrolls. The template brings its own scroll bar, which
    -- only needs telling to stay out of sight while everything fits.
    tab.scroll = CreateFrame("ScrollFrame", nil, tab, "ScrollFrameTemplate")
    tab.scroll:SetPoint("TOPLEFT", tab.stats, "BOTTOMLEFT", 0, -Kit.SECTION_GAP)
    tab.scroll:SetPoint("BOTTOMRIGHT", -SCROLL_BAR_ROOM, 8)
    tab.scroll.ScrollBar:SetHideIfUnscrollable(true)

    tab.page = CreateFrame("Frame", nil, tab.scroll)
    tab.page:SetSize(USUAL_WIDTH, 1)
    tab.scroll:SetScrollChild(tab.page)

    tab.healing =
        CreateColumn("Where the healing came from", "healing", FillHealingBar, ShowHealingTooltip)
    tab.harm = CreateColumn("What hurt you", "amount", FillHarmBar, ShowHarmTooltip)

    -- A sentence on the enemy's attacks and one on the heals.
    local defence = Piece(Kit.Section(tab.page, "Holding your ground"))
    tab.defenceSection = defence
    tab.defenceLines = {
        Piece(Kit.Paragraph(defence, "GameFontHighlight")),
        Piece(Kit.Paragraph(defence, "GameFontHighlight")),
    }

    -- Findings come a few at a time, so their rows are made as they're
    -- first needed.
    tab.findingsSection = Piece(Kit.Section(tab.page, "What to work on"))
    tab.findings = {}

    tab.footnote = Piece(Kit.Paragraph(tab.page, "GameFontHighlightSmall"))
    tab.footnote:SetTextColor(unpack(Kit.MUTED))

    tab.Refresh = Refresh
    return tab
end

-- Filling ------------------------------------------------------------------------

--- The tab with nothing to show: the logo, and a line on why.
local function ShowEmpty(words)
    tab.stats:Hide()
    tab.scroll:Hide()
    tab.shown = nil

    tab.empty:SetText(words)
    tab.empty:Show()
    tab.logo:Show()
end

local function ShowPage(summary)
    tab.empty:Hide()
    tab.logo:Hide()
    tab.stats:Show()
    tab.scroll:Show()

    local width = PageWidth()
    tab.stats:Fill(StatsFor(summary), width, false)

    for _, piece in ipairs(tab.pieces) do
        piece:Hide()
    end

    local layout = { frame = tab.page, left = 0, width = width, y = 0 }

    PlaceColumns(layout, summary)
    PlaceDefence(layout, summary)
    PlaceFindings(layout, summary)
    Kit.PlaceText(layout, tab.footnote, Kit.SECTION_GAP, FOOTNOTE)

    tab.page:SetSize(width, layout.y + Kit.SECTION_GAP)

    -- A new choice from the menu starts at the top. A redraw of the same
    -- one, as when a fight ends while the page is open, leaves the reader
    -- where they were.
    if tab.shown ~= scope then
        tab.scroll:SetVerticalScroll(0)
    end
    tab.shown = scope
end

--- Covers the given fights, from the Fights page, the next time the tab
--- is drawn. Called with none, as when the healing panel is clicked, it
--- goes back to the last fight if it was on fights brought over before:
--- those are old news by now, though the menu still offers them. Safe to
--- call before the tab exists.
---@param fights table|nil  list of fights
function HealingTab.Cover(fights)
    if fights then
        chosen = fights
        scope = CHOSEN.key
    elseif scope == CHOSEN.key then
        scope = "last"
    end

    -- The page is the same choice as before, but not the same fights, so
    -- it starts again at the top.
    if tab then
        tab.shown = nil
    end
end

function Refresh()
    if not tab or not tab:IsVisible() then
        return
    end

    -- A fight deleted since it was brought over is no longer on record.
    -- Drop the set rather than draw a fight that isn't there.
    if chosen then
        local kept = {}
        for _, fight in ipairs(ns.character.fights) do
            kept[fight] = true
        end
        for _, fight in ipairs(chosen) do
            if not kept[fight] then
                chosen = nil
                if scope == CHOSEN.key then
                    scope = "last"

                    -- The menu read its label when the tab was shown,
                    -- which was before this. Have it read it again.
                    tab.strip.menu:GenerateMenu()
                end
                break
            end
        end
    end

    local fights, name = FightsIn(scope)
    local summary = ns.Healing.Of(fights)
    tab.strip.cameTo:SetText(CameToText(fights, name, summary))

    local why = WhyEmpty(fights, summary)
    if why then
        ShowEmpty(why)
    else
        ShowPage(summary)
    end
end
