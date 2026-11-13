local _, ns = ...

-- Moments that change what the player's best next press is.
--
-- Two kinds, and the game tells us about each differently. A proc is a
-- buff that lands on the player now and then (Clearcasting, say, which
-- makes the next ability free). A reactive ability is one that can only be
-- pressed for a few seconds after something happens (Overpower after the
-- enemy dodges) or while something holds (Execute while the enemy is
-- nearly dead). UI\ProcAlert.lua draws whatever this file says is on.
--
-- What the client allows, as read from its own interface code:
--
--   * Buffs on the player are hidden during a fight, unless the game has
--     flagged that one buff as never hidden. A hidden buff can't even be
--     looked up: the call simply comes back empty. So each buff on our
--     list is asked about once. One the game hides isn't looked for at
--     all: shown only outside a fight, it would vanish at the pull. It's
--     handed instead to a display of the game's own, which may draw what
--     an addon can't read (UI\ProcAlert.lua sets that up), so it's still
--     shown in a fight, only not by us. Inside one it costs us nothing.
--   * Whether an ability can be pressed is never hidden, and that's the
--     very thing a reactive ability's window changes. So it's asked about
--     a few times a second while a fight lasts. If the game turns out to
--     say "yes" all the time, there's a fallback: the window is opened by
--     the dodge, parry or block that opens it in the game, and closed when
--     the ability is used or five seconds pass.
--   * The game lights up an action button when one of its abilities wants
--     pressing. Its pictures for that aren't loaded on this client, but the
--     message behind them may still come. Anything it lights is shown,
--     whether or not it's on our list.
--
-- Nothing here reads anything more than a few times a second, and only
-- while a fight is on or an alert is up. Anything the client refuses is
-- noted once and left alone after that.

local Procs = {}
ns.Procs = Procs

-- How often to look while a fight is on or an alert is up, and how soon
-- after one look a game event may bring on the next.
local LOOK_EVERY = 0.25
local SOONEST = 0.1

-- How long a reactive ability's window stays open after the blow that
-- opened it, when the game won't say itself. It's five seconds for every
-- ability below in the classic game.
local WINDOW_SECONDS = 5

-- A reactive ability can still be open just after a fight. This long
-- after one, every window has closed, and a reading of "ready" means the
-- game isn't really saying.
local SETTLE_SECONDS = 6

local IsSecret = issecretvalue or function()
    return false
end

-- What to watch -------------------------------------------------------------

-- By class, as the game names classes in English whatever the language.
-- Each entry is one of:
--
--   aura     a buff on the player: the spell IDs it can carry. `from` is
--            the talent or ability that grants it, for /temper check
--   ability  a reactive ability: the spell IDs of its ranks. `opens` is
--            what opens its window, by who it happens to, for when the
--            game won't say; `after` says the same in words
--
-- `english` is the name to fall back on if none of the IDs is found.
--
-- The spell IDs are the classic game's, as known from it, and can't be
-- checked against this client's source. A wrong one costs nothing: the
-- name is read from whichever ID the game recognises, everything else is
-- looked up by that name, and an entry with no name found is skipped.

