local _, ns = ...

-- The Record button: one small button that starts and stops a recording.
--
-- Left-click records, right-click opens the window, and it can be dragged
-- anywhere. While recording it says how many fights it has so far, which
-- is all the feedback there is. Nothing goes to chat.

local WIDTH = 124
local HEIGHT = 24

local button

local function Refresh()
    if not button then
        return
    end

    button:SetShown(ns.settings.recordButton)

    local recording = ns.Recorder.Open()
    if recording then
        local fights = #ns.Recorder.FightsOf(recording)
        button:SetText(
            ("|cffff4040Stop|r  %d %s"):format(fights, fights == 1 and "fight" or "fights")
        )
    else
        button:SetText("Record")
    end
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(ns.TITLE)

    if ns.Recorder.Open() then
        GameTooltip:AddLine("Recording. Click to stop and see the analysis.", 1, 1, 1, true)
    else
        GameTooltip:AddLine("Click to record your fights, then click again to stop.", 1, 1, 1, true)
    end
    GameTooltip:AddLine("Right-click to open the window. Drag to move.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

--- Starts or stops a recording, and shows the analysis of one that has
--- just been stopped. Shared by the button, the key binding and /temper.
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
        button:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
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
