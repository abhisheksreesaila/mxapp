#!/usr/bin/env bash
# Build HelloMojo for Mac and/or iPhone, all from Mojo. Works on Linux or a Mac.
#   apple/build.sh mac|ios|all
# Output: build/mac/HelloMojo.app (+ HelloMojo-mac.zip), build/ios/HelloMojo.ipa
# Bundle ID: set BUNDLE_ID (default com.mojoui.hellomojo).
# Runs on macOS 14+ / iOS 17+; marked as built with the 26 SDKs so new systems
# give it their current look (Liquid Glass) instead of compatibility mode.
set -euo pipefail
cd "$(dirname "$0")/.."
WHAT="${1:-all}"
BUNDLE_ID="${BUNDLE_ID:-com.mojoui.hellomojo}"
MOJO=(pixi run mojo build -I apple)
LD=(pixi run ld64.lld -arch arm64 -e _mojo_entry -dead_strip -no_adhoc_codesign)

mojo_obj() {  # mojo_obj <source> <target-triple> <out.o>: fails if Mojo fails
  local log; log=$(mktemp)
  if ! "${MOJO[@]}" "$1" --target-triple "$2" --emit object -o "$3" >"$log" 2>&1; then
    grep -v telemetry "$log" >&2; rm -f "$log"; return 1
  fi
  grep -v telemetry "$log" || true; rm -f "$log"
}

compile() {  # compile <platform-dir> <target-triple> <app-source>
  local out="build/$1"; mkdir -p "$out"
  rm -f "$out/hello_$1.o" "$out/mojo_rt.o"  # never link stale objects
  mojo_obj "$3" "$2" "$out/hello_$1.o"
  mojo_obj apple/mojo_rt.mojo "$2" "$out/mojo_rt.o"
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
  "${LD[@]}" -platform_version macos 14.0 26.0 -o "$app/Contents/MacOS/HelloMojo" \
    build/mac/hello_mac.o build/mac/mojo_rt.o apple/sdk/macos/*.tbd
  sed "s/__BUNDLE_ID__/$BUNDLE_ID/" apple/mac/Info.plist > "$app/Contents/Info.plist"
  printf 'APPL????' > "$app/Contents/PkgInfo"
  echo "== Mac: ad-hoc sign"
  sign "$app"
  rm -f build/mac/HelloMojo-mac.zip
  (cd build/mac && zip -qry HelloMojo-mac.zip HelloMojo.app)
  echo "   $app  (and build/mac/HelloMojo-mac.zip to copy to a Mac)"
}

build_ios() {
  echo "== iPhone: compile Mojo for arm64 iOS 17"
  compile ios arm64-apple-ios17.0 apple/ios/hello_ios.mojo
  local app=build/ios/Payload/HelloMojo.app
  rm -rf build/ios/Payload build/ios/HelloMojo.ipa; mkdir -p "$app"
  echo "== iPhone: link (UIKit, libobjc, libSystem only)"
  "${LD[@]}" -platform_version ios 17.0 26.0 -o "$app/HelloMojo" \
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
