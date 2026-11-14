#!/usr/bin/env python3
"""Unit tests for App Store submission. No App Store Connect calls."""

from __future__ import annotations

import io
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import app_store_connect as asc
import submit_app_store as submit

EXACT_101 = (
    "Predictions now use UK spellings. If Fix can't reach the correction service, "
    "or can't count a Fix, it tells you and your typing stays as it is. "
    "VoiceOver and Switch Control can now activate each key."
)
NOTES = EXACT_101


def version_row(
    *,
    state: str = "PREPARE_FOR_SUBMISSION",
    release_type: str | None = "MANUAL",
    build_id: str | None = None,
    version_id: str = "ver-1",
) -> dict:
    return {
        "id": version_id,
        "version_string": "1.0.1",
        "platform": "IOS",
        "state": state,
        "release_type": release_type,
        "build_id": build_id,
    }


def ready_build(build_id: str = "build-23", marketing: str = "1.0.1") -> dict:
    return {
        "id": build_id,
        "number": 23,
        "marketing_version": marketing,
        "platform": "IOS",
        "expired": False,
        "processing_state": "VALID",
        "internal_build_state": "IN_BETA_TESTING",
        "installable": True,
    }


def localization(text: str, locale: str = "en-GB", localization_id: str = "loc-gb") -> dict:
    return {"id": localization_id, "locale": locale, "whats_new": text}


def review(review_id: str, state: str, items: list[dict]) -> dict:
    return {"id": review_id, "state": state, "items": items}


def version_item(version_id: str = "ver-1", item_id: str = "item-1") -> dict:
    return {
        "id": item_id,
        "links": [
            {
                "relationship": "appStoreVersion",
                "type": "appStoreVersions",
                "id": version_id,
            }
        ],
    }


def other_item() -> dict:
    return {
        "id": "item-event",
        "links": [
            {"relationship": "appEvent", "type": "appEvents", "id": "event-1"}
        ],
    }


class FakeStore:
    def __init__(self):
        self.calls: list[tuple] = []
        self.app = "app-1"
        self.build = ready_build()
        self.version = None
        self.rows = [localization("old notes")]
        self.reviews: list[dict] = []

    def names(self) -> list[str]:
        return [call[0] for call in self.calls]

    def app_id(self) -> str:
        self.calls.append(("app_id",))
        return self.app

    def wait_installable(self, app_identifier: str, number: int) -> None:
        self.calls.append(("wait_installable", app_identifier, number))

    def fetch_build(self, app_identifier: str, number: int):
        self.calls.append(("fetch_build", app_identifier, number))
        return self.build

    def find_version(self, app_identifier: str, version: str):
        self.calls.append(("find_version", app_identifier, version))
        return self.version

    def create_version(self, app_identifier: str, version: str) -> dict:
        self.calls.append(("create_version", app_identifier, version))
        self.version = version_row(release_type="AFTER_APPROVAL")
        return self.version

    def set_release_type(self, version_id: str) -> None:
        self.calls.append(("set_release_type", version_id))

    def attach_build(self, version_id: str, build_id: str) -> None:
        self.calls.append(("attach_build", version_id, build_id))

    def localizations(self, version_id: str) -> list[dict]:
        self.calls.append(("localizations", version_id))
        return list(self.rows)

    def set_whats_new(self, localization_id: str, text: str) -> None:
        self.calls.append(("set_whats_new", localization_id, text))

    def open_reviews(self, app_identifier: str) -> list[dict]:
        self.calls.append(("open_reviews", app_identifier))
        return list(self.reviews)

    def cancel_review(self, review_id: str) -> None:
        self.calls.append(("cancel_review", review_id))

    def create_review(self, app_identifier: str) -> dict:
        self.calls.append(("create_review", app_identifier))
        return {"id": "rev-new", "state": "READY_FOR_REVIEW", "items": []}

    def add_version_item(self, review_id: str, version_id: str) -> None:
        self.calls.append(("add_version_item", review_id, version_id))

    def submit_review(self, review_id: str) -> None:
        self.calls.append(("submit_review", review_id))