local WATCH = {
    DRUID = {
        -- Omen of Clarity (a passive on Forever) now and then makes the
        -- next ability cost nothing. Best spent on the dearest one to hand.
        { aura = { 16870 }, from = { 16864 }, english = "Clearcasting" },
    },

    MAGE = {
        -- Arcane Concentration makes the next spell free: the moment for
        -- the biggest, costliest one.
        {
            aura = { 12536 },
            from = { 11213, 12574, 12575, 12576, 12577 },
            english = "Clearcasting",
        },
    },

    SHAMAN = {
        -- Elemental Focus, after a critical spell, takes most of the cost
        -- off the next two. A shock or a Chain Lightning, not a Healing
        -- Wave.
        { aura = { 16246 }, from = { 16164 }, english = "Clearcasting" },
    },

    WARLOCK = {
        -- Nightfall's Shadow Trance makes the next Shadow Bolt instant.
        { aura = { 17941 }, from = { 18094, 18095 }, english = "Shadow Trance" },
    },

    WARRIOR = {
        -- Overpower can only follow an enemy's dodge. It's cheap, can't be
        -- blocked, dodged or parried, and often crits.
        {
            ability = { 7384, 7887, 11584, 11585 },
            opens = { target = { DODGE = true } },
            after = "the enemy dodges",
            english = "Overpower",
        },

        -- Revenge follows the warrior's own block, dodge or parry: a lot of
        -- damage and threat for very little rage.
        {
            ability = { 6572, 6574, 7379, 11600, 11601, 25288 },
            opens = { player = { DODGE = true, PARRY = true, BLOCK = true } },
            after = "you block, dodge or parry",
            english = "Revenge",
        },

        -- Execute only works on an enemy nearly dead, and then it's the
        -- best use of rage there is.
        { ability = { 5308, 20658, 20660, 20661, 20662 }, english = "Execute" },
    },

    ROGUE = {
        -- Riposte follows a parry, and disarms as well as hurting.
        {
            ability = { 14251 },
            opens = { player = { PARRY = true } },
            after = "you parry",
            english = "Riposte",
        },
    },

    HUNTER = {
        -- Counterattack follows the hunter's own parry.
        {
            ability = { 19306, 20909, 20910 },
            opens = { player = { PARRY = true } },
            after = "you parry",
            english = "Counterattack",
        },

        -- Mongoose Bite follows a dodge by the enemy, and is a strong
        -- blow for little mana.
        {
            ability = { 1495, 14269, 14270, 14271 },
            opens = { target = { DODGE = true } },
            after = "the enemy dodges",
            english = "Mongoose Bite",
        },
    },

    PALADIN = {
        -- Hammer of Wrath, like Execute, only works on an enemy nearly
        -- dead, from range and hard. Nothing else a paladin has is
        -- granted by chance or opened by a dodge in the classic game.
        { ability = { 24275, 24274, 24239 }, english = "Hammer of Wrath" },
    },

    -- A priest's Inner Focus is pressed, not granted, and the priest has
    -- nothing that's opened by a dodge, so there's nothing to watch.
}

-- State ---------------------------------------------------------------------

-- The class's entries, each with what's been worked out about it:
--
--   name, icon  as the game shows them
--   known       for an ability, whether the player has it; for a buff,
--               whether they have what grants it
--   how         for a buff: "always" if it can be read in a fight,
--               "outside" if the game hides it there. For an ability:
--               "usable" if the game says when it's ready, "window" if we
--               open the window ourselves, "unknown" if neither will do,
--               "unlearned" if the player hasn't got it
--   on          whether it's showing; since, when it came on
--   expires, duration  a buff's timing, when it can be read
--   windowUntil when a window we opened ourselves closes
local entries = {}

-- The class the entries were made for, so they're only made afresh when
-- that changes.
local className

-- Abilities the game has lit up, by spell ID, and every one it has lit
-- this session, for /temper check.
local glowing = {}
local glowSince = {}
local glowSeen = {}
local glowsSeen = 0

-- Whether a fight is on, and when the last one ended.
local fighting = false
local lastFightEnd = -math.huge

-- Set once the game has refused a question, by what was asked, in its own
-- words. Each is asked once and then left alone.
Procs.complaints = {}

--- Asks the game something it might refuse. Once it has refused, that
--- question isn't asked again this session.
---@param what string  a key for Procs.complaints
local function Attempt(what, method, ...)
    if Procs.complaints[what] then
        return false
    end

    local result = { pcall(method, ...) }
    if not result[1] then
        Procs.complaints[what] = tostring(result[2])
        return false
    end
    return true, unpack(result, 2)
end

--- Asks something that may be refused for one spell and not another, so a
--- refusal is no reason to stop asking about the rest.
local function Ask(method, ...)
    if not method then
        return nil
    end

    local result = { pcall(method, ...) }
    if not result[1] then
        return nil
    end
    return unpack(result, 2)
end

--- True when the ability alert is switched on.
local function Enabled()
    return ns.settings ~= nil and ns.settings.procAlert
end

