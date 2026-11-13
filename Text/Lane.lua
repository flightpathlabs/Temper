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
-- An enemy with no nameplate gives us nothing to pin to, and its numbers
-- appear at a fixed spot above the middle of the screen instead.
--
-- The client is touchy about text that's pinned to a nameplate, so each
-- thing done to a number (pinning it, fading it, resizing it, giving it
-- an icon) is tried on its own. Only a refusal to pin sends a number to
-- the fixed spot. Anything else the client objects to is dropped for the
-- session and the numbers carry on without it.

local Lane = {}
ns.Lane = Lane

local MAX_NUMBERS = 24

-- How long a number stays, by the "stay" setting. A critical hit lingers
-- a little longer than the rest.
local STAY_SECONDS = { 1.4, 2.8, 4.5 }
local CRIT_LINGER = 1.25

-- Numbers are drawn in the game's ordinary text font, with an outline so
-- they read over any background, at the size chosen in the options. A
-- line is that tall plus a little air.
local FONT = GameFontNormal:GetFont() or STANDARD_TEXT_FONT
local USUAL_FONT_SIZE = 13
local SMALLEST_FONT_SIZE = 6
local LINE_SPACE = 3

-- An ability's icon, when shown, is this many times the line height.
local ICON_SIZE = 0.8

-- How quickly numbers step up to make room: the share of the remaining
-- distance covered each second. Higher is snappier.
local STEP_SPEED = 12

-- The "distance" setting, in pixels from the nameplate.
local GAPS = { 4, 22, 46 }

