import unittest

import select_iphone_simulator as sim


class SelectIPhoneSimulatorTests(unittest.TestCase):
    def test_picks_the_newest_iphone_runtime(self) -> None:
        devices = {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                {"name": "iPhone 16", "udid": "old", "isAvailable": True},
                {"name": "iPad Pro 13-inch", "udid": "ipad", "isAvailable": True},
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
                {"name": "iPhone 17", "udid": "new", "isAvailable": True},
                {"name": "iPhone 17 Pro", "udid": "pro", "isAvailable": False},
            ],
            "com.apple.CoreSimulator.SimRuntime.watchOS-11-0": [
                {"name": "iPhone 17", "udid": "watch", "isAvailable": True},
            ],
        }
        name, runtime, udid = sim.choose_iphone(devices)
        self.assertEqual(name, "iPhone 17")
        self.assertEqual(udid, "new")
        self.assertIn("iOS-26-0", runtime)
        self.assertEqual(sim.destination_for(udid), "platform=iOS Simulator,id=new")

    def test_version_sort_is_numeric(self) -> None:
        self.assertLess(sim.runtime_version("iOS-9-3"), sim.runtime_version("iOS-18-5"))
        self.assertLess(sim.runtime_version("iOS-18-6"), sim.runtime_version("iOS-26-0"))

    def test_missing_iphone_is_an_error(self) -> None:
        with self.assertRaises(RuntimeError):
            sim.choose_iphone(
                {
                    "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                        {"name": "iPad", "udid": "pad", "isAvailable": True}
                    ]
                }
            )


if __name__ == "__main__":
    unittest.main()
