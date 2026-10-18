# GOAL 20: omxplorer on what MX frame can do now: Parquet files, files bigger than memory, and no Python left in the framework

**End goal (owner, 2026-10-18):** "once its in main, please continue with tickets that depends on mxframe - and proceed on autopilot." F-138 put omxplorer on the MX frame Mojo package. The items in `docs/plans/needs-mxframe.md` that the package can serve today get built: opening Parquet files, opening files bigger than memory (F-140's `scan_parquet`, one row group at a time), and taking Python out of the last two framework modules (the Workbook's files, the analytics showcase's engine). SQL, joins, versions and distinct/percentile operators still wait: the package has none yet.

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | omxplorer opens Parquet | the Open buttons accept `.parquet`; a Parquet file (written by pyarrow in the check: integers, decimals, text, dates, booleans, empty cells) goes through the Import step with its columns' kinds, empty counts and samples, and Create table shows it; driven through the agent host, `read grid` equals pyarrow's rows and the status bar's Sum equals pyarrow's sum; a file that isn't Parquet says so and the screen stays as it was; a Mojo test covers the reader |
| M2 | Files bigger than memory | the package is re-vendored at MX frame's F-140 (`scan_parquet`); a Parquet file whose table wouldn't fit the memory budget opens **streamed**: the Import step says so, the grid pages row groups from disk (rows far from the top read right), the status bar's Sum/Average/Count, a chart and a pivot run through `Query(scan)` and equal pyarrow's; editing, sorting, formulas and Save are off with a reason; the agent host's process peak memory stays under a quarter of the table's in-memory size; a Mojo test covers the streamed sheet |
| M3 | No Python in the framework | `mojoui/workbook.mojo` reads and writes workbooks through the package (Parquet) and `mojoui/json.mojo`; the analytics showcase's MX frame engine (`mojoui/mxframe.mojo`) is a package `Query`; no `mojoui/` module imports `std.python` (the web host's module entry is the host, not the framework); the Workbook's and analytics' Linux binaries link no libpython; workbooks saved before still open |
| M4 | Nothing regressed | goal 19's checks (M1–M5: the agent host, goal 18's checks with every earlier goal's inside them, F-138's guard) still pass; `docs/plans/needs-mxframe.md` and the components matrix are current |

## Done means
`scripts/check` prints PASS for M1–M4; push to `origin` after (owner's standing permission). `docs/report.md` is short.

## Out of bounds
SQL, joins, a second table, versions, count distinct/percentiles as engine operators (the package has none: they stay in needs-mxframe.md); editing a streamed file; the GPU for a streamed file (the package's scan is CPU only); Excel and JSON import; changing the MX frame repo (it has another session's work in progress: the package is built from a clean `git archive` of a commit); no deploying, no paid services, no secrets, nothing outside this repo; `../mojo-ui-apple-test` stays untouched.

## Assumptions
- D-183: a Parquet file goes through the same Import step as a CSV file (one `TableImport` for both, from `mojoui/csvio.mojo`); the package's `read_parquet` reads it.
- D-184: a file opens streamed when its table (rows × columns × 8 bytes) is more than a quarter of the machine's memory; `OMX_STREAM_ROWS` sets a row count instead (the checks use it, so a small file streams).
- D-185: a streamed sheet is read-only and on the CPU; the grid keeps a few decoded row groups (least recently used goes first); every aggregate is one `Query(scan)`.
- D-186: the package is vendored from MX frame's main at F-140's merge (`ec268d2`), built from `git archive`, not from the MX frame checkout (which has another session's unfinished F-141).
- Budget: about 80 turns.
