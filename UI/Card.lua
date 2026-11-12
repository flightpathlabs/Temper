local _, ns = ...

-- The analysis card: everything about one recording on one page.
--
-- Read top to bottom it answers, in order: how hard did I hit, where did
-- it come from, and (when a second recording is chosen to compare with)
-- what changed. The comparison isn't a separate screen. It shows up as a
-- small green or red figure beside each number it applies to.

local Card = {}
ns.Card = Card

local MAX_BARS = 6

-- More changed slots than this and the list is cut short, with a count.
local MAX_GEAR_LINES = 4
local BAR_HEIGHT = 20
local BAR_GAP = 3

local MUTED = { 0.6, 0.6, 0.6 }

-- One colour per kind of source, so the bars can be read at a glance.
local KIND_COLORS = {
    skill = { 0.25, 0.55, 0.95 },
    auto = { 0.75, 0.75, 0.7 },
    pet = { 0.35, 0.8, 0.4 },
    other = { 0.75, 0.45, 0.9 },
}

--- "+12%" in green, "-8%" in red, nothing when there's no comparison.
local function ChangeText(change)
    if not change then
        return ""
    end

    local percent = math.floor(math.abs(change) * 100 + 0.5)
    if percent == 0 then
        return "|cff999999no change|r"
    elseif change > 0 then
        return ("|cff40e040+%d%%|r"):format(percent)
    end
    return ("|cffff5040-%d%%|r"):format(percent)
end

--- The same for a rate that's already a percentage: "+2 points", so that
--- going from 10% to 12% doesn't read as "+20%".
local function PointsText(points)
    if not points then
        return ""
    end

    local whole = math.floor(math.abs(points) * 100 + 0.5)
    if whole == 0 then
        return "|cff999999no change|r"
    end

    local word = whole == 1 and "point" or "points"
    if points > 0 then
        return ("|cff40e040+%d %s|r"):format(whole, word)
    end
    return ("|cffff5040-%d %s|r"):format(whole, word)
end

local function Label(parent, font, justify)
    local label = parent:CreateFontString(nil, "ARTWORK", font)
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(false)
    return label
end

-- A headline figure: what it is, the figure, and how it changed.
local function CreateTile(parent)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetHeight(56)

    tile.name = Label(tile, "GameFontHighlightSmall")
    tile.name:SetPoint("TOPLEFT")
    tile.name:SetTextColor(unpack(MUTED))

    tile.value = Label(tile, "GameFontNormalHuge")
    tile.value:SetPoint("TOPLEFT", tile.name, "BOTTOMLEFT", 0, -3)

    tile.change = Label(tile, "GameFontHighlightSmall")
    tile.change:SetPoint("TOPLEFT", tile.value, "BOTTOMLEFT", 0, -2)

    return tile
end

local function FillTile(tile, name, value, changeText)
    tile.name:SetText(name)
    tile.value:SetText(value)
    tile.change:SetText(changeText or "")
end

-- One ability: a bar as long as its share of the damage, its name on the
-- bar, and the figures to the right.
local function CreateBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(BAR_HEIGHT)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)

    local backing = bar:CreateTexture(nil, "BACKGROUND")
    backing:SetAllPoints()
    backing:SetColorTexture(1, 1, 1, 0.06)

    bar.name = Label(bar, "GameFontHighlightSmall")
    bar.name:SetPoint("LEFT", 6, 0)

    bar.figures = Label(bar, "GameFontHighlightSmall", "RIGHT")
    bar.figures:SetPoint("RIGHT", -6, 0)
    bar.name:SetPoint("RIGHT", bar.figures, "LEFT", -8, 0)

    return bar
end

local function FillBar(bar, ability, biggest, change)
    local color = KIND_COLORS[ability.kind] or KIND_COLORS.other
    bar:SetStatusBarColor(color[1], color[2], color[3], 0.75)
    bar:SetValue(biggest > 0 and ability.damage / biggest or 0)
    bar.name:SetText(ability.name)

    local figures = ("%s  %s"):format(ns.Number(ability.damage), ns.Percent(ability.share))
    if ability.perCast then
        figures = ("%s  |cff999999%s a use|r"):format(figures, ns.Rate(ability.perCast))
    end
    if change then
        figures = figures .. "  " .. ChangeText(change)
    end
    bar.figures:SetText(figures)
    bar:Show()
