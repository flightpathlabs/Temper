![Temper](docs/images/temper-logo.png)

# Temper

An addon for World of Warcraft: Forever that helps you understand your own
damage: how much you do, where it comes from, what's holding it back, and
whether a change you made helped.

To temper steel is to test it and make it harder. Same idea.

**It's about you, and it stays with you.** Temper looks only at your own
damage. It doesn't rank you against anyone, it doesn't measure other
players, and it has nothing to say about a group. It never posts to chat,
never sends anything to other players or to any server, and has no way to
share or export what it records. Your fights are kept in your own saved
game data and nowhere else.

## What it does

**Tidy damage numbers.** Your hits appear in a column by each enemy's
nameplate and follow it around, in place of numbers flying all over the
screen. By default they're a steady stream: small, staying put, stepping
up a line as new ones arrive. Critical hits are larger, a different
colour, and land with a pop.

**A panel for the fight you're in.** A small panel shows your damage a
second, damage, hits, crits and misses as the fight goes, and the last
fight's exact figures in between. Click it for the full window.

**A record of every fight.** Each solo fight is kept and listed with its
damage, damage a second, length and crit rate. Open one and you get:

- how much each ability did, with its icon, its share, and what each use
  and each point of mana or energy bought;
- every way an attack failed, counted separately: missed, dodged, parried;
- a strip of what you pressed, in order, with crits and misses marked;
- the biggest hit and biggest critical hit;
- a few plain sentences about what stands out and what's holding you
  back: a weapon skill that's behind the enemies you're fighting, a skill
  that keeps getting parried, time spent with nothing in use.

**Comparing.** Select some fights, keep them as "Before", select some
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
  Right-click for more. Type a note on a fight or a recording to remember
  what you changed.
- **Record** (bottom left, or `/temper record`, or a key under Options >
  Keybindings > Temper) marks a run of fights as a recording, which then
  selects with one click. Fights are kept whether or not you record.
- **To compare by hand,** select the earlier fights, press **Keep as
  Before**, then select the later ones. The strip above the page says
  which step you're at.
- **Experiments tab.** Press New experiment, say what you're trying, and
  follow the three steps. The panel tells you when it's your move.
- **Progress tab.** Click a best to open the fight it came from.
- Options are in the game's own Options window, under AddOns > Temper.
  The panel, the numbers and a small on-screen Record button can each be
  switched on or off there.

## What it can and can't know

Forever closes the combat log to addons, so Temper works from what the
game still offers. That shapes what it shows.

| It knows exactly | Because |
|---|---|
| Damage by ability, per fight | The game tallies it and lets addons read the tally when a fight ends |
| Damage a second, time in battle | From the same tally and the length of the fight |
| Hits, critical hits, misses, dodges, parries | The game reports each blow on an enemy as it lands |
| How many times you used each skill, and when | The game reports your own casts |
| What each skill costs, and so its damage per point of mana or energy | The game says what a skill costs; the rest is division |
| Your skill with the weapon in hand, and what a shortfall costs | The game shows it on the character sheet, and its own skills window gives the sums |

| It works out, and says "about" | How |
|---|---|
| How hard each blow landed, and so your biggest hit and biggest crit | An enemy's threat towards you rises by the damage of each blow, and the game lets addons read that. Blows that land close together can't be told apart, so not every blow is sized |
| Which ability a blow was, and whether each cast landed | From what you had just cast and the kind of damage |

| It can't know | Because |
|---|---|
| Your running damage during a fight | The game lets an addon show it but not read it. The panel shows it; the exact figures arrive when the fight ends |
| How much mana or energy you have left | Hidden. Temper counts the times the game says you hadn't enough |
| Whose hit it was, in a group | The game doesn't say, which is why Temper keeps to solo play |

Numbers are drawn above your target and any other enemy that is fighting
you. A stranger's fight nearby is left alone.

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