--- True if the player knows any of these spells.
local function KnowsAny(ids)
    for _, id in ipairs(ids or {}) do
        if Ask(C_SpellBook.IsSpellKnownOrInSpellBook, id) or Ask(C_SpellBook.IsSpellKnown, id) then
            return true
        end
    end
    return false
end

--- The first name the game gives for any of the IDs, in the player's own
--- language.
local function NameOf(ids, english)
    for _, id in ipairs(ids) do
        local name = Ask(C_Spell.GetSpellName, id)
        if type(name) == "string" and name ~= "" then
            return name, id
        end
    end
    return english, nil
end

-- Working out what each entry can do ----------------------------------------

--- How a buff can be read: "always", or "outside" a fight only.
local function AuraHow(ids)
    -- A client that never hides anything has nothing to ask about.
    if not C_Secrets or Ask(C_Secrets.HasSecretRestrictions) == false then
        return "always"
    end

    local never = Enum.SecrecyLevel and Enum.SecrecyLevel.NeverSecret
    for _, id in ipairs(ids) do
        local secrecy = Ask(C_Secrets.GetSpellAuraSecrecy, id)
        if never ~= nil and secrecy == never then
            return "always"
        end
    end
    return "outside"
end

--- Whether the game says an ability's window is open: ready to press, or
--- ready but for the rage or mana. nil if the game won't say.
local function ReadsOpen(entry)
    local ok, usable, short = Attempt("usable", C_Spell.IsSpellUsable, entry.name)
    if not ok or IsSecret(usable) or IsSecret(short) then
        return nil
    end
    return usable or short or false
end

--- A quiet moment is one well clear of any fight, when no reactive window
--- can be open.
local function Quiet()
    return not fighting and GetTime() - lastFightEnd >= SETTLE_SECONDS
end

--- Settles whether the player has a reactive ability, and how its window
--- can be told.
local function WorkOutAbility(entry)
    -- Looked up by name, which finds the rank the player has.
    local own = entry.name and Ask(C_Spell.GetSpellIDForSpellIdentifier, entry.name)
    entry.known = (own ~= nil and KnowsAny({ own })) or KnowsAny(entry.ability)
    if not entry.known then
        entry.how = "unlearned"
        return
    end

    -- Settled once, at a quiet moment. Until then the game is taken at its
    -- word.
    if entry.tested then
        return
    end
    entry.how = "usable"
    if not Quiet() then
        return
    end
    entry.tested = true

    -- Nothing can have opened the window now. "Ready" means the game
    -- doesn't really say.
    if ReadsOpen(entry) == false then
        return
    end
    entry.how = entry.opens and "window" or "unknown"
end

--- Works out one entry's name, icon and how it can be read.
local function WorkOut(entry)
    if entry.aura then
        entry.name = NameOf(entry.aura, entry.english)
        entry.icon = Ask(C_Spell.GetSpellTexture, entry.aura[1])
        entry.known = KnowsAny(entry.from)
        entry.how = AuraHow(entry.aura)
        return
    end

    local name, id = NameOf(entry.ability, entry.english)
    entry.name = name
    entry.icon = Ask(C_Spell.GetSpellTexture, name) or (id and Ask(C_Spell.GetSpellTexture, id))
    WorkOutAbility(entry)
end

--- Works out the class's entries afresh. Their state (whether each is
--- showing) is kept, so learning a rank mid-fight doesn't sound an alert
--- twice.
local function Rebuild()
    local _, class = UnitClass("player")
    if class ~= className then
        className = class
        entries = {}
        for _, watch in ipairs(WATCH[class] or {}) do
            local entry = setmetatable({}, { __index = watch })
            table.insert(entries, entry)
        end
    end

    for _, entry in ipairs(entries) do
        WorkOut(entry)
    end
end

-- Reading -------------------------------------------------------------------

