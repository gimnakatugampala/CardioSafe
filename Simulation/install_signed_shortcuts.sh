#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: bash $0 /path/to/CardioSafe.app SIMULATOR_UDID [signing-identity]" >&2
    exit 2
fi

app_path="$1"
device_id="$2"
signing_identity="${3:-Apple Development}"
[[ -d "$app_path" ]] || { echo "App bundle not found." >&2; exit 2; }
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")
[[ "$bundle_id" == "gimnak.CardioSafe" ]] || { echo "Expected the CardioSafe app bundle." >&2; exit 2; }
platform=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$app_path/Info.plist")
[[ "$platform" == "iPhoneSimulator" ]] || { echo "Use an iOS Simulator build." >&2; exit 2; }
xcrun simctl get_app_container "$device_id" com.apple.Preferences app >/dev/null

staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/cardiosafe-shortcuts.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
ditto "$app_path" "$staging_dir/CardioSafe.app"
codesign --force --sign "$signing_identity" --preserve-metadata=identifier,entitlements,flags --timestamp=none "$staging_dir/CardioSafe.app"
codesign --verify --strict "$staging_dir/CardioSafe.app"
signature=$(codesign -dv "$staging_dir/CardioSafe.app" 2>&1)
if [[ "$signature" != *TeamIdentifier=* || "$signature" == *TeamIdentifier=not\ set* ]]; then
    echo "A valid development signing team is required for App Shortcuts." >&2
    exit 1
fi
xcrun simctl terminate "$device_id" "$bundle_id" >/dev/null 2>&1 || true
xcrun simctl install "$device_id" "$staging_dir/CardioSafe.app"
xcrun simctl launch "$device_id" "$bundle_id"
echo "Installed the development-signed simulator build for App Shortcuts."
