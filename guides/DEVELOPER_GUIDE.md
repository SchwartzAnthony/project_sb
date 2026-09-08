# PROJECT SB — THE DEVELOPER GUIDE

One document. Use **Ctrl+F** and the search words in `CAPITALS` beside each
heading.

Godot 4.7 · repo: https://github.com/SchwartzAnthony/project_sb

---

## CONTENTS

| # | Section | Ctrl+F for |
|---|---|---|
| 0 | What changed in this delivery | `SEARCH-FIXES` |
| 1 | The one rule of this project | `SEARCH-RULE` |
| 2 | Every file, and where it goes | `SEARCH-FILES` |
| 3 | Every CSV, column by column | `SEARCH-CSV` |
| 4 | The Requires / Do language | `SEARCH-GRAMMAR` |
| 5 | The save: flags, counters, texts, unlocks | `SEARCH-SAVE` |
| 6 | A match, second by second | `SEARCH-MATCH` |
| 7 | Cards, tiers and power | `SEARCH-POWER` |
| 8 | Abilities | `SEARCH-ABILITIES` |
| 9 | Movement, quarters and the ball | `SEARCH-MOVEMENT` |
| 10 | The camera | `SEARCH-CAMERA` |
| 11 | Speed, AUTO and the controls | `SEARCH-CONTROLS` |
| 12 | The season | `SEARCH-SEASON` |
| 13 | Stats and the post-match screen | `SEARCH-STATS` |
| 14 | Unlocks, talents, brews, buildings | `SEARCH-UNLOCKS` |
| 15 | Dialogue and story | `SEARCH-STORY` |
| 16 | Screens, and how to redesign one | `SEARCH-SCREENS` |
| 17 | Art: sprites, sheets, portraits | `SEARCH-ART` |
| 18 | The tools | `SEARCH-TOOLS` |
| 19 | Recipes — "how do I…" | `SEARCH-RECIPES` |
| 20 | When something breaks | `SEARCH-TROUBLE` |
| 21 | Rules for writing GDScript here | `SEARCH-CODE` |

---

# 0. WHAT CHANGED IN THIS DELIVERY `SEARCH-FIXES`

Three bugs you reported, all confirmed and fixed, all verified against your
real CSVs.

## "The cards I pick aren't the stats used in combat"

**Real, and it was in `build_lineup()`.** It checked the Star's tier *first*
and dropped the Star into that slot — **throwing away the card you had just
chosen**. If your Star was Tier IV and you picked a Tier IV card, your pick
was discarded and the Star fought instead, with the Star's numbers.

Now **your pick always wins**. The Star is only a fallback for a tier where
nothing was picked at all.

Every round now also prints the actual line-up to the Output panel:

```
Tier I    YOU Boilerblast Brandteufel   atk 2 / def 2   THEM Smokestorm ...
Tier IV   YOU Blacksmoke Brandteufel    atk 3 / def 3   THEM Hexflame ...
```

If a number on screen ever looks wrong again, that line is the shortest way
to see whether the card that fought is the card you chose.

## "The enemy played a 5-power Tier IV three times in a row"

**Real, and it was by design — a bad design.** The Star used to fill its own
tier automatically, every round, for the whole cycle. Three rounds per cycle
meant the same Star three times running. Because the Lorelei Star is Tier IV
with 5 power, the enemy fielded a 5-power Tier IV three rounds running while
your Tier IV rotated through ordinary cards. It was never a fair fight.

Now **the Star is offered in its tier like any other card and is used up when
picked**, on both sides. Verified: three different Tier IV cards across a
cycle, and a 5-power card fielded at most once.

To put the old behaviour back: `star_holds_its_tier` → `true` in `Tuning.csv`.

## "Tier I is 0,1,2 … Tier IV is 3,4,5"

Nothing enforced that. One mistyped number put a 5-power card in Tier I and
no error appeared anywhere.

New file **`data/TierPowers.csv`** holds the bands. Every card is checked as
it loads: anything outside its band is **named in the startup report and
pulled back into range**. Verified: a 5-power Tier I becomes 2, a 1-power
Tier IV becomes 3, a correct card is untouched.

Your current cards already all sit inside their bands.

## "There are no abilities active?"

**There are — on four cards.** In
`example_unit_csv_with_ability_columns.csv`:

| Card | Attack ability | Defend ability |
|---|---|---|
| Coalblaze Brandteufel | `BRAND_RALLY` | — |
| Fireline Brandteufel | `BRAND_MASK_ATK` | `LORE_VEIL` |
| Hexflame Brandteufel | `BRAND_SCORCH` | — |
| Sigilburn Brandteufel | `LORE_SURGE` | — |

