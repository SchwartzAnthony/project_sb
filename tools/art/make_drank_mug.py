"""The empty Maß on a card of a player who already drank (24 Oct 2026).

Anthony: "After a player drinks a beer, have the mug placed on their card".
Free: the empty, lid-open mug from the save screen (r104, his pick), cut
tight round the glass and made card-sized. Run from the repo root:

    python3 tools/art/make_drank_mug.py
"""
from PIL import Image

SOURCE = "assets/ui/save/mugs/mug_open_empty.png"
OUT = "assets/cards/drank_mug.png"
TALL = 320          # pixels; the card shrinks it

mug = Image.open(SOURCE).convert("RGBA")
mug = mug.crop(mug.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
wide = round(mug.width * TALL / mug.height)
mug = mug.resize((wide, TALL), Image.LANCZOS)
mug.save(OUT)
print(OUT, mug.size, "aspect", round(mug.width / mug.height, 4))
