#!/bin/bash
# cleanMac: Release 构建 → 生成 DMG
# 用法:
#   ./Scripts/make_dmg.sh
#   CODESIGN_IDENTITY="Developer ID Application: ..." ./Scripts/make_dmg.sh
#   NOTARY_APPLE_ID=... NOTARY_TEAM_ID=... NOTARY_PASSWORD=... ./Scripts/make_dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="cleanMac.xcodeproj"
SCHEME="cleanMac"
CONFIG="Release"
APP_NAME="cleanMac"
DERIVED="$ROOT/build/dd"
APP_PATH="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
STAGING="$ROOT/build/dmg-staging"
DMG_PATH="$ROOT/build/$APP_NAME.dmg"
VOL_NAME="cleanMac"
ARCH_PATH="$ROOT/build/cleanMac.xcarchive"

echo "==> 1/5 构建 $CONFIG"
rm -rf "$DERIVED" "$STAGING"
mkdir -p "$ROOT/build"
BUILD_SETTINGS=()
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  BUILD_SETTINGS+=(CODE_SIGNING_ALLOWED=NO)
fi
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  "${BUILD_SETTINGS[@]}" \
  build | tail -n 20

if [[ ! -d "$APP_PATH" ]]; then
  echo "错误：未找到 $APP_PATH" >&2
  exit 1
fi

echo "==> 2/5 准备 staging"
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -sf /Applications "$STAGING/Applications"

echo "==> 3/5 签名（可选）"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime \
    --timestamp \
    --sign "$CODESIGN_IDENTITY" \
    "$STAGING/$APP_NAME.app"
  codesign --verify --verbose=2 "$STAGING/$APP_NAME.app"
else
  echo "    跳过签名（未设置 CODESIGN_IDENTITY）"
fi

echo "==> 4/5 生成 DMG"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$DMG_PATH" || true
fi

echo "==> 5/5 公证（可选）"
if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$NOTARY_TEAM_ID" \
    --password "$NOTARY_PASSWORD" \
    --wait
  xcrun stapler staple "$DMG_PATH"
else
  echo "    跳过公证（未设置 NOTARY_*）"
fi

echo ""
echo "完成: $DMG_PATH"
ls -lh "$DMG_PATH"
