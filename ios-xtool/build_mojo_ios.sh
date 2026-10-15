#!/usr/bin/env bash
# Rebuild the prebuilt Mojo libraries for iPhone and simulator, and refresh the C glue.
# Runs on Linux or macOS. Needs: mojo (pip install mojo), llvm-ar, llvm-nm.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=..

mojo build "$ROOT/app_entry.mojo" --target-triple arm64-apple-ios17.0 --emit object -o /tmp/mojoapp-ios.o
mojo build "$ROOT/app_entry.mojo" --target-triple arm64-apple-ios17.0-simulator --emit object -o /tmp/mojoapp-iossim.o

mkdir -p Mojo/ios-device Mojo/ios-simulator
rm -f Mojo/ios-device/libmojoapp.a Mojo/ios-simulator/libmojoapp.a
llvm-ar rcs --format=darwin Mojo/ios-device/libmojoapp.a /tmp/mojoapp-ios.o
llvm-ar rcs --format=darwin Mojo/ios-simulator/libmojoapp.a /tmp/mojoapp-iossim.o

# Keep the C glue in sync with the desktop bridge and the runtime stand-in.
cp "$ROOT/bridge/mojoui_bridge.c" Sources/MojoBridge/mojoui_bridge.c
cp "$ROOT/spike/kgen_shim.c"      Sources/MojoBridge/kgen_shim.c

echo "Symbols the Mojo library still needs from outside (check for new KGEN_* entries):"
llvm-nm -u Mojo/ios-device/libmojoapp.a | grep -v '^$' | grep -v ':$'
