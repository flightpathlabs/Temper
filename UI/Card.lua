local _, ns = ...

-- The analysis card: everything about a set of fights on one page.
--
-- Read top to bottom it answers, in order: how hard did I hit, where did
-- it come from, what did I press, what stands out, and (when there's a
-- "before" to compare with) what changed. The comparison isn't a separate
-- screen. It shows up as an arrow and a green or red figure beside each
-- number it applies to.
--
-- Some selections make a longer page than the window has room for, so
-- everything under the title scrolls. A scrolling page can't size itself
-- from its anchors, and text only wraps once it's told how wide it may
-- be. So the page is laid out by hand each time it's filled: every piece
-- is given a width and a place under the piece before it, and the page
-- ends where the last piece does.

local Card = {}
ns.Card = Card

local Kit = ns.Kit

local LOGO = "Interface\\AddOns\\Temper\\Media\\logo"
local NOTE_PROMPT = "Add a note: what did you change?"

-- Space between the card's edge and what's on it, and the room kept clear
-- down the right-hand side for the scroll bar.
local MARGIN = 14
local SCROLL_BAR_ROOM = 24

-- How far down the card the note box sits, and where the scrolling page
-- starts: lower when the note box is in between.
local NOTE_TOP = 44
local NOTE_HEIGHT = 20
local PAGE_TOP = 46
local PAGE_TOP_WITH_NOTE = 72

-- How wide the page is when the window is its usual size. Only used if
-- the card is filled before the game has worked out its real width.
local USUAL_WIDTH = 547

-- Space above a section's heading, under it, and between lines of text.
local SECTION_GAP = 16
local HEADING_GAP = 8
local LINE_GAP = 6

local TILE_GAP = 8
local MAX_BARS = 6
local BAR_GAP = 3
local FINDING_ICON = 16
local FINDING_GAP = 8

-- More changed slots than this and the list is cut short, with a count.
local MAX_GEAR_LINES = 5

-- The game's words for the ways an attack can fail, as we'd say them.
local AVOIDED_WORDS = {
    { "MISS", "missed" },
    { "DODGE", "dodged" },
    { "PARRY", "parried" },
    { "BLOCK", "blocked" },
    { "RESIST", "resisted" },
    { "ABSORB", "absorbed" },
    { "IMMUNE", "immune" },
    { "EVADE", "evaded" },
    { "DEFLECT", "deflected" },
    { "REFLECT", "reflected" },
}

-- What the page says ------------------------------------------------------------

--- "Biggest critical hit about 62 (Aimed Shot).   Biggest hit about 41."
-- The size of a single blow is worked out, not read (see Sizes.lua), so
-- it's always "about". Nil when no blow could be sized.
local function BlowsText(summary)
    local sizes = summary.sizes
    if not sizes then
        return nil
    end

    local function Blow(label, size, spell)
        local text = ("%s about %s"):format(label, Kit.Colored(ns.Number(size), Kit.GOLD))
        if spell then
            text = ("%s (%s)"):format(text, ns.Sources.Name(spell))
        end
        return text .. "."
    end

    local parts = {}
    if sizes.biggestCrit then
        table.insert(parts, Blow("Biggest critical hit", sizes.biggestCrit, sizes.biggestCritSpell))
    end
    if sizes.biggest and sizes.biggest ~= sizes.biggestCrit then
        table.insert(parts, Blow("Biggest hit", sizes.biggest, sizes.biggestSpell))
    end
    return #parts > 0 and table.concat(parts, "   ") or nil
end

--- "18 hits, 2 critical, 1 glancing.   3 missed, 1 dodged, 2 parried."
local function CountsText(summary)
    local text = ("%d hits, %d critical, %d glancing."):format(
        summary.hits,
        summary.crits,
        summary.glancing
    )
    if summary.avoided == 0 then
        return text .. "   Nothing missed."
    end

    local ways, counted = {}, 0
    for _, word in ipairs(AVOIDED_WORDS) do
        local times = summary.avoidedBy[word[1]]
        if times then
            table.insert(ways, ("%d %s"):format(times, word[2]))
            counted = counted + times
        end
    end

    -- Fights saved before the ways were told apart only have the total.
    if counted < summary.avoided then
        table.insert(ways, ("%d missed or avoided"):format(summary.avoided - counted))
    end
    return text .. "   " .. table.concat(ways, ", ") .. "."
