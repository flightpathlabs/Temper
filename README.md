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

It does two things.

**Tidy damage numbers.** Your hits appear in one column by your target's
nameplate and follow the enemy around, in place of numbers flying all over
the screen. Critical hits are larger, a different colour, and land with a
pop.

**A record you can compare.** Press Record, fight a few enemies, press it
again. You get a page that says how much damage you did a second, how much
of it each ability accounted for, and how often you crit. Change a weapon
or the order you press things in, record again, and the page shows what
moved: up in green, down in red, with the gear you swapped listed
underneath.

Then it tells you, in plain sentences, what stands out: which skill gives
the most for its mana, what's costing you hits, and what to try.

It's for playing on your own. In a group it steps aside: no numbers, no
record, no opinions.

## Using it

There is nothing to set up.

- **`/temper`** opens the window, as does Temper's entry in the addon list
  by the minimap.
- **Record** is at the bottom of the window. `/temper record` does the
  same, and there's a key binding under Options > Keybindings > Temper.
  If you'd like a small Record button on the screen as well, turn it on in
  the options: left-click to start and stop, right-click for the window,
  drag to move it.
- Every fight is kept, recording or not, and listed with its damage, damage
  a second, length and crit rate. Click one to read it. Shift-click selects
  a run of fights and Ctrl-click adds one; the page covers whatever is
  selected.
- To compare, select the earlier fights and press **Keep as Before**, then
  select the later ones. The strip above the page says which step you're
  at. Stopping a recording compares it with the one before automatically.
- Hover an ability's bar for the game's own tooltip, with what it did and
  what each point of mana or energy bought.
- "What stands out" says in a few sentences what the figures show, and what
  is holding your damage back: a weapon skill that's behind the enemies
  you're fighting, a lot of dodges and parries, glancing blows.
- A small panel stays on screen with the fight you're in, or the last one:
  damage a second, damage, hits, crits and misses. Click it for the window,
  right-click for a menu, drag it anywhere, or turn it off in the options.
- Options are in the game's own Options window, under AddOns > Temper.

## What it can and can't know

Forever closes the combat log to addons, so Temper works from what the
game still offers. That shapes what it shows.

| It knows exactly | Because |
|---|---|
| Damage by ability, per fight | The game tallies it and lets addons read the tally when a fight ends |
| Damage a second, time in battle | From the same tally and the length of the fight |
| Hits, critical hits, misses, dodges, parries | The game reports each blow on your target as it lands |
| Your skill with the weapon in hand, and what a shortfall costs | The game shows it on the character sheet, and its own skills window gives the sums |
| How many times you used each skill | The game reports your own casts |
| What each skill costs, and so its damage per point of mana or energy | The game says what a skill costs; the rest is division |

| It can't know | Because |
|---|---|
| The size of any one hit | The game lets an addon draw the amount on screen but not read it. The same goes for your running damage during a fight: the panel shows it, and the exact figures arrive when the fight ends |
| Your biggest crit | Follows from the above. "Hardest single use" is the nearest thing: when an ability is used once in a fight, its total for that fight is that one use |
| Which ability a given number on screen was | The game doesn't say what landed, only that something did. The optional icon beside each number is a best guess from what you just cast and the kind of damage |
| Whose hit it was, in a group | Likewise, which is why it keeps to solo play |

Numbers are shown for your current target only. Damage to other enemies
still counts in the analysis; it just isn't drawn.

## Blizzard's damage numbers

While Temper's column is showing, it switches the game's own damage
numbers off so each hit isn't shown twice, and puts your setting back when
it steps aside and when you log out. You can turn this off in the options.

Your setting is kept in Temper's saved data, so it's put back
correctly even if the game closed badly while the numbers were off. If you
remove Temper straight after a crash and find them missing, turn them
back on under Options > Combat.

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
