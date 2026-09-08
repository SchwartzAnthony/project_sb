# This round, what already exists, and what is left

You asked for about twenty things. Several are weeks of work each. I have
**built the bugs and the two systems that unblock the most**, told you
honestly **which things already exist and how to use them**, and written
**the CSV designs for the rest** so the next round is typing rather than
deciding.

I have not half-built ten features. That would have cost you a broken game.

---

## STEP 1 — Where every file goes

| File | Folder |
|---|---|
| `audio_db.gd` | `src/core/` |
| `audio_director.gd` | `src/core/` |
| `team_db.gd` | `src/core/` |
| `pause_menu.gd` | `src/ui/` |
| `Audio.csv` | `data/` |
| `Teams.csv` | `data/` |
| `ability_engine.gd` | `src/core/` *(replace)* |
| `scene_paths.gd` | `src/core/` *(replace)* |
| `season_db.gd` | `src/core/` *(replace)* |
| `match_report.gd` | `src/core/` *(replace)* |
| `content_report.gd` | `src/core/` *(replace)* |
| `main_scene.gd` | `src/formations/` *(replace)* |
| `goalie_unit.gd` | `src/units/` *(replace)* |
| `rps_clash.gd` | `src/ui/` *(replace)* |
| `season_screen.gd` `pub_screen.gd` `talent_screen.gd` `unlock_board.gd` `save_inspector.gd` | `src/ui/` *(replace)* |
| `Season.csv` `Tuning.csv` | `data/` *(replace)* |

**`Audio.csv` and `Teams.csv` are new — set both to "Keep File (No Import)".**
FileSystem → click the file → **Import** tab → **Keep File (No Import)** →
**Reimport**. Your `TierPowers.csv` still needs this too; I can see the
`.translation` files in the repo.

---

# PART 1 — THE BUGS

## The 6-power enemy — my fault

`Difficulty` in `Season.csv` adds a flat bonus to every enemy card. A
Difficulty of 1 on a 5-power Tier IV Star gives 6. I introduced that column
and never put a ceiling on it.

There is now a ceiling: **`max_card_power` in `Tuning.csv`, 5 by default.**
Nothing — not Difficulty, not an ability, not a brew — can push a card past
it. Verified across every fixture in your season: the old code could reach 8,
the new one never exceeds 5. Difficulty still does its job of lifting weak
cards (1 + 2 = 3), it just cannot break the top of the scale.

## Back went to the base instead of where you came from

Every screen hard-coded where its Back button went. Now `ScenePaths`
remembers the trail: `go_to()` records the screen you are leaving,
`go_back()` returns to it.

- main menu → season → **Back** → main menu
- base → season → **Back** → base
- three deep, Back three times walks you back out
- the trail is wiped at kick-off, so Back on the season table can never walk
  you into the match you just played

## Cards were in a random order

Now always **weakest on the left, strongest on the right** — by attack while
you are attacking, by defence while you are defending, so the right-hand card
is always the best one *for this round*. After two matches you stop reading
the numbers.

## Everything kept moving during a duel

The cut-away did not stop the pitch, so eighteen players carried on running
behind it. `freeze_play()` now wraps the whole cut-away.

## You could not see the keeper

The keeper's sprite has no texture until `Goalies.csv` gives it one. With a
blank Artwork column it was drawn as literally nothing. There is now a
fallback — a coloured keeper with gloves and a **G** — exactly like the
labelled plaques the base screen uses before you have building art. **Draw the
art and it disappears on its own.**

---

# PART 2 — WHAT I BUILT

## Audio.csv — every sound, from a spreadsheet

One row per sound. Nothing in code ever names a file.

| Column | |
|---|---|
| **When** | the moment: `screen_opened` `match_started` `play_maker` `hold_up` `goal_scored` `goal_conceded` `shot_taken` `save_made` `duel_won` `duel_lost` `brew_drunk` `match_ended` `card_hovered` `card_picked` |
| **Match** | a filter on that moment: `screen=base`, `star=yes`, `tier=IV`, `power>=4`, `result=win`. Blank = every time |
| **Sound** | the file in `assets/audio/`. Extension optional |
| **Bus** | `Music` `Effects` `UI` |
| **Loop** | `true` = keeps playing until something else claims that bus |
| **Volume** | decibels. `0` = as recorded, `-6` = half as loud |
| **Fade** | seconds to fade in, and the old track out |
| **Requires** | the same condition language as everywhere else |

**Two rows that show the whole idea:**

```
base_theme,screen_opened,screen=base,base_calm,Music,true,-10,2,,
base_theme_brewing,screen_opened,screen=base,base_warm,Music,true,-10,2,unlocked:Brewery,
```

Same moment, same bus. Before the Brewery you get the calm track; after it,
the warm one. **The last matching row wins**, so special cases go below
general ones.