end

--- "Skills 62%    Auto attacks 38%", each kind in the colour of its bars,
--- so the line is also the key to them.
local function KindsText(summary)
    local kinds = {}
    for _, kind in ipairs(ns.Sources.ORDER) do
        local damage = summary.kinds[kind] or 0
        if damage > 0 then
            local label = Kit.Colored(ns.Sources.LABELS[kind], Kit.KIND_COLORS[kind])
            table.insert(kinds, ("%s %s"):format(label, ns.Percent(damage / summary.damage)))
        end
    end
    return table.concat(kinds, "    ")
end

--- How fights against one enemy compare with fights against several, when
--- the set has both. Nil when there's nothing to say.
local function SplitText(summary)
    if summary.several.fights == 0 then
        return nil
    end
    if summary.single.fights == 0 then
        return "Every fight here was against several enemies at once."
    end

    return ("One enemy: %s a second over %d fights.   Several at once: %s over %d."):format(
        ns.Rate(summary.single.dps),
        summary.single.fights,
        ns.Rate(summary.several.dps),
        summary.several.fights
    )
end

--- For a set of fights, how busy the player's hands were: skills used,
--- how often, and how much of the time went by without one.
local function PressedText(summary)
    local time = ns.Duration(summary.watched)
    if summary.presses == 0 then
        return ("No skills were used in %s of fighting."):format(time)
    end

    local used = ("%d %s used in %s of fighting, about one every %.1fs."):format(
        summary.presses,
        summary.presses == 1 and "skill" or "skills",
        time,
        summary.watched / summary.presses
    )
    local unused = ("No skill was in use for about %s of that time."):format(
        ns.Percent(summary.idle / summary.watched)
    )
    local text = used .. " " .. unused

    -- Older fights have had their move-by-move record dropped to save room.
    if summary.watched < summary.seconds - 1 then
        local caveat = "Only the latest fights are followed this closely."
        text = text .. "  " .. Kit.Colored(caveat, Kit.MUTED)
    end
    return text
end

