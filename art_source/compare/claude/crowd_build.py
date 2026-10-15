# Builds crowd.svg: two rows of cheering fans behind a low advertising board.
import random
from people import *
random.seed(11)
W, H = 1536, 640
SHIRTS = [('#d8392f', '#a82820'), ('#ffffff', '#d4dbe3'), ('#2a6fd0', '#1d52a0'), ('#3f9a48', '#2c6e2a'), ('#f2c94c', '#d0a02a')]
HATS = [('#3f8f3a', '#1f4a1f'), ('#6b6b5a', '#2a2a20'), ('#3f8f3a', '#d8392f'), ('#5a3218', '#2a1a10')]
HAIRS = ['#3a2614', '#d8a030', '#141414', '#8a3a1a', '#7a7a7a']

def fan(x, base, s, i):
    skin = random.choice(SKINS)
    shirt = SHIRTS[i % len(SHIRTS)]
    dr = random.choice([1, -1])
    pose = random.choice(['stein', 'fists', 'stein', 'scarf', 'fist1'])
    o = []
    sw, sh = 78 * s, 170 * s       # shoulder half-width, torso height
    top = base - sh
    hx, hy = x + dr * 6 * s, top - 62 * s
    sl, sr = (x - sw, top + 20 * s), (x + sw, top + 20 * s)
    arms_back, arms_front = [], []
    if pose in ('stein', 'fist1'):
        up, down = (sl, sr) if dr == 1 else (sr, sl)
        ux = up[0] + (1 if up is sr else -1) * 40 * s
        hand = (ux + (1 if up is sr else -1) * 20 * s, hy - 110 * s)
        arms_front.append(limb(f'M{up[0]} {up[1]} C {ux} {up[1]-20*s}, {ux+ (10*s)} {hy}, {hand[0]} {hand[1]+20*s}', skin[0], 28 * s, 10))
        if pose == 'stein':
            arms_front.append(stein(hand[0] + 10 * s, hand[1] + 10 * s, 1.0 * s / 0.9))
        arms_front.append(fist(hand[0], hand[1] + 20 * s, skin, 24 * s))
        # other arm: scarf hand at chest
        arms_front.append(limb(f'M{down[0]} {down[1]} C {down[0]} {down[1]+60*s}, {x} {top+80*s}, {x} {top+70*s}', skin[0], 28 * s, 10))
        arms_front.append(fist(x, top + 70 * s, skin, 22 * s))
    elif pose == 'fists':
        for side, shd in ((-1, sl), (1, sr)):
            hand = (shd[0] + side * 50 * s, hy - 90 * s)
            arms_front.append(limb(f'M{shd[0]} {shd[1]} C {shd[0]+side*50*s} {shd[1]-30*s}, {hand[0]} {hy}, {hand[0]} {hand[1]+16*s}', skin[0], 28 * s, 10))
            arms_front.append(fist(hand[0], hand[1], skin, 24 * s))
    else:  # scarf stretched overhead
        hl, hr = (x - sw - 40 * s, hy - 100 * s), (x + sw + 40 * s, hy - 100 * s)
        for shd, hd in ((sl, hl), (sr, hr)):
            arms_front.append(limb(f'M{shd[0]} {shd[1]} C {shd[0]} {shd[1]-60*s}, {hd[0]} {hy}, {hd[0]} {hd[1]+16*s}', skin[0], 28 * s, 10))
        sy = hy - 110 * s
        sc = P(f'M{hl[0]} {sy} C {x-60*s} {sy-14*s}, {x+60*s} {sy+14*s}, {hr[0]} {sy} L{hr[0]} {sy+40*s} C {x+60*s} {sy+54*s}, {x-60*s} {sy+26*s}, {hl[0]} {sy+40*s} Z', '#2a6fd0', 10)
        stripes = ''.join(F(f'M{hl[0]+k*s} {sy+2*s} L{hl[0]+(k+22)*s} {sy+2*s} L{hl[0]+(k+22)*s} {sy+40*s} L{hl[0]+k*s} {sy+40*s} Z', '#ffffff') for k in range(26, int((hr[0]-hl[0])/s) - 30, 50))
        arms_front.append(sc + f'<g clip-path="none">{stripes}</g>' + P(f'M{hl[0]} {sy} C {x-60*s} {sy-14*s}, {x+60*s} {sy+14*s}, {hr[0]} {sy} L{hr[0]} {sy+40*s} C {x+60*s} {sy+54*s}, {x-60*s} {sy+26*s}, {hl[0]} {sy+40*s} Z', 'none', 10))
        arms_front.append(fist(hl[0], hl[1] + 6 * s, skin, 24 * s) + fist(hr[0], hr[1] + 6 * s, skin, 24 * s))
    # torso
    o.append(P(f'M{x-sw} {base+20} L{x-sw} {top+40*s} C {x-sw} {top+6*s}, {x-sw*0.5} {top}, {x} {top} C {x+sw*0.5} {top}, {x+sw} {top+6*s}, {x+sw} {top+40*s} L{x+sw} {base+20} Z', shirt[0], 12))
    o.append(F(f'M{x+dr*sw*0.55} {top+4*s} C {x+dr*sw*0.9} {top+10*s}, {x+dr*sw*0.95} {top+40*s}, {x+dr*sw*0.95} {top+60*s} L{x+dr*sw*0.95} {base} L{x+dr*sw*0.6} {base} Z', shirt[1]))
    # suspenders + bar on half of them, scarf around neck on others
    if i % 2 == 0:
        o.append(limb(f'M{x-sw*0.45} {top+6*s} L{x-sw*0.4} {base}', '#7a4a24', 16 * s, 8))
        o.append(limb(f'M{x+sw*0.45} {top+6*s} L{x+sw*0.4} {base}', '#7a4a24', 16 * s, 8))
        o.append(P(f'M{x-sw*0.55} {top+70*s} L{x+sw*0.55} {top+70*s} L{x+sw*0.55} {top+96*s} L{x-sw*0.55} {top+96*s} Z', '#3f9a48', 8))
    else:
        o.append(P(f'M{x-sw*0.7} {top+4*s} C {x-sw*0.3} {top+30*s}, {x+sw*0.3} {top+30*s}, {x+sw*0.7} {top+4*s} L{x+sw*0.6} {top+34*s} C {x+sw*0.2} {top+56*s}, {x-sw*0.2} {top+56*s}, {x-sw*0.6} {top+34*s} Z', '#2a6fd0', 10))
        o.append(P(f'M{x+dr*sw*0.3} {top+40*s} L{x+dr*sw*0.5} {top+120*s} L{x+dr*sw*0.2} {top+124*s} L{x+dr*sw*0.1} {top+44*s} Z', '#ffffff', 8))
    # neck
    o.append(P(f'M{hx-18*s} {top+10*s} L{hx-16*s} {hy+50*s} L{hx+18*s} {hy+50*s} L{hx+20*s} {top+10*s} Z', skin[0], 10))
    hat = random.choice(HATS) if random.random() < 0.65 else None
    o.append(head(hx, hy, s, skin, {'dir': dr, 'hat': hat, 'hair': random.choice(HAIRS),
                                     'mouth': random.choice([34, 44, 52]), 'look': (dr * random.choice([2, 5]), random.choice([-8, -2]))}))
    return ''.join(o[:-1]) + ''.join(a for a in arms_front if a.startswith('<path d="M') and 'stroke-width' in a and 'fill="none"' in a) + o[-1] + ''.join(a for a in arms_front if not (a.startswith('<path d="M') and 'fill="none"' in a))

