local _, ns = ...

-- Strikewise's page in the game's own Options window.
--
-- Everything works without a visit here. These are for people who want to
-- change how the numbers look or where they sit.

local PREFIX = "Strikewise_"

-- Changing how numbers look shows a few samples, so the choice can be
-- judged without going to find something to hit.
local function OnChanged(preview)
    ns.Publish("SETTINGS_CHANGED")
    if preview and ns.settings.lane then
        ns.Lane.Preview()
    end
end

-- Adds a tick box bound to one key of the saved settings.
local function AddCheckbox(category, key, label, tooltip, preview)
    local setting = Settings.RegisterAddOnSetting(
        category,
        PREFIX .. key,
        key,
        ns.settings,
        Settings.VarType.Boolean,
        label,
        ns.DEFAULT_SETTINGS[key]
    )
    Settings.CreateCheckbox(category, setting, tooltip)

    Settings.SetOnValueChangedCallback(PREFIX .. key, function()
        OnChanged(preview)
    end)
end

-- Adds a dropdown bound to one numeric key of the saved settings.
-- `choices` is a list of labels; a choice's place in the list is its value.
local function AddDropdown(category, key, label, tooltip, choices)
    local setting = Settings.RegisterAddOnSetting(
        category,
        PREFIX .. key,
        key,
        ns.settings,
        Settings.VarType.Number,
        label,
        ns.DEFAULT_SETTINGS[key]
    )

    Settings.CreateDropdown(category, setting, function()
        local container = Settings.CreateControlTextContainer()
        for value, choice in ipairs(choices) do
            container:Add(value, choice)
        end
        return container:GetData()
    end, tooltip)

    Settings.SetOnValueChangedCallback(PREFIX .. key, function()
        OnChanged(true)
    end)
end

-- Our page, once it exists. Kept so it can be opened directly.
local category

--- Opens the game's Options window on Strikewise's page.
function ns.OpenOptions()
    -- The Options window is one of the panels the game won't let addons
    -- open during combat.
    if InCombatLockdown() then
        ns.Print("Options can't be opened in combat. Try again in a moment.")
        return
    end

    if category then
        Settings.OpenToCategory(category:GetID())
    end
end

-- Registered at login rather than when the addon loads, so the Options
-- window has finished setting itself up.
ns.OnEvent("PLAYER_LOGIN", function()
    category = Settings.RegisterVerticalLayoutCategory(ns.TITLE)

    AddCheckbox(
        category,
        "lane",
        "Show my hits by the enemy's nameplate",
        "One tidy column of numbers that follows your target. Only while you're on your "
            .. "own: in a group it steps aside and the game's usual numbers come back.",
        true
    )

    local motions = {}
    for index, motion in ipairs(ns.Motions) do
        motions[index] = motion.label
    end
    AddDropdown(
        category,
        "motion",
        "How a number leaves",
        "Rise and fade is the calmest. Arc away tosses each number to one side. "
            .. "Shrink away keeps them close to the nameplate.",
        motions
    )

    AddDropdown(
        category,
        "laneSide",
        "Where the numbers sit",
        "Which side of the enemy's nameplate the column starts from.",
        { "Above the nameplate", "Left of the nameplate", "Right of the nameplate" }
    )

    AddDropdown(
        category,
        "laneDistance",
        "How far from the nameplate",
        "Move the column out if it covers something you want to see.",
        { "Close", "A little way off", "Well clear" }
    )

    AddDropdown(
        category,
        "textSize",
        "Size of the numbers",
        "Critical hits are always drawn larger than this.",
        { "Small", "Medium", "Large" }
    )

    AddDropdown(
        category,
        "critStyle",
        "Critical hits stand out in",
        "Every critical hit is larger and lands with a pop. This picks its colour.",
        { "Gold", "Red", "Size alone" }
    )

    AddCheckbox(
        category,
        "schoolColors",
        "Tint spell damage by its school",
        "Fire in orange, frost in blue and so on. Physical damage stays white.",
        true
    )

    AddCheckbox(
        category,
        "showMisses",
        "Show misses, dodges and parries",
        "As a small grey word in the same column."
    )

    AddCheckbox(
        category,
        "hideBlizzardNumbers",
        "Hide the game's own damage numbers while mine are showing",
        "Otherwise every hit is shown twice. Your own setting is put back whenever "
            .. "Strikewise steps aside, and when you log out."
    )

    AddCheckbox(
        category,
        "recordButton",
        "Show the Record button",
        "You can also record with a key (Options > Keybindings > Strikewise), "
            .. "with /strike record, or from the Strikewise window."
    )

    Settings.RegisterAddOnCategory(category)
end)
