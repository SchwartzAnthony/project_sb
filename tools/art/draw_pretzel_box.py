"""Draws the gold "look here" box: a whole inked pretzel in each corner.

Free, no AI: the pretzel is one rope drawn along a spline with thick black
ink, flat baked colours and salt, at 4x and shrunk so the lines stay crisp.
Used by the duel highlight and the tutorial (Tuning.csv duel_hl_box_art).

    python3 tools/art/draw_pretzel_box.py
"""
import math, random
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/ui/duel/duel_box_ink.png"
SS = 4                      # supersample
PRETZEL = 96                # pretzel width on screen (1920 x 1080)
MARGIN = 88                 # Tuning duel_hl_box_margin
SIZE = MARGIN * 2 + 8       # texture is square; the middle stretches

INK = (20, 14, 10, 255)
DOUGH = (176, 98, 34, 255)      # baked crust
DOUGH_DARK = (122, 60, 20, 255)
DOUGH_LIGHT = (250, 199, 41, 255)  # duel_hl_colour gold on the top
SALT = (255, 252, 240, 255)

# One rope, in pretzel units (about -1..1), y down. It starts on the
# right of the belly, runs up into the twist, round the left lobe, the
# belly and the right lobe, back through the twist, and ends on the left.
PTS = [(0.66, 0.50), (0.36, 0.22), (0.0, -0.02), (-0.24, -0.26),
       (-0.42, -0.60), (-0.74, -0.70), (-0.98, -0.40), (-0.96, 0.10),
       (-0.66, 0.52), (0.0, 0.70), (0.66, 0.52), (0.96, 0.10),
       (0.98, -0.40), (0.74, -0.70), (0.42, -0.60), (0.24, -0.26),
       (0.0, -0.02), (-0.36, 0.22), (-0.66, 0.50)]


def spline(pts, steps=40):
    out = []
    p = [pts[0]] + pts + [pts[-1]]
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t
                       + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                       + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3)
                       for k in range(2)))
    out.append(pts[-1])
    return out


def stroke(d, path, width, colour, off=(0, 0)):
    r = width / 2
    for (x, y) in path:
        x += off[0]; y += off[1]
        d.ellipse((x - r, y - r, x + r, y + r), fill=colour)


def draw_pretzel(px):
    """A pretzel `px` screen pixels wide, at SS x, on its own canvas."""
    rnd = random.Random(7)
    big = px * SS
    pad = int(big * 0.12)
    img = Image.new("RGBA", (big + pad * 2, int(big * 0.9) + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    scale = big / 2.1
    cx, cy = img.width / 2, img.height / 2 + big * 0.02
    path = [(cx + x * scale, cy + y * scale) for x, y in spline(PTS)]
    # A little wobble, so the line looks inked by hand, not plotted.
    path = [(x + math.sin(i * 0.11) * SS * 0.35, y + math.cos(i * 0.08) * SS * 0.35)
            for i, (x, y) in enumerate(path)]
    rope = 0.27 * scale
    ink = 3.2 * SS * px / 70

    n = len(path)
    seg = n // (len(PTS) - 1)
    first_end = path[: seg * 2 + 1]           # right end up into the twist
    body = path[seg * 2: n - seg * 2]
    last_end = path[n - seg * 2 - 1:]          # twist down to the left end

    def piece(part, trim_start, trim_end):
        o = part[trim_start: len(part) - trim_end]
        stroke(d, o, rope + ink * 2, INK)
        stroke(d, part, rope, DOUGH_DARK)
        stroke(d, part, rope * 0.72, DOUGH, off=(-rope * 0.08, -rope * 0.1))
        stroke(d, part, rope * 0.22, DOUGH_LIGHT, off=(-rope * 0.2, -rope * 0.24))

    # Body first, then each end lies over the belly and the twist.
    piece(body, 0, 0)
    piece(first_end, 0, 6)
    piece(last_end, 6, 0)
    # Coarse salt on the crust.
    for i in range(0, n, 9):
        if rnd.random() < 0.55:
            continue
        x, y = path[i]
        x += rnd.uniform(-1, 1) * rope * 0.15
        y += rnd.uniform(-1, 1) * rope * 0.15
        s = rope * rnd.uniform(0.12, 0.18)
        a = rnd.uniform(0, math.pi)
        poly = [(x + math.cos(a + k * 1.7) * s * rnd.uniform(0.8, 1.2),
                 y + math.sin(a + k * 1.7) * s * rnd.uniform(0.8, 1.2)) for k in range(4)]
        d.polygon(poly, fill=SALT, outline=INK, width=max(1, int(SS * 0.9)))
    return img.crop(img.getbbox())


def main():
    base = draw_pretzel(PRETZEL)
    tex = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    room = MARGIN * SS
    # Upright in every corner, leaning out a little: left ones lean left.
    corners = {}
    for rx in (0, 1):
        p = base.rotate(15 if rx == 0 else -15, resample=Image.BICUBIC, expand=True)
        p = p.crop(p.getbbox())
        fit = min(1.0, room / max(p.size))
        p = p.resize((int(p.width * fit), int(p.height * fit)), Image.LANCZOS)
        corners[(rx, 0)] = p
        corners[(rx, 1)] = p
    for (rx, ry), im in corners.items():
        x = (room - im.width) // 2 if rx == 0 else tex.width - room + (room - im.width) // 2
        y = (room - im.height) // 2 if ry == 0 else tex.height - room + (room - im.height) // 2
        tex.alpha_composite(im, (x, y))
    tex = tex.resize((SIZE, SIZE), Image.LANCZOS)
    tex.save(OUT)
    print("wrote", OUT, tex.size)


if __name__ == "__main__":
    main()