end

--- Builds an empty card inside `parent`.
---@param onCompare fun(button)  called when "Compare with..." is clicked
function Card.Create(parent, onCompare)
    local card = CreateFrame("Frame", nil, parent)

    card.title = Label(card, "GameFontNormalLarge")
    card.title:SetPoint("TOPLEFT", 14, -12)

    card.subtitle = Label(card, "GameFontHighlightSmall")
    card.subtitle:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
    card.subtitle:SetTextColor(unpack(MUTED))

    card.compare = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    card.compare:SetSize(150, 22)
    card.compare:SetPoint("TOPRIGHT", -12, -12)
    card.compare:SetScript("OnClick", onCompare)

    -- Shown in place of everything else when there's nothing to analyse.
    card.empty = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    card.empty:SetPoint("CENTER")
    card.empty:SetWidth(320)
    card.empty:SetTextColor(unpack(MUTED))
    card.empty:SetText(
        "No fights on record yet.\n\nPress Record and fight something on your own. "
            .. "Press it again and the analysis appears here."
    )

    card.body = CreateFrame("Frame", nil, card)
    card.body:SetPoint("TOPLEFT", 14, -56)
    card.body:SetPoint("BOTTOMRIGHT", -14, 10)
    local body = card.body

    card.tiles = {}
    for index = 1, 4 do
        local tile = CreateTile(body)
        tile:SetPoint("TOPLEFT", body, "TOPLEFT", (index - 1) * 118, 0)
        tile:SetWidth(112)
        card.tiles[index] = tile
    end

    card.counts = Label(body, "GameFontHighlightSmall")
    card.counts:SetPoint("TOPLEFT", 0, -64)
    card.counts:SetPoint("RIGHT")

    card.best = Label(body, "GameFontHighlightSmall")
    card.best:SetPoint("TOPLEFT", card.counts, "BOTTOMLEFT", 0, -4)
    card.best:SetPoint("RIGHT")

    card.sourcesTitle = Label(body, "GameFontNormal")
    card.sourcesTitle:SetPoint("TOPLEFT", card.best, "BOTTOMLEFT", 0, -14)
    card.sourcesTitle:SetText("Where the damage came from")

    card.bars = {}
    for index = 1, MAX_BARS do
        local bar = CreateBar(body)
        local offset = -6 - (index - 1) * (BAR_HEIGHT + BAR_GAP)
        bar:SetPoint("TOPLEFT", card.sourcesTitle, "BOTTOMLEFT", 0, offset)
        bar:SetPoint("RIGHT")
        card.bars[index] = bar
    end

    -- Everything below the bars is plain text that moves up to meet them,
    -- however many there are.
    card.notes = body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    card.notes:SetJustifyH("LEFT")
    card.notes:SetJustifyV("TOP")
    card.notes:SetSpacing(4)
    card.notes:SetPoint("RIGHT")

    return card
end

--- The lines under the bars: damage by kind of source, the split between
--- fights against one enemy and several, and what changed.
local function Notes(recording, summary, baseline, comparison)
    local lines = {}

    local kinds = {}
    for _, kind in ipairs(ns.Sources.ORDER) do
        local damage = summary.kinds[kind] or 0
        if damage > 0 then
            table.insert(
                kinds,
                ("%s %s"):format(ns.Sources.LABELS[kind], ns.Percent(damage / summary.damage))
            )
        end
    end
    table.insert(lines, table.concat(kinds, "   "))

    if summary.several.fights > 0 and summary.single.fights > 0 then
        table.insert(
            lines,
            ("One enemy: %s a second over %d fights.   Several at once: %s over %d."):format(
                ns.Rate(summary.single.dps),
                summary.single.fights,
                ns.Rate(summary.several.dps),
                summary.several.fights
            )
        )
    elseif summary.several.fights > 0 then
        table.insert(lines, "Every fight here was against several enemies at once.")
    end

    if not comparison then
        return table.concat(lines, "\n")
    end

    table.insert(lines, "")
    table.insert(lines, ("|cffffd100What changed since %s|r"):format(ns.Recorder.Label(baseline)))

    if comparison.levels then
        table.insert(
            lines,
            ("Level %d then, level %d now."):format(
                comparison.levels.before,
                comparison.levels.after
            )
        )
    end

    if not baseline.gear or not recording.gear then
        table.insert(lines, "|cff999999Gear is only noted for recordings, not for recent fights.|r")
    elseif #comparison.gear == 0 then
        table.insert(lines, "Same gear in both.")
    else
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
    end

    return table.concat(lines, "\n")
