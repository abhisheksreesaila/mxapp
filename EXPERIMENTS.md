# mojo-ui experiments log

A dated record of what was tried, what happened, and what it means. Newest first.

---

## 2026-10-15 · Experiment 4: web, components, a real todo, GPU, Android (autopilot, overnight)

**Goal (owner's words):** "render the web… build all the components… a todo list… the same declarative code in Mojo runs on all of them… try Android… an app that's great on GPUs." Contract: `GOAL.md`; report: `docs/report.md`.

**What worked (`scripts/check` 9/9):**
- **Web:** FastHTML + HTMX host; the Mojo app runs inside Python as an extension module (`PythonModuleBuilder`). Plain HTML controls; htmx vendored. Tested in headless Chromium (Playwright + system Chromium).
- **Components:** `Event(message, text, number)`; TextField, Toggle, Dropdown, Slider, ProgressBar, Divider, Scroll, Image on GTK, web, AppKit and UIKit (iOS dropdown = menu button with a hand-built Objective-C block; images via a PNG encoder written in Mojo).
- **Todo app:** one `app.mojo`; the same 13 test steps on GTK and in Chromium end in identical states; builds and signs for Mac + iPhone.
- **GPU:** `mojoui/gpu.mojo` runs a plain Mojo function per pixel as a GPU kernel (MAX 26.6): 480×320 Mandelbrot on an RTX 3090 in ~0.1 ms vs ~15–80 ms CPU, pixel-identical; degrades gracefully with no GPU.
- **Android:** apps compile for aarch64-linux-android; the todo app links into a 37 KB `libmojoui.so` (NativeActivity entry, only libc + liblog).

**What broke and how it was fixed:** GTK re-entrancy vs Mojo's exclusive `mut self` (busy flag moved into GTK); rebuilding inside a signal handler (deferred to idle); web lost a task on instant Return (shared HTMX queue + submit carries the text); htmx inherits hx-vals (typing counted as Return); no-GPU crashed in DeviceContext (device count first). Details: `docs/journal.md`.

**Not verified yet:** Mac and iPhone on real hardware; Android drawing/taps (needs a decision + Google's SDK licence: `docs/android.md`).

**Next:** run on Mac/iPhone; choose the Android route.

---

## 2026-10-15 · Experiment 3: declarative Mojo UI, rendered natively (autopilot)

**Goal (owner's words):** "All I want is Mojo declarative code and then it's rendered natively on all the platforms." Contract: `GOAL.md`.

**What worked (`scripts/check` 7/7):**
- `mojoui`: `VStack`/`HStack`/`Text`/`Button`/`Spacer` build a flat node tree; `App` trait (`view()`, `update()`); a diff turns each update into in-place patches or a rebuild.
- Three native renderers from the same tree: GTK4 + libadwaita (Linux), AppKit (Mac), UIKit (iPhone). One `app.mojo` per example, importing only `mojoui`.
- **Linux runs here:** the checker taps the real GtkButtons and reads the real GtkLabels; screenshots rendered by GTK (`docs/img/`).
- Mac and iPhone: compile, link and sign from the identical app file; only Apple system functions; entry `_mojo_entry`.

**What broke and how it was fixed:** recursive `View` not allowed → flat nodes; `App` needs `Deinitable`; borrow checker caught a held reference during recursive builds; a new runtime function (`KGEN_CompilerRT_fprintf`) → Mojo stand-in. Details in `docs/journal.md`.

**Not verified yet:** running on a real Mac and iPhone.

**Next:** run on hardware; then text input, scrolling lists, images; web host.

---

## 2026-10-14 · Experiment 2: Mac and iPhone apps written only in Mojo (autopilot)

_Later moved: `apple/objc.mojo` and `apple/mojo_rt.mojo` now live in `mojoui/hosts/`; the hand-written apps were replaced by the declarative hosts (Experiment 3)._

**Goal (owner's words):** "Create a Mojo app for macOS which I can test, then do it for iOS. Mojo all the way." Contract: `GOAL.md`; decisions: `docs/decisions.md`; step-by-step: `docs/journal.md`.

**Setup:** Linux x86-64, Mojo 1.1.0 via pixi (`pixi.toml`), `ld64.lld` from conda-forge, `rcodesign`, xtool (not signed in).

**What worked (all verified on Linux by `scripts/check`, 6/6 PASS):**
- Mojo drives AppKit and UIKit directly through the Objective-C runtime: `apple/objc.mojo` casts `objc_msgSend`'s address to a typed C function per call (the same trick Mojo's own `_DLCallable` uses). Button handlers are `abi("C")` Mojo functions added as methods to classes created at run time.
- No Swift, C or Objective-C anywhere in `apple/`. Entry point via the linker's `-e _mojo_entry`; the three Mojo runtime functions are written in Mojo (`apple/mojo_rt.mojo`), so no Modular runtime library ships.
- Linked on Linux with `ld64.lld` + `.tbd` stubs (`apple/sdk/`). Mac app ≈ 70 KB, loads only AppKit, libobjc, libSystem; iPhone app loads only UIKit, libobjc, libSystem.
- Machine code checked: rects travel in d0–d3 like Apple's NSRect-by-value; no x18, no thread-locals, no static initialisers.
- Ad-hoc signatures verified by our own hash checker (`scripts/verify_signature.py`), since `rcodesign verify` fails on ad-hoc signatures.

**What broke and how it was fixed:** see `docs/journal.md` (runtime functions must be in their own Mojo file; `@export("main")` is refused; printing floats pulls in `KGEN_CompilerRT_fprintf`; linker's own signature left stray bytes).

**Not verified yet:** running either app. Needs the owner's Apple Silicon Mac (copy `build/mac/HelloMojo-mac.zip`) and iPhone (`apple/install_iphone.sh`). See `apple/README.md`.

**Next:** run both on real hardware and record the result here.

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
