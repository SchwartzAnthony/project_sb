# Combat abilities — the plan (round Y · C2 Z · C3 AA · C4 AB)

> *"We need to go through each of the unique players and see if their
> triggers work when they should (during attack/defend or in void, on the
> field etc.) and are applied based on the priority that they have during
> combat... lay the ground work for the back system for these to function."*

This is that plan. It has four parts:

1. **When things can happen**: the timing chart of a round.
2. **Where cards can be**: the five zones.
3. **What we found**: the audit of all 276 ability texts.
4. **The phases**: C1 to C8, what each builds and how many cards it brings to life.

Two spreadsheets go with it:

| file | what it is |
|---|---|
| `data/AbilityAudit.csv` | **every ability text in the game**, one row each, broken into When / If / Cost / Do / Target / Value / Scope / Max, with the phase that makes it work |
| `data/AbilityRulings.csv` | **22 questions, each asked once.** You answered the first 21 in round Z; R18 is new. Until a question is answered, the engine uses `My Reading` |

`python3 tools/ability_audit.py` rebuilds both from your card files and
**keeps every ruling you've written**. Run it whenever you change a card's
text.

`godot --headless --script res://tools/ability_coverage.gd` is the meter: how
many abilities of each class **actually do something in a match**, today. It
should go up every round.

---

## 1. When things can happen — the timing chart

Every ability fires at one of these moments. The **bold** ones exist in the
engine today; the others arrive in C1.

```
MATCH START ............... match_start            (C1)
│
├─ CYCLE (x3)
│   │
│   ├─ ROUND (x3 per cycle)
│   │   │
│   │   ├─ PLAY MAKER!
│   │   ├─ DRAFT  ......... **reveal** (you press SHOW)
│   │   │                    picked card: field -> combat
│   │   ├─ ROUND START .... **passive**            every card in this round's line-up
│   │   │
│   │   ├─ DUEL, Tier I -> II -> III -> IV
│   │   │   ├─ duel start . **on_duel_start**, **flip**
│   │   │   │               while_in_exhaust       (C1) cards already used this cycle
│   │   │   │               "next" effects land    (C1) on the card that waited for them
│   │   │   ├─ the stack .. **on_attack** / **on_defend**
│   │   │   │               lowest PRIORITY first, attacker first on a tie
│   │   │   ├─ compare .... attack vs defence
│   │   │   └─ outcome .... **on_win_duel** / **on_lose_duel**
│   │   │                   after_duel             (C1)
│   │   │   (any time) .... on_counter             (C2) a card receives a counter
│   │   │
│   │   ├─ AFTER COMBAT ... after_combat           (C2) every card, any zone - "after Tier IV combat"
│   │   │
│   │   ├─ FOULS .......... the referee            (Fouls.csv, Referee.csv)
│   │   ├─ THE SHOT ....... on_shot                (C1) "shooting at goal"
│   │   │                   goalie_save            (C1) "goalie successfully defends"
│   │   │                   on_goal / on_concede   (C1) "after a goal"
│   │   └─ ROUND END ...... round_end              (C1)
│   │                       the four who played: combat -> exhaust
│   │                       on_enter_exhaust       (C1) "if sent to exhaust"
│   │
│   ├─ END OF CYCLE ....... end_of_cycle           (C1) "at the end of the cycle"
│   │                       exhaust -> field
│   │                       on_leave_exhaust       (C1)
│   └─ STAR PLAYER SWITCH
│
FULL TIME
```

### The stack, the rule that decides order

Inside one duel both cards' abilities go on a **stack**, and the stack
resolves **lowest ability priority first**. A card's priority is its power,
so a 0 goes before a 3. The attacker goes first on a tie. A card played face
up (SHOW) uses its power as its priority. This is already built (ruling F4
asks whether to keep it).

---

## 2. Where cards can be — the zones

| zone | who is there | today |
|---|---|---|
| **Bench** ("outside the game") | cards not in this match. Ruling R08: **at most 3**, and you choose which | C6 (fusing) |
| **Field** | the 12 who took the pitch and are still to play this cycle | built (C1) |
| **Combat** | the 4 drafted this round, until the round ends | built (C1) |
| **Exhaust** | cards already used this cycle. They return to the field at the end of the cycle | built (C1) |

