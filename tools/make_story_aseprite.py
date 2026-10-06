#!/usr/bin/env python3
# =============================================================
#  THE CONVERSATION PICTURES AS LAYERED ASEPRITE FILES  (round AN)
#
#      ~/.venvs/sturmball/bin/python tools/make_story_aseprite.py
#
#  Reads data/StoryArt.csv and writes, in art_source/aseprite/story/:
#    <id>.aseprite   one per background ID, one layer per row (first row at
#                    the bottom), e.g. bar.aseprite = room + regulars
#    cast.aseprite   every portrait, one layer each (switch layers on and
#                    off in Aseprite to see one face at a time)
#  After editing, export a layer back to the PNG its row names.
# =============================================================
import csv
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_aseprite import HERE, project_path, write_aseprite  # noqa: E402

OUT = os.path.join(HERE, "art_source", "aseprite", "story")


def main():
    rows = list(csv.DictReader(open(os.path.join(HERE, "data", "StoryArt.csv"), encoding="utf-8")))
    rooms, cast = {}, []
    for row in rows:
        path = project_path((row.get("Image") or "").strip())
        if not os.path.isfile(path):
            print("  ! no picture at %s - skipped" % row.get("Image"))
            continue
        im = Image.open(path).convert("RGBA")
        if (row.get("Kind") or "").strip().lower() == "background":
            rooms.setdefault(row["ID"].strip(), []).append(im)
        else:
            name = " ".join(x for x in (row["ID"].strip(), (row.get("Mood") or "").strip(), (row.get("View") or "").strip()) if x)
            cast.append((name, im))
    for room, images in rooms.items():
        w = max(im.width for im in images)
        h = max(im.height for im in images)
        layers = [("%02d %s" % (i + 1, room), im, 0, 0) for i, im in enumerate(images)]
        target = os.path.join(OUT, room + ".aseprite")
        write_aseprite(target, w, h, layers)
        print("  wrote %s: %dx%d, %d layers" % (target, w, h, len(layers)))
    if cast:
        w = max(im.width for _n, im in cast)
        h = max(im.height for _n, im in cast)
        target = os.path.join(OUT, "cast.aseprite")
        write_aseprite(target, w, h, [(name, im, 0, 0) for name, im in cast])
        print("  wrote %s: %dx%d, %d layers" % (target, w, h, len(cast)))


if __name__ == "__main__":
    main()
