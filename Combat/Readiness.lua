local _, ns = ...

-- Whether the player is ready for a fight, and which of the usual buffs
-- they have up.
--
-- Two screens draw from this. The warning box above the fight panel
-- (UI\ReadyAlert.lua) lists what's amiss: a fishing pole still in hand, a
-- buff of the class's own not up, a weapon with no poison or imbue on it,
-- ammunition running low, gear about to break, a pet away or unhappy.
-- The row of small icons along the bottom of the panel (UI\Widget.lua)
-- lights for each kind of buff that's on. This file does the looking and
-- keeps the answers; those two only draw them.
--
-- What the client allows, as read from its own interface code:
--
--   * The player's buffs can be read freely outside a fight. Inside one
--     they're hidden, so they're only read outside, and what the screens
--     show during a fight is how things stood as it began.
--   * What's in hand, a weapon's stone, oil, poison or imbue, how worn the
--     gear is, the ammunition and the pet aren't marked as hidden anywhere.
--     They're still asked about under pcall, anything that comes back
--     hidden is left as it was, and a part the game refuses outright is
--     noted once and not asked about again.
--
-- Nothing here runs every frame. It looks a moment after the game says
-- something changed, so a burst of news makes one look, and every ten
-- seconds outside a fight for what the game doesn't announce, such as a
-- weapon's oil wearing off. During a fight it looks again only when a
-- weapon is swapped or the pet comes or goes.

local Readiness = {}
ns.Readiness = Readiness

-- How soon after the game's news to look, and how often to look anyway
-- outside a fight.
local LOOK_SOON = 0.2
local LOOK_EVERY = 10

-- Gear at or under this share of its durability is about to break.
local WORN_OUT = 0.1

-- Fewer arrows or bullets than this is running low: a few minutes of
-- shooting.
local LOW_AMMO = 100

-- Flasks can't be drunk before this level.
local FLASK_LEVEL = 50

-- More buffs than a character can carry at once.
local MOST_AURAS = 40

-- Inventory slots, by the game's own names for them.
local MAIN_HAND = INVSLOT_MAINHAND or 16
local OFF_HAND = INVSLOT_OFFHAND or 17
local RANGED = INVSLOT_RANGED or 18
local AMMO = INVSLOT_AMMO or 0
local FIRST_WORN = INVSLOT_FIRST_EQUIPPED or 1
local LAST_WORN = INVSLOT_LAST_EQUIPPED or 19

-- The lowest of a hunter's pet's three moods. An unhappy pet does less
-- damage, and in time runs off.
local UNHAPPY = 1

-- The picture for rested experience, which has no buff of its own.
local RESTED_ICON = "Interface\\Icons\\Spell_Nature_Sleep"

local IsSecret = issecretvalue or function()
    return false
end

-- What to look for ------------------------------------------------------------

-- The spell and item IDs below are the classic game's, as known from it,
-- and couldn't be checked against this client's source. A wrong one costs
-- nothing: a buff is found by its ID, or (where it says `named`) by the
-- name the game gives that ID, and an ID the game doesn't know is skipped.
--
-- Each kind of buff is a table of:
--
--   ids      the buff's own spell IDs, to be found by
--   named    spell IDs whose names are looked for, for buffs that come in
--            many ranks or from many foods under the one name
--   english  the name to look for when none of `named` is found
--   look     where its picture comes from when none is on: an item, a
--            spell, or a file

-- Well Fed, from food. Many foods give it under IDs of their own, so it's
-- found by name too.
local FOOD = {
    ids = { 19705, 19706, 19708, 19709, 19710, 19711 },
    named = { 19705 },
    english = "Well Fed",
    look = { spell = 19705 },
}

-- Elixirs and their kin, from the first ones up to those made for raids.
-- Their buffs have plain names that other buffs share ("Agility",
-- "Armor"), so they're found by ID alone. One that isn't here simply
-- doesn't light the icon.
local ELIXIRS = {
    ids = {
        673, -- Elixir of Minor Defense
        2367, -- Elixir of Lion's Strength
        2374, -- Elixir of Minor Agility
        2378, -- Elixir of Minor Fortitude
        3160, -- Elixir of Lesser Agility
        3164, -- Elixir of Ogre's Strength
        3166, -- Elixir of Wisdom
        3219, -- Weak Troll's Blood Potion
        3220, -- Elixir of Defense
        3222, -- Strong Troll's Blood Potion
        3223, -- Mighty Troll's Blood Potion
        3593, -- Elixir of Fortitude
        7844, -- Elixir of Firepower
        11328, -- Elixir of Agility
        11334, -- Elixir of Greater Agility
        11348, -- Elixir of Superior Defense
        11349, -- Elixir of Greater Defense
        11371, -- Gift of Arthas
        11390, -- Arcane Elixir
        11396, -- Elixir of Greater Intellect
        11405, -- Elixir of Giants
        11474, -- Elixir of Shadow Power
        17535, -- Elixir of the Sages
        17537, -- Elixir of Brute Force
        17538, -- Elixir of the Mongoose
        17539, -- Greater Arcane Elixir
        21920, -- Elixir of Frost Power
        24361, -- Major Troll's Blood Potion
        24363, -- Mageblood Potion
        26276, -- Elixir of Greater Firepower
        17038, -- Winterfall Firewater
        10667, -- R.O.I.D.S.
        10668, -- Lung Juice Cocktail
        10669, -- Ground Scorpok Assay
        10692, -- Cerebral Cortex Compound
        10693, -- Gizzard Gum
    },
    look = { item = 13452, spell = 17538 },
}

