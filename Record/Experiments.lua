local _, ns = ...

-- Experiments: a question, a few fights each way, and a verdict.
--
-- "Is the new bow better?" is hard to answer from one fight, because
-- fights vary: a lucky crit here, a dodge there. An experiment takes the
-- guesswork out. It records a set number of fights as you are, waits
-- while you make the change, records the same number again, and then says
-- what the difference was and how far to trust it.
--
-- Under the hood an experiment is two recordings and a note of which is
-- which. It looks like this:
--
--   number    counts up per character
--   question  what the player said they were testing
--   size      how many fights each side is meant to have
--   before    the number of the first recording
--   after     the number of the second, once it's begun
--   state     "before"  recording the first side
--             "change"  first side done; waiting for the player
--             "after"   recording the second side
--             "done"

local Experiments = {}
ns.Experiments = Experiments

Experiments.DEFAULT_SIZE = 5

-- How many standard errors apart the two sides have to be before the
-- difference is called clear, or likely.
local CLEAR = 2
local LIKELY = 1

--- The experiment that isn't finished yet, or nil. There's only ever one.
function Experiments.Running()
    for _, experiment in ipairs(ns.character.experiments) do
        if experiment.state ~= "done" then
            return experiment
        end
    end
end

--- The fights on one side of an experiment.
---@param side string  "before" or "after"
function Experiments.FightsOf(experiment, side)
    local recording = experiment[side] and ns.Recorder.Numbered(experiment[side])
    return recording and ns.Recorder.FightsOf(recording) or {}
end

local function Changed()
    ns.Publish("EXPERIMENTS_CHANGED")
end

--- Begins an experiment and starts recording its first side.
---@param question string  what's being tested, in the player's words
---@param size number|nil  fights each side
---@return table|nil experiment  nil if one is already running
function Experiments.Start(question, size)
    if Experiments.Running() or ns.Recorder.Open() then
        return nil
    end

    local character = ns.character
    ns.Recorder.Start()

    local experiment = {
        number = character.nextExperiment,
        question = question,
        size = size or Experiments.DEFAULT_SIZE,
        before = ns.Recorder.Open().number,
        state = "before",
        startedAt = GetServerTime(),
    }
    character.nextExperiment = character.nextExperiment + 1
    table.insert(character.experiments, experiment)

    Changed()
    return experiment
end

--- Starts recording the second side, once the player has made the change.
function Experiments.Continue(experiment)
    if experiment.state ~= "change" or ns.Recorder.Open() then
        return
    end

    ns.Recorder.Start()
    experiment.after = ns.Recorder.Open().number
    experiment.state = "after"
    Changed()
end

--- Moves an experiment on when the side being recorded has ended, whether
--- because it has all its fights or because recording was stopped by hand.
local function Advance(experiment)
    if experiment.state == "before" then
        -- With nothing to compare against there's no experiment.
        if #Experiments.FightsOf(experiment, "before") == 0 then
            Experiments.Delete(experiment)
            return
        end
        experiment.state = "change"
    elseif experiment.state == "after" then
        experiment.state = "done"
        experiment.finishedAt = GetServerTime()
    end
    Changed()
end

function Experiments.Delete(experiment)
    local experiments = ns.character.experiments
    for index, candidate in ipairs(experiments) do
        if candidate == experiment then
            table.remove(experiments, index)
            break
        end
    end

    -- The fights stay in the list as ordinary recorded fights.
    local open = ns.Recorder.Open()
    if open and (open.number == experiment.before or open.number == experiment.after) then
        ns.Recorder.Stop()
    end
    Changed()
end

-- Keeps an eye on the recording behind the side in progress.
ns.Subscribe("FIGHTS_CHANGED", function()
    local experiment = ns.character and Experiments.Running()
    if not experiment or experiment.state == "change" then
        return
    end

    local side = experiment.state
    local open = ns.Recorder.Open()
    local recording = open and open.number == experiment[side]

    if not recording then
        -- Stopped by hand, or lost to a reload.
        Advance(experiment)
    elseif #Experiments.FightsOf(experiment, side) >= experiment.size then
        ns.Recorder.Stop()
        -- Stopping publishes FIGHTS_CHANGED again, which lands in the
        -- branch above and moves the experiment on.
    end
end)

