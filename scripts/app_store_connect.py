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


class ASCHTTPError(RuntimeError):
    def __init__(self, code: int, path: str, body: str):
        self.code = code
        self.path = path
        self.body = body
        super().__init__(f"App Store Connect {code} for {path}: {body}")


def asc_request(
    token: str,
    path: str,
    params: dict[str, str] | None = None,
    method: str = "GET",
    body: dict | None = None,
) -> dict:
    if path.startswith("https://"):
        url = path
    else:
        url = f"{ASC_BASE}{path}"
        if params:
            url += "?" + urllib.parse.urlencode(params)
    headers = {"authorization": f"Bearer {token}", "accept": "application/json"}
    raw_body = None
    if body is not None:
        raw_body = json.dumps(body).encode()
        headers["content-type"] = "application/json"
    request = urllib.request.Request(url, data=raw_body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read().decode()
            if not payload:
                return {}
            return json.loads(payload)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode()[:400]
        raise ASCHTTPError(exc.code, path, detail) from exc


def collect_resources(
    token: str, path: str, params: dict[str, str] | None = None
) -> tuple[list[dict], list[dict]]:
    items: list[dict] = []
    included: list[dict] = []
    url_path = path
    query = params
    while True:
        payload = asc_request(token, url_path, query)
        items.extend(payload.get("data") or [])
        included.extend(payload.get("included") or [])
        nxt = (payload.get("links") or {}).get("next")
        if not nxt:
            break
        parsed = urllib.parse.urlparse(nxt)
        url_path = parsed.path
        query = dict(urllib.parse.parse_qsl(parsed.query)) if parsed.query else None
    return items, included


def ignore_already_exists(exc: ASCHTTPError) -> bool:
    if exc.code == 409:
        return True
    return exc.code == 422 and (
        "already" in exc.body.lower() or "duplicate" in exc.body.lower()
    )


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


def parse_build(item: dict) -> dict | None:
    attrs = item.get("attributes") or {}
    raw = str(attrs.get("version") or "")
    if not raw.isdigit():
        return None
    return {
        "id": item["id"],
        "number": int(raw),
        "expired": bool(attrs.get("expired")),
        "processing_state": str(attrs.get("processingState") or ""),
        "uses_non_exempt_encryption": attrs.get("usesNonExemptEncryption"),
    }


def parse_group(item: dict) -> dict:
    attrs = item.get("attributes") or {}
    return {
        "id": item["id"],
        "name": str(attrs.get("name") or item["id"]),
        "is_internal": bool(attrs.get("isInternalGroup")),
        "has_access_to_all_builds": attrs.get("hasAccessToAllBuilds"),
    }


def latest_valid_build(builds: list[dict]) -> dict | None:
    ready = [
        item
        for item in builds
        if item["processing_state"] == "VALID" and not item["expired"]
    ]
    if not ready:
        return None
    return max(ready, key=lambda item: item["number"])


def builds_to_expire(builds: list[dict], latest: dict) -> list[dict]:
    return [
        item
        for item in builds
        if item["id"] != latest["id"]
        and not item["expired"]
        and item["processing_state"] == "VALID"
        and item["number"] < latest["number"]
    ]


def group_needs_all_builds(group: dict) -> bool:
    return group["is_internal"] and group.get("has_access_to_all_builds") is not True


def next_build_number(token: str, bundle_id: str) -> int:
    identifier = app_id(token, bundle_id)
    items, _ = collect_resources(
        token,
        "/v1/builds",
        {
            "filter[app]": identifier,
            "fields[builds]": "version",
            "limit": "200",
        },
    )
    highest = 0
    for item in items:
        parsed = parse_build(item)
        if parsed:
            highest = max(highest, parsed["number"])
    return highest + 1


def list_app_builds(token: str, identifier: str) -> list[dict]:
    items, _ = collect_resources(
        token,
        "/v1/builds",
        {
            "filter[app]": identifier,
            "fields[builds]": "version,expired,processingState,usesNonExemptEncryption",
            "limit": "200",
        },
    )
    builds = [parsed for item in items if (parsed := parse_build(item))]
    builds.sort(key=lambda item: item["number"], reverse=True)
    return builds


def list_beta_groups(token: str, identifier: str) -> list[dict]:
    items, _ = collect_resources(
        token,
        "/v1/betaGroups",
        {
            "filter[app]": identifier,
            "fields[betaGroups]": "name,isInternalGroup,hasAccessToAllBuilds",
            "limit": "200",
        },
    )
    return [parse_group(item) for item in items]


def group_builds(token: str, group_id: str) -> list[dict]:
    items, _ = collect_resources(
        token,
        f"/v1/betaGroups/{group_id}/builds",
        {"fields[builds]": "version,expired,processingState", "limit": "200"},
    )
    return [parsed for item in items if (parsed := parse_build(item))]


def group_testers(token: str, group_id: str) -> list[str]:
    items, _ = collect_resources(
        token,
        f"/v1/betaGroups/{group_id}/betaTesters",
        {"fields[betaTesters]": "email", "limit": "200"},
    )
    emails = []
    for item in items:
        email = (item.get("attributes") or {}).get("email")
        if email:
            emails.append(str(email))
    return emails


def assign_build_to_group(token: str, group_id: str, build_id: str) -> str:
    try:
        asc_request(
            token,
            f"/v1/betaGroups/{group_id}/relationships/builds",
            method="POST",
            body={"data": [{"type": "builds", "id": build_id}]},
        )
        return "assigned"
    except ASCHTTPError as exc:
        if ignore_already_exists(exc):
            return "already"
        raise


def enable_group_all_builds(token: str, group: dict) -> str:
    if not group_needs_all_builds(group):
        return "already"
    try:
        asc_request(
            token,
            f"/v1/betaGroups/{group['id']}",
            method="PATCH",
            body={
                "data": {
                    "type": "betaGroups",
                    "id": group["id"],
                    "attributes": {"hasAccessToAllBuilds": True},
                }
            },
        )
        return "enabled"
    except ASCHTTPError as exc:
        if ignore_already_exists(exc):
            return "already"
        raise


def expire_build(token: str, build: dict) -> str:
    if build["expired"]:
        return "already"
    asc_request(
        token,
        f"/v1/builds/{build['id']}",
        method="PATCH",
        body={
            "data": {
                "type": "builds",
                "id": build["id"],
                "attributes": {"expired": True},
            }
        },
    )
    return "expired"


def clear_export_compliance(token: str, build: dict) -> None:
    if build.get("uses_non_exempt_encryption") is not None:
        return
    try:
        asc_request(
            token,
            f"/v1/builds/{build['id']}",
            method="PATCH",
            body={
                "data": {
                    "type": "builds",
                    "id": build["id"],
                    "attributes": {"usesNonExemptEncryption": False},
                }
            },
        )
    except ASCHTTPError as exc:
        if ignore_already_exists(exc):
            return
        raise


def submit_beta_review(token: str, build_id: str) -> str:
    try:
        asc_request(
            token,
            "/v1/betaAppReviewSubmissions",
            method="POST",
            body={
                "data": {
                    "type": "betaAppReviewSubmissions",
                    "relationships": {
                        "build": {"data": {"type": "builds", "id": build_id}}
                    },
                }
            },
        )
        return "submitted"
    except ASCHTTPError as exc:
        if ignore_already_exists(exc):
            return "already"
        raise


def individual_testers(token: str, build_id: str) -> list[str]:
    items, _ = collect_resources(
        token,
        f"/v1/builds/{build_id}/individualTesters",
        {"fields[betaTesters]": "email", "limit": "200"},
    )
    return [item["id"] for item in items if item.get("id")]


def assign_individual_testers(token: str, build_id: str, tester_ids: list[str]) -> int:
    added = 0
    for tester_id in tester_ids:
        try:
            asc_request(
                token,
                f"/v1/builds/{build_id}/relationships/individualTesters",
                method="POST",
                body={"data": [{"type": "betaTesters", "id": tester_id}]},
            )
            added += 1
        except ASCHTTPError as exc:
            if ignore_already_exists(exc):
                continue
            raise
    return added


def wait_for_valid_build(
    token: str,
    identifier: str,
    number: int,
    timeout_s: int = 35 * 60,
    sleep_s: int = 30,
) -> dict:
    deadline = time.time() + timeout_s
    seen = "missing"
    while True:
        builds = list_app_builds(token, identifier)
        match = next((item for item in builds if item["number"] == number), None)
        if match:
            clear_export_compliance(token, match)
            seen = match["processing_state"] or "unknown"
            if match["processing_state"] == "VALID":
                return match
            if match["processing_state"] in {"FAILED", "INVALID"}:
                raise RuntimeError(f"build {number} is {match['processing_state']}")
        if time.time() >= deadline:
            raise RuntimeError(
                f"timed out waiting for build {number} to be VALID (state={seen})"
            )
        time.sleep(sleep_s)


def enforce_latest_only(token: str, identifier: str, latest: dict) -> None:
    groups = list_beta_groups(token, identifier)
    if not groups:
        raise RuntimeError("no TestFlight groups; add testers to a group first")

    failures: list[str] = []
    for group in groups:
        kind = "internal" if group["is_internal"] else "external"
        try:
            access = enable_group_all_builds(token, group)
            if access == "enabled":
                print(f"{kind} group {group['name']}: testers now get every new build")
            if not group["is_internal"]:
                review = submit_beta_review(token, latest["id"])
                if review == "submitted":
                    print(f"{kind} group {group['name']}: submitted build {latest['number']} for Beta Review")
            assigned = assign_build_to_group(token, group["id"], latest["id"])
            print(f"{kind} group {group['name']}: {assigned} build {latest['number']}")
        except ASCHTTPError as exc:
            failures.append(f"{kind} group {group['name']}: {exc}")
            print(f"{kind} group {group['name']}: FAILED {exc}", file=sys.stderr)

    old = builds_to_expire(list_app_builds(token, identifier), latest)
    tester_ids: list[str] = []
    for build in old:
        tester_ids.extend(individual_testers(token, build["id"]))
    unique_testers = list(dict.fromkeys(tester_ids))
    if unique_testers:
        added = assign_individual_testers(token, latest["id"], unique_testers)
        print(f"moved {added} individual tester assignment(s) to build {latest['number']}")

    if failures:
        raise RuntimeError(
            "not every TestFlight group has the latest build; older builds were left in place. "
            + " ".join(failures)
        )

    for build in old:
        result = expire_build(token, build)
        print(f"{result} build {build['number']}")


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


def _app_context() -> tuple[str, str, str]:
    key_id, issuer, key_path = credentials()
    token = make_token(key_id, issuer, key_path)
    bundle = app_bundle_id(PBXPROJ.read_text())
    return token, bundle, app_id(token, bundle)


def cmd_status() -> int:
    token, bundle, identifier = _app_context()
    builds = list_app_builds(token, identifier)
    latest = latest_valid_build(builds)
    print(f"app={bundle} id={identifier}")
    if latest:
        print(f"latest_valid={latest['number']}")
    else:
        print("latest_valid=none")
    for build in builds:
        flags = [build["processing_state"] or "unknown"]
        if build["expired"]:
            flags.append("expired")
        if latest and build["id"] == latest["id"]:
            flags.append("latest")
        print(f"build {build['number']} {' '.join(flags)}")
    for group in list_beta_groups(token, identifier):
        kind = "internal" if group["is_internal"] else "external"
        all_builds = group.get("has_access_to_all_builds")
        testers = ",".join(group_testers(token, group["id"])) or "none"
        numbers = ",".join(str(item["number"]) for item in group_builds(token, group["id"])) or "none"
        print(
            f"group {group['name']} {kind} all_builds={all_builds} "
            f"testers={testers} builds={numbers}"
        )
    return 0


def cmd_latest_only(wait_for: int | None) -> int:
    token, bundle, identifier = _app_context()
    if wait_for is not None:
        print(f"waiting for build {wait_for} on {bundle}")
        wait_for_valid_build(token, identifier, wait_for)
    latest = latest_valid_build(list_app_builds(token, identifier))
    if latest is None:
        raise RuntimeError("no VALID unexpired TestFlight build")
    print(f"latest {latest['number']}")
    enforce_latest_only(token, identifier, latest)
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
    sub.add_parser("status")
    latest_p = sub.add_parser("latest-only")
    latest_p.add_argument(
        "--wait-for",
        type=int,
        default=None,
        help="wait until this build number is VALID, then make it the only tester build",
    )
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
    if args.cmd == "status":
        return cmd_status()
    if args.cmd == "latest-only":
        return cmd_latest_only(args.wait_for)
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as exc:
        sys.stderr.write(f"{exc}\n")
        sys.exit(1)
