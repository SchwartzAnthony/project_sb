#!/usr/bin/env python3
# =============================================================
#  COMIC FIRST, PIXELS SECOND  (round AJ)
#
#      python3 tools/pixelate.py                 every row of data/Pixelate.csv
#      python3 tools/pixelate.py menu_hero       just that row
#
#  Your rule: draw it as a Marcinelle-school comic FIRST, then pixelate it.
#  The comic master (from Ludo.ai, or one you drew) lives in art_source/;
#  this script turns it into the pixel-art file the game uses.
#
#  ============ data/Pixelate.csv - one row per picture ============
#
#    ID         a name for the row
#    Source     the comic master, from the project folder
#    Output     where the pixel art goes (assets/...)
#    Height     how many pixels tall the pixel art is (the width follows).
#               The game then draws it 2x, 3x ... bigger, so it stays sharp.
#    Colours    how many colours it may use. Fewer = more "pixel".
#    Outline    yes = a 1-pixel black ink line all round the outside
#    Ink        how dark a colour must be to become pure black ink (0-255;
#               0 = off). Keeps the comic's black lines crisp.
#    Crop       yes = cut away the empty space round the figure first
#    Fill Holes a colour (#f4f1ea) for see-through holes INSIDE the figure.
#               PixelLab's background removal sometimes eats white areas
#               that are enclosed - the white panels of a football. Blank = off.
#    Notes      anything
#
#  Change a number, run it again, look in Godot.
# =============================================================

import csv
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(HERE, "data", "Pixelate.csv")
INK = (20, 14, 10)


def fill_holes(im, colour):
    """Transparent pixels that cannot reach the edge of the picture are holes:
    paint them `colour`, fully opaque."""
    w, h = im.size
    px = im.load()
    outside = set()
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y = stack.pop()
        if (x, y) in outside or not (0 <= x < w and 0 <= y < h) or px[x, y][3] > 0:
            continue
        outside.add((x, y))
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    rgb = tuple(int(colour.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0 and (x, y) not in outside:
                px[x, y] = rgb + (255,)
    return im


def pixelate(src, height, colours, outline, ink, crop, holes=""):
    im = Image.open(src).convert("RGBA")
    if holes:
        im = fill_holes(im, holes)
    if crop and im.getbbox():
        im = im.crop(im.getbbox())
    width = max(1, round(im.width * height / im.height))
    # Shrink in two steps (box, then lanczos) so thin ink lines survive.
    mid = im.resize((width * 2, height * 2), Image.BOX)
    small = mid.resize((width, height), Image.LANCZOS)
    alpha = small.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    # Flatten onto mid-grey so transparent edges do not pull colours to black.
    flat = Image.new("RGBA", small.size, (128, 128, 128, 255))
    flat.alpha_composite(small)
    rgb = flat.convert("RGB").quantize(colors=colours, method=Image.Quantize.FASTOCTREE,
                                       kmeans=4, dither=Image.Dither.NONE).convert("RGB")
    px = rgb.load()
    if ink > 0:
        for y in range(rgb.height):
            for x in range(rgb.width):
                r, g, b = px[x, y]
                if (r + g + b) / 3 < ink:
                    px[x, y] = INK
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    if outline:
        ap = alpha.load()
        op = out.load()
        for y in range(out.height):
            for x in range(out.width):
                if ap[x, y] == 0:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        X, Y = x + dx, y + dy
                        if 0 <= X < out.width and 0 <= Y < out.height and ap[X, Y] == 255:
                            op[x, y] = INK + (255,)
                            break
    return out


def main():
    only = sys.argv[1:]
    with open(SHEET, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            rid = (row.get("ID") or "").strip()
            if not rid or (only and rid not in only):
                continue
            src = os.path.join(HERE, row["Source"].strip())
            dst = os.path.join(HERE, row["Output"].strip())
            if not os.path.isfile(src):
                print("  ! %s: no comic master at %s" % (rid, row["Source"]))
                continue
            out = pixelate(src, int(float(row.get("Height") or 160)), int(float(row.get("Colours") or 32)),
                           (row.get("Outline") or "yes").strip().lower() == "yes",
                           int(float(row.get("Ink") or 60)), (row.get("Crop") or "yes").strip().lower() == "yes",
                           (row.get("Fill Holes") or "").strip())
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            out.save(dst)
            print("  %s: %s -> %s (%dx%d, %s colours)" % (rid, row["Source"], row["Output"], out.width, out.height, row.get("Colours")))


if __name__ == "__main__":
    main()