--- What differed between the two sets besides the fighting itself: the
--- player's level, and what they were wearing.
---@return table  list of lines
local function DifferenceLines(comparison)
    local lines = {}

    if comparison.levels then
        table.insert(
            lines,
            ("Level %d before, level %d now."):format(
                comparison.levels.before,
                comparison.levels.after
            )
        )
    end

    if not comparison.gearKnown then
        table.insert(
            lines,
            Kit.Colored("No note of the gear worn was kept for one of these.", Kit.MUTED)
        )
    elseif #comparison.gear == 0 then
        table.insert(lines, "Same gear in both.")
    end

    for index, change in ipairs(comparison.gear) do
        if index > MAX_GEAR_LINES then
            table.insert(lines, ("...and %d more."):format(#comparison.gear - MAX_GEAR_LINES))
            break
        end
        table.insert(
            lines,
            ("%s: %s  >  %s"):format(
                change.slot,
                change.before or "nothing",
                change.after or "nothing"
            )
        )
    end

    return lines
end

-- Laying out ---------------------------------------------------------------------

--- Text that runs on to as many lines as it needs.
local function Paragraph(parent, font)
    local text = Kit.Text(parent, font)
    text:SetWordWrap(true)
    text:SetJustifyV("TOP")
    text:SetSpacing(3)
    return text
end

--- Notes a piece of the page, so that a fill can start by clearing every
--- piece away and then show only the ones it places.
local function Piece(card, piece)
    table.insert(card.pieces, piece)
    return piece
end

--- Puts a piece on the page, under whatever was placed before it.
---@param layout table  { page, width, y }, y being how far down the page
---                     is taken so far
---@param gap number  space to leave above the piece
---@param height number|nil  the piece's own height unless given
local function Place(layout, piece, gap, height)
    layout.y = layout.y + gap

    piece:ClearAllPoints()
    piece:SetPoint("TOPLEFT", layout.page, "TOPLEFT", 0, -layout.y)
    piece:SetWidth(layout.width)
    piece:Show()

    layout.y = layout.y + (height or piece:GetHeight())
end

--- Places text that may wrap. It has to be told its width before its
--- words, or there's nothing to wrap to and nothing true to measure.
local function PlaceText(layout, text, gap, words)
    text:SetWidth(layout.width)
    text:SetText(words)
    Place(layout, text, gap, text:GetStringHeight())
end

--- The width there is for the page.
local function PageWidth(card)
    local width = card.scroll:GetWidth()
    return width > 0 and width or USUAL_WIDTH
end

--- True if two lists hold the same fights in the same order.
local function SameFights(a, b)
    if not a or #a ~= #b then
        return false
    end
    for index, fight in ipairs(a) do
        if b[index] ~= fight then
            return false
        end
    end
    return true
end

-- The note --------------------------------------------------------------------

--- Saves what's in the note box to the fight or recording it's about.
local function KeepNote(box)
    local about = box.about
    if not about then
        return
    end

    local note = ns.CleanNote(box:GetText())
    if note ~= about.note then
        about.note = note
        ns.Publish("FIGHTS_CHANGED")
    end
end

--- Points the note box at a fight or a recording, or hides it.
---@param about table|nil  the fight or recording the note belongs to
local function ShowNote(box, about)
    -- A redraw while the player is halfway through typing leaves it be.
    if box.about == about and box:HasFocus() then
        return
    end

    -- Clicking another fight doesn't take the cursor out of the box, so
    -- what was typed is kept here before the box moves on.
    if box:HasFocus() then
        KeepNote(box)
        box:ClearFocus()
    end

    box.about = about
    box:SetText(about and about.note or "")
    box:SetCursorPosition(0)
    box:SetShown(about ~= nil)
end

local function CreateNoteBox(card)
    local box = CreateFrame("EditBox", nil, card, "InputBoxInstructionsTemplate")
    box:SetHeight(NOTE_HEIGHT)

    -- The template draws its border a little to the left of the box.
    box:SetPoint("TOPLEFT", MARGIN + 5, -NOTE_TOP)
    box:SetPoint("TOPRIGHT", -MARGIN, -NOTE_TOP)

    -- Opening the window mustn't swallow the player's movement keys.
    box:SetAutoFocus(false)
    box:SetMaxLetters(ns.NOTE_LENGTH)
    box:SetTextInsets(2, 6, 0, 0)

    -- The template leaves room on the left for a search icon we don't have.
    box.Instructions:SetText(NOTE_PROMPT)
    box.Instructions:ClearAllPoints()
    box.Instructions:SetPoint("TOPLEFT", box, "TOPLEFT", 2, 0)
    box.Instructions:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 0)

    box:SetScript("OnEnterPressed", function(self)
        KeepNote(self)
        self:ClearFocus()
    end)

    -- Escape backs out: the note goes back to what it was.
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(self.about and self.about.note or "")
        self:ClearFocus()
    end)

    -- Hooked, not set, so the template's own tidying up still runs.
    box:HookScript("OnEditFocusLost", KeepNote)

    box:Hide()
    return box
end

-- The bars ----------------------------------------------------------------------

local function AddFigure(label, figure)
    GameTooltip:AddDoubleLine(label, figure, Kit.GOLD[1], Kit.GOLD[2], Kit.GOLD[3], 1, 1, 1)
end

--- The game's own tooltip for the ability, with our figures underneath.
local function ShowAbilityTooltip(bar)
    local ability = bar.ability
    if not ability then
        return
    end

    GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
    if ability.id and ability.id ~= 0 then
        GameTooltip:SetSpellByID(ability.id)
    else
        GameTooltip:SetText(ability.name)
    end

    GameTooltip:AddLine(" ")
    AddFigure("Damage", ("%s (%s)"):format(ns.Number(ability.damage), ns.Percent(ability.share)))
    if ability.perCast then
        AddFigure(
            ("Used %d %s"):format(ability.casts, ability.casts == 1 and "time" or "times"),
            ns.Rate(ability.perCast) .. " damage a use"
        )
    end
    if ability.perCost then
        AddFigure(
            ("Costs %d %s"):format(ability.cost, ns.Summary.PowerWord(ability.power)),
            ("%.1f damage a point"):format(ability.perCost)
        )
    end

    -- Which blow belongs to which use is worked out, not reported, so
    -- this is worded as the estimate it is.
    if ability.landed then
        AddFigure(
            "Landed, as far as could be traced",
            ("about %d of %d"):format(ability.landed, ability.landed + ability.failed)
        )
    end
    GameTooltip:Show()
