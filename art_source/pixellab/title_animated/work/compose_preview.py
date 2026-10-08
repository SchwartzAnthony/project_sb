# Builds the title-screen preview (still + GIF) from the layers (round AN draft).
import math, os, sys, numpy as np
from PIL import Image, ImageDraw, ImageFont
D=os.path.dirname(os.path.abspath(__file__)); T=os.path.dirname(D)
R=os.path.abspath(os.path.join(T,'..','..','..'))+'/'
OUT=sys.argv[1] if len(sys.argv)>1 else D
W,H=1376,768
L=lambda n: Image.open(os.path.join(T,n)).convert('RGBA')
sky=L('L0_sky.png'); clouds=L('L1_clouds.png')
cstrip=Image.new('RGBA',(2*W,H)); cstrip.alpha_composite(clouds,(0,0)); cstrip.alpha_composite(clouds.transpose(Image.FLIP_LEFT_RIGHT),(W,0))
land=L('L2_land.png'); rtr=np.array(L('L3_ribbons_top_right.png')); rbl=np.array(L('L4_ribbons_bottom_left.png'))
board=np.array(L('title_board.png')); menu=L('menu_board.png')
shot=Image.open(os.path.expanduser('~/.local/share/godot/app_userdata/Sturmball/shot_menu.png')).convert('RGBA')
up,down,perch=L('bird_wings_up.png'),L('bird_wings_down.png'),L('bird_perch.png')
# title board, ropes long enough to leave the top of the screen
pad=700; seg=board[0:14].copy()
ext=np.zeros((board.shape[0]+pad,board.shape[1],4),np.uint8); ext[pad:]=board
for y in range(pad-1,-1,-1): ext[y]=seg[(y-pad)%14]
ext[:pad,:100]=0; ext[:pad,140:550]=0; ext[:pad,600:]=0
bs=1.2; Bimg=Image.fromarray(ext); B=Bimg.resize((int(Bimg.width*bs),int(Bimg.height*bs)),Image.NEAREST)
font=ImageFont.truetype(R+'art_source/pixellab/font/sturmball_comic_pixellab.ttf',84)
d=ImageDraw.Draw(B); txt='STURMBALL'; tb=d.textbbox((0,0),txt,font=font)
cx,cy=B.width//2,int((pad+140)*bs)
d.text((cx-(tb[2]-tb[0])//2-tb[0],cy-(tb[3]-tb[1])//2-tb[1]),txt,font=font,fill=(247,192,48,255),stroke_width=6,stroke_fill=(40,20,10,255))
bx=(W-B.width)//2; by=-35-int(pad*bs)
# menu board in Anthony's green box (x 50-600, y 290-766); buttons inside the light panel
ms=2.2; M=menu.resize((int(menu.width*ms),int(menu.height*ms)),Image.NEAREST)
P=(int(126*ms),int(133*ms),int(259*ms),int(234*ms))
ys=[(405,467),(483,545),(561,623),(639,701)]
gap=6; bh=(P[3]-P[1]-12-gap*3)//4; f=bh/62.0
bw=int(238*f)
if bw>P[2]-P[0]-10: f=(P[2]-P[0]-10)/238.0
btns=[shot.crop((1410,a,1648,b)).resize((int(238*f),int((b-a)*f)),Image.NEAREST) for a,b in ys]
tot=sum(bt.height for bt in btns)+gap*3; yy=P[1]+(P[3]-P[1]-tot)//2
for bt in btns: M.alpha_composite(bt,((P[0]+P[2]-bt.width)//2,yy)); yy+=bt.height+gap
mx,my=277,197   # centred (Anthony, 7 Oct)
apex=(mx+int(191*ms), my+int(27*ms)+4)
def sway_tr(t):
    out=np.zeros_like(rtr)
    for y in range(0,265):
        k=(y/262.0)**1.3; dx=int(round(11*k*math.sin(2*math.pi*0.55*t-y/170.0)))
        out[y]=np.roll(rtr[y],dx,axis=0)
    out[265:]=rtr[265:]; return Image.fromarray(out)
def sway_bl(t):
    out=np.zeros_like(rbl)
    for y in range(500,H):
        k=(H-y)/268.0; dx=int(round(9*k*math.sin(2*math.pi*0.45*t+1.3+(H-y)/200.0)))
        out[y]=np.roll(rbl[y],dx,axis=0)
    return Image.fromarray(out)
bsc=1.4
sc=lambda im: im.resize((int(im.width*bsc),int(im.height*bsc)),Image.NEAREST)
UP,DOWN,PER=sc(up),sc(down),sc(perch); feet=int(53*bsc)
land_pos=(apex[0]-PER.width//2, apex[1]-feet); start=(-120,140)
lerp=lambda a,b,u:(a[0]+(b[0]-a[0])*u,a[1]+(b[1]-a[1])*u)
def bird(t):
    if t<3: return None
    if t<5:
        u=1-(1-(t-3)/2)**2; p=lerp(start,land_pos,u); p=(p[0],p[1]-40*math.sin(math.pi*u))
        fr=PER if u>0.92 else (UP if int(t*10)%2==0 else DOWN); return fr,p
    if t<10: return PER,land_pos
    u=(t-10)/2.0; p=lerp(land_pos,(1500,40),u**1.4)
    return (UP if int(t*10)%2==0 else DOWN),p
def frame(t,scale=0.5):
    img=sky.copy(); off=int(t*30)%(2*W)
    cl=Image.new('RGBA',(W,H))
    if off+W<=2*W: cl.alpha_composite(cstrip.crop((off,0,off+W,H)))
    else: cl.alpha_composite(cstrip.crop((off,0,2*W,H)),(0,0)); cl.alpha_composite(cstrip.crop((0,0,off+W-2*W,H)),(2*W-off,0))
    img.alpha_composite(cl); img.alpha_composite(land); img.alpha_composite(sway_tr(t)); img.alpha_composite(sway_bl(t))
    img.alpha_composite(M,(mx,my))
    bd=bird(t)
    if bd: img.alpha_composite(bd[0],(int(bd[1][0]),int(bd[1][1])))
    ang=2.5*math.sin(2*math.pi*0.5*t); o=int(pad*bs)+40
    big=Image.new('RGBA',(W,H+o+400)); big.alpha_composite(B,(bx,by+o))
    rot=big.rotate(ang,resample=Image.NEAREST,center=(W//2,by+o))
    img.alpha_composite(rot.crop((0,o,W,o+H)))
    if scale!=1.0: img=img.resize((int(W*scale),int(H*scale)),Image.NEAREST)
    return img
if __name__=='__main__':
    frame(7.0,1.0).convert('RGB').save(os.path.join(OUT,'menu_animated_mockup.png'))
    fr=[frame(i/10.0).convert('RGB') for i in range(130)]
    fr[0].save(os.path.join(OUT,'menu_animated_preview.gif'),save_all=True,append_images=fr[1:],duration=100,loop=0,optimize=True)
    print('ok', 'button', btns[0].size)
