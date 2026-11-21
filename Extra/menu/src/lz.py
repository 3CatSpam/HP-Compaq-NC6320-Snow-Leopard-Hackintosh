def lz_compress(data):
    data=bytes(data); n=len(data); out=bytearray(); i=0
    W=4096; MAXL=18
    heads={}
    items=[]
    def key(i): return data[i:i+3]
    while i<n:
        best=0; bd=0
        if i+3<=n:
            cand=heads.get(key(i),[])
            for j in reversed(cand[-48:]):
                d=i-j
                if d>W: break
                l=0
                lim=min(MAXL,n-i)
                while l<lim and data[j+l]==data[i+l]: l+=1
                if l>best: best=l; bd=d
                if best==MAXL: break
        if best>=3:
            items.append((0,bd,best)); step=best
        else:
            items.append((1,data[i],0)); step=1
        for k in range(i,i+step):
            if k+3<=n: heads.setdefault(key(k),[]).append(k)
        i+=step
    for g in range(0,len(items),8):
        grp=items[g:g+8]; flags=0; body=bytearray()
        for b,(t,a,l) in enumerate(grp):
            if t==1: flags|=1<<b; body.append(a)
            else:
                dd=a-1; body.append(dd&0xff); body.append(((dd>>8)<<4)|(l-3))
        out.append(flags); out+=body
    return bytes(out)
def lz_decompress(src,size):
    out=bytearray(); i=0
    while len(out)<size:
        fl=src[i]; i+=1
        for b in range(8):
            if len(out)>=size: break
            if fl>>b&1: out.append(src[i]); i+=1
            else:
                lo=src[i]; hi=src[i+1]; i+=2
                d=(((hi>>4)<<8)|lo)+1; l=(hi&15)+3
                for _ in range(l): out.append(out[-d])
    return bytes(out[:size])
