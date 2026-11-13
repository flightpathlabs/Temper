local _, ns = ...

-- The analysis card: everything about a set of fights on one page.
--
-- The figures come first and are kept small: one row under the title, DPS
-- at its head, and whatever lies behind a figure waiting in its tooltip.
-- That leaves the page to the two things worth looking at, where the
-- damage came from and what was used when. A few lines on healing and
-- defence come next, with their own tab a click away for the rest of
-- it. The advice follows, and then (when there are earlier fights to
-- compare with) what else changed. The comparison isn't a separate
-- screen. It shows up as an arrow and a green or red figure under or
-- beside each number it applies to.
--
-- Each part of the page sits in a box of its own (see Kit.Section), so
-- it's plain where one stops and the next starts.
--
-- Some selections make a longer page than the window has room for, so
-- everything under the row of figures scrolls, and the page is laid out
-- by hand each time it's filled. The laying out is the kit's, shared with
-- the Healing and defence tab (see "Pages" in Kit.lua).

local Card = {}
ns.Card = Card

local Kit = ns.Kit

local Paragraph = Kit.Paragraph
local Place, PlaceText = Kit.Place, Kit.PlaceText
local Inside, PlaceSection = Kit.Inside, Kit.PlaceSection
local AddFigure = Kit.TooltipFigure

local LOGO = "Interface\\AddOns\\Temper\\Media\\logo"
local NOTE_PROMPT = "Add a note: what did you change?"
local NOTHING_STANDS_OUT = "Nothing stands out in %s."

-- Space between the card's edge and what's on it, and the room kept clear
-- down the right-hand side for the scroll bar.
local MARGIN = 14
local SCROLL_BAR_ROOM = 24

-- Down the top of the card: the line the title stands on, with the small
-- print to its right, and where the next thing starts. That's the note
-- box when there is one, and then the row of figures.
local TITLE_FOOT = 26
local TITLE_GAP = 12
local HEAD_HEIGHT = 32
local NOTE_HEIGHT = 20
local NOTE_GAP = 6

-- How wide the page is when the window is its usual size. Only used if
-- the card is filled before the game has worked out its real width.
local USUAL_WIDTH = 547

-- The scrolling page stops this far short of the card's foot.
local FOOT_GAP = 8

-- With nothing selected: the logo, and under it a line on what to do,
-- set a little below the middle of the card and kept to this width.
local LOGO_WIDTH = 320
local LOGO_HEIGHT = 160
local LOGO_GAP = 6
local EMPTY_WIDTH = 340
local EMPTY_DROP = 60

-- Space between one section and the next, and between lines of text in
-- one.
local SECTION_GAP = Kit.SECTION_GAP
local LINE_GAP = 6

-- The bars, and the space between them and the line under them that
-- says what their colours mean.
local MAX_BARS = 6
local BAR_GAP = 3
local KEY_GAP = 8

-- The most lines the section on healing and defence runs to.
local HEALING_LINES = 5

-- The most other healers named in its line on them. The rest are summed.
local HEALERS_NAMED = 3

-- More changed slots than this and the list is cut short, with a count.
local MAX_GEAR_LINES = 5

-- What each kind of damage source is called on the page.
local KIND_LABELS = {
    skill = "Abilities",
    auto = "Auto attacks",
    pet = "Pet",
    other = "Items and other effects",
}

-- The game's words for the ways an attack can fail, as we'd say them.
local AVOIDED_WAYS = {
    { "MISS", "Missed" },
    { "DODGE", "Dodged" },
    { "PARRY", "Parried" },
    { "BLOCK", "Blocked" },
    { "RESIST", "Resisted" },
    { "ABSORB", "Absorbed" },
    { "IMMUNE", "Immune" },
    { "EVADE", "Evaded" },
    { "DEFLECT", "Deflected" },
    { "REFLECT", "Reflected" },
}

-- What a tooltip calls a figure as it stood in the fights compared with.
local EARLIER = "In the earlier fights"