local FLASKS = {
    ids = {
        17624, -- Flask of Petrification
        17626, -- Flask of the Titans
        17627, -- Flask of Distilled Wisdom
        17628, -- Flask of Supreme Power
        17629, -- Flask of Chromatic Resistance
    },
    look = { item = 13510, spell = 17626 },
}

-- The six scrolls, each in four strengths, weakest first. Plain names
-- again, so by ID.
local SCROLL_IDS = {
    { 8115, 8116, 8117, 12174 }, -- Agility
    { 8118, 8119, 8120, 12179 }, -- Strength
    { 8099, 8100, 8101, 12178 }, -- Stamina
    { 8096, 8097, 8098, 12176 }, -- Intellect
    { 8112, 8113, 8114, 12177 }, -- Spirit
    { 8091, 8094, 8095, 12175 }, -- Protection
}

local SCROLLS = {
    ids = {},
    look = { item = 3012, spell = 8115, file = "Interface\\Icons\\INV_Scroll_04" },
}
for _, strengths in ipairs(SCROLL_IDS) do
    for _, id in ipairs(strengths) do
        table.insert(SCROLLS.ids, id)
    end
end

-- Buffs another player puts on you. The class ones are found by name, so
-- the first rank's ID finds every rank. A few from the world are added by
-- ID.
local FROM_OTHERS = {
    named = {
        1243, -- Power Word: Fortitude
        21562, -- Prayer of Fortitude
        1126, -- Mark of the Wild
        21849, -- Gift of the Wild
        1459, -- Arcane Intellect
        23028, -- Arcane Brilliance
        14752, -- Divine Spirit
        27681, -- Prayer of Spirit
        976, -- Shadow Protection
        467, -- Thorns
        19740, -- Blessing of Might
        19742, -- Blessing of Wisdom
        20217, -- Blessing of Kings
        1038, -- Blessing of Salvation
        19977, -- Blessing of Light
        20911, -- Blessing of Sanctuary
        25782, -- Greater Blessing of Might
        25894, -- Greater Blessing of Wisdom
        25898, -- Greater Blessing of Kings
        25895, -- Greater Blessing of Salvation
        25890, -- Greater Blessing of Light
        25899, -- Greater Blessing of Sanctuary
    },
    ids = {
        22888, -- Rallying Cry of the Dragonslayer
        16609, -- Warchief's Blessing
        24425, -- Spirit of Zandalar
        15366, -- Songflower Serenade
        22817, -- Fengus' Ferocity
        22818, -- Mol'dar's Moxie
        22820, -- Slip'kik's Savvy
    },
    look = { spell = 1243 },
}

-- The buffs worth asking another player for, one line each in the "From
-- others" tooltip, lit or not. Each is satisfied by any of its spells: the
-- one-target buff or its group version, and for a paladin any blessing,
-- since a player only gets one from each paladin. Found by name like the
-- list above.
local MAJOR_BUFFS = {
    {
        english = "Power Word: Fortitude",
        named = { 1243, 21562 }, -- and Prayer of Fortitude
        look = { spell = 1243 },
    },
    {
        english = "Mark of the Wild",
        named = { 1126, 21849 }, -- and Gift of the Wild
        look = { spell = 1126 },
    },
    {
        english = "Arcane Intellect",
        named = { 1459, 23028 }, -- and Arcane Brilliance
        look = { spell = 1459 },
    },
    {
        english = "Divine Spirit",
        named = { 14752, 27681 }, -- and Prayer of Spirit
        look = { spell = 14752 },
    },
    {
        english = "Shadow Protection",
        named = { 976 },
        look = { spell = 976 },
    },
    {
        english = "A Blessing",
        label = "A paladin's Blessing",
        named = {
            19740, -- Might
            19742, -- Wisdom
            20217, -- Kings
            1038, -- Salvation
            19977, -- Light
            20911, -- Sanctuary
            25782, -- and the Greater ones
            25894,
            25898,
            25895,
            25890,
            25899,
        },
        look = { spell = 20217 },
    },
}

