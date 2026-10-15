# Shared comic-people parts for crowd.svg and brawl.svg (hand-built SVG paths).
K = '#141414'
SKINS = [('#f0a07c', '#d9805e', '#f07868'), ('#e8956a', '#c97452', '#e86858'),
         ('#f5b48e', '#de916c', '#f08070'), ('#d98a62', '#b86c48', '#de6a5a')]

def P(d, fill, sw=12, extra=''):
    return f'<path d="{d}" fill="{fill}" stroke="{K}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round" {extra}/>'

def F(d, fill):  # flat fill, no outline (shadow tones)
    return f'<path d="{d}" fill="{fill}"/>'

def L(d, sw=10, col=K):
    return f'<path d="{d}" fill="none" stroke="{col}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"/>'

def limb(d, col, w=34, ow=12):
    return L(d, w + ow * 2 - 4) + L(d, w, col)

def fist(x, y, skin, r=26):
    d = (f'M{x-r} {y+4} C {x-r-4} {y-r}, {x+r*0.6} {y-r-8}, {x+r} {y-r*0.3} '
         f'C {x+r+8} {y+r*0.2}, {x+r*0.4} {y+r+4}, {x-r*0.3} {y+r} C {x-r-2} {y+r*0.9}, {x-r-2} {y+r*0.4}, {x-r} {y+4} Z')
    return P(d, skin[0], 10) + L(f'M{x-r*0.4} {y-r*0.5} L{x-r*0.4} {y+r*0.1} M{x+r*0.15} {y-r*0.55} L{x+r*0.15} {y+r*0.1}', 6)

def stein(x, y, s=1.0):
    # stein centred at x, bottom at y
    w, h = 50 * s, 80 * s
    out = P(f'M{x-w/2} {y-h} L{x+w/2} {y-h} L{x+w/2-4} {y} L{x-w/2+4} {y} Z', '#f2b632', 10)
    out += F(f'M{x+w/2-14*s} {y-h+6} L{x+w/2-4} {y-h+6} L{x+w/2-6} {y-4} L{x+w/2-16*s} {y-4} Z', '#d8902a')
    fx = x - w / 2 - 8
    out += P(f'M{fx} {y-h+6} C {fx-10} {y-h-30*s}, {x-8} {y-h-40*s}, {x+4} {y-h-22*s} C {x+14} {y-h-44*s}, {x+w/2+20} {y-h-30*s}, {x+w/2+10} {y-h+4} '
             f'C {x+w/2+12} {y-h+22*s}, {x+w/2-6} {y-h+22*s}, {x+w/2-8} {y-h+10} C {x} {y-h+20*s}, {x-w/2} {y-h+24*s}, {fx} {y-h+6} Z', '#ffffff', 10)
    return out

