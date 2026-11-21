import numpy as np, struct, math
from PIL import Image, ImageDraw, ImageFont
from lz import lz_compress, lz_decompress
W,H=1024,768
import os
BASE=int(os.environ.get('BASEV','0xE00'),0)
def blend(a,b,t): return tuple(round(a[k]*(1-t)+b[k]*t) for k in range(3))
class Img:
    def __init__(s,w,h,pal,idx):
        s.w,s.h,s.pal,s.idx=w,h,pal,idx
        s.stream=lz_compress(idx.tobytes())
        assert lz_decompress(s.stream,w*h)==idx.tobytes()
        s.bytes=bytes([len(pal)])+b''.join(bytes([c[2],c[1],c[0]]) for c in pal)+s.stream
    def rgbmask(s):
        a=np.zeros((s.h,s.w,3),np.uint8); m=s.idx>0
        P=np.array([(0,0,0)]+list(s.pal),np.uint8); a=P[s.idx]; return a,m
def to_indexed(rgba,edge_bg,thr=24,nc=255):
    a=np.asarray(rgba.convert('RGBA'),np.float32)
    al=a[:,:,3:4]/255.0
    rgb=(a[:,:,:3]*al+np.array(edge_bg,np.float32)*(1-al)).clip(0,255).astype(np.uint8)
    mask=a[:,:,3]>=thr
    q=Image.fromarray(rgb).quantize(nc,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE)
    idx=np.asarray(q,np.uint8).astype(np.int32)+1
    pal=q.getpalette()[:nc*3]
    pal=[tuple(pal[i*3:i*3+3]) for i in range(nc)]
    idx=np.where(mask,idx,0).astype(np.uint8)
    used=sorted(set(idx.flatten().tolist())-{0})
    remap={0:0}; newpal=[]
    for k,u in enumerate(used): remap[u]=k+1; newpal.append(pal[u-1])
    idx=np.vectorize(remap.get)(idx).astype(np.uint8)
    return Img(rgba.width,rgba.height,newpal,idx)
class Scene:
    def __init__(s):
        s.canvas=np.zeros((H,W,3),np.uint8); s.images=[]
    # --- list builders: ops are tuples
def rr_rows(x,y,w,h,r,colfn,bgfn):
    """rounded rect with AA; returns rect tuples (x,y,w,1,color). colfn(i)->rgb fill ; bgfn(abs_y)->rgb"""
    ops=[]
    for i in range(h):
        dy=min(i,h-1-i)+0.5
        if dy<r:
            xe=r-math.sqrt(max(0,r*r-(r-dy)**2))
        else: xe=0.0
        fl=math.floor(xe); fr=xe-fl
        col=colfn(i); bg=bgfn(y+i)
        x0=x+math.ceil(xe-1e-9); x1=x+w-math.ceil(xe-1e-9)
        if x1>x0: ops.append((x0,y+i,x1-x0,1,col))
        if fr>1e-9:
            c=blend(bg,col,1-fr)
            ops.append((x+fl,y+i,1,1,c)); ops.append((x+w-1-fl,y+i,1,1,c))
    return ops
def merge(ops):
    out=[]
    for o in ops:
        if out and out[-1][0]==o[0] and out[-1][2]==o[2] and out[-1][4]==o[4] and out[-1][1]+out[-1][3]==o[1]:
            p=out[-1]; out[-1]=(p[0],p[1],p[2],p[3]+o[3],p[4])
        else: out.append(o)
    return out
def enc_rect(o):
    x,y,w,h,c=o[:5]; return bytes([1])+struct.pack('<HHHHI',x,y,w,h,(c[0]<<16)|(c[1]<<8)|c[2])
def enc_blit(x,y,img,ptr): return bytes([2])+struct.pack('<HHHHH',x,y,img.w,img.h,ptr)
