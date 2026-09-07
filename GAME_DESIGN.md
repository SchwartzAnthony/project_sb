# Godot Autobattler — Design Spec

**Status:** living document. Re-upload this at the start of any new AI chat so nothing has to be re-explained.
**Last updated:** 2026-09-07

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

### Stamina tuning (measured, not guessed)

Simulated matches using the real card data give a shot power of
**min 6, max 22, mean 14.1, median 14** across 45 shots.

| `max_stamina` | Goals per match (both sides) | Feel |
|---|---|---|
| 10–12 *(current CSV)* | ~3.7 | **Broken.** Every shot empties the keeper in one hit, so it collapses into "shot 1 breaks, shot 2 scores." Five test matches all ended 2–2. |
| **25–30** | **~2.7** | **Recommended.** Takes 2 shots to break the wall. Scorelines came out 1–1, 2–1, 1–2. |
| 40 | ~3.0 | Wall holds ~3 rounds. |
| 55 | ~1.7 | Very defensive; some 0–1 and 2–0 matches. |

Rule of thumb: **`max_stamina` ≈ 2× mean shot power.** Update the
`Max Stamina` column in `Goalies.csv` from 10/12 to roughly **25/30** and
re-run the importer.

---

## 6. Data model

### `PlayerData` (`res://data/players/normal/` and `/star_player/`)

| Field | Purpose |
|---|---|
| `unit_type` | class / race — also a targeting tag |
| `player_name` | display name |
| `attack_text` / `defend_text` | ability text (display-only for now) |
| `element` | targeting tag |
| `base_power_left` | **attack power** — confirmed, this is where the 0–5 number lives |
| `base_power_right` | **defense power** (mirrors left in all current cards) |
| `tier` | "I" / "II" / "III" / "IV" |
| `player_type` | "Normal" or "Star" |
| `formation_scene` | Star Players only — the pitch layout |
| `card_set` | "F01". **Cannot** be called `set_name` — `Resource` already has a `set_name()` method (the setter for `resource_name`), and a member of that name shadows it. `PlayerData._set()` intercepts the old `set_name` key so the existing 24 `.tres` files still load. |
| `stufe`, `tool` | currently the literal strings `"Level"` and `"Wand"` on **every** card — placeholder columns, no mechanical use |
| `element` | also `"Wand"` on every card — the targeting tag is not populated with real values yet |
| `artwork` | 12 × 39 spritesheet |

> ⚠️ Godot omits a property from a `.tres` when it equals the type default,
> so a card with a real power of **0** (legal at Tier I) writes no
> `base_power_left` line at all. Never treat "missing" as "unset" and fall
> back to another column — read the value directly.

### Verified roster (as of the current CSVs)

| Class | Star tier | Regulars |
|---|---|---|
| **Brandteufel** | III (Heatwave 2, Fireline 4, Coalblaze 3) | Tier I, II, IV × 3 each ✓ |
| **Lorelei** | IV (Twilight 3, Golden River 4, Heart-Luring Wave 5) | Tier I, II, III × 3 each ✓ |

Both classes obey the "all three Stars share one tier" rule and both have
exactly 9 regulars in the three non-Star tiers. The data is correct.

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

1. ~~Which CSV column holds the 0–5 number?~~ **Answered:** `base_power_left`. `stufe` and `tool` are placeholder strings on every card.
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

---

## 10. Bugs fixed in the second pass (verified against the real project in Godot 4.7)

- **`goalie_unit.tscn` root node was `Node2D` while `goalie_unit.gd` declares `extends Area2D`.** `GOALIE_SCENE.instantiate()` therefore returned `null`, producing
  `Script inherits from native type 'Area2D', so it can't be assigned to an object of type 'Node2D'`
  followed by `Invalid assignment of property or key 'is_enemy' … on a base object of type 'Nil'`.
  Both goalies ended up null, so **all 9 shots a match silently did nothing and no goal could ever be scored.**
  This bug was always present — the old `main_scene.gd` never called `spawn_goalies()`, so nothing triggered it. The scene has a `CollisionShape2D` child, which confirms the root was always meant to be an `Area2D`.