class ReleaseNotesTests(unittest.TestCase):
    def test_101_file_is_the_agreed_text(self) -> None:
        path = submit.release_notes_path("1.0.1")
        self.assertEqual(path.read_text(encoding="utf-8"), EXACT_101 + "\n")
        self.assertEqual(submit.load_release_notes("1.0.1"), EXACT_101)

    def test_current_marketing_version_has_release_notes(self) -> None:
        marketing, _number = submit.project_versions()
        self.assertTrue(submit.load_release_notes(marketing))

    def test_check_notes_does_not_contact_app_store_connect(self) -> None:
        marketing, number = submit.project_versions()

        def boom(*_args, **_kwargs):
            raise AssertionError("App Store Connect was contacted")

        original = asc.credentials
        asc.credentials = boom
        try:
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                code = submit.main(["--check-notes", "--version", marketing, "--build", number])
        finally:
            asc.credentials = original
        self.assertEqual(code, 0)
        self.assertIn(submit.load_release_notes(marketing), stdout.getvalue())

    def test_refuses_a_version_the_project_is_not(self) -> None:
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            code = submit.main(["--check-notes", "--version", "9.9.9", "--build", "1"])
        self.assertEqual(code, 1)
        self.assertIn("MARKETING_VERSION", stderr.getvalue())

    def test_rejects_path_like_versions_and_empty_notes(self) -> None:
        for bad in ("../1.0.1", "1.0.1/../../etc", "v1.0.1", "1.0.1.txt", ""):
            with self.assertRaises(RuntimeError):
                submit.release_notes_path(bad)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            notes = root / "release-notes"
            notes.mkdir()
            (notes / "1.2.3.txt").write_text("  \n", encoding="utf-8")
            with self.assertRaises(RuntimeError) as caught:
                submit.load_release_notes("1.2.3", root)
            self.assertIn("empty", str(caught.exception))
            (notes / "1.2.4.txt").write_text("x" * 4001, encoding="utf-8")
            with self.assertRaises(RuntimeError) as caught:
                submit.load_release_notes("1.2.4", root)
            self.assertIn("4000", str(caught.exception))
            with self.assertRaises(RuntimeError) as caught:
                submit.load_release_notes("9.9.9", root)
            self.assertIn("missing What's New", str(caught.exception))

    def test_resolve_target_uses_the_xcode_project(self) -> None:
        marketing, number = submit.project_versions()
        self.assertEqual(submit.resolve_target(None, None, True), (marketing, int(number)))
        self.assertEqual(
            submit.resolve_target(marketing, int(number), False),
            (marketing, int(number)),
        )
        with self.assertRaises(RuntimeError):
            submit.resolve_target(marketing, int(number) + 1, False)
        with self.assertRaises(RuntimeError):
            submit.resolve_target(marketing, int(number), True)


