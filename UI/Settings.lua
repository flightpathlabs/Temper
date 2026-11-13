local _, ns = ...

-- Temper's page in the game's own Options window.
--
-- Everything works without a visit here. These are for people who want to
-- change how the numbers look or where they sit, and what else Temper
-- puts on the screen.
--
-- While the page is open an example enemy stands beside the window with
-- made-up hits playing on it (see Example.lua), so every change can be
-- judged as it's made. The Options window sits in the middle of the
-- screen, where the fighting happens, so this file also lets it be
-- dragged aside by its title bar.

local PREFIX = "Temper_"

local function OnChanged()
    ns.Publish("SETTINGS_CHANGED")
end

--- Registers one key of the saved settings with the game's options.
local function Register(category, key, kind, label)
    local setting = Settings.RegisterAddOnSetting(
        category,
        PREFIX .. key,
        key,
        ns.settings,
        kind,
        label,
        ns.DEFAULT_SETTINGS[key]
    )
    Settings.SetOnValueChangedCallback(PREFIX .. key, OnChanged)
    return setting
end

-- Adds a tick box bound to one key of the saved settings.
local function AddCheckbox(category, key, label, tooltip)
    local setting = Register(category, key, Settings.VarType.Boolean, label)
    Settings.CreateCheckbox(category, setting, tooltip)
end

-- Adds a dropdown bound to one numeric key of the saved settings.
-- `choices` is a list of labels; a choice's place in the list is its value.
local function AddDropdown(category, key, label, tooltip, choices)
    local setting = Register(category, key, Settings.VarType.Number, label)

    Settings.CreateDropdown(category, setting, function()
        local container = Settings.CreateControlTextContainer()
        for value, choice in ipairs(choices) do
            container:Add(value, choice)
        end
        return container:GetData()
    end, tooltip)
end

-- Adds a slider bound to one numeric key of the saved settings.
---@param range table  { lowest, highest, step }
---@param unit string  what follows the figure beside the slider, e.g. "%"
local function AddSlider(category, key, label, tooltip, range, unit)
    local setting = Register(category, key, Settings.VarType.Number, label)

    local options = Settings.CreateSliderOptions(range[1], range[2], range[3])
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return ("%d%s"):format(math.floor(value + 0.5), unit)
    end)
    Settings.CreateSlider(category, setting, options, tooltip)
end

-- Adds a heading over the options that follow it, as the game's own pages
-- have.
local function AddHeader(layout, title)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
end

--- The labels of a list of choices that carry them, in order.
local function Labels(choices)
    local labels = {}
    for index, choice in ipairs(choices) do
        labels[index] = choice.label
    end
    return labels
end

-- Our page, once it exists. Kept so it can be opened directly.
local category

-- Whether the game's Options window is open, as told by the strip we lay
-- over its title bar (see WatchOptionsWindow).
local optionsOpen = false

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

local function OnOurPage()
    local current = SettingsPanel:GetCurrentCategory()
    return current ~= nil and current:GetID() == category:GetID()
end

--- True while the game's Options window is open on Temper's page.
function ns.OptionsPageShowing()
    if not category or not optionsOpen then
        return false
    end

    -- Asked carefully: this reaches into the game's window, and if it
    -- ever changes shape the answer is simply no.
    local ok, showing = pcall(OnOurPage)
    return ok and showing
end

-- The Options window itself --------------------------------------------------

-- How often, while the Options window is open, to look at which page
-- it's on.
local LOOK_EVERY = 0.2

--- Lays a strip of our own over the Options window's title bar. Dragging
--- it moves the window, and while the window is open it keeps an eye on
--- whether our page is the one showing.
local function WatchOptionsWindow()
    if not SettingsPanel then
        return
    end

    -- A child of the window, so it's only about while the window is.
    local strip = CreateFrame("Frame", nil, SettingsPanel)
    strip:SetPoint("TOPLEFT", 8, -1)
    strip:SetPoint("TOPRIGHT", -30, -1)
    strip:SetHeight(20)
    strip:SetFrameLevel(SettingsPanel:GetFrameLevel() + 20)

    strip:EnableMouse(true)
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", function()
        if not InCombatLockdown() then
            SettingsPanel:StartMoving()
        end
    end)
    strip:SetScript("OnDragStop", function()
        SettingsPanel:StopMovingOrSizing()

        -- Moved for now, not for good. The game puts the window back in
        -- the middle whenever it next lays its panels out, and this
        -- keeps the spot from being written to its saved layout.
        SettingsPanel:SetUserPlaced(false)
    end)

    -- The strip only gets a turn while the window is on screen, and is
    -- told the moment it goes.
    local sinceLook = 0
    strip:SetScript("OnUpdate", function(_, elapsed)
        sinceLook = sinceLook + elapsed
        if sinceLook >= LOOK_EVERY then
            sinceLook = 0
            optionsOpen = true
            ns.Example.Refresh()
        end
    end)
    strip:SetScript("OnHide", function()
        optionsOpen = false
        ns.Example.Refresh()
    end)
