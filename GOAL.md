# GOAL 22: omxplorer on MX frame 7cbcc04: files bigger than memory become editable; count distinct and median in the Report

**End goal (owner, 2026-10-18):** "please continue with tickets that depends on mxframe - and proceed on autopilot." MX frame 7cbcc04 (stable, its session's word) brings editing over a Parquet scan (F-147: `Frame(scan)`, `save`), count distinct / median / percentile / top-k as engine aggregates (F-148), and faster streaming (F-145, F-149). Goal 20 made a file bigger than memory open read-only; this goal makes it a sheet like any other, and puts the new aggregates where a user sees them.

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | The package at 7cbcc04 | `vendor/mxframe.mojoc` rebuilt from a clean `git archive` of 7cbcc04 (MXFRAME_COMMIT says so); the app follows its API (text lookups raise; a failure is shown, not hidden); the 100M-row streamed file still opens, scrolls, totals, charts and pivots equal pyarrow's, with the open, total and group-by times measured and logged |
| M2 | A streamed file is editable | over 100M streamed rows: typing into a cell, emptying one, adding a row, a formula column and Undo work as on a table in memory, and the totals and a chart include them; Save writes the edited file (`Frame.save`, streamed, its rows equal pyarrow's reading of it, the edits in it) and the saved document reopens streamed with its formats and edits; memory stays under a quarter of the table's size; sorting works when its order fits the memory budget and says why when it doesn't; a Mojo test proves a streamed sheet's edits, undo, totals and save equal the same sheet read whole |
| M3 | Count distinct and median in the Report | the Report's toolbar adds Distinct and Median tiles: count distinct of any column (text too) and the median of a number column, from the engine (`count_distinct`, `median`), through the Report's filter, equal to pyarrow's (median as DuckDB/pandas: the mean of the two middle values), on a table in memory and on a streamed file; they save and reopen; GTK and the web agree |
| M4 | Nothing regressed | goal 21's checks (M1–M4: goal 20's and every earlier goal's inside them) pass, with only steps pointing at changed behaviour updated (logged); `docs/plans/needs-mxframe.md` and the components matrix are current |

## Done means
`scripts/check` prints PASS for M1–M4; push to `origin` after (owner's standing permission). `docs/report.md` is short.

## Out of bounds
The GPU for a streamed file (F-146 isn't vendorable yet); SQL, joins, a second table, versions; percentile and top-k tiles beyond the two above; moving MX Studio's own engine (`mojoui/frame.mojo`) onto the package; changing the MX frame repo (ask for things with a GitHub issue labelled `omxplorer`); no deploying, no paid services, no secrets, nothing outside this repo; `../mojo-ui-apple-test` stays untouched.

## Assumptions
- D-213: a streamed sheet is the package's `Frame(scan)`; goal 20's own row-group cache (`Pages`) goes: the frame's chunk cache (128 MiB by default) reads rows, and its overlay holds the edits.
- D-214: Save of a streamed sheet streams with `Frame.save` into the document (`name.omx` in the documents folder), one row group at a time; a saved document too big for memory reopens streamed, as a Parquet file does.
- D-215: sorting a streamed sheet holds about 50 bytes a row (the package's permutation): allowed when that fits a quarter of memory, else refused with the reason.
- Budget: about 80 turns.
