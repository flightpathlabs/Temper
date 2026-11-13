local _, ns = ...

-- How a number moves while it's on screen.
--
-- Each motion is a function of how far through its life a number is, from
-- 0 to 1. It answers with where the number should be relative to where it
-- appeared, how solid it is and how large. Nothing here touches a frame,
-- which keeps the motions easy to add to and easy to reason about.
--
-- Whatever the motion, a number arriving on the heels of another nudges
-- the earlier one up to make room (see Lane.lua).

local Motions = {}
ns.Motions = Motions

-- How fast the rising stream climbs, in pixels a second. Slow enough to
-- read, quick enough that a line has cleared before the next arrives.
local RISE_SPEED = 26

--- Full strength until `from`, then a steady fade to nothing.
local function Fade(progress, from)
    if progress <= from then
        return 1
    end
    return 1 - (progress - from) / (1 - from)
end

-- The numbers in a motion's name are its setting value, so the order here
-- is the order in the options and must not be shuffled.

Motions[1] = {
    label = "Rising stream",
    -- Straight up at one steady pace for as long as it stays, like lines
    -- scrolling up a page. Nothing sideways, nothing sudden.
    ---@param life number  seconds the number is on screen for
    ---@return number dx, number dy, number alpha, number scale
    move = function(progress, _, life)
        return 0, RISE_SPEED * progress * life, Fade(progress, 0.7), 1
    end,
}

Motions[2] = {
    label = "Stay and step up",
    -- Stays where it lands. Each new number steps the column up one line,
    -- like lines in a chat window, and the oldest fade off the top.
    move = function(progress)
        return 0, 0, Fade(progress, 0.75), 1
    end,
}

Motions[3] = {
    label = "Arc away",
    -- Up and over, like something tossed aside. `lean` is -1 to go left
    -- and 1 to go right.
    move = function(progress, lean)
        return lean * 70 * progress, 120 * progress * (1 - progress), Fade(progress, 0.65), 1
    end,
}

Motions[4] = {
    label = "Shrink away",
    move = function(progress)
        return 0, 14 * progress, Fade(progress, 0.5), 1 - 0.5 * progress
    end,
}

-- How a critical hit lands ------------------------------------------------------
--
-- On top of whichever motion is chosen, a critical hit can make an
-- entrance. Each of these is a function of how long ago the number
-- appeared. It answers with how much larger than normal the number
-- should be drawn and how far sideways it's been knocked, and settles
-- to 1 and 0 within a fraction of a second.

--- Swells to `extra` over its size and settles within `seconds`.
local function Pop(extra, seconds)
    return function(age)
        if age >= seconds then
            return 1, 0
        end
        return 1 + extra * (1 - age / seconds), 0
    end
end

local SHAKE_SECONDS = 0.35
local SHAKE_WIDTH = 5
local SHAKE_SPEED = 55

-- As with the motions, a landing's place in this list is its setting
-- value.
Motions.Landings = {
    {
        label = "Nothing",
        land = function()
            return 1, 0
        end,
    },
    { label = "A small pop", land = Pop(0.25, 0.14) },
    { label = "A big pop", land = Pop(0.7, 0.22) },
    {
        label = "A shake",
        -- Side to side, quickly, and less each time.
        land = function(age)
            if age >= SHAKE_SECONDS then
                return 1, 0
            end
            local strength = 1 - age / SHAKE_SECONDS
            return 1, math.sin(age * SHAKE_SPEED) * SHAKE_WIDTH * strength
        end,
    },
}
