"""Cut drawn menu pictures off their key colour and size them like the old menu layers.
usage: python3 menu_cut.py land|sign|ribbons_tr|ribbons_bl|board|clouds|plank|bird in.png out.png"""
import sys
import numpy as np
from PIL import Image

def key(im, col, soft=60, hard=140):
    a = np.asarray(im.convert('RGB')).astype(np.float32)
    d = np.sqrt(((a - np.array(col, np.float32)) ** 2).sum(2))
    alpha = np.clip((d - soft) / (hard - soft), 0, 1)
    e = alpha < 1
    if col == (0, 255, 0):
        a[..., 1][e] = np.minimum(a[..., 1][e], np.maximum(a[..., 0][e], a[..., 2][e]) + 20)
    else:
        a[..., 0][e] = np.minimum(a[..., 0][e], a[..., 1][e] + 40)
        a[..., 2][e] = np.minimum(a[..., 2][e], a[..., 1][e] + 40)
    return Image.fromarray(np.dstack([np.clip(a, 0, 255), alpha * 255]).astype(np.uint8), 'RGBA')

def fit_box(k, box):
    a = np.asarray(k)[..., 3]
    ys, xs = np.where(a > 128)
    return k.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)).resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS)

kind, src, dst = sys.argv[1:4]
im = Image.open(src)
MAG = (255, 0, 255)
if kind in ('ribbons_tr', 'ribbons_bl'):
    # drawn from a crop of the old 1376x768 ribbon layer; put back in the same place
    box = (1104, 0, 1376, 363) if kind == 'ribbons_tr' else (0, 576, 144, 768)
    out = Image.new('RGBA', (1376, 768))
    out.alpha_composite(key(im, MAG).resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS), box[:2])
    out.save(dst)
elif kind == 'board':
    # fit into the old pixel board's box (66,27,318,352 on 384x384), but at the
    # size it shows on screen (1188) so it stays sharp (Anthony, 19 Oct)
    S = 1188 / 384
    box = tuple(round(v * S) for v in (66, 27, 318, 352))
    out = Image.new('RGBA', (1188, 1188))
    out.alpha_composite(fit_box(key(im, MAG), box), box[:2])
    # paint out the paper tabs and their pins along the panel top
    # (Anthony, 18 Oct): copy plain panel wood from lower down over them
    x0, x1 = round(124 * S), round(257 * S)
    out.paste(out.crop((x0, round(166 * S), x1, round(186 * S))), (x0, round(131 * S)))
    a = np.asarray(out).copy()
    med = [np.median(a[y, x0:x1, :3].astype(int).sum(1)) for y in range(len(a))]
    top = next(y for y in range(round(120 * S), len(a)) if med[y] > 500)
    for y in range(top, round(140 * S)):
        v = a[y, x0:x1, :3].astype(int).sum(1)
        good = [x for x in range(x0, x1) if v[x - x0] >= 450]
        for x in range(x0, x1):
            if v[x - x0] < 450 and good:
                a[y, x] = a[y, min(good, key=lambda g: abs(g - x))]
    # take off the beer mug hanging on the right post (Anthony, 19 Oct):
    # clear it right of the post and put the left post's wood, mirrored,
    # where the mug covered the right post
    a[730:905, 868:1000, 3] = 0
    left = a[760:942, 1188 - 868:1188 - 800][:, ::-1]
    a[760:942, 800:868] = left
    Image.fromarray(a).save(dst)
elif kind == 'bird':
    # three 512 poses side by side (wings up, wings down, sitting) -> a strip
    # of three 128 frames, about the size the bird shows on screen (126)
    k = key(im, MAG)
    out = Image.new('RGBA', (384, 128))
    for i in range(3):
        out.alpha_composite(k.crop((i * 512, 0, i * 512 + 512, 512)).resize((128, 128), Image.LANCZOS), (i * 128, 0))
    out.save(dst)
elif kind == 'plank':
    # the button plank, made at the buttons' own size (MenuConfig 250 x 64),
    # since the game draws it over the whole button with no smoothing
    fit_box(key(im, MAG), (0, 0, 250, 64)).save(dst)
elif kind == 'clouds':
    # a 1536x512 strip: scale to the layer's width, top of a 1376x768 layer
    k = key(im, MAG).resize((1376, 459), Image.LANCZOS)
    out = Image.new('RGBA', (1376, 768))
    out.alpha_composite(k)
    out.save(dst)
elif kind == 'land':
    key(im, (255, 0, 255)).resize((1376, 768), Image.LANCZOS).save(dst)
else:
    # the board came out taller/wider than the pixel one: stretch the ropes down and
    # fit the board back into the old board box (x 39-664, y 745-935 on 704x940), so the
    # STURMBALL title sits on it like before
    k = key(im, (0, 255, 0)).resize((704, 940), Image.LANCZOS)
    a = np.asarray(k)[..., 3]
    rows = np.where((a > 128).sum(1) > 300)[0]
    top, bot = rows[0], rows[-1] + 1
    cols = np.where(a[top:bot].max(0) > 128)[0]
    out = Image.new('RGBA', (704, 940))
    out.alpha_composite(k.crop((0, 0, 704, top)).resize((704, 745), Image.LANCZOS))
    out.alpha_composite(k.crop((cols[0], top, cols[-1] + 1, bot)).resize((664 - 39, 935 - 745), Image.LANCZOS), (39, 745))
    out.crop((8, 0, 696, 940)).save(dst)
