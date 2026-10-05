# Balance analysis

Made by `python3 tools/balance_analysis.py` from `data/combat_telemetry.json` (1000 simulated matches, seed 20261005). Re-run both after changing a card or a dial.

_Sturmball headless combat simulation (tests/sim_runner.gd). Engine-level: no pitch, no fouls, no Emblem race/Ultimates; questions answered with defaults. Power stands in for damage: there are no hit points._

Goals a match: **2.98**. Duels a match: 36.0.

## Classes

Score = (wins + half the draws) / matches. Fair band 45%-55%.

| class | Unkengeister strongest vs Lorelei random | best vs best | class vs Basic Team | random classes |
|---|---|---|---|---|
| Bergmännlein | - | 77% (95) | 96% (28) | 41% (314) **!** |
| Lorelei | 22% (100) | 61% (89) | 98% (27) | 48% (285) |
| Rauhnacht-Feuergeister | - | 25% (105) | 70% (23) | 54% (288) |
| Unkengeister | 78% (100) | 41% (111) | 95% (22) | 57% (313) **!** |

Duels won by tier (all rows):

| class | I | II | III | IV |
|---|---|---|---|---|
| Bergmännlein | 50% | 53% | 35% | 55% |
| Lorelei | 52% | 49% | 44% | 49% |
| Rauhnacht-Feuergeister | 49% | 64% | 60% | 44% |
| Unkengeister | 55% | 39% | 65% | 55% |

## Cards against their peers (same tier, same printed power)

Lift = this card's duel win rate minus its peers'. Flag beyond +/-15 points.

| card | class | tier | P | duels | wins | peers | lift | abilities a duel |
|---|---|---|---|---|---|---|---|---|
| Kurt | Lorelei | IV | 5 | 684 | 97% | 65% | **+32** | 1.50 |
| Thomas | Lorelei | I | 2 | 775 | 96% | 66% | **+30** | 1.47 |
| Sophie | Unkengeister | IV | 4 | 356 | 73% | 46% | **+26** | 0.00 |
| Greta | Unkengeister | III | 3 | 317 | 68% | 45% | **+23** | 0.00 |
| Patrick | Unkengeister | IV | 4 | 289 | 70% | 47% | **+23** | 0.03 |
| Konstantin | Unkengeister | IV | 4 | 277 | 67% | 47% | **+20** | 0.00 |
| Tim | Rauhnacht-Feuergeister | II | 3 | 659 | 84% | 65% | **+19** | 1.03 |
| Daniel | Unkengeister | III | 3 | 272 | 64% | 45% | **+19** | 0.00 |
| Walter | Bergmännlein | IV | 5 | 625 | 85% | 67% | **+19** | 0.99 |
| Fritz | Rauhnacht-Feuergeister | I | 0 | 357 | 33% | 15% | **+18** | 1.00 |
| Julian | Rauhnacht-Feuergeister | II | 2 | 268 | 61% | 45% | **+16** | 1.07 |
| Theresa | Unkengeister | III | 3 | 342 | 60% | 45% | **+15** | 0.00 |
| Kilian | Rauhnacht-Feuergeister | III | 2 | 288 | 35% | 20% | **+15** | 0.56 |
| Jakob | Lorelei | III | 3 | 373 | 32% | 48% | **-16** | 0.00 |
| Carl | Lorelei | III | 3 | 437 | 32% | 48% | **-16** | 0.37 |
| Edgar | Lorelei | III | 4 | 764 | 55% | 71% | **-17** | 0.00 |
| Ingrid | Lorelei | IV | 3 | 371 | 4% | 21% | **-17** | 0.00 |
| Caim (Star) | Unkengeister | II | 3 | 1638 | 51% | 72% | **-21** | 1.00 |
| Herbert | Lorelei | IV | 4 | 363 | 29% | 50% | **-22** | 0.00 |
| Haures (Star) | Bergmännlein | III | 4 | 1311 | 49% | 73% | **-24** | 0.39 |
| Niklas | Rauhnacht-Feuergeister | I | 2 | 673 | 45% | 70% | **-25** | 0.49 |

## Abilities

Most fired (per match):

- `C_Vassago_F` 1.64
- `C_Glasya-Labolas_F` 1.64
- `C_Caim_F` 1.64
- `C_Sallos_F2` 1.50
- `C_Sallos_F1` 1.50
- `C_Buer_F2` 1.23
- `C_Buer_F1` 1.23
- `C_Thomas_D` 0.77
- `C_Mario_D` 0.72
- `C_Kurt_D` 0.68

42 card(s) with 150+ duels never fired an ability in the simulation (many of these need the pitch - touches, mines, gravestones - which the simulation does not have):

Susanne (Unke III), Gertrud (Unke III), Rudolf (Berg IV), Hannah (Berg II), Sophie (Unke IV), Franz (Unke I), Greta (Unke III), Konstantin (Unke IV), David (Unke I), Daniel (Unke III), Alexander (Lore I), Gregor (Lore IV), Theresa (Unke III), Dennis (Lore III), Silke (Unke IV), Emma (Unke IV), Edgar (Lore III), Valentin (Unke I), Peter (Unke I), Zepar (Lore II), Ursula (Berg II), Veronika (Unke I), Günter (Berg IV), Flauros (Rauh IV), Gremory (Lore II), Bartholomäus (Lore I), Jakob (Lore III), Noah (Unke IV), Jan (Unke IV), Herbert (Lore IV), Belphegor (Rauh IV), Carsten (Unke III), Marie (Unke III), Sepp (Berg II), Ralf (Unke I), Frank (Berg IV), Finn (Unke I), Friedrich (Unke I), Gerhard (Lore III), Matthias (Lore I), Werner (Lore I), Ingrid (Lore IV)

## Flags

- Bergmännlein scores 41% in 'random classes'
- Unkengeister scores 57% in 'random classes'
- Kurt (Lorelei, Tier IV P5) lift +32
- Thomas (Lorelei, Tier I P2) lift +30
- Sophie (Unkengeister, Tier IV P4) lift +26
- Greta (Unkengeister, Tier III P3) lift +23
- Patrick (Unkengeister, Tier IV P4) lift +23
- Konstantin (Unkengeister, Tier IV P4) lift +20
- Tim (Rauhnacht-Feuergeister, Tier II P3) lift +19
- Daniel (Unkengeister, Tier III P3) lift +19
- Walter (Bergmännlein, Tier IV P5) lift +19
- Fritz (Rauhnacht-Feuergeister, Tier I P0) lift +18
- Julian (Rauhnacht-Feuergeister, Tier II P2) lift +16
- Theresa (Unkengeister, Tier III P3) lift +15
- Kilian (Rauhnacht-Feuergeister, Tier III P2) lift +15
- Jakob (Lorelei, Tier III P3) lift -16
- Carl (Lorelei, Tier III P3) lift -16
- Edgar (Lorelei, Tier III P4) lift -17
- Ingrid (Lorelei, Tier IV P3) lift -17
- Caim (Unkengeister, Tier II P3) lift -21
- Herbert (Lorelei, Tier IV P4) lift -22
- Haures (Bergmännlein, Tier III P4) lift -24
- Niklas (Rauhnacht-Feuergeister, Tier I P2) lift -25

