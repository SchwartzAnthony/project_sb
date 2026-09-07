# Phase 4 — The Pub and brews

## Your two questions

**Can you add new buildings through the CSV?**
Yes. One row in `Buildings.csv` — ID, Name, where it sits, what clicking it
does. Nothing else.

**Can talents unlock buildings?**
Yes, and it already works. A talent's `Effects` say `unlock:something`; a
building's `Requires` says `unlocked:something`. Taking a talent also unlocks
its own **ID**, so you can point a building straight at a talent.

I put a working example in `Buildings.csv` to prove it:

```
tap_room,Tap Room,...,unlocked:master_brewer,...
```

The Tap Room appears only once you take the **Master Brewer** talent. No code
was involved. The same trick works in reverse — a building's `Action` can say
`unlock:x` and a talent's `Requires` can test it.

---

## Where the files go

| File | Folder |
|---|---|
| `brew_db.gd` | `src/core/` |
| `pub_screen.gd` | `src/ui/` |
| `pub_screen.tscn` | `src/ui/` |
| `Brews.csv` | `data/` |
| `player_data.gd` | `src/core/` *(replace)* |
| `ability_engine.gd` | `src/core/` *(replace)* |
| `card_database.gd` | `src/core/` *(replace)* |
| `content_report.gd` | `src/core/` *(replace)* |
| `scene_paths.gd` | `src/core/` *(replace)* |
| `main_scene.gd` | `src/formations/` *(replace)* |
| `player_unit.gd` | `src/units/` *(replace)* |
| `Buildings.csv` | `data/` *(replace)* |

**After copying `Brews.csv` in, set its importer to "Keep File (No Import)".**

Then: **F5 → The Base → Pub.** You will see only the Keeper's Tonic until you
take the Brewing talents.

---

## What a brew does

Your base cards have **no abilities at all**. A brew is where a card's ability
comes from. It also changes what class the card **counts as**, so a Lorelei who
drank a Fire Brew is hit by "give all Brandteufel +1 power".

| Column | What it does |
|---|---|
| **ID** | short and lower-case: `fire`, `water`. This word lands in `goals_with_brew_{brew}`, so keep it tidy |
| **Name** | what the player sees |
| **Description** | one line |
| **Requires** | when the Pub can pour it. Usually `unlocked:Fire Brew`, which a talent grants |
| **For Class** | only this class may drink it. Blank = anyone |
| **Becomes** | the class it counts as afterwards. Blank = no change, abilities only |
| **Artwork** | spritesheet PNG in `assets/players/`. Blank = keeps its own art |
| **Attack Ability** | an Ability ID from `Abilities.csv` |
| **Defend Ability** | an Ability ID from `Abilities.csv` |
| **Permanent** | `true` = may be made permanent. Blank = one match only |

### Per-card art

If a PNG named `<Card Name> <brew id>.png` exists in `assets/players/`, it is
used instead of the brew's shared `Artwork`. So
`Silver-Rhine Lorelei fire.png` gives that one card its own fire look, and
everyone else falls back to the shared one.

---

## How long a brew lasts

- A normal brew **wears off at the final whistle**.
- A **permanent** brew stays until the player removes it at the Pub — but only
  if the brew's `Permanent` column is `true` **and** the player has unlocked
  `Permanent Brews` (the Master Brewer talent).
- A one-match brew poured on top of a permanent one **wins for that match**,
  then wears off and the permanent one is still underneath.
- **Clicking a brewed card at the Pub removes the brew**, permanent included.

I simulated the whole lifecycle against your real CSVs — the layering, the
wearing off, the permanent surviving, the wrong-class refusal, and the counters
feeding `Stats.csv`. All correct.

---

## One design decision worth knowing

A brew does **not** overwrite the card. It lays a thin overlay on top, and the
game reads `active_unit_type()` where it means "what does this count as" and
plain `unit_type` where it means "what is this".

That distinction matters: **roster building still uses the real class**, so a
Lorelei who drank a Fire Brew is still picked for your Lorelei team. If the
brew overwrote the class outright, that card would vanish from your own roster
the moment you brewed it.

Stars are not shown at the Pub — they keep their own printed abilities.

---

## Add a brew in one minute

1. Open `Brews.csv`
2. Add:
   `stone,Stone Brew,Heavy and slow and immovable.,,,,,,KEEP_BULWARK,,`
   *(no Requires = always on tap, no For Class = anyone, no Becomes = keeps
   their class, gains one defend ability)*
3. Save, set the importer if it is a new file, press F5

The startup report will tell you if `KEEP_BULWARK` is not a real Ability ID, or
if you named a class that no card belongs to.

---

## All four phases are done

| Step | | |
|---|---|---|
| 1 | The spine — stats, progression, the report | done |
| 2 | Base building — hub, buildings, visitors | done |
| 3 | Talent tree | done |
| **4** | **Pub and brews** | **done** |

You can now, entirely from spreadsheets: add cards, classes, abilities,
dialogue, achievements, buildings, visitors, talents, brews, and the rules for
when each of them appears.

---

## Three suggestions for what is next

**1. The loop has no ending.** You can play matches forever. A season — "ten
matches, then a final" — would give the prototype a shape to show off. It is
mostly `Progression.csv` rows plus a results screen.

**2. Nothing tells the player what changed.** Talents, brews and unlocks all
happen quietly. A short "what you gained" panel after a match would make the
progression legible to someone seeing it for the first time.

**3. The camera still shows the whole pitch at one size.** I have raised this
before and still think it is the single biggest visual win left — everything
reads small because it never moves.

Say which, if any, and I will start.
