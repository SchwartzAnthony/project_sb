# Star badges, the whistle, and where those other Stars came from

Four things changed. The first is new art you can swap; the other three are
fixes to things that were behaving badly.

---

## 1. Every Star Player now wears a badge

A marker rides above every Star Player and follows them everywhere:

| Where | What you see |
|---|---|
| On the pitch | A gold star floating above the unit's head |
| Kickoff card row | A star in the top-right corner of the card |
| Class select | Same corner badge on all three Stars |
| Team builder | Same badge on the locked Star tier |
| The power check (duel cut-away) | The badge stays up through the whole attack/defend sequence |

The enemy's Stars wear a **red** badge instead of gold, so you can tell at a
glance which side a Star belongs to. That answers most of question 4 below on
its own.

### Changing the art

Drop a PNG here and every one of those five places uses it:

```
res://assets/ui/star_badge.png
```

Anything square works; 32×32 or 64×64 is a good size. It is drawn with nearest
filtering, so pixel art stays crisp.

Want the enemy's badge to be a different picture rather than a red tint?

```
res://assets/ui/star_badge_enemy.png
```

Prefer to keep the art somewhere else? Add rows to `Tuning.csv`:

```
star_badge_art,res://assets/whatever/my_star.png,
star_badge_enemy_art,res://assets/whatever/their_star.png,
```

**With no PNG at all, a five-pointed star is drawn in code.** Nothing breaks
before you have made the art, and nothing needs the editor.

### Size and position

Three more `Tuning.csv` rows, already added for you:

| Key | Default | What it does |
|---|---|---|
| `star_badge_radius` | 9 | Bigger number, bigger badge |
| `star_badge_offset_y` | -34 | How high it floats. More negative = higher |
| `star_badge_pulse` | 0.08 | Gentle breathing. Set to `0` for a still badge |

---

## 2. The pitch now really does stop for HOLD UP!

**What was wrong.** `HOLD UP!` froze play *late* — after the enemy had
finished swapping its own Star and after the two-second banner. Both of those
take seconds, and the ball was live for all of it. So you would open the Star
picker to find the match had carried on without you.

**What happens now.** The whistle is the very first thing `HOLD UP!` does,
before the enemy substitution and before the banner. Nothing moves from that
moment on.

**And it stays stopped until the new Star is standing in their slot.** That
was the second half of the problem: play used to restart the instant you
clicked a card, while your incoming Star was still jogging on from the
touchline. The match now waits for both substitutions — yours and the
enemy's — to finish before the clock and the ball start again.

---

## 3. The ball no longer glides to the next player on its own

**What was wrong.** Two separate things combined into one odd-looking bug.

First, a pass caught in mid-air by the whistle was *paused* and then
*resumed*. So play would restart and the ball would carry on to a player
nobody had kicked it to any more.

Second — and this is the one that really looked like magic — a loose ball was
handed to whoever was **nearest**, from any distance at all. Not whoever
reached it. Nearest. So possession could jump clean across the pitch to
someone who had never moved.

**What happens now.**

- The whistle **drops** a pass in flight. The ball stops dead where it is and
  lies there as a loose ball. It does not remember where it was going.
- A loose ball is collected only by a player who **actually gets to it** —
  within `ball_pickup_radius` (26 pixels by default, about a player's width).
  Everyone within `unit_interest_radius` runs at a loose ball, so someone
  always arrives; it just has to be a real run now.
- Shots on goal and the scripted PLAY MAKER relay passes are deliberately
  exempt. Those are choreographed, the rest of the sequence waits on them
  landing, and stopping one mid-air would hang the match.

Three new `Tuning.csv` rows control this:

| Key | Default | What it does |
|---|---|---|
| `ball_pickup_radius` | 26 | How close you must get to collect a loose ball |
| `ball_loose_settle_seconds` | 0.35 | Beat before a stopped ball can be picked up |
| `ball_loose_timeout_seconds` | 6 | Safety valve: if nobody reaches it in this long, the nearest player collects it anyway |

If loose balls now sit around too long for your taste, raise
`ball_pickup_radius` toward 40. If possession still changes too easily, lower
it toward 16.

---

## 4. "Why are there Stars from another class in my match?"

Short answer: **they are the opposition, and they always were.**

Here is the shape of it. Your unit CSVs give each class three Tier III cards
marked `Star` and nine ordinary cards. A match spawns twenty units:

- **your ten** — your chosen Star plus nine regulars, all your class
- **their ten** — the enemy's Star plus nine regulars, all *one other* class

So a Brandteufel Star on the pitch during your Lorelei match is the enemy's
Star, doing exactly what it is supposed to. I checked the filtering that
builds both squads and it is correct: your side cannot draw a card from
another class, and it cannot draw a Star into a regular's slot.

**But you were right that something was off**, and two things made this far
more confusing than it needed to be:

**Nothing on screen said which units were Stars, or whose they were.** Twenty
similar-looking units, no markers. That is fixed by the badge above — gold is
yours, red is theirs.

**The enemy could field a Star you had just turned down.** Kickoff offers you
three Stars from three different classes. You pick one. The enemy then picked
its class at random from everything left — *including the two you had just
looked at and rejected*. So the card you passed on could walk straight back
onto the pitch wearing the other shirt, thirty seconds later. That reads as a
bug even though every individual step was working.

The enemy now avoids the classes you were offered, whenever the project has
enough classes to allow it. Turn it off with:

```
enemy_avoids_offered_classes,false,
```

### Checking it yourself

Every kickoff now prints both full line-ups to the Output panel:

```
[team] Your team:
         Tier I: Emberling, Cinderfoot, Ashling
         Tier II: ...
         Tier III: Brandteufel Heatwave ★
         Tier IV: ...
[team] Enemy:
         Tier I: ...
```

If a name under **Your team** is not one you picked, that is a real bug —
send me those lines. If the surprising names are all under **Enemy**, the
game is working and the badge will now make that obvious on the pitch.

---

## One more fix you did not ask for

Both teams are now laid out against a single snapshot of the play area. They
used to be positioned one after the other against a live reading of the
camera, so anything that nudged the view between spawning your side and
spawning theirs mirrored the two halves about slightly different centre lines
and let the formations drift into each other. That was another way foreign
units could appear to be standing in your half.
