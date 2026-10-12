#!/usr/bin/env python3
"""Builds the Sturmball System Builder.

  python3 tools/kit_src/build.py            -> sturmball_kit.html (double-click, in project_sb)
  python3 tools/kit_src/build.py --link OUT -> OUT, the same page without <html>/<head>,
                                               for publishing as the online link

The page carries a copy of the CSVs below, taken from data/ when you build.
"""
import json, os, sys, hashlib, glob

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHEETS = ["Achievements", "Progression", "Buildings", "Upgrades", "Shop", "Brews", "Items",
          "BreweryResources", "BrewerySections", "Currencies", "MatchModes", "Biomes",
          "AdventureEnemies", "Drops"]

def build(link_out=None):
    src = {}
    for s in SHEETS:
        with open(os.path.join(ROOT, "data", s + ".csv"), encoding="utf-8") as f:
            src[s] = f.read()
    body = open(os.path.join(ROOT, "tools", "kit_src", "kit.html"), encoding="utf-8").read()
    data = json.dumps(src, ensure_ascii=False).replace("</", "<\\/")
    stamp = hashlib.sha1(data.encode()).hexdigest()[:10]
    count = len(glob.glob(os.path.join(ROOT, "data", "*.csv")))
    body = (body.replace("/*__DATA__*/{}", data).replace("/*__STAMP__*/", stamp)
                .replace("/*__COUNT__*/132", str(count)))
    if link_out:
        open(link_out, "w", encoding="utf-8").write(body)
        print("wrote", link_out)
        return
    page = ('<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
            '</head><body>\n' + body + '\n</body></html>\n')
    out = os.path.join(ROOT, "sturmball_kit.html")
    open(out, "w", encoding="utf-8").write(page)
    print("wrote", out)

if __name__ == "__main__":
    build(sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == "--link" else None)
