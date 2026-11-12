local _, ns = ...

-- What the character is wearing.
--
-- Every fight keeps a note of this, so that two sets of fights can be
-- told apart by what changed between them: "Swapped Worn Shortbow for
-- Hornwood Recurve Bow". Gear changes far less often than fights happen,
-- so each different set is stored once and fights point at it by number.

local Gear = {}
ns.Gear = Gear

-- Inventory slots in the order a person would read them off, with the
-- game's own numbering. The ranged slot only exists on clients with
-- classic gear; asking an empty or absent slot for its item is harmless.
local SLOTS = {
    { 16, "Main hand" },
    { 17, "Off hand" },
    { 18, "Ranged" },
    { 1, "Head" },
    { 2, "Neck" },
    { 3, "Shoulders" },
    { 15, "Back" },
    { 5, "Chest" },
    { 9, "Wrists" },
    { 10, "Hands" },
    { 6, "Waist" },
    { 7, "Legs" },
    { 8, "Feet" },
    { 11, "Ring" },
    { 12, "Second ring" },
    { 13, "Trinket" },
    { 14, "Second trinket" },
}

--- What's in each slot right now, as item links by slot number.
---@return table
function Gear.Snapshot()
    local worn = {}
    for _, slot in ipairs(SLOTS) do
        worn[slot[1]] = GetInventoryItemLink("player", slot[1])
    end
    return worn
end

--- What makes an item the item it is, for telling whether a slot changed.
-- A link also carries the wearer's level and other things that change on
-- their own, so two links to the same sword needn't match. The item's
-- number and its enchantment are the first two fields, and are enough.
local function Identity(link)
    if not link then
        return nil
    end
    return link:match("item:(%d*:%d*)") or link
end

--- True if two snapshots hold the same items.
local function SameGear(a, b)
    for _, slot in ipairs(SLOTS) do
        if Identity(a[slot[1]]) ~= Identity(b[slot[1]]) then
            return false
        end
    end
    return true
end

--- Files a snapshot with a character's gear sets, reusing the latest one
--- when nothing has changed.
---@return number  the set's place in character.gearSets
function Gear.Keep(character, snapshot)
    local sets = character.gearSets
    local latest = sets[#sets]
    if latest and SameGear(latest, snapshot) then
        return #sets
    end

    table.insert(sets, snapshot)
    return #sets
end

--- The gear set the character is wearing right now, by number.
function Gear.Current()
    return Gear.Keep(ns.character, Gear.Snapshot())
end

--- A gear set by its number, or nil.
function Gear.Set(number)
    return number and ns.character.gearSets[number]
end

--- What differs between two snapshots.
---@param before table
---@param after table
---@return table  list of { slot = "Main hand", before = link, after = link },
---               either link nil for an empty slot
function Gear.Diff(before, after)
    local changes = {}
    if type(before) ~= "table" or type(after) ~= "table" then
        return changes
    end

    for _, slot in ipairs(SLOTS) do
        local was, is = before[slot[1]], after[slot[1]]
        if Identity(was) ~= Identity(is) then
            table.insert(changes, { slot = slot[2], before = was, after = is })
        end
    end
    return changes
end
