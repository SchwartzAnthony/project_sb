"""THE FREE KICK NUMBER GAME, WHEEL LOOK - draws the pieces (Anthony, 24 Oct 2026: "I like the wheel!").

The number call (src/ui/coin_clash.gd) as a fairground booth: a striped awning with a blank sign for the title,
two candy-striped posts, a painted wheel of fortune that spins and stops under a red flap, and raffle tickets for
the numbers and for ATTACK / DEFEND. Rough ink, flat bold colour, a little hatching - free, no paid art.

The pieces carry no words: the game writes the numbers and words on them, so they stay in data/ClashLook.csv
and Tuning.csv. The wheel face is drawn for 10 numbers (coin_faces 10), number 1 at the top.

    python3 tools/art/clash_wheel_pieces.py        ->  assets/ui/clash_wheel/*.png
"""
import math, os, random
from PIL import Image, ImageDraw, ImageChops

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'ui', 'clash_wheel')
S = 2                                     # drawn at twice the size, then shrunk, so the lines stay crisp
INK = (22, 15, 10, 255)
RED = (205, 38, 34, 255)
DARK_RED = (150, 40, 34, 255)
WHITE = (252, 250, 244, 255)
CREAM = (246, 234, 208, 255)
BLUE = (34, 98, 196, 255)
YOLK = (250, 196, 30, 255)
GOLD = (232, 170, 40, 255)
GREEN = (60, 150, 60, 255)
ATTACK_RED = (224, 69, 58, 255)     # role_colour_attack (Anthony 24 Oct: ATTACK red, DEFEND blue)
DEFEND_BLUE = (64, 143, 235, 255)   # role_colour_defend
DARK_BROWN = (96, 52, 26, 255)
FACES = 10
WHEEL_R = 290                             # the painted face's radius
RIM = 44                                  # the brown rim around it


def wobble(points, closed=True, amp=2.0, step=14):
    pts = list(points) + ([points[0]] if closed else [])
    out = []
    phase = random.random() * 10
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        d = math.hypot(x1 - x0, y1 - y0)
        n = max(1, int(d / (step * S)))
        nx, ny = (-(y1 - y0) / d, (x1 - x0) / d) if d else (0, 0)
        for i in range(n):
            t = i / n
            off = (math.sin(phase + len(out) * 0.55) * 0.6 + random.uniform(-0.4, 0.4)) * amp * S
            out.append((x0 + (x1 - x0) * t + nx * off, y0 + (y1 - y0) * t + ny * off))
    out.append(out[0] if closed else pts[-1])
    return out


def shape(img, points, fill=None, line=7, amp=2.0, closed=True, colour=INK):
    d = ImageDraw.Draw(img)
    p = wobble([(x * S, y * S) for x, y in points], closed, amp)
    if fill is not None:
        d.polygon(p, fill=fill)
    if line:
        for i in range(len(p) - 1):
            w = int(line * S * random.uniform(0.8, 1.2))
            d.line([p[i], p[i + 1]], fill=colour, width=w)
            d.ellipse([p[i][0] - w / 2, p[i][1] - w / 2, p[i][0] + w / 2, p[i][1] + w / 2], fill=colour)


def ellipse_pts(cx, cy, rx, ry, n=48):
    return [(cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n)) for i in range(n)]


def star_pts(cx, cy, r1, r2, n):
    return [(cx + (r1 if i % 2 == 0 else r2) * math.cos(-math.pi / 2 + math.pi * i / n),
             cy + (r1 if i % 2 == 0 else r2) * math.sin(-math.pi / 2 + math.pi * i / n)) for i in range(2 * n)]


