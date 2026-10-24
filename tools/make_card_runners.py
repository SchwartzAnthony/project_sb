#!/usr/bin/env python3
# =============================================================
#  SHARP CARD RUNNERS  (Anthony, 24 Oct 2026: "The twice size players on the
#  cards are now blurry, need to get them redone or redrawn")
#
#      python3 tools/make_card_runners.py
#
#  The player running on his beer mat card used to be his pitch sheet blown
#  up about twice, which is what made him blurry. These are the same run
#  frames cut three times bigger from the big source pictures
#  (art_source/card_runners/<look>/run_w_NN.png), so the card shrinks them
#  instead of stretching them.
#
#  Writes assets/players/card/<pitch sheet name>.webp: one row of the run
#  facing west, as many frames as data/PitchAnims.csv's run row, one per
#  pitch sheet (every skin tone in data/SkinTones.csv for the Club men; the
#  classes and the people with their own colours keep theirs).
#  A pitch sheet with no card runner here simply keeps the old (blurry) way.
#  Free: no new pictures are made.
# =============================================================
import glob
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_drawn_pitch_sheet import CLASSES, HERE, read_csv, recolour  # noqa: E402

SRC = os.path.join(HERE, "art_source/card_runners")
OUT = os.path.join(HERE, "assets/players/card")


def strip(frames, want, light, colour):
    cell = frames[0].width
    out = Image.new("RGBA", (want * cell, cell), (0, 0, 0, 0))
    for i in range(want):
        f = frames[int(i * len(frames) / want)]
        out.alpha_composite(recolour(f, light, colour), (i * cell, 0))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    want = int(next(a for a in read_csv("PitchAnims.csv") if a["Animation"] == "run")["Frames"])
    tones = read_csv("SkinTones.csv")
    classes = {os.path.basename(p.rstrip("/")) for p in glob.glob(os.path.join(CLASSES, "*/"))}
    for folder in sorted(glob.glob(os.path.join(SRC, "*/"))):
        look = os.path.basename(folder.rstrip("/"))
        frames = [Image.open(p).convert("RGBA") for p in sorted(glob.glob(os.path.join(folder, "run_w_*.png")))]
        if not frames:
            continue
        if look in classes:
            jobs = [(f"drawn_class_{look}", 1.0, 1.0)]
        else:
            jobs = [(f"drawn_{look}_{t['Tone']}", float(t["Lightness"] or 1), float(t["Colour"] or 1)) for t in tones]
        for name, light, colour in jobs:
            im = strip(frames, want, light, colour)
            im.save(os.path.join(OUT, name + ".webp"), quality=90, method=6)
            print(name, im.size)


if __name__ == "__main__":
    main()
