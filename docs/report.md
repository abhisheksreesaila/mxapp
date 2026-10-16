# Goal 9 report: the Workbook

**End goal (owner's words):** "a spreadsheet where you can edit rows… but you can also create a report and a dashboard built on the same engine"; Numbers-style free-flow objects; columns, never cell addresses; packaged for the morning.

## How far it got
Full run (before the review fixes, machine under a load average of ~23 from other projects' processes):
```
PASS  M1  typed columns, formulas with a dependency graph, edits, tombstones, sort permutation, undo
PASS  M2  20,000,000 rows: GPU = CPU on 262 numbers, ≤ 1.900826 ms, patch + pivot, on NVIDIA GeForce RTX 3090
PASS  M3  table, pivot, chart and note objects; edits, pivots, crossfilter and formulas identical on GTK and web
PASS  M4  Board: absolute positions, drag + snap identical on GTK and web; narrow windows show a list
PASS  M5  save → open round-trips tables, formulas, pivots, charts, notes and layout
PASS  M6  packaged Linux app + web, launcher, morning walkthrough, gallery and README updated
FAIL  M7  check crashed: TimeoutExpired(['…/build/lens/linux/lens'], 120)
PASS  M8  20M rows loaded once per process and shared by every session (workbook and analytics)
PASS  M9  wasm: 8 undefined symbols, hello.wasm runs in headless Chromium
PASS  M10 README opens picture-first (9 images) and shows the workbook
```
After the review fixes (three reviewer rounds; PASS on the code), the targeted checks were rerun: M1–M6, M8 and M10 PASS with the stricter proofs (M4 now includes a corner resize; M5 asserts "Opened" and the kept edit; M8 runs the analytics app with two tabs too; M10 counts app pictures, not badges).

**M7 (goal 8's regression suite) is unproven**, not failed on merit: goal 6's Data Lens got 0 drawn frames in 20 s on GTK. Goal 7's own build, run alternately at the same moment, also drew 0 frames (A/B), with the GPU idle and the CPU load average at 17–23 from six other-project Python jobs. It will be rerun when the machine is quiet; the run's output goes at the bottom of this file.

## Result
- `mojoui/frame.mojo`: typed columns (integer, decimal, text dictionary, date) shared read-only per process; a session's edits, appended and removed rows as a sparse overlay; formula columns (`margin = cents - cost`) compiled to a small bytecode with a column-level dependency graph; sort permutations; undo.
- `mojoui/frame_gpu.mojo`: group-bys with the key, value and filters chosen at run time, 0.8–1.9 ms on 20M rows, exact against the CPU on 262 numbers; 2-D pivots; the overlay applied as exact deltas.
- `examples/workbook/app.mojo`: a table grid over 20M rows (tap, edit, add, delete, sort, undo), a pivot, two Flint charts with crossfiltering, a note, on a `Board` (drag by the header, resize by the corner, snap to 8 pt; a list under 720 pt); the same on GTK and the web.
- Workbook files: `workbook.json` + Parquet (pyarrow); Save/Open; `examples/workbook/contoso.mxwb`.
- `App.init_shared()`: the rows and GPU buffers built once per process; every web tab shares them (analytics too).
- The wasm spike: Mojo's IR retargeted to wasm64 + an 8-symbol shim runs List/String/print code in Chromium (`docs/wasm.md`).

## Try it
```bash
scripts/workbook.sh          # Linux window
scripts/workbook.sh web      # http://127.0.0.1:5001
```
Walkthrough: `docs/morning.md`.

## Three decisions worth a second look
- D-80: edits as a sparse overlay + CPU deltas, formulas as virtual columns (no per-session copies of 20M rows).
- D-85: the shared-data registry lives in the process environment (Mojo has no globals).
- D-90: wasm via retargeted LLVM IR and a C shim, not a compiler fork; wasm64 because Mojo's Int is 64-bit.

## Next
The MX frame Mojo API (spec items 13–22) so the Workbook runs on the Mac; a real wasm allocator and a client-side host.

## The final full run (2026-10-16 02:03, after the review fixes; load average 6–14 during the run)
```
PASS  M1  typed columns, formulas with a dependency graph, edits, tombstones, sort permutation, undo
PASS  M2  20,000,000 rows: GPU = CPU on 262 numbers, ≤ 1.953574 ms, patch + pivot, on NVIDIA GeForce RTX 3090
PASS  M3  table, pivot, chart and note objects; edits, pivots, crossfilter and formulas identical on GTK and web
PASS  M4  Board: absolute positions, drag, resize + snap identical on GTK and web; narrow windows show a list
PASS  M5  save → open round-trips tables, formulas, pivots, charts, notes and layout
PASS  M6  packaged Linux app + web, launcher, morning walkthrough, gallery and README updated
FAIL  M7  check crashed: TimeoutExpired(['/home/abhisheksreesaila/Projects/mxapp/mojo-ui/build/lens/linux/lens'], 120)
PASS  M8  20M rows loaded once per process and shared by every session (workbook and analytics)
PASS  M9  wasm: 8 undefined symbols before the shim; hello, List/String and print samples run in headless Chromium
PASS  M10  README opens picture-first (4 images) and shows the workbook
```
M7 timed out on goal 6's lens again under the load from other projects' jobs. Right after the run, at a load average of 6, the lens drew 180 frames at 31.9 fps on GTK: it works, but goal 6's bar is 55 fps, which this machine reaches only when idle (59 fps measured on 2026-10-15). An M7-only run is queued to start when the load average falls below 2; its output lands in `/tmp/check9_m7.txt` and will be pasted here.

## M7, run on its own after the fixes (2026-10-16 05:08, load average 9–12)
```
FAIL  M7  goal 8 M9: goal 7 M7: goal 6 M3: 21.8 fps < 55; goal 6 M6: web canvas looks blank (39 colours)
```
Three real regressions surfaced once M7 could run, all fixed and committed: the test-only layout wait blocked on an unshown window (goal 6's lens runs hung); goal 8's spec and engine tests construct the analytics app without a host, so the shared data must build lazily; the apps had picked up `std.*` imports (goal 5's rule: apps import only `mojoui`). What remains are the two goal-6 lens items that predate this goal and need the owner's decision: the 55 fps bar (this machine reaches it only when idle; other projects' jobs ran all night) and the "not blank" colour count (invalidated by goal 8's PNG frames; a painted-share measure was proposed). Every other check in goals 3–8 passes.

## Morning feedback (2026-10-16, after the owner's first test)
The owner's four points: how to add a card, how to edit a cell, sort slow or crashing, jittery drags. Fixed and checked (D-91–D-94):

| Point | Cause | Now |
|---|---|---|
| Sort slow / crashes | standard comparison sort on 20M keys with 8 distinct values (quadratic) | radix sort over the gathered column: 0.45 s (category), 0.9 s (cents), 2.1 s (formula) on 20M rows |
| Jittery drag (GTK) | the drag gesture sat on the card it moved, measuring against itself | one gesture per Board, hit-tested; a drop is a patch (no rebuild) on both hosts |
| Add a card | no way to | **Insert…** menu (Table, Pivot, Chart, Note) and a Remove button per card |
| Edit a cell | not obvious | the walkthrough step says what to tap and where the value goes (no code change) |

```
PASS  M3  table, pivot, chart and note objects; edits, pivots, crossfilter, formulas, sort (18 s incl. start-up), insert and remove identical on GTK and web
PASS  M4  Board: absolute positions, drag, resize + snap identical on GTK and web; narrow windows show a list
PASS  M5  save → open round-trips tables, formulas, pivots, charts, notes and layout
PASS  M6  packaged Linux app + web, launcher, morning walkthrough, gallery and README updated
PASS  M8  20M rows loaded once per process and shared by every session (workbook and analytics)
```
Also from the morning: GTK checks now run on a headless display (D-95), so `scripts/check` opens no windows; goal 6's frame-rate check measures 60 fps there.
The owner approved the painted-share measure (D-96): goal 6's lens canvas and goal 8's analytics page are now judged by the share of pixels away from the background on both hosts, and the 55 fps bar stays (60 fps headless once the test emulator is stopped before goal 6 runs). The goal-6 lens items that blocked M7 since goal 8 are closed.

## Full check, headless (2026-10-16 afternoon): 10/10
```
PASS  M1  typed columns, formulas with a dependency graph, edits, tombstones, sort permutation, undo
PASS  M2  20,000,000 rows: GPU = CPU on 262 numbers, ≤ 1.896125 ms, patch + pivot, on NVIDIA GeForce RTX 3090
PASS  M3  table, pivot, chart and note objects; edits, pivots, crossfilter, formulas, sort (16 s incl. start-up), insert and remove identical on GTK and web
PASS  M4  Board: absolute positions, drag, resize + snap identical on GTK and web; narrow windows show a list
PASS  M5  save → open round-trips tables, formulas, pivots, charts, notes and layout
PASS  M6  packaged Linux app + web, launcher, morning walkthrough, gallery and README updated
PASS  M7  goal 8's checks (and goals 3–7's inside them) still pass
PASS  M8  20M rows loaded once per process and shared by every session (workbook and analytics)
PASS  M9  wasm: 8 undefined symbols before the shim; hello, List/String and print samples run in headless Chromium
PASS  M10 README opens picture-first (4 images) and shows the workbook
```
M1–M6 and M8–M10 from the full rebuild run; M7 rerun on its own after the Android driver fix (its only failure in the full run). No window opened on the desktop.

