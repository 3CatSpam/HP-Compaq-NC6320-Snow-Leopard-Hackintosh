from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
import numpy as np, math
SS=4
def lin(w,h,top,bot):
    """vertical gradient RGBA image"""
    a=np.zeros((h,w,4),np.float32)
    t=np.linspace(0,1,h)[:,None]
    for k in range(3): a[:,:,k]=(np.array(top[k])*(1-t)+np.array(bot[k])*t)
    a[:,:,3]=255
    return Image.fromarray(a.clip(0,255).astype(np.uint8),'RGBA')
def rrmask(w,h,r,box=None):
    m=Image.new('L',(w,h),0); ImageDraw.Draw(m).rounded_rectangle(box or (0,0,w-1,h-1),r,fill=255); return m
def paste_grad(img,box,r,top,bot):
    x0,y0,x1,y1=box; w,h=x1-x0,y1-y0
    g=lin(w,h,top,bot); m=rrmask(w,h,r)
    img.paste(g,(x0,y0),m)
def radial(w,h,c0,c1,cx=0.5,cy=0.4,rad=0.7):
    y,x=np.mgrid[0:h,0:w].astype(np.float32)
    d=np.sqrt(((x-cx*w)/w)**2+((y-cy*h)/h)**2)/rad
    d=d.clip(0,1)[:,:,None]
    a=np.concatenate([np.array(c0[:3])*(1-d)+np.array(c1[:3])*d,np.full((h,w,1),255,np.float32)],2)
    return Image.fromarray(a.clip(0,255).astype(np.uint8),'RGBA')
def drive(kind='mac',S=SS,size=128):
    """top-view hard drive icon, RGBA, size x size px (rendered at S x)"""
    W=size*S; H=size*S
    im=Image.new('RGBA',(W,H),(0,0,0,0))
    s=lambda v:int(v*S)
    if kind=='xp':
        # lower chassis (peeking out below)
        paste_grad(im,(s(10),s(86),s(118),s(120)),s(7),(150,155,162),(92,96,104))
        for i in range(8): ImageDraw.Draw(im).rectangle((s(44+i*5),s(106),s(46+i*5),s(114)),fill=(40,42,48,255))
    # main body
    top=(4,2,124,100) if kind=='mac' else (4,2,124,88)
    bx0,by0,bx1,by1=[s(v) for v in top]
    # side/front face (darker, bottom)
    fh=22 if kind=='mac' else 20
    paste_grad(im,(bx0,by1-s(fh),bx1,by1+s(8) if kind=='mac' else by1+s(6)),s(8),(150,156,164),(86,90,98))
    # top plate
    paste_grad(im,(bx0,by0,bx1,by1-s(fh)+s(10)),s(10),(236,240,244),(176,182,190))
    d=ImageDraw.Draw(im)
    d.rounded_rectangle((bx0,by0,bx1,by1-s(fh)+s(10)),s(10),outline=(110,116,126,255),width=max(1,S//2*1))
    # inner recess
    ix0,iy0,ix1,iy1=bx0+s(8),by0+s(8),bx1-s(8),by1-s(fh)+s(2)
    paste_grad(im,(ix0,iy0,ix1,iy1),s(8),(196,202,210),(222,226,232))
    d.rounded_rectangle((ix0,iy0,ix1,iy1),s(8),outline=(140,146,156,255),width=max(1,S//2))
    # platter
    pr=s(32) if kind=='mac' else s(28)
    pcx=ix0+s(40); pcy=(iy0+iy1)//2
    pl=radial(2*pr,2*pr,(246,248,250),(150,158,168),0.45,0.4,0.75)
    pm=Image.new('L',(2*pr,2*pr),0); ImageDraw.Draw(pm).ellipse((0,0,2*pr-1,2*pr-1),fill=255)
    im.paste(pl,(pcx-pr,pcy-pr),pm)
    d.ellipse((pcx-pr,pcy-pr,pcx+pr,pcy+pr),outline=(120,128,138,255),width=max(1,S//2))
    d.ellipse((pcx-pr+s(10),pcy-pr+s(10),pcx+pr-s(10),pcy+pr-s(10)),outline=(170,178,188,255),width=max(1,S//2))
    d.ellipse((pcx-s(6),pcy-s(6),pcx+s(6),pcy+s(6)),fill=(120,128,138,255))
    d.ellipse((pcx-s(3),pcy-s(3),pcx+s(3),pcy+s(3)),fill=(220,224,230,255))
    # actuator arm
    d.polygon([(ix1-s(20),iy0+s(10)),(ix1-s(8),iy0+s(14)),(pcx+pr-s(6),pcy+s(6)),(pcx+pr-s(14),pcy-s(2))],fill=(150,158,168,255))
    d.ellipse((ix1-s(26),iy0+s(8),ix1-s(12),iy0+s(22)),fill=(120,128,138,255))
    # label plate / badge
    if kind=='mac':
        d.rectangle((ix1-s(44),iy0+s(4),ix1-s(8),iy0+s(14)),fill=(40,44,52,255))
        for i in range(3): d.line((ix1-s(40),iy0+s(6)+i*s(3),ix1-s(12),iy0+s(6)+i*s(3)),fill=(170,176,184,255),width=max(1,S//2))
    # screws
    for (sx,sy) in ((bx0+s(5),by0+s(5)),(bx1-s(5),by0+s(5)),(bx0+s(5),by1-s(fh)+s(5)),(bx1-s(5),by1-s(fh)+s(5))):
        d.ellipse((sx-s(2),sy-s(2),sx+s(2),sy+s(2)),fill=(96,102,112,255))
    # vents on front face
    vy0=by1-s(fh)+s(13); 
    for i in range(10):
        vx=bx0+s(30)+i*s(7)
        d.rectangle((vx,vy0,vx+s(3),vy0+s(9)),fill=(36,38,44,255))
    if kind=='xp':
        bw,bh=s(44),s(24); bxx=ix1-bw-s(6); byy=iy0+s(8)
        paste_grad(im,(bxx,byy,bxx+bw,byy+bh),s(7),(88,160,255),(24,90,214))
        d.rounded_rectangle((bxx,byy,bxx+bw,byy+bh),s(7),outline=(10,50,150,255),width=max(1,S//2))
        f=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',s(15))
        tw=d.textlength('XP',font=f); d.text((bxx+(bw-tw)/2,byy+bh/2-s(9)),'XP',font=f,fill=(255,255,255,255))
    return im.resize((size,size),Image.LANCZOS)
if __name__=='__main__':
    for k in ('mac','xp'):
        im=drive(k); bg=Image.new('RGBA',im.size,(0,0,0,255)); bg.alpha_composite(im); bg.resize((384,384),Image.NEAREST).save(f'icon_{k}.png')