-- The class's own long-lasting buffs, by class as the game names classes
-- in English whatever the language. Only buffs that last ten minutes or
-- more and that belong up for every fight are here: a shout or a seal
-- that's cast in the fight itself isn't. Each is:
--
--   ids      the abilities that give it, first rank only: a character
--            keeps every rank they learn, so the first is known whenever
--            any is. Any one of them up will do
--   also     buffs that count as well, such as the group version
--   missing  what the warning says when none is up; otherwise it's the
--            ability's name and "isn't up"
--
-- A buff is only asked for once the player has learned one of its `ids`.
local CLASS_BUFFS = {
    MAGE = {
        -- Frost Armor, and in time Ice Armor or Mage Armor in its place.
        { ids = { 168, 7302, 6117 }, english = "Frost Armor", missing = "No armour up" },
        { ids = { 1459 }, also = { 23028 }, english = "Arcane Intellect" },
    },

    WARLOCK = {
        -- Demon Skin, then Demon Armor.
        { ids = { 687, 706 }, english = "Demon Skin", missing = "No armour up" },
    },

    PRIEST = {
        { ids = { 588 }, english = "Inner Fire" },
        { ids = { 1243 }, also = { 21562 }, english = "Power Word: Fortitude" },
    },

    DRUID = {
        -- Thorns is left out: it often isn't wanted, and the warning would
        -- nag. So is Omen of Clarity, which on Forever is a passive with
        -- nothing to keep up. What matters is when it procs, and that's
        -- the alerts' business (see Combat\Procs.lua).
        { ids = { 1126 }, also = { 21849 }, english = "Mark of the Wild" },
    },

    PALADIN = {
        -- Any of the auras: Devotion, Retribution, Concentration, the
        -- three resistances and Sanctity.
        {
            ids = { 465, 7294, 19746, 19876, 19888, 19891, 20218 },
            english = "Devotion Aura",
            missing = "No aura up",
        },
    },

    HUNTER = {
        -- Any of the aspects: the Monkey, the Hawk, the Cheetah, the Pack,
        -- the Beast and the Wild.
        {
            ids = { 13163, 13165, 5118, 13159, 13161, 20043 },
            english = "Aspect of the Hawk",
            missing = "No aspect up",
        },
    },

    -- A warrior's shouts last two minutes and a rogue has nothing to keep
    -- up but poisons, which are below. A shaman's Lightning Shield loses
    -- its charges in every fight, so asking for it would nag.
}

-- What a rogue or a shaman puts on their weapon. `ids` are what shows the
-- player can: the Poisons skill, or any of the four imbues. A rogue
-- poisons both hands.
local COATINGS = {
    ROGUE = { ids = { 2842 }, english = "Poisons", word = "poison", bothHands = true },
    SHAMAN = { ids = { 8017, 8024, 8033, 8232 }, english = "Rockbiter Weapon", word = "imbue" },
}

-- Call Pet: a hunter who has it has a pet to call.
local CALL_PET = { 883 }

-- State -------------------------------------------------------------------------

local className

-- The class's own buffs the player has learned, each with its name and
-- picture; the coating their class puts on a weapon, if they've learned
-- it; and whether they have a pet to call.
local needs = {}
local coating
local hasPet = false

-- The player's buffs as last read outside a fight, by spell ID and by
-- name. Each is { name, icon, expires, own }.
local auras = { byId = {}, byName = {} }

-- What's in hand and worn: main and off, each { icon, weapon, fishing }
-- or nil; mainCoat and offCoat, each { expires, charges }, false for none
-- or nil when the game won't say; worn, the worst-worn item or nil; ammo,
-- { count, icon } or nil.
local gear = {}

-- "away", "dead", "unhappy", or nil when the pet is fine or there isn't one.
local pet

-- { amount, resting }, or nil when rested experience means nothing (at the
-- level cap, say).
local rested

-- away: dead or on a flight, when there's nothing to be done; resting:
-- in an inn or a city, where buffs are let lapse.
local standing = {}

local fighting = false
local rebuildAfterFight = false

-- What the screens are given, worked out after each look, and the words
-- of the last lot, to tell whether anything changed.
local problems = {}
local slots = {}
local lastSaid = ""

-- Set once the game has refused a question, by what was being read. That
-- part isn't read again this session.
Readiness.complaints = {}

--- Asks something that may be refused, without letting a refusal stop
--- anything else.
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

--- The first thing an answer gives, unless it's hidden.
local function Read(method, ...)
    local value = Ask(method, ...)
    if IsSecret(value) then
        return nil
    end
    return value
end

--- Whether there's anything to look for: either screen switched on, and the
--- character known.
local function Enabled()
    return ns.character ~= nil and (ns.settings.readyAlert or ns.settings.widgetBuffs)
end

local function Knows(id)
    if Read(C_SpellBook.IsSpellKnownOrInSpellBook, id) or Read(C_SpellBook.IsSpellKnown, id) then
        return true
    end

    -- By name as well, which finds the ID of the rank the player has.
    local name = Read(C_Spell.GetSpellName, id)
    local own = name and Read(C_Spell.GetSpellIDForSpellIdentifier, name)
    return own ~= nil and own ~= id and Read(C_SpellBook.IsSpellKnown, own) == true
end

--- The first of the IDs the player knows.
local function FirstKnown(ids)
    for _, id in ipairs(ids or {}) do
        if Knows(id) then
            return id
        end
    end
    return nil
end