--- The buff, if it's on the player and the game will show it.
local function FindAura(entry)
    for _, id in ipairs(entry.aura) do
        local aura = Ask(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if aura then
            return aura
        end
    end

    -- By name, in case the game's ID for it is another than ours. The three
    -- Clearcastings share a name, which does no harm: a class only ever
    -- gets its own.
    return entry.name and Ask(C_UnitAuras.GetAuraDataBySpellName, "player", entry.name, "HELPFUL")
end

--- Whether a buff is on, and its timing when that can be read.
local function ReadAura(entry)
    -- One the game hides in a fight is left to the game's own display.
    -- Shown by us only outside one, it would vanish at the pull, just when
    -- it matters, and come back with a sound when the fight was over.
    if entry.how ~= "always" then
        return false
    end

    local aura = FindAura(entry)
    if type(aura) ~= "table" then
        return false
    end

    local expires, duration = aura.expirationTime, aura.duration
    if IsSecret(expires) or IsSecret(duration) or type(duration) ~= "number" or duration <= 0 then
        return true
    end
    return true, expires, duration
end

--- Whether a reactive ability's window is open.
local function ReadAbility(entry, now)
    if entry.how == "usable" then
        local open = ReadsOpen(entry)
        if open == nil then
            -- Refused mid-fight. The window can still be opened by hand.
            entry.how = entry.opens and "window" or "unknown"
            return false
        end
        return open
    elseif entry.how == "window" then
        return entry.windowUntil ~= nil and now < entry.windowUntil
    end
    return false
end

--- Whether the game has lit up an ability by this name.
local function LitByName(name)
    for id in pairs(glowing) do
        if Ask(C_Spell.GetSpellName, id) == name then
            return true
        end
    end
    return false
end

--- Whether an entry is on, and a buff's timing when that can be read.
local function Read(entry, now)
    if not entry.name then
        return false
    end

    local on, expires, duration
    if entry.aura then
        on, expires, duration = ReadAura(entry)
    else
        on = ReadAbility(entry, now)
    end
    return on or LitByName(entry.name), expires, duration
end

-- Looking -------------------------------------------------------------------

-- Shown only while there's a reason to look, so it costs nothing otherwise.
local poller = CreateFrame("Frame")
poller:Hide()

-- Seconds since the last look, and whether a look has been asked for.
local sinceLook = 0
local wanted = false

-- What can be read during a fight. Anything else is left alone there.
local IN_A_FIGHT = { always = true, usable = true, window = true }

--- Whether there's any reason to keep looking: something showing that may
--- go, or a fight on with something in it worth watching for.
local function WorthLooking()
    if next(glowing) then
        return true
    end
    for _, entry in ipairs(entries) do
        if entry.on or (fighting and IN_A_FIGHT[entry.how]) then
            return true
        end
    end
    return false
end

--- Reads every entry, and says so if anything changed.
local function Look()
    sinceLook = 0
    wanted = false
    if not Enabled() then
        poller:Hide()
        return
    end

    local now = GetTime()
    local changed = false
    for _, entry in ipairs(entries) do
        local on, expires, duration = Read(entry, now)
        on = on and true or false

        if on ~= (entry.on or false) or expires ~= entry.expires then
            changed = true
            if on and not entry.on then
                entry.since = now
            end
            entry.on = on
            entry.expires = expires
            entry.duration = duration
        end
    end

    poller:SetShown(WorthLooking())
    if changed then
        ns.Publish("PROCS_CHANGED")
    end
end

--- Asks for a look as soon as is reasonable, rather than straight away:
--- some events come in bursts.
local function LookSoon()
    if not Enabled() then
        return
    end
    wanted = true
    poller:Show()
end

poller:SetScript("OnUpdate", function(_, elapsed)
    sinceLook = sinceLook + elapsed
    if sinceLook >= LOOK_EVERY or (wanted and sinceLook >= SOONEST) then
        Look()
    end
end)

-- What the alert is told ----------------------------------------------------

--- What's on, oldest first.
---@return table  list of { key, name, icon, expires, duration, since },
---               where expires and duration are a buff's timing when it
---               can be read, for a sweep, and since is when it came on
function Procs.Active()
    local active = {}
    if not Enabled() then
        return active
    end

    local named = {}
    for _, entry in ipairs(entries) do
        if entry.name then
            named[entry.name] = true
        end
        if entry.on then
            table.insert(active, {
                key = entry.name,
                name = entry.name,
                icon = entry.icon,
                expires = entry.expires,
                duration = entry.duration,
                since = entry.since or 0,
            })
        end
    end

    -- Anything else the game has lit up, unless it's one of ours under
    -- another rank's ID.
    for id in pairs(glowing) do
        local name = Ask(C_Spell.GetSpellName, id)
        if name and not named[name] then
            named[name] = true
            table.insert(active, {
                key = name,
                name = name,
                icon = Ask(C_Spell.GetSpellTexture, id),
                since = glowSince[id] or 0,
            })
        end
    end

    table.sort(active, function(a, b)
        return a.since < b.since
    end)
    return active
end

--- The buffs the game hides in a fight, for the game's own display to
--- draw instead.
---@return table  list of { name, ids, known }, where ids are the spell IDs
---               the buff can carry and known is whether the player has
---               what grants it
function Procs.HiddenInFights()
    local hidden = {}
    for _, entry in ipairs(entries) do
        if entry.aura and entry.name and entry.how ~= "always" then
            table.insert(hidden, { name = entry.name, ids = entry.aura, known = entry.known })
        end
    end
    return hidden
end

-- For /temper check ---------------------------------------------------------

-- What's said of a buff the game hides in a fight, by how the game's own
-- display fares with it (see ProcAlert.GameDrawing).
local HIDDEN_BUFF_LINES = {
    ready = "%s: the game keeps it from addons in a fight, so the game draws it itself "
        .. "in the alert's place, in a fight and out of one. It comes without the "
        .. "alert's sound, which the game can't be asked to play for it.",
    waiting = "%s: the game keeps it from addons in a fight. Once this fight is over, "
        .. "the game will draw it itself in the alert's place.",
    failed = "%s: the game hides it during a fight and wouldn't draw it for Temper "
        .. "(see below), so Temper can't alert you to it.",
    off = "%s: the game keeps it from addons in a fight, so while alerts are on the "
        .. "game draws it itself in the alert's place.",
}

--- One entry's line for /temper check.
local function EntryLine(entry)
    local name = entry.name or entry.english

    if entry.aura then
        local line
        if entry.how == "always" then
            line = "%s: shown in a fight and out of one."
        else
            local drawing = ns.ProcAlert and ns.ProcAlert.GameDrawing(entry.name)
            line = HIDDEN_BUFF_LINES[drawing or "off"]
        end
        line = line:format(name)
        if not entry.known then
            line = line .. " (What grants it doesn't look learned yet.)"
        end
        return line
    end

    if entry.how == "unlearned" then
        return ("%s: not learned yet."):format(name)
    elseif entry.how == "usable" then
        return ("%s: the game says when it's ready, so it's shown the moment it is."):format(name)
    end

    local unsaid = ("%s: the game doesn't say when it's ready"):format(name)
    if entry.how == "window" then
        return ("%s, so it's shown for %d seconds after %s."):format(
            unsaid,
            WINDOW_SECONDS,
            entry.after
        )
    end
    return unsaid .. ", so it's left out."
end

--- What the alert can and can't watch for on this character, as lines of
--- text for /temper check.
---@return table  list of strings
function Procs.CheckLines()
    local lines = {}
    if not ns.settings then
        return lines
    end

    if ns.settings.procAlert then
        table.insert(lines, "Ability alerts are on.")
    else
        table.insert(
            lines,
            ("Ability alerts are off. They can be switched on in Options > AddOns > %s."):format(
                ns.TITLE
            )
        )
    end

    Rebuild()
    if #entries == 0 then
        table.insert(lines, "Nothing on the list for your class.")
    end
    for _, entry in ipairs(entries) do
        table.insert(lines, EntryLine(entry))
    end

    if glowsSeen == 1 then
        table.insert(lines, "The game has lit up 1 ability this session, and it's shown too.")
    elseif glowsSeen > 1 then
        table.insert(
            lines,
            ("The game has lit up %d abilities this session, and they're shown too."):format(
                glowsSeen
            )
        )
    else
        table.insert(lines, "The game hasn't lit up any ability this session.")
    end

    for what, problem in pairs(Procs.complaints) do
        table.insert(lines, ("The game refused a question (%s): %s"):format(what, problem))
    end

    -- And anything it objected to in drawing the alert.
    local drawing = ns.ProcAlert and ns.ProcAlert.complaints or {}
    for what, problem in pairs(drawing) do
        table.insert(lines, ("The game objected to the alert's %s: %s"):format(what, problem))
    end
    return lines
end

-- Events --------------------------------------------------------------------

ns.Subscribe("DATABASE_READY", function()
    -- A reload in the middle of a fight brings no word that one began.
    fighting = InCombatLockdown()
    Rebuild()
    Look()
end)

ns.Subscribe("SETTINGS_CHANGED", function()
    if Enabled() then
        Rebuild()
        Look()
    else
        poller:Hide()
        for _, entry in ipairs(entries) do
            entry.on = false
        end
        ns.Publish("PROCS_CHANGED")
    end
end)

-- Learning a rank or a talent changes what can be watched.
ns.OnEvent("SPELLS_CHANGED", function()
    if ns.settings then
        Rebuild()
    end
end)

ns.OnEvent("PLAYER_REGEN_DISABLED", function()
    fighting = true
    LookSoon()
end)

-- Out of a fight, a buff the game was hiding can be read again.
ns.OnEvent("PLAYER_REGEN_ENABLED", function()
    fighting = false
    lastFightEnd = GetTime()
    LookSoon()
end)

-- The game says when an ability's usability may have changed. It's only a
-- prompt to look: what's looked at is the same either way.
ns.OnEvent("SPELL_UPDATE_USABLE", LookSoon)

-- Our own frame for the player's buffs, registered for the player alone.
-- The shared one would hear about every nameplate's as well, which in a
-- busy place is a great many.
local auraWatch = CreateFrame("Frame")
pcall(auraWatch.RegisterUnitEvent, auraWatch, "UNIT_AURA", "player")
auraWatch:SetScript("OnEvent", LookSoon)

-- The game lights an ability up, or lets it go.
ns.OnEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(spellID)
    if IsSecret(spellID) or type(spellID) ~= "number" then
        return
    end

    if not glowing[spellID] then
        glowSince[spellID] = GetTime()
    end
    glowing[spellID] = true
    if not glowSeen[spellID] then
        glowSeen[spellID] = true
        glowsSeen = glowsSeen + 1
    end
    LookSoon()
    ns.Publish("PROCS_CHANGED")
end)

