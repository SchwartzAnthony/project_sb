# Balance review: round AI

These are the conclusions I drew as lead systems and combat designer from
1,000 simulated matches. The raw numbers are in `data/combat_telemetry.json`,
and the tables are in `guides/BALANCE_ANALYSIS.md`.

## How to read the simulation first

Sturmball has **no hit points, attack speed or "DPS"**. A duel is one power
against another, the winner keeps or takes the ball, and the bank becomes a
shot at a keeper. So the simulation measures these instead:

| asked for | what Sturmball measures |
|---|---|
| unit DPS | **power per duel**, and the **duel win rate** |
| damage taken | **power faced per duel** |
| damage to the enemy | **keeper stamina taken** by your shots, and goals |
| match duration (ticks) | **duels a match** (always 36: 9 rounds × 4 tiers) |
| ability trigger frequency | **abilities fired**, per card and per ability |

**The simulation does not see the pitch.** It leaves out:

- touches on the ball;
- mines and Ore from mining;
- gravestones knocked over;
- fouls and free kicks;
- the Emblem race, so there are no Ultimates.

Because of that it **under-rates**:

- **Bergmännlein**: its Ore comes from mines;
- **Haures**: his front side spends Ore;
- the **Unkengeister cards that need a touch**.

42 cards never fired an ability in the simulation for this reason. For the
whole game, `tools/balance_report.py` plays the real match, slowly.

## What is fine

- **Four classes are within a few points of each other.** Each class's score
  is wins plus half the draws, divided by matches. With both sides picking at
  random, the scores run 41%–57%.
- **Every class beats the Basic Team 70%–98% of the time.** That gap is the
  reward for building a class.
- **Goals average 3 a match** in the simulation; the real game is about 2.5.
  A match feels busy without every round being a goal.
- **Nothing scales multiplicatively.**
  - Every power change is added.
  - The keeper's chance comes from one table (ShotOdds.csv), clamped to
    0–100%.
  - Shields only stop shots.

## The one mechanical flaw: switching to defender, plus the tie rule

**What happens:**

- Ties go to the **defender** (`ties_go_to_attacker` is false).
- "Switch to being the defender" (the Sallos set) turns the attacker into the
  defender after both cards' abilities have fired.
- So **the switcher wins every tie**. It also gets to use its own defend side
  as well as its attack side.

**At the top of a tier, that is almost unbeatable:**

| card | his duels won | other cards of the same tier and power |
|---|---|---|
| **Kurt** (Lorelei, IV, P5) | 97% | 65% |
| **Thomas** (Lorelei, I, P2) | 96% | 66% |

**Lower down a tier, switching only gives a tie that wasn't coming anyway.**
Monika (IV, P3) wins 11%.

**I tried a fix.** `switch_loses_ties` true means a card that switched must
win outright. It fixed Kurt and Thomas, but the rest of the Sallos set fell
behind its peers (−16 to −18 points), and Lorelei dropped from 48% to 41%. So
**I left it off**.

**The better fix is a card change. That's yours to make (Q131):**

- a) "Switch to being the defender **if this is not the stronger card**";
- b) the switcher **does not also fire its defend side**;
- c) Kurt and Thomas move down a power in their tier.

## Other cards worth a look

These are measured against cards of the same tier and power.

| card | lift | why | my suggestion |
|---|---|---|---|
| Niklas (Rauhnacht, I, P2) | −25 | "If this wins: −1 power counter" lasts the **match**, so every win makes him weaker for good | make the counter last the **cycle** |
| Haures (Star, III, P4) | −24 | his front side spends Ore on the keeper; no Ore in the simulation | check in the real game (mines) before changing |
| Caim (Star, II, P3) | −21 | his front side buffs the **next two allies**, not himself | fine: the help shows in the Unkengeister Tier III numbers (65%) |
| Tim (Rauhnacht, II, P3) | +19 | −1 on the next enemy **and** +1 on the next fire ally | fine for a Tier II; watch it |
| Unkengeister Tier IV | +20 to +26 | `tier_power_unkengeister_IV` 1 (round AH), as intended | real-match check: 6 wins / 5 draws / 5 losses in 16 |

## Changed this round

**No card was changed.** One new dial, `switch_loses_ties`, is **off**, so
the game plays exactly as before. Every finding above is a question for you
(Q131–Q133). To try a change:

1. Edit the card or dial.
2. Run `tests/sim_runner.gd`.
3. Run `tools/balance_analysis.py`.
4. Compare.
