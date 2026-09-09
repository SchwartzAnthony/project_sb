# Adventure, Phase 1 — the Bounty Board

Phase 1 is built and pressable. Five new spreadsheets, a loader, a run
object, and the board screen. Your six answers are written down at the
bottom as the spec Phase 3 will be built against.

---

## STEP 1 — Where the files go

| File | Folder | |
|---|---|---|
| `adventure_db.gd` | `src/core/` | **NEW** |
| `adventure_run.gd` | `src/core/` | **NEW** |
| `bounty_board.gd` | `src/ui/` | **NEW** |
| `bounty_board.tscn` | `src/ui/` | **NEW** |
| `Biomes.csv` `Bounties.csv` `AdventureEnemies.csv` `Items.csv` `Drops.csv` | `data/` | **NEW** |
| `scene_paths.gd` `card_database.gd` `player_data.gd` `content_report.gd` | `src/core/` | replace |
| `base_screen.gd` | `src/ui/` | replace |
| `MenuConfig.csv` `MatchModes.csv` `Tuning.csv` | `data/` | replace |

**All five new CSVs need "Keep File (No Import)":** FileSystem → click the
file → **Import** tab → **Keep File (No Import)** → **Reimport**.

---

## STEP 2 — What you can do now

- **Adventure** replaces Quick Match on the main menu, and sits beside
  "Play a match" at the base. Both open the **Bounty Board**.
- The board shows **biomes on the left** (locked ones greyed, saying exactly
  what would open them) and **the bounties pinned up for the one you picked
  on the right**.
- Each bounty names its boss and reads out **how many layers it has, how
  deep it is, and what it hits for** — so you can see what you are walking
  into before you commit.
- **Start Exploring** opens the run, remembers the bounty, and sends you to
  class select → team builder, so you pick the squad you set off with
  exactly the way you pick a league side.

**What happens after that is still an ordinary match.** The scrolling field,
the encounters and the loot are Phases 2–5. That is deliberate — the board
and its spreadsheets are worth getting right before anything is built on
them.

---

## STEP 3 — The five spreadsheets

### Biomes.csv — the areas

`ID, Name, Order, Requires, Waves, Enemy Pool, Scroll Art, Ground, Music, Drops, Difficulty, Description`

**Waves** is how many encounters before the boss. **Enemy Pool** is which
`AdventureEnemies.csv` rows can turn up. **Ground** and **Drops** are the
scrolling floor and what you pick up off it.

### Bounties.csv — the jobs. **A bounty is a boss.**

`ID, Name, Biome, Boss, Reward, Requires, Repeatable, Recommended Power, Art, Description`

One row is one job on the board: go into this biome, kill this thing, get
paid. **Reward** is the normal Effects language, so
`unlock:Marsh King;count:coins+120` works with no new code. A non-repeatable
bounty you have already claimed shows as **✓ claimed**.

### AdventureEnemies.csv — and the layers

`ID, Name, Pool, Tier, Power, Layers, Damage, Targeting, Element, Ability, Art, Drops, Weight, Boss, Description`

**This is the important column.** A Bog Lurker is `Hide:3:1|Body:6`:

| | |
|---|---|
| `Hide` | 3 points thick, and **soaks 1** off every hit |
| `Body` | 6 points thick, no soak |

The shape is **`Name:Amount:Soak`**, separated by `|`. Soak is optional —
`Body:5` is a perfectly good one-layer enemy. Damage always goes into the
**outermost layer still standing**; empty the last one and the enemy dies.

The Marsh King is `Crown:6:2|Weed:8:1|Body:12` — three layers, each softer
than the one outside it. That is what makes a boss a boss rather than just a
big number.

**Other columns worth knowing:**

- **Tier** — which tier of the draft it stands in. *The ladder governs
  enemies too*: a Tier I enemy must be a 0, 1 or 2. The startup report
  catches it if you slip.
- **Targeting** — `weakest` `strongest` `lowest_stamina` `aoe`. The
  infrastructure you asked for. `weakest` is the default rule you specified;
  the others are there for later enemies.
- **Weight** — how often it turns up. **0 means never randomly**, which is
  what bosses are.

### Items.csv and Drops.csv

Items are **counters**, so a building's cost, a talent's requirement and a
bounty's reward all already understand them. Nothing had to be built.

A drop **table** is every row in `Drops.csv` sharing a `Table` name.
`Chance` is 0–1, and `Requires` gates a drop — the Marsh Ale recipe only
falls if you have the Brewery.

---

## STEP 4 — Two problems the check caught

