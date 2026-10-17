# Goal 12 (draft): MX Studio's Report, components first

The Report mode (SCREENS.md §2, MX_STUDIO.md A5): a dashboard over the same ledger the Sheet edits, so an edit
in the Sheet redraws every tile. It makes the mode switch real (Sheet ↔ Report).

## Components it needs
| Component | Today | Plan |
|---|---|---|
| `KpiView` (label, value, change vs last period, sparkline, focal accent) | 🔨 mojoui.charts.KpiTile, wired by each app on a Canvas | a view-level component like ChartView |
| Line chart with an event marker and a second series (revenue and margin by week, "Jul 14 · rate table v7") | LineChart has one series, no marker | extend LineChart; ChartView kind "Line Chart" |
| `Heatmap` (margin by region × product) | ❌ | new chart in mojoui.charts, through ChartView |
| `FindingCard` (what the agent noticed, the rows behind it, actions) | ❌ debt in examples/mxstudio | extract from the Sheet's agent card; Report's "Worth a look" uses it |
| Filter capsules (Quarter, Region, Product) | ✅ Dropdown | reuse; crossfilter by tapping bars (ChartView) |

## Milestones
1. KpiView, line marker + second series, Heatmap, FindingCard in mojoui with tests; the matrix shows them.
2. The anomaly finder: margin by region × heavy/light × before/after Jul 14 on the GPU → "Heavy items in the West lost N margin points after Jul 14", with its rows.
3. The Report screen: filters, four KPIs (vs the previous quarter), revenue and margin by week with the Jul 14 marker, top customers (merged), product mix, margin heatmap, "Worth a look"; every tile says its source and time.
4. One engine: an edit or a merge in the Sheet changes the Report's tiles; "Open the rows" goes to the Sheet filtered to them; identical on GTK and web.
5. Nothing regressed.
