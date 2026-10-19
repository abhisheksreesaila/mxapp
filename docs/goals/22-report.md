# Goal 22 report: files bigger than memory become editable; Distinct and Median in the Report

**End goal (owner, 2026-10-18):** "please continue with tickets that depends on mxframe - and proceed on autopilot." MX frame 7cbcc04 (its session called it stable) brings editing over a streamed Parquet file (F-147), count distinct and median as engine aggregates (F-148), and faster streaming (F-145, F-149).

## Result: M1–M4 PASS

```
PASS  M1  vendored from 7cbcc04; 100M streamed rows open in 0.2 s, a total takes 210 ms, a group-by 553 ms; rows, totals, a chart and a pivot equal pyarrow's (goal 20's M2)
PASS  M2  100M streamed rows: a typed value, an emptied cell, a new row and a formula show, total and chart with the edits; Undo takes the formula, then the row back; on an 8 GB machine sorting and a median are refused with the reason, a distinct count of region works; saved (streamed, 6 s) to a file pyarrow reads with the edits, which reopens streamed, bold currency; peak 0.27 GB; here, a sort of all 100M rows takes 7 s and reads in order far down
PASS  M3  Median (5,005.54) and Distinct (amounts 4,741, regions 5) tiles equal pyarrow's, in memory and streamed, through the filter (West), saved and reopened; a Median of text is refused; identical on GTK and the web
PASS  M4  goal 21's M1–M4 (goals 3–20 inside them) pass
```

The full run's M4 failed only on goal 5's README check, which found no `docs/report.md`: this report was moved to the archive at the start of the goal. That check passes with this file in place. Everything else in M4 passed on that run. Reviewer: PASS in round 3. Rounds 1 and 2 found a Count tile lost on reopen, a formula column that Undo couldn't take back, and then a crash when Undo took away a column a chart read. All are fixed and tested.

## What changed

- **A file bigger than memory is an ordinary sheet now.** You can type into it, empty cells, add rows, add formula columns and Undo. Totals, charts, pivots and the Report include your edits.
  - Save streams the edited file out: 100M rows take 6 s, with memory peaking at 0.27 GB.
  - A saved document too big for memory reopens streamed, with its formats.
  - Sorting works when its memory (about 50 bytes a row) fits a quarter of the machine's memory. On this machine that means all 100M rows, in 7 s. Otherwise sorting is refused with the reason.
- **The Report has Distinct and Median tiles, computed by the engine.**
  - Distinct counts any column, text too ("Different region: 5").
  - Median is the mean of the two middle values, as in Excel, pandas and DuckDB.
  - Both apply the Report's filter and work on streamed files.
- **Undo takes back a formula column**, unless a chart, pivot or tile reads it. Then it says which, so you can remove that first.
- **Faster:** a 100M-row streamed total takes 0.21 s (it was 0.44 s), and a group-by 0.55 s (it was 0.58 s).

## Three decisions worth a second look

- **D-213: a streamed sheet is the engine's own `Frame(scan)`.** goal 20's private row-group cache is gone. One engine path now serves both kinds of sheet.
- **D-215 and D-219: memory guards.** Sort, Median and Distinct on a streamed file are refused when their working memory wouldn't fit a quarter of the machine's. That's about 50, 27 and 35 bytes a row, or per distinct value for Distinct. The checks prove this by acting as an 8 GB machine (`OMX_MEMORY_BYTES`, D-217).
- **D-216: goal 20's and goal 21's checks required streamed files to be read-only.** Those steps now require the opposite; nothing else in them changed.

## Next

Goal 23 is MX frame 1889b7f: the GPU for streamed files (F-146).
