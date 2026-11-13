![Temper](docs/images/temper-logo.png)

# Temper

An addon for World of Warcraft: Forever that helps you understand your own
fighting: how much damage you do, where it comes from, what's holding it
back, how well you keep yourself going, and whether a change you made
helped.

To temper steel is to test it and make it harder. Same idea.

**It's about you, and it stays with you.** Temper looks only at your own
fighting. It doesn't rank you against anyone, it doesn't measure other
players, and it has nothing to say about a group. It never posts to chat,
never sends anything to other players or to any server, and has no way to
share or export what it records. Your fights are kept in your own saved
game data and nowhere else.

## What it does

**Tidy damage numbers.** Your hits appear in a column by each enemy's
nameplate and follow it around, in place of numbers flying all over the
screen. By default they're a rising stream: small numbers climbing
straight up at a steady pace, like a scrolling log. Weapon swings are
white, abilities yellow and magic the colour of its school; critical hits
are larger and land with a pop. All of it can be changed, and an example
plays beside the options while you do.

**A panel for the fight you're in.** A small panel shows your DPS, damage,
hits, crits and misses as the fight goes, and the last fight's exact
figures in between. Click it for the full window.

**A record of every fight.** Each solo fight is kept and listed with its
damage, DPS, length and crit rate. Open one and you get:

- how much each ability did, with its icon, its share, and what each use
  and each point of mana or energy bought;
- every way an attack failed, counted separately: missed, dodged, parried;
- a few plain sentences about what to work on: a weapon skill that's
  behind the enemies you're fighting, an ability that keeps getting
  parried, time spent with nothing in use;
- a strip of what you used, in order, with crits and misses marked;
- the biggest hit and biggest critical hit.

**Healing and defence.** Each fight also keeps how much you healed and
with what, the damage you took and what it came from, what your shields
soaked up, and how many casts you interrupted and effects you dispelled.
The fight page sums it up in a line or two; the Healing and defence tab breaks it
down for the last fight, the session or everything on record; and a
second small panel, off until you want it, shows your healing live.

**Comparing.** Select some fights, press Compare with..., pick some
others, and every figure shows how far it moved, with the gear that
changed listed underneath.

**Experiments.** For a straight answer to "is this better?": Temper
records a few fights as you are, waits while you make your change, records
a few more, and gives a verdict that says how far to trust it.

**Progress.** Your bests, and a column for each day you've played,
measured against nobody but yourself. A fluke can be left out with a
click, and some are left out automatically.

It's for playing on your own. In a group it steps aside: no numbers, no
record, no opinions.

## Using it

There is nothing to set up.

- **`/temper`** opens the window, as does a click on the panel or on
  Temper's entry in the addon list by the minimap.
- **Fights tab.** Click a fight to read it. Shift-click selects a run of
  fights and Ctrl-click adds one; the page covers whatever is selected.
  Right-click for more. Type a note on a session to remember what you
  changed.
- **Start session** (bottom left, or `/temper session`, or a key under
  Options > Keybindings > Temper) marks a run of fights as a session,
  which then selects with one click. Fights are kept either way.
- **To compare,** select some fights, press **Compare with...**, click the
  fights to set them against, and press **Done**. The strip under the title
  bar says which step you're at. Whichever set is older is treated as the
  "before", so green always means you improved.
- **Experiments tab.** Press New experiment, say what you're trying, and
  follow the three steps. The panel tells you when it's your move.
- **Progress tab.** Click a best to open the fight it came from.
- Options are in the game's own Options window, under AddOns > Temper.
  The cog on the panel or in the window's title bar takes you there. The
  panel, the numbers and a small on-screen Start session button can each
  be switched on or off, and while the page is open an example enemy
  shows what your numbers will look like. Drag it, or the Options window
  by its title bar, wherever you can see it best.

## What it can and can't know

Forever closes the combat log to addons, so Temper works from what the
game still offers. That shapes what it shows.

| It knows exactly | Because |
|---|---|
| Damage by ability, per fight | The game tallies it and lets addons read the tally when a fight ends |
| DPS and fight length | From the same tally and the length of the fight |
| Hits, critical hits, misses, dodges, parries | The game reports each blow on an enemy as it lands |
| How many times you used each ability, and when | The game reports your own casts |
| What each ability costs, and so its damage per point of mana or energy | The game says what an ability costs; the rest is division |
| Healing by ability, damage taken by enemy ability, absorbs, interrupts and dispels, per fight | The game keeps tallies of these alongside its damage tally. Only healing done during a fight is in them; eating or bandaging between fights isn't |
| Your skill with the weapon in hand, and what a shortfall costs | The game shows it on the character sheet, and its own skills window gives the sums |

| It works out, and says "about" | How |
|---|---|
| How hard each blow landed, and so your biggest hit and biggest crit | An enemy's threat towards you rises by the damage of each blow, and the game lets addons read that. Blows that land close together can't be told apart, so not every blow is sized |
| Which ability a blow was, and whether each use landed | From what you had just used and the kind of damage |
| How much of the damage coming at you was stopped: by armour, by blows dodged, parried or missed, by your shield | The character sheet says what your armour takes off a blow and what your shield blocks, and every enemy blow that missed is counted. A blow that didn't land is valued at an average one that did. Resisted spells are counted but not valued: the game doesn't say by how much |

| It can't know | Because |
|---|---|
| Your running damage during a fight | The game lets an addon show it but not read it. The panel shows it; the exact figures arrive when the fight ends |
| How much mana or energy you have left | Hidden. Temper counts the times the game says you hadn't enough |
| Whose hit it was, in a group | The game doesn't say, which is why Temper keeps to solo play |

Numbers are drawn above your target and any other enemy that is fighting
you. A stranger's fight nearby is left alone. They follow each enemy's
nameplate, so enemy nameplates need to be on; with them off, the numbers
appear in the middle of the screen.

## Blizzard's damage numbers

While Temper's column is showing, it switches the game's own damage
numbers off so each hit isn't shown twice, and puts your setting back when
it steps aside and when you log out. You can turn this off in the options.

Your setting is kept in Temper's saved data, so it's put back correctly
even if the game closed badly while the numbers were off. If you remove
Temper straight after a crash and find them missing, turn them back on
under Options > Combat.

## Working on it

Lua 5.1, no libraries. From the addon folder:

```
stylua .
luacheck .
```

Every Lua file has to be listed in `Temper.toc`, in an order where each
file only uses what the ones above it define. The game says nothing about
a file that exists but isn't listed.

Files newly added to the TOC need a full restart of the game, not a
`/reload`.

## Licence

MIT. See [LICENSE](LICENSE).

Temper is a fan-made addon. World of Warcraft and related names and
artwork are trademarks of Blizzard Entertainment. This project is not
affiliated with or endorsed by Blizzard Entertainment.
