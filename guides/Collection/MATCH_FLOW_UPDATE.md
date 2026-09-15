# Passing, tackling, shooting and standing too close

Four changes to how a round looks. Every number below is a row in
`Tuning.csv`, so all of it is adjustable without opening a script.

---

## 1. The ball is worked up the pitch, not fired across it

**Before.** After each combat check the ball was struck in one straight line
from wherever it was to the next tier's attacker, however far away that was.
Nobody else touched it.

**Now.** It is played through the team-mates standing along the way. The
attacker for that tier is still the end of the line — he is just no longer the
only one who touches it.

The chain is built greedily from where the ball actually is: take the
**nearest** team-mate who is meaningfully closer to the destination, then
repeat from him. Picking the nearest rather than the furthest is what makes it
read as a passing move instead of a series of long balls. Every hop has to
advance the move, so the ball never goes sideways or backwards on its way up.

| Key | Default | What it does |
|---|---|---|
| `relay_max_hops` | 3 | How many players it goes through. **0 restores the old direct pass.** |
| `relay_hop_max_distance` | 420 | Longest single pass. Shorter = more players touch it |
| `relay_min_progress` | 60 | A hop must gain at least this much ground or it is skipped |
| `relay_hop_beat_seconds` | 0.12 | Pause on each intermediate player |

If your formations are tight and you want more touches, drop
`relay_hop_max_distance` to about 260 and raise `relay_max_hops` to 4 or 5.

---

## 2. A turnover is now an interception

**Before.** The attacker lost, and the ball was handed to the man who had just
beaten him. Nobody passes to the player marking them.

**Now.** The beaten attacker looks for **his own team-mate closest to the
danger** and plays it there — and the winner reads it and cuts in front of the
receiver. The ball is in flight for real: partway along, it turns out of its
line toward the interceptor, who is leaping into its path at the same time. The
two of them meet.

The ball ends up in the same hands as before. It just gets there for a reason
you can watch.

| Key | Default | What it does |
|---|---|---|
| `intercept_at_fraction` | 0.55 | How far along the pass it is picked off. 0.5 = halfway |
| `intercept_leap_seconds` | 0.45 | How long the interceptor takes to get across |
| `intercept_beat_seconds` | 0.3 | Pause afterwards before play continues |

The Output panel names it:

```
Tier II: Cinderworks (3 atk) vs Wellenklang (4 def) -> TURNOVER
Wellenklang reads it and cuts out the pass to Foundryburn.
```

---

## 3. Shots are taken from somewhere believable

**Before.** The shooter stepped a flat 25% of the way toward the keeper. From
the far half that still left them striking from around the halfway line.

**Now.** They carry it to a set distance **off the goal line** — so wherever
the move started, the shot is taken from roughly the same believable place.
Not right on top of the keeper; near enough that you would believe it.

The distance is a **fraction of the pitch**, not a pixel count, so it reads the
same whether your field art is 1280 wide or 4000. They also swing round toward
the middle of the goal without going all the way, so shots keep some of the
angle the move arrived at, and they never run *backwards* to reach the spot.

| Key | Default | What it does |
|---|---|---|
| `shot_distance_fraction` | 0.20 | How far out they stand, as a fraction of pitch width. **Lower = closer to goal** |
| `shot_distance_min_pixels` | 120 | Never closer than this, whatever the pitch size |
| `shot_centring` | 0.6 | 1 = dead centre of goal, 0 = keeps their angle entirely |
| `shot_run_up_speed` | 520 | Pixels per second they carry it in |
| `shot_run_up_min_seconds` / `_max_seconds` | 0.35 / 1.3 | Clamps on the run-up so a long carry does not crawl |

Start with `shot_distance_fraction`. 0.20 is about a fifth of the pitch out;
0.12 is nearly in the six-yard box.

---

## 4. Players stop standing inside each other

**Before.** Movement was a plain `move_toward` at the target. Nothing stopped
two units occupying the same few pixels, and a loose ball pulled everyone onto
one spot where they stayed.

**Now.** The pull toward wherever they are heading is one force among three,
and the sum decides the heading:

- **the target** — the ball, the goal, or their formation slot
- **separation** — a push away from every unit inside `unit_separation_radius`,
  strongest when almost touching and nothing at all at the edge
- **swerve** — a sideways bias whose direction is fixed per unit for its
  lifetime, strong when far out and straightening as they arrive

That last one is what stops ten units converging on a loose ball in one
straight queue. Each takes its own curved line, because each bends the same way
every time rather than dithering.

**Fighting over the ball still happens.** The separation deliberately fades out
inside `unit_contest_radius` of the ball — otherwise the shoving cancels the
chase and nobody ever wins a tackle. Near the ball they crowd; away from it
they keep their shape.

| Key | Default | What it does |
|---|---|---|
| `unit_separation_radius` | 52 | How close before they give way. **0 restores the old overlapping** |
| `unit_separation_strength` | 0.9 | How hard the shove is relative to where they are going |
| `unit_contest_radius` | 70 | Inside this range of the ball the shove fades so they contest it |
| `unit_swerve_strength` | 0.35 | How much they curve their run. 0 = straight lines |

If they look too polite and never tackle, raise `unit_contest_radius` to about
110. If they still bunch up, raise `unit_separation_radius` toward 70 — but
much past that and a tight formation cannot hold its shape.

Goalies share the units container but are a different type, so they stay out of
the shoving entirely and keep their line.

---

## Nothing here changed your formations

All four are position-agnostic — they work off whatever positions your
formation scenes give them. Your repositioned `lorelei_formation.tscn` and
`brandteufel_formation.tscn` are untouched, and neither is `main_scene.tscn`.
