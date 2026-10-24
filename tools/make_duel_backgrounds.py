#!/usr/bin/env python3
# =============================================================
#  DUEL BACKGROUNDS  (Anthony, 24 Oct 2026: "random between 8 different
#  backgrounds" ... "It should be from around the map we use")
#
#      python3 tools/make_duel_backgrounds.py [views folder]
#
#  Eight eye-level views from the pitch of our village (the map the match
#  is played on, art_source/drawn_pitch/village_from_above.png), one per
#  side and corner: north is the base picture, the other seven were drawn
#  by Sunburst on 24 Oct (/mnt/project-files/duel_look/map_views/,
#  mv<n>_<side>.png). Cut to the duel card's shape (760 x 430) so they are
#  drawn at about their own size. Writes assets/ui/duel/fields/map_<side>.png;
#  data/DuelBackgrounds.csv lists the pictures the duel picks from.
# =============================================================
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else "/mnt/project-files/duel_look/map_views"
OUT = os.path.join(HERE, "assets/ui/duel/fields")
SIZE = (760, 430)
VIEWS = {
    "north": os.path.join(HERE, "assets/base/village.png"),
    "west": "mv2_west.png",
    "east": "mv3_east.png",
    "south": "mv4_south.png",
    "northwest": "mv5_northwest.png",
    "northeast": "mv6_northeast.png",
    "southwest": "mv7_southwest.png",
    "southeast": "mv8_southeast.png",
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for side, path in VIEWS.items():
        im = Image.open(os.path.join(SRC, path)).convert("RGB")
        # Trim to the card's shape from the top (keep all the grass).
        h = min(im.height, int(im.width * SIZE[1] / SIZE[0]))
        im.crop((0, im.height - h, im.width, im.height)).resize(SIZE, Image.LANCZOS).save(
            os.path.join(OUT, f"map_{side}.png"))
        print(side)


if __name__ == "__main__":
    main()
