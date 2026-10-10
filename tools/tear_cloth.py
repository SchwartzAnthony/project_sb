#!/usr/bin/env python3
# =============================================================
#  THE TORN CONQUESTS CLOTH, AND ITS INFINITY  (Conquests placeholder)
#
#      ~/.venvs/sturmball/bin/python tools/tear_cloth.py
#      ~/.venvs/sturmball/bin/python tools/make_banners.py
#
#  Anthony: "Conquests would actually also be a flag on the top with the
#  rest of the options, but it being a black infinite symbol on it and it
#  looking really torn and old."
#
#  So this takes the ONE shared PixelLab cloth and ages it, instead of
#  drawing a new one: faded to a dirty grey-brown, ragged down both sides, two
#  moth holes, a rip up from the swallowtail and half the stitches gone.
#  It writes:
#
#      art_source/pixellab/banners/cloths/conquests.png    the torn cloth
#      art_source/pixellab/banners/emblems/conquests.png   the black infinity
#
#  make_banners.py then uses cloths/<name>.png instead of the shared cloth
#  for any banner that has one.
#
#  BOTH ARE STAND-INS until PixelLab draws them (ArtOrders.csv,
#  conquests_banner). Same seed, same picture, every run.
# =============================================================

import math
import os
import random

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(HERE, "art_source", "pixellab", "banners")
SEED = 1979
INK = (1, 1, 2, 255)
# A weathered, dirty grey-brown: dark enough that the cream name thread
# every banner uses still reads on it, light enough for a black infinity.
BONE = (112, 100, 82, 255)        # the old cloth, where it was blue
BONE_DARK = (86, 76, 62, 255)     # its shadows and stains
THREAD = (150, 124, 78, 255)      # what is left of the gold stitching
# The rows the name is stitched on (MenuSupport.BANNER_TEXT_BOX, in cloth
# pixels from the top of the loops). Nothing is torn or stained there, so
# the whole word sits on solid cloth like on every other banner.
NAME_ROWS = range(24, 43)


def _is_ink(px):
    return px[3] > 0 and max(px[:3]) < 30


def tear(cloth):
    rnd = random.Random(SEED)
    w, h = cloth.size
    out = cloth.copy()
    box = cloth.getbbox()
    left, top, right, bottom = box

    # 1. Fade: blue cloth -> dirty grey-brown, gold thread -> dull brown, and lose
    #    about half the stitches.
    for y in range(h):
        for x in range(w):
            p = out.getpixel((x, y))
            if p[3] == 0 or _is_ink(p):
                continue
            r, g, b, _ = p
            if b > r:   # the blue cloth
                out.putpixel((x, y), BONE_DARK if b < 80 else BONE)
            else:       # the gold stitching
                out.putpixel((x, y), BONE if rnd.random() < 0.5 else THREAD)

    # 2. Stains: a few blotches of the darker shade.
    for _ in range(5):
        cx, cy = rnd.randint(left + 4, right - 4), rnd.randint(top + 14, bottom - 14)
        if cy - top in range(NAME_ROWS.start - 4, NAME_ROWS.stop + 4):
            continue
        rad = rnd.randint(2, 4)
        for y in range(cy - rad, cy + rad + 1):
            for x in range(cx - rad, cx + rad + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= rad * rad and rnd.random() < 0.7:
                    p = out.getpixel((x, y))
                    if p == BONE:
                        out.putpixel((x, y), BONE_DARK)

    # 3. What is torn away: ragged bites down both sides, two holes, a rip
    #    up from the swallowtail's notch. The loops at the top stay whole -
    #    it still has to hang from the rod.
    gone = set()
    hang = top + 8
    for y in range(hang, bottom + 1):
        if y - top in NAME_ROWS:
            continue
        if rnd.random() < 0.35:
            depth = rnd.randint(1, 3)
            for x in range(left, left + depth):
                gone.add((x, y))
        if rnd.random() < 0.35:
            depth = rnd.randint(1, 3)
            for x in range(right - depth, right):
                gone.add((x, y))
    # Both kept clear of the name's box (MenuSupport.BANNER_TEXT_BOX), so
    # the stitched word stays whole.
    for cx, cy, rad in ((left + 6, top + 45, 2), (right - 6, top + 21, 1)):
        for y in range(cy - rad, cy + rad + 1):
            for x in range(cx - rad, cx + rad + 1):
                if abs(x - cx) + abs(y - cy) <= rad:
                    gone.add((x, y))
    # The rip: from the notch, a jagged line climbing up and to the left.
    notch_x = (left + right) // 2
    notch_y = max(y for y in range(h) if not out.getpixel((notch_x, y))[3]
                  and y < bottom and out.getpixel((notch_x, y - 1))[3])
    x = notch_x
    for y in range(notch_y, max(notch_y - 8, top + NAME_ROWS.stop), -1):
        x += rnd.choice((-1, 0, 0, -1, 1))
        gone.add((x, y))
        if rnd.random() < 0.5:
            gone.add((x + 1, y))
    # The tails' tips, frayed off.
    for x in range(left, right):
        for y in range(bottom - 3, bottom + 1):
            if rnd.random() < 0.45:
                gone.add((x, y))

    for (x, y) in gone:
        if 0 <= x < w and 0 <= y < h and y >= hang:
            out.putpixel((x, y), (0, 0, 0, 0))

    # 4. Ink every cut edge again, so it reads as cloth and not as damage
    #    to the picture.
    edge = []
    for y in range(h):
        for x in range(w):
            if out.getpixel((x, y))[3] == 0 or _is_ink(out.getpixel((x, y))):
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < w and 0 <= ny < h) or out.getpixel((nx, ny))[3] == 0:
                    edge.append((x, y))
                    break
    for xy in edge:
        out.putpixel(xy, INK)
    return out


def infinity(size=32):
    """A black lemniscate, thick inked line with a thin grey shine."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cx, cy = size / 2 - 0.5, size / 2 - 0.5
    a = 12.5

    def dots(thick, colour, shift=0.0):
        for i in range(2000):
            t = i / 2000 * 2 * math.pi
            d = 1 + math.sin(t) ** 2
            x = cx + a * math.cos(t) / d
            y = cy + a * math.sin(t) * math.cos(t) / d * 1.25 + shift
            for ox in range(-thick, thick + 1):
                for oy in range(-thick, thick + 1):
                    if ox * ox + oy * oy <= thick * thick + 0.5:
                        px, py = int(round(x + ox)), int(round(y + oy))
                        if 0 <= px < size and 0 <= py < size:
                            img.putpixel((px, py), colour)

    dots(2, INK)
    # A sliver of shine on the upper edge of each loop, so it is a thing and
    # not a hole.
    for i in range(2000):
        t = i / 2000 * 2 * math.pi
        d = 1 + math.sin(t) ** 2
        x = cx + a * math.cos(t) / d
        y = cy + a * math.sin(t) * math.cos(t) / d * 1.25
        if abs(math.cos(t)) > 0.75 and math.sin(t) * math.cos(t) < -0.12:
            img.putpixel((int(round(x)), int(round(y - 1))), (70, 70, 78, 255))
    return img


def main():
    cloth = Image.open(os.path.join(SRC, "cloth.png")).convert("RGBA")
    os.makedirs(os.path.join(SRC, "cloths"), exist_ok=True)
    tear(cloth).save(os.path.join(SRC, "cloths", "conquests.png"))
    infinity().save(os.path.join(SRC, "emblems", "conquests.png"))
    print("wrote cloths/conquests.png and emblems/conquests.png")


if __name__ == "__main__":
    main()
