"""Draws the Star player's card: the beer mat frame with a gold star where the
bottle cap was (24 Oct, Anthony: "For Star player cards, have the circle be
replaced by a star of the same art style").

Free, no AI. The cap is painted out of the frame first (the blue-white
diamonds are filled in by OpenCV's shift-map inpaint, the red and white
stripes are carried along their own curve), then a fat five-point star is
drawn on top at 4x: thick black ink, gold facets lit from the top left like
the cap's metal, and the cap's own cream middle so the number sits on the
same cardboard as on every other card.

    pip install opencv-contrib-python-headless   (once)
    python3 tools/art/draw_star_cap.py
"""
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "art_source/cards/beermat_frame_r187.png"
OUT = ROOT / "assets/cards/beermat_frame_star.webp"

CX, CY = 512, 998          # middle of the cap (CardFace.csv cap)
CAP_R = 107                # the cap with its ink edge
STAR_OUT = 120             # star tip radius
STAR_IN = 66               # star valley radius
CREAM_R = 47               # the cream middle the number sits on
SS = 4                     # supersample

INK = (20, 14, 10)
GOLD_LIGHT = np.array([255, 238, 160])
GOLD_MID = np.array([226, 170, 54])
GOLD_DARK = np.array([112, 66, 14])

# The centre line of the red stripes inside the cap, measured on the frame
# (x, y from the cap middle). Left halves; the right is the mirror.
UPPER = [(-150, -15), (-130, -23), (-110, -42), (-80, -68), (-50, -91), (-20, -103.5), (0, -112.5)]
LOWER = [(-150, 95.5), (-100, 95.5), (-60, 98), (-30, 116), (-10, 127), (0, 129)]


def dense(points):
    """The polyline (mirrored to a full chevron) sampled every pixel:
    positions, unit directions and normals."""
    full = points + [(-x, y) for x, y in reversed(points[:-1])]
    pos = []
    for (x0, y0), (x1, y1) in zip(full, full[1:]):
        n = max(1, int(math.hypot(x1 - x0, y1 - y0)))
        for i in range(n):
            t = i / n
            pos.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    pos = np.array(pos, float)
    d = np.gradient(pos, axis=0)
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    nrm = np.stack([-d[:, 1], d[:, 0]], 1)
    return pos, nrm


def carry_stripe(src, out, mask, points, half_width):
    """Pixels of the mask close to the stripe get the stripe copied along
    its own curve from just outside the cap (same distance from the line)."""
    pos, nrm = dense(points)
    abs_pos = pos + [CX, CY]
    outside = np.hypot(pos[:, 0], pos[:, 1]) > CAP_R + 6
    ys, xs = np.nonzero(mask)
    for y, x in zip(ys, xs):
        d = np.hypot(abs_pos[:, 0] - x, abs_pos[:, 1] - y)
        i = int(np.argmin(d))
        s = float(np.dot([x, y] - abs_pos[i], nrm[i]))
        if abs(s) > half_width:
            continue
        # Nearest stretch of the same curve that is outside the cap, on the
        # same side of the middle.
        # Nearest stretch of the same curve, on the same side of the middle,
        # where the same distance from the line is clear of the cap.
        left = (x < CX)
        off = pos + nrm * s
        clear = np.hypot(off[:, 0], off[:, 1]) > CAP_R + 8
        cand = np.nonzero(clear & ((pos[:, 0] < 0) == left))[0]
        if len(cand) == 0:
            continue
        j = cand[np.argmin(np.abs(cand - i))]
        sx, sy = abs_pos[j] + nrm[j] * s
        out[y, x] = src[int(round(sy)), int(round(sx))]


def paint_out_cap(frame):
    bgr = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)
    # Only the band between the edelweiss: no flowers to copy from.
    x0, y0, x1, y1 = CX - 175, CY - 150, CX + 175, CY + 150
    crop = bgr[y0:y1, x0:x1].copy()
    keep = np.full(crop.shape[:2], 255, np.uint8)
    cv2.circle(keep, (CX - x0, CY - y0), CAP_R, 0, -1)
    # Leaves and grass are not sources either, so the gaps get diamonds.
    r, g, b = [crop[..., 2 - i].astype(int) for i in range(3)]
    keep[(g > r + 15) & (g > b + 15)] = 0
    # Nor the red stripes (they are carried along their own line below).
    keep[(r > 150) & (g < 110) & (b < 100)] = 0
    keep[r + g + b < 240] = 0           # grass ink and the cap's own rim
    keep = cv2.erode(keep, np.ones((9, 9), np.uint8))
    filled = crop.copy()
    cv2.xphoto.inpaint(crop, keep, filled, cv2.xphoto.INPAINT_SHIFTMAP)
    yy, xx = np.mgrid[0:frame.shape[0], 0:frame.shape[1]]
    hole = np.hypot(xx - CX, yy - CY) <= CAP_R
    out = frame.copy()
    out[y0:y1, x0:x1][hole[y0:y1, x0:x1]] = cv2.cvtColor(filled, cv2.COLOR_BGR2RGB)[hole[y0:y1, x0:x1]]
    carry_stripe(frame, out, hole, UPPER, 22)
    carry_stripe(frame, out, hole, LOWER, 16)
    return out


