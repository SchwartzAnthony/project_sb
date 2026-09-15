# FINALISING THE PROTOTYPE — what changed and where it goes

Everything you asked for in the last message is done. This file is the
drop-in list, then the answer to your real question: *what is still missing
before you can stop asking me and just design?*

---

## 1. WHERE EVERY FILE GOES

Copy these into your project. Anything marked **replaces** should overwrite
the file that is already there.

### `res://src/core/`

| File | |
|---|---|
| `team_roster.gd` | NEW — your saved teams |
| `team_builder_handoff.gd` | NEW — tells the builder which team it is editing |
| `menu_escape.gd` | NEW — Escape, and the one line that applies settings |
| `game_keys.gd` | NEW — the keys, from `Keys.csv` |
| `game_settings.gd` | NEW — screen / sound / colour / controller |
| `tutorial_base.gd` | NEW — the enclosed tutorial |
| `menu_support.gd` | **replaces** |
| `scene_paths.gd` | **replaces** |
| `game_state.gd` | **replaces** |
| `base_db.gd` | **replaces** |
| `dialogue_db.gd` | **replaces** |

### `res://src/ui/`

| File | |
|---|---|
| `team_select.gd` + `team_select.tscn` | NEW — CHOOSE YOUR TEAM |
| `settings_screen.gd` + `settings_screen.tscn` | NEW |
| `team_builder.gd` | **replaces** |
| `class_select.gd` | **replaces** |
| `base_screen.gd` | **replaces** |
| `main_menu.gd` | **replaces** |
| `pause_menu.gd` | **replaces** |
| `match_hud.gd` | **replaces** |
| `dialogue_view.gd` | **replaces** |
| `player_card_ui.gd` + `player_card_ui.tscn` | **replaces BOTH** |

> **The card scene is replaced on purpose.** The old `player_card_ui.tscn`
> had the card's layout nailed into it by hand, which is why the card on the
> pitch never quite matched the card in the builder. The new one is an empty
> Control that draws itself. Delete the old `.tscn` — do not merge them.

### `res://src/adventure/`

`adventure_scene.gd`, `adventure_walker.gd`, `adventure_strike.gd`,
`adventure_encounter.gd` — all **replace**.

### `res://src/formations/`

`main_scene.gd` — **replaces**. One change only: it no longer draws a second
Star badge on top of the one the card draws itself.

### `res://data/`

| File | |
|---|---|
| `Keys.csv` | NEW |
| `MenuConfig.csv` | **replaces** — Start / Settings / Tutorial / Quit |
| `Tuning.csv` | **replaces** — 9 new rows at the bottom |
| `tutorial/Buildings.csv` | NEW — make the `tutorial` folder |
| `tutorial/Visitors.csv` | NEW |
| `tutorial/Dialogue.csv` | NEW |

---

## 2. WHAT EACH CHANGE ACTUALLY DOES

### The main menu is Start / Settings / Tutorial / Quit

Four rows in `MenuConfig.csv`. **Start** opens the base, **Settings** opens
the new screen, **Tutorial** opens the tutorial base, **Quit** closes the
game. Move a button by changing its X and Y in that file; add a fifth by
adding a row.

### The base

* The **Main menu** button is gone. Escape leaves the game now, so it was a
  door to nowhere.
* The buttons are **centred across the top** and each one is **a picture and
  a word in a single button**. The picture is a drawn symbol until you make
  the art: drop `play.png`, `season.png`, `adventure.png`, `unlocks.png`,
  `teams.png` or `dev.png` into `res://assets/icons/` and that button wears
  it. Nothing to change in code — the button asks for `play|▶`, meaning
  *`play.png` if it exists, this symbol until then*.
* **Play a match** now goes to the team shelf, not the class picker.
* A new **Your teams** button, for building without playing.

### Escape

| Where | What Escape does |
|---|---|
| In a match | Opens the sub menu — speed, AUTO, quit the match |
| Anywhere else | Asks "quit the game?" — Escape again, or the button, closes it |

The warning panel is there because Escape is a key people hit by accident.
If you would rather it close instantly, set `escape_quits_instantly` to
`true` in `Tuning.csv`.

### CHOOSE YOUR TEAM replaces CHOOSE YOUR CLASS

A team is a thing you own now — a name, a badge, a class and nine regulars,
kept in `user://teams.json`.

| Button | What it does |
|---|---|
| **LOCK IN** | Straight to the match. No detour through the builder. |
| **Edit team** | Opens the builder on the team you picked. |
| **Create team** | The class picker, then the builder, on a new team. |

With nothing saved yet, **Create team** is the only button on the screen.

The class picker is now what it always should have been: the first step of
making a team, which you do once. Its button says **USE THIS CLASS**, not
LOCK IN, because locking in means taking the pitch.

### Naming and badging a team

Top of the builder: a text field for the name and a **Choose badge** button.
Twelve shapes, six colours, all drawn in code so a team has a badge from day
one. Drop a PNG into `res://assets/team_icons/` named after a shape and that
shape becomes your artwork instead.

Both the name and the badge are what you see on the shelf.

The builder has two ways out now: **Save** keeps the team and goes back to
the shelf, **LOCK IN** keeps it and walks straight out onto the pitch. Back
saves too — a half-built team is never lost, the shelf just marks it as not
ready to play.

### Bigger cards

Two rows of `Tuning.csv`:

```
card_width     220
card_height    290
```

Change them, press F5, the cards on the pitch are bigger. The portrait, the
writing and the Star badge all grow with the card, so it reads bigger rather
than just being wider. The Adventure fight has its own pair
(`adventure_card_width` / `adventure_card_height`) so you can keep the two
matching or deliberately differ.