parts = []
# back row: smaller, higher
xs_back = [110 + i * 220 for i in range(7)]
for i, x in []:
    parts.append(fan(x + random.randint(-10, 10), 440, 0.8, i + 3))
# front row
xs = [i * 256 + 40 for i in range(7)]
for i, x in enumerate(xs):
    parts.append(fan(x + 10 + random.randint(-10, 10), 560, 1.1, i))
# advertising board: plain colour panels, no text
board = []
cols = ['#d8392f', '#ffffff', '#2a6fd0', '#f2c94c', '#3f9a48', '#ffffff', '#d8392f', '#2a6fd0']
pw = W / len(cols)
for i, c in enumerate(cols):
    board.append(P(f'M{i*pw:.0f} 520 L{(i+1)*pw:.0f} 520 L{(i+1)*pw:.0f} 632 L{i*pw:.0f} 632 Z', c, 12))
    board.append(F(f'M{i*pw+8:.0f} 600 L{(i+1)*pw-8:.0f} 600 L{(i+1)*pw-8:.0f} 626 L{i*pw+8:.0f} 626 Z', '#000000" fill-opacity="0.14'))
svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">\n' + '\n'.join(parts) + '\n' + ''.join(board) + '\n</svg>\n'
open('crowd.svg', 'w').write(svg)
