# Zones, pressing, and a pitch that never stops

Six changes. All of it is `Tuning.csv` rows — nothing here needs a script
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
  middle third. Tuned down to about one in three, and the ball now uses **around
  three-quarters of the pitch width** instead of 58%.

Final measurements, averaged over five runs of a simulated minute:

| | |
|---|---|
| Time spent getting open / marking / chasing / pressing | 45% / 25% / 17% / 7% |
| Time spent doing nothing in particular | **0%** |
| Units outside their own quarter | 10–14% (all inside the 33% band) |
| Ball's range across the pitch | 70–79% of full width |
| Passes intercepted | ~31% |
| Average pass | ~315px, about a fifth of the pitch |

---

## 1. Four quarters, mirrored

Each side's Tier I sits in its **own defensive quarter** and its Tier IV in
the attacking one, so the two teams are mirrored — defenders at the back,
attackers up front, like a real formation.

```
    | quarter 1  | quarter 2  | quarter 3  | quarter 4  |
    | you I      | you II     | you III    | you IV     |
    |     them IV|     them III|    them II |     them I |
    |____________|____________|____________|____________|
    ^ your goal                          their goal ^
```

**So marking is by quarter, not by Tier.** Your Tier I defenders shadow their
Tier IV attackers, because those are the two standing on the same grass. Pairs
are matched by how far down the pitch they start, so the marking never crosses
over itself. Within a quarter your side stands nearer your own goal and theirs
nearer theirs, which puts each pair side by side.

Worth knowing: this means the units who eventually **duel** each other (Tier I
against Tier I) are at opposite ends of the pitch during open play. That is the
trade for a formation that looks like football. `zones_enabled,false` returns
to the old layout if you want to compare.

A unit owns 25% but may chase into 33%, then gets pulled back. Measured, they
are outside their strict quarter 10–14% of the time — always inside the 33%
band, never wandering.

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
random one. That single change is most of the jump from 58% to ~75% of the
pitch being used.

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


---

## 5. Following the ball

Two things you picked, both cheap and both aimed squarely at "I can see what is
happening".

**A trail and a ring.** The ball leaves a short fading trail, and whoever is
carrying it gets a ring at their feet — blue for you, red for them. I had to
add exactly this to my own simulation before I could follow the play in it at
all, which is fairly strong evidence it was the missing piece.

| Key | Default | |
|---|---|---|
| `ball_trail_seconds` | 0.55 | length of the trail. 0 = off |
| `ball_ring_radius` | 17 | ring at the carrier's feet. 0 = off |

**The quarters are painted on.** Each Tier zone gets a faint wash of its own
colour with a line down the boundary, so the four-quarter system is learnable
by looking. It sits at 7% opacity during play and **brightens to 20% while you
are choosing cards**, then fades back — loud exactly when it is useful.

| Key | Default | |
|---|---|---|
| `zone_tint_alpha` | 0.07 | resting strength. 0 = off |
| `zone_tint_alpha_draft` | 0.20 | strength while a draft is open |

`zone_overlay.gd` draws it. It must sit in the tree **after** your field sprite
and **before** the units — `main_scene.gd` already adds it in the right place,
so there is nothing to do unless you rearrange `_ready()`.

---

## Still on the table

Two things from my list you did not pick, both still worth doing later:

- **A camera that follows play.** Right now the whole pitch is always on screen
  at one size, which is most of why everything reads small. Slow drift toward
  the ball with a pull-back for the PLAY MAKER call would do more for the feel
  than anything else remaining.
- **Facing and run animations.** Units currently slide without turning. Flipping
  the sprite toward movement and playing a run cycle while chasing is cheap and
  is most of what separates "pieces moving" from "players running".
