#!/usr/bin/env python3
# =============================================================
#  DRAWN WINDOW SHEETS  (Anthony, 24 Oct 2026: "the player needs to be more
#  crisp and not so blurry")
#
#      python3 tools/make_drawn_window_sheet.py [frames folder]
#
#  The pitch sheets are cut at 112 px a frame, which is right for the pitch
#  but blurry when a window shows the player big (the drinking window). This
#  cuts the same drawn frames again from the full-size 900 x 1500 video
#  frames (art_tool/thomas_video in the project files, made 18 Oct), at
#  CELL x TALL px a frame (data/DrinkWindow.csv window_cell), facing right
#  (east), three rows:
#      row 0  idle   4 frames  (standing)
#      row 1  cheer  9 frames  (looks without a cheer clip stand instead)
#      row 2  front  4 frames  (standing, facing the camera, for the line-up;
#                               a look without front frames stands side-on)
#  Every figure is drawn the same size, feet on the same line (FEET).
#  Writes assets/players/window/<same name as the pitch sheet>.webp: one per
#  skin tone (data/SkinTones.csv) for the Club men, one each for the classes,
#  the club women and the Rival man. DrinkWindow uses it when it is there
#  (data/DrinkWindow.csv window_sheets).
# =============================================================
import csv
import glob
import os
import sys

import numpy as np
from PIL import Image, ImageOps

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_drawn_pitch_sheet import recolour  # noqa: E402  (the same skin tones as the pitch)

SRC = sys.argv[1] if len(sys.argv) > 1 else "/mnt/project-files/art_tool/thomas_video"
OUT = os.path.join(HERE, "assets/players/window")
CELL = 336                 # frame width: 3 x the pitch frame
TALL = 460                 # frame height: room above for a cheering jump
FEET = 0.965               # feet line, as a share of the frame height
FIG = CELL * 91.0 / 112.0  # a running figure's height, as on the pitch
SOURCE_FIG = 709.0         # ... in the 900 x 1500 frames (feet at 1480, centre x 450)
CHEER = 9
IDLE = 4
# Classes drawn a little bigger, as on the pitch (class_prep.py SIZE).
SIZE = {"feuergeist": 1.15,
        # Tutorial Koch (Anthony 24 Oct: "Koch is too large ... shouldn't look
        # like a giant"): drawn a touch shorter so he stands in line.
        "koch_tut": 0.95}


def clear_leg_gap(canvas):
    """The video cut left the white background showing between the legs
    (closed in by the legs, so it was never keyed out): any big near-white
    patch in the lowest quarter of the figure, below the shorts, goes."""
    import cv2
    a = np.array(canvas.convert("RGBA"))
    top = int(1480 - 0.26 * SOURCE_FIG)
    band = a[top:1500]
    light = (band[..., :3].min(2) > 215) & (band[..., 3] > 0)
    n, lab, stats, _ = cv2.connectedComponentsWithStats(light.astype(np.uint8), connectivity=4)
    for i in range(1, n):
        w, h = stats[i, cv2.CC_STAT_WIDTH], stats[i, cv2.CC_STAT_HEIGHT]
        if stats[i, cv2.CC_STAT_AREA] > 500 and h > 40 and w < 0.6 * h:   # tall and narrow: a gap, not shorts
            band[lab == i, 3] = 0
    a[top:1500] = band
    return Image.fromarray(a)


def to_cell(canvas, extra=1.0, mirror=True):
    k = FIG / SOURCE_FIG * extra
    im = clear_leg_gap(canvas).resize((max(1, int(900 * k)), max(1, int(1500 * k))), Image.LANCZOS)
    cell = Image.new("RGBA", (CELL, TALL), (0, 0, 0, 0))
    cell.alpha_composite(im, (int(CELL / 2 - 450 * k), int(TALL * FEET - 1480 * k)))
    return ImageOps.mirror(cell) if mirror else cell


def frames(pattern):
    return [Image.open(f) for f in sorted(glob.glob(os.path.join(SRC, pattern)))]


def whole_feet(seq):
    """Only the frames whose shoes are whole: the 18 Oct video cut some
    off at the bottom edge (Anthony 24 Oct: "his feet are still cut off,
    see the shoes"). Keeps them all if fewer than three are whole."""
    whole = [im for im in seq if im.getbbox() and im.getbbox()[3] < 1497]
    return whole if len(whole) >= 3 else seq


def pick(seq, n):
    return [seq[int(i * len(seq) / n)] for i in range(n)]


def sheet(idle, cheer, front):
    out = Image.new("RGBA", (CHEER * CELL, 3 * TALL), (0, 0, 0, 0))
    for i, im in enumerate(front):
        out.alpha_composite(im, (i * CELL, 2 * TALL))
    for i, im in enumerate(idle):
        out.alpha_composite(im, (i * CELL, 0))
    for i, im in enumerate(cheer):
        out.alpha_composite(im, (i * CELL, TALL))
    return out


def save(im, name):
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, name), quality=92, method=6)
    print(name, im.size)


def main():
    with open(os.path.join(HERE, "data/SkinTones.csv"), newline="", encoding="utf-8") as f:
        tones = [t for t in csv.DictReader(f) if t["Tone"]]
    # The Club men: side-on standing frame (Thomas has his own breathing idle) and the cheer clip.
    for look in ("thomas", "fat_afro", "muscular_quiff", "skinny_mullet"):
        breath = (1.0, 1.006, 1.012, 1.006)
        side = frames(f"moves/{look}/stand_side.png")
        front = frames(f"moves/{look}/stand_front.png")
        if look == "thomas":
            idle = [to_cell(im) for im in frames("idle/w_*.png")]
        elif side:
            # moves/<look>/stand_side.png and stand_front.png: the standing
            # frames with their boots drawn whole (24 Oct, 6 Sunburst edits,
            # /mnt/project-files/drink_window/shoe_fix/), soles at 1482.
            idle = [to_cell(side[0], br) for br in breath]
        else:
            hold = frames(f"moves/{look}/idle_hold_[0-9]*.png")[0]
            idle = [to_cell(hold, br) for br in breath]
        cheer = pick([to_cell(im) for im in whole_feet(frames(f"moves/{look}/cheer_[0-9]*.png"))], CHEER)
        if front:
            front = [to_cell(front[0], br, mirror=False) for br in breath]
        else:
            front = [to_cell(im, mirror=False) for im in frames(f"moves/{look}/idle_s_[0-9]*.png")] or idle
        base = sheet(pick(idle, IDLE), cheer, pick(front, IDLE))
        for tone in tones:
            save(recolour(base, float(tone["Lightness"] or 1), float(tone["Colour"] or 1)),
                 f"drawn_{look}_{tone['Tone']}.webp")
    # The classes, the club women and the Rival man: their own colours.
    for folder in sorted(glob.glob(os.path.join(SRC, "elements/*/frames"))):
        name = folder.split(os.sep)[-2]
        if not os.path.exists(os.path.join(HERE, f"assets/players/pitch/drawn_class_{name}.webp")):
            continue
        extra = SIZE.get(name, 1.0)
        rel = os.path.relpath(folder, SRC)
        idle = [to_cell(im, extra, mirror=False) for im in frames(f"{rel}/idle_[0-9]*.png")]
        cheer = [to_cell(im, extra) for im in whole_feet(frames(f"{rel}/cheer_[0-9]*.png"))] or idle
        # Their standing frames already face the camera.
        save(sheet(pick(idle, IDLE), pick(cheer, CHEER), pick(idle, IDLE)), f"drawn_class_{name}.webp")


if __name__ == "__main__":
    main()
