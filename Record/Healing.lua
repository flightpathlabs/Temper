local _, ns = ...

-- Adds up the other side of a set of fights: what the player healed, what
-- they took, and what they did about it, including about how much never
-- reached them (worked out fight by fight in Mitigation.lua).
--
-- It's to healing and defence what Summary.lua is to damage. Like a
-- summary, nothing here is saved: it's worked out from the fights each
-- time it's wanted. The few sentences there are to say about it are here
-- too, since these figures are all they read. They follow the rules in
-- Findings.lua: one plain sentence each, and only when the figures clearly
-- support it.
--
-- Fights saved before Temper recorded any of this carry none of it. They
-- count as fights given but not as fights tracked, so a page can tell
-- "nothing was healed" from "nothing was written down".

local Healing = {}
ns.Healing = Healing

-- How many sentences at most.
local MOST = 3

-- Healing has to come to this much of the damage taken before the two are
-- worth setting side by side, and to this much before that's good news.
local HEALED_BACK_WORTH_MENTIONING = 0.1
local MUCH_HEALED_BACK = 0.5

-- How much of the damage taken the game has to mark as avoidable before
-- it's worth a sentence.
local MUCH_AVOIDABLE = 0.15

-- How much more healing one ability has to give for its cost than another
-- before it's worth suggesting the cost be spent there instead, and how
-- many times each has to have been used before what it gives counts.
local CLEARLY_BETTER_VALUE = 1.2
local FEWEST_USES = 3

-- A Defence skill has to be this far short of what the enemy calls for
-- before it's worth a sentence, as with a weapon skill (see Findings.lua).
-- Fifteen points is also where crushing blows start.
local SKILL_GAP_WORTH_MENTIONING = 15

-- Spells have to be this many of what hit the player, and this big a
-- share of it, before what they were made of is worth a sentence; and one
-- school has to be this big a share of them to be the one that mattered.
local ENOUGH_SPELLS = 6
local MUCH_MAGIC = 0.25
local MOSTLY_ONE_SCHOOL = 2 / 3

-- An enemy lands a critical hit on about one blow in twenty against a
-- player of its level. This many blows have to have landed before the
-- share of crits means anything, and the share has to be this high
-- before it's worth a sentence.
local ENOUGH_BLOWS = 20
local MANY_CRITS = 0.12

-- Physical damage has to be this big a share of the damage taken before
-- what armour did about it is worth a sentence.
local MOSTLY_PHYSICAL = 0.5

-- The ways in which an attack fails to land, as they're said in a list:
-- "dodges, parries and misses".
local TURNED_WORDS = {
    { "DODGE", "dodges" },
    { "PARRY", "parries" },
    { "MISS", "misses" },
}

-- Adding up -------------------------------------------------------------------

--- True if a fight carries any of the figures added up here.
local function IsTracked(fight)
    return fight.healing ~= nil
        or fight.absorbed ~= nil
        or fight.taken ~= nil
        or fight.interrupts ~= nil
        or fight.dispels ~= nil
        or fight.defence ~= nil
end

--- Adds one fight's healing, ability by ability.
---@param byKey table  the abilities met so far, so each gets one line
local function AddHealing(summary, byKey, healing)
    summary.healing = summary.healing + (healing.total or 0)

    for _, spell in ipairs(healing.spells or {}) do
        -- By spell and by whose it is, so a pet's heal and the player's
        -- own of the same name don't end up on one line.
        local key = (spell.pet and "pet" or "own") .. spell.id
        local ability = byKey[key]
        if not ability then
            ability = { id = spell.id, name = spell.name, pet = spell.pet, healing = 0 }
            byKey[key] = ability
            table.insert(summary.abilities, ability)
        end

        ability.healing = ability.healing + spell.amount

        -- Icon, rank and cost as they were in whichever fight is read last.
        ability.icon = spell.icon or ability.icon
        ability.rank = spell.rank or ability.rank
        if spell.cost then
            ability.cost, ability.power = spell.cost, spell.power
        end

        -- Healing per use is worked out over the fights where the casts
        -- were seen, in case some fight's weren't.
        if spell.casts then
            ability.casts = (ability.casts or 0) + spell.casts
            ability.castHealing = (ability.castHealing or 0) + spell.amount
        end
    end