**That file is an example I shipped.** If it is sitting in `res://data/`,
those twelve Brandteufel cards are in your game and four of them have
abilities. If you did not intend that, move it out of `data/`.

The duel cut-away already shows an ability when there is one and says
**"no ability"** when there is not — so what you saw was correct.

## "The cards don't show attack power or abilities"

New: **hover a card during a PLAY MAKER** and a window appears above the row
with the name, tier, class, star, brew, attack, defence, both abilities in
plain English, and what the tier's band is. Move away and it goes.

Switch: `card_hover_stats` in `Tuning.csv`.

**Files in this delivery:** `card_database.gd`, `main_scene.gd`,
`card_stats_panel.gd` (new), `TierPowers.csv` (new), `Tuning.csv`.

**`TierPowers.csv` is a new CSV — do the import step in `SEARCH-TROUBLE`.**

---

# 1. THE ONE RULE OF THIS PROJECT `SEARCH-RULE`

> **Content lives in spreadsheets. Code only reads them.**

Nothing in `src/` knows what a duel, a brew or a Brewery is. It knows how to
read a CSV, test a condition and carry out an effect. Everything else — every
card, every unlock, every number, every line of dialogue — is a row you can
edit in a spreadsheet.

Three consequences worth holding on to:

**Files are identified by their COLUMNS, never their name.** A CSV with a
`When` and a `Do` column is a progression file whether it is called
`Progression.csv` or `Chapter7.csv`. Split your rows across five files if you
like; the game reads every `.csv` in `res://data/`.

**Names are matched loosely.** `First Win`, `first_win` and `FIRSTWIN` are the
same thing everywhere. Letters and digits are compared; spaces, underscores
and capitals are ignored. A typo cannot quietly create a second flag.

**Everything is checked at startup.** Press F5 and the Output panel prints a
report: how much content was found, and everything that looks wrong. Nothing
in that report stops the game — it just tells you which content will not
appear and why.

---

# 2. EVERY FILE, AND WHERE IT GOES `SEARCH-FILES`

```
project_sb/
├── data/            EVERY .csv, no exceptions
├── assets/
│   ├── players/     card and unit spritesheets
│   ├── goalies/     keeper art
│   ├── base/        background.png + one PNG per building
│   ├── portraits/   one PNG per visitor
│   └── menu/        class banners
├── src/
│   ├── core/        the readers and the rules
│   ├── ui/          every screen
│   ├── units/       the things on the pitch
│   └── formations/  the match itself
└── tools/           the two HTML tools (NOT in data/)
```

## `src/core/` — the readers and the rules

| File | What it does |
|---|---|
| `card_database.gd` | reads every CSV; holds cards, abilities, animations, tuning, tier bands |
| `player_data.gd` | one card: name, class, tier, power, abilities, brew overlay |
| `goalie_data.gd` | one keeper |
| `ability_data.gd` | one row of Abilities.csv |
| `ability_engine.gd` | applies abilities during a duel; holds the per-side power bonus |
| `anim_spec.gd` | one row of Animations.csv |
| `field_bounds.gd` | where the pitch is |
| `pitch_zones.gd` | the four quarters |
| `zone_overlay.gd` | the quarter tinting |
| `menu_support.gd` | shared colours, panel styles, CSV helper |
| `scene_paths.gd` | where every screen lives; `go_to()` changes screen safely |
| `team_selection.gd` | your chosen team, carried between screens |
| `game_state.gd` | **the save** — flags, counters, texts, unlocks |
| `dialogue_grammar.gd` | **the language** — `test()` and `apply()` |
| `dialogue_db.gd`, `dialogue_line.gd`, `dialogue_choice.gd` | the story |
| `stats_rules.gd` | Stats.csv → counters |
| `progression.gd` | Progression.csv → when things happen |
| `season_db.gd` | Season.csv → the fixture list |
| `base_db.gd` | Buildings.csv + Visitors.csv |
| `talent_db.gd` | Talents.csv |
| `brew_db.gd` | Brews.csv |
| `unlock_progress.gd` | "how close am I, and what is missing" |
| `match_report.gd` | what you gained this match |
| `match_camera.gd` | the view that follows the ball |
| `game_speed.gd` | 1x / 2x / 4x / 8x |
| `content_report.gd` | the startup report |

## `src/ui/` — the screens

`main_menu` · `class_select` · `team_builder` · `dialogue_view` ·
`base_screen` · `talent_screen` · `pub_screen` · `season_screen` ·
`match_stats_screen` · `unlock_board` · `save_inspector` · `card_popup` ·
`player_card_ui` · `duel_arena` · `rps_clash` · `shootout_view` ·
`star_badge` · `progress_row` · `new_unlocks_panel` · `match_hud` ·
`card_stats_panel`

