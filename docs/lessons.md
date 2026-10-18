# Lessons

One line per rule that prevents a mistake that happened.

- Mojo frees a value right after its last use, and `Int(x.unsafe_ptr())` doesn't count as a use: keep buffers you hand to C alive past the C call (e.g. `_ = len(buf)` afterwards).
- Mojo rejects one C function declared with two signatures in a module (even `0` vs a string pointer): pass the same types everywhere, or look the function up with dlsym and cast (`ccall`, `msg`).
- Callbacks from GTK/AppKit can re-enter while a `mut self` method runs; never rely on a Mojo field to block them (keep the flag in the toolkit, or defer work to the next main-loop turn).
- htmx inherits hx-* attributes from ancestors (bit us twice: hx-vals, hx-target). `disableInheritance` (on in mojoui/hosts/web.py) stops most of it, but **hx-vals is still merged from ancestors**: every element must set every hx-vals key it relies on itself.
- A GTK drag gesture reports coordinates relative to the widget it's attached to: never attach it to the widget it moves (jitter); attach it to the container and hit-test.
- Under htmx with `swap: 'none'`, a `<script>` in the response is not executed: send a hidden element with data attributes and let the page's adapter apply it.
- Never sort 20M rows with a comparison sort keyed on a few distinct values (quadratic): gather the column and radix-sort it.
- On GTK a `Spacer()` inside a card header expands vertically too and starves the card's canvas: push header items apart with `.justify(BETWEEN)`.
- GTK test windows go on the headless display (`scripts/headless.py`), never the desktop; a window covered by another gets no frame-clock ticks, so fps checks on a real screen are unreliable.
- Never run benchmarks or rebuild one platform of an example while a regression check runs: GPU timings pick up the extra load and the "built from the same app.mojo" check fails when only Linux was rebuilt.
- Look at every screenshot a check takes: a missing glyph (▲/▼ drew as a box) and a page wider than a 1280-pt window both passed the state checks.

- `Int(X)` of a comptime float constant (`comptime ROW_H = 26.0`) fails to compile ("the SIMD type must be floating point"): keep an Int constant beside it, or convert through `Float64(X)`.
- Never edit source while a full check runs: it rebuilds from the working tree, so half-written code turns into false failures (goal 11's first full run).
- Archived checkers (docs/goals/NN-check.py) ignore milestone arguments, rebuild everything and don't start the headless display: call their functions from a script that runs headless.ensure() first, never the file directly.
- To stop a check use scripts/stop-check (by argv and directory); never pkill -f / pgrep -f on its command line: it matched and killed my own shell twice.
- On the Android emulator, heavy load can leave a "System UI isn't responding" dialog over the app ("no Button #0"): scripts/android_drive.py closes system dialogs before each launch.
- 2026-10-18 · A stopped `scripts/check` leaves its Xvfb display running (`scripts/stop-check` ends only check.py); two orphaned displays made the next runs' headless Chromium fail with ERR_INSUFFICIENT_RESOURCES / "Target crashed" in earlier goals' web steps. After stopping a check, list `Xvfb :9N` processes whose cwd is this checkout and stop them by PID before rerunning.
- GTK and web test runs print only the last screen's labels: check a state that lasts (a button's title), not a message a later step replaces.
