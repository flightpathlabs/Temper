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
--                             seen to do (see Combat\Guess.lua)
--                 ticking     how often each ability has been seen ticking
--                             after its cast, like a bleed (also Guess.lua)
--                 nextNumber  the number the next recording will carry
--   widget      where the last-fight panel was dragged to
--   healWidget  where the healing panel was dragged to
--   button      where the record button was dragged to
--   procAlert   where the ability alert was dragged to, by its middle
--   example     where the example enemy in the options was dragged to
--   toldAboutNameplates  set once the player has been told the numbers
--               need enemy nameplates (see Text\Lane.lua)
--   blizzardDamageText  the player's own setting for Blizzard's damage
--               numbers, as last seen before we switched them off (see
--               Text\Feed.lua)
--
-- Forever's beta builds had a bug where saved data was written but not read
-- back. It's fixed in the build we developed on, but the lesson stands:
-- never assume the table is there, and never replace what did load with
-- defaults. We only ever fill in what's missing.

local SCHEMA = 5

ns.DEFAULT_SETTINGS = {
    -- Show the player's hits in a lane by the target's nameplate.
    lane = true,

    -- Show numbers above every enemy being fought, not only the target.
    allEnemies = true,

    -- How the numbers move: 1 rise steadily, 2 stay and step up, 3 arc
    -- away, 4 shrink away.
    motion = 1,

    -- How long a number stays: 1 briefly, 2 a few seconds, 3 a good while.
    stay = 2,

    -- Where the lane sits by the nameplate: 1 above, 2 left, 3 right.
    laneSide = 1,

    -- How far from the nameplate: 1 close, 2 a little off, 3 well clear.
    laneDistance = 1,

    -- The height of an ordinary number, in pixels, and its font: 1 the
    -- game's usual, 2 a narrow one, 3 the game's own damage-number font, 4
    -- a decorative one (see Text\Lane.lua).
    fontSize = 13,
    font = 1,

    -- What the colour of a number says: 1 its kind (weapon swings white,
    -- abilities yellow, magic by its school), 2 magic only, 3 nothing.
    colorBy = 1,

    -- A critical hit: how large it's drawn, as a percentage of an
    -- ordinary hit; its colour (1 gold, 2 red, 3 the hit's own); and how
    -- it lands (1 no fuss, 2 a small pop, 3 a big pop, 4 a shake).
    critSize = 140,
    critStyle = 3,
    critLanding = 2,

    -- Put the icon of the ability beside each number. The game doesn't say
    -- which ability a hit was, so this is a best guess. Off to begin with.
    icons = false,

    -- Show "Miss", "Dodge" and the like as small words.
    showMisses = true,

    -- Hits that were most likely somebody else's: 1 small and faint in a
    -- column of their own, 2 not shown, 3 shown like the player's own.
    others = 1,

    -- Switch Blizzard's own damage numbers off while the lane is showing.
    hideBlizzardNumbers = true,

    -- The small panel that shows the fight in progress or the last one.
    widget = true,

    -- On that panel: our icon in the corner; the few fights before the
    -- last (1 none, 2 three, 3 five); figures for the session so far; and
    -- along the bottom, a small icon for each kind of buff worth having
    -- up, lit while it's on (see Combat\Readiness.lua).
    widgetBrand = true,
    widgetRecent = 2,
    widgetStats = true,
    widgetBuffs = true,

    -- A short note just above that panel when something's amiss before a
    -- fight: a fishing pole still in hand, a buff of the class's own not
    -- up, gear about to break (see UI\ReadyAlert.lua). Silent but for a
    -- fight begun with the fishing pole, which plays the alert sound below.
    readyAlert = true,

    -- A second panel like it, for healing. Off unless asked for: it can be
    -- popped out from the fight panel's menu or the options.
    healWidget = false,

    -- A small Record button on the screen. Off unless asked for: the window
    -- and the panel's menu both record, and there's a key binding.
    recordButton = false,

    -- An ability's icon below the middle of the screen when something has
    -- made it the best next press: Clearcasting, or Overpower after a
    -- dodge. Off unless asked for. With it, a sound: 1 none, otherwise
    -- one of the game's alert sounds, 2 being an anvil strike (see the
    -- list in UI\ProcAlert.lua).
    procAlert = false,
    procSound = 2,
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
    if db.settings.recordButton ~= nil and (db.schema or 1) < 2 then
        db.settings.recordButton = false
    end

    -- The motions were renumbered and the default replaced in the third
    -- layout, so a saved choice no longer means what it did.
    if (db.schema or 1) < 3 then
        db.settings.motion = nil
        db.settings.textSize = nil
    end

    -- The fourth layout sets the size of the numbers in pixels where
    -- there were three sizes, and colours them by kind where there was a
    -- tick box for tinting magic. Critical hits used to be gold whatever
    -- they were; among coloured numbers that default no longer suits, so
    -- anyone still on it starts again from the new one.
    if (db.schema or 1) < 4 then
        local settings = db.settings
        local sizes = { 11, 13, 16 }
        if settings.textSize ~= nil then
            settings.fontSize = sizes[settings.textSize]
            settings.textSize = nil
        end
        if settings.schoolColors == false then
            settings.colorBy = 3
        end
        settings.schoolColors = nil

        -- Red was somebody's choice. Gold was only ever the default.
        if settings.critStyle == 1 then
            settings.critStyle = nil
        end
    end
    -- The fifth layout replaced the alert sounds with louder ones, so a
    -- saved choice no longer means what it did. "No sound" still does.
    if (db.schema or 1) < 5 and db.settings.procSound ~= 1 then
        db.settings.procSound = nil
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