end

local function CreateBar(page)
    local bar = Kit.Bar(page)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", ShowAbilityTooltip)
    bar:SetScript("OnLeave", GameTooltip_Hide)
    return bar
end

--- Every ability from `first` on, added up into one line.
local function EverythingElse(summary, first)
    local rest = { name = "Everything else", kind = "other", damage = 0 }
    for index = first, #summary.abilities do
        rest.damage = rest.damage + summary.abilities[index].damage
    end
    rest.share = rest.damage / summary.damage
    return rest
end

---@param biggest number  the damage of the biggest ability, which gets a
---                       full bar; the others are drawn against it
---@param change number|nil  how its damage a second moved since "before"
local function FillBar(bar, ability, biggest, change)
    bar.ability = ability

    local name = ability.name
    if ability.rank then
        name = name .. "  " .. Kit.Colored(ability.rank, Kit.MUTED)
    end

    -- Damage and share for everything. For skills, what each use did and
    -- what each point of mana or energy bought.
    local figures = ("%s  %s"):format(ns.Number(ability.damage), ns.Percent(ability.share))
    if ability.perCast then
        local perUse = ns.Rate(ability.perCast) .. " a use"
        figures = figures .. "  " .. Kit.Colored(perUse, Kit.MUTED)
    end
    if ability.perCost then
        local perPoint = ("%.1f per %s"):format(
            ability.perCost,
            ns.Summary.PowerWord(ability.power)
        )
        figures = figures .. "  " .. Kit.Colored(perPoint, Kit.MUTED)
    end
    if change then
        figures = figures .. "  " .. Kit.ChangeText(change)
    end

    local share = biggest > 0 and math.min(ability.damage / biggest, 1) or 0
    local color = Kit.KIND_COLORS[ability.kind] or Kit.KIND_COLORS.other
    bar:Set(ability.icon, name, figures, share, color)
end

-- Building ---------------------------------------------------------------------

--- Builds an empty card inside `parent`.
function Card.Create(parent)
    local card = CreateFrame("Frame", nil, parent)
    card.pieces = {}

    -- Fixed at the top: what's selected, and a note about it.
    card.title = Kit.Text(card, "GameFontNormalLarge")
    card.title:SetPoint("TOPLEFT", MARGIN, -8)
    card.title:SetPoint("TOPRIGHT", -MARGIN, -8)

    card.subtitle = Kit.Text(card, "GameFontHighlightSmall")
    card.subtitle:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
    card.subtitle:SetPoint("TOPRIGHT", card.title, "BOTTOMRIGHT", 0, -3)
    card.subtitle:SetTextColor(unpack(Kit.MUTED))

    card.note = CreateNoteBox(card)

    -- Shown in place of everything else when there's nothing to analyse.
    card.empty = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    card.empty:SetPoint("CENTER", 0, -60)
    card.empty:SetWidth(340)
    card.empty:SetTextColor(unpack(Kit.MUTED))

    card.logo = card:CreateTexture(nil, "ARTWORK")
    card.logo:SetTexture(LOGO)
    card.logo:SetSize(320, 160)
    card.logo:SetPoint("BOTTOM", card.empty, "TOP", 0, 6)

    -- The rest scrolls. The template brings its own scroll bar, which
    -- only needs telling to stay out of sight while everything fits.
    card.scroll = CreateFrame("ScrollFrame", nil, card, "ScrollFrameTemplate")
    card.scroll:SetPoint("TOPLEFT", MARGIN, -PAGE_TOP)
    card.scroll:SetPoint("BOTTOMRIGHT", -SCROLL_BAR_ROOM, 8)
    card.scroll.ScrollBar:SetHideIfUnscrollable(true)

    local page = CreateFrame("Frame", nil, card.scroll)
    page:SetSize(USUAL_WIDTH, 1)
    card.scroll:SetScrollChild(page)
    card.page = page

    card.tiles = {}
    for index = 1, 4 do
        card.tiles[index] = Piece(card, Kit.Tile(page))
    end

    card.counts = Piece(card, Paragraph(page, "GameFontHighlightSmall"))

    card.sourcesHeading = Piece(card, Kit.Header(page, "Where the damage came from"))
    card.bars = {}
    for index = 1, MAX_BARS do
        card.bars[index] = Piece(card, CreateBar(page))
    end
    card.kinds = Piece(card, Kit.Text(page, "GameFontHighlightSmall"))
    card.split = Piece(card, Paragraph(page, "GameFontHighlightSmall"))
    card.split:SetTextColor(unpack(Kit.MUTED))

    card.pressedHeading = Piece(card, Kit.Header(page, "What you pressed"))
    card.timeline = Piece(card, ns.Timeline.Create(page))
    card.pressed = Piece(card, Paragraph(page, "GameFontHighlight"))

    -- Findings and differences come a few at a time, so their rows are
    -- made as they're first needed.
    card.findingsHeading = Piece(card, Kit.Header(page, "What stands out"))
    card.findings = {}

    card.differencesHeading = Piece(card, Kit.Header(page, "What was different"))
    card.differences = {}

    return card
