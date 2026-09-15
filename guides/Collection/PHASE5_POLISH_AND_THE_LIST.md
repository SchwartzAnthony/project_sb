# Phase 5 — nine fixes, and the rest of the list

Everything from your list except the last line. **Item 4 (halftime locker
room, `Recipes.csv`, the tutorial) is three separate league-side features
and I have not started them** — see the last section for why, and what I
would do instead before your presentation.

---

## STEP 1 — Where the files go

**Nine files. No CSV shape changed.**

| File | Folder |
|---|---|
| `adventure_scene.gd` `adventure_walker.gd` `adventure_encounter.gd` `adventure_strike.gd` `adventure_run.gd` | `src/adventure/` |
| `bounty_board.gd` `menu_support.gd` `player_card_ui.gd` `team_builder.gd` | `src/ui/` *(menu_support may be in `src/core/` — put it back where it was)* |
| `Tuning.csv` | `data/` |

---

## STEP 2 — The nine things you reported

### 1. Combat did not open when the enemies lined up

It was waiting for **the players** to settle too — and the players drift on
purpose, so "everybody has settled" could be true late or never. Only the
enemies walking into place is waited on now, and even that has a ceiling:
`adventure_meet_seconds` (1.6) and the fight opens regardless.

### 2. Click the enemies themselves

You pick by clicking the thing on the pitch. The panel buttons still work —
same choice, another route, and what a controller will use later. The one
you are going after wears a solid accent ring.

There is no camera on the run, so a world position *is* a screen position —
which is why this is a plain distance check rather than a collision shape
on every enemy. The catch radius is generous (46px) so it never feels
fiddly.

### 3. Hover shows their stats

Hovering anything on the pitch reads it out under the enemy row: what it
hits for, who it goes for, and **every layer with how much is left of it**.
A pale ring follows the pointer.

### 4. Uniform cards

There is one card face now — `MenuSupport.card_face()` — used by the **team
builder**, the **match draft** and the **Adventure fight**. Portrait, name,
tier and power, tinted by tier. Change it in one place and all three change.

### 5. The player art

**This was the sliver-and-dashes in your screenshot.** The walker was
handing `card.artwork` — the *entire* 1536×2496 spritesheet — straight to a
40-pixel box. It now uses `MenuSupport.portrait_for()`, which slices one
frame using `Animations.csv`, exactly as the team builder does.

The match draft had the same fault in a different form: a hard-coded
`Rect2(0, 0, 128, 64)`, right for one sheet size only. Also fixed.

### 6. Players stuck while grabbing items

A player half way to a pickup when a wave arrived kept walking towards it
forever — the pickup was no longer being scrolled, so it never arrived and
neither did they. **That is the two stranded players in your screenshot.**
Everything being chased is now dropped the moment a wave starts.

### 7. Enemy stamina did not go down

The bars were drawn from the CSV row, which never changes — so they sat
full however hard you hit. The fight now writes what is **left** onto each
enemy after every hit, and the bars empty as you chew through the layers.

### 8. They were kicking new balls

`kick()` was making a fresh ball each time, so the real one sat on the grass
while phantoms flew about. The run's own ball is passed in now: it leaves
their feet, arcs at the enemy, and is put back so the party still has it.

### 9. The combat text has its own window

The log has moved out from under the buttons into **its own panel up the
right-hand side**, with a **HIDE LOG / SHOW LOG** button. It **opens by
itself** — on a first run you want to see what the numbers are doing — and
one press shuts it for the rest of the fight. It holds a dozen lines.

---

## STEP 3 — The rest of the list

### Items from the Bounty Board ✅

A **KIT** button next to START EXPLORING. It shows every item with a `Use`
column and how many you have, so you notice you are out of Smelling Salts
*before* you set off rather than three waves in. Nothing is spent there —
it is a reckoning, not a shop; kit is still used from ITEMS in a fight.

### Stamina carried into the next wave ✅

The loot popup now has a **THE PARTY** panel: how many are standing in each
tier and what percentage of that tier's stamina is left, red under a third.
If anyone is down it says so and reminds you Smelling Salts bring them back.

Stamina does not refill between waves, so this is the number that decides
Continue Forward or Return to Base — it was the one thing the popup did not
tell you.

### Biome unlock chains and the scaling loop ✅

Beating a bounty's boss now records a **clear** as an ordinary counter
(`cleared_marshlands`), so a talent or a building can test it:
`count:cleared_marshlands>=3`.

Going back in, the enemies scale — layers *and* attack:

| Biome | 1st visit | after 1 clear | 2 | 3 |
|---|---|---|---|---|
| Marshlands | ×1.00 | ×1.35 | ×1.70 | ×2.05 |
| Cinder Wastes | ×1.00 | ×1.70 | ×2.40 | ×3.10 |
| Hollowdeep | ×1.00 | ×2.05 | ×3.10 | ×4.15 |
| Frostreach | ×1.00 | ×2.40 | ×3.80 | ×5.20 |

**One decision worth knowing about.** I first made `Difficulty` multiply the
first visit too, and it was wrong — the Hollowdeep's enemies are *already*
written tougher than the marsh's in `AdventureEnemies.csv`, so multiplying
by 3 on top counted it twice and made the later biomes unplayable.

A first visit is now always ×1, and **Difficulty decides how fast a biome
ramps when you go back**. The marsh climbs gently, the Frostreach steeply.
Set `adventure_repeat_step` to 0 to turn repeat scaling off entirely.

The CSV row is never touched — the scaled numbers go into a copy, so a Mire
Grub is still a Mire Grub in the spreadsheet however often you clear the
marsh.

---

## STEP 4 — What I did NOT do, and my honest advice

**The halftime locker room, `Recipes.csv` and the tutorial** are three
separate league-side features. Each is roughly the size of one of the
Adventure phases, and half-building three of them a few days before a
presentation would leave you with three things that nearly work rather than
one loop that does.

**Adventure is now complete end to end** — board, kit, squad, scroll,
pickups, a real fight with clicking, items, fleeing, loot, the party's
state, banking, and a reason to go back in. That is the thing to show.

**For the presentation, run Clear the Reeds.** Two waves, the gentlest
boss, and it walks through the whole loop in a couple of minutes. Turn the
log on for the first fight so people can see the numbers, then hide it for
the second and let them watch the football.

If anything looks slow on the day, three numbers in `Tuning.csv` fix it
without opening a script: `adventure_kick_seconds` (0.42),
`adventure_wave_gap` (12) and `adventure_scroll_speed` (120).

**Next round, in the order I would take them:** the halftime locker room
first — it is the most fun thing left and the ladder already makes "swap for
a card of the same power" a rule the screen can enforce for free — then
`Recipes.csv` to close the resource loop, then the tutorial.
