-- Luacheck configuration for Temper.
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

-- The only globals Temper creates: its saved data, slash command, key
-- binding and the addon-list click handler named in the TOC.
globals = {
    "SlashCmdList",
    "UISpecialFrames",
    "StaticPopupDialogs",

    -- Ours
    "TemperDB",
    "SLASH_TEMPER1",
    "Temper_OnAddonCompartmentClick",
    "Temper_ToggleRecording",
    "BINDING_NAME_TEMPER_RECORD",
}

read_globals = {
    -- Lua extensions the client adds
    "strtrim",
    "date",

    -- Client constants
    "Enum",

    -- Blizzard's shared Lua helpers
    "AbbreviateNumbers",
    "BreakUpLargeNumbers",
    "CombatFeedbackText",
    "CreateColor",
    "CreateDataProvider",
    "CreateScrollBoxListLinearView",
    "CreateSettingsListSectionHeaderInitializer",
    "GameTooltip_Hide",
    "MinimalSliderWithSteppersMixin",
    "MenuUtil",
    "PanelTemplates_SetNumTabs",
    "PanelTemplates_SetTab",
    "PanelTemplates_TabResize",
    "ScrollBoxConstants",
    "ScrollUtil",
    "StaticPopup_Show",

    -- Frames and widgets
    "CreateFrame",
    "UIParent",
    "GameTooltip",
    "GameFontNormal",
    "STANDARD_TEXT_FONT",
    "Settings",
    "SettingsPanel",

    -- Namespaced API
    "C_AddOns",
    "C_DamageMeter",
    "C_Item",
    "C_SkillInfo",
    "C_NamePlate",
    "C_Spell",
    "C_SpellBook",
    "C_StringUtil",
    "C_Timer",

    -- Loose API functions
    "GetBindingKey",
    "GetBindingText",
    "GetCVar",
    "GetCVarBool",
    "SetCVar",
    "GetInventoryItemID",
    "GetInventoryItemLink",
    "GetServerTime",
    "GetShapeshiftForm",
    "GetTime",
    "InCombatLockdown",
    "IsControlKeyDown",
    "IsInGroup",
    "IsShiftKeyDown",
    "UnitCanAttack",
    "UnitDetailedThreatSituation",
    "UnitExists",
    "UnitClass",
    "UnitGUID",
    "UnitIsUnit",
    "UnitLevel",
    "UnitName",
    "UnitPower",
    "UnitPowerMax",
    "UnitPowerType",
    "UnitThreatSituation",
    "geterrorhandler",
    "issecretvalue",
}
