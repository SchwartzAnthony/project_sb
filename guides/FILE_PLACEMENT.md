# Where every file goes

Copy the files into the folders below. Order does not matter — do them all,
then launch. Nothing here overwrites work you have done yourself except where
it says **replace**.

---

## Delete these first

They were part of the broken menu and are no longer used:

```
res://src/ui/menu_button.gd
res://src/ui/menu_button.tscn
```

If your old `main_menu.tscn` and `main_menu.gd` are already in place, the new
ones in this delivery **replace** them.

---

## `res://data/`   — everything you will edit as a spreadsheet

| File | What it holds | New? |
|---|---|---|
| your unit CSVs | the cards | you already have these |
| `Goalies.csv` | keepers | you already have this |
| `Abilities.csv` | ability definitions | — |
| `Animations.csv` | which sheet row is which animation | — |
| `Tuning.csv` | every number in the game | **replace** — has new field rows |
| `MenuConfig.csv` | the main menu's buttons | **replace** — new Quick Match row |
| `ClassInfo.csv` | class blurbs and banner art | **new** |
| `Collection.csv` | which cards you have unlocked | optional, you create it |

---

## `res://src/core/`   — the engine

| File | New? |
|---|---|
| `card_database.gd` | — |
| `player_data.gd` | — |
| `goalie_data.gd` | — |
| `ability_data.gd` | — |
| `ability_engine.gd` | — |
| `anim_spec.gd` | — |
| `field_bounds.gd` | — |
| `menu_support.gd` | **new** — shared CSV reading, portraits and menu colours |
| `team_selection.gd` | **new** — carries your chosen team into the match |
| `scene_paths.gd` | **new** — the one place that knows where each screen lives |

---

## `res://src/ui/`   — every screen

| File | New? |
|---|---|
| `main_menu.gd` + `main_menu.tscn` | **replace** — the old ones were broken |
| `class_select.gd` + `class_select.tscn` | **new** |
| `team_builder.gd` + `team_builder.tscn` | **new** |
| `card_popup.gd` | **new** — no scene file, built in code |
| `rps_clash.gd` + `.tscn` | — |
| `duel_arena.gd` + `.tscn` | — |
| `shootout_view.gd` + `.tscn` | — |
| `player_card_ui.tscn` | yours already |

---

## `res://src/units/`

`player_unit.gd` / `.tscn`, `goalie_unit.gd` / `.tscn`, `ball.gd`,
`sprite_animator.gd` — all unchanged from before.

---

## Wherever `main_scene.tscn` already lives

**Do not move it, and do not overwrite `main_scene.gd`.** It needs six small
hand-edits instead: see **MAIN_SCENE_PATCH.md**.

My scripts guess `res://src/formations/main_scene.tscn`. Your project has a
`res://src/match/` folder, so that guess may be wrong — and it does not matter.
The menus look the scene up through `scene_paths.gd`, which searches `res://`
if its guess misses, uses what it finds, and prints the real path in the Output
panel. Paste that path into the top of `scene_paths.gd` to skip the search
next time.

---

## `res://assets/menu/`   — create this folder

Optional art. Everything works without it.

```
background.png       behind the main menu
button_start.png     260 x 68
button_quick.png
button_quit.png
banner_<class>.png   900 x 300, one per class
```

---

## Project root

`test_run.gd` and `export_sheet_preview.gd` — command-line tools, unchanged.

> ⚠ Neither of these may be set as the Main Scene or added as an Autoload.
> Both call `quit()` on purpose, so the game would close instantly.

---

## Then, in the Godot editor

1. **Project → Project Settings → General → Application → Run → Main Scene**
   Set it to `res://src/ui/main_menu.tscn`.
2. **Project → Project Settings → Globals → Autoload** — confirm it is empty.
3. Apply the six edits in **MAIN_SCENE_PATCH.md**.
4. Press **F5**.

---

## The order to read the docs

| Read this | When |
|---|---|
| **TROUBLESHOOTING.md** | first, and any time something closes or won't load |
| **MAIN_SCENE_PATCH.md** | the six hand-edits to `main_scene.gd` |
| **MENU_GUIDE.md** | changing the menus, adding a class, unlocks |
| **FIELD_AND_MENU_SETUP.md** | the pitch size and keeping players inside the lines |
| **CSV_GUIDE.md** | cards, abilities, balance |
| **ARTIST_GUIDE.md** | drawing animations and pointing `Animations.csv` at them |
| **GAME_DESIGN.md** | the whole design, for handing to a new chat |

---

## What "working" looks like

| Step | You should see |
|---|---|
| F5 | main menu, with a card count along the bottom |
| Start Game | classes on the left, three Stars and a formation on the right |
| click a Star | its full card, ability written out in a sentence |
| LOCK IN | Tiers I–IV down the left, Star tier locked in amber, collection on the right |
| READY | the match starts with exactly the players you slotted |
| HOLD UP! | the pitch stops dead while you choose, then resumes |

If the card count along the bottom of the main menu says **0 cards**, your unit
CSVs are not being read — the Output panel will name the file.
