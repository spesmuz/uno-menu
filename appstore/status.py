import os, time, jwt, requests
now=int(time.time())
t=jwt.encode({"iss":os.environ["ASC_ISSUER_ID"],"iat":now,"exp":now+600,"aud":"appstoreconnect-v1"},os.environ["ASC_KEY_P8"],algorithm="ES256",headers={"kid":os.environ["ASC_KEY_ID"],"typ":"JWT"})
H={"Authorization":"Bearer "+t}
A="https://api.appstoreconnect.apple.com"
app=requests.get(A+"/v1/apps",params={"filter[bundleId]":"uz.uno.airways"},headers=H).json()["data"][0]["id"]
for v in requests.get(A+f"/v1/apps/{app}/appStoreVersions",params={"limit":5},headers=H).json()["data"]:
    a=v["attributes"]; print("VERSION",a.get("versionString"),a.get("appVersionState") or a.get("appStoreState"),a.get("createdDate"))
for s in requests.get(A+"/v1/reviewSubmissions",params={"filter[app]":app,"limit":5},headers=H).json()["data"]:
    print("SUBMISSION",s["attributes"].get("state"),s["attributes"].get("submittedDate"))
r=requests.get("https://itunes.apple.com/lookup",params={"id":app,"country":"uz"}).json()
print("PUBLIC",r.get("resultCount"),[(x.get("trackName"),x.get("version"),x.get("trackViewUrl")) for x in r.get("results",[])])