-- A recording doesn't survive a reload, so neither does the side of an
-- experiment that was being recorded. Pick up from wherever that leaves it.
ns.Subscribe("DATABASE_READY", function()
    local experiment = Experiments.Running()
    if experiment and experiment.state ~= "change" then
        Advance(experiment)
    end
end)

-- The verdict --------------------------------------------------------------

--- The average and the spread of damage a second across a set of fights.
local function Spread(fights)
    local damage, seconds = 0, 0
    for _, fight in ipairs(fights) do
        damage = damage + fight.damage
        seconds = seconds + fight.length
    end
    if seconds == 0 then
        return nil
    end
    local mean = damage / seconds

    -- How much single fights stray from that. With one fight there's no
    -- telling, which the verdict treats as "can't be sure of anything".
    local squares = 0
    for _, fight in ipairs(fights) do
        squares = squares + (fight.damage / fight.length - mean) ^ 2
    end
    local variance = #fights > 1 and squares / (#fights - 1) or nil

    return mean, variance
end

--- What an experiment found.
---@return table|nil verdict:
---   before, after   damage a second on each side
---   change          the difference as a fraction of before
---   direction       "better", "worse" or "same"
---   sureness        "clear", "likely" or "unsure"
---   more            roughly how many more fights each side would settle
---                   it, when it's unsure; nil otherwise
--- nil until both sides have a fight.
function Experiments.Verdict(experiment)
    local was = Experiments.FightsOf(experiment, "before")
    local is = Experiments.FightsOf(experiment, "after")
    local before, spreadBefore = Spread(was)
    local after, spreadAfter = Spread(is)
    if not before or not after or before == 0 then
        return nil
    end

    local verdict = {
        before = before,
        after = after,
        change = (after - before) / before,
        fightsBefore = #was,
        fightsAfter = #is,
    }

    local difference = after - before
    if math.abs(verdict.change) < 0.01 then
        verdict.direction = "same"
    else
        verdict.direction = difference > 0 and "better" or "worse"
    end

    if not spreadBefore or not spreadAfter then
        verdict.sureness = "unsure"
        verdict.more = Experiments.DEFAULT_SIZE
        return verdict
    end

    -- How far apart the two averages are, measured in the amount they'd
    -- be expected to wobble by chance.
    local wobble = math.sqrt(spreadBefore / #was + spreadAfter / #is)
    local apart = wobble > 0 and math.abs(difference) / wobble or math.huge

    if verdict.direction == "same" or apart >= CLEAR then
        verdict.sureness = "clear"
    elseif apart >= LIKELY then
        verdict.sureness = "likely"
    else
        verdict.sureness = "unsure"
    end

    -- Chance wobble shrinks with the square root of the number of fights,
    -- so getting from where we are to "clear" takes this many in all.
    if verdict.sureness ~= "clear" and apart > 0 then
        local fights = math.max(#was, #is)
        local needed = math.ceil(fights * (CLEAR / apart) ^ 2)
        verdict.more = math.max(2, math.min(needed - fights, 30))
    end

    return verdict
end

--- The verdict in a sentence or two.
---@return string headline, string detail
function Experiments.InWords(verdict)
    local percent = math.floor(math.abs(verdict.change) * 100 + 0.5)

    local headline
    if verdict.direction == "same" then
        headline = "No real difference."
    elseif verdict.direction == "better" then
        headline = ("Better: %d%% more damage a second."):format(percent)
    else
        headline = ("Worse: %d%% less damage a second."):format(percent)
    end

    local detail
    if verdict.sureness == "clear" then
        detail = "The fights agree with each other, so this can be trusted."
    elseif verdict.sureness == "likely" then
        detail = ("Probably real, but fights vary. About %d more each way would settle it."):format(
            verdict.more or Experiments.DEFAULT_SIZE
        )
    else
        detail = (
            "Too close to call: the difference is no bigger than one fight differs from "
            .. "the next. About %d more each way would tell."
        ):format(verdict.more or Experiments.DEFAULT_SIZE)
    end
    return headline, detail
end
