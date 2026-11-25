"""Download dish videos from Supabase, crop to the square the menu card shows, drop sound, 720x720 H.264 MP4 into media/v/; media/opt.json {old_id: new_path}."""
import json, os, subprocess, urllib.request
U="https://eaxavnixuqgwashplnhz.supabase.co"; K="sb_publishable_gILXDU_L8vepyEbsF87Tcg_hYyMpril"
H={"apikey":K,"Authorization":"Bearer "+K}
rows=json.load(urllib.request.urlopen(urllib.request.Request(U+"/rest/v1/uno_docs?select=path,data",headers=H),timeout=60))
os.makedirs("media/v",exist_ok=True)
opt=json.load(open("media/opt.json")) if os.path.exists("media/opt.json") else {}
for r in rows:
    vid=(r.get("data") or {}).get("videoId")
    if not vid or "/" in vid or opt.get(vid,"").endswith("-hq.mp4"): continue
    src="/tmp/"+vid; out="media/v/"+vid.rsplit(".",1)[0]+"-hq.mp4"
    urllib.request.urlretrieve(U+"/storage/v1/object/public/uno-media/"+urllib.request.quote(vid), src)
    subprocess.run(["ffmpeg","-y","-loglevel","error","-i",src,"-vf","crop='min(iw,ih)':'min(iw,ih)',scale='min(1080,min(iw,ih))':'min(1080,min(iw,ih))':flags=lanczos,fps=30",
                    "-c:v","libx264","-preset","slow","-crf","22","-profile:v","high","-pix_fmt","yuv420p","-movflags","+faststart",
                    "-an",out],check=True)
    print(vid, round(os.path.getsize(src)/1e6,1),"MB ->", round(os.path.getsize(out)/1e6,1),"MB")
    old=opt.get(vid)
    if old and old!=out and os.path.exists(old): os.remove(old)
    opt[vid]=out
json.dump(opt,open("media/opt.json","w"),indent=1)

import re
h=open("index.html").read()
h2=re.sub(r"var VOPT=\{.*?\};", "var VOPT="+json.dumps(opt,separators=(",",":"))+";", h, count=1)
if h2!=h: open("index.html","w").write(h2)
