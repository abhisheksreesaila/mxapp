# CLAUDE.md — briefing for Claude Code

Mode: experiment
Ship: direct

Current experiment: `GOAL.md` (goal 3: web, components, todo, GPU, Android; goals 1–2 in `docs/goals/`). Check with `scripts/check`; decisions in `docs/decisions.md`, attempts in `docs/journal.md`.

You are helping build **mojo-ui**: a long-term, experimental side project to write apps once in **Mojo** and run them natively on Linux, Mac, iPhone and the web. The owner is an app developer (Python/FastHTML background), not a systems programmer. They want to develop this **slowly and organically**: one small, verified step per session.

## Read first, in this order
1. `ROADMAP.md`: the vision, why Mojo, decisions 1–8, the two tracks.
2. `SPEC.md`: the technical spec and milestones (M0–M5) with acceptance checks.
3. `EXPERIMENTS.md`: what has actually been tried and what happened. **Trust this over the spec when they disagree.**

## Where things stand
- **Newest (Experiment 4, 2026-10-15):** web host (FastHTML), all common components, a real todo app, a GPU example, Android exploration. Linux + web run and are tested here; see `docs/report.md`.
- **Experiment 3 (2026-10-15):** declarative UI. Apps are `examples/<name>/app.mojo` (`view()`/`update()`), drawn natively by `mojoui/hosts/` (GTK, AppKit, UIKit). Build with `scripts/build.sh <name> all`. Linux runs and is tested here; Mac/iPhone build and sign but haven't run on hardware yet.
- **Done:** M0 (Mojo ↔ C both directions, Mojo keeps state across calls from C) and M5 steps 1–2 (Mojo compiles to iPhone objects; the app needs only two Mojo runtime functions, covered by `spike/kgen_shim.c`).
- **Next, main track (Linux):** M1, the real `core/` (`State`, `Msg`, `update`, `view`, `ViewTree`) with tests. See SPEC §5 and §9.
- **Next, side track (iPhone):** M5 step 3 via xtool, using `ios-xtool/`. Needs the owner's machine, an iPhone, and Xcode.xip downloaded from Apple. See `ios-xtool/README.md`.

## How to work
- **One milestone (or less) per session.** Stop when its acceptance checks pass, show the result, and ask before starting the next.
- **Verify by running, not by reasoning.** Build it, run it, show the output (or a screenshot for UI).
- **Log every session** at the top of `EXPERIMENTS.md`: date, setup, what worked, what broke and how it was fixed, what it means, next small step.
- **Explain plainly.** Short sentences, no unexplained jargon. When there are trade-offs, list the cons.
- **Keep the repo honest:** mark anything unverified as unverified.

## Mojo rules that bite (verified on Mojo 1.1.0)
- Install: `pixi install` (this repo's `pixi.toml` pins Mojo 1.1); run with `pixi run mojo …`.
- `def` only (`fn` is deprecated); no `@value` (use `@fieldwise_init` + explicit traits).
- Imports use `std.`: `from std.ffi import external_call`, `from std.memory import Pointer`, `from std.memory.alloc import alloc, Layout`.
- `UnsafePointer` is deprecated: use `Pointer`. Heap state handed to C: `alloc(Layout[T].single())` → `allocation^.unsafe_leak()` → `p.unsafe_write(...)`; back from an address with `Pointer[T, MutUntrackedOrigin](unsafe_from_address=addr)`; free with `unsafe_deinit_pointee()` + `unsafe_free()`.
- FFI: scalars and `(ptr, len)` strings only (`s.unsafe_ptr()`, `s.byte_length()`); never structs by value. Exports use `@export` + `abi("C")` and cannot `raise`.
- Linking a Mojo shared library: add `-Xlinker -rpath -Xlinker '$ORIGIN'` (Mojo sets its own RUNPATH).
- Inspect Mach-O (iOS) objects on Linux with `llvm-nm` / `llvm-objdump`, not GNU `nm`.
- The compiler tries to reach `telemetry.modular.com`; in a sandbox that warning is harmless.
- When unsure of an API, fetch the docs as Markdown: append `.md` to any `mojolang.org/docs/...` URL, or start from `https://mojolang.org/llms.txt`. Don't guess.

## Guardrails
- `spike/kgen_shim.c` is an **unofficial** stand-in for two Mojo runtime functions; signatures were inferred from compiled code. Keep it in `spike/`, labelled. After any change to Mojo code destined for iOS, re-run `llvm-nm -u` and record new `KGEN_*` symbols in `EXPERIMENTS.md`.
- Don't patch the Mojo compiler or rewrite Mach-O platform tags. If blocked, record the blocker and stop; the owner decides.
- Experiment mode: commit after each passing milestone; never push.

## Repo map
```
CLAUDE.md          this briefing
ROADMAP.md         vision, decisions, tracks, risks
SPEC.md            technical spec + milestones
EXPERIMENTS.md     dated log of real results
app_entry.mojo     M0: Mojo app exported to C (init/event/quit), keeps state
m0_call_c.mojo     M0: Mojo calling C
bridge/            C side: mojoui_bridge.c (bridge), host_main.c (C shell driving Mojo)
spike/             iOS spike: tiny.mojo, kgen_shim.c (runtime stand-in)
scripts/m0_linux.sh  reproduces Experiment 1 end to end on Linux
mojoui/            the framework: view.mojo (components), diff.mojo, app.mojo (App, Event, Runtime), gpu.mojo, png.mojo, hosts/ (gtk, web.mojo+web.py, appkit, uikit, objc, mojo_rt)
hosts/             entry points per platform (import your app.mojo)
examples/          hello/, gallery/, todo/, gpu/: one app.mojo each (optional `platforms` file)
scripts/build.sh   build an example for linux|web|mac|ios|android|all
scripts/drive.py   drives the web app in headless Chromium with the GTK test-mode steps
apple/             Info.plists, sdk/ (.tbd stubs), install_iphone.sh, README
GOAL.md            current experiment contract; scripts/check proves it; docs/decisions.md, docs/journal.md
ios-xtool/         superseded: earlier SwiftUI skin + prebuilt Mojo iPhone library
docs/              visual guide (open visual-guide.html in a browser)
```
M1 onwards follows the layout in SPEC §3 (`core/`, `hosts/native/`, `hosts/web/`, `tests/`); move the M0 files into it when convenient.
