"""Read-only check: are the newer database functions installed, and which news posts are visible."""
import json, urllib.request
U="https://eaxavnixuqgwashplnhz.supabase.co"; K="sb_publishable_gILXDU_L8vepyEbsF87Tcg_hYyMpril"
H={"apikey":K,"Authorization":"Bearer "+K,"Content-Type":"application/json"}
def rpc(fn,args):
    try:
        r=urllib.request.urlopen(urllib.request.Request(U+"/rest/v1/rpc/"+fn,data=json.dumps(args).encode(),headers=H),timeout=30)
        return "OK "+r.read().decode()[:200]
    except urllib.error.HTTPError as e: return "HTTP %d %s"%(e.code,e.read().decode()[:160])
for fn,a in [("uno_bday_gift",{"p_device":"check-x","p_lang":"uz"}),("uno_my_birthday",{"p_device":"check-x"}),("uno_media_kick",{}),("uno_waiter_calls",{"p_token":"check-x"})]:
    print("FN",fn,"->",rpc(fn,a))
rows=json.load(urllib.request.urlopen(urllib.request.Request(U+"/rest/v1/uno_docs?select=path,data&path=like.news/*",headers=H),timeout=30))
for r in rows:
    d=r.get("data") or {}
    print("NEWS",r["path"],"hidden" if d.get("hidden") else "visible","|",d.get("title"),"|",d.get("title_ru"))
s=json.load(urllib.request.urlopen(urllib.request.Request(U+"/rest/v1/uno_docs?select=data&path=eq.settings/main",headers=H),timeout=30))
g=(s[0]["data"] or {}).get("grow",{}) if s else {}
print("GROW bdayOn",g.get("bdayOn"),"| text:",g.get("bdayText"),"| ru:",g.get("bdayText_ru"))
