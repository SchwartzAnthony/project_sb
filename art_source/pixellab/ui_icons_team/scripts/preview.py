from PIL import Image, ImageDraw, ImageFont
import numpy as np
P='/home/deck/Documents/GitHub/project_sb/'
exec(open('subjects.py').read())
F=ImageFont.truetype(P+'assets/fonts/Schola-Regular.otf',17)
FB=ImageFont.truetype(P+'assets/fonts/Bonum-Bold.otf',20)
FS=ImageFont.truetype(P+'assets/fonts/Schola-Regular.otf',13)
def hexc(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16) for i in (0,2,4))+(255,)
def nine(im,s,W,H,tile=False,tint=None):
    a=im; w,h=a.size; o=Image.new('RGBA',(W,H))
    def put(box,dst):
        part=a.crop(box); dw,dh=dst[2]-dst[0],dst[3]-dst[1]
        if dw<=0 or dh<=0: return
        if tile and (part.width!=dw and part.height!=dh)==False:
            t=Image.new('RGBA',(dw,dh))
            for x in range(0,dw,part.width):
                for y in range(0,dh,part.height): t.paste(part,(x,y))
            o.paste(t,dst[:2])
        else: o.paste(part.resize((dw,dh),Image.NEAREST),dst[:2])
    xs=[0,s,w-s,w]; Xs=[0,s,W-s,W]; ys=[0,s,h-s,h]; Ys=[0,s,H-s,H]
    for i in range(3):
        for j in range(3): put((xs[i],ys[j],xs[i+1],ys[j+1]),(Xs[i],Ys[j],Xs[i+1],Ys[j+1]))
    if tint:
        arr=np.array(o).astype(float); arr[:,:,:3]*=np.array(tint[:3])/255; o=Image.fromarray(arr.astype(np.uint8))
    return o
bg=hexc('#19110a')
S_=Image.new('RGBA',(1400,1800),bg); d=ImageDraw.Draw(S_)
d.text((16,10),'ui_icons_team - new PixelLab UI frames (1x as in game, 9-sliced with Theme.csv slice values) and icons',font=FS,fill=hexc('#bca888'))
UI=P+'assets/ui/'
rows=[('window','beerhall_window',28,None,'#f3e8d4',False,'Dialog window','The keeper saves it. The crowd throws pretzels.'),
 ('panel (tinted #8a5a34, a mid wood)','beerhall_panel',28,hexc('#8a5a34'),'#f3e8d4',False,'Panel, tinted','Every card, tile and strip wears this one.'),
 ('panel (tinted slate #4a6b8a)','beerhall_panel',28,hexc('#4a6b8a'),'#f3e8d4',False,'Panel, tier 1','Tier colours land on the light oak.'),
 ('slot','beerhall_slot',28,None,'#3b2a18',True,'Beer mat slot','Dark text on the cream card.')]
y=40
for label,f,s,tint,tc,tile,title,body in rows:
    im=Image.open(UI+f+'.png').convert('RGBA')
    box=nine(im,s,520,130,tile,tint); S_.alpha_composite(box,(16,y))
    d.text((44,y+26),title,font=FB,fill=hexc(tc)); d.text((44,y+60),body,font=F,fill=hexc(tc))
    d.text((550,y+4),label+'  (Slice %d)'%s,font=FS,fill=hexc('#bca888'))
    S_.alpha_composite(im.resize((384,384),Image.NEAREST).crop((0,0,384,120)),(990,y))
    y+=145
d.text((990,30),'4x zoom (top part)',font=FS,fill=hexc('#bca888'))
# buttons
x=16
for f,tc,lab in [('beerhall_button','#f2e4c6','PLAY'),('beerhall_button_hover','#fff4d8','PLAY (hover)'),('beerhall_button_pressed','#e6d3ab','PLAY (pressed)')]:
    im=Image.open(UI+f+'.png').convert('RGBA'); b=nine(im,12,200,46); S_.alpha_composite(b,(x,y))
    tw=d.textlength(lab,font=F); d.text((x+100-tw/2,y+12),lab,font=F,fill=hexc(tc))
    S_.alpha_composite(im.resize((192,192),Image.NEAREST),(x+4,y+56)); x+=230
d.text((710,y),'button / hover / pressed (Slice 12), 2x zoom below',font=FS,fill=hexc('#bca888'))
y+=260
# bars
bb=Image.open(UI+'beerhall_bar_back.png').convert('RGBA'); bf=Image.open(UI+'beerhall_bar_fill.png').convert('RGBA')
for i,frac in enumerate([1.0,0.6,0.25]):
    S_.alpha_composite(nine(bb,10,400,24),(16,y+i*34))
    w=int(392*frac)
    if w>20: S_.alpha_composite(nine(bf,10,w,16),(20,y+4+i*34))
d.text((430,y),'bar_back + bar_fill (Slice 10)',font=FS,fill=hexc('#bca888'))
S_.alpha_composite(bb.resize((128,128),0),(700,y-10)); S_.alpha_composite(bf.resize((128,128),0),(840,y-10))
y+=140
# icons
d.text((16,y),'Icons 64x64 (1x), then at 28px as the trait bar shows them',font=FS,fill=hexc('#bca888')); y+=22
names=list(S); cols=13
for i,n in enumerate(names):
    im=Image.open(P+'assets/icons/'+n+'.png').convert('RGBA')
    cx=16+(i%cols)*104; cy=y+(i//cols)*120
    S_.alpha_composite(im,(cx,cy))
    S_.alpha_composite(im.resize((28,28),Image.LANCZOS),(cx+68,cy+36))
    d.text((cx,cy+68),n.replace('trait_','t_')[:16],font=FS,fill=hexc('#bca888'))
y+=3*120+10
# team
ban=Image.open(P+'assets/team/banner_normal_team.png').convert('RGBA'); S_.alpha_composite(ban,(16,y))
fo=Image.open(P+'assets/team/formation_normal_team.png').convert('RGBA'); S_.alpha_composite(fo,(170,y))
d.text((520+64,y),'team/: banner 128x128, formation 324x232',font=FS,fill=hexc('#bca888'))
S_=S_.crop((0,0,1400,y+240))
S_.convert('RGB').save(P+'art_source/pixellab/ui_icons_team/preview.png')
print(S_.size)
