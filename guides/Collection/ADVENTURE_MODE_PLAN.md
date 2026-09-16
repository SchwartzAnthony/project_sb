# Adventure Mode — the plan, before any code

**No gameplay code has been written for this.** This document is the loop as
I understand it, the gaps I want you to close, the CSV structures, and a
six-phase build order where every phase is playable on its own.

---

# PART 1 — THE LOOP, AS I UNDERSTAND IT

1. **Hub** — "Adventure" on the main menu and the base opens a **Bounty
   Board**: quests, rewards, a choice of biome, and *Start Exploring*.
2. **Scroll** — your 10 players run right, passing the ball, picking up
   resources off the ground. Endless.
3. **Encounter** — they meet enemies, stop in formation on the left, idle.
4. **Draft** — you draft Tier I, II, III and IV. The enemy drafts too.
5. **Flee** — available *during* the draft, costs 20% of resources. Draft
   all four tiers and you are locked in.
6. **Resolve** — power totals compared. Winner deals damage. The last player
   kicks the ball at the enemy for the damage.
7. **Stamina** — *this mode only*, players have a health bar. At 0 they are
   knocked out. Enemies damage players based on their wins.
8. **Victory** — loot popup, then *Continue Forward* or *Return to Base*.
9. **Progression** — each biome has its own enemies, drop rates and an **End
   Boss**. The boss gives the best resources and brewing recipes.

That reads clean. Below are the places where it is not yet decided, and I
need answers before Phase 3.

---

# PART 2 — GAPS AND CONCERNS

## ⚠️ 1. This contradicts the enemy design from last round

Last round's `ENEMIES_AND_QUICK_MATCH.md` had enemies as **goalies** — nests
to crack, stamina bars, players shooting at them. This design has enemies
**drafting cards and comparing power totals**, like an opposing team.

Those are two different games. **I think this one is better** — it reuses
the draft you already have, so an encounter is a match round rather than a
new combat system, and the "last player kicks the ball at the enemy" keeps
the shooting as the *payoff* rather than the mechanic.

**Please confirm: this design replaces the nest design.** If so I will
retire that document so we are not carrying two answers.

## ⚠️ 2. The tier ladder versus knocked-out players — the big one

Your ladder rule says a tier holds **one card of each power**. Tier I is a
0, a 1 and a 2.

Three encounters into a run, your 2-power Tier I is knocked out. Now Tier I
cannot be drafted legally. **What happens?**

| Option | What it feels like |
|---|---|
| **A. The tier is skipped** — you draft 3 tiers, and the missing tier contributes 0 power | Losing a player *hurts*, visibly. Simple. My preference |
| **B. A reserve fills the rung** from cards you own but did not field | Softer. Needs a reserve bench in the UI |
| **C. The tier drafts short** — two cards instead of three | Muddies the ladder, which you have asked to be absolute |

**I recommend A**, because it makes stamina matter and keeps the ladder
untouched. It also gives the run a natural death spiral, which is what makes
*Return to Base* a real decision.

## ⚠️ 3. Where does stamina live?

A core rule of this project is that `PlayerData` is **never written to** —
cards are shared, so damage written onto a card would follow it into your
next season match.

So stamina must live in a **run state** object that maps card → current
stamina, created when the run starts and thrown away when it ends. Same
pattern as `MatchReport`, riding on the SceneTree.

**No new CSV needed for the numbers.** Two rows in `Tuning.csv`:

```
adventure_stamina_base,6,"Starting stamina for a Tier I 0-power player in Adventure."
adventure_stamina_per_power,3,"Extra stamina per point of power. A 5-power card gets base + 15."
```

So a 0-power has 6 and a 5-power has 21 — strong cards last longer, which is
already true of everything else in your game. An optional **`Stamina`**
column on a unit CSV overrides one specific card.

## ⚠️ 4. Flee: 20% of *what*?

If it is 20% of everything banked at the base, nobody will ever flee.

**I recommend 20% of the run's unbanked haul** — what you have picked up
since leaving. That makes fleeing a real choice that costs real progress
without touching your savings, and it makes *Return to Base* (which banks
everything) meaningfully different from fleeing.

## ⚠️ 5. Does the draft reveal the enemy?

This decides whether Flee is a decision or a coin flip.

**I recommend: the enemy reveals its card for a tier the moment you commit
yours.** So after Tier I you know one of their four; after Tier II you know
two. Every pick tells you more, and the fourth pick is the point of no
return. That is genuine escalating tension and it costs nothing to build.

Drafting blind makes Flee unusable. Full reveal up front makes it trivial.

