"""Cut a keeper clip shot on flat magenta into frames (used by tools/make_keeper_sheets.py). Despill only on the edges, so his skin keeps its red.
(key_cut.py's magenta despill greys skin). Pink dust (magenta mixed with white) counts as background."""
import sys, cv2, numpy as np
from PIL import Image
def frames(clip):
    cap = cv2.VideoCapture(clip); F = []
    while True:
        ok, f = cap.read()
        if not ok: break
        F.append(cv2.cvtColor(f, cv2.COLOR_BGR2RGB))
    return F
def cut(f, key=(250, 7, 243), one_piece=True, min_area=150):
    a = f.astype(np.float32); d = np.sqrt(((a - np.array(key, np.float32)) ** 2).sum(2))
    al = np.clip((d - 70) / 80, 0, 1)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    pink = (r > 170) & (b > 170) & (r - g > 25) & (b - g > 25)
    al[pink] = 0
    m = (al > 0.5).astype(np.uint8); n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    big = [i for i in range(1, n) if st[i, 4] > min_area]
    if one_piece and big: big = [max(big, key=lambda i: st[i, 4])]
    keep = np.isin(lab, big)
    keep = cv2.dilate(keep.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    al = np.where(keep, al, 0)
    edge = (al < 0.98) & (al > 0)
    lo = np.minimum(r, b); r2 = np.where(edge, np.minimum(r, np.maximum(g, lo * 0.8)), r); b2 = np.where(edge, np.minimum(b, np.maximum(g, r2)), b)
    rgb = np.dstack([r2, g, b2]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, (al * 255).astype(np.uint8)]))
def strip(ims, height, out, pad=6):
    """One fixed crop for all frames (so the motion stays), scaled so the crop is `height` tall, side by side."""
    boxes = [im.getbbox() for im in ims]
    x0 = min(b[0] for b in boxes) - pad; y0 = min(b[1] for b in boxes) - pad
    x1 = max(b[2] for b in boxes) + pad; y1 = max(b[3] for b in boxes) + pad
    k = height / (y1 - y0); w = int((x1 - x0) * k)
    s = Image.new('RGBA', (w * len(ims), height), (0, 0, 0, 0))
    for i, im in enumerate(ims):
        s.alpha_composite(im.crop((x0, y0, x1, y1)).resize((w, height), Image.LANCZOS), (i * w, 0))
    s.save(out); print(out, len(ims), 'frames of', w, 'x', height)
    return w
