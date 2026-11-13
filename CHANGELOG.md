# Changelog

## Unreleased

First version.

**The numbers**

- Your hits appear in a column by each enemy's nameplate and follow it. By
  default they sit to the right of it, each with its ability's icon, and
  step up a line as new ones arrive, like a short log.
- Numbers show above your target and any other enemy that's fighting you,
  each with a column of its own.
- Choose how they move (rising stream, stay and step up, arc away, shrink
  away), how long they stay, which side of the nameplate they sit on, how
  far off, their size on a slider, and their font: any of the four the
  game uses, including the heavy one it draws its own damage numbers in.
- Numbers are coloured by kind of damage: weapon swings white, abilities
  yellow, magic in the colour of its school, a pet's blows green. Or
  colour magic only, or nothing.
- Critical hits have settings of their own: how much larger they are, on
  a slider; gold, red or their own colour; and whether they land with a
  small pop, a big pop, a shake or no fuss.
- Misses, dodges and parries show as small grey words.
- Hits on an enemy that isn't fighting you, when you haven't just swung or
  cast, are taken as somebody else's: small, faint and in a column of
  their own, or hidden, or shown like yours, as you choose. They're never
  counted in your figures.
- Optionally, an icon beside every number: the ability's own when Temper
  can tell which it was, a small dot in the school's colour for each tick
  of a bleed or damage over time, and a faint plain picture of the kind
  of damage for a hit it can't place. Bleed ticks are told from weapon
  swings, so they no longer show your weapon.
- Above the nameplate each number and its icon are centred together.
  Beside it, the icons form a straight column against the nameplate and
  the numbers line up flush beside them.
- While Temper's options are open, an example enemy stands beside the
  window with made-up hits playing on it, so each change shows as it's
  made. Drag it wherever suits. The Options window itself can be dragged
  aside by its title bar. `/temper example` shows the example at any time.
- The numbers need enemy nameplates to follow. With nameplates off they
  appear mid-screen, and Temper says so once.

**The panel**

- A small panel on screen shows the fight you're in as it happens (DPS,
  damage, a timer, hits, crits and misses) and the last fight's
  exact figures in between. Click it for the window, right-click for a
  menu, drag it anywhere, or turn it off.
- Under those it can list your last few fights and a few figures for the
  session: fights, average DPS, crit rate and biggest hit. Each of these,
  and the Temper icon, can be switched off from the panel's menu.
- A cog on the panel, and one in the window's title bar, opens the
  options. Beside the panel's cog, a stopwatch starts and ends a session:
  grey while none is running, in colour while one is.
- Along the bottom of the panel, a row of small icons lights for the buffs
  you have up: rested experience, food, an elixir, a flask, a scroll,
  something on your weapon, your class's own buffs and buffs from others.
  Point at one for what it is and how long is left. Just above the panel,
  a short note says when you're not ready to fight: a fishing pole still
  in hand, a class buff not up, no poison or imbue on your weapon, low
  ammunition, gear about to break, or a pet that's away or unhappy. It's
  silent, except that a fight begun with the fishing pole turns it red and
  plays your alert sound. Both can be switched off.

- Combo points as small pips just under your target's nameplate, lit as
  you build them, for rogues and druids in cat form.
- Numbers on an enemy that dies or goes out of sight go with it, rather
  than moving to the next enemy the game gives its nameplate to.
- Both panels come in a normal and a large size, and the buff icons
  along the bottom are a little larger.

**Fights**

- Every solo fight is kept, up to 200 for each character, and listed with
  its damage, DPS, length and crit rate.
- Click a fight to read it. Shift-click and Ctrl-click select several, and
  the page covers them all. Start session marks a run of fights so it
  selects with one click.
- The page opens with one compact row of figures: DPS, damage, time, crit
  rate, hits, attacks avoided and the biggest hit. Point at any of them
  for the detail behind it. Under the row, in boxed sections, come a bar
  for each ability with its icon, rank and share, the timeline of what
  you used, and what to work on. Hover a bar for its damage per use and
  per point of mana or energy.
- Misses, dodges, parries, blocks and resists are counted separately.
- A strip shows what you used, in order and to scale, with critical hits
  and failures marked.
- The biggest hit and biggest critical hit, worked out from how the
  enemy's threat rose with each blow. These are close estimates.
- "What to work on" says in a few sentences what's holding your damage
  back: a weapon skill behind the level of the enemies you're fighting,
  an ability that keeps failing, time with no ability in use, running
  short of mana, or an ability whose cost would do more spent on another.
  Advice about cost waits until each ability has been used a few times,
  so one lucky hit doesn't decide it.
- A note can be left on any session.

**Healing and defence**

