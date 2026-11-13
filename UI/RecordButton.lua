local _, ns = ...

-- The session button: one small button that starts and ends a session,
-- which is the player's word for what the code calls a recording.
--
-- Left-click starts or ends one, right-click opens the window, and it can
-- be dragged anywhere. While a session is in progress the button turns red
-- and says how many fights it has so far, which is all the feedback there
-- is. Nothing goes to chat. It's off unless asked for in the options.

-- The button's size, and where it starts out: this far below the middle
-- of the screen.
local WIDTH = 130
local HEIGHT = 24
local BELOW_MIDDLE = 220

-- What the tooltip says, with no session running and with one.
local IDLE_HELP = "Click to start a session. Your fights are kept together until you click "
    .. "again to end it."
local IN_PROGRESS_HELP = "A session is in progress. The number is how many fights it has so far. "
    .. "Click to end it and see the analysis."

local button

--- Shows the button if it's wanted, and says what a click on it would do.
local function Refresh()
    if not button then
        return
    end

    button:SetShown(ns.settings.recordButton)

    local recording = ns.Recorder.Open()
    if recording then
        button:SetText(("|cffff4040End session (%d)|r"):format(#ns.Recorder.FightsOf(recording)))
    else
        button:SetText("Start session")
    end
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(ns.TITLE)

    local help = ns.Recorder.Open() and IN_PROGRESS_HELP or IDLE_HELP
    GameTooltip:AddLine(help, 1, 1, 1, true)
    GameTooltip:AddLine("Right-click to open Temper. Drag to move.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

--- Starts or stops a recording, and shows the analysis of one that has
--- just been stopped. Shared by everything that starts or ends a session:
--- this button, the fight panel's stopwatch and menu, the Fights tab, the
--- key binding and /temper session.
function ns.ToggleRecording()
    if not ns.character then
        return
    end

    -- A recording stopped during its first fight has nothing to show yet.
    local finished = ns.Recorder.Toggle()
    if finished and #ns.Recorder.FightsOf(finished) > 0 then
        ns.ShowRecording(finished)
    end
end

--- Builds the button where it was last left. Whether it shows is for
--- Refresh to say.
local function Create()
    button = CreateFrame("Button", "TemperRecordButton", UIParent, "UIPanelButtonTemplate")
    button:SetSize(WIDTH, HEIGHT)
    button:SetFrameStrata("MEDIUM")
    button:SetClampedToScreen(true)

    -- Back where it was last left, or below the middle of the screen.
    local place = ns.db.button
    if type(place) == "table" and place.point then
        button:SetPoint(place.point, UIParent, place.relativePoint or place.point, place.x, place.y)
    else
        button:SetPoint("CENTER", UIParent, "CENTER", 0, -BELOW_MIDDLE)
    end

    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", button.StartMoving)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        ns.db.button = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.ToggleWindow()
        else
            ns.ToggleRecording()
        end
    end)

    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)
end

ns.Subscribe("DATABASE_READY", function()
    Create()
    Refresh()
end)

ns.Subscribe("FIGHTS_CHANGED", Refresh)
ns.Subscribe("SETTINGS_CHANGED", Refresh)
