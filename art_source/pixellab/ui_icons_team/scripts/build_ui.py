from PIL import Image, ImageEnhance, ImageOps
import numpy as np, colorsys
M='/home/deck/Documents/GitHub/project_sb/art_source/pixellab/ui_icons_team/'
OUT='ui_out/'
import os; os.makedirs(OUT,exist_ok=True)

def nine(src, c, size, centre=None):
    """Rebuild a 9-slice frame: corners c px copied, edges repeat their middle 1-px line, centre flat."""
    a=np.array(src); h,w=a.shape[:2]; W,H=size
    o=np.zeros((H,W,4),np.uint8)
    o[:c,:c]=a[:c,:c]; o[:c,W-c:]=a[:c,w-c:]; o[H-c:,:c]=a[h-c:,:c]; o[H-c:,W-c:]=a[h-c:,w-c:]
    mx=w//2; my=h//2
    o[:c,c:W-c]=a[:c,mx:mx+1]; o[H-c:,c:W-c]=a[h-c:,mx:mx+1]
    o[c:H-c,:c]=a[my:my+1,:c]; o[c:H-c,W-c:]=a[my:my+1,w-c:]
    if centre is None: centre=a[my,mx]
    o[c:H-c,c:W-c]=centre
    return Image.fromarray(o)

def piece(sheet, box, scale=1):
    im=Image.open(M+sheet).convert('RGBA').crop(box)
    if scale>1: im=im.resize((im.width*scale,im.height*scale),Image.NEAREST)
    return im

def edge_tile(src,c,size):
    """Like nine() but tiles the full top/bottom edge pattern (for the lozenge bands)."""
    a=np.array(src); h,w=a.shape[:2]; W,H=size
    o=np.array(nine(src,c,size))
    seg=a[:, c:w-c]  # pattern strip
    sw=seg.shape[1]
    for x in range(c,W-c):
        o[:c,x]=seg[:c,(x-c)%sw]; o[H-c:,x]=seg[h-c:,(x-c)%sw]
    return Image.fromarray(o)

def recolour(im, fn):
    a=np.array(im).astype(float)/255
    out=a.copy()
    for y in range(a.shape[0]):
        for x in range(a.shape[1]):
            if a[y,x,3]>0:
                out[y,x,:3]=fn(*a[y,x,:3])
    return Image.fromarray((np.clip(out,0,1)*255).astype(np.uint8))

# --- window: native 1px, from the clean single-frame master
win=Image.open(M+'beerhall_window.png').convert('RGBA').crop((33,37,159,154))
window=nine(win,26,(96,96))
window.save(OUT+'beerhall_window.png')

# --- button family: kit piece 30 (28x24) from the button sheet, x2
btn_src=piece('beerhall_button.png',(151,95,179,119),2)
button=nine(btn_src,10,(96,96))
button.save(OUT+'beerhall_button.png')
def hov(r,g,b):
    h,l,s=colorsys.rgb_to_hls(r,g,b)
    if l<0.35: l=l*1.45+0.02     # wood lit from above
    else: l=min(1,l*1.12); s=min(1,s*1.15)  # brass shines
    return colorsys.hls_to_rgb(h,l,s)
recolour(button,hov).save(OUT+'beerhall_button_hover.png')
def prs(r,g,b):
    h,l,s=colorsys.rgb_to_hls(r,g,b)
    if l<0.35: l=l*0.72
    else: l=l*0.80; s=s*0.75
    return colorsys.hls_to_rgb(h,l,s)
recolour(button.rotate(180),prs).save(OUT+'beerhall_button_pressed.png')

# --- panel: light kit piece 30 from the panel sheet, x2
pan_src=piece('beerhall_panel.png',(151,95,179,119),2)
nine(pan_src,10,(96,96)).save(OUT+'beerhall_panel.png')

# --- slot: beer mat piece 30 from the slot sheet, x2, lozenge band tiled along the edges
slot_src=piece('beerhall_slot.png',(151,95,179,119),2)
edge_tile(slot_src,14,(96,96)).save(OUT+'beerhall_slot.png')

