# Goal 15 report: omxplorer: charts and pivots on the sheet, and a Report built from scratch (2026-10-17)

The sheet now holds more than the table. Chart and Pivot in the toolbar place a chart or a pivot beside it, each on the GPU and each in its value column's format. You can drag one by its title bar or resize it by its corner, and the inspector regroups or restyles it.

A Report tab builds a page from nothing: Sum, Average and Count tiles and chart tiles. One filter (region = West, say) recomputes every tile. A saved `.omx` keeps all of it.

![The Report: three KPI tiles and a chart tile, filtered to West](img/omxplorer-report.png)

## Checks
```
PASS  M1  sheet objects (charts, pivots: GPU sums = a CPU pass, with an edit) and the report page (tiles through a filter) in mojoui with a test; ✅ on Linux and web in the matrix
PASS  M2  Chart puts revenue by carrier on the sheet; the inspector regroups it by region and makes it a line; a picked bar reads its group's total in Currency, equal to the CSV's; identical on GTK and web
PASS  M3  Pivot puts revenue by carrier × region on the sheet with row, column and grand totals, all 12 cells equal to the CSV's and in Currency; identical on GTK and web
PASS  M4  a Report from scratch: Sum, Average, Count and a chart tile; the West filter changes every tile (sum $28,560,486.00, 250,217 rows), all equal to the CSV's; identical on GTK and web
PASS  M5  an .omx document keeps the sheet's chart and pivot (where they were) and the Report's tiles and West filter; both hosts' files reopen on both hosts
PASS  M6  goal 14's checks (and goals 3–13's inside them) pass
```

M1–M5 ran after the last change. M6 reruns every earlier goal's checks (34 minutes) and ran on the review's first-round fixes; the second round changed only the KPI row's packing, which no earlier goal uses.

![A chart and a pivot beside the table, in Currency](img/omxplorer-pivot.png)

## Components added (omxapp)
| Component | Linux | Web |
|---|---|---|
| Sheet objects: charts and pivots placed in free space, moved and resized, readouts in the column's format (`mojoui.sheetpage`) | ✅ | ✅ |
| Report page: KPI and chart tiles, a filter for every tile (`mojoui.reportpage`) | ✅ | ✅ |
| `Frame.format_average`, one average everywhere | ✅ | ✅ |
| `.omx` documents keep objects and the Report, checked by kind on open (`mojoui.omxfile.open_document`) | ✅ | ✅ |

## Decisions worth a look
- **D-146:** a new chart groups by the text column with the fewest values, so revenue by carrier rather than by customer. The contract's wording follows this.
- **D-148:** the Report has one filter for now. The Stitch design has three.

## Next
More filters on the Report (quarter, product). A column chart and a date axis. The Stitch chart-type picker and inspector tabs (Axis, Series). Then rung 2, data in 3D.
