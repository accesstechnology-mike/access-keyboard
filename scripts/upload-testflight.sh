#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

if [ -f "$ROOT/secrets/AppStoreConnect.env" ]; then
  # shellcheck disable=SC1091
  set -a
  . "$ROOT/secrets/AppStoreConnect.env"
  set +a
fi

: "${APP_STORE_CONNECT_KEY_ID:?}"
: "${APP_STORE_CONNECT_ISSUER_ID:?}"
: "${APP_STORE_CONNECT_API_KEY_PATH:?}"

KEY_PATH="$APP_STORE_CONNECT_API_KEY_PATH"
case "$KEY_PATH" in
  /*) ;;
  *) KEY_PATH="$ROOT/$KEY_PATH" ;;
esac

if [ ! -f "$KEY_PATH" ]; then
  echo "API key file is missing: $KEY_PATH" >&2
  exit 1
fi

if [ ! -f "$ROOT/Secrets.xcconfig" ]; then
  echo "Secrets.xcconfig is missing; Fix will not authenticate." >&2
  exit 1
fi

python3 "$ROOT/scripts/check-testflight.py"

BUILD="${BUILD_NUMBER:-}"
if [ -z "$BUILD" ]; then
  BUILD="$(python3 "$ROOT/scripts/app_store_connect.py" next-build)"
fi
python3 "$ROOT/scripts/app_store_connect.py" set-build "$BUILD"
echo "Archiving build $BUILD"

WORK="$ROOT/build/testflight"
rm -rf "$WORK"
mkdir -p "$WORK"
python3 "$ROOT/scripts/app_store_connect.py" write-export-options "$WORK/ExportOptions.plist"

ARCHIVE="$WORK/AccessKeyboard.xcarchive"
xcodebuild \
  -project "$ROOT/AccessKeyboard.xcodeproj" \
  -scheme AccessKeyboard \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$WORK/export" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"

echo "Uploaded build $BUILD to App Store Connect / TestFlight."
