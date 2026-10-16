#!/usr/bin/env bash
# LLVM IR emitted by `mojo build --emit llvm` (host x86-64) → a wasm64 object, with LLVM's own wasm backend.
#   scripts/wasm_convert.sh in.ll out.o
# Mojo 1.1 has no wasm target of its own; this retargets its IR: the triple, the data layout
# (pointers stay 64-bit, hence wasm64), and the x86 CPU/feature attributes go.
set -euo pipefail
in="$1"; out="$2"; ll="${out%.o}.wasm64.ll"
sed -e 's/^target triple = .*/target triple = "wasm64-unknown-unknown"/' \
    -e 's/^target datalayout = .*/target datalayout = "e-m:e-p:64:64-p10:8:8-p20:8:8-i64:64-i128:128-n32:64-S128-ni:1:10:20"/' \
    -e 's/"target-cpu"="[^"]*" *//g' -e 's/"target-features"="[^"]*" *//g' \
    -e 's/"tune-cpu"="[^"]*" *//g' -e 's/attributes \(#[0-9]*\) = { *}/attributes \1 = { nounwind }/' "$in" > "$ll"
LLC="${LLC:-llc}"
"$LLC" -mtriple=wasm64-unknown-unknown -O2 -filetype=obj "$ll" -o "$out"
