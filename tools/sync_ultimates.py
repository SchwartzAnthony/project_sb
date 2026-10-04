#!/usr/bin/env python3
# =============================================================
#  ONE PLACE FOR AN ULTIMATE  (round AF, your Q101)
#
#      python3 tools/sync_ultimates.py
#
#  "The ultimates are actually the Star Players' second side." So the text
#  you write is the ULTIMATE SIDE column of data/Star Players.csv, and only
#  there. This copies it onto the matching Emblem's Ultimate Side column (the
#  Emblem whose Star column names that Star), so the Emblem tile and the
#  Star card always say the same thing.
#
#  Run it after you change an Ultimate. The game itself also reads the
#  Star's text first (EmblemBook), so forgetting to run this only leaves the
#  Emblem file's copy out of date - nothing breaks.
# =============================================================

import csv
import glob
import io
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(HERE, "data")


def main():
    stars = {}
    with open(os.path.join(DATA, "Star Players.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            stars[r["Name"].strip()] = (r.get("Ultimate Side") or "").strip()
    changed = 0
    for path in sorted(glob.glob(os.path.join(DATA, "* Emblems.csv"))):
        with open(path, encoding="utf-8") as f:
            rows = list(csv.reader(f))
        head = rows[0]
        si, ui = head.index("Star"), head.index("Ultimate Side")
        ai = head.index("For AI notes") if "For AI notes" in head else -1
        touched = False
        for r in rows[1:]:
            want = stars.get(r[si].strip(), "")
            if want and r[ui].strip() != want:
                r[ui] = want
                touched = True
                changed += 1
            if ai >= 0 and "PROPOSED BY CLAUDE" in r[ai]:
                r[ai] = r[ai].split(" ULTIMATE SIDE PROPOSED BY CLAUDE")[0].strip()
                touched = True
        if touched:
            out = io.StringIO()
            csv.writer(out, lineterminator="\n").writerows(rows)
            with open(path, "w", encoding="utf-8") as f:
                f.write(out.getvalue())
    print("%d Emblem Ultimate Side(s) copied from Star Players.csv." % changed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
