local _, ns = ...

-- The window: recordings down the left, the analysis of one on the right.
--
-- Click a recording to read it. Choose a second with "Compare with..." (or
-- by right-clicking it in the list) and the analysis grows green and red
-- figures showing what changed.

local WIDTH = 780
local HEIGHT = 580
local LIST_WIDTH = 210
local ROW_HEIGHT = 40

local window

-- The recording being read, and the one it's compared with, if any.
local selected
local baseline

--- True if two list entries are the same recording. The unrecorded fights
--- are a fresh entry every time the list is built, so they're matched by
--- what they are.
local function Same(a, b)
    if not a or not b then
        return false
    end
    return a == b or (a.recent and b.recent) or false
end

local function Find(list, wanted)
    for _, recording in ipairs(list) do
        if Same(recording, wanted) then
            return recording
        end
    end
end

local Refresh

local function ShowRowMenu(row, recording)
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(ns.Recorder.Label(recording))

        if Same(recording, baseline) then
            root:CreateButton("Stop comparing with this", function()
                baseline = nil
                Refresh()
            end)
        elseif not Same(recording, selected) then
            root:CreateButton("Compare with this", function()
                baseline = recording
                Refresh()
            end)
        end

        if not recording.recent then
            root:CreateButton("Delete", function()
                ns.Recorder.Delete(recording)
            end)
        end
    end)
end

local function CreateRowWidgets(row)
    row.created = true
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.chosen = row:CreateTexture(nil, "BACKGROUND")
    row.chosen:SetAllPoints()
    row.chosen:SetColorTexture(1, 0.82, 0, 0.12)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)

    row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.title:SetPoint("TOPLEFT", 8, -6)
    row.title:SetPoint("RIGHT", -8, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)

    row.detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.detail:SetPoint("RIGHT", -8, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)

    row:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            ShowRowMenu(self, self.recording)
            return
        end

        selected = self.recording
        if Same(selected, baseline) then
            baseline = nil
        end
        Refresh()
    end)
end

local function FillRow(row, recording)
    row.recording = recording
    row.chosen:SetShown(Same(recording, selected))

    local title = ns.Recorder.Label(recording)
    if ns.Recorder.Open() == recording then
        title = title .. "  |cffff4040recording|r"
    elseif Same(recording, baseline) then
        title = title .. "  |cff999999compared|r"
    end
    row.title:SetText(title)

    local summary = ns.Summary.Of(recording)
    if summary.fights == 0 then
        row.detail:SetText("No fights yet")
    else
        row.detail:SetText(
            ("%d %s   %s a second"):format(
                summary.fights,
                summary.fights == 1 and "fight" or "fights",
                ns.Rate(summary.dps)
            )
        )
    end
end

--- The menu behind "Compare with...": every other recording, and a way out.
local function ShowCompareMenu(button)
    MenuUtil.CreateContextMenu(button, function(_, root)
        root:CreateTitle("Compare with")

        for _, recording in ipairs(ns.Recorder.List()) do
            if not Same(recording, selected) and #recording.fights > 0 then
                root:CreateRadio(ns.Recorder.Label(recording), function()
                    return Same(recording, baseline)
                end, function()
                    baseline = recording
                    Refresh()
                end)
            end
        end

        root:CreateRadio("Nothing", function()
            return baseline == nil
        end, function()
            baseline = nil
            Refresh()
        end)
    end)
end

local function Create()
    local frame = CreateFrame("Frame", "StrikewiseWindow", UIParent, "ButtonFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    ButtonFrameTemplate_HidePortrait(frame)
    frame:SetTitle(ns.TITLE)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    -- Lets Escape close it like any other panel.
    table.insert(UISpecialFrames, frame:GetName())

    local inset = frame.Inset

    local scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 6, -6)
    scrollBox:SetPoint("BOTTOMLEFT", 6, 6)
    scrollBox:SetWidth(LIST_WIDTH)

    local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

    local view = CreateScrollBoxListLinearView()
    -- Rows are plain buttons rather than an XML template, so the list can't
    -- work out their height for itself.
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, recording)
        if not row.created then
            CreateRowWidgets(row)
        end
        FillRow(row, recording)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    frame.scrollBox = scrollBox

    frame.card = ns.Card.Create(inset, ShowCompareMenu)
    frame.card:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 22, 0)
    frame.card:SetPoint("BOTTOMRIGHT", -4, 4)

    -- The same Record button as the one on the screen, for people who've
    -- hidden that one.
    frame.record = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.record:SetSize(120, 22)
    frame.record:SetPoint("BOTTOMLEFT", 8, 4)
    frame.record:SetScript("OnClick", function()
        ns.ToggleRecording()
    end)

    frame:SetScript("OnShow", function()
        Refresh()
    end)
    return frame
end

function Refresh()
    if not window or not window:IsShown() then
        return
    end

    -- Hold on to the choices across a rebuild of the list, and drop any
    -- that have since been deleted.
    local list = ns.Recorder.List()
    selected = Find(list, selected) or list[1]
    baseline = Find(list, baseline)
    if Same(selected, baseline) then
        baseline = nil
    end

    window.scrollBox:SetDataProvider(
        CreateDataProvider(list),
        ScrollBoxConstants.RetainScrollPosition
    )
    window.card:SetShown(true)
    ns.Card.Fill(window.card, selected, baseline)
    window.record:SetText(ns.Recorder.Open() and "Stop recording" or "Record")
end

function ns.ToggleWindow()
    if not ns.character then
        return
    end
    if not window then
        window = Create()
    end
    window:SetShown(not window:IsShown())
end

--- Opens the window on one recording. If there's an earlier recording, the
--- two are compared straight away, since that's usually why it was made.
function ns.ShowRecording(recording)
    if not window then
        window = Create()
    end

    local list = ns.Recorder.List()
    selected = recording
    baseline = nil
    for index, candidate in ipairs(list) do
        if candidate == recording then
            local earlier = list[index + 1]
            if earlier and not earlier.recent then
                baseline = earlier
            end
            break
        end
    end

    window:Show()
    Refresh()
end

ns.Subscribe("RECORDINGS_CHANGED", function()
    Refresh()
end)

-- Slash command, key binding and the addon list -------------------------------

local function PrintCheck()
    local recordings = ns.character and #ns.character.recordings or 0
    local recent = ns.character and #ns.character.recent or 0
    ns.Print("%d recordings and %d recent fights on record.", recordings, recent)

    if ns.Lane.refusal then
        ns.Print("The game wouldn't pin numbers to a nameplate: %s", ns.Lane.refusal)
    else
        ns.Print("Numbers are pinning to nameplates without complaint.")
    end
end

SLASH_STRIKEWISE1 = "/strikewise"
SLASH_STRIKEWISE2 = "/strike"
SlashCmdList.STRIKEWISE = function(message)
    message = strtrim(message or ""):lower()

    if message == "record" or message == "stop" then
        ns.ToggleRecording()
    elseif message == "options" then
        ns.OpenOptions()
    elseif message == "check" then
        PrintCheck()
    else
        ns.ToggleWindow()
    end
end

BINDING_NAME_STRIKEWISE_RECORD = "Start or stop recording"

function Strikewise_ToggleRecording()
    ns.ToggleRecording()
end

function Strikewise_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.OpenOptions()
    else
        ns.ToggleWindow()
    end
end
