local _, ns = ...

-- The parts every screen is built from.
--
-- Temper should look like something Blizzard shipped, so everything here
-- is one of the game's own pieces: its fonts, its icons, the bars from its
-- damage meter, its dialog for "are you sure". Each name below was found
-- in use in the Forever client's own interface code. Keeping them in one
-- file means a screen never spells an atlas name itself, and a piece that
-- turns out not to exist on some client is fixed in one place.

local Kit = {}
ns.Kit = Kit

-- Colours ------------------------------------------------------------------

Kit.MUTED = { 0.62, 0.62, 0.62 }
Kit.GOLD = { 1, 0.82, 0 }
Kit.GOOD = { 0.25, 0.88, 0.25 }
Kit.BAD = { 1, 0.31, 0.25 }
Kit.BLUE = { 0.35, 0.65, 1 }

-- One colour per kind of damage source, so bars can be read at a glance.
Kit.KIND_COLORS = {
    skill = { 0.25, 0.55, 0.95 },
    auto = { 0.75, 0.75, 0.7 },
    pet = { 0.35, 0.8, 0.4 },
    other = { 0.75, 0.45, 0.9 },
}

--- Wraps text in a colour.
---@param color table  { r, g, b }
function Kit.Colored(text, color)
    return ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, text)
end

-- Icons --------------------------------------------------------------------