### Adventure scale

Four more rows, and these are the ones you asked about:

```
adventure_lane_top       250     was 300 — the band starts higher
adventure_lane_height    540     was 380 — much deeper, more room to crisscross
adventure_player_size     26     was 17 — a player reads like a player
adventure_ball_size        7     was 8 — the pitch ball is 6, so these now match
```

The stamina bar, the power number and the enemy spacing all scale off the
player size, so raising it does not leave a big circle with tiny writing in
it or a thread of a health bar under it.

### Settings

Five tabs, and none of them has anything typed into the screen:

* **Keys** — every row of `Keys.csv`. Click a key, press a new one. A key
  already doing another job is refused and it tells you which. "Put every
  key back" undoes the lot.
* **Screen** — window mode, size, vsync, frame cap.
* **Sound** — master, music, effects, voice. These are the four buses your
  `Audio.csv` already uses.
* **Colour** — colour-blind palettes and high contrast. Worth knowing why
  this exists: Tier II is a green and Tier III is an amber, which is exactly
  the pair red-green colour blindness merges. Picking a palette repaints
  every screen in the game, because every screen reads its colours from one
  place.
* **Controller** — on/off, stick deadzone, vibration, and a list of what
  each button does (from the Default Button column of `Keys.csv`).

Everything saves the moment you change it, into `user://settings.json`.
There is no Apply button because there is nothing to apply.

**Adding a key is a row in `Keys.csv`.** It then exists, is rebindable, is
on the settings screen under whatever its Group column says, and answers to
a controller button. No code.

### The tutorial base

Press Tutorial and you are in a base that looks and works exactly like the
real one — because it *is* the real one. Two things are swapped underneath:

* the spreadsheets come from `res://data/tutorial/` instead of `res://data/`
* progress goes to `user://tutorial_save.json` instead of your own save

So nothing you do in the tutorial can touch your real game, and the tutorial
cannot drift out of date, because it is the game with different furniture.

**To write the tutorial you write two spreadsheets.** `tutorial/Buildings.csv`
is what stands there; `tutorial/Visitors.csv` is who explains it;
`tutorial/Dialogue.csv` is what they say. I have put a starting version of
all three in. Rewrite them freely — there is no tutorial script and no step
list anywhere in the code.

There is a **Leave tutorial** button on the base's top row, and only there.

---

## 3. THE ANSWER: WHAT IS STILL MISSING

You asked, seriously, what else is needed to finalise this prototype draft so
you can focus on design and art. Here is the honest list, shortest first.

### Nothing is blocking you. These four are worth an hour each.

**1. Art slots that are still empty.** Not code — the game runs without any
of it and draws a placeholder. But for a presentation the placeholders are
what people will notice:

* `assets/icons/` — `play`, `season`, `adventure`, `unlocks`, `teams`,
  `back`, `edit`, `new_team`, `exit`, `keys`, `screen`, `sound`, `colour`,
  `controller`. Small square images. Every one has a drawn symbol standing in.
* `assets/menu/` — `button_start`, `button_settings`, `button_tutorial`,
  `button_quit`, `background`.
* `assets/team_icons/` — any of the twelve badge shapes you want as art.
* `assets/base/background.png` and one image per building.

**2. A save/load slot screen.** There is one save. For a prototype that is
fine, and for a presentation it may even be preferable. If you want three
slots it is an afternoon, and it belongs on the main menu between Start and
Settings.

**3. Sound files.** `Audio.csv` is fully wired and every cue is named; the
game is silent because the files are not there yet. Dropping WAVs into
`assets/audio/` with the names in that spreadsheet turns the whole thing on.

**4. A pass over `Progression.csv`.** The content audit is clean now, but
the story beats are still mostly the ones I wrote as examples. That is
design work, not code, and it is exactly what you should be spending the
time on.

### Things that are deliberately not built, and why

* **Multiplayer / online.** Out of scope for a prototype.
* **Controller navigation of menus.** The buttons respond to a controller,
  but moving the *highlight* between them with a stick is not wired. Mouse
  and keyboard is the whole story for a presentation.
* **Localisation.** All the player-facing words are in the CSVs already,
  which is most of the work, but there is no language switch.

### What I would do next if you asked me

In this order, and none of it is urgent:

1. Fill the icon folder — biggest visual return for the least effort.
2. Write the tutorial dialogue properly. Three or four scenes.
3. Three save slots.
4. Sound.

Everything else in the game is now reachable from a spreadsheet.

---

## 4. FIRST RUN CHECKLIST

1. Copy the files in, overwriting where the table says **replaces**.
2. Delete the old `player_card_ui.tscn` if your editor kept a copy.
3. Make the `res://data/tutorial/` folder and put the three CSVs in it.
4. Press F5. Watch the Output panel — it prints:
   * `[keys] N action(s) ready.`
   * `[adventure] Lane 250 to 790, player radius 26, ball radius 7.`
   * `[teams] Saved N team(s) to ...` the first time you save one.
5. Main menu → Start → the base. The buttons are across the middle of the
   top and each has a symbol in it.
6. Play a match → CHOOSE YOUR TEAM → Create team → pick a class → name it,
   badge it, LOCK IN. You should go straight to the pitch.
7. Back at the shelf, the team is listed with its badge. LOCK IN goes
   straight to the pitch; Edit team opens the builder.
8. Press Escape anywhere outside a match. You should get the quit panel.
9. Press Escape inside a match. You should get the sub menu instead.