-- Several fights are shown by a typical one (see Summary.Typical). When
-- none of them goes towards that, the plain figure stands in, and says so.
local NONE_TYPICAL = "None of these fights counts towards a typical figure, so this is "
    .. "all the damage over all the time."

-- The size of a single blow is worked out, not read (see Sizes.lua), so
-- it's always "about", and its tooltip says why.
local SIZES_ARE_ESTIMATES = "The game doesn't say how hard a single blow lands, so its size is "
    .. "worked out and may be a little off."

-- What the page says ----------------------------------------------------------

--- "Abilities 62%    Auto attacks 38%", each kind in the colour of its
--- bars, so the line is also the key to them.
local function KindsText(summary)
    local kinds = {}
    for _, kind in ipairs(ns.Sources.ORDER) do
        local damage = summary.kinds[kind] or 0
        if damage > 0 then
            local label = Kit.Colored(KIND_LABELS[kind], Kit.KIND_COLORS[kind])
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

    return ("One enemy: %s DPS over %s.   Several at once: %s DPS over %s."):format(
        ns.Rate(summary.single.dps),
        summary.single.fights == 1 and "1 fight" or summary.single.fights .. " fights",
        ns.Rate(summary.several.dps),
        summary.several.fights == 1 and "1 fight" or summary.several.fights .. " fights"
    )
end

--- For a set of fights, how busy the player's hands were: how often an
--- ability was used, and how much of the time went by without one.
local function UsedText(summary)
    local time = ns.Duration(summary.watched)
    if summary.presses == 0 then
        return ("No abilities were used in %s of fighting."):format(time)
    end

    local used = ("You used an ability %d %s in %s of fighting, about once every %.1fs."):format(
        summary.presses,
        summary.presses == 1 and "time" or "times",
        time,
        summary.watched / summary.presses
    )
    local unused = ("For about %s of that time no ability was in use."):format(
        ns.Percent(summary.idle / summary.watched)
    )
    local text = used .. " " .. unused

    -- Older fights have had their use-by-use record dropped to save room.
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
            ("Level %d in the earlier fights, level %d in these."):format(
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

--- "About 38% of the damage coming at you was stopped (armour 18%, dodges
--- and misses 14%)." Nil when none of it could be worked out.
---@param healing table  from Healing.Of
local function StoppedLine(healing)
    local stopped = healing.stopped
    if not stopped then
        return nil
    end

    local ways = {}
    for _, way in ipairs(ns.Healing.StoppedWays(stopped)) do
        table.insert(ways, ("%s %s"):format(way.words, ns.Percent(way.share)))
    end
    if #ways == 0 then
        return nil
    end

    return ("About %s of the damage coming at you was stopped (%s)."):format(
        ns.Percent(stopped.share),
        table.concat(ways, ", ")
    )
end

--- "Others healed you for 230 (Tharic 180, someone else 50)." Nil when no
--- one else healed the player.
---@param healing table  from Healing.Of
local function OthersLine(healing)
    local healers, given = healing.healers, healing.healedByOthers
    if given <= 0 or #healers == 0 then
        return nil
    end

    -- Everyone the game wouldn't name is one "someone else", however many
    -- classes they were.
    local named, unnamed = {}, 0
    for _, healer in ipairs(healers) do
        if healer.name == ns.Healing.SOMEONE then
            unnamed = unnamed + healer.amount
        else
            table.insert(named, healer)
        end
    end

    if #named == 1 and unnamed == 0 then
        return ("%s healed you for %s."):format(named[1].name, ns.Number(given))
    elseif #named == 0 then
        return ("Someone else healed you for %s."):format(ns.Number(given))
    end

    local parts, rest = {}, unnamed
    for index, healer in ipairs(named) do
        if index <= HEALERS_NAMED then
            table.insert(parts, ("%s %s"):format(healer.name, ns.Number(healer.amount)))
        else
            rest = rest + healer.amount
        end
    end
    if rest > 0 then
        local others = #named > HEALERS_NAMED and "others" or "someone else"
        table.insert(parts, ("%s %s"):format(others, ns.Number(rest)))
    end

    return ("Others healed you for %s (%s)."):format(ns.Number(given), table.concat(parts, ", "))