end

-- The page -----------------------------------------------------------------------

local function AddNumberOptions(layout)
    AddHeader(layout, "Damage numbers")

    AddCheckbox(
        category,
        "lane",
        "Show my hits by the enemy's nameplate",
        "A tidy column of numbers that follows each enemy you hit. It needs enemy "
            .. "nameplates to be on: without one to follow, numbers appear mid-screen. "
            .. "Only while you're on your own: in a group it steps aside and the game's "
            .. "usual numbers come back."
    )

    AddCheckbox(
        category,
        "allEnemies",
        "Show numbers above every enemy I'm fighting",
        "Each enemy gets its own column, so hits on several at once don't pile up over "
            .. "your target. Only enemies that are fighting you are included. Untick to "
            .. "show your target's alone."
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

    AddSlider(
        category,
        "fontSize",
        "Size of the numbers",
        "The height of an ordinary hit, in pixels. Chat text is about 13.",
        { 8, 28, 1 },
        ""
    )

    AddDropdown(
        category,
        "colorBy",
        "Colour the numbers",
        "By kind of damage: weapon swings in white, abilities in yellow, magic in the "
            .. "colour of its school (fire orange, frost blue and so on), a pet's blows "
            .. "in green. Magic only leaves everything else white.",
        { "By kind of damage", "Magic only", "All white" }
    )

    AddDropdown(
        category,
        "motion",
        "How the numbers move",
        "Rising stream is the calmest: numbers climb straight up at a steady pace, like "
            .. "a scrolling log. The others stay put, arc or shrink as they go.",
        Labels(ns.Motions)
    )

    AddDropdown(
        category,
        "stay",
        "How long a number stays",
        "Longer shows more of your recent hits at once.",
        { "Short", "Medium", "Long" }
    )

    AddCheckbox(
        category,
        "icons",
        "Show a best-guess ability icon beside each number",
        "The game doesn't tell addons which ability a hit was, so Temper works it out from "
            .. "what you just used and the kind of damage. It's usually right, gets better "
            .. "the more it sees, and is sometimes wrong when two things land at once."
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

    AddHeader(layout, "Critical hits")

    AddSlider(
        category,
        "critSize",
        "Size of a critical hit",
        "How large a critical hit is drawn beside an ordinary one. 100% is no larger.",
        { 100, 250, 10 },
        "%"
    )

    AddDropdown(
        category,
        "critStyle",
        "Colour of a critical hit",
        "Same as the hit keeps the colour its kind of damage has, so a crit is told by "
            .. "its size and its landing.",
        { "Gold", "Red", "Same as the hit" }
    )

    AddDropdown(
        category,
        "critLanding",
        "How a critical hit lands",
        "A pop swells the number for a moment as it appears. A shake knocks it from side "
            .. "to side.",
        Labels(ns.Motions.Landings)
    )
end

local function AddScreenOptions(layout)
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
        "Session figures on the panels",
        "How many fights, your average DPS, how often you crit and your biggest hit, for "
            .. "the session you started or else since you logged in. The healing panel shows "
            .. "its own: how much you healed and your average HPS."
    )

    AddCheckbox(
        category,
        "widgetBrand",
        "The Temper icon on the panel",
        "Untick for a plainer panel."
    )

    AddCheckbox(
        category,
        "healWidget",
        "Show the healing panel",
        "A second small panel, the fight panel's twin, with your HPS and what you healed in "
            .. "the fight you're in or the last one."
    )

    AddCheckbox(
        category,
        "recordButton",
        "Show a Start session button on the screen",
        "A small button you can drag anywhere: left-click to start or end a session, "
            .. "right-click to open Temper. Without it, start a session from the Temper "
            .. "window, with a key (Options > Keybindings > Temper), or with /temper session."
    )
end

-- Registered at login rather than when the addon loads, so the Options
-- window has finished setting itself up.
ns.OnEvent("PLAYER_LOGIN", function()
    -- The layout is the page's list of rows. The tick boxes, dropdowns
    -- and sliders add themselves to it; a heading has to be added by hand.
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory(ns.TITLE)

    AddNumberOptions(layout)
    AddScreenOptions(layout)

    Settings.RegisterAddOnCategory(category)
    WatchOptionsWindow()
end)
