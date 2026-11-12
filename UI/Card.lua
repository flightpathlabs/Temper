local _, ns = ...

-- The analysis card: everything about a set of fights on one page.
--
-- Read top to bottom it answers, in order: how hard did I hit, where did
-- it come from, what stands out, and (when there's a "before" to compare
-- with) what changed. The comparison isn't a separate screen. It shows up
-- as a small green or red figure beside each number it applies to.

local Card = {}
ns.Card = Card

local MAX_BARS = 6
local BAR_HEIGHT = 22
local BAR_GAP = 3
local ICON_SIZE = 22

-- More changed slots than this and the list is cut short, with a count.
local MAX_GEAR_LINES = 2

local MUTED = { 0.6, 0.6, 0.6 }
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local LOGO = "Interface\\AddOns\\Temper\\Media\\logo"

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

--- The game's own tooltip for the ability, with our figures underneath.
local function ShowAbilityTooltip(row)
    local ability = row.ability
    if not ability then
        return
    end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if ability.id and ability.id ~= 0 then
        GameTooltip:SetSpellByID(ability.id)
    else
        GameTooltip:SetText(ability.name)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(
        "Damage",
        ("%s (%s)"):format(ns.Number(ability.damage), ns.Percent(ability.share)),
        1,
        0.82,
        0,
        1,
        1,
        1
    )
    if ability.perCast then
        GameTooltip:AddDoubleLine(
            ("Used %d %s"):format(ability.casts, ability.casts == 1 and "time" or "times"),
            ns.Rate(ability.perCast) .. " damage a use",
            1,
            0.82,
            0,
            1,
            1,
            1
        )
    end
    if ability.perCost then
        local word = ns.Summary.PowerWord(ability.power)
        GameTooltip:AddDoubleLine(
            ("Costs %d %s"):format(ability.cost, word),
            ("%.1f damage a point"):format(ability.perCost),
            1,
            0.82,
            0,
            1,
            1,
            1
        )
    end
    GameTooltip:Show()
end

