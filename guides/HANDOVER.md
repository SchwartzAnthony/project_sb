# Sturmball (Project SB) — handover to a new session

Written by Claude for the session that picks this up. **Read this first, then
`guides/DESIGNER_MANUAL.md`** (32 sections, the full reference) and
`guides/PHASES.md`. Everything below is accurate as of the repo commit
`3575bba "Referee"` plus the zip this file arrived in.

---

## 1. Who and what

**Anthony Schwartz** (`schwartzanthonyj@gmail.com`) is a game designer, not a
programmer. He does design, art, music, story, items and achievements; Claude
writes the code. He will give Claude full credit when he takes this to a
studio. He is warm, generous and works in long rounds.

**Sturmball** is a CSV-driven football autobattler in **Godot 4.7**. Theme:
**Bavarian mythology and Oktoberfest brewing, while playing football.** Art
direction: **1970s–90s European comic, the Marcinelle school** (Asterix,
Franquin, Motomania, *Kleines Arschloch*) — rendered as pixel art (see §9).

**Repo:** `https://github.com/SchwartzAnthony/project_sb` (public, readable
with plain `git clone`). He pushes after applying each zip.

### His standing instructions — repeated in every message, honour all of them

- Code for a non-coder: **data in CSVs or files in folders**. Every
  file and folder designed to be used and extended by a game/system designer.
- **Godot 4.7.**
- Use the GitHub repo.
- **Clear, concise guides** he can follow alone later without asking again.
- **Tell him your questions, concerns and suggestions.**
- **Zips mirror the Godot project's folders**, so he copies them straight over.
- **Only changed files go in the zip.** No identical re-sends.
- **Run the game yourself** and test for errors, inconsistencies and ways to
  improve player engagement.
- **Final reminder, every round:** update **all impacted CSVs**, **the
  workbench** (`sturmball_workbench.html`), and **the DESIGNER MANUAL**.

### How a round is delivered

1. A zip of changed files only, mirroring the project folders.
2. A `READ ME FIRST.md` at the top of the zip: what he asked, what was built,
   what the tools measured, what's still open, and **questions + suggestions**
   at the end.
3. A short chat reply. He reads the README; the chat is a summary.

Use `AskUserQuestion` before large rounds when a design choice is genuinely
his. Put a recommendation first and give a concrete preview per option. He
has accepted the recommended option every time, but he likes being asked.

---

## 2. Things that have bitten this project — read before writing GDScript

| trap | rule |
|---|---|
| **THE TYPED-ARRAY RULE** (cost five rounds) | `for x in ["a","b"]` makes `x` untyped, so `var y := x + z` won't compile. A bare `[...]` or `a if c else b` over two literals is an untyped `Array`, and assigning it to `Array[PlayerData]` / `Array[Vector2]` **fails silently at runtime**. Always declare `var list: Array[String] = [...]` first. |
| **Every `.csv` needs a `.csv.import`** | Three lines: `[remap]`, a blank line, `importer="keep"`. Without it Godot turns the CSV into translation tables and litters the folder. `tools/csv_import_fix.gd` writes missing ones. **His repo has 26 stray `.translation` files in `data/tutorial/` to delete.** |
| **Tabs, never spaces** | Lint with `tools/gd_lint.py`. It has 5 known false positives (continuation lines in ability_engine, referee, class_select, class_tree_check, shape_check). |
| **A new `class_name`** | Run `--import` before `--check-only`, or `X.new()` inside the class itself reports "Identifier not found". |
| **Don't shadow a variable** | e.g. two `var bits` in one function — parse error. |
| **Workbench parts are JS template literals** | A backtick anywhere inside CSS or HTML strings ends the string and breaks the whole page silently. |
| **Workbench global names** | `TIERS` and `esc` already exist (schema/engine); the wizard uses `WIZ_TIERS` / `wizEsc`. Check before adding globals. |
| **Silent failures are the enemy** | Every loader complains *by name* in the Output panel. An unknown action term in any `Do`/`Action` column is now printed loudly (round U). Keep that standard. |
| **A tool must press the real button** | Screenshot tools that call internal functions directly can't catch broken buttons (the round U lesson). |

### Verifying, every round

```
godot --headless --path <proj> --import                        # 0 errors
godot --headless --path <proj> --check-only --script res://X.gd   # every .gd
python3 tools/gd_lint.py $(find src tools -name "*.gd")
godot --headless --path <proj> --script res://tools/<check>.gd    # each checker
godot --headless --path <proj> --script res://tools/match_soak.gd       # "NO TROUBLE"
godot --headless --path <proj> --script res://tools/adventure_soak.gd   # "NO TROUBLE"
xvfb-run -a godot --path <proj> --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/<x>_shot.gd     # screenshots land in user://
```

**Checkers that should say ALL GOOD:** season, rooms, shop, brewery,
shot_odds, theme, out_of_bounds, celebration, foul, achievement, class_tree,
referee. `class_check` and `emblem_check` currently list **genuine unwritten
content** (§11), not faults. `lane_check` and `recovery_check` speak in
sentences. `recovery_check` correctly says to keep recovery OFF.

---

