#!/usr/bin/env python3
# =============================================================
#  THE BASE TOWN MAP  (round AN)
#
#      ~/.venvs/sturmball/bin/python tools/make_base_town.py
#
#  Reads data/BaseTown.csv - one row per PixelLab part (the valley ground,
#  the pitch, clouds, boats, the maypole, trees) - and builds:
#
#      assets/base/background.png               the base screen's backdrop
#      art_source/aseprite/base_town.aseprite   every part on its own layer
#
#  The picture is the screen (1920 x 1080). A row's X and Y are its top-left
#  corner in screen pixels. Crop (x,y,width,height, in the part's own pixels)
#  cuts a piece out of a bigger picture; the piece keeps its place, so the
#  pitch cut from the ground lands exactly on the ground.
#
#  Every row is its own layer in the Aseprite file, so a part can be
#  repainted alone; this script then fuses them into the one picture.
#
#  Scale is a whole number with no smoothing, so pixels stay square.
#  New part: make it in PixelLab, save it in art_source/pixellab/base_town/,
#  add a row, run this again.
# =============================================================

import csv
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "tools"))
from make_aseprite import write_aseprite  # noqa: E402

SHEET = os.path.join(HERE, "data", "BaseTown.csv")
OUT = os.path.join(HERE, "assets", "base", "background.png")
ASE = os.path.join(HERE, "art_source", "aseprite", "base_town.aseprite")
W, H = 1920, 1080


def part_image(row):
    """The part at its final size, and where its top-left corner goes."""
    img = Image.open(os.path.join(HERE, row["Image"].strip())).convert("RGBA")
    x, y = int(float(row.get("X") or 0)), int(float(row.get("Y") or 0))
    scale = max(1, int(float(row.get("Scale") or 1)))
    crop = (row.get("Crop") or "").strip()
    if crop:
        cx, cy, cw, ch = [int(v) for v in crop.split(",")]
        img = img.crop((cx, cy, cx + cw, cy + ch))
        x, y = x + cx * scale, y + cy * scale
    if scale != 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    if "h" in (row.get("Flip") or "").lower():
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    return img, x, y


def main():
    with open(SHEET, encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f) if (r.get("Image") or "").strip()]
    sheet = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    layers = []
    for row in rows:
        img, x, y = part_image(row)
        sheet.alpha_composite(img, (max(0, x), max(0, y)), (max(0, -x), max(0, -y)))
        # Aseprite wants the part cropped to the canvas.
        box = (max(0, -x), max(0, -y), min(img.width, W - x), min(img.height, H - y))
        layers.append((row["Part"], img.crop(box), max(0, x), max(0, y)))
    sheet.convert("RGB").save(OUT)
    print("wrote %s" % os.path.relpath(OUT, HERE))
    write_aseprite(ASE, W, H, layers)
    print("wrote %s (%d layers)" % (os.path.relpath(ASE, HERE), len(layers)))


if __name__ == "__main__":
    main()
