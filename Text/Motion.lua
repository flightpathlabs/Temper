local _, ns = ...

-- How a number moves while it's on screen.
--
-- Each motion is a function of how far through its life a number is, from
-- 0 to 1. It answers with where the number should be relative to where it
-- appeared, how solid it is and how large. Nothing here touches a frame,
-- which keeps the motions easy to add to and easy to reason about.
--
-- Whatever the motion, a new number nudges the ones before it upward to
-- make room (see Lane.lua). In the steady stream that nudge is the only
-- movement there is.

local Motions = {}
ns.Motions = Motions

-- A critical hit lands oversized and settles within this many seconds.
local POP_SECONDS = 0.14
local POP_SIZE = 0.35

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
    label = "Steady stream",
    -- Stays where it lands. Each new number steps the column up one line,
    -- like lines in a chat window, and the oldest fade off the top.
    ---@return number dx, number dy, number alpha, number scale
    move = function(progress)
        return 0, 0, Fade(progress, 0.75), 1
    end,
}

Motions[2] = {
    label = "Rise and fade",
    move = function(progress)
        return 0, 46 * progress, Fade(progress, 0.7), 1
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

--- The extra size a critical hit carries just after it lands.
---@param age number  seconds since the number appeared
---@return number  a multiplier, 1 once the pop is over
function Motions.Pop(age)
    if age >= POP_SECONDS then
        return 1
    end
    return 1 + POP_SIZE * (1 - age / POP_SECONDS)
end