## 3. The rules nothing may break

**The tier ladder.** Four tiers. Each holds **exactly one card of each power
in its span**, never two the same:

```
   Tier I  0·1·2     Tier II 1·2·3     Tier III 2·3·4     Tier IV 3·4·5
```

A card's power is its **slot, not a stat**. Every legal team has the same
total power. **A bonus never goes on a card** — combos, difficulty, talents
and trait breakpoints all go on the **shot**. A red card leaves a hole, which
is filled by a **stand-in**: a surviving tier-mate copied at the missing
power, with no abilities (`FoulBook.stand_in_for`).

**The condition language** (`src/core/dialogue_grammar.gd`), used in every
`Requires` / `Do` / `Action` / `Effects` / `Reward` / `Turns On` column:

```
   Requires:  flag:x   !flag:x   unlocked:Name   count:c>=10   is:state      ";" = AND
   Do:        unlock:Name   flag:x   flag:x=false   count:c+10   count:c=0
              sign:Name   release:Name   count:tune_<TuningRow>+n
```

`count:tune_<row>+n` **edits a Tuning.csv row** for as long as the source is
held — that's how talents work. **Unlock spelling is flattened** (lowercase,
letters and digits only), so `Master Brewer` == `master_brewer`.

**Four DEFERRED actions** open something, so they're handed back to the
calling screen instead of written to the save: `story:`, `goto:`,
`announce:`, `window:`. The list is `Progression.DEFERRED`.

**A card is identified by its Name**, including inside saves; renaming breaks
saves. **A Star is `Name#CardNumber`** (`ClassTree.star_key`).