Each screen is a `.gd` plus a `.tscn` of the same name.

## `src/units/` and `src/formations/`

`player_unit.gd` · `goalie_unit.gd` · `ball.gd` · `sprite_animator.gd`
`main_scene.gd` + `main_scene.tscn` + the `*_formation.tscn` files.

---

# 3. EVERY CSV, COLUMN BY COLUMN `SEARCH-CSV`

Every file lives in `res://data/`. The **identified by** column is what makes
the game recognise the file — the name does not matter.

| File | Identified by | What it holds |
|---|---|---|
| unit CSVs | `Unit Type` + `Base Power Left` | your cards |
| `Goalies.csv` | `Max Stamina` | keepers |
| `Abilities.csv` | `Ability ID` | what abilities do |
| `Animations.csv` | `Animation` + `Row` | spritesheet frames |
| `Tuning.csv` | `Key` + `Value` | every number in the game |
| `TierPowers.csv` | `Tier` + `Min Attack` | the power band per tier |
| `ClassInfo.csv` | `Class` | class names, blurbs, banners |
| `MenuConfig.csv` | — | main menu buttons |
| `Stats.csv` | `Counter` + `Event` | what gets counted |
| `Progression.csv` | `When` + `Do` | when things happen |
| `Season.csv` | `Match` + `Opponent` | the fixture list |
| `Buildings.csv` | `Action` + `Name` | the base |
| `Visitors.csv` | `Story` + `Name` | who is at the base |
| `Talents.csv` | `Tree` + `Effects` | the talent tree |
| `Brews.csv` | `ID` + `Becomes` | what the Pub pours |
| `Dialogue.csv` | `Scene` + `Text` | the story |

## Unit CSVs — your cards

| Column | What it does |
|---|---|
| **Name** | the card's name. Also the key for `goals_by_{card}` and per-card art |
| **Unit Type** | the class: `Lorelei`, `Brandteufel` |
| **Tier** | `I`, `II`, `III` or `IV` |
| **Base Power Left** | ATTACK power. Must sit in the tier's band |
| **Base Power Right** | DEFENCE power. Same |
| **Player Type** | `Star` or blank (= Normal) |
| **Attack Ability** / **Defend Ability** | an Ability ID, or blank for none |
| **Artwork** | spritesheet PNG in `assets/players/` |
| **Attack** / **Defend** | the printed prose on the card |
| **Element**, **Stufe**, **Tool**, **Card Number**, **Set Name**, **Created By** | flavour and bookkeeping |
| **Formation** | Stars only: which `*_formation.tscn` their team stands in |

## `TierPowers.csv` — the bands

```
Tier,Min Attack,Max Attack,Min Defense,Max Defense,Notes
I,0,2,0,2,
II,1,3,1,3,
III,2,4,2,4,
IV,3,5,3,5,
```

Change these and the game agrees with you next F5. **Delete the file and no
checking happens at all** — cards keep whatever numbers the CSV gives them.

## `Tuning.csv` — every number

Three columns: **Key**, **Value**, **What it does**. Do not rename a Key
unless you change the code too; everything else is yours. See `SEARCH-MATCH`,
`SEARCH-CAMERA` and `SEARCH-CONTROLS` for the ones worth playing with.

*(For the remaining files' columns see the section that owns them:
`SEARCH-STATS`, `SEARCH-SEASON`, `SEARCH-UNLOCKS`, `SEARCH-STORY`.)*

---

# 4. THE REQUIRES / DO LANGUAGE `SEARCH-GRAMMAR`

**One language, shared by every CSV.** Dialogue, progression, buildings,
visitors, talents, brews and fixtures all use exactly these words.

## Conditions — the `Requires` column

| Write | Means |
|---|---|
| `flag:met_lorelei` | that flag is on |
| `!flag:met_lorelei` | it is off |
| `unlocked:Brewery` | you have that unlock |
| `count:matches_won>=3` | at least three. Also `<=` `>` `<` `=` `!=` |
| `is:next_class=Lorelei` | that text equals that value |

Join with `;` or the word ` and `. **All of them must be true.**

```
unlocked:Brewery and count:matches_played>=5
```

Blank means "no condition" — always true.

## Effects — the `Do`, `Effects`, `Action`, `On Win`, `On Loss` columns

