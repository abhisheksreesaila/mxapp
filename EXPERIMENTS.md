# mojo-ui experiments log

A dated record of what was tried, what happened, and what it means. Newest first.

---

## 2026-10-17 · Experiment 14: omxplorer, the data app from scratch (autopilot, night)

**Goal (owner's words):** "I should be able to install this Linux app, load some data from CSV… use it from scratch"; "follow [Stitch], the classic design"; "this product will be called [omxplorer]… all small case"; "load one million… then try 10, 50, 100 million". Contract: `docs/goals/14-omxplorer.md` once archived. Report: `docs/report.md`.

**What worked:**
- **The flow:** omxplorer (`examples/omxplorer`) goes Start → choose a CSV → review its columns → a Numbers-classic sheet. The sheet has a toolbar, sheet tabs, formula bar, grid, format inspector and status bar. Formats are currency, percent, compact and dates, with decimals, separators and negatives. You can add formula columns and rows, sort, and save and open `.omx` files (one Parquet file).
- **New omxapp components:** TOOL buttons, FilePicker, Inspector, sheet chrome, number formats, the CSV reader, `.omx` files and `mojoui.files`.
- **Scale:** 100M rows: import 106 s on a loaded machine, sort 3.7 s, format change 54 ms, GPU sum 19 ms.

**What broke and how it was fixed:**
- **Mojo 1.1 gaps:** there's no `memcpy` (libc's is used), and its `mkdir` declaration clashes with the stdlib's (`std.os.makedirs` is used).
- **Layout:** a `Board` needs its own height, or the grid doesn't show.
- **A formula column's GPU sum read garbage** until `Frame.flatten` inlined formulas into stored-column steps.
- **Memory at 50M+ rows:** custom date parsers and numpy temporaries thrashed memory (the owner's other work had 32 GB in swap). The fix: default parsers, Arrow kernels, and one column at a time.
- **Three review rounds** made weak checks real and validated `.omx` files before they reach memory. They also fixed averages, formatting edges, upload and dialog hygiene, and a failed open that left the sheet on freed memory.
- **A stuck System UI dialog on the emulator** is now closed by the Android driver.

**What it means:** the component library carries a real product. The app is wiring, and the next screens (charts, pivots, Report) reuse what's there.

**Next:** goal 15. Insert a chart and a pivot onto the sheet (Stitch 05), and build a Report page from scratch (Stitch 06).

---

## 2026-10-16 · Experiments 11–13: MX Studio's Sheet and Report, and spreadsheet keys (autopilot, night)

**Goal (owner's words):** "the killer app is the data transformation app… primarily focused on Linux and Web"; "ask yourself, okay, what component do I need, then build the component… then go back and build the app"; "go for it and make me proud". Contracts: `docs/goals/11-mxstudio-sheet.md`, `12-mxstudio-report.md`, `GOAL.md` (13). Reports: `docs/goals/11-report.md`, `12-report.md`, `docs/report.md`.

**What worked:**
- **Goal 11, MX Studio's Sheet:** a 2M-row planted ledger. DataGrid, PivotTable and ChartView came out of the Workbook into `mojoui/`. A finding merges three spellings of Acme in one undoable step.
- **Goal 12, the Report:** KpiView, FindingCard, line markers and Heatmap. A GPU anomaly finder (heavy parcels in the West lost 7.66 margin points after Jul 14, Carrier A's freight to $14.20) checked against the CPU. One engine with the Sheet: merges reach the Report, and "Open the rows" filters the Sheet.
- **Goal 13, keys:** `KEY` events on any `Canvas(keys=True)`, `TextField(on_cancel=)`, `.echo()`, and DataGrid's Excel keyboard. It runs on both apps and both hosts. Fast data entry works even against a slow server.

**What broke and how it was fixed:**
- **Goal 12's regressions:** MX Studio's local imports broke goal 3's purity rule (they moved into mojoui), and with no theme file the accent wasn't Tokyo Night's.
- **Goal 13's review, five rounds:** the typed text lived in two places and keys raced between them. The fix gave the grid sole ownership (D-132), plus a page-wide event queue on the web.
- **Checks that couldn't fail:** a slow test server and real GTK focus on the private display made them able to fail.
- **A worktree's own Android debug key:** the emulator refused its APKs, so the worktree uses the main checkout's key.
- **Process mistakes, both now in `docs/lessons.md`:** running an archived checker directly, and `pgrep -f` killing my own shell (now `scripts/stop-check`).

**What it means:** the component library carries the apps. The grid, its keyboard, KPIs, findings and charts are framework pieces with their own tests, and both apps are mostly wiring. Everything MX Studio still needs that isn't in MX frame is listed in `docs/plans/needs-mxframe.md`.

**Next:** MX Studio's Explore and Query (they need MX frame's Mojo API), cell formatting (`docs/plans/formatting.md`), or keys and the new components on Android.

---

## 2026-10-16 · Experiment 10: the Workbook (autopilot, overnight)

**Goal (owner's words):** "a spreadsheet where you can edit rows… but also a report and a dashboard built on the same engine"; Numbers-style, "you can place tables and you can place charts, everything is free flowing"; columns instead of Excel's cells, on purpose. Contract `GOAL.md`, report `docs/report.md`, walkthrough `docs/morning.md`.

**What worked:** `mojoui/frame.mojo` (typed columns shared per process, a session's edits as a sparse overlay, formula columns compiled to a small bytecode with a column-level dependency graph, tombstones, sort permutations, undo); `mojoui/frame_gpu.mojo` (group-bys whose key, value and filters are chosen at run time, 0.8–1.9 ms on 20M rows, exact; pivots; edits applied as deltas); the Workbook app (`examples/workbook`): a table grid over 20M rows, a pivot, two Flint charts with crossfiltering, a note, all on a `Board` (a new container: absolute positions, drag by the header, resize by the corner, snap to 8 pt; a list on narrow windows), identical on GTK and the web; workbook files (JSON + Parquet); `App.init_shared()` so every web tab shares one GPU copy of the rows (the analytics app too). The wasm spike: Mojo's LLVM IR retargeted to wasm64 plus a 25-line C shim runs List/String/print code in Chromium (`docs/wasm.md`).

**What broke and how it was fixed:** a `SIMD` vector used as an interpreter stack segfaults the compiler (stack_allocation instead); the first GPU interpreter took 23 ms (a row vector in local memory) until columns were read directly and the stack moved to registers; GTK test taps landed on a 0×0 canvas before the first layout (the steps now wait for layout and the first draw); Mojo has no global variables (the shared registry lives in the process environment); a struct holding a Frame can't be partly moved (out-parameters). See `docs/journal.md`.

**Next:** the MX frame Mojo API (`docs/mxframe-mojo-api.md`, items 13–22) so the workbook runs on the Mac; a real allocator for wasm and a client-side host; AI column types; the drag-and-drop chart editor.

---

## 2026-10-15 · Experiment 9: the analytics showcase (autopilot)

**Goal (owner's words):** "the analytics part… the poster child… really polished"; Flint as the common chart language; MX frame; a gallery on GitHub. Contract `GOAL.md`, report `docs/report.md`.

**What worked:** Contoso Retail (`examples/analytics`): 20M rows re-aggregated per click (GPU 5.9 ms, MX frame 114 ms, CPU loops 746 ms; equal to the cent); charts declared as Flint specs, drawn natively by mojoui and also valid through Flint → Vega-Lite → SVG; crossfiltering by tapping charts, identical on GTK and the web; Fluent 2 controls; fits 1440×900 and 1280×800. New in mojoui: canvas text (baked Noto Sans), drawing + charts, Flint specs, exact GPU group-by, an MX frame engine. Gallery page; MX frame Mojo API spec.

**What broke and how it was fixed:** misread Flint as Fluent (corrected, D-76); GPU atomics contention (shared-memory totals); GTK picture natural size; dark-theme cards; hinted glyph advances; cents in Flint's chart. See `docs/journal.md`.

**Next:** Flint island on the web; Mac after the MX frame Mojo API; notebook editor; Ask your data.

---

## 2026-10-15 · Experiment 8: Android (autopilot)

**Goal (owner's words):** "one code compile and you get for everything"; the Java listener approved; SDK installed and licences accepted by the owner. Contract `GOAL.md`, report `docs/report.md`.

**What worked:** Mojo drives Android's own views through JNI (function-table slots from jni.h); one 78-line framework Java file; signed APKs for arm64 phones and x86_64 emulators. On the Android 16 emulator, with real input: hello, gallery and todo end in the same state as GTK; goal 5's layout rules hold; the Data Lens runs (CPU, 2M trips) and a real swipe pans it like GTK.

**What broke and how it was fixed:** the root's fixed width; slider taps on the thumb; Apple-only clock symbol; option-id collisions; edge-to-edge drawing on Android 15+; MAX release functions pulled in by freeing the app. See `docs/journal.md`.

**Next:** a real phone; goal-4 components on Android; MX frame.

---

## 2026-10-15 · Experiment 7: GPU Data Lens (autopilot)

**Goal (owner's words):** "a real fancy app which takes advantage of GPUs… same code base which builds a web and a Linux and later a Mac app." Contract `GOAL.md`, report `docs/report.md`.

**What worked:** a Canvas view (the app paints it in `draw()`, gestures and per-frame events come back as events) on GTK, web, AppKit and UIKit; `mojoui.gpu.PointCloud` bins 20M points into a 1080p frame in 1.48 ms on the RTX 3090 (CPU 132 ms, identical pixels); Data Lens runs at 59.2 fps on GTK and streams at 59.9 fps to Chromium; Mac/iPhone build and sign on the CPU path (not run).

**What broke and how it was fixed:** web readiness probe started 20M-point sessions; web fps measured through a start-up gap and unpaced pulls; GTK first draw before the window manager tiled the window; empty test steps didn't report; the lens imported std.math (now `mojoui.maths`). Probes: no wasm target in Mojo 1.1; `std.atomic`; Apple GPU code compiles out; CGPoint returns in d0/d1. See `docs/journal.md`.

**Next:** MX frame columns into PointCloud; galaxy/deep-zoom showcases; Android (Java shim, after the owner accepts Google's SDK licence); Apple GPU.

---

## 2026-10-15 · Experiment 6: layout as a thin layer (autopilot)

**Goal:** flexbox-named layout settings mapped onto each platform's own layout (ROADMAP decision 10). Contract `GOAL.md`, report `docs/report.md`.

**What worked (`scripts/check` 11/11):** padding, width/height, min/max width, grow, fill, align and justify on every view, measured on GTK and in Chromium (same geometric relations within 1.5 pt). Pocket Expenses and todo use them; field and list widths measured equal to their columns. Apple: NSStackView/UIStackView + Auto Layout (builds and signs; not run).

**What broke and how it was fixed:** web grow wrapped rows; web Scroll was a row; GTK fixed width was only a minimum (AdwClamp); wrapping labels squeezed; built-in control widths fought app layout on every host (now preferences that yield, direction-aware); a test window caught the owner's keystrokes (test windows ignore input). See `docs/journal.md`.

**Next:** the owner's Apple results; Android route.

---

## 2026-10-15 · Experiment 5: components real apps need + Pocket Expenses (autopilot)

**Goal (owner's words):** "continue with 2–4, 8, then … until 9 … and build a fancier app for all platforms." Contract: `GOAL.md`; report: `docs/report.md`.

**What worked (`scripts/check` 11/11):** Segmented, Radio, TextArea, Alert, Tabs, NavBar, DatePicker, Icon, Grid and LazyList, on GTK, web, AppKit and UIKit (Apple ones build and sign; not run on hardware). Kitchen-sink and Pocket Expenses examples are identical on GTK and in Chromium. A 10,000-row list keeps 30 rows in the web page.

**What broke and how it was fixed:** Mojo frees buffers after their last use (GtkTextIter); htmx attribute inheritance (twice); same-named radio groups; GTK `items_changed` refresh ignored; GTK alert Escape; web alert keyboard. See `docs/journal.md`, `docs/lessons.md`.

**Next:** the owner's Apple results; bottom tab bar and push navigation on iPhone; controls inside list rows.

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