Music survives changing screens — the player lives on the tree root, not on a
screen — and asking for the track that is already playing does nothing, so
base → pub → base does not restart the theme.

**Why this needed almost no hooks:** the match already reports every event
with its facts, so one line in `_report()` gave `Audio.csv` every match
moment at once, including any you add later. Screen music is one line in
`go_to()`, which covers every screen there is *and every screen you ever add*.

I have shipped 24 rows ready to go. **You have no `assets/audio/` folder yet**,
so the startup report will say *"24 sound rows are ready and waiting"* as one
line rather than 24 complaints. Make the folder, drop files in with those
names, and they play with no further changes.

## Teams.csv — you can now say who you play against

This was your clearest gap: *"I cannot dictate who the player will play
against."*

| Column | |
|---|---|
| **ID** | what `Season.csv`'s new **Team** column names |
| **Name** | what the player sees |
| **Class** | which class they field |
| **Cards** | the exact card names, separated by `\|`. **Blank = any cards of that class**, which is what the game did before |
| **Power** | how strong you *intend* it to be, for matching |
| **Requires** | a team can be locked behind anything |

**Power is measured, not just claimed.** The startup report reads the actual
cards and tells you when a team marked Power 2 really averages 4. That is what
stops the matching quietly lying to you.

`Season.csv` now has a **Team** column and all eleven fixtures name one, so
the season ramps 1 → 1 → 2 → 2 → 3 → 3 → 4 → 4 → 4 → 5 → 5. Verified: it
never dips.

**Matching to the player** is built (`for_power()`): ask for the power of the
player's own squad and you get an opponent of about that strength. That is
the engine your quick match needs — see Part 4.

## Escape pauses everything

Escape at any moment: speed buttons, AUTO on/off, Resume, and **Quit this
match**.

Quit warns you once, and the second press **puts your save back exactly as it
was at kick-off** — goals, unlocks and achievement progress all undone. That
needed no new bookkeeping: the match already photographs your save at
kick-off so the "what you gained" panel can work, and quitting simply pastes
that photograph back.

## AUTO now plays the whole match

It already picked your cards. It now also throws rock/paper/scissors and
chooses attack or defend. `auto_attack_chance` in `Tuning.csv` (0.5 = a coin,
1 = always attack).

---

# PART 3 — THINGS YOU ASKED FOR THAT ALREADY EXIST

## "Goal points for the talent tree"

**One row in `Stats.csv`:**

```
goal_points,goal_scored,,,Match,Goal points,
```

That is it. Every goal now adds one. Spend them with a talent whose
`Requires` is `count:goal_points>=5`. The talent tree already spends
counters — that is exactly how `talent_points` works.

Want 3 points for a Star's goal? A second row below it:

```
goal_points,goal_scored,star=yes,2,Match,,Two MORE on top of the one above.
```

## "Distinguish normal achievements from season progress"

Already there, two ways:

**By name.** Anything the season keeps starts `season_` —
`season_wins`, `season_points`, `flag:season_champion`. Your own achievements
do not. So `count:season_wins>=3` and `count:matches_won>=3` are different
questions and always were.

**By Group.** `Stats.csv`'s `Group` column already sorts the post-match
screen into panels. Put your achievement counters in a Group called
`Achievements` and season ones in `Season` and they are visually separated
with no code.

## "Buildings that produce wheat, water, components"

Already possible. A building's **Action** column runs the same effects
language as everything else:

```
mill,The Mill,Grinds what the fields give up.,unlocked:Mill,mill,0.3,0.4,count:wheat+3,
well,The Well,,unlocked:Well,well,0.6,0.4,count:water+2,
```

Click the Mill, get 3 wheat. A shop is a building whose Action is
`count:wheat-5;count:hops+1`. A recipe is a talent or a building whose
`Requires` is `count:wheat>=5 and count:water>=3`.

**What is genuinely missing** is a *Recipes.csv* so you are not writing the
trade into each building's Action, and a stash screen. Design in Part 4.

## "Design new window screens through CSV"

Partly. **`Dialogue.csv` already is a window system** — a scene, lines,
a speaker, choices, and each choice can carry any effects. An event window
with three options and different rewards is a handful of rows today.

What it cannot do is arbitrary layout. Design in Part 4.

## "Quick Match contributes to achievements but not the season"

The machinery exists: a match with no fixture on is already a friendly and
records nothing to the season, and every `Stats.csv` counter still runs.
What is missing is the menu button and the hover text. Part 4.

---

# PART 4 — THE REST, DESIGNED

Each of these is real work. The CSV shapes are here so you can start writing
content before the code exists, and so the next round is building rather than
deciding.

## Quick Match  —  *small, do this first*

A `MenuConfig.csv` row pointing at `goto:classes`, plus a flag
`quick_match` set before the match so `SeasonDB.record()` is skipped. The
hover text is a `Description` column on the menu row.

## The halftime locker room  —  *medium*