def head(x, y, s, skin, opts):
    """Head centred at x,y (y = middle of face). Faces right (dir=1) or left (dir=-1)."""
    dr = opts.get('dir', 1)
    o = []
    hw, hh = 58 * s, 70 * s
    hair = opts.get('hair', '#3a2614')
    # wild hair behind
    if opts.get('wild', True):
        hx = x - dr * hw * 0.6
        o.append(P(f'M{x} {y-hh} C {hx-dr*50*s} {y-hh-20*s}, {hx-dr*80*s} {y-hh*0.4}, {hx-dr*50*s} {y-hh*0.1} '
                   f'C {hx-dr*84*s} {y+10*s}, {hx-dr*40*s} {y+40*s}, {hx} {y+20*s} L{x} {y} Z', hair, 10))
    # ear
    ex = x - dr * hw * 0.85
    o.append(P(f'M{ex+dr*10*s} {y-20*s} C {ex-dr*30*s} {y-40*s}, {ex-dr*40*s} {y+20*s}, {ex+dr*6*s} {y+24*s} Z', skin[0], 10))
    # head: egg with heavy chin
    o.append(P(f'M{x-hw} {y-10*s} C {x-hw} {y-hh*1.1}, {x+hw} {y-hh*1.1}, {x+hw} {y-10*s} '
               f'C {x+hw*1.05} {y+hh*0.7}, {x+hw*0.4} {y+hh}, {x} {y+hh*0.95} C {x-hw*0.6} {y+hh}, {x-hw*1.05} {y+hh*0.6}, {x-hw} {y-10*s} Z', skin[0], 12))
    o.append(F(f'M{x-dr*hw*0.95} {y+10*s} C {x-dr*hw*0.9} {y+hh*0.6}, {x-dr*hw*0.4} {y+hh*0.9}, {x+dr*hw*0.1} {y+hh*0.92} C {x-dr*hw*0.5} {y+hh*0.6}, {x-dr*hw*0.8} {y+hh*0.3}, {x-dr*hw*0.95} {y+10*s} Z', skin[1]))
    face_at = len(o)
    # mouth: big open grin with gap teeth
    mx = x + dr * 8 * s
    my = y + 26 * s
    mw = 40 * s
    open_h = opts.get('mouth', 40) * s
    o.append(P(f'M{mx-mw} {my-6*s} C {mx-mw*0.6} {my+open_h}, {mx+mw*0.6} {my+open_h}, {mx+mw} {my-6*s} C {mx+mw*0.4} {my+4*s}, {mx-mw*0.4} {my+4*s}, {mx-mw} {my-6*s} Z', '#7a1a1a', 10))
    o.append(F(f'M{mx-mw*0.5} {my+open_h*0.55} C {mx-mw*0.2} {my+open_h*0.8}, {mx+mw*0.3} {my+open_h*0.8}, {mx+mw*0.55} {my+open_h*0.5} C {mx+mw*0.2} {my+open_h*0.45}, {mx-mw*0.2} {my+open_h*0.45}, {mx-mw*0.5} {my+open_h*0.55} Z', '#e8606a'))
    o.append(P(f'M{mx-mw*0.55} {my+0*s} L{mx-mw*0.12} {my+2*s} L{mx-mw*0.12} {my+16*s} L{mx-mw*0.5} {my+13*s} Z', '#ffffff', 6))
    o.append(P(f'M{mx+mw*0.12} {my+2*s} L{mx+mw*0.55} {my+0*s} L{mx+mw*0.5} {my+13*s} L{mx+mw*0.12} {my+16*s} Z', '#ffffff', 6))
    # eyes: big white ovals, small pupils
    e1 = x + dr * 2 * s
    e2 = x + dr * 34 * s
    ey = y - 26 * s
    look = opts.get('look', (dr * 5, -6))
    o.append(P(f'M{e1} {ey-26*s} C {e1+18*s} {ey-26*s}, {e1+18*s} {ey+24*s}, {e1} {ey+24*s} C {e1-18*s} {ey+24*s}, {e1-18*s} {ey-26*s}, {e1} {ey-26*s} Z', '#ffffff', 10))
    o.append(P(f'M{e2} {ey-24*s} C {e2+15*s} {ey-24*s}, {e2+15*s} {ey+22*s}, {e2} {ey+22*s} C {e2-15*s} {ey+22*s}, {e2-15*s} {ey-24*s}, {e2} {ey-24*s} Z', '#ffffff', 10))
    o.append(f'<circle cx="{e1+look[0]*s}" cy="{ey+look[1]*s}" r="{6*s}" fill="{K}"/><circle cx="{e2+look[0]*s}" cy="{ey+look[1]*s}" r="{5.5*s}" fill="{K}"/>')
    # potato nose, huge, bulging forward
    nx = x + dr * 30 * s
    ny = y + 2 * s
    o.append(P(f'M{nx-dr*20*s} {ny-20*s} C {nx+dr*20*s} {ny-40*s}, {nx+dr*64*s} {ny-14*s}, {nx+dr*56*s} {ny+18*s} '
               f'C {nx+dr*50*s} {ny+40*s}, {nx+dr*16*s} {ny+38*s}, {nx+dr*4*s} {ny+28*s} C {nx-dr*20*s} {ny+36*s}, {nx-dr*36*s} {ny+10*s}, {nx-dr*20*s} {ny-20*s} Z', skin[2], 12))
    o.append(f'<ellipse cx="{nx+dr*28*s}" cy="{ny-12*s}" rx="{8*s}" ry="{5*s}" fill="#ffffff"/>')
    # brows
    if opts.get('angry'):
        o.append(L(f'M{e1-dr*16*s} {ey-40*s} L{e1+dr*16*s} {ey-24*s}', 12))
        o.append(L(f'M{e2+dr*14*s} {ey-40*s} L{e2-dr*12*s} {ey-24*s}', 12))
    else:
        o.append(L(f'M{e1-14*s} {ey-34*s} C {e1-6*s} {ey-42*s}, {e1+8*s} {ey-42*s}, {e1+14*s} {ey-36*s}', 9))
        o.append(L(f'M{e2-12*s} {ey-34*s} C {e2-4*s} {ey-42*s}, {e2+8*s} {ey-40*s}, {e2+12*s} {ey-34*s}', 9))
    # hat
    hat = opts.get('hat')
    if hat:
        col, band = hat
        ht = y - hh * 1.02
        o.append(P(f'M{x-hw*0.75} {ht} C {x-hw*0.8} {ht-50*s}, {x-hw*0.4} {ht-74*s}, {x-hw*0.05} {ht-70*s} C {x+hw*0.15} {ht-62*s}, {x+hw*0.3} {ht-64*s}, {x+hw*0.45} {ht-72*s} C {x+hw*0.8} {ht-60*s}, {x+hw*0.85} {ht-30*s}, {x+hw*0.8} {ht} Z', col, 10))
        o.append(P(f'M{x-hw*0.78} {ht-6*s} C {x-hw*0.2} {ht-16*s}, {x+hw*0.3} {ht-16*s}, {x+hw*0.82} {ht-6*s} L{x+hw*0.82} {ht+6*s} C {x+hw*0.3} {ht-2*s}, {x-hw*0.2} {ht-2*s}, {x-hw*0.78} {ht+8*s} Z', band, 6))
        o.append(P(f'M{x-hw*1.2} {ht+4*s} C {x-hw*1.3} {ht-14*s}, {x-hw*1.0} {ht-8*s}, {x-hw*0.8} {ht} C {x-hw*0.2} {ht+12*s}, {x+hw*0.5} {ht+10*s}, {x+hw*1.1} {ht-6*s} C {x+hw*1.3} {ht-10*s}, {x+hw*1.3} {ht+6*s}, {x+hw*1.1} {ht+12*s} C {x+hw*0.4} {ht+34*s}, {x-hw*0.6} {ht+30*s}, {x-hw*1.2} {ht+4*s} Z', col, 10))
        if opts.get('feather', True):
            fx = x - dr * hw * 0.5
            o.append(P(f'M{fx} {ht-10*s} C {fx-dr*14*s} {ht-50*s}, {fx-dr*30*s} {ht-80*s}, {fx-dr*52*s} {ht-100*s} C {fx-dr*30*s} {ht-70*s}, {fx-dr*6*s} {ht-44*s}, {fx+dr*8*s} {ht-12*s} Z', '#f4f1ea', 8))
    else:
        # messy mop of hair: curved tufts flicking in all directions
        t = y - hh * 0.55
        d = (f'M{x-hw*1.02} {t+hh*0.2} C {x-hw*1.3} {t-hh*0.06}, {x-hw*1.1} {t-hh*0.21}, {x-hw*1.35} {t-hh*0.33} '
             f'C {x-hw*0.95} {t-hh*0.30}, {x-hw*0.8} {t-hh*0.27}, {x-hw*0.7} {t-hh*0.30} '
             f'C {x-hw*0.75} {t-hh*0.48}, {x-hw*0.6} {t-hh*0.57}, {x-hw*0.45} {t-hh*0.63} '
             f'C {x-hw*0.3} {t-hh*0.48}, {x-hw*0.2} {t-hh*0.42}, {x-hw*0.05} {t-hh*0.39} '
             f'C {x+hw*0.05} {t-hh*0.57}, {x+hw*0.2} {t-hh*0.66}, {x+hw*0.45} {t-hh*0.69} '
             f'C {x+hw*0.4} {t-hh*0.51}, {x+hw*0.45} {t-hh*0.42}, {x+hw*0.55} {t-hh*0.36} '
             f'C {x+hw*0.8} {t-hh*0.45}, {x+hw*1.0} {t-hh*0.42}, {x+hw*1.25} {t-hh*0.48} '
             f'C {x+hw*1.05} {t-hh*0.30}, {x+hw*1.15} {t-hh*0.12}, {x+hw*1.0} {t+hh*0.15} '
             f'C {x+hw*0.5} {t-hh*0.09}, {x-hw*0.5} {t-hh*0.09}, {x-hw*1.02} {t+hh*0.2} Z')
        o.insert(face_at, P(d, hair, 10))
    return ''.join(o)
