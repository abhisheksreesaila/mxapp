# GOAL 14: omxplorer from scratch: open a CSV, a Numbers-style sheet with formats (Linux + web)

**End goal (owner's words, 2026-10-16):** "I should be able to install this Linux app, load some data from CSV… get the thing up and running, add a report… use it from scratch as opposed to having widgets on a screen"; "follow [the Stitch designs]… I like the classic design, not the island"; "this product will be called [omxplorer]"; "focus on the web and the Linux for now… load one million… once you get the features right then try it on 10, 50, 100 million… dazzle me."

Design: the Stitch classic screens in `docs/design/mxstudio-app/` (01 start, 02 import, 03 sheet classic; 05 chart and 06 report are goal 15). Language: Omarchy (JetBrains Mono, flat, Tokyo Night). New app: `examples/omxplorer` (the earlier `examples/mxstudio` stays as a showcase: thirteen goals of checks name it).

## Components this needs (from `docs/components.md`, before the build)
| Component | Before | Plan |
|---|---|---|
| Toolbar button, icon over label (Numbers) | ❌ (`Button(icon=)` puts the icon beside the text) | `Button(style=TOOL)` on GTK and web |
| File picker | ❌ every host | `FilePicker(title, on_pick)`: GTK's file dialog; web upload; a test step `pick:` |
| Inspector (tabs + titled sections of controls) | ❌ (each app wires its own) | `mojoui/inspector.mojo`: `Inspector(tabs, sections)` built from Segmented/Dropdown/Toggle/Text |
| Stepper (− value +) | ❌ | `Stepper(value, on_change)` composite |
| Formula bar, sheet tabs, status bar | app-local in the Workbook / MX Studio | `mojoui/sheetchrome.mojo`, used by omxplorer |
| Column number formats (currency, percent, decimals, thousands, negatives, compact, dates) | ❌ | `ColumnFormat` in `mojoui/frame.mojo`, drawn by DataGrid, followed by pivots, charts and the status bar |
| CSV reader | ❌ (MX frame's job) | `mojoui/csvio.mojo`: SHIM through pyarrow until MX frame's readers land; types inferred; logged in `docs/plans/needs-mxframe.md` |

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | The components | TOOL buttons, FilePicker, Inspector, Stepper, sheet chrome in mojoui with tests; the matrix lists them ✅ on Linux and web |
| M2 | Start → import a CSV | omxplorer opens on the Start screen (Stitch 01); picking `orders_1m.csv` (1,000,000 rows, 12 columns) shows the Import step (Stitch 02: columns, inferred types, row count) and creates a table; the sums of revenue and qty equal an independent pass over the CSV; identical on GTK and web |
| M3 | The sheet, Numbers classic | Stitch 03: toolbar, sheet tabs, formula bar, grid, inspector (Table · Cell), status bar; choosing Currency / Percent / decimals / thousands / negatives in the inspector changes the column everywhere (grid cells, status-bar sum, a pivot of it); add a row; add a formula column from the toolbar; sort; identical on GTK and web |
| M4 | Save and open | Save writes `.omx` (the table, its formats, its formulas, edits); opening it restores the same screen on both hosts |
| M5 | Scale | the same CSV at 1M (default), then 10M, 50M, 100M rows: import, sort, recompute and first-draw times measured on this machine and written to the report; 1M meets: import < 5 s, sort < 1 s, a format change < 50 ms |
| M6 | Nothing regressed | goal 13's checks (and goals 3–12's inside them) still pass; the matrix is current |

## Done means
`scripts/check` prints PASS for M1–M6; push to `origin` after.

## Out of bounds
No deploys, sign-ups or secrets. Checks headless. Charts, pivots placed by the user and the Report tab are goal 15 (Stitch 05, 06). Other platforms: components copied only where trivial (the owner tests them on the weekend).

## Assumptions
- Name spelled **omxplorer**, all lowercase, one word (owner); one rename if the owner meant otherwise.
- CSV reading goes through pyarrow as a labelled SHIM (fast, correct quoting and types) until MX frame's readers exist.
- One table per sheet for now; multiple sheets later.
- Budget: the night (about 7 hours).
