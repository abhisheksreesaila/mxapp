#!/usr/bin/env bash
# Reproduce Experiment 1 (M0 + the runtime stand-in check) on Linux.
# Needs: mojo (pip install mojo), gcc. Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

echo "== 1. Build the C bridge"
gcc -Wall -Wextra -shared -fPIC -o build/libmojoui_bridge.so bridge/mojoui_bridge.c

echo "== 2. Mojo calls C"
mojo build m0_call_c.mojo -o build/m0_call_c -Xlinker -Lbuild -Xlinker -lmojoui_bridge
LD_LIBRARY_PATH=build ./build/m0_call_c

echo "== 3. C calls Mojo; Mojo keeps state across calls"
mojo build app_entry.mojo --emit shared-lib -o build/libmojoui_app.so \
  -Xlinker -Lbuild -Xlinker -lmojoui_bridge -Xlinker -rpath -Xlinker '$ORIGIN'
gcc -Wall -o build/hello-host bridge/host_main.c -Lbuild -lmojoui_app -lmojoui_bridge \
  -Wl,--disable-new-dtags,-rpath,'$ORIGIN'
./build/hello-host

echo "== 4. Same app, statically linked with NO Mojo runtime (unofficial stand-in)"
mojo build app_entry.mojo --emit object -o build/app-linux.o
gcc -Wall -o build/hello-static bridge/host_main.c bridge/mojoui_bridge.c spike/kgen_shim.c build/app-linux.o
echo "   dynamic deps: $(ldd build/hello-static | awk '{print $1}' | tr '\n' ' ')"
./build/hello-static

echo "== 5. iOS objects: what they still need"
mojo build app_entry.mojo --target-triple arm64-apple-ios17.0 --emit object -o build/app-ios.o
llvm-nm -u build/app-ios.o | tr '\n' ' '; echo
echo "Done."