- **`StaminaBar` is a `TextureProgressBar`, typed in code as `ProgressBar`.** Those are siblings, not parent/child — both extend `Range`. Now typed as `Range`, so either node type works.
- **Phantom shots.** `round_player_picks` was only cleared when a PLAY MAKER started, so each HOLD UP! draft re-resolved the *previous* round's duels and fired an extra shot — **11 shots per match instead of 9**. Now gated behind an explicit `round_in_progress` flag.
- **`card_set` vs `set_name`.** All 24 `.tres` files store `set_name`; the field was declared as `card_set`. Godot silently drops unknown properties, so the value was being lost on every load.
- **`get_defense_power()` fallback removed** — see the warning in §6.

---

## 11. Bugs fixed in the third pass (the 11 editor errors)

| Error | Cause | Fix |
|---|---|---|
| `"set_name" is shadowing an already-declared method in the base class "Resource"` | `Resource::set_name()` is the setter for `resource_name`. A member of the same name shadows the engine's own method. | Field renamed to `card_set`; `PlayerData._set()` intercepts the legacy `set_name` key so old `.tres` files still load. |
| `Formation for 'X' is missing StarSlot with a Marker2D child` (×2) | Both formation scenes have `RegularSlots` but no `StarSlot`. The Star was never spawned. | Formation scenes are now **optional**. `build_layout()` reads whatever the scene provides and `default_layout()` fills the gaps from the pitch rect. |
| `Could not find a star unit on the pitch to swap` (×4) | Downstream of the above — HOLD UP! had no Star on the pitch to rotate. | Fixed by the Star now spawning. |
| `No goalie resource at res://data/goalies/…` (×2) | `Goalies.csv` was never imported. | Ship `brandteufel_goalie.tres` / `lorelei_goalie.tres`, or wire `import_goalies()` into `csv_importer.gd::_run()`. |
| `No HomeGoaliePos / AwayGoaliePos markers found` | Markers are genuinely optional; the pitch-bounds fallback is correct behaviour. | Demoted from `push_warning` to `print`. |
| `Only 2 distinct classes have Star Players` | Only 2 classes are imported. Correct behaviour. | Demoted to `print`. |

### Formation scenes are now optional

`default_layout()` builds a 3-3-3 grid from `get_pitch_rect()`, with tier
columns at 16% / 25% / 34% / 43% of pitch width and rows at 28% / 50% / 72%
of height. The Star takes the centre row of its own tier's column. A
formation scene now only needs to supply the parts you want to hand-place —
anything absent (or a tier node with fewer than 3 markers) falls back to the
grid.

---

## 12. The ball (`ball.gd`)

Created in code by `main_scene.spawn_ball()` — there is no `ball.tscn`. It
draws itself and is **not** a physics body: possession is decided by distance
checks, which is cheap, deterministic and works under `--headless`.

```
carrier dribbles toward the opposing goal for 1.6–3.4 s
   ↓
passes to a team-mate — 75% of the time to one further upfield
   ↓
pass travels at 380 px/s
   ├─ an opponent within 45 px of the ball in flight  -> INTERCEPTED
   └─ otherwise the receiver collects it
   ↓
at any time, an opponent within 22 px of the CARRIER  -> TACKLED
```

| Knob | Default | What it does |
|---|---|---|
| `pass_speed` | 380 px/s | |
| `carry_seconds` | 1.6 – 3.4 s | how long before a carrier passes |
| `forward_pass_chance` | 0.75 | how often a pass looks upfield |
| `intercept_radius` | 45 px | corridor around a pass in flight |
| `intercept_grace` | 0.18 | fraction of the pass that cannot be picked off |
| `tackle_radius` | 22 px | how close to the carrier to win the ball |
| `possession_grace` | 0.7 s | new carrier is safe this long |
| `tackle_recovery` | 2.5 s | a tackled unit stops chasing this long |

