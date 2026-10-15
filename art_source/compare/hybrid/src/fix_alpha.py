# PixelLab image_to_pixelart returned the cut-outs on a flat grey background.
# This puts the transparency back: it takes the alpha of the OpenAI cut-out
# (cropped the same way as make_src.py), scales it to the PixelLab size with
# hard edges and applies it. The untouched PixelLab results are kept as
# <name>_raw.png.
#
# It also makes a STAND-IN bg.png (NOT PixelLab): the OpenAI bg pixelated by
# tools/pixelate.py the same way compose.py "paint" does, because the bg
# could not be sent to PixelLab (see prompts.txt).
import os, shutil, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SET = os.path.dirname(HERE)
SRC = os.path.join(SET, "..", "openai")
ROOT = os.path.abspath(os.path.join(SET, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))

for n in ["brewery", "tent", "crowd", "brawl", "sign", "hero"]:
    out = os.path.join(SET, n + ".png")
    raw = os.path.join(SET, n + "_raw.png")
    if not os.path.exists(raw):
        shutil.copy(out, raw)
    px = Image.open(raw).convert("RGBA")
    src = Image.open(os.path.join(SRC, n + ".png")).convert("RGBA")
    src = src.crop(src.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox())
    mask = src.getchannel("A").resize(px.size, Image.BOX).point(lambda a: 255 if a > 127 else 0)
    px.putalpha(mask)
    px.save(out)
    print(n, px.size)

if "--bg" in sys.argv:
    import pixelate as pxl
    small = pxl.pixelate(os.path.join(SRC, "bg.png"), 540, 32, False, 45, False,
                         smooth=7, aspect="16:9", neutral=0.5)
    small.save(os.path.join(SET, "bg.png"))
    print("bg stand-in", small.size)
