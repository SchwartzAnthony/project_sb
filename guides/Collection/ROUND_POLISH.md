# POLISH ROUND — nine fixes, five new systems

Worked in four phases, in this order and for this reason:

1. **The bugs first**, because two of them were feedback bugs — you could not
   tell the game was working.
2. **One button style**, because five of the later items add buttons and
   there was no point adding them to an inconsistent set.
3. **The new screens** (seasons, save slots) on top of that style.
4. **The two systems that touch everything** — controller and language —
   last, so they covered everything that had just been built.

---

## 1. WHERE THE FILES GO

**NEW — `res://src/core/`**

| File | |
|---|---|
| `controller_focus.gd` | moving the highlight with a stick or the arrows |
| `localisation.gd` | the language layer (`class_name Loc`) |
| `season_book.gd` | reads `Seasons.csv` |
| `save_slots.gd` | which save you are playing |

**NEW — `res://src/ui/`**

`season_picker.gd` + `.tscn`, `slot_screen.gd` + `.tscn`

**NEW — `res://data/`**

`Seasons.csv`, `Language.csv`, `tutorial/Dialogue.csv` (replaces the stub)

**REPLACES** — `menu_support.gd`, `menu_escape.gd`, `scene_paths.gd`,
`season_db.gd`, `team_roster.gd`, `content_report.gd`, and every loader that
had a `reload()` (see §2); `main_menu.gd`, `base_screen.gd`, `season_screen.gd`,
`match_stats_screen.gd`, `unlock_board.gd`, `bounty_board.gd`, `pub_screen.gd`,
`talent_screen.gd`, `save_inspector.gd`, `dialogue_view.gd`, `duel_arena.gd`,
`settings_screen.gd`, `class_select.gd`, `team_builder.gd`;
`adventure_scene.gd`, `adventure_encounter.gd`, `adventure_strike.gd`;
`Season.csv`, `MenuConfig.csv`, `Tuning.csv`

**Reference, not code:** `ICONS_WANTED.csv`, `SOUNDS_WANTED.csv`

---

## 2. THE TUTORIAL CRASH — I had this wrong

```
tutorial_base.gd:93 @ enter(): Cannot reload script while instances exist.
```

Every `class_name` in Godot is *also* a Script object, and **Script already
has a built-in `reload()`**. So `BaseDB.reload()` resolved to *that* — which
is why it errored — and my own static `reload()` was never called at all. The
tutorial was quietly loading the real spreadsheets the whole time.

Renamed to **`reload_files()`** in all thirteen loaders. If you add a loader
of your own, avoid `reload()`, `free()`, `duplicate()` and `get_name()` for
the same reason. There is a note saying so on every one of them.

---

## 3. THE TWO FEEDBACK BUGS

**Stamina did not move when a player was hit.** The run holds the stamina;
the walkers on the pitch only *draw* it — and nothing put the two in step
until the whole fight was over. The fight now emits `party_changed` the
instant anything changes a player, the scene repaints every bar, and a red
number rises off whoever took it with a shove backwards. Healing and reviving
show a green number the same way.

**The ball stopped dead while you chose a target.** It was only passed while
the party was RUNNING. It is passed in every state now except while a shot is
genuinely in the air — `adventure_strike.gd` puts a `busy` mark on the ball
while it is mid-flight and takes it off when it lands, so a pass can never
yank a shot out of the sky.

---

## 4. THE SCREEN FIXES

**Two "back to base" buttons at full time.** When a match did not go in the
table, Continue *also* said "Back to the base" — two identical buttons side
by side. Continue is the one that stays; the separate Home button now only
appears when Continue is going somewhere else.

**"FULL TIME" on the season page** was left over from the last match you
played. The title is the competition's own name now; the scoreline under it
already says what the last result was.

**Back moved to the bottom-left** on the season page, so only "Play: *team*"
sits in the middle of the bottom — matching every other screen.

**"WHY IS THIS LOCKED" → "ACHIEVEMENTS"**, and its "back to base" is the
standard bottom-left Back.

