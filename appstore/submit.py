#!/usr/bin/env python3
"""Fill in the App Store listing through the App Store Connect API and submit the app for review.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, BUNDLE_ID. Screenshots: appstore/shots/<locale>/*.png (1290x2796).
Every step is logged; a step that fails is reported and the script goes on, so one run shows everything missing.
"""
import os, sys, json, time, hashlib, glob, uuid
import jwt, requests

API = "https://api.appstoreconnect.apple.com"
META = json.load(open(os.path.join(os.path.dirname(__file__), "meta.json")))
BUNDLE = os.environ.get("BUNDLE_ID", "uz.uno.airways")
SUBMIT = os.environ.get("SUBMIT", "1") == "1"
LOG = []
PRIMARY = {"l": "en-US"}
EXCLUDE = {"CHN"}


def log(msg):
    print(msg, flush=True)
    LOG.append(msg)


def token():
    key = os.environ["ASC_KEY_P8"]
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


TOK = {"t": None, "at": 0}


def call(method, path, body=None, params=None, ok=(200, 201, 204)):
    if time.time() - TOK["at"] > 900:
        TOK["t"], TOK["at"] = token(), time.time()
    url = path if path.startswith("http") else API + path
    r = requests.request(method, url, params=params, json=body,
                         headers={"Authorization": "Bearer " + TOK["t"], "Content-Type": "application/json"}, timeout=60)
    if r.status_code not in ok:
        try:
            errs = r.json().get("errors", [])
            detail = " | ".join((e.get("title", "") + ": " + e.get("detail", "")) for e in errs)
            for e in errs:
                ae = (e.get("meta") or {}).get("associatedErrors") or {}
                for k, lst in ae.items():
                    for x in lst: detail += f" || {x.get('code','')}: {x.get('detail') or x.get('title','')}"
        except Exception:
            detail = r.text[:500]
        raise RuntimeError(f"{method} {path} -> {r.status_code}: {detail}")
    return r.json() if r.text else {}


def step(name, fn):
    try:
        res = fn()
        log(f"OK   {name}" + (f" — {res}" if isinstance(res, str) and res else ""))
        return True
    except Exception as e:
        log(f"FAIL {name} — {e}")
        return False


