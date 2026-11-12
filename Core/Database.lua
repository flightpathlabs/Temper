local addonName, ns = ...

-- Saved data.
--
-- One account-wide table, TemperDB, laid out like this:
--
--   schema      version of this layout, for migrations
--   settings    the player's options
--   characters  one entry per character, by GUID:
--                 name        for telling them apart when reading the file
--                 recent      the last few fights fought outside a recording
--                 recordings  what the player chose to record (see Recorder)
--                 nextNumber  the number the next recording will carry
--   button      where the record button was dragged to
--   blizzardDamageText  the player's own setting for Blizzard's damage
--               numbers, as last seen before we switched them off (see
--               Text\Feed.lua)
--
-- Forever's beta builds had a bug where saved data was written but not read
-- back. It's fixed in the build we developed on, but the lesson stands:
-- never assume the table is there, and never replace what did load with
-- defaults. We only ever fill in what's missing.

local SCHEMA = 1

ns.DEFAULT_SETTINGS = {
    -- Show the player's hits in a lane by the target's nameplate.
    lane = true,

    -- How a number leaves: 1 rises and fades, 2 arcs away, 3 shrinks.
    motion = 1,

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

    -- Show "Miss", "Dodge" and the like as small words.
    showMisses = true,

    -- Switch Blizzard's own damage numbers off while the lane is showing.
    hideBlizzardNumbers = true,

    -- The small Record button on the screen.
    recordButton = true,
}

-- How many unrecorded fights to keep, and how many recordings.
ns.RECENT_FIGHTS = 30
ns.MAX_RECORDINGS = 40

local function FillIn(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = value
        end
    end
end

ns.OnEvent("ADDON_LOADED", function(name)
    if name ~= addonName then
        return
    end

    if type(TemperDB) ~= "table" then
        TemperDB = {}
    end
    local db = TemperDB

    db.schema = db.schema or SCHEMA
    if type(db.settings) ~= "table" then
        db.settings = {}
    end
    if type(db.characters) ~= "table" then
        db.characters = {}
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
    if type(character.recent) ~= "table" then
        character.recent = {}
    end
    if type(character.recordings) ~= "table" then
        character.recordings = {}
    end
    character.nextNumber = character.nextNumber or 1

    ns.character = character
    ns.Publish("DATABASE_READY")
end)
