local _, ns = ...

-- What the player used in one fight, laid out along a line of time.
--
-- Time runs left to right, and when a fight is longer than one line holds
-- it carries on underneath, the way text does. Abilities sit on the upper
-- lane as icons; auto attacks sit on a lane of their own below, smaller,
-- so the abilities stand out. Because an icon's place is the moment it
-- was used, a stretch of bare upper lane is time in which no ability was
-- used, and that can be seen without reading a number.
--
-- Each icon also says how that use went, with cues the game already
-- uses: a gold edge for a critical hit, a red cross over a greyed icon for
-- one that didn't land. An ordinary hit, and a use no blow could be
-- traced to, are left plain. The tooltip says all of it in words.
--
-- The game reports a blow and the use of an ability separately, and the
-- two are paired up here by how close together they came. That's right
-- nearly every time and not every time, and a line under the key says so.

local Timeline = {}
ns.Timeline = Timeline

local Kit = ns.Kit

-- How much of a fight one line holds at most, and how often a time is
-- marked under it. A short fight gets a shorter line, so its few icons
-- aren't huddled at one end of a line made for half a minute.
local LONGEST_ROW = 30
local SHORTEST_ROW = 10
local TICK_SECONDS = 5

-- How much one line holds for the fight being shown.
local rowSeconds = LONGEST_ROW

-- The most a saved timeline holds (see Combat\Hits.lua). One that's full
-- was cut short, and says so.
local MOST_ITEMS = 120

local SKILL_SIZE = 20
local SWING_SIZE = 12
local SWING_ALPHA = 0.85

-- The line round each icon: thin and dark as a rule, wider and gold for a
-- critical hit. Icons keep far enough apart for two gold edges to clear.
local EDGE = 1
local CRIT_EDGE = 2
local SPACE = 2 * CRIT_EDGE + 1
local DARK = { 0, 0, 0 }

-- How far an icon that didn't land is greyed, and how big the cross over
-- it is next to the icon.
local DIMMED = 0.45
local CROSS_SCALE = 0.75

-- One line, top to bottom: the skills, the auto attacks, then a rule
-- with the times under it. Each lane leaves room for a gold edge.
local SKILL_TOP = CRIT_EDGE
local SWING_TOP = SKILL_TOP + SKILL_SIZE + 2 * CRIT_EDGE + 2
local AXIS_TOP = SWING_TOP + SWING_SIZE + CRIT_EDGE + 3
local TICK_HEIGHT = 3
local ROW_HEIGHT = AXIS_TOP + TICK_HEIGHT + 12
local ROW_GAP = 6

-- Icons stop this far short of either end, again for the gold edge.
local INSET = CRIT_EDGE

local LEGEND_GAP = 8
local LEGEND_HEIGHT = 12
local LEGEND_SPACE = 14

-- Space above each line of small print under the key.
local SMALL_PRINT_GAP = 4

local MATCHED_BY_TIMING = "Critical hits and misses are matched to abilities by timing, "
    .. "so the odd one may be wrong."
local CUT_SHORT = ("Only the first %d attacks and abilities of a long fight are kept."):format(
    MOST_ITEMS
)

-- How a use went, in words. Anything not listed as landing counts as
-- having failed.
local LANDED = { HIT = true, CRIT = true, GLANCE = true }

local OUTCOMES = {
    HIT = "Hit",
    CRIT = "Critical hit",
    GLANCE = "Glancing blow",
    MISS = "Missed",
    DODGE = "Dodged",
    PARRY = "Parried",
    BLOCK = "Blocked",
    RESIST = "Resisted",
    ABSORB = "Absorbed",
    IMMUNE = "The enemy was immune",
    EVADE = "Evaded",
    DEFLECT = "Deflected",
    REFLECT = "Reflected",
}

--- Whether a spell is an auto attack: a swing, a shot or a wand.
--- Remembered, so the game is only asked once per spell.
local autoAttacks = {}
local function IsAutoAttack(id)
    if autoAttacks[id] == nil then
        autoAttacks[id] = id == ns.Guess.MELEE_SWING or ns.Sources.Kind(id, false) == "auto"
    end
    return autoAttacks[id]
end

--- A time under the rule: "25s", then "1:05" once seconds get unwieldy.
local function Clock(seconds)
    if seconds < 60 then
        return seconds .. "s"
    end
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

