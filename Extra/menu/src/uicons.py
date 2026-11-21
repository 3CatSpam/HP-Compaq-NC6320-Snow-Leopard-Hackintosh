from PIL import Image, ImageDraw, ImageFilter
import numpy as np
def load(path,maxdim=134):
    im=Image.open(path).convert('RGBA')
    a=np.asarray(im)
    if a[:,:,3].min()==255:
        # white background connected to border -> transparent
        near=((a[:,:,:3]>=246).all(2)).astype(np.uint8)*255
        m=Image.fromarray(near,'L')
        from scipy import ndimage
        lab,n=ndimage.label(near>0)
        border=set(lab[0,:])|set(lab[-1,:])|set(lab[:,0])|set(lab[:,-1]); border.discard(0)
        bg=np.isin(lab,list(border)).astype(np.float32)
        bgs=Image.fromarray((bg*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
        alpha=255-np.asarray(bgs).astype(np.int32)
        alpha=np.clip((alpha-30)*255//195,0,255).astype(np.uint8)
        im.putalpha(Image.fromarray(alpha))
    bb=im.split()[3].point(lambda v:255 if v>8 else 0).getbbox()
    im=im.crop(bb)
    s=maxdim/max(im.size)
    return im.resize((max(1,round(im.width*s)),max(1,round(im.height*s))),Image.LANCZOS)
if __name__=='__main__':
    for n in ('mac','xp'):
        i=load(f'ico_{n}_src.png'); print(n,i.size)
        bg=Image.new('RGBA',i.size,(40,40,40,255)); bg.alpha_composite(i); bg.resize((i.width*3,i.height*3)).save(f'ico_{n}_t.png')
