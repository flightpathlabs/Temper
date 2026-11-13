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

-- Numbers are drawn in the font and at the size chosen in the options,
-- with an outline so they read over any background. A line is that tall
-- plus a little air.
--
-- The fonts are the four the game itself uses, each taken from one of the
-- game's own named fonts rather than by file. The game picks a different
-- file for the same font in some languages, and this way gets it right.
-- A choice's place in the list is its setting value.
Lane.FONTS = {
    { label = "Friz Quadrata, the game's usual", font = "GameFontNormal" },
    { label = "Arial Narrow, as in chat", font = "ChatFontNormal" },
    { label = "Skurri, as the game's own damage numbers", font = "NumberFont_Outline_Huge" },
    { label = "Morpheus, as in quest titles", font = "Fancy16Font" },
}

--- The file of the font chosen in the options.
local function ChosenFont()
    local choice = Lane.FONTS[ns.settings.font] or Lane.FONTS[1]
    local named = _G[choice.font]
    local file = named and named.GetFont and named:GetFont()
    return file or STANDARD_TEXT_FONT
end

local USUAL_FONT_SIZE = 13
local SMALLEST_FONT_SIZE = 6
local LINE_SPACE = 3

-- An ability's icon, when shown, is this many times the line height, and
-- sits this far from its number.
local ICON_SIZE = 0.8
local ICON_GAP = 3

-- A tick's dot is drawn this much smaller than an icon, in the middle of
-- the icon's place, so it reads as a mark rather than a picture.
local DOT_SHRINK = 0.5

-- How quickly numbers step up to make room: the share of the remaining
-- distance covered each second. Higher is snappier.
local STEP_SPEED = 12

-- The "distance" setting, in pixels from the nameplate.
local GAPS = { 4, 22, 46 }

-- For each side of the nameplate: how a number and its icon line up, the
-- corner of the pair that's pinned, the edge of the nameplate it's pinned
-- to, and which way "further" is. Always pinned by the bottom edge,
-- because the column is stacked by counting up from the bottom of each
-- line.
--
-- Above, each number is centred, with its icon to its left and the pair
-- of them centred together. Beside the nameplate, the icons form a
-- straight column next to it and the numbers line up against them:
-- flush left on the right-hand side, flush right on the left.
local SIDES = {
    { layout = "centre", point = "BOTTOM", plate = "TOP", x = 0, y = 1 },
    { layout = "flushRight", point = "BOTTOMRIGHT", plate = "LEFT", x = -1, y = 0 },
    { layout = "flushLeft", point = "BOTTOMLEFT", plate = "RIGHT", x = 1, y = 0 },
}

-- How far other people's numbers sit from the player's own, so that the
-- two never share a column: to the right of the player's when they're
-- centred above the nameplate, and further out when they're beside it.
-- So many times the height of an ordinary number, and never less than the
-- smallest distance: room for a few digits and an icon at any size.
local ASIDE_LINES = 4.5
local LEAST_ASIDE = 56

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
    number.anchor, number.anchorPoint = UIParent, "CENTER"
    number.x, number.y = 0, SPARE_HEIGHT
end

--- Hangs a number and its icon off one another, so that only one of them,
--- the lead, need be pinned to the nameplate. Which leads depends on how
--- the side lines numbers up: the number when they're centred, so the icon
--- can sit off to its left; the icon when they're in a column beside the
--- nameplate, so every icon is in the same place whatever the number's
--- width.
local function Attach(number)
    local text, icon = number.text, number.icon
    text:ClearAllPoints()
    icon:ClearAllPoints()

    if number.layout == "centre" or not number.slot then
        number.lead = text
        icon:SetPoint("RIGHT", text, "LEFT", -ICON_GAP, 0)
    elseif number.layout == "flushLeft" then
        -- Right of the nameplate: icon, then the number reading away.
        number.lead = icon
        text:SetPoint("LEFT", icon, "RIGHT", ICON_GAP, 0)
    else
        -- Left of it: the number, then its icon against the nameplate.
        number.lead = icon
        text:SetPoint("RIGHT", icon, "LEFT", -ICON_GAP, 0)
    end
end

--- How far to move a centred number to the right, so that it and the icon
--- on its left are centred as a pair.
local function Shift(number)
    if number.layout ~= "centre" or not number.hasIcon then
        return 0
    end
    return (number.iconSide + ICON_GAP) / 2
end

local function Pin(number, x, y)
    number.lead:SetPoint(number.point, number.anchor, number.anchorPoint, x + Shift(number), y)
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

    -- At the fixed spot a number is centred, whichever side it was on.
    local dx, dy = x - number.x, y - number.y
    number.layout, number.point = "centre", "BOTTOM"
    UseFixedSpot(number)
    Attach(number)
    pcall(Pin, number, number.x + dx, number.y + dy)
end

local function DropIcon(number)
    number.hasIcon = false
    pcall(number.icon.Hide, number.icon)
end

