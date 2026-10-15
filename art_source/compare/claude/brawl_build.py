# Builds brawl.svg: a comic dust-cloud fight with stuff flying out.
import math, random
from people import *
random.seed(5)
W, H = 1536, 1024
cx, cy = 768, 560

def cloud(cx, cy, rx, ry, n, bump, fill, sw=14, seed=1):
    r = random.Random(seed)
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        k = 1 + r.uniform(-0.08, 0.08)
        pts.append((cx + rx * k * math.cos(a), cy + ry * k * math.sin(a)))
    d = f'M{pts[0][0]:.0f} {pts[0][1]:.0f} '
    for i in range(n):
        p, q = pts[i], pts[(i + 1) % n]
        mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
        nx, ny = mx - cx, my - cy
        ln = math.hypot(nx, ny)
        b = bump * r.uniform(0.8, 1.3)
        c1 = (p[0] + nx / ln * b, p[1] + ny / ln * b)
        c2 = (q[0] + nx / ln * b, q[1] + ny / ln * b)
        d += f'C {c1[0]:.0f} {c1[1]:.0f}, {c2[0]:.0f} {c2[1]:.0f}, {q[0]:.0f} {q[1]:.0f} '
    return P(d + 'Z', fill, sw)

def star(x, y, r, rot=0, col='#f2c94c'):
    pts = []
    for i in range(10):
        a = math.radians(rot + i * 36 - 90)
        rr = r if i % 2 == 0 else r * 0.45
        pts.append(f'{x + rr*math.cos(a):.0f} {y + rr*math.sin(a):.0f}')
    return P('M' + ' L'.join(pts) + ' Z', col, 10)

def boot(x, y, ang, s=1.0):
    return (f'<g transform="translate({x} {y}) rotate({ang}) scale({s})">'
            + P('M-60 -40 C -60 -70, 0 -74, 6 -46 C 40 -40, 80 -24, 86 4 C 88 22, 74 28, 50 28 L-56 28 C -72 28, -72 6, -66 -6 Z', '#141414', 12)
            + F('M-50 -36 C -44 -56, -6 -58, 0 -40 C 30 -34, 66 -20, 72 0 L-56 4 Z', '#3a3a3a')
            + L('M-30 -40 L-10 -22 M-14 -46 L4 -28', 6, '#ffffff')
            + ''.join(P(f'M{sx-6} 28 L{sx+6} 28 L{sx+4} 44 L{sx-4} 44 Z', '#bfc6cd', 6) for sx in (-40, 0, 40))
            + '</g>')

def pretzel(x, y, s, ang):
    d = 'M-40 50 C -90 40, -90 -40, -40 -45 C 0 -50, 10 -10, 0 10 C -10 30, -30 40, 40 52 M40 50 C 90 40, 90 -40, 40 -45 C 0 -50, -10 -10, 0 10 C 10 30, 30 40, -40 52'
    return (f'<g transform="translate({x} {y}) rotate({ang}) scale({s})">' + L(d, 40) + L(d, 24, '#b5672a')
            + ''.join(f'<circle cx="{a}" cy="{b}" r="5" fill="#ffffff"/>' for a, b in ((-60, -16), (54, -12), (-30, -44), (34, -42), (-62, 24))) + '</g>')

def wurst(x, y, s, ang):
    return (f'<g transform="translate({x} {y}) rotate({ang}) scale({s})">'
            + P('M-80 0 C -80 -30, -40 -34, 0 -32 C 40 -34, 80 -30, 84 0 C 80 30, 40 34, 0 32 C -40 34, -80 30, -80 0 Z', '#c8642e', 12)
            + F('M-70 12 C -40 26, 40 26, 74 12 C 60 26, 30 30, 0 28 C -30 30, -60 24, -70 12 Z', '#9a4a20')
            + L('M-40 -12 L-20 -16 M10 -16 L30 -12', 7) + L('M-80 0 L-96 -6 M84 0 L100 6', 10) + '</g>')

def ball(x, y, r):
    return (f'<circle cx="{x}" cy="{y}" r="{r}" fill="#ffffff" stroke="{K}" stroke-width="12"/>'
            + F(f'M{x} {y-r*0.3} L{x+r*0.3} {y-r*0.08} L{x+r*0.18} {y+r*0.3} L{x-r*0.18} {y+r*0.3} L{x-r*0.3} {y-r*0.08} Z', K)
            + F(f'M{x-r*0.95} {y-r*0.1} L{x-r*0.62} {y-r*0.2} L{x-r*0.55} {y+r*0.25} L{x-r*0.85} {y+r*0.45} C {x-r*0.98} {y+r*0.2}, {x-r} {y}, {x-r*0.95} {y-r*0.1} Z', K)
            + F(f'M{x+r*0.95} {y-r*0.1} L{x+r*0.62} {y-r*0.2} L{x+r*0.55} {y+r*0.25} L{x+r*0.85} {y+r*0.45} C {x+r*0.98} {y+r*0.2}, {x+r} {y}, {x+r*0.95} {y-r*0.1} Z', K)
            + F(f'M{x-r*0.3} {y-r*0.95} L{x+r*0.3} {y-r*0.95} L{x+r*0.2} {y-r*0.7} L{x-r*0.2} {y-r*0.7} Z', K))

