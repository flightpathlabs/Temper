local addonName, ns = ...

-- "Report a problem": a window with everything a bug report needs, ready
-- to copy.
--
-- The game can't open a web page or send anything anywhere, and Temper
-- wouldn't if it could. So the best it can do is make a report easy to
-- carry: gather the facts that would otherwise take three messages back
-- and forth to collect, put them in a box, and say where to paste them.
-- The player copies it and sends it themselves, or doesn't.
--
-- What's gathered is about the addon and its surroundings, not the player:
-- no character names, no realm, nothing from their fights. The class and
-- level are in it, since an ability alert or a finding that goes wrong
-- usually goes wrong for one class at some levels, and neither says who
-- anyone is. It's all shown before anything is copied, so there are no
-- surprises in it.
--
-- Temper keeps no record of its own errors. A handler that fails passes
-- its error to the game's error display (see Core\Events.lua), so the
-- report says whether that display is switched on instead.

local Kit = ns.Kit

-- Where reports go.
local ISSUES_URL = "https://github.com/flightpathlabs/Temper/issues/new/choose"

-- The window's size, and how far down its header runs: two lines of
-- instruction and the address.
local WIDTH, HEIGHT = 640, 480
local HEADER_HEIGHT = 92

-- The inset the report sits in keeps this far in from the window's sides.
-- The report's box keeps this far in from the inset's left and right, and
-- leaves this much for the box's own scroll bar.
local INSET_EDGE = 8
local REPORT_LEFT = 10
local REPORT_RIGHT = 28
local SCROLL_BAR_ROOM = 18

-- Other addons that draw combat text, measure damage or dress up
-- nameplates: the ones most likely to be behind numbers in the wrong place,
-- twice over or not at all. These are their folder names as their authors
-- publish them, which nothing here can check; a wrong one is simply never
-- found loaded.
local COMPANIONS = {
    "Details",
    "Skada",
    "Recount",
    "MikScrollingBattleText",
    "Parrot",
    "xCT+",
    "NameplateSCT",
    "ShadowedUnitFrames",
    "Plater",
    "Kui_Nameplates",
    "TidyPlates_ThreatPlates",
    "WeakAuras",
}

-- The game's own settings that change what Temper can show: enemy
-- nameplates, which the numbers follow; its own damage numbers, which
-- Temper switches off while its column shows; its damage meter; and
-- whether it shows Lua errors at all.
local GAME_SETTINGS = {
    "nameplateShowEnemies",
    "floatingCombatTextCombatDamage_v2",
    "damageMeterEnabled",
    "scriptErrors",
}

-- Gathering the facts ---------------------------------------------------------

--- A value as text, or "hidden" if the game won't let it be read.
local function Plain(value)
    if issecretvalue and issecretvalue(value) then
        return "hidden"
    end
    return tostring(value)
end

--- Settings the player has changed, since the defaults are known.
local function ChangedSettings()
    if not ns.settings then
        return "not loaded"
    end

    local changed = {}
    for key, default in pairs(ns.DEFAULT_SETTINGS) do
        local value = ns.settings[key]
        if value ~= default then
            table.insert(changed, ("%s=%s"):format(key, tostring(value)))
        end
    end
    table.sort(changed)
    return #changed > 0 and table.concat(changed, ", ") or "none"
end

--- The game's own settings in GAME_SETTINGS, as they stand.
local function GameSettings()
    local parts = {}
    for _, name in ipairs(GAME_SETTINGS) do
        table.insert(parts, ("%s=%s"):format(name, tostring(GetCVar(name))))
    end
    return table.concat(parts, ", ")
end

--- Which of the COMPANIONS are loaded, with their versions where they
--- give one.
local function LoadedCompanions()
    local loaded = {}
    for _, name in ipairs(COMPANIONS) do
        -- Asking after an addon that isn't installed should only say no,
        -- but this is no place for a surprise.
        local ok, isLoaded = pcall(C_AddOns.IsAddOnLoaded, name)
        if ok and isLoaded then
            local found, version = pcall(C_AddOns.GetAddOnMetadata, name, "Version")
            if found and version then
                table.insert(loaded, ("%s %s"):format(name, version))
            else
                table.insert(loaded, name)
            end
        end
    end
    return #loaded > 0 and table.concat(loaded, ", ") or "none of the ones Temper looks for"
end

