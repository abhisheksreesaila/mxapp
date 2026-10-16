# GOAL 11: MX Studio's Sheet, components first (Linux + web)

**End goal (owner's words, 2026-10-16):** "the killer app is the data transformation app… I'm showing you how it would look like, the end product"; "the core mission is still one language which we can compile for all platforms… focus on these two platforms now [Linux and web]"; "every time ask yourself what component do I need, then build the component and add it to the ever-growing list… then go back and build the app with those components". Source: `docs/mx-studio/` (PLAN.md rung 1, MX_STUDIO.md A1/A2, SCREENS.md §1).

The smallest proof of rung 1: MX Studio's **Sheet** (a page with a transactions grid, a pivot and a chart over one engine, editable, with an inspector) plus the **agent finding** that drives its story (duplicate customer spellings → merge), on the planted-story orders data, built from components that live in `mojoui/` and show in the component matrix.

## Components this needs (from `docs/components.md`, before the build)
| Component | Status before | Plan |
|---|---|---|
| `DataGrid` (virtual grid, scroll bar, select, sort, resize, fit, edit in place, header histograms) | ❌ app-local in the Workbook | extract into `mojoui/datagrid.mojo`; the Workbook and MX Studio both use it |
| `PivotTable` (rows × columns × value grid with totals and highlighted rows) | ❌ app-local | `mojoui/pivot.mojo` |
| `ChartView` (a Flint spec on a Canvas, tap-to-select, themed) | ❌ app-local wiring | `mojoui/chartview.mojo` |
| `Card` tones (warning / good) for agent findings | ❌ | `Card(…, tone=)` on GTK and web |
| `Segmented` (mode switch), `Tabs` (sheet tabs), `Overlay` + `.pin` (inspector), `Button(icon=)`, `TextField` | ✅ Linux + web | reuse |

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | DataGrid component | `mojoui/datagrid.mojo` with a `GridSource` trait; `tests/test_datagrid.mojo` (scroll bar, cell and column select, sort marker, resize, fit, sideways scroll, in-place editor placement, header histograms) passes; the Workbook is rebuilt on it and goal 10's grid checks (M4, M5, M11, M12) still pass |
| M2 | PivotTable, ChartView, Card tones | `mojoui/pivot.mojo`, `mojoui/chartview.mojo`, `Card(tone=)` on GTK and web, each with a test; the Workbook's pivot and charts use them; the component matrix lists all four ✅ on Linux and web |
| M3 | The planted-story orders data | `examples/mxstudio/orders.mojo` generates N rows (default 2M, `MOJOUI_ROWS`) deterministically with SCREENS.md's story: Acme Corp under 3 spellings, Carrier A's flat $14.20 freight on parcels over 4 kg from Jul 14, Q3 margin falling ~3 points, 412 duplicate orders at ZIP 94110; `tests/test_orders.mojo` proves each planted fact with exact counts |
| M4 | The Sheet | `examples/mxstudio`: top bar (title, mode switch Sheet · Report · Explore · Query, Insert buttons), sheet tabs, the Transactions DataGrid, Pivot 1 (revenue, customer × product), Chart 1 (from Pivot 1), an exact status bar (rows, sum revenue, distinct customers, ms), an inspector island (Comes from, Feeds, Your edits, Undo all edits); editing a customer cell changes the pivot, chart and status bar identically on GTK and web |
| M5 | The agent finding | the engine finds near-duplicate spellings (normalised names) with the rows behind them; an agent card (warning tone) says so and offers "Merge into Acme Corp"; merging is one undoable operation in the edit log (a value merge, not millions of cell edits); the pivot regroups and the card turns into the green "names are clean" card; identical on GTK and web |
| M6 | Nothing regressed | goal 10's checks still pass; the component matrix is current |

## Done means
`scripts/check` prints PASS for M1–M6; push to `origin` after.

## Out of bounds
No deploying; no sign-ups, secrets or licences; push only to this repo's `origin`; checks run headless; don't touch `../mojo-ui-apple-test`; no compiler fork; Report, Explore, Query, MCP tools, Doc Intelligence and the 3D/animation rungs are later goals.

## Assumptions
- Rung 1 starts with A1 + the A2 finding; the other modes show in the switch but say "next" (one screen proven end to end beats four sketches).
- The look is the owner's Omarchy theme (their latest instruction: "default it to Omarchy… everywhere"), not the handoff's Liquid Glass light; layout and interactions follow SCREENS.md.
- The engine is mojo-ui's frame (`mojoui/frame.mojo` + `frame_gpu.mojo`) until MX Frame's Mojo API lands (`docs/mxframe-mojo-api.md`); operations are Mojo functions in `examples/mxstudio/ops.mojo` with typed results, so an MCP layer can expose them later ("engine op → agent tool → UI").
- A merge of spellings is a dictionary-level alias (codes folded at read and aggregation time): O(dictionary), not O(rows), and undo is exact.
- Default data size 2M rows for fast iteration (owner: "reduce the data size… then scale it up"); the checks also run it once at 20M.
- Budget: 6 hours wall clock.
