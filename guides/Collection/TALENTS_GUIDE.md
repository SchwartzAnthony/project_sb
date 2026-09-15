# Phase 3 — The talent tree

## Where the files go

| File | Folder |
|---|---|
| `talent_db.gd` | `src/core/` |
| `talent_screen.gd` | `src/ui/` |
| `talent_screen.tscn` | `src/ui/` |
| `Talents.csv` | `data/` |
| `card_database.gd` | `src/core/` *(replace)* |
| `content_report.gd` | `src/core/` *(replace)* |
| `scene_paths.gd` | `src/core/` *(replace)* |
| `main_scene.gd` | `src/formations/` *(replace)* |
| `Buildings.csv` | `data/` *(replace)* |
| `Progression.csv` | `data/` *(replace)* |

**After copying `Talents.csv` in, set its importer to "Keep File (No Import)"**
— same as you did for the others. New CSVs arrive as translations.

Then: **F5 → The Base → Training Ground.**

You will have no talent points at first. Play a match and you get one.

---

## What you can now do without code

Open `Talents.csv`. Every row is one talent.

| Column | What it does |
|---|---|
| **ID** | unique. Taking the talent unlocks this name, so `unlocked:high_press` works anywhere afterwards |
| **Name** | what the player sees |
| **Tree** | which column. **A new word here = a new column on screen** |
| **Tier** | which row, 1 at the top |
| **Parent** | the ID that must be taken first. Blank = a root |
| **Requires** | an extra condition on top of the parent |
| **Cost** | talent points. Blank or `0` = free |
| **Effects** | what taking it does |
| **Description** | one line for the player |
| **Art**, **Notes** | optional |

**You never position anything.** The screen works out the columns and rows and
draws the connecting lines. Add a row with `Tree` = `Keeping` and a third
column appears.

---

## The important bit: talents can change any tuning number

Any counter named `tune_<something>` is **added** to the `Tuning.csv` row of
that name. So this in a talent's Effects:

```
count:tune_press_speed+12
```

makes `press_speed` 92 + 12 = 104 for that save, permanently, with no code.
It works for **every row in Tuning.csv** — speeds, radii, counts, press
helpers, relay hops, shot distance, all of it.

That is the whole mechanism. There is nothing else to learn to make a talent
that actually changes the match.

**Whole numbers only.** It suits speeds and radii and counts. It does *not*
suit the 0-to-1 chances like `goalie_break_through_chance` — adding 1 to 0.05
would make it 1.05. Use flags for those and I will wire them individually.

If you misspell the target — `tune_pres_speed` — the startup report tells you:

```
a talent raises 'tune_pres_speed', but Tuning.csv has no row of that name
— the talent would do nothing
```

---

## The tree that ships with it

**Tactics** — things you feel on the pitch:

```
        High Press  (1pt)  press_speed +12
             |
      +------+------+
      |             |
   Swarm (1)    Wide Play (1)
   +1 presser   +40 open spread
      |
  Relentless (2)  -- also needs 3 wins
  chase speed +10
```

**Brewing** — opens up phase 4:

```
     Brewing Basics (1)  unlocks Fire Brew
             |
      +------+------+
      |             |
  Water Craft (1)  Steady Pour (1)
  unlocks Water    mark distance +10
      |
  Master Brewer (2)  -- also needs 5 brews drunk
  unlocks Permanent Brews
```

I simulated a full run of both trees: gating by points, by parent and by extra
condition all behave, and every `tune_` target exists in your real
`Tuning.csv`.

---

## A decision I made, and how to undo it

**I gave talents a cost in talent points.** You told me buildings should be
requirements-only with no currency, but I never asked about talents, and a
tree where everything unlocks automatically is a list rather than a choice.

**To make talents free instead:** clear the `Cost` column in `Talents.csv`.
Every talent then unlocks the moment its parent and Requires allow. Nothing
else to change.

**Where points come from** — one row in `Progression.csv`:

```
talent_point,match_ended,unlocked:Talent Tree,count:talent_points+1,,
```

One per match, once the Training Ground is open. Change `+1` to `+2` for a
faster tree. Delete the row and nothing earns points.

---

## Three things worth knowing

**1. Do not rename a talent ID after anyone has a save.** Taken talents are
remembered by ID. Rename `high_press` and a player who had it loses it. Change
the `Name` freely — that is only what is displayed.

**2. Talents are permanent.** There is no respec. If you want one, it is a
building action away — `unlock:respec` and a row that clears the taken
talents. Say the word and I will add it.

**3. A parent loop is caught for you.** If A's parent is B and B's parent is
A, the screen would hang. The startup report catches it instead and names the
row.

---

## Add your own talent in one minute

1. Open `Talents.csv`
2. Add a row:
   `iron_lungs,Iron Lungs,Tactics,3,wide_play,,1,count:tune_unit_walk_speed+8,Your players never stop moving.,,`
3. Save, press F5, open the Training Ground

It will be greyed out until you have taken Wide Play and have a point. Click it
and your walk speed goes up for good.

---

## Where we are

| Step | | |
|---|---|---|
| 1 | The spine — stats, progression, the report | done |
| 2 | Base building — hub, buildings, visitors | done |
| **3** | **Talent tree** | **done, this delivery** |
| 4 | Pub and brews — `Brews.csv` | next |

Phase 4 is already half-plumbed. `Brewing Basics` unlocks `Fire Brew`,
`Master Brewer` unlocks `Permanent Brews`, every unit carries an `active_brew`,
and `brews_drunk` is already counted. The Pub screen and `Brews.csv` are what
is left.