def motion(x, y, ang, n=3, ln=60):
    a = math.radians(ang)
    out = ''
    for i in range(n):
        o = (i - (n - 1) / 2) * 24
        px, py = x + o * math.sin(a), y - o * math.cos(a)
        out += L(f'M{px:.0f} {py:.0f} L{px - ln*math.cos(a):.0f} {py - ln*math.sin(a):.0f}', 9)
    return out

o = []
# flying things BEHIND the cloud edge (they poke out)
o.append('<g transform="rotate(-28 300 300)">' + stein(300, 330, 1.7) + '</g>')
o.append(pretzel(1130, 190, 0.9, 20))
o.append(boot(1320, 470, 25, 1.1))
# limbs sticking out of the cloud (drawn before the cloud so the cloud covers their roots)
skinA, skinB, skinC = SKINS[0], SKINS[1], SKINS[2]
o.append(limb('M560 540 C 470 500, 420 430, 380 380', skinA[0], 40, 12))
o.append(fist(372, 372, skinA, 38))
o.append(limb('M980 520 C 1060 470, 1120 420, 1150 350', skinB[0], 40, 12))
o.append(fist(1156, 342, skinB, 38))
# legs with boots out the bottom and sides
o.append(limb('M600 700 C 540 780, 480 820, 420 840', '#d8392f', 44, 12))
o.append(limb('M450 832 C 430 836, 410 840, 396 842', '#ffffff', 44, 12))
o.append(boot(360, 846, 200, 1.0))
o.append(limb('M940 720 C 1010 790, 1080 820, 1150 820', '#2a6fd0', 44, 12))
o.append(limb('M1130 820 C 1140 820, 1150 820, 1160 820', '#2a6fd0', 44, 12))
o.append(boot(1210, 826, 0, 1.0))
o.append(limb('M780 760 C 790 820, 800 860, 806 900', '#d8392f', 44, 12))
o.append(boot(830, 920, 90 - 80, 0.95))
# the dust cloud
o.append(cloud(cx, cy, 380, 290, 16, 70, '#ece3cf', 16, 3))
o.append(cloud(cx + 40, cy + 70, 300, 190, 12, 40, '#d6c8a6', 0, 4).replace('stroke="#141414" stroke-width="0"', 'stroke="none"'))
o.append(cloud(cx - 120, cy - 120, 120, 80, 8, 30, '#f6f1e6', 0, 6).replace('stroke="#141414" stroke-width="0"', 'stroke="none"'))
# a few small puffs around the edge
for (px, py, r) in ((420, 760, 50), (1110, 740, 46), (470, 330, 40), (1060, 300, 44), (760, 260, 38)):
    o.append(cloud(px, py, r, r * 0.8, 7, r * 0.4, '#ece3cf', 12, px))
# footballer A (red), head out on the left, angry, facing right
o.append(P('M470 700 C 470 600, 540 540, 610 536 C 690 532, 720 600, 716 700 Z', '#d8392f', 14))
o.append(F('M640 540 C 700 550, 716 610, 712 700 L670 700 C 676 630, 664 570, 640 540 Z', '#a82820'))
o.append(P('M560 520 L600 552 L650 518 Z', '#ffffff', 10))
o.append(head(600, 430, 1.35, skinA, {'dir': 1, 'angry': True, 'mouth': 46, 'hair': '#d8a030', 'wild': True, 'look': (6, 0)}))
# footballer B (blue), head on the right, facing left, angry
o.append(P('M820 710 C 816 620, 860 560, 930 556 C 1010 552, 1070 610, 1070 710 Z', '#2a6fd0', 14))
o.append(F('M840 700 C 840 630, 860 580, 900 560 C 880 600, 876 650, 880 700 Z', '#1d52a0'))
o.append(P('M900 540 L940 572 L990 540 Z', '#ffffff', 10))
o.append(head(940, 450, 1.35, skinB, {'dir': -1, 'angry': True, 'mouth': 50, 'hair': '#3a2614', 'look': (-6, 0)}))
# a fist mid-punch between them
o.append(limb('M700 640 C 740 610, 760 560, 772 520', skinA[0], 40, 12))
o.append(fist(776, 512, skinA, 40))
# third guy: dazed head peeking at the bottom with stars
o.append(head(760, 720, 0.9, skinC, {'dir': 1, 'mouth': 26, 'hat': ('#3f8f3a', '#1f4a1f'), 'look': (0, -10)}))
# flying things IN FRONT
o.append(ball(1340, 300, 70))
o.append(wurst(250, 600, 1.1, -25))
for (x, y, r, rot) in ((540, 230, 40, 10), (980, 200, 34, -12), (1380, 640, 40, 20), (180, 440, 32, 0), (700, 640, 26, 15), (860, 650, 24, -10)):
    o.append(star(x, y, r, rot))
svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">\n' + '\n'.join(o) + '\n</svg>\n'
open('brawl.svg', 'w').write(svg)
