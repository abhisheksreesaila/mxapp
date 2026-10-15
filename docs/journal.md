# Journal (autopilot)

Newest last. What was tried, what happened, dead ends.

## 2026-10-14
- Mojo 1.1.0 via pixi (`pixi add --pypi mojo`; needed glibc 2.34 on the platform entry).
- Probe: `OwnedDLHandle().get_function[T]("name")` calls one C symbol with any argument types (labs, fabs) ✅. A Mojo `def … abi("C")` passed to C works as a callback (qsort) ✅.
- Draft `apple/hello_mac.mojo` compiled for `arm64-apple-macosx14.0` first try; needed Mojo runtime (`KGEN_*`, 10 functions) because of Mojo's `main`.
- Probe: export a Mojo entry function instead of `main` → only 3 runtime functions left. `@export("main")` is refused ("only 'main' can be exported as 'main'").
- Dead end: defining `KGEN_CompilerRT_AlignedFree` in the same module that uses it → "Call parameter type does not match function signature" (Int vs ptr). Fix: separate Mojo file.
- `KGEN_CompilerRT_GetStackTrace(ptr buf, i64 depth) -> i64` (read from LLVM IR); returns 0 = "no trace". Needed only because errors can be raised.
- Result on Linux: Mojo-only executable, no Mojo runtime, depends only on libc. Prints "Hello, Ada! 3".
- `xtool new --skip-setup` shows xtool's package shape; `xtool install <ipa>` installs a prebuilt app.
- `@export` in the same module as a call to the runtime fn fails → `apple/mojo_rt.mojo` on its own.
- Linked the Mac app with `ld64.lld` + `.tbd` stubs: 72 KB arm64 Mach-O, LC_MAIN → `_mojo_entry`, loads only AppKit, libobjc, libSystem.
- `rcodesign verify` fails on every ad-hoc signature ("CMS error", and it warns its verify is buggy). Wrote `scripts/verify_signature.py` (recomputes page + Info.plist hashes); tamper tests catch a 1-byte change in code and in Info.plist.
- Linker's own ad-hoc signature left 5 KB of stray bytes after rcodesign re-signed → link with `-no_adhoc_codesign`, sign once.
- Read Mojo's `std/ffi/__init__.mojo` (github modular/modular, `Mojo/stdlib/std/ffi`): `_DLCallable` just bitcasts the address to `def(*a: *T) thin abi("C") -> R`. Copied the trick: `dlsym(RTLD_DEFAULT=-2, "objc_msgSend")` + bitcast → one variadic `msg()`; no dlopen/dlclose, nothing raises, GetStackTrace no longer pulled in.
- Gotcha: printing a Float64 pulls in `KGEN_CompilerRT_fprintf`. Don't print floats in app code (or add a stand-in).
- Disassembly check (arm64): window init puts the rect in d0–d3 (0, 0, 460.0, 280.0) and style/backing/defer in x2/x3/x4 — same as Apple's NSRect-by-value convention. Insets: 32.0 in d0–d3.
- Reviewer: PASS, nothing expected to crash; 10 findings. Fixed 1–9, #10 not an issue (xtool prefixes bundle IDs per user).
- Quirk: Mojo built fine with an unfinished `def broken(` appended to an *imported* module (`hello_core.mojo`); it seems to parse imported modules lazily. Errors in the app file itself fail the build (exit 1), and `build.sh` now stops and leaves no stale objects. The M1 tests cover `hello_core`.
- Resource seal (`_CodeSignature/CodeResources`) now verified too; tamper test caught.
- Re-review: PASS. SDK-26 marking judged low risk (no launch check on dev installs; app already uses scenes).
