import sys
sys.path.insert(0,'/home/deck/Documents/GitHub/project_sb/tools')
from make_aseprite import write_aseprite
from PIL import Image
M='/home/deck/Documents/GitHub/project_sb/art_source/pixellab/ui_icons_team/'
pitch=Image.open(M+'formation_pitch.png').convert('RGBA')
assert pitch.size==(324,232)
spr={k:Image.open(M+'formation_'+k+'.png').convert('RGBA') for k in ['player_front','player_back','keeper']}
# feet positions read off the original 1296x928 formation (divided by 4): same lineup, same spots
spots=[('keeper',163,47,'keeper')]+[('player_front',x,47,'top row') for x in (79,130,202,252)] \
 +[('player_front',x,95,'second row') for x in (130,198)] \
 +[('player_back',63,117,'left wing'),('player_front',267,117,'right wing')] \
 +[('player_back',127,143,'third row'),('player_back',162,137,'third row'),('player_back',202,140,'third row')] \
 +[('player_back',x,183,'front row') for x in (79,120,162,203,243)]
spots.sort(key=lambda s:s[2])
layers=[('pitch',pitch,0,0)]
out=pitch.copy()
for i,(k,fx,fy,label) in enumerate(spots):
    im=spr[k]; bb=im.getbbox()
    x=fx-(bb[0]+bb[2])//2; y=fy-bb[3]
    out.alpha_composite(im,(x,y)) if x>=0 and y>=0 else out.paste(im,(x,y),im)
    layers.append(('%02d %s %s'%(i+1,k.replace('_',' '),label),im,x,y))
out.convert('RGB').save('formation_normal_team.png')
write_aseprite('/home/deck/Documents/GitHub/project_sb/art_source/aseprite/ui_icons_team/formation_normal_team.aseprite',324,232,layers)
out.resize((648,464),0).save('formation_x2.png')
print(len(layers))
