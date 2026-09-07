# File Placement Guide

Place these files into your Godot project exactly as shown below. **File order does not matter** — copy everything at once. The project structure is designed so new code slots alongside existing files without conflicts.

---

## 📁 Project Structure Overview

```
res://
├── data/
│   ├── Abilities.csv                    (new)
│   ├── Animations.csv                   (new)
│   ├── Tuning.csv                       (new)
│   ├── goalies/                         (new directory)
│   └── [other existing CSVs]
├── assets/
│   ├── players/                         (your card spritesheets here)
│   ├── goalies/                         (first-person keeper sheets here)
│   └── [other existing art]
├── src/
│   ├── core/
│   │   ├── ability_data.gd              (new)
│   │   ├── ability_engine.gd            (new)
│   │   ├── anim_spec.gd                 (new)
│   │   ├── card_database.gd             (new)
│   │   ├── player_data.gd               (new)
│   │   └── [other core scripts]
│   ├── units/
│   │   ├── ball.gd                      (new)
│   │   ├── player_unit.gd               (new)
│   │   ├── goalie_unit.gd               (new)
│   │   ├── sprite_animator.gd           (new)
│   │   └── [other unit scripts]
│   ├── ui/
│   │   ├── rps_clash.gd                 (new)
│   │   ├── rps_clash.tscn               (new)
│   │   ├── duel_arena.gd                (new)
│   │   ├── duel_arena.tscn              (new)
│   │   ├── shootout_view.gd             (new)
│   │   ├── shootout_view.tscn           (new)
│   │   └── [other UI scripts]
│   ├── formations/
│   │   ├── main_scene.tscn              (existing, leave it)
│   │   └── [class-specific formation scenes]
│   └── main_scene.gd                    (REPLACE existing)
├── test_run.gd                          (new, project root)
├── export_sheet_preview.gd              (new, project root)
└── [project.godot, etc.]
```

---

## 📋 Placement Checklist

### ✅ Data Files — `res://data/`

Copy these **four** CSV files into `res://data/`:

1. **`Abilities.csv`** — Ability definitions (trigger, target, effect, value, scope)
2. **`Animations.csv`** — Animation sheet metadata (row, frame count, fps, loop)
3. **`Tuning.csv`** — Game balance and pacing numbers (stamina, speeds, cut-away timing, **field bounds**)
4. **`MenuConfig.csv`** — Menu button layout and art paths (NEW)

**Reference file (optional):**
- `example_unit_csv_with_ability_columns.csv` — Shows what a unit CSV looks like with new columns. Use it as a template when adding Attack Ability / Defend Ability columns to your own unit CSVs.

**Goalies directory:**
- Create an empty `res://data/goalies/` directory. This is where you'll place any updated goalie CSV files if you create them.

---

### ✅ Core Engine — `res://src/core/`

Copy these six scripts into `res://src/core/`:

1. **`ability_data.gd`** — One row from Abilities.csv. Validates trigger/target/effect/value/scope enums.
2. **`ability_engine.gd`** — Manages ability firing order, scoped buffs, and stamina changes. Main entry points: `apply_passives()`, `resolve_duel_abilities()`, `resolve_duel_outcome()`.
3. **`anim_spec.gd`** — One row from Animations.csv. Validates sheet grid, row, frame range.
4. **`card_database.gd`** — Loads all CSVs at startup, detects file types by header, caches data. Called by `CardDatabase.get_db()` in code.
5. **`player_data.gd`** — One card's data (name, power, tier, tags, artwork).
6. **`field_bounds.gd`** — Field geometry helper. Provides methods for constraining positions within field bounds and automatic field sprite scaling.

---

### ✅ Unit/Entity Code — `res://src/units/`

Copy these four scripts into `res://src/units/`:

1. **`ball.gd`** — Scripted delivery and shooting. Entry points: `delivery_to(destination)`, `shoot(power, destination)`.
2. **`player_unit.gd`** — On-pitch player sprite. Reads animation frames via sprite_animator, emits signals when duel resolves.
3. **`goalie_unit.gd`** — On-pitch keeper sprite. Tracks stamina, reads animation frames. First-person keeper sheet handled separately in shootout_view.
4. **`sprite_animator.gd`** — Animates any sprite on demand. Handles auto-crop detection, caching, nearest-neighbour scaling, fallback to still frame if art is missing.

