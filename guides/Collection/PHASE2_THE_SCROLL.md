# Adventure, Phase 2 — the scroll

The run is playable end to end. Set off from the Bounty Board, run right,
pick things up, meet waves, clear them, choose to push on or go home, and
bank the haul. **The encounter itself is still an automatic win** — that is
Phase 3.

Also in this round: the audio crash on startup.

---

## STEP 1 — Where the files go

**Make a new folder first: `src/adventure/`.**

| File | Folder | |
|---|---|---|
| `adventure_scene.gd` | `src/adventure/` | **NEW** |
| `adventure_scene.tscn` | `src/adventure/` | **NEW** |
| `adventure_walker.gd` | `src/adventure/` | **NEW** |
| `Bounties.csv` | `data/` | replace — **new Waves column** |
| `MatchModes.csv` | `data/` | replace — **new Scene column** |
| `MenuConfig.csv` `Tuning.csv` | `data/` | replace |
| `audio_director.gd` `adventure_db.gd` `adventure_run.gd` `match_mode.gd` `scene_paths.gd` | `src/core/` | replace |
| `team_builder.gd` | `src/ui/` | replace |

---

## STEP 2 — The audio crash

```
Parent node is busy setting up children, `add_child()` failed.
audio_director.gd:61 @ fetch()
```

The very first sound of a session is fired from a screen's `_ready()`, and
the tree is **locked** while Godot is still adding that screen's children —
so adding the audio player to the root fails outright.

It is added with `call_deferred()` now, meaning "as soon as the tree is
free". That leaves a gap of a frame where the director exists but is not in
the tree yet, and two things handle it:

- a static `_pending` holds it, so a second call in that same gap gets the
  **same** director rather than making a second one
- anything fired during the gap is **queued and flushed** by `_ready()`

So nothing is dropped and nothing plays twice. Without the queue the first
screen of every session would have opened in silence.

---

## STEP 3 — What you can do now

**Adventure → a bounty → Start Exploring → class select → team builder →
the run.**

- The party runs right, the field slides left, the ball is knocked between
  them as they go.
- Things appear on the ground ahead. **Up to three of the nearest players
  peel off**, fetch it, and fall back into formation.
- The banner says what was picked up; the top-right corner says what you are
  carrying.
- When a wave arrives the party **forms up on the left** and the enemies
  walk on from the right. `COMBAT` shows.
- Clearing a wave rolls its drops and opens the popup: **Continue forward**
  or **Return to base**. The last wave is the boss, and clearing it offers
  **Claim the bounty**.
- Going home **banks the haul** — every item becomes a counter in your save,
  so a building can cost it the same day you write the row.

**A player with no artwork is drawn as a tier-coloured disc with its power
in the middle and a stamina bar underneath.** Give the card artwork in your
unit CSV and the disc is replaced. Same rule as the keeper.

**Each enemy shows one bar per layer**, outermost on top, darker when it
soaks more. That is the shape of the Phase 3 fight made visible now.

---

## STEP 4 — Two new columns

### `MatchModes.csv` gained **Scene**

| Mode | Scene |
|---|---|
| season, quick, cup | `match` |
| adventure | `adventure` |

The team builder no longer decides where a team goes — **the mode does**.
Point a new mode at a new screen and nothing in code changes.

### `Bounties.csv` gained **Waves**

The simulation caught this: *Clear the Reeds* is described as "a short run"
but inherited the Marshlands' 4 waves, so it was exactly as long as hunting
the Marsh King. A bounty can now set its own length; **blank means "however
long the biome is"**, which stays the normal case.

```
reed_clearing   waves 2     a genuinely short job
slag_run        waves 3
marsh_king      (blank)     the biome's 4
```

### `Tuning.csv` gained three

```
adventure_wave_gap,12          seconds of running between waves
adventure_pass_seconds,1.4     how often the ball is knocked on
adventure_enemies_per_wave,3   enemies in an ordinary wave
```

Plus the ones from Phase 1: `adventure_scroll_speed`,
`adventure_pickup_gap`, `adventure_pickup_carriers`.

**These are the numbers to play with.** Speed and spacing are the whole
point of this phase and I cannot judge them from a spreadsheet — change
them, run it, tell me what feels right.

---

## STEP 5 — What a full run pays

Simulated ten runs of each bounty against the real drop tables, assuming
every wave is cleared and nothing is banked early:

| Bounty | Waves | Average haul |
|---|---|---|
| Clear the Reeds | 2 | 41 reed, 43 coins, 3 bog iron |
| The Marsh King | 4 | 31 reed, 95 coins, 17 bog iron, **the Marsh Ale recipe** |
| The Slag Run | 3 | 30 ash glass, 16 bog iron, 83 coins |
| The Ash Tyrant | 5 | 45 ash glass, 187 coins, **the Cinder Stout recipe** |
| The Hollow Mother | 6 | 63 deep salt, 376 coins, **the Hollow Porter recipe** |

A recipe drops exactly once, from a boss, and only if you have the Brewery.
That ramp looks right to me, but it is a first guess — the `Amount` and
`Chance` columns in `Drops.csv` are the knobs.

---

## STEP 6 — Your two answers, written into the plan

**The focus target.** When a wave is met, a `COMBAT` banner comes up and
**you pick an enemy before any tier is drafted** — hover or click to see its
stamina, attack and layers, JRPG-style. Then Tier I, II, III, IV as normal.
Noted and built into Phase 3's shape; the enemies already draw their layer
bars so there is something to hover.

**All enemies hit.** You can only focus one, but every living enemy deals
its damage each round. That is what makes focusing a decision rather than a
formality — and it means a wave of three is genuinely three times the
pressure, which the `adventure_enemies_per_wave` knob now controls.

---

## STEP 7 — What I want from you before Phase 3

Play it once and tell me about **feel**, not features:

1. **Speed** — is `adventure_scroll_speed` 120 too slow, too fast?
2. **Spacing** — `adventure_wave_gap` 12 seconds between waves: enough time
   picking things up, or too long between fights?
3. **Pickups** — three players peeling off: does it read as football, or
   does the formation look broken?
4. **The wave** — do three enemies feel like a wall, or thin?

---

## NEXT — Phase 3, the encounter

This is the big one, and it replaces one function (`_run_encounter`):

1. Pick the enemy to focus, with its stats on hover.
2. Draft Tier I — **the enemy reveals its Tier I as you commit**.
3. II, III, IV the same. **Flee until the fourth is committed.**
4. Compare totals per tier; damage goes into the focused enemy's outermost
   layer; a tier the other side cannot field is a **walkover, counting
   twice**.
5. Every living enemy hits back, weakest of each tier first.

Phase 4 then turns on stamina and knockouts, which is when losing actually
costs you something.
