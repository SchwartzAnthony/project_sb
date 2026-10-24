"""Koch's transformation faces cut like the Head Coach's (24 Oct 2026).

Anthony: the Bergmaennlein and his silhouette in the tutorial text box get the
same cut and spot as the Head Coach. The whole running gnome
(art_source/story/*_full.png) is scaled down and cut at the shorts, on the
coach's 720x810 canvas: hat top at 200 (coach's hair starts at 248), body
standing on the bottom edge, centred.

    python3 tools/art/koch_transform_busts.py
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CANVAS = (720, 810)
SCALE = 0.85      # gnome's face ends up near the coach's size
TOP = 200         # where the hat tip sits on the canvas
CENTRE_X = 517    # middle of the gnome, fist to fist, in the full picture

for name in ["koch_bergmaennlein_side", "koch_silhouette_side"]:
    full = Image.open(ROOT / "art_source/story" / f"{name}_full.png").convert("RGBA")
    small = full.resize((round(full.width * SCALE), round(full.height * SCALE)), Image.LANCZOS)
    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    out.paste(small, (round(CANVAS[0] / 2 - CENTRE_X * SCALE), TOP), small)
    out.save(ROOT / "assets/story/portraits" / f"{name}.png")
    print(name, out.getchannel("A").getbbox())