--- When in the fight something happened, for a tooltip.
local function WhenText(t)
    -- The first blow is struck a moment before the game calls it a fight.
    if t <= 0 then
        return "As the fight began"
    elseif t < 60 then
        return ("%.1fs in"):format(t)
    end
    return ns.Duration(t) .. " in"
end

--- How a use went, for a tooltip, and the colour to say it in.
local function OutcomeText(result)
    if not result then
        return "Result unknown", Kit.MUTED
    elseif result == "CRIT" then
        return OUTCOMES.CRIT, Kit.GOLD
    elseif LANDED[result] then
        return OUTCOMES[result], Kit.GOOD
    end
    return OUTCOMES[result] or "Didn't land", Kit.BAD
end

local function ShowTooltip(frame)
    local item = frame.item
    local outcome, color = OutcomeText(item.r)

    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.Sources.Name(item.id))
    GameTooltip:AddLine(WhenText(item.t), 1, 1, 1)
    GameTooltip:AddLine(outcome, color[1], color[2], color[3])
    GameTooltip:Show()
end

-- Icons -------------------------------------------------------------------------

local function CreateIcon(timeline)
    local frame = CreateFrame("Frame", nil, timeline)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", ShowTooltip)
    frame:SetScript("OnLeave", GameTooltip_Hide)

    -- The edge is a plain square a little bigger than the icon, behind it.
    frame.edge = frame:CreateTexture(nil, "BACKGROUND")

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()

    frame.cross = Kit.Icon(frame, SKILL_SIZE, "bad")
    frame.cross:SetDrawLayer("OVERLAY")
    frame.cross:SetPoint("CENTER")

    return frame
end

--- Makes an icon show one use of a spell and how it went.
---@param item table  { t, id, r } from a fight's timeline
---@param lane table  the lane it sits on, for its size and strength
local function DressIcon(frame, item, lane)
    local size = lane.size
    local crit = item.r == "CRIT"
    local failed = item.r ~= nil and not LANDED[item.r]

    frame.item = item
    frame:SetSize(size, size)
    frame:SetAlpha(lane.alpha)

    Kit.SetSpellIcon(frame.icon, C_Spell.GetSpellTexture(item.id))
    if failed then
        frame.icon:SetDesaturated(true)
        frame.icon:SetVertexColor(DIMMED, DIMMED, DIMMED)
    end

    frame.cross:SetSize(size * CROSS_SCALE, size * CROSS_SCALE)
    frame.cross:SetShown(failed)

    local edge = crit and CRIT_EDGE or EDGE
    local color = crit and Kit.GOLD or DARK
    frame.edge:ClearAllPoints()
    frame.edge:SetPoint("TOPLEFT", -edge, edge)
    frame.edge:SetPoint("BOTTOMRIGHT", edge, -edge)
    frame.edge:SetColorTexture(color[1], color[2], color[3], 1)
end

--- Finds an icon its seat on a lane: at its moment if that's free, and
--- otherwise straight after the icon before it, on the next line if this
--- one is full. Two skills in the same second sit side by side, not one
--- on top of the other.
---@param lane table  { size, row, free, ... }: how big its icons are, the
---                   line it has reached and how far along that is taken
---@param t number  seconds into the fight
---@param scale number  pixels to a second
---@param width number  of the whole timeline
---@return number row, number x  the line, counting from 0, and how far in
local function Seat(lane, t, scale, width)
    local row = math.floor(t / rowSeconds)
    if row > lane.row then
        lane.row, lane.free = row, INSET
    end

    local x = math.max(INSET + (t - lane.row * rowSeconds) * scale, lane.free)
    if x + lane.size + INSET > width then
        lane.row, x = lane.row + 1, INSET
    end

    lane.free = x + lane.size + SPACE
    return lane.row, x
end

-- The line under the icons --------------------------------------------------------