end

--- Fills the card in.
---@param card table  from Card.Create
---@param recording table|nil  what to analyse
---@param baseline table|nil   what to compare it with, if anything
function Card.Fill(card, recording, baseline)
    local summary = recording and ns.Summary.Of(recording)
    if not summary or summary.fights == 0 then
        card.title:SetText(ns.TITLE)
        card.subtitle:SetText("")
        card.compare:Hide()
        card.body:Hide()
        card.empty:Show()
        return
    end

    card.empty:Hide()
    card.body:Show()
    card.compare:Show()
    card.compare:SetText(baseline and "Comparing..." or "Compare with...")

    local comparison = baseline and ns.Compare.Between(baseline, recording)

    card.title:SetText(ns.Recorder.Label(recording))

    local about = ("%d %s"):format(summary.fights, summary.fights == 1 and "fight" or "fights")
    if recording.startedAt then
        about = date("%d %b %H:%M", recording.startedAt) .. "   " .. about
    end
    if recording.level then
        about = about .. "   level " .. recording.level
    end
    if ns.Recorder.Open() == recording then
        about = about .. "   |cffff4040still recording|r"
    end
    card.subtitle:SetText(about)

    FillTile(
        card.tiles[1],
        "Damage a second",
        ns.Rate(summary.dps),
        comparison and ChangeText(comparison.dps.change)
    )
    FillTile(
        card.tiles[2],
        "Damage a fight",
        ns.Number(summary.damage / summary.fights),
        comparison and ChangeText(comparison.perFight.change)
    )
    FillTile(card.tiles[3], "Time in battle", ns.Duration(summary.seconds))
    FillTile(
        card.tiles[4],
        "Critical hits",
        summary.critRate and ns.Percent(summary.critRate) or "-",
        comparison and PointsText(comparison.critRate.points)
    )

    card.counts:SetText(
        ("%d hits, %d critical, %d glancing. %d missed or avoided."):format(
            summary.hits,
            summary.crits,
            summary.glancing,
            summary.avoided
        )
    )

    if summary.best then
        card.best:SetText(
            ("Hardest single use: %s for %s."):format(
                summary.best.name,
                ns.Number(summary.best.damage)
            )
        )
    else
        card.best:SetText("")
    end

    -- The biggest abilities get a bar each. Any beyond that share the last.
    local abilities = summary.abilities
    local biggest = abilities[1] and abilities[1].damage or 0
    local shown = math.min(#abilities, MAX_BARS)

    for index, bar in ipairs(card.bars) do
        local ability = abilities[index]
        if index == MAX_BARS and #abilities > MAX_BARS then
            local rest = { name = "Everything else", kind = "other", damage = 0 }
            for later = MAX_BARS, #abilities do
                rest.damage = rest.damage + abilities[later].damage
            end
            rest.share = rest.damage / summary.damage
            FillBar(bar, rest, biggest)
        elseif ability then
            local change = comparison and comparison.abilities[ability.kind .. ability.id]
            FillBar(bar, ability, biggest, change and change.change)
        else
            bar:Hide()
        end
    end

    card.notes:ClearAllPoints()
    card.notes:SetPoint("TOPLEFT", card.bars[math.max(shown, 1)], "BOTTOMLEFT", 0, -12)
    card.notes:SetPoint("RIGHT", card.body, "RIGHT")
    card.notes:SetText(Notes(recording, summary, baseline, comparison))
end
