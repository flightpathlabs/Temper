local _, ns = ...

-- The window: a frame in the game's own style with three tabs along the
-- bottom, the way the auction house and the character sheet have them.
--
--   Fights       every fight, and the analysis of whichever are selected
--   Experiments  a question, two sets of fights, and a verdict
--   Progress     bests and the trend, against nobody but yourself
--
-- Each tab is built by its own file and knows how to redraw itself. This
-- file only owns the frame and decides which tab is showing.

local WIDTH = 900
local HEIGHT = 680

local TABS = {
    {
        label = "Fights",
        build = function(...)
            return ns.FightsTab.Create(...)
        end,
    },
    {
        label = "Experiments",
        build = function(...)
            return ns.ExperimentsTab.Create(...)
        end,
    },
    {
        label = "Progress",
        build = function(...)
            return ns.ProgressTab.Create(...)
        end,
    },
}

local FIGHTS, EXPERIMENTS = 1, 2

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

local function Create()
    local frame = CreateFrame("Frame", "TemperWindow", UIParent, "ButtonFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 10)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    ButtonFrameTemplate_HidePortrait(frame)

    -- Without a portrait the strip under the title bar holds nothing.
    ButtonFrameTemplate_HideAttic(frame)
    frame:SetTitle(ns.TITLE)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

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

    if ns.Lane.refusal then
        ns.Print("The game wouldn't pin numbers to a nameplate: %s", ns.Lane.refusal)
    else
        ns.Print("Numbers are pinning to nameplates without complaint.")
    end
    if ns.Lane.iconRefusal then
        ns.Print("The game wouldn't draw icons beside them: %s", ns.Lane.iconRefusal)
    end
end

SLASH_TEMPER1 = "/temper"
SlashCmdList.TEMPER = function(message)
    message = strtrim(message or ""):lower()

    if message == "session" or message == "record" or message == "stop" then
        ns.ToggleRecording()
    elseif message == "options" then
        ns.OpenOptions()
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
