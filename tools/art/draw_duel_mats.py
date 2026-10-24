"""Draws the start of a duel (Anthony's pick B, 24 Oct 2026): the backs of the
two beer mats that crash together, and the yellow comic burst they make.

Free, no AI: cut from the beer mat card frame (assets/cards/beermat_frame.webp).
The blue-white diamond border and the wooden plank are kept, the inside is
cream cardboard with a beer ring, and a big bottle cap sits in the middle. The
words (TIER, the numeral, KRACH!) are NOT drawn here; the game writes them in
its own font so every tier and language uses the same two pictures.

    mat_back_attack.png   red ribbon round the edge (the attacking side)
    mat_back_defend.png   blue ribbon (the defending side)
    clash_burst.png       the yellow burst with ink speed lines

    python3 tools/art/draw_duel_mats.py
"""
import math, random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/ui/duel"
FRAME = ROOT / "assets/cards/beermat_frame.webp"
INK = (25, 17, 10, 255)
PIN = (196, 40, 36, 255)
# The same cloth colours as the ATTACKING / DEFENDING flags (side_banner.gd).
ATTACK = (214, 51, 33, 255)
DEFEND = (36, 105, 196, 255)
MAT_W, MAT_H = 600, 900          # saved size; shown at Tuning duel_clash_mat_height


def mat_back(ribbon):
    frame = Image.open(FRAME).convert("RGBA")
    b = frame.copy()
    cream = frame.crop((140, 1150, 560, 1300)).resize((930, 1250), Image.LANCZOS)
    m = Image.new("L", cream.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, cream.width - 1, cream.height - 1), 44, fill=255)
    b.paste(cream, (47, 88), m)
    d = ImageDraw.Draw(b)
    d.rounded_rectangle((47, 88, 976, 1337), 44, outline=INK, width=6)
    d.rounded_rectangle((80, 120, 944, 1305), 34, outline=PIN, width=9)
    d.rounded_rectangle((98, 138, 926, 1287), 28, outline=PIN, width=3)
    ring = Image.new("RGBA", b.size, (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse((560, 760, 900, 1100), outline=(150, 100, 40, 70), width=22)
    b.alpha_composite(ring.filter(ImageFilter.GaussianBlur(5)))
    # The bottle cap from the front of the card, three times the size.
    cap = frame.crop((512 - 110, 998 - 110, 512 + 110, 998 + 110))
    cm = Image.new("L", cap.size, 0)
    ImageDraw.Draw(cm).ellipse((14, 14, 206, 206), fill=255)
    cap.putalpha(cm)
    cap = cap.resize((600, 600), Image.LANCZOS)
    b.alpha_composite(cap, (512 - 300, 700 - 300))
    # Rounded corners, then the side's ribbon and an ink edge round it all.
    mask = Image.new("L", b.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, b.width - 1, b.height - 1), 60, fill=255)
    b.putalpha(mask)
    d = ImageDraw.Draw(b)
    d.rounded_rectangle((6, 6, b.width - 7, b.height - 7), 60, outline=ribbon, width=26)
    d.rounded_rectangle((2, 2, b.width - 3, b.height - 3), 62, outline=INK, width=6)
    return b.resize((MAT_W, MAT_H), Image.LANCZOS)


def burst():
    SS = 3
    w, h = 900 * SS, 640 * SS
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = w / 2, h / 2
    rng = random.Random(1860)
    # Ink speed lines flying out from behind the burst.
    for _ in range(26):
        a = rng.uniform(0, math.tau)
        r0, r1 = rng.uniform(250, 300) * SS, rng.uniform(380, 445) * SS
        d.line((cx + math.cos(a) * r0, cy + math.sin(a) * r0 * 0.68,
                cx + math.cos(a) * r1, cy + math.sin(a) * r1 * 0.68), fill=INK, width=6 * SS)
    # The burst: a jagged star, wider than tall, thick ink edge.
    spikes, r = 14, 215 * SS
    pts = []
    for i in range(spikes * 2):
        a = i * math.pi / spikes
        rr = r * (1.0 if i % 2 == 0 else 0.6) * rng.uniform(0.86, 1.12)
        pts.append((cx + math.cos(a) * rr * 1.3, cy + math.sin(a) * rr))
    d.polygon(pts, fill=INK)
    inner = [(cx + (x - cx) * 0.94, cy + (y - cy) * 0.92) for x, y in pts]
    d.polygon(inner, fill=(255, 214, 40, 255))
    # A paler middle so the words stand out, like a printed comic.
    mid = [(cx + (x - cx) * 0.62, cy + (y - cy) * 0.6) for x, y in pts]
    d.polygon(mid, fill=(255, 236, 120, 255))
    return im.resize((900, 640), Image.LANCZOS)


if __name__ == "__main__":
    mat_back(ATTACK).save(OUT / "mat_back_attack.png")
    mat_back(DEFEND).save(OUT / "mat_back_defend.png")
    burst().save(OUT / "clash_burst.png")
    print("wrote", OUT / "mat_back_attack.png", OUT / "mat_back_defend.png", OUT / "clash_burst.png")
