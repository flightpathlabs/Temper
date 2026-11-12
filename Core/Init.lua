local addonName, ns = ...

-- Strikewise
--
-- Everything hangs off the private table the client hands every file in an
-- addon (ns). Nothing here is global except the saved-variables table, the
-- slash command, the key binding and the addon-list click handler, which
-- the client needs to find by name.

ns.name = addonName

-- What the addon is called wherever a player reads it.
ns.TITLE = "Strikewise"

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
--- Used for slash-command replies only. Strikewise doesn't narrate in chat.
function ns.Print(text, ...)
    if select("#", ...) > 0 then
        text = text:format(...)
    end
    print("|cffffd100" .. ns.TITLE .. "|r: " .. text)
end
