import numpy as np, struct, math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from scene import *
import art
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
CX=[356,668]; TILE_Y=236; TILE=178; REG_Y=226; REG_H=310; REG_W=230
BAR=(352,684,320,4)
SECS=8
def text_rgba(txt,size,color,w=None,pad=2):
    f=ImageFont.truetype(FONT,size)
    d=ImageDraw.Draw(Image.new('L',(1,1)))
    tw=int(d.textlength(txt,font=f))
    ww=w or tw+2*pad
    h=size+8
    m=Image.new('L',(ww,h),0); ImageDraw.Draw(m).text(((ww-tw)//2,2),txt,font=f,fill=255)
    im=Image.new('RGBA',(ww,h),color+(0,)); im.putalpha(m); return im
def arrow_rgba(color,S=4,size=52):
    im=Image.new('RGBA',(size*S,size*S),(0,0,0,0)); d=ImageDraw.Draw(im)
    d.ellipse((2*S,2*S,(size-2)*S,(size-2)*S),outline=color+(255,),width=3*S)
    c=size*S//2
    d.polygon([(c,c-13*S),(c-12*S,c+1*S),(c-5*S,c+1*S),(c-5*S,c+13*S),(c+5*S,c+13*S),(c+5*S,c+1*S),(c+12*S,c+1*S)],fill=color+(255,))
    return im.resize((size,size),Image.LANCZOS)
def with_shadow(ic):
    pad=18; w=ic.width+2*pad; h=ic.height+2*pad
    sh=Image.new('RGBA',(w,h),(0,0,0,0)); a=ic.split()[3].point(lambda v:int(v*0.5))
    layer=Image.new('RGBA',ic.size,(0,0,0,255)); layer.putalpha(a)
    sh.paste(layer,(pad,pad+8),layer); sh=sh.filter(ImageFilter.GaussianBlur(7))
    sh.alpha_composite(ic,(pad,pad)); return sh,pad
def with_reflection(ic):
    h=56; gap=3
    w=ic.width; im=Image.new('RGBA',(w,ic.height+gap+h),(0,0,0,0)); im.alpha_composite(ic,(0,0))
    fl=ic.transpose(Image.FLIP_TOP_BOTTOM).crop((0,0,w,h))
    a=np.asarray(fl.split()[3],np.float32)
    fade=np.linspace(0.42,0,h)[:,None]
    fl.putalpha(Image.fromarray((a*fade).astype(np.uint8)))
    im.alpha_composite(fl,(0,ic.height+gap)); return im,0
class Design:
    def __init__(s,name,bgfn,stars,hl,label_col,edge_bg,fx,arrow_col,bar_track,bar_fill,hint_col,hint,label_edge=None,nc=160):
        s.name=name; s.bgfn=bgfn; s.stars=stars; s.hl=hl; s.label_col=label_col; s.edge_bg=edge_bg; s.fx=fx
        s.arrow_col=arrow_col; s.bar_track=bar_track; s.bar_fill=bar_fill; s.hint_col=hint_col; s.hint=hint
        s.label_edge=label_edge or edge_bg; s.nc=nc
    def bg_ops(s,x,y,w,h):
        ops=[(x,yy,w,1,s.bgfn(yy)) for yy in range(y,y+h)]
        ops=merge(ops)
        st=[(sx,sy,sz,c) for (sx,sy,sz,c) in s.stars if sx>=x and sy>=y and sx+sz<=x+w and sy+sz<=y+h]
        return ops+[(sx,sy,sz,sz,c) for (sx,sy,sz,c) in st]
    def build(s):
        images=[]; 
        def addimg(img): images.append(img); return len(images)-1
        icons=[]
        for kind in ('mac','xp'):
            import uicons; ic=uicons.load(f'ico_{kind}_src.png',134)
            if s.fx=='shadow': ic,pad=with_shadow(ic)
            elif s.fx=='reflect': ic,pad=with_reflection(ic)
            else: pad=0
            icons.append((addimg(to_indexed(ic,s.edge_bg,nc=s.nc)),pad))
        labels=[addimg(to_indexed(text_rgba(t,21,s.label_col,REG_W),s.label_edge)) for t in ('Mac OS X','Windows XP')]
        arrow=addimg(to_indexed(arrow_rgba(s.arrow_col),s.edge_bg))
        hint=addimg(to_indexed(text_rgba(s.hint,15,s.hint_col,640),s.label_edge))
        # pointer layout
        hdr=26; off=BASE+hdr; ptrs=[]; boff=0
        for im in images: ptrs.append(0x40000+boff); boff+=len(im.bytes)
        lists={}
        def L(): return []
        st=[]  # items: ('r',tuple) or ('b',x,y,imgidx)
        st+= [('r',o) for o in s.bg_ops(0,0,W,H)]
        st+= [('r',o) for o in getattr(s,'extra',[])]
        st.append(('b',(W-images[hint].w)//2,724,hint))
        lists['static']=st
        for i in range(2):
            cx=CX[i]
            for sel in (0,1):
                l=[('r',o) for o in s.bg_ops(cx-REG_W//2,REG_Y,REG_W,REG_H)]
                if sel: l+=[('r',o) for o in s.hl(cx-TILE//2,TILE_Y,TILE,TILE,s.bgfn)]
                ii,pad=icons[i]; im=images[ii]
                l.append(('b',cx-im.w//2,TILE_Y+(TILE-im.h+2*pad)//2-pad-4,ii))
                lb=images[labels[i]]; l.append(('b',cx-lb.w//2,TILE_Y+TILE+14,labels[i]))
                if sel: l.append(('b',cx-26,TILE_Y+TILE+14+36,arrow))
                lists[(i,sel)]=l
        bx,by,bw,bh=BAR
        er=[('r',o) for o in s.bg_ops(bx-6,by-6,bw+12,bh+12)]+[('r',(bx,by,bw,bh,s.bar_track))]
        lists['erase']=er
        sp=[('r',o) for o in s.bg_ops(0,0,W,H)]
        ii0,pad0=icons[0]; im0=images[ii0]
        sp.append(('b',(W-im0.w)//2,290-pad0,ii0))
        lb0=images[labels[0]]; sp.append(('b',(W-lb0.w)//2,290+im0.h+24,labels[0]))
        lists['splash']=sp
        # serialize
        def ser(items):
            b=bytearray()
            for it in items:
                if it[0]=='r': b+=enc_rect(it[1])
                else:
                    _,x,y,ii=it; b+=bytes([2])+struct.pack('<HHHHI',x,y,images[ii].w,images[ii].h,ptrs[ii])
            b.append(0); return bytes(b)
        order=['static',(0,0),(0,1),(1,0),(1,1),'erase','splash']
        lp={}; data=b''
        for k in order:
            lp[k]=off+len(data); data+=ser(lists[k])
        fill=(s.bar_fill[0]<<16)|(s.bar_fill[1]<<8)|s.bar_fill[2]
        header=struct.pack('<HHHHHH',lp['static'],lp[(0,0)],lp[(0,1)],lp[(1,0)],lp[(1,1)],lp['erase'])+struct.pack('<HHHH',bx,by,bw,bh)+struct.pack('<I',fill)+struct.pack('<H',lp['splash'])
        assert len(header)==26
        blob=header+data
        s.bank=b''.join(im.bytes for im in images)
        assert len(s.bank)<=62*512,len(s.bank)
        s.images=images; s.lists=lists; s.blob=blob
        return blob
    def raster(s,sel,secs=SECS,auto=True):
        c=np.zeros((H,W,3),np.uint8)
        def apply(items):
            for it in items:
                if it[0]=='r':
                    x,y,w,h,col=it[1][:5]; c[y:y+h,x:x+w]=col
                else:
                    _,x,y,ii=it; im=s.images[ii]; rgb,m=im.rgbmask()
                    reg=c[y:y+im.h,x:x+im.w]; reg[m]=rgb[m]
        apply(s.lists['static'])
        apply(s.lists[(0,1 if sel==0 else 0)]); apply(s.lists[(1,1 if sel==1 else 0)])
        apply(s.lists['erase'])
        if auto:
            bx,by,bw,bh=BAR; w=bw*secs>>3; c[by:by+bh,bx:bx+w]=s.bar_fill
        return c
def mk_stars(seed,n,avoid):
    r=random.Random(seed); out=[]
    while len(out)<n:
        x=r.randrange(6,1016); y=r.randrange(6,760); sz=r.choice((1,1,2))
        box=(x,y,x+sz,y+sz)
        ok=True
        for (ax,ay,aw,ah) in avoid:
            # must be fully inside or fully outside
            inter=not (box[2]<=ax or box[0]>=ax+aw or box[3]<=ay or box[1]>=ay+ah)
            inside=box[0]>=ax and box[1]>=ay and box[2]<=ax+aw and box[3]<=ay+ah
            if inter and not inside: ok=False
        v=r.choice((120,170,230,255)); out.append((x,y,sz,(v,v,min(255,v+20)))) if ok else None
    return out
AVOID=[(CX[0]-REG_W//2,REG_Y,REG_W,REG_H),(CX[1]-REG_W//2,REG_Y,REG_W,REG_H),(BAR[0]-6,BAR[1]-6,BAR[2]+12,BAR[3]+12)]
# ---- A: classic black startup manager ----
def hlA(x,y,w,h,bgfn):
    return merge(rr_rows(x,y,w,h,9,lambda i:tuple(round(140-18*i/(h-1)) for _ in range(3)),bgfn))
def A():
    return Design('A',lambda y:(0,0,0),[],hlA,(255,255,255),(40,40,40),'none',(205,205,205),(48,48,48),(205,205,205),(120,120,120),'arrow keys + Enter  -  or press 1 / 2')
# ---- B: light grey (Snow-Leopard-ish) ----
def bgB(y):
    t=y/(H-1); return tuple(round(a+(b-a)*t) for a,b in zip((236,237,240),(190,193,201)))
def hlB(x,y,w,h,bgfn):
    ops=rr_rows(x,y,w,h,10,lambda i:(150,168,205),bgfn)
    inner=rr_rows(x+1,y+1,w-2,h-2,9,lambda i:blend(bgfn(y+1+i),(255,255,255),0.6),lambda yy:(150,168,205))
    # fix per-row colour for inner
    return merge(ops+inner)
def B():
    return Design('B',bgB,[],hlB,(30,32,40),(222,224,230),'shadow',(70,76,92),(205,208,216),(80,100,150),(110,114,126),'arrow keys + Enter  -  or press 1 / 2')
# ---- C: space glass ----
def bgC(y):
    t=y/(H-1); return tuple(round(a+(b-a)*t) for a,b in zip((46,22,92),(4,8,30)))
def hlC(x,y,w,h,bgfn):
    ops=rr_rows(x,y,w,h,12,lambda i:blend(bgfn(y+i),(255,255,255),0.45),bgfn)
    inner=rr_rows(x+1,y+1,w-2,h-2,11,lambda i:blend(bgfn(y+1+i),(255,255,255),0.16+0.08*(1-i/(h-3))),lambda yy:blend(bgfn(yy),(255,255,255),0.45))
    return merge(ops+inner)
def C():
    return Design('C',bgC,mk_stars(7,70,AVOID),hlC,(255,255,255),(36,22,76),'shadow',(235,235,255),(60,50,100),(210,210,255),(140,135,185),'arrow keys + Enter  -  or press 1 / 2')

def T():
    d=A(); d.name='T'
    cols=[(255,0,0),(0,255,0),(0,0,255),(255,255,0),(0,255,255),(255,0,255),(255,255,255),(255,128,0)]
    ex=[]
    for k in range(8):
        y0=k*100
        ex.append((0,y0,70,100,cols[k]))
        ex.append((0,y0,1024,1,(255,255,255)))
    for x in range(0,1024,128): ex.append((x,0,1,768,(120,120,120)))
    ex+=[(0,0,1024,3,(255,0,0)),(0,765,1024,3,(255,0,0)),(0,0,3,768,(255,0,0)),(1021,0,3,768,(255,0,0))]
    d.extra=ex
    return d

def T2():
    d=A(); d.name='T2'
    ex=[]
    for i,b in enumerate(range(4,10)):
        x=60+i*90
        for y in range(0,768):
            pass
        run=None
        y=0
        while y<768:
            if (y>>b)&1:
                y2=y
                while y2<768 and (y2>>b)&1: y2+=1
                ex.append((x,y,80,y2-y,(255,255,255)))
                y=y2
            else: y+=1
        ex.append((x,0,80,1,(255,0,0)))
    ex+=[(0,0,1024,2,(255,0,0)),(0,766,1024,2,(255,0,0)),(0,0,2,768,(255,0,0)),(1022,0,2,768,(255,0,0))]
    d.extra=ex
    return d
