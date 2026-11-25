import json, urllib.request
U="https://eaxavnixuqgwashplnhz.supabase.co"; K="sb_publishable_gILXDU_L8vepyEbsF87Tcg_hYyMpril"
H={"apikey":K,"Authorization":"Bearer "+K}
def get(url, method="GET", body=None, extra=None):
    h=dict(H); h.update(extra or {})
    r=urllib.request.Request(url, data=body, headers=h, method=method)
    return urllib.request.urlopen(r, timeout=60)
rows=json.load(get(U+"/rest/v1/uno_docs?select=path,data"))
ids=[]
for r in rows:
    d=r.get("data") or {}
    for k in ("imgId","videoId","logoId"):
        if d.get(k): ids.append((r["path"],k,d[k]))
print("docs",len(rows),"media refs",len(ids))
tot={"imgId":0,"videoId":0,"logoId":0}; lst=[]
for p,k,i in ids:
    url=i if i.startswith("http") else U+"/storage/v1/object/public/uno-media/"+urllib.request.quote(i)
    try:
        r=get(url,"HEAD"); n=int(r.headers.get("Content-Length") or 0); cc=r.headers.get("Cache-Control"); ct=r.headers.get("Content-Type")
    except Exception as e: n=0; cc=str(e); ct=""
    tot[k]+=n; lst.append((n,p,k,ct,cc))
lst.sort(reverse=True)
for n,p,k,ct,cc in lst[:40]: print(f"{n/1e6:8.2f} MB  {k:7} {ct:12} {p}  cc={cc}")
print({k:round(v/1e6,1) for k,v in tot.items()}, "MB total", round(sum(tot.values())/1e6,1))
try:
    b=json.load(get(U+"/storage/v1/object/list/uno-media","POST",json.dumps({"prefix":"","limit":1000}).encode(),{"Content-Type":"application/json"}))
    s=sum((o.get("metadata") or {}).get("size",0) for o in b); print("bucket files",len(b),"size MB",round(s/1e6,1))
except Exception as e: print("bucket list:",e)
