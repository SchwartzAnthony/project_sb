"""Take the pale-blue ribbon out of the drawn top-right ribbons (Anthony, 18 Oct:
'the white strip is sadly not fitting'). usage: python3 ribbon_fix.py in.png out.png"""
import sys
import numpy as np
from PIL import Image, ImageFilter


def grow(m, n):
    return np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(n))) > 0


def shrink(m, n):
    return np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(n))) > 0


a = np.asarray(Image.open(sys.argv[1]).convert('RGBA')).astype(int)
r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
vis = al > 10
pale = vis & (g > 150) & (b > 160) & (r > 90) & (b >= r)
dark = vis & (r + g + b < 260)
colour = vis & ~pale & ~dark
kill = pale | (shrink(grow(pale, 11), 5) & ~grow(colour, 3)) | (dark & grow(pale, 7) & ~grow(colour, 7))
# the gap between the two orange ribbons where the pale one hung: keep only the orange and its ink
orange = vis & (r > 170) & (b < 110) & (r > g + 40)
gap = np.zeros_like(vis)
gap[90:222, 1280:1328] = True
inside = shrink(grow(orange, 5), 5)  # the orange ribbons with their hatching
kill |= gap & ~inside
hole = gap & inside & kill  # specks the pale cut took out of the orange
a[kill, 3] = 0
# fill those specks, then ink a clean edge round the orange ribbons in the gap
a[hole] = [235, 110, 35, 255]
orange = inside
edge = gap & grow(orange, 5) & ~orange
a[edge] = [15, 10, 10, 255]
Image.fromarray(a.astype(np.uint8)).save(sys.argv[2])
