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

## Goal 2: declarative UI (2026-10-15)
- Probe: `struct View` holding `List[View]` → "field 'children' has non-'Deinitable' type"; `ImplicitlyDestructible` trait doesn't exist in 1.1. → flat node list (D-14).
- GTK 4.22.4 + libadwaita 1.9.3 installed; Wayland session available, `grim` for screenshots.
- `App` trait needed `Deinitable` for `Runtime[A]` to hold an `A` ("non-'Deinitable' type 'A'").
- GTK host built; borrow checker caught `ref node` held across recursive `build()` that mutates self → copy the node first.
- First GTK run: real buttons tapped, real label "Hello, Ada! (click 3)". Screenshot: button stretched full width → centre VStack children (native stacks do).
- AppKit and UIKit hosts compiled first try. New needs: `_bzero`, `KGEN_CompilerRT_fprintf(i64 stream, ptr fmt, ...)` (assert-failure path) → stand-in.
- Todo example: 3 adds + remove → rebuilds; GTK labels Task 1, Task 3, "2 tasks". Checker 7/7.
- Re-review (goal 2): PASS. Fixed leftovers: untracked __pycache__, comment on the iOS height limit, oversized screens now show a 'Too many items' label instead of leaving stale controls.

## Goal 3: web, components, todo, Android, GPU (2026-10-15, owner asleep)
- Mojo Python module (`PythonModuleBuilder`, `PyInit_mojoui_app`) built from the unchanged hello app: Python got the same patches the native hosts get. First try.
- chrome-devtools-axi wants Google Chrome at /opt/google; only /usr/bin/chromium here → Playwright (`pixi add --pypi playwright`) with `executable_path=/usr/bin/chromium`, headless. Clicked Greet 3x → "Hello, Ada! (click 3)".
- Events with values (`Event(message, text, number)`) + 7 components: 14 core tests pass first try.
- GTK: `g_signal_connect_data` needed two callback signatures → `ccall()` looks C functions up with dlsym and casts per call (same trick as objc msg).
- Bug: after Reset, typing stopped reaching update(). Trace: the field's own "changed" signal fired re-entrantly while `apply()` ran, and `self.updating = True` wasn't visible to it (Mojo `mut self` is exclusive; the store can be optimised away). Fix: busy flag kept on the GApplication via g_object_set_data (opaque C calls), checked before handlers touch the host.
- Web components: plain HTML controls + HTMX; text field inside a tiny form so Return submits with no custom JS. Playwright `has_text` regex failed on pretty-printed label HTML → match the label's <span>.
- AppKit + UIKit hosts for every component compile; only Apple system functions. iOS dropdown = UIButton menu (showsMenuAsPrimaryAction + changesSelectionAsPrimaryAction) whose UIActions call a hand-built global Objective-C block (Mojo invoke function); identifier "<tag>:<index>".
- Todo app: same 10 steps in GTK and Chromium → identical state reports.
- GTK CRITICAL g_object_notify_by_pspec: rebuilding inside the dropdown's own notify handler destroyed it mid-signal → rebuilds deferred to g_idle_add; test steps run pending GTK work between steps. Screenshot after a deferred rebuild was empty → wait ~300 ms of real frames.
- GPU: plain `mojo` ships only std; `pixi add --pypi max` (26.6) gives `max.gpu` + `layout`. Modular's Mandelbrot example ran on the RTX 3090 first try.
- Generic per-pixel kernel: kernel params must be `thin` functions; `Int` isn't DevicePassable → Int32 sizes. 480×320 in ~0.1 ms, identical to CPU.
- First fractal was all black: the camera glided through the set's interior → fixed centre on a spiral. GtkPicture grew past its pixels → content-fit scale-down + centre.
- Review (goal 3, round 1): NEEDS WORK — web lost a task on instant Return (reproduced by reviewer), CDN JS, .sesskey committed, checker weaker than goal 2's, etc. All fixed (D-34, D-35); new `enter:` step reproduces the race; harsher todo run identical on GTK and web.
- htmx inherits hx-vals from ancestors: the field's input inherited the form's second=1 → typing = submit. M6 still passed because the shape-version check rejected the duplicate; added a draft-only final step so M6 catches it too.
- GPU memory per web tab measured with nvidia-smi: 512 MiB at 1, 2, 5 and 10 sessions → MAX shares one CUDA context per process; no per-tab cost.

