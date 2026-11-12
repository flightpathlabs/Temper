# Strikewise

An addon for World of Warcraft: Forever, for players who want to know
whether a change made them hit harder.

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

It's for playing on your own. In a group it steps aside.

## Using it

There is nothing to set up.

- **Record** is a small button on the screen. Left-click to start and stop,
  right-click to open the window, drag to move it. There's a key binding
  too, under Options > Keybindings > Strikewise.
- **`/strike`** opens the window. `/strike record` starts and stops a
  recording.
- Fights are kept even when you aren't recording, under "Recent fights", so
  there's something to compare with after the fact.
- To compare, open a recording and choose **Compare with...**. Stopping a
  recording compares it with the one before automatically.
- Options are in the game's own Options window, under AddOns > Strikewise.

## What it can and can't know

Forever closes the combat log to addons, so Strikewise works from what the
game still offers. That shapes what it shows.

| It knows exactly | Because |
|---|---|
| Damage by ability, per fight | The game tallies it and lets addons read the tally when a fight ends |
| Damage a second, time in battle | From the same tally and the length of the fight |
| Hits, critical hits, misses, dodges, parries | The game reports each blow on your target as it lands |
| How many times you used each skill | The game reports your own casts |

| It can't know | Because |
|---|---|
| The size of any one hit | The game lets an addon draw the amount on screen but not read it |
| Your biggest crit | Follows from the above. "Hardest single use" is the nearest thing: when an ability is used once in a fight, its total for that fight is that one use |
| Which ability a given number on screen was | The game doesn't say what landed, only that something did |
| Whose hit it was, in a group | Likewise, which is why it keeps to solo play |

Numbers are shown for your current target only. Damage to other enemies
still counts in the analysis; it just isn't drawn.

## Blizzard's damage numbers

While Strikewise's column is showing, it switches the game's own damage
numbers off so each hit isn't shown twice, and puts your setting back when
it steps aside and when you log out. You can turn this off in the options.

Your setting is kept in Strikewise's saved data, so it's put back
correctly even if the game closed badly while the numbers were off. If you
remove Strikewise straight after a crash and find them missing, turn them
back on under Options > Combat.

## Working on it

Lua 5.1, no libraries. From the addon folder:

```
stylua .
luacheck .
```

Every Lua file has to be listed in `Strikewise.toc`, in an order where each
file only uses what the ones above it define. The game says nothing about
a file that exists but isn't listed.

Files newly added to the TOC need a full restart of the game, not a
`/reload`.

## Licence

MIT. See [LICENSE](LICENSE).
