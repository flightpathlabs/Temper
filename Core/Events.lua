local _, ns = ...

-- Two small message buses.
--
-- Game events come from the client. Messages are how Temper's own parts
-- tell each other that something changed, so the part that records a fight
-- can say so without knowing that a window exists to redraw.

local frame = CreateFrame("Frame")
local eventHandlers = {}
local messageHandlers = {}

--- Calls handler whenever the client fires a game event.
--- Several handlers can share one event; they run in the order they were added.
---@param event string
---@param handler fun(...)
---@return boolean registered  false if this client has no such event
function ns.OnEvent(event, handler)
    if not eventHandlers[event] then
        -- RegisterEvent throws on names the client doesn't know, and Forever
        -- lacks a few events that retail has. Better to carry on without
        -- one feature than to stop the whole file loading.
        if not pcall(frame.RegisterEvent, frame, event) then
            return false
        end
        eventHandlers[event] = {}
    end

    table.insert(eventHandlers[event], handler)
    return true
end

-- Runs every handler even if one of them fails. The failure still reaches
-- the game's error display; it just doesn't take the handlers queued
-- behind it down as well.
local function Dispatch(handlers, ...)
    for _, handler in ipairs(handlers) do
        xpcall(handler, geterrorhandler(), ...)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    Dispatch(eventHandlers[event], ...)
end)

--- Calls handler whenever another part of Temper publishes a message.
---@param message string
---@param handler fun(...)
function ns.Subscribe(message, handler)
    messageHandlers[message] = messageHandlers[message] or {}
    table.insert(messageHandlers[message], handler)
end

--- Tells everyone subscribed to a message that it happened.
---@param message string
function ns.Publish(message, ...)
    local handlers = messageHandlers[message]
    if handlers then
        Dispatch(handlers, ...)
    end
end

-- Messages in use, so there's one place to look them up:
--
--   DATABASE_READY               saved data is loaded and safe to read
--   SETTINGS_CHANGED             the player changed an option
--   TARGET_HIT        hit        something landed on, or missed, the
--                                player's target (see Combat\Hits.lua)
--   PLAYER_CAST       spellID    the player or their pet cast something
--   FIGHTS_CHANGED               a fight was saved or deleted, or a
--                                recording started or stopped
--   EXPERIMENTS_CHANGED          an experiment began, moved on a step or
--                                was deleted
--   PROCS_CHANGED                something worth pressing now came up, or
--                                went (see Combat\Procs.lua)
--   READINESS_CHANGED            a warning or a buff on the panel's row
--                                came or went (see Combat\Readiness.lua)