local function SizeIcon(number, fontSize)
    -- In a column beside the nameplate the numbers line up against their
    -- icons, so every icon there is the same size, whatever the size of
    -- its number. A crit's larger icon would push it out of line.
    if number.layout ~= "centre" then
        fontSize = tonumber(ns.settings.fontSize) or USUAL_FONT_SIZE
    end

    local side = (fontSize + LINE_SPACE) * ICON_SIZE
    number.iconSide = side
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

    Attempt("size", number.text.SetFont, number.text, number.font, size, "OUTLINE")
    if number.slot and number.layout == "centre" then
        SizeIcon(number, size)
    end
end

local function Fade(number, alpha)
    Attempt("fade", number.text.SetAlpha, number.text, alpha)
    local iconAlpha = alpha * number.iconAlpha
    if number.hasIcon and not Attempt("icon", number.icon.SetAlpha, number.icon, iconAlpha) then
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
    number.icon:ClearAllPoints()

    -- Emptied, so it isn't holding an amount we may not read while it
    -- waits to be used again.
    pcall(number.text.ClearText, number.text)
    number.icon:Hide()
    table.insert(spare, number)
end

--- Asks the numbers already showing to step up, so a new one of the
--- given height has room. Only numbers pinned to the same thing share a
--- column; ones still fading over another enemy are left alone.
local function MakeRoom(anchor, aside, height)
    local floor = height

    for index = #showing, 1, -1 do
        local number = showing[index]
        if number.anchor == anchor and number.aside == aside then
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
    number.icon:Hide()
    return number
end

-- A plain white disc, which the game keeps for cutting portraits round.
-- Tinted, it makes the dot shown for a tick.
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

--- Gives a number its icon. An ability's is trimmed a touch, as the game
--- does, to lose the border drawn into every one. A dot is the disc above,
--- tinted, drawn small in the middle of the icon's place.
---@param texture table  the number's icon
---@param look table  as for Lane.Show: icon, or dot
local function SetIcon(texture, look)
    if look.dot then
        -- Drawn small by asking for more of the picture than there is,
        -- with nothing round the edge. Should the game not allow that, a
        -- dot the full size of an icon will do.
        local margin = DOT_SHRINK / 2 / (1 - DOT_SHRINK)
        if
            pcall(texture.SetTexture, texture, DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        then
            texture:SetTexCoord(-margin, 1 + margin, -margin, 1 + margin)
        else
            texture:SetTexture(DISC)
            texture:SetTexCoord(0, 1, 0, 1)
        end
        texture:SetVertexColor(look.dot[1], look.dot[2], look.dot[3])
    else
        texture:SetTexture(look.icon)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        texture:SetVertexColor(1, 1, 1)
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
---@param look table  { r, g, b, scale, crit, icon, dot, iconAlpha,
---                   slot }: icon is a texture to show beside the number,
---                   dot a colour for a small dot to show instead,
---                   iconAlpha how solid either is (for the guesses that
---                   should stay in the background), and slot true to keep
---                   the icon's place empty when there's neither, so that a
---                   word lines up with the numbers in a column; aside true
---                   for somebody else's, which go in a column of their own
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
    local iconsWork = not Lane.complaints.icon
    local wantsIcon = (look.icon ~= nil or look.dot ~= nil) and iconsWork
    number.slot = wantsIcon or (look.slot and iconsWork) or false
    number.point = side.point
    if plate then
        number.layout = side.layout
        number.anchor, number.anchorPoint = plate, side.plate
        number.x, number.y = side.x * gap, side.y * gap
    else
        number.layout = "centre"
        number.point = "BOTTOM"
        UseFixedSpot(number)
    end
    Attach(number)

    -- Somebody else's, in a column of its own: further out beside the
    -- nameplate, or off to the right above it and at the fixed spot.
    number.aside = look.aside or false
    local outward = (plate and side.x ~= 0) and side.x or 1
    if number.aside then
        local base = tonumber(ns.settings.fontSize) or USUAL_FONT_SIZE
        number.x = number.x + outward * math.max(LEAST_ASIDE, base * ASIDE_LINES)
    end

    -- A lane beside the nameplate arcs away from it. One above takes
    -- turns, but somebody else's always arcs away from the player's own.
    if side.x ~= 0 or number.aside then
        number.lean = outward
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

    number.rise = 0
    number.lift = 0
    number.liftWanted = 0
    MakeRoom(number.anchor, number.aside, number.height)

    -- A spent number was last seen faded to nothing. Made solid here,
    -- while it's pinned to nothing, so it shows even if the client later
    -- objects to fading.
    number.text:SetAlpha(1)
    number.icon:SetAlpha(1)
    number.iconAlpha = look.iconAlpha or 1

    -- A font has to be set before any text is.
    number.font = ChosenFont()
    number.text:SetFont(number.font, number.drawnSize, "OUTLINE")
    number.text:SetText(value)
    number.text:SetTextColor(look.r, look.g, look.b)
    number.text:Show()

    -- On the books before anything else can go wrong, so that whatever
    -- happens the number is taken down again when its time is up.
    table.insert(showing, number)

    number.hasIcon = wantsIcon
        and Attempt("icon", SetIcon, number.icon, look)
        and Attempt("icon", number.icon.Show, number.icon)
    if not number.hasIcon then
        DropIcon(number)
    end

    -- Sized even when it isn't shown, when a word keeps its place.
    if number.slot then
        SizeIcon(number, number.drawnSize)
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
