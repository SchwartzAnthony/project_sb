#!/usr/bin/env python3
# =============================================================
#  THE BASE'S FLAG BANNERS  (round AN)
#
#      ~/.venvs/sturmball/bin/python tools/make_banners.py
#
#  Every top-row banner hangs from THE SAME wooden rod (Anthony). So each
#  banner is two PixelLab parts:
#
#      art_source/pixellab/banners/rod.png          the one rod, for all
#      art_source/pixellab/banners/<name>.png       the cloth + emblem
#                                                   (its own rod is cut off)
#
#  and this writes, for every <name>:
#
#      assets/ui/banners/<name>.png                 what the game shows
#      art_source/aseprite/banners/<name>.aseprite  cloth and rod as layers
#
#  New banner: make the cloth in PixelLab, save it in art_source/pixellab/
#  banners/, run this. The game picks it up by name (base_screen.gd _exit).
# =============================================================

import glob
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "tools"))
from make_aseprite import write_aseprite  # noqa: E402

SRC = os.path.join(HERE, "art_source", "pixellab", "banners")
OUT = os.path.join(HERE, "assets", "ui", "banners")
ASE = os.path.join(HERE, "art_source", "aseprite", "banners")
W, H = 48, 64          # the finished banner, rod finials included
ROD_Y = 1              # where the rod's top sits


def cloth_only(img):
    """The cloth from its first full row of blue down: the banner's own rod
    and hanging loops are cut away, so only the shared rod shows."""
    a = np.array(img)
    r, g, b, al = (a[..., i].astype(int) for i in range(4))
    blue = (al > 25) & (b > r + 30)
    rows = blue.sum(1)
    top = int(np.argmax(rows > img.width * 0.6))
    a[:top] = 0
    out = Image.fromarray(a)
    return out.crop(out.getbbox())


def main():
    rod = Image.open(os.path.join(SRC, "rod.png")).convert("RGBA")
    rod = rod.crop(rod.getbbox())
    names = [os.path.splitext(os.path.basename(p))[0]
             for p in glob.glob(os.path.join(SRC, "*.png"))]
    for name in sorted(n for n in names if n != "rod"):
        cloth = cloth_only(Image.open(os.path.join(SRC, name + ".png")).convert("RGBA"))
        rod_at = ((W - rod.width) // 2, ROD_Y)
        cloth_at = ((W - cloth.width) // 2, ROD_Y + rod.height // 2)
        sheet = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        sheet.alpha_composite(cloth, cloth_at)
        sheet.alpha_composite(rod, rod_at)
        sheet.save(os.path.join(OUT, name + ".png"))
        write_aseprite(os.path.join(ASE, name + ".aseprite"), W, H,
                       [("cloth", cloth, cloth_at[0], cloth_at[1]),
                        ("rod (shared)", rod, rod_at[0], rod_at[1])])
        print("wrote %s" % name)


if __name__ == "__main__":
    main()
