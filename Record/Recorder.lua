local _, ns = ...

-- Recordings.
--
-- Every fight is kept whether or not the player is recording. A recording
-- is a label on a run of them: the fights between pressing Record and
-- pressing Stop. It saves picking them out of the list by hand, and makes
-- "these five, then those five" one click each.
--
-- A recording looks like this:
--
--   number     counts up per character; it's how the player refers to it
--   startedAt  server time
--   endedAt    server time, absent while it's still open
--
-- The fights carry the recording's number, not the other way round.

local Recorder = {}
ns.Recorder = Recorder

-- The recording being added to, if any.
local open

--- The recording in progress, or nil.
function Recorder.Open()
    return open
end

--- A recording by its number, or nil.
function Recorder.Numbered(number)
    for _, recording in ipairs(ns.character.recordings) do
        if recording.number == number then
            return recording
        end
    end
end

--- True if the recording is still on the books, not deleted meanwhile.
function Recorder.StillKept(recording)
    return Recorder.Numbered(recording.number) == recording
end

--- The fights that belong to a recording, oldest first.
function Recorder.FightsOf(recording)
    local fights = {}
    for _, fight in ipairs(ns.character.fights) do
        if fight.recording == recording.number then
            table.insert(fights, fight)
        end
    end
    return fights
end

--- The recording before this one that has any fights left, or nil.
function Recorder.Before(recording)
    local recordings = ns.character.recordings
    for index = #recordings, 1, -1 do
        local earlier = recordings[index]
        if earlier.number < recording.number and #Recorder.FightsOf(earlier) > 0 then
            return earlier
        end
    end
end

function Recorder.Start()
    if open or not ns.character then
        return
    end

    local character = ns.character
    open = { number = character.nextNumber, startedAt = GetServerTime() }
    character.nextNumber = character.nextNumber + 1
    table.insert(character.recordings, open)

    ns.Publish("FIGHTS_CHANGED")
end

--- Forgets a recording. Its fights stay, as ordinary unrecorded ones.
local function Forget(recording)
    local character = ns.character
    for index, candidate in ipairs(character.recordings) do
        if candidate == recording then
            table.remove(character.recordings, index)
            break
        end
    end
    for _, fight in ipairs(character.fights) do
        if fight.recording == recording.number then
            fight.recording = nil
        end
    end

    -- Give the number back if it was the latest, so a Record pressed by
    -- mistake doesn't leave a gap in the numbering. Not if an experiment
    -- is holding on to it, though: the next recording would be taken for
    -- one of that experiment's.
    local held = false
    for _, experiment in ipairs(character.experiments or {}) do
        held = held or experiment.before == recording.number or experiment.after == recording.number
    end
    if not held and recording.number == character.nextNumber - 1 then
        character.nextNumber = recording.number
    end
end

---@return table|nil finished  the recording, if it has any fights in it
function Recorder.Stop()
    if not open then
        return
    end

    local finished = open
    open = nil
    finished.endedAt = GetServerTime()

    -- A recording with nothing in it isn't worth keeping, unless its
    -- first fight is still being fought.
    local empty = #Recorder.FightsOf(finished) == 0
    if empty and not ns.Fights.BelongsTo(finished) then
        Forget(finished)
        finished = nil
    end

    ns.Publish("FIGHTS_CHANGED")
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

--- Forgets any recording that has no fights left.
function Recorder.Tidy()
    local recordings = ns.character.recordings
    for index = #recordings, 1, -1 do
        local recording = recordings[index]
        if recording ~= open and #Recorder.FightsOf(recording) == 0 then
            Forget(recording)
        end
    end
end

--- Deletes fights for good. A recording left with none goes too.
---@param doomed table  set of fights: doomed[fight] = true
function Recorder.DeleteFights(doomed)
    local character = ns.character
    local fights = character.fights
    for index = #fights, 1, -1 do
        if doomed[fights[index]] then
            table.remove(fights, index)
        end
    end

    Recorder.Tidy()
    ns.Publish("FIGHTS_CHANGED")
end

--- Forgets everything recorded for this character: fights, recordings,
--- experiments and what's been learned about their abilities. There's no
--- getting it back, so whoever calls this asks first.
function Recorder.ForgetEverything()
    local character = ns.character
    open = nil

    for _, list in ipairs({ "fights", "recordings", "experiments", "gearSets", "schools" }) do
        character[list] = {}
    end
    character.nextNumber = 1
    character.nextExperiment = 1

    ns.Publish("EXPERIMENTS_CHANGED")
    ns.Publish("FIGHTS_CHANGED")
end

-- A recording can't outlive the session it was started in: the fights in
-- between would be missing. Whatever was open at the last logout or reload
-- is closed as it stood, and any that ended up empty are dropped.
ns.Subscribe("DATABASE_READY", function()
    local recordings = ns.character.recordings
    for index = #recordings, 1, -1 do
        local recording = recordings[index]
        local fights = Recorder.FightsOf(recording)

        if #fights == 0 then
            Forget(recording)
        elseif not recording.endedAt then
            local last = fights[#fights]
            recording.endedAt = last.at + math.floor(last.length)
        end
    end
end)
