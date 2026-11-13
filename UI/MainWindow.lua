local addonName, ns = ...

-- The window: a frame in the game's own style with four tabs along the
-- bottom, the way the auction house and the character sheet have them.
--
--   Fights       every fight, and the analysis of whichever are selected
--   Healing and defence   what was healed, what did the hurting and what
--                was stopped, over a set of fights picked from a menu
--   Experiments  a question, two sets of fights, and a verdict
--   Progress     bests and the trend, against nobody but yourself
--
-- Each tab is built by its own file and knows how to redraw itself. This
-- file only owns the frame and decides which tab is showing.
--
-- Our emblem sits in the round corner the game's windows keep for a
-- portrait. The strip beside it, under the title bar, belongs to the tab
-- that's showing: the Fights and Healing tabs put their own things there,
-- and the others get a sentence saying what they're for.

local Kit = ns.Kit

local WIDTH = 900
local HEIGHT = 720

local PORTRAIT = "Interface\\AddOns\\Temper\\Media\\portrait"

-- What the emblem says when the mouse is over it.
local ABOUT = {
    "Understand your own damage: where it comes from, what's holding it back, and whether "
        .. "a change helped.",
    "Your fights are kept on this computer. Nothing is shared or posted.",
}

-- The game only finds a file that's new to an addon when it starts, so
-- straight after an update that adds a tab, that tab isn't there yet.
local RESTART = "This tab is new. Quit the game and start it again to finish installing it."

--- A page that says one thing, standing in for a tab that couldn't be
--- built, so that the rest of the window still opens.
local function PlaceHolder(parent, words)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local text = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("CENTER")
    text:SetText(words)

    function page.Refresh() end
    return page
end

local TABS = {
    {
        label = "Fights",
        -- No sentence here: the tab fills the strip under the title bar
        -- itself.
        build = function(...)
            return ns.FightsTab.Create(...)
        end,
    },
    {
        -- The tab sizes itself to its label, and there's room for the
        -- longer name along the window's foot.
        label = "Healing and defence",
        -- Nor here: its menu of which fights to cover goes in the strip.
        build = function(parent, ...)
            if ns.HealingTab and ns.Healing then
                return ns.HealingTab.Create(parent, ...)
            end
            return PlaceHolder(parent, RESTART)
        end,
    },
    {
        label = "Experiments",
        blurb = "Change one thing, fight a few times each way, and see whether it helped.",
        build = function(...)
            return ns.ExperimentsTab.Create(...)
        end,
    },
    {
        label = "Progress",
        blurb = "Your own bests and your trend, measured against nobody but you.",
        build = function(...)
            return ns.ProgressTab.Create(...)
        end,
    },
}

local FIGHTS, HEALING, EXPERIMENTS = 1, 2, 3

local window
local currentTab = FIGHTS

local function Refresh()
    if window and window:IsShown() then
        window.pages[currentTab]:Refresh()
    end
end

local function ShowTab(index)
    currentTab = index
    PanelTemplates_SetTab(window, index)
    window.blurb:SetText(TABS[index].blurb or "")

    for place, page in ipairs(window.pages) do
        page:SetShown(place == index)
    end
    Refresh()
end

