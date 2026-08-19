#!/usr/bin/env python3
"""Fail if the Xcode project is not ready to archive for TestFlight."""

from __future__ import annotations

import json
import os
import plistlib
import re
import struct
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []
NOTES: list[str] = []

RELEASE_FIX_URL = "https://access-keyboard.vercel.app/api/fix"
DEBUG_FIX_URL = "http://127.0.0.1:8787/api/fix"
BUNDLE_ID = "app.access.keyboard"
EXTENSION_BUNDLE_ID = "app.access.keyboard.extension"
TEAM = "6M3Z27M69P"
APP_GROUP = f"group.{TEAM}.app.access.keyboard"
MARKETING_VERSION = "0.1.0"


def error(message: str) -> None:
    ERRORS.append(message)


def note(message: str) -> None:
    NOTES.append(message)


def read_png_ihdr(path: Path) -> tuple[int, int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    offset = 8
    while offset + 8 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk = data[offset + 8 : offset + 8 + length]
        if chunk_type == b"IHDR":
            width, height, _bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
            return width, height, color_type
        if chunk_type == b"IEND":
            break
        offset += 8 + length + 4
    raise ValueError(f"{path} has no IHDR")


def check_icon() -> None:
    path = ROOT / "AccessKeyboard/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    width, height, color_type = read_png_ihdr(path)
    if (width, height) != (1024, 1024):
        error(f"App icon is {width}x{height}, not 1024x1024")
    if color_type != 2:
        error(f"App icon color type is {color_type}; App Store Connect needs RGB (2) with no alpha")
    else:
        note(f"App icon is {width}x{height} RGB (no alpha)")


def load_plist(path: Path) -> dict:
    return plistlib.loads(path.read_bytes())


def check_info_plists() -> None:
    for rel in ("AccessKeyboard/Info.plist", "AccessKeyboardExtension/Info.plist"):
        info = load_plist(ROOT / rel)
        url = info.get("AKFixProxyURL")
        if url != "$(AK_FIX_PROXY_URL)":
            error(f"{rel} AKFixProxyURL is {url!r}, expected $(AK_FIX_PROXY_URL)")
        else:
            note(f"{rel} reads AKFixProxyURL from the build setting")
        secret = info.get("AKFixProxySecret")
        if secret != "$(AK_FIX_PROXY_SECRET)":
            error(f"{rel} AKFixProxySecret is {secret!r}, expected $(AK_FIX_PROXY_SECRET)")
        else:
            note(f"{rel} reads AKFixProxySecret from the build setting")


def check_privacy() -> None:
    for rel in (
        "AccessKeyboard/PrivacyInfo.xcprivacy",
        "AccessKeyboardExtension/PrivacyInfo.xcprivacy",
    ):
        privacy = load_plist(ROOT / rel)
        if privacy.get("NSPrivacyTracking") is not False:
            error(f"{rel} must set NSPrivacyTracking to false")
        types = privacy.get("NSPrivacyAccessedAPITypes") or []
        user_defaults = [
            item
            for item in types
            if item.get("NSPrivacyAccessedAPIType")
            == "NSPrivacyAccessedAPICategoryUserDefaults"
        ]
        if not user_defaults:
            error(f"{rel} does not declare UserDefaults")
            continue
        reasons = user_defaults[0].get("NSPrivacyAccessedAPITypeReasons") or []
        if "CA92.1" not in reasons:
            error(f"{rel} UserDefaults reason should include CA92.1 (App Group)")
        else:
            note(f"{rel} declares UserDefaults CA92.1")


def check_entitlements() -> None:
    for rel in (
        "AccessKeyboard/AccessKeyboard.entitlements",
        "AccessKeyboardExtension/AccessKeyboardExtension.entitlements",
    ):
        entitlements = load_plist(ROOT / rel)
        groups = entitlements.get("com.apple.security.application-groups") or []
        if APP_GROUP not in groups:
            error(f"{rel} is missing {APP_GROUP}")
        else:
            note(f"{rel} includes {APP_GROUP}")


def setting_values(pbxproj: str, key: str) -> list[str]:
    return re.findall(rf"{re.escape(key)} = ([^;]+);", pbxproj)


def quoted(value: str) -> str:
    return value.strip().strip('"')


def check_project() -> None:
    pbxproj = (ROOT / "AccessKeyboard.xcodeproj/project.pbxproj").read_text()

    versions = {quoted(v) for v in setting_values(pbxproj, "MARKETING_VERSION")}
    if versions != {MARKETING_VERSION}:
        error(f"MARKETING_VERSION values are {sorted(versions)}, expected only {MARKETING_VERSION}")
    else:
        note(f"MARKETING_VERSION is {MARKETING_VERSION} on every target")

    builds = {quoted(v) for v in setting_values(pbxproj, "CURRENT_PROJECT_VERSION")}
    if len(builds) != 1:
        error(f"CURRENT_PROJECT_VERSION is not consistent: {sorted(builds)}")
    else:
        note(f"CURRENT_PROJECT_VERSION is {next(iter(builds))} on every target")

    teams = {quoted(v) for v in setting_values(pbxproj, "DEVELOPMENT_TEAM") if quoted(v)}
    if teams != {TEAM}:
        error(f"DEVELOPMENT_TEAM values are {sorted(teams)}, expected {TEAM}")
    else:
        note(f"DEVELOPMENT_TEAM is {TEAM}")

    bundle_ids = {quoted(v) for v in setting_values(pbxproj, "PRODUCT_BUNDLE_IDENTIFIER")}
    if bundle_ids != {BUNDLE_ID, EXTENSION_BUNDLE_ID}:
        error(f"bundle identifiers are {sorted(bundle_ids)}")
    else:
        note(f"bundle identifiers are {BUNDLE_ID} and {EXTENSION_BUNDLE_ID}")

    families = {quoted(v) for v in setting_values(pbxproj, "TARGETED_DEVICE_FAMILY")}
    if families != {"2"}:
        error(f"TARGETED_DEVICE_FAMILY is {sorted(families)}; testers need iPad-only")
    else:
        note("device family is iPad only")

    encryption = {
        quoted(v) for v in setting_values(pbxproj, "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption")
    }
    if encryption != {"NO"}:
        error("ITSAppUsesNonExemptEncryption is not NO on every target")
    else:
        note("export compliance is set to exempt (HTTPS only)")

    debug_urls = set()
    release_urls = set()
    for match in re.finditer(
        r"/\* (Debug|Release) \*/ = \{.*?AK_FIX_PROXY_URL = ([^;]+);",
        pbxproj,
        flags=re.S,
    ):
        url = quoted(match.group(2))
        if match.group(1) == "Debug":
            debug_urls.add(url)
        else:
            release_urls.add(url)

    if debug_urls != {DEBUG_FIX_URL}:
        error(f"Debug AK_FIX_PROXY_URL is {sorted(debug_urls)}, expected {DEBUG_FIX_URL}")
    else:
        note(f"Debug Fix URL is {DEBUG_FIX_URL}")

    if release_urls != {RELEASE_FIX_URL}:
        error(f"Release AK_FIX_PROXY_URL is {sorted(release_urls)}, expected {RELEASE_FIX_URL}")
    else:
        note(f"Release Fix URL is {RELEASE_FIX_URL}")


def load_fix_proxy_secret() -> str:
    env_secret = os.environ.get("FIX_PROXY_SECRET", "").strip()
    if env_secret:
        return env_secret

    xcconfig = ROOT / "Secrets.xcconfig"
    if xcconfig.exists():
        for raw in xcconfig.read_text().splitlines():
            line = raw.strip()
            if line.startswith("AK_FIX_PROXY_SECRET"):
                _, _, value = line.partition("=")
                token = value.strip().strip('"').strip("'")
                if token:
                    return token

    env_local = ROOT / "proxy" / ".env.local"
    if env_local.exists():
        for raw in env_local.read_text().splitlines():
            line = raw.strip()
            if line.startswith("FIX_PROXY_SECRET="):
                token = line.split("=", 1)[1].strip().strip('"').strip("'")
                if token:
                    return token
    return ""


def check_secret_wiring() -> None:
    gitignore = (ROOT / ".gitignore").read_text()
    if "Secrets.xcconfig" not in gitignore:
        error(".gitignore does not ignore Secrets.xcconfig")
    else:
        note("Secrets.xcconfig is gitignored")

    example = ROOT / "Secrets.xcconfig.example"
    if not example.exists():
        error("Secrets.xcconfig.example is missing")
    elif "AK_FIX_PROXY_SECRET" not in example.read_text():
        error("Secrets.xcconfig.example does not define AK_FIX_PROXY_SECRET")
    else:
        note("Secrets.xcconfig.example names AK_FIX_PROXY_SECRET")

    shared = ROOT / "Shared.xcconfig"
    if not shared.exists():
        error("Shared.xcconfig is missing")
    elif 'Secrets.xcconfig' not in shared.read_text():
        error("Shared.xcconfig does not include Secrets.xcconfig")
    else:
        note("Shared.xcconfig includes Secrets.xcconfig")

    example_env = (ROOT / "proxy" / ".env.example").read_text()
    if "FIX_PROXY_SECRET=" not in example_env:
        error("proxy/.env.example is missing FIX_PROXY_SECRET")
    else:
        note("proxy/.env.example includes FIX_PROXY_SECRET")

    if not load_fix_proxy_secret():
        error("FIX_PROXY_SECRET is not set locally; copy Secrets.xcconfig.example to Secrets.xcconfig")
    else:
        note("a local Fix proxy secret is present")


def check_privacy_page() -> None:
    page = ROOT / "proxy/public/privacy.html"
    text = page.read_text()
    if RELEASE_FIX_URL not in text:
        error("proxy/public/privacy.html does not name the live Fix URL")
    else:
        note("privacy page names the live Fix URL")


def check_live_proxy() -> None:
    secret = load_fix_proxy_secret()
    if not secret:
        error("cannot probe the live Fix proxy without FIX_PROXY_SECRET")
        return
    request = urllib.request.Request(
        RELEASE_FIX_URL,
        data=json.dumps({"text": "teh cat sat"}).encode(),
        headers={
            "content-type": "application/json",
            "authorization": f"Bearer {secret}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            body = json.loads(response.read().decode())
            status = response.status
    except urllib.error.HTTPError as exc:
        error(f"live Fix proxy returned HTTP {exc.code}")
        return
    except urllib.error.URLError as exc:
        error(f"live Fix proxy is unreachable: {exc.reason}")
        return

    corrected = body.get("text") if isinstance(body, dict) else None
    if status != 200 or not corrected:
        error(f"live Fix proxy returned {status} {body!r}")
        return
    if "cat" not in corrected.lower():
        error(f"live Fix proxy changed the meaning: {corrected!r}")
        return
    note(f"live Fix proxy corrected sample text to {corrected!r}")


def main() -> int:
    check_icon()
    check_info_plists()
    check_privacy()
    check_entitlements()
    check_project()
    check_secret_wiring()
    check_privacy_page()
    check_live_proxy()

    for line in NOTES:
        print(f"OK  {line}")
    if ERRORS:
        print()
        for line in ERRORS:
            print(f"ERR {line}")
        return 1
    print()
    print("Ready to archive AccessKeyboard for TestFlight on a Mac.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