## ⚠️ 6. What is the damage formula?

"The winning side deals damage" needs a number. **I recommend:**

```
damage = winning total − losing total
```

A 14-vs-13 win chips one off. A 14-vs-4 win takes ten. No new concept,
readable on screen, and it means a blowout is worth playing for. It should
be a `Tuning.csv` row so you can scale it:

```
adventure_damage_scale,1.0,"Multiplies the power difference to get damage dealt."
adventure_damage_minimum,1,"A win always takes at least this much off."
```

Who takes the damage on the losing side? **I recommend the lowest-stamina
player still standing** — it concentrates losses so knockouts actually
happen, rather than spreading damage so thinly nobody ever falls.

## ⚠️ 7. "Endless" versus "End Boss"

These pull against each other. **I recommend:** a biome has a fixed number
of waves (`Waves` in `Biomes.csv`), the boss is the last one. "Endless"
means you *choose* to continue after each wave. Beat the boss and the biome
loops with a scaling multiplier, so it is endless for anyone who wants it
and finite for anyone who does not.

## ⚠️ 8. What ends a run?

Three ways, and I want to confirm all three:

- **Return to Base** — you keep everything. The good ending.
- **Flee** — you keep 80% and go home.
- **All 10 knocked out** — do you keep anything? **I recommend you keep
  nothing.** That is what makes *Return to Base* the interesting button.

## Smaller questions

- Are ground resources picked up **automatically** as they run? (I would say
  yes — it is an autobattler.)
- Do bounties persist across runs, and can they be rerolled?
- Does Adventure use your team-builder team, or a fixed Adventure squad?
- Do brews work in Adventure? (They are per-match today.)

---

# PART 3 — THE CSV STRUCTURES

Five new files. Every one follows the project's conventions: identified by
its columns, `Requires` in the usual language, `Art` a file name, and
anything numeric overridable from `Tuning.csv`.

## Biomes.csv — the areas you explore

```
ID,Name,Order,Requires,Waves,Enemy Pool,Boss,Scroll Art,Music,Drops,Difficulty,Description
marshlands,The Marshlands,1,,5,marsh,marsh_king,bg_marsh,marsh_theme,marsh_common,1,"Wet, green, and full of things that bite."
cinderwastes,The Cinder Wastes,2,unlocked:Marsh King,6,cinder,ash_tyrant,bg_cinder,cinder_theme,cinder_common,2,"Ash underfoot. Everything here burns."
```

| Column | |
|---|---|
| **Order** | where it sits on the Bounty Board |
| **Requires** | so a biome is locked until you beat the one before |
| **Waves** | encounters before the boss |
| **Enemy Pool** | which `AdventureEnemies.csv` rows can appear (matched on their Pool column) |
| **Boss** | the enemy ID of the End Boss |
| **Scroll Art / Music** | the endless background, and its track |
| **Drops** | the drop table for ordinary pickups off the ground |
| **Difficulty** | a multiplier on enemy power and stamina |

## AdventureEnemies.csv — who you meet

```
ID,Name,Pool,Tier,Power,Stamina,Damage,Element,Ability,Art,Drops,Weight,Boss,Description
mire_grub,Mire Grub,marsh,I,1,4,1,Water,,grub,grub_drops,10,no,"Slow and soft."
bog_lurker,Bog Lurker,marsh,II,2,7,2,Water,,lurker,lurker_drops,6,no,""
marsh_king,The Marsh King,marsh,IV,5,40,4,Water,shield_first_hit,king,king_drops,0,yes,"The End Boss of the Marshlands."
```

| Column | |
|---|---|
| **Pool** | matches a biome's Enemy Pool |
| **Tier** | which tier of the draft it stands in — **so the ladder still governs who faces what** |
| **Power** | its number in the power comparison |
| **Stamina / Damage** | its health, and what it takes off you when it wins |
| **Ability** | an `Abilities.csv` ID — enemies use the ability engine you already have |
| **Weight** | how often it turns up. 0 = never randomly (bosses) |
| **Boss** | `yes` puts it at the end of the biome |

## Bounties.csv — the board

```
ID,Name,Biome,Goal,Target,Amount,Reward,Requires,Repeatable,Description
first_blood,First Blood,marshlands,kill,mire_grub,10,count:coins+50,,no,"Put down ten Mire Grubs."
gather_reed,Reed Cutter,marshlands,collect,reed,25,unlock:Reed Basket,,yes,"Bring back 25 reed."
king_slayer,King Slayer,marshlands,boss,marsh_king,1,unlock:Marsh King;count:recipes+1,,no,"Kill the Marsh King."
```