I ran the shipped content through the same rules the game uses. Two real
faults, both now fixed, both worth knowing because you will hit them again:

**1. The Hollowdeep had no Tier II enemy.** Every encounter there would have
handed you a free Tier II win forever — the walkover rule cutting the wrong
way. `adventure_db.gd` now names any biome missing a tier at startup.

**2. The bosses were too fat to kill.** At a typical power gap of 4 the
Marsh King needed 14 won tiers and the Ash Tyrant 25 — several draft rounds
of flawless play each. Trimmed to a readable ramp:

| Boss | Layers | Depth | Won tiers at gap 4 |
|---|---|---|---|
| The Reed Warden | 2 | 12 | **4** — about one draft round |
| The Slag Walker | 2 | 18 | **7** |
| The Marsh King | 3 | 26 | **9** — two or three rounds |
| The Ash Tyrant | 3 | 36 | **13** |
| The Hollow Mother | 3 | 44 | **15** — four rounds, and it should be |

These are first-guess numbers and the layer amounts are the knob to turn.
I have the check script, so when combat exists I can re-run it against real
fights rather than my arithmetic.

**One rule that falls out of the layers:** damage is
`(power gap × scale) − soak`, but never less than `adventure_damage_minimum`
(1). So a layer can always be chewed through eventually — a soak is a wall
that slows you, never one that stops you. The report warns if you write a
soak of 5 or more, because the largest gap possible is 5.

---

## STEP 5 — Your answers, written down as the spec

This is what Phase 3 and 4 will be built to. **Correct anything I have
misread now**, while it is still only a document.

**Encounter order**
1. Party meets a wave and stops in formation on the left.
2. **You pick which enemy to focus** — before any tier is drafted.
3. Draft Tier I. **The enemy reveals its Tier I the moment you commit.**
4. Same for II, III, IV. **Flee is available until you commit Tier IV.**
5. All four resolved, then damage is dealt.

**Winning a tier**
- `damage = (your total − their total) × adventure_damage_scale`, minimum 1.
- **A tier the other side cannot field is a walkover** — an automatic win,
  and the damage counts **twice** (`adventure_walkover_multiplier`). An
  empty slot is drawn as an empty shirt so you can see it.
- This cuts both ways: your knocked-out Tier I is a free double for them.
- Your damage goes to **the enemy you focused**, delivered by the last
  player in that tier duel kicking the ball at it.

**Enemies hitting you**
- Default targeting is **weakest first**: Tier I's 0, then Tier II's 1, then
  Tier III's 2, then Tier IV's 3.
- `strongest`, `lowest_stamina` and `aoe` exist in the column for later.

**Stamina — Adventure only**
- `stamina = adventure_stamina_base + power × adventure_stamina_per_power`
  (6 and 3 by default), so a Tier I 0-power has 6 and a Tier IV 5-power has
  21. Weak in stamina, strong in abilities early, as you wanted.
- An optional **`Stamina`** column on a unit CSV overrides one card.
- **It lives on the run, never on the card.** Damage written onto Müller in
  the Marshlands would still be on Müller in Saturday's league match, and
  nothing in this project ever writes to a card.
- League matches are untouched: the only thing with stamina there is still
  the keeper.

**Fleeing and the haul**
- Nothing is yours until you carry it home. The haul sits on the run.
- **Flee keeps 80%** (`adventure_flee_keep`) of everything collected this
  run — materials *and* recipes — rounded down.
- **Party wiped keeps nothing.**
- The warning box says both numbers before you commit.

**The scroll** is cosmetic: the field slides left while the party runs
right. Up to three of the nearest players peel off to collect a pickup
(`adventure_pickup_carriers`).

**Brews work in Adventure.** Nothing to change — they are applied at match
start already.

---

## STEP 6 — What I need from you

Only two things, and neither blocks Phase 2:

1. **Is the encounter order above right?** Particularly: you pick the focus
   target *once at the start of the encounter*, not per tier.
2. **Can a wave hold more than one enemy?** Your "pick which enemy to focus
   (if there are multiple)" says yes. If so — do the non-focused enemies
   still hit you each round? I would say **yes, all living enemies attack**,
   which is what makes focusing a real decision.

---

## NEXT — Phase 2, the endless scroll

The run scene: the party running right, the field sliding left, ground
pickups collected by the nearest players, and a stop when a wave arrives.
The encounter will resolve as an automatic win for now, so the loop is
playable end to end before combat goes in.

That is the phase where you tell me whether the speed and the spacing feel
right, which is not a thing either of us can judge from a spreadsheet.