ns.OnEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(spellID)
    if IsSecret(spellID) or not glowing[spellID] then
        return
    end
    glowing[spellID] = nil
    glowSince[spellID] = nil
    LookSoon()
    ns.Publish("PROCS_CHANGED")
end)

-- A loading screen ends whatever the game had lit.
ns.OnEvent("PLAYER_ENTERING_WORLD", function()
    if next(glowing) then
        glowing = {}
        glowSince = {}
        ns.Publish("PROCS_CHANGED")
    end
end)

-- When the game won't say, the blow that opens a window opens ours. The
-- event doesn't say whose blow it was; alone, an enemy's dodge was of the
-- player's attack or their pet's.
ns.OnEvent("UNIT_COMBAT", function(unit, action, flag)
    if not Enabled() or IsSecret(unit) or IsSecret(action) or IsSecret(flag) then
        return
    end

    local side = (unit == "player" and "player") or (unit == "target" and "target")
    if not side then
        return
    end

    -- A blow only partly blocked still counts as a block.
    local what = action
    if action == "WOUND" and (flag == "BLOCK" or flag == "BLOCK_REDUCED") then
        what = "BLOCK"
    end

    for _, entry in ipairs(entries) do
        local opens = entry.how == "window" and entry.opens and entry.opens[side]
        if opens and opens[what] then
            entry.windowUntil = GetTime() + WINDOW_SECONDS
            LookSoon()
        end
    end
end)

-- Using the ability closes a window we opened.
ns.Subscribe("PLAYER_CAST", function(spellID)
    local name = Ask(C_Spell.GetSpellName, spellID)
    for _, entry in ipairs(entries) do
        if entry.how == "window" and entry.windowUntil and entry.name == name then
            entry.windowUntil = nil
            LookSoon()
        end
    end
end)