## Goal 4: components real apps need + Pocket Expenses (2026-10-15)
- Mojo traits support default method bodies → `App.row(list_id, index)` with a default; apps without lists don't change.
- GTK: AdwToggleGroup (libadwaita 1.9) for segmented + tabs, AdwAlertDialog, GtkCalendar, GtkListView with a signal factory (row text asked for in `bind`). 10,000-row list built 205 row widgets.
- Bug: GtkTextIter buffers freed before GTK wrote them (Mojo frees after last use; Int(ptr) isn't a use) → keep alive explicitly. Logged in docs/lessons.md.
- Bug: `gtk_label_new(0)` vs `gtk_label_new(string)` → Mojo "conflicting signature" for one C symbol.
- Web: JS regex with `\n` inside a Python string became a real newline; switched to char codes.
- Web bug: list rows inherited the list's hx-target, failed to find it, and htmx silently sent nothing. Second inheritance bug → disableInheritance globally (D-42).
- Web bug (caught by M1): all radio groups shared name="number" → one browser group; each group now named, choice sent in hx-vals (D-43).
- AppKit/UIKit: NSSegmentedControl/UISegmentedControl, NSTableView/UITableView data sources (methods added to our runtime classes), NSAlert runModal on the next run-loop turn, UIAlertController actions with a data-carrying block (tag after the block header), SF Symbols, NSDatePicker/UIDatePicker via NSDateComponents.
- Pocket Expenses: GTK and Chromium identical over 12 steps; checker 11/11.
- Review round 2 (goal 4): the GTK items_changed refresh was a no-op (reviewer probe); fresh model + Bump-row proof on both hosts. Web alert → overlay + inert page. LISTROW needed unbind tracking tied to the item (old row 0 unbinds after the new one binds).

## Goal 5: layout as a thin layer (2026-10-15)
- Web: settings → CSS flexbox one-to-one; every relation held on the first run (border-box sizing).
- GTK: CSS padding classes (one provider), size requests (they include padding: border-box holds), AdwClamp for max width, halign/valign + expand for align/fill/grow, invisible expanding spacers for justify. All relations held on the first measured run (gtk_widget_compute_bounds).
- Looking at screenshots found three mapping gaps the relation checks didn't: web grow from content width wrapped the todo row (→ flex 1 1 0); web Scroll was a row (→ column); GTK fixed width is only a minimum (→ AdwClamp at the fixed width) and wrapping labels asked for minimal width (→ natural wrap mode none).
- A GTK test window shown for a screenshot caught the owner's real keystrokes ("td" in the field) → test windows ignore real input.
- Apple: NSStackView edge insets / UIStackView layout margins for padding, distribution equal-spacing for BETWEEN, flexible spacers for START/CENTER/END, hugging priority for grow, constraints for sizes/fill. Builds and signs; not run.

## Goal 6: GPU Data Lens (2026-10-15)
- Probe: Mojo 1.1 has no wasm target ("No available targets are compatible with triple wasm32-*"); a trivial export's LLVM IR retargets with system `llc -mtriple=wasm32` after stripping target attributes. Parked for a later goal.
- Probe: `from std.atomic import Atomic, Ordering` (not std.os.atomic). 20M points binned into 1920×1080 with relaxed atomics: 2.4 ms on the RTX 3090.
- Probe: `max.gpu` imports compile for arm64-apple-macosx/ios; guarding the GPU calls with `comptime if CompilationTarget.is_linux()` removes every AsyncRT symbol from the iOS object (is_macos() alone left them in iOS).
- `comptime` List tables can't be indexed at run time ("cannot materialize… not ImplicitlyCopyable") → `materialize[HUBS]()` once, passed in.
- PointCloud: grid-stride bin kernel (one thread many points, totals added once per thread) + per-pixel shade + one copy into the host surface: 1.48 ms per 1080p frame for 20M points, pixel-identical to the CPU path (130 ms).
- GTK canvas: GtkPicture (can-shrink, content-fit fill) + GdkMemoryTexture per draw, tick callback per canvas; the first draw happened before Hyprland tiled the window, so "drawn" now also means "at the current size".
- Empty MOJOUI_TEST with a screenshot didn't report (empty = unset) → test mode is "MOJOUI_TEST is set".
- GTK playing: 180 frames in 3048 ms = 59.0 fps, every frame redrawn (60 Hz display, 1123×1402 px canvas).
- Web: the driver's readiness probe fetched "/", and every retry started a 20M-point session (3.3 s, ~640 MB each) → the server drowned. The probe now fetches a static file.
- `pkill -f <pattern>` inside a Bash tool command kills the tool's own shell (the pattern is in its command line): use `ps | grep "[w]eb.py"` instead.
- Web frames: 6.6 ms server-side at 1280×800 (draw + JPEG). First measurement 18.8 fps: the loop awaited the side-panel refresh. Measured properly (per-frame intervals): one 371 ms gap as Play starts (click → event → first pull), then 7–10 ms per frame; unpaced, the browser pulled 145 fps, more than any screen shows. Now: side-panel refreshes go alongside (≤ 10/s, always a last one), frames are paced by requestAnimationFrame, the driver skips 10 warm-up frames → 59.9 fps steady.
- Apple: a struct of two doubles returned through `msg[CGPoint]` is read from d0/d1 after the objc_msgSend call (arm64 disassembly: `blr x19; fmadd d0, d0, d2, d1`), matching Apple's CGPoint ABI; CGRect is the same rule with d0–d3.
- AppKit's build() has stacks in its final `else:`, so a new kind's branch must go before it (first attempt: "unexpected token" on the elif after else).
- Lens for Mac/iPhone: new undefined symbols were only libSystem's sin, cos, __sincos_stret (trip generator) and clock_gettime_nsec_np (frame timing); added to the stubs + allowlist (D-61). No AsyncRT/MAX symbols: the GPU path compiles out.
- Review round 1 (NEEDS WORK, 1 must-fix): a 409 carrying pending changes was ignored by the canvas adapter, and the server kept sending frame events while a rebuild waited. Fixed both. New guard test (`tests/frame_rebuild`, in M6): frames keep coming after a frame-driven rebuild. Honest note: the old code also passed it, because the throttled side-panel refresh (added for the fps fix) happened to deliver the rebuild; the freeze needed timing the test can't force.
- Also from the review: pending patches cleared on every rebuild sent; GTK touchpad scroll is in pixels (gtk_event_controller_scroll_get_unit), now 100 px = 2×; idle canvases stop ticking (GTK tick callbacks removed when idle and re-armed by patches/window resizes; Apple display links paused and woken by patches and size notifications); iPhone pan limited to one finger; GPU failures are printed and switch the cloud to the CPU; GPU buffers grow together and are reused (no reallocation per filter change); grid size no longer the 3090's SM count; CGImageCreate's bool/int32 stack arguments at their natural sizes; README claims qualified.
- Full check after round 1: M2 failed twice over. (a) Real bug from the idle change: Hyprland resized the window after the first draw and nothing re-armed the canvas (GTK4 doesn't update default-width on compositor resizes) → listen to the GdkSurface "layout" signal, and stop ticking only after 3 idle ticks (layout runs after tick callbacks in a frame). (b) Environment: the desktop now tiled the test window into a 661-pt slot (canvas 321 pt < 400) → GTK test windows are non-resizable at the app's own size (Hyprland floats them), so measurements don't depend on the desktop.
- Review round 2 (NEEDS WORK): the guard test couldn't fail, because every frame changed a label and the canvas version, so the throttled refresh always delivered the rebuild. Now nothing changes while playing except the frame-driven rebuild: with the JS fix removed, `wait:Replay` times out (red); with it, it passes (green). Also: events against a stale screen while a rebuild waits now get the new screen instead of acting on the wrong control; GTK re-arms on the surface's scale change and AppKit on NSWindowDidChangeBackingPropertiesNotification; iPhone canvases wake from `layoutSubviews` (calling UIImageView's own via objc_msgSendSuper) instead of orientation notifications; failed GPU uploads are printed.
- iOS objects after goal 6: still only the four KGEN runtime functions (AlignedAlloc, AlignedFree, GetStackTrace, fprintf), all defined in mojoui/hosts/mojo_rt.mojo. Review round 3: PASS. Final full check 9/9.

## Goal 7: Android (2026-10-15)
- Owner ran scripts/android_setup.sh (licences accepted by them). Installed the emulator + android-36 default x86_64 image with sdkmanager: no licence prompt appeared (covered by the accepted ones).
- avdmanager wrote the AVD under ~/.config/.android/avd (XDG); the emulator only looks in ~/.android/avd → ANDROID_AVD_HOME. `-d pixel_7` failed (no devices.xml in the image) → plain AVD + lcd settings in config.ini.
- Mojo targets x86_64-linux-android29 as well as aarch64; both libraries go in one APK.
- First run: the hello APK started ("HelloMojo: started, 5 nodes" in logcat), showed a TextView/Button screen, and 3 real `input tap`s gave "Hello, Ada! (click 3)" (uiautomator dump).
- Mojo borrow checker: passing self.canvases[k].pixels to a `mut self` method is aliasing → copy first.
- Todo first run: squeezed to 204 px and one row 1924 px tall: the root's fixed width (320) was ignored (WRAP) → root LayoutParams take the root's own size; justify gaps are 0×0 with weight 1.
- Slider: a tap on the thumb itself doesn't move it, so nudging by a few pixels never converged (73 instead of 70) → calibrate with two far-apart taps, step away from the thumb, tap the computed spot.
- Lens on Android: Mojo's perf_counter_ns() compiled to Apple's clock_gettime_nsec_np for Android too (dlopen failed) → mojoui/clock.mojo (clock_gettime on Android, -D MOJOUI_ANDROID). The compiler prints "no libcall available for fsincos" for Android targets but still emits separate sin/cos calls (harmless; the symbol check proves it).
- First full check: M6's "≥ 500 colours" was miscalibrated for 2M points on the CPU (a few dozen density levels: 39 colours) → measure painted share + gradient instead (D-70). M7: README linked docs/report.md, moved to docs/goals/06-report.md (goal 7's report restores it).
- Review round 1 (NEEDS WORK): radio/tab option ids (j+1) collided with the group's own id (findViewById matches the group first) → options use 1,000,000 + j; M5 now switches tabs for real. That exposed a bigger bug: with targetSdk 36, Android 15+ draws edge to edge, so tall centred screens put their top under the status/action bars, unreachable by touch → setFitsSystemWindows on the content view, and flexible space instead of centring gravity.
- Also from the review: JNI exceptions logged under the mojoui tag (the driver's crash scan sees them); strings cross JNI as UTF-16 (modified UTF-8 breaks emoji); cursor positions in UTF-16 units; canvases reuse one Bitmap filled straight from the pixels through a direct ByteBuffer (no colour conversion: same byte layout); a canvas keeps its gestures from scrolling parents; touch cancel handled; the host is freed in onDestroy. Freeing the app pulled in MAX's DeviceBuffer/DeviceContext release functions through PointCloud's (always empty) GPU fields → two no-op stand-ins for CPU-only builds (mojoui/hosts/no_gpu_rt.mojo), like mojo_rt.mojo.
- M5 after the edge-to-edge fix: the layout example no longer fits one screen and uiautomator reports only on-screen views → M5 measures at 300 dpi (more dp on screen); the rules are in dp, so unchanged.
