# GOAL 29: charts that ask the new engine more (MX frame 321870f)

**Why:** the engine job vendored MX frame **321870f** (STABLE.md: SQL, joins, a planner, expressions, FLOAT64, median and
quantiles per group, NULL as its own group). The chart sentence (goal 28) can now say what people ask next: "median by
region", "p90", "by month", "amount over 1,000". Owner's bar: the best-performing dashboard, macOS polish, Linux speed,
Windows usability; MX frame's later work (23edc59: background queries, range aggregates) folds in at a stopping point.

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M0 | The new engine, everywhere | omxplorer and every example build for Linux, the web, Mac and iPhone on 321870f (the full check rebuilds them); its API changes hold: a FLOAT column shows its numbers; the Median tile and the inspector's median read the interpolated median right (goal 22's checks, inside M5); vendor/MXFRAME_COMMIT says 321870f |
| M1 | Median and percentiles per group | the sentence's combine offers Median and p90 (and the ask reads "median", "p90", "90th percentile"); every group's value equals pyarrow's (median: interpolated; p90: quantile_disc) for 6 specs, in their order, with top N |
| M2 | Numbers as filters | "amount over 1,000", "under 500", "at least", "at most", "between 100 and 200" (the ask, and the Rows page) filter a chart, on a decimal or a whole-number column; with a text or Yes/No filter too; each equals pyarrow's |
| M3 | By month, quarter or weekday | a chart grouped by a date column's month, quarter or weekday ("by month of day"), every month of the span in calendar order, across years and before 1970 too; equals pyarrow's |
| M4 | What a chart costs | at 1M rows a sum, a median and a month chart each fit one 60 Hz frame (16 ms); at 100M rows the times are recorded (the slow ones wait for MX frame's background queries: goal 30) |
| M5 | Nothing regressed | goal 28's checks (M0–M7; every earlier goal inside them) |

## Out of bounds
Background queries and range aggregates (MX frame 23edc59, goal 30); a "(blank)" group's median (rows without a group
key: the engine's NULL group via SQL, later); joins and a second table; an LLM behind the ask.

## Done means
PASS for M0–M5, the reviewer passes it, a short `docs/report.md`; merged into main locally (CLAUDE.md: never push).
