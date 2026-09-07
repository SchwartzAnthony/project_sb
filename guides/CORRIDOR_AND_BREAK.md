# Keeping the ball out of Tier IV, and the break to goal

Two changes. Both are `Tuning.csv` rows — no script needs opening to adjust
either, and either can be switched off from the spreadsheet.

---

## 1. The ball stays in midfield until the whistle

During ordinary waiting play the ball is fenced into **quarters 2 and 3** — the
middle half of the pitch. Quarters 1 and 4 are the two Tier IV territories
(theirs at one end, yours at the other), and the ball never enters them.

```
   | quarter 1 | quarter 2 | quarter 3 | quarter 4 |
   | you I     |    ball lives here    | you IV    |
   | them IV   |                       | them I    |
   |___________|_______________________|___________|
                 ^ during waiting play
```

So ambient passing can never threaten a goal, and **every shot has to come out
of a PLAY MAKER**. The fence lifts the moment a PLAY MAKER starts resolving.

Three things enforce it, so there is no single point of failure:

- **Passes** can only be aimed at team-mates inside the strip. Tier IV
  therefore simply never receives the ball during waiting play.
- **The carrier** aims at the edge of the strip rather than at the goal, so he
  does not run into the fence and lean on it.
- **A stray ball** — after a goal kick that lands too far forward, say — is
  played back inside rather than snapped. If a carrier is caught outside, he
  passes it back in at the next opportunity.

| Key | Default | |
|---|---|---|
| `ball_roam_quarter_first` | 2 | first quarter the ball may enter, counted 1–4 from your goal |
| `ball_roam_quarter_last` | 3 | last quarter it may enter |
| `ball_corridor_return_speed` | 420 | how fast a stray ball rolls back in |

**Set `first` to 1 and `last` to 4 to switch the whole rule off.**

Measured across five 90-second simulated runs: **0 breaches in 4250 samples.**

---

## 2. The break

When the Tier IV duel settles, the side that won it now **breaks for goal
together** before the shot, instead of the ball appearing at a shooter who was
standing still.

The order of it:

1. The Tier IV duel resolves. Whoever holds the ball is the shooter.
2. **The break starts.** Every unit on that side abandons its quarter and runs
   at the goal it attacks, at normal pace.
3. The other side **drops back with them** rather than staying on its post.
4. After `surge_lead_seconds`, the ball is worked forward — through the
   team-mates standing along the way — to the Tier IV winner.
5. He carries it into range and shoots.

Two details worth knowing, because both were wrong on the first attempt and
the simulation caught them:

**The break closes a fraction of the remaining distance to goal**, not a fixed
number of pixels. A fixed shift squashed the back players into the touchline
while the front ones ran out of pitch. Closing 45% of the gap moves the whole
shape up while keeping its order and spacing.

**The defending side had to be unleashed too.** Left marking from their posts,
the attack ran straight through them and the two teams passed each other like
ghosts. Letting defenders retreat with their man cut the number of overlapping
players during a break by **61%** (2.24 stacked pairs down to 0.87).

| Key | Default | |
|---|---|---|
| `surge_lead_seconds` | 0.7 | how long they run before the ball starts moving |
| `surge_advance` | 0.45 | how much of the gap to goal the break closes. 0 = nobody moves |
| `surge_centring` | 0.35 | how much it funnels toward the goal mouth. 0 = everyone keeps their lane |

### One judgement call

You described this for the case where **the attacker loses** at Tier IV. I made
it run whichever way the last duel goes, because a shot with no build-up looks
just as abrupt when the attacker holds. If you want it only on the turnover,
say so — it is a one-line change.

---

## How this was checked

Still no Godot 4 in my sandbox, so I could not play it. As before I ran the
rules in a Python copy on a pitch your size and measured. `corridor_and_break.gif`
is that simulation: the yellow lines are the fence, and they vanish when the
break starts.

---

## ⚠ Your repo is one delivery behind

I cloned `project_sb` before starting and it still has the **mid-turn** version
of the previous task. None of your own edits are in there — it is exactly what
I sent partway through — but it is missing:

- the **mirrored** quarters you chose (it still has both teams sharing each quarter)
- `zone_overlay.gd` entirely
- the ball trail and possession ring
- 4 `Tuning.csv` rows

The files in this delivery are built on the correct versions, so copying this
batch in brings everything up to date at once. Nothing needs merging.
