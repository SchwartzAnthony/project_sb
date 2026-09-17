# TWO PROBLEMS. One is a typo of mine, one is a mess I made of your folders.

I pulled your repo, so this is checked against your actual project rather
than guessed.

---

## PART 1 — copy these three files (30 seconds)

```
src/ui/menu_support.gd        THE FIX
src/core/install_check.gd     now also finds duplicates
data/FileManifest.csv         rebuilt from YOUR real folders
```

**Note `menu_support.gd` goes in `src/ui/`** — that is where yours lives, and
my last zip wrongly said `src/core/`. More on that in Part 2.

### What the bug was

`menu_support.gd` line 685:

```gdscript
node.offset_bottom = -inset      # inset is a Vector2. offset_bottom is a float.
```

It should be `-inset.y`. One missing `.y`, in the last line of the file.

`offset_bottom` takes a number; `inset` in that function is a Vector2. Godot
refuses it at parse time, which kills `menu_support.gd` — and since every
screen in the game calls something in that file, every screen died with it.
The three lines above it are correct, which is how I missed it: I wrote
`.x` and `.y` on those and dropped it on the fourth.

---

## PART 2 — delete 12 files (2 minutes, and this one is my fault)

My last zip guessed which folder each file belonged in. Your project had
several of them somewhere else. So instead of overwriting, **it added a
second copy**, and you now have eleven scripts existing twice.

That is the `Class "GoalieUnit" hides a global script class` error. Godot
registers a `class_name` once. A second copy anywhere gives you that error
and then loads whichever it happens to find first — which may be the older
one. It is quietly the worst of the two problems.

### Delete exactly these — keep the other copy of each

| Delete this | Keep this |
|---|---|
| `src/core/adventure_db.gd` | `src/adventure/adventure_db.gd` ← newer |
| `src/core/adventure_run.gd` | `src/adventure/adventure_run.gd` |
| `src/core/enemy_pick_layer.gd` | `src/adventure/enemy_pick_layer.gd` |
| `src/ui/base_db.gd` | `src/core/base_db.gd` ← newer |
| `src/ui/dialogue_choice.gd` | `src/core/dialogue_choice.gd` |
| `src/ui/dialogue_line.gd` | `src/core/dialogue_line.gd` |
| `src/ui/zone_overlay.gd` | `src/core/zone_overlay.gd` |
| `src/units/sprite_animator.gd` | `src/core/sprite_animator.gd` |
| `src/ui/goalie_unit.gd` | `src/units/goalie_unit.gd` |
| `src/ui/goalie_unit.tscn` | `src/units/goalie_unit.tscn` |
| `export_sheet_preview.gd` (project root) | `src/core/export_sheet_preview.gd` |
| `test_run.gd` (project root) | `src/core/test_run.gd` |

**Two of those matter more than the rest.** `adventure_db.gd` and
`base_db.gd` differ between their two copies — the ones marked *newer* have
last round's `reload_files()` rename. Delete the wrong one of those pair and
the tutorial breaks again. The other nine are byte-identical, so only the
tidiness matters.

Do it in the Godot FileSystem dock (right-click → Delete) rather than in
Explorer, so the `.uid` files go with them.

> `data/Dialogue.csv` and `data/tutorial/Dialogue.csv` are **not** duplicates.
> Same for Buildings.csv and Visitors.csv. Those pairs are deliberate — the
> tutorial has its own spreadsheets. Leave them alone.

---

## WHAT I CHANGED SO THIS CANNOT HAPPEN AGAIN

**`FileManifest.csv` is now built from your repo, not from my guess.** All 155
files, with the folder each one is actually in.

**`InstallCheck` now looks for duplicates too.** It only checks `.gd` and
`.tscn` — two spreadsheets of one name in two folders is normal. From now on
the title screen prints this instead of leaving you to find it:

```
 THERE ARE TWO COPIES  (2)
   Delete the second path on each line. Godot only wants one.
   adventure_db.gd
        keep    res://src/adventure/adventure_db.gd
        DELETE  res://src/core/adventure_db.gd
```

and when all is well:

```
[install] All 155 files are where they should be, one copy each.
```

**And from here on I will check the repo before I send folders.** Guessing
your layout is what caused this; I have your actual one now.

---

## DO THIS, IN ORDER

1. Copy the three files from this zip over.
2. Delete the twelve files in the table above.
3. Press F5.
4. The **Output** panel should open with:
   ```
   [install] All 155 files are where they should be, one copy each.
   ```
5. Press **Start**.

If anything is still red, send me the **first three errors** again — that
screenshot is what let me find both of these.

While you are in the FileSystem dock: select every CSV in `res://data/`,
Import tab, **Keep File (No Import)**, Reimport. That clears the two UID
warnings for good. The game reads those files itself and never wanted
Godot's importer.