local function CreateTabs(frame)
    for index, definition in ipairs(TABS) do
        -- The template adds each tab to frame.Tabs for us.
        local tab = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
        tab:SetID(index)
        tab:SetText(definition.label)
        PanelTemplates_TabResize(tab, 0)
        tab:SetScript("OnClick", function(self)
            ShowTab(self:GetID())
        end)

        -- Only the first needs placing. SetNumTabs chains the rest to it.
        if index == 1 then
            tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
        end
    end

    PanelTemplates_SetNumTabs(frame, #TABS)
end

--- Tells anyone who points at the emblem what Temper is.
local function CreateEmblemTooltip(frame)
    local hover = CreateFrame("Frame", nil, frame)
    hover:SetAllPoints(frame:GetPortrait())
    hover:SetFrameLevel(frame.CloseButton:GetFrameLevel())

    -- It only wants to know the mouse is there. Clicks go through to the
    -- window, so it can still be dragged by this corner.
    hover:SetMouseClickEnabled(false)
    hover:SetMouseMotionEnabled(true)

    hover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.TITLE)
        for _, line in ipairs(ABOUT) do
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end

        local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
        if version then
            GameTooltip:AddLine("Version " .. version, 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    hover:SetScript("OnLeave", GameTooltip_Hide)
end

local function Create()
    local frame = CreateFrame("Frame", "TemperWindow", UIParent, "ButtonFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 10)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    frame:SetTitle(ns.TITLE)
    frame:SetPortraitTextureRaw(PORTRAIT)
    CreateEmblemTooltip(frame)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    -- The tabs hang below the frame's own edge. Count them as part of it,
    -- or the window can be dragged until they're off the screen.
    frame:SetClampRectInsets(0, 0, 0, -30)

    -- The cog, in the title bar beside the close button and level with
    -- it, so the window's border doesn't draw over it.
    local options = Kit.OptionsButton(frame, 16)
    options:SetPoint("RIGHT", frame.CloseButton, "LEFT", -2, 0)
    options:SetFrameLevel(frame.CloseButton:GetFrameLevel())

    -- The strip under the title bar, clear of the emblem.
    frame.blurb = Kit.Text(frame, "GameFontHighlight")
    frame.blurb:SetPoint("TOPLEFT", 66, -34)
    frame.blurb:SetPoint("RIGHT", -16, 0)

    -- Lets Escape close it like any other panel.
    table.insert(UISpecialFrames, frame:GetName())

    frame.pages = {}
    for index, definition in ipairs(TABS) do
        local page = definition.build(frame.Inset, frame)
        page:Hide()
        frame.pages[index] = page
    end
    CreateTabs(frame)

    frame:SetScript("OnShow", function()
        ShowTab(currentTab)
    end)
    return frame
end

local function Open(tab)
    if not ns.character then
        return false
    end
    if not window then
        window = Create()
    end

    currentTab = tab or currentTab
    if window:IsShown() then
        ShowTab(currentTab)
    else
        window:Show()
    end
    return true
end

function ns.ToggleWindow()
    if window and window:IsShown() then
        window:Hide()
    else
        Open()
    end
end

--- Opens the window on the latest fight, or closes it if it's open. This
--- is what a click on the panel does.
function ns.ShowLatest()
    if window and window:IsShown() then
        window:Hide()
        return
    end
    if not Open(FIGHTS) then
        return
    end

    local fights = ns.character.fights
    if fights[#fights] then
        ns.FightsTab.Select({ fights[#fights] })
    end
end

--- Opens the window on a set of fights, optionally read against another.
---@param fights table  list of fights
---@param against table|nil  list of fights to compare them with
function ns.ShowFights(fights, against)
    if Open(FIGHTS) then
        ns.FightsTab.Select(fights, against)
    end
end

--- Opens the window on one recording. If there's an earlier recording, the
--- two are compared straight away, since that's usually why it was made.
function ns.ShowRecording(recording)
    local earlier = ns.Recorder.Before(recording)
    ns.ShowFights(ns.Recorder.FightsOf(recording), earlier and ns.Recorder.FightsOf(earlier) or nil)
end

--- Opens the window on the Healing tab: on the given fights, as from the
--- Fights page, or with none given, as from the healing panel, on
--- whichever of its own choices it was last on.
---@param fights table|nil  list of fights
function ns.ShowHealing(fights)
    if ns.HealingTab then
        ns.HealingTab.Cover(fights)
    end
    Open(HEALING)
end

--- Opens the window on the Experiments tab.
function ns.ShowExperiments()
    Open(EXPERIMENTS)
end

ns.Subscribe("FIGHTS_CHANGED", Refresh)
ns.Subscribe("EXPERIMENTS_CHANGED", Refresh)

-- Slash command, key binding and the addon list -------------------------------

local function PrintCheck()
    local fights = ns.character and #ns.character.fights or 0
    local recordings = ns.character and #ns.character.recordings or 0
    ns.Print("%d fights on record, %d recordings.", fights, recordings)

    -- Where the numbers have been going, and anything the game objected
    -- to along the way.
    local lane = ns.Lane
    ns.Print(
        "%d numbers followed a nameplate this session; %d had none and went mid-screen.",
        lane.pinned,
        lane.loose
    )
    if not GetCVarBool("nameplateShowEnemies") then
        ns.Print("Enemy nameplates are switched off, so numbers have nothing to follow.")
    end
    if lane.knockedOff > 0 then
        ns.Print(
            "%d more found a nameplate but the game wouldn't pin them to it: %s",
            lane.knockedOff,
            lane.lastRefusal
        )
    end
    if lane.refusal then
        ns.Print("That happened often enough that nameplates are being left alone for now.")
    end
    for what, problem in pairs(lane.complaints) do
        ns.Print("The game objected to a number's %s: %s", what, problem)
    end

    -- What the alerts can watch for this character, and how. Missing
    -- straight after an update, until the game is restarted.
    if ns.Procs then
        for _, line in ipairs(ns.Procs.CheckLines()) do
            ns.Print(line)
        end
    end

    -- Anything the readiness warnings and the buff row had to give up on.
    if ns.Readiness then
        for what, problem in pairs(ns.Readiness.complaints) do
            ns.Print("Temper couldn't read your %s, and has stopped trying: %s", what, problem)
        end
    end
end

SLASH_TEMPER1 = "/temper"
SlashCmdList.TEMPER = function(message)
    message = strtrim(message or ""):lower()

    if message == "session" or message == "record" or message == "stop" then
        ns.ToggleRecording()
    elseif message == "options" then
        ns.OpenOptions()
    elseif message == "example" then
        ns.Example.Toggle()
    elseif message == "check" then
        PrintCheck()
    else
        ns.ToggleWindow()
    end
end

BINDING_NAME_TEMPER_RECORD = "Start or end a session"

function Temper_ToggleRecording()
    ns.ToggleRecording()
end

function Temper_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.OpenOptions()
    else
        ns.ToggleWindow()
    end
end
