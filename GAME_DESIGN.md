# Godot Autobattler — Design Spec

**Status:** living document. Re-upload this at the start of any new AI chat so nothing has to be re-explained.
**Last updated:** 2026-09-06

---

## 1. Match shape

A match is a strict **90 in-game minutes**. The clock pauses for exactly **11 events**.

| Term | Meaning |
|---|---|
| **Round** | One "PLAY MAKER!" — you draft through Tier I → II → III → IV. |
| **Cycle** | Three rounds: choices shrink 3-of-3 → 2-of-2 → 1-of-1. |
| **HOLD UP!** | End of a cycle. Active Star Player goes inactive, you pick a replacement, all 9 regulars reset to active. |

**Full sequence**

```
Kickoff  → pick 1 of 3 Star Players (this chooses your class/race)
         → formation spawns, whistle blows, clock starts

Cycle 1  → PLAY MAKER (3-of-3)   ┐
         → PLAY MAKER (2-of-2)   ├ 3 rounds
         → PLAY MAKER (1-of-1)   ┘
         → HOLD UP!  pick 1 of the 2 remaining Stars

Cycle 2  → PLAY MAKER ×3
         → HOLD UP!  pick the 1 remaining Star

Cycle 3  → PLAY MAKER ×3
         → no Stars left; clock runs out to 90:00
```

**9 PLAY MAKERs + 2 HOLD UPs = 11 pauses.**

---

## 2. Roster

**10 units on the pitch per side:** 1 active Star Player + 9 regulars.

- Tiers are **I, II, III, IV**.
- Your active Star Player **occupies one tier**. That tier is hidden from drafting — the Star already fills the slot.
- The other **three tiers hold 3 regular units each** (3 × 3 = 9).
- **All three Star Players in a class/race bundle share the same tier**, so the hidden tier never changes across a match. The same 9 regulars stay on the pitch all match; HOLD UP! just resets their exhaustion.
- Rosters are class/race specific — you only ever draft from your own class's cards.
- The enemy is always a **different class** from yours, so no mirror matches. Their Star may sit in a **different tier** than yours.

**Exhaustion:** picking a unit in a round marks it exhausted for the rest of the cycle. That's what shrinks the choices 3 → 2 → 1. HOLD UP! clears all exhaustion.

---

## 3. Power and abilities

Every card carries **one number**, which is both its power and its ability priority.

| Tier | Possible numbers |
|---|---|
| I | 0, 1, 2 |
| II | 1, 2, 3 |
| III | 2, 3, 4 |
| IV | 3, 4, 5 |

- **Higher number wins** a duel.
- **Lower number resolves its ability first** (priority).
- Attack and defense are currently the *same* number. `PlayerData` keeps `base_power_left` (attack) and `base_power_right` (defense) as separate fields, and all combat code goes through `get_attack_power()` / `get_defense_power()`, so a future class with 4 attack / 2 defense needs only a CSV change.
- On an **ability priority tie**, the **attacker resolves first**.

**Element / class / race are targeting tags, not a matchup triangle.** They exist so card text can say *"give all Fire players +1 power"* or *"all Brandteufel gain +1 when defending"*. `PlayerData.get_tags()` returns the lowercase tag set for a card.

**Buff duration scopes (4):**

| Scope | Lasts |
|---|---|
| `DUEL` | this one tier duel |
| `ROUND` | the whole PLAY MAKER |
| `CYCLE` | until the next HOLD UP! |
| `MATCH` | rest of the game |

---

## 4. Combat — a PLAY MAKER round

```
"PLAY MAKER!" announced
   ↓
Rock / paper / scissors mini-game (single throw, ties re-throw)
   → winner chooses ATTACK or DEFEND for the Tier I duel
   ↓
Draft: Tier I → Tier II → Tier III → Tier IV
   (your Star's tier is skipped — it's already filled)
   ↓
Four duels resolve in tier order, I → II → III → IV.
Your Star fights in its own tier's slot.
   ↓
Each duel: camera zooms in (Advance Wars style)
   1. Abilities go on the stack, lowest number first (attacker wins ties)
   2. Abilities resolve — immediate or stacked
   3. Attack power vs defense power compared
   4. Camera zooms back out
   ↓
The WINNER of each duel is the ATTACKER in the next tier's duel.
Lose a duel and possession flips to the enemy.
   ↓
After Tier IV: whoever holds the ball takes a shot on the OPPOSING goalie.
```

### Shot power

For **every duel you won**, bank **your unit's power + the defeated enemy unit's power** (plus buffs).
Duels you lost bank nothing.

> Example: you win Tier II (your 3 vs their 2) and Tier IV (your 5 vs their 4).
> Shot power = (3 + 2) + (5 + 4) = **14**.

Because possession can flip mid-round, **the enemy can score on your goalie during your own PLAY MAKER.**

---

## 5. Goalies

Stamina is a **wall**, not a health bar.

1. Shot arrives while stamina **> 0** → subtract shot power from stamina. The shot scores only on a small fixed chance (`break_through_chance`, default **5%**).
2. Shot arrives while stamina **= 0** → the goal is open. Scores on `open_goal_chance`, default **90%** — the keeper can still get lucky.
3. **On conceding, that goalie's stamina resets to max.** Only the goalie who conceded. If your keeper is emptied and the enemy scores, *your* keeper refills; the enemy keeper keeps whatever stamina it had.