**Every system follows the same shape:** a CSV, a loader that reads it and
complains about it, a screen that shows it, and a **tool that measures it in
units a designer can feel** (goals per match, bottles per season, prices in
wins, rooms in seasons, the race in duels, the referee's miss rate).

---

## 4. Folders

```
data/      73 CSVs. His half of the project. Everything the game is made of
assets/    ui/ (the nine-slice skin), players/, field/, icons/, base/,
           portraits/, menu/, team/, backgrounds/, fonts/, audio/
src/core/      loaders and rules (~70 files)
src/ui/        screens (~45)
src/adventure/ Adventure mode
src/formations/main_scene.gd   THE MATCH. Very large; edit surgically
src/units/     player_unit, goalie_unit, ball, name_plate
tools/     49 .gd measuring tools + make_chrome.py + gd_lint.py
           + workbench_src/ (the workbench's parts and build.sh)
guides/    DESIGNER_MANUAL.md · PHASES.md · WHAT_A_FOOTBALL_GAME_NEEDS.md · this file
sturmball_workbench.html   the CSV editor (§10)
```

`data/FileManifest.csv` lists every file with a plain-words description.
**Add a row for every new file.**

---

## 5. The systems, one line each

| system | data | code | measured by |
|---|---|---|---|
| Cards, tiers | unit sets, `TierPowers.csv`, `Animations.csv` | card_database, player_data, tier_ladder | class_check |
| League match | `Tuning.csv` (350 rows), `Combos.csv`, `Abilities.csv`, `ShotOdds.csv`, `OutOfBounds.csv`, `Celebration.csv` | formations/main_scene | match_soak, scoring_balance, movement, lane |
| Fouls + cards | `Fouls.csv` (did one happen) | foul_book | foul_check |
| **Referee** | `Referee.csv` (did he see it) | referee, ui/ref_bar, ui/ref_window | referee_check, ref_shot |
| **Emblems** | `<Class> Emblems.csv`, `Star Players.csv` | class_book (reads), emblem_book (rules), ui/emblem_bar | emblem_check |
| Class tree | `ClassTree.csv` | class_tree, ui/class_tree_screen | class_tree_check |
| Talents | `Talents.csv` | talent_db | — |
| Achievements (root of all unlocks) | `Achievements.csv`, `Stats.csv` | achievement_book, stats_rules | achievement_check |
| Progression / story | `Progression.csv`, `Dialogue.csv`, `Visitors.csv` | progression, dialogue_* | — |
| The base (9 buildings, windows over the base) | `Buildings.csv` | ui/base_screen, ui/base_window | base_shot (presses real buttons) |
| Rooms | `Dorms.csv`, `Trophies.csv`, `Training.csv` | base_rooms, ui/room_screen | rooms_check |
| Brewery | `BrewerySections.csv`, `BreweryResources.csv` | brewery_book | brewery_check |
| Pub + brews | `Brews.csv` | brew_db, ui/pub_screen | — |
| Traveling Brewer (shop) | `Shop.csv`, `Currencies.csv` | shop_book | shop_check |
| Seasons | `Season.csv`, `Seasons.csv`, `SeasonRules.csv` | season_* | season_check |
| Adventure | `Adventure*.csv`, `Biomes.csv`, `Drops.csv`, `Pickups.csv`, `Bounties.csv` | src/adventure/ | adventure_soak |
| Squad ownership | `squad_ownership` (OFF) | squad_book | — |
| Recovery / tiredness | `Recovery.csv`, `recovery` (OFF) | recovery_book | recovery_check |
| **Dev mode** | `dev_mode` (OFF) | dev_mode + pause menu + red strip | — |
| Look | `Theme.csv`, **`Motion.csv`**, `Juice.csv`, `Stadium.csv` | theme_book, **motion_book**, juice | theme_check |
| Art pipeline | **`ArtOrders.csv`** | **tools/make_chrome.py** | — |
| Generator vocabulary | **`UnitActions.csv`**, `Elements.csv`, `Keywords.csv` | workbench wizard | — |

---

## 6. The four classes — one per element, all written

| class | element | Stars (Goetia demons) | Star tier | sets cover | tokens |
|---|---|---|---|---|---|
| **Lorelei** | WATER | Gremory, Zepar, Sallos | II | I·III·IV | Rose Unit · Swan · Song counter |
| **Rauhnacht-Feuergeister** | FIRE | Belphegor, Flauros, Buer | IV | I·II·III | victory counter · fused unit · Teufel Mask |
| **Bergmännlein** | EARTH | Belial, Valefor, Haures | III | I·II·IV | Ore (all three) |
| **Unkengeister** | AIR | Vassago, Glasya-Labolas, Caim | II | I·III·IV | — · cold touch · gravestone |

**A class is 30 cards:** 3 Stars holding one whole tier (one power each) in
`Star Players.csv`, plus **3 sets of nine** in `Unit_Set_<Class>.csv`, each
covering the other three tiers three cards apiece. **You field 12**: three
Stars, plus one tier's worth from each set ("divided into 3 players each"),
which leaves 18 on the bench.

**Gremory's nine are the Sitri set.** That's correct. The `Set` column says
which set answers for which Star, and the code no longer assumes they share a
name. Emblem rows are named `"Gremory's Emblem"`; the code finds them by
either name (`ClassEntry.aliases`). **Never make him rename.**

Also present: `Normal` (BasicTeam, Stars Tier IV), `Rivals` (locked), and
**`Brandteufel`** in `example_unit_csv_with_ability_columns.csv`. Brandteufel
is probably the retired ancestor of Rauhnacht-Feuergeister. **Unresolved —
ask him.**

---

## 7. Emblems (round V) — decided

- **A Star carries its Emblem onto the pitch.** Emblems are no longer bought
  in the tree.
- **A race:** all three collect on their Basic side, the **first** to meet its
  Condition turns over, and the other two are **held** (`emblem_race`).
- **Element feeds Basic, class fulfils the Condition.** Any water unit feeds a
  Lorelei Emblem's Basic side; only Lorelei can complete its Condition. The
  Condition rule can't be loosened by a column (`EmblemBook.feeds_condition`).
- **A goal resets the race** (`emblem_reset_on_goal`).
- **Both faces flip together:** the Emblem turns over *and* the Star shows its
  `Ultimate Side`. **A Star has one ability** (`Front Side`, which the loader
  fills into both attack and defend). **Hover always shows the Ultimate.**
- **Progress is read out of `Turns On`** (`count:x>=n`), not stored in a
  column of its own.
- **The tree** = three set nodes → an **Element node** (`Open Water`, which
  lets other classes of your element play) → Team Spirit. `Emblem Cost`
  became `Element Cost`.
- `emblem_check` prices the race in duels and flags the spread. **Buer needs 8
  where Belphegor needs 4**, so Buer's Ultimate will almost never be seen.
  Flagged, not changed — it's his prose.

**The workbench's "+ New class" wizard** walks Emblem → Ultimate → Star → nine
units, three times, rolling unit abilities from `UnitActions.csv` (a trigger
plus an effect, with `{token}`, `{tier}`, `{element}` and `{n}` filled in).
It writes four files at once.

---

## 8. The referee (round W) — decided

A foul is **two questions**. `Fouls.csv` decides whether one *happened*
(unchanged, driven by triggers that round). `Referee.csv` decides whether
**he saw it**. **Unseen fouls cost nothing** — no card, no free kick.

- Each side has a bar of `Segments` (1–5). Triggers add `Fill Per Trigger`;
  an **unseen** foul adds `Fill Per Foul` (more).
- Chance of being seen: `Caught Per Segment` × lit segments. Once the bar is
  full it's `Caught When Full`. **Once booked**, `Caught After Yellow` replaces
  both.
- **Red comes from yellows:** `Red Per Yellow` × that side's bookings is the
  chance a *yellow* becomes a red. Zero bookings means no bump. (The first
  wiring double-rolled red, giving 297 yellows to 204 reds; `referee_check`
  caught it. It's now 393:131.)
- He slides in from the left with the card held up (`ref_window.gd`). The card
  is drawn, not an image file. The portrait slot (`ref_default`) has no art
  yet. **No pop-up for an unseen foul.**
- **League only.** Three refs ship: `*`, `lenient` and `strict`, chosen by
  `referee_id`.
- **Finding:** about 0.5 cards per match. That comes from the Fouls.csv curve,
  not the referee — see §12.

---

## 9. Art direction and PixelLab

**PixelLab makes pixel art; Marcinelle is brush and ink.** The game is
already pixel art (96×96 nine-slice UI, 128×64 sprite cells, NEAREST
filtering everywhere), so the decision was to **keep the medium and borrow
the language**:

> heavy 1px pure-black outline · flat fills, 2–3 tones, no gradients ·
> exaggerated silhouettes · warm limited palette · **ONE hot accent** ·
> slight hand-wobble

**The palette is already in `Theme.csv`:** accent `#f2b33d` (beer gold, the
only bright colour), background `#19110a`, panel `#3a2415`, text `#f3e8d4`
(cream, never white), attack `#dd6f24`, defend `#5a93cc`. Tier colours are
deliberately muted.

**`data/ArtOrders.csv`** lists 14 PixelLab jobs in order, each with tool,
size, prompt, palette and what to do with the result:

- **Pass 1 (1–7) — APPROVED by Anthony.** The nine-slice chrome: panel,
  window, button / hover / pressed, slot, bars. **Do order 1 (the panel)
  first.** Look at it in the game, then pass it as `style_image` to all the
  rest so they read as one set.
- **Pass 2 (8, 10, 11).** Title wallpaper (**480×270**, exactly ×4 to
  1080p), the base yard (centre left empty for the buildings), **the pitch**
  (2560×1440, lines inset 6% / 10%). The current pitch is 1000×667 — the
  biggest single visual win available.
- **Pass 3 (12, 13).** The referee, and the twelve emblems (drawn at 56×56, so
  each needs one strong shape).

**Nine-slice rules:** detail only in the corners, inside the slice border
(panel/window/slot **28**, button **26**, bars **10**). The centre stays flat,
or it smears when stretched. **Check returned art for this first.**

**`tools/make_chrome.py`** (this round) draws all seven chrome files from the
Theme.csv palette with Pillow. They're placeholders in the right style that
he can edit, and they're in this zip. PixelLab output replaces them file for
file.

**This session couldn't reach PixelLab.** The cloud sandbox blocks
`api.pixellab.ai`. The new Desktop session has it working (Tier 2, 5,000
generations, resets 1 Nov 2026). He pasted his API key into an old chat and **rotated it in round AH**.

---

## 10. The workbench (`sturmball_workbench.html`)

A single offline HTML page. He loads his `data/` folder into it. Pages down
the left: **Where things go** (live list of assets the CSVs ask for), **Art &
sizes** (40 asset kinds, sizes measured from the game, ticks), **Handbook**
(15 cards of rules), **Reference**, **Keywords**. The header has **+ New
class** (the wizard). Every file gets schema help text and a checker.

**Source is in `tools/workbench_src/`.** Edit the parts, then run `build.sh`.
The order matters: `head, part2, part2b_seed, part3_schema, part4_engine,
part6_guide, part7_wizard, part5_tail`. Per-file help lives in
`part3_schema.js`; the Handbook in `part6_guide.js`; the wizard in
`part7_wizard.js`. `real.mjs` and `wiz.mjs` are Playwright tests — fix their
hard-coded `/tmp` paths and Chromium path before using them. Six known
checker notes are expected (Normal class has no adventure cards, Brandteufel
has no ClassInfo row, four biome music rows missing from Audio.csv). Google
Fonts fail offline, which is fine.

---

## 11. Known gaps (content, not faults)

- **Six Ultimate Sides unwritten** (all of Bergmännlein and Unkengeister),
  plus **Vassago's Token**.
- **Emblem counters are named but not wired.** `Stats.csv` rows like
  `lorelei_swans_made` and `unken_gravestones` have a placeholder `Event`, so
  the bars read 0/n until wired to real match events.
- Two unlocks nobody tests (`Emblems`, `Trophy Case`). Eleven sounds have no
  file (`SOUNDS_WANTED.csv`). Four buildings have no art. `recovery` is OFF on
  purpose (needs six players per tier).
- `data/tutorial/*.translation` — delete them.
- Brandteufel: is it still a class?

---

## 12. Round X — DONE (delivered from the Desktop session with PixelLab)

**PixelLab works in the Desktop session** (tools appear as
`mcp__remote-devices__pixellab__*`). Tier 2, 5,000 generations, resets 1 Nov.
About 185 were spent on Pass 1. (The key from the old chat was rotated in
round AH.)

**Built:**

- **Pass 1 chrome from PixelLab**, all eight files. The UI tool returns a
  SHEET, so `art_source/pixellab/` keeps the sheets and
  **`tools/cut_chrome.py`** cuts them, following new `Sheet` / `Cut` /
  `Finish` columns in ArtOrders.csv. It reproduces the shipped files
  byte-for-byte. `make_chrome.py` now refuses to overwrite PixelLab art
  without `--placeholders`. Theme.csv got a **`Repeat`** column (`tile`) for
  the beer mat's lozenges. Lesson: **the panel is TINTED by every screen and
  tint multiplies** - dark art goes black. It is lifted light on purpose.
- **Names.** `data/Names.csv`, `name_book.gd`. The 108 `Unit Name` cards now
  have unique German first names (Johannes kept free for a recruit).
  Workbench flags duplicate names and `Unit Name`; the wizard names units.
- **Recruits.** `recruit:I0`, `recruit:I0=Johannes`, and `release:` frees the
  name. `recruit_book.gd`, behind **`named_recruits`** (false).
- **Three beers.** `Drinks` column in Brews.csv; four `turn_*` rows;
  `transform_book.gd`. He chose: **pick the set** at the last beer, **a new
  element restarts** the count, and it works on BasicTeam plain cards today.
  Stored as `drinks_<name>` / `became_<name>` (the role card's Name).
- **Repeat offender.** `Caught Per Own Foul`, `Card Per Own Foul` in
  Referee.csv; `Referee.fouls_by/record_foul/card_bump`.
- **Leaning on the ref.** `add_card_chance` effect + `Max` column in
  Abilities.csv; Karl (Bergmännlein, Belial, I P2) carries
  `BERG_ORE_WHISPER`. Talent door: `foul_card_bonus_enemy/_you` in Tuning.
- `round_x_check.gd` (ALL GOOD), `pub_turn_shot.gd` (presses real buttons),
  `match_soak.gd` race fixed (match could finish between polls).

**Findings handed to him as questions:**

1. Each class has one tier owned by its Stars, so a plain player of that tier
   cannot turn (Lorelei/Unken II, Feuergeister IV, Bergmännlein III).
2. Fouls are ~1.4 a match over 12 men, so the repeat-offender rule fires
   ~2 times per 1,000 matches and Karl's card adds ~9 yellows per 1,000 SEEN
   fouls. Both correct, both nearly invisible until Fouls.csv is raised (x2 =
   0.94 cards a match per side) or the Yellow share lowered.
3. The set cards' abilities are prose; only Ability-ID rows run. Ore has no
   counter in a match yet.
4. The Pub lists Rivals (enemy) cards under YOUR CARDS - pre-existing.

## 12b. Round Y — DONE

**His answers:** a team is **12** (3 Stars + 9) and must exist, with its class's
Stars placed, before the Pub or any match; Stars gate the set cards; the
Talent Tree building became **Team Build** (Star Hall / Your Teams /
Talents); option (a) for tiers that cannot turn; fouls "do what you think"
(doubled); **no PixelLab until further notice**; the focus is now **every
ability, emblem and star working as written**. Pin the other suggestions and
remind him once the combat system is complete (listed in guides/PHASES.md).

**Built:** `team_build.gd` + `team_build_screen.gd` (gate at the Pub door,
Play a match, The season, the team shelf's LOCK IN; first 3 Stars free via
`team_build_free_stars`); button re-cut from the slim PixelLab plaque (slice
12) because the big plaque's rule crossed text on short buttons; Fouls.csv
x2 (~1 card/match/side).

**The combat plan:** `guides/COMBAT_PHASES.md`. `tools/ability_audit.py`
reads all 276 texts into When/If/Cost/Do/Target/Value/Scope/Max ->
`data/AbilityAudit.csv` + `data/AbilityRulings.csv` (F1-F4 + R01-R17, answers
preserved on re-run). **Phase C1 built**: zone book (field/combat/exhaust,
contemplation/rejuvenation), moments (match_start, round_end, end_of_cycle,
while_in_exhaust, after_duel, on_shot, goalie_save, on_goal, on_concede),
`If` column, next_ally/next_enemy/next_self/ally: targets that WAIT, Max
1/cycle, one side per duel (`ability_uses_role_side`), multi-ID cells.
`tools/ability_rows.py` writes `data/CardAbilities.csv` (C_ IDs) from every
reading whose phase is in BUILT_PHASES and wires the card cells.
`ability_coverage.gd`: 33/228 work. `ability_check.gd`: 40/40 fire right.

**Next: C2** (counters, tokens, Ore pool) — add "C2" to BUILT_PHASES in
ability_rows.py when built, re-run both scripts. Answer-dependent: R12 (Ore).

## 12c. Round Z — DONE (phase C2)

**His answers:** all of F1-F4 and R01-R17 in `data/AbilityRulings.csv`
(summarised as a table in guides/COMBAT_PHASES.md §3). The big ones: **Exile =
Exhaust** (R14 - every card text changed, no exile zone); "next" = **the next
unit played** (R03 -> new target `next_tier_ally`); one Ore pool per side
(R12); F3 wants a pending-buff window and an ask-after-pick reveal; F4 wants
priority / +- power bubbles; F2 and R17 want the PLAYER to choose (screens -
C5). He also said yes to "each Star only fits its own set's node". He wants
**in-depth questions** every round, and asked for the next phase each time.

**Built (C2):** counters on cards (`_counters`, keyed card+side - the engine
keys EVERYTHING by `_k(card, side)` now because both teams can field the same
resource), side pools (`_pool`: ore, victory), the **Cost** column (`ore:N`,
paid after the Max check, before the effect; unpaid = did not happen),
tokens (`_make_token`: duplicate PlayerData with `extra_tags` ["rose","token"],
original HELD in exhaust; the match re-cards the body via `take_swaps()` and
reverts `all_swaps()` at full time BEFORE the squad is read), swans
(`_kinds`), `on_counter` and `after_combat` triggers, `next_tier_ally`,
`replace:<filter>` / `side` targets, Max `1/round` and `/side`, conditions
has_counter / enemy_has_counter / has_token / tokens_at_least / is_swan /
is_token / ore_this_round / ore_at_least / element / exhausted_this_round.
**Emblem Basic Ability column** -> EMB_ rows in Abilities.csv fire for every
card that feeds the emblem (Gremory, Zepar, Sallos, Belphegor, Buer). Engine
`events` -> main_scene `_absorb_ability_news()` -> Stats.csv events
(token_made, swan_made, counter_placed, ore_gained, ore_spent, emblem_basic)
for the player's side, which fills the Emblem conditions. UI: `MatchTracker`
(src/ui/match_tracker.gd), card marks strip + emblem SHOW
(`PlayerCardUI.set_marks/allow_show`), duel window `(+1)` and priority line.
Star Hall: `ClassTree.fits()` (emblem Set column decides; `star_fits_own_set_only`).

**Audit changes:** two-part sentences split at ". If this wins" with a When per
part (ability_rows takes When/If/Cost per part); answered questions no longer
mark a row "needs your ruling"; R18 added (attack power = combat power).
BUILT_PHASES = C1, C2. Coverage **103/228**. ability_check **125 + 5 emblem
stories**. Soaks: `SOAK_CLASS=Lorelei` env var picks the class.

**Next: C3** (keeper % / shield / foul heat / foul chance / coin flip). Then C4.

## 12d. Round AA — DONE (phase C3 + the choices)

**His answers to round Z:** swans count as tokens; Rose tokens last until a
goal; the PLAYER picks which unit becomes a Rose, is asked before Ore is
spent and before a Swan transformation; priority and power are two numbers
(show priority when power moved); F2 side choice once per cycle; Gremory
must be comfortably usable once. He swapped Buer/Belphegor Set Names in
Unit_Set_Rauhnacht_Feuergeister.csv - BUT HIS FILE WAS AN OLD COPY: every name
was "Unit Name" and the ability-ID columns and my exile->exhaust edits were
gone. I merged by row: his Set Names and his "(once per cycle)" additions on
the Sitri cards kept, names / exhaust wording restored, ID columns re-added
by ability_rows.py. **Check for this every round** (diff his commits).
His notes: emblems only while their Star is on the pitch, one ascension locks
the rest; the combat screen was unreadable (bars over the duel window); he
wants a questions FILE with no limit -> `data/Questions.csv` +
`tools/questions.py`. Read it first every round.

**Built:** C3 - `goalie_chance` (keeper_shift, until the next shot),
`goalie_shield` / `remove_shields` (GoalieUnit.shield soaks stamina loss
first), `foul_heat` (Referee.add_heat), `foul_chance` (FoulBook.roll extra,
until the next fouls), `foul_coin_flip` (banked, spent in _settle_fouls).
Asking: engine `interactive[side]` (player, AUTO off), `duel_questions()` +
`consent()` before each duel, `take_asks()` / `answer()` / `answer_default()`
after reveals, rounds, cycles; `ChoiceWindow.ask()` (src/ui/choice_window.gd).
Abilities.csv `Ask` column. F2: `_side_up` per cycle, `OUTSIDE_DUEL`.
`end_tokens("rose")` on any goal. Emblems: `_my_cards()` / `_stars_of()` =
the Star on the pitch only (`emblem_follows_star`), locked emblems dropped
from the engine (`emblem_locked_is_inactive`). Placeholder Stats rows that
counted "every duel won" rewired (one had turned Haures over by accident -
dangerous now that a turn-over locks the others). Duel window shows what
fired. Emblem bar + tracker on layer 18 (under duel 20 / shot 21), emblem
tile right-aligned. on_shot fires BEFORE the shot window now.

**Measured:** coverage 122/228 (54%). ability_check 152 + Emblem stories +
the asking stories. Soaks clean (Lorelei, Bergmännlein, Rauhnacht).
**Gremory finding:** it turns over at the end of round 3 of its own cycle -
zero rounds of Ultimate before the switch takes it off (Questions Q013).

**Next: C4** (bending the duel, Sven's token power).

## 12e. Round AB — DONE (phase C4 + his testing notes)

**His Questions.csv answers** (all 59): "attack power" -> "base power" in
every card text; Sven = the enemy uses a token's power (you pick, shown);
Rose and Swans end when THEIR OWNER scores; Emblems: Basic always active with
its Star, ONE Ultimate per game (a second turns over greyed + red X), no goal
reset, kept when the Star returns; show the enemy Emblem; AI saves Ore;
shields stop shots only; Kerstin -50% once per round; one window for all side
choices; AUTO menu; enemy moves on the tracker; coin shown; SHOW -> REVEAL.
Statuses in Questions.csv: built / answered (later phase) / pinned (mass
testing). New questions Q060-Q075.

**His notes:** foul text unreadable -> ref bar on dark glass; hover window
-> own layer 130, BELOW the card (and _card_top_centre had always fallen back
to the row centre - it read `data`, the card UI's field is `current_data`);
kick-out -> from the player's feet to the nearest touchline; play-maker
variety -> proposal in Q060; "no Emblem, feels like an old build" -> could NOT
reproduce (tile visible at 3 resolutions); added `build_stamp` bottom-left
and an [emblems] log line, asked in Q062. ALSO FOUND: Emblem flags/counters
were never reset between matches -> EmblemBook.new_match().

**C4 built:** switch_to_defender (take_switch -> main_scene turns the duel
round), always_defending, swap_power, set_power_from_token (consent_token,
pick window), use_enemy_power, force_ability, negate_ability (Buff.source_key
lets it take buffs back), negate_buff, change/give_priority (dynamic stack),
uncounterable, power_from_count, remove_condition. Exhaust abilities fire
BEFORE pending effects land in begin_duel. Coverage 156/228.

**New tools:** tools/balance_report.py (SOAK_SEED/SOAK_SPEED env on
match_soak), tools/combat_shot.gd. **Next: C5.**

## 12f. Round AC — DONE (phase C5 + his testing notes)

**His notes:** Godot "output overflow" -> the 132-line CSV problem list is
cut to `log_problem_lines` + csv_problems.txt; emblem log only on change;
project.godot debugger limits raised. Units on the touchline -> linger clock
(`_keep_moving` in main_scene, PlayerUnit.linger_*), `edge_keep`, zone map
(ZoneOverlay.detail, Z key = `zones` in Keys.csv, camera goes wide). Emblem
"missing" was the plain enemy team -> NO EMBLEM tile. Test Complete
Environment -> src/core/test_environment.gd (own save folder, orange strip
via MenuEscape.install, class_select ignores locks, SaveSlots.choose leaves
it; tools/test_env_check.gd). FOUND: units with no Artwork were invisible
-> CardDatabase._stand_in_art() + placeholder_art rows.

**His answers built:** Q060 all five starts (PlayMakerStarts.csv +
src/core/play_maker_starts.gd; OutOfBounds beats use {call}/{caption};
_blame_somebody picks the start; _kick_for_start, _walk_up_to_it per kind;
_ask_the_thrower by Restart; _take_the_throw from _restart_from), Q061
restart side attacks, Q062 none tile, Q063/64 enemy race
(main_scene.enemy_race GameState, stats.record on enemy events), Q043/44.

**C5 built:** reveal_after_pick (_on_card_selected async, _pick_in_progress
guard, _their_pending_reveal, _show_both_reveals); exhaust swap
(engine exhaust_swap_options / do_exhaust_swap, trigger exhaust_swap fired in
begin_duel, _offer_exhaust_swaps + _light_exhaust in main_scene); zone moves
logged via _c5_move/take_zone_moves -> unit.is_exhausted; ask kind "choose";
Jakob re-read on makeswan. Coverage 168/228. AUTO now reveals - which is why
AB's test matches had no Swans.

**New tools:** test_env_check.gd, test_env_shot.gd, c5_shot.gd;
combat_shot SHOT_ZONES / SHOT_START / SHOT_COUNT; match_soak SOAK_START /
SOAK_TEST_ENV. **Next: C6.**

## 12g. Round AD — DONE (phase C6, 228/228)

**C6:** src/formations/pitch_engines.gd (PitchEngines node, opened at the
first PLAY MAKER by main_scene._c6_at_play_maker): touches + mining tracked
every physics frame (tick), handed to the engine at every PLAY MAKER
(set_touched / set_mining / mine_ore), mines from data/Mines.csv, drawn mines
and gravestones, icy ball. Bench chosen in _choose_benches (ask_rows window,
AUTO kind "bench"). Engine: C6_EFFECTS + _engine_effect (coldtouch,
swapfromvoid, gravestone, mine, fuse, fused), weapon = addpower buff,
_swap_mid_duel -> take_mid_swap (main_scene swaps atk/def after the stack),
_fused_with (power = max of the two printed, partner's cell appended in
_fire_for). Targets `ball` / `field` are known now. Stats rows for Flauros,
Belial, Glasya, Caim rewired to real events.

**His answers:** Q077 Dev zone-map switch (flag dev_zone_map), Q082 more
corners / goal kicks, Q085 AI swaps only stronger (ai_exhaust_swap_any),
Q086 Flauros asks (ask kind choose / reveal_from_exhaust + _reread).
**Next: C7 (Q099).**

## 12h. Round AE — DONE (phase C7, all 12 Emblem Basic sides)

EMB_VASSAGO_WIN / EMB_GLASYA_TOUCH / EMB_CAIM_SWAP (trigger position_swap,
fired for the card that came in from do_exhaust_swap and _swap_mid_duel).
Engine: has_emblem(), _belial_mines (in round_lineups), _haures_save (in
after_shot) + keeper_shift rock, _flauros (after a buff lands on another
fire card), _exhaust_peaks (Vassago's counter, event exhaust_peak),
nugget_picked. PitchEngines: Valefor crater + nuggets (_drop_ore at every
PM, _pick_up_nuggets in tick, mine_for prefers nuggets). Keeper modulate
for Haures in _arm_abilities. Q096: fused card uses the stronger card's
cells (_partner_is_stronger). Q098: PlayerCardUI glow (card_glow_words).
Q100: six Ultimates written into the Emblem CSVs. emblem_check is ALL GOOD
for the first time. **Next: C8 (Q108), Rauhnacht balance (Q107).**

## 12i. Round AF — DONE (phase C8, combat complete)

Q101: Star Players.csv Ultimate Side is the master (ClassBook reads it over
the Emblem file's copy; tools/sync_ultimates.py syncs; my six AE proposals
removed). Engine C8 block "THE STARS' ULTIMATES": set_ultimates (main_scene
_push_ultimates from EmblemBook.ultimate_stars, each _arm_abilities and on
turn-over), on_ultimate (Flauros weapon / fusion break, Buer mask),
_ultimate_power (Belphegor, mask, counter_power_<kind> dial),
_ultimate_duel_start (Sallos, Valefor, Vassago copy -> _copied/_pinned, Caim
ghosts), _ultimate_round (Belial bonus, Valefor exhaust mining), _haures_armour
(begin_round), shop_items/shop_buy (data/OreShop.csv; main_scene
_offer_ore_shop after begin_duel; AUTO kind "shop"), Zepar at the top of
resolve_duel_abilities, Gremory in createtoken + shot_bonus, Belphegor reset
via take_emblem_resets -> main_scene _emblem_resets -> EmblemBook.unflip.
PitchEngines: Caim stones (on_ultimate, _ball_knocks_stones), Glasya terrify
(mines in at_play_maker, nuggets). Q103 valefor_refill, Q104 haures_rock_scale.
Balance: counter_power_<kind> dial, experiment in README. **Next: Q117.**

## 12j. Round AG — DONE (pinned phases P1–P5 written; P2 built, P1 started)

PHASES.md "After combat — the pinned phases": P1 mass testing/balance, P2 free
kicks, P3 recruitment board, P4 hide Rivals' cards, P5 art pass 2 (blocked,
no PixelLab). Answers: Q115 counter_power_burn 1, Q116 haures_rock_shift 0,
Q112 b engine vassago_options/vassago_copy + main_scene _offer_vassago_copy
after _offer_ore_shop (AUTO kind "vassago"), Q113 b PitchEngines._possess
(victim, kind) with Tuning glasya_objects (mine, ore, touch, gravestone).
P2: src/core/free_kicks.gd + data/FreeKicks.csv; main_scene _free_kick (in
_settle_fouls; returns power/takes_ball/taker/spot), fouls["taker"] sets
round_shooter_card, _free_kick_spot overrides _shooting_position once; AUTO
kind "freekick"; Stats free_kick_won; Tuning free_kicks; tools/free_kick_check.gd.
P1: "  DUEL <tier>: you|they win" log line; balance_report.py counts duels per
tier and free kicks per range. Q118 dials: star_power_tier_<T> (in
_ultimate_power), count_power_floor (in powerfromcount). Results in README.
ability_check: _check_ag; Buer/Haures stories read the dials now.

## 12k. Round AH — DONE (P3 recruitment board, P4 Pub, art phases A1–A5, Q124)

PixelLab allowed again (Q125); its tools come through the remote-devices
bridge (his desktop app, a Steam Deck). His claude_desktop_config.json needed
the stdio form: command npx, args -y mcp-remote https://api.pixellab.ai/mcp
--header Authorization:${PIXELLAB_AUTH}, env PIXELLAB_AUTH "Bearer <key>"
(the "url"/"transport" form is ignored by the desktop app). A1 DONE: pitch =
pixflux grass + tools/make_pitch.py lines (1280 grid x2 - the 640 grid was
too blocky in-match); title + base yard = create_image_pro 480x272 with the
panel as style_image, crop + x4. tools/a1_shot.gd photographs them. api.pixellab.ai is reachable from the sandbox (401 without a
key) - never ask him to paste the key. P3: src/core/recruit_board.gd +
data/RecruitBoard.csv; room_screen _fill_recruit_board (Club House, above
resting); board in save `recruit_board` / `recruit_board_at` vs
`matches_played`; names held by NameBook while on the board; beds_free =
BaseRooms.beds - recruit_beds_kept - recruits; named_recruits now TRUE,
squad_ownership stays FALSE (Q126). tools/recruit_board_check.gd,
tools/recruit_shot.gd. P4: pub_screen _rebuild_cards skips
pub_hidden_classes. Art: ArtOrders.csv Phase column + orders 15–21 (A4 units,
A5 icons), pitch row moved first; tools/art_status.py -> guides/ART_STATUS.md.
Q124: engine dial tier_power_<class lower, no spaces/hyphens>_<tier> in
_ultimate_power; cause = Unkengeister Tier IV abilities never change combat
power (exhaust / cold touch / gravestone / force).

## 13. Ideas worth offering him

- An `Ultimate In Short` column so the emblem bar and hover can show one line
  instead of a paragraph.
- Optionally collapse the emblem bar to picture and pips, with text on hover.
- Referee portraits for `lenient` (old brewer) and `strict` (thin Prussian).
- Once names exist: a recruitment screen where you sign named plain players,
  then brew them into a class at the Pub. That turns the brewery economy into
  the roster economy, which is the theme.
