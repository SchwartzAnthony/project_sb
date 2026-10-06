#!/usr/bin/env python3
# =============================================================
#  THE VILLAGE ROUND THE PITCH  (round AN)
#
#      ~/.venvs/sturmball/bin/python tools/make_village.py
#
#  Reads data/VillageGround.csv - one row per PixelLab part (the meadow,
#  the houses, the farm, the beer tent, the clubhouse, the trees, the fans)
#  - and builds the two pictures data/Stadium.csv draws behind the grass:
#
#      assets/field/stadium_back.png    every row with Layer background
#      assets/field/stadium_crowd.png   every row with Layer crowd
#                                       (shown once Full House is unlocked)
#
#  and one layered Aseprite file with every part on its own layer:
#
#      art_source/aseprite/stadium.aseprite
#
#  Both pictures are the size of the pitch (2560 x 1440) and sit exactly
#  under it, so a part at X 436 lines up with the goal line. Move a part:
#  change its X / Y and run this again. New part: make it in PixelLab, save
#  it in art_source/pixellab/village/, add a row.
#
#  Scale is a whole number and is applied with no smoothing, so pixels stay
#  square: 2 for buildings and trees (the pitch's own pixel size), 1 for
#  people (the players' pixel size).
# =============================================================

import csv
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "tools"))
from make_aseprite import write_aseprite  # noqa: E402

SHEET = os.path.join(HERE, "data", "VillageGround.csv")
OUT = {
    "background": os.path.join(HERE, "assets", "field", "stadium_back.png"),
    "crowd": os.path.join(HERE, "assets", "field", "stadium_crowd.png"),
}
ASE = os.path.join(HERE, "art_source", "aseprite", "stadium.aseprite")
W, H = 2560, 1440


def no_magenta(img):
    """PixelLab sometimes leaves a line of its magenta key colour on the
    edge of a cut-out. Nothing in the village is that colour, so it goes."""
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a and r > 200 and g < 60 and b > 180:
                px[x, y] = (0, 0, 0, 0)
    return img


def part_image(row):
    img = no_magenta(Image.open(os.path.join(HERE, row["Image"].strip())).convert("RGBA"))
    scale = max(1, int(float(row.get("Scale") or 1)))
    if scale != 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    if "h" in (row.get("Flip") or "").lower():
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    return img


def main():
    with open(SHEET, encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f) if (r.get("Image") or "").strip()]
    sheets = {name: Image.new("RGBA", (W, H), (0, 0, 0, 0)) for name in OUT}
    layers = []
    for row in rows:
        group = (row.get("Layer") or "background").strip()
        if group not in sheets:
            print("skipped %s: Layer must be background or crowd" % row["Part"])
            continue
        img = part_image(row)
        x, y = int(float(row["X"] or 0)), int(float(row["Y"] or 0))
        sheets[group].alpha_composite(img, (max(0, x), max(0, y)),
                                      (max(0, -x), max(0, -y)))
        # Aseprite wants the part cropped to the canvas.
        box = (max(0, -x), max(0, -y), min(img.width, W - x), min(img.height, H - y))
        layers.append(("%s (%s)" % (row["Part"], group), img.crop(box), max(0, x), max(0, y)))
    for name, path in OUT.items():
        sheets[name].save(path)
        print("wrote %s" % os.path.relpath(path, HERE))
    pitch = os.path.join(HERE, "assets", "field", "soccerfield.png")
    if os.path.exists(pitch):
        layers.append(("pitch (soccerfield.png, made by make_pitch.py)",
                       Image.open(pitch).convert("RGBA").resize((W, H), Image.NEAREST), 0, 0))
    write_aseprite(ASE, W, H, layers)
    print("wrote %s (%d layers)" % (os.path.relpath(ASE, HERE), len(layers)))


if __name__ == "__main__":
    main()
