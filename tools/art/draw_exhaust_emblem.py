"""Draws the EXHAUST ZONE marker in our rough comic look (25 Oct 2026).

Anthony 24 Oct: "redraw the Exhaust Zone emblem, it doesn't look like our art
style, and make it half as big". The old pieces were a clean vector beer mat
and an engraved glass Maß. These are drawn free, no AI, the same way as the
highlight pretzel (draw_pretzel_box.py): thick black ink wobbled by hand, flat
bold colours, at 4x and shrunk so the lines stay crisp.

    python3 tools/art/draw_exhaust_emblem.py

Writes assets/ui/exhaust/ (the names the game already reads):
  coaster.png   a worn cardboard beer mat, blue-white diamonds round the rim
  mug.png       an empty Maß, foam dregs left in it (a spent card)
  badge.png     the red count disc
  *_aura.png    a white glow mask behind each piece (the game tints it)
The game's size is Tuning.csv exhaust_icon_scale (0.5 = half).
"""
import math, random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/ui/exhaust"
SS = 4

INK = (20, 14, 10, 255)
CARD = (238, 222, 184, 255)       # cardboard
CARD_DARK = (214, 190, 142, 255)
BLUE = (28, 92, 186, 255)
WHITE = (252, 248, 236, 255)
GLASS = (196, 224, 232, 255)
GLASS_DARK = (138, 182, 200, 255)
GLASS_INSIDE = (92, 132, 150, 255)
FOAM = (255, 252, 240, 255)
BEER = (236, 176, 44, 255)
RED = (204, 38, 30, 255)
RED_DARK = (150, 22, 18, 255)

rnd = random.Random(11)


def wobble(path, amount, seed):
    """Nudge a line so it looks inked by hand, not plotted."""
    r = random.Random(seed)
    a, b = r.uniform(0, 6), r.uniform(0, 6)
    return [(x + math.sin(i * 0.13 + a) * amount, y + math.cos(i * 0.09 + b) * amount)
            for i, (x, y) in enumerate(path)]


def ring(cx, cy, rx, ry, n=240, a0=0.0, a1=math.tau):
    return [(cx + rx * math.cos(a0 + (a1 - a0) * i / n), cy + ry * math.sin(a0 + (a1 - a0) * i / n))
            for i in range(n + 1)]


def ink_line(d, path, width, colour=INK):
    r = width / 2
    for (x, y) in path:
        d.ellipse((x - r, y - r, x + r, y + r), fill=colour)
    for p, q in zip(path, path[1:]):
        d.line([p, q], fill=colour, width=int(width))


def aura(im, reach, soft):
    pad = reach + soft * 2
    a = im.split()[3].point(lambda v: 255 if v > 40 else 0)
    big = Image.new("L", (im.width + pad * 2, im.height + pad * 2), 0)
    big.paste(a, (pad, pad))
    big = big.filter(ImageFilter.MaxFilter(reach * 2 + 1)).filter(ImageFilter.GaussianBlur(soft))
    out = Image.new("RGBA", big.size, (255, 255, 255, 0))
    out.putalpha(big)
    return out


def save(big, name, size, reach=10, soft=8):
    im = big.resize(size, Image.LANCZOS)
    im.save(OUT / f"{name}.png")
    aura(im, reach, soft).save(OUT / f"{name}_aura.png")
    print("wrote", name, im.size)


