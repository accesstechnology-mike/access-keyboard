#!/usr/bin/env python3
"""Submit one App Store version for access: keyboard.

The What's New text is the stripped contents of ``release-notes/<version>.txt``.
That file is the en-GB text. This command writes nothing else on the version:
no description, keywords, promotional text, URLs, screenshots, pricing, privacy
answers, or review notes.

It uses the same App Store Connect key as ``scripts/app_store_connect.py``.

    python3 scripts/submit_app_store.py --version 1.0.1 --build 23
    python3 scripts/submit_app_store.py --version 1.0.1 --build 23 --dry-run
    python3 scripts/submit_app_store.py --from-project
    python3 scripts/submit_app_store.py --check-notes --from-project

``--dry-run`` only reads App Store Connect. ``--check-notes`` does not contact
App Store Connect at all. A re-run is safe when the version already exists or
is already in review: matching state is left alone, and a second submission is
not sent.
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

import app_store_connect as asc

ROOT = asc.ROOT
PLATFORM = "IOS"
PRIMARY_LOCALE = "en-GB"
AUTOMATIC_RELEASE = "AFTER_APPROVAL"
WHATS_NEW_LIMIT = 4000
VERSION_RE = re.compile(r"\d+\.\d+(?:\.\d+)?")

# Version states where the build and What's New may still be changed.
EDITABLE_STATES = frozenset(
    {
        "PREPARE_FOR_SUBMISSION",
        "READY_FOR_REVIEW",
        "REJECTED",
        "METADATA_REJECTED",
        "DEVELOPER_REJECTED",
        "INVALID_BINARY",
    }
)
# Already with App Review, or already released. Do not edit the build or What's New.
LOCKED_STATES = frozenset(
    {
        "WAITING_FOR_REVIEW",
        "IN_REVIEW",
        "ACCEPTED",
        "PENDING_DEVELOPER_RELEASE",
        "PENDING_APPLE_RELEASE",
        "WAITING_FOR_EXPORT_COMPLIANCE",
        "PENDING_CONTRACT",
        "PROCESSING_FOR_DISTRIBUTION",
        "PROCESSING_FOR_APP_STORE",
        "READY_FOR_DISTRIBUTION",
        "READY_FOR_SALE",
    }
)
# Apple may still accept a release-type change in these states.
RELEASE_TYPE_STILL_SETTABLE = frozenset(
    {
        "READY_FOR_REVIEW",
        "WAITING_FOR_REVIEW",
        "IN_REVIEW",
        "ACCEPTED",
        "PENDING_DEVELOPER_RELEASE",
        "PENDING_APPLE_RELEASE",
    }
)
TERMINAL_REFUSAL = frozenset(
    {
        "REPLACED_WITH_NEW_VERSION",
        "REMOVED_FROM_SALE",
        "DEVELOPER_REMOVED_FROM_SALE",
    }
)
OPEN_REVIEW_STATES = (
    "READY_FOR_REVIEW",
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "UNRESOLVED_ISSUES",
)
IN_FLIGHT_REVIEW_STATES = frozenset({"WAITING_FOR_REVIEW", "IN_REVIEW"})


def project_versions() -> tuple[str, str]:
    text = asc.PBXPROJ.read_text()
    return (
        asc.unique_setting(text, "MARKETING_VERSION"),
        asc.unique_setting(text, "CURRENT_PROJECT_VERSION"),
    )


def resolve_target(
    version: str | None, build: int | None, from_project: bool
) -> tuple[str, int]:
    marketing, project_build = project_versions()
    try:
        project_number = int(project_build)
    except ValueError as exc:
        raise RuntimeError(
            f"CURRENT_PROJECT_VERSION is not an integer: {project_build}"
        ) from exc
    if from_project:
        if version is not None or build is not None:
            raise RuntimeError(
                "pass either --from-project or --version and --build, not both"
            )
        return marketing, project_number
    if version is None or build is None:
        raise RuntimeError("pass --version and --build, or --from-project")
    if build < 1:
        raise RuntimeError(f"build number must be a positive integer, got {build}")
    if version != marketing:
        raise RuntimeError(
            f"refusing to submit {version}: MARKETING_VERSION in the Xcode project is {marketing}"
        )
    if build != project_number:
        raise RuntimeError(
            f"refusing to submit build {build}: "
            f"CURRENT_PROJECT_VERSION in the Xcode project is {project_number}"
        )
    return version, build


def release_notes_path(version: str, root: Path | None = None) -> Path:
    if not VERSION_RE.fullmatch(version):
        raise RuntimeError(
            f"version must look like 1.0.1 (digits and dots only), got {version!r}"
        )
    base = ROOT if root is None else root
    return base / "release-notes" / f"{version}.txt"


def load_release_notes(version: str, root: Path | None = None) -> str:
    path = release_notes_path(version, root)
    relative = f"release-notes/{version}.txt"
    if not path.is_file():
        raise RuntimeError(
            f"missing What's New text for {version}: {relative}. "
            "Add that file before submitting. This workflow will not invent release notes."
        )
    try:
        raw = path.read_text(encoding="utf-8")
    except UnicodeError as exc:
        raise RuntimeError(f"{relative} is not UTF-8: {exc}") from exc
    text = raw.strip()
    if not text:
        raise RuntimeError(f"{relative} is empty")
    if len(text) > WHATS_NEW_LIMIT:
        raise RuntimeError(
            f"{relative} is {len(text)} characters; Apple allows {WHATS_NEW_LIMIT}"
        )
    return text


def _resource(
    type_name: str,
    ident: str | None,
    attributes: dict | None,
    relationships: dict | None,
    allowed_attributes: frozenset[str],
    allowed_relationships: frozenset[str],
) -> dict:
    """Build one JSON:API resource and refuse any other attribute or relationship."""
    if attributes is not None:
        illegal = set(attributes) - allowed_attributes
        if illegal:
            raise RuntimeError(
                f"refusing to send {sorted(illegal)} on {type_name}; "
                f"this workflow only sets {sorted(allowed_attributes) or 'nothing'}"
            )
    if relationships is None:
        if allowed_relationships:
            raise RuntimeError(f"{type_name} is missing relationships {sorted(allowed_relationships)}")
    elif set(relationships) != allowed_relationships:
        raise RuntimeError(
            f"refusing to send relationships {sorted(relationships)} on {type_name}; "
            f"only {sorted(allowed_relationships) or 'none'} are allowed"
        )
    data: dict = {"type": type_name}
    if ident is not None:
        data["id"] = ident
    if attributes is not None:
        data["attributes"] = attributes
    if relationships is not None:
        data["relationships"] = relationships
    return {"data": data}


def version_state(attributes: dict) -> str:
    current = attributes.get("appVersionState")
    legacy = attributes.get("appStoreState")
    return str(current or legacy or "")


def parse_store_version(item: dict) -> dict:
    attributes = item.get("attributes") or {}
    return {
        "id": str(item.get("id") or ""),
        "version_string": str(attributes.get("versionString") or ""),
        "platform": str(attributes.get("platform") or ""),
        "state": version_state(attributes),
        "release_type": attributes.get("releaseType"),
        "build_id": None,
    }


def parse_localization(item: dict) -> dict:
    attributes = item.get("attributes") or {}
    whats_new = attributes.get("whatsNew")
    return {
        "id": str(item.get("id") or ""),
        "locale": str(attributes.get("locale") or ""),
        "whats_new": "" if whats_new is None else str(whats_new),
    }


def parse_review_item(item: dict) -> dict:
    links = []
    for key, value in (item.get("relationships") or {}).items():
        data = (value or {}).get("data")
        rows = data if isinstance(data, list) else [data]
        for row in rows:
            if isinstance(row, dict) and row.get("id"):
                links.append(
                    {
                        "relationship": key,
                        "type": str(row.get("type") or key),
                        "id": str(row["id"]),
                    }
                )
    return {"id": str(item.get("id") or ""), "links": links}


def parse_store_build(item: dict, included: list[dict]) -> dict | None:
    parsed = asc.parse_build(item)
    if parsed is None:
        return None
    asc.attach_beta_detail(item, parsed, included)
    marketing, platform = _included_pre_release(item, included)
    parsed["marketing_version"] = marketing
    parsed["platform"] = platform
    parsed["installable"] = asc.is_installable(parsed)
    return parsed


def _included_pre_release(item: dict, included: list[dict]) -> tuple[str, str]:
    linkage = ((item.get("relationships") or {}).get("preReleaseVersion") or {}).get("data") or {}
    wanted = linkage.get("id")
    if not wanted:
        return "", ""
    for resource in included:
        if resource.get("type") == "preReleaseVersions" and resource.get("id") == wanted:
            attributes = resource.get("attributes") or {}
            return str(attributes.get("version") or ""), str(attributes.get("platform") or "")
    return "", ""


def _item_is_this_version(item: dict, version_id: str) -> bool:
    links = item.get("links") or []
    return bool(links) and all(
        link.get("type") == "appStoreVersions" and link.get("id") == version_id for link in links
    )


def _review_has_version(review: dict, version_id: str) -> bool:
    return any(_item_is_this_version(item, version_id) for item in review.get("items") or [])


def _only_this_version(review: dict, version_id: str) -> bool:
    items = review.get("items") or []
    return bool(items) and all(_item_is_this_version(item, version_id) for item in items)


def _draft_is_safe(review: dict, version_id: str | None) -> bool:
    items = review.get("items") or []
    if not items:
        return True
    if not version_id:
        return False
    return all(_item_is_this_version(item, version_id) for item in items)


def _describe_items(review: dict) -> str:
    parts = []
    for item in review.get("items") or []:
        links = item.get("links") or []
        if not links:
            parts.append(f"{item.get('id') or 'item'} (no related resource)")
            continue
        for link in links:
            parts.append(f"{link.get('relationship') or link.get('type')}={link.get('id')}")
    return ", ".join(parts) or "none"


def en_gb_localization(rows: list[dict], version: str) -> dict:
    matches = [row for row in rows if row.get("locale") == PRIMARY_LOCALE]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        locales = ", ".join(sorted({row.get("locale") or "?" for row in rows})) or "none"
        raise RuntimeError(
            f"version {version} has no {PRIMARY_LOCALE} localization (found {locales}). "
            "Refusing to create one. This workflow only sets What's New and will not "
            "write any other listing field."
        )
    raise RuntimeError(f"version {version} has {len(matches)} {PRIMARY_LOCALE} localizations")


def _act(mutate: bool, message: str, action) -> None:
    if not mutate:
        print(f"dry-run: would {message}", flush=True)
        return
    print(f"app store: {message}", flush=True)
    action()


def _require_build(build: dict | None, version: str, number: int, mutate: bool) -> dict:
    wait_hint = "" if mutate else " A real run waits until processing finishes."
    if build is None:
        raise RuntimeError(f"build {number} is not in App Store Connect.{wait_hint}")
    marketing = build.get("marketing_version") or ""
    if not marketing:
        raise RuntimeError(
            f"build {number} did not include a preReleaseVersion, so its marketing "
            f"version cannot be checked. Refusing to attach it to {version}."
        )
    if marketing != version:
        raise RuntimeError(
            f"build {number} is marketing version {marketing}, not {version}. Refusing to attach it."
        )
    platform = build.get("platform") or ""
    if platform and platform != PLATFORM:
        raise RuntimeError(f"build {number} platform is {platform}, not {PLATFORM}")
    if not build.get("installable"):
        raise RuntimeError(
            f"build {number} is not ready to submit "
            f"(processing={build.get('processing_state') or 'unknown'}, "
            f"internal={build.get('internal_build_state') or 'none'}, "
            f"expired={build.get('expired')}).{wait_hint}"
        )
    return build


def _reject_blocking_reviews(reviews: list[dict], version_id: str | None, version: str) -> None:
    drafts = [review for review in reviews if review.get("state") == "READY_FOR_REVIEW"]
    if len(drafts) > 1:
        ids = ", ".join(review["id"] for review in drafts)
        raise RuntimeError(
            f"found {len(drafts)} draft review submissions ({ids}); "
            "refusing to guess which one to submit"
        )
    for review in reviews:
        state = review.get("state")
        if state in IN_FLIGHT_REVIEW_STATES:
            if version_id and _review_has_version(review, version_id):
                continue
            raise RuntimeError(
                f"review submission {review['id']} is {state} and does not include "
                f"version {version}. Refusing to submit {version} while that review is open."
            )
        if state == "UNRESOLVED_ISSUES":
            if version_id and _only_this_version(review, version_id):
                continue
            raise RuntimeError(
                f"review submission {review['id']} is UNRESOLVED_ISSUES and is not only "
                f"version {version} ({_describe_items(review)}). "
                "Refusing to cancel or submit it."
            )
        if state == "READY_FOR_REVIEW" and not _draft_is_safe(review, version_id):
            raise RuntimeError(
                f"draft review submission {review['id']} contains items other than "
                f"version {version}: {_describe_items(review)}. Refusing to submit them."
            )


def _finish_already_submitted(client, version_row: dict, build: dict, notes: str, version: str, mutate: bool) -> None:
    state = version_row["state"] or "unknown"
    if version_row.get("build_id") != build["id"]:
        attached = version_row.get("build_id") or "none"
        raise RuntimeError(
            f"version {version} is {state} with build id {attached}, "
            f"not build {build['number']} ({build['id']}). "
            "Refusing to replace a build that is already with App Review."
        )
    localization = en_gb_localization(client.localizations(version_row["id"]), version)
    if localization["whats_new"].strip() != notes:
        raise RuntimeError(
            f"version {version} is {state}, but {PRIMARY_LOCALE} What's New does not match "
            f"release-notes/{version}.txt. Refusing to edit a version that is already with App Review."
        )
    print(f"app store: version {version} is already {state}", flush=True)
    if version_row.get("release_type") == AUTOMATIC_RELEASE:
        print(
            "app store: release type is already AFTER_APPROVAL (automatic after approval)",
            flush=True,
        )
        return
    if state in RELEASE_TYPE_STILL_SETTABLE:
        _act(
            mutate,
            f"set release type AFTER_APPROVAL on version {version_row['id']}",
            lambda: client.set_release_type(version_row["id"]),
        )
        return
    print(
        f"app store: version is {state} with release type "
        f"{version_row.get('release_type') or 'unset'}; leaving the release type as Apple has it",
        flush=True,
    )


def _send_review(client, app_identifier: str, version_row: dict, reviews: list[dict], version: str, mutate: bool, canceled_id: str | None) -> None:
    version_id = version_row["id"]
    live = [review for review in reviews if review["id"] != canceled_id]
    inflight = [
        review
        for review in live
        if review.get("state") in IN_FLIGHT_REVIEW_STATES and _review_has_version(review, version_id)
    ]
    if inflight:
        print(
            f"app store: version {version} is already {inflight[0]['state']} "
            f"on review submission {inflight[0]['id']}",
            flush=True,
        )
        return
    drafts = [review for review in live if review.get("state") == "READY_FOR_REVIEW"]
    if len(drafts) > 1:
        raise RuntimeError("more than one draft review submission appeared before submit")
    if not mutate:
        if drafts:
            print(
                f"dry-run: would submit draft review submission {drafts[0]['id']} "
                f"containing only version {version}",
                flush=True,
            )
        else:
            print(
                f"dry-run: would create a review submission containing only version {version} "
                "and submit it for App Review",
                flush=True,
            )
        return
    if drafts:
        draft = drafts[0]
        if not _draft_is_safe(draft, version_id):
            raise RuntimeError(
                f"draft review submission {draft['id']} is no longer only version {version}"
            )
        if not any(_item_is_this_version(item, version_id) for item in draft.get("items") or []):
            print(f"app store: adding version {version} to review submission {draft['id']}", flush=True)
            client.add_version_item(draft["id"], version_id)
        print(f"app store: submitting review submission {draft['id']}", flush=True)
        client.submit_review(draft["id"])
    else:
        print(f"app store: creating a review submission for version {version}", flush=True)
        created = client.create_review(app_identifier)
        print(
            f"app store: adding version {version} to review submission {created['id']}",
            flush=True,
        )
        client.add_version_item(created["id"], version_id)
        print(f"app store: submitting review submission {created['id']}", flush=True)
        client.submit_review(created["id"])
    print(
        f"app store: submitted version {version} for App Review; "
        "it will be released automatically after approval",
        flush=True,
    )


def _run_submission(client, version: str, build_number: int, notes: str, mutate: bool) -> None:
    app_identifier = client.app_id()
    print(
        f"app store: version {version} build {build_number} "
        f"What's New release-notes/{version}.txt ({len(notes)} characters)",
        flush=True,
    )
    if mutate:
        client.wait_installable(app_identifier, build_number)
    build = _require_build(
        client.fetch_build(app_identifier, build_number), version, build_number, mutate
    )
    print(
        f"app store: build {build['number']} id={build['id']} "
        f"processing={build['processing_state']} marketing={build['marketing_version']}",
        flush=True,
    )

    version_row = client.find_version(app_identifier, version)
    reviews = client.open_reviews(app_identifier)
    _reject_blocking_reviews(
        reviews, version_row["id"] if version_row else None, version
    )

    created = False
    if version_row is None:
        if not mutate:
            print(
                "dry-run: would create the App Store version with release type AFTER_APPROVAL, "
                "attach the build, set en-GB What's New, and submit it for App Review",
                flush=True,
            )
            return
        print(f"app store: creating version {version}", flush=True)
        version_row = client.create_version(app_identifier, version)
        created = True
        print(
            f"app store: using version {version} id={version_row['id']} "
            f"state={version_row['state'] or 'unknown'}",
            flush=True,
        )
    else:
        print(
            f"app store: reusing version {version} id={version_row['id']} "
            f"state={version_row['state'] or 'unknown'}",
            flush=True,
        )

    state = version_row["state"]
    if state in TERMINAL_REFUSAL:
        raise RuntimeError(
            f"version {version} is {state}; this workflow will not resubmit it"
        )
    if state in LOCKED_STATES or _in_flight(reviews, version_row["id"]):
        _finish_already_submitted(client, version_row, build, notes, version, mutate)
        return
    if state not in EDITABLE_STATES:
        raise RuntimeError(
            f"version {version} is in state {state or 'unknown'}, "
            "which this workflow does not know how to submit"
        )

    canceled_id = None
    unresolved = _unresolved_only_this(reviews, version_row["id"])
    if unresolved is not None:
        canceled_id = unresolved["id"]
        _act(
            mutate,
            f"cancel unresolved review submission {canceled_id} so version {version} can be resubmitted",
            lambda: client.cancel_review(canceled_id),
        )

    if version_row.get("build_id") == build["id"]:
        print(f"app store: build {build['number']} is already attached", flush=True)
    else:
        _act(
            mutate,
            f"attach build {build['number']} ({build['id']}) to version {version_row['id']}",
            lambda: client.attach_build(version_row["id"], build["id"]),
        )

    localization = en_gb_localization(
        _localizations(client, version_row["id"], created, mutate), version
    )
    if localization["whats_new"].strip() == notes:
        print("app store: en-GB What's New already matches the release notes", flush=True)
    else:
        _act(
            mutate,
            f"set en-GB What's New on {localization['id']} ({len(notes)} characters)",
            lambda: client.set_whats_new(localization["id"], notes),
        )

    if version_row.get("release_type") == AUTOMATIC_RELEASE:
        print("app store: release type is already AFTER_APPROVAL", flush=True)
    else:
        _act(
            mutate,
            f"set release type AFTER_APPROVAL on version {version_row['id']}",
            lambda: client.set_release_type(version_row["id"]),
        )

    _send_review(
        client, app_identifier, version_row, reviews, version, mutate, canceled_id
    )


def _localizations(client, version_id: str, created: bool, mutate: bool) -> list[dict]:
    """Read localizations. A brand-new version can take a moment to copy en-GB."""
    rows = client.localizations(version_id)
    if rows or not created or not mutate:
        return rows
    for _attempt in range(3):
        print(
            "app store: version has no localizations yet; waiting for Apple to copy them",
            flush=True,
        )
        time.sleep(2)
        rows = client.localizations(version_id)
        if rows:
            return rows
    return rows


def _in_flight(reviews: list[dict], version_id: str) -> bool:
    return any(
        review.get("state") in IN_FLIGHT_REVIEW_STATES and _review_has_version(review, version_id)
        for review in reviews
    )


def _unresolved_only_this(reviews: list[dict], version_id: str) -> dict | None:
    matches = [
        review
        for review in reviews
        if review.get("state") == "UNRESOLVED_ISSUES" and _only_this_version(review, version_id)
    ]
    if len(matches) > 1:
        ids = ", ".join(review["id"] for review in matches)
        raise RuntimeError(
            f"found {len(matches)} unresolved review submissions for this version ({ids})"
        )
    return matches[0] if matches else None


def submit_release(client, version: str, build_number: int, notes: str, mutate: bool) -> None:
    _run_submission(client, version, build_number, notes, mutate)
    if not mutate:
        print("dry-run: finished without changing App Store Connect", flush=True)


class StoreClient:
    """App Store Connect calls for one submission. Reads and writes are separate methods."""

    def __init__(self, request, collect, token: str):
        self.request = request
        self.collect = collect
        self.token = token

    @classmethod
    def from_environment(cls) -> "StoreClient":
        return cls(asc.asc_request, asc.collect_resources, asc.fresh_token())

    def app_id(self) -> str:
        bundle = asc.app_bundle_id(asc.PBXPROJ.read_text())
        found = asc.app_id(self.token, bundle)
        print(f"app store: bundle {bundle} app {found}", flush=True)
        return found

    def wait_installable(self, app_identifier: str, number: int) -> None:
        print(f"app store: waiting for build {number} to finish processing", flush=True)
        asc.wait_for_installable_build(self.token, app_identifier, number)
        self.token = asc.fresh_token()

    def fetch_build(self, app_identifier: str, number: int) -> dict | None:
        items, included = self._list_numbered_builds(app_identifier, number)
        parsed = []
        for item in items:
            row = parse_store_build(item, included)
            if row is None or row["number"] != number:
                continue
            if not row["marketing_version"]:
                marketing, platform = self.read_pre_release_version(row["id"])
                row["marketing_version"] = marketing
                if platform:
                    row["platform"] = platform
            parsed.append(row)
        active = [row for row in parsed if not row["expired"]]
        chosen = active or parsed
        if not chosen:
            return None
        if len(chosen) > 1:
            raise RuntimeError(
                f"App Store Connect returned {len(chosen)} builds numbered {number}"
            )
        return chosen[0]

    def _list_numbered_builds(self, app_identifier: str, number: int):
        params = {
            "filter[app]": app_identifier,
            "filter[version]": str(number),
            "limit": "10",
        }
        try:
            return self.collect(
                self.token,
                "/v1/builds",
                {**params, "include": "preReleaseVersion,buildBetaDetail"},
            )
        except asc.ASCHTTPError as exc:
            if exc.code != 400:
                raise
            print(
                "app store: build list rejected include; reading the build without it",
                flush=True,
            )
            return self.collect(self.token, "/v1/builds", params)

    def read_pre_release_version(self, build_id: str) -> tuple[str, str]:
        try:
            payload = self.request(self.token, f"/v1/builds/{build_id}/preReleaseVersion")
        except asc.ASCHTTPError as exc:
            if exc.code == 404:
                return "", ""
            raise
        attributes = ((payload.get("data") or {}).get("attributes") or {})
        return str(attributes.get("version") or ""), str(attributes.get("platform") or "")

    def find_version(self, app_identifier: str, version: str) -> dict | None:
        items, _included = self.collect(
            self.token,
            f"/v1/apps/{app_identifier}/appStoreVersions",
            {
                "filter[platform]": PLATFORM,
                "filter[versionString]": version,
                "limit": "5",
            },
        )
        matched = []
        for item in items:
            parsed = parse_store_version(item)
            if parsed["version_string"] != version:
                continue
            if parsed["platform"] not in ("", PLATFORM):
                continue
            if not parsed["id"]:
                raise RuntimeError(f"App Store Connect returned version {version} without an id")
            parsed["build_id"] = self.read_attached_build_id(parsed["id"])
            matched.append(parsed)
        if not matched:
            return None
        if len(matched) > 1:
            raise RuntimeError(
                f"App Store Connect returned {len(matched)} iOS versions named {version}"
            )
        return matched[0]

    def read_attached_build_id(self, version_id: str) -> str | None:
        try:
            payload = self.request(
                self.token, f"/v1/appStoreVersions/{version_id}/relationships/build"
            )
        except asc.ASCHTTPError as exc:
            if exc.code == 404:
                return None
            raise
        data = payload.get("data")
        if not isinstance(data, dict):
            return None
        build_id = data.get("id")
        return str(build_id) if build_id else None

    def create_version(self, app_identifier: str, version: str) -> dict:
        body = _resource(
            "appStoreVersions",
            None,
            {
                "platform": PLATFORM,
                "versionString": version,
                "releaseType": AUTOMATIC_RELEASE,
            },
            {"app": {"data": {"type": "apps", "id": app_identifier}}},
            frozenset({"platform", "versionString", "releaseType"}),
            frozenset({"app"}),
        )
        try:
            payload = self.request(
                self.token, "/v1/appStoreVersions", method="POST", body=body
            )
        except asc.ASCHTTPError as exc:
            if exc.code != 409:
                raise
            existing = self.find_version(app_identifier, version)
            if existing is None:
                raise
            print(
                f"app store: version {version} already exists (id={existing['id']}); reusing it",
                flush=True,
            )
            return existing
        return self._version_from_write(payload, version)

    def _version_from_write(self, payload: dict, version: str) -> dict:
        data = payload.get("data") or {}
        if not data.get("id"):
            raise RuntimeError(f"App Store Connect did not return a version id for {version}")
        parsed = parse_store_version(data)
        if parsed["version_string"] and parsed["version_string"] != version:
            raise RuntimeError(
                f"App Store Connect returned version {parsed['version_string']} instead of {version}"
            )
        parsed["build_id"] = self.read_attached_build_id(parsed["id"])
        return parsed

    def set_release_type(self, version_id: str) -> None:
        body = _resource(
            "appStoreVersions",
            version_id,
            {"releaseType": AUTOMATIC_RELEASE},
            None,
            frozenset({"releaseType"}),
            frozenset(),
        )
        self.request(
            self.token,
            f"/v1/appStoreVersions/{version_id}",
            method="PATCH",
            body=body,
        )

    def attach_build(self, version_id: str, build_id: str) -> None:
        body = {"data": {"type": "builds", "id": build_id}}
        try:
            self.request(
                self.token,
                f"/v1/appStoreVersions/{version_id}/relationships/build",
                method="PATCH",
                body=body,
            )
        except asc.ASCHTTPError as exc:
            if exc.code != 409:
                raise
            current = self.read_attached_build_id(version_id)
            if current == build_id:
                print(f"app store: build {build_id} is already attached to {version_id}", flush=True)
                return
            raise

    def localizations(self, version_id: str) -> list[dict]:
        items, _included = self.collect(
            self.token,
            f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
            {"limit": "200"},
        )
        return [parse_localization(item) for item in items]

    def set_whats_new(self, localization_id: str, text: str) -> None:
        if not text or text != text.strip():
            raise RuntimeError("refusing to send What's New that is empty or has surrounding whitespace")
        if len(text) > WHATS_NEW_LIMIT:
            raise RuntimeError(f"What's New is {len(text)} characters; Apple allows {WHATS_NEW_LIMIT}")
        body = _resource(
            "appStoreVersionLocalizations",
            localization_id,
            {"whatsNew": text},
            None,
            frozenset({"whatsNew"}),
            frozenset(),
        )
        self.request(
            self.token,
            f"/v1/appStoreVersionLocalizations/{localization_id}",
            method="PATCH",
            body=body,
        )

    def open_reviews(self, app_identifier: str) -> list[dict]:
        found = []
        seen: set[str] = set()
        for state in OPEN_REVIEW_STATES:
            items, _included = self.collect(
                self.token,
                "/v1/reviewSubmissions",
                {
                    "filter[app]": app_identifier,
                    "filter[platform]": PLATFORM,
                    "filter[state]": state,
                    "limit": "20",
                },
            )
            for item in items:
                review_id = str(item.get("id") or "")
                if not review_id or review_id in seen:
                    continue
                seen.add(review_id)
                attributes = item.get("attributes") or {}
                found.append(
                    {
                        "id": review_id,
                        "state": str(attributes.get("state") or state),
                        "items": self.review_items(review_id),
                    }
                )
        return found

    def review_items(self, review_id: str) -> list[dict]:
        items, _included = self.collect(
            self.token,
            f"/v1/reviewSubmissions/{review_id}/items",
            {"limit": "50"},
        )
        return [parse_review_item(item) for item in items]

    def cancel_review(self, review_id: str) -> None:
        body = _resource(
            "reviewSubmissions",
            review_id,
            {"canceled": True},
            None,
            frozenset({"canceled"}),
            frozenset(),
        )
        self.request(
            self.token,
            f"/v1/reviewSubmissions/{review_id}",
            method="PATCH",
            body=body,
        )

    def create_review(self, app_identifier: str) -> dict:
        body = _resource(
            "reviewSubmissions",
            None,
            {"platform": PLATFORM},
            {"app": {"data": {"type": "apps", "id": app_identifier}}},
            frozenset({"platform"}),
            frozenset({"app"}),
        )
        payload = self.request(self.token, "/v1/reviewSubmissions", method="POST", body=body)
        data = payload.get("data") or {}
        review_id = data.get("id")
        if not review_id:
            raise RuntimeError("App Store Connect did not return a review submission id")
        return {
            "id": str(review_id),
            "state": str((data.get("attributes") or {}).get("state") or "READY_FOR_REVIEW"),
            "items": [],
        }

    def add_version_item(self, review_id: str, version_id: str) -> None:
        body = _resource(
            "reviewSubmissionItems",
            None,
            None,
            {
                "reviewSubmission": {
                    "data": {"type": "reviewSubmissions", "id": review_id}
                },
                "appStoreVersion": {
                    "data": {"type": "appStoreVersions", "id": version_id}
                },
            },
            frozenset(),
            frozenset({"reviewSubmission", "appStoreVersion"}),
        )
        try:
            self.request(self.token, "/v1/reviewSubmissionItems", method="POST", body=body)
        except asc.ASCHTTPError as exc:
            if exc.code != 409:
                raise
            if any(
                _item_is_this_version(item, version_id) for item in self.review_items(review_id)
            ):
                print(
                    f"app store: version {version_id} is already on review submission {review_id}",
                    flush=True,
                )
                return
            raise RuntimeError(
                f"version {version_id} was not added to review submission {review_id}. "
                f"It may already be attached to a different submission. {exc}"
            ) from exc

    def submit_review(self, review_id: str) -> None:
        body = _resource(
            "reviewSubmissions",
            review_id,
            {"submitted": True},
            None,
            frozenset({"submitted"}),
            frozenset(),
        )
        self.request(
            self.token,
            f"/v1/reviewSubmissions/{review_id}",
            method="PATCH",
            body=body,
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="marketing version, for example 1.0.1")
    parser.add_argument("--build", type=int, help="build number already uploaded")
    parser.add_argument(
        "--from-project",
        action="store_true",
        help="use MARKETING_VERSION and CURRENT_PROJECT_VERSION from the Xcode project",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="read App Store Connect and print the plan; do not change or submit anything",
    )
    parser.add_argument(
        "--check-notes",
        action="store_true",
        help="check the release notes and project version locally; do not contact App Store Connect",
    )
    args = parser.parse_args(argv)
    try:
        version, number = resolve_target(args.version, args.build, args.from_project)
        notes = load_release_notes(version)
    except RuntimeError as exc:
        sys.stderr.write(f"{exc}\n")
        return 1
    if args.check_notes:
        print(f"release notes {version} build {number}: {len(notes)} characters")
        print(notes)
        return 0
    if args.dry_run:
        print("dry-run: reading App Store Connect only; nothing will be submitted", flush=True)
    try:
        submit_release(
            StoreClient.from_environment(),
            version,
            number,
            notes,
            mutate=not args.dry_run,
        )
    except RuntimeError as exc:
        sys.stderr.write(f"App Store submit failed: {exc}\n")
        sys.stderr.flush()
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
