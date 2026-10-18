# Goal 20 report: omxplorer on what MX frame can do now

**End goal (owner, 2026-10-18):** "once its in main, please continue with tickets that depends on mxframe - and proceed on autopilot."
F-138 had put omxplorer on the MX frame Mojo package. This goal built the items in `docs/plans/needs-mxframe.md` that the package can serve today.

## Result: M1–M4 PASS

The full check passed M1–M3 on 59b49e3. Its M4 runs were first stopped by headless Chromium running out of resources (`ERR_INSUFFICIENT_RESOURCES`): two Xvfb displays left over from stopped runs (now in docs/lessons.md). With those cleared, M4 passed on 5736908. Only docs changed between the two runs.

```
PASS  M1  small.parquet (pyarrow) through the Import step; 40 rows, the sum and the average equal pyarrow's; a bad file says so and the sheet stays
PASS  M2  100,000,000 rows streamed (opened in 4.3 s): rows far down, Sum, Average, a chart and a pivot equal pyarrow's; edits, sorts, formulas and Save off; peak 0.16 GB for a 4.0 GB table
PASS  M3  no mojoui module imports std.python; the Workbook and analytics binaries link no libpython; workbooks round-trip and the pyarrow-saved one opens; analytics' engine totals pass
PASS  M4  goal 19's M1–M5 (goals 3–18 and F-138 inside them) pass; needs-mxframe.md is current  (1916 s)
```

**What's new**

- **Parquet files open in omxplorer.** They go through the same Import step as CSV. The check compares them against pyarrow through the agent host: rows, column types, empty cells, the sum and the average.
- **Files bigger than memory open, streamed.** This applies to a Parquet file whose table is more than a quarter of the machine's memory.
  - The grid reads row groups from disk as you scroll.
  - Totals, charts, pivots and the Report are MX frame queries over the file (`scan_parquet`, F-140).
  - The sheet is read-only and says why; editing a cell explains it.
  - At 100,000,000 rows, opening takes 4.3 s and memory peaks at 0.16 GB.
- **No Python in the framework.** The Workbook saves and opens through the package, and a workbook saved by the old pyarrow code still opens. The analytics showcase's "MX frame" engine is now a package query.
- **An agent can read a chart's numbers**, the same way it reads the grid.

![The streamed grid, 100M rows](img/goal20-streamed-grid.png)
![A chart over 100M streamed rows: amount by region, with the (blank) group](img/goal20-streamed-chart.png)

## Try it (30 seconds)

```
pixi run python scripts/parquet_fixture.py big build/g20/big.parquet 100000000   # about 15 s, 1.1 GB
OMX_STREAM_ROWS=10000000 OMX_OPEN=build/g20/big.parquet scripts/omxplorer.sh      # or open any .parquet from the Start screen
```

Without `OMX_STREAM_ROWS`, a file streams only when it wouldn't fit a quarter of memory. On this 62 GB machine that means a table over about 15 GB.

## Three decisions worth a second look

- **D-184/D-185: when to stream, and streamed means read-only.** The threshold is a quarter of memory. A streamed sheet runs on the CPU and can't be edited, sorted or saved, because the package's scan has neither a GPU path nor an edit overlay. Totals take 4 to 5 s per column and are kept once computed; a chart takes about 11 s.
- **D-186: the package is built from a clean `git archive` of MX frame main (05332ac), not from the MX frame checkout.** That checkout has another session's unfinished F-141.
- **D-193: a fix to a rule the F-138 merge had broken.** Goal 3/5's rule says an app imports only the framework. omxplorer had imported the package directly since F-138, and those checks were failing on main. The blank sheet's table moved into `mojoui.sheet`, and the rule still stands.

## Known limits

- When a streamed file disappears while it's open, the status bar shows the error one event late (D-194).
- Narrow column headers truncate their names ("amou…") because the grid's minimum width doesn't count the type badge. This predates goal 20.
- The Mac and iPad builds of the streamed path haven't been run.

## Update: MX frame 581250b (same night)

The MX frame session finished F-141–F-143 (bulk, parallel and prefetched Parquet decode) and F-140's review fixes. Re-vendored (D-196); a streamed sheet now asks the scan for its words, which are built on first use (D-197); a file deleted while open keeps reading, one that changes size says so (D-198). Measured on the same 100M-row file: opening (with the first column's total) 4.3 s → 0.4 s, a streamed total 4.5 s → 0.44 s, a group-by 7.5 s → 0.58 s, one row group 177 ms → 12 ms; peak 0.18 GB.

## Next

The GPU for a streamed file, or editing over a scan. Both need MX frame first, as does faster Parquet decoding (F-141).
