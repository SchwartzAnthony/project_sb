# Drawing for the close-up views

No code. You draw animation frames on your spritesheets, then describe each
one as a row of `Animations.csv`. The game asks for animations **by name**.

---

## Step 1 — find out which row is which

You already have 39 rows drawn per card, and only you know what they are. Run
the preview tool once:

```
godot --headless --script res://export_sheet_preview.gd
```

(or open `export_sheet_preview.gd` in Godot and use **File → Run**.)

It writes one labelled PNG per card into `res://sheet_previews/`. Each output
row shows, down the left margin:

- **blue digits** — the row number (`00`, `01`, … `38`)
- **amber digits** — how many frames are actually drawn on that row (`5f`, `12f`)

…then the first, middle and last drawn frame of that row.

Open one, scroll, and write down which row is your run cycle, your kick, and
so on. The tool only reads your art; it never changes it.

---

## Step 2 — fill in `Animations.csv`

```
Animation,Unit Type,Sheet Columns,Sheet Rows,Row,First Frame,Frames,FPS,Loop,Notes
run,,12,39,8,0,12,14,true,Both units run at each other
```

| Column | Meaning |
|---|---|
| `Animation` | the **name the game asks for** — see the list below |
| `Unit Type` | blank = every class. Fill it in to override for one class only. |
| `Sheet Columns` / `Sheet Rows` | your grid. Defaults to 12 × 39. |
| `Row` | which row of the sheet (0 at the top) |
| `First Frame` | which column the animation starts on (0 at the left) |
| `Frames` | how many frames it runs for |
| `FPS` | frames per second |
| `Loop` | `true` to repeat, `false` to play once and hold the last frame |

Because `Unit Type` can override, you can give one class a different run cycle
without touching the others — add a second `run` row with `Brandteufel` in the
`Unit Type` column.

### The names the game asks for

| Name | When it plays | Loops? |
|---|---|---|
| `idle` | **the fallback for everything.** If a name below is missing, `idle` is used. If `idle` is missing too, a still frame is shown. | yes |
| `run` | both units running at each other as the duel window opens | yes |
| `ability` | when that unit's ability lights up | no |
| `win` | on the winning panel after the numbers are compared | no |
| `lose` | on the losing panel | no |
| `kick` | striking the ball | no |
| `kick_back` | the striker **seen from behind** in the shootout (camera over their shoulder). Falls back to `kick`. | no |
| `keeper_ready` | first-person keeper waiting for the shot | yes |
| `keeper_dive` | first-person keeper diving | no |

Nothing here is required. Every missing animation degrades to `idle`, and a
missing `idle` degrades to a still frame — so the game always runs and you can
add animations one at a time.

---

## Step 3 — how the zoom works (so your art looks right)

Your frames are 128 × 64, but the footballer only fills a small part of that.
The close-up does two things automatically:

1. **Crops to the drawn character.** It scans the frames of the animation,
   finds the box that actually has pixels in it, and crops every frame of that
   animation to the *same* box. Measured on your current art, that's roughly
   25 × 47 or 43 × 38 instead of the empty 128 × 64 cell.

   Using one shared box for the whole animation is deliberate — a per-frame box
   would make the figure jitter as its silhouette changed.

2. **Scales by a whole number, nearest-neighbour.** A 6× blow-up is exactly six
   hard pixels per source pixel. No blur, no half-pixel shimmer.

**What this means for you:** draw the character anywhere in the cell you like,
and keep the animation's frames roughly consistent in size. If one frame of a
run cycle has an arm flung far out, the shared crop box grows to fit it and the
figure sits slightly smaller for the whole animation. That's usually fine, but
it's the one thing that will make a close-up look "zoomed out" unexpectedly.

---

## The shootout keeper

The first-person keeper is a **separate sheet**, because it's a different view
from the pitch sprite.

1. Draw it as a grid — any size. The shipped rows assume 4 × 4.
2. Save it in `res://assets/goalies/`.
3. Add a **`Shootout Artwork`** column to `Goalies.csv` naming the file.
4. Point `keeper_ready` and `keeper_dive` at its rows in `Animations.csv`,
   setting `Sheet Columns` / `Sheet Rows` to match your grid.

Until you do, the shootout draws a plain coloured block where the keeper goes,
so the whole sequence is playable now.

The striker in the shootout is drawn from your **normal card sheet** using
`kick_back`. Draw a from-behind kick on a spare row and point `kick_back` at
it; until then it falls back to your normal `kick`.

---

## Pacing

Every pause is a row in `Tuning.csv` — nothing is baked in.

| Row | What it controls |
|---|---|
| `arena_speed` | overall cut-away speed. `2` = twice as fast |
| `arena_run_in_seconds` | the run-at-each-other beat |
| `arena_reveal_seconds` | power numbers appearing |
| `arena_ability_seconds` | each ability lighting up |
| `arena_compare_seconds` | final numbers settling |
| `arena_result_seconds` | how long WIN / LOSE holds |
| `shootout_*_seconds` | the four beats of the shootout |
| `verdict_seconds` | how long GOAL / MISS holds |
| `arena_skip_speed` | speed while holding SPACE / clicking |
| `duel_arena_enabled` | `false` turns the duel cut-away off entirely |
| `shootout_enabled` | `false` turns the shootout off entirely |

**Holding SPACE, or clicking, fast-forwards the cut-away you're watching.**
Nothing is skipped silently — it just runs at `arena_skip_speed`.

There are 36 duel cut-aways in a match, so if it starts to drag while you're
testing, raise `arena_speed` rather than switching them off.