---

### ✅ UI Code — `res://src/ui/`

Copy these **ten** files into `res://src/ui/`:

**Rock-paper-scissors:**
1. **`rps_clash.gd`** — Logic for the throw mini-game.
2. **`rps_clash.tscn`** — Scene for the clash window (lazy node lookup, works if added before _ready()).

**Duel cut-away:**
3. **`duel_arena.gd`** — Advance Wars-style duel window. Entry point: `show_duel_arena(attacker, defender, win_duel_callback)`.
4. **`duel_arena.tscn`** — Scene for the duel window (left = player side always, right = enemy side).

**Shootout:**
5. **`shootout_view.gd`** — First-person keeper view before shot. Entry point: `show_shootout(striker, keeper, result_callback)`.
6. **`shootout_view.tscn`** — Scene for the shootout window (keeper front-on, striker from behind).

**Main menu (NEW):**
7. **`main_menu.gd`** — CSV-driven menu manager. Loads buttons from MenuConfig.csv, handles actions (start, settings, quit).
8. **`main_menu.tscn`** — Menu scene. Set this as your project's starting scene.
9. **`menu_button.gd`** — Individual menu button handler. Displays PNG art or colored placeholder.
10. **`menu_button.tscn`** — Button scene template.

---

### ✅ Main Match Controller — `res://src/formations/`

**IMPORTANT: Do NOT overwrite** `main_scene.gd` — it already has freeze_play() implemented!

Instead, make **two small code additions** to `main_scene.gd`:

1. **In `trigger_hold_up_event()` (line ~913):** Add `freeze_play(true)` before showing star selection UI
2. **In `_on_draft_complete()` (line ~1130):** Add `freeze_play(false)` in the first branch (HOLD UP! star selection)

See `MAIN_SCENE_INTEGRATION.md` for the exact code locations and changes needed.

---

### ✅ Tools — Project Root

Copy these two scripts to the **project root** (`res://`):

1. **`test_run.gd`** — Headless match simulator. Run with:
   ```bash
   godot --headless --path . --script res://test_run.gd
   ```
   Auto-picks the first card in every draft. A full match takes ~25 seconds. Use this to:
   - Smoke-test new CSVs
   - Sample balance (run it a few times and watch final scores)
   - Verify no crashes on bad data

2. **`export_sheet_preview.gd`** — Artist tool that labels your animation sheets. Run with:
   ```bash
   godot --headless --script res://export_sheet_preview.gd
   ```
   Or in the editor: **File → Run** (with this file open).
   
   Writes one labelled PNG per card to `res://sheet_previews/`. Shows:
   - Blue row numbers (0–38)
   - Amber frame counts (how many frames are drawn on that row)
   - First, middle, last drawn frame of each row
   
   Use the output to identify which row holds your run cycle, kick, etc., then fill those row numbers into `Animations.csv`.

---

## 📝 Next Steps After Placement

### 1. **Check Godot Doesn't Error on Startup**
   - Open your project in the Godot editor
   - Press **Play** — the match should start without errors
   - If there are CSVs you haven't migrated yet (old unit CSVs, old goalies), the game will report them in the Output panel and carry on

### 2. **Wire Up Your Unit CSVs**
   - Open your unit CSV files (e.g., `Units Set FO1 - Brandteufel.csv`)
   - Add two new columns if they don't exist: `Attack Ability` and `Defend Ability`
   - For each card, enter the Ability ID from `Abilities.csv` (or leave blank for no mechanical ability)
   - Example: `Coalblaze` might have `Attack Ability = BRAND_RALLY`
   - See `example_unit_csv_with_ability_columns.csv` for format