**There is no Exile zone.** Ruling R14: *"Exile = Exhaust, Exile was the old
name."* Every card text that said exile now says exhaust (round Z). **"The
void"** (ruling R07) is the exhaust if the card says so, otherwise that
card's own tier zone - the cards of its tier not played yet.

One card is **held** in the exhaust: a card a Rose Unit token replaced. It
stays there while its token plays, and does not come back at the end of the
cycle (round Z).

---

## 3. What the audit found

**276 ability texts**: 216 on the 108 set cards, 24 on the 12 Stars, 36 on the
12 Emblems.

Round Z re-read the cards with your rulings (Exile = Exhaust moved most of
the old C5 rows into C1/C2):

| | works today | C1 ✅ | C2 ✅ | C3 | C4 | C5 | C6 | C7 | C8 | systems | not written |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Bergmännlein | 0 | 8 | 18 | 9 | 8 | 0 | 14 | 3 | 0 | 6 | 3 |
| Lorelei | 0 | 10 | 22 | 4 | 19 | 2 | 0 | 3 | 3 | 6 | 0 |
| Rauhnacht-Feuergeister | 7 | 11 | 26 | 0 | 2 | 1 | 10 | 3 | 0 | 9 | 0 |
| Unkengeister | 0 | 1 | 0 | 6 | 6 | 8 | 36 | 3 | 0 | 6 | 3 |
| **total** | **7** | **30** | **66** | **19** | **35** | **11** | **60** | **12** | **3** | **27** | **6** |

A row sits in the **highest** phase any of its words needs. "Systems" are
Emblem Basic Sides and Star Ultimates. Each is a small rule-set of its own (a
mine in every zone, Rose tokens replacing units) and is built whole in C7 or
C8. "Not written" means the six Ultimates you haven't written yet.

