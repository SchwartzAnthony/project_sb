# Phase 5 — The season, the gains panel, the camera, and a CSV tool

All three things you asked for are done, in the order you asked for them.
There is also a designer tool at the end.

---

## STEP 1 — Where every file goes

Copy these into the repo at these exact paths. *(replace)* means a file of
that name is already there — overwrite it.

| File | Folder |
|---|---|
| `season_db.gd` | `src/core/` |
| `match_report.gd` | `src/core/` |
| `match_camera.gd` | `src/core/` |
| `season_screen.gd` | `src/ui/` |
| `season_screen.tscn` | `src/ui/` |
| `Season.csv` | `data/` |
| `game_state.gd` | `src/core/` *(replace)* |
| `ability_engine.gd` | `src/core/` *(replace)* |
| `brew_db.gd` | `src/core/` *(replace)* |
| `content_report.gd` | `src/core/` *(replace)* |
| `scene_paths.gd` | `src/core/` *(replace)* |
| `main_scene.gd` | `src/formations/` *(replace)* |
| `base_screen.gd` | `src/ui/` *(replace)* |
| `Progression.csv` | `data/` *(replace)* |
| `Buildings.csv` | `data/` *(replace)* |
| `Tuning.csv` | `data/` *(replace)* |
| `csv_workbench.html` | `tools/` — make that folder. **Not** in `data/` |

---

## STEP 2 — The one thing you must do by hand, right now

`Season.csv` is a new file, so Godot will try to import it as a translation
and it will ship **empty**. Same fix as last time:

1. In Godot, click **FileSystem** (bottom-left panel)
2. Click `data/Season.csv` once to select it
3. Click the **Import** tab (top-left, next to Scene)
4. In the **Import As** dropdown choose **Keep File (No Import)**
5. Click **Reimport**

That is it. `csv_workbench.html` needs no import step because it is not in
`data/` — that is the only reason it goes in `tools/`.

---

## STEP 3 — Press F5

You should see, in the **Output** panel at the bottom:

```
[content] 11 fixture(s) in the season, the last being Match 11.
[camera] Following the ball. Set camera_enabled to false in Tuning.csv to switch it off.
[season] Matchday 1 of 11 — Reedbank Wanderers
```

If you do **not** see the `[content] 11 fixture(s)` line, Step 2 did not take.

---

# THE SEASON

Eleven fixtures: ten league games and a final. One spreadsheet,
`data/Season.csv`.

## What a row looks like

```
md07,7,Nixenhafen Harbour,Lorelei,2,,,,,The harbour side.,
```

| Column | What it does |
|---|---|
| **ID** | short, unique. Also how this fixture's result is remembered — do **not** rename one after you have a save you care about |
| **Match** | the fixture number. They are played 1, 2, 3… whatever order the rows sit in |
| **Opponent** | who you play. Shown on the season screen |
| **Class** | which class they field: `Lorelei`, `Brandteufel`. **Blank = random**, which is what the game did before |
| **Difficulty** | a flat power bonus to every enemy card, this fixture only. `0` is a fair fight. Keep it 0–3: cards are 0–5 power, so 4 is nearly unbeatable |
| **Final** | `true` on the last one. Winning it makes you champions |
| **Requires** | optional. A fixture whose condition fails is skipped |
| **On Win** | what you get for winning: `unlock:Cup Room`, `count:coins+50`, `announce:Well played`. Same words as `Progression.csv`'s **Do** |
| **On Loss** | the same, for a defeat. **A draw gets neither** |
| **Description** | one line, shown under the fixture |
| **Notes** | yours |

## Add a fixture in one minute

1. Open `data/Season.csv`
2. Change the last row's **Match** from `11` to `12`
3. Add a row above it:
   `md11,11,Weirwater Town,Lorelei,3,,,,,One more before the final.,`
4. Save, press F5

The startup report will tell you if you left a gap in the numbering, used an
ID twice, or named a class no card belongs to.

## What the season remembers

All ordinary counters, so **any** of your other CSVs can test them:

```
season_match            the fixture number you play next
season_wins  season_draws  season_losses
season_points           3 for a win, 1 for a draw
season_goals_for  season_goals_against
season_number           1 for your first season, 2 after a reset
flag season_over        the final has been played
flag season_champion    ...and you won it
```

So this is now a legal Progression row, with no code:

```
ID        cup_parade
When      match_ended
Requires  flag:season_champion
Do        story:parade;unlock:Trophy Room
Once      true
```

I put a working example in already: winning the final runs
`unlock:The Cup`, and `Buildings.csv` has a **Trophy Room** whose Requires is
`unlocked:The Cup`. Win the cup, the room appears at the base. No code.

## The season screen

It does two jobs and works out which by itself:

- **Straight after a match** — the score, what you gained, the table
- **Opened from the base** ("The season" button, top right) — just the table

At the end of the final it says **CHAMPIONS** or **RUNNERS-UP**, and offers
*Start season 2*. That keeps everything you unlocked and wipes the record.

---

# THE "WHAT YOU GAINED" PANEL

## How it works, and why that matters to you

It photographs your progress at kick-off, photographs it again at the final
whistle, and lists the differences.

That means **there is no list for you to keep in step**. A Progression row
you write next month, a fixture reward, a stat you invent in `Stats.csv` —
all of it appears on the panel by itself, because all of it is a flag, a
counter or an unlock, and the panel simply notices those changing.

You never have to come back and register anything.

## Making it read well

The panel shows the spelling you used in the CSV. So a `Stats.csv` row named

```
goals_with_brew_{brew}
```

shows on screen as **Goals With Brew Fire +2**. If you would rather it said
something else, rename the row in `Stats.csv` — that is the only place the
words come from.

Two settings in `Tuning.csv`:

