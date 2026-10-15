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