| Write | Does |
|---|---|
| `flag:brave` | switch a flag on |
| `clear:next_class` | empty a text |
| `count:coins+10` | add. `-5` subtracts, `=3` sets |
| `unlock:Brewery` | grant an unlock |
| `set:next_class=Lorelei` | remember a word |
| `story:prologue` | play that dialogue scene |
| `goto:base` | change screen |
| `announce:Well played` | put a line on screen |

Semicolons between several. The last three need the game running, so they do
**not** work in a fixture's `On Win` — put those in a Progression row.

**Screens `goto:` accepts:** `menu` `classes` `builder` `match` `story`
`base` `talents` `pub` `season` `stats` `unlocks` `inspector`.

---

# 5. THE SAVE `SEARCH-SAVE`

Four kinds of memory, and everything the game will ever need fits in one:

| Kind | Is | Example |
|---|---|---|
| **flag** | on / off | `first_win`, `season_champion` |
| **counter** | a number | `matches_won`, `talent_points`, `coins` |
| **text** | a word | `next_class` = `Lorelei` |
| **unlock** | a thing you own | `Brewery`, `The Cup` |

> An achievement is a flag. A resource is a counter. A building is an unlock.

It is written to `user://story_state.json` — **never** into your project
folder. The save inspector shows you the exact path.

**The name book.** Names are squashed to letters and digits for matching, so
`first_win` becomes `firstwin`. The first spelling used is kept alongside, so
screens can print "First Win" instead of "firstwin".

## Counters the game keeps itself

`season_match` `season_wins` `season_draws` `season_losses` `season_points`
`season_goals_for` `season_goals_against` `season_number`, and the flags
`season_over` `season_champion` `auto_pick`. Everything else comes from
`Stats.csv` or from a `count:` effect you wrote.

---

# 6. A MATCH, SECOND BY SECOND `SEARCH-MATCH`

```
kick-off
  │
  ├── 90 in-game minutes run
  │
  ├── PLAY MAKER  (x3)          ← the whistle. Everything stops.
  │     rock/paper/scissors → who attacks
  │     you pick one card per tier: I, II, III, IV
  │     four duels resolve, tier by tier
  │     the winner's side surges, relays, shoots
  │
  ├── HOLD UP     (between cycles)
  │     both sides swap their Star
  │
  └── FULL TIME → stats screen → season table → base
```

Three cycles, three PLAY MAKERs each, two HOLD UPs between them: eleven
pauses across the ninety minutes.

## A duel

1. The ball is relayed up to this tier's attacker.
2. Both power numbers appear.
3. The **lower** number has priority and fires its ability first.
4. Then the other.
5. The numbers settle and are compared. Higher wins.
6. A tie goes to the defender, unless `ties_go_to_attacker` is true.

Each duel you win banks (your power + the beaten card's power). The banked
total becomes the shot power at the end of the round.

## The numbers to play with

| Key | Default | |
|---|---|---|
| `match_length_minutes` | 90 | |
| `first_event_minute` / `last_event_minute` | 5 / 82 | when the pauses fall |
| `ties_go_to_attacker` | false | |
| `enemy_attack_chance` | 0.5 | enemy's odds of choosing ATTACK |
| `star_holds_its_tier` | **false** | see `SEARCH-FIXES` |
| `arena_speed` / `arena_skip_speed` | 1 / 6 | duel pacing, and hold-to-hurry |
| `verdict_seconds` | 1.4 | how long GOAL / MISS stays up |
| `goal_kick_tier` | `III` | who the keeper aims at |

---

# 7. CARDS, TIERS AND POWER `SEARCH-POWER`

A card's **Tier** says where it stands; its **power** says how good it is.
They must agree:

| Tier | Attack and defence |
|---|---|
| I | 0, 1, 2 |
| II | 1, 2, 3 |
| III | 2, 3, 4 |
| IV | 3, 4, 5 |

Held in `data/TierPowers.csv`. Anything outside its band is named in the
startup report and pulled back into range as the card loads.

**Stars** are ordinary cards with `Player Type` = `Star`. They are stronger
in practice because a class's Stars sit in a particular tier (Brandteufel
Tier III, Lorelei Tier IV), but they use the same bands and — since this
delivery — they are drafted and exhausted exactly like everyone else.

**Attack and defence are separate columns** and always have been. Everything
in combat goes through `get_attack_power()` / `get_defense_power()`, so the
day you want a 4-attack / 2-defence card it is two numbers in the CSV.

---

# 8. ABILITIES `SEARCH-ABILITIES`

`data/Abilities.csv`:

