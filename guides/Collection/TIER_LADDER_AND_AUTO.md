# The tier ladder, and AUTO

Two things this round. The first is a rule the whole game now obeys. The
second is two fixes to AUTO.

---

## STEP 1 — Where the files go

| File | Folder | |
|---|---|---|
| `tier_ladder.gd` | `src/core/` | **NEW** |
| `team_builder.gd` | `src/ui/` | replace |
| `player_card_ui.gd` | `src/ui/` | replace |
| `rps_clash.gd` | `src/ui/` | replace |
| `pause_menu.gd` | `src/ui/` | replace |
| `match_hud.gd` | `src/ui/` | replace |
| `main_scene.gd` | `src/formations/` | replace |
| `ability_engine.gd` | `src/core/` | replace |
| `content_report.gd` | `src/core/` | replace |
| `TierPowers.csv` `Tuning.csv` | `data/` | replace |

No new CSV. The rule reads the `TierPowers.csv` you already have.

**Also fixed:** the parse error at `main_scene.gd:697`. My last patch landed
one tab too shallow and put the whole team-lookup block outside its `if`.
That is corrected, and I ran a structural check over all 60 scripts to be
sure nothing else has the same fault. Two hits remain and both are fine —
one is text inside a `"""` block, the other is alignment inside brackets,
which GDScript allows.

---

# PART 1 — THE LADDER

## The rule

    Tier I     holds a 0, a 1 and a 2
    Tier II    holds a 1, a 2 and a 3
    Tier III   holds a 2, a 3 and a 4
    Tier IV    holds a 3, a 4 and a 5

Three cards a tier, three different powers, always. In the collection, in
the team builder, on the pitch, for you and for the opposition. Never three
2s. Never two 5s.

## Where the numbers live

`data/TierPowers.csv`, which you already had:

```
Tier,Min Attack,Max Attack,Min Defense,Max Defense,Notes
I,0,2,0,2,...
II,1,3,1,3,...
```

**Min to Max is now read as the list of slots.** Tier I is 0 to 2, so it
has three slots: one for a 0, one for a 1, one for a 2. That is the only
place the numbers exist — change them and every screen agrees next time you
press F5. Keep each span three wide, because the pitch has three positions
per tier.

Nothing else needs editing. Your unit CSVs already obey the rule: I checked
all 48 cards and every one already sits on its proper rung.

## What it changes in the team builder

The slots are now **labelled by power**. An empty Tier I reads

    [ 0 power ]  [ 1 power ]  [ 2 power ]

A 2-power card can only go in the 2 slot. Click one while another 2 is
standing there and **they swap** — no "tier is full" message any more,
because there is exactly one slot that card could ever want and you have
just asked for it. The status line names what is still missing by power
("Tier II still needs a 3") rather than counting heads.

AUTO-FILL fills one per rung. CLEAR empties them all. READY stays greyed
out until every tier is a legal ladder.

## What it changes in a match

`spawn_team()` used to shuffle a tier's cards and take the first three. That
is what let the enemy field three 2s while you fielded a 0, a 1 and a 2 —
the unfairness was in the shuffle, not in the cards.

Now both sides are built **rung by rung**:

- **Your side** starts from the team you built and only has gaps filled.
  A saved team that has gone illegal (because you edited a CSV) is repaired
  rather than rejected, and the Output panel names anyone left out.
- **The enemy** is drawn fresh each match, so it is a different legal three
  every time. If its `Teams.csv` row names cards, those are always preferred
  and the rest of its class quietly fills any rung the row forgot — so a row
  naming two cards still fields a legal three.

## What may still change a power

Only abilities and elements, only during a match, only for as long as they
say. `AbilityEngine` holds every bonus **beside** the card and throws it
away at the end of the duel, round, cycle or match. The card itself is never
written to, so it walks into the next match on its proper rung. That was
already true and it stays true.

## Season Difficulty no longer touches the cards

This is the change you should know about, because it is a design decision
and not just a fix.

