# TWO THINGS LEFT. Both are copy-and-paste — nothing to delete.

I pulled your repo. Here is exactly what is in it and what these files do.

---

## 1. THE ERROR — nine leftover scripts, not one

```
Class "GoalieUnit" hides a global script class
```

`goalie_unit.gd` is the one Godot is complaining about right now, but **it is
one of nine**. Your project still has two copies of each of these:

```
adventure_db.gd   adventure_run.gd   enemy_pick_layer.gd
base_db.gd        dialogue_choice.gd dialogue_line.gd
zone_overlay.gd   sprite_animator.gd goalie_unit.gd
```

Godot registers a `class_name` once. A second copy anywhere gives that error
and refuses to load one of them. It reports them one at a time, so clearing
`goalie_unit` on its own would just hand you the next.

**This is my fault.** A zip of mine guessed the wrong folder for each of
these, so instead of overwriting your copy it dropped a second one beside it.

### The fix, without deleting anything

I asked you to delete them last time and I should have done this instead.
This zip contains **nine emptied-out versions of the leftover copies**. Each
one keeps the file where it is but takes the `class_name` off it, so the
clash disappears the moment you paste them in. Each also explains, in the
file itself, what it is and that you can delete it whenever you feel like it.

They extend the same base class the originals did, so no scene pointing at
one of them can break.

**Your real scripts are untouched.** The nine that survive are:

| Kept (the real one) | Emptied (the leftover) |
|---|---|
| `src/adventure/adventure_db.gd` | `src/core/adventure_db.gd` |
| `src/adventure/adventure_run.gd` | `src/core/adventure_run.gd` |
| `src/adventure/enemy_pick_layer.gd` | `src/core/enemy_pick_layer.gd` |
| `src/core/base_db.gd` | `src/ui/base_db.gd` |
| `src/core/dialogue_choice.gd` | `src/ui/dialogue_choice.gd` |
| `src/core/dialogue_line.gd` | `src/ui/dialogue_line.gd` |
| `src/core/zone_overlay.gd` | `src/ui/zone_overlay.gd` |
| `src/core/sprite_animator.gd` | `src/units/sprite_animator.gd` |
| `src/units/goalie_unit.gd` | `src/ui/goalie_unit.gd` |

Two of those pairs were not identical — `adventure_db.gd` and `base_db.gd`.
The kept copy is the newer one in both cases, which is why the table matters
more than it looks.

> `test_run.gd` and `export_sheet_preview.gd` also exist twice, but neither
> declares a `class_name`, so neither causes an error. Ignore them.

---

## 2. THE WARNINGS — Godot has made 148 files you never asked for

```
UID duplicate detected between res://data/ScratchNames.Second.translation
and res://data/ScratchNames.csv
```

Look in `res://data/` and you will find **148 `.translation` files** and 39
`.csv.import` files. Godot treats every `.csv` as a **translation table** by
default, so it has been turning each column of each of your spreadsheets into
a separate translation resource:

```
AdventureEnemies.Attack.translation
AdventureEnemies.Buff.translation
AdventureEnemies.Weight.translation      ... and 145 more
```

That is where the UID clashes come from, and it grows every time you add a
spreadsheet.

**The game never wanted any of this.** It opens those CSVs itself with
`FileAccess` and reads them as text. Godot's importer is pure overhead here.

### The fix, also copy-and-paste

The zip has a `.csv.import` file for all 39 of your spreadsheets, each saying
one thing:

```
[remap]

importer="keep"
```

That is exactly what the editor writes when you pick **Keep File (No Import)**
in the Import tab — I have just written all 39 for you instead of you
multi-selecting them by hand.

Godot normally clears out the `.translation` files it made as soon as the
importer changes. If any are still sitting there after a restart, select the
`data` folder in Windows Explorer, search `*.translation`, select all, delete.
Nothing reads them.

---

## DO THIS

1. Copy `src/` and `data/` from this zip over your project.
2. **Close Godot completely and reopen it.** The importer change needs a
   restart — reimporting from inside the editor is not enough.
3. Watch the **Output** panel. You want:
   ```
   [install] All 155 files are where they should be, one copy each.
   ```
   (it may still list the nine as doubled — that is correct and harmless now;
   the class clash is what mattered and it is gone)
4. Press **Start**.

---

## A SUGGESTION, AND AN APOLOGY

The last four rounds have all been the same mistake wearing different hats: I
sent you folders without knowing your folder layout. You offered me the repo
in your very first message and I did not use it until two rounds ago.

**From here on I pull the repo before I build any zip.** That is what let me
find all nine of these in one go instead of one per round, and it is what I
should have been doing from the start.

If you push your changes before asking me something, I will always be working
against what you actually have rather than what I think you have.