**Running total of class abilities that work in a match** (the meter,
`ability_coverage.gd`, counts the 228 Attack/Defend sides of the set cards and
Stars' Front Sides): 1 before C1 → 33 after C1 → 103 after C2 (round Z) →
122 after C3 (round AA) → 156 after C4 (round AB) → 168 after C5 (round
AC) → **228 after C6 (round AD, 100%)**. C7 and C8
are the Emblems and Ultimates on top.

### Your rulings (answered in round Z) and what they changed

| | your ruling, short | built as |
|---|---|---|
| **F1** | the attacker uses its Attack side, the defender its Defend side, unless a card says otherwise; "switch to defender" = it now uses its Defend side | built in C1; the switch is C4 |
| **F2** | Exile = Exhaust; outside a duel the **player chooses one side**, never both | today: the side it played last. The choice is a screen - planned for C5 (see the questions) |
| **F3** | the enemy may Reveal in the same tier; the next tier waits for both; after picking a Reveal card you are **asked** whether to reveal it; a **window tracks the pending buffs** | the **match tracker** is built (round Z). The ask-after-pick flow is C5 |
| **F4** | keep it; "-1 priority" moves priority, not power; show a **priority bubble** when it differs from power, and a **+/- bubble** for combat power | built: the duel window shows `3 (+1)` and "priority 2" (round Z) |
| R01 | both keepers possible; most are the enemy's | "goalie" = the enemy's, unless "your goalie" |
| R02 | change the %, not stamina | C3 |
| R03 | "next" = **the next unit played** (Tier III → Tier IV); old cards meant "-1 priority" | new target `next_tier_ally` (round Z); Lennart's text now says "-1 priority" |
| R04 | while in combat and burning, +1 power | built (C2) |
| R05 / R06 | Max = per match; once per cycle = per card | built |
| R07 | the void = the exhaust (if it says so) or its unplayed tier zone | C5 |
| R08 | outside the game = the bench, **max 3, the player picks them** | C6 |
| R09 | one tier segment of the yellow bar | C3 |
| R10 | a real %, start at 5% | Konstantin's text says 5% now; C3 |
| R11 | a shield is a separate bar that goes before stamina | C3 |
| R12 | one Ore pool per side; mines by emblem and other means, on the side of the field; any mine (even in the exhaust) +1 ore; Tobias's mine "one per game" | **the pool is built (C2)**; Tobias says (Max 1); mines are C6 |
| R13 | before the PLAY MAKER | C6 |
| R14 | **Exile = Exhaust** | every card text changed; no exile zone |
| R15 | yes | C4 |
| R16 | just +5% foul for the match, once per game | Nils's text rewritten; C3 |
| R17 | during combat the exhaust zone **lights up** when a card in it can act; before the duel you may swap; only interrupt when someone has a choice | C5 (it is a screen) |
| **R18** | your answer was about **Sven**: if you control a token, choose one of the same tier and use its power, and show it on screen | Sven is C4. The Gerhard half is asked again as Q001 in `data/Questions.csv` |

**Round AA answers** (your notes on the round Z READ ME):

| | you said | built |
|---|---|---|
| Swans count as tokens | yes | `swans_count_as_tokens` stays on |
| Rose tokens last | until a goal | a goal - either side's - sends every Rose home (`rose_tokens_end_on_goal`) |
| who picks the Rose | the player | a window lists the units it can replace |
| spending Ore | ask the player | asked before the duel (`ask_before_spending_ore`) |
| Zepar's Swan | the player may say no | asked after the reveal (the `Ask` column = yes) |
| power vs priority | two numbers; show priority when power moved | the card strip and the duel window show "priority N" |
| burn | the set names were swapped in your file | Buer's set burns, Belphegor's set makes power counters |
| F2 side choice | once per cycle | asked when a card goes to the exhaust, if both its sides work out there |
| Gremory's pace | maybe too slow; must be usable once | **measured: it turns over at the very end of its cycle - see Questions Q013** |
| emblems | only the Star on the pitch brings its Emblem; once one turns over the others are locked | `emblem_follows_star`, `emblem_locked_is_inactive` |

**From now on every open question is in `data/Questions.csv`** (59 to start),
not ten at a time in the READ ME. `python3 tools/questions.py` counts them.

---

## 4. The phases

Each phase is one round of work, built the same way as everything else: the
words go into `Keywords.csv` / `AbilityTriggers.csv` as `live`, a tool
measures them, and the cards that only needed those words start working with
no edit to the card.

### C1 — The foundation · 33 abilities working · ✅ BUILT IN ROUND Y

The moments, the conditions and "the next one":

- **The zone book**: field, combat, exhaust, with enter/leave events.
- **New moments**: `end_of_cycle`, `round_end`, `after_duel`,
  `while_in_exhaust`, `on_enter_exhaust`, `on_leave_exhaust`, `on_shot`,
  `goalie_save`, `on_goal`, `on_concede`, `match_start`.
- **An `If` column** in Abilities.csv: `defending`, `attacking`,
  `last_ally_won`, `last_ally_lost`, `enemy_not_element:air`,
  `own_goalie_lower`, `in_exhaust`, `has_tag:swan`… A condition whose word
  isn't built yet is simply false, and the Output panel says so once.
- **New targets**: `next_ally`, `next_ally:fire`, `next_enemy`,
  `ally_tier:IV`. A "next" waits until that card duels.
- **`Max`** takes `1/cycle`, `2/cycle` and `1/game` as well as a number.
- **One side per duel** (ruling F1), behind `ability_uses_role_side`.
- **`tools/ability_coverage.gd`**, the meter: 33 of 228 class abilities
  (14%) work in a match today, up from 1.
- **`tools/ability_check.gd`**, the proof: stages each wired card's moment on
  a fresh engine and checks the effect landed where its sentence says, and
  that an Attack ability stays silent when the card defends. 40 of 40.
- **`tools/ability_rows.py`** turns every audited reading whose words are
  built into a real row in `data/CardAbilities.csv`, and puts its ID on the
  card. Each later phase adds itself to that script's list and runs it again.

### C2 — Counters, tokens and Ore · 103 working · ✅ BUILT IN ROUND Z

- **Counters on cards**, for the whole match, whatever zone: `add_counter:burn`,
  `remove_counter`, and the **power counter** (`add_counter:power` -1: Fritz's
  "-1 power counter" makes him 1 weaker in every later duel). A card receiving
  one fires the new moment **`on_counter`**. If words: `has_counter[:kind]`,
  `enemy_has_counter[:kind]`.
- **The Ore pool, one per side** (ruling R12): `gain_ore`, and a new **Cost**
  column - `ore:3` is paid *before* the ability fires; not enough Ore and it
  does not happen at all (not counted, not spent against its Max). If words:
  `ore_this_round`, `ore_at_least:n`.
- **Tokens**: `create_token:rose`. A Rose Unit token is a copy of the card it
  replaces (same tier, same power, no text); the card is **held** in the
  exhaust while the token plays - where its "While in exhaust" side works.
  The body on the pitch changes card; at full time every original comes back.
  If words: `has_token`, `tokens_at_least:n`, `is_token`.
- **Swans**, a creature type: `make_swan`; `is_swan`; `next_ally:swan` finds
  them. While `swans_count_as_tokens` is on, a Swan counts as a token.
- **`next_tier_ally`** (ruling R03): the very next card played. **`side`**
  and **`replace:<filter>`** targets. **Max** takes `1/round` and `/side`.
- **`after_combat`**: once a round, after the Tier IV duel, for every card in
  any zone (Carl: "while in exhaust ... after Tier IV combat"). "While in
  exhaust ... at the end of a cycle" now reads as **once**, at the end of the
  cycle - not at every duel.
- **Five Emblems' Basic sides play** (pulled forward from C7, because the
  Sitri and Zepar cards are dead without them). A new **Basic Ability** column
  in the Emblems files names `EMB_` rows in Abilities.csv:
  - **Gremory** - two water units into the exhaust in a round: a Rose token
    replaces a water Tier I.
  - **Zepar** - a revealed water unit becomes a Swan; a Swan is +1 in combat.
    The draft card gets a SHOW button for it.
  - **Sallos** - a water unit that defends and wins puts a Song on the enemy.
  - **Belphegor** - a fire win is a victory counter, two per cycle per side.
  - **Buer** - a fire unit receiving a counter is +1 in its combat, once a cycle.
  Their Conditions now fill from **real events** in Stats.csv (`token_made`,
  `swan_made`, `counter_placed`, `ore_gained`, `ore_spent`) instead of the old
  "every duel won" placeholder.