# ---------------- the beer mat ----------------
def coaster():
    D = 200 * SS
    img = Image.new("RGBA", (D, D), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = D / 2
    r_out, r_in = c - 9 * SS, c - 44 * SS
    edge = wobble(ring(c, c, r_out, r_out * 0.985), 1.6 * SS, 1)
    d.polygon(edge, fill=CARD)
    # Blue-white diamonds round the rim, each a little crooked, cut by hand.
    cells = 22
    for k in range(cells):
        a = math.tau * k / cells + rnd.uniform(-0.02, 0.02)
        mid = (r_out + r_in) / 2 + rnd.uniform(-1, 1) * SS
        h = (r_out - r_in) * 0.40
        w = math.pi * mid / cells * 0.80
        pts = []
        for (u, v) in [(0, -h), (w, 0), (0, h), (-w, 0)]:
            # u along the circle, v across it
            x = c + (mid + v) * math.cos(a) - u * math.sin(a)
            y = c + (mid + v) * math.sin(a) + u * math.cos(a)
            pts.append((x, y))
        d.polygon(pts, fill=BLUE if k % 2 == 0 else WHITE)
        ink_line(d, pts + [pts[0]], 2.4 * SS)
    # The cardboard middle, a darker beer ring stain where a mug once stood.
    mid_ring = wobble(ring(c, c, r_in, r_in), 1.2 * SS, 2)
    d.polygon(mid_ring, fill=CARD)
    stain = wobble(ring(c + 4 * SS, c + 3 * SS, r_in * 0.70, r_in * 0.68, a0=0.5, a1=math.tau - 0.4), 1.5 * SS, 3)
    ink_line(d, stain, 7 * SS, CARD_DARK)
    ink_line(d, mid_ring, 4.5 * SS)
    ink_line(d, edge, 7 * SS)
    # A nick in the rim: it's been chewed at.
    nx, ny = c + r_out * math.cos(-0.7), c + r_out * math.sin(-0.7)
    d.pieslice((nx - 9 * SS, ny - 9 * SS, nx + 9 * SS, ny + 9 * SS), 0, 360, fill=(0, 0, 0, 0))
    ink_line(d, ring(nx, ny, 9 * SS, 9 * SS, 60, math.pi * 0.55, math.pi * 1.45), 5 * SS)
    save(img, "coaster", (200, 200))


# ---------------- the empty Maß ----------------
def mug():
    W, H = 120 * SS, 222 * SS          # aspect 0.54, what the game expects
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = SS
    left, right = 10 * s, 84 * s       # the glass body
    top, bottom = 40 * s, 212 * s
    # Handle first, so the glass lies over its ends.
    handle_out = wobble(ring(right, 118 * s, 30 * s, 52 * s, 120, -math.pi / 2, math.pi / 2), 0.8 * s, 4)
    ink_line(d, handle_out, 22 * s)
    ink_line(d, handle_out, 11 * s, GLASS_DARK)
    # The glass: a slightly bellied, flat-bottomed Maß.
    body = [(left + 3 * s, top), (right - 3 * s, top), (right, top + 60 * s), (right - 1 * s, bottom - 10 * s),
            (right - 8 * s, bottom), (left + 8 * s, bottom), (left + 1 * s, bottom - 10 * s), (left, top + 60 * s)]
    outline = []
    for p, q in zip(body, body[1:] + body[:1]):
        for t in range(20):
            outline.append((p[0] + (q[0] - p[0]) * t / 20, p[1] + (q[1] - p[1]) * t / 20))
    outline = wobble(outline, 0.9 * s, 5)
    d.polygon(outline, fill=GLASS)
    # Shade down the right, the thick glass base.
    d.polygon([(right - 22 * s, top + 4 * s), (right - 3 * s, top + 4 * s), (right - 1 * s, bottom - 12 * s),
               (right - 9 * s, bottom - 2 * s), (right - 22 * s, bottom - 2 * s)], fill=GLASS_DARK)
    d.rectangle((left + 6 * s, bottom - 24 * s, right - 6 * s, bottom - 3 * s), fill=GLASS_DARK)
    ink_line(d, wobble([(left + 6 * s, bottom - 24 * s), (right - 6 * s, bottom - 24 * s)], 0.6 * s, 6), 3.5 * s)
    # Dimples: three rows of fat ovals, drawn in thin dark glass lines.
    for row in range(3):
        for col in range(3):
            x = left + (16 + col * 25) * s
            y = top + (34 + row * 42) * s
            ov = wobble(ring(x, y, 9 * s, 15 * s, 50), 0.5 * s, 10 + row * 3 + col)
            ink_line(d, ov, 3 * s, GLASS_INSIDE)
    # A white shine down the left: two quick strokes.
    ink_line(d, wobble([(left + 9 * s, top + 16 * s + i * s) for i in range(0, 120, 2)], 0.4 * s, 7), 6 * s, WHITE)
    ink_line(d, wobble([(left + 19 * s, top + 26 * s + i * s) for i in range(0, 40, 2)], 0.4 * s, 8), 4 * s, WHITE)
    # The dregs: a puddle of beer at the bottom and foam left on the inside.
    d.rectangle((left + 7 * s, bottom - 38 * s, right - 7 * s, bottom - 26 * s), fill=BEER)
    ink_line(d, wobble([(left + 6 * s, bottom - 38 * s), (right - 6 * s, bottom - 38 * s)], 0.6 * s, 9), 3 * s)
    # Open mouth: the dark inside, a foam ring dribbling down.
    mouth = wobble(ring((left + right) / 2, top, (right - left) / 2 - 2 * s, 11 * s), 0.6 * s, 12)
    d.polygon(mouth, fill=GLASS_INSIDE)
    for i, x in enumerate(range(int(left + 6 * s), int(right - 6 * s), int(13 * s))):
        drip = (12 + rnd.randint(0, 16)) * s
        d.rounded_rectangle((x, top, x + 11 * s, top + drip), radius=5 * s, fill=FOAM, outline=INK, width=int(2.4 * s))
    ink_line(d, mouth, 5 * s)
    ink_line(d, outline + outline[:1], 7 * s)
    save(img, "mug", (120, 222))


# ---------------- the count disc ----------------
def badge():
    B = 72 * SS
    img = Image.new("RGBA", (B, B), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = B / 2
    outer = wobble(ring(c, c, c - 5 * SS, c - 5.5 * SS), 0.25 * SS, 20)
    d.polygon(outer, fill=RED)
    d.pieslice((c - 22 * SS, c - 10 * SS, c + 30 * SS, c + 30 * SS), 20, 160, fill=RED_DARK)
    ink_line(d, outer, 6 * SS)
    save(img, "badge", (72, 72), 6, 4)


if __name__ == "__main__":
    coaster()
    mug()
    badge()