**Adventure's "KIT" → "Items", bottom centre.** It opens the same list the
ITEMS button opens during a fight, and two names for one thing is one too
many.

---

## 5. ONE BUTTON STYLE

Everything now uses the **"Play a match" style** you asked for — a small
picture on the left, the words on the right, one button. Four helpers in
`menu_support.gd` do it:

```
MenuSupport.footer_bar(self, on_back)     the standard bottom row, Back on the left
MenuSupport.footer_button(icon, label)    anything else in that row
MenuSupport.footer_primary(icon, label)   the one that matters, lit in accent
MenuSupport.restyle(button, icon, label)  gives a .tscn button the same face
```

That last one is the useful one. The season table and the full-time report
have their buttons laid out inside their scene files, which cannot be
replaced — so they are **restyled and repositioned from code**, and you never
have to open those `.tscn` files to keep them in step. `pin_bottom_left()`,
`pin_bottom_centre()` and `pin_bottom_right()` place them, and they lift a
button out of its container first, because a Control inside an HBoxContainer
has its position rewritten every frame and anchors on it do nothing.

**The base is the exception you asked for** — its buttons stay across the top.

---

## 6. THE SEASONS SHELF

`THE SEASON` on the base now opens a **shelf of competitions**, laid out like
the talent tree, and the table you already had is what opens when you pick
one.

All of it is `res://data/Seasons.csv`:

| Column | |
|---|---|
| `ID` | fixtures name this in their own `Season` column |
| `Name`, `Art`, `Colour` | the tile. A shield with the initial is drawn until the art exists |
| `Requires` | the usual language — `unlocked:X`, `count:z>=3`. Blank = always open |
| `Row`, `Column` | **where the tile sits.** This is the talent-tree part |
| `After` | draws the joining line back to another season |
| `Matches` | for the tile. Blank = counted from `Season.csv` |

**Add a row, get a season. There is no limit.** Put one on Row 7 and the
shelf grows a seventh row. The shipped file has five — one open, four locked
— laid out as:

```
              county_league
winter_cup  |             |  coast_division
              inland_shield
              the_crown
```

`Season.csv` gained a **`Season`** column and every existing fixture is
tagged `county_league`. Only the chosen season's fixtures are loaded, so the
table, "next up" and the final all work exactly as they did — they simply
have one competition in front of them. **A blank `Season` cell means "the
first one",** so a fixture list written before this still works.

---

## 7. CONTROLLER NAVIGATION

Stick, d-pad and arrow keys move the highlight; `confirm` presses it;
`cancel` is the screen's Back button.

It does **not** use Godot's neighbour properties, which would mean wiring
every button to every other button on every screen by hand. It works out the
nearest button in the direction you pushed from where the buttons actually
are — so a screen that builds its buttons from a CSV is navigable the moment
the CSV changes.

Two details worth knowing:

- **Moving the mouse clears the highlight**, and pushing the stick brings it
  back. A focus box sitting on a button you are not using looks like a bug.
- **A held stick is one step, not forty.** It has to return to the middle
  before it counts again.

`icon_button()` had `focus_mode = FOCUS_NONE`, which is what stopped any of
this working. It is `FOCUS_ALL` now with an accent-coloured focus box.

**No screen has to do anything** — `MenuEscape.install(self)` installs it, and
that call is now on every screen. Two screens take a lighter version:
`dialogue_view` and `duel_arena` have their own use for the pause key and
would have lost it.

---

## 8. LANGUAGES

`res://data/Language.csv`, **one column per language**:

```
Key,English,Deutsch,Notes
back,Back,Zurück,The Back button on every screen
```

Add a column headed `Français`, fill it in, and French appears in
**Settings → Language**. There is no list of languages anywhere in the code —
the columns of that file *are* the list. The shipped file has 55 keys in
English and German.

**The other spreadsheets are translated in place**, with a dotted column:

```
Name,Name.Deutsch
Mire Grub,Sumpfmade
```

