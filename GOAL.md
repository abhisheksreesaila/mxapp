# GOAL 8: the analytics showcase (Linux + web), polished

**End goal (owner's words, 2026-10-15):** "the analytics part… that's the poster child for all this… make this really polished and really good"; "UI charts with some sample data… then MX frame… load data, put them on GPU and then try to aggregate on GPU… render it on the UI"; "a common [design] language between the native and the web"; "push it to GitHub… put the gallery showcase so people can see". Linux and web now; the Mac after MX frame gains a Mojo-level API.

A Power BI / Tableau-style dashboard in one Mojo file: tens of millions of rows aggregated on the GPU every time a filter changes, drawn as charts the app paints itself (the same on every platform), around native controls styled in one shared design language (Fluent 2).

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | Design language | `design()` = FLUENT applies Fluent 2 tokens on web (CSS) and GTK (CSS); `Card` container on every host; core tests pass |
| M2 | Text on canvas | an anti-aliased font atlas (Noto Sans, baked from the font file) draws text at any scale; widths within 2 px of the font's own metrics; tests pass |
| M3 | Charts | `mojoui.charts`: KPI tile, bar, line/area, histogram, with axes, gridlines, labels, selection and hit-testing; tests pass |
| M4 | GPU aggregation | `mojoui.gpu` group-by sums over int32 columns, exact (64-bit): 20M rows, GPU = CPU to the cent, ≤ 5 ms per group-by |
| M5 | Analytics app | `examples/analytics` (20M synthetic order lines): KPIs, revenue by month, by category and by region (tap to filter), order-value histogram, top products, year/channel filters; GTK + web end in the same state after the same clicks; fits 1440×900 and 1280×800 without scrolling on both; rich screenshots |
| M6 | MX frame | the app's engine switch runs the same aggregates through MX frame (CPU), on web + Linux; MX frame and GPU totals agree exactly on the same data |
| M7 | Gallery | `docs/gallery/index.html`: an interactive showcase (native shines / web shines / both, one Mojo file each), every image and link resolving, no console errors; published on GitHub Pages |
| M8 | MX frame API spec | `docs/mxframe-mojo-api.md`: the Mojo-level API the Mac/native version needs (types, calls, memory, devices), from the app's real call sites |
| M9 | Nothing regressed | goal 7's checks still pass |
| M10 | Docs | README: the analytics showcase, how to run it on Linux and the web, the gallery link |

## Out of bounds
No deploying anything but the gallery's GitHub Pages site; push to `origin` (the owner asked for it) only after the checks pass; no sign-ups, secrets or licences; windows may show during checks; don't touch `../mojo-ui-apple-test`.

## Assumptions
- "Flint" = Fluent 2, Microsoft's design system (the owner's words were "a design language called Flint which [Microsoft] use"): tokens shared by the charts (drawn by Mojo) and the native/web chrome. Light theme.
- Charts are drawn by Mojo on Canvas views (no common native chart widget exists); numbers on KPI tiles too, so every platform looks the same. Text on canvases comes from a baked font atlas (Noto Sans, SIL OFL, installed here).
- Sample data: synthetic retail order lines with seasonality (shaped so charts tell a story), generated deterministically; MX frame runs over the same columns.
- Interactions are taps (filters, selections); hover tooltips need a pointer-move event mojoui doesn't have yet.
- The web shows charts as PNG frames (crisp text); JPEG only while animating.

## Budget
~4 hours. Stop with a clear report if blocked.
