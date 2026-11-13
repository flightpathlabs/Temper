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

--- A section heading: a title with the game's ruled line under it.
---@return table frame  24 high; anchor its left and right edges
function Kit.Header(parent, title)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(24)

    header.title = Kit.Text(header, "GameFontNormal")
    header.title:SetPoint("TOPLEFT", 0, -2)
    header.title:SetText(title)

    header.rule = header:CreateTexture(nil, "ARTWORK")
    header.rule:SetAtlas("Options_HorizontalDivider")
    header.rule:SetHeight(2)
    header.rule:SetPoint("BOTTOMLEFT", 0, 1)
    header.rule:SetPoint("BOTTOMRIGHT", 0, 1)
    header.rule:SetAlpha(0.6)

    return header
end

--- A headline figure: what it is, the figure in large type, and how it
--- changed, with an arrow.
---@return table tile  56 high; call tile:Set(name, value, changeText, change)
function Kit.Tile(parent)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetHeight(56)

    tile.name = Kit.Text(tile, "GameFontDisableSmall")
    tile.name:SetPoint("TOPLEFT")

    tile.value = Kit.Text(tile, "GameFontNormalHuge")
    tile.value:SetPoint("TOPLEFT", tile.name, "BOTTOMLEFT", 0, -3)

    tile.arrow = Kit.Icon(tile, 12)
    tile.arrow:SetPoint("TOPLEFT", tile.value, "BOTTOMLEFT", 0, -3)
    tile.arrow:Hide()

    tile.change = Kit.Text(tile, "GameFontHighlightSmall")
    tile.change:SetPoint("LEFT", tile.arrow, "RIGHT", 3, 0)

    --- @param changeText string|nil  from ChangeText or PointsText
    --- @param change number|nil  the figure behind it, for the arrow
    function tile:Set(name, value, changeText, change)
        self.name:SetText(name)
        self.value:SetText(value)
        self.change:SetText(changeText or "")
        Kit.SetArrow(self.arrow, changeText and change or nil)
    end

    return tile
end

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