- **On screen**: the **match tracker** (Ore, tokens, victory counters, every
  "next" still waiting - ruling F3), a strip on each draft card (`burn 1
  power -1 SWAN`), and the duel window's `(+1)` and priority bubbles (F4).
- **Measured**: `ability_coverage` 103 of 228 (45%); `ability_check` stages
  125 abilities and the five Emblem stories - ALL GOOD; three match soaks
  (Bergmännlein, Lorelei, Rauhnacht) with no trouble - the Lorelei one made
  three Rose tokens and turned Gremory over.

### C3 — The keeper and the referee · 122 working · ✅ BUILT IN ROUND AA

All five rulings it needed are in (R01, R02, R09, R10, R11, and R16):

- **`goalie_chance`**: ± % on a keeper's save chance for the round - the %,
  never the stamina (R02). Erich, Dominik, Harald, Michael, Hannah, Frank,
  Kurt, Konstantin, Silke, Kerstin ("to 0% this turn").
- **The shield** (R11): a second bar on the keeper that empties before
  stamina. `goalie_shield` (Rudolf), `remove_shields` (Monika).
- **`foul_heat`**: one tier segment of the enemy's yellow-card bar (R09) -
  Thomas, Carsten, Jan.
- **`foul_chance`**: +n% for the enemy to commit a foul - Konstantin (5%, the
  round, R10), Nils (5%, the match, once per game, R16).
- **The coin flip** (Manfred's Defend): "if you cause a foul, flip a coin to
  see if the enemy gets it instead".
- On screen: the keeper's label shows `(+5%)` and `shield 2`; the shot
  window says "+5% from abilities"; the referee bar takes the segment.
- A "for the round" keeper shift lasts **until the next shot**, and a "for
  the round" foul shift **until the next fouls** - so a card that fires after
  them (a save, the exhaust) still counts.

**Also built in round AA, alongside C3:**

- **The question window** (`src/ui/choice_window.gd`): Ore (before the duel),
  Zepar's Swan, the Rose pick, which side stays up (F2). Only for your side,
  never in AUTO.
- **The duel window** shows the ability that really went off, a dim "(not
  this time)" when its If was not met, and the If in words ("... if you
  control a token").
