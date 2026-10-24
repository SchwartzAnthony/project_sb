# Free: cut the rbt1 pictures into the Bottling game's pieces.
# Usage: make_game_pieces.py <rbt1/out> <assets/brewery/games/bottling>
import sys, numpy as np
from PIL import Image, ImageFilter
src, dst = sys.argv[1:3]
def cut(name):
    im = Image.open(f'{src}/{name}').convert('RGBA')
    return im.crop(im.getchannel('A').point(lambda a: 255 if a > 40 else 0).getbbox())
def fit(im, h=None, w=None):
    if h: return im.resize((round(im.width * h / im.height), h), Image.LANCZOS)
    return im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
fit(cut('rbt1-filler-nozzle.png'), h=240).save(f'{dst}/tap.png')
fit(cut('rbt1-belt.png'), w=1280).save(f'{dst}/belt.png')
# The bottle: the glass goes see-through (ink and white highlights stay), and
# bottle_inside.png is the shape the beer fills.
b = fit(cut('rbt1-bottle-empty.png'), h=340)
a = np.array(b).astype(float)
lum = a[..., :3].mean(axis=2)
alpha = a[..., 3]
solid = alpha > 200
ink = lum < 90
shine = lum > 246
glass = solid & ~ink & ~shine
# stopper and wire stay solid: the top 9% of the bottle
top = int(b.height * 0.09)
glass[:top] = False
a[..., 3] = np.where(glass, 45, alpha)
Image.fromarray(a.astype(np.uint8)).save(f'{dst}/bottle.png')
# inside = the solid shape, shrunk a little so beer stays inside the ink
m = Image.fromarray((solid * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(9))
mm = np.array(m) > 0
mm[:top + 8] = False
inside = np.zeros((b.height, b.width, 4), np.uint8)
inside[mm] = (255, 255, 255, 255)
Image.fromarray(inside).save(f'{dst}/bottle_inside.png')
print('ok', b.size)
