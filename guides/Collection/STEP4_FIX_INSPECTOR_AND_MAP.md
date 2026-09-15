# The parse error, the save inspector, and the content map

**Copy the eight files below in and press F5. The error goes away.**

Then the list is finished — everything you have asked for and everything I
suggested is built. Go and do art.

---

## STEP 1 — Where every file goes

| File | Folder |
|---|---|
| `season_screen.gd` | `src/ui/` *(replace — **this is the fix**)* |
| `match_stats_screen.gd` | `src/ui/` *(replace — **this is the fix**)* |
| `save_inspector.gd` | `src/ui/` |
| `save_inspector.tscn` | `src/ui/` |
| `unlock_progress.gd` | `src/core/` *(replace)* |
| `scene_paths.gd` | `src/core/` *(replace)* |
| `base_screen.gd` | `src/ui/` *(replace)* |
| `Tuning.csv` | `data/` *(replace)* |
| `content_map.html` | `tools/` — beside `csv_workbench.html`. **Not** in `data/` |

No new CSV, so no import step.

---

# THE ERROR — what it was, and why it will not happen again

```
The function signature doesn't match the parent.
Parent signature is "_set(StringName, Variant) -> bool".
```

I wrote a little helper called `_set(label, text)` to put text into a label.

**`_set` is one of Godot's own methods.** Every Object in Godot has
`_set(StringName, Variant) -> bool`. A function of that name with different
arguments does not override it — it collides with it, and Godot refuses to
compile the whole script. That took down both screens and everything that
depends on them, which is why five errors appeared from one mistake.

It is renamed to `_put` in both files, with a comment saying why.

## The part that matters more

My own checking script did not catch it, so I have fixed the script too. It
now knows Godot's method names and their real signatures, and refuses any
script that redefines one differently. I proved it by putting the bug back:

```
_sweeptest.gd:132: func _set(label: Label, text: String) collides with Godot's
own _set(), which takes StringName, Variant. Godot will refuse to compile the
script. Rename it to something that is not one of Godot's method names.
```

**The names to avoid** if you ever write a helper of your own:
`_set` `_get` `_draw` `_init` `_ready` `_process` `_input` `_notification`
`_to_string` `_gui_input`. If a name starts with an underscore and then an
ordinary word, assume Godot has already taken it.

---

# THE SAVE INSPECTOR

**Base → Dev.**

Everything the game remembers about you, on one page, with buttons.

## The row that matters is the top one

**JUMP STRAIGHT TO** — one button per locked thing in the game, closest
first, each showing how far along you are. Press "Pub 80%" and your save is
moved to exactly the state where you have the Pub: counters set to their
targets, flags switched on, unlocks granted.

Testing "what happens when the Brewery opens" is now one click instead of
three matches. Combined with holding `F`, testing content is a minute's work.

It satisfies each requirement **directly** rather than earning it — granting
the Pub does not silently play five matches for you. That is what you want
from a test tool, and it is worth knowing when a number looks lower than you
expected afterwards.

## The rest of the screen

- **Counters** — every number, with `-1` `+1` `+5` `0`
- **Unlocks and flags** — everything you hold, each with "take away"
- **A box at the bottom** — type any name and press *Unlock this*, *Set as a
  flag*, or *Count = 1 / 5 / 10*. This is how you invent a counter that does
  not exist yet and test a CSV row against it before you have written the
  thing that fills it.
- **Wipe the save** — two presses, because there is no undo

Every change is written to disk immediately. The line under the title says
what just happened and where your save file actually is on your computer.

## Before you show the game to anyone

`Tuning.csv` → `show_dev_tools` → `false`

The **Dev** button disappears from the base. The screen stays in the project;
it is just not reachable. Set it back to `true` when you want it again.

---

# THE CONTENT MAP

`tools/content_map.html`. **Double-click it.** Drag in everything from
`res://data/` at once.

One picture of what unlocks what. Arrows run left to right: the thing on the
left is what the thing on the right is waiting for.

Your game right now is **61 things, 63 links, 10 steps deep**, and you can
follow any chain with your eye:

```
matches_played ──> Pub (unlock) ──> Pub (building)
goals_with_brew_fire ──> Brewery ──> Pub
talent_points ──> Brewing Basics ──> Fire Brew (unlock) ──> Fire Brew (brew)
Match 11 ──> The Cup ──> Trophy Room
```

**Save PNG** and **Save SVG** put the picture on disk. The PNG is worth having
in front of you while you write content, and it is a good thing to show
someone who is trying to understand the game in thirty seconds.

## It also finds broken content

Anything **red** is a requirement that nothing in your CSVs ever provides —
everything to the right of it can never be reached. A **dashed** box is part
of a loop, where two rows require each other so neither can ever happen.

Right now it says *"Every requirement in the game is filled by something.
Nothing is stranded."*

I tested that by adding a row requiring something that does not exist. It
found it, named it, and flagged **only** it — no false alarms around it.

## Two things it does deliberately

**Counters that gate nothing are left out.** Most of `Stats.csv` exists to be
*read* on the post-match screen, not to unlock anything — `goals_by_{card}`,
`saves_by_{card}`, `duels_lost`. Drawn in, they were sixty boxes in a column
with no arrows, pushing the actual web off the side of the picture. The
button in the corner puts them back when you want the full inventory.

**Several files of the same kind are merged, not replaced.** The game reads
every CSV in `res://data/`, so splitting your Progression rows across
`Progression.csv` and `Chapter2.csv` is a perfectly good way to work — and the
map sees both.

---

# WHAT I CHECKED

Seven passes, all green.

- **The fix.** The parse error is gone from both files, and the checker now
  catches that exact class of mistake — proven by putting the bug back and
  watching it get named.
- **The map, against your real CSVs**, run in an actual browser: every chain
  above verified link by link, nothing stranded, no loops, the layering in
  the right order, and a deliberately broken row flagged as the only problem.
- Two real bugs in the map found and fixed before you saw it: `{fact}`
  counters like `goals_with_brew_fire` being wrongly called unreachable
  (the map now matches Stats.csv patterns the same way the game does), and
  a second file of the same kind wiping the first.
- Plus the earlier season, camera, controls, stats and unlock passes, the
  static sweep of 54 scripts, and the scene check on all 15 `.tscn` files.

---

# THAT IS THE WHOLE LIST

Everything you asked for and everything I suggested now exists:

| | |
|---|---|
| Season with an ending | done |
| "What you gained" panel | done |
| Camera that follows play | done |
| Visual CSV editor | done — `tools/csv_workbench.html` |
| Designable screen template | done — `season_screen.tscn` is the pattern |
| Speed buttons + fast-forward | done — `1 2 3 4`, hold `F` |
| AUTO pick / watch mode | done |
| Duel input (click, hold, timing) | done |
| Goal kick to Tier III | done |
| Post-match stats screen | done |
| Unlock progress bars | done |
| "Why is this locked?" board | done |
| Flash at the base | done |
| Save inspector | done |
| Content map | done |

**One thing does not exist, and I want to be straight about it:** the
"Play it again" button is a rerun, not a rewatch. Nothing about a match is
recorded, so there is nothing to play back. A true replay means storing the
random seed and every decision and replaying them deterministically — real
work, and worth doing only if you actually want it.

Go and spend the week on art and gameplay. When you come back, the useful
next thing is whatever you actually hit while playing — not the next item on
a list.
