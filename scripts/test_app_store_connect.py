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

    def test_conflict_is_ignored_only_when_apple_says_already_exists(self) -> None:
        already = asc.ASCHTTPError(
            409,
            "/v1/betaGroups/1/relationships/builds",
            '{"errors":[{"detail":"The specified resource already exists."}]}',
        )
        other = asc.ASCHTTPError(409, "/v1/builds/1", '{"errors":[{"detail":"Nope."}]}')
        self.assertTrue(asc.ignore_already_exists(already))
        self.assertFalse(asc.ignore_already_exists(other))


if __name__ == "__main__":
    unittest.main()
