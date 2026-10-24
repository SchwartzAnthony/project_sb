#!/usr/bin/env python3
# =============================================================
#  DRAWN DUEL SHEETS  (Anthony, 24 Oct 2026: "During combat the players
#  look very blurry")
#
#      python3 tools/make_drawn_duel_sheet.py [frames folder]
#
#  The duel showed the 112 px pitch frames blown up about three times, so
#  they went soft. This cuts every move the duel plays again from the
#  full-size 900 x 1500 video frames (art_tool/thomas_video in the project
#  files, made 18 Oct), big enough that the duel never has to blow them up.
#  CELL x TALL px a frame (Tuning.csv duel_cell), all facing right (east);
#  the duel mirrors the right-hand player. Five rows (PitchSprite.DUEL_ROWS):
#      row 0  idle   4 frames  (standing)
#      row 1  run    8 frames
#      row 2  kick   9 frames  (the ability)
#      row 3  cheer  9 frames  (won; a look without a cheer clip stands)
#      row 4  fall   7 frames  (lost; a look without a fall clip tips over)
#  Every figure is drawn the same size, feet on the same line (FEET).
#  Writes assets/players/duel/<same name as the pitch sheet>.webp: one per
#  skin tone (data/SkinTones.csv) for the Club men, one each for the
#  classes, the club women and the Rival man.
# =============================================================
import csv
import glob
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_drawn_pitch_sheet import recolour  # noqa: E402  (the same skin tones as the pitch)
from make_drawn_window_sheet import SIZE, clear_leg_gap, whole_feet, pick  # noqa: E402

SRC = sys.argv[1] if len(sys.argv) > 1 else "/mnt/project-files/art_tool/thomas_video"
OUT = os.path.join(HERE, "assets/players/duel")
CELL = 400                 # frame width
TALL = 540                 # frame height: room above for a cheering jump
FEET = 0.965               # feet line, as a share of the frame height
FIG = CELL * 91.0 / 112.0  # a running figure's height, as on the pitch (325 px)
SOURCE_FIG = 709.0         # ... in the 900 x 1500 frames (feet at 1480, centre x 450)
BOB = 0.35                 # how much of the run's head bounce stays (approved 18 Oct)
COUNTS = (4, 8, 9, 9, 7)   # idle, run, kick, cheer, fall


def to_cell(canvas, extra=1.0, mirror=True, dy=0):
    k = FIG / SOURCE_FIG * extra
    im = clear_leg_gap(canvas).resize((max(1, int(900 * k)), max(1, int(1500 * k))), Image.LANCZOS)
    cell = Image.new("RGBA", (CELL, TALL), (0, 0, 0, 0))
    cell.alpha_composite(im, (int(CELL / 2 - 450 * k), int(TALL * FEET - 1480 * k + dy)))
    return cell.transpose(Image.FLIP_LEFT_RIGHT) if mirror else cell


def frames(pattern):
    return [Image.open(f) for f in sorted(glob.glob(os.path.join(SRC, pattern)))]


def debob(seq):
    """The run as on the pitch: only BOB of the head bounce stays."""
    tops = np.array([im.getbbox()[1] for im in seq], float)
    out = []
    for im, top in zip(seq, tops):
        c = Image.new("RGBA", im.size, (0, 0, 0, 0))
        c.alpha_composite(im, (0, int(round(-(1 - BOB) * (top - tops.mean())))))
        out.append(c)
    return out


def tip_over(cell):
    """A free stand-in fall for a look with no fall clip: he tips over
    backwards from his feet."""
    pivot = (CELL * 0.5, TALL * FEET)
    out = []
    for a in (0, 8, 20, 36, 52, 64, 72):
        big = Image.new("RGBA", (CELL * 2, TALL), (0, 0, 0, 0))
        big.alpha_composite(cell, (CELL // 2, 0))
        big = big.rotate(a, resample=Image.BICUBIC, center=(pivot[0] + CELL // 2, pivot[1]))
        box = big.getbbox()
        # Lying on the grass, not sinking into it; kept inside his frame.
        lifted = Image.new("RGBA", big.size, (0, 0, 0, 0))
        lifted.alpha_composite(big, (0, int(TALL * FEET) - box[3]))
        left = CELL // 2 - int(110 * a / 72)   # he slides back as he goes down
        out.append(lifted.crop((left, 0, left + CELL, TALL)))
    return out


def sheet(rows):
    out = Image.new("RGBA", (max(COUNTS) * CELL, len(rows) * TALL), (0, 0, 0, 0))
    for r, row in enumerate(rows):
        for i, im in enumerate(pick(row, COUNTS[r])):
            out.alpha_composite(im, (i * CELL, r * TALL))
    return out


def save(im, name):
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, name), quality=90, method=6)
    print(name, im.size)


def main():
    with open(os.path.join(HERE, "data/SkinTones.csv"), newline="", encoding="utf-8") as f:
        tones = [t for t in csv.DictReader(f) if t["Tone"]]
    # The Club men.
    runs = {"thomas": "dirs/w_*.png"}
    for look in ("thomas", "fat_afro", "muscular_quiff", "skinny_mullet"):
        breath = (1.0, 1.006, 1.012, 1.006)
        side = frames(f"moves/{look}/stand_side.png")
        if look == "thomas":
            idle = [to_cell(im) for im in frames("idle/w_*.png")]
        elif side:
            idle = [to_cell(side[0], br) for br in breath]
        else:
            idle = [to_cell(frames(f"moves/{look}/idle_hold_[0-9]*.png")[0], br) for br in breath]
        run = frames(runs.get(look, f"looks/{look}/frames/run_[0-9]*.png"))
        if look == "skinny_mullet":
            run = run[::2]
        run = [to_cell(im) for im in debob(run)]
        kick = [to_cell(im) for im in frames(f"moves/{look}/kick_[0-9]*.png")]
        cheer = [to_cell(im) for im in whole_feet(frames(f"moves/{look}/cheer_[0-9]*.png"))] or idle
        fall = [to_cell(im) for im in frames(f"moves/{look}/fall_[0-9]*.png")] or tip_over(idle[0])
        base = sheet([idle, run, kick, cheer, fall])
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
        # Their standing frames face the camera, so they stay as drawn.
        idle = [to_cell(im, extra, mirror=False) for im in frames(f"{rel}/idle_[0-9]*.png")]
        run = [to_cell(im, extra) for im in debob(frames(f"{rel}/run_[0-9]*.png"))]
        kick = [to_cell(im, extra) for im in frames(f"{rel}/kick_[0-9]*.png")]
        cheer = [to_cell(im, extra) for im in whole_feet(frames(f"{rel}/cheer_[0-9]*.png"))] or idle
        fall = [to_cell(im, extra) for im in frames(f"{rel}/fall_[0-9]*.png")] or tip_over(run[0])
        save(sheet([idle, run, kick, cheer, fall]), f"drawn_class_{name}.webp")


if __name__ == "__main__":
    main()
