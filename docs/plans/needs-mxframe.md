# What waits for MX frame (the core engine, being built in its own project)

Owner, 2026-10-16: "use the existing [engine] for whatever your need is, but for things that you absolutely need MX
frame to support, log it or mark it and move on to the next feature."

The stand-in is `mojoui/frame.mojo` + `frame_gpu.mojo`: one table of typed columns, column formulas, a sparse
edit overlay with undo and value merges, GPU group-by/pivot with filters, radix sort, header histograms. That
covers MX Studio's Sheet and Report. These need MX frame and are skipped or stubbed until it lands
(the Mojo API wish list is `docs/mxframe-mojo-api.md`):

| Feature (MX_STUDIO.md) | Needs from MX frame | What the app does meanwhile |
|---|---|---|
| Query mode (A3, C4, C8): SQL cells, EXPLAIN | a SQL front end compiling to the plan IR; joins; HAVING; CTEs | mode switch says "next"; not built |
| Explore mode (A4, C3): pipelines of input → join → clean → formula → summarize → output, per-step previews, cached steps | joins, multi-table plans, step caching, fuzzy name matching as an operator | not built; the Sheet's merge is the one "clean" step, done in the stand-in |
| Reading real files (E2): CSV, Parquet, Arrow, XLSX | readers with type inference and bad-row reports | CSV and Parquet: done (the package's readers, omxplorer and the Workbook); Arrow and XLSX wait |
| A second table (Sheet's Insert → Table) | multiple tables and joins in one workbook | Insert Table explains it comes with Explore (D-116) |
| Versions, branches, diff, the time machine (C1, X) | versioned column chunks shared between versions | one undo log per session (edits and merges) |
| Data bigger than GPU or host memory (E8) | chunked, streamed execution (`docs/mxframe-mojo-api.md` §7a) | Parquet: done, streamed and read-only (goal 20, `scan_parquet`); CSV still loads whole; no GPU when streamed |
| The DuckDB test oracle and TPC-H (P3–P5, E5) | the engine those tests are for | the stand-in is checked against its own CPU path (GPU = CPU exactly) |
| Count distinct, percentiles, top-k, binning as engine operations (E5, C5) | aggregate operators | done in app code over GPU group-by results (histograms, top customers) |
| CSV, Parquet, Excel and JSON readers (omxplorer's import, `mojoui/csvio.mojo`) | streaming typed readers | CSV and Parquet: the package's readers (F-138, goal 20); Excel and JSON wait |
| More than 16 columns in a table | wider row vectors / columnar GPU frame | done (F-138: 4,096) |
| Blank (null) numbers and dates: Delete on a number cell, empty cells in imports | nulls per column | done (F-138, D-170) |

## Done with the package (F-138, goal 20)

- omxplorer runs on the MX frame Mojo package (F-138: `vendor/mxframe.mojoc`): CSV import, nulls, BOOL columns, more
  than 16 columns, `.omx` files as Parquet.
- **Parquet files open** (goal 20, D-183): the package's `read_parquet`, through the same Import step as CSV.
- **Files bigger than memory** (goal 20, D-184, D-185): a Parquet file whose table is over a quarter of memory opens
  streamed with F-140's `scan_parquet`: the grid reads row groups from disk as they're shown, totals, charts, pivots
  and the Report are `Query(scan)` on the CPU, and the sheet is read-only. 100M rows open in 4.5 s and peak at 0.16 GB.
- **no Python** in the framework (goal 20): the Workbook's files and the analytics showcase's engine are on the package.

## Still waiting (the package has none of these yet)

Query mode (SQL, joins, HAVING), Explore mode (multi-table plans), a second table, versions and the time machine,
count distinct / percentiles / top-k as operators, Excel and JSON import, the DuckDB oracle, the GPU for a streamed
file (the scan is CPU only), editing a streamed file (an overlay on a scan), and faster Parquet decoding (F-141: a
streamed total over 100M rows takes 4.5 s, a group-by 7.5 s). The table above says what the app does meanwhile.

When MX frame's Mojo API is ready, the switch is one layer: `GridSource`, the ops modules
(`mojoui/orders_ops.mojo`, `orders_report.mojo`) and the Workbook's compute() call the engine; the components
(DataGrid, PivotTable, ChartView, KpiView, FindingCard) don't change.