`PlayerUnit` steering (per physics frame, priority order):

1. **I have the ball** → dribble at `dribble_speed` (44) toward the enemy goal
2. **Ball within `interest_radius`** (190 px) → run at it at `chase_speed` (66)
3. **Otherwise** → amble at `walk_speed` (30) within `roam_radius` of my slot

Everything is clamped to `get_play_rect()`, so nobody walks off screen.

### Three tuning dead-ends worth not repeating

Measured over 60-second samples with the match clock frozen:

| Attempt | Result |
|---|---|
| Interception only (no tackling), 44 px corridor | 23 steals / 60 s — possession flipped every 2.3 s |
| Interception only, 26–34 px corridor | **0** steals. The ball never left your own half, so no opponent ever came near it |
| Tackling with no recovery timer | 81 flips / 60 s — two units stood on the same spot trading the ball every 0.7 s |
| **Tackling + 2.5 s recovery + forward-biased passing** | **~19 flips / 60 s**, both sides get real possession |

The second row is the instructive one: an opponent was measured standing
**0 px from the ball** and could not take it, because interception only ever
applied to passes in flight. Tackling the carrier was the missing mechanic.

### Substitutions

`_swap_star_on_pitch()` is now an animation. `freeze_play(true)` stops every
unit and the ball (reference-counted, because both sides rotate their Star at
the same HOLD UP!), the outgoing Star runs off the nearer touchline, the card
is swapped while it is off screen, it runs back into the same slot, then
`freeze_play(false)`. If the outgoing Star was on the ball it drops it, and the
nearest unit collects it after 0.3 s.

### Kickoff

`get_star_player_choices()` now always returns **3** cards: one per class
first, then topped up from the classes you do have. With only Brandteufel and
Lorelei imported you get 3 cards across 2 classes; add a third class and it
becomes one per class automatically.

---

## 13. Bugs fixed in the fourth pass

- **`StarSlot` markers are grandchildren.** The real layout is
  `StarSlot/TierIII/Star_TierIII`, but the code did `star_slot.get_child(0) as Marker2D`,
  which returned the intermediate `TierIII` Node2D, cast to `null`. That — not a
  missing node — is why both Stars failed to spawn and why every HOLD UP! then
  reported "could not find a star unit to swap". Marker lookup is now recursive.
- **Formations were authored across the whole pitch** (x 358 → 1479 on a 1920
  wide screen), so once the enemy side was mirrored the two teams overlapped
  around the halfway line and half the units sat off screen. `_fit_layout_to_home_half()`
  keeps the shape you drew but remaps its bounding box into your own half of the
  visible area. Measured after the fix: home x 115–892, away x 1028–1805, zero
  units outside the play rect.
- **Enemy mirroring used the field texture's centre** (x = 980.5) rather than the
  centre of what is visible (x = 960), shifting the whole away team 20 px off.
  `get_pitch_center_x()` now returns the play rect's centre.
- **Formation scenes carry their own pitch sprites** (`Soccerfield`,
  `Soccerlineup`). They are instantiated to read marker positions, so they are
  now hidden before being added and freed immediately rather than via
  `queue_free()`, which let them render for a frame.

### Still missing from the repo (present locally, just never committed)

- `src/core/player_data.gd`, `src/core/goalie_data.gd`, `src/core/csv_importer.gd`
- `src/formations/brandteufel_formation.tscn`, `src/formations/lorelei_formation.tscn`
- `data/goalies/*.tres` — `Goalies.csv` has never been imported. Call `import_goalies()` from `csv_importer.gd`'s `_run()`.

### Test rig

The full match loop can be run headlessly with no display:

```
godot --headless --path <project> --script res://test_run.gd
```

where `test_run.gd` extends `SceneTree`, instantiates `main_scene.tscn`, raises
`time_scale`, and auto-clicks the first card whenever `card_container` has
children. A 90-minute match completes in about 25 seconds and prints every
duel, shot and goal — which is how the stamina table in §5 was measured.
