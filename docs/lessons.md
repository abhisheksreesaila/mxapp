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
- 2026-10-18 · Checks proved state, never looks: the GTK Format menu's submenu rows had button chrome and a bigger font for weeks. Compare every changed screen against its design image side by side (open:/pause: test steps + a display grab catch popovers).
- 2026-10-19 · A new message constant fell inside another's range (COPY = 41 inside RECENT 40–49): Copy silently did nothing. Before picking a message number, grep the app's `m >= X and m < X + n` ranges.
- 2026-10-19 · A view whose number of children depends on the selection (status items, inspector controls) rebuilds the whole screen on every move, restarting canvases and animations: keep fixed slots (StatusBar's 8).
- 2026-10-19 · A test-only probe must fail when the thing never stops: GLIDE first passed on a 2 s timeout; it now reports "settled".
- 2026-10-19 · (encoded) The "a changing child count rebuilds the whole screen" lesson came back a second time (a drag died when the inspector changed): it is now structure, not a rule: the diff keeps every widget it can (tests/test_diff_keep.mojo, goal 25 M1 counts full rebuilds).
- 2026-10-19 · Test steps call the host's handlers directly, so they never saw a rebuild kill a GTK drag in progress. Anything gesture-shaped is proven with real input too (scripts/live.py: XTest on the headless display, `report` prints the state).
- 2026-10-19 · Every check ran at 1440×900, the size the layout's constants were made for, and passed while the owner's 1742×876 window lost its status bar. Layout checks run at several window sizes (goal 25 M2: three).
- 2026-10-19 · Count bytes with code, not by hand: " · " is 4 bytes in UTF-8 and a hard-coded 5 ate the first digit of "5,000 of 5,000 rows".
- 2026-10-19 · A new view passed its own check ("the logo is there") while it broke the layout around it (a 100 px SVG stretched the web's menu bar under the toolbar; only goal 24's regression run caught it). A check for something added to a bar also checks it fits the bar.
- 2026-10-19 · Moving a style sheet "verbatim" moves its unscoped rules too: before splitting CSS by owner, list every rule that isn't under the owner's class (they were global), and prove the move with before/after pixels of every screen, run twice for the noise (goal 27 M3 caught the toolbar).