--- The whole report, as it goes in the box.
local function ReportText()
    local version, build, _, interface = GetBuildInfo()
    local _, class = UnitClass("player")

    local lines = {
        ns.TITLE .. " " .. (C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"),
        ("Game: %s (build %s, interface %s), %s"):format(
            version,
            build,
            tostring(interface),
            GetLocale()
        ),
        ("Character: level %s %s, %s"):format(
            Plain(UnitLevel("player")),
            class or "?",
            IsInGroup() and "in a group" or "on their own"
        ),
        "Settings changed: " .. ChangedSettings(),
        "Game settings: " .. GameSettings(),
        "Other addons: " .. LoadedCompanions(),
        "",
        "What /temper check says:",
    }

    -- Defined with the slash command, which loads after this file.
    for _, line in ipairs(ns.CheckLines and ns.CheckLines() or {}) do
        table.insert(lines, "  " .. line)
    end

    table.insert(lines, "")
    table.insert(
        lines,
        "Errors: Temper keeps no record of them. Any it met went to the game's error "
            .. "display, which shows them only while scriptErrors is 1."
    )

    return table.concat(lines, "\n")
end

-- The window ------------------------------------------------------------------

-- Made the first time it's asked for.
local window

--- Builds the window, hidden and with nothing in its box yet.
local function Create()
    local frame = CreateFrame("Frame", "TemperReport", UIParent, "ButtonFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetTitle(ns.TITLE .. ": report a problem")
    -- No portrait: the header is all words, and they need the room.
    ButtonFrameTemplate_HidePortrait(frame)
    -- Above the main window, which it's usually opened from.
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    -- Lets Escape close it like any other panel.
    table.insert(UISpecialFrames, frame:GetName())

    -- The panel the report sits in, below the header and above the buttons.
    frame.Inset:ClearAllPoints()
    frame.Inset:SetPoint("TOPLEFT", INSET_EDGE, -HEADER_HEIGHT)
    frame.Inset:SetPoint("BOTTOMRIGHT", -INSET_EDGE, 32)

    local first = Kit.Text(frame, "GameFontHighlight")
    first:SetPoint("TOPLEFT", 16, -30)
    first:SetText("1. Press Select all below, then Ctrl+C to copy the report.")

    local second = Kit.Text(frame, "GameFontHighlight")
    second:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, -8)
    second:SetText("2. Paste it into a new report at this address:")

    -- The address, in a box of its own so it can be copied too.
    local address = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    address:SetSize(WIDTH - 48, 20)
    address:SetPoint("TOPLEFT", second, "BOTTOMLEFT", 6, -6)
    address:SetAutoFocus(false)
    address:SetText(ISSUES_URL)
    address:SetCursorPosition(0)
    -- It's there to be copied, not edited. Put back whatever is typed.
    address:HookScript("OnTextChanged", function(self, byPlayer)
        if byPlayer then
            self:SetText(ISSUES_URL)
            self:HighlightText()
        end
    end)

    -- Blizzard's own scrolling text box. It keeps the cursor in view and
    -- takes the keyboard when clicked, which a bare edit box doesn't.
    local scroll = CreateFrame("ScrollFrame", nil, frame.Inset, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", REPORT_LEFT, -10)
    scroll:SetPoint("BOTTOMRIGHT", -REPORT_RIGHT, 10)
    -- It's built for typing a short note, and counts the letters left.
    scroll.CharCount:Hide()

    -- The text is as wide as what's left of the window once all that is
    -- taken off.
    local report = scroll.EditBox
    report:SetMaxLetters(0)
    report:SetFontObject("GameFontHighlightSmall")
    report:SetWidth(WIDTH - 2 * INSET_EDGE - REPORT_LEFT - REPORT_RIGHT - SCROLL_BAR_ROOM)
    report:SetAutoFocus(false)
    -- The report isn't for editing either.
    report:HookScript("OnTextChanged", function(self, byPlayer)
        if byPlayer and frame.text then
            self:SetText(frame.text)
        end
    end)
    report:HookScript("OnEscapePressed", function()
        frame:Hide()
    end)
    frame.Report = report

    local note = Kit.Text(frame, "GameFontHighlightSmall")
    note:SetPoint("BOTTOMLEFT", 14, 11)
    note:SetTextColor(unpack(Kit.MUTED))
    note:SetText("No character names or realm are in it, and nothing is sent. Read it first.")

    local selectAll = Kit.Button(frame, "Select all", 110, function()
        report:SetFocus()
        report:HighlightText()
    end)
    selectAll:SetPoint("BOTTOMRIGHT", -8, 5)

    return frame
end

--- Opens the report window with a fresh report.
function ns.ShowReport()
    window = window or Create()

    window.text = ReportText()
    window.Report:SetText(window.text)
    window.Report:SetCursorPosition(0)
    window.Report:ClearFocus()
    window:Show()
end
