# Mojo → WebAssembly: the spike (goal 9, M9)

**Question:** can Mojo code run in the browser today, without forking the compiler?
**Answer:** yes, for real stdlib code, with an 8-symbol runtime shim. `scripts/wasm_spike.sh` reproduces everything below in about a minute.

WASM: shim-sized

## What was tried, in order
1. `mojo build --target-triple wasm32-unknown-unknown` (and wasm64): **refused**: "No available targets are compatible with triple". Mojo 1.1's compiler ships no wasm backend.
2. `mojo build --emit llvm spike/tiny.mojo`: the compiler's LLVM IR for the host. Retargeting that IR (the triple, the data layout, the x86 CPU/feature attributes; `scripts/wasm_convert.sh`) and feeding it to LLVM 22's own `llc -mtriple=wasm64-unknown-unknown` **works**: pointers and `Int` are 64-bit in the IR, so the target is wasm64 (Memory64), which Chromium 152 runs.
3. `wasm-ld --no-entry --export-all` → `build/wasm/hello.wasm` (671 bytes). Headless Chromium calls `mojo_add(2, 3)` and gets **5** (`scripts/wasm_run.py`).
4. A realistic sample (`spike/wasm_medium.mojo`: a struct, `List`, `String` building, loops) has **8 undefined symbols** after retargeting; `spike/wasm_print.mojo` (`print`) has 7, the same ones:

   | symbol | what it is | provided by |
   |---|---|---|
   | `KGEN_CompilerRT_AlignedAlloc`, `KGEN_CompilerRT_AlignedFree` | Mojo's runtime allocator (the same two the iOS spike needed) | `spike/wasm_shim.c`: a bump allocator |
   | `write`, `dup`, `fdopen`, `fclose`, `fflush` | the stdlib's stdout path | the shim; `write` calls an imported JS function |
   | `__stack_pointer` | the linker's | wasm-ld |

   `spike/wasm_shim.c` is 25 lines, built with `clang --target=wasm64-unknown-unknown -nostdlib`. With it: `sum_squares(1000) = 333832500`, `text_length(5) = 10`, and `say(41)` prints "hello from Mojo 41" through the import and returns 42, all in headless Chromium.

## What this means
- **The compiler is not the wall.** LLVM's wasm backend already does the work; Mojo only needs to stop refusing the triple (or keep emitting IR). No fork, no new target.
- **The runtime is small.** Everything a stdlib program asked for fits in one C file. The iOS spike found the same two `KGEN_*` entry points.
- **The browser is the host.** mojo-ui's web host already turns the view tree into JSON and renders it with a fixed JavaScript adapter; a wasm build of an app would emit that same JSON in the page, with no server, and the Canvas adapter would paint frames from the module's memory. That is the "client-side mojo-ui" path.

## What remains (not tonight)
- Memory grows only (the bump allocator never frees): a real build needs `dlmalloc` or walloc compiled to wasm64, a few hundred lines.
- A wasm32 build (every browser, smaller pointers) needs the compiler to emit 32-bit IR: that is the one thing only Modular can do, or a compiler contribution once the compiler is open (the IR retargeting trick can't shrink `Int`).
- The GPU: WebGPU from wasm goes through imports (the browser owns the device); mojoui's kernels would be WGSL, not MAX, a port rather than a recompile.
- Threads, files, time: more imports in the same shim, one per libc call the stdlib makes.

## Reproduce
```bash
scripts/wasm_spike.sh     # builds build/wasm/{hello,medium,print}.wasm and runs them in Chromium
```
