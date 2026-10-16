#!/usr/bin/env bash
# Mojo → WebAssembly, today (goal 9's spike; the findings are in docs/wasm.md):
#   mojo build --emit llvm  →  retarget the IR to wasm64 (scripts/wasm_convert.sh)  →  llc  →  wasm-ld with
#   spike/wasm_shim.c (8 symbols: the KGEN allocator + the stdlib's stdout calls)  →  runs in Chromium.
# Builds build/wasm/{hello,medium,print}.wasm and runs each in headless Chromium (scripts/wasm_run.py).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/.pixi/envs/default/bin:$PATH"   # wasm-ld; llc and clang come from the system's LLVM
mkdir -p build/wasm
emit() { pixi run mojo build --emit llvm "$1" -o "$2" 2>&1 | grep -v telemetry || true; }
emit spike/tiny.mojo build/wasm/hello.ll
emit spike/wasm_medium.mojo build/wasm/medium.ll
emit spike/wasm_print.mojo build/wasm/print.ll
for f in hello medium print; do scripts/wasm_convert.sh build/wasm/$f.ll build/wasm/$f.o; done
clang --target=wasm64-unknown-unknown -nostdlib -O2 -c spike/wasm_shim.c -o build/wasm/shim.o
wasm-ld --no-entry --export-all -mwasm64 build/wasm/hello.o -o build/wasm/hello.wasm
for f in medium print; do wasm-ld --no-entry --export-all --allow-undefined -mwasm64 build/wasm/$f.o build/wasm/shim.o -o build/wasm/$f.wasm; done
echo "undefined symbols before the shim: medium $(llvm-nm --undefined-only build/wasm/medium.o | wc -l), print $(llvm-nm --undefined-only build/wasm/print.o | wc -l)"
pixi run python scripts/wasm_run.py build/wasm/hello.wasm mojo_add 2 3
pixi run python scripts/wasm_run.py build/wasm/medium.wasm sum_squares 1000
pixi run python scripts/wasm_run.py build/wasm/medium.wasm text_length 5
pixi run python scripts/wasm_run.py build/wasm/print.wasm say 41