| Column | |
|---|---|
| **Ability ID** | what a card's Attack Ability / Defend Ability column names |
| **Display Name** | what the cut-away calls it |
| **Trigger** | `passive` `on_attack` `on_defend` `on_win_duel` `on_lose_duel` |
| **Effect** | `add_attack` `add_defense` `add_power` `add_shot_power` `drain_stamina` `restore_stamina` |
| **Value** | how much. May be negative |
| **Scope** | `duel` (this fight) · `round` (this PLAY MAKER) · `cycle` · `match` |
| **Target** | who it lands on |

**Priority: the LOWER power number fires first.** A tie goes to the attacker.

The cut-away shows the number lighting up, then the ability plate, then the
numbers changing — so a buff is always visible as it lands. A card with no
ability shows **"no ability"**, which is correct and not a fault.

**Your base cards mostly have none.** That is the design: abilities come from
brews. See `SEARCH-FIXES` for the four cards that do carry one.

---

# 9. MOVEMENT, QUARTERS AND THE BALL `SEARCH-MOVEMENT`

The pitch is four quarters, **mirrored**: each side's Tier I sits in its own
defensive quarter, so marking is by quarter, not by tier number.

Every unit is given one **role** each physics frame, centrally, in
`main_scene._assign_roles()`. A single unit cannot see how many team-mates
have already broken toward the ball; from up here it is four lines.

| Role | |
|---|---|
| `HOLD` | stay in your quarter |
| `MARK` | stick to your opposite number |
| `OPEN` | break off your marker to show for a pass |
| `PRESS` | charge the ball carrier |
| `BALL` / `DRIBBLE` / `RECEIVE` | on the ball |
| `SURGE` | run at goal after a won duel |
| `RECOVER` | chase back |

## The corridor

During waiting play the ball is fenced into quarters 2–3, so it never drifts
into either Tier IV's territory until a PLAY MAKER ends and a shot is on.
`ball_roam_quarter_first` / `_last` in `Tuning.csv`; set `1` and `4` to allow
the whole pitch.

## Numbers worth playing with

`press_radius_fraction` `press_helpers` `press_speed` `mark_distance`
`open_spread` `unit_chase_speed` `surge_advance` `surge_centring`
`surge_lead_seconds` `intercept_grace` `intercept_radius`
`zone_share` `zone_stretch` `zone_side_inset` `zone_tint_alpha`

---

# 10. THE CAMERA `SEARCH-CAMERA`

The view pushes in on the ball during live play, pulls out for the whistle,
the draft and full time, and gets tight on a shot.

| Key | Default | |
|---|---|---|
| `camera_enabled` | true | false = the old fixed view, nothing else changes |
| `camera_zoom` | 1.55 | **the one to play with.** Try 1.8 |
| `camera_zoom_close` | 2.10 | for a shot |
| `camera_follow_speed` | 3.2 | higher = snappier |
| `camera_zoom_speed` | 2.2 | |
| `camera_lead` | 0.30 | how far ahead of the ball it looks mid-pass |
| `camera_deadzone` | 36 | drift before it bothers to move |

**The thing to understand:** the camera never changes where players are
allowed to stand. The pitch is measured once, before the camera exists, and
the formations, the quarters and the corridor all keep using that measurement
forever. If the camera fed back into the play area, zooming in would squash
both teams toward the ball. It also never zooms out past the opening framing,
so you can never see past the edge of the grass.

---

# 11. SPEED, AUTO AND THE CONTROLS `SEARCH-CONTROLS`

A strip in the top-left of every match.

| Input | Does |
|---|---|
| the buttons, or `1` `2` `3` `4` | 1x / 2x / 4x / 8x |
| **hold `F`** | 20x for as long as you hold |
| `A` | toggle AUTO |
| **hold SPACE or the mouse** during a duel | run it at 6x |
| tap SPACE or click | latch the fast speed for that duel |

At 8x a full match takes about 11 seconds; holding `F`, about 4.5.

It works by setting `Engine.time_scale`, Godot's own global clock — which is
why nothing can be accidentally left out of it. Time returns to 1x at full
time and on every menu.

**AUTO** picks your cards at every PLAY MAKER and Star swap, so you can watch
a whole match without touching anything. Highest attack when attacking,
highest defence when defending; a Star breaks a tie. It is saved, so any CSV
can test `flag:auto_pick`.

| Key | Default |
|---|---|
| `game_speed_steps` | `1,2,4,8` |
| `game_speed_turbo` | 20 |
| `game_speed_start` | 1 |
| `auto_pick` | false |
| `auto_pick_seconds` | 0.9 |
| `card_hover_stats` | true |

---

# 12. THE SEASON `SEARCH-SEASON`

`data/Season.csv` — ten league fixtures and a final.

