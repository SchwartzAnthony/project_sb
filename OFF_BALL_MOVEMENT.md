# Zones, pressing, and a pitch that never stops

Four changes. All of it is `Tuning.csv` rows — nothing here needs a script
opened. `zones_enabled,false` puts the whole thing back the way it was, which
is the fastest way to compare.

---

## How I checked this without playing it

There is no Godot in my sandbox, so I could not run your game. Instead I built
a Python copy of the movement rules on a pitch your size, ran it for minutes at
a time, and measured what actually happened. `movement_preview.gif` is that
simulation — circles are you, squares are them, and the letter beside each unit
is what it is doing.

That is how the numbers below were chosen rather than guessed. Three examples
of what it caught:

- The first version had everyone slowly **drift to the bottom of the pitch**
  and stay there. Marking chased marking chased marking, with nothing anchoring
  it. That is why the leash exists.
- Roles were **switching off during every pass**. Since the ball is in the air
  most of the match, both teams spent most of their time milling about. Now a
  side "has" the ball while it is still flying.
- Two-thirds of all passes were being intercepted, so the ball never left the
  middle third. Tuned down to about one in three, and the ball now uses **82%
  of the pitch width** instead of 58%.

Final measurements, averaged over five runs of a simulated minute:

| | |
|---|---|
| Time spent getting open / marking / chasing / pressing | 45% / 27% / 15% / 7% |
| Time spent doing nothing in particular | **0%** |
| Units outside their own quarter | 5% (all inside the 33% band) |
| Ball's range across the pitch | 79–88% of full width |
| Passes intercepted | ~31% |
| Average pass | ~315px, about a fifth of the pitch |

---

## 1. Four quarters, one per Tier

Tier I owns the leftmost quarter, Tier IV the rightmost — and **both teams
share each quarter**. That is deliberate: your Tier II and their Tier II are
the two that will duel, so they stand in the same part of the pitch and shadow
each other all match. When the PLAY MAKER comes, the fight you are about to
watch has been visible for a minute already.

```
    |  Tier I   |  Tier II  | Tier III  |  Tier IV  |
    | H       A | H       A | H       A | H       A |
    |___________|___________|___________|___________|
    ^ your goal                       their goal ^
```

Within a quarter your side stands nearer your own goal and theirs nearer
theirs, which is what puts the marking pairs side by side.

A unit owns 25% but may chase into 33%, then gets pulled back. Measured, they
are outside their strict quarter about 5% of the time.

| Key | Default | |
|---|---|---|
| `zones_enabled` | true | false = the old layout, both squads in their own half |
| `zone_share` | 0.25 | what each Tier owns outright |
| `zone_stretch` | 0.33 | what it may chase into |
| `zone_side_inset` | 0.34 | how far across its quarter each side stands. 0.5 puts them nose to nose |

**Your formation scenes still matter.** With zones on, the quarter decides
*x* and your `lorelei_formation.tscn` markers still decide *y* — the vertical
shape you positioned is stretched over the full height of the pitch. Only the
horizontal placement is taken over.

---

## 2. Pressing and getting open

Every unit's job is decided centrally, once per physics frame, and this is
the part that could not work any other way: a single unit cannot see how many
team-mates have already broken toward the ball, so left alone either all ten
charge or none do.

**When they have it:**
- everyone in the quarter the ball is in **charges the carrier**
- the nearest `press_helpers` from neighbouring quarters **come across**
- everyone else **stays goal-side of their man**

**When you have it**, your other nine **get off their markers and show for the
pass**, without leaving their lane.

**While the ball is in the air**, all of that keeps running — defenders press
where it is *landing*, not where it is, so they arrive with it instead of
trailing behind it. The man it is aimed at goes to meet it.

| Key | Default | |
|---|---|---|
| `press_radius_fraction` | 0.55 | charge range, as a fraction of pitch **height**. Bigger = more swarming |
| `press_helpers` | 2 | extra defenders from other quarters |
| `press_speed` | 92 | px/sec when charging |
| `mark_distance` | 54 | how far goal-side of his man a marker stands |
| `open_spread` | 230 | how far an attacker breaks off to show |
| `unit_leash` | 210 | how far from its slot a marking or showing unit may stray |

`unit_leash` is the one to reach for if the shape feels either rigid or
sloppy. It is what stops marking dragging a whole tier across the pitch.

---

## 3. The pitch keeps moving during PLAY MAKER

You were right that this was killing it. Play used to stop at the whistle and
stay stopped through the entire relay, so the ball was passed around a field of
statues.

Now **only two moments freeze**: the "PLAY MAKER!" call itself, and while you
are picking cards. The relay and the duels run with everyone moving.

The ball still behaves during the relay, because freezing the players and
scripting the ball are now two separate things. `scripted_possession` means the
ball keeps whoever the script gave it to — no dribble timer, no tackles, no
interceptions — so the relay always shows the right man, while the other
nineteen run, mark and show around him.

---

## 4. The carrier passes out of pressure

Not something you asked for, but the simulation would not behave until it was
in. The carrier used to hold the ball until its dribble timer ran out, by which
point five opponents had arrived, and the ball died in a scrum on the same
patch of grass.

Now, once he has held it a moment, an opponent getting close makes him move it
on — and a hurried pass picks the team-mate with the **most room**, not a
random one. That single change is most of the jump from 58% to 82% of the pitch
being used.

| Key | Default | |
|---|---|---|
| `ball_pressure_radius` | 82 | an opponent this close makes him release |
| `ball_min_hold_seconds` | 0.9 | but never sooner than this |
| `ball_intercept_grace` | 0.30 | fraction of a pass that cannot be picked off. Higher = more passes complete |

---

## Speeds went up

The old defaults (walk 30, chase 66, dribble 44) were set for a much smaller
pitch than the one you are actually using — roughly 1600px across. At those
speeds crossing a single quarter took six seconds and everything looked like it
was wading. They are now 52 / 104 / 68, with pressing at 92.

"Normal speed, not hyper fast" was the brief; if it still reads slow, raise
`unit_chase_speed` and `press_speed` together and leave `unit_walk_speed`
alone — that keeps the contrast between drifting and committing to a run,
which is most of what makes it readable.
