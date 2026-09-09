# Two kinds of match: the Season, and the Enemies

This document is the design for the second game mode. **Part 1 is built and
in this round. Part 2 is designed, not built** — the CSV shapes are here so
you can write content now and so the next build round is typing rather than
deciding.

---

## The two modes, side by side

| | **Season Match** | **Quick Match** |
|---|---|---|
| Against | another human side | enemies (nests, monsters) |
| Clock | 90 minutes | none — it ends when the rounds do |
| Stars | three, rotating at HOLD UP | one, all the way through |
| Table | the result goes in it | never touched |
| They get stronger by | drinking brews | being a harder kind of enemy |
| You come away with | league position, and the big unlocks — *Season of Fire* opens a building | resources, recipes, items, achievement progress |
| Why you play it | the campaign | you need materials and have no buildings yet |

The important relationship: **Quick Matches are how you afford the buildings
that would otherwise make your materials.** Early on you have no Mill and no
Well, so you go and hit things with a football until you do.

---

# PART 1 — WHAT IS BUILT NOW

## MatchModes.csv

A match's shape is a row, not code.

```
ID,Name,Records Season,Timer,Cycles,Rounds,Star Rotation,Opponent,Requires,Description
season,Season Match,yes,90,3,3,yes,team,,"The league..."
quick,Quick Match,no,0,1,3,no,team,,"A single run for resources..."
cup,Cup Tie,no,90,3,3,yes,team,unlocked:The Cup,"..."
```

| Column | |
|---|---|
| **ID** | what a button names. `match:cup` starts the `cup` row |
| **Records Season** | `yes` = the result goes in the table and moves the season on. `no` = it never touches it |
| **Timer** | minutes. **`0` means no clock at all** — the match ends when the last round has been played |
| **Cycles / Rounds** | how long. A season match is 3 cycles of 3 |
| **Star Rotation** | `no` = one Star for the whole match, no HOLD UP |
| **Opponent** | `team` today. `nest` is Part 2 |
| **Requires** | the same condition language as everywhere else, so a mode can be locked |
| **Description** | the hover text on its button |

**Adding a mode is a row.** A five-cycle cup tie that does not count, a
one-round training run — neither needs code.

## What you get today

- **Quick Match on the main menu** — the button was already in
  `MenuConfig.csv`; it now starts the `quick` mode rather than being a
  shortcut to an ordinary match.
- **Quick Match at the base**, beside "Play a match", because that is where
  you are standing when you realise you need wheat.
- No clock. The corner reads **ROUND 2 / 3** instead of a running time.
- One Star, no HOLD UP.
- Nothing written to the season table — and the post-match screen's
  Continue button says **Back to the base** and goes there, rather than
  showing you a table that did not change.
- **Every `Stats.csv` counter still runs.** That is what makes it worth
  playing: the resources, unlocks and achievement progress are all real.

## Making a Quick Match pay, today, with no new code

Resources are counters, so `Stats.csv` already grants them:

```
wheat,goal_scored,,1,Quick Match,Wheat,One wheat per goal.
coins,duel_won,,2,Quick Match,Coins,Two coins per duel won.
scrap,match_ended,result=win,5,Quick Match,Scrap,Five for winning.
```

Put them in a **Group** called `Quick Match` and they get their own panel on
the post-match screen. Then a building costs them:

```
mill,The Mill,Grinds what the fields give up.,count:wheat>=20 and count:scrap>=5,mill,0.3,0.4,count:wheat-20;count:scrap-5,
```

That loop — play quick matches, collect, buy the Mill, the Mill makes wheat
for you — works **now**, with rows only.

---

# PART 2 — THE ENEMY MODE, DESIGNED

This is the part that is genuinely different, and it is real work: new
units, new behaviour, a new kind of target. Here is the shape it should take
so that when it is built, it is built on the same bones as everything else.

## The idea, restated

- Enemies come out of **nests**. A nest has to be cracked open first.
- The soccer players **pass the ball between themselves**, exactly as now.
- When a player wins a **power check**, they **kick the ball at an enemy**.
- **The enemy is a goalie.** It has a stamina bar and it tries to save.
- When an enemy's stamina runs out it **dies and drops things** — recipes,
  items, resources.

The elegant part is that **you already have all of this**. `GoalieData` has
stamina and a save ability. `shootout_view.gd` already resolves a shot
against a keeper. An enemy is a goalie that stands in the open, belongs to a
nest, and drops loot when it is beaten. That is a much smaller build than it
sounds, and it is why the mode is worth doing this way rather than as a
separate combat system.

## Enemies.csv

