# Goal 9 report: the Workbook

**End goal (owner's words):** "a spreadsheet where you can edit rows… but you can also create a report and a dashboard built on the same engine"; Numbers-style free-flow objects; columns, never cell addresses; packaged for the morning.

## How far it got
_(the final `scripts/check` output is pasted below when the run finishes)_

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
