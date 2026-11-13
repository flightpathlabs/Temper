local _, ns = ...

-- The example enemy: a stand-in nameplate with made-up hits playing on
-- it, so a change in the options can be judged as it's made without
-- finding something to hit.
--
-- It stands beside the game's Options window while Temper's page is
-- open, in front of everything, and can be dragged to wherever the
-- numbers are easiest to see. `/temper example` shows it at any other
-- time, and puts it away again. Samples of the ability alert and of the
-- warning above the fight panel come and go with it (see ProcAlert.lua
-- and ReadyAlert.lua).

local Example = {}
ns.Example = Example

local Kit = ns.Kit

-- About the size of one of the game's nameplates: a name over a bar.
local WIDTH = 132
local HEIGHT = 30
local BAR_HEIGHT = 10

-- Seconds between one made-up hit and the next.
local HIT_EVERY = 0.7

-- Where it stands until it's dragged: a little way off the Options
-- window's right-hand side and below its middle, or, with that window
-- shut, this far above the middle of the screen.
local BESIDE_OPTIONS_X = 24
local BESIDE_OPTIONS_Y = -40
local ABOVE_MIDDLE = 100

-- The stand-in nameplate, and what plays the hits on it while it shows.
local stand
local ticker

-- Asked for by hand with the slash command, whatever the Options window
-- is doing.
local keptOpen = false

--- Where it was last left, or beside the Options window if that's open.
local function PutInPlace()
    stand:ClearAllPoints()

    local place = ns.db.example
    if type(place) == "table" and place.point then
        stand:SetPoint(place.point, UIParent, place.relativePoint or place.point, place.x, place.y)
    elseif SettingsPanel and SettingsPanel:IsShown() then
        stand:SetPoint("LEFT", SettingsPanel, "RIGHT", BESIDE_OPTIONS_X, BESIDE_OPTIONS_Y)
    else
        stand:SetPoint("CENTER", UIParent, "CENTER", 0, ABOVE_MIDDLE)
    end
end

--- Starts the made-up hits, one at once and then one every so often.
local function StartHits()
    -- The numbers live under the game's windows as a rule. While the
    -- example is up they have to be in front, or the Options window
    -- would hide the very thing it's adjusting.
    ns.Lane.BringForward(true)

    ns.Feed.ShowSample(stand)
    ticker = C_Timer.NewTicker(HIT_EVERY, function()
        ns.Feed.ShowSample(stand)
    end)
end

--- Stops the hits and clears away any still on screen.
local function StopHits()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    ns.Lane.Clear(stand)
    ns.Lane.BringForward(false)
end

--- Builds the stand-in nameplate, hidden. The hits start and stop as it
--- shows and hides.
local function Create()
    stand = CreateFrame("Frame", "TemperExample", UIParent)
    stand:SetSize(WIDTH, HEIGHT)
    stand:SetFrameStrata("DIALOG")
    stand:SetClampedToScreen(true)
    stand:Hide()

    stand:SetMovable(true)
    stand:EnableMouse(true)
    stand:RegisterForDrag("LeftButton")
    stand:SetScript("OnDragStart", stand.StartMoving)
    stand:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        ns.db.example = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)

    local name = Kit.Text(stand, "GameFontNormalSmall", "CENTER")
    name:SetPoint("TOP")
    name:SetText("Example enemy")

    -- A plain red bar with a dark edge stands in for the health bar.
    local edge = stand:CreateTexture(nil, "BACKGROUND")
    edge:SetColorTexture(0, 0, 0, 0.9)
    edge:SetPoint("BOTTOMLEFT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetHeight(BAR_HEIGHT + 2)

    local bar = stand:CreateTexture(nil, "ARTWORK")
    bar:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
    bar:SetVertexColor(0.85, 0.15, 0.1)
    bar:SetPoint("BOTTOMLEFT", 1, 1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetHeight(BAR_HEIGHT)

    local hint = Kit.Text(stand, "GameFontDisableSmall", "CENTER")
    hint:SetPoint("TOP", stand, "BOTTOM", 0, -3)
    hint:SetText("Drag me where you can see")

    stand:SetScript("OnShow", StartHits)
    stand:SetScript("OnHide", StopHits)
end

--- Shows the example if it's wanted now and hides it if it isn't. Called
--- whenever that might have changed.
function Example.Refresh()
    local wanted = keptOpen or ns.OptionsPageShowing()

    -- The ability alert shows a sample at the same times, so it can be
    -- seen and placed too, and so does the warning above the fight panel.
    if ns.ProcAlert then
        ns.ProcAlert.Sample(wanted)
    end
    if ns.ReadyAlert then
        ns.ReadyAlert.Sample(wanted)
    end

    if not wanted and not stand then
        return
    end
    if not stand then
        Create()
    end

    if wanted and not stand:IsShown() then
        PutInPlace()
        stand:Show()
    elseif not wanted and stand:IsShown() then
        stand:Hide()
    end
end

--- Shows the example whatever the Options window is doing, or puts it
--- away again. This is what `/temper example` does.
function Example.Toggle()
    keptOpen = not keptOpen
    Example.Refresh()

    if keptOpen then
        ns.Print("Example hits are playing. Type /temper example again to put them away.")
    end
end