end

--- Adds one fight's damage taken, enemy ability by enemy ability.
---@param byKey table  the enemy abilities met so far
local function AddTaken(summary, byKey, taken)
    summary.taken = summary.taken + (taken.total or 0)
    if taken.avoidable then
        summary.avoidable = (summary.avoidable or 0) + taken.avoidable
    end

    for _, source in ipairs(taken.sources or {}) do
        -- Two kinds of enemy can share an ability. Each keeps its own line.
        local key = source.id .. source.name .. (source.from or "")
        local blow = byKey[key]
        if not blow then
            blow = { id = source.id, name = source.name, from = source.from, amount = 0 }
            byKey[key] = blow
            table.insert(summary.hurtBy, blow)
        end

        blow.amount = blow.amount + source.amount
        blow.avoidable = blow.avoidable or source.avoidable
    end
end

--- Adds one fight's count of what landed on the player.
local function AddDefence(summary, defence)
    summary.heals = summary.heals + (defence.heals or 0)
    summary.healCrits = summary.healCrits + (defence.healCrits or 0)
    summary.struck = summary.struck + (defence.struck or 0)
    summary.avoided = summary.avoided + (defence.avoided or 0)
    for way, times in pairs(defence.avoidedBy or {}) do
        summary.avoidedBy[way] = (summary.avoidedBy[way] or 0) + times
    end

    -- Crits and crushing blows were only counted later on. Their share is
    -- only of the blows in the fights that counted them.
    if defence.crits then
        summary.crits = summary.crits + defence.crits
        summary.crushing = summary.crushing + (defence.crushing or 0)
        summary.critBlows = summary.critBlows + (defence.struck or 0)
    end

    -- The same goes for the spells that hit the player.
    if defence.magic then
        summary.magic = summary.magic + defence.magic
        summary.allHits = summary.allHits + defence.magic + (defence.struck or 0)
        summary.resisted = summary.resisted + (defence.resisted or 0)
        for school, times in pairs(defence.schools or {}) do
            summary.schools[school] = (summary.schools[school] or 0) + times
        end
    end
end

--- Adds about what one fight's armour, dodging and blocking stopped. A
--- fight from before this was worked out adds nothing.
local function AddStopped(summary, fight)
    local estimate = ns.Mitigation.Estimate(fight)
    if not estimate or not estimate.estimated then
        return
    end

    local stopped = summary.stopped
    if not stopped then
        stopped = {
            fights = 0,
            coming = 0,
            taken = 0,
            physical = 0,
            absorbed = 0,
            armour = 0,
            avoided = 0,
            blocked = 0,
            -- For the average share armour took off: each fight's share,
            -- weighed by the physical damage it was taken off.
            cutSum = 0,
            cutPhysical = 0,
            ways = {},
            blocks = 0,
        }
        summary.stopped = stopped
    end

    stopped.fights = stopped.fights + 1
    for _, field in ipairs({ "coming", "taken", "physical", "absorbed" }) do
        stopped[field] = stopped[field] + estimate[field]
    end

    local defence = fight.defence
    local by = defence.avoidedBy or {}

    if estimate.armour then
        stopped.armour = stopped.armour + estimate.armour
        stopped.cutPhysical = stopped.cutPhysical + estimate.physical
        stopped.cutSum = stopped.cutSum + estimate.armourCut * estimate.physical
    end
    if estimate.avoided then
        stopped.avoided = stopped.avoided + estimate.avoided
        for _, way in ipairs({ "DODGE", "PARRY", "MISS" }) do
            stopped.ways[way] = (stopped.ways[way] or 0) + (by[way] or 0)
        end
    end
    if estimate.blocked then
        stopped.blocked = stopped.blocked + estimate.blocked
        stopped.blocks = stopped.blocks + (by.BLOCK or 0) + (defence.partBlocked or 0)
    end

    -- The character's own figures, as they were in the newest fight.
    local saved = fight.mitigation or {}
    if not stopped.at or (fight.at or 0) > stopped.at then
        stopped.at = fight.at or 0
        stopped.armourValue = saved.armour or stopped.armourValue
        stopped.blockValue = saved.blockValue or stopped.blockValue
    end
