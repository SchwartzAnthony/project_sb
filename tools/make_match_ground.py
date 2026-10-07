#!/usr/bin/env python3
# =============================================================
#  THE MATCH GROUND = THE BASE TOWN, ZOOMED IN  (round AN)
#
#      ~/.venvs/sturmball/bin/python tools/make_match_ground.py
#
#  Anthony: the match is played on the base's own pitch, seen like a drone
#  shot, with every building, path and tree exactly where the base has them.
#  So this does not draw anything new. It takes the base's own parts -
#  data/BaseTown.csv (ground, clouds, boats, paths, bridge, maypole, trees)
#  and the buildings of data/Buildings.csv at their X / Y / Map Size - and
#  puts them together again, bigger, for the match:
#
#      assets/field/match_ground.png            the picture behind the pitch
#      art_source/aseprite/match_ground.aseprite every part on its own layer
#
#  data/MatchGround.csv says which parts go in, how much bigger (Scale) and
#  where the base's pitch lines are, so they can be painted out: the match
#  draws its own pitch, tilted onto that spot (data/PitchView.csv).
# =============================================================

import csv
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "tools"))
from make_aseprite import write_aseprite  # noqa: E402
from make_base_town import part_image  # noqa: E402

SHEET = os.path.join(HERE, "data", "MatchGround.csv")
BASE = os.path.join(HERE, "data", "BaseTown.csv")
BUILDINGS = os.path.join(HERE, "data", "Buildings.csv")
OUT = os.path.join(HERE, "assets", "field", "match_ground.png")
ASE = os.path.join(HERE, "art_source", "aseprite", "match_ground.aseprite")
BASE_W, BASE_H = 1920, 1080


def settings():
    out = {}
    with open(SHEET, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            out[(row.get("Key") or "").strip()] = (row.get("Value") or "").strip()
    return out


def inside(poly, x, y):
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def paint_out_lines(img, poly):
    """The base's pitch lines, inside poly (corner points in the ground
    picture's own pixels), become grass: every pixel there that is not grass
    green takes the colour of the nearest grass pixel."""
    px = img.load()
    x0, x1 = min(p[0] for p in poly), max(p[0] for p in poly) + 1
    y0, y1 = min(p[1] for p in poly), max(p[1] for p in poly) + 1
    mask = {(x, y) for y in range(y0, y1) for x in range(x0, x1) if inside(poly, x, y)}

    def grass(c):
        r, g, b = c[0], c[1], c[2]
        return g > r + 25 and g > b + 25

    for _ in range(40):
        changed = 0
        for (x, y) in mask:
                if grass(px[x, y]):
                    continue
                for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0), (0, -2), (0, 2)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < img.width and 0 <= ny < img.height and grass(px[nx, ny]):
                        px[x, y] = px[nx, ny]
                        changed += 1
                        break
        if not changed:
            break
    return img


def main():
    cfg = settings()
    scale = max(1, int(float(cfg.get("scale", "2"))))
    skip = {p.strip() for p in cfg.get("skip_base_parts", "").split("|") if p.strip()}
    poly = [tuple(int(v) for v in p.split(",")) for p in cfg.get("pitch_paint_polygon", "").split("|") if "," in p]
    W, H = BASE_W * scale, BASE_H * scale

    parts = []
    with open(BASE, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            name = row["Part"].strip()
            if not (row.get("Image") or "").strip() or name in skip:
                continue
            img, x, y = part_image(row)
            if name == "ground" and len(poly) >= 3:
                # Paint in the ground's own pixels, then scale like part_image.
                raw = Image.open(os.path.join(HERE, row["Image"].strip())).convert("RGBA")
                s = max(1, int(float(row.get("Scale") or 1)))
                raw = paint_out_lines(raw, poly)
                img = raw.resize((raw.width * s, raw.height * s), Image.NEAREST)
            parts.append((name, img, x, y))

    with open(BUILDINGS, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            art = (row.get("Map Art") or "").strip()
            if not art or row["ID"].strip() in skip:
                continue
            path = os.path.join(HERE, "assets", "base", "map", art + ".png")
            if not os.path.isfile(path):
                continue
            img = Image.open(path).convert("RGBA")
            size = (row.get("Map Size") or "").strip().lower()
            w, h = (img.width * 2, img.height * 2)
            if "x" in size:
                w, h = [int(v) for v in size.split("x")]
            img = img.resize((w, h), Image.NEAREST)
            # Exactly where base_screen.gd _place() puts it (scenery: no margins).
            x = min(max(0, BASE_W * float(row["X"]) - w / 2), BASE_W - w)
            y = min(max(0, BASE_H * float(row["Y"]) - h / 2), BASE_H - h)
            parts.append((row["ID"].strip(), img, int(x), int(y)))

    sheet = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    layers = []
    for name, img, x, y in parts:
        if scale != 1:
            img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
            x, y = x * scale, y * scale
        sheet.alpha_composite(img, (max(0, x), max(0, y)), (max(0, -x), max(0, -y)))
        crop = (max(0, -x), max(0, -y), min(img.width, W - x), min(img.height, H - y))
        layers.append((name, img.crop(crop), max(0, x), max(0, y)))
    sheet.convert("RGB").save(OUT)
    print("wrote %s (%dx%d)" % (os.path.relpath(OUT, HERE), W, H))
    write_aseprite(ASE, W, H, layers)
    print("wrote %s (%d layers)" % (os.path.relpath(ASE, HERE), len(layers)))


if __name__ == "__main__":
    main()