class SubmissionFlowTests(unittest.TestCase):
    def submit(self, store: FakeStore, *, mutate: bool = True, notes: str = NOTES):
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            submit.submit_release(store, "1.0.1", 23, notes, mutate)
        return stdout.getvalue()

    def test_creates_version_attaches_build_sets_exact_notes_and_submits(self) -> None:
        store = FakeStore()
        output = self.submit(store)
        self.assertEqual(
            store.names(),
            [
                "app_id",
                "wait_installable",
                "fetch_build",
                "find_version",
                "open_reviews",
                "create_version",
                "attach_build",
                "localizations",
                "set_whats_new",
                "create_review",
                "add_version_item",
                "submit_review",
            ],
        )
        self.assertEqual(store.calls[store.names().index("set_whats_new")][2], EXACT_101)
        self.assertEqual(store.calls[store.names().index("attach_build")][2], "build-23")
        self.assertIn("submitted version 1.0.1 for App Review", output)
        self.assertIn("automatically after approval", output)

    def test_reuses_editable_version_and_skips_unchanged_fields(self) -> None:
        store = FakeStore()
        store.version = version_row(
            release_type="AFTER_APPROVAL", build_id="build-23"
        )
        store.rows = [localization(EXACT_101), localization("untouched", "en-US", "loc-us")]
        output = self.submit(store)
        self.assertNotIn("create_version", store.names())
        self.assertNotIn("attach_build", store.names())
        self.assertNotIn("set_whats_new", store.names())
        self.assertNotIn("set_release_type", store.names())
        self.assertIn("submit_review", store.names())
        self.assertIn("already attached", output)
        self.assertIn("already matches", output)
        self.assertNotIn("loc-us", [call[1] for call in store.calls if call[0] == "set_whats_new"])

    def test_updates_manual_release_type_and_replaces_the_build(self) -> None:
        store = FakeStore()
        store.version = version_row(release_type="MANUAL", build_id="build-22")
        self.submit(store)
        self.assertIn(("attach_build", "ver-1", "build-23"), store.calls)
        self.assertIn(("set_release_type", "ver-1"), store.calls)
        self.assertIn(("set_whats_new", "loc-gb", EXACT_101), store.calls)

    def test_already_in_review_with_the_same_build_and_notes_does_not_submit_again(self) -> None:
        store = FakeStore()
        store.version = version_row(
            state="WAITING_FOR_REVIEW",
            release_type="AFTER_APPROVAL",
            build_id="build-23",
        )
        store.rows = [localization(EXACT_101)]
        store.reviews = [review("rev-live", "WAITING_FOR_REVIEW", [version_item()])]
        output = self.submit(store)
        for forbidden in (
            "attach_build",
            "set_whats_new",
            "set_release_type",
            "create_review",
            "submit_review",
            "cancel_review",
        ):
            self.assertNotIn(forbidden, store.names())
        self.assertIn("already WAITING_FOR_REVIEW", output)

    def test_in_review_with_a_different_build_fails_before_editing(self) -> None:
        store = FakeStore()
        store.version = version_row(state="IN_REVIEW", build_id="build-22")
        store.reviews = [review("rev-live", "IN_REVIEW", [version_item()])]
        with self.assertRaises(RuntimeError) as caught:
            self.submit(store)
        self.assertIn("not build 23", str(caught.exception))
        self.assertNotIn("set_whats_new", store.names())
        self.assertNotIn("attach_build", store.names())
        self.assertNotIn("submit_review", store.names())

    def test_in_review_with_different_notes_fails_without_patching(self) -> None:
        store = FakeStore()
        store.version = version_row(
            state="IN_REVIEW", release_type="AFTER_APPROVAL", build_id="build-23"
        )
        store.rows = [localization("previous What's New")]
        with self.assertRaises(RuntimeError) as caught:
            self.submit(store)
        self.assertIn("does not match", str(caught.exception))
        self.assertNotIn("set_whats_new", store.names())

    def test_pending_developer_release_tries_to_set_automatic_and_does_not_release(self) -> None:
        store = FakeStore()
        store.version = version_row(
            state="PENDING_DEVELOPER_RELEASE",
            release_type="MANUAL",
            build_id="build-23",
        )
        store.rows = [localization(EXACT_101)]
        self.submit(store)
        self.assertIn(("set_release_type", "ver-1"), store.calls)
        self.assertNotIn("submit_review", store.names())

    def test_ready_for_sale_leaves_a_manual_release_type_alone(self) -> None:
        store = FakeStore()
        store.version = version_row(
            state="READY_FOR_SALE", release_type="MANUAL", build_id="build-23"
        )
        store.rows = [localization(EXACT_101)]
        output = self.submit(store)
        self.assertNotIn("set_release_type", store.names())
        self.assertNotIn("submit_review", store.names())
        self.assertIn("leaving the release type", output)

    def test_refuses_a_draft_that_contains_other_items(self) -> None:
        store = FakeStore()
        store.version = version_row()
        store.reviews = [review("draft-1", "READY_FOR_REVIEW", [version_item(), other_item()])]
        with self.assertRaises(RuntimeError) as caught:
            self.submit(store)
        self.assertIn("other than version 1.0.1", str(caught.exception))
        self.assertIn("appEvent=event-1", str(caught.exception))
        for forbidden in ("attach_build", "set_whats_new", "submit_review", "create_review"):
            self.assertNotIn(forbidden, store.names())

    def test_refuses_to_submit_while_another_version_is_in_review(self) -> None:
        store = FakeStore()
        store.version = None
        store.reviews = [review("rev-other", "IN_REVIEW", [version_item("ver-other", "item-other")])]
        with self.assertRaises(RuntimeError) as caught:
            self.submit(store)
        self.assertIn("rev-other", str(caught.exception))
        self.assertNotIn("create_version", store.names())

    def test_resubmits_after_an_unresolved_submission_that_is_only_this_version(self) -> None:
        store = FakeStore()
        store.version = version_row(state="REJECTED", release_type="AFTER_APPROVAL")
        store.reviews = [review("rev-old", "UNRESOLVED_ISSUES", [version_item()])]
        self.submit(store)
        self.assertIn(("cancel_review", "rev-old"), store.calls)
        self.assertIn(("create_review", "app-1"), store.calls)
        self.assertIn(("submit_review", "rev-new"), store.calls)
        self.assertNotIn(("submit_review", "rev-old"), store.calls)

    def test_submits_an_existing_draft_that_already_contains_only_this_version(self) -> None:
        store = FakeStore()
        store.version = version_row(release_type="AFTER_APPROVAL", build_id="build-23")
        store.rows = [localization(EXACT_101)]
        store.reviews = [review("draft-1", "READY_FOR_REVIEW", [version_item()])]
        self.submit(store)
        self.assertNotIn("create_review", store.names())
        self.assertNotIn("add_version_item", store.names())
        self.assertIn(("submit_review", "draft-1"), store.calls)

    def test_missing_en_gb_localization_fails_before_submit(self) -> None:
        store = FakeStore()
        store.version = version_row(release_type="AFTER_APPROVAL")
        store.rows = [localization("other", "en-US", "loc-us")]
        with self.assertRaises(RuntimeError) as caught:
            self.submit(store)
        self.assertIn("no en-GB localization", str(caught.exception))
        self.assertNotIn("submit_review", store.names())
        self.assertNotIn("set_whats_new", store.names())

    def test_wrong_marketing_version_on_the_build_fails_before_any_edit(self) -> None:
        store = FakeStore()
        store.build = ready_build(marketing="1.0")
        with self.assertRaises(RuntimeError) as caught:
            self.submit(store)
        self.assertIn("marketing version 1.0", str(caught.exception))
        self.assertNotIn("find_version", store.names())
        self.assertNotIn("create_version", store.names())

    def test_missing_pre_release_version_fails(self) -> None:
        store = FakeStore()
        store.build = ready_build(marketing="")
        with self.assertRaises(RuntimeError) as caught:
            self.submit(store)
        self.assertIn("preReleaseVersion", str(caught.exception))

    def test_dry_run_prints_the_plan_and_makes_no_changes(self) -> None:
        store = FakeStore()
        store.version = version_row(release_type="MANUAL", build_id=None)
        output = self.submit(store, mutate=False)
        for forbidden in (
            "wait_installable",
            "create_version",
            "attach_build",
            "set_whats_new",
            "set_release_type",
            "create_review",
            "add_version_item",
            "submit_review",
            "cancel_review",
        ):
            self.assertNotIn(forbidden, store.names())
        self.assertIn("dry-run: would attach build 23", output)
        self.assertIn("dry-run: would set en-GB What's New", output)
        self.assertIn("dry-run: would set release type AFTER_APPROVAL", output)
        self.assertIn("dry-run: would create a review submission containing only version 1.0.1", output)
        self.assertIn("finished without changing App Store Connect", output)

    def test_new_version_waits_for_apple_to_copy_localizations(self) -> None:
        store = FakeStore()
        store.rows = []
        attempts = {"n": 0}

        def localizations(version_id: str) -> list[dict]:
            attempts["n"] += 1
            store.calls.append(("localizations", version_id))
            if attempts["n"] == 1:
                return []
            return [localization("old notes")]

        store.localizations = localizations
        slept: list[int] = []
        original = submit.time.sleep
        submit.time.sleep = slept.append
        try:
            self.submit(store)
        finally:
            submit.time.sleep = original
        self.assertEqual(slept, [2])
        self.assertEqual(attempts["n"], 2)
        self.assertIn(("set_whats_new", "loc-gb", EXACT_101), store.calls)

    def test_dry_run_of_a_new_version_does_not_create_it(self) -> None:
        store = FakeStore()
        output = self.submit(store, mutate=False)
        self.assertNotIn("create_version", store.names())
        self.assertIn("would create the App Store version", output)

    def test_dry_run_reports_a_build_that_is_still_processing(self) -> None:
        store = FakeStore()
        store.build = ready_build()
        store.build["installable"] = False
        store.build["processing_state"] = "PROCESSING"
        with self.assertRaises(RuntimeError) as caught:
            self.submit(store, mutate=False)
        self.assertIn("not ready", str(caught.exception))
        self.assertIn("real run waits", str(caught.exception))

    def test_replaced_version_is_refused(self) -> None:
        store = FakeStore()
        store.version = version_row(state="REPLACED_WITH_NEW_VERSION", build_id="build-23")
        with self.assertRaises(RuntimeError) as caught:
            self.submit(store)
        self.assertIn("will not resubmit", str(caught.exception))
        self.assertNotIn("submit_review", store.names())


