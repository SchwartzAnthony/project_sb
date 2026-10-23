"""Free: the beer mat player card (r186, Anthony 23 Oct: 'name on the bottom and the number in the circle then
scribbles on the card in the center (cannot be read and is standard for all cards)').
python3 beermat_card.py NAME NUMBER out.png  -> the r186 card with the name on the plank (game font), the number in
the bottle cap and the same unreadable signature on every card (fixed seed)."""
import sys, math, random
from PIL import Image, ImageDraw, ImageFilter
REPO = '/home/claude/project_sb'
CARD = '/mnt/project-files/art_tool/rounds/r187/out/r187-beermat-empty.png'   # r187: the empty frame
FNT = f'{REPO}/assets/fonts/SturmballComicHD.fnt'
INK = (25, 17, 10)
PLANK = (512, 1398, 720, 78)     # centre x, centre y, max width, max height
CAP = (512, 998, 92)            # centre x, centre y, max size
SIGN = (512, 1212)               # centre of the signature panel

def font():
    chars = {}; page = None
    for line in open(FNT, encoding='utf-8'):
        p = line.split()
        if not p: continue
        kv = dict(x.split('=', 1) for x in p[1:] if '=' in x)
        if p[0] == 'page': page = Image.open(f'{REPO}/assets/fonts/' + kv['file'].strip('"')).convert('RGBA')
        if p[0] == 'char': chars[int(kv['id'])] = {k: int(kv[k]) for k in ('x', 'y', 'width', 'height', 'xoffset', 'yoffset', 'xadvance')}
    return page, chars

def text_image(s, colour):
    page, chars = font()
    w = sum(chars.get(ord(c), chars[32])['xadvance'] for c in s) + 16
    im = Image.new('RGBA', (w, 96), (0, 0, 0, 0)); x = 4
    for c in s:
        ch = chars.get(ord(c), chars[32])
        if ch['width']:
            g = page.crop((ch['x'], ch['y'], ch['x'] + ch['width'], ch['y'] + ch['height']))
            a = g.split()[3]
            solid = Image.new('RGBA', g.size, colour + (255,)); solid.putalpha(a)
            im.alpha_composite(solid, (x + ch['xoffset'], 8 + ch['yoffset']))
        x += ch['xadvance']
    return im.crop(im.getbbox())

def fit(im, w, h):
    k = min(w / im.width, h / im.height); return im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)

def paste_centre(card, im, cx, cy):
    card.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))

def signature():
    """One flowing pen line that reads as a signature but spells nothing: tall narrow loops (like l and h), small
    humps and one loop below the line, slanted, with a smooth underline flourish. Same seed = same scribble on
    every card."""
    rng = random.Random(1860)
    S = 3; W, H = 900 * S, 260 * S
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    base = H * 0.6; x = 70 * S; key = [(x, base + 10 * S)]
    kinds = ['big', 'small', 'tall', 'small', 'small', 'down', 'tall', 'small', 'small', 'tall', 'small']
    for kind in kinds:
        w = rng.uniform(26, 40) * S
        if kind == 'big':     key += [(x + 30 * S, base - 150 * S), (x - 10 * S, base - 120 * S), (x + 40 * S, base)]; x += 60 * S
        elif kind == 'tall':  key += [(x + w * 0.9, base - rng.uniform(95, 125) * S), (x + w * 0.3, base - 80 * S), (x + w, base)]
        elif kind == 'down':  key += [(x + w * 0.6, base + 70 * S), (x + w * 0.1, base + 45 * S), (x + w, base - 20 * S)]
        else:                 key += [(x + w * 0.5, base - rng.uniform(28, 45) * S), (x + w, base)]
        x += w
    key += [(x + 30 * S, base - 40 * S), (x + 10 * S, base + 30 * S), (x - 250 * S, base + 55 * S), (70 * S, base + 48 * S)]
    pts = []                                   # Catmull-Rom through the key points: one smooth pen line
    P = [key[0]] + key + [key[-1]]
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(12):
            t = k / 12
            pts.append(tuple(0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in (0, 1)))
    pts = [(px - (py - base) * 0.28, py) for px, py in pts]   # slant to the right
    d.line(pts, fill=(28, 60, 160, 255), width=6 * S, joint='curve')
    im = im.resize((W // S, H // S), Image.LANCZOS)
    im = im.crop(im.getbbox())
    return fit(im, 700, 180)


def make(name, number, out):
    card = Image.open(CARD).convert('RGBA')
    paste_centre(card, signature(), *SIGN)
    paste_centre(card, fit(text_image(name.upper(), INK), PLANK[2], PLANK[3]), PLANK[0], PLANK[1])
    paste_centre(card, fit(text_image(str(number), INK), CAP[2], CAP[2]), CAP[0], CAP[1])
    card.save(out)

FRAMES = '/mnt/project-files/art_tool/thomas_video'
FIG_H, FEET_Y = 600, 870          # the runner in the window: height and where his feet are
def run_frames(pattern):
    """The same run the player has on the pitch (the 900x1500 frames the pitch sheets are made from), with the
    pitch's head bob (debob) and its 8 frames."""
    import glob
    src = open(f'{FRAMES}/game_prep.py').read(); g = {}
    exec(src[:src.index("TH = '")].replace('import numpy as np, glob, os, cv2, math', 'import numpy as np, glob, os, math'), g)
    L = [Image.open(f).convert('RGBA') for f in sorted(glob.glob(pattern))]
    return g['resample'](g['debob'](L), 8)

def make_gif(name, number, pattern, out, mirror=False):
    card = Image.open(CARD).convert('RGBA')
    paste_centre(card, signature(), *SIGN)
    paste_centre(card, fit(text_image(name.upper(), INK), PLANK[2], PLANK[3]), PLANK[0], PLANK[1])
    paste_centre(card, fit(text_image(str(number), INK), CAP[2], CAP[2]), CAP[0], CAP[1])
    window = Image.new('L', card.size, 0)
    ImageDraw.Draw(window).rounded_rectangle((62, 112, 962, 960), 24, fill=255)   # keep him inside the picture window
    k = FIG_H / 709.0
    frames = []
    for im in run_frames(pattern):
        if mirror: im = im.transpose(Image.FLIP_LEFT_RIGHT)
        im = im.resize((int(900 * k), int(1500 * k)), Image.LANCZOS)
        lay = Image.new('RGBA', card.size, (0, 0, 0, 0)); lay.alpha_composite(im, (int(512 - 450 * k), int(FEET_Y - 1480 * k)))
        a = Image.fromarray(__import__('numpy').minimum(__import__('numpy').array(lay.split()[3]), __import__('numpy').array(window)))
        lay.putalpha(a)
        f = card.copy(); f.alpha_composite(lay); frames.append(f.convert('RGB').resize((512, 768), Image.LANCZOS))
    pal = frames[0].quantize(colors=240, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    q[0].save(out, save_all=True, append_images=q[1:], duration=1000 // 14, loop=0)
    frames[0].save(out.replace('.gif', '.png'))

if __name__ == '__main__':
    if len(sys.argv) > 4: make_gif(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
    else: make(sys.argv[1], sys.argv[2], sys.argv[3])
