# GOAL 12: MX Studio's Report, components first (Linux + web)

**End goal (owner's words, 2026-10-16):** "the killer app is the data transformation app… I'm showing you how it would look like, the end product"; "ask yourself what component do I need, then build the component… then go back and build the app"; "go for it and make me proud". Source: SCREENS.md §2 (Report), MX_STUDIO.md A5.

The Report mode: a dashboard over the same ledger the Sheet edits, so an edit or a merge in the Sheet redraws every tile, and a finding opens its rows back in the Sheet. The mode switch becomes real (Sheet ↔ Report).

## Components this needs (from `docs/components.md`, before the build)
| Component | Before | Plan |
|---|---|---|
| `KpiView` (label, value, change vs last period, sparkline, focal accent) | ❌ (KpiTile wired by each app on a Canvas) | `mojoui/kpi.mojo`: native labels (readable, testable) plus a small sparkline Canvas |
| Line chart with a second series and an event marker | ❌ | `LineChart.with_second / with_marker`, `ChartView.line` |
| `Heatmap` | ❌ | `mojoui.charts.Heatmap`, `ChartView.heatmap` (tap a cell) |
| `FindingCard` | ❌ debt in the Sheet | `mojoui/finding.mojo`; the Sheet's agent card and the Report's "Worth a look" both use it |
| Dropdown filters, ChartView bars, Card, Overlay islands, Tabs, Segmented | ✅ Linux + web | reuse |

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | The components | KpiView, FindingCard, line marker + second series, Heatmap in mojoui with tests (`tests/test_components.mojo`); the matrix lists KpiView and FindingCard ✅ on Linux and web; the Sheet's agent card is a FindingCard |
| M2 | The anomaly finder | `worst_margin_fall` (margin by region × parcel weight × before/after Jul 14, on the GPU) names the West's heavy parcels and a fall of at least 5 points, with its order count; `tests/test_report.mojo` checks it against a CPU computation |
| M3 | The Report screen | on both hosts: filters (quarter, region, product), four KPIs with their change against the previous quarter, revenue and margin by week with the Jul 14 marker, top customers, product mix, the margin heatmap, "Worth a look"; every tile's numbers identical on GTK and web; picking a region changes the KPIs |
| M4 | One engine | a merge in the Sheet changes the Report (active customers 20 → 18; top customers says what the merge added); "Open the rows" opens the Sheet filtered to the finding's rows (the count matches the finding); tapping a product bar filters the other tiles; identical on GTK and web |
| M5 | Nothing regressed | goal 11's checks still pass; the component matrix is current |

## Done means
`scripts/check` prints PASS for M1–M5; push to `origin` after.

## Out of bounds
As goal 11 (no deploys, secrets or sign-ups; checks headless; Explore, Query, MCP and the later rungs are later goals).

## Assumptions
- One Report page (Revenue) is built; Margin and Customers pages answer "next".
- KPIs compare against the previous quarter; Q1 says "first quarter of data".
- Budget: 3 hours wall clock (the Report's code was written while goal 11's full check ran; D-120).
