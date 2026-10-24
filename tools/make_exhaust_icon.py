# Makes the drawn pieces of the EXHAUST ZONE marker (Anthony 23 Oct 2026:
# "cannot see it, it blends in too much"). Free: built from the drawn empty
# Maß of the save screen plus shapes drawn here in thick ink and flat colour.
#
#     python3 tools/make_exhaust_icon.py
#
# Writes assets/ui/exhaust/:
#   mug.png          the empty open Maß (a spent card = an empty mug)
#   coaster.png      a round beer mat with a blue-white diamond rim
#   badge.png        a red count disc with a white ring and ink edge
#   *_aura.png       a white glow mask behind each piece (the game tints it)
import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "exhaust")
os.makedirs(OUT, exist_ok=True)
INK = (25, 17, 10, 255)
BLUE = (31, 102, 196, 255)
WHITE = (250, 246, 236, 255)
CREAM = (244, 230, 196, 255)
RED = (200, 36, 30, 255)
S = 4  # draw big, shrink for smooth ink


def aura(im: Image.Image, reach: int, soft: int) -> Image.Image:
    """A white mask that hugs the drawing, padded so it can spill past it."""
    pad = reach + soft * 2
    a = im.split()[3].point(lambda v: 255 if v > 40 else 0)
    big = Image.new("L", (im.width + pad * 2, im.height + pad * 2), 0)
    big.paste(a, (pad, pad))
    big = big.filter(ImageFilter.MaxFilter(reach * 2 + 1))
    big = big.filter(ImageFilter.GaussianBlur(soft))
    out = Image.new("RGBA", big.size, (255, 255, 255, 0))
    out.putalpha(big)
    return out


def save(im: Image.Image, name: str, reach: int = 10, soft: int = 8) -> None:
    im.save(os.path.join(OUT, name + ".png"))
    aura(im, reach, soft).save(os.path.join(OUT, name + "_aura.png"))
    print(name, im.size)


# --- the empty Maß, cut to its drawing and made smaller ---
mug = Image.open(os.path.join(ROOT, "assets/ui/save/mugs/mug_open_empty.png")).convert("RGBA")
mug = mug.crop(mug.getbbox())
h = 220
mug = mug.resize((round(mug.width * h / mug.height), h), Image.LANCZOS)
save(mug, "mug")

# --- the beer mat: ink edge, ring of blue-white diamonds, cream middle ---
D = 200
big = Image.new("RGBA", (D * S, D * S), (0, 0, 0, 0))
g = ImageDraw.Draw(big)
c = D * S / 2
r_out, r_in = c - 6 * S, c - 40 * S
g.ellipse([c - r_out, c - r_out, c + r_out, c + r_out], fill=WHITE)
cells = 28
for row in range(2):
    ra = r_out - (r_out - r_in) * row / 2
    rb = r_out - (r_out - r_in) * (row + 1) / 2
    for k in range(cells):
        if (k + row) % 2:
            continue
        a0 = 2 * math.pi * k / cells
        a1 = 2 * math.pi * (k + 1) / cells
        pts = []
        for t in range(9):
            a = a0 + (a1 - a0) * t / 8
            pts.append((c + ra * math.cos(a), c + ra * math.sin(a)))
        for t in range(9):
            a = a1 - (a1 - a0) * t / 8
            pts.append((c + rb * math.cos(a), c + rb * math.sin(a)))
        g.polygon(pts, fill=BLUE)
g.ellipse([c - r_in, c - r_in, c + r_in, c + r_in], fill=CREAM, outline=INK, width=4 * S)
g.ellipse([c - r_out, c - r_out, c + r_out, c + r_out], outline=INK, width=6 * S)
coaster = big.resize((D, D), Image.LANCZOS)
save(coaster, "coaster")

# --- the count badge: red disc, white ring, ink edge ---
B = 72
big = Image.new("RGBA", (B * S, B * S), (0, 0, 0, 0))
g = ImageDraw.Draw(big)
e = 3 * S
g.ellipse([e, e, B * S - e, B * S - e], fill=INK)
e2 = e + 4 * S
g.ellipse([e2, e2, B * S - e2, B * S - e2], fill=WHITE)
e3 = e2 + 5 * S
g.ellipse([e3, e3, B * S - e3, B * S - e3], fill=RED, outline=INK, width=2 * S)
save(big.resize((B, B), Image.LANCZOS), "badge", 6, 4)