end

--- What the fights have to say about healing and defence, in a line or
--- five. The Healing and defence tab has the detail.
---@param healing table  from Healing.Of
---@return table  list of lines; empty when there's nothing to say
local function HealingLines(healing)
    local lines = {}
    if healing.tracked == 0 then
        return lines
    end

    -- Healed back is the healing that landed on the player. When that's
    -- just what they healed, one sentence says both.
    local back = healing.healedBack
    local allMine = healing.healedOn == healing.healing and healing.healedByOthers == 0
    if healing.healing > 0 and back and allMine then
        table.insert(
            lines,
            ("Healed %s (%s HPS), which is %s of the %s damage you took."):format(
                ns.Number(healing.healing),
                ns.Rate(healing.hps),
                ns.Percent(back),
                ns.Number(healing.taken)
            )
        )
    elseif healing.healing > 0 and back then
        table.insert(
            lines,
            ("Healed %s (%s HPS). Healing on you came to %s of the %s damage you took."):format(
                ns.Number(healing.healing),
                ns.Rate(healing.hps),
                ns.Percent(back),
                ns.Number(healing.taken)
            )
        )
    elseif healing.healing > 0 then
        table.insert(
            lines,
            ("Healed %s (%s HPS)."):format(ns.Number(healing.healing), ns.Rate(healing.hps))
        )
    elseif healing.taken > 0 then
        table.insert(lines, ("You took %s damage."):format(ns.Number(healing.taken)))
    end

    local others = OthersLine(healing)
    if others then
        table.insert(lines, others)
    end

    local stopped = StoppedLine(healing)
    if stopped then
        table.insert(lines, stopped)
    end

    if healing.absorbed > 0 then
        table.insert(
            lines,
            ("Your own shields absorbed %s damage."):format(ns.Number(healing.absorbed))
        )
    end

    local deeds = {}
    if healing.interrupts > 0 then
        table.insert(deeds, ns.Count(healing.interrupts, "interrupt"))
    end
    if healing.dispels > 0 then
        table.insert(deeds, ns.Count(healing.dispels, "dispel"))
    end
    if #deeds > 0 then
        table.insert(lines, table.concat(deeds, ", ") .. ".")
    end

    -- Fights from before healing was recorded are in the set but not in
    -- these figures, and the reader should know that.
    if #lines > 0 and healing.tracked < healing.fights then
        local caveat = "Older fights here have no record of healing."
        lines[#lines] = lines[#lines] .. "  " .. Kit.Colored(caveat, Kit.MUTED)
    end
    return lines
end

-- The figures -----------------------------------------------------------------

-- Each figure in the row is a table of the kind Kit.StatRow shows: a
-- label and a value, what lies behind it for its tooltip, and when
-- comparing, how it moved since the earlier fights.

--- Adds to a figure how it moved since the earlier fights.
---@param changeText string  from Kit.ChangeText or Kit.PointsText
---@param change number|nil  the number behind it, for the arrow
---@param earlier string|nil  what the figure was then, if that's known
local function Compared(stat, changeText, change, earlier)
    stat.changeText, stat.change = changeText, change
    if earlier then
        table.insert(stat.figures, { EARLIER, earlier })
    end
end

--- DPS: a single fight's own, and for several the typical fight's (see
--- Summary.Typical), with the plain figure and how the typical one was
--- reached in its tooltip.
local function DpsStat(summary, comparison)
    local dps, typical = ns.Summary.DpsOf(summary)
    local stat = {
        label = "DPS",
        value = ns.Rate(dps),
        title = "Damage per second",
        figures = {
            { "Damage", ns.Number(summary.damage) },
            { "Time fighting", ns.Duration(summary.seconds) },
        },
    }

    if typical then
        local reached = summary.typical
        stat.label = "DPS, typical"
        stat.title = "Typical damage per second"
        stat.figures = { { "Going by", reached.how } }
        if reached.left > 0 then
            table.insert(stat.figures, { "Not counted", ns.Count(reached.left, "fight") })
        end
        table.insert(stat.figures, { "All damage over all time", ns.Rate(summary.dps) })
        stat.note = ns.Summary.TYPICAL_RULE
    elseif summary.fights > 1 then
        stat.note = NONE_TYPICAL
    end

    if comparison then
        local pair = comparison.dps
        local earlier = ns.Rate(pair.before)
        if pair.typicalBefore then
            earlier = earlier .. " typical"
        end
        Compared(stat, Kit.ChangeText(pair.change), pair.change, earlier)
    end
    return stat
end

--- The damage done: all of it for one fight, a fight's worth for several,
--- so that a set of three fights can be read against a set of ten.
local function DamageStat(summary, comparison)
    local stat = {
        label = "Damage",
        value = ns.Number(summary.damage / summary.fights),
        figures = {},
    }

    if summary.fights > 1 then
        stat.label = "Damage per fight"
        stat.figures = {
            { "Fights", ns.Number(summary.fights) },
            { "Damage in all", ns.Number(summary.damage) },
        }
    end

    if comparison then
        local perFight = comparison.perFight
        local earlier = perFight.before and ns.Number(perFight.before)
        if earlier and comparison.was.fights > 1 then
            earlier = earlier .. " a fight"
        end
        Compared(stat, Kit.ChangeText(perFight.change), perFight.change, earlier)
    end
    return stat
end

--- How long the fighting took, with the average fight in the tooltip.
local function TimeStat(summary)
    local stat = {
        label = "Time",
        value = ns.Duration(summary.seconds),
        title = "Time fighting",
        figures = {},
    }

    if summary.fights > 1 then
        stat.figures = {
            { "Fights", ns.Number(summary.fights) },
            { "A fight, on average", ns.Duration(summary.seconds / summary.fights) },
        }
    end
    return stat
end

--- The share of hits that were critical, "-" when nothing landed.
local function CritStat(summary, comparison)
    local stat = {
        label = "Crit",
        value = summary.critRate and ns.Percent(summary.critRate) or "-",
        title = "Critical hits",
        figures = {},
    }

    if summary.hits > 0 then
        local hits = summary.hits == 1 and "1 hit" or summary.hits .. " hits"
        table.insert(stat.figures, { "Critical", ("%d of %s"):format(summary.crits, hits) })
    end

    -- A rate that's already a percentage moves in points, not per cent.
    if comparison then
        local rate = comparison.critRate
        local earlier = rate.before and ns.Percent(rate.before)
        Compared(stat, Kit.PointsText(rate.points), rate.points, earlier)
    end
    return stat
end

--- How many blows landed. Nil when none did.
local function HitsStat(summary)
    if summary.hits == 0 then
        return nil
    end

    local stat = {
        label = "Hits",
        value = ns.Number(summary.hits),
        title = "Hits that landed",
        figures = {},
    }
    if summary.crits > 0 then
        table.insert(stat.figures, { "Critical", ns.Number(summary.crits) })
    end
    if summary.glancing > 0 then
        table.insert(stat.figures, { "Glancing", ns.Number(summary.glancing) })
    end
    return stat
end

--- How many attacks failed, with the ways they failed in the tooltip.
--- Nil when none did.
local function AvoidedStat(summary)
    if summary.avoided == 0 then
        return nil
    end

    local stat = {
        label = "Avoided",
        value = ns.Number(summary.avoided),
        title = "Attacks that didn't land",
        figures = {},
    }

    local counted = 0
    for _, way in ipairs(AVOIDED_WAYS) do
        local times = summary.avoidedBy[way[1]]
        if times and times > 0 then
            table.insert(stat.figures, { way[2], ns.Number(times) })
            counted = counted + times
        end
    end

    -- Fights saved before the ways were told apart only have the total.
    if counted < summary.avoided then
        local rest = summary.avoided - counted
        table.insert(stat.figures, { "Missed or avoided", ns.Number(rest) })
    end

    if summary.avoidRate then
        table.insert(stat.figures, { "Share of your attacks", ns.Percent(summary.avoidRate) })
    end
    return stat
end

--- "about 62 (Aimed Shot)"
---@param spell number|nil  the spell the blow probably was, if that's known
local function BlowText(size, spell)
    local text = "about " .. ns.Number(size)
    if spell then
        text = ("%s (%s)"):format(text, ns.Sources.Name(spell))
    end
    return text
end

--- The hardest single blow, with what it was in the tooltip. Nil when no
--- blow could be sized.
local function BiggestStat(summary)
    local sizes = summary.sizes
    if not sizes then
        return nil
    end

    local stat = {
        label = "Biggest hit",
        value = "about " .. ns.Number(sizes.biggest),
        figures = {},
        note = SIZES_ARE_ESTIMATES,
    }

    -- When the hardest blow of all was a critical hit, the two are one
    -- and the same, and it's only listed as that.
    if sizes.biggest ~= sizes.biggestCrit then
        local blow = BlowText(sizes.biggest, sizes.biggestSpell)
        table.insert(stat.figures, { "Biggest hit", blow })
    end
    if sizes.biggestCrit then
        local blow = BlowText(sizes.biggestCrit, sizes.biggestCritSpell)
        table.insert(stat.figures, { "Biggest critical hit", blow })
    end
    return stat
end

--- The figures for the row, left to right. DPS always comes first. The
--- last three are only there when they have something to say.
local function StatsFor(summary, comparison)
    local stats = {
        DpsStat(summary, comparison),
        DamageStat(summary, comparison),
        TimeStat(summary),
        CritStat(summary, comparison),
    }

    for _, Optional in ipairs({ HitsStat, AvoidedStat, BiggestStat }) do
        local stat = Optional(summary)
        if stat then
            table.insert(stats, stat)
        end
    end
    return stats
end

-- Laying out ------------------------------------------------------------------

--- Notes a piece of the page, so that a fill can start by clearing every
--- piece away and then show only the ones it places.
local function Piece(card, piece)
    table.insert(card.pieces, piece)
    return piece
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

--- Saves what's in the note box to the session it's about.
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

--- Points the note box at a session, or hides it.
---@param about table|nil  the session the note belongs to
local function ShowNote(box, about)
    -- A redraw while the player is halfway through typing leaves it be.
    if box.about == about and box:HasFocus() then
        return
    end

    -- Clicking other fights doesn't take the cursor out of the box, so
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

--- The box under the title where a session's note is typed.
local function CreateNoteBox(card)
    local box = CreateFrame("EditBox", nil, card, "InputBoxInstructionsTemplate")
    box:SetHeight(NOTE_HEIGHT)

    -- The template draws its border a little to the left of the box. On
    -- the right it stops where the row of figures and the page do.
    box:SetPoint("TOPLEFT", MARGIN + 5, -HEAD_HEIGHT)
    box:SetPoint("TOPRIGHT", -SCROLL_BAR_ROOM, -HEAD_HEIGHT)

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

-- The bars --------------------------------------------------------------------

--- What an ability did, in a tooltip of our own: its name and rank, then
--- the figures the bar has no room for. The game's own tooltip for the
--- ability is a paragraph of rules, which isn't what's wanted here.
local function ShowAbilityTooltip(bar)
    local ability = bar.ability
    if not ability then
        return
    end

    GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
    GameTooltip:SetText(ability.name, 1, 1, 1)
    if ability.rank then
        GameTooltip:AddLine(ability.rank, Kit.MUTED[1], Kit.MUTED[2], Kit.MUTED[3])
    end

    AddFigure("Damage", ("%s (%s)"):format(ns.Number(ability.damage), ns.Percent(ability.share)))
    if ability.perCast then
        AddFigure(
            ("Used %d %s"):format(ability.casts, ability.casts == 1 and "time" or "times"),
            ns.Rate(ability.perCast) .. " damage per use"
        )
    end
    if ability.perCost then
        local power = ns.Summary.PowerWord(ability.power)
        AddFigure(
            ("Costs %d %s"):format(ability.cost, power),
            ("%.1f damage per point"):format(ability.perCost)
        )
    end

    -- Which blow belongs to which use is worked out, not reported, so
    -- this is marked as the estimate it is.
    if ability.landed then
        AddFigure(
            "Landed",
            ("%d of %d uses (estimated)"):format(ability.landed, ability.landed + ability.failed)
        )
    end
    GameTooltip:Show()
end

--- A bar for one ability, with its figures in a tooltip.
local function CreateBar(parent)
    local bar = Kit.Bar(parent)
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

--- Shows one ability on a bar: its name and rank, its damage and share,
--- and how it moved when comparing.
---@param biggest number  the damage of the biggest ability, which gets a
---                       full bar; the others are drawn against it
---@param change number|nil  how its DPS moved since the earlier fights
local function FillBar(bar, ability, biggest, change)
    bar.ability = ability

    local name = ability.name
    if ability.rank then
        name = name .. "  " .. Kit.Colored(ability.rank, Kit.MUTED)
    end

    local figures = ("%s  %s"):format(ns.Number(ability.damage), ns.Percent(ability.share))
    if change then
        figures = figures .. "  " .. Kit.ChangeText(change)
    end

    local share = biggest > 0 and math.min(ability.damage / biggest, 1) or 0
    local color = Kit.KIND_COLORS[ability.kind] or Kit.KIND_COLORS.other
    bar:Set(ability.icon, name, figures, share, color)
end

-- Building --------------------------------------------------------------------

--- Builds an empty card inside `parent`.
function Card.Create(parent)
    local card = CreateFrame("Frame", nil, parent)
    card.pieces = {}

    -- Fixed at the top: what's selected, when it was, a note about it,
    -- and the figures. The title is given its width when it's filled, as
    -- whatever the small print beside it leaves.
    card.title = Kit.Text(card, "GameFontNormalLarge")
    card.title:SetPoint("BOTTOMLEFT", card, "TOPLEFT", MARGIN, -TITLE_FOOT)

    -- Smaller type sits a little lower on its line, so it's raised to
    -- stand level with the title.
    card.subtitle = Kit.Text(card, "GameFontHighlightSmall", "RIGHT")
    card.subtitle:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", -SCROLL_BAR_ROOM, 1 - TITLE_FOOT)
    card.subtitle:SetTextColor(unpack(Kit.MUTED))

    card.note = CreateNoteBox(card)

    card.stats = Kit.StatRow(card)
    card.stats:Hide()

    -- Shown in place of everything else when there's nothing to analyse.
    card.empty = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    card.empty:SetPoint("CENTER", 0, -EMPTY_DROP)
    card.empty:SetWidth(EMPTY_WIDTH)
    card.empty:SetTextColor(unpack(Kit.MUTED))

    card.logo = card:CreateTexture(nil, "ARTWORK")
    card.logo:SetTexture(LOGO)
    card.logo:SetSize(LOGO_WIDTH, LOGO_HEIGHT)
    card.logo:SetPoint("BOTTOM", card.empty, "TOP", 0, LOGO_GAP)

    -- The rest scrolls. The template brings its own scroll bar, which
    -- only needs telling to stay out of sight while everything fits.
    card.scroll = CreateFrame("ScrollFrame", nil, card, "ScrollFrameTemplate")
    card.scroll:SetPoint("TOPLEFT", MARGIN, -HEAD_HEIGHT)
    card.scroll:SetPoint("BOTTOMRIGHT", -SCROLL_BAR_ROOM, FOOT_GAP)
    card.scroll.ScrollBar:SetHideIfUnscrollable(true)

    local page = CreateFrame("Frame", nil, card.scroll)
    page:SetSize(USUAL_WIDTH, 1)
    card.scroll:SetScrollChild(page)
    card.page = page

    -- A section's contents belong to the section, so they're drawn over
    -- its fill and go when it goes.
    local sources = Piece(card, Kit.Section(page, "Where the damage came from"))
    card.sourcesSection = sources
    card.bars = {}
    for index = 1, MAX_BARS do
        card.bars[index] = Piece(card, CreateBar(sources))
    end
    card.kinds = Piece(card, Kit.Text(sources, "GameFontHighlightSmall"))
    card.split = Piece(card, Paragraph(sources, "GameFontHighlightSmall"))
    card.split:SetTextColor(unpack(Kit.MUTED))

    local used = Piece(card, Kit.Section(page, "What you used"))
    card.usedSection = used
    card.timeline = Piece(card, ns.Timeline.Create(used))
    card.used = Piece(card, Paragraph(used, "GameFontHighlight"))

    -- A few lines only. The rest is a click away, by the link at the end
    -- of the section's title band.
    local healing = Piece(card, Kit.Section(page, "Healing and defence"))
    card.healingSection = healing
    card.healingLines = {}
    for index = 1, HEALING_LINES do
        card.healingLines[index] = Piece(card, Paragraph(healing, "GameFontHighlight"))
    end

    -- The Healing and defence tab, on the same fights as this page.
    local more = Kit.Link(healing, "More on the Healing and defence tab", function()
        ns.ShowHealing(card.fights)
    end)
    more:SetPoint("RIGHT", healing.title, "RIGHT", 4, 0)

    -- Findings and differences come a few at a time, so their rows are
    -- made as they're first needed.
    card.findingsSection = Piece(card, Kit.Section(page, "What to work on"))
    card.findings = {}

    card.differencesSection = Piece(card, Kit.Section(page, "What changed"))
    card.differences = {}

    return card
end

-- Filling ---------------------------------------------------------------------

--- The title, and on the same line, small and to the right, when the
--- fights were. How long they lasted is in the row of figures.
---@param width number  of the page, which the two share
local function ShowTitle(card, heading, width)
    card.subtitle:SetText(heading.subtitle or "")

    -- A long name is cut short before it runs into the small print.
    card.title:SetWidth(width - card.subtitle:GetStringWidth() - TITLE_GAP)
    card.title:SetText(heading.title)
end

--- A bar for each of the biggest abilities, and under them the split by
--- kind of source.
local function PlaceSources(card, layout, summary, comparison)
    local abilities = summary.abilities

    -- With no abilities on record there's nothing to draw, and an empty
    -- box would only look broken.
    if #abilities == 0 then
        return
    end

    local section = card.sourcesSection
    local inside = Inside(layout, section)
    local biggest = abilities[1].damage
    local gap = 0

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
            Place(inside, bar, gap)
            gap = BAR_GAP
        else
            bar.ability = nil
        end
    end

    card.kinds:SetText(KindsText(summary))
    Place(inside, card.kinds, KEY_GAP, card.kinds:GetStringHeight())

    local split = SplitText(summary)
    if split then
        PlaceText(inside, card.split, LINE_GAP, split)
    end

    PlaceSection(layout, section, inside)
end

--- What was used: one use after another for a single fight, summed up
--- for several.
local function PlaceUsed(card, layout, summary, fights)
    local section = card.usedSection
    local inside = Inside(layout, section)

    if summary.fights == 1 then
        -- The timeline hides itself if this fight's uses weren't kept,
        -- and then there's nothing to put a box round.
        local timeline = card.timeline
        timeline:SetWidth(inside.width)
        timeline:Set(fights[1])
        if timeline:IsShown() then
            Place(inside, timeline, 0)
            PlaceSection(layout, section, inside)
        end
    elseif summary.watched > 0 then
        PlaceText(inside, card.used, 0, UsedText(summary))
        PlaceSection(layout, section, inside)
    end
end

--- The few lines on healing and defence, when the fights have anything
--- to say about either. Fights from before healing was recorded don't,
--- and nor does a fight in which nothing was healed and nothing landed.
local function PlaceHealing(card, layout, fights)
    -- Missing only straight after an update, until the game is restarted
    -- and finds the new file.
    if not ns.Healing then
        return
    end

    local lines = HealingLines(ns.Healing.Of(fights))
    if #lines == 0 then
        return
    end

    local section = card.healingSection
    local inside = Inside(layout, section)

    local gap = 0
    for index, line in ipairs(lines) do
        PlaceText(inside, card.healingLines[index], gap, line)
        gap = LINE_GAP
    end

    PlaceSection(layout, section, inside)
end

--- One row per finding. With no findings the section says so in a line
--- of its own, so the page keeps its shape from one selection to the
--- next.
local function PlaceFindings(card, layout, findings, summary)
    local section = card.findingsSection
    local inside = Inside(layout, section)

    if #findings == 0 then
        local these = summary.fights == 1 and "this fight" or "these fights"
        findings = { { kind = "tip", text = NOTHING_STANDS_OUT:format(these) } }
    end

    Kit.PlaceFindings(inside, card.findings, findings)
    PlaceSection(layout, section, inside)
end

--- What else changed since the earlier fights, a line at a time.
local function PlaceDifferences(card, layout, comparison)
    local section = card.differencesSection
    local inside = Inside(layout, section)

    local gap = 0
    for index, line in ipairs(DifferenceLines(comparison)) do
        local text = card.differences[index]
        if not text then
            text = Piece(card, Paragraph(section, "GameFontHighlight"))
            card.differences[index] = text
        end

        PlaceText(inside, text, gap, line)
        gap = LINE_GAP
    end

    PlaceSection(layout, section, inside)
end

--- The card with nothing selected: the logo, and a line on what to do.
local function ShowEmpty(card, heading)
    card.title:SetText("")
    card.subtitle:SetText("")
    ShowNote(card.note, nil)
    card.stats:Hide()
    card.scroll:Hide()
    card.shown = nil

    card.empty:SetText(heading.empty)
    card.empty:Show()
    card.logo:Show()
end

--- Fills the card in.
---@param card table  from Card.Create
---@param fights table  the fights to analyse; may be empty
---@param before table|nil  the earlier fights to compare them with, if any
---@param heading table  { title, subtitle, empty, recording }: what to call
---                      this set, what to say when there's nothing in it,
---                      and the session when it's exactly one whole one
function Card.Fill(card, fights, before, heading)
    card.fights = fights
    local summary = ns.Summary.Of(fights)
    if summary.fights == 0 then
        ShowEmpty(card, heading)
        return
    end

    card.empty:Hide()
    card.logo:Hide()
    card.scroll:Show()

    local comparison = before and ns.Compare.Between(before, fights)
    local width = PageWidth(card)

    ShowTitle(card, heading, width)

    -- A note belongs to a session: it's where "what did you change?" has
    -- an answer. Any other selection is just a selection, with nowhere to
    -- keep one.
    local noted = heading.recording
    ShowNote(card.note, noted)

    -- The figures go under the title, or under the note box when that's
    -- in between, and the scrolling page starts under them.
    local top = HEAD_HEIGHT
    if noted then
        top = top + NOTE_HEIGHT + NOTE_GAP
    end

    card.stats:Fill(StatsFor(summary, comparison), width, comparison ~= nil)
    card.stats:SetPoint("TOPLEFT", MARGIN, -top)
    card.stats:SetPoint("TOPRIGHT", -SCROLL_BAR_ROOM, -top)
    card.stats:Show()

    top = top + card.stats:GetHeight() + SECTION_GAP
    card.scroll:SetPoint("TOPLEFT", MARGIN, -top)

    for _, piece in ipairs(card.pieces) do
        piece:Hide()
    end

    local layout = { frame = card.page, left = 0, width = width, y = 0 }

    PlaceSources(card, layout, summary, comparison)
    PlaceUsed(card, layout, summary, fights)
    PlaceHealing(card, layout, fights)
    PlaceFindings(card, layout, ns.Findings.For(summary, comparison), summary)
    if comparison then
        PlaceDifferences(card, layout, comparison)
    end

    card.page:SetSize(width, layout.y + SECTION_GAP)

    -- A new selection starts at the top. A redraw of the same one, as when
    -- a fight ends while the page is open, leaves the reader where they were.
    if not SameFights(card.shown, fights) then
        card.scroll:SetVerticalScroll(0)
    end
    card.shown = fights
end