- **The clutter**: the emblem tile moved to the top right, and the emblem bar
  and tracker sit UNDER the duel and shot windows.

### C4 — Bending the duel · 156 working · ✅ BUILT IN ROUND AB

`switch_to_defender`, `always_defending`, `swap_power`, `use_enemy_power`,
`force_ability` (attack / defend / other), `negate_ability`, `negate_buff`,
`change_priority`, `give_priority`, `uncounterable`, `double_attack`,
`power_from_count`, and **Sven** (Q002: the enemy fights with the power of a
token you own - you pick it, Q003, and the duel window shows it, Q004).

Built as you answered: the abilities go off **then** the card switches to
defender (Q047) and the winner attacks next; a negate stops the side the
enemy is using - one that switched sides dodged it (Q050); Lothar's double
is printed power, buffs after (Q051, C5); swaps use printed power (Q052);
"cannot be countered" stops negate and force (Q053); priority changes stack
(Q045). **The stack re-sorts as it goes**, so a priority change that lands
before a card resolves moves it. And from the exhaust, "a Tier IV water
unit" now WAITS for that card (it used to expire at the Tier I duel).

### C5 — Zones in action, and the choices · 168 working · ✅ BUILT IN ROUND AC

- **The ask-after-pick Reveal (F3, Q043, Q044):** pick, then "Reveal it?";
  both sides blind; both reveals shown together, lower power first.
- **The exhaust lights up (R17):** before a duel, a card in the exhaust with
  an `exhaust_swap` / `swap_in_tier` row can swap in for the card about to
  duel - you are asked, the AI always swaps. Once per cycle. The card it
  replaces goes to the exhaust. Ralf, Peter, Franz (`swapped_was:air`).
- **Zone moves:** `send_to_exhaust`, `swap_from_exhaust` (Lothar's token,
  after its doubled duel), `exhaust_other_return` (Jan, Silke: you pick which
  other Tier IV goes), `reveal_another` (Ingrid: your next pick is revealed),
  `reveal_from_exhaust` (Flauros, `revealed_was:fire`), `double_attack`
  (printed power doubled, max 5, buffs after - Q051). Jakob's Swan token.
- **F2 (which side counts outside a duel)** was already a choice since round
  AA (one window per round, Q037).
- Still for later: the void (R07, Marie - "if this touched the ball", C6) and
  copying from the exhaust (Vassago's Emblem, C7).

### C6 — The class engines · 228 working · ✅ BUILT IN ROUND AD

- **Touches (R13):** every unit that had the ball in open play since the last
  PLAY MAKER (TOUCHED on its card). `touched_ball`, `touched_before_playmaker`.
- **Cold touch:** the ball turns icy until the next PLAY MAKER; counted.
- **Gravestones:** on the pitch for the match (Q058); counted.
- **Mines (Q091, Q055):** data/Mines.csv, four per side at its touchline;
  earth units near one are MINING; +1 Ore per worked mine per PLAY MAKER;
  Tobias's `mine`; Belial's `weapon`.
- **Fusing (R08, Q056):** a bench of 3 you choose; `fuse:fire+iii`; higher
  power, both abilities, FUSED.
- **The void (R07):** `swap_from_void` mid-duel; Nicole's swap from the
  exhaust mid-duel.

### C7 — The Emblems' Basic Sides · 7 systems left · NEXT

Five were built early in C2 (Gremory, Zepar, Sallos, Belphegor, Buer). Left:
Flauros (fused units - after C6), the Bergmännlein mines, crater and rock
keeper (after C6), and the three Unkengeister rules. Plus the Turns On
counters still on the placeholder (`rauhnacht_units_active` and the
Bergmännlein / Unkengeister ones).

### C8 — The Stars · 12 Front Sides + 15 Ultimates

The Front Sides mostly ride on C1–C6 words. The Ultimates are systems like
the Emblems. **Six Ultimates still need writing.**

---

## What I need from you

1. **`data/Questions.csv`** - 59 questions, each with the default that is
   already playing. Q009 (the Emblem lock) and Q013 (Gremory's pace) matter
   most.
3. **The six unwritten Ultimates** (Bergmännlein and Unkengeister) and
   **Vassago's Token**, before C7/C8.
