# Goal 11 report: MX Studio's Sheet, components first (2026-10-16)

MX Studio's first screen, from the owner's handoff (`docs/mx-studio/`), on Linux and web: a transactions grid over a planted-story ledger, Pivot 1 and Chart 1 that follow every edit, an inspector (where the table comes from, what it feeds, your edits, Undo all), and an agent's finding (Acme Corp under three spellings) that merges in one undoable step. Built components-first: the grid, pivot and chart moved out of the Workbook into `mojoui/` and both apps use them.

![MX Studio's Sheet on Linux](img/mxstudio-sheet.png)

## Checks (full rebuild, headless)
```
PASS  M1  mojoui/datagrid.mojo (GridSource) with its own test; the Workbook runs on it; goal 10's grid checks pass
PASS  M2  PivotTable, ChartView, Card and Text tones in mojoui with a test; the Workbook uses them; the matrix shows them ✅ on Linux and web
PASS  M3  ORDERS: 2000000 rows; Acme 398950 under 3 spellings; 286625 parcels at the flat $14.20 from Jul 14; 412 duplicates at ZIP 94110 · MARGIN: Q2 39.48% → Q3 36.44% (3.04 points)
PASS  M4  the Sheet on both hosts: grid, Pivot 1, Chart 1, inspector, exact status; an in-place edit regroups the pivot and shows in Your edits; also at 20M rows
PASS  M5  the agent finds 3 spellings with their rows; Merge regroups (20 → 18 customers) as one undoable step; identical on both hosts
FAIL  M6  goal 10 M7: sort: margin 3846 ms (> 2500); goal 7 M2: STEP FAILED: ValueError('no Button #0')
```
M6's two failures, run again on their own: the formula sort took 2.06 s (the machine was loaded by other projects' agents; it then got faster: formulas read only their own columns, 1.1 s), and goal 7's Android hello app passed from a cold emulator (the driver now waits up to 10 s for a view, as a person would). M6 runs again inside goal 12's final check.

## Components added (docs/components.md)
| Component | Linux | Web | Used by |
|---|---|---|---|
| DataGrid (scroll bar, select, sort marker, resize, fit, sideways scroll, edit in place, header histograms) | ✅ | ✅ | Workbook, MX Studio |
| PivotTable (native labels, totals, highlighted rows) | ✅ | ✅ | Workbook, MX Studio |
| ChartView (Flint bars and lines, heatmaps, tap to select) | ✅ | ✅ | Workbook, MX Studio |
| Card tones, Text tones | ✅ | ✅ | MX Studio |

## Review
One round, NEEDS WORK; all must-fix and should-fix items addressed: GTK now follows tone changes (and both hosts report tones, so the checks see colours); merges in the engine follow chains and can't collide across columns (tested); Insert works (Pivot, Chart, Text, Formula, Agent; Table explains it needs Explore); the inspector floats in an island; chart taps use the drawn size; histograms follow edits; tests use golden counts and compute expectations independently.

## What waits for MX frame
`docs/plans/needs-mxframe.md`: Query (SQL), Explore (pipelines and joins), file readers, multiple tables, versions, out-of-core. Skipped, not faked.

## Next
Goal 12: the Report (built; its contract and checks next), `docs/plans/GOAL12.md`.