| Column | |
|---|---|
| **ID** | unique. Also how the result is remembered — do not rename after shipping |
| **Match** | the fixture number. Played 1, 2, 3… whatever order the rows sit in |
| **Opponent** | who you play |
| **Class** | which class they field. **Blank = random** |
| **Difficulty** | a flat power bonus to every enemy card, this fixture only. Keep it 0–3 |
| **Final** | `true` on the last one. Winning it makes you champions |
| **Requires** | optional. A fixture whose condition fails is skipped |
| **On Win** / **On Loss** | same words as Progression's `Do`. A draw gets neither |
| **Description** | one line, shown under the fixture |

The season screen does two jobs and works out which by itself: straight after
a match it shows the score and what you gained; opened from the base it is
just the table.

**Add a fixture:** bump the final's `Match` number, add a row above it, save,
F5. The report warns about a gap in the numbering, a duplicate ID, a missing
final, or a class no card belongs to.

---

# 13. STATS AND THE POST-MATCH SCREEN `SEARCH-STATS`

`data/Stats.csv` — the game reports plain **events**; every row says "when
this happens, add to this counter".

| Column | |
|---|---|
| **Counter** | the counter to add to. May contain `{facts}` |
| **Event** | `goal_scored` `goal_conceded` `duel_won` `duel_lost` `brew_drunk` `match_ended` `match_started` `shot_taken` `save_made` |
| **When** | optional filter: `result=win`, `margin>=3`, `power>=4` |
| **Amount** | how much. Blank = 1. **May be a `{fact}`** |
| **Group** | which panel of the post-match screen: `Goals` `Duels` `Keeper` `Match` `Brews`, or a new word |
| **Label** | what the screen calls it. Blank = the counter name tidied up |

## `{facts}` are the whole trick

```
goals_with_brew_{brew},goal_scored,,,Goals,,
```

One row, a counter per brew. A goal by someone who drank nothing has no
`brew` fact, so the row is simply skipped rather than making a counter called
`goals_with_brew_`.

**Facts each event carries:**

| Event | Facts |
|---|---|
| `goal_scored` / `goal_conceded` | class, tier, card, brew, star |
| `duel_won` / `duel_lost` | class, tier, card, brew, star, opponent |
| `shot_taken` | class, tier, card, brew, star, **power**, result |
| `save_made` | class, **card** (the keeper), **power**, **stamina** |
| `match_ended` | class, result, scored, conceded, margin |
| `brew_drunk` | class, tier, card, brew |

## Amount as a `{fact}`

```
keeper_stamina_spent,save_made,,{stamina},Keeper,Keeper stamina spent,
```

Adds however much that save actually cost, not 1. This is how "used 600
stamina" is counted.

## Where "this match" comes from

The match photographs your save at kick-off and again at the whistle. The
difference **is** this match. So adding a stat to the post-match screen is a
row in `Stats.csv` and nothing else — there is no list in any file to add it
to, and no code knows what a duel is.

`gains_max_rows` and `progress_bars_max` in `Tuning.csv` set how much shows.

---

# 14. UNLOCKS, TALENTS, BREWS, BUILDINGS `SEARCH-UNLOCKS`

## `Progression.csv` — when things happen

| Column | |
|---|---|
| **ID** | unique. Also how "Once" is remembered |
| **When** | `game_start` `menu_opened` `match_started` `match_ended` `base_opened` `story_ended` |
| **Requires** | the condition. Blank = always |
| **Do** | what happens |
| **Once** | `true` = fire once ever |

```
ID        chapter2_intro
When      match_ended
Requires  count:matches_played>=3
Do        story:chapter2;unlock:Brewery
Once      true
```

## `Buildings.csv` — the base

**ID · Name · Description · Requires · Art · X · Y · Action**

X and Y are fractions of the screen, 0 to 1. `Action` is what clicking does:
`goto:pub`, `announce:Text`, `unlock:x`, or blank for just the description.

## `Visitors.csv` — who is there

**ID · Name · Portrait · Requires · Story · Once · X · Y**

## `Talents.csv` — the tree

**ID · Name · Tree · Tier · Parent · Requires · Cost · Effects · Description · Art**

`Tree` is the column it appears in — a new word makes a new column. `Tier` is
the row. Taking a talent also unlocks **its own ID**, so a building's
`Requires` can name a talent directly.

`count:tune_press_speed+12` raises the `press_speed` row of `Tuning.csv` by
12. **Any tuning row works this way** — that is how a talent changes the game
without code.

## `Brews.csv` — what the Pub pours

**ID · Name · Description · Requires · For Class · Becomes · Artwork ·
Attack Ability · Defend Ability · Permanent**

