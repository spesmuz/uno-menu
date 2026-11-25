"""Download dish videos from Supabase, re-encode them small (720p H.264 MP4) into media/v/, write media/opt.json {old_id: new_path}."""
import json, os, subprocess, urllib.request
U="https://eaxavnixuqgwashplnhz.supabase.co"; K="sb_publishable_gILXDU_L8vepyEbsF87Tcg_hYyMpril"
H={"apikey":K,"Authorization":"Bearer "+K}
rows=json.load(urllib.request.urlopen(urllib.request.Request(U+"/rest/v1/uno_docs?select=path,data",headers=H),timeout=60))
os.makedirs("media/v",exist_ok=True)
opt=json.load(open("media/opt.json")) if os.path.exists("media/opt.json") else {}
for r in rows:
    vid=(r.get("data") or {}).get("videoId")
    if not vid or "/" in vid or vid in opt: continue
    src="/tmp/"+vid; out="media/v/"+vid.rsplit(".",1)[0]+".mp4"
    urllib.request.urlretrieve(U+"/storage/v1/object/public/uno-media/"+urllib.request.quote(vid), src)
    subprocess.run(["ffmpeg","-y","-loglevel","error","-i",src,"-vf","scale='if(gt(iw,ih),min(1280,iw),-2)':'if(gt(iw,ih),-2,min(1280,ih))',fps=30",
                    "-c:v","libx264","-preset","slow","-crf","27","-profile:v","high","-pix_fmt","yuv420p","-movflags","+faststart",
                    "-c:a","aac","-b:a","96k","-ac","2",out],check=True)
    print(vid, round(os.path.getsize(src)/1e6,1),"MB ->", round(os.path.getsize(out)/1e6,1),"MB")
    opt[vid]=out
json.dump(opt,open("media/opt.json","w"),indent=1)
