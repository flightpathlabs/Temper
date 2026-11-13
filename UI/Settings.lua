local _, ns = ...

-- Temper's page in the game's own Options window.
--
-- Everything works without a visit here. These are for people who want to
-- change how the numbers look or where they sit, under one heading, and
-- what else Temper puts on the screen, under another.

local PREFIX = "Temper_"

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

-- Adds a heading over the options that follow it, as the game's own pages
-- have.
local function AddHeader(layout, title)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
end

-- Our page, once it exists. Kept so it can be opened directly.
local category

--- Opens the game's Options window on Temper's page.
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
    -- The layout is the page's list of rows. The tick boxes and dropdowns
    -- add themselves to it; a heading has to be added by hand.
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory(ns.TITLE)

    AddHeader(layout, "Damage numbers")

    AddCheckbox(
        category,
        "lane",
        "Show my hits by the enemy's nameplate",
        "One tidy column of numbers that follows your target. Only while you're on your "
            .. "own: in a group it steps aside and the game's usual numbers come back.",
        true
    )

    AddCheckbox(
        category,
        "allEnemies",
        "Show numbers above every enemy I'm fighting",
        "Each enemy gets its own column, so hits on several at once don't pile up over "
            .. "your target. Only enemies that are fighting you are included. Untick to "
            .. "show your target's alone."
    )

    local motions = {}
    for index, motion in ipairs(ns.Motions) do
        motions[index] = motion.label
    end
    AddDropdown(
        category,
        "motion",
        "How the numbers move",
        "Rising stream is the calmest: small numbers that climb straight up at a steady "
            .. "pace, like a scrolling log. The others stay put, arc or shrink as they go.",
        motions
    )

    AddDropdown(
        category,
        "stay",
        "How long a number stays",
        "Longer shows more of your recent hits at once.",
        { "Short", "Medium", "Long" }
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
        { "Near", "Medium", "Far" }
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
        "icons",
        "Show a best-guess ability icon beside each number",
        "The game doesn't tell addons which ability a hit was, so Temper works it out from "
            .. "what you just used and the kind of damage. It's usually right, gets better "
            .. "the more it sees, and is sometimes wrong when two things land at once.",
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
            .. "Temper steps aside, and when you log out."
    )

    AddHeader(layout, "On screen")

    AddCheckbox(
        category,
        "widget",
        "Show the fight panel",
        "A small panel with your DPS, damage, hits and crits for the fight you're in, or "
            .. "the last one. Click it to open Temper, right-click for a menu, drag it "
            .. "anywhere."
    )

    AddDropdown(
        category,
        "widgetRecent",
        "Recent fights on the panel",
        "A line for each of the fights before the last one, with its DPS.",
        { "None", "Last 3", "Last 5" }
    )

    AddCheckbox(
        category,
        "widgetStats",
        "Session figures on the panel",
        "How many fights, your average DPS, how often you crit and your biggest hit, for "
            .. "the session you started or else since you logged in."
    )

    AddCheckbox(
        category,
        "widgetBrand",
        "The Temper icon on the panel",
        "Untick for a plainer panel."
    )

    AddCheckbox(
        category,
        "recordButton",
        "Show a Start session button on the screen",
        "A small button you can drag anywhere: left-click to start or end a session, "
            .. "right-click to open Temper. Without it, start a session from the Temper "
            .. "window, with a key (Options > Keybindings > Temper), or with /temper session."
    )

    Settings.RegisterAddOnCategory(category)
end)
