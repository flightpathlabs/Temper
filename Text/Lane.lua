local _, ns = ...

-- The lane: one tidy column of numbers by an enemy's nameplate.
--
-- Each number is a piece of text pinned to the nameplate of the enemy it
-- landed on, so it follows that enemy around the screen without our doing
-- anything. Each enemy being fought gets a column of its own. The client
-- won't say where a nameplate is, and won't let anything pinned to one be
-- measured either. So a number is only ever moved by changing how far it
-- sits from the nameplate, never by asking where it is now.
--
-- New numbers appear at the bottom of the column and rise steadily, so
-- the column reads like a short scrolling log of recent hits. Two that
-- arrive together are kept a line apart.
--
-- When the target has no nameplate, numbers appear at a fixed spot above
-- the middle of the screen instead.

local Lane = {}
ns.Lane = Lane

local MAX_NUMBERS = 24

-- How long a number stays, by the "stay" setting. A critical hit lingers
-- a little longer than the rest.
local STAY_SECONDS = { 1.4, 2.8, 4.5 }
local CRIT_LINGER = 1.25

-- The size of a number at normal size, in the game's ordinary text font
-- with an outline so it reads over any background, and the room to leave
-- between one number and the next.
local FONT_SIZE = 13
local LINE_HEIGHT = FONT_SIZE + 3
local FONT = GameFontNormal:GetFont() or STANDARD_TEXT_FONT

-- An ability's icon, when shown, is this many times the line height.
local ICON_SIZE = 0.8

-- How quickly numbers step up to make room: the share of the remaining
-- distance covered each second. Higher is snappier.
local STEP_SPEED = 12

-- Setting values to sizes and distances.
local SIZES = { 0.85, 1, 1.25 }
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

-- A nameplate can vanish between a number being pinned and being moved,
-- which is no reason to give up on nameplates. This many refusals in a
-- row, with no success between them, is.
local REFUSALS_ALLOWED = 3

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
local PREVIEW_SECONDS = 4
local previews = 0

-- Set once the client has refused to pin text to a nameplate too often,
-- after which the fixed spot is used for the rest of the session.
Lane.refusal = nil

-- Set if the client refuses to draw an icon beside a pinned number, after
-- which icons are left off for the rest of the session.
Lane.iconRefusal = nil
local refusals = 0

local function UseFixedSpot(number)
    number.point, number.anchor, number.anchorPoint = "CENTER", UIParent, "CENTER"
    number.x, number.y = 0, SPARE_HEIGHT
end

local function Put(number, x, y, alpha, scale)
    local text = number.text
    text:SetPoint(number.point, number.anchor, number.anchorPoint, x, y)
    text:SetAlpha(alpha)

    -- The size proper is in the font (see Lane.Show). This is only for
    -- the brief swell of a critical hit and for the motion that shrinks.
    text:SetTextScale(scale)
end

local function ShowIcon(number, texture)
    number.icon:SetTexture(texture)
    number.icon:Show()
end

local function PutIcon(number, alpha, scale)
    local size = LINE_HEIGHT * ICON_SIZE * scale * number.scale
    number.icon:SetSize(size, size)
    number.icon:SetAlpha(alpha)
end

--- Moves a number to where its motion says it should be by now.
local function Place(number, now, elapsed)
    local progress = (now - number.start) / number.life
    local motion = ns.Motions[ns.settings.motion] or ns.Motions[1]
    local dx, dy, alpha, scale = motion.move(progress, number.lean, number.life)

    -- Step up toward the height the newer numbers have asked for, quickly
    -- but not in one jump.
    local remaining = number.liftWanted - number.lift
    number.lift = number.lift + remaining * math.min(1, elapsed * STEP_SPEED)

    number.rise = dy
    if number.crit then
        scale = scale * ns.Motions.Pop(now - number.start)
    end

    local x, y = number.x + dx, number.y + dy + number.lift
    local ok, problem = pcall(Put, number, x, y, alpha, scale)
    if ok and number.anchor ~= UIParent then
        refusals = 0
    end

    -- The icon is handled apart from the number, so that if the client
    -- objects to it the numbers themselves carry on as before.
    if number.hasIcon then
        local drawn, objection = pcall(PutIcon, number, alpha, scale)
        if not drawn then
            Lane.iconRefusal = tostring(objection)
            number.hasIcon = false
            number.icon:Hide()
        end
    end

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
    number.icon:Hide()
    table.insert(spare, number)
