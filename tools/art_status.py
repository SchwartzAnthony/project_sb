#!/usr/bin/env python3
# =============================================================
#  WHERE THE ART STANDS  (round AH - the art phases A1-A5)
#
#      python3 tools/art_status.py
#
#  Reads three lists and checks every file they name against assets/:
#
#      data/ArtOrders.csv     the PixelLab work orders, by Phase
#      the unit CSVs          every Artwork a card names (assets/players/)
#      data/ICONS_WANTED.csv  every icon the screens would use
#
#  and prints, per phase, what is DONE, what is MISSING, and the next order
#  to make. Writes the same to guides/ART_STATUS.md.
#
#  Nothing in the game reads this. A missing file is never an error - the
#  game draws a stand-in - it is just art that is not made yet.
# =============================================================

import csv
import glob
import os

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(path):
    with open(os.path.join(HERE, path), encoding="utf-8") as f:
        return list(csv.DictReader(f))


def exists(rel):
    return os.path.isfile(os.path.join(HERE, rel.strip()))


def main():
    lines = ["# Art status", "", "Made by `python3 tools/art_status.py` - run it again after adding art.", ""]
    orders = read("data/ArtOrders.csv")
    phases = {}
    for o in orders:
        phases.setdefault(o.get("Phase", "").strip() or "?", []).append(o)
    lines.append("## The work orders (data/ArtOrders.csv)")
    lines.append("")
    lines.append("| phase | order | what | status |")
    lines.append("|---|---|---|---|")
    first_open = None
    for ph in sorted(phases, key=lambda p: (p != "pass 1", p)):
        for o in phases[ph]:
            done = o.get("Status", "").upper().startswith("DONE")
            if not done and first_open is None:
                first_open = o
            lines.append("| %s | %s | %s | %s |" % (ph, o["Order"], o["ID"], "done" if done else "to make"))
    lines.append("")
    if first_open:
        lines.append("**Next to make:** order %s, `%s` (%s), phase %s -> `%s`" % (
            first_open["Order"], first_open["ID"], first_open["Tool"], first_open.get("Phase", ""), first_open["Goes To"]))
        lines.append("")

    # Unit art, from the cards themselves.
    wanted = {}
    for path in sorted(glob.glob(os.path.join(HERE, "data", "Unit_Set_*.csv"))) + [
            os.path.join(HERE, "data", n) for n in ("Star Players.csv", "BasicTeam.csv", "BasicEnemyTeam.csv")]:
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as f:
            for r in csv.DictReader(f):
                art = (r.get("Artwork") or "").strip()
                if art:
                    wanted.setdefault(art, os.path.basename(path))
    missing = sorted(a for a in wanted if not exists("assets/players/" + a))
    lines.append("## Unit art (phase A4): %d of %d files there" % (len(wanted) - len(missing), len(wanted)))
    lines.append("")
    for a in missing:
        lines.append("- missing `assets/players/%s` (named in %s)" % (a, wanted[a]))
    lines.append("")

    icons = read("data/ICONS_WANTED.csv")
    have = [i for i in icons if exists((i.get("Folder") or "") + (i.get("File") or ""))]
    lines.append("## Icons (phase A5): %d of %d there" % (len(have), len(icons)))
    lines.append("")
    for i in icons:
        if i not in have:
            lines.append("- `%s%s` - %s" % (i.get("Folder", ""), i.get("File", ""), (i.get("What it should show") or "").strip()))
    text = "\n".join(lines) + "\n"
    print(text)
    with open(os.path.join(HERE, "guides", "ART_STATUS.md"), "w", encoding="utf-8") as f:
        f.write(text)


if __name__ == "__main__":
    main()
