-- Luacheck configuration for Strikewise.
-- Run from the repo root:  luacheck .
--
-- There is no maintained luacheck "std" for the 12.x / Forever API, so we
-- list the globals we actually touch. Add to read_globals as new API gets
-- used; a typo in an API name then shows up as a lint warning instead of a
-- nil error in game.

std = "lua51"
max_line_length = 100
max_string_line_length = false
max_comment_line_length = 100
codes = true

exclude_files = {
    "Libs/**",
    ".release/**",
}

ignore = {
    "212/self", -- unused "self" on mixin methods is normal
    "212/event", -- event handlers often ignore the event name
}

-- The only globals Strikewise creates: its saved data, slash command, key
-- binding and the addon-list click handler named in the TOC.
globals = {
    "SlashCmdList",
    "UISpecialFrames",

    -- Ours
    "StrikewiseDB",
    "SLASH_STRIKEWISE1",
    "SLASH_STRIKEWISE2",
    "Strikewise_OnAddonCompartmentClick",
    "Strikewise_ToggleRecording",
    "BINDING_NAME_STRIKEWISE_RECORD",
}

read_globals = {
    -- Lua extensions the client adds
    "strtrim",
    "date",

    -- Client constants
    "Enum",

    -- Blizzard's shared Lua helpers
    "BreakUpLargeNumbers",
    "ButtonFrameTemplate_HidePortrait",
    "CombatFeedbackText",
    "CreateDataProvider",
    "CreateScrollBoxListLinearView",
    "GameTooltip_Hide",
    "MenuUtil",
    "ScrollBoxConstants",
    "ScrollUtil",

    -- Frames and widgets
    "CreateFrame",
    "UIParent",
    "GameTooltip",
    "Settings",

    -- Namespaced API
    "C_DamageMeter",
    "C_NamePlate",
    "C_Spell",
    "C_SpellBook",
    "C_Timer",

    -- Loose API functions
    "GetCVar",
    "SetCVar",
    "GetInventoryItemLink",
    "GetServerTime",
    "GetTime",
    "InCombatLockdown",
    "IsInGroup",
    "UnitCanAttack",
    "UnitGUID",
    "UnitLevel",
    "UnitName",
    "geterrorhandler",
    "issecretvalue",
}
