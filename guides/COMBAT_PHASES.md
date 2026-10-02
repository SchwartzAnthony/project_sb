# Combat abilities — the plan (round Y)

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
| `data/AbilityRulings.csv` | **21 questions, each asked once.** Fill in `Your Ruling`. Until you do, the engine uses `My Reading` |

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
│   │   │   │               while_in_exile         (C5)
│   │   │   ├─ the stack .. **on_attack** / **on_defend**
│   │   │   │               lowest PRIORITY first, attacker first on a tie
│   │   │   ├─ compare .... attack vs defence
│   │   │   └─ outcome .... **on_win_duel** / **on_lose_duel**
│   │   │                   after_duel             (C1) "after Tier IV combat"
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

## 2. Where cards can be — the five zones

| zone | who is there | today |
|---|---|---|
| **Bench** ("the void"?) | the 18 cards in your collection that are not in this match | exists, unnamed |
| **Field** | the 12 who took the pitch and are still to play this cycle | exists |
| **Combat** | the 4 drafted this round, until the round ends | exists |
| **Exhaust** | cards already used this cycle. They return to the field at the end of the cycle | exists as a flag (`is_exhausted`) |
| **Exile** | cards removed by a rule (a Rose token replacing a unit, a swan going to exile). They come back only when a rule says so | **does not exist** (C5) |

C1 turns the first four into a proper **zone book**: every card on both sides
always has exactly one zone, and moving between zones *fires* (enter
exhaust, leave exhaust). Exile comes with C5.

---

## 3. What the audit found

**276 ability texts**: 216 on the 108 set cards, 24 on the 12 Stars, 36 on the
12 Emblems.

| | works today | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | systems | not written |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Bergmännlein | 0 | 8 | 18 | 9 | 8 | 0 | 14 | 3 | 0 | 6 | 3 |
| Lorelei | 0 | 5 | 21 | 3 | 17 | 11 | 0 | 3 | 3 | 6 | 0 |
| Rauhnacht-Feuergeister | 7 | 11 | 26 | 0 | 2 | 0 | 10 | 3 | 0 | 9 | 0 |
| Unkengeister | 0 | 1 | 0 | 6 | 6 | 6 | 36 | 3 | 0 | 6 | 3 |
| **total** | **7** | **25** | **65** | **18** | **33** | **17** | **60** | **12** | **3** | **27** | **6** |

A row sits in the **highest** phase any of its words needs. "Systems" are
Emblem Basic Sides and Star Ultimates. Each is a small rule-set of its own (a
mine in every zone, Rose tokens replacing units) and is built whole in C7 or
C8. "Not written" means the six Ultimates you haven't written yet.

**Running total of abilities that work:** 7 before C1 → **32** after C1 (done
in this round — plus Karl's ore card, 33) → **97** after C2 → 115 → 148 → 165
→ **225** after C6 → all of them after C8.

### The four rulings that decide everything else

These are in `AbilityRulings.csv` as F1–F4. They aren't about any one
sentence; they're about how a card with two abilities behaves at all.

- **F1. One side per duel.** A card attacking uses its Attack ability, a card
  defending uses its Defend ability. (Today the engine fires both, which is
  wrong for your cards: "Enemy has to use Attack Ability" only makes sense if
  a card normally uses one.)
- **F2. Outside a duel** (exhaust, exile, end of cycle): the side it played
  last.
- **F3. Reveal** happens before anyone knows who attacks: two SHOW buttons?
- **F4. Priority:** keep "power = priority, lowest first"?

Then 17 more about wording (R01–R17): which keeper "goalie" means, what
"next" means, where Ore lives, what "the void" is, and so on. **36 cards hang
on R03 ("next") and 35 on R12 (Ore)**, so those two answers move the most.

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

### C2 — Counters, tokens and Ore · +65 → 97

Counters on a card (`burn`, `power`, `song`, `victory`), the side's **Ore
pool** (`gain_ore`, `Cost: ore:3`, "if collected Ore this round"), tokens (a
Rose or Swan unit standing in for a card), and creature types (a unit that
*is a swan*). **Needs R12** (where Ore lives).

### C3 — The keeper and the referee · +18 → 115

`goalie_chance` (± % on a keeper), `goalie_shield`, `remove_shields`,
`foul_heat` (+1 on the yellow-card bar), `foul_chance`, the coin-flip foul.
**Needs R01, R02, R09, R10, R11.**

### C4 — Bending the duel · +33 → 148

`switch_to_defender`, `always_defending`, `swap_power`, `use_enemy_power`,
`force_ability` (attack / defend / other), `negate_ability`, `negate_buff`,
`change_priority`, `give_priority`, `uncounterable`, `double_attack`,
`power_from_count`. **Needs F1, F4, R15.**

### C5 — Zones in action · +17 → 165

The **Exile** zone. `while_in_exile`, `send_to_exile`, swapping from exile
or the bench, "send a different Tier IV to the exhaust and return this to
the stack", revealing from the exhaust, copying from the exhaust (Vassago).
**Needs F2, R07, R14, R17.**

### C6 — The class engines · +60 → 225

The things on the pitch: **mines and mining** (Bergmännlein), **fusing**
(Feuergeister), **touching the ball, cold touch, gravestones** (Unkengeister).
These are the ones that need the match to *watch the pitch* rather than the
cards. **Needs R08, R13.**

### C7 — The Emblems' Basic Sides · 12 systems + 12 conditions

Each Basic Side built as a whole: Rose tokens, the swan transformation, Song
counters, victory counters, the fire buffs, mines and craters and the rock
keeper, the air rules. And every `Turns On` counter fed by a **real** event
instead of a placeholder, so the emblem bar finally moves.

### C8 — The Stars · 12 Front Sides + 15 Ultimates

The Front Sides mostly ride on C1–C6 words. The Ultimates are systems like
the Emblems. **Six Ultimates still need writing.**

---

## What I need from you

1. **`data/AbilityRulings.csv`**: the four F rulings first, then R03 and R12
   (they decide 71 cards between them). Everything else can wait for its
   phase.
2. **The six unwritten Ultimates** (Bergmännlein and Unkengeister) and
   **Vassago's Token**, before C7/C8.
3. Nothing else for C1–C3. They can be built on the default readings and
   changed by a ruling later; the rulings sheet says what each default is.
