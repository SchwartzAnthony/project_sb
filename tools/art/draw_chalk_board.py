"""THE BREWERY'S CHALK BOARD (24 Oct 2026, Anthony picked look B; ink edges
thinned the same day, "so large and intense make it smaller":
"B please ... but not on a wooden plank ... on a board").

Draws, for free, the pieces of the stock bar at the top of the Brewery:
  chalkboard.png   the slate in its slim wooden board frame (9-sliced in game,
                   so only the middle stretches: data/Theme.csv brewery_board)
  chalk_box.png    an empty chalk-drawn tick box
  chalk_tick.png   the yellow chalk tick that goes in it

    python3 tools/art/draw_chalk_board.py [repo folder]
"""
import math, random, sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

REPO = sys.argv[1] if len(sys.argv) > 1 else "."
OUT = REPO.rstrip("/") + "/assets/brewery/ui/"
INK = (18, 10, 4, 255)
CHALK = (236, 236, 226, 255)
YELLOW = (250, 226, 120, 255)
random.seed(24)


def grain(img, amount):
    n = Image.effect_noise(img.size, amount).convert("L")
    r, g, b, a = img.split()
    return Image.merge("RGBA", [ImageChops.add(c, n, 1, -128) for c in (r, g, b)] + [a])


def board(w=640, h=170, frame=22):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # the wooden board frame: flat brown, darker grain strokes, ink edges
    d.rounded_rectangle((0, 0, w - 1, h - 1), 12, fill=(150, 92, 44, 255))
    for i in range(70):
        y = random.randint(4, h - 4)
        x = random.randint(0, w)
        d.line([(x, y), (x + random.randint(30, 110), y + random.randint(-1, 1))],
               fill=(104, 60, 26, 255), width=2)
    for i in range(70):
        x = random.randint(4, w - 4)
        y = random.randint(0, h)
        d.line([(x, y), (x + random.randint(-1, 1), y + random.randint(20, 60))],
               fill=(104, 60, 26, 255), width=2)
    # keep the grain strokes inside the board's outline
    shape = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shape).rounded_rectangle((0, 0, w - 1, h - 1), 12, fill=255)
    img.putalpha(ImageChops.multiply(img.split()[3], shape))
    d = ImageDraw.Draw(img)
    # mitred corners
    for (x0, y0, x1, y1) in [(0, 0, frame, frame), (w - 1, 0, w - 1 - frame, frame),
                             (0, h - 1, frame, h - 1 - frame), (w - 1, h - 1, w - 1 - frame, h - 1 - frame)]:
        d.line([(x0, y0), (x1, y1)], fill=INK, width=2)
    d.rounded_rectangle((1, 1, w - 2, h - 2), 12, outline=INK, width=3)
    # highlight along the top of the frame
    d.line([(14, 6), (w - 14, 6)], fill=(206, 146, 84, 255), width=3)
    # the slate
    sx0, sy0, sx1, sy1 = frame, frame, w - 1 - frame, h - 1 - frame
    slate = Image.new("RGBA", (sx1 - sx0, sy1 - sy0), (44, 58, 52, 255))
    slate = grain(slate, 16)
    smudge = Image.new("RGBA", slate.size, (0, 0, 0, 0))
    ds = ImageDraw.Draw(smudge)
    for i in range(10):
        x = random.randint(0, slate.width)
        y = random.randint(0, slate.height)
        ds.ellipse((x - 80, y - 18, x + 80, y + 18), fill=(230, 230, 220, 20))
    slate.alpha_composite(smudge.filter(ImageFilter.GaussianBlur(12)))
    img.alpha_composite(slate, (sx0, sy0))
    d = ImageDraw.Draw(img)
    d.rectangle((sx0, sy0, sx1, sy1), outline=INK, width=3)
    # a few nails in the frame corners
    for (x, y) in [(11, 11), (w - 12, 11), (11, h - 12), (w - 12, h - 12)]:
        d.ellipse((x - 4, y - 4, x + 4, y + 4), fill=(170, 170, 160, 255), outline=INK, width=2)
    img.save(OUT + "chalkboard.png")


def chalky(img):
    """Breaks a stroke up into chalk grain."""
    a = img.split()[3]
    n = Image.effect_noise(img.size, 90).point(lambda v: 255 if v > 60 else 90)
    img.putalpha(ImageChops.multiply(a, n.convert("L")))
    return img


def box(size=64):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = 8
    for k in range(2):
        j = lambda: random.randint(-2, 2)
        d.line([(m + j(), m + j()), (size - m + j(), m + j()), (size - m + j(), size - m + j()),
                (m + j(), size - m + j()), (m + j(), m + j())], fill=CHALK, width=4)
    chalky(img).save(OUT + "chalk_box.png")


def tick(size=64):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.line([(size * 0.2, size * 0.52), (size * 0.4, size * 0.78), (size * 0.92, size * 0.06)],
           fill=YELLOW, width=9, joint="curve")
    chalky(img).save(OUT + "chalk_tick.png")


board()
box()
tick()
print("drew chalkboard.png, chalk_box.png, chalk_tick.png in", OUT)
