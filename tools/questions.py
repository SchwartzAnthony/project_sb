#!/usr/bin/env python3
# =============================================================
#  THE QUESTIONS FILE  (round AA)
#
#      python3 tools/questions.py
#
#  data/Questions.csv is where Claude asks you everything that is not a
#  question about one card's wording (those stay in AbilityRulings.csv).
#  As many questions as there are, not ten at a time - you asked for that.
#
#  HOW YOU USE IT
#    Open data/Questions.csv (the workbench edits it like any other file).
#    Write in `Your Answer`. A letter is enough ("a"), or words, or both.
#    Leave the ones you do not care about yet - `My Default` is what the game
#    already does, so a blank answer is never a broken game.
#
#  HOW CLAUDE USES IT
#    Every round starts by reading this file. An answered question becomes
#    `answered`, then `built` once the game does what you said. New questions
#    are added at the bottom with the round they came from; your answers are
#    never overwritten.
#
#  This script just counts, and lists what is answered but not built yet.
# =============================================================

import csv
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(HERE, "data", "Questions.csv")


def main():
    if not os.path.exists(PATH):
        print("No data/Questions.csv.")
        return 1
    with open(PATH, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    answered = [r for r in rows if (r.get("Your Answer") or "").strip()]
    by_area = Counter(r["Area"] for r in rows)
    open_area = Counter(r["Area"] for r in rows if not (r.get("Your Answer") or "").strip())
    print("%d questions, %d answered, %d still open." % (len(rows), len(answered), len(rows) - len(answered)))
    print("")
    for area in by_area:
        print("   %-14s %2d asked, %2d open" % (area, by_area[area], open_area.get(area, 0)))
    waiting = [r for r in answered if (r.get("Status") or "").strip().lower() != "built"]
    if waiting:
        print("")
        print("Answered, not built yet:")
        for r in waiting:
            print("   %s  %s" % (r["ID"], r["Question"][:90]))
            print("        -> %s" % r["Your Answer"].strip()[:120])
    return 0


if __name__ == "__main__":
    sys.exit(main())
