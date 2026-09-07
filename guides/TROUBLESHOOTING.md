# The game closed instantly — what happened

Short version: **that was my mistake, not yours.** The two scene files I sent
last time (`main_menu.tscn` and `menu_button.tscn`) were written in an invalid
format. Godot could not load them, and a main scene that fails to load makes
the window open and close again immediately — often with nothing useful in the
Output panel.

## What was wrong

A Godot 4 `.tscn` declares an external file, gives it an **id**, and then
refers to that id. Mine skipped the id and pointed at the scene's own UID
instead:

```
[ext_resource type="Script" path="res://src/ui/main_menu.gd"]      ← no id
script = ExtResource("uid://b1gctjx1hb3qp")                        ← wrong thing
```

It should be:

```
[ext_resource type="Script" path="res://src/ui/main_menu.gd" id="1_mainmenu"]
script = ExtResource("1_mainmenu")
```

The replacements in this delivery are correct. I have also removed
`menu_button.tscn` from the design entirely — the menu now builds its buttons
in code, so there is one less hand-written scene file that can go wrong.

## Do this

1. **Delete these two files** from your project if they are there:
   - `res://src/ui/menu_button.tscn`
   - `res://src/ui/menu_button.gd`
2. Copy in the new `main_menu.tscn`, `class_select.tscn`, `team_builder.tscn`
   and their `.gd` files.
3. Launch again.

---

# "The variable type is being inferred from a Variant value"

Also mine. Three lines in `card_popup.gd`, fixed in this delivery.

**What the rule is.** In GDScript, `:=` means *"work out the type from the
right-hand side."* But `Dictionary.get()` can hand back anything, so its type
is `Variant` — "could be anything". Since Godot 4.2, inferring a type from a
Variant is a **hard error**, not a warning, because it silently defeats the
point of typing the variable.

```gdscript
var when_text := {"on_attack": "when attacking"}.get(trigger, trigger)   # ✗ error
var when_text: String = TRIGGER_WORDS.get(trigger, trigger)              # ✓ fine
```

The fix is always the same: **stop using `:=` and name the type instead.**
Writing `: String` promises Godot what will come back, and it checks that
promise at runtime.

You will meet this again if you edit GDScript, and the same fix works every
time. It shows up wherever a value's type cannot be known in advance —
`Dictionary.get()`, indexing an untyped array, `.pop_back()`.

I have swept every script in this delivery for the pattern; there are none
left.

---

# If something still closes instantly

Work down this list. Each step is quick and rules out one cause.

### 1. Run the match scene directly, bypassing the menu

In the Godot editor, open `res://src/formations/main_scene.tscn` and press
**F6** (Run Current Scene) rather than F5.

- **The match runs** → the problem is in the menu scenes, not the game.
- **It also closes** → the problem is in the match scene or the CSVs.

### 2. Check what the Main Scene is set to

**Project → Project Settings → General → Application → Run → Main Scene**

It must be a `.tscn` file. If it points at a `.gd` file, or specifically at
`test_run.gd` or `export_sheet_preview.gd`, that is your instant close: both of
those are headless tools that call `quit()` on purpose the moment they finish.

Set it to `res://src/ui/main_menu.tscn`.

### 3. Check for autoloads

**Project → Project Settings → Globals → Autoload**

This list should be **empty** for this project. Nothing I have given you needs
an autoload. If `test_run.gd` or `export_sheet_preview.gd` got added here, remove
it — an autoload that extends `SceneTree` and calls `quit()` will end the game
before you see anything.

### 4. Read the full log from a terminal

The editor's Output panel sometimes loses the very last messages when the
process dies. Running from a terminal never does. In the folder that contains
`project.godot`:

```
godot --path . --verbose
```

On Windows, if `godot` is not a recognised command, use the full path to the
executable in quotes, for example:

```
"C:\Program Files\Godot\Godot_v4.x.exe" --path . --verbose
```

Scroll to the **last 30 lines**. A parse error, a missing file or a failed
scene load will be named there. Send me those lines and I can tell you exactly
what it is.

### 5. A screen loads but a button does nothing

The menu screens no longer hard-code where the other scenes live — they ask
`src/core/scene_paths.gd`. If a path there is wrong, the game **searches
res:// for a file of that name**, uses what it finds, and prints the real path:

```
[scenes] 'main_scene.tscn' is not at res://src/formations/main_scene.tscn
         — found it at res://src/match/main_scene.tscn instead.
         Open src/core/scene_paths.gd and put that path in, and this search
         stops happening.
```

So a different folder layout costs you one printed note, not a dead button.
Paste the path it found into the matching line at the top of `scene_paths.gd`
and the message goes away.

If instead you see `Could not find 'x.tscn' anywhere in res://`, that file
genuinely is not in the project.

### 6. Confirm every script landed in the folder its neighbours expect

Scripts find each other by path. If one is in the wrong folder the scene that
preloads it fails, and the failure cascades. Check these exact locations:

```
res://src/core/     card_database.gd  player_data.gd  ability_data.gd
                    ability_engine.gd  anim_spec.gd  goalie_data.gd
                    field_bounds.gd  menu_support.gd  team_selection.gd
                    scene_paths.gd
res://src/ui/       main_menu.gd/.tscn  class_select.gd/.tscn
                    team_builder.gd/.tscn  card_popup.gd
                    rps_clash.gd/.tscn  duel_arena.gd/.tscn
                    shootout_view.gd/.tscn  player_card_ui.tscn
res://src/units/    player_unit.gd/.tscn  goalie_unit.gd/.tscn
                    ball.gd  sprite_animator.gd
res://src/formations/  main_scene.tscn  main_scene.gd
                    (a different folder is fine — see step 5)
res://data/         your unit CSVs, Goalies.csv, Abilities.csv,
                    Animations.csv, Tuning.csv, MenuConfig.csv,
                    ClassInfo.csv
```

The scripts with `class_name` at the top (CardDatabase, PlayerData,
MenuSupport, TeamSelection, and so on) can technically live anywhere, but the
`.tscn` files and the `preload(...)` lines use the paths above literally.

### 7. Nuclear option: let Godot rebuild its cache

Close Godot. Delete the `.godot` folder next to `project.godot` — it is a
cache, not your work, and Godot rebuilds it on the next open. Reopen the
project. This clears out stale references to files that have moved.

---

## Reading the CSV report

Whatever else happens, the game prints one report at startup:

```
[CardDB] 24 cards, 2 goalies, 8 abilities, 51 tuning values.
[CardDB] 2 thing(s) need attention in your CSVs:
   - ...
```

The main menu also shows a shortened version of this along the bottom of the
screen. If it says **0 cards**, your unit CSVs are not being read, and the
class select screen will be empty — that is a data problem, not a crash, and
the report will name the file.
