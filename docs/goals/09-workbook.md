# GOAL 9: the Workbook (Linux + web)

**End goal (owner's words, 2026-10-15):** "a spreadsheet where you can edit rows… but you can also create a report and a dashboard built on the same engine"; Numbers-style, "it's not a grid to begin with… you can place tables and you can place charts, everything is free flowing"; "tomorrow morning… a Linux app that you have packaged for me that I can open up, type, drag a table, type formulas, drag a chart, hook up those transactional data, aggregate like crazy, put a note on it saying please review this and create a dashboard". Give up Excel's cell addresses on purpose: "being like Excel, providing the same functionality and not being Excel is actually a good thing".

A page you drop objects on: **tables** (typed columns over millions of rows, editable row by row, formula columns), **pivots** (group-by on the GPU), **charts** (Flint specs, click to crossfilter) and **notes**. One engine under all of them: an edit in a table changes the pivot and the charts. Saved as a workbook folder (Parquet per table + JSON for everything else) that an agent can write as easily as a person.

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | Frame | `mojoui/frame.mojo`: typed columns (integer, decimal with a scale, text dictionary-encoded, date as days), formula columns from a small expression language (`+ - * / min max`, columns, numbers) with a column-level dependency graph recomputed when inputs change; `set`, `append`, `remove` (tombstones), `permutation` (sort without moving data), an edit log with `undo`; `tests/test_frame.mojo` passes |
| M2 | Frame on the GPU | group-by with the key, value and filters chosen at run time (not compile time), a 2-D pivot, and a patch kernel for small edit batches (re-upload for large ones); 20M rows: GPU = CPU exactly, ≤ 10 ms per group-by, an edit's effect visible in the next group-by; `tests/test_frame_gpu.mojo` (built, not `mojo run`) passes |
| M3 | Objects | `examples/workbook`: a **Table** object (a virtualised grid over 20M rows: scroll, tap a cell, a native text field edits it, Enter writes, add row, sort by column, formula column added by typing an expression), a **Pivot** object (rows, columns and value chosen from dropdowns), a **Chart** object (Flint, tap to crossfilter), a **Note**; GTK and web end in the same state after the same steps, and an edit changes the pivot's and the chart's totals on both |
| M4 | Board | a `Board` container: children at absolute positions, drag by the header, resize by the corner, snap to an 8-pt grid (GtkFixed on GTK, CSS absolute on web); narrower than 720 pt the same page renders as a full-width list; a scripted drag moves an object on both hosts and both report the same positions |
| M5 | Workbook file | save → open round-trips every table (Parquet), formula, pivot, chart, note and layout identically; the sample workbook ships in `examples/workbook/contoso.mxwb/` |
| M6 | Packaged | `build/workbook/linux/workbook` opens the sample; `scripts/workbook.sh` launches it (and `web` serves it); `docs/morning.md` is the owner's 2-minute walkthrough; the gallery page shows the workbook; README says how to run it |
| M7 | Nothing regressed | goal 8's checks still pass |
| M8 | Shared data | `App.init_shared()` builds the read-only data (the 20M rows, on the GPU) **once per process**; every session (web tab, window) references it instead of generating its own; edits are a per-session overlay on top; the web check opens two tabs against one server and the server reports one load for two sessions; the analytics app is converted too (one copy per server, not per tab) |
| M9 | wasm spike (bounded: 2 hours) | `docs/wasm.md` records how far `spike/tiny.mojo` gets through LLVM's wasm32 backend: the missing-symbol count, and a verdict line `WASM: shim-sized` (with `build/wasm/hello.wasm` running in headless Chromium) or `WASM: wall` (with what's missing and what a compiler contribution would need) |
| M10 | README refresh | the README opens with the picture-first showcase (the one-code-many-platforms diagram and ≥ 4 gallery images in its first 60 lines) and the workbook |

## Done means
`scripts/check` prints PASS for M1–M10; `git push` after.

## Out of bounds
No deploying anything but the gallery's GitHub Pages site; push to `origin` after milestones pass; no sign-ups, secrets or licences; windows may show during checks; don't touch `../mojo-ui-apple-test`; no compiler fork.

## Assumptions
- Columns, not cells: every column has one type; formulas are column expressions; no `=B3*C3`. Decimals are scaled integers (cents), so sums stay exact on the GPU.
- The host keeps the truth in Int64 columns; the GPU holds Int32 copies (values are checked to fit). A small edit batch goes to the GPU as a patch kernel; above a few thousand edits the column is re-uploaded.
- Parquet is written and read through pyarrow (already installed) from Python, on Linux and web only; the Mojo-level MX frame API (`docs/mxframe-mojo-api.md` items 13–22) replaces it later.
- The grid is a Canvas (one renderer everywhere); cell editing uses a native text field in an edit bar above the grid at first, placed over the cell once the Board's absolute positioning exists (if time allows).
- Mouse wheel scrolls the grid; drag pans it; tap selects a cell.
- The sample data is goal 8's Contoso order lines (20M rows), generated at start as before.
- Crossfiltering works between objects on the same table.
- Edits never copy the shared columns: a session keeps a sparse overlay (changed cells, appended rows, removed rows), the GPU aggregates the shared base, and the overlay's deltas are applied on the CPU (exact; O(edits) per query). Formula columns are virtual: evaluated per visible row in the grid and inside the group-by kernel (a small bytecode), so they cost no memory per session.
- Budget: 10 hours wall clock; the wasm spike gets 2 of them at most; the README refresh only if M1–M9 are green.
