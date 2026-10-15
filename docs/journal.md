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