-- One ability: its icon, then a bar as long as its share of the damage
-- with its name on it and the figures to the right.
local function CreateBar(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(BAR_HEIGHT)
    row:EnableMouse(true)
    row:SetScript("OnEnter", ShowAbilityTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMRIGHT")
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    row.bar = bar

    local backing = bar:CreateTexture(nil, "BACKGROUND")
    backing:SetAllPoints()
    backing:SetColorTexture(1, 1, 1, 0.06)

    row.name = Label(bar, "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 6, 0)

    row.figures = Label(bar, "GameFontHighlightSmall", "RIGHT")
    row.figures:SetPoint("RIGHT", -6, 0)
    row.name:SetPoint("RIGHT", row.figures, "LEFT", -8, 0)

    return row
end

local function FillBar(row, ability, biggest, change)
    row.ability = ability

    local color = KIND_COLORS[ability.kind] or KIND_COLORS.other
    row.bar:SetStatusBarColor(color[1], color[2], color[3], 0.75)
    row.bar:SetValue(biggest > 0 and ability.damage / biggest or 0)
    row.icon:SetTexture(ability.icon or QUESTION_MARK)

    local name = ability.name
    if ability.rank then
        name = ("%s  |cff999999%s|r"):format(name, ability.rank)
    end
    row.name:SetText(name)

    -- Damage and share for everything. For skills, what each use did and
    -- what each point of mana or energy bought.
    local figures = ("%s  %s"):format(ns.Number(ability.damage), ns.Percent(ability.share))
    if ability.perCast then
        figures = ("%s  |cff999999%s a use|r"):format(figures, ns.Rate(ability.perCast))
    end
    if ability.perCost then
        figures = ("%s  |cff999999%.1f per %s|r"):format(
            figures,
            ability.perCost,
            ns.Summary.PowerWord(ability.power)
        )
    end
    if change then
        figures = figures .. "  " .. ChangeText(change)
    end
    row.figures:SetText(figures)
    row:Show()
end

--- Builds an empty card inside `parent`.
function Card.Create(parent)
    local card = CreateFrame("Frame", nil, parent)

    card.title = Label(card, "GameFontNormalLarge")
    card.title:SetPoint("TOPLEFT", 14, -8)
    card.title:SetPoint("RIGHT", -14, 0)

    card.subtitle = Label(card, "GameFontHighlightSmall")
    card.subtitle:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
    card.subtitle:SetPoint("RIGHT", -14, 0)
    card.subtitle:SetTextColor(unpack(MUTED))

    -- Shown in place of everything else when there's nothing to analyse.
    card.empty = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    card.empty:SetPoint("CENTER", 0, -60)
    card.empty:SetWidth(340)
    card.empty:SetTextColor(unpack(MUTED))

    card.logo = card:CreateTexture(nil, "ARTWORK")
    card.logo:SetTexture(LOGO)
    card.logo:SetSize(320, 160)
    card.logo:SetPoint("BOTTOM", card.empty, "TOP", 0, 6)

    card.body = CreateFrame("Frame", nil, card)
    card.body:SetPoint("TOPLEFT", 14, -50)
    card.body:SetPoint("BOTTOMRIGHT", -14, 8)
    local body = card.body

    card.tiles = {}
    for index = 1, 4 do
        local tile = CreateTile(body)
        tile:SetPoint("TOPLEFT", body, "TOPLEFT", (index - 1) * 130, 0)
        tile:SetWidth(124)
        card.tiles[index] = tile
    end

    card.counts = Label(body, "GameFontHighlightSmall")
    card.counts:SetPoint("TOPLEFT", 0, -64)
    card.counts:SetPoint("RIGHT")

    card.sourcesTitle = Label(body, "GameFontNormal")
    card.sourcesTitle:SetPoint("TOPLEFT", card.counts, "BOTTOMLEFT", 0, -12)
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
--- fights against one enemy and several, what stands out, and what
--- changed.
local function Notes(summary, comparison)
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

    local findings = ns.Findings.For(summary, comparison)
    if #findings > 0 then
        table.insert(lines, "")
        table.insert(lines, "|cffffd100What stands out|r")
        for _, finding in ipairs(findings) do
            table.insert(lines, finding)
        end
    end

    if not comparison then
        return table.concat(lines, "\n")
    end

    table.insert(lines, "")
    table.insert(lines, "|cffffd100What was different|r")

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
        table.insert(lines, "|cff999999No note of the gear worn was kept for one of these.|r")
    elseif #comparison.gear == 0 then
        table.insert(lines, "Same gear in both.")
    else
        for index, change in ipairs(comparison.gear) do
            if index > MAX_GEAR_LINES then
                local more = #comparison.gear - MAX_GEAR_LINES
                table.insert(lines, ("...and %d more."):format(more))
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
---@param fights table  the fights to analyse; may be empty
---@param before table|nil  the fights to compare them with, if any
---@param heading table  { title, subtitle, empty }: what to call this set,
---                      and what to say when there's nothing in it
function Card.Fill(card, fights, before, heading)
    local summary = ns.Summary.Of(fights)
    if summary.fights == 0 then
        card.title:SetText("")
        card.subtitle:SetText("")
        card.body:Hide()
        card.empty:SetText(heading.empty)
        card.empty:Show()
        card.logo:Show()
        return
    end

    card.empty:Hide()
    card.logo:Hide()
    card.body:Show()
    card.title:SetText(heading.title)
    card.subtitle:SetText(heading.subtitle)

    local comparison = before and ns.Compare.Between(before, fights)

    FillTile(
        card.tiles[1],
        "Damage a second",
        ns.Rate(summary.dps),
        comparison and ChangeText(comparison.dps.change)
    )
    FillTile(
        card.tiles[2],
        summary.fights == 1 and "Damage" or "Damage a fight",
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

    card.counts:SetText(CountsText(summary))

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
            bar.ability = nil
            bar:Hide()
        end
    end

    card.notes:ClearAllPoints()
    card.notes:SetPoint("TOPLEFT", card.bars[math.max(shown, 1)], "BOTTOMLEFT", 0, -10)
    card.notes:SetPoint("RIGHT", card.body, "RIGHT")
    card.notes:SetText(Notes(summary, comparison))
end
