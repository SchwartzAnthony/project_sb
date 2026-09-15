# Can you build this game from spreadsheets alone?

**Yes — about 95% of it.** This document is the honest accounting: what you
can do without me, what you cannot, and what I changed this round to close
the gaps.

Read Part 1 if you only read one thing.

---

# STEP 0 — The two launch errors

Neither is in the code. Both are file-level and take a minute.

### `Class "MenuSupport" hides a global script class`

**There are two copies of `menu_support.gd` in your project.** A
`class_name` must be unique, so the second one refuses to compile — and
because half the game uses `MenuSupport`, that one error cascades.

**Fix:** in the FileSystem panel, type `menu_support` into the filter. You
will see it twice — almost certainly `src/core/` *and* `src/ui/`, because I
told you "put it back where it was" and it ended up in both. **Delete the
one you did not have before.** Mine belongs wherever it already lived.

Same trick for any future `hides a global script class`: filter for the
file name, delete the duplicate.

### `UID duplicate detected between Teams.csv and Talents.csv`

Godot writes a `.uid` file next to each import, and copying a CSV over
another copies its `.uid` too — so two files claim the same identity.

**Fix:** in your `data` folder, delete `Talents.csv.uid` (and `Teams.csv.uid`
if it complains again). Godot rebuilds them on the next scan. It is a
warning, not a crash, but it will keep nagging until you clear it.

**To avoid both in future:** when I send a replacement file, drag it in and
let Godot overwrite — do not copy the whole folder into a second location.

---

# PART 1 — THE HONEST ACCOUNTING

## What you CAN build with no code at all

| You want | File | Notes |
|---|---|---|
| A new player card | any unit CSV | Class, tier, power, element, art, abilities, Adventure stamina |
| A new class/race | any unit CSV | Give twelve cards a new **Unit Type** and it is a playable class |
| Change the tier ladder | `TierPowers.csv` | Every screen follows it |
| A new opposing team | `Teams.csv` | Names its cards, its keeper, its power |
| A whole season | `Season.csv` | Fixtures, difficulty, rewards, gating |
| A new kind of match | `MatchModes.csv` | Clock, cycles, Star rotation, which screen it plays in |
| A new biome | `Biomes.csv` | Waves, enemy pool, **and its whole colour scheme** |
| A new bounty / boss | `Bounties.csv` | Which biome, which boss, what it pays |
| A new enemy | `AdventureEnemies.csv` | Attack, layers, targeting, drops, how often it appears |
| A new item | `Items.csv` | Material, currency, recipe — or usable kit |
| What things drop | `Drops.csv` | Chance, amount, gated |
| A new brew | `Brews.csv` | **Now with a Cost** — see Part 2 |
| A new building | `Buildings.csv` | Including recipes — see Part 2 |
| A talent tree | `Talents.csv` | Parents, costs, any Tuning number as an effect |
| What gets counted | `Stats.csv` | New counter = new row |
| When things happen | `Progression.csv` | Unlocks, story, announcements |
| The story | `Dialogue.csv` | Scenes, choices, effects |
| Sound | `Audio.csv` | Music and effects, per moment, per condition |
| The main menu | `MenuConfig.csv` | Buttons, positions, art, actions |
| ~152 numbers | `Tuning.csv` | Speeds, timings, costs, difficulty |

**That is the whole game as it stands.** Every loop you named is
spreadsheet-only:

- **Adventure → resources**: `Biomes` → `AdventureEnemies` → `Drops` → `Items`
- **Resources → brews → race changes**: `Items` → `Brews.Cost` → `Brews.Becomes`
- **Resources → buildings**: `Buildings.Requires` is the price, `Action` is the trade
- **Season → big unlocks**: `Season.On Win` → `unlock:` → gates a biome, a building, a fixture
- **Everything → talents**: any counter or unlock in a talent's `Requires`

## What you CANNOT do without me — the complete list

Only five things. I have kept it short on purpose.

**1. A new ability EFFECT word.** `Abilities.csv` can combine the effects
the engine knows (power up/down, shot bonus, keeper stamina, and so on)
however you like. A genuinely new *verb* — "steal the ball", "swap two
cards" — is one function in `ability_engine.gd`. **This is the one you will
hit most.** Send me a list and I can add several at once.

**2. A new screen.** `goto:` reaches the screens that exist. A brand-new one
— a stash, a bestiary, a settings page — is a new file.

**3. A new match rule.** Two balls, a sending-off, extra time.

**4. A new column meaning.** You can rename columns and reorder them freely.
A column that means something new needs a line telling the loader to read it.

**5. Art behaviour.** Spritesheets are sliced from `Animations.csv`, but a
new *kind* of animation is code.

**Everything else is a row.**

---

# PART 2 — WHAT I FIXED THIS ROUND

## The economy had a hole in it: brewing was free

