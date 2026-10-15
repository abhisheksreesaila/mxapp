#!/usr/bin/env bash
# Build HelloMojo for Mac and/or iPhone, all from Mojo. Works on Linux or a Mac.
#   apple/build.sh mac|ios|all
# Output: build/mac/HelloMojo.app, build/ios/HelloMojo.ipa
# Bundle ID: set BUNDLE_ID (default com.mojoui.hellomojo).
set -euo pipefail
cd "$(dirname "$0")/.."
WHAT="${1:-all}"
BUNDLE_ID="${BUNDLE_ID:-com.mojoui.hellomojo}"
MOJO=(pixi run mojo build -I apple)
LD=(pixi run ld64.lld -arch arm64 -e _mojo_entry -dead_strip -no_adhoc_codesign)

compile() {  # compile <platform-dir> <target-triple> <app-source>
  local out="build/$1"; mkdir -p "$out"
  "${MOJO[@]}" "$3" --target-triple "$2" --emit object -o "$out/hello_$1.o" 2>&1 | grep -v telemetry || true
  "${MOJO[@]}" apple/mojo_rt.mojo --target-triple "$2" --emit object -o "$out/mojo_rt.o" 2>&1 | grep -v telemetry || true
  test -s "$out/hello_$1.o" && test -s "$out/mojo_rt.o"
}

sign() {  # ad-hoc signature: codesign on a Mac, rcodesign on Linux
  if command -v codesign >/dev/null; then codesign --force --sign - "$1"; else rcodesign sign "$1" >/dev/null; fi
}

build_mac() {
  echo "== Mac: compile Mojo for arm64 macOS 14"
  compile mac arm64-apple-macosx14.0 apple/mac/hello_mac.mojo
  local app=build/mac/HelloMojo.app
  rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
  echo "== Mac: link (AppKit, libobjc, libSystem only)"
  "${LD[@]}" -platform_version macos 14.0 14.0 -o "$app/Contents/MacOS/HelloMojo" \
    build/mac/hello_mac.o build/mac/mojo_rt.o apple/sdk/macos/*.tbd
  sed "s/__BUNDLE_ID__/$BUNDLE_ID/" apple/mac/Info.plist > "$app/Contents/Info.plist"
  printf 'APPL????' > "$app/Contents/PkgInfo"
  echo "== Mac: ad-hoc sign"
  sign "$app"
  echo "   $app"
}

build_ios() {
  echo "== iPhone: compile Mojo for arm64 iOS 17"
  compile ios arm64-apple-ios17.0 apple/ios/hello_ios.mojo
  local app=build/ios/Payload/HelloMojo.app
  rm -rf build/ios/Payload build/ios/HelloMojo.ipa; mkdir -p "$app"
  echo "== iPhone: link (UIKit, libobjc, libSystem only)"
  "${LD[@]}" -platform_version ios 17.0 17.0 -o "$app/HelloMojo" \
    build/ios/hello_ios.o build/ios/mojo_rt.o apple/sdk/ios/*.tbd
  sed "s/__BUNDLE_ID__/$BUNDLE_ID/" apple/ios/Info.plist > "$app/Info.plist"
  printf 'APPL????' > "$app/PkgInfo"
  echo "== iPhone: ad-hoc sign (xtool re-signs with your Apple ID on install)"
  sign "$app"
  (cd build/ios && zip -qry HelloMojo.ipa Payload)
  echo "   build/ios/HelloMojo.ipa"
}

case "$WHAT" in
  mac) build_mac ;;
  ios) build_ios ;;
  all) build_mac; build_ios ;;
  *) echo "usage: apple/build.sh mac|ios|all" >&2; exit 2 ;;
esac
