local _, ns = ...

-- The lane: one tidy column of numbers by the target's nameplate.
--
-- Each number is a piece of text pinned to the nameplate, so it follows
-- the enemy around the screen without our doing anything. The client
-- won't say where a nameplate is, and won't let anything pinned to one be
-- measured either. So a number is only ever moved by changing how far it
-- sits from the nameplate, never by asking where it is now.
--
-- When the target has no nameplate, numbers appear at a fixed spot above
-- the middle of the screen instead.

local Lane = {}
ns.Lane = Lane

local MAX_NUMBERS = 14
local LIFETIME = 1.2
local CRIT_LIFETIME = 1.6

-- Room to leave between one number and the next, at normal size.
local LINE_HEIGHT = 22

-- The game's combat font is drawn very large and scaled down by whoever
-- uses it. This brings it to about the height of a line.
local FONT_SCALE = LINE_HEIGHT / 64

-- A nameplate can vanish between a number being pinned and being moved,
-- which is no reason to give up on nameplates. This many refusals is.
local REFUSALS_ALLOWED = 3

-- Setting values to sizes and distances.
local SIZES = { 0.8, 1, 1.3 }
local GAPS = { 4, 22, 46 }

-- For each side of the nameplate: the edge of the text that's pinned, the
-- edge of the nameplate it's pinned to, and which way "further" is.
local SIDES = {
    { point = "BOTTOM", plate = "TOP", x = 0, y = 1 },
    { point = "RIGHT", plate = "LEFT", x = -1, y = 0 },
    { point = "LEFT", plate = "RIGHT", x = 1, y = 0 },
}

-- Where numbers go when there's no nameplate to pin them to.
local SPARE_HEIGHT = 140

-- A frame of our own to own the text, sitting under the game's windows.
-- It's shown only while there are numbers to move.
local holder = CreateFrame("Frame", nil, UIParent)
holder:SetFrameStrata("LOW")
holder:Hide()

-- Numbers on screen, oldest first, and spent ones waiting to be reused.
local showing = {}
local spare = {}

-- Arcing numbers take turns going left and right.
local nextLean = 1

-- How long the sample numbers from the options page stay in front of the
-- game's windows, and how many times they've been asked for.
local PREVIEW_SECONDS = 2.5
local previews = 0

-- Set once the client has refused to pin text to a nameplate too often,
-- after which the fixed spot is used for the rest of the session.
Lane.refusal = nil
local refusals = 0

local function UseFixedSpot(number)
    number.point, number.anchor, number.anchorPoint = "CENTER", UIParent, "CENTER"
    number.x, number.y = 0, SPARE_HEIGHT
end

local function Put(number, x, y, alpha, scale)
    local text = number.text
    text:SetPoint(number.point, number.anchor, number.anchorPoint, x, y)
    text:SetAlpha(alpha)
    text:SetTextScale(scale)
end

--- Moves a number to where its motion says it should be by now.
local function Place(number, now)
    local progress = (now - number.start) / number.life
    local motion = ns.Motions[ns.settings.motion] or ns.Motions[1]
    local dx, dy, alpha, scale = motion.move(progress, number.lean)

    number.rise = dy
    scale = scale * number.scale * FONT_SCALE
    if number.crit then
        scale = scale * ns.Motions.Pop(now - number.start)
    end

    local x, y = number.x + dx, number.y + dy + number.lift
    local ok, problem = pcall(Put, number, x, y, alpha, scale)
    if ok or number.anchor == UIParent then
        return
    end

    -- The nameplate wouldn't have it. Carry on at the fixed spot, and if
    -- this keeps happening stop trying nameplates until the next session.
    refusals = refusals + 1
    if refusals >= REFUSALS_ALLOWED then
        Lane.refusal = tostring(problem)
    end
    number.text:ClearAllPoints()
    UseFixedSpot(number)
    pcall(Put, number, number.x + dx, number.y + dy + number.lift, alpha, scale)
end

local function Retire(index)
    local number = table.remove(showing, index)
    number.text:Hide()
    number.text:ClearAllPoints()
    table.insert(spare, number)
end

--- Nudges the numbers already showing upward, so the new one has room.
-- Rapid hits would otherwise land on top of each other.
-- Only numbers pinned to the same thing share a column; ones still fading
-- over the last target are left alone.
local function MakeRoom(anchor, newScale)
    local floor = LINE_HEIGHT * newScale

    for index = #showing, 1, -1 do
        local number = showing[index]
        if number.anchor == anchor then
            local height = number.rise + number.lift
            if height < floor then
                number.lift = number.lift + (floor - height)
                height = floor
            end
            floor = height + LINE_HEIGHT * number.scale
        end
    end
end

holder:SetScript("OnUpdate", function()
    local now = GetTime()

    for index = #showing, 1, -1 do
        local number = showing[index]
        if now - number.start >= number.life then
            Retire(index)
        else
            Place(number, now)
        end
    end

    if #showing == 0 then
        holder:Hide()
    end
end)

--- Adds a number, or a word such as "Dodge", to the lane.
---@param value any  what to show. May be an amount the client won't let us
---                  read, which is why it goes straight to the text and is
---                  never looked at here.
---@param look table  { r, g, b, scale, crit }
function Lane.Show(value, look)
    if #showing >= MAX_NUMBERS then
        Retire(1)
    end

    local number = table.remove(spare)
    if not number then
        number = { text = holder:CreateFontString(nil, "OVERLAY", "CombatTextFontOutline") }
    end

    local side = SIDES[ns.settings.laneSide] or SIDES[1]
    local gap = GAPS[ns.settings.laneDistance] or GAPS[1]

    local found, plate
    if not Lane.refusal then
        found, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
    end
    if found and plate then
        number.point, number.anchor, number.anchorPoint = side.point, plate, side.plate
        number.x, number.y = side.x * gap, side.y * gap
    else
        UseFixedSpot(number)
    end

    -- A lane beside the nameplate arcs away from it. One above takes turns.
    if side.x ~= 0 then
        number.lean = side.x
    else
        number.lean = nextLean
        nextLean = -nextLean
    end

    number.start = GetTime()
    number.life = look.crit and CRIT_LIFETIME or LIFETIME
    number.scale = look.scale * (SIZES[ns.settings.textSize] or 1)
    number.crit = look.crit
    number.rise = 0
    number.lift = 0

    MakeRoom(number.anchor, number.scale)

    number.text:SetText(value)
    number.text:SetTextColor(look.r, look.g, look.b)
    number.text:Show()

    table.insert(showing, number)
    Place(number, number.start)
    holder:Show()
end

--- A few sample numbers, so a change in the options can be seen at once
--- without finding something to hit.
function Lane.Preview()
    -- The options window would otherwise be in the way.
    previews = previews + 1
    local thisPreview = previews
    holder:SetFrameStrata("TOOLTIP")
    C_Timer.After(PREVIEW_SECONDS, function()
        if thisPreview == previews then
            holder:SetFrameStrata("LOW")
        end
    end)

    local white = { r = 1, g = 1, b = 1, scale = 1 }
    Lane.Show(41, white)
    C_Timer.After(0.25, function()
        Lane.Show(38, white)
    end)
    C_Timer.After(0.5, function()
        ns.Feed.ShowSample()
    end)
end