- Each fight also keeps the healing you did, ability by ability; the
  damage you took, by the enemy ability that dealt it, with those the
  game marks avoidable flagged; what your own shields absorbed; and how
  many casts you interrupted and effects you dispelled. Heals that landed
  on you, how many were critical, and how many enemy attacks you dodged,
  parried or blocked are counted too.
- The fight page has a short "Healing and defence" section, with a link
  that opens the Healing and defence tab on the same fights.
- A Healing and defence tab breaks it all down for the last fight, the
  session, the last ten fights or everything on record: healing and HPS, damage taken
  and how much of it you healed back, a bar for each healing ability and
  each thing that hurt you, and a few plain sentences on what to work on.
- A healing panel, a twin of the fight panel, shows your healing and HPS
  live during a fight and the last fight's figures in between. It's on
  to begin with, and can be put away from the fight panel's right-click
  menu or the options.
- Only healing done during a fight is counted.
- **Who healed you.** The tab shows a bar each for you, your pet and
  anyone outside your group who healed you, and says how much of your
  own healing went on you, your pet and others. Healed back counts the
  healing that landed on you, yours and theirs. The fight page names who
  else healed you.
- **How much was stopped.** An estimate of the damage coming at you that
  never landed: how much your armour kept off, what your dodges, parries
  and blocks saved, and what your own shields absorbed, as a share of it
  all, with a bar for each. Crits and crushing blows taken are counted,
  and your Defence skill is noted with each fight.
- Advice on defence: a Defence skill behind the level of the enemies
  you're fighting, with the crits and crushing blows it's letting through;
  a resistance worth having when most of the damage was one kind of
  magic; and how much of the physical damage your armour is stopping.

**Alerts**

- An optional alert for the moments that change what's worth pressing
  next: Clearcasting for druids, mages and shamans, a warlock's Shadow
  Trance, and abilities that open up, such as Overpower, Revenge,
  Execute, Riposte, Counterattack, Mongoose Bite and Hammer of Wrath.
  The ability's icon appears below the middle of the screen with the
  game's own proc glow, and a sound you can pick or switch off: any of
  the game's own alert sounds, played at your Master Volume so it's heard
  over a fight.
- Off to begin with. It shows in a group too, since it's about your own
  next move. Clicks pass through it; it can be dragged while the options
  are open, where a sample shows.
- Buffs the game keeps from addons in a fight, Clearcasting among them,
  are drawn by the game's own buff display in the alert's place, so they
  show in a fight too. These have no sound yet.
- `/temper check` says which of your class's alerts this client lets
  Temper watch, and how.

**Your enemies**

- Each fight keeps who you fought: the target's level and whether it
  was elite, rare or a boss, and every enemy you struck.
- The list of fights names each by its boss, its enemy or its group
  ("Greater Tarantula ×3", "Group of 4"), with the level and a mark for
  elite, rare or boss beside it, and the fight's length where the time
  of day was. A search box at its top finds fights by enemy name.

**A typical DPS**

- Wherever fights are averaged (several fights on the Fights page,
  comparisons, experiments' verdicts, the day-by-day chart, the panel's
  session average and its arrow), the figure is a typical one: fights
  against critters and grey enemies, very short ones and the highest and
  lowest are left out, and it says how many it went by.

**About and problems**

- An About tab: what Temper is for, how to get the most from it, answers
  to the usual questions, the commands and the small print.
- Report a problem gathers what a report needs (nothing personal) into a
  box to copy, with the address to paste it at. Also `/temper report`.

**Comparing**

- Select some fights, press Compare with..., and pick any others. Each
  figure shows how far it moved, the ability that changed most is named,
  and the gear that differs is listed. The older set is always the
  "before".
- Ending a session compares it with the one before automatically.

**Experiments**

- Say what you're trying, fight a few enemies as you are, make the change,
  fight a few more. Temper gives a verdict and says how far to trust it:
  clear, probably, or too close to call, with how many more fights would
  settle it.

**Progress**

- Your bests: highest DPS, biggest critical hit, biggest hit and more.
  Click one to open its fight.
- A fluke can be left out with a click. Very short fights, and fights
  where much of the damage came from an item or some other effect, are
  left out automatically.
- A column for each day you've played, with your level marked.
- "Forget everything" wipes what's been recorded for the character, from the
  Progress tab or from the bottom of the Options page.

**Good manners**

- It's about your own fighting and nobody else's. Nothing is posted to chat,
  sent to other players or shared anywhere; your fights stay in your own
  saved data.
- Solo only. In a group the column steps aside, nothing is recorded and
  the game's own numbers come back. The ability alert and the combo
  points still show, since they're only about your own next move.
- The game's own damage numbers are switched off while the column is
  showing and put back afterwards. This can be turned off.