-- Small pictures by what they mean. An entry is an atlas name, or a file
-- path where the game keeps that one as a loose texture.
local ICONS = {
    good = { atlas = "common-icon-checkmark" },
    bad = { atlas = "common-icon-redx" },
    warning = { file = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew" },
    tip = { file = "Interface\\common\\help-i" },
    up = { atlas = "bags-greenarrow" },
    clock = { atlas = "auctionhouse-icon-clock" },
    best = { atlas = "auctionhouse-icon-favorite" },
    delete = { atlas = "common-icon-delete" },
    combat = { atlas = "UI-HUD-UnitFrame-Player-CombatIcon" },
    recording = { file = "Interface\\FriendsFrame\\StatusIcon-DnD" },
    ready = { file = "Interface\\FriendsFrame\\StatusIcon-Online" },
    waiting = { file = "Interface\\FriendsFrame\\StatusIcon-Away" },
    unknown = { file = "Interface\\Icons\\INV_Misc_QuestionMark" },
}

--- Points a texture at one of the icons above.
---@param kind string  a key of ICONS
function Kit.SetIcon(texture, kind)
    local icon = ICONS[kind] or ICONS.unknown
    texture:SetRotation(0)
    texture:SetDesaturated(false)
    texture:SetVertexColor(1, 1, 1)

    if icon.atlas then
        texture:SetAtlas(icon.atlas)
    else
        texture:SetTexture(icon.file)
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

--- A new icon.
---@param size number  width and height
---@param kind string|nil  a key of ICONS, if it's known yet
function Kit.Icon(parent, size, kind)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    texture:SetSize(size, size)
    if kind then
        Kit.SetIcon(texture, kind)
    end
    return texture
end

--- Shows a spell's own icon, trimmed the way the game trims them to lose
--- the border drawn into every icon.
---@param icon number|string|nil  a texture, as saved with a fight
function Kit.SetSpellIcon(texture, icon)
    texture:SetRotation(0)
    texture:SetDesaturated(false)
    texture:SetVertexColor(1, 1, 1)
    texture:SetTexture(icon or ICONS.unknown.file)
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
end

--- Turns a texture into an arrow for "better" or "worse": green and up,
--- red and down. Hidden when there's nothing to say.
---@param change number|nil  positive for better
function Kit.SetArrow(texture, change)
    if not change or math.abs(change) < 0.005 then
        texture:Hide()
        return
    end

    -- The game has a green up arrow and no red down one, so the down
    -- arrow is the same picture turned over and tinted.
    texture:SetAtlas(ICONS.up.atlas)
    if change > 0 then
        texture:SetRotation(0)
        texture:SetDesaturated(false)
        texture:SetVertexColor(1, 1, 1)
    else
        texture:SetRotation(math.pi)
        texture:SetDesaturated(true)
        texture:SetVertexColor(Kit.BAD[1], Kit.BAD[2], Kit.BAD[3])
    end
    texture:Show()
end

-- Text ---------------------------------------------------------------------

--- A piece of text in one of the game's fonts.
---@param font string  e.g. "GameFontHighlightSmall"
---@param justify string|nil  "LEFT" unless given
function Kit.Text(parent, font, justify)
    local text = parent:CreateFontString(nil, "ARTWORK", font)
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    return text
end

--- "+12%" in green, "-8%" in red, nothing when there's no comparison.
---@param change number|nil  a fraction: 0.12 for twelve per cent up
function Kit.ChangeText(change)
    if not change then
        return ""
    end

    local percent = math.floor(math.abs(change) * 100 + 0.5)
    if percent == 0 then
        return Kit.Colored("no change", Kit.MUTED)
    elseif change > 0 then
        return Kit.Colored(("+%d%%"):format(percent), Kit.GOOD)
    end
    return Kit.Colored(("-%d%%"):format(percent), Kit.BAD)
end

--- The same for a rate that's already a percentage: "+2 points", so that
--- going from 10% to 12% doesn't read as "+20%".
---@param points number|nil  0.02 for two points up
function Kit.PointsText(points)
    if not points then
        return ""
    end

    local whole = math.floor(math.abs(points) * 100 + 0.5)
    if whole == 0 then
        return Kit.Colored("no change", Kit.MUTED)
    end

    local text = ("%s%d %s"):format(
        points > 0 and "+" or "-",
        whole,
        whole == 1 and "point" or "points"
    )
    return Kit.Colored(text, points > 0 and Kit.GOOD or Kit.BAD)
end

-- Bigger pieces ----------------------------------------------------------------

--- A bar in the style of the game's own damage meter: an icon, then a
--- bar with a name on the left and figures on the right.
---@return table row  22 high; call row:Set(icon, name, figures, share, color)
function Kit.Bar(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT")

    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMRIGHT")
    bar:SetStatusBarTexture("UI-HUD-CoolDownManager-Bar")
    bar:SetMinMaxValues(0, 1)
    row.bar = bar

    local backing = bar:CreateTexture(nil, "BACKGROUND")
    backing:SetAtlas("ui-damagemeters-bar-shadowbg")
    backing:SetAllPoints()

    row.figures = Kit.Text(bar, "GameFontHighlightSmall", "RIGHT")
    row.figures:SetPoint("RIGHT", -6, 0)

    row.name = Kit.Text(bar, "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetPoint("RIGHT", row.figures, "LEFT", -8, 0)

    --- @param icon number|string|nil  a spell's texture
    --- @param share number  how full the bar is, 0 to 1
    --- @param color table  { r, g, b }
    function row:Set(icon, name, figures, share, color)
        Kit.SetSpellIcon(self.icon, icon)
        self.name:SetText(name)
        self.figures:SetText(figures)
        self.bar:SetValue(share)
        self.bar:GetStatusBarTexture():SetVertexColor(color[1], color[2], color[3])
        self:Show()
    end

    return row
end

--- Dresses a list row the way the auction house dresses its own: the
--- game's glow under the mouse, and its band across a row that's chosen.
--- Call row.chosen:SetShown(...) to mark it.
function Kit.DressRow(row)
    -- Both are glows, meant to be added to what's under them. Drawn
    -- plainly they're solid bands, and the one under the mouse sits above
    -- the row's text and hides it.
    row.chosen = row:CreateTexture(nil, "BACKGROUND")
    row.chosen:SetAtlas("auctionhouse-ui-row-select")
    row.chosen:SetBlendMode("ADD")
    row.chosen:SetAlpha(0.7)
    row.chosen:SetAllPoints()
    row.chosen:Hide()

    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAtlas("auctionhouse-ui-row-highlight")
    row.hover:SetBlendMode("ADD")
    row.hover:SetAlpha(0.5)
    row.hover:SetAllPoints()
end

--- A sunken panel in the game's style, for setting a list apart from the
--- page beside it. Anchor it around whatever it should frame.
function Kit.Inset(parent)
    return CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
end

--- A small "i" that explains something when the mouse is over it, in
--- place of a paragraph of instructions that's always on show.
---@param lines table  list of strings
function Kit.HelpButton(parent, title, lines)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(18, 18)

    local icon = Kit.Icon(button, 18, "tip")
    icon:SetAllPoints()

    Kit.Tooltip(button, title, function()
        return lines
    end)
    return button
end

--- One of the game's ordinary buttons.
function Kit.Button(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

--- A small cog that opens Temper's options, the one the game uses for
--- settings on its own panels.
---@param size number  how many pixels across
function Kit.OptionsButton(parent, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)

    local cog = button:CreateTexture(nil, "ARTWORK")
    cog:SetAtlas("questlog-icon-setting")
    cog:SetAllPoints()

    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAtlas("questlog-icon-setting")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.4)
    glow:SetAllPoints()

    button:SetScript("OnClick", function()
        ns.OpenOptions()
    end)
    Kit.Tooltip(button, "Options", function()
        return { "How your damage numbers look, and what Temper shows on screen." }
    end)
    return button
end

--- Gives a frame a tooltip: a title and any number of lines under it.
---@param lines fun(): table|nil  called each time, so the words can change;
---                               returns a list of strings
function Kit.Tooltip(frame, title, lines)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        for _, line in ipairs(lines and lines() or {}) do
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- "Are you sure?" ---------------------------------------------------------------

local CONFIRM = "TEMPER_CONFIRM"

StaticPopupDialogs[CONFIRM] = {
    text = "%s",
    button1 = "Yes",
    button2 = "Cancel",
    OnAccept = function(_, onAccept)
        onAccept()
    end,
    hideOnEscape = true,
    timeout = 0,
    whileDead = true,
    showAlert = true,
}

--- Asks the player to confirm something that can't be undone, in the
--- game's own dialog.
---@param question string
---@param onAccept fun()  called if they say yes
function Kit.Confirm(question, onAccept)
    StaticPopup_Show(CONFIRM, question, nil, onAccept)
end

-- Boxes ------------------------------------------------------------------------

-- A box sets one part of a page apart without shouting about it: a shade
-- darker than what's round it, with a hairline for an edge. A page of
-- them already sits inside a window's own frame, so anything heavier (the
-- game's tooltip border, say) would be frames within frames.
local BOX_FILL = { 0, 0, 0, 0.25 }
local BOX_EDGE = { 1, 1, 1, 0.14 }

-- The band a section's title sits in: a touch lighter than the box, and
-- this tall with the rule under it.
local BAND_FILL = { 1, 1, 1, 0.04 }
local BAND_HEIGHT = 24

-- The space between a section's edge and what's in it, and how far down
-- a section its contents start: under the band, and padded.
Kit.SECTION_PADDING = 10
Kit.SECTION_TOP = BAND_HEIGHT + Kit.SECTION_PADDING

--- A hairline in the colour boxes are edged with, for dividing up what's
--- inside one. Give it a place, and a width or a height of 1.
function Kit.Rule(parent)
    local rule = parent:CreateTexture(nil, "BORDER")
    rule:SetColorTexture(unpack(BOX_EDGE))
    return rule
end

--- A plain box: the fill and the edge, with nothing in it.
---@return table box  give it a place and a size
function Kit.Box(parent)
    local box = CreateFrame("Frame", nil, parent)

    local fill = box:CreateTexture(nil, "BACKGROUND")
    fill:SetColorTexture(unpack(BOX_FILL))
    fill:SetAllPoints()

    local top = Kit.Rule(box)
    top:SetHeight(1)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")

    local bottom = Kit.Rule(box)
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")

    -- The sides run between the other two, not over them. The edge is
    -- see-through, so where two lines crossed, the corner would show
    -- brighter than the rest.
    local left = Kit.Rule(box)
    left:SetWidth(1)
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT")

    local right = Kit.Rule(box)
    right:SetWidth(1)
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")

    return box
end

--- One part of a page: a box with its title in a band along the top, in
--- the gold the game heads its own panels with.
---@return table section  give it a place, a width and a height. What goes
---                       in it starts Kit.SECTION_TOP down, and keeps
---                       Kit.SECTION_PADDING in from either side
function Kit.Section(parent, title)
    local section = Kit.Box(parent)

    -- The band and its rule stay inside the box's edge, for the same
    -- reason the sides of the box stop short of its corners.
    local band = section:CreateTexture(nil, "BORDER")
    band:SetColorTexture(unpack(BAND_FILL))
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", -1, -1)
    band:SetHeight(BAND_HEIGHT - 2)

    local rule = Kit.Rule(section)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", band, "BOTTOMLEFT")
    rule:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT")

    section.title = Kit.Text(section, "GameFontNormal")
    section.title:SetPoint("LEFT", band, "LEFT", Kit.SECTION_PADDING - 1, 0)
    section.title:SetPoint("RIGHT", band, "RIGHT", 1 - Kit.SECTION_PADDING, 0)
    section.title:SetText(title)

    return section
end

-- Pages -------------------------------------------------------------------------

-- Every page in the window is built from the same pieces and laid out the
-- same way, so they read as one. A page that scrolls can't
-- size itself from its anchors, and text only wraps once it's told how
-- wide it may be. So a page is laid out by hand each time it's filled:
-- every piece is given a width and a place under the piece before it, and
-- the page ends where the last piece does.
--
-- A layout is a table that keeps track of that: { frame, left, width, y }.
-- The frame is what the pieces are pinned to (the page, or one section of
-- it), left is how far in from its left edge they start, width is how wide
-- they are, and y is how far down it has been taken so far.

-- Space between one section of a page and the next.
Kit.SECTION_GAP = 8

--- Text that runs on to as many lines as it needs. Give it a width, or
--- anchor its left and right edges, so it knows where to wrap.
function Kit.Paragraph(parent, font, justify)
    local text = Kit.Text(parent, font, justify)
    text:SetWordWrap(true)
    text:SetJustifyV("TOP")
    text:SetSpacing(3)
    return text
end

--- Puts a piece in its place, under whatever was placed before it.
---@param layout table  see above
---@param gap number  space to leave above the piece
---@param height number|nil  the piece's own height unless given
function Kit.Place(layout, piece, gap, height)
    layout.y = layout.y + gap

    piece:ClearAllPoints()
    piece:SetPoint("TOPLEFT", layout.frame, "TOPLEFT", layout.left, -layout.y)
    piece:SetWidth(layout.width)
    piece:Show()

    layout.y = layout.y + (height or piece:GetHeight())
end

--- Places text that may wrap. It has to be told its width before its
--- words, or there's nothing to wrap to and nothing true to measure.
function Kit.PlaceText(layout, text, gap, words)
    text:SetWidth(layout.width)
    text:SetText(words)
    Kit.Place(layout, text, gap, text:GetStringHeight())
end

--- A layout for what goes inside a section: pinned to the section, not
--- the page, so it doesn't matter that the section has no place yet.
---@param layout table  the layout the section will be placed with, for
---                     its width
function Kit.Inside(layout, section)
    return {
        frame = section,
        left = Kit.SECTION_PADDING,
        width = layout.width - 2 * Kit.SECTION_PADDING,
        y = Kit.SECTION_TOP,
    }
end

--- Puts a section on the page once everything in it has been placed. It
--- ends where the last thing in it did, plus the padding.
---@param inside table  the layout its contents were placed with
function Kit.PlaceSection(layout, section, inside)
    local height = inside.y + Kit.SECTION_PADDING
    section:SetHeight(height)

    -- Nothing comes before the first section, so it needs no gap.
    Kit.Place(layout, section, layout.y > 0 and Kit.SECTION_GAP or 0, height)
end

-- A row of figures ----------------------------------------------------------------

-- The row across the top of a page: one thin box of cells divided by
-- rules, each cell a small label with its figure under it and, when the
-- page is comparing, how the figure moved under that. Whatever lies behind
-- a figure waits in its tooltip.
--
-- Each figure is a table:
--   label, value        what it is, and the figure itself
--   title               what its tooltip is headed, when the label is too
--                       short to be one
--   figures             list of { label, figure } for the tooltip: what
--                       lies behind the figure. With none, and no note,
--                       there's no tooltip
--   note                a sentence to end the tooltip with, if any
--   changeText, change  when comparing: how it moved since the earlier
--                       fights, in words and as the number behind them

-- How tall the row is, and how tall when each figure has its change under
-- it. Down a cell go the label, the figure, and the change with its arrow.
-- The figures stand on a line of their own, so that the first, in its
-- larger type, lines up with the rest.
local STATS_HEIGHT = 44
local STATS_HEIGHT_COMPARING = 56
local STAT_PADDING = 9
local STAT_LABEL_TOP = 6
local STAT_FIGURE_FOOT = 36
local STAT_CHANGE_TOP = 38
local STAT_ARROW = 10
local STAT_ARROW_GAP = 3
local HERO_FONT = "GameFontNormalLarge"
local FIGURE_FONT = "GameFontHighlightMedium"

--- Adds a line to the tooltip being built: what a figure is on the left,
--- in gold, and the figure on the right.
function Kit.TooltipFigure(label, figure)
    GameTooltip:AddDoubleLine(label, figure, Kit.GOLD[1], Kit.GOLD[2], Kit.GOLD[3], 1, 1, 1)
end

--- What lies behind a figure, for those that have something behind them.
local function ShowStatTooltip(cell)
    local stat = cell.stat
    if not stat or not (stat.figures[1] or stat.note) then
        return
    end

    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:SetText(stat.title or stat.label, 1, 1, 1)
    for _, figure in ipairs(stat.figures) do
        Kit.TooltipFigure(figure[1], figure[2])
    end
    if stat.note then
        GameTooltip:AddLine(stat.note, Kit.MUTED[1], Kit.MUTED[2], Kit.MUTED[3], true)
    end
    GameTooltip:Show()
end

--- One cell of the row: a small label, the figure under it, and under
--- that, when comparing, how the figure moved.
---@param first boolean  true for the cell at the head of the row, which
---                      holds the one figure set larger and in gold
local function CreateStat(strip, first)
    local cell = CreateFrame("Frame", nil, strip)
    cell:EnableMouse(true)
    cell:SetScript("OnEnter", ShowStatTooltip)
    cell:SetScript("OnLeave", GameTooltip_Hide)

    cell.label = Kit.Text(cell, "GameFontDisableSmall")
    cell.label:SetPoint("TOPLEFT", STAT_PADDING, -STAT_LABEL_TOP)

    cell.value = Kit.Text(cell, first and HERO_FONT or FIGURE_FONT)
    cell.value:SetPoint("BOTTOMLEFT", cell, "TOPLEFT", STAT_PADDING, -STAT_FIGURE_FOOT)

    cell.arrow = Kit.Icon(cell, STAT_ARROW)
    cell.arrow:SetPoint("TOPLEFT", STAT_PADDING, -STAT_CHANGE_TOP)
    cell.arrow:Hide()

    cell.change = Kit.Text(cell, "GameFontHighlightSmall")

    -- A rule down the left of every cell but the first divides the row.
    -- It stops short of the strip's own edge, top and bottom.
    if not first then
        local rule = Kit.Rule(cell)
        rule:SetWidth(1)
        rule:SetPoint("TOPLEFT", 0, -1)
        rule:SetPoint("BOTTOMLEFT", 0, 1)
    end

    return cell
end

--- Shows a figure in a cell, and notes how wide the cell has to be for
--- all of it to be read.
local function FillStat(cell, stat)
    cell.stat = stat
    cell.label:SetText(stat.label)
    cell.value:SetText(stat.value)
    cell.change:SetText(stat.changeText or "")
    Kit.SetArrow(cell.arrow, stat.changeText and stat.change or nil)

    -- The words about the change come after the arrow. With no arrow
    -- ("no change") they start where it would have been.
    local indent = cell.arrow:IsShown() and STAT_ARROW + STAT_ARROW_GAP or 0
    cell.change:ClearAllPoints()
    cell.change:SetPoint(
        "LEFT",
        cell,
        "TOPLEFT",
        STAT_PADDING + indent,
        -(STAT_CHANGE_TOP + STAT_ARROW / 2)
    )

    local widest = math.max(
        cell.label:GetStringWidth(),
        cell.value:GetStringWidth(),
        cell.change:GetStringWidth() + indent
    )
    cell.needs = widest + 2 * STAT_PADDING

    -- A fight can end while the mouse is resting on a cell. Its tooltip
    -- is redrawn then, so it doesn't go on quoting the fight before.
    if GameTooltip:IsOwned(cell) then
        GameTooltip:Hide()
        ShowStatTooltip(cell)
    end
end

--- A row of figures with nothing in it yet.
---@return table strip  anchor its left and right edges, and call
---                     strip:Fill(stats, width, comparing)
function Kit.StatRow(parent)
    local strip = Kit.Box(parent)
    strip:SetHeight(STATS_HEIGHT)

    -- Cells are made as a fill first needs them.
    strip.cells = {}

    --- Fills the row and shares its width out among the figures. Each
    --- cell gets what its words need and an even share of whatever is
    --- left over. Were they ever to need more than there is, the same sum
    --- takes the difference back out of their padding.
    ---@param stats table  list of figures, left to right; at least one
    ---@param width number  of the whole row
    ---@param comparing boolean  true to leave room for each figure's change
    function strip:Fill(stats, width, comparing)
        local needed = 0
        for index, stat in ipairs(stats) do
            local cell = self.cells[index]
            if not cell then
                cell = CreateStat(self, index == 1)
                self.cells[index] = cell
            end

            FillStat(cell, stat)
            needed = needed + cell.needs
        end

        local spare = (width - needed) / #stats
        local left = 0
        for index, cell in ipairs(self.cells) do
            cell:SetShown(index <= #stats)
            if index <= #stats then
                local share = cell.needs + spare
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", self, "TOPLEFT", left, 0)
                cell:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", left, 0)
                cell:SetWidth(share)
                left = left + share
            end
        end

        self:SetHeight(comparing and STATS_HEIGHT_COMPARING or STATS_HEIGHT)
    end

    return strip
end

-- Findings ------------------------------------------------------------------------

-- A finding is a picture and a sentence, the sentence starting this far
-- in to clear the picture.
local FINDING_ICON = 16
local FINDING_INDENT = FINDING_ICON + 8
local FINDING_GAP = 8

local function CreateFindingRow(section)
    local row = CreateFrame("Frame", nil, section)

    row.icon = Kit.Icon(row, FINDING_ICON)
    row.icon:SetPoint("TOPLEFT")

    row.text = Kit.Paragraph(row, "GameFontHighlight")
    row.text:SetPoint("TOPLEFT", FINDING_INDENT, -1)

    return row
end

--- Places a row for each finding in a section: a picture for the kind of
--- news it is, then the sentence.
---@param inside table  the layout for the section's contents
---@param rows table  the rows made so far, which the page keeps from one
---                   fill to the next. Findings come a few at a time, so
---                   their rows are made as they're first needed
---@param findings table  list of { kind, text }
function Kit.PlaceFindings(inside, rows, findings)
    local gap = 0
    for index, finding in ipairs(findings) do
        local row = rows[index]
        if not row then
            row = CreateFindingRow(inside.frame)
            rows[index] = row
        end

        Kit.SetIcon(row.icon, finding.kind)
        row.text:SetWidth(inside.width - FINDING_INDENT)
        row.text:SetText(finding.text)
        row:SetHeight(math.max(FINDING_ICON, row.text:GetStringHeight() + 1))

        Kit.Place(inside, row, gap)
        gap = FINDING_GAP
    end

    -- Rows left over from a fill that had more to say are put away.
    for index = #findings + 1, #rows do
        rows[index]:Hide()
    end
end

-- Links -----------------------------------------------------------------------------

--- A few words that go somewhere when clicked. They're grey until the
--- mouse is on them, so they don't shout over what they sit beside.
function Kit.Link(parent, text, onClick)
    local link = CreateFrame("Button", nil, parent)

    local label = Kit.Text(link, "GameFontDisableSmall")
    label:SetPoint("CENTER")
    label:SetText(text)

    link:SetFontString(label)
    link:SetNormalFontObject("GameFontDisableSmall")
    link:SetHighlightFontObject("GameFontHighlightSmall")
    link:SetSize(label:GetStringWidth() + 8, 18)
    link:SetScript("OnClick", onClick)

    return link
end
