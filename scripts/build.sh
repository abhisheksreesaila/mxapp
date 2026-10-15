#!/usr/bin/env bash
# Build a mojoui example for Linux, Mac and/or iPhone from ONE app file.
#   scripts/build.sh <example> linux|mac|ios|all      e.g. scripts/build.sh hello all
# Input:  examples/<example>/app.mojo (defines Main)
# Output: build/<example>/linux/<example>            native GTK app (runs here)
#         build/<example>/mac/<Name>Mojo.app (+ .zip)  native AppKit app (Apple Silicon)
#         build/<example>/ios/<Name>Mojo.ipa           native UIKit app (install with apple/install_iphone.sh)
#         build/<example>/web/mojoui_app.so            the app as a Python module, served by mojoui/hosts/web.py
# Env: BUNDLE_PREFIX (default com.mojoui) → bundle ID <prefix>.<example>
set -euo pipefail
cd "$(dirname "$0")/.."
EX="${1:?usage: scripts/build.sh <example> linux|web|mac|ios|android|all}"
WHAT="${2:-all}"
SRC="examples/$EX/app.mojo"
test -f "$SRC" || { echo "no $SRC" >&2; exit 2; }
NAME="$(tr '[:lower:]' '[:upper:]' <<< "${EX:0:1}")${EX:1}Mojo"   # hello → HelloMojo
BUNDLE_ID="${BUNDLE_PREFIX:-com.mojoui}.$EX"
MOJO=(pixi run mojo build -I "examples/$EX" -I .)

mojo_build() {  # mojo_build <args...>: fails if Mojo fails, hides the telemetry warning
  local log; log=$(mktemp)
  if ! "${MOJO[@]}" "$@" >"$log" 2>&1; then grep -v telemetry "$log" >&2; rm -f "$log"; return 1; fi
  grep -v telemetry "$log" || true; rm -f "$log"
}

stamp() { sha256sum "$SRC" | cut -d' ' -f1 > "$1/app.sha256"; }  # which app file this build used

sign() {  # ad-hoc signature: codesign on a Mac, rcodesign on Linux
  if command -v codesign >/dev/null; then codesign --force --sign - "$1"; else rcodesign sign "$1" >/dev/null 2>&1; fi
}

plist() {  # plist <template> <out>
  sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/HelloMojo/$NAME/g" "$1" > "$2"
}

build_linux() {
  local out="build/$EX/linux"; mkdir -p "$out"; rm -f "$out/$EX"
  echo "== Linux ($EX): GTK4 + libadwaita"
  mojo_build hosts/linux_main.mojo -o "$out/$EX" \
    -Xlinker -lgtk-4 -Xlinker -ladwaita-1 -Xlinker -lgobject-2.0 -Xlinker -lglib-2.0 -Xlinker -lgio-2.0
  stamp "$out"; echo "   $out/$EX"
}

build_web() {
  local out="build/$EX/web"; mkdir -p "$out"; rm -f "$out/mojoui_app.so"
  echo "== Web ($EX): Mojo Python module for FastHTML"
  mojo_build hosts/web_main.mojo --emit shared-lib -o "$out/mojoui_app.so"
  stamp "$out"; echo "   $out/mojoui_app.so  (serve: pixi run python mojoui/hosts/web.py $out)"
}

build_android() {  # exploration: a real arm64 libmojoui.so, no APK yet (docs/android.md)
  local out="build/$EX/android"; mkdir -p "$out/lib/arm64-v8a" "$out/stubs"; rm -f "$out"/*.o
  echo "== Android ($EX): arm64 libmojoui.so for a NativeActivity (exploration)"
  mojo_build hosts/android_main.mojo --target-triple aarch64-linux-android29 --emit object -o "$out/app.o"
  mojo_build mojoui/hosts/mojo_rt.mojo --target-triple aarch64-linux-android29 --emit object -o "$out/mojo_rt.o"
  # Empty stand-ins that only carry the system libraries' names (like apple/sdk/*.tbd);
  # the device's real libc/liblog provide the functions at run time.
  echo "" | llvm-mc -triple=aarch64-linux-android -filetype=obj -o "$out/stubs/empty.o"
  for lib in libc liblog; do  # only what the library uses
    pixi run ld.lld -shared -soname "$lib.so" -o "$out/stubs/$lib.so" "$out/stubs/empty.o"
  done
  pixi run ld.lld -shared -soname libmojoui.so -z noexecstack --gc-sections -o "$out/lib/arm64-v8a/libmojoui.so" \
    "$out/app.o" "$out/mojo_rt.o" "$out"/stubs/*.so
  stamp "$out"; echo "   $out/lib/arm64-v8a/libmojoui.so"
}

apple_objects() {  # apple_objects <dir> <triple> <host-main>
  rm -f "$1"/*.o
  mojo_build "$3" --target-triple "$2" --emit object -o "$1/app.o"
  mojo_build mojoui/hosts/mojo_rt.mojo --target-triple "$2" --emit object -o "$1/mojo_rt.o"
}

build_mac() {
  local out="build/$EX/mac"; mkdir -p "$out"
  echo "== Mac ($EX): AppKit, arm64 macOS 14+"
  apple_objects "$out" arm64-apple-macosx14.0 hosts/mac_main.mojo
  local app="$out/$NAME.app"; rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
  pixi run ld64.lld -arch arm64 -e _mojo_entry -dead_strip -no_adhoc_codesign \
    -platform_version macos 14.0 26.0 -o "$app/Contents/MacOS/$NAME" "$out"/*.o apple/sdk/macos/*.tbd
  plist apple/mac/Info.plist "$app/Contents/Info.plist"
  printf 'APPL????' > "$app/Contents/PkgInfo"
  sign "$app"
  rm -f "$out/$NAME-mac.zip"; (cd "$out" && zip -qry "$NAME-mac.zip" "$NAME.app")
  stamp "$out"; echo "   $app (+ $out/$NAME-mac.zip)"
}

build_ios() {
  local out="build/$EX/ios"; mkdir -p "$out"
  echo "== iPhone ($EX): UIKit, arm64 iOS 17+"
  apple_objects "$out" arm64-apple-ios17.0 hosts/ios_main.mojo
  local app="$out/Payload/$NAME.app"; rm -rf "$out/Payload" "$out/$NAME.ipa"; mkdir -p "$app"
  pixi run ld64.lld -arch arm64 -e _mojo_entry -dead_strip -no_adhoc_codesign \
    -platform_version ios 17.0 26.0 -o "$app/$NAME" "$out"/*.o apple/sdk/ios/*.tbd
  plist apple/ios/Info.plist "$app/Info.plist"
  printf 'APPL????' > "$app/PkgInfo"
  sign "$app"
  (cd "$out" && zip -qry "$NAME.ipa" Payload)
  stamp "$out"; echo "   $out/$NAME.ipa"
}

case "$WHAT" in
  linux) build_linux ;;
  web) build_web ;;
  mac) build_mac ;;
  ios) build_ios ;;
  android) build_android ;;
  all)  # every platform, or only those listed in examples/<example>/platforms
    for p in $(cat "examples/$EX/platforms" 2>/dev/null || echo linux web mac ios); do "build_$p"; done ;;
  *) echo "usage: scripts/build.sh <example> linux|web|mac|ios|android|all" >&2; exit 2 ;;
esac
