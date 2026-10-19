#!/usr/bin/env bash
# CI only. Usage: run.sh "<device name prefix>" <out dir>
set -euo pipefail
NAME="$1"; OUT="$2"; mkdir -p "$OUT"
xcrun simctl shutdown all || true
# Newest available iOS runtime for this device. (Do not pin 26.2: some runners
# list that runtime without a bootable device, and bootstatus hangs forever.)
INFO=$(xcrun simctl list devices available -j | python3 -c "
import json,sys,re
d=json.load(sys.stdin)['devices']
best=None
for rt,devs in d.items():
    if 'iOS' not in rt: continue
    v=tuple(int(x) for x in re.findall(r'\d+',rt.split('iOS')[-1]))
    for dev in devs:
        if dev['name'].startswith(sys.argv[1]) and (best is None or v>best[0]):
            best=(v,dev['udid'],dev['name'],rt)
if best is None:
    raise SystemExit('no simulator matching '+sys.argv[1])
print(best[1]); print(best[2]+'|'+'.'.join(map(str,best[0]))); print(best, file=sys.stderr)
" "$NAME")
UDID=$(echo "$INFO" | sed -n 1p); DEVNAME=$(echo "$INFO" | sed -n 2p | cut -d"|" -f1); DEVOS=$(echo "$INFO" | sed -n 2p | cut -d"|" -f2)
xcrun simctl boot "$UDID" || true
# Cap boot wait so a bad runtime cannot hang the job for the full 60 minutes.
if ! timeout 180 xcrun simctl bootstatus "$UDID" -b; then
  echo "simctl bootstatus timed out or failed for $UDID ($DEVNAME OS $DEVOS)" >&2
  exit 1
fi
xcrun simctl ui "$UDID" appearance light || true
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
(
  while true; do
    for f in "$OUT"/ready-*; do
      [ -e "$f" ] || continue
      n=$(basename "$f"); n=${n#ready-}
      B=$(xcrun simctl list devices booted -j | python3 -c "import json,sys;print(next((d['udid'] for v in json.load(sys.stdin)['devices'].values() for d in v if d['name'].startswith(sys.argv[1])),'$UDID'))" "$NAME")
      xcrun simctl io "$B" screenshot "$OUT/$n.png" && touch "$OUT/done-$n"
      rm -f "$f"
    done
    sleep 0.5
  done
) &
WATCH=$!
set +e
run_tests() {
  TEST_RUNNER_SHOT_DIR="$OUT" TEST_RUNNER_STOREKIT_PATH="$PWD/AccessKeyboard/AccessKeyboard.storekit" xcodebuild test \
    -project AccessKeyboard.xcodeproj -scheme ReviewShots \
    -destination "$1" -derivedDataPath "$RUNNER_TEMP/shots-dd" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO > "$OUT/xcodebuild-$(echo "$NAME" | tr ' ' '-').log" 2>&1
  local rc=$?
  tail -80 "$OUT/xcodebuild-$(echo "$NAME" | tr ' ' '-').log"
  return $rc
}
run_tests "id=$UDID"; STATUS=$?
if [ "$STATUS" = 70 ]; then
  echo "id destination not found; retrying by name $DEVNAME OS $DEVOS"
  run_tests "platform=iOS Simulator,name=$DEVNAME,OS=$DEVOS"; STATUS=$?
fi
kill $WATCH || true
ls -la "$OUT"
exit $STATUS