```
ID,Name,Kind,Stamina,Save Power,Tier,Element,Ability,Art,Drops,Description
grubling,Grubling,swarm,2,0,I,,,grubling,grub_drops,"Weak, and there are always more."
husk,Ash Husk,brute,5,1,II,Fire,,husk,husk_drops,"Slow. Soaks a shot."
nestward,Nestward,guard,8,2,III,,shield_first_shot,nestward,ward_drops,"Guards the nest it came from."
```

| Column | |
|---|---|
| **ID / Name** | as everywhere else |
| **Kind** | `swarm` `brute` `guard` — how it behaves. One word the movement code reads |
| **Stamina** | how many shots it takes. This is `GoalieData.max_stamina`, reused |
| **Save Power** | subtracted from a shot, like a keeper's |
| **Tier** | which tier's players it stands in front of, so the ladder still decides who faces what |
| **Element** | for ability matching — a Fire enemy, a Water enemy |
| **Ability** | an `Abilities.csv` id, so enemies use the ability engine you already have |
| **Drops** | names a row in `Drops.csv` |

## Nests.csv

```
ID,Name,Health,Spawns,Rate,Max Alive,Tier,Requires,Art,Drops,Description
mound,Grub Mound,3,grubling,1,4,I,,mound,mound_drops,"Crack it and grublings pour out."
cinder_pit,Cinder Pit,6,husk|grubling,1,3,II,,pit,pit_drops,"Ash Husks, slowly."
```

| Column | |
|---|---|
| **Health** | shots to crack it open |
| **Spawns** | which enemies, separated by `\|` |
| **Rate** | how many come out per round |
| **Max Alive** | the cap, so a mound cannot flood the pitch |
| **Tier** | which part of the pitch it sits in |
| **Drops** | cracking the nest itself pays |

## Drops.csv

```
ID,Item,Amount,Chance,Requires,Notes
grub_drops,wheat,1,1.0,,Always one wheat.
grub_drops,scrap,1,0.25,,A quarter of the time.
mound_drops,recipe_fire_ale,1,0.1,unlocked:Brewery,"Only once you can brew."
```

One row per possible drop; a drop table is every row sharing an **ID**.
**Chance** is 0–1. **Requires** is the usual condition language, so a recipe
can be gated behind the building that would use it.

Because items are counters, everything that already tests a counter works on
them the day they exist — a building's cost, a talent's requirement, a
dialogue choice.

## How a round plays

1. Nests are placed by tier at kick-off, from the mode's `Opponent` column.
2. Your players pass as they do now.
3. At PLAY MAKER you pick a card, exactly as now.
4. The power check resolves against **the enemy standing in that tier**
   rather than against an opposing card.
5. Winning it means your player **shoots**. `shootout_view` already draws
   this; the keeper is the enemy.
6. Stamina drops by the shot's power. At zero the enemy dies and rolls its
   drops.
7. No enemies left in a tier and its nest still standing? The shots go at
   **the nest** instead.
8. Rounds run out, full time, and the drops panel is the post-match screen
   you already have.

## What actually needs writing

In rough order of size:

1. `enemy_db.gd` — read the three CSVs. Same shape as `team_db.gd`.
2. `enemy_unit.gd` — a `GoalieUnit` that stands in the open, holds a nest
   reference, and dies. It can reuse the placeholder-drawing trick that
   makes the keeper visible without art.
3. `nest_unit.gd` — health, a spawn timer, and it uses the same drop roll.
4. In `main_scene`, one branch: when the mode's **Opponent** is `nest`,
   build nests instead of an opposing team, and resolve a won power check
   against the enemy in that tier instead of against a card.
5. The drops panel — which is `MatchReport` with no changes, because drops
   are counters and it already notices counters changing.

Step 4 is the only one that touches existing code, and it is one branch.

## Two questions before it gets built

1. **Do enemies attack back?** If a player *loses* a power check, does
   something happen to them — sent off for a round, stamina of their own —
   or is the cost simply that the shot is wasted? The second is simpler and
   probably better; the first gives the mode teeth.
2. **Does a Quick Match end when the nests are cleared, or when the rounds
   run out?** "Clear the nests" is a goal and reads better; "rounds run out"
   is what is built. I would do **clear the nests, with the rounds as a
   ceiling** — you win by clearing, you leave with less if you run out.

---

# WHERE THE BIG UNLOCKS LIVE

You said a Season unlocks a building — *Season of Fire* opens something.
That is `Season.csv`'s reward on the final fixture, which already works:

```
Reward: unlock:The Forge
```

and the building appears because `Buildings.csv` has a row whose
**Requires** is `unlocked:The Forge`. No code. This is the split worth
holding on to:

- **Quick matches pay in materials** — counters, spent at the base.
- **Seasons pay in unlocks** — new buildings, new classes, new places.

One is the treadmill, the other is the story. Keeping them in different
currencies is what stops either one trivialising the other.
