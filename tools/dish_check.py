"""Diagnostics: every dish with its photo/video ids, optimized copies and the video codec."""
import json, os, subprocess, urllib.request
U="https://eaxavnixuqgwashplnhz.supabase.co"; K="sb_publishable_gILXDU_L8vepyEbsF87Tcg_hYyMpril"
H={"apikey":K,"Authorization":"Bearer "+K}
rows=json.load(urllib.request.urlopen(urllib.request.Request(U+"/rest/v1/uno_docs?select=path,data,updated_at&path=like.dishes/*",headers=H),timeout=60))
opt=json.load(open("media/opt.json"))
def probe(src):
    r=subprocess.run(["ffprobe","-v","error","-show_entries","stream=codec_name,width,height,pix_fmt:format=duration,size","-of","compact",src],capture_output=True,text=True)
    return (r.stdout+r.stderr).replace("\n"," | ")[:300]
for r in rows:
    d=r.get("data") or {}
    v=d.get("videoId") or ""; i=d.get("imgId") or ""
    print("DISH", r["path"], "|", d.get("name"), "|", d.get("name_ru"), "| img:", i, "| vid:", v, "| upd:", d.get("updatedAt"))
    if v:
        print("   opt:", opt.get(v), "exists:", os.path.exists(opt.get(v) or "-"))
        src="/tmp/x_"+v.replace("/","_")
        try:
            urllib.request.urlretrieve(U+"/storage/v1/object/public/uno-media/"+urllib.request.quote(v), src)
            print("   orig:", probe(src))
        except Exception as e: print("   orig download error:", e)
        if opt.get(v) and os.path.exists(opt[v]): print("   copy:", probe(opt[v]))
