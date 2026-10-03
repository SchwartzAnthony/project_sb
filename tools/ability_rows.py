#!/usr/bin/env python3
# =============================================================
#  FROM YOUR CARD TEXT TO ABILITIES THE MATCH RUNS  (round Y)
#
#      python3 tools/ability_audit.py      (read the card texts)
#      python3 tools/ability_rows.py       (then this)
#
#  For every row of data/AbilityAudit.csv whose words the engine ALREADY
#  understands, this writes the Abilities rows into data/CardAbilities.csv
#  and puts their IDs into the card's Attack Ability / Defend Ability cell.
#  That is the moment a card stops being words on a card and starts doing
#  something in a match.
#
#  WHICH ROWS: those whose Status is `works today`, or whose Phase is one
#  the engine has finished (BUILT_PHASES below - C1 in round Y). Every later
#  round adds its phase to that list and runs this again, and the next batch
#  of cards comes to life.
#
#  WHAT IT NEVER TOUCHES
#    - Abilities.csv. Your own rows stay yours; these live in their own file.
#    - An ability cell YOU wrote. Generated IDs start with C_ (C_Vitus_D);
#      a cell holding anything else - Karl's BERG_ORE_WHISPER - is left alone.
#
#  A SENTENCE WITH TWO HALVES ("+1 power now. If this wins: ...") becomes
#  two rows, C_Name_A1 and C_Name_A2, and the cell names both: C_Name_A1;C_Name_A2.
#
#  YOUR RULINGS WIN. If AbilityRulings.csv changes a reading, re-run both
#  scripts. Nothing here is precious - CardAbilities.csv is rebuilt from
#  scratch every time.
# =============================================================

import csv
import glob
import io
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(HERE, "data")
AUDIT = os.path.join(DATA, "AbilityAudit.csv")
OUT = os.path.join(DATA, "CardAbilities.csv")

## The phases the engine has finished. Each round adds the phase it built
## (C1 in round Y, C2 in round Z, C3 in round AA, C4 in round AB).
BUILT_PHASES = ["C1", "C2", "C3", "C4"]

COLUMNS = ["Ability ID", "Name", "Trigger", "Target", "Effect", "Value", "Scope", "Max", "If", "Cost", "Ask", "Notes"]
SIDE_CODE = {"Attack": "A", "Defend": "D", "Star Front Side": "F"}


def usable(row):
    status = (row.get("Status") or "").split(" - ")[0].strip()
    if status == "works today":
        return True
    return status in BUILT_PHASES


def rows_for(audit):
    """One audit row -> (cell_ids, ability_rows)."""
    code = SIDE_CODE.get(audit["Side"])
    if code is None or not audit["Do"]:
        return [], []
    dos = [d.strip() for d in audit["Do"].split("|")]
    targets = [t.strip().rstrip("?") for t in audit["Target"].split("|")]
    values = [v.strip() for v in audit["Value"].split("|")]
    scopes = [s.strip() for s in audit["Scope"].split("|")]
    # ROUND Z: a sentence with two halves has a moment (and an If, and a
    # Cost) PER HALF - "+1 now | if this wins: -1 power counter".
    whens = [w.strip() for w in audit["When"].split("|")]
    ifs = [w.strip() for w in audit["If"].split("|")]
    costs = [w.strip() for w in audit["Cost"].split("|")]

    def nth(items, i):
        return items[i] if len(items) > 1 and i < len(items) else items[0]
    ids, out = [], []
    for i, do in enumerate(dos):
        ability_id = "C_%s_%s%s" % (audit["Card"].replace(" ", "_"), code, (i + 1) if len(dos) > 1 else "")
        scope = scopes[i] if i < len(scopes) else "duel"
        if scope in ("now", ""):
            scope = "duel"
        out.append({
            "Ability ID": ability_id,
            "Name": "%s (%s)" % (audit["Card"], audit["Side"]),
            "Trigger": nth(whens, i),
            "Target": targets[i] if i < len(targets) else "self",
            "Effect": do,
            "Value": values[i] if i < len(values) else "1",
            "Scope": scope,
            "Max": audit["Max"],
            "If": nth(ifs, i),
            "Cost": nth(costs, i),
            # Round AA: "you CAN ..." on a card asks you first.
            "Ask": "yes" if " can " in (" " + audit["Text"].lower() + " ") and "can be fused" not in audit["Text"].lower() and "cannot" not in audit["Text"].lower() else "",
            "Notes": "MADE FROM THE CARD TEXT by tools/ability_rows.py - do not edit here; change the card (or a ruling) and re-run. Text: " + audit["Text"],
        })
        ids.append(ability_id)
    return ids, out


def main():
    if not os.path.exists(AUDIT):
        print("No data/AbilityAudit.csv - run python3 tools/ability_audit.py first.")
        return 1
    with open(AUDIT, encoding="utf-8") as f:
        audit_rows = list(csv.DictReader(f))

    made = []
    cells = {}           # (card, side) -> "C_x;C_y"
    for a in audit_rows:
        if not usable(a):
            continue
        ids, rows = rows_for(a)
        if ids:
            made.extend(rows)
            cells[(a["Card"], a["Side"])] = ";".join(ids)

    out = io.StringIO()
    w = csv.DictWriter(out, fieldnames=COLUMNS, lineterminator="\n")
    w.writeheader()
    w.writerows(made)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(out.getvalue())
    imp = OUT + ".import"
    if not os.path.exists(imp):
        with open(imp, "w") as f:
            f.write('[remap]\n\nimporter="keep"\n')

    # ---- put the IDs on the cards ----
    def owned_by_us(cell):
        parts = [p.strip() for p in cell.split(";") if p.strip()]
        return all(p.startswith("C_") for p in parts)

    wired = 0
    left_alone = []
    files = sorted(glob.glob(os.path.join(DATA, "Unit_Set_*.csv"))) + [os.path.join(DATA, "Star Players.csv")]
    for path in files:
        with open(path, encoding="utf-8") as f:
            table = list(csv.reader(f))
        head = table[0]
        is_star = path.endswith("Star Players.csv")
        for col in ("Attack Ability", "Defend Ability"):
            if col not in head:
                head.append(col)
                for r in table[1:]:
                    r.append("")
        name_i = head.index("Name")
        for r in table[1:]:
            while len(r) < len(head):
                r.append("")
            card = r[name_i]
            for col, side in (("Attack Ability", "Star Front Side" if is_star else "Attack"),
                              ("Defend Ability", "Star Front Side" if is_star else "Defend")):
                i = head.index(col)
                want = cells.get((card, side), "")
                if not owned_by_us(r[i]):
                    if want:
                        left_alone.append("%s %s (it says %s)" % (card, col, r[i]))
                    continue
                if r[i] != want:
                    r[i] = want
                if want:
                    wired += 1
        o = io.StringIO()
        csv.writer(o, lineterminator="\n").writerows(table)
        with open(path, "w", encoding="utf-8") as f:
            f.write(o.getvalue())

    print("%d ability row(s) written to data/CardAbilities.csv." % len(made))
    print("%d card ability cell(s) now point at them." % wired)
    for note in left_alone:
        print("   left alone, because you wrote it yourself: %s" % note)
    return 0


if __name__ == "__main__":
    sys.exit(main())
