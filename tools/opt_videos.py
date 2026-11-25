"""Light, colour-enhanced copies of dish media, served from this site (saves Supabase traffic).
Videos: square crop (what the menu card shows), no sound, up to 1080x1080 H.264.  Photos: up to 1200 px JPEG.
Both get a gentle colour boost (saturation, contrast, warmth, sharpness). media/opt.json maps original id -> copy;
the same map is written into index.html (var VOPT) so the menu uses the copies at once."""
import json, os, re, subprocess, urllib.request
U="https://eaxavnixuqgwashplnhz.supabase.co"; K="sb_publishable_gILXDU_L8vepyEbsF87Tcg_hYyMpril"
H={"apikey":K,"Authorization":"Bearer "+K}
TAG="-c2"   # bump to rebuild every copy with new settings
VCOL="eq=saturation=1.22:contrast=1.06,colorbalance=rs=0.03:bs=-0.03:rm=0.02:bm=-0.02,unsharp=5:5:0.6"
PCOL="eq=saturation=1.12:contrast=1.04,colorbalance=rs=0.02:bs=-0.02,unsharp=5:5:0.45"
rows=json.load(urllib.request.urlopen(urllib.request.Request(U+"/rest/v1/uno_docs?select=path,data",headers=H),timeout=60))
for d in ("media/v","media/p","/tmp/cmp"): os.makedirs(d,exist_ok=True)
opt=json.load(open("media/opt.json")) if os.path.exists("media/opt.json") else {}
def ff(*a): subprocess.run(["ffmpeg","-y","-loglevel","error",*a],check=True)
def expose(src, video):
    """How light is the dish itself (its brightest tenth; the dark background is ignored)?
    Dark shots are brightened to a common level, already-bright ones are left alone; black stays black."""
    import math
    vf=("fps=1," if video else "")+"scale=200:-2,format=gray"
    raw=subprocess.run(["ffmpeg","-loglevel","error","-i",src,"-vf",vf,"-frames:v","6" if video else "1","-f","rawvideo","-"],capture_output=True,check=True).stdout
    px=sorted(raw) or [128]; n=len(px); q=lambda f: max(1,px[min(n-1,int(n*f))])
    p80,p90,p97=q(.80),q(.90),q(.97)
    gain=max(1.0,min(1.45,200.0/p90,245.0/p97))
    g=max(1.0,min(1.2,math.log(min(250,p80*gain)/255.0)/math.log(140/255.0)))
    print(f"   light: p80 {p80}, p90 {p90}, p97 {p97} -> gain {gain:.2f}, gamma {g:.2f}")
    w=1.0/gain
    return f"colorlevels=rimin=0.035:gimin=0.035:bimin=0.035:rimax={w:.3f}:gimax={w:.3f}:bimax={w:.3f},eq=gamma={g:.3f}," if gain>1.01 or g>1.01 else ""
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
