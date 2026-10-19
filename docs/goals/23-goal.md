# GOAL 23: the GPU for streamed files (MX frame 1889b7f, F-146)

**End goal (owner, 2026-10-18):** "please continue with tickets that depends on mxframe - and proceed on autopilot." MX frame 1889b7f (reviewed, its session's word) runs `Query(scan)` and `Query(Frame(scan))` on the GPU: each row group decodes on the CPU while the previous one uploads and aggregates on the device; AUTO picks the device per machine and plan and says why. The owner also settled text order: case ignored everywhere ("apple" before "Zebra"), bytes breaking ties.

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | Streamed aggregates may run on the GPU | the package is vendored from a clean `git archive` of 1889b7f; a streamed sheet asks for AUTO (it asked for the CPU) and names the device that ran in the status bar and a chart's message; a Mojo test shows the GPU's totals, chart and pivot over a streamed file, edits included, equal the CPU's; over the 100M-row file the CPU's, the GPU's and AUTO's times for a total and a group-by are measured and logged, with AUTO's choice; goal 22's streamed checks still pass |
| M2 | Text order as the owner settled it | a sort of a text column (in memory and streamed) puts words in alphabetical order ignoring case, bytes breaking ties ("Apple", "apple", "banana", "Zebra"), largest first the reverse; (charts and pivots list groups in the file's word order and sort nothing by name) |
| M3 | Nothing regressed | goal 22's checks (M1–M4: every earlier goal's inside them) pass; `docs/plans/needs-mxframe.md` is current |

## Done means
`scripts/check` prints PASS for M1–M3; push to `origin` after (owner's standing permission). `docs/report.md` is short.

## Out of bounds
SQL and joins (F-150 onwards); count distinct, percentiles and top-k on the GPU (the package runs them on the CPU); changing the MX frame repo; no deploying, no paid services, no secrets, nothing outside this repo; `../mojo-ui-apple-test` stays untouched.

## Assumptions
- D-221: a streamed sheet's device is AUTO, as a sheet in memory's is; the package decides (on this 12-core machine it is expected to keep the CPU, per its measurements); the GPU's name comes from a one-row device table made when the sheet opens.
- Budget: about 30 turns.