| Column | |
|---|---|
| **Goal** | `kill` `collect` `boss` `survive` `flee_never` — the kind of thing being counted |
| **Target** | what specifically (an enemy ID, an item ID) |
| **Amount** | how many |
| **Reward** | the usual Effects language |
| **Repeatable** | `yes` = it comes back after claiming |

**Progress is a counter**, so it needs no new bookkeeping: a `kill` bounty
watches `count:killed_mire_grub`, which a `Stats.csv` row fills in.

## Items.csv — what you pick up

```
ID,Name,Kind,Stack,Art,Description
reed,Reed,material,99,reed,"Cut from the marsh. The Brewery wants it."
bog_iron,Bog Iron,material,99,iron,""
recipe_marsh_ale,Marsh Ale Recipe,recipe,1,scroll,"Teaches the Brewery to make Marsh Ale."
```

Items are **counters**, so everything that already tests a counter works on
them from day one — a building's cost, a talent's requirement, a bounty.

## Drops.csv — what things leave behind

```
ID,Item,Amount,Chance,Requires,Notes
grub_drops,reed,2,1.0,,Always two reed.
grub_drops,bog_iron,1,0.2,,One in five.
king_drops,recipe_marsh_ale,1,1.0,unlocked:Brewery,"Only if you can brew."
marsh_common,reed,1,1.0,,Ground pickups while scrolling.
```

A drop table is every row sharing an **ID**. **Chance** is 0–1.

## Tuning.csv — the numbers, not a new file

```
adventure_stamina_base,6,"Starting stamina for a 0-power player in Adventure."
adventure_stamina_per_power,3,"Extra stamina per point of power."
adventure_damage_scale,1.0,"Multiplies the power difference to get damage."
adventure_damage_minimum,1,"A win always takes at least this much off."
adventure_flee_cost,0.2,"Fraction of this run's unbanked haul lost by fleeing."
adventure_scroll_speed,120,"Pixels per second the party runs right."
adventure_pickup_gap,3.0,"Seconds of scrolling between ground pickups."
```

---

# PART 4 — THE ROADMAP

Six phases. **Every one ends with something you can press play on**, so you
can tell me it feels wrong before the next phase builds on it.

### Phase 1 — The Bounty Board *(small)*
`Biomes.csv`, `Bounties.csv`, a new `adventure_db.gd`, and the Bounty Board
screen. "Quick Match" becomes "Adventure" on the menu and the base. Picking
a biome and pressing *Start Exploring* runs an ordinary match for now.

**You get:** the screen, the biome list with locks, bounties showing real
progress from your counters. Nothing new to balance yet.

### Phase 2 — The endless scroll *(medium)*
The run scene: 10 players running right, the background scrolling, ground
pickups collected automatically, and a stop when an encounter arrives. The
encounter immediately resolves as a win.

**You get:** the feel of the mode. This is the phase where you tell me if
the speed and the spacing are right.

### Phase 3 — The encounter *(medium — needs your answers)*
The draft against an enemy line-up, tier-by-tier reveal, Flee, the power
comparison, and the ball-kick payoff. No stamina yet — the winner just wins.

**Blocked on:** gaps 2, 4, 5 and 6 above.

### Phase 4 — Stamina and knockouts *(medium)*
`adventure_run.gd` holding stamina per card, damage from the comparison,
knockouts, and the run ending when the party falls. Whatever we decide for
gap 2 happens here.

**You get:** the mode's actual tension.

### Phase 5 — Loot and the choice *(small)*
`Items.csv`, `Drops.csv`, the loot popup, *Continue Forward* / *Return to
Base*, and banking. Bounties start completing.

**You get:** the reason to play it.

### Phase 6 — Bosses and biomes *(medium)*
End Bosses, biome unlock chains, recipes as drops, and the scaling loop
after a boss falls.

**You get:** the progression.

---

# WHAT I NEED FROM YOU TO START PHASE 3

Just these, in a sentence each:

1. Does this design **replace** the nest/goalie design? (I think yes.)
2. **Knocked-out tier** — skip it, or fill from a reserve? (I recommend skip.)
3. **Flee costs 20% of** the run's haul, or of everything you own?
4. **Does the enemy reveal** its card as you commit each tier?
5. **Damage = power difference?** And does the lowest-stamina player take it?
6. **All 10 down** — keep nothing?

Phases 1 and 2 need none of this, so say the word and I will start on the
Bounty Board while you think about the rest.