A brew does not overwrite the card. It lays a thin overlay: the game reads
`active_unit_type()` where it means "what does this count as", and plain
`unit_type` where it means "what is this". **Roster building still uses the
real class**, so a Lorelei who drank a Fire Brew is still picked for your
Lorelei team.

A normal brew wears off at the whistle. A permanent one stays until you
remove it at the Pub. A one-match brew poured on top of a permanent one wins
for that match; the permanent one is still underneath.

**Per-card art:** a PNG called `<Card Name> <brew id>.png` in
`assets/players/` beats the brew's shared `Artwork`.

## The unlock board

**Base → Unlocks.** Every earnable thing, with a bar and exactly what is
missing. It follows the chain: the Pub's `Requires` is `unlocked:Pub`, which
is useless, so the board looks up what grants `unlock:Pub` and says
*"Pub, which needs Brewery, which needs goals with brew fire: 0 of 3"*.

Whether something is **done** is decided by the same call the game makes, so
the board can never disagree with what actually happens.

---

# 15. DIALOGUE AND STORY `SEARCH-STORY`

`data/Dialogue.csv`:

**Scene · ID · Speaker · Text · Requires · Effects · Goto · Choice 1 …**

A `Scene` is one conversation. `story:<scene>` plays it, from a Progression
row, a building's Action, or a visitor.

Dialogue **only** happens when something asks for it. There is no launch
dialogue; the prologue is a Progression row that fires the first time you
open the base, and deleting that row removes it.

---

# 16. SCREENS, AND HOW TO REDESIGN ONE `SEARCH-SCREENS`

Most screens build their layout in code. **Three do not, and they are the
pattern to copy:** `season_screen`, `match_stats_screen`, `unlock_board`,
`save_inspector`.

> **The `.tscn` decides what it looks like. The `.gd` only puts words into it.**

Open `src/ui/season_screen.tscn` in Godot, move the panels, change every font
and colour, drop in a background, press F5. It still works, because the
script never says where anything is — only "put this text in the node called
`Title`".

**The rules:**

- **Do** move, restyle, re-parent, add art
- **Do not** rename the nodes the script fills
- Leave "Access as Unique Name" (the `%` icon, right-click a node) **on**
- Lists that rows get added to must stay `VBoxContainer`s

Delete one by accident and nothing crashes: the Output panel names the
missing node and the rest of the screen still draws.

**The nodes each screen fills** are listed in a comment at the top of its
`.gd`. Open the file and read the first forty lines.

---

# 17. ART `SEARCH-ART`

| Folder | What goes in it | Named |
|---|---|---|
| `assets/players/` | card and unit spritesheets | the `Artwork` column |
| `assets/players/` | brewed art | `<Card Name> <brew id>.png` |
| `assets/goalies/` | keeper art | the Goalies.csv column |
| `assets/base/` | `background.png`, one per building | the `Art` column |
| `assets/portraits/` | visitors | the `Portrait` column |
| `assets/menu/` | class banners | ClassInfo.csv |

**Everything is optional.** With no art you get a labelled plaque for a
building and a big letter for a visitor, so you can lay the whole base out
and play it before drawing anything.

`Animations.csv` says which row of a spritesheet is which animation:
**Unit Type · Animation · Row · First Frame · Frames · Loop · Sheet Columns**.
The scenes ask for `run`, `ability`, `win`, `idle`, falling back to a still
frame — so a half-drawn sheet still works.

---

# 18. THE TOOLS `SEARCH-TOOLS`

Both live in `tools/`, **not** in `data/` — that is the only reason they need
no Godot import step. Double-click either; they open in your browser, and
nothing leaves your computer.

## `csv_workbench.html` — the visual CSV editor

Drag CSVs on (several at once become tabs). Hover a column heading and it
tells you what that column does. Broken cells turn red with the reason on
hover. **Save CSV** writes it back out correctly quoted — which is the thing
Excel and Numbers most often get wrong here, because a comma inside a
Description splits the row.

It identifies files by their columns, like the game does, and checks the
grammar, duplicate IDs, `goto:` targets, numbers that are not numbers,
X/Y outside 0–1, and gaps in the season's fixture numbering.

**It does not replace the startup report** — the report sees across files
("this scene does not exist"), the tool sees only the file in front of it.

## `content_map.html` — the picture

Drag in everything from `data/`. One picture of what unlocks what, left to
right. **Save PNG / Save SVG.**

Red = a requirement nothing in your CSVs ever provides. Dashed = a loop where
two rows require each other. Counters that gate nothing are left out; the
button in the corner puts them back.

## The save inspector — **Base → Dev**

