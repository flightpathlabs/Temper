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
    "GameRulesUtil",
    "GameTooltip_Hide",
    "GetClassAtlas",
    "MinimalSliderWithSteppersMixin",
    "MenuUtil",
    "PanelTemplates_SetNumTabs",
    "PanelTemplates_SetTab",
    "PanelTemplates_TabResize",
    "RAID_CLASS_COLORS",
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
    "C_Secrets",
    "C_Spell",
    "C_SpellBook",
    "C_StringUtil",
    "C_Timer",
    "C_UnitAuras",

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
    "PlaySound",
    "SOUNDKIT",
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

    -- The character sheet's defensive figures
    "C_PaperDollInfo",
    "GetShieldBlock",
    "UnitArmor",
    "UnitDefenseSkill",
    "UnitResistance",

    -- Readiness: what's worn and in hand, rest, and the hunter's pet
    "C_PetInfo",
    "GetInventoryItemCount",
    "GetInventoryItemDurability",
    "GetInventoryItemTexture",
    "GetMaxPlayerLevel",
    "GetXPExhaustion",
    "HasPetUI",
    "INVSLOT_AMMO",
    "INVSLOT_FIRST_EQUIPPED",
    "INVSLOT_LAST_EQUIPPED",
    "INVSLOT_MAINHAND",
    "INVSLOT_OFFHAND",
    "INVSLOT_RANGED",
    "IsResting",
    "IsXPUserDisabled",
    "UnitIsDead",
    "UnitIsDeadOrGhost",
    "UnitOnTaxi",
    "UnitUsesAmmo",
}
