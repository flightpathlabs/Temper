local addonName, ns = ...

-- Temper
--
-- Everything hangs off the private table the client hands every file in an
-- addon (ns). Nothing here is global except the saved-variables table, the
-- slash command, the key binding and the addon-list click handler, which
-- the client needs to find by name.

ns.name = addonName

-- What the addon is called wherever a player reads it.
ns.TITLE = "Temper"

-- The longest note a player can leave on a fight or a recording.
ns.NOTE_LENGTH = 120

--- Formats a whole number the way the game does, with thousands separated.
---@param number number
---@return string
function ns.Number(number)
    return BreakUpLargeNumbers(math.floor(number + 0.5))
end

--- Formats a figure that needs one decimal place to mean anything, such as
--- damage per second at low level.
---@param number number
---@return string  e.g. "7.8", "112"
function ns.Rate(number)
    if number >= 100 then
        return ns.Number(number)
    end
    return ("%.1f"):format(number)
end

--- Formats a share of something as a percentage.
---@param fraction number  0 to 1
---@return string  e.g. "12%"
function ns.Percent(fraction)
    return ("%d%%"):format(math.floor(fraction * 100 + 0.5))
end

--- Formats a length of time spent fighting.
---@param seconds number
---@return string  e.g. "14s", "2m 05s"
function ns.Duration(seconds)
    seconds = math.floor(seconds + 0.5)
    if seconds < 60 then
        return seconds .. "s"
    end
    return ("%dm %02ds"):format(math.floor(seconds / 60), seconds % 60)
end

--- What to call a fight: its boss, its enemy, or its group of enemies,
--- as the Fights list names it (see Record\Foes.lua), or else what the
--- player had targeted.
---@param otherwise string  for a fight with nothing to go by
function ns.FightTitle(fight, otherwise)
    if not fight.target and not fight.foes then
        return otherwise
    end

    -- Foes loads after this file, and only after a full restart following
    -- an update, so it's looked up when it's wanted.
    if ns.Foes then
        local ok, described = pcall(ns.Foes.Describe, fight)
        if ok and type(described) == "table" and described.title then
            return described.title
        end
    end
    return fight.target or otherwise
end

--- A count with the thing counted.
---@param count number  rounded to a whole number
---@param thing string  what's counted, as one of them: "cast"
---@return string  e.g. "1 cast", "3 casts"
function ns.Count(count, thing)
    count = math.floor(count + 0.5)
    return ("%d %s%s"):format(count, thing, count == 1 and "" or "s")
end

--- How much something changed, as a fraction of where it started.
---@param before number
---@param after number
---@return number|nil  0.12 for twelve per cent up; nil when there was
---                    nothing to start from
function ns.Change(before, after)
    if not before or not after or before == 0 then
        return nil
    end
    return (after - before) / before
end

--- Prints a line to chat with the addon's name in front.
--- Used for slash-command replies only. Temper doesn't narrate in chat.
function ns.Print(text, ...)
    if select("#", ...) > 0 then
        text = text:format(...)
    end
    print("|cffffd100" .. ns.TITLE .. "|r: " .. text)
end

--- Tidies a note the player typed before it's kept: one line, no codes
--- the game would try to draw, and not too long.
---@param text string|nil
---@return string|nil  nil for an empty note
function ns.CleanNote(text)
    text = (text or ""):gsub("|", ""):gsub("%s+", " ")
    text = strtrim(text):sub(1, ns.NOTE_LENGTH)
    return text ~= "" and text or nil
end