end

--- Asks the numbers already showing to step up, so the new one has room.
-- Only numbers pinned to the same thing share a column; ones still fading
-- over the last target are left alone.
local function MakeRoom(anchor, newScale)
    local floor = LINE_HEIGHT * newScale

    for index = #showing, 1, -1 do
        local number = showing[index]
        if number.anchor == anchor then
            local height = number.rise + number.liftWanted
            if height < floor then
                number.liftWanted = number.liftWanted + (floor - height)
                height = floor
            end
            floor = height + LINE_HEIGHT * number.scale
        end
    end
end

holder:SetScript("OnUpdate", function(_, elapsed)
    local now = GetTime()

    for index = #showing, 1, -1 do
        local number = showing[index]
        if now - number.start >= number.life then
            Retire(index)
        else
            Place(number, now, elapsed)
        end
    end

    if #showing == 0 then
        holder:Hide()
    end
end)

local function NewNumber()
    local number = {
        text = holder:CreateFontString(nil, "OVERLAY"),
        icon = holder:CreateTexture(nil, "OVERLAY"),
    }

    -- The icon rides just to the left of its number. Trimmed a touch, as
    -- the game does, to lose the border drawn into every icon.
    number.icon:SetPoint("RIGHT", number.text, "LEFT", -2, 0)
    number.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    number.icon:Hide()
    return number
end

--- Adds a number, or a word such as "Dodge", to the lane.
---@param value any  what to show. May be an amount the client won't let us
---                  read, which is why it goes straight to the text and is
---                  never looked at here.
---@param look table  { r, g, b, scale, crit, icon }; icon is a texture to
---                   show beside the number, if any
---@param unit string|nil  whose nameplate to pin it to; the target's if
---                        not given
function Lane.Show(value, look, unit)
    if #showing >= MAX_NUMBERS then
        Retire(1)
    end

    local number = table.remove(spare) or NewNumber()

    local side = SIDES[ns.settings.laneSide] or SIDES[1]
    local gap = GAPS[ns.settings.laneDistance] or GAPS[1]

    local found, plate
    if not Lane.refusal then
        found, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit or "target")
    end
    local wantsIcon = look.icon ~= nil and not Lane.iconRefusal
    if found and plate then
        number.point, number.anchor, number.anchorPoint = side.point, plate, side.plate
        number.x, number.y = side.x * gap, side.y * gap

        -- To the right of the nameplate, the icon would sit on top of it.
        if wantsIcon and side.x > 0 then
            number.x = number.x + LINE_HEIGHT
        end
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
    number.life = STAY_SECONDS[ns.settings.stay] or STAY_SECONDS[2]
    if look.crit then
        number.life = number.life * CRIT_LINGER
    end
    number.scale = look.scale * (SIZES[ns.settings.textSize] or 1)
    number.crit = look.crit

    -- A font has to be set before any text is, and this is where the
    -- number gets its size.
    number.text:SetFont(FONT, math.floor(FONT_SIZE * number.scale + 0.5), "OUTLINE")
    number.rise = 0
    number.lift = 0
    number.liftWanted = 0

    MakeRoom(number.anchor, number.scale)

    number.text:SetText(value)
    number.text:SetTextColor(look.r, look.g, look.b)
    number.text:Show()

    -- On the books before anything else can go wrong, so that whatever
    -- happens the number is taken down again when its time is up.
    table.insert(showing, number)

    number.hasIcon = wantsIcon and pcall(ShowIcon, number, look.icon)
    if not number.hasIcon then
        pcall(number.icon.Hide, number.icon)
    end

    Place(number, number.start, 0)
    holder:Show()
end

--- A handful of sample numbers, so a change in the options can be seen at
--- once without finding something to hit.
function Lane.Preview()
    -- The options window would otherwise be in the way.
    previews = previews + 1
    local thisPreview = previews
    holder:SetFrameStrata("TOOLTIP")
    C_Timer.After(PREVIEW_SECONDS + (STAY_SECONDS[ns.settings.stay] or 0), function()
        if thisPreview == previews then
            holder:SetFrameStrata("LOW")
        end
    end)

    for index = 0, 4 do
        C_Timer.After(index * 0.45, function()
            if thisPreview == previews then
                ns.Feed.ShowSample(index == 3)
            end
        end)
    end
end
