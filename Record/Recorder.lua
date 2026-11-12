local _, ns = ...

-- Recordings.
--
-- A recording is the fights between pressing Record and pressing Stop,
-- kept together with a note of what the character was wearing. It's the
-- unit of comparison: record a few fights, change something, record a few
-- more, and put the two side by side.
--
-- A recording looks like this:
--
--   number     counts up per character; it's how the player refers to it
--   startedAt  server time
--   endedAt    server time, absent while it's still open
--   level      the player's level when it began
--   gear       what was worn when it began (see Combat\Gear.lua)
--   fights     the fights, oldest first (see Combat\Fights.lua)

local Recorder = {}
ns.Recorder = Recorder

-- The recording being added to, if any.
local open

--- The recording in progress, or nil.
function Recorder.Open()
    return open
end

function Recorder.Start()
    if open or not ns.character then
        return
    end

    local character = ns.character
    open = {
        number = character.nextNumber,
        startedAt = GetServerTime(),
        level = UnitLevel("player"),
        gear = ns.Gear.Snapshot(),
        fights = {},
    }
    character.nextNumber = character.nextNumber + 1

    local recordings = character.recordings
    table.insert(recordings, open)
    while #recordings > ns.MAX_RECORDINGS do
        table.remove(recordings, 1)
    end

    ns.Publish("RECORDINGS_CHANGED")
end

function Recorder.Stop()
    if not open then
        return
    end

    local finished = open
    open = nil
    finished.endedAt = GetServerTime()

    -- A recording with nothing in it isn't worth a line in the list,
    -- unless its first fight is still being fought.
    if #finished.fights == 0 and not ns.Fights.BelongsTo(finished) then
        Recorder.Delete(finished)
        return nil
    end

    ns.Publish("RECORDINGS_CHANGED")
    return finished
end

--- Starts a recording, or stops the one in progress.
---@return table|nil finished  the recording that was just stopped, if it
---                            had any fights in it
function Recorder.Toggle()
    if open then
        return Recorder.Stop()
    end
    Recorder.Start()
end

function Recorder.Delete(recording)
    if recording == open then
        open = nil
    end

    local character = ns.character
    local recordings = character.recordings
    for index, candidate in ipairs(recordings) do
        if candidate == recording then
            table.remove(recordings, index)
            break
        end
    end

    -- Give the number back if it was the latest and never held a fight, so
    -- a Record pressed by mistake doesn't leave a gap in the numbering.
    if recording.number == character.nextNumber - 1 and #recording.fights == 0 then
        character.nextNumber = recording.number
    end

    ns.Publish("RECORDINGS_CHANGED")
end

--- Everything there is to look at, newest first. The fights fought outside
--- any recording come last, as one entry, so there's something to read
--- before the player has ever pressed Record.
---@return table  list of recordings; the unrecorded entry has recent = true
function Recorder.List()
    local list = {}
    if not ns.character then
        return list
    end

    local recordings = ns.character.recordings
    for index = #recordings, 1, -1 do
        table.insert(list, recordings[index])
    end

    if #ns.character.recent > 0 then
        table.insert(list, { recent = true, fights = ns.character.recent })
    end
    return list
end

--- What to call a recording in a list.
---@return string  e.g. "Recording 3", "Recent fights"
function Recorder.Label(recording)
    if recording.recent then
        return "Recent fights"
    end
    return "Recording " .. recording.number
end

-- A recording can't outlive the session it was started in: the fights in
-- between would be missing. Whatever was open at the last logout or reload
-- is closed as it stood.
ns.Subscribe("DATABASE_READY", function()
    local recordings = ns.character.recordings
    for index = #recordings, 1, -1 do
        local recording = recordings[index]
        if not recording.endedAt then
            if type(recording.fights) ~= "table" or #recording.fights == 0 then
                table.remove(recordings, index)
            else
                local last = recording.fights[#recording.fights]
                recording.endedAt = last.at + math.floor(last.length)
            end
        end
    end
end)