--- A picture for something that isn't on: the item's, which is the bottle
--- or scroll the player knows, else the spell's, else a file.
local function Picture(look)
    if not look then
        return nil
    end
    local icon
    if look.item then
        local _, _, _, _, picture = Ask(C_Item.GetItemInfoInstant, look.item)
        icon = not IsSecret(picture) and picture or nil
    end
    icon = icon or (look.spell and Read(C_Spell.GetSpellTexture, look.spell))
    return icon or look.file
end

-- Working out what to look for ----------------------------------------------------

--- Fills in the names a kind of buff is found by.
local function Prepare(kind)
    kind.names = {}
    for _, list in ipairs({ kind.named or {}, kind.also or {} }) do
        for _, id in ipairs(list) do
            local name = Read(C_Spell.GetSpellName, id)
            if type(name) == "string" and name ~= "" then
                kind.names[name] = true
            end
        end
    end
    if kind.english and not next(kind.names) then
        kind.names[kind.english] = true
    end
    kind.icon = Picture(kind.look)
end

--- Works out, for the player's class, which buffs to ask for. Learning an
--- ability or a talent can change it, so it's done again when that
--- happens.
local function Rebuild()
    local _, class = UnitClass("player")
    className = class

    for _, kind in ipairs({ FOOD, ELIXIRS, FLASKS, SCROLLS, FROM_OTHERS }) do
        Prepare(kind)
    end
    for _, kind in ipairs(MAJOR_BUFFS) do
        Prepare(kind)
    end

    needs = {}
    for _, buff in ipairs(CLASS_BUFFS[class] or {}) do
        local known = FirstKnown(buff.ids)
        if known then
            -- Every rank of each ability is found by its name.
            local need = { ids = buff.ids, named = buff.ids, also = buff.also }
            need.english = buff.english
            Prepare(need)
            need.name = Read(C_Spell.GetSpellName, known) or buff.english
            need.icon = Read(C_Spell.GetSpellTexture, known)
            need.missing = buff.missing or (need.name .. " isn't up")

            -- One of several, such as "No armour up", is said that way in
            -- the tooltip too, rather than by the first one's name.
            need.grouped = buff.missing ~= nil
            table.insert(needs, need)
        end
    end

    local coat = COATINGS[class]
    coating = coat and FirstKnown(coat.ids) and coat or nil
    hasPet = class == "HUNTER" and FirstKnown(CALL_PET) ~= nil
end

-- Reading ----------------------------------------------------------------------------

