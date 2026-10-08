#!/usr/bin/env python3
# =============================================================
#  THE GAME FONT  (round AN)
#
#      ~/.venvs/sturmball/bin/python tools/make_font.py
#
#  Turns the PixelLab font sheet into a font Godot can use everywhere:
#
#      art_source/pixellab/font/sturmball_comic_atlas.png   (the master)
#          -> assets/fonts/SturmballComic.fnt  +  SturmballComic.png
#
#  WHY NOT JUST THE .ttf PixelLab GIVES YOU? It has no umlauts and no ß, and
#  this game says Schäfer, Bergmännlein and Günter on every other screen. So
#  this script cuts every letter out of the sheet and ADDS the German ones:
#  Ä Ö Ü ä ö ü are the plain letter with two dots on top, ß is the B.
#  Anything still missing (& # @ ★ ...) is drawn in the `fallback` font of
#  data/Theme.csv, so nothing ever turns into an empty box.
#
#  THE SHEET: 8 columns x 10 rows of 16 x 16 cells, black letters on
#  transparent, in this order (PixelLab's own):
#      ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.,!?:;'"-+()0123456789/%*=_$
#  Redraw any letter in Aseprite, save the sheet, run this again.
#
#  To use a different font, put its name in the Font column of the heading,
#  body and small rows of data/Theme.csv. Nothing else.
#
#  TWO FONTS COME OUT (round AN, your answer: "less pixelated when very large,
#  more clean and crisp"):
#      SturmballComic     the pixel letters exactly as drawn, 16 high
#      SturmballComicHD   the SAME letters smoothed, 4 times the detail (64
#                         high): the steps on curves and slopes are rounded
#                         off (Scale2x three times, then a soft edge), so big
#                         words are clean instead of blocky.
# =============================================================

from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "art_source/pixellab/font/sturmball_comic_atlas.png"
OUT_DIR = ROOT / "assets/fonts"
NAME = "SturmballComic"

ORDER = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.,!?:;'\"-+()0123456789/%*=_$"
CELL = 16
COLUMNS = 8
TOP_ROOM = 2          # empty rows added above every letter, for the umlaut dots
SPACING = 1           # pixels between two letters
SPACE_WIDTH = 5       # the width of " "
BASELINE = 14 + TOP_ROOM
LINE_HEIGHT = CELL + TOP_ROOM + 2

# letter -> (made from, add two dots?)
EXTRA = {
	"Ä": ("A", True), "Ö": ("O", True), "Ü": ("U", True),
	"ä": ("a", True), "ö": ("o", True), "ü": ("u", True),
	"ß": ("B", False),
}


