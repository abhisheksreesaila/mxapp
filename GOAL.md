# GOAL 15: omxplorer: charts and pivots on the sheet, and a Report built from scratch (Linux + web)

**End goal (owner's words, 2026-10-16):** "you can add table and then add rows… add a report… use it from scratch as opposed to having widgets on a screen"; "follow [the Stitch designs]… the classic design"; "dazzle me." Design: Stitch 05 (insert chart) and 06 (report from scratch) in `docs/design/mxstudio-app/`, Omarchy language.

## Components this needs (from `docs/components.md`, before the build)
| Component | Before | Plan |
|---|---|---|
| A sheet that holds objects (the table, charts, pivots), each moved by its header | the Workbook / MX Studio pages are app code | `mojoui/sheetpage.mojo`: objects with a title bar on a `Board`, placed in free space, the table first |
| Chart: bar or line of a value column by a text column, with a readout of the picked bar in the column's format | `ChartView` (bars, lines, heatmaps) | `ChartView` + a `readout`; omxplorer computes the group-by on the GPU |
| Pivot: rows × columns of a value column, totals, in the column's format | `PivotTable` (labels only) | reused; the numbers from one GPU group-by |
| Chart and pivot inspector tabs | `Inspector` | `Section`s for type, value, group by, rows/columns |
| Report page: a title, KPI tiles, chart tiles, an empty "add" slot, filters that apply to every tile | `KpiView`, `ChartView`, `Dropdown` | `mojoui/reportpage.mojo` layout; tiles computed with the filters as GPU ranges |

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | The components | sheet page and report page modules with tests; the matrix lists them ✅ on Linux and web |
| M2 | Insert a chart | the toolbar's Chart puts the selected value column on the sheet grouped by the text column with the fewest values (revenue by carrier, D-146); the inspector switches it to a line and to another grouping; picking a bar reads its total in the column's format; the chart's totals equal an independent pass over the CSV (one picked bar per grouping on the hosts, every group in tests/test_sheetpage.mojo); identical on GTK and web |
| M3 | Insert a pivot | the toolbar's Pivot puts the value column by the two text columns with the fewest values on the sheet (revenue by carrier × region, D-146), with totals, in the column's format (Currency shows $); every cell equals the CSV's; identical on GTK and web |
| M4 | A Report from scratch | a Report tab: add KPI tiles (sum, average, count of chosen columns) and a chart tile; a filter (one value of a text column) changes every tile; every number equals the CSV's with that filter; identical on GTK and web |
| M5 | Save and open | an .omx document keeps the sheet's objects and the Report (tiles and filter) and opens them again on both hosts |
| M6 | Nothing regressed | goal 14's checks (and every earlier goal's inside them) still pass; the matrix is current |

## Done means
`scripts/check` prints PASS for M1–M6; push to `origin` after.

## Out of bounds
As goal 14. Pie, scatter, bubble and histogram charts, 3D (the next rung), and moving tiles on the Report by drag are later.

## Assumptions
- One chart or pivot inserted at a time from the toolbar; any number can sit on the sheet.
- Report filters are one value of one text column (region = West) to start; more later.
- Budget: what's left of the night.