So the pattern is: grind a keeper to 0 across several rounds, then convert.

---

## 6. Data model

### `PlayerData` (`res://data/players/normal/` and `/star_player/`)

| Field | Purpose |
|---|---|
| `unit_type` | class / race — also a targeting tag |
| `player_name` | display name |
| `attack_text` / `defend_text` | ability text (display-only for now) |
| `element` | targeting tag |
| `base_power_left` | **attack power** (the 0–5 number) |
| `base_power_right` | **defense power** (mirrors left for now) |
| `tier` | "I" / "II" / "III" / "IV" |
| `player_type` | "Normal" or "Star" |
| `formation_scene` | Star Players only — the pitch layout |
| `stufe`, `tool`, `card_*`, `created_by` | card metadata (**purpose TBC**) |
| `artwork` | 12 × 39 spritesheet |

### `GoalieData` (`res://data/goalies/<team>_goalie.tres`)
`team`, `goalie_name`, `max_stamina`, `ability_text`, `artwork`.

### Formation scenes (`res://src/formations/<unit_type>_formation.tscn`)

```
Formation (Node2D)
├── StarSlot
│   └── Marker2D
└── RegularSlots
    ├── TierI    → 3 × Marker2D   ┐ only the THREE tiers
    ├── TierII   → 3 × Marker2D   ├ that are NOT the
    └── TierIV   → 3 × Marker2D   ┘ Star's own tier
```

Positions are authored for the **home** side; the enemy side is mirrored across the pitch centre at runtime. The formation node is freed once coordinates are read.

Pitch also needs `HomeGoaliePos` and `AwayGoaliePos` Marker2D nodes.

---

## 7. Code map

| File | Role |
|---|---|
| `player_data.gd` | Card resource + power/tier/tag helpers |
| `goalie_data.gd` | Goalie resource |
| `player_unit.gd` | A card on the pitch — display, highlight, roaming |
| `goalie_unit.gd` | Stamina wall + probabilistic shot resolution |
| `player_card_ui.gd` | Draft card — hover/select signals |
| `main_scene.gd` | Match clock, event schedule, drafting, spawning, round resolution |
| `csv_importer.gd` | `@tool` EditorScript — CSV → `.tres` |
| `rps_clash.tscn` | **not built yet** — rock/paper/scissors screen |
| `combat_arena.tscn` | **not built yet** — Advance Wars duel + shot |

### Signals exposed by `main_scene.gd`

```gdscript
signal round_ready_for_combat(player_lineup: Array, enemy_lineup: Array)
signal round_resolved(player_score: int, enemy_score: int)
signal match_ended(player_score: int, enemy_score: int)
```

`headless_combat` (exported bool) resolves rounds instantly in code so the full
90-minute loop is playable today. Turn it **off** once `combat_arena.tscn` exists;
the arena then listens to `round_ready_for_combat` and calls
`main_scene.finish_round(shooter_is_player, shot_power)` when the duels are done.

---

## 8. Open questions

1. **Which CSV column holds the 0–5 number?** Currently assumed `base_power_left`. `stufe` and `tool` are unassigned — what are they for?
2. **Duel power ties.** Two units with the same number meet. Attacker breaks through, or defender holds? Currently exported as `ties_go_to_attacker` (default: defender holds).
3. **Ability text → mechanics.** Keyword parser reading `attack_text`, or new structured columns (`ability_id`, `trigger`, `value`)?
4. Does the RPS winner ever *want* to defend, or is attacking always correct? If defending is never chosen, the choice is decorative.
5. Draw / extra time / penalties at 90:00?
6. Does the enemy AI draft intelligently, or stay random?

---

## 9. Bugs fixed in the 2026-09-06 pass

- **Duplicated enemy AI block** in `_on_card_selected` — it picked a random enemy twice; the second pass re-picked from a stale list and undid the first pass's exhaustion and highlighting.
- **Star swap broke the sprite** — `update_display()` drove the artwork as a 12 × 39 spritesheet while `update_unit_data()` replaced it with a 128 × 64 `AtlasTexture`, so a HOLD UP! star rotation left the sprite showing a sliver. Both now go through one path.
- **`spawn_goalies()` was never called**, and crashed on a missing marker. Now called from `_ready()` with a pitch-bounds fallback.
- **Star identified by `"star_player" in resource_path`** — replaced with an explicit `is_star_player` flag set at spawn.
- **Kickoff offered 3 random Stars** from the whole pool, so you could be shown three cards from the same class. Now one Star from each of three different classes.
- **`get_node_or_null("StarSlot").get_child(0)`** crashed when the node was missing. Guarded, with a clear error naming the offending Star.
- **Event timing** used a rolling `randf_range(7.6, 8.3)` that could push the 11th event past 90:00. Replaced with an up-front schedule spread from minute 5 to 82 with jitter.
- **Regular unit selection** took the first N cards in directory order. Now shuffled.
- **`next_playmaker_time`** was declared and never used. Removed.
- **The Star's own tier** could be filled with regular units if the formation scene had a node for it. Now skipped with a warning naming the scene.
- Enemy team is now chosen *after* your kickoff pick, so it's never a mirror match, and the enemy rotates its own Star at each HOLD UP!.
