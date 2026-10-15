# mojo-ui experiments log

A dated record of what was tried, what happened, and what it means. Newest first.

---

## 2026-10-14 · Prep for M5 step 3: iPhone from Linux via xtool (not yet run)

**Why:** xtool (github.com/xtool-org/xtool) builds, signs and installs Swift-package iOS apps from Linux, WSL or Windows onto a real iPhone. Combined with a SwiftUI skin, it removes the need for a Mac and for porting SDL3 to iOS.

**What was prepared (all on Linux):**
- `bridge/mojoui_bridge.c` now keeps the last text Mojo sends, readable via `mui_last_text()` / `mui_last_text_len()`. Desktop M0 still passes (`scripts/m0_linux.sh`, clean build, all 5 steps).
- `ios-xtool/Mojo/ios-device/libmojoapp.a`: `app_entry.mojo` for iPhone (`platform ios`); `ios-simulator/libmojoapp.a` for the simulator (`platform iossimulator`). Built with `mojo build --target-triple … --emit object` + `llvm-ar rcs --format=darwin`.
- Exports: `_mojo_app_init`, `_mojo_app_event`, `_mojo_app_quit`. Still needs from outside: the two `KGEN_CompilerRT_Aligned*` functions (covered by `kgen_shim.c`), our `_mui_echo`, and standard C (`memcpy`, `write`, `fflush`, `fdopen`, `fclose`, `dup`).
- `ios-xtool/` Swift package: `MojoBridge` C target (bridge + shim, links `libmojoapp.a` via `-L` + `linkedLibrary`) and a `HelloMojo` SwiftUI target.
- The C glue passes a syntax check on Linux.

**Not verified yet:** the Swift package itself (needs Xcode.xip's iOS SDK via `xtool setup`), xtool's expected package shape, linking through SwiftPM, and running on an iPhone.

**Next:** follow `ios-xtool/README.md` on the owner's machine with an iPhone attached; record the result here.

---

## 2026-10-14 · Experiment 1: Mojo ↔ C both ways, and the first iOS measurement

**Setup:** Linux x86-64, Python 3.13, `pip install mojo` → Mojo 1.1.0 (8189361e).

### M0 · Mojo calls C — ✅ worked first try
- `bridge/mojoui_bridge.c` exports `mui_version()` and `mui_echo(ptr, len)`.
- `m0_call_c.mojo` calls both with `external_call`, passing a Mojo `String` as `s.unsafe_ptr()` + `s.byte_length()`.
- Built with `mojo build m0_call_c.mojo -Xlinker -Lbuild -Xlinker -lmojoui_bridge`.
- Output: `mui_version() = 1`; C received the 15-byte string correctly.

### M0 · C calls Mojo, Mojo keeps state — ✅ worked after two fixes
- `app_entry.mojo` exports `mojo_app_init`, `mojo_app_event`, `mojo_app_quit` with `@export … abi("C")`; app state is a heap struct handed to C as an `Int` address.
- `bridge/host_main.c` owns the loop: init, three simulated clicks, quit. Each click updates Mojo state and Mojo calls back into C.
- Output: "Hello, Ada! (click 1/2/3)", clean exit.
- **Fix 1 (API drift):** Mojo 1.1 deprecated `UnsafePointer` for `Pointer`; `alloc` now takes a `Layout` and returns an owning `Allocation`. Working pattern: `alloc(Layout[App].single())` → `allocation^.unsafe_leak()` → `p.unsafe_write(App())`; free with `unsafe_deinit_pointee()` + `unsafe_free()`; rebuild from C's address with `Pointer[App, MutUntrackedOrigin](unsafe_from_address=app)`.
- **Nice surprise:** the compiler *refused* to let the allocation go out of scope unconsumed and suggested `unsafe_leak()`. Handing memory to C has to be explicit.
- **Fix 2 (linking):** Mojo stamps its runtime folder into the library's `RUNPATH`, which makes the loader ignore the executable's `rpath` for the library's own dependencies. Adding `-Xlinker -rpath -Xlinker '$ORIGIN'` to the Mojo build fixed it.
- The Mojo app library depends on exactly **one** Mojo runtime library: `libKGENCompilerRTShared.so`.

### M5 steps 1–2 · Can Mojo target iPhone? — ✅ promising, run entirely on Linux
- `mojo build tiny.mojo --target-triple arm64-apple-ios17.0 --emit object` → `Mach-O 64-bit arm64 object`, `LC_BUILD_VERSION platform ios, minos 17.0`. Same for `arm64-apple-ios17.0-simulator` → `platform iossimulator`.
- `tiny.o` (`mojo_add`) has **no undefined symbols**.
- The M0 app code compiled for iOS needs:
  - standard C: `memcpy`, `write`, `fflush`, `fdopen`, `fclose`, `dup` (all in iOS's libSystem)
  - our bridge: `mui_echo`
  - Mojo runtime: **only** `KGEN_CompilerRT_AlignedAlloc` and `KGEN_CompilerRT_AlignedFree`
- From x86 call sites: `AlignedAlloc(align, size)`, `AlignedFree(ptr)`.
- `spike/kgen_shim.c` implements both with `posix_memalign` / `free` (10 lines).
- Linked the Linux build of the same app **statically with no Mojo runtime**: only `libc` remains. Ran correctly. Clean under AddressSanitizer + UBSan. Binary size: **25 KB**.

### What it means
- The Flutter-style plan is real at this scale: Mojo produces proper iOS objects, and a small app needs almost nothing from Mojo's runtime.
- Not yet proven: linking and running inside an actual Xcode app on a simulator or phone (M5 steps 3–4 need a Mac), and how the runtime needs grow as `core/` gets bigger (lists, dicts, more strings, GPU).
- The stand-in is unofficial; signatures were inferred and could change between Mojo releases.

### Next small steps (pick one, no rush)
- **M1:** write the real `core/` (`State`, `update`, `view`, `ViewTree`) with tests, then re-run `llvm-nm -u` on its iOS object to see if the runtime list grows.
- **M5 step 3** (when on a Mac): drop `app-ios.o` + `kgen_shim.c` into a blank Xcode app and call it from Swift.