The top row is the point: **one button per locked thing**, closest first.
Press "Pub 80%" and your save jumps to exactly the state where you have it.
Below: every counter with `-1 +1 +5 0`, every unlock and flag with "take
away", and a box where you can type any name and set it.

`show_dev_tools` → `false` in `Tuning.csv` hides the button before a demo.

---

# 19. RECIPES `SEARCH-RECIPES`

**Add a card** — a row in a unit CSV. Name, Unit Type, Tier, the two powers
inside the band, and Artwork if you have it. Save, F5.

**Add a class** — give cards a new `Unit Type`, add a row to `ClassInfo.csv`,
make sure at least one card has `Player Type` = `Star`.

**Add an ability** — a row in `Abilities.csv`, then put its ID in a card's
Attack Ability or Defend Ability column.

**Change how hard a fixture is** — the `Difficulty` column in `Season.csv`.
0–3. It is a flat power bonus to every enemy card, that fixture only.

**Add a fixture** — bump the final's `Match` number, add a row above it.

**Add a building** — a row in `Buildings.csv`. `Requires` decides when it
appears; `Action` decides what clicking does.

**Make a talent unlock a building** — the talent's `Effects` say
`unlock:Cup Room`; the building's `Requires` says `unlocked:Cup Room`. Or
point the building straight at the talent's ID.

**Add an achievement** — a Progression row whose `Do` is `flag:something`.
It appears on the "what you gained" panel and the unlock board on its own.

**Count something new** — a row in `Stats.csv`. Give it a `Group` and it
appears in that panel of the post-match screen.

**Make the game faster to test** — hold `F`, or press AUTO, or use the save
inspector's jump buttons.

**Change the camera** — `camera_zoom` in `Tuning.csv`. Try 1.8.

**Turn something off** — `camera_enabled`, `duel_arena_enabled`,
`shootout_enabled`, `zones_enabled`, `card_hover_stats`, `show_dev_tools`.

---

# 20. WHEN SOMETHING BREAKS `SEARCH-TROUBLE`

## A new CSV does nothing / ships empty

**This is the one that will bite you every time you add a CSV.** Godot
imports a `.csv` as a translation file. It works in the editor and ships
empty.

1. **FileSystem** panel (bottom-left)
2. Click the CSV once
3. **Import** tab (top-left, next to Scene)
4. **Import As** → **Keep File (No Import)**
5. **Reimport**

Also, once: **Project → Export → Resources → Filters to export** → add
`*.csv`.

**Do this now for `TierPowers.csv`.**

## "The function signature doesn't match the parent"

You named a function something Godot already owns. `_set` `_get` `_draw`
`_init` `_ready` `_process` `_input` `_notification` `_to_string`
`_gui_input`. Rename it. If a name starts with an underscore and then an
ordinary word, assume Godot has taken it.

## "Parent node is busy adding/removing children"

Something changed scene during `_ready()`. Always change screen through
`ScenePaths.go_to()`, which defers it.

## A condition never becomes true

Open the **unlock board** (Base → Unlocks) and read what it says is missing.
If it says "needs X" and nothing grants X, the startup report will have said
so too, and the content map will show it in red.

## A card's power is not what the CSV says

Read the startup report. If the number is outside the tier's band it was
pulled into range and the report names the card and the column to fix.

## The card that fought is not the card I picked

Read the per-round line in the Output panel — it prints the exact four cards
and their powers for both sides, every round.

## Where is my save?

The save inspector prints the full path under its title.

## Nothing works and I want to start clean

Save inspector → **Wipe the save** (two presses).

---

# 21. RULES FOR WRITING GDSCRIPT HERE `SEARCH-CODE`

If you or anyone else adds code, these are the traps this project has already
hit:

1. **Never name a function after a Godot method.** See `SEARCH-TROUBLE`.
2. **`Dictionary.get()` returns Variant.** `var x := d.get("k")` is a hard
   error. Write `var x: String = d.get("k", "")` or `String(d["k"])`.
3. **Tabs, not spaces.**
4. **`class_name` is global.** A script's folder does not matter to Godot,
   only to human sanity.
5. **Change scene with `ScenePaths.go_to()`**, never
   `change_scene_to_file()` directly.
6. **Find nodes with `find_child(name, true, false)`**, not
   `get_node("Name")` — `get_node` only looks one level down, and that is
   what crashed the season screen.
7. **The game decides what is unlocked, once.** Anything that displays
   progress asks `DialogueGrammar.test()`; it never works it out for itself.

---

*Everything in this document was checked against the CSVs in the repo. Where
a number is quoted — 61 things on the content map, 11 seconds for a match at
8x, three different Tier IV cards per cycle — it was measured, not estimated.*
