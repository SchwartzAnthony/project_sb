# Start here

Three jobs, in order. Job 1 takes five minutes and you must do it. Jobs 2 and
3 are copying files.

---

# JOB 1 — Stop Godot treating your CSVs as translations

**Why:** Godot has decided every `.csv` in `data/` is a *translation file*.
That is what the 58 `Dialogue.Text.translation`-style files are. It works in
the editor because the real `.csv` is still on your hard drive. **The day you
export the game, it will not be**, and the game will start with no cards, no
dialogue and no tuning.

You have not done this yet — I checked your repo. Do it before anything else.

### Steps

1. Open the project in Godot.
2. In the **FileSystem** dock (bottom-left), click the `data` folder.
3. Click the first `.csv`. Then hold **Shift** and click the last `.csv`.
   All of them should now be highlighted.
4. Look at the **top-left** panel. It has two tabs: **Scene** and **Import**.
   Click **Import**.
5. There is a dropdown labelled **Importer**. It currently says
   **"CSV Translation"**. Change it to **"Keep File (No Import)"**.
6. Click the **Reimport** button underneath.
7. Godot will think for a second. Done.

### Then delete the leftovers

In the FileSystem dock, in `data/`, select every file ending in
`.translation` and press **Delete**. There are 58 of them. They are
regenerated junk; nothing uses them.

### Then one more safety net

1. Menu bar: **Project → Export...**
2. Click your export preset on the left. *(If there is no preset yet, skip
   this — come back when you make one.)*
3. Click the **Resources** tab.
4. Find the box labelled **"Filters to export non-resource files/folders"**.
5. Type into it: `*.csv`
6. Close the window.

### How you know it worked

Click any `.csv` in `data/` and look at the **Import** tab. It should say
**Keep File**. There should be no `.translation` files left.

---

# JOB 2 — Fix the crash

That error you got:

```
scene_paths.gd:80 @ go_to(): Parent node is busy adding/removing children
```

**This was my bug, not your file placement.** I checked your repo and every
single file is in the right folder. Nothing to fix there.

What went wrong: the game tried to change screens *during* the main menu's
first frame, and Godot will not allow that. The fix is in `scene_paths.gd`,
which now waits until the end of the frame. It is fixed for every screen at
once, so this cannot come back.

**You also asked for the opening dialogue to go away.** It has. The prologue
now plays the first time you open **the Base**, not when the game launches. If
you want no story at all, open `Progression.csv` and delete the row whose ID is
`welcome_at_base`.

---

# JOB 3 — Copy these files in

Every file in this delivery, and exactly where it goes.

### New files

| File | Put it in |
|---|---|
| `base_db.gd` | `src/core/` |
| `base_screen.gd` | `src/ui/` |
| `base_screen.tscn` | `src/ui/` |
| `Buildings.csv` | `data/` |
| `Visitors.csv` | `data/` |

### Replace the ones already there

| File | Put it in |
|---|---|
| `scene_paths.gd` | `src/core/` |
| `progression.gd` | `src/core/` |
| `dialogue_grammar.gd` | `src/core/` |
| `content_report.gd` | `src/core/` |
| `main_menu.gd` | `src/ui/` |
| `Progression.csv` | `data/` |
| `MenuConfig.csv` | `data/` |

**After copying the two new CSVs in, do JOB 1's import fix on them too.**
New CSVs arrive as translations by default.

### Then

Press **F5**. Click **The Base**.

---

# The complete file map

Keep this. It is where *everything* lives, so you never have to ask again.

| Folder | What belongs there |
|---|---|
| `data/` | **every `.csv`.** No exceptions. |
| `src/core/` | the engine. Anything with no screen of its own: `card_database`, `player_data`, `goalie_data`, `ability_data`, `ability_engine`, `anim_spec`, `field_bounds`, `menu_support`, `pitch_zones`, `zone_overlay`, `scene_paths`, `team_selection`, `game_state`, `dialogue_grammar`, `dialogue_choice`, `dialogue_line`, `dialogue_db`, `stats_rules`, `progression`, `content_report`, `base_db` |
| `src/ui/` | every screen, and its `.tscn` beside it: `main_menu`, `class_select`, `team_builder`, `dialogue_view`, `base_screen`, `card_popup`, `player_card_ui`, `duel_arena`, `rps_clash`, `shootout_view`, `star_badge` |
| `src/units/` | things on the pitch: `player_unit`, `goalie_unit`, `ball`, `sprite_animator` |
| `src/formations/` | `main_scene.gd`, `main_scene.tscn`, and your `*_formation.tscn` files |
| project root | `test_run.gd`, `export_sheet_preview.gd`, `project.godot` |
| `assets/` | art — see the art table below |
| *(outside the project)* | the `.md` guides. They are for you, not the game. |