`Brews.csv` could be *gated* on having materials, but pouring one never
**spent** anything — so one Adventure run bought infinite brews forever.
That is the loop you asked about, and it was open.

**`Brews.csv` now has a `Cost` column:**

```
Cost
reed:6
reed:4|bog_iron:2
ash_glass:5|reed:3
```

Same `name:amount` shape as everywhere else, pipe-separated. The Pub greys
out anything you cannot pay for, and pouring takes the materials out of
your counters. Blank costs nothing, exactly as before.

**Adventure → materials → brews → a Lorelei that fights as a Brandteufel**
is now a closed loop with no code in it anywhere.

## Two content bugs the audit found

I wrote a checker that walks every CSV and matches every counter and unlock
against everything that writes one. It found two dead ends **in content I
had written myself**:

**`unlocked:Brewery and count:matches_played>=5`** — the condition language
joins terms with a semicolon, and `and` is not a word it knows. That row
could never be true, so **the Pub could never open**. Now `;`.

**`count:goals_with_brew_fire>=3`** unlocked the Brewery, but nothing ever
counted that. Two `Stats.csv` rows added and the chain works.

Both are the same class of mistake, and both were invisible: a condition
that is never true does not warn, it just quietly never fires. **The startup
report catches these now** — it names any counter read but never written.

## Every CSV is now well formed

The audit also found five rows with unquoted commas that had split into
extra cells. Fixed. **Every file in `data/` now parses cleanly and every
cross-reference resolves** — every drop names a real item, every bounty a
real boss, every talent a real parent, every visitor a real scene.

---

# PART 3 — THE WORKED PROTOTYPE

You asked for one of everything, built as a designer with no access to
code. Here is the chain I added, and every row of it is a worked example
you can copy.

**The Reed Press** — `Buildings.csv`

```
Requires  count:reed>=20
Action    count:reed-20;count:coins+60
```

**A recipe is a building Action.** Requires is the price check, Action is
the trade. That is why there is no `Recipes.csv` — there does not need to
be one.

**The Forge** pays in an *unlock* instead of a counter:

```
Requires  count:bog_iron>=25
Action    count:bog_iron-25;unlock:Iron Boots
```

**The Still** chains off both a building and a deep-biome material, so it is
only reachable once Adventure has taken you past the Marshlands.

**Marsh Legs** — `Talents.csv` — a talent that reads Adventure:

```
Requires  count:cleared_marshlands>=1
Effects   count:tune_adventure_stamina_base+2
```

`cleared_marshlands` is written when you beat the Marsh King. `tune_` in
front of **any** `Tuning.csv` key edits that number permanently.

**Iron Shod** requires `unlocked:Iron Boots` — so the full chain is
**Adventure → bog iron → the Forge → a talent that makes Adventure easier.**

**Matchday 12** — `Season.csv` — `Requires: unlocked:Marsh King`. The league
decider only opens once you have been into a biome. The two halves of the
game now need each other.

**The Brewer** — `Visitors.csv` + `Dialogue.csv` — turns up at the base the
moment the Brewery unlocks, says one thing, and goes.

---

# PART 4 — HOW TO WORK ON YOUR OWN

## The loop to get into

1. Edit a CSV. Save it.
2. Press **F5**.
3. **Read the Output panel.** Every loader reports what it found; the
   content report names anything that does not line up.
4. If a screen is blank or a thing never appears, the answer is almost
   always in that panel.

## The five mistakes that cost the most time

1. **`and` instead of `;`** in a Requires. Terms are separated by
   semicolons. `unlocked:Brewery;count:coins>=50`.
2. **A counter you read but never write.** `count:wheat>=5` is false forever
   until something adds wheat. The report names these.
3. **A comma in a Notes column without quotes.** Wrap any cell containing a
   comma in `"double quotes"`.
4. **Copying a CSV rather than replacing it**, which duplicates the `.uid`.
5. **Two files with the same `class_name`.** Delete the duplicate.

## What to ask me for next time

The most valuable thing, by a distance: **a list of ability effects you
want.** Everything else is a row you can write yourself; abilities are the
one place the spreadsheet runs out of vocabulary. Give me ten verbs and I
will add them all at once, and after that `Abilities.csv` will cover almost
anything you can imagine.

After that, in the order I would take them: **the halftime locker room**
(the most fun thing left, and the ladder already makes "swap for a card of
the same power" a rule the screen can enforce for free), then **the
tutorial**, then a **stash screen** so items have a home outside a fight.

---

# FOR THE PRESENTATION

**Run Clear the Reeds.** Two waves, the gentlest boss, the whole loop in a
couple of minutes. Log on for the first fight so people see the numbers,
off for the second so they watch the football.

Then open `Biomes.csv` on screen, change four colours, press F5, and walk
back into a different-looking world. That is the demo that makes the point:
**the spreadsheet is the game.**
