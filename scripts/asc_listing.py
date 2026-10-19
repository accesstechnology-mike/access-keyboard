#!/usr/bin/env python3
"""access: keyboard 1.0 App Store listing in App Store Connect.

  --status   read-only. Prints every current value as JSON (this is the backup
             taken before any write) and writes it to asc-listing-status.json.
  --apply    sets the listing, review details, age rating, price (free),
             availability, product metadata and review screenshots, version
             screenshots, and attaches the newest VALID 1.0 build.

Never submits anything for review. Never touches agreements, banking or tax.
Copy lives in docs/app-store/ so it can be reviewed without reading code.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_store_connect as asc  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
COPY = ROOT / "docs" / "app-store"
APP_ID = "6803257519"
VERSION_STRING = "1.0"
LOCALE = "en-GB"
PRODUCT_LOCALES = ("en-GB", "en-US")
GROUP_NAME = "access: keyboard Pro"
COPYRIGHT = "2026 access: technology"
SUPPORT_URL = "https://accesstechnology.co.uk/contact"
MARKETING_URL = "https://accesstechnology.co.uk/"
PRIVACY_URL = "https://access-keyboard.vercel.app/privacy.html"
SUBTITLE = "Large keys, iPhone and iPad"
PRIMARY_CATEGORY = "UTILITIES"
SECONDARY_CATEGORY = "PRODUCTIVITY"
# Excluded from availability: China mainland (generative AI services need a
# separate licence there, and OpenAI is not offered there).
EXCLUDED_TERRITORIES = {"CHN"}
REVIEW_CONTACT = {
    "contactFirstName": "Mike",
    "contactLastName": "Thrussell",
    "contactEmail": "mike@accesstechnology.co.uk",
    "contactPhone": "+44 1765 824971",
    "demoAccountRequired": False,
}
PRODUCT_COPY = {
    "pro.monthly": ("Pro Monthly", "Up to 100 Fixes a day, billed monthly."),
    "pro.yearly": ("Pro Yearly", "Up to 100 Fixes a day, billed yearly."),
    "pro.lifetime": ("Pro Lifetime", "Up to 100 Fixes a day. Pay once."),
}
PRODUCT_REVIEW_NOTE = (
    "The keyboard and predictions are free. Fix (AI correction of the current "
    "paragraph) is free for 30 Fixes a month. Pro removes the monthly limit, with a "
    "fair-use cap of 100 a day. Pro Monthly GBP 3.99 and Pro Yearly GBP 29.99 each "
    "have a 14-day free trial; Pro Lifetime is GBP 79.99 once. Buy or redeem in the "
    "app: the Pro item in the main list, or Settings > Pro. Restore Purchases is on the same screen."
)
AGE_ENUMS = (
    "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated",
    "gunsOrOtherWeapons", "horrorOrFearThemes", "matureOrSuggestiveThemes",
    "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
    "sexualContentGraphicAndNudity", "sexualContentOrNudity",
    "violenceCartoonOrFantasy", "violenceRealistic",
    "violenceRealisticProlongedGraphicOrSadistic",
)
AGE_BOOLS = (
    "advertising", "ageAssurance", "gambling", "healthOrWellnessTopics", "lootBox",
    "messagingAndChat", "parentalControls", "unrestrictedWebAccess",
    "userGeneratedContent", "socialMedia", "socialMediaAgeRestricted",
)
# display type -> folder in docs/app-store/screenshots
SCREENSHOT_SETS = {
    "APP_IPHONE_67": "iphone-6.9",
    "APP_IPAD_PRO_3GEN_129": "ipad-13",
}
REVIEW_SHOT = COPY / "review" / "paywall.png"

TOKEN = {"value": None, "at": 0.0}


def token() -> str:
    if TOKEN["value"] is None or time.time() - TOKEN["at"] > 600:
        TOKEN["value"] = asc.fresh_token()
        TOKEN["at"] = time.time()
    return TOKEN["value"]


def req(path, params=None, method="GET", body=None):
    for attempt in range(8):
        try:
            return asc.asc_request(token(), path, params, method=method, body=body)
        except asc.ASCHTTPError as exc:
            if exc.code == 429 and attempt < 7:
                time.sleep(min(60, 2 ** attempt))
                continue
            raise


def get(path, params=None):
    return req(path, params)


def get_opt(path, params=None):
    try:
        return get(path, params)
    except asc.ASCHTTPError as exc:
        if exc.code in (404,):
            return {"data": None, "_status": exc.code}
        return {"data": None, "_error": f"{exc.code} {exc.body[:300]}"}


def collect(path, params=None):
    items, included = asc.collect_resources(token(), path, params)
    return items


def ref(kind, ident):
    return {"data": {"type": kind, "id": ident}}


def text(name: str) -> str:
    return (COPY / name).read_text(encoding="utf-8").strip()


def check_copy() -> dict:
    copy = {
        "description": text("description.txt"),
        "keywords": text("keywords.txt"),
        "promotionalText": text("promotional-text.txt"),
        "reviewNotes": text("review-notes.txt"),
    }
    limits = {"description": 4000, "keywords": 100, "promotionalText": 170, "reviewNotes": 4000}
    for key, value in copy.items():
        assert len(value) <= limits[key], (key, len(value))
        assert "\u2014" not in value and "\u2013" not in value, f"dash in {key}"
    assert len(SUBTITLE) <= 30
    return copy


# ---------------------------------------------------------------- read

def version() -> dict:
    items = collect(f"/v1/apps/{APP_ID}/appStoreVersions", {"limit": "50"})
    for item in items:
        a = item["attributes"]
        if a.get("platform") == "IOS" and a.get("versionString") == VERSION_STRING:
            return item
    raise SystemExit(f"No iOS {VERSION_STRING} version")


def app_info() -> dict:
    items = collect(f"/v1/apps/{APP_ID}/appInfos")
    live = [i for i in items if i["attributes"].get("state") not in ("READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_INFO")]
    return (live or items)[0]


def builds() -> list[dict]:
    data = get("/v1/builds", {
        "filter[app]": APP_ID, "limit": "50", "sort": "-uploadedDate",
        "include": "preReleaseVersion",
    })
    pre = {i["id"]: i["attributes"].get("version") for i in data.get("included") or [] if i["type"] == "preReleaseVersions"}
    out = []
    for b in data.get("data") or []:
        a = b["attributes"]
        pid = ((b.get("relationships") or {}).get("preReleaseVersion") or {}).get("data") or {}
        out.append({
            "id": b["id"], "version": a.get("version"), "short": pre.get(pid.get("id")),
            "processingState": a.get("processingState"), "expired": a.get("expired"),
            "usesNonExemptEncryption": a.get("usesNonExemptEncryption"),
            "uploadedDate": a.get("uploadedDate"),
        })
    return out


def products() -> dict:
    out = {"groups": [], "iaps": []}
    for g in collect(f"/v1/apps/{APP_ID}/subscriptionGroups"):
        group = {"id": g["id"], "attributes": g["attributes"],
                 "localizations": collect(f"/v1/subscriptionGroups/{g['id']}/subscriptionGroupLocalizations"),
                 "subscriptions": []}
        for s in collect(f"/v1/subscriptionGroups/{g['id']}/subscriptions"):
            group["subscriptions"].append({
                "id": s["id"], "attributes": s["attributes"],
                "localizations": collect(f"/v1/subscriptions/{s['id']}/subscriptionLocalizations"),
                "reviewScreenshot": get_opt(f"/v1/subscriptions/{s['id']}/appStoreReviewScreenshot").get("data"),
            })
        out["groups"].append(group)
    for i in collect(f"/v1/apps/{APP_ID}/inAppPurchasesV2"):
        out["iaps"].append({
            "id": i["id"], "attributes": i["attributes"],
            "localizations": collect(f"/v2/inAppPurchases/{i['id']}/inAppPurchaseLocalizations"),
            "reviewScreenshot": get_opt(f"/v2/inAppPurchases/{i['id']}/appStoreReviewScreenshot").get("data"),
        })
    return out


def status() -> dict:
    v = version()
    info = app_info()
    locs = collect(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")
    sets = {}
    for loc in locs:
        for s in collect(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets"):
            shots = collect(f"/v1/appScreenshotSets/{s['id']}/appScreenshots")
            sets[s["attributes"]["screenshotDisplayType"]] = {
                "id": s["id"], "locale": loc["attributes"]["locale"],
                "screenshots": [{"id": x["id"], "fileName": x["attributes"].get("fileName"),
                                 "state": (x["attributes"].get("assetDeliveryState") or {}).get("state")} for x in shots],
            }
    availability = get_opt(f"/v1/apps/{APP_ID}/appAvailabilityV2")
    avail_count = None
    if availability.get("data"):
        terr = collect(f"/v2/appAvailabilities/{availability['data']['id']}/territoryAvailabilities", {"limit": "200"})
        avail_count = {"available": sum(1 for t in terr if t["attributes"].get("available")), "total": len(terr)}
    result = {
        "taken_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "app": get(f"/v1/apps/{APP_ID}")["data"]["attributes"],
        "version": {"id": v["id"], "attributes": v["attributes"]},
        "version_localizations": [{"id": l["id"], "attributes": l["attributes"]} for l in locs],
        "screenshot_sets": sets,
        "review_detail": get_opt(f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail").get("data"),
        "attached_build": get_opt(f"/v1/appStoreVersions/{v['id']}/build").get("data"),
        "app_info": {"id": info["id"], "attributes": info["attributes"]},
        "app_info_localizations": [{"id": l["id"], "attributes": l["attributes"]} for l in collect(f"/v1/appInfos/{info['id']}/appInfoLocalizations")],
        "primary_category": get_opt(f"/v1/appInfos/{info['id']}/primaryCategory").get("data"),
        "secondary_category": get_opt(f"/v1/appInfos/{info['id']}/secondaryCategory").get("data"),
        "age_rating": get_opt(f"/v1/appInfos/{info['id']}/ageRatingDeclaration").get("data"),
        "price_schedule": get_opt(f"/v1/apps/{APP_ID}/appPriceSchedule", {"include": "baseTerritory,manualPrices"}),
        "availability": availability.get("data"),
        "availability_counts": avail_count,
        "builds": builds(),
        "products": products(),
    }
    return result


# ---------------------------------------------------------------- write

def upload_asset(create_path: str, kind: str, rel_name: str, parent_kind: str, parent_id: str, path: Path) -> str:
    data = path.read_bytes()
    created = req(create_path, method="POST", body={"data": {
        "type": kind,
        "attributes": {"fileName": path.name, "fileSize": len(data)},
        "relationships": {rel_name: ref(parent_kind, parent_id)},
    }})["data"]
    for op in created["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]: op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        r = urllib.request.Request(op["url"], data=chunk, headers=headers, method=op["method"])
        with urllib.request.urlopen(r, timeout=120) as resp:
            resp.read()
    req(f"{create_path}/{created['id']}", method="PATCH", body={"data": {
        "type": kind, "id": created["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()},
    }})
    for _ in range(30):
        got = get(f"{create_path}/{created['id']}")["data"]["attributes"]
        state = (got.get("assetDeliveryState") or {}).get("state")
        if state in ("COMPLETE", "FAILED"):
            errs = (got.get("assetDeliveryState") or {}).get("errors")
            print(f"  {path.name}: {state} {errs or ''}")
            if state == "FAILED":
                raise SystemExit(f"upload failed: {path.name} {errs}")
            break
        time.sleep(2)
    else:
        print(f"  {path.name}: still processing")
    return created["id"]


def step(name, fn):
    print(f"== {name}")
    try:
        fn()
        return True
    except Exception as exc:  # report every step, carry on with the rest
        print(f"  FAILED: {exc}")
        return False


def apply(copy: dict, before: dict, only: set[str] | None) -> list[str]:
    failed = []
    v = before["version"]
    info = before["app_info"]

    def want(name):
        return only is None or name in only

    def do_version():
        req(f"/v1/appStoreVersions/{v['id']}", method="PATCH", body={"data": {
            "type": "appStoreVersions", "id": v["id"], "attributes": {"copyright": COPYRIGHT}}})
        loc = next(l for l in before["version_localizations"] if l["attributes"]["locale"] == LOCALE)
        req(f"/v1/appStoreVersionLocalizations/{loc['id']}", method="PATCH", body={"data": {
            "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {
                "description": copy["description"], "keywords": copy["keywords"],
                "promotionalText": copy["promotionalText"], "supportUrl": SUPPORT_URL,
                "marketingUrl": MARKETING_URL}}})
        print("  version copyright and en-GB listing set")

    def do_info():
        loc = next(l for l in before["app_info_localizations"] if l["attributes"]["locale"] == LOCALE)
        req(f"/v1/appInfoLocalizations/{loc['id']}", method="PATCH", body={"data": {
            "type": "appInfoLocalizations", "id": loc["id"], "attributes": {
                "subtitle": SUBTITLE, "privacyPolicyUrl": PRIVACY_URL}}})
        req(f"/v1/appInfos/{info['id']}", method="PATCH", body={"data": {
            "type": "appInfos", "id": info["id"], "relationships": {
                "primaryCategory": ref("appCategories", PRIMARY_CATEGORY),
                "secondaryCategory": ref("appCategories", SECONDARY_CATEGORY)}}})
        req(f"/v1/apps/{APP_ID}", method="PATCH", body={"data": {
            "type": "apps", "id": APP_ID, "attributes": {
                "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
        print("  subtitle, privacy URL, categories, content rights set")

    def do_age():
        age = before["age_rating"]
        present = set((age or {}).get("attributes", {}).keys())
        attrs = {k: "NONE" for k in AGE_ENUMS if k in present}
        attrs.update({k: False for k in AGE_BOOLS if k in present})
        if "kidsAgeBand" in present:
            attrs["kidsAgeBand"] = None
        body = {"data": {"type": "ageRatingDeclarations", "id": age["id"], "attributes": attrs}}
        try:
            req(f"/v1/ageRatingDeclarations/{age['id']}", method="PATCH", body=body)
        except asc.ASCHTTPError as exc:
            print(f"  bulk age patch refused ({exc.code}), trying field by field: {exc.body[:300]}")
            for k, val in attrs.items():
                try:
                    req(f"/v1/ageRatingDeclarations/{age['id']}", method="PATCH", body={"data": {
                        "type": "ageRatingDeclarations", "id": age["id"], "attributes": {k: val}}})
                except asc.ASCHTTPError as e2:
                    print(f"  {k}: {e2.code} {e2.body[:200]}")
        print(f"  age rating answered: {len(attrs)} fields")

    def do_review():
        attrs = dict(REVIEW_CONTACT, notes=copy["reviewNotes"])
        rd = before["review_detail"]
        if rd:
            req(f"/v1/appStoreReviewDetails/{rd['id']}", method="PATCH", body={"data": {
                "type": "appStoreReviewDetails", "id": rd["id"], "attributes": attrs}})
        else:
            req("/v1/appStoreReviewDetails", method="POST", body={"data": {
                "type": "appStoreReviewDetails", "attributes": attrs,
                "relationships": {"appStoreVersion": ref("appStoreVersions", v["id"])}}})
        print("  App Review contact and notes set")

    def do_price():
        ps = before["price_schedule"]
        if ps.get("data") and (ps.get("included") or []):
            print("  price schedule exists; left as is:", [i["type"] for i in ps.get("included")])
            return
        points = collect(f"/v1/apps/{APP_ID}/appPricePoints", {"filter[territory]": "GBR", "limit": "200"})
        free = next(p for p in points if float(p["attributes"]["customerPrice"]) == 0.0)
        req("/v1/appPriceSchedules", method="POST", body={
            "data": {"type": "appPriceSchedules", "relationships": {
                "app": ref("apps", APP_ID),
                "baseTerritory": ref("territories", "GBR"),
                "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
            "included": [{"type": "appPrices", "id": "${free}",
                          "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": ref("appPricePoints", free["id"])}}]})
        print("  price set: free, base territory GBR")

    def do_availability():
        if before["availability"]:
            print("  availability exists; counts:", before["availability_counts"])
            return
        territories = [t["id"] for t in collect("/v1/territories", {"limit": "200"}) if t["id"] not in EXCLUDED_TERRITORIES]
        req("/v2/appAvailabilities", method="POST", body={
            "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                     "relationships": {"app": ref("apps", APP_ID), "territoryAvailabilities": {"data": [
                         {"type": "territoryAvailabilities", "id": f"${{{t}}}"} for t in territories]}}},
            "included": [{"type": "territoryAvailabilities", "id": f"${{{t}}}",
                          "attributes": {"available": True},
                          "relationships": {"territory": ref("territories", t)}} for t in territories]})
        print(f"  available in {len(territories)} territories (not {sorted(EXCLUDED_TERRITORIES)})")

    def product_key(product_id: str) -> str:
        return product_id.split("6M3Z27M69P.", 1)[1]

    def do_products():
        prods = before["products"]
        for g in prods["groups"]:
            req(f"/v1/subscriptionGroups/{g['id']}", method="PATCH", body={"data": {
                "type": "subscriptionGroups", "id": g["id"], "attributes": {"referenceName": GROUP_NAME}}})
            have = {l["attributes"]["locale"]: l for l in g["localizations"]}
            for locale in PRODUCT_LOCALES:
                if locale in have:
                    req(f"/v1/subscriptionGroupLocalizations/{have[locale]['id']}", method="PATCH", body={"data": {
                        "type": "subscriptionGroupLocalizations", "id": have[locale]["id"],
                        "attributes": {"name": GROUP_NAME, "customAppName": None}}})
                else:
                    req("/v1/subscriptionGroupLocalizations", method="POST", body={"data": {
                        "type": "subscriptionGroupLocalizations",
                        "attributes": {"name": GROUP_NAME, "locale": locale},
                        "relationships": {"subscriptionGroup": ref("subscriptionGroups", g["id"])}}})
            print(f"  group {g['id']}: name '{GROUP_NAME}' in {', '.join(PRODUCT_LOCALES)}")
            for s in g["subscriptions"]:
                name, desc = PRODUCT_COPY[product_key(s["attributes"]["productId"])]
                req(f"/v1/subscriptions/{s['id']}", method="PATCH", body={"data": {
                    "type": "subscriptions", "id": s["id"], "attributes": {"reviewNote": PRODUCT_REVIEW_NOTE}}})
                have = {l["attributes"]["locale"]: l for l in s["localizations"]}
                for locale in PRODUCT_LOCALES:
                    if locale in have:
                        req(f"/v1/subscriptionLocalizations/{have[locale]['id']}", method="PATCH", body={"data": {
                            "type": "subscriptionLocalizations", "id": have[locale]["id"],
                            "attributes": {"name": name, "description": desc}}})
                    else:
                        req("/v1/subscriptionLocalizations", method="POST", body={"data": {
                            "type": "subscriptionLocalizations",
                            "attributes": {"name": name, "locale": locale, "description": desc},
                            "relationships": {"subscription": ref("subscriptions", s["id"])}}})
                if REVIEW_SHOT.exists() and not s["reviewScreenshot"]:
                    upload_asset("/v1/subscriptionAppStoreReviewScreenshots", "subscriptionAppStoreReviewScreenshots",
                                 "subscription", "subscriptions", s["id"], REVIEW_SHOT)
                print(f"  {s['attributes']['productId']}: review note, localisations{', screenshot' if REVIEW_SHOT.exists() else ''}")
        for i in prods["iaps"]:
            name, desc = PRODUCT_COPY[product_key(i["attributes"]["productId"])]
            req(f"/v2/inAppPurchases/{i['id']}", method="PATCH", body={"data": {
                "type": "inAppPurchases", "id": i["id"], "attributes": {"reviewNote": PRODUCT_REVIEW_NOTE}}})
            have = {l["attributes"]["locale"]: l for l in i["localizations"]}
            for locale in PRODUCT_LOCALES:
                if locale in have:
                    req(f"/v1/inAppPurchaseLocalizations/{have[locale]['id']}", method="PATCH", body={"data": {
                        "type": "inAppPurchaseLocalizations", "id": have[locale]["id"],
                        "attributes": {"name": name, "description": desc}}})
                else:
                    req("/v1/inAppPurchaseLocalizations", method="POST", body={"data": {
                        "type": "inAppPurchaseLocalizations",
                        "attributes": {"name": name, "locale": locale, "description": desc},
                        "relationships": {"inAppPurchaseV2": ref("inAppPurchases", i["id"])}}})
            if REVIEW_SHOT.exists() and not i["reviewScreenshot"]:
                upload_asset("/v1/inAppPurchaseAppStoreReviewScreenshots", "inAppPurchaseAppStoreReviewScreenshots",
                             "inAppPurchaseV2", "inAppPurchases", i["id"], REVIEW_SHOT)
            print(f"  {i['attributes']['productId']}: review note, localisations{', screenshot' if REVIEW_SHOT.exists() else ''}")

    def do_screenshots():
        loc = next(l for l in before["version_localizations"] if l["attributes"]["locale"] == LOCALE)
        for display, folder in SCREENSHOT_SETS.items():
            files = sorted((COPY / "screenshots" / folder).glob("*.png"))
            if not files:
                print(f"  {display}: no files in {folder}")
                continue
            existing = before["screenshot_sets"].get(display)
            if existing and existing["screenshots"]:
                print(f"  {display}: already has {len(existing['screenshots'])}; left as is")
                continue
            set_id = existing["id"] if existing else req("/v1/appScreenshotSets", method="POST", body={"data": {
                "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
                "relationships": {"appStoreVersionLocalization": ref("appStoreVersionLocalizations", loc["id"])}}})["data"]["id"]
            for f in files[:10]:
                upload_asset("/v1/appScreenshots", "appScreenshots", "appScreenshotSet", "appScreenshotSets", set_id, f)
            print(f"  {display}: uploaded {len(files[:10])}")

    def do_build():
        valid = [b for b in before["builds"] if b["processingState"] == "VALID" and b["short"] == VERSION_STRING]
        if not valid:
            print("  no VALID 1.0 build")
            return
        newest = max(valid, key=lambda b: int(b["version"]))
        if newest["usesNonExemptEncryption"] is None:
            req(f"/v1/builds/{newest['id']}", method="PATCH", body={"data": {
                "type": "builds", "id": newest["id"], "attributes": {"usesNonExemptEncryption": False}}})
        req(f"/v1/appStoreVersions/{v['id']}/relationships/build", method="PATCH",
            body={"data": {"type": "builds", "id": newest["id"]}})
        print(f"  attached build {newest['version']} ({newest['id']}), expired={newest['expired']}")

    for name, fn in (("version", do_version), ("info", do_info), ("age", do_age), ("review", do_review),
                     ("price", do_price), ("availability", do_availability), ("products", do_products),
                     ("screenshots", do_screenshots), ("build", do_build)):
        if want(name) and not step(name, fn):
            failed.append(name)
    return failed


def summary(s: dict) -> None:
    print("== summary")
    v = s["version"]["attributes"]
    print(f"version {v['versionString']} state={v.get('appStoreState')} copyright={v.get('copyright')!r}")
    for l in s["version_localizations"]:
        a = l["attributes"]
        print(f"  {a['locale']}: description={len(a.get('description') or '')} chars keywords={a.get('keywords')!r}")
        print(f"    promo={len(a.get('promotionalText') or '')} chars support={a.get('supportUrl')} marketing={a.get('marketingUrl')}")
    for l in s["app_info_localizations"]:
        a = l["attributes"]
        print(f"  info {a['locale']}: name={a.get('name')!r} subtitle={a.get('subtitle')!r} privacy={a.get('privacyPolicyUrl')}")
    print(f"categories: {(s['primary_category'] or {}).get('id')} / {(s['secondary_category'] or {}).get('id')}")
    print(f"content rights: {s['app'].get('contentRightsDeclaration')}")
    age = (s["age_rating"] or {}).get("attributes") or {}
    print(f"age rating unanswered: {[k for k, val in age.items() if val is None and k not in ('kidsAgeBand', 'developerAgeRatingInfoUrl', 'ageRatingOverride', 'koreaAgeRatingOverride')]}")
    print(f"app info age: {s['app_info']['attributes'].get('appStoreAgeRating')}")
    rd = (s["review_detail"] or {}).get("attributes") or {}
    print(f"review detail: contact={rd.get('contactEmail')} phone set={bool(rd.get('contactPhone'))} notes={len(rd.get('notes') or '')} chars")
    print(f"price schedule: {bool((s['price_schedule'] or {}).get('data'))} included={[i['type'] + ':' + i['id'] for i in (s['price_schedule'] or {}).get('included') or []][:3]}")
    print(f"availability: {s['availability_counts']}")
    for d, st in s["screenshot_sets"].items():
        print(f"screenshots {d}: {[(x['fileName'], x['state']) for x in st['screenshots']]}")
    print(f"attached build: {(s['attached_build'] or {}).get('attributes', {}).get('version')}")
    for b in s["builds"][:4]:
        print(f"build {b['version']} ({b['short']}) {b['processingState']} expired={b['expired']} encryption={b['usesNonExemptEncryption']}")
    for g in s["products"]["groups"]:
        print(f"group {g['attributes'].get('referenceName')!r} locs={[(l['attributes']['locale'], l['attributes'].get('name'), l['attributes'].get('customAppName'), l['attributes'].get('state')) for l in g['localizations']]}")
        for sub in g["subscriptions"]:
            a = sub["attributes"]
            print(f"  {a['productId']} state={a.get('state')} note={bool(a.get('reviewNote'))} shot={bool(sub['reviewScreenshot'])}")
            print(f"    locs={[(l['attributes']['locale'], l['attributes'].get('name'), l['attributes'].get('description'), l['attributes'].get('state')) for l in sub['localizations']]}")
    for i in s["products"]["iaps"]:
        a = i["attributes"]
        print(f"  {a['productId']} state={a.get('state')} note={bool(a.get('reviewNote'))} shot={bool(i['reviewScreenshot'])}")
        print(f"    locs={[(l['attributes']['locale'], l['attributes'].get('name'), l['attributes'].get('description'), l['attributes'].get('state')) for l in i['localizations']]}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--only", default="", help="comma list of steps for --apply")
    args = parser.parse_args()
    copy = check_copy()
    print(f"copy: description {len(copy['description'])}, keywords {len(copy['keywords'])}, promo {len(copy['promotionalText'])}, notes {len(copy['reviewNotes'])}")
    before = status()
    Path("asc-listing-status-before.json").write_text(json.dumps(before, indent=1))
    print("== backup (before)")
    print(json.dumps(before, separators=(",", ":"))[:200000])
    summary(before)
    if not args.apply:
        return 0
    failed = apply(copy, before, set(filter(None, args.only.split(","))) or None)
    after = status()
    Path("asc-listing-status-after.json").write_text(json.dumps(after, indent=1))
    print("== after")
    summary(after)
    print("failed steps:", failed or "none")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
