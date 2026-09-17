# What Sturmball is still missing, as a football game

You asked what a fan of a football autobattler would want that is not here
yet. This is that list, written after reading the whole project rather than
from a general idea of what football games have.

It is in priority order, and every item says **what already exists** — because
most of these are smaller than they look. The engine is unusually complete;
what is thin is the *fiction around a match*, and that is mostly spreadsheets.

---

## The one-line version

Sturmball has a very good ninety minutes and almost nothing around it.

A football fan does not turn up for a match. They turn up for **a table with
their name moving up it**, for **a squad that is theirs** because of what
happened to it, and for **the next fixture mattering more than the last one**.
Right now a win changes a number in a save file and nothing on a screen the
player cares about. That is the gap, and it is one gap, not eight.

---

## 1. The league table is the game

**What exists:** `Season.csv` (12 fixtures), `Seasons.csv` (a shelf of
competitions), `season_screen.gd`, and `MatchModes.csv` with a `Records
Season` column. `season_db.gd` already keeps `season_wins`, `season_draws`,
`season_losses`, `season_points`, `season_goals_for` and
`season_goals_against` as ordinary counters, so any `Requires` can already
test them.

**What is missing:** *other teams playing each other.* Your table has one
real team in it — yours. Every other side exists only as the opponent in one
fixture.

A table where everyone else's results are invented each week is the single
highest-value thing you could add, and it is cheap: after your match, roll a
result for each other fixture from the two sides' `Power` in `Teams.csv` and
write it into the table. No new screen; `season_screen.gd` already draws one.

What it buys you: **a reason to care about a 1-0 win in November.** Third
place chasing second is the whole emotional content of a football season and
you currently have none of it.

*Suggested shape:* a `Fixtures` column on `Seasons.csv` naming a round-robin,
or simply a `Rivals` column listing the other sides in the division, and one
function that plays their week in the background.

---

## 2. Your players have no history

**What exists:** Stats.csv already counts `goals_by_{card}`,
`duels_won_by_{card}`, `saves_by_{card}`. The counters are there. Nothing
shows them.

**What is missing:** a **player page**. Games played, goals, duels won, the
season they joined, the brews they have drunk.

This is the cheapest big win in the list, because the data is already being
recorded — it is one screen reading counters that exist. A card stops being a
card the moment it has scored eleven goals for you.

*Related and nearly free:* a **top scorer** line on the season screen. One
sort over `goals_by_{card}`.

---

## 3. Nothing happens to a squad between matches

**What exists:** `Brews.csv` (one-match changes), `Talents.csv` (11 rows),
Adventure stamina and knock-outs.

**What is missing:** the things that make a squad a *story*:

* **Injuries and suspensions.** A player who is out for two fixtures forces a
  different team. You already have the machinery — a counter and a `Requires`
  on availability — and it is the single best generator of "I had to play the
  kid at Tier II and he scored".
* **Form.** A player on a run of good games plays better; one on a bad run
  does not. A counter and a modifier on the shot.
* **Fatigue across fixtures**, not just within a run. Playing your Star
  every week should cost something.
* **Signings.** There is no way to acquire a player. A transfer market, a
  youth intake, a scout — some faucet other than "the class you picked".

None of these needs new systems. They need a counter, a `Requires`, and a
place to see them.

---

## 4. The match tells you almost nothing afterwards

**What exists:** `match_stats_screen.gd`, and Stats.csv counting shots,
duels, saves, clean sheets.

**What is missing:** the things a football fan reads after a game.

* **Possession, shots on target, the scoreline by half.** You have the events;
  nobody totals them.
* **A man of the match.** One line: highest duels-won plus goals.
* **A match report in words** — three or four generated sentences. Dialogue.csv
  can already produce text from conditions; it is a natural fit.

---

## 5. There is no commentary and no crowd

**What exists:** `Audio.csv`, `Juice.csv` with fourteen moments.

**What is missing:** the sound of a football match. This is not code — it is
rows and audio files:

* A **crowd bed** that rises with the score and with a shot on goal.
* **Commentary stings** on the moments you already fire: `goal_scored`,
  `play_maker`, `star_switch`, and the new `coin_exact`.
* A **whistle** at kick-off and full time. (The PLAY MAKER whistle exists.)

Every one of these is an `Audio.csv` row and a file. Nothing in code has to
change. This is the biggest *felt* difference per hour of work in the whole
list.

---

## 6. The opposition has no character

**What exists:** `Teams.csv` (12 sides with a `Class` and a `Power`),
`BasicEnemyTeam.csv`, `ClassInfo.csv`.

**What is missing:** a reason to recognise one. A side needs a **colour, a
crest, a ground and a habit** — "they sit deep and play Tier IV early", "they
always brew Fire". Two of those are columns you could add this afternoon; the
habit is one more column read by the enemy's picking.

And **rivalries**: a fixture flagged as a derby, with a different crowd sound
and a bigger reward. One column on `Season.csv`.

---

## 7. Formations are invisible

**What exists:** `PitchZones`, the four tiers, `_slot_for`-style home
positions, a `formation` key in Keys.csv.

**What is missing:** the player choosing one. A football game where you cannot
say "we sit deeper today" is missing the one strategic lever every football
fan expects to have. You have the zones; a `Formations.csv` with a name and
four tier offsets would make it a decision, and it would interact with the
tier ladder rather than fighting it.

---

## 8. Set pieces

There is a kick-off, a goal kick and a shot. There is no **corner**, **free
kick** or **penalty**. A penalty in particular is free drama and you already
have the shootout view to draw it in — it is the coin clash with a different
title.

Not urgent. But "we won a penalty" is a sentence football fans like.

---

## What I would NOT add

Being honest about the other half of the question:

* **Real-time control.** It is an autobattler. Adding direct control would
  dilute the thing that makes the draft matter.
* **A full 11-a-side simulation.** The four tiers are a better game than a
  worse copy of Football Manager, and the tier ladder is the reason the maths
  stays clean.
* **More numbers on a card.** The ladder says a card's power is its slot.
  Adding pace, stamina and flair would break the one rule everything else
  leans on.

---

## If you only do three

1. **Other teams play their fixtures**, so the table moves without you.
2. **A player page**, reading counters you already record.
3. **Crowd and commentary rows in Audio.csv** — no code at all.

Those three turn a very good match into a season, and a season is the thing
people come back to.
