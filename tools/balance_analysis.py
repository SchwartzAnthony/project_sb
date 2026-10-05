#!/usr/bin/env python3
# =============================================================
#  THE BALANCE ANALYST  (round AI)
#
#      godot --headless --path . --script res://tests/sim_runner.gd
#      python3 tools/balance_analysis.py
#
#  Reads data/combat_telemetry.json (made by tests/sim_runner.gd) and writes
#  guides/BALANCE_ANALYSIS.md: what is out of line, and by how much.
#
#  ============ HOW IT JUDGES ============
#
#  CLASSES. Score = (wins + half the draws) / matches, from the matchup row
#  where both sides pick at random ("random classes") - the fairest row.
#  Outside 45%-55% is flagged.
#
#  CARDS. A card's duel win rate mostly follows its printed power - a Tier IV
#  P5 SHOULD beat a Tier IV P3. So a card is compared with every other card
#  of the SAME tier and SAME printed power ("its peers"). The gap is its
#  LIFT: +20 points means its abilities win it 20% more duels than an
#  ordinary card of that power. Beyond +/-15 points is flagged.
#
#  Cards with fewer than MIN_DUELS duels are left out (not enough evidence).
# =============================================================

import json
import os
from collections import defaultdict

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IN = os.path.join(HERE, "data", "combat_telemetry.json")
OUT = os.path.join(HERE, "guides", "BALANCE_ANALYSIS.md")

FAIR_ROW = "random classes"
CLASS_BAND = (0.45, 0.55)
LIFT_FLAG = 0.15
MIN_DUELS = 150
SKIP_CLASSES = {"Normal", "Rivals"}


def pct(x):
    return "%d%%" % round(100 * x)


def main():
    d = json.load(open(IN, encoding="utf-8"))
    out = ["# Balance analysis", "",
           "Made by `python3 tools/balance_analysis.py` from `data/combat_telemetry.json` "
           "(%d simulated matches, seed %s). Re-run both after changing a card or a dial." % (d["matches"], d["seed"]),
           "", "_%s_" % d["about"], "",
           "Goals a match: **%s**. Duels a match: %s." % (d["match"]["goals_per_match"], d["match"]["ticks_per_match"]), ""]

    # ---- classes ----
    out += ["## Classes", "", "Score = (wins + half the draws) / matches. Fair band 45%-55%.", ""]
    rows = d.get("classes_by_matchup", {})
    out.append("| class | " + " | ".join(rows.keys()) + " |")
    out.append("|---|" + "---|" * len(rows))
    flags = []
    names = sorted({k for t in rows.values() for k in t if k not in SKIP_CLASSES})
    for klass in names:
        cells = []
        for row_name, table in rows.items():
            c = table.get(klass)
            if not c:
                cells.append("-")
                continue
            score = (c["won"] + 0.5 * c["drawn"]) / max(1, c["played"])
            mark = ""
            if row_name == FAIR_ROW and not (CLASS_BAND[0] <= score <= CLASS_BAND[1]):
                mark = " **!**"
                flags.append("%s scores %s in '%s'" % (klass, pct(score), FAIR_ROW))
            cells.append("%s (%d)%s" % (pct(score), c["played"], mark))
        out.append("| %s | %s |" % (klass, " | ".join(cells)))
    out.append("")
    out += ["Duels won by tier (all rows):", "", "| class | I | II | III | IV |", "|---|---|---|---|---|"]
    for klass, c in sorted(d["classes"].items()):
        if klass in SKIP_CLASSES:
            continue
        t = c["duels_by_tier"]
        out.append("| %s | %s |" % (klass, " | ".join(pct(t.get(x, {}).get("win_rate", 0)) for x in ["I", "II", "III", "IV"])))
    out.append("")

    # ---- cards: lift over peers ----
    peers = defaultdict(lambda: [0, 0])
    for c in d["cards"]:
        if c["class"] in SKIP_CLASSES:
            continue
        k = (c["tier"], c["printed_power"])
        peers[k][0] += c["duels_won"]
        peers[k][1] += c["duels"]
    lifts = []
    for c in d["cards"]:
        if c["class"] in SKIP_CLASSES or c["duels"] < MIN_DUELS:
            continue
        k = (c["tier"], c["printed_power"])
        won, total = peers[k]
        others = (won - c["duels_won"]) / max(1, total - c["duels"])
        lifts.append((c["duel_win_rate"] - others, others, c))
    lifts.sort(key=lambda x: -x[0])
    out += ["## Cards against their peers (same tier, same printed power)", "",
            "Lift = this card's duel win rate minus its peers'. Flag beyond +/-%d points." % round(LIFT_FLAG * 100), "",
            "| card | class | tier | P | duels | wins | peers | lift | abilities a duel |", "|---|---|---|---|---|---|---|---|---|"]
    for lift, others, c in lifts:
        if abs(lift) < LIFT_FLAG:
            continue
        out.append("| %s%s | %s | %s | %d | %d | %s | %s | **%+d** | %.2f |" % (
            c["name"], " (Star)" if c["star"] else "", c["class"], c["tier"], c["printed_power"], c["duels"],
            pct(c["duel_win_rate"]), pct(others), round(lift * 100), c["abilities_per_duel"]))
        flags.append("%s (%s, Tier %s P%d) lift %+d" % (c["name"], c["class"], c["tier"], c["printed_power"], round(lift * 100)))
    out.append("")

    # ---- abilities that never fire ----
    fired = {a["ability"] for a in d["abilities"]}
    out += ["## Abilities", "", "Most fired (per match):", ""]
    for a in d["abilities"][:10]:
        out.append("- `%s` %.2f" % (a["ability"], a["per_match"]))
    out.append("")
    quiet = [c for c in d["cards"] if c["class"] not in SKIP_CLASSES and c["duels"] >= MIN_DUELS and c["abilities_per_duel"] == 0]
    out.append("%d card(s) with %d+ duels never fired an ability in the simulation (many of these need the pitch - "
               "touches, mines, gravestones - which the simulation does not have):" % (len(quiet), MIN_DUELS))
    out.append("")
    out.append(", ".join("%s (%s %s)" % (c["name"], c["class"][:4], c["tier"]) for c in quiet))
    out.append("")

    out += ["## Flags", ""] + ["- " + f for f in flags] + [""]
    text = "\n".join(out) + "\n"
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print(text)


if __name__ == "__main__":
    main()