def sym(src, c, size):
    """Frame from the clean BOTTOM half of a kit panel (its top carries a name plate):
    the top corners and top edge are the bottom ones mirrored."""
    a=np.array(src); h,w=a.shape[:2]; W,H=size
    o=np.zeros((H,W,4),np.uint8)
    bl=a[h-c:,:c]; br=a[h-c:,w-c:]
    o[H-c:,:c]=bl; o[H-c:,W-c:]=br; o[:c,:c]=bl[::-1]; o[:c,W-c:]=br[::-1]
    mx=w//2; my=h//2+4
    o[H-c:,c:W-c]=a[h-c:,mx:mx+1]; o[:c,c:W-c]=a[h-c:,mx:mx+1][::-1]
    o[c:H-c,:c]=a[my:my+1,:c]; o[c:H-c,W-c:]=a[my:my+1,w-c:]
    o[c:H-c,c:W-c]=a[my,mx]
    return Image.fromarray(o)

button=sym(piece('beerhall_button.png',(10,61,70,104)),9,(96,96))
button.save(OUT+'beerhall_button.png')
def hov(r,g,b):
    h,l,s=colorsys.rgb_to_hls(r,g,b)
    if l<0.30: h=0.075; l=l*1.55; s=min(1,s*1.05)   # caramel wood under the lamp
    else: l=min(0.93,l*1.10); s=min(1,s*1.2)          # brass shines
    return colorsys.hls_to_rgb(h,l,s)
recolour(button,hov).save(OUT+'beerhall_button_hover.png')
def prs(r,g,b):
    h,l,s=colorsys.rgb_to_hls(r,g,b)
    if l<0.30: l=l*0.70
    else: l=l*0.78; s=s*0.7
    return colorsys.hls_to_rgb(h,l,s)
recolour(button.rotate(180),prs).save(OUT+'beerhall_button_pressed.png')
sym(piece('beerhall_panel.png',(10,61,70,104)),9,(96,96)).save(OUT+'beerhall_panel.png')

# --- bars: from the progress bars on the button kit sheet
sheet=np.array(Image.open(M+'beerhall_button.png').convert('RGBA'))
body=sheet[165:176,154:181]          # empty trough, right of its round cap
bb=np.argwhere(body[:,:,3]>0); y0,x0=bb.min(0); y1,x1=bb.max(0)+1
body=body[y0:y1,x0:x1]; h,w=body.shape[:2]
cap=4; top=4; bot=h-top-1
row=lambda r: r
n=np.zeros((16,16,4),np.uint8)
# vertical profile: top rows, stretched middle, bottom rows
vr=list(range(top))+[top]*(16-top-(h-top-1))+list(range(top+1,h))
right=body[:, w-cap:]; left=right[:, ::-1]
mid=body[:, w//2:w//2+1]
hc=[('L',i) for i in range(cap)]+[('M',0)]*(16-2*cap)+[('R',i) for i in range(cap)]
for X,(k,i) in enumerate(hc):
    src={'L':left,'M':mid,'R':right}[k]
    for Y,r in enumerate(vr): n[Y,X]=src[r,i]
Image.fromarray(n).resize((32,32),Image.NEAREST).save(OUT+'beerhall_bar_back.png')

slot_sheet=np.array(Image.open(M+'beerhall_slot.png').convert('RGBA'))
cream=tuple(slot_sheet[107,165])  # beer-mat cream
cols=[tuple(sheet[y,140]) for y in (144,145,146,147)]  # amber ramp from the gold bar fill
f=np.zeros((16,16,4),np.uint8)
prof=[cream,cream,tuple(sheet[142,140])]+[cols[0]]*2+[cols[1]]*6+[cols[2]]*3+[cols[3]]*2
for Y,c in enumerate(prof): f[Y,:]=c
Image.fromarray(f).resize((32,32),Image.NEAREST).save(OUT+'beerhall_bar_fill.png')
print('cream',cream)