end

--- Notes the Defence skill and resistances from a fight, if it's the
--- newest yet that has them: they're true of the character as they are,
--- not of the set.
local function NoteCharacter(summary, fight)
    local saved = fight.mitigation
    if not saved then
        return
    end
    local level = fight.level

    if saved.defence and saved.defenceBase and level then
        local known = summary.defenceSkill
        if not known or (fight.at or 0) > known.at then
            local skillPerLevel = ns.Mitigation.SKILL_PER_LEVEL
            summary.defenceSkill = {
                at = fight.at or 0,
                rank = saved.defence,
                base = saved.defenceBase,
                cap = level * skillPerLevel,
                level = level,
                enemyLevel = fight.enemyLevel,
                wanted = fight.enemyLevel and fight.enemyLevel * skillPerLevel,
            }
        end
    end

    if saved.resistances then
        local known = summary.resisting
        if not known or (fight.at or 0) > known.at then
            summary.resisting = {
                at = fight.at or 0,
                by = saved.resistances,
                level = fight.enemyLevel or level,
            }
        end
    end
end

--- Sums up the healing and defence in a set of fights.
---@param fights table|nil  list of fights, in any order
---@return table summary:
---   fights      how many fights were given
---   tracked     how many of them had any of this written down; fights
---               saved before Temper recorded it have none
---   seconds     how long the tracked fights lasted in all
---   healing, hps   healing done, and healing per second of those fights
---   absorbed    damage soaked up by the player's own shields
---   taken       damage the player took
---   avoidable   how much of that the game marks as avoidable; nil if it
---               never said
---   healedBack  healing as a share of the damage taken; nil when none was
---   abilities   list, biggest first, of:
---                 id, name, icon, rank, pet   what it is, and whether
---                                             it's the pet's
---                 healing, share              what it did
---                 casts, perCast              uses, and healing per use;
---                                             only where casts were seen
---                 cost, power                 what one use costs
---                 perCost                     healing per point of that
---   hurtBy      list, biggest first, of the enemy abilities that did the
---               damage: id, name, from (the enemy's name, if known),
---               amount, share, avoidable. A fight keeps only its worst
---               few, so these needn't add up to all that was taken
---   heals, healCrits   heals that landed on the player, counted
---   critRate    critical heals as a share of them; nil without a heal
---   struck, avoided    enemy attacks that landed, and that didn't
---   avoidedBy   how many were avoided each way: DODGE, PARRY, BLOCK...
---   avoidRate   attacks avoided as a share of all attacks; nil without
---               a single attack
---   crits, crushing   blows that landed as critical or crushing hits
---   critBlows   the blows that landed in the fights where those were
---               counted, which older fights didn't
---   magic       spells that hit the player, in the fights that counted them
---   allHits     blows and spells together, in those same fights
---   schools     how many of the spells were of each school, by the
---               game's mask for it (see Mitigation.lua)
---   resisted    how many spells were marked as resisted, in full or part
---   interrupts, dispels   casts interrupted and effects dispelled
---
--- and, each only when there's something to say:
---
---   stopped     about how much of the harm coming at the player never
---               reached them, over the fights where it could be worked
---               out (see Mitigation.Estimate):
---                 fights       how many of them
---                 coming       the harm that came at the player in them
---                 taken, physical, absorbed   what got through, how much
---                              of that was physical, and what shields
---                              soaked up
---                 armour, avoided, blocked   about what armour, the blows
---                              dodged, parried and missed, and the
---                              shield stopped; 0 where none was worked out
---                 share        all that was stopped, as a share of coming
---                 armourCut    the share armour took off a physical blow,
---                              on average; nil if never known
---                 ways         how many blows were dodged, parried and
---                              missed: { DODGE, PARRY, MISS }
---                 blocks       how many blows the shield blocked
---                 armourValue, blockValue   the player's armour and block,
---                              as they were in the newest of the fights
---   defenceSkill  { rank, base, cap, level, enemyLevel, wanted }: the
---               player's Defence skill in the newest fight that noted it,
---               with bonuses and as trained, the most their level
---               allows, and what that fight's enemy called for
---   resisting   { by, level }: the player's resistances in the newest
---               fight that noted them, by school, and the level of the
---               enemy they were up against
---   level, enemyLevel   as they were in the newest fight
function Healing.Of(fights)
    local summary = {
        fights = 0,
        tracked = 0,
        seconds = 0,
        healing = 0,
        hps = 0,
        absorbed = 0,
        taken = 0,
        abilities = {},
        hurtBy = {},
        heals = 0,
        healCrits = 0,
        struck = 0,
        avoided = 0,
        avoidedBy = {},
        crits = 0,
        crushing = 0,
        critBlows = 0,
        magic = 0,
        allHits = 0,
        schools = {},
        resisted = 0,
        interrupts = 0,
        dispels = 0,
    }

    local abilities, blows = {}, {}
    local newest

    for _, fight in ipairs(fights or {}) do
        summary.fights = summary.fights + 1
        if not newest or (fight.at or 0) > (newest.at or 0) then
            newest = fight
        end

        if IsTracked(fight) then
            summary.tracked = summary.tracked + 1
            summary.seconds = summary.seconds + (fight.length or 0)
            summary.absorbed = summary.absorbed + (fight.absorbed or 0)
            summary.interrupts = summary.interrupts + (fight.interrupts or 0)
            summary.dispels = summary.dispels + (fight.dispels or 0)

            if fight.healing then
                AddHealing(summary, abilities, fight.healing)
            end
            if fight.taken then
                AddTaken(summary, blows, fight.taken)
            end
            if fight.defence then
                AddDefence(summary, fight.defence)
            end

            -- Missing straight after an update, until the game is
            -- restarted and finds the new file.
            if ns.Mitigation then
                AddStopped(summary, fight)
                NoteCharacter(summary, fight)
            end
        end
    end

    if newest then
        summary.level = newest.level
        summary.enemyLevel = newest.enemyLevel
    end

    local stopped = summary.stopped
    if stopped then
        local kept = stopped.armour + stopped.avoided + stopped.blocked + stopped.absorbed
        stopped.share = stopped.coming > 0 and kept / stopped.coming or 0
        if stopped.cutPhysical > 0 then
            stopped.armourCut = stopped.cutSum / stopped.cutPhysical
        end
    end

    if summary.seconds > 0 then
        summary.hps = summary.healing / summary.seconds
    end
    if summary.taken > 0 then
        summary.healedBack = summary.healing / summary.taken
    end
    if summary.heals > 0 then
        summary.critRate = summary.healCrits / summary.heals
    end
    if summary.struck + summary.avoided > 0 then
        summary.avoidRate = summary.avoided / (summary.struck + summary.avoided)
    end

    for _, ability in ipairs(summary.abilities) do
        ability.share = summary.healing > 0 and ability.healing / summary.healing or 0
        if ability.casts and ability.casts > 0 then
            ability.perCast = ability.castHealing / ability.casts
            if ability.cost then
                ability.perCost = ability.perCast / ability.cost
            end
        end
    end
    table.sort(summary.abilities, function(a, b)
        return a.healing > b.healing
    end)

    for _, blow in ipairs(summary.hurtBy) do
        blow.share = summary.taken > 0 and blow.amount / summary.taken or 0
    end
    table.sort(summary.hurtBy, function(a, b)
        return a.amount > b.amount
    end)

    return summary
end

--- The words for blows dodged, parried and missed, naming only the ways
--- that happened, so a player who can't parry isn't told they did.
local function TurnedWords(ways)
    local words = {}
    for _, way in ipairs(TURNED_WORDS) do
        if (ways[way[1]] or 0) > 0 then
            table.insert(words, way[2])
        end
    end

    if #words == 0 then
        return "dodges and misses"
    elseif #words == 1 then
        return words[1]
    end
    local last = table.remove(words)
    return table.concat(words, ", ") .. " and " .. last
end

--- Each way the harm coming at the player was stopped, biggest first,
--- leaving out any that stopped nothing.
---@param stopped table  from Healing.Of
---@return table  list of { key = "armour", "avoided", "blocked" or
---               "absorbed", words = how a sentence says it ("armour",
---               "dodges and misses"...), amount, share of what came at
---               the player }
function Healing.StoppedWays(stopped)
    local ways = {}
    local function Add(key, words, amount)
        if amount > 0 and stopped.coming > 0 then
            table.insert(ways, {
                key = key,
                words = words,
                amount = amount,
                share = amount / stopped.coming,
            })
        end
    end

    Add("armour", "armour", stopped.armour)
    Add("avoided", TurnedWords(stopped.ways), stopped.avoided)
    Add("blocked", "your shield", stopped.blocked)
    Add("absorbed", "absorbs", stopped.absorbed)

    table.sort(ways, function(a, b)
        return a.amount > b.amount
    end)
    return ways
end

-- Saying what it shows ------------------------------------------------------------

--- True if a heal's healing for its cost is worth comparing: the player
--- paid for it, and it's been used often enough to go by. One lucky
--- critical heal shouldn't be enough to recommend it. A pet pays for its
--- heals out of its own, which is nothing the player can spend.
local function Comparable(ability)
    return ability.perCost ~= nil and not ability.pet and (ability.casts or 0) >= FEWEST_USES
end

--- The healing ability that gives most and least for what it costs, among
--- the player's own that cost the same resource. Needs two to mean
--- anything.
local function BestValue(summary)
    -- Compare within whichever resource most of them use.
    local counts, common = {}, nil
    for _, ability in ipairs(summary.abilities) do
        if Comparable(ability) then
            counts[ability.power] = (counts[ability.power] or 0) + 1
            if not common or counts[ability.power] > counts[common] then
                common = ability.power
            end
        end
    end

    local best, worst
    for _, ability in ipairs(summary.abilities) do
        if Comparable(ability) and ability.power == common then
            if not best or ability.perCost > best.perCost then
                best = ability
            end
            if not worst or ability.perCost < worst.perCost then
                worst = ability
            end
        end
    end

    if best and worst and best ~= worst then
        return best, worst
    end
end

--- What to call an ability in a sentence that also names another. Two
--- ranks of one heal share a name, and it's common to keep both on the
--- bars, so then the rank goes in too.
local function NameBeside(ability, other)
    if ability.name == other.name and ability.rank then
        return ("%s (%s)"):format(ability.name, ability.rank)
    end
    return ability.name
end

--- The enemy ability that did the most damage of those the game marks as
--- avoidable.
local function WorstAvoidable(summary)
    for _, blow in ipairs(summary.hurtBy) do
        if blow.avoidable then
            -- One the game gave no name for is no use named.
            return blow.id and blow.id ~= 0 and blow or nil
        end
    end
end

--- How far the player's Defence skill is behind what the enemy calls for,
--- if it's far enough to matter and could still be trained higher.
---@return table|nil skill  the summary's defenceSkill
---@return number|nil gap  how many points short it is
local function DefenceShortfall(summary)
    local skill = summary.defenceSkill
    if not skill or not skill.wanted then
        return nil
    end

    -- Not worth a word about a fight in which the enemy hardly swung at
    -- the player, as for someone fighting from range.
    if summary.struck + summary.avoided < ENOUGH_BLOWS then
        return nil
    end

    -- As high as the player's level allows, there's nothing to train, and
    -- nothing to be done about enemies above it. Only the part of the gap
    -- that training can close counts.
    local gap = math.min(skill.wanted, skill.cap) - skill.rank
    if skill.base >= skill.cap or gap < SKILL_GAP_WORTH_MENTIONING then
        return nil
    end
    return skill, gap
end

--- "2 critical and 3 crushing blows", or whichever of the two there were.
local function HardBlowsText(summary)
    local crits, crushing = summary.crits, summary.crushing
    if crits > 0 and crushing > 0 then
        return ("%d critical and %s"):format(crits, ns.Count(crushing, "crushing blow"))
    elseif crushing > 0 then
        return ns.Count(crushing, "crushing blow")
    end
    return ns.Count(crits, "critical hit")
end

--- The sentence on a Defence skill that's behind. It says what the gap
--- costs by the character sheet's own sums, and what it came to here.
local function DefenceSentence(summary, skill, gap, these)
    local mitigation = ns.Mitigation
    local crushing = mitigation.CrushingChance(skill.enemyLevel, skill.level, skill.rank)
    local critMore = gap * mitigation.COST_PER_POINT

    local cost
    if crushing > 0 then
        cost = ("about a %s chance of a crushing blow and %.1f%% more of a critical hit"):format(
            ns.Percent(crushing),
            critMore
        )
    else
        cost = (
            "about %.1f%% more chance of a critical hit, and %.1f%% less of missing you or "
            .. "being dodged"
        ):format(critMore, critMore * 2)
    end

    local took = ""
    if summary.critBlows > 0 and summary.crits + summary.crushing > 0 then
        took = (" You took %s in %s."):format(HardBlowsText(summary), these)
    end

    return (
        "Your Defence skill is %d; level %d enemies call for %d, which gives them %s.%s "
        .. "It rises as enemies attack you."
    ):format(skill.rank, skill.enemyLevel, skill.wanted, cost, took)
end

--- The school of magic most of the spells that hit the player were of,
--- when spells were a good part of what hit them and one school was most
--- of those, and there's resistance to be had against it.
---@return number|nil school  the game's mask for it
---@return number|nil times  how many of the spells were of it
local function MainSchool(summary)
    if summary.magic < ENOUGH_SPELLS or summary.magic / summary.allHits < MUCH_MAGIC then
        return nil
    end

    local main, most = nil, 0
    for school, times in pairs(summary.schools) do
        if times > most then
            main, most = school, times
        end
    end

    local resistible = ns.Mitigation and ns.Mitigation.Resistible(main)
    if main and most / summary.magic >= MOSTLY_ONE_SCHOOL and resistible then
        return main, most
    end
end

--- The sentence on the player's resistance to the school most of what hit
--- them was. Nil when the resistance wasn't noted.
local function ResistanceSentence(summary, school, times, these)
    local resisting = summary.resisting
    local resistance = resisting and resisting.by[school]
    if not resistance or not resisting.level then
        return nil
    end

    local word = ns.Mitigation.SchoolWord(school)
    local most = ("Most of the spells that hit you in %s were %s: %d of %d."):format(
        these,
        word,
        times,
        summary.magic
    )
    if resistance <= 0 then
        return (
            "%s You have no %s resistance, and gear with %s resistance would turn some of "
            .. "it aside."
        ):format(most, word, word)
    end

    local share = ns.Mitigation.ResistedShare(resistance, resisting.level)
    return (
        "%s Your %s resistance of %d turns aside about %s of %s damage from level %d "
        .. "enemies, and gear with %s resistance raises that."
    ):format(most, word, resistance, ns.Percent(share), word, resisting.level, word)
end

--- A few sentences about the healing and defence in a set of fights.
---@param summary table  from Healing.Of
---@return table  list of { kind = "good", "warning" or "tip", text = the
---               sentence }, most useful first; empty when there's
---               nothing worth saying
function Healing.Findings(summary)
    local found = {}
    local function Say(kind, text, ...)
        if #found < MOST then
            table.insert(found, { kind = kind, text = text:format(...) })
        end
    end

    if not summary or summary.tracked == 0 then
        return found
    end

    local these = summary.fights == 1 and "this fight" or "these fights"

    -- First, a Defence skill that's letting blows through. Of everything
    -- here it's the one that goes away just by fighting.
    local defence, gap = DefenceShortfall(summary)
    if defence then
        Say("warning", "%s", DefenceSentence(summary, defence, gap, these))
    end

    -- Then how the healing stood against the damage taken.
    local back = summary.healedBack
    if back and back >= 1 then
        Say(
            "good",
            "You healed as much in %s as the damage you took: %s healed, %s taken.",
            these,
            ns.Number(summary.healing),
            ns.Number(summary.taken)
        )
    elseif back and back >= HEALED_BACK_WORTH_MENTIONING then
        Say(
            back >= MUCH_HEALED_BACK and "good" or "tip",
            "You healed back %s of the damage you took in %s: %s of %s.",
            ns.Percent(back),
            these,
            ns.Number(summary.healing),
            ns.Number(summary.taken)
        )
    end

    -- Then damage that needn't have been taken. Which abilities count is
    -- the game's own judgement, so the sentence says whose it is.
    local avoidable = summary.avoidable
    local share = avoidable and summary.taken > 0 and math.min(avoidable / summary.taken, 1)
    if share and share >= MUCH_AVOIDABLE then
        local worst = WorstAvoidable(summary)
        if worst then
            Say(
                "warning",
                "%s of the damage you took in %s was from abilities the game marks as "
                    .. "avoidable, most of all %s.",
                ns.Percent(share),
                these,
                worst.name
            )
        else
            Say(
                "warning",
                "%s of the damage you took in %s was from abilities the game marks as avoidable.",
                ns.Percent(share),
                these
            )
        end
    end

    -- Then magic that the right gear would turn some of aside.
    local school, times = MainSchool(summary)
    local resistance = school and ResistanceSentence(summary, school, times, these)
    if resistance then
        Say("tip", "%s", resistance)
    end

    -- Then what a heal's cost buys, where one gives clearly more for its
    -- mana than another: that's a choice the player can make.
    local best, worst = BestValue(summary)
    if best and best.perCost >= worst.perCost * CLEARLY_BETTER_VALUE then
        local resource = ns.Summary.PowerWord(best.power)
        Say(
            "tip",
            "%s costs %d %s for about %s healing. The same %s spent on %s would heal about %s.",
            NameBeside(worst, best),
            worst.cost,
            resource,
            ns.Number(worst.perCast),
            resource,
            NameBeside(best, worst),
            ns.Number(worst.cost * best.perCost)
        )
    end

    -- Then a lot of hard blows. When the Defence skill is behind, that's
    -- already been said, with the counts.
    local hard = summary.crits + summary.crushing
    if
        not defence
        and summary.critBlows >= ENOUGH_BLOWS
        and hard / summary.critBlows >= MANY_CRITS
    then
        local why = ""
        local level, enemyLevel = summary.level, summary.enemyLevel
        if level and enemyLevel and enemyLevel > level then
            why = " Enemies above your level land them more often."
        end
        Say(
            "tip",
            "%s of the enemy blows that landed on you in %s were critical or crushing: %s "
                .. "of %d.%s",
            ns.Percent(hard / summary.critBlows),
            these,
            HardBlowsText(summary),
            summary.critBlows,
            why
        )
    end

    -- Then what armour did, said plainly, when most of the harm was the
    -- kind it works on.
    local stopped = summary.stopped
    if
        stopped
        and stopped.armourCut
        and stopped.armour > 0
        and stopped.physical >= stopped.taken * MOSTLY_PHYSICAL
    then
        Say(
            "tip",
            "Your armour took about %s off each physical blow in %s: about %s damage "
                .. "you didn't take.",
            ns.Percent(stopped.armourCut),
            these,
            ns.Number(stopped.armour)
        )
    end

    -- Last, what went well.
    local interrupts, dispels = summary.interrupts, summary.dispels
    if interrupts > 0 and dispels > 0 then
        Say(
            "good",
            "You interrupted %s and dispelled %s in %s.",
            ns.Count(interrupts, "cast"),
            ns.Count(dispels, "effect"),
            these
        )
    elseif interrupts > 0 then
        Say("good", "You interrupted %s in %s.", ns.Count(interrupts, "cast"), these)
    elseif dispels > 0 then
        Say("good", "You dispelled %s in %s.", ns.Count(dispels, "effect"), these)
    end

    return found
end
