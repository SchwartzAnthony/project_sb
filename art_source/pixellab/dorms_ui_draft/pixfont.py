# Draws words in the game's own pixel font (assets/fonts/SturmballComic.fnt)
# onto a PIL image, for the Dorms UI mockups. Not used by the game.
import os
import re
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "..", "..", "..", "assets", "fonts", "SturmballComic.fnt")

_chars = {}
_atlas = None
_line = 20


def _load():
    global _atlas, _line
    if _atlas is not None:
        return
    folder = os.path.dirname(FONT)
    for line in open(FONT, encoding="utf-8"):
        f = dict(re.findall(r'(\w+)=("[^"]*"|\S+)', line))
        if line.startswith("common"):
            _line = int(f["lineHeight"])
        elif line.startswith("page"):
            _atlas = Image.open(os.path.join(folder, f["file"].strip('"'))).convert("RGBA")
        elif line.startswith("char "):
            _chars[int(f["id"])] = {k: int(f[k]) for k in ("x", "y", "width", "height", "xoffset", "yoffset", "xadvance")}


def width(text, scale=1):
    _load()
    return sum(_chars.get(ord(c), _chars[32])["xadvance"] + 1 for c in text) * scale


def draw(img, text, x, y, colour=(255, 255, 255), scale=1, shadow=True):
    """Draw `text` with its top-left at x, y. Returns the width drawn."""
    _load()
    if shadow:
        draw(img, text, x + scale, y + scale, (20, 12, 8), scale, False)
    cx = x
    for c in text:
        ch = _chars.get(ord(c), _chars[32])
        if ch["width"] > 0:
            glyph = _atlas.crop((ch["x"], ch["y"], ch["x"] + ch["width"], ch["y"] + ch["height"]))
            tint = Image.new("RGBA", glyph.size, colour + (255,))
            tint.putalpha(glyph.getchannel("A"))
            if scale != 1:
                tint = tint.resize((tint.width * scale, tint.height * scale), Image.NEAREST)
            img.alpha_composite(tint, (cx + ch["xoffset"] * scale, y + ch["yoffset"] * scale))
        cx += (ch["xadvance"] + 1) * scale
    return cx - x
