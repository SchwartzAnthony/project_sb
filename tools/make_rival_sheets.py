#!/usr/bin/env python3
# =============================================================
#  THE RIVALS IN MANY LOOKS  (Anthony, 24 Oct 2026: "Make the rivals also
#  diverse please not just one player type but a variety like our team")
#
#      python3 tools/make_rival_sheets.py
#
#  The Rivals wear the Club's own drawn players (every body, hair and skin
#  tone of the men, and the five women) with the red of the Club kit turned
#  into the Rivals' blue, so they look as varied as your side but never like
#  it. Reads the finished pitch sheets in assets/players/pitch/ and writes:
#
#    drawn_rival_<look>_<tone>.webp        the men     (cut like drawn_*)
#    drawn_class_rival_<woman>.webp        the women   (cut like drawn_class_*)
#
#  The big duel sheets in assets/players/duel/ get the same treatment, under
#  the same names, so the Rivals are sharp in the duel too.
#
#  Only strongly red pixels change (shirt, socks, trim); skin, ginger hair,
#  white shorts and the ink stay as drawn. Change RIVAL_HUE / the strengths
#  below and run it again. At the end it prints the two Pitch Sheet lists for
#  data/PitchSprites.csv (rows Rivals and class_Rivals_female.png).
# =============================================================
import glob
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PITCH = os.path.join(HERE, "assets", "players", "pitch")
DUEL = os.path.join(HERE, "assets", "players", "duel")      # the big duel sheets, same names
MEN = ("fat_afro", "muscular_quiff", "skinny_mullet", "thomas")
WOMEN = ("woman_afro_puffs", "woman_blonde_ponytail", "woman_bob", "woman_ginger", "woman_plaits")
RIVAL_HUE = 207 / 360.0            # the blue of the Rival man's shorts (7, 94, 145)
SATURATION = 0.85                  # of the old red's saturation
DARKEN = 0.72                      # blue reads darker than red at the same brightness
RED_MAX_HUE = 16 / 360.0           # kit red reaches this far toward orange (the women's socks)
RED_MIN_HUE = 335 / 360.0          # ...and this far toward pink
RED_MIN_SAT = 0.42


def to_rival(im):
    a = np.asarray(im.convert("RGBA")).copy()
    hsv = np.asarray(im.convert("RGB").convert("HSV")).astype(np.float32) / 255.0
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    red = ((h <= RED_MAX_HUE) | (h >= RED_MIN_HUE)) & (s >= RED_MIN_SAT) & (a[..., 3] > 0)
    # Soft at the edge of the kit, so the ink line keeps its anti-aliasing.
    weight = np.clip((s - RED_MIN_SAT) / 0.15, 0, 1) * red
    new = np.dstack([np.full_like(h, RIVAL_HUE), s * SATURATION, v * DARKEN])
    rgb = np.asarray(Image.fromarray((new * 255).astype(np.uint8), "HSV").convert("RGB")).astype(np.float32)
    old = a[..., :3].astype(np.float32)
    w = weight[..., None]
    a[..., :3] = (old * (1 - w) + rgb * w).round().astype(np.uint8)
    return Image.fromarray(a, "RGBA")


def rival(source, name):
    """The pitch sheet and its duel sheet, if there is one."""
    for folder in (PITCH, DUEL):
        path = os.path.join(folder, source)
        if os.path.exists(path):
            to_rival(Image.open(path)).save(os.path.join(folder, name), quality=90, method=6)
            print(os.path.relpath(os.path.join(folder, name), HERE))


def main():
    from multiprocessing import Pool
    men, women, jobs = [], [], []
    for look in MEN:
        for path in sorted(glob.glob(os.path.join(PITCH, "drawn_%s_*.webp" % look))):
            if os.path.basename(path).startswith("drawn_rival_"):
                continue
            name = "drawn_rival_" + os.path.basename(path)[len("drawn_"):]
            jobs.append((os.path.basename(path), name))
            men.append(name)
    for look in WOMEN:
        source = "drawn_class_%s.webp" % look
        if os.path.exists(os.path.join(PITCH, source)):
            name = "drawn_class_rival_%s.webp" % look
            jobs.append((source, name))
            women.append(name)
    with Pool() as pool:
        pool.starmap(rival, jobs)
    print("Rivals (men):\n" + "|".join(["drawn_class_rival_man_stubble.webp"] + men))
    print("\nclass_Rivals_female.png (women):\n" + "|".join(women))


if __name__ == "__main__":
    main()