def cut(sheet: Image.Image, index: int) -> Image.Image:
	x = (index % COLUMNS) * CELL
	y = (index // COLUMNS) * CELL
	cell = sheet.crop((x, y, x + CELL, y + CELL))
	# White letters: the game colours them with the Text Colour column.
	white = Image.new("RGBA", cell.size, (255, 255, 255, 0))
	white.putalpha(cell.getchannel("A"))
	tall = Image.new("RGBA", (CELL, CELL + TOP_ROOM), (255, 255, 255, 0))
	tall.paste(white, (0, TOP_ROOM))
	return tall


def trim_sides(glyph: Image.Image) -> Image.Image:
	box = glyph.getchannel("A").getbbox()
	if box is None:
		return glyph
	return glyph.crop((box[0], 0, box[2], glyph.height))


def add_dots(glyph: Image.Image) -> Image.Image:
	out = glyph.copy()
	alpha = out.getchannel("A")
	box = alpha.getbbox()
	if box is None:
		return out
	left, top, right, _ = box
	# Two 2x2 dots, one row of air above the letter.
	dot_bottom = top - 2
	dot_top = max(0, dot_bottom - 1)
	width = right - left
	for dot_x in (left + width // 4 - 1, right - width // 4 - 1):
		for x in range(dot_x, dot_x + 2):
			for y in range(dot_top, dot_bottom + 1):
				if 0 <= x < out.width:
					out.putpixel((x, y), (255, 255, 255, 255))
	return out


def scale2x(mask: np.ndarray) -> np.ndarray:
	"""EPX / Scale2x: doubles a 1-bit picture and fills in the diagonal steps."""
	p = np.pad(mask, 1, mode="constant")
	a, b, c, d = p[:-2, 1:-1], p[1:-1, 2:], p[1:-1, :-2], p[2:, 1:-1]   # up, right, left, down
	e = mask
	out = np.zeros((mask.shape[0] * 2, mask.shape[1] * 2), dtype=bool)
	out[0::2, 0::2] = np.where((c == a) & (c != d) & (a != b), a, e)
	out[0::2, 1::2] = np.where((a == b) & (a != c) & (b != d), b, e)
	out[1::2, 0::2] = np.where((d == c) & (d != b) & (c != a), c, e)
	out[1::2, 1::2] = np.where((b == d) & (b != a) & (d != c), d, e)
	return out


def smooth(glyph: Image.Image, scale: int) -> Image.Image:
	"""The same letter at `scale` times the size, with clean round edges."""
	mask = np.array(glyph.getchannel("A")) > 127
	mask = np.pad(mask, 1, mode="constant")      # room for the soft edge
	big = mask
	for _ in range(3):                           # x8
		big = scale2x(big)
	soft = Image.fromarray((big * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
	soft = soft.resize((mask.shape[1] * scale, mask.shape[0] * scale), Image.LANCZOS)
	v = np.array(soft).astype(np.float32) / 255.0
	edge = np.clip((v - 0.42) / 0.24, 0.0, 1.0)
	edge = edge * edge * (3 - 2 * edge)          # smoothstep
	out = Image.new("RGBA", soft.size, (255, 255, 255, 0))
	out.putalpha(Image.fromarray((edge * 255).astype(np.uint8)))
	return out


def write_font(name: str, glyphs: dict, scale: int, pad: int) -> None:
	"""One BMFont: name.fnt + name.png in assets/fonts/. pad = blank source
	pixels round each letter (the smoothed one needs room for its edge)."""
	chars = list(glyphs.keys())
	per_row = 16
	cell_w = max(g.width for g in glyphs.values()) + 2
	cell_h = max(g.height for g in glyphs.values()) + 2
	rows = (len(chars) + per_row - 1) // per_row
	page = Image.new("RGBA", (per_row * cell_w, rows * cell_h), (255, 255, 255, 0))
	lines = [
		f'info face="{name}" size={CELL * scale} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth={1 if scale > 1 else 0} aa=1 padding=0,0,0,0 spacing=1,1',
		f"common lineHeight={LINE_HEIGHT * scale} base={BASELINE * scale} scaleW={page.width} scaleH={page.height} pages=1 packed=0",
		f'page id=0 file="{name}.png"',
		f"chars count={len(chars) + 1}",
		f"char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance={SPACE_WIDTH * scale} page=0 chnl=15",
	]
	for i, ch in enumerate(chars):
		g = glyphs[ch]
		x = (i % per_row) * cell_w
		y = (i // per_row) * cell_h
		page.paste(g, (x, y))
		inner = g.width - 2 * pad * scale
		lines.append(
			f"char id={ord(ch)} x={x} y={y} width={g.width} height={g.height} "
			f"xoffset={-pad * scale} yoffset={-pad * scale} xadvance={inner + SPACING * scale} page=0 chnl=15")
	OUT_DIR.mkdir(parents=True, exist_ok=True)
	page.save(OUT_DIR / f"{name}.png")
	(OUT_DIR / f"{name}.fnt").write_text("\n".join(lines) + "\n", encoding="utf-8")
	print(f"{len(chars)} letters -> assets/fonts/{name}.fnt + {name}.png")


def main() -> None:
	sheet = Image.open(SHEET).convert("RGBA")
	glyphs: dict[str, Image.Image] = {}
	for i, ch in enumerate(ORDER):
		glyphs[ch] = cut(sheet, i)
	for ch, (base, dots) in EXTRA.items():
		made = glyphs[base].copy()
		glyphs[ch] = add_dots(made) if dots else made
	trimmed = {ch: trim_sides(g) for ch, g in glyphs.items()}
	write_font(NAME, trimmed, 1, 0)
	write_font(NAME + "HD", {ch: smooth(g, 4) for ch, g in trimmed.items()}, 4, 1)


if __name__ == "__main__":
	main()