### 3. **Add Shootout Keeper Art (Optional)**
   - Draw a first-person keeper grid (e.g., 4 × 4) as a separate spritesheet
   - Save it in `res://assets/goalies/` with a clear name (e.g., `BrandteufelKeeperShootout.png`)
   - Add a `Shootout Artwork` column to `Goalies.csv`
   - Put the file name in that column (e.g., `BrandteufelKeeperShootout.png`)
   - Until you do, the shootout shows a coloured block where the keeper goes

### 4. **Update Animations.csv**
   - Run `export_sheet_preview.gd` to label your sheets
   - Open the output PNGs and read off which row holds which animation
   - Fill `Animations.csv` with those row numbers:
     - `run` (both units running)
     - `kick` (attacking player strikes)
     - `kick_back` (attacking player from behind, for shootout striker)
     - `keeper_ready` (first-person keeper waiting)
     - `keeper_dive` (first-person keeper diving)
     - And `idle`, `ability`, `win`, `lose` as you draw them
   - Missing animations fall back gracefully (idle → still frame)

### 5. **Tune Balance in Tuning.csv**
   - `Tuning.csv` has every number the game reads (stamina, speeds, pacing, etc.)
   - A missing or misspelled row falls back to built-in default — you cannot break the game
   - Common tuning:
     - `Max Stamina` in `Goalies.csv` should be ~2× the mean shot power (recommended: 25–30)
     - `arena_speed` — overall cut-away speed (default 2 = normal)
     - `relay_beat_seconds` — PLAY MAKER relay timing
     - `scoreboard_x`, `scoreboard_y`, `scoreboard_font_size` — score position and size

---

## 🔗 File Dependencies

If you need to understand what calls what:

- **CardDatabase** is the entry point — loaded once at startup by `main_scene.gd`, accessed everywhere via `CardDatabase.get_db()`
- **AbilityEngine** is called by `main_scene.gd` and `duel_arena.gd` to resolve abilities in order
- **SpriteAnimator** is used by `player_unit.gd`, `goalie_unit.gd`, and `shootout_view.gd` to play animations
- **Duel Arena** is called by `main_scene.gd` after abilities resolve
- **Shootout View** is called by `main_scene.gd` before the shot on goal
- **RPS Clash** is instantiated by `main_scene.gd` at the start of each round

All of these are designed to work standalone — you can test any one of them in isolation.

---

## ⚠️ Important Notes

1. **Do not delete old code** unless you understand what it does. The new code is *additive* — your old formations, assets, and any custom nodes stay as they are.

2. **Formation scenes** (`res://src/formations/<class>_formation.tscn`) are untouched. If you don't have one for a new class, the game generates a formation from the pitch automatically.

3. **The scoreboard is spawned in code**, not in a scene file. If you want to change its position or size, edit `Tuning.csv` (rows: `scoreboard_x`, `scoreboard_y`, `scoreboard_font_size`).

4. **Animation fallback is automatic.** If `Animations.csv` is missing a row, or the art is missing, the game shows `idle` → still frame. Nothing crashes.

5. **CSV validation is printed on startup.** Open the **Output panel** in the Godot editor and read the report after every CSV change. Broken rows are skipped and logged by name.

---

## 📚 Documentation

After placement, read these guides:

- **`FIELD_AND_MENU_SETUP.md`** — How to set up the scalable field system and main menu
- **`MAIN_SCENE_INTEGRATION.md`** — Code changes needed in main_scene.gd for HOLD UP! freeze

---

## 🧪 Testing After Placement

Once everything is in place:

1. **Test the main menu:**
   - Open `main_menu.tscn` and press Play
   - Verify buttons appear and are clickable
   - Click "Start Game" to load the match

2. **Test field bounds:**
   - Run a match and verify players stay within the field edge
   - Adjust `field_margin` in Tuning.csv if needed

3. **Test HOLD UP! freeze:**
   - Run a full cycle (3 PLAY MAKERs)
   - When HOLD UP! appears, verify on-pitch action pauses
   - Pick your next star and verify action resumes

4. **Run `test_run.gd`** from terminal to smoke-test:
   ```bash
   godot --headless --path . --script res://test_run.gd
   ```

5. **Check the Output panel** for CSV validation warnings

All should succeed without crashes.