`Difficulty` in `Season.csv` used to add a flat bonus to **every enemy
card**. A Difficulty of 2 turned their Tier I into a 2, a 3 and a 4. That is
the same bug as the 6-power enemy, and the power ceiling only hid it — it
stopped a 6 appearing, it did not stop a Tier I fielding a 4.

Difficulty now makes the opposition **finish better** instead: it is added
to their shot when they get one. Same "this fixture is harder", and not a
single card leaves its rung. Your `Season.csv` needs no edits.

`difficulty_as_power` in `Tuning.csv` puts the old behaviour back if you
ever want to see it. Leave it off.

## A real problem it found

The startup report now checks whether every class can actually fill every
tier. Running it against your data turned up something worth fixing:

> **`example_unit_csv_with_ability_columns.csv` is a second complete copy of
> the Brandteufel set.**

`CardDatabase` reads **every** `.csv` in `res://data/`, so Brandteufel
currently loads twice — 24 cards, **six** Star Players instead of three, and
two cards on every rung. The game will still field a legal three, but *which*
three is arbitrary, and the star bundle is wrong.

**Fix it by moving that file out of `res://data/`** — a `docs/` folder is a
good home — or by renaming it so it does not end in `.csv`. I have not
touched it, because it is your file and it may be there on purpose.

The report will name it at startup either way, along with anything else that
cannot form a ladder: a class missing a rung, two Stars sharing a power, or
a card whose attack and defence disagree.

---

# PART 2 — AUTO

## It starts off now

AUTO was stored in your save, so turning it on once meant every later match
played itself until you noticed. Every match now begins with you in charge.

`auto_pick` in `Tuning.csv` sets what a match *starts* at — leave it `false`.
It is no longer "the starting value until the save overrides it"; it is the
value every match begins from, full stop.

## Your clicks lock while it is on

Cards and clash buttons go dim and stop responding. That was the real bug:
you and the computer could both choose in the same round, half a second
apart, and the round would resolve twice.

The lock covers everything you could click during a match:

- the offered cards at PLAY MAKER and at every Star swap — including hover,
  so the stats panel does not follow a card you cannot pick
- the three throw buttons and the ATTACK / DEFEND buttons in the clash
- cards created *while* AUTO is already running are born locked, so there is
  never a frame where a fresh card is live during an automatic pick

Press **AUTO** or **A** to take back over and it all lights up again,
mid-round if you like. The pause menu's AUTO button now does the same thing
as the HUD's — before this round it toggled the flag but nothing else heard
about it, so the lock (and the HUD button) would not have followed.

---

# WHAT I CHECKED

Against your real CSVs, not invented ones.

- **Every card is on a real rung** of its tier — all 48, no exceptions.
- **Every class can fill every tier** — the only failure was the duplicated
  Brandteufel file above.
- **2000 random line-ups** across every class and tier: no duplicate powers,
  no card off its rung, always weakest-first, always three.
- **All 12 `Teams.csv` rows** field a legal ladder in every tier, and named
  cards are always preferred over the class fallback.
- **`repair()` on a deliberately illegal saved team** (three cards of the
  same power) returns a legal three and drops exactly the two that had
  nowhere to stand.
- **Difficulty never reaches card power** — the only line that writes it is
  behind the `difficulty_as_power` switch, which is off.
- **Every AUTO toggle reaches the lock** — the HUD button, the keyboard
  shortcut and the pause menu all route through the same handler.
- **Structural check of all 60 scripts** for the indentation fault that
  broke the last build.

---

# WHAT I WOULD DO NEXT

Unchanged from last round, and Quick Match is still the cheapest win:

1. **Quick Match** — an hour, and `TeamDB.for_power()` is already built for it
2. **The halftime locker room** — and the ladder makes "swap for a card of
   the same power" a rule the screen can enforce for free
3. **Resources and recipes**
4. **The seasons as biomes**
5. **The tutorial**
6. **Input actions**, then settings and controller

One question before the locker room: when you swap a card at halftime,
should the replacement have to come off the **same rung** (a 2 for a 2), or
just from the **same tier** (any of that tier's three powers)? The first
keeps the ladder exactly; the second lets halftime genuinely change your
shape. I would build the first unless you say otherwise.
