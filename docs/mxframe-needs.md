# What omxplorer and mojo-ui need from MX frame (goal 27 M8, 2026-10-19)

The owner asked: "after this polish, super silky smooth UI, make a list of operations you need from mxframe". This is
that list, ranked by what a person feels. Vendored today: MX frame **1889b7f** (`vendor/MXFRAME_COMMIT`); **dc1a722**
(SQL, FLOAT64) waits to be called stable. The history of what already landed is in `docs/plans/needs-mxframe.md`.

How to read it: **Need** is the operation, **Why** is what the person sees today, **Meanwhile** is what the app does
instead (with the code), **Matters** is high / medium / low.

## 1. Silky: keep the UI thread free (the owner's bar)
The Scene made drawing cost ≤ 1 ms a frame (goal 26). What still freezes the window is data work on the same thread.

| # | Need | Why | Meanwhile | Matters |
|---|---|---|---|---|
| 1 | **Run a query off the caller's thread**: start it, get a handle, ask "done?" (or a callback), **cancel** it, read **progress** (rows done of rows) | opening 1M CSV rows takes 0.71 s, 100M 106 s; a streamed group-by 0.34–0.70 s and a pivot runs four; a sort of 100M 3.7 s: the window stops for all of it | everything runs synchronously in `update()` (`examples/omxplorer/app.mojo` `open_path`, `refresh`, Save) | high |
| 2 | **Incremental results after an edit**: a total or group-by updated by the edited rows' delta (or cached per plan and invalidated by what changed) | one typed cell recomputes every chart, pivot and tile from scratch (`refresh()`) | `refresh()` recomputes all; streamed totals are cached by edit count (`mojoui/sheet.mojo` `Notes.plain`) | high |
| 3 | **Range aggregates in a given order**: sum / count / mean / min / max over rows a..b of a permutation (the sorted view) × a set of columns, exact in each column's own decimal scale | the status bar's figures for a selected block, and Copy, read one cell at a time | a cell-by-cell loop capped at 100,000 cells ("Too many cells to total here"; `app.mojo` `BLOCK_CAP`) | high |
| 4 | **A window of rows in one call**: rows a..b (in a permutation) of n columns, typed, with null flags | the grid reads each visible cell separately every frame it rebuilds (≈ 1,000 calls a scroll frame at 2.8k × 1.4k) | per-cell `is_null` / `value` (`mojoui/datagrid.mojo`) | medium |

## 2. Charts and the Report (goal 28: "the title is the query")

| # | Need | Why | Meanwhile | Matters |
|---|---|---|---|---|
| 5 | **More aggregates per group**: mean, median and percentiles, min, max, **standard deviation and variance** (also for a whole column) | a chart can only sum; "average by region" and "median by month" can't be asked; the Average tile can't show σ | sums and counts per group; median and distinct for a whole column only | high |
| 6 | **Ordered, limited group results**: sort groups by their aggregate, top-N / bottom-N with an "everything else" row | "largest first, top 5" is the second thing anyone asks of a chart | groups come in dictionary (file) order; nothing sorts or cuts them | high |
| 7 | **Filters as expressions on every query**: ranges, is-in, and / or / not, null tests; per query, streamed and on the GPU alike | the Report has one filter for everything (`column = value`); a chart can't have its own ("only unpaid") | `ReportFilter{col, code}` (`mojoui/reportpage.mojo`) | high |
| 8 | **Date parts and bins as group keys**: year, quarter, month, week, weekday; numeric bins (equal width or quantile) | "by month" is the most common chart there is; histograms are done by hand | no date grouping; 16 bins with `least`/`greatest` (`mojoui/sheetpage.mojo` `shape_of`) | high |
| 9 | **Group by any column and several keys**: Yes/No, dates, numbers, formula columns; multi-key group-by; the empty-value group returned by the engine | only stored text columns can group; pivots build `row × columns + column` keys by hand and find "(blank)" by subtraction (2–4 queries per object) | dense dictionary codes only (`sheetpage.mojo` `compute`) | medium |
| 10 | **Count distinct and median on the GPU and streamed in parallel**, spilling (or approximate, e.g. HyperLogLog, t-digest) when memory is short | on big files they're refused when their working memory wouldn't fit | memory guards by bytes per row (`sheet.mojo` `fits`); CPU only | medium |

## 3. Files and scale

| # | Need | Why | Meanwhile | Matters |
|---|---|---|---|---|
| 11 | **Streamed CSV** (Parquet streams today), with a report of rows that didn't parse | a CSV bigger than memory can't open | CSV loads whole (`mojoui/csvio.mojo`) | medium |
| 12 | **Sort that spills to disk**, and sort by several keys | sorting a big streamed file is refused | refused above a quarter of memory (~50 bytes a row) | medium |
| 13 | **Undo that includes formula columns** | the app keeps a second undo log and merges the two | `StyleChange` with row −3 (`sheet.mojo`) | low |
| 14 | **Compressed Parquet writes on every platform** | the Mac build has no zstd or snappy, so every `.omx` is written uncompressed | uncompressed everywhere (`mojoui/omxfile.mojo`) | low |
| 15 | **Excel and JSON readers** | people's data arrives as .xlsx | not offered | medium |

## 4. Later modes (already on MX frame's own plan)

| # | Need | Why | Matters |
|---|---|---|---|
| 16 | SQL over one table and joins (dc1a722 has SQL); a second table in a document | Query and Explore modes, the pipeline's blue | high, later |
| 17 | Window functions: running totals, rank, moving averages | "running total" and "rank" columns in the sheet | medium |
| 18 | String search and contains (Find, filters on text) | there's no Find in omxplorer | medium |
| 19 | Versions and the time machine | MX Studio's design | later |

## Order I'd ask for
1, 3, 5, 6, 7, 8 first: they make the app feel instant and make charts worth editing. Then 2 and 4 (smoothness at
100M rows), then 9–12, then the rest. Not filed yet: the channel is a GitHub issue on abhisheksreesaila/mxframe
labelled `omxplorer`, which waits for the owner's yes.
