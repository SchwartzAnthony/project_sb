#!/usr/bin/env python3
# =============================================================
#  DUEL BACKGROUNDS  (Anthony, 24 Oct 2026: "their background is the same
#  ... have it be random between 8 different backgrounds please")
#
#      python3 tools/make_duel_backgrounds.py
#
#  Free crops of the drawn village pictures already in the game, each a
#  different spot round the pitch, cut to the duel card's shape (760 x 430)
#  so they are drawn at about their own size, not blown up. Writes
#  assets/ui/duel/fields/<name>.png. data/DuelBackgrounds.csv lists the
#  pictures the duel picks from at random.
# =============================================================
import os

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "assets/ui/duel/fields")
SIZE = (760, 430)
# name: (picture, left, top, width) - the height follows the card's shape
CROPS = {
    "dorms_wall": ("assets/base/village.png", 0, 300, 900),
    "brewery_goal": ("assets/base/village.png", 300, 330, 940),
    "goal_corner": ("assets/base/village.png", 636, 330, 900),
    "meadow": ("assets/ui/anim_window/meadow.png", 0, 50, 840),
    "church_goal": ("assets/ui/shootout/goal_stage.png", 150, 0, 830),
    "far_village": ("assets/menu/village/title_village_r191_soft.png", 0, 0, 1536),
    "whole_village": ("assets/loading/drawn/village.png", 0, 0, 1536),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (path, x, y, w) in CROPS.items():
        im = Image.open(os.path.join(HERE, path)).convert("RGB")
        h = min(int(w * SIZE[1] / SIZE[0]), im.height - y)
        im.crop((x, y, x + w, y + h)).resize(SIZE, Image.LANCZOS).save(os.path.join(OUT, name + ".png"))
        print(name)


if __name__ == "__main__":
    main()