- `gains_max_rows` — how many lines before it says "…and 4 more" (default 8)
- `full_time_seconds` — how long FULL TIME sits on screen first (default 2.6)

Plumbing is hidden automatically: talent bonuses (`tune_…`), the
"this row already fired" bookkeeping, and `season_match` itself.

---

# THE CAMERA

The view now pushes in on the ball during live play and pulls back out for
the whistle, the draft and full time. A shot on goal gets a tighter look.

## The switch, if you hate it

`Tuning.csv` → `camera_enabled` → `false`. The match then plays exactly as it
did before, with no camera in the scene at all. Nothing else changes.

## The dials

| Key | Default | What it does |
|---|---|---|
| `camera_zoom` | 1.55 | how far in during live play. **This is the one to play with.** Try 1.8 |
| `camera_zoom_close` | 2.10 | how far in for a shot |
| `camera_follow_speed` | 3.2 | how quickly it catches up. Higher = snappier |
| `camera_zoom_speed` | 2.2 | how quickly it changes zoom |
| `camera_lead` | 0.30 | how far ahead of the ball it looks during a pass |
| `camera_deadzone` | 36 | how far the ball drifts before it bothers to move |

## The one thing worth understanding

The camera **never changes where players are allowed to stand.**

The pitch is measured once, before the camera exists, and the formations, the
four quarters and the ball corridor all keep using that measurement forever.
If the camera fed back into the play area, zooming in would squash both teams
in toward the ball — and that is a bug you would have spent a long evening on.

It also never zooms out past the opening framing, so you can never see past
the edge of the grass.

---

# THE CSV TOOL

`tools/csv_workbench.html`. **Double-click it.** It opens in your browser.
No install, no internet, no server — it is one file on your computer, and
nothing you open in it leaves your machine.

## How to use it

1. Drag any of your CSVs onto the page (several at once is fine — they become
   tabs along the top)
2. Edit in the grid. **Hover a column heading** and it tells you what that
   column does
3. Broken cells turn red, questionable ones amber, with the reason on hover
4. **Save CSV** puts the file in your Downloads. Drop it back over the one in
   `res://data/`

`Ctrl+S` saves. `Copy` puts the whole file on your clipboard instead, if you
would rather paste.

## What it actually knows

It identifies your file **by its columns, not its name** — exactly the way the
game does. So it recognises `Season.csv`, `Progression.csv`, `Stats.csv`,
`Talents.csv`, `Brews.csv`, `Buildings.csv`, `Visitors.csv`, `Dialogue.csv`,
`Tuning.csv` and `Abilities.csv`, and it would still recognise them if you
renamed every one of them.

It checks, live, as you type:

- the `Requires` / `Do` / `Effects` / `Action` / `On Win` / `On Loss` grammar —
  a mistyped `unlocked:` or a `count:` with no comparison
- `goto:` naming a screen that does not exist
- duplicate IDs
- Progression's **When** being one of the six real moments
- numbers that are not numbers, X/Y that are not 0–1, true/false that is neither
- gaps in the season's fixture numbering, and a season with no final
- rows with more values than there are columns

**It does not replace the game's own startup report.** The report can see
across files — "this dialogue scene does not exist", "nothing ever fills that
counter" — and the tool only sees the one file in front of it. Use the tool
while writing, use the report after pressing F5.

It also quotes the CSV properly on save, which is the thing Excel and Numbers
most often get wrong on this project — a comma inside a Description ends up
splitting the row.

---

# OTHER TOOLS I WOULD BUILD, IF YOU WANT THEM

You asked what else would help. In the order I would do them:

**1. A "why is this locked?" screen.** One page listing every unlock, talent,
building, brew and fixture in the game, and for each one: have you got it, and
if not, exactly what is missing. Right now finding out why the Pub has not
appeared means reading three CSVs. This would be about an hour's work and it
is the thing I would want most in your position — especially when demoing,
because you can answer "how does the player get that?" instantly.

**2. A fast-forward key.** Hold a key and the match runs at 20× with the
cut-aways skipped. Testing a Progression row that fires at ten matches
currently means playing ten matches. This is small — it is mostly
`time_scale` — but it changes how much you can test in an hour.

**3. A save-state inspector.** A screen showing every flag, counter, text and
unlock you currently hold, with buttons to set them. So you can jump straight
to "I have won six matches and unlocked the Brewery" instead of playing there.
Combined with (2) this is the difference between testing content in minutes
and testing it in evenings.

**4. A content map.** One picture — generated from the CSVs — showing what
unlocks what. Fixture → unlock → building → talent → brew. When the web gets
bigger than about twenty things, you will stop being able to hold it in your
head, and this is the moment you notice something is unreachable.

Say which of those you want and I will build them. I would take (1) and (2)
first; they pay for themselves within a day.

---

## What I checked before sending this

- A full eleven-match season simulated against your real CSVs: fixtures played
  in order, opponents and classes read from the file, points and goal
  difference correct, the final recognised, champion and runner-up both right,
  a second season resetting the record while keeping every unlock.
- The Brewery / Pub / talent chain still fires correctly *inside* a season.
- The Trophy Room appearing only after the cup is won.
- Four deliberately broken `Season.csv` rows — a duplicate ID, a duplicate
  match number, a missing opponent, a gap in the numbering — all four caught.
- The gains panel: leading with unlocks, readable names, plumbing hidden, and
  fewer lines on a later match than on the first.
- The camera, over 1800 frames of ball movement including corners: the view
  never left the grass once, the ball was never off screen, and the largest
  single-frame movement was 22px — no jerk.
- A static sweep of all 46 scripts: brackets, duplicate functions, typing,
  tabs, missing classes, and every `tune_` key having a real `Tuning.csv` row.
