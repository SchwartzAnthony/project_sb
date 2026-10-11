#!/usr/bin/env python3
# =============================================================
#  THE BASE'S FLAG BANNERS  (round AN)
#
#      ~/.venvs/sturmball/bin/python tools/make_banners.py
#
#  Every top-row banner is the SAME banner (Anthony): one cloth, one rod -
#  only the emblem and the name differ. Three kinds of PixelLab part:
#
#      art_source/pixellab/banners/cloth.png            the one blank cloth
#      art_source/pixellab/banners/rod.png              the one wooden rod
#      art_source/pixellab/banners/emblems/<name>.png   one emblem per door
#
#  and this writes, for every emblem:
#
#      assets/ui/banners/<name>.png                     what the game shows
#      art_source/aseprite/banners/<name>.aseprite      cloth, emblem, rod
#                                                       as three layers
#
#  The finished picture is screen size (drawn 1:1): cloth and rod x3, the
#  emblem x2 so it sits inside the stitched border. The name is NOT in the
#  picture - the game stitches it on (MenuSupport.banner_button), shrinking
#  the thread until the longest word fits the cloth.
#
#  A banner may have its OWN cloth: art_source/pixellab/banners/cloths/
#  <name>.png is used instead of the shared one when it exists (the torn
#  Conquests flag, tools/tear_cloth.py).
#
#  New door: make its emblem in PixelLab (32 x 32, see ArtOrders), save it
#  in emblems/, run this. The game finds it by name (base_screen.gd _exit).
# =============================================================

import glob
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "tools"))
from make_aseprite import write_aseprite  # noqa: E402

SRC = os.path.join(HERE, "art_source", "pixellab", "banners")
OUT = os.path.join(HERE, "assets", "ui", "banners")
ASE = os.path.join(HERE, "art_source", "aseprite", "banners")
CLOTH_SCALE = 3     # cloth and rod
EMBLEM_SCALE = 2    # the emblem, so it fits inside the border
ROD_DOWN = 3        # cloth pixels from the top of the loops to the rod
EMBLEM_TOP = 9      # cloth pixels from the top of the loops to the emblem


def part(path, scale):
    img = Image.open(path).convert("RGBA")
    img = img.crop(img.getbbox())
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def main():
    cloth = part(os.path.join(SRC, "cloth.png"), CLOTH_SCALE)
    rod = part(os.path.join(SRC, "rod.png"), CLOTH_SCALE)
    w = max(cloth.width, rod.width)
    h = cloth.height
    cloth_at = ((w - cloth.width) // 2, 0)
    rod_at = ((w - rod.width) // 2, ROD_DOWN * CLOTH_SCALE)
    for path in sorted(glob.glob(os.path.join(SRC, "emblems", "*.png"))):
        name = os.path.splitext(os.path.basename(path))[0]
        emblem = part(path, EMBLEM_SCALE)
        emblem_at = ((w - emblem.width) // 2, EMBLEM_TOP * CLOTH_SCALE)
        own = os.path.join(SRC, "cloths", name + ".png")
        this_cloth, cloth_layer = cloth, "cloth (shared)"
        if os.path.exists(own):
            this_cloth, cloth_layer = part(own, CLOTH_SCALE), "cloth (" + name + ")"
        sheet = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        for img, at in ((this_cloth, cloth_at), (emblem, emblem_at), (rod, rod_at)):
            sheet.alpha_composite(img, at)
        sheet.save(os.path.join(OUT, name + ".png"))
        write_aseprite(os.path.join(ASE, name + ".aseprite"), w, h,
                       [(cloth_layer, this_cloth, cloth_at[0], cloth_at[1]),
                        ("emblem", emblem, emblem_at[0], emblem_at[1]),
                        ("rod (shared)", rod, rod_at[0], rod_at[1])])
        print("wrote %s  (%d x %d)" % (name, w, h))


if __name__ == "__main__":
    main()
