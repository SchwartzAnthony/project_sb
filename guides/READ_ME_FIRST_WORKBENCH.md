# The `card_face` error, and the Workbench

---

## 1. The error — one file, wrong copy

```
Static function "card_face()" not found in base "MenuSupport"
```

When you deleted the duplicate `menu_support.gd`, **the copy that got
deleted was the new one**. The old one has no `card_face()`, and
`team_builder.gd` and `adventure_encounter.gd` both call it.

**Fix:** drop the `menu_support.gd` in this folder over the one in your
project, wherever it currently lives.

**To be sure you have the right one:** open it in Godot and press
<kbd>Ctrl</kbd>+<kbd>F</kbd> for `card_face`. The correct file has it, in a
section headed **ONE CARD FACE, USED ON EVERY SCREEN**, around line 165. If
the search finds nothing, you still have the old copy.

**The general rule**, because this will happen again: a `class_name` must
be unique. Two files claiming `MenuSupport` is an error; *zero* files with
the function a caller wants is a different error, and this was the second
one wearing the first one's clothes.

---

## 2. The Workbench

A single web page that edits every CSV in the game at once, and checks that
they line up. It runs in your browser — nothing is uploaded, and your work
is kept between visits.

There are two copies and they are the same page:

- **The file in this folder.** Double-click it. Downloads work here, so
  **Export → Download** writes a real `.csv` straight to your Downloads
  folder. This is the one to use for actual work.
- **The published link** in the chat. Handy on another machine; there,
  Export → **Copy** puts the file on your clipboard instead.

### Getting started, once

1. Open the page. It comes up on a **trimmed example set** so you can see
   how it works. The problems it lists are mostly the sample's own fault —
   it is only six rows per file — and it says so.
2. Press **Load CSVs** → **Choose files**, go to `project_sb/data/`, select
   **everything**, open.
3. That is it. It remembers, so next time it opens on your real data.

**Load them all at once.** The checker's whole value is seeing the files
*together* — it cannot tell you a bounty names a boss that does not exist
if it has never seen `AdventureEnemies.csv`.

### What it does

**Edits.** A row per row, a column per column. `+ New row` starts you with
sensible defaults for that file — a new enemy arrives with an Attack, a
Layers string and a Weight already filled in.

**Knows your columns.** `Tier` is a dropdown. `Boss` lists the enemies that
are actually bosses. `Item` lists what is in `Items.csv`. `Sky` and `Grass`
get a colour picker. Nothing is typed from memory and misspelled.

**Checks.** Eight things, live, every time you type:

- two rows sharing an id
- a reference to something that does not exist
- **`and` where a semicolon belongs** — the mistake that silently stopped
  the Pub from ever opening
- **a counter you read but nothing ever writes** — a condition that is
  false forever and never complains
- an unlock required but never granted
- a card off its tier's rung
- an enemy with no Attack, or a layer that soaks so much nothing gets through
- a brew costing an item that is not in `Items.csv`

Every problem says what is wrong, what to do about it, and has a **show**
link that jumps to the exact cell.

**Exports.** Per file: **Copy** (works everywhere) or **Download** (works
in the local copy). Paste over the real file and press F5 in Godot.

### Adding a file it does not know

It will still edit any CSV you drop in — it just will not have the notes,
the dropdowns or the checks. Those live in one block at the top of the
page's code called `SCHEMA`, and adding an entry is about six lines. Ask me
and I will wire in whatever you add.

---

## One habit worth keeping

**Edit in the Workbench → Export → paste → F5 → read the Output panel.**

The Workbench catches what the game cannot warn you about — the conditions
that are quietly false forever. The Output panel catches the rest. Between
them, almost nothing gets to be a mystery.
