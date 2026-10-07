# Exports the animated title screen's pictures for the game (round AN).
#   ~/.venvs/sturmball/bin/python art_source/pixellab/title_animated/work/export_game_art.py
import os, sys, numpy as np
from PIL import Image
D=os.path.dirname(os.path.abspath(__file__)); T=os.path.dirname(D)
R=os.path.abspath(os.path.join(T,'..','..','..')); OUT=os.path.join(R,'assets','menu','layers','animated')
sys.path.insert(0,os.path.join(R,'tools')); from make_aseprite import write_aseprite
L=lambda n: Image.open(os.path.join(T,n)).convert('RGBA')
names={'L0_sky.png':'10_sky.png','L1_clouds.png':'11_clouds.png','L2_land.png':'12_land.png',
       'L3_ribbons_top_right.png':'13_ribbons_top_right.png','L4_ribbons_bottom_left.png':'14_ribbons_bottom_left.png',
       'menu_board.png':'20_menu_board.png'}
for a,b in names.items(): L(a).save(os.path.join(OUT,b))
# bird strip: wings up | wings down | perched
strip=Image.new('RGBA',(192,64)); 
for i,n in enumerate(['bird_wings_up.png','bird_wings_down.png','bird_perch.png']): strip.alpha_composite(L(n),(i*64,0))
strip.save(os.path.join(OUT,'30_bird.png'))
# title board with ropes long enough to leave the top of the screen at any swing
board=np.array(L('title_board.png')); pad=700; seg=board[0:14].copy()
ext=np.zeros((board.shape[0]+pad,board.shape[1],4),np.uint8); ext[pad:]=board
for y in range(pad-1,-1,-1): ext[y]=seg[(y-pad)%14]
ext[:pad,:100]=0; ext[:pad,140:550]=0; ext[:pad,600:]=0
Image.fromarray(ext).save(os.path.join(OUT,'40_title_board.png'))
# layered file for Aseprite (the still screen)
W,H=1376,768
layers=[(n[:-4],L(n),0,0) for n in ['L0_sky.png','L1_clouds.png','L2_land.png','L3_ribbons_top_right.png','L4_ribbons_bottom_left.png']]
mb=L('menu_board.png').resize((845,845),Image.NEAREST); layers.append(('menu_board',mb,277,197))
bd=L('bird_perch.png').resize((90,90),Image.NEAREST); layers.append(('bird',bd,697-45,260-74))
tb=Image.open(os.path.join(OUT,'40_title_board.png')).resize((826,1128),Image.NEAREST).crop((0,840,826,1128)); layers.append(('title_board',tb,275,-35))
write_aseprite(os.path.join(R,'art_source','aseprite','title_screen_animated.aseprite'),W,H,layers)
print('exported')
