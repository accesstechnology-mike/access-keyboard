#!/usr/bin/env python3
"""Talk to App Store Connect using the local API key. Prints no secrets."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBXPROJ = ROOT / "AccessKeyboard.xcodeproj/project.pbxproj"
ENV_FILE = ROOT / "secrets/AppStoreConnect.env"
ASC_BASE = "https://api.appstoreconnect.apple.com"


def load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and os.environ.get(key) in (None, ""):
            os.environ[key] = value


def credentials() -> tuple[str, str, Path]:
    load_dotenv(ENV_FILE)
    key_id = os.environ.get("APP_STORE_CONNECT_KEY_ID", "").strip()
    issuer = os.environ.get("APP_STORE_CONNECT_ISSUER_ID", "").strip()
    raw_path = os.environ.get("APP_STORE_CONNECT_API_KEY_PATH", "").strip()
    if not key_id or not issuer or not raw_path:
        sys.stderr.write(
            "Set APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, "
            "and APP_STORE_CONNECT_API_KEY_PATH (or secrets/AppStoreConnect.env).\n"
        )
        sys.exit(1)
    path = Path(raw_path)
    if not path.is_absolute():
        path = ROOT / path
    if not path.exists():
        sys.stderr.write(f"API key file is missing: {path}\n")
        sys.exit(1)
    return key_id, issuer, path


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _take_len(buf: bytes, index: int) -> tuple[int, int]:
    first = buf[index]
    index += 1
    if first < 0x80:
        return first, index
    count = first & 0x7F
    value = int.from_bytes(buf[index : index + count], "big")
    return value, index + count


def der_ecdsa_to_jose(der: bytes) -> bytes:
    if not der or der[0] != 0x30:
        raise ValueError("openssl signature was not a DER sequence")
    _, index = _take_len(der, 1)
    if der[index] != 0x02:
        raise ValueError("expected INTEGER r")
    index += 1
    r_len, index = _take_len(der, index)
    r = der[index : index + r_len]
    index += r_len
    if der[index] != 0x02:
        raise ValueError("expected INTEGER s")
    index += 1
    s_len, index = _take_len(der, index)
    s = der[index : index + s_len]

    def i32(raw: bytes) -> bytes:
        return int.from_bytes(raw, "big").to_bytes(32, "big")

    return i32(r) + i32(s)


def make_token(key_id: str, issuer: str, key_path: Path) -> str:
    now = int(time.time())
    header = b64url(
        json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode()
    )
    payload = b64url(
        json.dumps(
            {
                "iss": issuer,
                "iat": now,
                "exp": now + 20 * 60,
                "aud": "appstoreconnect-v1",
            },
            separators=(",", ":"),
        ).encode()
    )
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.check_output(
        ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
        input=signing_input,
    )
    return f"{header}.{payload}.{b64url(der_ecdsa_to_jose(der))}"


def asc_request(token: str, path: str, params: dict[str, str] | None = None) -> dict:
    url = f"{ASC_BASE}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(
        url,
        headers={"authorization": f"Bearer {token}", "accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode()[:400]
        raise RuntimeError(f"App Store Connect {exc.code} for {path}: {body}") from exc


def app_bundle_id(pbxproj: str) -> str:
    ids = {
        v.strip().strip('"')
        for v in re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", pbxproj)
    }
    apps = [value for value in ids if not value.endswith(".extension")]
    if len(apps) != 1:
        raise RuntimeError(f"could not find the app bundle id: {sorted(ids)}")
    return apps[0]


def unique_setting(pbxproj: str, key: str) -> str:
    values = {v.strip().strip('"') for v in re.findall(rf"{re.escape(key)} = ([^;]+);", pbxproj)}
    values.discard("")
    if len(values) != 1:
        raise RuntimeError(f"{key} is not a single value in the Xcode project: {sorted(values)}")
    return next(iter(values))


def app_id(token: str, bundle_id: str) -> str:
    payload = asc_request(
        token,
        "/v1/apps",
        {"filter[bundleId]": bundle_id, "limit": "1"},
    )
    data = payload.get("data") or []
    if not data:
        raise RuntimeError(f"No App Store Connect app for {bundle_id}")
    return data[0]["id"]


def next_build_number(token: str, bundle_id: str) -> int:
    identifier = app_id(token, bundle_id)
    highest = 0
    url_path = "/v1/builds"
    params: dict[str, str] | None = {
        "filter[app]": identifier,
        "fields[builds]": "version",
        "limit": "200",
    }
    while True:
        payload = asc_request(token, url_path, params)
        for item in payload.get("data") or []:
            raw = str(item.get("attributes", {}).get("version") or "")
            if raw.isdigit():
                highest = max(highest, int(raw))
        nxt = (payload.get("links") or {}).get("next")
        if not nxt:
            break
        parsed = urllib.parse.urlparse(nxt)
        url_path = parsed.path
        params = dict(urllib.parse.parse_qsl(parsed.query)) if parsed.query else None
    return highest + 1


def set_build_number(build: int) -> None:
    text = PBXPROJ.read_text()
    updated, count = re.subn(
        r"CURRENT_PROJECT_VERSION = [^;]+;",
        f"CURRENT_PROJECT_VERSION = {build};",
        text,
    )
    if count == 0:
        raise RuntimeError("no CURRENT_PROJECT_VERSION entries to update")
    PBXPROJ.write_text(updated)


def write_export_options(path: Path, team_id: str) -> None:
    path.write_text(
        f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>{team_id}</string>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
"""
    )


def cmd_ping() -> int:
    key_id, issuer, key_path = credentials()
    token = make_token(key_id, issuer, key_path)
    app_bundle = app_bundle_id(PBXPROJ.read_text())
    identifier = app_id(token, app_bundle)
    nxt = next_build_number(token, app_bundle)
    print(f"app={app_bundle} id={identifier} next_build={nxt}")
    return 0


def cmd_next_build() -> int:
    key_id, issuer, key_path = credentials()
    token = make_token(key_id, issuer, key_path)
    app_bundle = app_bundle_id(PBXPROJ.read_text())
    print(next_build_number(token, app_bundle))
    return 0


def cmd_set_build(build: int) -> int:
    set_build_number(build)
    print(build)
    return 0


def cmd_export_options(path: Path) -> int:
    team_id = unique_setting(PBXPROJ.read_text(), "DEVELOPMENT_TEAM")
    write_export_options(path, team_id)
    print(path)
    return 0


def cmd_team() -> int:
    print(unique_setting(PBXPROJ.read_text(), "DEVELOPMENT_TEAM"))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("ping")
    sub.add_parser("next-build")
    set_p = sub.add_parser("set-build")
    set_p.add_argument("build", type=int)
    export_p = sub.add_parser("write-export-options")
    export_p.add_argument("path", type=Path)
    sub.add_parser("team")
    args = parser.parse_args()
    if args.cmd == "ping":
        return cmd_ping()
    if args.cmd == "next-build":
        return cmd_next_build()
    if args.cmd == "set-build":
        return cmd_set_build(args.build)
    if args.cmd == "write-export-options":
        return cmd_export_options(args.path)
    if args.cmd == "team":
        return cmd_team()
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as exc:
        sys.stderr.write(f"{exc}\n")
        sys.exit(1)
