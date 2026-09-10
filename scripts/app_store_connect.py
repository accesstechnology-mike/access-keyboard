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
TOKEN_LIFETIME_S = 20 * 60
TOKEN_REFRESH_MARGIN_S = 5 * 60
LIVE_TESTER_STATES = frozenset({"INVITED", "ACCEPTED", "INSTALLED"})


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
                "exp": now + TOKEN_LIFETIME_S,
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


def token_needs_refresh(now: int, expires_at: int) -> bool:
    return now + TOKEN_REFRESH_MARGIN_S >= expires_at


def fresh_token() -> str:
    key_id, issuer, key_path = credentials()
    return make_token(key_id, issuer, key_path)


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
    last_error: ASCHTTPError | None = None
    for attempt in range(3):
        request = urllib.request.Request(url, data=raw_body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read().decode()
                if not payload:
                    return {}
                return json.loads(payload)
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode()[:400]
            last_error = ASCHTTPError(exc.code, path, detail)
            if exc.code != 500 or attempt == 2:
                raise last_error from exc
            time.sleep(2**attempt)
    raise last_error or RuntimeError(f"App Store Connect request failed for {path}")


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
    if tester_cannot_be_assigned(exc):
        return False
    if exc.code == 409:
        return True
    return exc.code == 422 and (
        "already" in exc.body.lower() or "duplicate" in exc.body.lower()
    )


def tester_cannot_be_assigned(exc: ASCHTTPError) -> bool:
    return exc.code == 409 and "cannot be assigned" in exc.body.lower()


def tester_is_missing(exc: ASCHTTPError) -> bool:
    return exc.code == 404


def internal_group_rejects_assign(exc: ASCHTTPError) -> bool:
    body = exc.body.lower()
    return exc.code == 422 and (
        "cannot add internal group" in body
        or "cannot be assigned to this internal group" in body
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
        "internal_build_state": None,
        "external_build_state": None,
    }


def parse_group(item: dict) -> dict:
    attrs = item.get("attributes") or {}
    return {
        "id": item["id"],
        "name": str(attrs.get("name") or item["id"]),
        "is_internal": bool(attrs.get("isInternalGroup")),
        "has_access_to_all_builds": attrs.get("hasAccessToAllBuilds"),
        "public_link_enabled": attrs.get("publicLinkEnabled"),
        "public_link": str(attrs.get("publicLink") or ""),
        "public_link_limit_enabled": attrs.get("publicLinkLimitEnabled"),
        "public_link_limit": attrs.get("publicLinkLimit"),
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


INSTALLABLE_INTERNAL_STATES = frozenset(
    {"READY_FOR_BETA_TESTING", "IN_BETA_TESTING"}
)
BLOCKED_INTERNAL_STATES = frozenset(
    {
        "PROCESSING",
        "MISSING_EXPORT_COMPLIANCE",
        "IN_EXPORT_COMPLIANCE_REVIEW",
        "EXPIRED",
    }
)

# externalBuildState values Apple reports on a build's buildBetaDetail. A build
# is only installable by external testers once Beta App Review has approved it.
EXTERNAL_TESTING_STATES = frozenset(
    {"BETA_APPROVED", "READY_FOR_BETA_TESTING", "IN_BETA_TESTING"}
)
EXTERNAL_REVIEW_PENDING_STATES = frozenset(
    {"WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW"}
)
EXTERNAL_NEEDS_SUBMISSION_STATES = frozenset({"READY_FOR_BETA_SUBMISSION"})
EXTERNAL_REJECTED_STATES = frozenset({"BETA_REJECTED"})


def external_build_ready(build: dict) -> bool:
    return build.get("external_build_state") in EXTERNAL_TESTING_STATES


def external_review_pending(build: dict) -> bool:
    return build.get("external_build_state") in EXTERNAL_REVIEW_PENDING_STATES


def external_needs_submission(build: dict) -> bool:
    state = build.get("external_build_state")
    return state in EXTERNAL_NEEDS_SUBMISSION_STATES or state in {None, ""}


def is_installable(build: dict) -> bool:
    if build["expired"] or build["processing_state"] != "VALID":
        return False
    state = build.get("internal_build_state")
    if state in BLOCKED_INTERNAL_STATES:
        return False
    return state in INSTALLABLE_INTERNAL_STATES or state in {None, ""}


def latest_installable_build(builds: list[dict]) -> dict | None:
    ready = [item for item in builds if is_installable(item)]
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


def attach_beta_detail(item: dict, parsed: dict, included: list[dict]) -> dict:
    details = {
        resource["id"]: resource
        for resource in included
        if resource.get("type") == "buildBetaDetails"
    }
    rel = ((item.get("relationships") or {}).get("buildBetaDetail") or {}).get("data") or {}
    detail = details.get(rel.get("id") or "", {})
    detail_attrs = detail.get("attributes") or {}
    parsed["internal_build_state"] = detail_attrs.get("internalBuildState")
    parsed["external_build_state"] = detail_attrs.get("externalBuildState")
    return parsed


def list_app_builds(token: str, identifier: str) -> list[dict]:
    items, included = collect_resources(
        token,
        "/v1/builds",
        {
            "filter[app]": identifier,
            "include": "buildBetaDetail",
            "fields[builds]": "version,expired,processingState,usesNonExemptEncryption,buildBetaDetail",
            "fields[buildBetaDetails]": "internalBuildState,externalBuildState",
            "limit": "200",
        },
    )
    builds = [
        attach_beta_detail(item, parsed, included)
        for item in items
        if (parsed := parse_build(item))
    ]
    builds.sort(key=lambda item: item["number"], reverse=True)
    return builds


TESTER_FIELDS = "email,inviteType,state,firstName,lastName"


def parse_tester(item: dict) -> dict:
    attrs = item.get("attributes") or {}
    return {
        "id": item["id"],
        "email": str(attrs.get("email") or ""),
        "invite_type": str(attrs.get("inviteType") or ""),
        "state": str(attrs.get("state") or ""),
        "first_name": str(attrs.get("firstName") or ""),
        "last_name": str(attrs.get("lastName") or ""),
    }


def _merge_testers(dest: dict[str, dict], items: list[dict]) -> None:
    for item in items:
        parsed = parse_tester(item)
        dest[parsed["id"]] = parsed


def list_testers_from_path(
    token: str, path: str, params: dict[str, str]
) -> list[dict]:
    items, _ = collect_resources(token, path, params)
    return items


def list_app_testers(
    token: str, identifier: str, groups: list[dict] | None = None
) -> list[dict]:
    testers: dict[str, dict] = {}
    queries = [
        (
            "/v1/betaTesters",
            {
                "filter[apps]": identifier,
                "fields[betaTesters]": TESTER_FIELDS,
                "limit": "200",
            },
        ),
        (
            "/v1/betaTesters",
            {"fields[betaTesters]": TESTER_FIELDS, "limit": "200"},
        ),
        (
            f"/v1/apps/{identifier}/betaTesters",
            {"fields[betaTesters]": TESTER_FIELDS, "limit": "200"},
        ),
    ]
    for group in groups or []:
        queries.append(
            (
                f"/v1/betaGroups/{group['id']}/betaTesters",
                {"fields[betaTesters]": TESTER_FIELDS, "limit": "200"},
            )
        )
    errors: list[str] = []
    for path, params in queries:
        try:
            _merge_testers(testers, list_testers_from_path(token, path, params))
        except ASCHTTPError as exc:
            errors.append(f"{path}: {exc}")
    if not testers and errors:
        raise RuntimeError("could not list TestFlight testers: " + " ".join(errors))
    return sorted(testers.values(), key=lambda item: item["email"] or item["id"])


def tester_live(tester: dict) -> bool:
    return tester.get("state") in LIVE_TESTER_STATES


def tester_needs_reinvite(tester: dict) -> bool:
    return bool(tester.get("email")) and tester.get("state") not in LIVE_TESTER_STATES


def testers_needing_reinvite(testers: list[dict]) -> list[dict]:
    return [tester for tester in testers if tester_needs_reinvite(tester)]


def revoked_testers(testers: list[dict]) -> list[dict]:
    return testers_needing_reinvite(testers)


def delete_tester(token: str, tester_id: str) -> str:
    try:
        asc_request(token, f"/v1/betaTesters/{tester_id}", method="DELETE")
        return "removed"
    except ASCHTTPError as exc:
        if tester_is_missing(exc):
            return "already"
        raise


def tester_create_relationships(group_ids: list[str], build_id: str) -> dict:
    # Apple returns 409 "Only one relationship should be included when creating betaTesters".
    if group_ids:
        return {
            "betaGroups": {
                "data": [
                    {"type": "betaGroups", "id": group_id} for group_id in group_ids
                ]
            }
        }
    if build_id:
        return {"builds": {"data": [{"type": "builds", "id": build_id}]}}
    raise RuntimeError("creating a tester needs a group or a build")


def parse_created_tester(payload: dict, email: str) -> dict:
    data = payload.get("data") or {}
    parsed = parse_tester({"id": data.get("id") or "", "attributes": data.get("attributes") or {}})
    if not parsed["id"]:
        raise RuntimeError(f"creating tester {email} returned no id")
    if not parsed["email"]:
        parsed["email"] = email
    return parsed


def post_tester(
    token: str, email: str, group_ids: list[str], build_id: str
) -> dict:
    relationships = tester_create_relationships(group_ids, build_id)
    payload = asc_request(
        token,
        "/v1/betaTesters",
        method="POST",
        body={
            "data": {
                "type": "betaTesters",
                "attributes": {"email": email},
                "relationships": relationships,
            }
        },
    )
    return parse_created_tester(payload, email)


def create_tester(token: str, email: str, group_ids: list[str], build_id: str) -> dict:
    attempts: list[tuple[list[str], str]] = []
    if group_ids:
        attempts.append((group_ids, ""))
    if build_id:
        attempts.append(([], build_id))
    if not attempts:
        raise RuntimeError("creating a tester needs a group or a build")
    last: ASCHTTPError | None = None
    for groups, identifier in attempts:
        via = "groups" if groups else "build"
        try:
            created = post_tester(token, email, groups, identifier)
            print(
                f"created tester {email} via {via} id={created['id']} "
                f"state={created['state'] or 'unknown'}"
            )
            return created
        except ASCHTTPError as exc:
            last = exc
            if tester_cannot_be_assigned(exc):
                print(f"create {email} via {via}: {exc}", file=sys.stderr)
                continue
            raise
    raise last or RuntimeError(f"creating tester {email} failed")


def list_user_invitations(token: str) -> list[dict]:
    items, _ = collect_resources(
        token,
        "/v1/userInvitations",
        {"fields[userInvitations]": "email,firstName,lastName", "limit": "200"},
    )
    invitations: list[dict] = []
    for item in items:
        attrs = item.get("attributes") or {}
        email = str(attrs.get("email") or "")
        if not email:
            continue
        invitations.append(
            {
                "id": item["id"],
                "email": email,
                "first_name": str(attrs.get("firstName") or ""),
                "last_name": str(attrs.get("lastName") or ""),
            }
        )
    return invitations


def invite_app_store_connect_user(
    token: str, email: str, first_name: str, last_name: str, app_id: str
) -> str:
    # Marketing is the least privileged App Store Connect role Apple documents
    # as enough for internal TestFlight testers.
    payload = asc_request(
        token,
        "/v1/userInvitations",
        method="POST",
        body={
            "data": {
                "type": "userInvitations",
                "attributes": {
                    "email": email,
                    "firstName": first_name,
                    "lastName": last_name,
                    "roles": ["MARKETING"],
                    "allAppsVisible": False,
                    "provisioningAllowed": False,
                },
                "relationships": {
                    "visibleApps": {
                        "data": [{"type": "apps", "id": app_id}]
                    }
                },
            }
        },
    )
    created = (payload.get("data") or {}).get("id")
    if not created:
        raise RuntimeError(f"inviting App Store Connect user {email} returned no id")
    return str(created)


def reinvite_revoked_testers(
    token: str,
    testers: list[dict],
    groups: list[dict],
    build_id: str,
    app_id: str,
    team_emails: set[str],
) -> list[dict]:
    group_ids = [group["id"] for group in groups if group["is_internal"]]
    if not group_ids:
        group_ids = [group["id"] for group in groups]
    try:
        pending = {item["email"].lower(): item for item in list_user_invitations(token)}
    except ASCHTTPError as exc:
        print(f"user invitations: {exc}", file=sys.stderr)
        pending = {}
    kept: list[dict] = []
    for tester in testers:
        if not tester_needs_reinvite(tester):
            kept.append(tester)
            continue
        email = tester["email"]
        prior = tester.get("state") or "unknown"
        try:
            result = delete_tester(token, tester["id"])
            print(f"{result} {prior} tester {email}")
        except ASCHTTPError as exc:
            print(f"could not remove {prior} tester {email}: {exc}", file=sys.stderr)
        created = None
        try:
            created = create_tester(token, email, group_ids, build_id)
            print(
                f"reinvited {email} was={prior} id={created['id']} "
                f"state={created['state'] or 'unknown'}"
            )
        except ASCHTTPError as exc:
            print(f"could not reinvite {email}: {exc}", file=sys.stderr)
            created = tester
        if tester_needs_reinvite(created) and email.lower() not in team_emails:
            first = created.get("first_name") or tester.get("first_name") or ""
            last = created.get("last_name") or tester.get("last_name") or ""
            if email.lower() in pending:
                print(
                    f"waiting for {email} to accept App Store Connect user invite",
                    file=sys.stderr,
                )
            elif not first or not last:
                print(
                    f"cannot invite {email} as App Store Connect user; "
                    f"Apple did not return a name",
                    file=sys.stderr,
                )
            else:
                try:
                    invite_id = invite_app_store_connect_user(
                        token, email, first, last, app_id
                    )
                    print(
                        f"invited {email} to App Store Connect as MARKETING "
                        f"id={invite_id}; they must accept that email before "
                        f"internal TestFlight works"
                    )
                except ASCHTTPError as exc:
                    if ignore_already_exists(exc):
                        print(f"App Store Connect invite already exists for {email}")
                    else:
                        print(
                            f"could not invite {email} to App Store Connect: {exc}",
                            file=sys.stderr,
                        )
        kept.append(created)
    return kept


def parse_user_email(item: dict) -> str:
    attrs = item.get("attributes") or {}
    return str(attrs.get("username") or attrs.get("email") or "")


def list_team_user_emails(token: str) -> list[str]:
    items, _ = collect_resources(
        token,
        "/v1/users",
        {"fields[users]": "username", "limit": "200"},
    )
    emails: list[str] = []
    for item in items:
        email = parse_user_email(item)
        if "@" in email:
            emails.append(email)
    return emails


def invite_missing_team_users(
    token: str, testers: list[dict], groups: list[dict], build_id: str
) -> list[dict]:
    known = {item["email"].lower() for item in testers if item.get("email")}
    group_ids = [group["id"] for group in groups if group["is_internal"]]
    if not group_ids:
        group_ids = [group["id"] for group in groups]
    try:
        emails = list_team_user_emails(token)
    except ASCHTTPError as exc:
        print(f"team users: {exc}", file=sys.stderr)
        return testers
    print(f"team users={len(emails)}")
    for email in emails:
        print(f"team user {email}")
    extra = list(testers)
    for email in emails:
        if email.lower() in known:
            continue
        try:
            created = create_tester(token, email, group_ids, build_id)
            print(
                f"invited team user {email} id={created['id']} "
                f"state={created['state'] or 'unknown'}"
            )
            extra.append(created)
            known.add(email.lower())
        except ASCHTTPError as exc:
            print(f"could not invite team user {email}: {exc}", file=sys.stderr)
    return extra


def add_tester_to_group(token: str, group_id: str, tester_id: str) -> str:
    try:
        asc_request(
            token,
            f"/v1/betaGroups/{group_id}/relationships/betaTesters",
            method="POST",
            body={"data": [{"type": "betaTesters", "id": tester_id}]},
        )
        return "added"
    except ASCHTTPError as exc:
        if ignore_already_exists(exc):
            return "already"
        raise


def list_beta_groups(token: str, identifier: str) -> list[dict]:
    items, _ = collect_resources(
        token,
        "/v1/betaGroups",
        {
            "filter[app]": identifier,
            "fields[betaGroups]": (
                "name,isInternalGroup,hasAccessToAllBuilds,publicLinkEnabled,"
                "publicLink,publicLinkLimitEnabled,publicLinkLimit"
            ),
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
        if internal_group_rejects_assign(exc):
            return "automatic"
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


def external_groups(groups: list[dict]) -> list[dict]:
    return [group for group in groups if not group["is_internal"]]


def find_group_by_name(groups: list[dict], name: str) -> dict | None:
    wanted = name.strip().lower()
    for group in groups:
        if group["name"].strip().lower() == wanted:
            return group
    return None


def get_beta_group(token: str, group_id: str) -> dict:
    payload = asc_request(
        token,
        f"/v1/betaGroups/{group_id}",
        {
            "fields[betaGroups]": (
                "name,isInternalGroup,hasAccessToAllBuilds,publicLinkEnabled,"
                "publicLink,publicLinkLimitEnabled,publicLinkLimit"
            )
        },
    )
    return parse_group(payload.get("data") or {"id": group_id})


def create_external_group(token: str, identifier: str, name: str) -> dict:
    # Beta groups created through the API are external; internal groups are
    # managed by App Store Connect and cannot be created here.
    payload = asc_request(
        token,
        "/v1/betaGroups",
        method="POST",
        body={
            "data": {
                "type": "betaGroups",
                "attributes": {"name": name},
                "relationships": {
                    "app": {"data": {"type": "apps", "id": identifier}}
                },
            }
        },
    )
    return parse_group(payload.get("data") or {})


def enable_public_link(token: str, group: dict) -> dict:
    payload = asc_request(
        token,
        f"/v1/betaGroups/{group['id']}",
        method="PATCH",
        body={
            "data": {
                "type": "betaGroups",
                "id": group["id"],
                "attributes": {"publicLinkEnabled": True},
            }
        },
    )
    return parse_group(payload.get("data") or {"id": group["id"]})


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


def wait_for_installable_build(
    token: str,
    identifier: str,
    number: int,
    timeout_s: int = 45 * 60,
    sleep_s: int = 30,
) -> dict:
    deadline = time.time() + timeout_s
    seen = "missing"
    expires_at = int(time.time()) + TOKEN_LIFETIME_S
    while True:
        now = int(time.time())
        if token_needs_refresh(now, expires_at):
            print("refreshing App Store Connect token")
            token = fresh_token()
            expires_at = now + TOKEN_LIFETIME_S
        builds = list_app_builds(token, identifier)
        match = next((item for item in builds if item["number"] == number), None)
        if match:
            clear_export_compliance(token, match)
            seen = (
                f"{match['processing_state'] or 'unknown'}"
                f"/{match.get('internal_build_state') or 'no-internal-state'}"
            )
            if is_installable(match):
                return match
            if match["processing_state"] in {"FAILED", "INVALID"}:
                raise RuntimeError(f"build {number} is {match['processing_state']}")
        if time.time() >= deadline:
            raise RuntimeError(
                f"timed out waiting for build {number} to be installable (state={seen})"
            )
        time.sleep(sleep_s)


def entitle_every_tester(token: str, identifier: str, latest: dict, groups: list[dict]) -> None:
    testers = {item["id"]: item for item in list_app_testers(token, identifier, groups)}
    for build in list_app_builds(token, identifier):
        try:
            items, _ = collect_resources(
                token,
                f"/v1/builds/{build['id']}/individualTesters",
                {"fields[betaTesters]": TESTER_FIELDS, "limit": "200"},
            )
            _merge_testers(testers, items)
        except ASCHTTPError as exc:
            print(f"individual testers on build {build['number']}: {exc}", file=sys.stderr)

    records = sorted(testers.values(), key=lambda item: item["email"] or item["id"])
    try:
        team_emails = {email.lower() for email in list_team_user_emails(token)}
    except ASCHTTPError as exc:
        print(f"team users: {exc}", file=sys.stderr)
        team_emails = set()
    records = invite_missing_team_users(token, records, groups, latest["id"])
    records = reinvite_revoked_testers(
        token, records, groups, latest["id"], identifier, team_emails
    )
    print(f"app testers={len(records)}")
    for tester in records:
        label = tester["email"] or tester["id"]
        name = " ".join(
            part
            for part in (tester.get("first_name"), tester.get("last_name"))
            if part
        )
        print(
            f"tester {label} invite={tester['invite_type'] or 'unknown'} "
            f"state={tester['state'] or 'unknown'}"
            + (f" name={name}" if name else "")
        )
    if not records:
        raise RuntimeError("no TestFlight testers found; not expiring older builds")
    still_blocked = testers_needing_reinvite(records)
    if still_blocked:
        labels = ", ".join(
            f"{item['email']}={item.get('state') or 'unknown'}" for item in still_blocked
        )
        raise RuntimeError(
            f"testers still cannot install after reinvite; not expiring older builds: {labels}"
        )

    for group in groups:
        if not group["is_internal"]:
            continue
        for tester in records:
            try:
                result = add_tester_to_group(token, group["id"], tester["id"])
                label = tester["email"] or tester["id"]
                print(f"internal group {group['name']}: {result} {label}")
            except ASCHTTPError as exc:
                label = tester["email"] or tester["id"]
                print(
                    f"internal group {group['name']}: could not add {label}: {exc}",
                    file=sys.stderr,
                )

    added = assign_individual_testers(
        token, latest["id"], [tester["id"] for tester in records]
    )
    print(f"entitled {added} tester(s) to build {latest['number']}")


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
            if group["is_internal"] and (
                group.get("has_access_to_all_builds") is True or access == "enabled"
            ):
                print(f"{kind} group {group['name']}: already receives every build")
                continue
            if not group["is_internal"]:
                review = submit_beta_review(token, latest["id"])
                if review == "submitted":
                    print(
                        f"{kind} group {group['name']}: submitted build {latest['number']} for Beta Review"
                    )
            assigned = assign_build_to_group(token, group["id"], latest["id"])
            if assigned == "automatic":
                print(f"{kind} group {group['name']}: already receives every build")
            else:
                print(f"{kind} group {group['name']}: {assigned} build {latest['number']}")
        except ASCHTTPError as exc:
            if group["is_internal"] and internal_group_rejects_assign(exc):
                print(f"{kind} group {group['name']}: already receives every build")
                continue
            failures.append(f"{kind} group {group['name']}: {exc}")
            print(f"{kind} group {group['name']}: FAILED {exc}", file=sys.stderr)

    entitle_every_tester(token, identifier, latest, groups)

    if failures:
        raise RuntimeError(
            "not every TestFlight group has the latest build; older builds were left in place. "
            + " ".join(failures)
        )
    if not is_installable(latest):
        raise RuntimeError(
            f"build {latest['number']} is not installable yet "
            f"(internal={latest.get('internal_build_state')}); not expiring older builds"
        )

    old = builds_to_expire(list_app_builds(token, identifier), latest)
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


CERTIFICATE_FIELDS = (
    "certificateType,displayName,name,serialNumber,expirationDate,platform"
)
# Development certificate types that consume the Apple Development cert cap and
# therefore block Automatic signing once the account is full. This is an
# iPad-only app, so the iOS/Apple Development types are what matter; Mac
# development certs are included because they share the same development pool.
DEVELOPMENT_CERT_TYPES = frozenset(
    {"DEVELOPMENT", "IOS_DEVELOPMENT", "MAC_APP_DEVELOPMENT"}
)


def parse_certificate(item: dict) -> dict:
    attrs = item.get("attributes") or {}
    return {
        "id": str(item.get("id") or ""),
        "type": str(attrs.get("certificateType") or ""),
        "name": str(attrs.get("name") or ""),
        "display_name": str(attrs.get("displayName") or ""),
        "serial": str(attrs.get("serialNumber") or ""),
        "expiration": str(attrs.get("expirationDate") or ""),
        "platform": str(attrs.get("platform") or ""),
    }


def list_certificates(token: str) -> list[dict]:
    items, _ = collect_resources(
        token,
        "/v1/certificates",
        {"fields[certificates]": CERTIFICATE_FIELDS, "limit": "200"},
    )
    return [parse_certificate(item) for item in items]


def development_certificates(
    certs: list[dict], types: frozenset[str] = DEVELOPMENT_CERT_TYPES
) -> list[dict]:
    return [cert for cert in certs if cert["type"] in types]


def certificate_age_key(cert: dict) -> tuple[str, str]:
    # A cert lives one year from creation, so the one expiring soonest is the
    # oldest. Sorting by expiration ascending puts the oldest certs first; the
    # serial breaks ties deterministically.
    return (cert["expiration"] or "", cert["serial"] or cert["id"])


def spare_certificates_to_revoke(certs: list[dict], keep: int) -> list[dict]:
    ordered = sorted(certs, key=certificate_age_key)
    if keep <= 0:
        return ordered
    if len(ordered) <= keep:
        return []
    return ordered[:-keep]


def revoke_certificate(token: str, cert_id: str) -> str:
    try:
        asc_request(token, f"/v1/certificates/{cert_id}", method="DELETE")
        return "revoked"
    except ASCHTTPError as exc:
        if exc.code == 404:
            return "already"
        raise


def describe_certificate(cert: dict) -> str:
    return (
        f"id={cert['id']} type={cert['type'] or '?'} "
        f"name={cert['name'] or '?'} display={cert['display_name'] or '?'} "
        f"expires={cert['expiration'] or '?'} serial={cert['serial'] or '?'}"
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
        if build.get("internal_build_state"):
            flags.append(f"internal={build['internal_build_state']}")
        if build.get("external_build_state"):
            flags.append(f"external={build['external_build_state']}")
        if is_installable(build):
            flags.append("installable")
        if external_build_ready(build):
            flags.append("external-ready")
        print(f"build {build['number']} {' '.join(flags)}")
    testers = list_app_testers(token, identifier, list_beta_groups(token, identifier))
    print(f"app testers={len(testers)}")
    for tester in testers:
        print(
            f"tester {tester['email'] or tester['id']} "
            f"invite={tester['invite_type'] or 'unknown'} "
            f"state={tester['state'] or 'unknown'}"
        )
    groups = list_beta_groups(token, identifier)
    if not external_groups(groups):
        print("external_group=none")
    for group in groups:
        kind = "internal" if group["is_internal"] else "external"
        all_builds = group.get("has_access_to_all_builds")
        testers = ",".join(group_testers(token, group["id"])) or "none"
        numbers = ",".join(str(item["number"]) for item in group_builds(token, group["id"])) or "none"
        line = (
            f"group {group['name']} {kind} all_builds={all_builds} "
            f"testers={testers} builds={numbers}"
        )
        if not group["is_internal"]:
            link = group.get("public_link") or "none"
            line += (
                f" public_link_enabled={group.get('public_link_enabled')} "
                f"public_link={link}"
            )
        print(line)
    return 0


def cmd_revoke_spare_development_certs(keep: int, execute: bool) -> int:
    if keep < 0:
        raise RuntimeError("--keep must be zero or greater")
    token = fresh_token()
    certs = list_certificates(token)
    dev = development_certificates(certs)
    print(f"development certificates={len(dev)} (of {len(certs)} total)")
    for cert in sorted(dev, key=certificate_age_key):
        print(f"cert {describe_certificate(cert)}")
    to_revoke = spare_certificates_to_revoke(dev, keep)
    if not to_revoke:
        print(f"nothing to revoke; keeping newest {keep} development cert(s)")
        return 0
    print(
        f"keeping newest {keep}; {len(to_revoke)} spare development cert(s) "
        f"{'to revoke' if execute else 'would be revoked'}"
    )
    if not execute:
        for cert in to_revoke:
            print(f"would revoke {describe_certificate(cert)}")
        print("dry run; pass --execute to revoke")
        return 0
    failures: list[str] = []
    for cert in to_revoke:
        try:
            result = revoke_certificate(token, cert["id"])
            print(f"{result} {describe_certificate(cert)}")
        except ASCHTTPError as exc:
            failures.append(f"{cert['id']}: {exc}")
            print(f"could not revoke {describe_certificate(cert)}: {exc}", file=sys.stderr)
    if failures:
        raise RuntimeError("some development certs could not be revoked: " + " ".join(failures))
    return 0


def cmd_latest_only(wait_for: int | None) -> int:
    token, bundle, identifier = _app_context()
    if wait_for is not None:
        print(f"waiting for build {wait_for} on {bundle}", flush=True)
        wait_for_installable_build(token, identifier, wait_for)
        token = fresh_token()
    latest = latest_installable_build(list_app_builds(token, identifier))
    if latest is None:
        latest = latest_valid_build(list_app_builds(token, identifier))
        if latest is None:
            raise RuntimeError("no VALID unexpired TestFlight build")
        raise RuntimeError(
            f"build {latest['number']} is VALID but not installable yet "
            f"(internal={latest.get('internal_build_state')})"
        )
    print(f"latest {latest['number']} {latest.get('internal_build_state')}")
    enforce_latest_only(token, identifier, latest)
    return 0


def _print_public_link(group: dict) -> str | None:
    link = group.get("public_link") or ""
    if group.get("public_link_enabled") and link:
        print(f"INVITE public_link={link}")
        return link
    return None


def cmd_invite_tester(
    email: str,
    external: bool,
    internal: bool,
    group_name: str | None,
    create_group: bool,
    submit_review: bool,
    public_link: bool,
) -> int:
    email = email.strip()
    if "@" not in email:
        raise RuntimeError(f"invalid tester email: {email!r}")
    # External is the preferred path unless internal was explicitly requested.
    want_external = external or not internal
    token, bundle, identifier = _app_context()
    builds = list_app_builds(token, identifier)
    latest = latest_installable_build(builds) or latest_valid_build(builds)
    if latest is None:
        raise RuntimeError("no VALID unexpired TestFlight build to invite testers onto")
    print(f"app={bundle} id={identifier}")
    print(
        f"latest build {latest['number']} "
        f"internal={latest.get('internal_build_state') or 'none'} "
        f"external={latest.get('external_build_state') or 'none'}"
    )
    groups = list_beta_groups(token, identifier)

    if internal and not external:
        internal_groups = [group for group in groups if group["is_internal"]]
        if not internal_groups:
            raise RuntimeError("no internal group exists; create one in App Store Connect")
        target = internal_groups[0]
        try:
            created = create_tester(token, email, [target["id"]], "")
        except ASCHTTPError as exc:
            if tester_cannot_be_assigned(exc):
                print(
                    f"INVITE BLOCKER internal: {email} is not an App Store Connect user, "
                    f"so Apple refuses the internal group '{target['name']}'. "
                    f"Use --external (preferred) or add them as an ASC user first.",
                    file=sys.stderr,
                )
                return 1
            raise
        print(
            f"INVITE internal group={target['name']} email={email} "
            f"state={created['state'] or 'unknown'} id={created['id']}"
        )
        return 0 if tester_live(created) else 1

    # External path (preferred).
    externals = external_groups(groups)
    target = None
    if group_name:
        target = find_group_by_name(externals, group_name)
    elif externals:
        target = externals[0]
    if target is None:
        if not create_group:
            existing = ", ".join(g["name"] for g in externals) or "none"
            raise RuntimeError(
                "no matching external beta group "
                f"(external groups: {existing}); pass --create-group to create "
                f"'{group_name or 'External Testers'}' or create it in App Store Connect"
            )
        name = group_name or "External Testers"
        target = create_external_group(token, identifier, name)
        print(f"INVITE created external group={target['name']} id={target['id']}")

    try:
        assigned = assign_build_to_group(token, target["id"], latest["id"])
        print(f"INVITE external group={target['name']}: {assigned} build {latest['number']}")
    except ASCHTTPError as exc:
        print(
            f"INVITE could not assign build {latest['number']} to '{target['name']}': {exc}",
            file=sys.stderr,
        )

    if submit_review and not external_build_ready(latest):
        try:
            review = submit_beta_review(token, latest["id"])
            print(
                f"INVITE external group={target['name']}: beta review {review} "
                f"build {latest['number']}"
            )
        except ASCHTTPError as exc:
            print(
                f"INVITE could not submit build {latest['number']} for Beta Review: {exc}",
                file=sys.stderr,
            )

    # Refresh the build so we report the true external state after any assign/submit.
    fresh = next(
        (b for b in list_app_builds(token, identifier) if b["id"] == latest["id"]),
        latest,
    )
    if external_build_ready(fresh):
        print(f"INVITE external build {fresh['number']} is APPROVED for external testing")
    elif external_review_pending(fresh):
        print(
            f"INVITE BLOCKER external build {fresh['number']} is in Beta App Review "
            f"(external={fresh.get('external_build_state')}); testers can install once approved",
            file=sys.stderr,
        )
    else:
        print(
            f"INVITE BLOCKER external build {fresh['number']} is not yet approved "
            f"(external={fresh.get('external_build_state') or 'none'}); it must pass "
            f"Beta App Review before external testers can install",
            file=sys.stderr,
        )

    created = create_tester(token, email, [target["id"]], "")
    print(
        f"INVITE external group={target['name']} email={email} "
        f"state={created['state'] or 'unknown'} id={created['id']}"
    )

    link = None
    target = get_beta_group(token, target["id"])
    if public_link and not target.get("public_link_enabled"):
        try:
            target = enable_public_link(token, target)
            print(f"INVITE external group={target['name']}: public link enabled")
        except ASCHTTPError as exc:
            print(
                f"INVITE could not enable public link on '{target['name']}': {exc}",
                file=sys.stderr,
            )
    link = _print_public_link(target)
    if public_link and not link:
        print(
            f"INVITE public link not available yet on '{target['name']}' "
            f"(Apple enables it once the group has an approved build)",
            file=sys.stderr,
        )

    return 0 if tester_live(created) else 1


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
    invite_p = sub.add_parser("invite-tester")
    invite_p.add_argument("--email", required=True, help="tester email address")
    invite_p.add_argument(
        "--external",
        action="store_true",
        help="invite as an external tester (preferred; default when neither flag is set)",
    )
    invite_p.add_argument(
        "--internal",
        action="store_true",
        help="invite as an internal tester (requires the email to be an App Store Connect user)",
    )
    invite_p.add_argument(
        "--group",
        default=None,
        help="external beta group name to use (matched by name; created with --create-group)",
    )
    invite_p.add_argument(
        "--create-group",
        action="store_true",
        help="create the external beta group if no matching one exists",
    )
    invite_p.add_argument(
        "--submit-review",
        action="store_true",
        help="submit the latest build for Beta App Review if it is not already approved",
    )
    invite_p.add_argument(
        "--public-link",
        action="store_true",
        help="enable and print the external group's public TestFlight link",
    )
    revoke_p = sub.add_parser("revoke-spare-development-certs")
    revoke_p.add_argument(
        "--keep",
        type=int,
        default=1,
        help="how many newest Development certificates to keep (default 1)",
    )
    revoke_p.add_argument(
        "--execute",
        action="store_true",
        help="actually revoke; without this the command only lists (dry run)",
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
    if args.cmd == "invite-tester":
        return cmd_invite_tester(
            args.email,
            args.external,
            args.internal,
            args.group,
            args.create_group,
            args.submit_review,
            args.public_link,
        )
    if args.cmd == "revoke-spare-development-certs":
        return cmd_revoke_spare_development_certs(args.keep, args.execute)
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as exc:
        sys.stderr.write(f"{exc}\n")
        sys.exit(1)