def hatch(img, points, spacing=11, angle=-0.9, w=2.2, colour=(22, 15, 10, 170), seed=1):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).polygon([(x * S, y * S) for x, y in points], fill=255)
    layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    xs = [p[0] for p in points]; ys = [p[1] for p in points]
    rng = random.Random(seed)
    k = min(xs) - 200
    while k < max(xs) + 200:
        L = (max(ys) - min(ys)) * 1.6
        a = (k + rng.uniform(-2, 2), max(ys))
        b = (a[0] + math.cos(angle) * L * rng.uniform(0.5, 1), a[1] + math.sin(angle) * L * rng.uniform(0.5, 1))
        d.line([(a[0] * S, a[1] * S), (b[0] * S, b[1] * S)], fill=colour, width=int(w * S))
        k += spacing
    layer.putalpha(ImageChops.multiply(layer.getchannel('A'), mask))
    img.alpha_composite(layer)


def save(img, name):
    img.resize((img.width // S, img.height // S), Image.LANCZOS).save(os.path.join(OUT, name))
    print('  ' + name)


def blank(w, h):
    return Image.new('RGBA', (w * S, h * S), (0, 0, 0, 0))


def awning():
    """The striped booth roof across the top, with the blank yellow sign in the middle (the title goes on it)."""
    random.seed(11)
    img = blank(1920, 210)
    stripes = 12
    for i in range(stripes):
        x0 = 60 + i * 1800 / stripes; x1 = x0 + 1800 / stripes
        shape(img, [(x0, 0), (x1, 0), (x1 + 4, 150), (x0 + 4, 150)], RED if i % 2 == 0 else WHITE, 0)
    for i in range(stripes):
        x0 = 60 + i * 1800 / stripes; x1 = x0 + 1800 / stripes
        pts = [(x0 + 4, 148)] + [((x0 + x1) / 2 + 4 + (x1 - x0) / 2 * math.cos(math.pi - math.pi * k / 12),
                                   150 + 42 * math.sin(math.pi * k / 12)) for k in range(13)]
        shape(img, pts, RED if i % 2 == 0 else WHITE, 6)
    shape(img, [(60, 0), (1860, 0), (1864, 150), (64, 150)], None, 8)
    hatch(img, [(60, 110), (1864, 110), (1864, 150), (60, 150)], 10, seed=3)
    shape(img, [(700, 22), (1220, 16), (1232, 128), (690, 134)], YOLK, 8)
    hatch(img, [(690, 104), (1232, 100), (1232, 128), (690, 134)], 9, seed=4)
    save(img, 'awning.png')


def post():
    """One candy-striped booth post (the right one is the same picture, flipped)."""
    random.seed(12)
    w, h = 90, 980
    img = blank(w, h)
    px = 45
    body = [(px - 34, 4), (px + 34, 2), (px + 36, h - 2), (px - 36, h - 2)]
    shape(img, body, WHITE, 7)
    for k in range(10):
        y = 30 + k * 100
        shape(img, [(px - 32, y), (px + 32, y - 30), (px + 32, y + 20), (px - 32, y + 50)], RED, 0)
    shape(img, body, None, 7)
    hatch(img, [(px + 10, 4), (px + 34, 2), (px + 36, h - 2), (px + 12, h - 2)], 9, seed=7)
    save(img, 'post.png')


def wheel_face():
    """The painted wedges, number 1 at the top, going clockwise. The game turns this picture."""
    random.seed(21)
    size = WHEEL_R * 2 + 20
    img = blank(size, size)
    c = size / 2
    cols = [RED, WHITE, BLUE, YOLK, GREEN]
    wedge = 2 * math.pi / FACES
    for i in range(FACES):
        a = -math.pi / 2 - wedge / 2 + i * wedge
        pts = [(c, c)] + [(c + WHEEL_R * math.cos(a + k * wedge / 8), c + WHEEL_R * math.sin(a + k * wedge / 8)) for k in range(9)]
        shape(img, pts, cols[i % len(cols)], 6)
        if i % 2:
            hatch(img, pts[:1] + pts[5:], 12, seed=i)
    save(img, 'wheel_face.png')


def wheel_rim():
    """The brown rim with its light bulbs and a soft drop shadow. It stays still; the face turns inside it."""
    random.seed(22)
    outer = WHEEL_R + RIM
    size = outer * 2 + 40
    img = blank(size, size)
    c = size / 2
    ring = blank(size, size)
    shape(ring, ellipse_pts(c + 10, c + 14, outer + 2, outer + 2), (10, 6, 4, 150), 0)
    shape(ring, ellipse_pts(c, c, outer, outer), DARK_BROWN, 9)
    hole = Image.new('L', ring.size, 0)
    ImageDraw.Draw(hole).ellipse([(c - WHEEL_R + 3) * S, (c - WHEEL_R + 3) * S, (c + WHEEL_R - 3) * S, (c + WHEEL_R - 3) * S], fill=255)
    ring.putalpha(ImageChops.subtract(ring.getchannel('A'), hole))
    img.alpha_composite(ring)
    shape(img, ellipse_pts(c, c, WHEEL_R, WHEEL_R, 60), None, 6)
    for k in range(30):
        a = 2 * math.pi * k / 30
        bx, by = c + (WHEEL_R + 22) * math.cos(a), c + (WHEEL_R + 22) * math.sin(a)
        shape(img, ellipse_pts(bx, by, 11, 11, 12), YOLK if k % 2 else WHITE, 4)
    save(img, 'wheel_rim.png')


def hub():
    random.seed(23)
    img = blank(170, 170)
    shape(img, ellipse_pts(85, 85, 70, 70), GOLD, 8)
    shape(img, ellipse_pts(85, 85, 52, 52), None, 4)
    hatch(img, ellipse_pts(105, 105, 50, 50)[0:24] + [(85, 85)], 8, seed=9)
    save(img, 'hub.png')


def pointer():
    random.seed(24)
    img = blank(110, 150)
    shape(img, [(15, 22), (95, 22), (55, 140)], RED, 8)
    shape(img, ellipse_pts(55, 20, 16, 16, 14), GOLD, 5)
    save(img, 'pointer.png')


def ticket(name, w, h, fill, seed):
    """A raffle ticket: notched sides and a thin inner line. Blank - the game writes on it."""
    random.seed(seed)
    img = blank(w + 16, h + 16)
    x, y = 8, 8
    pts = [(x, y), (x + w, y), (x + w, y + h * 0.35), (x + w - 10, y + h * 0.5), (x + w, y + h * 0.65),
           (x + w, y + h), (x, y + h), (x, y + h * 0.65), (x + 10, y + h * 0.5), (x, y + h * 0.35)]
    shape(img, pts, fill, 7)
    shape(img, [(x + 18, y + 12), (x + w - 18, y + 12), (x + w - 18, y + h - 12), (x + 18, y + h - 12)], None, 2.5)
    save(img, name)


def ring():
    """The blue ring around the number you called."""
    random.seed(25)
    img = blank(180, 130)
    shape(img, ellipse_pts(90, 65, 80, 56, 30), None, 6, colour=BLUE)
    save(img, 'ring.png')


def burst():
    """The yellow burst for an exact call. The words go on it in the game."""
    random.seed(26)
    img = blank(290, 290)
    shape(img, star_pts(145, 145, 134, 100, 13), YOLK, 7)
    save(img, 'burst.png')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    print(os.path.normpath(OUT))
    awning(); post(); wheel_face(); wheel_rim(); hub(); pointer(); ring(); burst()
    ticket('ticket_theirs.png', 130, 86, DARK_RED, 31)
    ticket('ticket_theirs_called.png', 130, 86, RED, 32)
    ticket('ticket_mine.png', 130, 86, CREAM, 33)
    ticket('ticket_mine_called.png', 130, 86, YOLK, 34)
    ticket('ticket_random.png', 280, 70, CREAM, 35)
    ticket('ticket_attack.png', 340, 110, ATTACK_RED, 36)
    ticket('ticket_defend.png', 340, 110, DEFEND_BLUE, 37)
