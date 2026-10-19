#!/usr/bin/env python3
"""Choose an available iPhone simulator for `xcodebuild test`.

The runner image decides which devices exist, so this does not hard-code a
name or OS. It writes an xcodebuild destination string.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys


def runtime_version(runtime: str) -> tuple[int, ...]:
    numbers: list[int] = []
    current = ""
    for char in runtime:
        if char.isdigit():
            current += char
        elif current:
            numbers.append(int(current))
            current = ""
    if current:
        numbers.append(int(current))
    return tuple(numbers)


def choose_iphone(devices_by_runtime: dict) -> tuple[str, str, str]:
    phones: list[tuple[tuple[int, ...], str, str, str]] = []
    for runtime, devices in devices_by_runtime.items():
        if "iOS" not in runtime:
            continue
        version = runtime_version(runtime)
        if not version:
            continue
        for device in devices or []:
            if device.get("isAvailable") is False:
                continue
            name = str(device.get("name") or "")
            udid = str(device.get("udid") or "")
            if not name.startswith("iPhone") or not udid:
                continue
            phones.append((version, name, runtime, udid))
    if not phones:
        raise RuntimeError("no available iPhone simulator")
    # Newest iOS, then a stable name so the choice does not flap.
    phones.sort(key=lambda item: (item[0], item[1]))
    version, name, runtime, udid = phones[-1]
    del version
    return name, runtime, udid


def destination_for(udid: str) -> str:
    return f"platform=iOS Simulator,id={udid}"


def main() -> int:
    raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
    data = json.loads(raw)
    name, runtime, udid = choose_iphone(data.get("devices") or {})
    destination = destination_for(udid)
    out = os.environ.get("SIMULATOR_DESTINATION_FILE")
    if not out:
        out = os.path.join(os.environ.get("RUNNER_TEMP", "."), "simulator-destination.txt")
    with open(out, "w", encoding="utf-8") as handle:
        handle.write(destination + "\n")
    print(f"simulator {name} runtime={runtime} destination={destination}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as exc:
        sys.stderr.write(f"{exc}\n")
        sys.exit(1)