local function CreateRow(timeline)
    local row = { ticks = {}, times = {} }

    -- A faint track behind the skills, so a gap in them reads as a gap.
    row.track = timeline:CreateTexture(nil, "BACKGROUND")
    row.track:SetColorTexture(1, 1, 1, 0.05)

    row.rule = timeline:CreateTexture(nil, "BACKGROUND")
    row.rule:SetColorTexture(Kit.MUTED[1], Kit.MUTED[2], Kit.MUTED[3], 0.6)

    for index = 1, LONGEST_ROW / TICK_SECONDS do
        local tick = timeline:CreateTexture(nil, "BACKGROUND")
        tick:SetColorTexture(Kit.MUTED[1], Kit.MUTED[2], Kit.MUTED[3], 0.6)
        tick:SetSize(1, TICK_HEIGHT)
        row.ticks[index] = tick

        row.times[index] = Kit.Text(timeline, "GameFontDisableSmall")
    end

    return row
end

local function HideRow(row)
    row.track:Hide()
    row.rule:Hide()
    for index, tick in ipairs(row.ticks) do
        tick:Hide()
        row.times[index]:Hide()
    end
end

--- Draws one line's track, rule and times.
---@param index number  which line, counting from 0
---@param reach number  how far along the line the fight goes
---@param scale number  pixels to a second
local function ShowRow(timeline, row, index, reach, scale)
    local top = index * (ROW_HEIGHT + ROW_GAP)

    row.track:ClearAllPoints()
    row.track:SetPoint("TOPLEFT", timeline, "TOPLEFT", 0, -top)
    row.track:SetSize(reach + INSET, SKILL_SIZE + 2 * CRIT_EDGE)
    row.track:Show()

    row.rule:ClearAllPoints()
    row.rule:SetPoint("TOPLEFT", timeline, "TOPLEFT", INSET, -(top + AXIS_TOP))
    row.rule:SetSize(reach - INSET, 1)
    row.rule:Show()

    for place, tick in ipairs(row.ticks) do
        local seconds = (place - 1) * TICK_SECONDS
        local x = INSET + seconds * scale
        local time = row.times[place]

        if x <= reach then
            tick:ClearAllPoints()
            tick:SetPoint("TOPLEFT", timeline, "TOPLEFT", x, -(top + AXIS_TOP))
            tick:Show()

            time:ClearAllPoints()
            time:SetPoint("TOPLEFT", tick, "BOTTOMLEFT", 0, -2)
            time:SetText(Clock(index * rowSeconds + seconds))
            time:Show()
        else
            tick:Hide()
            time:Hide()
        end
    end
end

-- The key ---------------------------------------------------------------------

--- One line that says what the marks mean, with a sample of each.
local function CreateLegend(timeline)
    local legend = CreateFrame("Frame", nil, timeline)
    legend:SetHeight(LEGEND_HEIGHT)

    local function Words(text)
        local words = Kit.Text(legend, "GameFontHighlightSmall")
        words:SetTextColor(unpack(Kit.MUTED))
        words:SetText(text)
        return words
    end

    -- A gold-edged square, standing for any icon that was a critical hit.
    local gold = legend:CreateTexture(nil, "BACKGROUND")
    gold:SetColorTexture(Kit.GOLD[1], Kit.GOLD[2], Kit.GOLD[3], 1)
    gold:SetSize(10, 10)
    gold:SetPoint("LEFT", INSET, 0)

    local inside = legend:CreateTexture(nil, "ARTWORK")
    inside:SetColorTexture(0.15, 0.15, 0.15, 1)
    inside:SetPoint("TOPLEFT", gold, "TOPLEFT", CRIT_EDGE, -CRIT_EDGE)
    inside:SetPoint("BOTTOMRIGHT", gold, "BOTTOMRIGHT", -CRIT_EDGE, CRIT_EDGE)

    local critical = Words("Critical hit")
    critical:SetPoint("LEFT", gold, "RIGHT", 4, 0)

    local cross = Kit.Icon(legend, 12, "bad")
    cross:SetPoint("LEFT", critical, "RIGHT", LEGEND_SPACE, 0)

    local failed = Words("Didn't land")
    failed:SetPoint("LEFT", cross, "RIGHT", 4, 0)

    -- The rest gives way first if the line is ever too long for its width.
    local rest = Words("Small icons are auto attacks.")
    rest:SetPoint("LEFT", failed, "RIGHT", LEGEND_SPACE, 0)
    rest:SetPoint("RIGHT")

    return legend
end

-- The whole thing ------------------------------------------------------------------

