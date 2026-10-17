# Goal 12 report: MX Studio's Report, components first (2026-10-16 night)

The Report mode from the owner's handoff (SCREENS.md §2) on Linux and web, on the same ledger the Sheet edits: filters, four KPIs against the previous quarter, revenue and margin by week with the Jul 14 rate-table marker, top customers, product mix, a margin heatmap, and "Worth a look": the engine's own finding (heavy parcels in the West lost 7.7 margin points after Jul 14) with the cause it found in those rows (Carrier A's freight rose to $14.20 an order) and a button that opens those rows in the Sheet.

![MX Studio's Report on Linux (headless GTK; the web run is identical)](img/mxstudio-report.png)

## Checks
```
PASS  M1  KpiView, FindingCard, line markers and Heatmap in mojoui with tests; the matrix shows them ✅ on Linux and web
PASS  M2  REPORT: worst fall West heavy 7.66 points on 96927 orders; Q3 KPIs = CPU
PASS  M3  the Report on both hosts: filters, four KPIs, weekly revenue and margin (the marker proven in test_components), top customers, product mix, heatmap, 'Worth a look' with the cause it found; the West filter changes the KPIs
PASS  M4  one engine: the Sheet's merge reaches the Report; Open the rows filters the Sheet to the finding's rows; a product bar filters the tiles; identical on both hosts
PASS  M5  goal 11's checks (and goals 3–10's inside them) pass
```

That is the final run from scratch (commit d46cd53). The run before it failed only M5 (goals 3–11 inside it), on three things fixed without touching a check:
- MX Studio imported its own modules, which breaks goal 3's "apps import only mojoui" rule. They moved into `mojoui/` (D-126).
- With no theme file the accent wasn't Tokyo Night's (D-127).
- The README's Android row lost the word goal 7 looks for.

Goal 6's lens also ran at 54 fps on that busy machine. Run alone it held 60.0 fps three times out of three, and it passed in the final run.

## Components added
| Component | Linux | Web | Used by |
|---|---|---|---|
| KpiView (native labels + sparkline, tone set by the app) | ✅ | ✅ | MX Studio |
| FindingCard (warning / resolved, actions, look again) | ✅ | ✅ | MX Studio (Sheet and Report) |
| LineChart: second series (share) + event marker | ✅ | ✅ | MX Studio |
| Heatmap (tap a cell) | ✅ | ✅ | MX Studio |

## Proven against the CPU (tests/test_report.mojo)
The anomaly group, its order count and its cause; weekly revenue and margin, the region × product heatmap, product shares and KPIs, with a region filter and a session edit (the GPU base plus the edit's delta).

## Review
One round, NEEDS WORK, all addressed: the finding no longer states a cause it didn't compute (D-122); the host checks now assert the KPIs (20 → 18 after a merge; filters change them); the marker test compares the chart with and without the marker; Q4 is compared over the same days (D-123); negative heatmap shares print right; KPI tones come from the app (D-124); the finder runs again only after edits.

## Next
Goal 13 (keys: arrows, typing, Escape in the grid), drafted in docs/plans/GOAL13.md. What waits for MX frame: docs/plans/needs-mxframe.md.
