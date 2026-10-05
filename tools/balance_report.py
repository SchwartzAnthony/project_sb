#!/usr/bin/env python3
# =============================================================
#  THE BALANCE REPORT  (round AB - your answer Q059)
#
#      python3 tools/balance_report.py              5 matches per class
#      python3 tools/balance_report.py 20           20 per class
#      python3 tools/balance_report.py 10 Lorelei   only one class
#
#  Plays whole league matches with nobody watching (tools/match_soak.gd, AUTO
#  on, fast), several at once, each with a different seed, and counts what
#  happened in them from the Output log:
#
#      results         won / drawn / lost, goals for and against
#      Emblems         how often each one turned over, and how often BLOCKED
#      the engines     Rose tokens, Swans, Ore gained and spent, counters
#      bending         switches to defender, negates, forced sides
#      the referee     fouls, cards, coin flips, bar segments from abilities
#      free kicks      how many of each Range of data/FreeKicks.csv (round AG)
#      duels by tier   how many duels each class wins in Tier I, II, III, IV
#                      (round AG - a weak tier shows up here first)
#
#  Writes the table to the screen and to balance_report.md beside this file.
#  It takes a while: about 4 minutes per match, four at a time.
#  Needs Godot on the PATH as `godot` (or set GODOT=/path/to/godot).
# =============================================================

import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "godot")
CLASSES = ["Lorelei", "Rauhnacht-Feuergeister", "Bergmännlein", "Unkengeister"]
PARALLEL = int(os.environ.get("BALANCE_PARALLEL", "4"))
SPEED = os.environ.get("BALANCE_SPEED", "6")

COUNT = [
    ("rose tokens", r"place is taken by a Rose Unit"),
    ("roses home", r"the Rose Unit token goes"),
    ("swans", r"becomes a Swan"),
    ("ore gained", r": \+(\d+) Ore"),
    ("ore spent", r"pays (\d+) Ore"),
    ("burn counters", r"\+1 burn counter"),
    ("power counters", r"-1 power counter"),
    ("victory counters", r"victory for the side"),
    ("switches", r"switches to being the defender"),
    ("negates", r"is NEGATED"),
    ("forced", r"must use its"),
    ("keeper % shifts", r"to be beaten"),
    ("shields", r"shield on the"),
    ("bar segments", r"on the referee's bar"),
    ("coin flips", r"COIN FLIP for"),
    ("fouls", r"  FOUL: "),
    ("yellows", r"-> yellow"),
    ("reds", r"-> red"),
    ("free kicks: close", r"FREE KICK \(close\)"),
    ("free kicks: edge", r"FREE KICK \(edge\)"),
    ("free kicks: far", r"FREE KICK \(far\)"),
    ("SCRIPT ERRORS", r"SCRIPT ERROR"),
]
TIERS = ["I", "II", "III", "IV"]


def play(klass, seed):
    env = dict(os.environ, SOAK_CLASS=klass, SOAK_SEED=str(seed), SOAK_SPEED=SPEED)
    try:
        out = subprocess.run([GODOT, "--headless", "--path", HERE, "--script", "res://tools/match_soak.gd"],
                             env=env, capture_output=True, text=True, timeout=1500).stdout
    except subprocess.TimeoutExpired:
        out = ""
    return klass, seed, out


def read(klass, out):
    row = Counter()
    m = re.findall(r"FULL TIME — (\d+) : (\d+)", out)
    if not m:
        row["unfinished"] += 1
        return row
    us, them = map(int, m[-1])
    row["played"] += 1
    row["won" if us > them else ("lost" if us < them else "drawn")] += 1
    row["for"] += us
    row["against"] += them
    for name, pat in COUNT:
        hits = re.findall(pat, out)
        if hits and isinstance(hits[0], str) and hits[0].isdigit():
            row[name] += sum(int(h) for h in hits)
        else:
            row[name] += len(hits)
    # ROUND AG (P1): duels won per tier - the number that found the Rauhnacht
    # Tier IV problem, now counted for every class.
    for tier, who in re.findall(r"  DUEL (I|II|III|IV): (you|they) win", out):
        row["duels Tier %s" % tier] += 1
        if who == "you":
            row["won Tier %s" % tier] += 1
    for em in re.findall(r"\[emblems\] (.+?) ASCENDED", out):
        row["ascended: " + em] += 1
    for em in re.findall(r"\[emblems\] (.+?) turns over - BLOCKED", out):
        row["blocked: " + em] += 1
    return row


def main():
    per = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 5
    only = [a for a in sys.argv[1:] if not a.isdigit()]
    classes = only or CLASSES
    jobs = [(k, 1000 + i) for k in classes for i in range(per)]
    print("Playing %d matches (%d per class), %d at a time..." % (len(jobs), per, PARALLEL))
    totals = defaultdict(Counter)
    with ThreadPoolExecutor(PARALLEL) as pool:
        for klass, seed, out in pool.map(lambda j: play(*j), jobs):
            totals[klass].update(read(klass, out))
            print("   done: %s seed %d" % (klass, seed))
    lines = ["# Balance report", "", "%d matches per class, AUTO on both sides." % per, ""]
    keys = ["played", "won", "drawn", "lost", "for", "against"] + [n for n, _ in COUNT]
    lines.append("| | " + " | ".join(classes) + " |")
    lines.append("|---|" + "---|" * len(classes))
    for k in keys:
        lines.append("| %s | %s |" % (k, " | ".join(str(totals[c][k]) for c in classes)))
    for t in TIERS:
        cells = []
        for c in classes:
            n = totals[c]["duels Tier %s" % t]
            w = totals[c]["won Tier %s" % t]
            cells.append("%d of %d (%d%%)" % (w, n, round(100 * w / n)) if n else "-")
        lines.append("| duels won, Tier %s | %s |" % (t, " | ".join(cells)))
    extra = sorted({k for c in classes for k in totals[c] if k.startswith(("ascended", "blocked", "unfinished"))})
    for k in extra:
        lines.append("| %s | %s |" % (k, " | ".join(str(totals[c][k]) for c in classes)))
    text = "\n".join(lines) + "\n"
    print(text)
    with open(os.path.join(HERE, "tools", "balance_report.md"), "w", encoding="utf-8") as f:
        f.write(text)


if __name__ == "__main__":
    main()
