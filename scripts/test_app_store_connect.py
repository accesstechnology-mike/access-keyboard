#!/usr/bin/env python3
"""Unit tests for TestFlight latest-only selection. No App Store Connect calls."""

from __future__ import annotations

import unittest

import app_store_connect as asc


def build(
    number: int,
    *,
    expired: bool = False,
    processing_state: str = "VALID",
    identifier: str | None = None,
) -> dict:
    return {
        "id": identifier or f"build-{number}",
        "number": number,
        "expired": expired,
        "processing_state": processing_state,
        "uses_non_exempt_encryption": False,
    }


class LatestOnlyTests(unittest.TestCase):
    def test_parse_build_reads_apple_version_as_build_number(self) -> None:
        parsed = asc.parse_build(
            {
                "id": "abc",
                "attributes": {
                    "version": "6",
                    "expired": False,
                    "processingState": "VALID",
                    "usesNonExemptEncryption": False,
                },
            }
        )
        self.assertEqual(
            parsed,
            {
                "id": "abc",
                "number": 6,
                "expired": False,
                "processing_state": "VALID",
                "uses_non_exempt_encryption": False,
                "internal_build_state": None,
            },
        )

    def test_parse_build_skips_non_numeric_versions(self) -> None:
        self.assertIsNone(
            asc.parse_build({"id": "x", "attributes": {"version": "0.1.0"}})
        )

    def test_latest_valid_build_is_highest_unexpired_valid(self) -> None:
        latest = asc.latest_valid_build(
            [
                build(1),
                build(6),
                build(5, expired=True),
                build(7, processing_state="PROCESSING"),
                build(4, processing_state="FAILED"),
            ]
        )
        self.assertIsNotNone(latest)
        self.assertEqual(latest["number"], 6)

    def test_latest_valid_build_none_when_nothing_installable(self) -> None:
        self.assertIsNone(
            asc.latest_valid_build(
                [
                    build(1, expired=True),
                    build(2, processing_state="PROCESSING"),
                ]
            )
        )

    def test_expire_every_older_valid_build_and_leave_latest(self) -> None:
        latest = build(6)
        to_expire = asc.builds_to_expire(
            [
                build(1),
                build(2, expired=True),
                latest,
                build(5),
                build(4, processing_state="PROCESSING"),
            ],
            latest,
        )
        self.assertEqual([item["number"] for item in to_expire], [1, 5])

    def test_internal_group_without_all_builds_is_the_dev_account_trap(self) -> None:
        self.assertTrue(
            asc.group_needs_all_builds(
                {
                    "id": "internal",
                    "name": "Access Technology",
                    "is_internal": True,
                    "has_access_to_all_builds": False,
                }
            )
        )
        self.assertFalse(
            asc.group_needs_all_builds(
                {
                    "id": "internal-open",
                    "name": "Access Technology",
                    "is_internal": True,
                    "has_access_to_all_builds": True,
                }
            )
        )
        self.assertFalse(
            asc.group_needs_all_builds(
                {
                    "id": "external",
                    "name": "External Testers",
                    "is_internal": False,
                    "has_access_to_all_builds": None,
                }
            )
        )

    def test_conflict_is_ignored_for_existing_relationships(self) -> None:
        already = asc.ASCHTTPError(
            409,
            "/v1/betaGroups/1/relationships/builds",
            '{"errors":[{"detail":"The specified resource already exists."}]}',
        )
        other_409 = asc.ASCHTTPError(409, "/v1/builds/1", '{"errors":[{"detail":"Nope."}]}')
        real_error = asc.ASCHTTPError(
            422,
            "/v1/betaGroups/1/relationships/builds",
            '{"errors":[{"detail":"The build is not available for external testing."}]}',
        )
        self.assertTrue(asc.ignore_already_exists(already))
        self.assertTrue(asc.ignore_already_exists(other_409))
        self.assertFalse(asc.ignore_already_exists(real_error))

    def test_internal_auto_distribute_group_cannot_be_assigned_a_build(self) -> None:
        alpha = asc.ASCHTTPError(
            422,
            "/v1/betaGroups/1d669790-f55d-4154-804b-239ee314f1de/relationships/builds",
            '{"errors":[{"title":"Builds cannot be assigned to this internal group.",'
            '"detail":"Cannot add internal group to a build."}]}',
        )
        external = asc.ASCHTTPError(
            422,
            "/v1/betaGroups/ext/relationships/builds",
            '{"errors":[{"detail":"The build is not available for external testing."}]}',
        )
        self.assertTrue(asc.internal_group_rejects_assign(alpha))
        self.assertFalse(asc.internal_group_rejects_assign(external))
        self.assertFalse(asc.ignore_already_exists(alpha))

    def test_valid_without_beta_detail_is_installable(self) -> None:
        processing = build(7)
        processing["internal_build_state"] = "PROCESSING"
        ready = build(7, identifier="ready")
        ready["internal_build_state"] = "READY_FOR_BETA_TESTING"
        missing = build(9, identifier="missing")
        missing["internal_build_state"] = None
        self.assertFalse(asc.is_installable(processing))
        self.assertTrue(asc.is_installable(ready))
        self.assertTrue(asc.is_installable(missing))
        self.assertEqual(
            asc.latest_installable_build([processing, ready, missing])["id"],
            "missing",
        )

    def test_asc_token_must_refresh_before_apple_20_minute_cap(self) -> None:
        issued = 1_000_000
        expires = issued + asc.TOKEN_LIFETIME_S
        self.assertFalse(asc.token_needs_refresh(issued + 10 * 60, expires))
        self.assertTrue(asc.token_needs_refresh(issued + 16 * 60, expires))
        self.assertTrue(asc.token_needs_refresh(expires, expires))

    def test_revoked_testers_are_the_ones_who_see_no_builds(self) -> None:
        testers = [
            {"id": "1", "email": "ok@example.com", "state": "INSTALLED"},
            {"id": "2", "email": "gone@example.com", "state": "REVOKED"},
            {"id": "3", "email": "", "state": "REVOKED"},
            {"id": "4", "email": "pending@example.com", "state": "NOT_INVITED"},
            {"id": "5", "email": "invited@example.com", "state": "INVITED"},
            {"id": "6", "email": "accepted@example.com", "state": "ACCEPTED"},
        ]
        blocked = asc.testers_needing_reinvite(testers)
        self.assertEqual(
            [item["email"] for item in blocked],
            ["gone@example.com", "pending@example.com"],
        )
        self.assertEqual(
            [item["email"] for item in asc.revoked_testers(testers)],
            ["gone@example.com", "pending@example.com"],
        )

    def test_team_user_email_comes_from_username(self) -> None:
        self.assertEqual(
            asc.parse_user_email(
                {"attributes": {"username": "tester@example.com", "roles": ["ADMIN"]}}
            ),
            "tester@example.com",
        )
        self.assertEqual(asc.parse_user_email({"attributes": {}}), "")

    def test_missing_tester_and_cannot_assign_are_detected(self) -> None:
        missing = asc.ASCHTTPError(
            404,
            "/v1/betaTesters/ghost",
            '{"errors":[{"detail":"There is no resource of type \'betaTesters\'"}]}',
        )
        blocked = asc.ASCHTTPError(
            409,
            "/v1/betaTesters",
            '{"errors":[{"detail":"Tester(s) cannot be assigned"}]}',
        )
        other = asc.ASCHTTPError(409, "/v1/betaTesters", '{"errors":[{"detail":"Nope."}]}')
        self.assertTrue(asc.tester_is_missing(missing))
        self.assertTrue(asc.tester_cannot_be_assigned(blocked))
        self.assertFalse(asc.tester_cannot_be_assigned(other))
        self.assertFalse(asc.tester_is_missing(blocked))

    def test_create_tester_sends_only_groups_or_only_builds(self) -> None:
        groups = asc.tester_create_relationships(["alpha", "beta"], "build-11")
        self.assertEqual(list(groups), ["betaGroups"])
        self.assertEqual(
            groups["betaGroups"]["data"],
            [
                {"type": "betaGroups", "id": "alpha"},
                {"type": "betaGroups", "id": "beta"},
            ],
        )
        builds = asc.tester_create_relationships([], "build-11")
        self.assertEqual(list(builds), ["builds"])
        self.assertEqual(
            builds["builds"]["data"],
            [{"type": "builds", "id": "build-11"}],
        )
        with self.assertRaises(RuntimeError):
            asc.tester_create_relationships([], "")

    def test_expired_first_invite_is_not_installable(self) -> None:
        first = build(1, expired=True)
        first["internal_build_state"] = "EXPIRED"
        self.assertFalse(asc.is_installable(first))


if __name__ == "__main__":
    unittest.main()
