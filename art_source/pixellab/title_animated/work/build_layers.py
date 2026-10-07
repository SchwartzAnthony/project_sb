# Rebuilds the title-screen layers from the hi-res maypole view (round AN).
import numpy as np
from PIL import Image
from scipy import ndimage
import os
D=os.path.dirname(os.path.abspath(__file__)); T=os.path.dirname(D)
SRC=os.path.join(T,'..','title_maypole','maypole_view_hires.png')
A=np.array(Image.open(SRC).convert('RGB')); Ai=A.astype(int); H,W,_=A.shape
# 1) the crossed-out ribbon across the right goal: mask it, paint PixelLab's inpaint back in
x0,y0,x1,y1=1184,512,1336,768
c=Ai[y0:y1,x0:x1]; r,g,b=c[...,0],c[...,1],c[...,2]
brown=(r>90)&(r<170)&(g<100)&(b<90)&(r>g+25)
lab,n=ndimage.label(brown); k=np.argmax(ndimage.sum(brown,lab,range(1,n+1)))+1
dark=c.sum(2)<120
m=ndimage.binary_dilation(lab==k,iterations=3)
for _ in range(6): m=m|(ndimage.binary_dilation(m)&dark)
m=ndimage.binary_dilation(m,iterations=2)
fx=np.array(Image.open(os.path.join(D,'fix_out.png')).convert('RGB'))
A[y0:y1,x0:x1][m]=fx[m]
# the rest of that ribbon below/left of the inpaint box: fill from the left
x0b=1080; c=A[480:,x0b:1336].astype(int); r,g,b=c[...,0],c[...,1],c[...,2]
brown=(r>90)&(r<170)&(g<100)&(b<90)&(r>g+25)
if brown.any():
    lab,n=ndimage.label(brown); k=np.argmax(ndimage.sum(brown,lab,range(1,n+1)))+1
    mm=ndimage.binary_dilation(lab==k,iterations=3)
    for _ in range(6): mm=mm|(ndimage.binary_dilation(mm)&(c.sum(2)<120))
    for yy in range(mm.shape[0]):
        xs=np.where(mm[yy])[0]
        if len(xs)==0: continue
        L=xs.min()-1
        while L>0 and c[yy,L].sum()<120: L-=1
        c[yy,xs]=c[yy,L]
    A[480:,x0b:1336]=c.astype('uint8')
Ai=A.astype(int); r,g,b=Ai[...,0],Ai[...,1],Ai[...,2]
# 2) sky + clouds
sky=(b>r+50)&(b>g+15)&(b>120)
cloud=(r>140)&(g>150)&(b>130)&(np.abs(r-g)<45)
cand=(sky|cloud); cand[300:,:]=False
lab,n=ndimage.label(cand); top=set(np.unique(lab[0,:]))-{0}
region=ndimage.binary_closing(np.isin(lab,list(top)),iterations=1); region[:,1333:]=False
# 3) top-right maypole ribbons
rib=np.zeros((H,W),bool)
treecols=set(map(tuple,Ai[200:255,1060:1135].reshape(-1,3)))
for y in range(0,262):
    for x in range(1138,1333):
        if region[y,x]: continue
        if y<196 or tuple(Ai[y,x]) not in treecols: rib[y,x]=True
l2,n2=ndimage.label(rib); keep=set(np.unique(l2[:196][rib[:196]]))-{0}; rib=np.isin(l2,list(keep))
for x in range(1138,1333):
    if not rib[195,x]: continue
    ref=Ai[195,x]
    for y in range(196,262):
        cc=Ai[y,x]
        if np.abs(cc-ref).sum()<45 or cc.sum()<90: rib[y,x]=True
        else: break
# 4) bottom-left ribbons
reg=np.zeros((H,W),bool); reg[540:,0:150]=True
red=(r>140)&(g<95)&(b<95); blue=(b>r+50)&(b>g+10)
bl=reg&(red|(blue&(np.arange(H)[:,None]>600)))
dk=Ai.sum(2)<110
for _ in range(5): bl=bl|(ndimage.binary_dilation(bl)&dk&reg)
def fill(mask, from_left=True):
    out=Ai.copy()
    for y in range(H):
        xs=np.where(mask[y])[0]
        if len(xs)==0: continue
        if from_left:
            L=xs.min()-1
            while L>0 and (mask[y,L] or Ai[y,L].sum()<110): L-=1
            out[y,xs]=Ai[y,max(L,0)]
        else:
            R=xs.max()+1
            while R<W-1 and (mask[y,R] or Ai[y,R].sum()<110): R+=1
            out[y,xs]=Ai[y,min(R,W-1)]
    return out
rows=np.arange(H)[:,None]
land_rgb=fill(rib&(rows>=196),True)
land_rgb=np.where(bl[...,None], fill(bl,False), land_rgb)
alpha=np.where(region|(rib&(rows<196)),0,255)
def layer(mask):
    o=np.zeros((H,W,4),np.uint8); o[mask,:3]=A[mask]; o[mask,3]=255; return Image.fromarray(o)
skyl=np.zeros_like(Ai)
for y in range(H):
    row=Ai[y][sky[y]&region[y]]
    skyl[y]=row.mean(0) if len(row)>20 else (skyl[y-1] if y>0 else [39,139,204])
Image.fromarray(skyl.astype('uint8')).save(os.path.join(T,'L0_sky.png'))
layer(region&cloud).save(os.path.join(T,'L1_clouds.png'))
Image.fromarray(np.dstack([land_rgb,alpha]).astype('uint8')).save(os.path.join(T,'L2_land.png'))
layer(rib).save(os.path.join(T,'L3_ribbons_top_right.png'))
layer(bl).save(os.path.join(T,'L4_ribbons_bottom_left.png'))
print('layers ok')