One rule, everywhere. `Loc.translated(row, "Name")` is what reads it.

**Settings → Language → "List the missing words"** prints every key the game
asked for that has no row yet, already formatted to paste into the
spreadsheet. That is your to-do list: play a screen, press the button, paste.

I did not use Godot's own translation importer on purpose — it wants CSVs
shaped its way in a folder configured in Project Settings, re-imported from
the editor every time you add a word. It is also what caused your
`ScratchNames.Second.translation` warning (see §11).

---

## 9. SAVE SLOTS

**Start** on the title screen now asks which save. `slot_count` in
`Tuning.csv` says how many — three out of the box, and setting it to 1 gives
you a one-tile screen rather than a different code path.

**Slot 1 is your existing save.** It keeps the old paths
(`user://story_state.json`, `user://teams.json`) so nothing you have already
played is lost. Slots 2 and up live in `user://slot2/` and so on.

Each tile shows how many matches and unlocks are in it and when it was last
played. Erasing asks twice. **Settings are not per slot** — the language, the
keys, the volume and the palette are things about you, not about a
playthrough.

---

## 10. ICONS, SOUNDS AND THE TUTORIAL

**`ICONS_WANTED.csv`** — 32 rows: every picture the game looks for, which
folder, which screen uses it, what stands in for it now, and what it should
show. Drop a PNG in and it is used at once; there is no code and no reimport.
`back.png` is the one to draw first — it is on every screen.

**`SOUNDS_WANTED.csv`** — the 24 sounds `Audio.csv` already asks for, with
the bus and the moment each one plays. Every row already works; the game is
silent only because the files are not there.

**The tutorial dialogue** is written: five scenes, twenty lines, with choices
that let you jump between them — the ladder, how a match goes, what Adventure
is, and a way out of each. It lives in `data/tutorial/Dialogue.csv` and is
only loaded inside the tutorial base.

---

## 11. THE TWO EDITOR WARNINGS

```
UID duplicate detected between res://data/ScratchNames.Second.translation
and res://data/ScratchNames.csv
UID duplicate detected between res://data/Teams.csv and res://data/Talents.csv
```

**Both are Godot importing your data CSVs as translation files.** `.csv` is
handled by the CSV Translation importer by default, so Godot looked at
`ScratchNames.csv`, decided `Second` was a locale, and generated
`ScratchNames.Second.translation`. It is harmless but it will keep
multiplying as you add spreadsheets.

**The fix, once, in the editor:**

1. In the FileSystem dock, select **every CSV in `res://data/`** (click the
   first, shift-click the last).
2. Go to the **Import** tab (beside Scene, top-left).
3. Set **Import As** to **`Keep File (No Import)`**.
4. Press **Reimport**.

The game reads these files itself with `FileAccess`, so it does not want or
need Godot's importer at all. The `Teams.csv` / `Talents.csv` collision is a
stale `.import` from a copied file and clears up in the same pass.

Do this for `data/tutorial/` too.

---

## 12. FIRST RUN CHECKLIST

1. Copy the files in. Do §11 first — it takes a minute and stops the warnings.
2. Press F5. The Output panel should print `[language]`, `[seasons]`,
   `[combos]` and `[keys]` lines.
3. **Start** → the save slot screen. Pick slot 1; your existing game is in it.
4. Base → **The season** → the shelf. Four tiles locked with their reasons,
   County League open. Click it — the table opens with its own name at the top
   and Back on the bottom-left.
5. Full time after a friendly → **one** way home, not two.
6. Adventure → a fight. Watch a player's bar drop when they are hit, and the
   ball keep moving while you choose a target. **Items** is bottom centre.
7. Achievements → titled ACHIEVEMENTS, Back bottom-left.
8. **Unplug nothing** — push an arrow key on any screen. A gold box appears on
   a button and the arrows walk it about. Move the mouse and it goes away.
9. Settings → **Language** → Deutsch. The screen redraws in German.
10. Main menu → **Tutorial**. No red errors in the Output panel this time.
