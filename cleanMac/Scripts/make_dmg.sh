#!/bin/bash
# 默认生成 Apple Silicon 和 Intel 两个 DMG。
# BUILD_ARCH=arm64|x86_64|universal 可仅生成指定架构。
# 正式发布：CODESIGN_IDENTITY="Developer ID Application: ..." NOTARY_KEYCHAIN_PROFILE=... ./Scripts/make_dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP_NAME="cleanMac"
BUILD_ARCH="${BUILD_ARCH:-all}"
SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"
BUNDLE_ID="com.cleanMac.cache.cleanMac"

case "$BUILD_ARCH" in
  all) TARGET_ARCHS=(arm64 x86_64) ;;
  arm64|x86_64|universal) TARGET_ARCHS=("$BUILD_ARCH") ;;
  *) echo "错误：BUILD_ARCH 只支持 all、arm64、x86_64 或 universal" >&2; exit 1 ;;
esac

HAS_NOTARY=0
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  HAS_NOTARY=1
elif [[ -n "${NOTARY_APPLE_ID:-}${NOTARY_TEAM_ID:-}${NOTARY_PASSWORD:-}" ]]; then
  if [[ -z "${NOTARY_APPLE_ID:-}" || -z "${NOTARY_TEAM_ID:-}" || -z "${NOTARY_PASSWORD:-}" ]]; then
    echo "错误：NOTARY_APPLE_ID、NOTARY_TEAM_ID 和 NOTARY_PASSWORD 必须同时设置" >&2
    exit 1
  fi
  HAS_NOTARY=1
fi
if [[ "$HAS_NOTARY" = 1 && "$SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
  echo "错误：Apple 公证需要 Developer ID Application 签名证书" >&2
  exit 1
fi

SIGN_OPTIONS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" = "-" ]]; then
  SIGN_OPTIONS+=(--timestamp=none)
else
  SIGN_OPTIONS+=(--options runtime --timestamp)
fi

# 先签内部代码，再封装整个 app，确保资源清单完整。
sign_app() {
  local app="$1" code
  while IFS= read -r -d '' code; do
    if /usr/bin/file -b "$code" | /usr/bin/grep -q 'Mach-O'; then
      codesign "${SIGN_OPTIONS[@]}" "$code"
    fi
  done < <(find "$app/Contents" -type f -print0)
  while IFS= read -r -d '' code; do
    codesign "${SIGN_OPTIONS[@]}" "$code"
  done < <(find "$app/Contents" -depth -type d \( -name '*.framework' -o -name '*.xpc' -o -name '*.appex' -o -name '*.app' \) -print0)
  codesign "${SIGN_OPTIONS[@]}" --identifier "$BUNDLE_ID" \
    --entitlements "$ROOT/cleanMac/cleanMac.entitlements" "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
}

verify_dmg() {
  local dmg="$1" expected_arch="$2" expected_version="$3" expected_build="$4" mount_dir actual_arch
  hdiutil verify "$dmg"
  mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/cleanmac-verify.XXXXXX")"
  hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg" >/dev/null
  # 子 shell 的退出处理确保校验失败时也卸载镜像。
  (
    trap 'hdiutil detach "$mount_dir" >/dev/null; rmdir "$mount_dir"' EXIT
    local_app="$mount_dir/$APP_NAME.app"
    codesign --verify --deep --strict --verbose=2 "$local_app"
    test "$(plutil -extract CFBundleIdentifier raw -o - "$local_app/Contents/Info.plist")" = "$BUNDLE_ID"
    test "$(plutil -extract CFBundleShortVersionString raw -o - "$local_app/Contents/Info.plist")" = "$expected_version"
    test "$(plutil -extract CFBundleVersion raw -o - "$local_app/Contents/Info.plist")" = "$expected_build"
    actual_arch="$(lipo -archs "$local_app/Contents/MacOS/$APP_NAME")"
    if [[ "$expected_arch" = universal ]]; then
      lipo -verify_arch arm64 x86_64 "$local_app/Contents/MacOS/$APP_NAME"
    else
      test "$actual_arch" = "$expected_arch"
    fi
    if [[ "$HAS_NOTARY" = 1 ]]; then
      xcrun stapler validate "$dmg"
      spctl --assess --type execute --verbose=2 "$local_app"
    fi
    echo "校验通过：$expected_version ($expected_build)，$actual_arch"
  )
}

build_dmg() {
  local arch="$1" suffix derived app_path staging dmg log version build
  suffix="-$arch"
  [[ "$arch" != universal ]] || suffix=""
  derived="$ROOT/build/dd$suffix"
  app_path="$derived/Build/Products/Release/$APP_NAME.app"
  staging="$ROOT/build/dmg-staging$suffix"
  dmg="$ROOT/build/$APP_NAME$suffix.dmg"
  log="$ROOT/build/xcodebuild-release$suffix.log"
  local build_settings=(CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO)
  if [[ "$arch" = universal ]]; then
    build_settings+=("ARCHS=arm64 x86_64")
  else
    build_settings+=("ARCHS=$arch")
  fi
  mkdir -p "$ROOT/build"
  echo "==> [$arch] 构建 Release"
  if ! xcodebuild -project cleanMac.xcodeproj -scheme cleanMac \
    -configuration Release -derivedDataPath "$derived" \
    -destination 'generic/platform=macOS' "${build_settings[@]}" build > "$log" 2>&1; then
    tail -n 100 "$log" >&2
    return 1
  fi
  test -d "$app_path"
  version="$(plutil -extract CFBundleShortVersionString raw -o - "$app_path/Contents/Info.plist")"
  build="$(plutil -extract CFBundleVersion raw -o - "$app_path/Contents/Info.plist")"
  rm -rf "$staging"
  mkdir -p "$staging"
  ditto "$app_path" "$staging/$APP_NAME.app"
  ln -s /Applications "$staging/Applications"
  echo "==> [$arch] 完整签名"
  sign_app "$staging/$APP_NAME.app"
  echo "==> [$arch] 生成 DMG"
  hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -ov -format UDZO "$dmg"
  if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$dmg"
    codesign --verify --strict --verbose=2 "$dmg"
  fi
  if [[ "$HAS_NOTARY" = 1 ]]; then
    echo "==> [$arch] Apple 公证"
    if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
      xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
    else
      xcrun notarytool submit "$dmg" --apple-id "$NOTARY_APPLE_ID" \
        --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --wait
    fi
    xcrun stapler staple "$dmg"
  fi
  echo "==> [$arch] 校验镜像内的签名、版本和架构"
  verify_dmg "$dmg" "$arch" "$version" "$build"
  shasum -a 256 "$dmg"
  ls -lh "$dmg"
}

for target_arch in "${TARGET_ARCHS[@]}"; do
  build_dmg "$target_arch"
done
if [[ "$HAS_NOTARY" != 1 ]]; then
  echo "提示：安装包已完成完整性签名，但尚未通过 Apple 公证，下载后仍可能被 Gatekeeper 拦截。"
fi
