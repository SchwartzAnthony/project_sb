#!/usr/bin/env python3
"""Builds sturmball_designer.html (project root) from designer.html.

    python3 tools/designer_src/build.py

It pastes a copy of the game's CSVs into the page, so a plain double-click
opens it with today's data. "Load game data..." in the page reads newer CSVs.
Only the files the Designer uses are copied: the ones it edits, the ones it
lists from, and every file that tests an unlock (`unlocked:`).
"""
import glob, json, os, subprocess, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
ALWAYS = {"Achievements", "Upgrades", "Brews", "Items", "Stats", "Currencies",
          "Buildings", "BrewerySections", "BreweryResources", "ClassInfo", "Elements"}
SKIP = {"Dialogue", "Tuning", "Keywords", "Questions"}

files = {}
for path in sorted(glob.glob(os.path.join(ROOT, "data", "*.csv"))):
    name = os.path.basename(path)[:-4]
    text = open(path, encoding="utf-8").read()
    if name in ALWAYS or (name not in SKIP and "unlocked:" in text):
        files[name] = text

try:
    commit = subprocess.check_output(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], text=True).strip()
except Exception:
    commit = "?"
stamp = "%s (%s)" % (datetime.date.today().strftime("%d %b %Y"), commit)
data = json.dumps({"stamp": stamp, "files": files}, ensure_ascii=False).replace("</", "<\\/")

page = open(os.path.join(HERE, "designer.html"), encoding="utf-8").read()
start, end = page.index("/*GAME_DATA*/"), page.index("/*END_GAME_DATA*/")
page = page[:start] + "/*GAME_DATA*/" + data + page[end:]
out = os.path.join(ROOT, "sturmball_designer.html")
open(out, "w", encoding="utf-8").write(page)
print("wrote %s with %d CSV files (%d KB)" % (out, len(files), len(page) // 1024))