--- The player's buffs. Only ever called outside a fight.
local function ReadAuras()
    local byId, byName = {}, {}
    for index = 1, MOST_AURAS do
        local aura = Ask(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")

        -- Half a list would report buffs that are up as missing. Better
        -- to keep the last whole one.
        if IsSecret(aura) then
            return
        end
        if type(aura) ~= "table" then
            break
        end

        local id, name = aura.spellId, aura.name
        if not IsSecret(id) and not IsSecret(name) then
            local expires = aura.expirationTime
            local found = {
                name = name,
                icon = not IsSecret(aura.icon) and aura.icon or nil,
                expires = not IsSecret(expires) and expires or nil,
                own = not IsSecret(aura.isFromPlayerOrPlayerPet) and aura.isFromPlayerOrPlayerPet,
            }
            if type(id) == "number" then
                byId[id] = found
            end
            if type(name) == "string" then
                byName[name] = found
            end
        end
    end
    auras = { byId = byId, byName = byName }
end

--- What's in one hand, or nil when it's empty.
local function ReadHand(slot)
    local item = Read(GetInventoryItemID, "player", slot)
    if type(item) ~= "number" then
        return nil
    end

    local _, _, _, _, icon, itemClass, subclass = Ask(C_Item.GetItemInfoInstant, item)
    if IsSecret(icon) then
        icon = nil
    end
    local weapon = not IsSecret(itemClass) and itemClass == Enum.ItemClass.Weapon
    if IsSecret(subclass) then
        subclass = nil
    end
    return {
        icon = Read(GetInventoryItemTexture, "player", slot) or icon,
        weapon = weapon,
        fishing = weapon and subclass == Enum.ItemWeaponSubclass.Fishingpole,
    }
end

--- When a weapon's coating wears off, from what the game says is left.
local function Timing(milliseconds, charges, timed)
    local coat = {}
    if
        timed
        and not IsSecret(milliseconds)
        and type(milliseconds) == "number"
        and milliseconds > 0
    then
        coat.expires = GetTime() + milliseconds / 1000
    end
    if not IsSecret(charges) and type(charges) == "number" and charges > 0 then
        coat.charges = charges
    end
    return coat
end

--- The stone, oil, poison or imbue on a weapon: its timing, false for
--- none, or nil when the game won't say.
local function ReadCoating(slot, weaponSlot)
    local paperDoll = C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo
    if paperDoll then
        local ok, info = pcall(paperDoll, slot)
        if not ok or IsSecret(info) then
            return nil
        end
        if type(info) ~= "table" then
            return false
        end
        local timed = info.hasExpirationTime
        return Timing(info.remainingTimeMs, info.chargesRemaining, IsSecret(timed) or timed)
    end

    -- The way the game's own buff frame asks, for a client without the
    -- first.
    local byItem = C_Item.GetWeaponEnchantInfo
    if byItem and weaponSlot then
        local ok, enchants = pcall(byItem, weaponSlot)
        if not ok or IsSecret(enchants) or type(enchants) ~= "table" then
            return nil
        end
        for _, enchant in pairs(enchants) do
            local has = type(enchant) == "table" and enchant.hasEnchant
            if not IsSecret(has) and has == true then
                return Timing(enchant.timeLeft, enchant.charges, true)
            end
        end
        return false
    end
    return nil
end

--- The worst-worn item, if anything is at or under WORN_OUT.
local function ReadWorn()
    local worst
    for slot = FIRST_WORN, LAST_WORN do
        local current, most = Ask(GetInventoryItemDurability, slot)
        if
            not IsSecret(current)
            and not IsSecret(most)
            and type(current) == "number"
            and type(most) == "number"
            and most > 0
        then
            local share = current / most
            if share <= WORN_OUT and (not worst or share < worst.share) then
                worst = { slot = slot, share = share }
            end
        end
    end
    if not worst then
        return nil
    end

    local link = Read(GetInventoryItemLink, "player", worst.slot)
    worst.name = type(link) == "string" and link:match("%[(.-)%]") or nil
    worst.icon = Read(GetInventoryItemTexture, "player", worst.slot)
    return worst
end

--- A hunter's arrows or bullets, or nil when there's nothing to say: not a
--- hunter, a weapon that needs none, or a client that won't tell.
local function ReadAmmo()
    if className ~= "HUNTER" or Read(UnitUsesAmmo, "player") ~= true then
        return nil
    end

    -- The game's own character window hides the ammunition slot when the
    -- game says none is needed, and so does this.
    local paperDoll = C_PaperDollInfo
    if Read(paperDoll and paperDoll.AmmoNeeded) == false then
        return nil
    end

    local item = Ask(GetInventoryItemID, "player", AMMO)
    if IsSecret(item) then
        return nil
    end
    local icon = Read(GetInventoryItemTexture, "player", RANGED)
    if not item then
        return { count = 0, icon = icon }
    end

    -- For the ammunition slot the game counts every one of that kind the
    -- player carries, as its own character window does.
    local count = Read(GetInventoryItemCount, "player", AMMO)
    if type(count) ~= "number" then
        return nil
    end
    return { count = count, icon = Read(GetInventoryItemTexture, "player", AMMO) or icon }
end

local function ReadGear()
    local weaponSlots = Enum.WeaponSlot or {}
    gear = {
        main = ReadHand(MAIN_HAND),
        off = ReadHand(OFF_HAND),
        mainCoat = ReadCoating(MAIN_HAND, weaponSlots.MainHand),
        offCoat = ReadCoating(OFF_HAND, weaponSlots.OffHand),
        worn = ReadWorn(),
        ammo = ReadAmmo(),
    }
end

local function ReadPet()
    pet = nil
    if not hasPet then
        return
    end

    local out = Ask(UnitExists, "pet")
    if IsSecret(out) then
        return
    end
    if not out then
        pet = "away"
        return
    end
    if Read(UnitIsDead, "pet") == true then
        pet = "dead"
        return
    end

    -- Only a hunter's own pet has a mood. One the hunter has charmed for a
    -- while hasn't.
    local _, hunterPet = Ask(HasPetUI)
    if IsSecret(hunterPet) or not hunterPet then
        return
    end
    local happiness = Read(C_PetInfo and C_PetInfo.GetPetHappiness)
    if happiness == UNHAPPY then
        pet = "unhappy"
    end
end

local function ReadRested()
    rested = nil

    -- The game's own experience bar knows best when there's no more to
    -- earn: it allows for the highest level this world goes to, which
    -- can be lower than the highest there is.
    local ok, showsBar = pcall(function()
        return GameRulesUtil.CanShowExperienceBar()
    end)
    if ok and showsBar == false then
        return
    end

    local level, cap = Read(UnitLevel, "player"), Read(GetMaxPlayerLevel)
    if type(level) == "number" and type(cap) == "number" and level >= cap then
        return
    end
    if Read(IsXPUserDisabled) == true then
        return
    end

    local amount = Read(GetXPExhaustion)
    rested = {
        amount = type(amount) == "number" and amount or 0,
        resting = Read(IsResting) == true,
    }
end

local function ReadStanding()
    standing = {
        away = Read(UnitIsDeadOrGhost, "player") == true or Read(UnitOnTaxi, "player") == true,
        resting = Read(IsResting) == true,
    }
end

--- Reads one part, and gives it up for the session the first time the
--- game refuses it.
local function Attempt(what, method)
    if Readiness.complaints[what] then
        return
    end
    local ok, problem = pcall(method)
    if not ok then
        Readiness.complaints[what] = tostring(problem)
    end
end

-- Finding buffs ------------------------------------------------------------------------

--- Every buff of a kind the player has on, as last read.
local function FindAll(kind)
    local found, seen = {}, {}
    local function Keep(aura)
        if aura and not seen[aura] then
            seen[aura] = true
            table.insert(found, aura)
        end
    end

    for _, id in ipairs(kind.ids or {}) do
        Keep(auras.byId[id])
    end
    for _, id in ipairs(kind.also or {}) do
        Keep(auras.byId[id])
    end
    for name in pairs(kind.names or {}) do
        Keep(auras.byName[name])
    end
    return found
end

--- Buffs from others: the ones on the list that the player didn't cast.
local function FindFromOthers()
    local found = {}
    for _, aura in ipairs(FindAll(FROM_OTHERS)) do
        if not aura.own then
            table.insert(found, aura)
        end
    end
    return found
end

local function HostileTarget()
    return Read(UnitExists, "target") == true
        and Read(UnitCanAttack, "player", "target") == true
        and Read(UnitIsDead, "target") ~= true
end

-- Working out what to say ------------------------------------------------------------

--- "No poison on your off hand", or nil when the weapon is seen to.
local function CoatingProblem()
    local main, off = gear.main, gear.off
    if not coating or not main or not main.weapon or main.fishing then
        return nil
    end

    -- A coating the game won't say about is taken to be there.
    local bareMain = gear.mainCoat == false
    local bareOff = coating.bothHands and off and off.weapon and gear.offCoat == false
    local where
    if bareMain and bareOff then
        where = "weapons"
    elseif bareMain then
        where = (coating.bothHands and off and off.weapon) and "main hand" or "weapon"
    elseif bareOff then
        where = "off hand"
    else
        return nil
    end
    return ("No %s on your %s"):format(coating.word, where)
end

local PET_WORDS = {
    away = "Your pet isn't out",
    dead = "Your pet is dead",
    unhappy = "Your pet is unhappy",
}

local function ComposeProblems()
    local list = {}
    local function Add(key, text, icon, urgent)
        table.insert(list, { key = key, text = text, icon = icon, urgent = urgent, sound = urgent })
    end

    -- Nothing can be put right while dead or on a flight.
    if standing.away and not fighting then
        return list
    end

    -- A fishing pole is the one thing worth raising a voice about, and
    -- only once a fight has begun with it. Before then it's mentioned
    -- only when there's an enemy targeted.
    local main = gear.main
    if main and main.fishing and (fighting or HostileTarget()) then
        Add("fishing", "Fishing pole still in hand", main.icon, fighting)
    end

    local worn = gear.worn
    if worn then
        local what = worn.name or "An item"
        Add(
            "worn",
            (worn.share <= 0 and "Broken: %s" or "Nearly broken: %s"):format(what),
            worn.icon
        )
    end

    local ammo = gear.ammo
    if ammo and ammo.count < LOW_AMMO then
        local text = ammo.count == 0 and "Out of ammunition"
            or ("Low on ammunition: %d left"):format(ammo.count)
        Add("ammo", text, ammo.icon)
    end

    -- In a town or an inn, buffs are let lapse and the pet sent off, and
    -- that's no cause for a warning. A fight there still brings them up.
    if standing.resting and not fighting then
        return list
    end

    if pet then
        Add("pet", PET_WORDS[pet], Read(C_Spell.GetSpellTexture, CALL_PET[1]))
    end

    local bare = CoatingProblem()
    if bare then
        Add("coating", bare, main and main.icon)
    end

    for index, need in ipairs(needs) do
        if not FindAll(need)[1] then
            Add("class" .. index, need.missing, need.icon)
        end
    end
    return list
end

local function ComposeSlots()
    local list = {}
    local function Add(slot)
        table.insert(list, slot)
    end

    -- Nothing left to gain from rest at the level cap.
    if rested then
        Add({ key = "rested", label = "Rested", icon = RESTED_ICON, lit = rested.amount > 0 })
    end

    local function ByKind(key, label, kind, found)
        found = found or FindAll(kind)
        local first = found[1]
        Add({
            key = key,
            label = label,
            icon = first and first.icon or kind.icon,
            lit = first ~= nil,
            found = found,
        })
    end

    ByKind("food", "Food", FOOD)
    ByKind("elixir", "Elixir", ELIXIRS)

    local level = Read(UnitLevel, "player")
    if type(level) == "number" and level >= FLASK_LEVEL then
        ByKind("flask", "Flask", FLASKS)
    end
    ByKind("scroll", "Scroll", SCROLLS)

    -- Any class can put a stone or an oil on a weapon, so this is there
    -- whenever one is in hand.
    local main = gear.main
    if main and main.weapon then
        local lit = not main.fishing and type(gear.mainCoat) == "table"
        Add({ key = "weapon", label = "Weapon", icon = main.icon, lit = lit })
    end

    if needs[1] then
        local up, icon = true, nil
        for _, need in ipairs(needs) do
            local first = FindAll(need)[1]
            up = up and first ~= nil
            icon = icon or (first and first.icon)
        end
        Add({ key = "class", label = "Class buffs", icon = icon or needs[1].icon, lit = up })
    end

    ByKind("others", "From others", FROM_OTHERS, FindFromOthers())
    return list
end

--- The words of everything the screens show, to tell whether any changed.
local function Said()
    local parts = {}
    for _, problem in ipairs(problems) do
        table.insert(
            parts,
            ("%s%s%s"):format(problem.key, problem.urgent and "!" or "", problem.text)
        )
        table.insert(parts, tostring(problem.icon))
    end
    for _, slot in ipairs(slots) do
        table.insert(
            parts,
            ("%s%s%s"):format(slot.key, slot.lit and "+" or "-", tostring(slot.icon))
        )
    end
    return table.concat(parts, "|")
end

local function Compose()
    if Enabled() then
        problems = ComposeProblems()
        slots = ComposeSlots()
    else
        problems, slots = {}, {}
    end

    local said = Said()
    if said ~= lastSaid then
        lastSaid = said
        ns.Publish("READINESS_CHANGED")
    end
end

-- Looking --------------------------------------------------------------------------------

--- Reads everything that can be read now, and says so if anything changed.
local function Look()
    if Enabled() then
        -- Buffs can't be read in a fight, and nothing about rest changes in
        -- one. Those keep what was read before it.
        if not fighting then
            Attempt("buffs", ReadAuras)
            Attempt("rest", ReadRested)
            Attempt("standing", ReadStanding)
        end
        Attempt("gear", ReadGear)
        Attempt("pet", ReadPet)
    end
    Compose()
end

local lookPending = false

--- Asks for a look in a moment rather than straight away: some news comes
--- in bursts.
local function LookSoon()
    if lookPending or not Enabled() then
        return
    end
    lookPending = true
    C_Timer.After(LOOK_SOON, function()
        lookPending = false
        Look()
    end)
end

--- The same, but not during a fight, for news that can wait for its end.
local function LookSoonIfCalm()
    if not fighting then
        LookSoon()
    end
end

-- What the screens are told --------------------------------------------------------------

--- What's amiss, most pressing first.
---@return table  list of { key, text, icon, urgent, sound }, where sound is
---               set for the one line that asks for the alert sound
function Readiness.Problems()
    return problems
end

--- The buff icons for the bottom of the fight panel, in order.
---@return table  list of { key, label, icon, lit }
function Readiness.Slots()
    return slots
end

--- "24 minutes left", or nil for a buff that doesn't run out.
local function TimeLeft(expires)
    if type(expires) ~= "number" or expires <= 0 then
        return nil
    end

    local left = expires - GetTime()
    if left <= 0 then
        return "running out"
    elseif left < 60 then
        return "under a minute left"
    elseif left >= 90 * 60 then
        return ("about %s left"):format(ns.Count(left / 3600, "hour"))
    end
    return ns.Count(math.floor(left / 60), "minute") .. " left"
end

--- "Elixir of the Mongoose: 40 minutes left".
local function BuffLine(name, expires)
    local left = TimeLeft(expires)
    return left and ("%s: %s"):format(name, left) or name
end

-- A small icon at the start of a tooltip line, trimmed of its border as
-- the game trims spell icons, and greyed out for a buff that isn't up.
local LINE_ICON = "|T%s:16:16:0:0:64:64:5:59:5:59|t "
local GREY_LINE_ICON = "|T%s:16:16:0:0:64:64:5:59:5:59:110:110:110|t "

local function WithIcon(icon, text, missing)
    if not icon then
        return text
    end
    return (missing and GREY_LINE_ICON or LINE_ICON):format(tostring(icon)) .. text
end

--- One line per buff worth asking another player for, lit or greyed out,
--- then any of the world's buffs the player has.
local function MajorLines(Add)
    local counted = {}
    for _, kind in ipairs(MAJOR_BUFFS) do
        local aura = FindAll(kind)[1]
        if aura then
            counted[aura] = true
            local line = BuffLine(aura.name, aura.expires)
            if aura.own then
                line = line .. " (your own)"
            end
            Add(WithIcon(aura.icon or kind.icon, line))
        else
            -- Named by its one-target version, in the player's language.
            local first = Read(C_Spell.GetSpellName, kind.named[1])
            local name = kind.label or (type(first) == "string" and first) or kind.english
            Add(WithIcon(kind.icon, name .. ": not up", true), true)
        end
    end

    for _, aura in ipairs(FindFromOthers()) do
        if not counted[aura] then
            Add(WithIcon(aura.icon, BuffLine(aura.name, aura.expires)))
        end
    end
end

-- What lights each icon, for its tooltip when it's dim.
local HINTS = {
    rested = "Lights while you have rested experience. It builds up while you're in an inn "
        .. "or a city, and while you're logged out there.",
    food = "Lights while you're Well Fed from eating.",
    elixir = "Lights for the common elixirs, such as the Mongoose, Giants or Greater Arcane "
        .. "Elixir. One Temper doesn't know won't light it.",
    flask = "Lights for any of the five flasks.",
    scroll = "Lights for a scroll of Agility, Strength, Stamina, Intellect, Spirit or "
        .. "Protection.",
    weapon = "Lights while a sharpening stone, an oil, a poison or an imbue is on your weapon.",
    class = "Lights while all of these are up.",
    others = "Lights for buffs other players give: Fortitude, Mark of the Wild, Arcane "
        .. "Intellect, a Blessing and the like.",
}

local function WeaponLines(add)
    if gear.main and gear.main.fishing then
        add("A fishing pole is in your hand.", true)
        return
    end

    for _, hand in ipairs({ { "Main hand", gear.mainCoat }, { "Off hand", gear.offCoat } }) do
        local coat = hand[2]
        if type(coat) == "table" then
            local line = BuffLine(hand[1], coat.expires)
            if coat.charges then
                line = ("%s, %s"):format(line, ns.Count(coat.charges, "charge"))
            end
            add(line)
        end
    end
end

--- What an icon's tooltip says.
---@param key string  a slot's key
---@return string|nil title
---@return table lines  list of { text, hint }, where hint is set for the
---                     greyer lines that explain rather than report
function Readiness.Tooltip(key)
    local slot
    for _, candidate in ipairs(slots) do
        if candidate.key == key then
            slot = candidate
        end
    end
    if not slot then
        return nil, {}
    end

    local lines = {}
    local function Add(text, hint)
        table.insert(lines, { text = text, hint = hint })
    end

    if key == "rested" then
        if rested and rested.amount > 0 then
            Add(("About %s rested experience left."):format(ns.Number(rested.amount)))
        end
        if rested and rested.resting then
            Add("You're resting now, so more is building up.")
        end
    elseif key == "weapon" then
        WeaponLines(Add)
    elseif key == "others" then
        MajorLines(Add)
    elseif key == "class" then
        for _, need in ipairs(needs) do
            local first = FindAll(need)[1]
            if first then
                Add(BuffLine(first.name, first.expires))
            else
                Add(need.grouped and need.missing or (need.name .. ": not up"), true)
            end
        end
    else
        for _, aura in ipairs(slot.found or {}) do
            Add(BuffLine(aura.name, aura.expires))
        end
    end

    if (not slot.lit or key == "class" or key == "elixir") and key ~= "others" then
        Add(HINTS[key], true)
    end
    if fighting then
        Add("As it was when the fight began.", true)
    end
    return slot.label, lines
end

-- Events -----------------------------------------------------------------------------------

ns.Subscribe("DATABASE_READY", function()
    -- A reload in the middle of a fight brings no word that one began.
    fighting = InCombatLockdown()
    Rebuild()
    Look()

    -- For what the game doesn't announce.
    C_Timer.NewTicker(LOOK_EVERY, function()
        if not fighting and Enabled() then
            Look()
        end
    end)
end)

ns.Subscribe("SETTINGS_CHANGED", function()
    if ns.character then
        Look()
    end
end)

-- Learning an ability or a talent changes what's asked for. It can wait
-- for the end of a fight.
ns.OnEvent("SPELLS_CHANGED", function()
    if not ns.character then
        return
    end
    if fighting then
        rebuildAfterFight = true
        return
    end
    Rebuild()
    LookSoon()
end)

ns.OnEvent("PLAYER_REGEN_DISABLED", function()
    fighting = true
    -- What was missing just before is said again, and a fishing pole now
    -- calls for the alert.
    Attempt("gear", ReadGear)
    Compose()
end)

ns.OnEvent("PLAYER_REGEN_ENABLED", function()
    fighting = false
    if rebuildAfterFight then
        rebuildAfterFight = false
        Rebuild()
    end
    LookSoon()
end)

-- A weapon can be swapped in a fight, and the pet can come or go.
ns.OnEvent("PLAYER_EQUIPMENT_CHANGED", LookSoon)
ns.OnEvent("UNIT_PET", function(unit)
    if not IsSecret(unit) and unit == "player" then
        LookSoon()
    end
end)
ns.OnEvent("UNIT_HAPPINESS", function(unit)
    if not IsSecret(unit) and unit == "pet" then
        LookSoon()
    end
end)

-- Everything else waits for the fight to end.
for _, event in ipairs({
    "PLAYER_TARGET_CHANGED",
    "UPDATE_INVENTORY_DURABILITY",
    "PLAYER_LEVEL_UP",
    "PLAYER_XP_UPDATE",
    "UPDATE_EXHAUSTION",
    "PLAYER_UPDATE_RESTING",
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
    "PLAYER_CONTROL_GAINED",
    "PLAYER_CONTROL_LOST",
    "PLAYER_ENTERING_WORLD",
}) do
    ns.OnEvent(event, LookSoonIfCalm)
end

-- Putting a stone or a poison on a weapon, and arrows being used up.
ns.OnEvent("UNIT_INVENTORY_CHANGED", function(unit)
    if not IsSecret(unit) and unit == "player" then
        LookSoonIfCalm()
    end
end)

-- Our own frame for the player's buffs, registered for the player alone,
-- as Combat\Procs.lua does it: the shared one would hear about every
-- nameplate's as well.
local auraWatch = CreateFrame("Frame")
pcall(auraWatch.RegisterUnitEvent, auraWatch, "UNIT_AURA", "player")
auraWatch:SetScript("OnEvent", LookSoonIfCalm)