**The one rule that matters:** a `.gd` file with `class_name` at the top can
technically sit anywhere and Godot will find it. `zone_overlay.gd` is in
`src/core/` instead of `src/ui/` in your repo and it works perfectly. Folders
are for **your** sanity, not Godot's. So if you are ever unsure, put it in the
folder the table says and move on.

### Art folders

All optional. Everything below works with none of it — you get plaques and
letters instead of pictures.

| Folder | For |
|---|---|
| `assets/base/` | `background.png`, and one PNG per building named in `Buildings.csv` |
| `assets/portraits/` | one PNG per visitor and per dialogue speaker |
| `assets/backgrounds/` | dialogue backdrops |
| `assets/ui/` | `star_badge.png` |
| `assets/menu/` | main menu buttons and background |
| `assets/players/` | your card spritesheets |

---

# What the Base does now

It is a hub between matches, reached from the main menu or from
`goto:base` anywhere.

Everything on it comes from two new spreadsheets. **Nothing in the code needs
touching to add a building or a visitor.**

## Buildings.csv

| Column | What it does |
|---|---|
| **ID** | a unique name. Only you and the error report see it |
| **Name** | the sign on the building |
| **Description** | one line, shown when clicked |
| **Requires** | when it becomes usable. Blank = always. Usually `unlocked:Brewery` |
| **Art** | PNG name in `assets/base/`. Blank = a labelled plaque |
| **X, Y** | where it sits. `0,0` is top-left, `1,1` is bottom-right, `0.5,0.5` is dead centre |
| **Action** | what clicking does: `story:name`, `goto:classes`, `announce:Text`, `unlock:Thing`. Blank = just show the description |
| **Notes** | yours |

A **locked** building is still drawn, greyed out, and clicking it tells the
player what they need — in plain English, generated from your `Requires`.
`count:goals_with_brew_fire>=3` shows as *"Needs goals with brew fire: at least
3."* That is a good reason to name your counters in full words.

## Visitors.csv

| Column | What it does |
|---|---|
| **ID** | unique |
| **Name** | shown under them |
| **Portrait** | PNG in `assets/portraits/`. Blank = a big letter |
| **Requires** | when they turn up. Blank = always |
| **Story** | the `Dialogue.csv` **Scene** to play when clicked |
| **X, Y** | same 0–1 fractions |
| **Once** | `true` = they leave for good after you talk to them |
| **Notes** | yours |

A visitor is a portrait wired to a dialogue scene. Who they are and why they
came is all written in `Dialogue.csv`.

### To add a visitor right now

1. Open `Dialogue.csv`. Add rows with **Scene** = `brewer_chat`.
2. Open `Visitors.csv`. Add:
   `brewer2,Old Hallag,hallag,unlocked:Brewery,brewer_chat,0.30,0.78,,`
3. Press F5, open the Base.

If you spell `brewer_chat` wrong in one of the two files, the Output panel
tells you at startup, by file and row number. It will not fail silently.

---

# Answers to your other two questions, recorded for step 4

You said the brew:

- changes a player **for one match**, with a **permanent option** you can
  choose to keep or remove later
- gives the card its **own art and abilities**, since base players have none

Both are noted and shape `Brews.csv` when I build the Pub. The plumbing is
already in — every unit carries an `active_brew`, and the match already reports
it with every goal and duel, which is what makes
`count:goals_with_brew_fire>=3` work.

---

# Where we are

| Step | | |
|---|---|---|
| 1 | The spine — stats, progression, the report | done |
| **2** | **Base building — the hub, buildings, visitors** | **done, this delivery** |
| 3 | Talent tree — `Talents.csv`, opened from the Training Ground | next |
| 4 | Pub and brews — `Brews.csv`, one-match and permanent | after that |
