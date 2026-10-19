#!/usr/bin/env bash
# CI only. Usage: run.sh "<device name prefix>" <out dir>
set -euo pipefail
NAME="$1"; OUT="$2"; mkdir -p "$OUT"
UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys,re
d=json.load(sys.stdin)['devices']
best=None
for rt,devs in d.items():
    if 'iOS' not in rt: continue
    v=tuple(int(x) for x in re.findall(r'\d+',rt.split('iOS')[-1]))
    for dev in devs:
        if dev['name'].startswith(sys.argv[1]) and (best is None or v>best[0]):
            best=(v,dev['udid'],dev['name'],rt)
print(best[1]); print(best, file=sys.stderr)
" "$NAME")
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance light || true
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
(
  while true; do
    for f in "$OUT"/ready-*; do
      [ -e "$f" ] || continue
      n=$(basename "$f"); n=${n#ready-}
      xcrun simctl io "$UDID" screenshot "$OUT/$n.png" && touch "$OUT/done-$n"
      rm -f "$f"
    done
    sleep 0.5
  done
) &
WATCH=$!
set +e
TEST_RUNNER_SHOT_DIR="$OUT" xcodebuild test \
  -project AccessKeyboard.xcodeproj -scheme ReviewShots \
  -destination "id=$UDID" -derivedDataPath "$RUNNER_TEMP/shots-dd" \
  -resultBundlePath "$OUT/result-$(echo "$NAME" | tr ' ' '-').xcresult" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -60
STATUS=${PIPESTATUS[0]}
kill $WATCH || true
ls -la "$OUT"
exit $STATUS