-- For each side of the nameplate: the corner of the text that's pinned,
-- the edge of the nameplate it's pinned to, and which way "further" is.
-- Text is always pinned by its bottom edge, because the column is stacked
-- by counting up from the bottom of each line.
local SIDES = {
    { point = "BOTTOM", plate = "TOP", x = 0, y = 1 },
    { point = "BOTTOMRIGHT", plate = "LEFT", x = -1, y = 0 },
    { point = "BOTTOMLEFT", plate = "RIGHT", x = 1, y = 0 },
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

-- Set once the client has refused to pin text to a nameplate too often,
-- after which the fixed spot is used for the rest of the session.
Lane.refusal = nil
local refusals = 0

-- Anything else the client has objected to, in its own words, by what
-- was being tried: "fade", "size" or "icon". Each is tried once and then
-- left alone. `/temper check` reads these out.
Lane.complaints = {}

-- For `/temper check`: how many numbers this session followed a
-- nameplate, how many had none to follow, and how many found one only
-- for the game to refuse the pin, with what it said the last time.
Lane.pinned = 0
Lane.loose = 0
Lane.knockedOff = 0
Lane.lastRefusal = nil

--- Tries something the client might object to. Once it has objected,
--- that thing isn't tried again this session.
---@param what string  a key for Lane.complaints
---@return boolean  true if it went through
local function Attempt(what, method, ...)
    if Lane.complaints[what] then
        return false
    end

    local ok, problem = pcall(method, ...)
    if not ok then
        Lane.complaints[what] = tostring(problem)
    end
    return ok
end

local function UseFixedSpot(number)
    number.point, number.anchor, number.anchorPoint = "BOTTOM", UIParent, "CENTER"
    number.x, number.y = 0, SPARE_HEIGHT
end

local function Pin(number, x, y)
    number.text:SetPoint(number.point, number.anchor, number.anchorPoint, x, y)
end

--- Moves a number to its place for this frame. If the nameplate won't
--- have it, the number carries on at the fixed spot.
local function Move(number, x, y)
    local pinned, problem = pcall(Pin, number, x, y)
    if number.anchor == UIParent then
        return
    end

    if pinned then
        refusals = 0
        return
    end

    Lane.pinned = Lane.pinned - 1
    Lane.knockedOff = Lane.knockedOff + 1
    Lane.lastRefusal = tostring(problem)

    -- If this keeps happening, stop trying nameplates until next session.
    refusals = refusals + 1
    if refusals >= REFUSALS_ALLOWED then
        Lane.refusal = Lane.lastRefusal
    end

    local dx, dy = x - number.x, y - number.y
    number.text:ClearAllPoints()
    UseFixedSpot(number)
    pcall(Pin, number, number.x + dx, number.y + dy)
end

local function DropIcon(number)
    number.hasIcon = false
    pcall(number.icon.Hide, number.icon)
end

local function SizeIcon(number, fontSize)
    local side = (fontSize + LINE_SPACE) * ICON_SIZE
    if not Attempt("icon", number.icon.SetSize, number.icon, side, side) then
        DropIcon(number)
    end
end

--- Draws a number at `scale` times its own size. The font is only set
--- again when that comes to a different whole size, which outside a
--- critical hit's landing and the motion that shrinks is never.
local function Resize(number, scale)
    local size = math.max(SMALLEST_FONT_SIZE, math.floor(number.size * scale + 0.5))
    if size == number.drawnSize then
        return
    end
    number.drawnSize = size

    Attempt("size", number.text.SetFont, number.text, FONT, size, "OUTLINE")
    if number.hasIcon then
        SizeIcon(number, size)
    end
end

local function Fade(number, alpha)
    Attempt("fade", number.text.SetAlpha, number.text, alpha)
    if number.hasIcon and not Attempt("icon", number.icon.SetAlpha, number.icon, alpha) then
        DropIcon(number)
    end
end

--- Puts a number where its motion says it should be by now.
local function Place(number, now, elapsed)
    local age = now - number.start
    local motion = ns.Motions[ns.settings.motion] or ns.Motions[1]
    local dx, dy, alpha, scale = motion.move(age / number.life, number.lean, number.life)

    -- Step up toward the height the newer numbers have asked for, quickly
    -- but not in one jump.
    local remaining = number.liftWanted - number.lift
    number.lift = number.lift + remaining * math.min(1, elapsed * STEP_SPEED)
    number.rise = dy

    if number.crit then
        local landings = ns.Motions.Landings
        local landing = landings[ns.settings.critLanding] or landings[1]
        local swell, knock = landing.land(age)
        scale = scale * swell
        dx = dx + knock
    end

    Move(number, number.x + dx, number.y + dy + number.lift)
    Fade(number, alpha)
    Resize(number, scale)
end

local function Retire(index)
    local number = table.remove(showing, index)
    number.text:Hide()
    number.text:ClearAllPoints()

    -- Emptied, so it isn't holding an amount we may not read while it
    -- waits to be used again.
    pcall(number.text.ClearText, number.text)
    number.icon:Hide()
    table.insert(spare, number)
end

--- Asks the numbers already showing to step up, so a new one of the
--- given height has room. Only numbers pinned to the same thing share a
--- column; ones still fading over another enemy are left alone.
local function MakeRoom(anchor, height)
    local floor = height

    for index = #showing, 1, -1 do
        local number = showing[index]
        if number.anchor == anchor then
            local bottom = number.rise + number.liftWanted
            if bottom < floor then
                number.liftWanted = number.liftWanted + (floor - bottom)
                bottom = floor
            end
            floor = bottom + number.height
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

    -- The icon rides just to the left of its number.
    number.icon:SetPoint("RIGHT", number.text, "LEFT", -2, 0)
    number.icon:Hide()
    return number
end

--- Gives a number its icon: an ability's, trimmed a touch as the game
--- does to lose the border drawn into every one, or one of the game's own
--- small pictures, which has no border and is used whole.
---@param texture table  the number's icon
---@param icon number|string|nil  a spell's texture
---@param atlas string|nil  one of the game's pictures, used instead
local function SetIcon(texture, icon, atlas)
    if atlas then
        -- A picture the game doesn't have isn't an error, but would leave
        -- whatever icon this number had the last time it was used.
        if not texture:SetAtlas(atlas) then
            texture:SetTexture(nil)
        end
        texture:SetTexCoord(0, 1, 0, 1)
    else
        texture:SetTexture(icon)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

--- Says, once ever, why the numbers aren't following the enemy: with
--- enemy nameplates switched off there's nothing to pin them to.
local function MentionNameplates()
    if ns.db.toldAboutNameplates or GetCVarBool("nameplateShowEnemies") then
        return
    end
    ns.db.toldAboutNameplates = true

    local key = GetBindingKey("NAMEPLATES")
    ns.Print(
        "Your damage numbers follow each enemy's nameplate, and enemy nameplates are "
            .. "switched off, so they're showing mid-screen instead. Turn nameplates on%s "
            .. "and each enemy gets its own.",
        key and (" (%s)"):format(GetBindingText(key)) or ""
    )
end

--- The nameplate to pin a number to, if there is one.
local function PlateFor(unit)
    if Lane.refusal then
        return nil
    end

    local found, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit or "target")
    if found and plate then
        Lane.pinned = Lane.pinned + 1
        return plate
    end

    Lane.loose = Lane.loose + 1
    MentionNameplates()
    return nil
