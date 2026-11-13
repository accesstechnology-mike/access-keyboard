import importlib.util
import unittest
from pathlib import Path

_path = Path(__file__).with_name("check-testflight.py")
_spec = importlib.util.spec_from_file_location("check_testflight", _path)
assert _spec and _spec.loader
check_testflight = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_testflight)

MARKETING_VERSION = check_testflight.MARKETING_VERSION
live_proxy_problem = check_testflight.live_proxy_problem


class LiveProxyProblemTests(unittest.TestCase):
    def test_marketing_version_is_the_release_being_shipped(self) -> None:
        self.assertEqual(MARKETING_VERSION, "1.0.1")

    def test_signed_data_required_is_a_healthy_production_proxy(self) -> None:
        self.assertIsNone(
            live_proxy_problem(401, {"error": "signed_data_required"})
        )

    def test_a_wrong_secret_still_fails(self) -> None:
        self.assertIn(
            "401",
            live_proxy_problem(401, {"error": "unauthorized"}) or "",
        )

    def test_a_successful_legacy_fix_must_keep_the_word_cat(self) -> None:
        self.assertIsNone(live_proxy_problem(200, {"text": "The cat sat"}))
        self.assertIn("meaning", live_proxy_problem(200, {"text": "hello"}) or "")


if __name__ == "__main__":
    unittest.main()
