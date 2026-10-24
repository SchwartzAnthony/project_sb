# Makes the drawn referee cards of the referee's card box (Anthony 24 Oct 2026:
# his sketch - a wide box, the counter inside, a yellow card left and a red
# card right tilted out of the top - "Yes I love it"). Free: flat colour with
# thick ink, drawn here. The count is written on top in the game.
#
#     python3 tools/make_ref_cards.py
#
# Writes assets/ui/referee/:
#   card_yellow.png / card_red.png            a card that has been shown
#   card_yellow_none.png / card_red_none.png  the same card, none shown yet
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "referee")
os.makedirs(OUT, exist_ok=True)
INK = (25, 17, 10, 255)
S = 4  # draw big, shrink for smooth ink
CARDS = {
    "card_yellow": (247, 200, 38),
    "card_red": (206, 38, 38),
    "card_yellow_none": (196, 180, 128),
    "card_red_none": (170, 120, 110),
}


def card(colour, w=74, h=104):
    pad = 10
    im = Image.new("RGBA", ((w + 2 * pad) * S, (h + 2 * pad) * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box = (pad * S, pad * S, (w + pad) * S, (h + pad) * S)
    d.rounded_rectangle(box, radius=8 * S, fill=colour + (255,))
    hi = tuple(min(255, c + 45) for c in colour) + (255,)
    d.polygon([((pad + 8) * S, (pad + 8) * S), ((pad + 24) * S, (pad + 8) * S), ((pad + 8) * S, (pad + 42) * S)], fill=hi)
    sh = tuple(int(c * 0.78) for c in colour) + (255,)
    d.line(((w + pad - 7) * S, (pad + 12) * S, (w + pad - 7) * S, (h + pad - 9) * S), fill=sh, width=5 * S)
    d.rounded_rectangle(box, radius=8 * S, outline=INK, width=6 * S)
    return im.resize((w + 2 * pad, h + 2 * pad), Image.LANCZOS)


for name, colour in CARDS.items():
    card(colour).save(os.path.join(OUT, name + ".png"))
    print("wrote", name)
