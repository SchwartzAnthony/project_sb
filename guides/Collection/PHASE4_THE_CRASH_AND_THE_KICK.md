# The crash, and Phase 4 — the ball-kick

---

## STEP 1 — Where the files go

| File | Folder | |
|---|---|---|
| `adventure_strike.gd` | `src/adventure/` | **NEW** |
| `bounty_board.gd` | `src/ui/` | replace — **this is the crash fix** |
| `adventure_encounter.gd` `adventure_scene.gd` | `src/adventure/` | replace |
| `Tuning.csv` | `data/` | replace |

No CSV shape changed this round. If you already installed Phase 3, this is
four files on top of it.

---

## STEP 2 — The crash, and it was mine

```
Invalid access to property or key 'damage' on a base object of type 'Dictionary'
bounty_board.gd:365 @ _boss_line()
```

In Phase 3 I renamed the enemy's `Damage` column to **`Attack`** — and did
not carry that rename through to the Bounty Board, which was still asking
for `damage`. **Fixed**, and I am sorry it cost you a Godot recovery.

### The real lesson, and what I did about it

**A missing key on a Dictionary is a hard crash in GDScript.** Not a
warning, not a blank — the game stops. That is a genuinely nasty trap in a
project whose whole design is "the spreadsheet is the game", because it
means **renaming a column can take the game down**, and the error points at
the screen rather than at the CSV.

So every screen now *asks* for a key instead of demanding it:

```gdscript
int(boss["attack"])                # crashes if the column was renamed
int(boss.get("attack", 0))         # shows a 0 and keeps going
```

I swept both screens: **26 hard lookups made safe in `bounty_board.gd`, 12
in `adventure_encounter.gd`.** The worst a renamed or half-filled column
can now do is show a 0 or a blank where a number should be.

I left the ones inside `adventure_db.gd` alone on purpose — that file reads
dictionaries **it built itself**, so every key is guaranteed to be there.
Churning those would have added noise without removing risk.

**If you rename a column in future**, the safe order is: change the CSV,
press F5, and read the Output panel. The startup report names anything it
cannot find, and no screen will crash while you sort it out.

---

## STEP 3 — Phase 4, the kick

Damage was a line in a panel. Now you watch it.

**On your hit:** the player drafted **last** — Tier IV normally, or the
highest tier that still had somebody — steps out of the line, kicks the
ball in an arc at the enemy you focused, the enemy is shoved backwards, and
the damage number floats up off it in the accent colour.

**On theirs:** the enemy puts one back at whoever it picked, that player
flinches, and a red number floats off them. An `aoe` sweep shakes the enemy
instead and lets the four numbers tell the story.

### Why it is its own file

`adventure_strike.gd` holds the *looking*; `adventure_encounter.gd` holds
the *rules*. That split means you can re-balance numbers without touching
animation, and replace all of this with real artwork without touching a
single rule.

**It needs no art at all.** The ball is drawn, the flinch is a nudge on a
position, the number is a Label with an outline so it reads over grass or
over an enemy. Watchable today; better the moment you draw something.

### Four new knobs in `Tuning.csv`

```
adventure_kick_seconds,0.42      the ball's flight
adventure_stepup_seconds,0.26    the player stepping out before kicking
adventure_flinch_seconds,0.22    the shove backwards on a hit
adventure_float_seconds,0.9      how long a damage number hangs
```

**A whole fight is roughly `kick + flinch + float` per hit.** If it feels
slow with three enemies, halve `adventure_kick_seconds` first — that is the
one you feel most.

---

## STEP 4 — If something else breaks before your presentation

The two things most likely to go wrong, and what to do:

**A crash naming a key** (`Invalid access to property or key '...'`) — a
column got renamed or removed. The line number tells you the screen; the
key name tells you the column. Put the column back and press F5.

**A screen opens blank** — read the Output panel. Every loader prints what
it found at startup, and `ContentReport` names anything that does not line
up: a bounty whose boss does not exist, a biome with no enemies, a drop
table naming an item that is not in `Items.csv`.

Nothing in the adventure system stops the game for bad data any more. It
prints, falls back, and carries on.

---

## WHERE THINGS STAND

**Working end to end:** Bounty Board → biome and bounty → team builder →
the run → pickups → waves → the fight with focus, items, the four-tier
draft and fleeing → loot → Continue or Return → banking.

**Still on the list, in the order I would do them:**

1. **Items from the Bounty Board** — spend them before you set off, not
   only mid-fight
2. **The stamina you carry into the next wave** shown on the loot popup, so
   Continue Forward is an informed choice
3. **Biome unlock chains and the scaling loop** after a boss falls
4. Back to the league side: the halftime locker room, `Recipes.csv`, the
   tutorial

For the presentation I would run **Clear the Reeds** — two waves, the
gentlest boss, and it shows the whole loop in a couple of minutes.
