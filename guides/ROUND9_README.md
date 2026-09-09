# Three bugs, Quick Match, and a brief for Gemini

---

## STEP 1 — Where the files go

| File | Folder | |
|---|---|---|
| `match_mode.gd` | `src/core/` | **NEW** |
| `MatchModes.csv` | `data/` | **NEW** — set to "Keep File (No Import)" |
| `BasicEnemyTeam.csv` | `data/` | replace — **this is bug 1's real fix** |
| `main_scene.gd` | `src/formations/` | replace |
| `card_database.gd` `content_report.gd` `scene_paths.gd` `tier_ladder.gd` | `src/core/` | replace |
| `class_select.gd` `base_screen.gd` `main_menu.gd` `match_stats_screen.gd` | `src/ui/` | replace |
| `MenuConfig.csv` | `data/` | replace (notes only) |

**"Keep File (No Import)":** FileSystem → click the file → **Import** tab →
**Keep File (No Import)** → **Reimport**.

---

# THE THREE BUGS

## Bug 3 — `last_numbers` (do this first, it stops the game)

```
Nonexistent function 'last_numbers' in base 'RefCounted (SeasonDB)'
main_scene.gd:748 @ _apply_fixture()
```

A typo of mine from an earlier round: **`last_numbers()` should be
`last_number()`** (no s). The `main_scene.gd` in this round is already
correct, so replacing the file fixes it.

If you would rather not replace the whole file: open `main_scene.gd`, go to
line 748, and delete the `s`.

## Bug 1 — a Tier IV Star in the Tier I Star slot

**This was a data collision, and it is worth understanding because it will
happen again.**

`BasicTeam.csv` and `BasicEnemyTeam.csv` both had `Unit Type = Normal`.
Every `.csv` in `res://data/` is loaded, so the game did not see two teams —
it saw **one class called "Normal" with 24 cards and six Star Players**:

- Hoffmann, Schäfer, Koch — **Tier IV** Stars (3, 4, 5)
- Bauer, Richter, Klein — **Tier I** Stars (0, 1, 2)

So the Star slot was Tier I, the game offered you every "Normal" Star, and
you picked a Tier IV one. Exactly what you saw.

**The fix is in the data:** `BasicEnemyTeam.csv` is now class **`Rivals`**.
Two files, two classes, no collision. That is the whole fix, and it is one
column you can edit yourself next time.

**Three code guards so it cannot silently happen again:**

- A class's star tier is now **the tier that holds most of its Stars**, not
  "whatever the first Star row happens to be".
- The Stars are taken as a **ladder** — one per rung of that tier. A Star in
  the wrong tier is left out rather than fielded in the wrong place.
- HOLD UP only offers Stars **of your star tier**, and the swap refuses a
  Star from another tier instead of quietly moving the tier to match it.

The startup report now names any Star outside its class's tier, and says
which tier to move it to.

## Bug 2 — Back went to the main menu

`class_select.gd` had its Back button hard-coded to the main menu. It is
reached from **two** places — the main menu, and the base's "Play a match" —
so leaving the base to look at the classes and changing your mind dumped you
out of the base. It now uses the trail like every other screen.

**If you still see this on another screen,** the Output panel will now tell
us which one. Every Back press prints a line:

```
[nav] Back: season -> base   (behind it: main_menu > base)
[nav] Back from talents: nothing remembered, falling back to base.
```

The second line is the one that matters: it means the screen you came *from*
was opened without leaving a trail. Send me that line and I can name the
button in one go.

---

# QUICK MATCH — built

## MatchModes.csv

The kind of match is a spreadsheet row now, not code:

```
ID,Name,Records Season,Timer,Cycles,Rounds,Star Rotation,Opponent,Requires,Description
season,Season Match,yes,90,3,3,yes,team,,"The league..."
quick,Quick Match,no,0,1,3,no,team,,"A single run for resources..."
cup,Cup Tie,no,90,3,3,yes,team,unlocked:The Cup,"..."
```

| Column | |
|---|---|
| **Records Season** | `no` = the result never touches the table |
| **Timer** | minutes. **`0` = no clock** — it ends when the rounds do |
| **Cycles / Rounds** | how long it is |
| **Star Rotation** | `no` = one Star all match, no HOLD UP |
| **Opponent** | `team` today. `nest` is the enemy mode |
| **Requires** | so a mode can be locked |