At 45:00, freeze and open a screen. One swap per tier, same power level, or
drink a brew to change a card's class. Everything needed is already there:
`BrewDB.pour()`, the tier bands to enforce "same power level", and the
`.tscn` template pattern for the screen. **This is the most fun thing on the
list and I would do it second.**

## The seasons as biomes  —  *medium*, new CSV

```
Seasons.csv
ID,Name,Biome,Order,Requires,Tiers,Description
kesselgrund,The Kesselgrund Cup,marsh,1,,3,The home league.

SeasonTiers.csv
Season,Tier,Games,Must Win,Attempts,Reward,Notes
kesselgrund,1,3,2,1,count:coins+50,"Win 2 of 3 or start over"
kesselgrund,2,4,3,1,count:coins+80,
kesselgrund,3,5,3,1,count:coins+120,
kesselgrund,final,1,1,2,unlock:The Cup,Two attempts at the final
```

"The Season" becomes "The Seasons": biomes, locked ones greyed out, and
picking one opens a tree of tiers. `unlock_progress.gd` already draws exactly
this kind of tree with bars and "what is missing" — it would be reused, not
rewritten.

## Resources and brewing  —  *medium*, two new CSVs

```
Items.csv
ID,Name,Kind,Description,Art,Stack,Notes
wheat,Wheat,component,,wheat,99,
hops,Hops,component,,hops,99,
fire_ale,Fire Ale,drink,Grants BRAND_SCORCH for one match,fire_ale,5,

Recipes.csv
ID,Building,Makes,Amount,Costs,Time,Requires,Notes
fire_ale,brewery,fire_ale,1,wheat:3|hops:2|water:4,1,unlocked:Brewery,
```

`Costs` is the only new idea, and it is the same `name:amount` shape you
already read. Items are counters, so everything that already tests a counter
works on them for free. Collectible-after-a-match is a Progression row at
`match_ended`.

## The tutorial  —  *medium*, new CSV

```
Tutorial.csv
ID,Chapter,When,Requires,Title,Text,Points At,Pause,Once,Notes
first_pick,basics,play_maker,,Choosing a card,"The card on the right is the strongest...",CardContainer,true,true,
```

`When` reuses the moments the audio and progression systems already listen
for. `Points At` is a node name to highlight. `Pause` stops the game until
dismissed — the pause machinery now exists. Hovering explanations are the
card hover panel, generalised.

## Settings and Steam Deck  —  *large*

Audio volumes are nearly free now that the buses exist — three sliders
writing to `AudioServer`. Graphics, resolution and fullscreen are standard.
**Keybinds and controller are the real work**: every input in the game is
currently a hard-coded key, and they all have to become named actions in
Godot's Input Map first. That refactor is worth a round on its own.

For Steam Deck: export as Linux x86-64, controller support, and a default
resolution of 1280×800. The game already runs on all three platforms —
nothing in it is Windows-only.

## Player teams and upgrades  —  *large*

`Teams.csv` is the opponent half and it is done. The player half needs:
`Players.csv` (the pool of every card that exists), the player's own roster
saved in `GameState`, and a screen to swap and upgrade. The brew overlay
already does "temporarily change what a card counts as", so the temporary
half is largely built.

## The shot cut-away, the kickoff circle, passing instead of sprinting

All three are animation and timing work in `main_scene.gd`. They are real
but they are the kind of change I cannot verify without watching it run, so
I would rather do them in a round where you can look at each one and say
"more like that".

---

# WHAT I CHECKED

Nine passes, all green, all against your real CSVs.

- **The ceiling**, against every fixture: the old code could reach 8, the new
  one never exceeds 5, and difficulty still lifts a weak card.
- **The card order**, per tier and per class, attacking and defending, with
  ties keeping their order.
- **Teams.csv**: every named card exists, no team claims a power its cards do
  not have, matching picks the right opponent at every power, the locked team
  stays locked, and the season ramps without dipping.
- **Audio.csv**: every `When` is a moment the game really reports, loops are
  all on Music, the two-rows-one-moment trick resolves correctly, and a big
  save only fires above 4 power.
- **Quitting**: goals, unlocks and achievements all go back.
- **The back trail**: seven cases including "never walk into the match".
- Plus the earlier season, camera, controls, stats, unlock and combat passes,
  the static sweep of 60 scripts, and the scene check.

Two real problems were caught this way and fixed before you saw them: the
season difficulty dipping at match 7, and 24 audio warnings that would have
buried the rest of the report.

---

# WHAT I WOULD DO NEXT, IN ORDER

1. **Quick Match** — an hour, and it is on your list twice
2. **The halftime locker room** — the most fun thing here
3. **Resources and recipes** — `Items.csv` + `Recipes.csv` + a stash screen
4. **The seasons as biomes** — reusing the unlock-tree drawing
5. **The tutorial**
6. **Input actions**, then settings and controller

Tell me which and I will build it properly rather than quickly.