end

--- Adds a number, or a word such as "Dodge", to the lane.
---@param value any  what to show. May be an amount the client won't let us
---                  read, which is why it goes straight to the text and is
---                  never looked at here.
---@param look table  { r, g, b, scale, crit, icon, atlas }; icon is a
---                   texture to show beside the number, if any, and atlas
---                   one of the game's pictures to show instead
---@param unit string|nil  whose nameplate to pin it to; the target's if
---                        not given
---@param stand table|nil  a frame of our own to pin it to instead of a
---                        nameplate, for the example in the options
function Lane.Show(value, look, unit, stand)
    if #showing >= MAX_NUMBERS then
        Retire(1)
    end

    local number = table.remove(spare) or NewNumber()

    local side = SIDES[ns.settings.laneSide] or SIDES[1]
    local gap = GAPS[ns.settings.laneDistance] or GAPS[1]

    local plate = stand or PlateFor(unit)
    local wantsIcon = (look.icon ~= nil or look.atlas ~= nil) and not Lane.complaints.icon
    if plate then
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
    number.life = STAY_SECONDS[ns.settings.stay] or STAY_SECONDS[2]
    if look.crit then
        number.life = number.life * CRIT_LINGER
    end
    number.crit = look.crit

    -- Its own size, before any swelling or shrinking, and the height of
    -- the line it takes up in the column.
    number.size = (tonumber(ns.settings.fontSize) or USUAL_FONT_SIZE) * look.scale
    number.drawnSize = math.max(SMALLEST_FONT_SIZE, math.floor(number.size + 0.5))
    number.height = number.drawnSize + LINE_SPACE

    -- To the right of the nameplate, the icon would sit on top of it.
    if plate and wantsIcon and side.x > 0 then
        number.x = number.x + number.height
    end

    number.rise = 0
    number.lift = 0
    number.liftWanted = 0
    MakeRoom(number.anchor, number.height)

    -- A spent number was last seen faded to nothing. Made solid here,
    -- while it's pinned to nothing, so it shows even if the client later
    -- objects to fading.
    number.text:SetAlpha(1)
    number.icon:SetAlpha(1)

    -- A font has to be set before any text is.
    number.text:SetFont(FONT, number.drawnSize, "OUTLINE")
    number.text:SetText(value)
    number.text:SetTextColor(look.r, look.g, look.b)
    number.text:Show()

    -- On the books before anything else can go wrong, so that whatever
    -- happens the number is taken down again when its time is up.
    table.insert(showing, number)

    number.hasIcon = wantsIcon
        and Attempt("icon", SetIcon, number.icon, look.icon, look.atlas)
        and Attempt("icon", number.icon.Show, number.icon)
    if number.hasIcon then
        SizeIcon(number, number.drawnSize)
    else
        DropIcon(number)
    end

    Place(number, number.start, 0)
    holder:Show()
end

--- Draws the numbers in front of the game's windows, or back under them.
--- In front is for the example in the options, which would otherwise be
--- hidden behind the Options window.
function Lane.BringForward(forward)
    holder:SetFrameStrata(forward and "DIALOG" or "LOW")
end

--- Takes down at once every number pinned to a frame of our own.
---@param stand table  the frame, as given to Lane.Show
function Lane.Clear(stand)
    for index = #showing, 1, -1 do
        if showing[index].anchor == stand then
            Retire(index)
        end
    end
end
