#!/usr/bin/env python3
# =============================================================
#  DRAWN PITCH SHEETS  (Anthony, 18 Oct 2026: drawn players, not pixel art)
#
#      ~/.venvs/sturmball/bin/python tools/make_drawn_pitch_sheet.py
#
#  Reads every look in art_source/drawn_players/<look>/, frames named
#  <animation>_<direction>_<NN>.png (direction w, sw, s, nw, n, e, se, ne),
#  each one a 112 x 112 cell with the feet on the same line.
#  Writes assets/players/pitch/drawn_<look>_<tone>.webp for every tone in
#  data/SkinTones.csv, laid out like data/PitchAnims.csv (First Row, then
#  the 8 direction rows). The frame size and placement of these sheets are in
#  data/PitchSheets.csv.
#
#  A direction with no frames borrows one: east = west mirrored, south-east
#  = south-west mirrored, north-east = north-west mirrored; south-west and
#  north-west use west, south uses south-west, north uses north-west.
#  An animation with no frames at all is left out, so the game plays its
#  Stand-in (PitchAnims.csv).
#  At the end it prints the Pitch Sheet list for data/PitchSprites.csv.
# =============================================================
import csv
import glob
import os
import re

import numpy as np
from PIL import Image, ImageOps

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(HERE, "art_source/drawn_players")
OUT = os.path.join(HERE, "assets/players/pitch")
CELL = 112
ORDER = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]          # PitchAnims.csv row order
BORROW = {"e": ("w", True), "se": ("sw", True), "ne": ("nw", True),
          "sw": ("w", False), "nw": ("w", False), "s": ("sw", False), "n": ("nw", False)}


def read_csv(name):
    with open(os.path.join(HERE, "data", name), newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def skin_mask(rgb):
    import cv2
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    h, s, v = (hsv[..., i].astype(int) for i in range(3))
    m = (h >= 5) & (h <= 22) & (s > 50) & (s < 200) & (v > 120)
    m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    return cv2.GaussianBlur(m.astype(np.float32), (3, 3), 0)


def recolour(im, light, colour):
    if light == 1.0 and colour == 1.0:
        return im
    import cv2
    a = np.array(im)
    rgb = a[..., :3].copy()
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).astype(np.float32)
    m = skin_mask(rgb)[..., None]
    new = np.dstack([lab[..., 0] * light, 128 + (lab[..., 1] - 128) * colour,
                     128 + (lab[..., 2] - 128) * colour]).clip(0, 255).astype(np.uint8)
    new = cv2.cvtColor(new, cv2.COLOR_LAB2RGB).astype(np.float32)
    rgb = (rgb * (1 - m) + new * m).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, a[..., 3]]))


def frames_of(folder):
    """{animation: {direction: [frame, ...]}}"""
    out = {}
    for path in sorted(glob.glob(os.path.join(folder, "*.png"))):
        m = re.match(r"([a-z]+)_([a-z]+)_(\d+)\.png$", os.path.basename(path))
        if m:
            out.setdefault(m.group(1), {}).setdefault(m.group(2), []).append(Image.open(path).convert("RGBA"))
    return out


def direction(anim, d):
    if d in anim:
        return anim[d]
    seen = {d}
    while d in BORROW and d not in anim:
        d2, mirror = BORROW[d]
        if d2 in seen:
            break
        seen.add(d2)
        if d2 in anim:
            return [ImageOps.mirror(f) for f in anim[d2]] if mirror else anim[d2]
        if d2 in BORROW and BORROW[d2][0] in anim:
            src = anim[BORROW[d2][0]]
            return [ImageOps.mirror(f) for f in src] if (mirror != BORROW[d2][1]) else src
        d = d2
    return next(iter(anim.values()))


def main():
    anims = read_csv("PitchAnims.csv")
    tones = read_csv("SkinTones.csv")
    names = []
    for folder in sorted(glob.glob(os.path.join(SRC, "*/"))):
        look = os.path.basename(folder.rstrip("/"))
        have = frames_of(folder)
        rows = [a for a in anims if a["Animation"] in have]
        last = max(int(a["First Row"]) + 8 for a in rows)
        cols = max(int(a["Frames"]) for a in rows)
        for tone in tones:
            light, colour = float(tone["Lightness"] or 1), float(tone["Colour"] or 1)
            sheet = Image.new("RGBA", (cols * CELL, last * CELL), (0, 0, 0, 0))
            for a in rows:
                want = int(a["Frames"])
                for k, d in enumerate(ORDER):
                    fr = direction(have[a["Animation"]], d)
                    for i in range(want):
                        f = fr[int(i * len(fr) / want)]
                        sheet.alpha_composite(recolour(f, light, colour), (i * CELL, (int(a["First Row"]) + k) * CELL))
            name = f"drawn_{look}_{tone['Tone']}.webp"
            sheet.save(os.path.join(OUT, name), quality=90, method=6)
            names.append(name)
            print(name, sheet.size, "moves:", ", ".join(a["Animation"] for a in rows))
    print("\nPitch Sheet for data/PitchSprites.csv:\n" + "|".join(names))


if __name__ == "__main__":
    main()
