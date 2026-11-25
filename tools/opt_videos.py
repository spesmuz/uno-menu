"""Light, colour-enhanced copies of dish media, served from this site (saves Supabase traffic).
Videos: square crop (what the menu card shows), no sound, up to 1080x1080 H.264.  Photos: up to 1200 px JPEG.
Exposure is checked per file: only too dark or too bright media are corrected; normal ones keep their colours. media/opt.json maps original id -> copy;
the same map is written into index.html (var VOPT) so the menu uses the copies at once."""
import json, os, re, subprocess, urllib.request
U="https://eaxavnixuqgwashplnhz.supabase.co"; K="sb_publishable_gILXDU_L8vepyEbsF87Tcg_hYyMpril"
H={"apikey":K,"Authorization":"Bearer "+K}
TAG="-c3"   # bump to rebuild every copy with new settings
VCOL="unsharp=5:5:0.35"
PCOL="unsharp=5:5:0.3"
rows=json.load(urllib.request.urlopen(urllib.request.Request(U+"/rest/v1/uno_docs?select=path,data",headers=H),timeout=60))
for d in ("media/v","media/p","/tmp/cmp"): os.makedirs(d,exist_ok=True)
opt=json.load(open("media/opt.json")) if os.path.exists("media/opt.json") else {}
def ff(*a): subprocess.run(["ffmpeg","-y","-loglevel","error",*a],check=True)
def expose(src, video):
    """Exposure check of the dish itself (pixels of the dark studio background are left out).
    Normal light -> untouched. Too dark -> brightened. Too bright / burnt-out -> calmed. Black stays black."""
    import math
    vf=("fps=1," if video else "")+"scale=240:-2,format=gray"
    raw=subprocess.run(["ffmpeg","-loglevel","error","-i",src,"-vf",vf,"-frames:v","8" if video else "1","-f","rawvideo","-"],capture_output=True,check=True).stdout
    fg=sorted(b for b in raw if b>40)
    if len(fg)<len(raw)*0.04: print("   light: too little dish found -> untouched"); return ""
    n=len(fg); med=fg[n//2]; p97=fg[min(n-1,int(n*0.97))]; clip=sum(1 for b in fg if b>=248)/n
    if med<88:
        gain=max(1.0,min(1.35,112.0/med,245.0/max(1,p97))); w=1.0/gain
        print(f"   light: dish median {med}, top {p97}, burnt {clip:.1%} -> TOO DARK, brighten x{gain:.2f}")
        return f"colorlevels=rimax={w:.3f}:gimax={w:.3f}:bimax={w:.3f}," if gain>1.02 else ""
    if med>172 or clip>0.06:
        g=max(0.72,min(0.95,math.log(150/255.0)/math.log(min(250,med)/255.0)))
        print(f"   light: dish median {med}, top {p97}, burnt {clip:.1%} -> TOO BRIGHT, gamma {g:.2f}")
        return f"eq=gamma={g:.3f},"
    print(f"   light: dish median {med}, top {p97}, burnt {clip:.1%} -> normal, untouched")
    return ""
for r in rows:
    if not r["path"].startswith("dishes/"): continue
    data=r.get("data") or {}
    for key in ("videoId","imgId"):
        mid=data.get(key)
        if not mid or "/" in mid or TAG in opt.get(mid,""): continue
        src="/tmp/"+mid; base=mid.rsplit(".",1)[0]
        urllib.request.urlretrieve(U+"/storage/v1/object/public/uno-media/"+urllib.request.quote(mid), src)
        if key=="videoId":
            out="media/v/"+base+TAG+".mp4"
            ff("-i",src,"-vf","crop='min(iw,ih)':'min(iw,ih)',scale='min(1080,min(iw,ih))':'min(1080,min(iw,ih))':flags=lanczos,fps=30,"+expose(src,True)+VCOL,
               "-c:v","libx264","-preset","slow","-crf","22","-profile:v","high","-pix_fmt","yuv420p","-movflags","+faststart","-an",out)
            ff("-ss","1.5","-i",src,"-vf","crop='min(iw,ih)':'min(iw,ih)',scale=540:540","-frames:v","1","/tmp/a.png")
            ff("-ss","1.5","-i",out,"-vf","scale=540:540","-frames:v","1","/tmp/b.png")
        else:
            out="media/p/"+base+TAG+".jpg"
            ff("-i",src,"-vf","scale='min(1200,iw)':-2:flags=lanczos,"+expose(src,False)+PCOL,"-q:v","3",out)
            ff("-i",src,"-vf","scale=540:-2","/tmp/a.png"); ff("-i",out,"-vf","scale=540:-2","/tmp/b.png")
        ff("-i","/tmp/a.png","-i","/tmp/b.png","-filter_complex","[0][1]scale2ref[a][b];[a][b]hstack","/tmp/cmp/"+base+".jpg")
        print(key, mid, round(os.path.getsize(src)/1e6,2),"MB ->", round(os.path.getsize(out)/1e6,2),"MB")
        old=opt.get(mid)
        if old and old!=out and os.path.exists(old): os.remove(old)
        opt[mid]=out
json.dump(opt,open("media/opt.json","w"),indent=1)
h=open("index.html").read()
h2=re.sub(r"var VOPT=\{.*?\};", "var VOPT="+json.dumps(opt,separators=(",",":"))+";", h, count=1)
if h2!=h: open("index.html","w").write(h2)
