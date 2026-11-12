local addonName, ns = ...

-- Saved data.
--
-- One account-wide table, TemperDB, laid out like this:
--
--   schema      version of this layout, for migrations
--   settings    the player's options
--   characters  one entry per character, by GUID:
--                 name        for telling them apart when reading the file
--                 fights      every fight on record, oldest first (see
--                             Combat\Fights.lua)
--                 recordings  the stretches the player chose to record;
--                             a label on a run of fights (see Recorder)
--                 experiments questions put to a pair of recordings (see
--                             Record\Experiments.lua)
--                 gearSets    each different set of gear a fight was
--                             fought in (see Combat\Gear.lua)
--                 schools     which school of damage each ability has been
--                             seen to do (see Text\Guess.lua)
--                 nextNumber  the number the next recording will carry
--   widget      where the last-fight panel was dragged to
--   button      where the record button was dragged to
--   blizzardDamageText  the player's own setting for Blizzard's damage
--               numbers, as last seen before we switched them off (see
--               Text\Feed.lua)
--
-- Forever's beta builds had a bug where saved data was written but not read
-- back. It's fixed in the build we developed on, but the lesson stands:
-- never assume the table is there, and never replace what did load with
-- defaults. We only ever fill in what's missing.

local SCHEMA = 2

ns.DEFAULT_SETTINGS = {
    -- Show the player's hits in a lane by the target's nameplate.
    lane = true,

    -- Show numbers above every enemy being fought, not only the target.
    allEnemies = true,

    -- How the numbers move: 1 a steady stream, 2 rise and fade, 3 arc
    -- away, 4 shrink away.
    motion = 1,

    -- How long a number stays: 1 briefly, 2 a few seconds, 3 a good while.
    stay = 2,

    -- Where the lane sits by the nameplate: 1 above, 2 left, 3 right.
    laneSide = 1,

    -- How far from the nameplate: 1 close, 2 a little off, 3 well clear.
    laneDistance = 1,

    -- 1 small, 2 medium, 3 large.
    textSize = 2,

    -- How a critical hit stands out: 1 gold, 2 red, 3 by size alone.
    critStyle = 1,

    -- Tint spell damage by its school; physical damage stays white.
    schoolColors = true,

    -- Put the icon of the ability beside each number. The game doesn't say
    -- which ability a hit was, so this is a best guess. Off to begin with.
    icons = false,

    -- Show "Miss", "Dodge" and the like as small words.
    showMisses = true,

    -- Switch Blizzard's own damage numbers off while the lane is showing.
    hideBlizzardNumbers = true,

    -- The small panel that shows the fight in progress or the last one.
    widget = true,

    -- A small Record button on the screen. Off unless asked for: the window
    -- and the panel's menu both record, and there's a key binding.
    recordButton = false,
}

-- How many fights to keep for each character. The oldest go first.
ns.MAX_FIGHTS = 200

local function FillIn(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = value
        end
    end
end

--- Moves a character's data from the first layout, where fights lived
--- inside recordings, to one list of fights with recordings as labels.
local function FlattenFights(character)
    local fights = character.fights

    for _, recording in ipairs(character.recordings) do
        if type(recording.fights) == "table" then
            local gear = recording.gear and ns.Gear.Keep(character, recording.gear)
            for _, fight in ipairs(recording.fights) do
                fight.recording = recording.number
                fight.gear = gear
                table.insert(fights, fight)
            end
        end
        recording.fights = nil
        recording.gear = nil
    end

    if type(character.recent) == "table" then
        for _, fight in ipairs(character.recent) do
            table.insert(fights, fight)
        end
        character.recent = nil
    end

    table.sort(fights, function(a, b)
        return (a.at or 0) < (b.at or 0)
    end)
end

ns.OnEvent("ADDON_LOADED", function(name)
    if name ~= addonName then
        return
    end

    if type(TemperDB) ~= "table" then
        TemperDB = {}
    end
    local db = TemperDB

    if type(db.settings) ~= "table" then
        db.settings = {}
    end
    if type(db.characters) ~= "table" then
        db.characters = {}
    end
    -- The Record button was on to begin with in the first layout. Anyone
    -- coming from that never chose it, so they get the new default.
    if db.settings.recordButton ~= nil and (db.schema or 1) < SCHEMA then
        db.settings.recordButton = false
    end
    FillIn(db.settings, ns.DEFAULT_SETTINGS)

    ns.db = db
    ns.settings = db.settings
end)

-- The character isn't known until login, so that's when the rest of the
-- addon is told the data is ready.
ns.OnEvent("PLAYER_LOGIN", function()
    local guid = UnitGUID("player")
    local characters = ns.db.characters

    if type(characters[guid]) ~= "table" then
        characters[guid] = {}
    end
    local character = characters[guid]

    character.name = UnitName("player")
    for _, list in ipairs({ "fights", "recordings", "experiments", "gearSets", "schools" }) do
        if type(character[list]) ~= "table" then
            character[list] = {}
        end
    end
    character.nextNumber = character.nextNumber or 1
    character.nextExperiment = character.nextExperiment or 1

    FlattenFights(character)
    ns.db.schema = SCHEMA

    ns.character = character
    ns.Publish("DATABASE_READY")
end)