class ParserTests(unittest.TestCase):
    def test_version_state_prefers_app_version_state(self) -> None:
        self.assertEqual(
            submit.version_state(
                {"appVersionState": "PREPARE_FOR_SUBMISSION", "appStoreState": "READY_FOR_SALE"}
            ),
            "PREPARE_FOR_SUBMISSION",
        )
        self.assertEqual(submit.version_state({"appStoreState": "READY_FOR_SALE"}), "READY_FOR_SALE")

    def test_parse_store_build_reads_pre_release_version(self) -> None:
        item = {
            "id": "build-23",
            "attributes": {
                "version": "23",
                "expired": False,
                "processingState": "VALID",
                "usesNonExemptEncryption": False,
            },
            "relationships": {
                "preReleaseVersion": {"data": {"type": "preReleaseVersions", "id": "pre-1"}},
                "buildBetaDetail": {"data": {"type": "buildBetaDetails", "id": "detail-1"}},
            },
        }
        included = [
            {
                "type": "preReleaseVersions",
                "id": "pre-1",
                "attributes": {"version": "1.0.1", "platform": "IOS"},
            },
            {
                "type": "buildBetaDetails",
                "id": "detail-1",
                "attributes": {"internalBuildState": "IN_BETA_TESTING"},
            },
        ]
        parsed = submit.parse_store_build(item, included)
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed["number"], 23)
        self.assertEqual(parsed["marketing_version"], "1.0.1")
        self.assertEqual(parsed["platform"], "IOS")
        self.assertTrue(parsed["installable"])
        self.assertEqual(parsed["internal_build_state"], "IN_BETA_TESTING")

    def test_review_item_keeps_only_linked_resources(self) -> None:
        parsed = submit.parse_review_item(
            {
                "id": "item-1",
                "relationships": {
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": "ver-1"}
                    },
                    "appCustomProductPageVersion": {"data": None},
                },
            }
        )
        self.assertEqual(
            parsed["links"],
            [{"relationship": "appStoreVersion", "type": "appStoreVersions", "id": "ver-1"}],
        )

    def test_resource_guard_rejects_other_listing_fields(self) -> None:
        with self.assertRaises(RuntimeError) as caught:
            submit._resource(
                "appStoreVersionLocalizations",
                "loc-1",
                {"whatsNew": "notes", "description": "changed", "keywords": "changed"},
                None,
                frozenset({"whatsNew"}),
                frozenset(),
            )
        self.assertIn("description", str(caught.exception))
        self.assertIn("keywords", str(caught.exception))