def star_points(cx, cy, r_out, r_in):
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        r = r_out if k % 2 == 0 else r_in
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def draw_star(frame):
    size = (STAR_OUT + 30) * 2
    big = size * SS
    c = big / 2
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    g = ImageDraw.Draw(layer)
    ink_w = 9 * SS
    # Thick ink outline round the whole star, drawn first so the gold sits
    # inside it.
    pts = star_points(c, c, STAR_OUT * SS, STAR_IN * SS)
    g.polygon(pts, fill=INK + (255,))
    g.line(pts + pts[:1], fill=INK + (255,), width=ink_w * 2, joint="curve")
    # Gold facets: each point is two triangles (tip, valley, middle), lit
    # from the top left like the cap.
    light = np.array([-0.6, -0.8])
    for k in range(10):
        a, b = pts[k], pts[(k + 1) % 10]
        mid = ((a[0] + b[0]) / 2 - c, (a[1] + b[1]) / 2 - c)
        n = np.array(mid) / (np.linalg.norm(mid) + 1e-6)
        lit = float(np.dot(n, light))          # -1 .. 1
        # Alternate sides of each point catch the light differently.
        lit += 0.25 if k % 2 == 0 else -0.25
        t = (lit + 1) / 2
        col = GOLD_DARK + (GOLD_MID - GOLD_DARK) * min(1, t * 2) if t < 0.5 else \
            GOLD_MID + (GOLD_LIGHT - GOLD_MID) * (t - 0.5) * 2
        g.polygon([a, b, (c, c)], fill=tuple(int(v) for v in col) + (255,))
    # Ink ridges from the middle to each tip and valley.
    for k, p in enumerate(pts):
        w = (3 if k % 2 == 0 else 2) * SS
        g.line([(c, c), p], fill=INK + (255,), width=w)
    # The cream middle: a dark gold rim, ink line, then the cap's cardboard.
    rim = (CREAM_R + 9) * SS
    g.ellipse([c - rim - 3 * SS, c - rim - 3 * SS, c + rim + 3 * SS, c + rim + 3 * SS], fill=INK + (255,))
    g.ellipse([c - rim, c - rim, c + rim, c + rim], fill=tuple(GOLD_MID) + (255,))
    g.ellipse([c - rim, c - rim, c + rim - 4 * SS, c + rim - 4 * SS], fill=tuple(GOLD_LIGHT) + (255,))
    g.ellipse([c - rim + 4 * SS, c - rim + 4 * SS, c + rim, c + rim], fill=tuple(GOLD_DARK) + (255,))
    g.ellipse([c - rim + 3 * SS, c - rim + 3 * SS, c + rim - 3 * SS, c + rim - 3 * SS], fill=tuple(GOLD_MID) + (255,))
    cr = CREAM_R * SS
    g.ellipse([c - cr - 2 * SS, c - cr - 2 * SS, c + cr + 2 * SS, c + cr + 2 * SS], fill=INK + (255,))
    star = layer.resize((size, size), Image.LANCZOS)

    # Paste the cap's own cream middle into the hole.
    src = Image.fromarray(np.asarray(Image.open(SRC).convert("RGB")))
    cream = src.crop((CX - CREAM_R, CY - CREAM_R, CX + CREAM_R, CY + CREAM_R))
    disc = Image.new("L", (CREAM_R * 2 * SS,) * 2, 0)
    ImageDraw.Draw(disc).ellipse([0, 0, CREAM_R * 2 * SS - 1, CREAM_R * 2 * SS - 1], fill=255)
    disc = disc.resize((CREAM_R * 2,) * 2, Image.LANCZOS)
    star.paste(cream, (size // 2 - CREAM_R, size // 2 - CREAM_R), disc)

    # Grain so the gold is not flat plastic: the same paper speckle as the mat.
    arr = np.asarray(star).astype(float)
    rng = np.random.default_rng(24)
    grain = rng.normal(0, 7, arr.shape[:2])
    grain = np.asarray(Image.fromarray(((grain + 128).clip(0, 255)).astype(np.uint8))
                       .filter(ImageFilter.GaussianBlur(0.7))).astype(float) - 128
    arr[..., :3] = (arr[..., :3] + grain[..., None]).clip(0, 255)
    star = Image.fromarray(arr.astype(np.uint8), "RGBA")

    out = Image.fromarray(frame).convert("RGBA")
    out.alpha_composite(star, (CX - size // 2, CY - size // 2))
    return out.convert("RGB")


def main():
    frame = np.asarray(Image.open(SRC).convert("RGB")).copy()
    patched = paint_out_cap(frame)
    card = draw_star(patched)
    card.save(OUT, quality=92)
    print("saved", OUT)


if __name__ == "__main__":
    main()