**Adding a mode is a row.** A button with `Action = match:cup` starts the
`cup` row — no new code for any mode you ever add.

## What Quick Match does now

- On the **main menu** (the button was already in `MenuConfig.csv`) and on
  the **base**, beside "Play a match" — because the base is where you are
  standing when you realise you need materials.
- No clock. The corner reads **ROUND 2 / 3**.
- One Star, no HOLD UP.
- Nothing written to the table, and the post-match Continue button says
  **Back to the base** and goes there.
- **Every `Stats.csv` counter still runs**, which is the whole point.

## Making it pay — today, with rows only

```
wheat,goal_scored,,1,Quick Match,Wheat,One wheat per goal.
coins,duel_won,,2,Quick Match,Coins,Two coins per duel won.
scrap,match_ended,result=win,5,Quick Match,Scrap,Five for winning.
```

Then a building costs them:

```
mill,The Mill,Grinds what the fields give up.,count:wheat>=20,mill,0.3,0.4,count:wheat-20;count:wheat+3,
```

Play quick matches → collect → buy the Mill → the Mill makes wheat for you.
That loop works **now**.

---

# THE ENEMY MODE — designed, not built

**ENEMIES_AND_QUICK_MATCH.md** has the full design: `Enemies.csv`,
`Nests.csv`, `Drops.csv`, and how a round plays.

The short version, and the reason it is a smaller build than it sounds:
**an enemy is a goalie.** It has a stamina bar, it tries to save, and you
already have all of that — `GoalieData`, `GoalieUnit` and `shootout_view`
resolve a shot against a keeper today. An enemy is a goalie that stands in
the open, belongs to a nest, and drops loot when it is beaten.

Only one existing file needs a branch: when the mode's **Opponent** is
`nest`, build nests instead of an opposing team.

**Two questions I need answered before building it** (both in the doc):

1. **Do enemies hit back?** If you lose a power check, does something happen
   to your player — or is the wasted shot the whole cost? The second is
   simpler; the first gives it teeth.
2. **Does a Quick Match end when the nests are cleared, or when the rounds
   run out?** I would do *clear the nests, with the rounds as a ceiling* —
   you win by clearing, you leave with less if you run out.

---

# FOR GEMINI

**GEMINI_SYSTEM_BRIEF.md** is the file to upload. It is the whole system in
one document: the tier ladder, the condition language, every CSV and its
columns, every script and what it does, the ten conventions that keep the
project editable, and what is built versus designed versus not started.

It opens with **a paragraph to paste as your first message**, which tells
the assistant the three rules of this project:

1. New content is a spreadsheet row, never code.
2. Tell me what already covers this before inventing anything.
3. Give me steps I can follow without a follow-up question.

The single most useful question in it, and the one to ask before any big
feature:

> "Before you design this, tell me what in the existing system already does
> part of it."

---

# WHAT I CHECKED

- **Every class now has a clean star ladder in one tier, no strays** —
  Brandteufel III (2,3,4), Lorelei IV (3,4,5), Normal IV (3,4,5), Rivals I
  (0,1,2). Before the fix, "Normal" had six Stars across two tiers.
- The six ladder passes re-run against the changed data: 48 cards all on a
  real rung, every class fills every tier, 2000 random line-ups legal, all
  12 `Teams.csv` rows legal, named cards preferred, `repair()` fixes an
  illegal saved team.
- `MatchModes.csv` parses to the three modes with the right shapes.
- Structural check of all 61 scripts. The two remaining hits are
  pre-existing and legal: text inside a `"""` block, and alignment inside
  brackets.

---

# STILL ON THE LIST

1. **The enemy/nest mode** — answer the two questions and it is buildable
2. **The halftime locker room**
3. **`Items.csv` + `Recipes.csv` + a stash screen**
4. **Seasons as biomes**
5. **The tutorial**
6. **Input actions**, then settings and controller

And one housekeeping item from last round, still worth doing:
**`example_unit_csv_with_ability_columns.csv` is a second complete copy of
the Brandteufel set.** Move it out of `res://data/` or rename it off `.csv`
— it is the same "every CSV is loaded" trap that caused bug 1.