class HTTPBodyTests(unittest.TestCase):
    def client(self, request, collect=None):
        if collect is None:
            collect = lambda *_args, **_kwargs: ([], [])
        return submit.StoreClient(request, collect, token="token")

    def test_create_version_sends_only_platform_version_and_release_type(self) -> None:
        seen = {}

        def request(_token, path, params=None, method="GET", body=None):
            if method == "POST":
                seen["path"] = path
                seen["body"] = body
                return {
                    "data": {
                        "id": "ver-1",
                        "attributes": {
                            "versionString": "1.0.1",
                            "platform": "IOS",
                            "releaseType": "AFTER_APPROVAL",
                            "appVersionState": "PREPARE_FOR_SUBMISSION",
                        },
                    }
                }
            self.assertEqual(path, "/v1/appStoreVersions/ver-1/relationships/build")
            return {"data": None}

        client = self.client(request)
        created = client.create_version("app-1", "1.0.1")
        self.assertEqual(seen["path"], "/v1/appStoreVersions")
        self.assertEqual(
            seen["body"],
            {
                "data": {
                    "type": "appStoreVersions",
                    "attributes": {
                        "platform": "IOS",
                        "versionString": "1.0.1",
                        "releaseType": "AFTER_APPROVAL",
                    },
                    "relationships": {"app": {"data": {"type": "apps", "id": "app-1"}}},
                }
            },
        )
        self.assertEqual(created["id"], "ver-1")
        self.assertIsNone(created["build_id"])

    def test_create_version_409_reuses_the_existing_version(self) -> None:
        def request(_token, path, params=None, method="GET", body=None):
            if method == "POST":
                raise asc.ASCHTTPError(409, path, "duplicate version")
            self.assertEqual(path, "/v1/appStoreVersions/ver-9/relationships/build")
            return {"data": {"type": "builds", "id": "build-23"}}

        def collect(_token, path, params=None):
            self.assertEqual(path, "/v1/apps/app-1/appStoreVersions")
            self.assertEqual(params["filter[versionString]"], "1.0.1")
            return (
                [
                    {
                        "id": "ver-9",
                        "attributes": {
                            "versionString": "1.0.1",
                            "platform": "IOS",
                            "appVersionState": "PREPARE_FOR_SUBMISSION",
                            "releaseType": "MANUAL",
                        },
                    }
                ],
                [],
            )

        created = self.client(request, collect).create_version("app-1", "1.0.1")
        self.assertEqual(created["id"], "ver-9")
        self.assertEqual(created["build_id"], "build-23")

    def test_whats_new_patch_sends_only_that_field(self) -> None:
        seen = {}

        def request(_token, path, params=None, method="GET", body=None):
            seen["method"] = method
            seen["path"] = path
            seen["body"] = body
            return {}

        self.client(request).set_whats_new("loc-gb", EXACT_101)
        self.assertEqual(seen["method"], "PATCH")
        self.assertEqual(seen["path"], "/v1/appStoreVersionLocalizations/loc-gb")
        self.assertEqual(
            seen["body"]["data"]["attributes"],
            {"whatsNew": EXACT_101},
        )
        self.assertNotIn("relationships", seen["body"]["data"])

    def test_attach_and_release_type_are_separate_requests(self) -> None:
        seen = []

        def request(_token, path, params=None, method="GET", body=None):
            seen.append((method, path, body))
            return {}

        client = self.client(request)
        client.attach_build("ver-1", "build-23")
        client.set_release_type("ver-1")
        self.assertEqual(
            seen[0],
            (
                "PATCH",
                "/v1/appStoreVersions/ver-1/relationships/build",
                {"data": {"type": "builds", "id": "build-23"}},
            ),
        )
        self.assertEqual(set(seen[1][2]["data"]["attributes"]), {"releaseType"})
        self.assertEqual(seen[1][2]["data"]["attributes"]["releaseType"], "AFTER_APPROVAL")
        self.assertNotIn("relationships", seen[1][2]["data"])

    def test_review_submission_contains_only_this_version_and_submits(self) -> None:
        seen = []

        def request(_token, path, params=None, method="GET", body=None):
            seen.append((method, path, body))
            if path == "/v1/reviewSubmissions" and method == "POST":
                return {"data": {"id": "rev-1", "attributes": {"state": "READY_FOR_REVIEW"}}}
            return {}

        client = self.client(request)
        created = client.create_review("app-1")
        client.add_version_item(created["id"], "ver-1")
        client.submit_review(created["id"])
        self.assertEqual(seen[0][2]["data"]["attributes"], {"platform": "IOS"})
        self.assertEqual(set(seen[0][2]["data"]["relationships"]), {"app"})
        self.assertEqual(seen[1][0], "POST")
        self.assertEqual(seen[1][1], "/v1/reviewSubmissionItems")
        self.assertEqual(
            set(seen[1][2]["data"]["relationships"]),
            {"reviewSubmission", "appStoreVersion"},
        )
        self.assertNotIn("attributes", seen[1][2]["data"])
        self.assertEqual(seen[2][2]["data"]["attributes"], {"submitted": True})

    def test_fetch_build_lists_again_without_include_when_apple_rejects_it(self) -> None:
        def collect(_token, path, params=None):
            self.assertEqual(path, "/v1/builds")
            if "include" in (params or {}):
                raise asc.ASCHTTPError(400, path, "invalid include")
            return (
                [
                    {
                        "id": "build-23",
                        "attributes": {
                            "version": "23",
                            "expired": False,
                            "processingState": "VALID",
                            "usesNonExemptEncryption": False,
                        },
                    }
                ],
                [],
            )

        def request(_token, path, params=None, method="GET", body=None):
            self.assertEqual(path, "/v1/builds/build-23/preReleaseVersion")
            return {"data": {"attributes": {"version": "1.0.1", "platform": "IOS"}}}

        fetched = self.client(request, collect).fetch_build("app-1", 23)
        self.assertIsNotNone(fetched)
        assert fetched is not None
        self.assertEqual(fetched["marketing_version"], "1.0.1")
        self.assertTrue(fetched["installable"])

    def test_fetch_build_reads_pre_release_when_include_omits_it(self) -> None:
        def collect(_token, path, params=None):
            return (
                [
                    {
                        "id": "build-23",
                        "attributes": {
                            "version": "23",
                            "expired": False,
                            "processingState": "VALID",
                            "usesNonExemptEncryption": False,
                        },
                        "relationships": {},
                    }
                ],
                [],
            )

        def request(_token, path, params=None, method="GET", body=None):
            self.assertEqual(path, "/v1/builds/build-23/preReleaseVersion")
            return {"data": {"attributes": {"version": "1.0.1", "platform": "IOS"}}}

        fetched = self.client(request, collect).fetch_build("app-1", 23)
        self.assertIsNotNone(fetched)
        assert fetched is not None
        self.assertEqual(fetched["marketing_version"], "1.0.1")

    def test_add_item_409_on_a_different_submission_fails(self) -> None:
        def request(_token, path, params=None, method="GET", body=None):
            raise asc.ASCHTTPError(409, path, "already exists on another submission")

        def collect(_token, path, params=None):
            return ([], [])

        with self.assertRaises(RuntimeError) as caught:
            self.client(request, collect).add_version_item("rev-1", "ver-1")
        self.assertIn("different submission", str(caught.exception))


class WorkflowContractTests(unittest.TestCase):
    def test_release_tag_is_separate_from_testflight(self) -> None:
        root = submit.ROOT
        testflight = (root / ".github/workflows/testflight.yml").read_text(encoding="utf-8")
        app_store = (root / ".github/workflows/app-store.yml").read_text(encoding="utf-8")
        releasing = (root / "RELEASING.md").read_text(encoding="utf-8")
        self.assertIn('"testflight-*"', testflight)
        self.assertNotIn("release-", testflight)
        self.assertNotIn("submit_app_store", testflight)
        self.assertIn('"release-*"', app_store)
        self.assertIn("workflow_dispatch:", app_store)
        self.assertIn("submit_app_store.py", app_store)
        self.assertIn("--from-project", app_store)
        self.assertIn("--dry-run", app_store)
        self.assertIn("1.0.1", releasing)
        self.assertIn("23", releasing)
        self.assertNotIn("6803257519", (root / "scripts/submit_app_store.py").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