end

-- Filling ------------------------------------------------------------------------

--- The headline figures side by side, and the count of blows under them.
local function PlaceHeadlines(card, layout, summary, comparison)
    local width = (layout.width - (#card.tiles - 1) * TILE_GAP) / #card.tiles
    for index, tile in ipairs(card.tiles) do
        local left = (index - 1) * (width + TILE_GAP)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", layout.page, "TOPLEFT", left, -layout.y)
        tile:SetWidth(width)
        tile:Show()
    end
    layout.y = layout.y + card.tiles[1]:GetHeight()

    card.tiles[1]:Set(
        "Damage a second",
        ns.Rate(summary.dps),
        comparison and Kit.ChangeText(comparison.dps.change),
        comparison and comparison.dps.change
    )
    card.tiles[2]:Set(
        summary.fights == 1 and "Damage" or "Damage a fight",
        ns.Number(summary.damage / summary.fights),
        comparison and Kit.ChangeText(comparison.perFight.change),
        comparison and comparison.perFight.change
    )
    card.tiles[3]:Set("Time in battle", ns.Duration(summary.seconds))

    -- A rate that's already a percentage moves in points, not per cent.
    card.tiles[4]:Set(
        "Critical hits",
        summary.critRate and ns.Percent(summary.critRate) or "-",
        comparison and Kit.PointsText(comparison.critRate.points),
        comparison and comparison.critRate.points
    )

    local counts = CountsText(summary)
    local blows = BlowsText(summary)
    if blows then
        counts = counts .. "\n" .. blows
    end
    PlaceText(layout, card.counts, LINE_GAP, counts)
end

--- A bar for each of the biggest abilities, and under them the split by
--- kind of source.
local function PlaceSources(card, layout, summary, comparison)
    Place(layout, card.sourcesHeading, SECTION_GAP)

    local abilities = summary.abilities
    local biggest = abilities[1] and abilities[1].damage or 0
    local gap = HEADING_GAP

    for index, bar in ipairs(card.bars) do
        local ability = abilities[index]
        local change

        -- Any abilities beyond the last bar share it.
        if index == MAX_BARS and #abilities > MAX_BARS then
            ability = EverythingElse(summary, MAX_BARS)
        elseif ability and comparison then
            local pair = comparison.abilities[ability.kind .. ability.id]
            change = pair and pair.change
        end

        if ability then
            FillBar(bar, ability, biggest, change)
            Place(layout, bar, gap)
            gap = BAR_GAP
        else
            bar.ability = nil
        end
    end

    card.kinds:SetText(KindsText(summary))
    Place(layout, card.kinds, HEADING_GAP, card.kinds:GetStringHeight())

    local split = SplitText(summary)
    if split then
        PlaceText(layout, card.split, LINE_GAP, split)
    end
end

--- What was pressed: move by move for one fight, summed up for several.
local function PlacePressed(card, layout, summary, fights)
    if summary.fights == 1 then
        -- The timeline hides itself if this fight's moves weren't kept.
        card.timeline:SetWidth(layout.width)
        card.timeline:Set(fights[1])
        if card.timeline:IsShown() then
            Place(layout, card.pressedHeading, SECTION_GAP)
            Place(layout, card.timeline, HEADING_GAP)
        end
    elseif summary.watched > 0 then
        Place(layout, card.pressedHeading, SECTION_GAP)
        PlaceText(layout, card.pressed, HEADING_GAP, PressedText(summary))
    end
end

local function CreateFindingRow(card)
    local row = Piece(card, CreateFrame("Frame", nil, card.page))

    row.icon = Kit.Icon(row, FINDING_ICON)
    row.icon:SetPoint("TOPLEFT")

    row.text = Paragraph(row, "GameFontHighlight")
    row.text:SetPoint("TOPLEFT", FINDING_ICON + 8, -1)

    return row
end

--- One row per finding: a picture for the kind of news it is, then the
--- sentence.
local function PlaceFindings(card, layout, findings)
    if #findings == 0 then
        return
    end
    Place(layout, card.findingsHeading, SECTION_GAP)

    for index, finding in ipairs(findings) do
        local row = card.findings[index]
        if not row then
            row = CreateFindingRow(card)
            card.findings[index] = row
        end

        Kit.SetIcon(row.icon, finding.kind)
        row.text:SetWidth(layout.width - FINDING_ICON - 8)
        row.text:SetText(finding.text)

        local height = math.max(FINDING_ICON, row.text:GetStringHeight() + 1)
        row:SetHeight(height)
        Place(layout, row, FINDING_GAP)
    end
end

local function PlaceDifferences(card, layout, comparison)
    Place(layout, card.differencesHeading, SECTION_GAP)

    local gap = HEADING_GAP
    for index, line in ipairs(DifferenceLines(comparison)) do
        local text = card.differences[index]
        if not text then
            text = Piece(card, Paragraph(card.page, "GameFontHighlight"))
            card.differences[index] = text
        end

        PlaceText(layout, text, gap, line)
        gap = LINE_GAP
    end
end

--- The card with nothing selected: the logo, and a line on what to do.
local function ShowEmpty(card, heading)
    card.title:SetText("")
    card.subtitle:SetText("")
    ShowNote(card.note, nil)
    card.scroll:Hide()
    card.shown = nil

    card.empty:SetText(heading.empty)
    card.empty:Show()
    card.logo:Show()
end

--- Fills the card in.
---@param card table  from Card.Create
---@param fights table  the fights to analyse; may be empty
---@param before table|nil  the fights to compare them with, if any
---@param heading table  { title, subtitle, empty, recording }: what to call
---                      this set, what to say when there's nothing in it,
---                      and the recording when it's exactly one whole one
function Card.Fill(card, fights, before, heading)
    local summary = ns.Summary.Of(fights)
    if summary.fights == 0 then
        ShowEmpty(card, heading)
        return
    end

    card.empty:Hide()
    card.logo:Hide()
    card.title:SetText(heading.title)
    card.subtitle:SetText(heading.subtitle)

    -- A note belongs to one fight or to one recording. Any other
    -- selection is just a selection, with nowhere to keep one.
    local noted = summary.fights == 1 and fights[1] or heading.recording
    ShowNote(card.note, noted)

    card.scroll:SetPoint("TOPLEFT", MARGIN, -(noted and PAGE_TOP_WITH_NOTE or PAGE_TOP))
    card.scroll:Show()

    for _, piece in ipairs(card.pieces) do
        piece:Hide()
    end

    local comparison = before and ns.Compare.Between(before, fights)
    local layout = { page = card.page, width = PageWidth(card), y = 0 }

    PlaceHeadlines(card, layout, summary, comparison)
    PlaceSources(card, layout, summary, comparison)
    PlacePressed(card, layout, summary, fights)
    PlaceFindings(card, layout, ns.Findings.For(summary, comparison))
    if comparison then
        PlaceDifferences(card, layout, comparison)
    end

    card.page:SetSize(layout.width, layout.y + MARGIN)

    -- A new selection starts at the top. A redraw of the same one, as when
    -- a fight ends while the page is open, leaves the reader where they were.
    if not SameFights(card.shown, fights) then
        card.scroll:SetVerticalScroll(0)
    end
    card.shown = fights
end
