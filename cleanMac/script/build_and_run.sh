#!/usr/bin/env bash
set -euo pipefail

mode="${1:-run}"
app_name="cleanMac"
bundle_id="com.cleanMac.cache.cleanMac"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bundle="$root_dir/build/dd/Build/Products/Debug/$app_name.app"
app_binary="$app_bundle/Contents/MacOS/$app_name"

case "$mode" in
  run|--debug|--logs|--telemetry|--verify) ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

pkill -x "$app_name" >/dev/null 2>&1 || true
xcodebuild \
  -project "$root_dir/cleanMac.xcodeproj" \
  -scheme "$app_name" \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$root_dir/build/dd" \
  -quiet build

case "$mode" in
  run)
    /usr/bin/open -n "$app_bundle"
    ;;
  --debug)
    lldb -- "$app_binary"
    ;;
  --logs)
    /usr/bin/open -n "$app_bundle"
    /usr/bin/log stream --info --style compact --predicate "process == \"$app_name\""
    ;;
  --telemetry)
    /usr/bin/open -n "$app_bundle"
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$bundle_id\""
    ;;
  --verify)
    /usr/bin/open -n "$app_bundle"
    sleep 1
    pgrep -f "$app_binary" >/dev/null
    ;;
esac