def main():
    apps = call("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE})["data"]
    if not apps:
        log(f"FAIL app {BUNDLE} not found in App Store Connect"); return
    app = apps[0]; APP = app["id"]
    log(f"OK   app {app['attributes'].get('name')} ({APP}), primary locale {app['attributes'].get('primaryLocale')}")
    PRIMARY["l"] = app["attributes"].get("primaryLocale") or "en-US"

    # --- app-level: content rights, category, app info localizations (subtitle, privacy URL)
    step("content rights", lambda: call("PATCH", f"/v1/apps/{APP}", {"data": {"type": "apps", "id": APP,
          "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}}) and "")

    infos = call("GET", f"/v1/apps/{APP}/appInfos")["data"]
    info = next((i for i in infos if i["attributes"].get("appStoreState") in (None, "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "WAITING_FOR_REVIEW") or i["attributes"].get("state") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED")), infos[0])
    INFO = info["id"]
    step("category", lambda: call("PATCH", f"/v1/appInfos/{INFO}", {"data": {"type": "appInfos", "id": INFO, "relationships": {
          "primaryCategory": {"data": {"type": "appCategories", "id": META["category"]}}}}}) and "")

    def info_locs():
        have = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/appInfos/{INFO}/appInfoLocalizations")["data"]}
        for loc, m in META["locales"].items():
            attrs = {"subtitle": m["subtitle"], "privacyPolicyUrl": m["privacyPolicyUrl"]}
            if loc in have:
                call("PATCH", f"/v1/appInfoLocalizations/{have[loc]['id']}", {"data": {"type": "appInfoLocalizations", "id": have[loc]["id"], "attributes": attrs}})
            else:
                attrs.update({"locale": loc, "name": app["attributes"].get("name") or "UNO Airways"})
                call("POST", "/v1/appInfoLocalizations", {"data": {"type": "appInfoLocalizations", "attributes": attrs,
                     "relationships": {"appInfo": {"data": {"type": "appInfos", "id": INFO}}}}})
        return ", ".join(META["locales"])
    step("app info (subtitle, privacy policy URL)", info_locs)

    # --- age rating: everything "none"; guests can post dish reviews (moderated) → user generated content
    def age():
        d = call("GET", f"/v1/appInfos/{INFO}/ageRatingDeclaration")["data"]
        cur = d["attributes"]
        enums = ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons", "horrorOrFearThemes",
                 "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity",
                 "sexualContentOrNudity", "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"]
        bools_false = ["gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat", "parentalControls", "ageAssurance",
                       "advertising", "healthOrWellnessTopics", "seventeenPlus", "socialMedia", "datingAndRelationships", "sharedLocation", "socialMediaAgeRestricted"]
        attrs = {}
        for k in enums:
            if k in cur: attrs[k] = "NONE"
        for k in bools_false:
            if k in cur: attrs[k] = False
        if "userGeneratedContent" in cur: attrs["userGeneratedContent"] = True
        import re
        for _ in range(12):
            try:
                call("PATCH", f"/v1/ageRatingDeclarations/{d['id']}", {"data": {"type": "ageRatingDeclarations", "id": d["id"], "attributes": attrs}})
                break
            except RuntimeError as e:
                m = re.search(r"attribute '(\w+)'", str(e))
                if not m or m.group(1) in attrs: raise
                k = m.group(1)
                attrs[k] = "NONE" if any(w in k for w in ("Themes", "Reference", "Violence", "violence", "Nudity", "Humor", "Information", "Weapons", "contests", "Simulated")) else False
                log(f"     age rating: added {k}={attrs[k]}")
        left = [k for k, v in call("GET", f"/v1/appInfos/{INFO}/ageRatingDeclaration")["data"]["attributes"].items() if v is None and k not in ("kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride", "developerAgeRatingInfoUrl")]
        return "unset: " + ",".join(left) if left else ""
    step("age rating", age)

    # --- price: free, available everywhere
    def price():
        try:
            call("GET", f"/v1/apps/{APP}/appPriceSchedule"); have = True
        except Exception:
            have = False
        if have:
            try:
                cur = call("GET", f"/v1/apps/{APP}/appPriceSchedule/manualPrices")["data"]
                if cur: return "already set"
            except Exception:
                pass
        pts = call("GET", f"/v1/apps/{APP}/appPricePoints", params={"filter[territory]": "USA", "limit": 200})["data"]
        free = next(p for p in pts if float(p["attributes"].get("customerPrice") or 0) == 0)
        pid = "${p1}"
        call("POST", "/v1/appPriceSchedules", {"data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": APP}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": pid}]}}},
            "included": [{"type": "appPrices", "id": pid, "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}]})
        return "free"
    step("price (free)", price)

    def availability():
        try:
            a = call("GET", f"/v1/apps/{APP}/appAvailabilityV2")
            if a.get("data"):
                # mainland China needs its own government filing (and two China-only compliance forms): leave it out
                AID = a["data"]["id"]; off = []
                url = f"/v2/appAvailabilities/{AID}/territoryAvailabilities"; params = {"limit": 200, "include": "territory"}
                while url:
                    r = call("GET", url, params=params)
                    for t in r["data"]:
                        tid = ((t.get("relationships") or {}).get("territory") or {}).get("data", {}).get("id")
                        if tid in EXCLUDE and t["attributes"].get("available"):
                            call("PATCH", f"/v1/territoryAvailabilities/{t['id']}", {"data": {"type": "territoryAvailabilities", "id": t["id"], "attributes": {"available": False}}})
                            off.append(tid)
                    url = r.get("links", {}).get("next"); params = None
                return "already set" + (f"; removed {','.join(off)}" if off else "")
        except Exception as e:
            if "removed" in str(e) or "PATCH" in str(e): raise
            pass
        terr = []
        url = "/v1/territories"; params = {"limit": 200}
        while url:
            r = call("GET", url, params=params); terr += [t["id"] for t in r["data"]]
            url = r.get("links", {}).get("next"); params = None
        rel, inc = [], []
        for i, t in enumerate(terr):
            lid = "${t%d}" % i
            rel.append({"type": "territoryAvailabilities", "id": lid})
            inc.append({"type": "territoryAvailabilities", "id": lid, "attributes": {"available": t not in EXCLUDE},
                        "relationships": {"territory": {"data": {"type": "territories", "id": t}}}})
        payload = {"data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
             "relationships": {"app": {"data": {"type": "apps", "id": APP}}, "territoryAvailabilities": {"data": rel}}}, "included": inc}
        for n in range(3):
            try:
                call("POST", "/v2/appAvailabilities", payload); break
            except Exception as e:
                if n == 2: raise
                time.sleep(5)
        return f"{len(terr)} territories"
    step("availability (all countries)", availability)

    # --- the version
    vers = call("GET", f"/v1/apps/{APP}/appStoreVersions", params={"filter[platform]": "IOS", "limit": 20})["data"]
    def vstate(v): return v["attributes"].get("appVersionState") or v["attributes"].get("appStoreState")
    log("     versions: " + ", ".join(f"{v['attributes'].get('versionString')}={vstate(v)}" for v in vers))
    if any(vstate(v) in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE") for v in vers):
        log("SKIP a version is already with App Review — nothing changed"); return
    editable = [v for v in vers if vstate(v) in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")]
    attrs = {"versionString": META["version"], "copyright": META["copyright"], "releaseType": "AFTER_APPROVAL"}
    if editable:
        V = editable[0]["id"]
        try:
            call("PATCH", f"/v1/appStoreVersions/{V}", {"data": {"type": "appStoreVersions", "id": V, "attributes": attrs}})
        except Exception as e:
            log(f"WARN version attrs — {e}")
        log(f"OK   version {META['version']} ({V}, was {editable[0]['attributes'].get('versionString')})")
    else:
        V = call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions", "attributes": dict(attrs, platform="IOS"),
                 "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]["id"]
        log(f"OK   version {META['version']} created ({V})")

    # --- version localizations: description, keywords, URLs, screenshots
    def vlocs():
        have = {l["attributes"]["locale"]: l["id"] for l in call("GET", f"/v1/appStoreVersions/{V}/appStoreVersionLocalizations")["data"]}
        for loc, m in META["locales"].items():
            a = {k: m[k] for k in ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl")}
            if loc in have:
                call("PATCH", f"/v1/appStoreVersionLocalizations/{have[loc]}", {"data": {"type": "appStoreVersionLocalizations", "id": have[loc], "attributes": a}})
            else:
                have[loc] = call("POST", "/v1/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations",
                    "attributes": dict(a, locale=loc), "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": V}}}}})["data"]["id"]
        VLOC.update(have)
        return ", ".join(META["locales"])
    VLOC = {}
    step("description, keywords, URLs", vlocs)

    def shots(loc):
        files = sorted(glob.glob(os.path.join(os.path.dirname(__file__), "shots", loc, "*.png"))) or \
                (sorted(glob.glob(os.path.join(os.path.dirname(__file__), "shots", "main", "*.png"))) if loc == PRIMARY["l"] else [])
        if not files: return "no files"
        lid = VLOC[loc]
        sets = call("GET", f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets")["data"]
        st = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"), None)
        if st:
            for sc in call("GET", f"/v1/appScreenshotSets/{st['id']}/appScreenshots")["data"]:
                call("DELETE", f"/v1/appScreenshots/{sc['id']}")
            SID = st["id"]
        else:
            SID = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
                       "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": lid}}}}})["data"]["id"]
        for f in files[:10]:
            data = open(f, "rb").read()
            sc = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": os.path.basename(f), "fileSize": len(data)},
                      "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": SID}}}}})["data"]
            for op in sc["attributes"]["uploadOperations"]:
                part = data[op["offset"]: op["offset"] + op["length"]]
                h = {x["name"]: x["value"] for x in op.get("requestHeaders", [])}
                r = requests.request(op["method"], op["url"], data=part, headers=h, timeout=120)
                if r.status_code >= 300: raise RuntimeError(f"upload part {r.status_code}")
            call("PATCH", f"/v1/appScreenshots/{sc['id']}", {"data": {"type": "appScreenshots", "id": sc["id"],
                 "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        return f"{min(10, len(files))} screenshots"
    for loc in META["locales"]:
        if loc in VLOC: step(f"screenshots {loc}", lambda loc=loc: shots(loc))

    # --- build
    def build():
        for _ in range(40):
            bs = call("GET", "/v1/builds", params={"filter[app]": APP, "filter[preReleaseVersion.version]": META["version"],
                      "sort": "-uploadedDate", "limit": 1})["data"]
            if bs and bs[0]["attributes"].get("processingState") == "VALID": break
            time.sleep(30)
        if not bs: raise RuntimeError(f"no build {META['version']} uploaded")
        b = bs[0]
        if b["attributes"].get("processingState") != "VALID": raise RuntimeError("build still processing: " + str(b["attributes"].get("processingState")))
        if b["attributes"].get("usesNonExemptEncryption") is None:
            call("PATCH", f"/v1/builds/{b['id']}", {"data": {"type": "builds", "id": b["id"], "attributes": {"usesNonExemptEncryption": False}}})
        call("PATCH", f"/v1/appStoreVersions/{V}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
        return f"build {b['attributes'].get('version')}"
    step("attach build", build)

    # --- review contact
    def review():
        r = META["review"]
        a = {"contactFirstName": r["contactFirstName"], "contactLastName": r["contactLastName"], "contactPhone": r["contactPhone"],
             "contactEmail": r["contactEmail"], "demoAccountRequired": False, "notes": r["notes"]}
        try:
            cur = call("GET", f"/v1/appStoreVersions/{V}/appStoreReviewDetail")["data"]
        except Exception:
            cur = None
        if cur:
            call("PATCH", f"/v1/appStoreReviewDetails/{cur['id']}", {"data": {"type": "appStoreReviewDetails", "id": cur["id"], "attributes": a}})
        else:
            call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": a,
                 "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": V}}}}})
        return ""
    step("App Review contact & notes", review)

    if not SUBMIT:
        log("SKIP submit (SUBMIT=0)"); return

    # --- submit for review
    def submit():
        subs = call("GET", "/v1/reviewSubmissions", params={"filter[app]": APP, "filter[platform]": "IOS", "limit": 20})["data"]
        open_ = next((s for s in subs if s["attributes"].get("state") in ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES")), None)
        busy = next((s for s in subs if s["attributes"].get("state") in ("WAITING_FOR_REVIEW", "IN_REVIEW")), None)
        if busy: return "already in review (" + busy["attributes"]["state"] + ")"
        SID = open_["id"] if open_ else call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
              "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]["id"]
        items = call("GET", f"/v1/reviewSubmissions/{SID}/items")["data"]
        log("     submission " + (open_["attributes"].get("state") if open_ else "new") + "; items: " + ", ".join(i["attributes"].get("state", "?") for i in items))
        if open_ and open_["attributes"].get("state") == "UNRESOLVED_ISSUES":
            # after a rejection the old submission keeps the rejected item: cancel it and send a fresh one
            try:
                call("PATCH", f"/v1/reviewSubmissions/{SID}", {"data": {"type": "reviewSubmissions", "id": SID, "attributes": {"canceled": True}}})
                log("     old rejected submission canceled")
                for _ in range(20):
                    st = call("GET", f"/v1/reviewSubmissions/{SID}")["data"]["attributes"].get("state")
                    if st not in ("CANCELING",): break
                    time.sleep(15)
            except Exception as e:
                log(f"     cancel failed — {e}")
            SID = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                  "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]["id"]
            items = []
        if not items:
            call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
                 "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": SID}},
                 "appStoreVersion": {"data": {"type": "appStoreVersions", "id": V}}}}})
        for k in range(16):   # freshly uploaded screenshots / build need a few minutes before Apple accepts the submission
            try:
                call("PATCH", f"/v1/reviewSubmissions/{SID}", {"data": {"type": "reviewSubmissions", "id": SID, "attributes": {"submitted": True}}})
                break
            except RuntimeError as e:
                if "not ready" not in str(e) and "STATE_ERROR" not in str(e) or k == 15: raise
                log(f"     not ready yet, waiting ({k+1})"); time.sleep(45)
        return "SUBMITTED — waiting for review"
    step("submit for review", submit)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log(f"FAIL fatal — {e}")
    os.makedirs("out", exist_ok=True)
    open("out/appstore.log", "w").write("\n".join(LOG) + "\n")
