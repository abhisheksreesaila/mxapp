# GOAL 29 (draft): MX frame 321870f, and charts that ask it more

**Why:** MX frame's session called **321870f** stable (STABLE.md at the root of abhisheksreesaila/mxframe: SQL, joins, a
planner, expressions, FLOAT64, median and quantiles per group, NULL as its own group). Much of docs/mxframe-needs.md
is in it (D-265). The chart sentence (goal 28) can then say what people ask next: "median by region", "by month",
"over $1,000", "only West and paid".

## Milestones (draft)
| # | Milestone | Proof |
|---|---|---|
| M0 | Vendored by the book | `vendor/mxframe.mojoc` built from `git archive 321870f` (STABLE.md's commands), `vendor/MXFRAME_COMMIT` = 321870f; the Mac link allows the six libSystem symbols STABLE.md names; every platform builds |
| M1 | Its API changes handled | median is interpolated (scale + 1: the Median tile and the inspector's stats read it right); FLOAT64 columns show, sort, total and chart (a new column kind); CSV money with more than 4 places stays exact (decimal_columns) or reads as a float on purpose; every earlier goal still passes |
| M2 | The engine groups | charts, tiles and pivots ask the builder (or SQL) for their groups: NULL is its own group (no "(blank)" by subtraction: one query a chart, not 2–4), order and top N in the query; the same numbers as goal 28's (pyarrow) |
| M3 | More words | the sentence offers Median and percentiles (p90…) per group; "by month / quarter / weekday of <date>"; numbers "over / under / between" as a filter; two conditions ("only West and paid"); the ask reads them; tests for each |
| M4 | As fast or faster | a chart's numbers at 1M and 100M rows (streamed): one query each, timed against goal 28's |
| M5 | Nothing regressed | goal 28's checks (every earlier goal inside them) |

## Open questions to settle while building
- Builder or SQL text for charts: the builder keeps types and needs no quoting; SQL is what an agent writes. Probably the builder in the app, SQL for the agent host.
- FLOAT64 in the grid: how many places to show by default.
