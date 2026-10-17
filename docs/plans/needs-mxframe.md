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
| Reading real files (E2): CSV, Parquet, Arrow, XLSX | readers with type inference and bad-row reports | the planted-story ledger is generated in Mojo; the Workbook's Parquet goes through pyarrow (a labelled shim) |
| A second table (Sheet's Insert → Table) | multiple tables and joins in one workbook | Insert Table explains it comes with Explore (D-116) |
| Versions, branches, diff, the time machine (C1, X) | versioned column chunks shared between versions | one undo log per session (edits and merges) |
| Data bigger than GPU or host memory (E8) | chunked, streamed execution | 20M rows in memory; MOJOUI_ROWS caps it |
| The DuckDB test oracle and TPC-H (P3–P5, E5) | the engine those tests are for | the stand-in is checked against its own CPU path (GPU = CPU exactly) |
| Count distinct, percentiles, top-k, binning as engine operations (E5, C5) | aggregate operators | done in app code over GPU group-by results (histograms, top customers) |

When MX frame's Mojo API is ready, the switch is one layer: `GridSource`, the ops modules
(`examples/mxstudio/ops.mojo`, `report_ops.mojo`) and the Workbook's compute() call the engine; the components
(DataGrid, PivotTable, ChartView, KpiView, FindingCard) don't change.