--- How long a stretch of the fight the timeline accounts for. A timeline
--- that was cut short says nothing about the time after its last entry,
--- so that time isn't drawn as if nothing happened in it.
local function Covered(fight)
    local items = fight.timeline
    local last = math.max(items[#items].t, 0)
    if #items >= MOST_ITEMS then
        return last
    end
    return math.max(fight.length or 0, last)
end

--- Shows a fight, or hides the timeline if the fight has none on record.
--- The timeline must have been given its width first; it works out its
--- own height.
---@param fight table|nil  a saved fight (see Combat\Fights.lua)
local function Set(self, fight)
    local items = fight and fight.timeline
    if not items or #items == 0 then
        self:Hide()
        return
    end

    -- Whole ticks, so the last time marked is the end of the line.
    local wanted = math.ceil(fight.length / TICK_SECONDS) * TICK_SECONDS
    rowSeconds = math.min(math.max(wanted, SHORTEST_ROW), LONGEST_ROW)

    local width = self:GetWidth()
    local scale = (width - 2 * INSET - SKILL_SIZE) / rowSeconds

    local skills = { size = SKILL_SIZE, top = SKILL_TOP, alpha = 1, row = 0, free = INSET }
    local swings = {
        size = SWING_SIZE,
        top = SWING_TOP,
        alpha = SWING_ALPHA,
        row = 0,
        free = INSET,
    }

    for index, item in ipairs(items) do
        local frame = self.icons[index]
        if not frame then
            frame = CreateIcon(self)
            self.icons[index] = frame
        end

        local lane = IsAutoAttack(item.id) and swings or skills
        local row, x = Seat(lane, math.max(item.t, 0), scale, width)

        DressIcon(frame, item, lane)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", self, "TOPLEFT", x, -(row * (ROW_HEIGHT + ROW_GAP) + lane.top))
        frame:Show()
    end
    for index = #items + 1, #self.icons do
        self.icons[index]:Hide()
    end

    -- Every line runs the full width except the last, which stops where
    -- the fight did, or where the icons do if they were crowded past it.
    local covered = Covered(fight)
    local last = math.max(math.ceil(covered / rowSeconds) - 1, skills.row, swings.row)
    local reach = INSET + (covered - last * rowSeconds) * scale + SKILL_SIZE
    for _, lane in ipairs({ skills, swings }) do
        if lane.row == last then
            reach = math.max(reach, lane.free - SPACE)
        end
    end
    reach = math.min(reach, width - INSET)

    for index = 0, last do
        local row = self.rows[index + 1]
        if not row then
            row = CreateRow(self)
            self.rows[index + 1] = row
        end
        ShowRow(self, row, index, index < last and width - INSET or reach, scale)
    end
    for index = last + 2, #self.rows do
        HideRow(self.rows[index])
    end

    local height = (last + 1) * ROW_HEIGHT + last * ROW_GAP + LEGEND_GAP
    self.legend:SetPoint("TOPLEFT", 0, -height)
    self.legend:SetWidth(width)
    height = height + LEGEND_HEIGHT

    self.matched:SetPoint("TOPLEFT", INSET, -(height + SMALL_PRINT_GAP))
    self.matched:SetWidth(width - 2 * INSET)
    height = height + SMALL_PRINT_GAP + LEGEND_HEIGHT

    local cut = #items >= MOST_ITEMS
    self.cut:SetShown(cut)
    if cut then
        self.cut:SetPoint("TOPLEFT", INSET, -(height + SMALL_PRINT_GAP))
        height = height + SMALL_PRINT_GAP + LEGEND_HEIGHT
    end

    self:SetHeight(height)
    self:Show()
end

--- A timeline, empty until it's given a fight.
---@return table frame  set its width, then call frame:Set(fight). It sets
---                     its own height, and hides itself when the fight
---                     has no timeline on record.
function Timeline.Create(parent)
    local timeline = CreateFrame("Frame", nil, parent)
    timeline:Hide()

    -- Icons and lines are made as they're first needed and kept for the
    -- next fight shown.
    timeline.icons = {}
    timeline.rows = {}

    timeline.legend = CreateLegend(timeline)

    local function SmallPrint(text)
        local words = Kit.Text(timeline, "GameFontHighlightSmall")
        words:SetTextColor(unpack(Kit.MUTED))
        words:SetText(text)
        return words
    end
    timeline.matched = SmallPrint(MATCHED_BY_TIMING)
    timeline.cut = SmallPrint(CUT_SHORT)

    timeline.Set = Set
    return timeline
end
