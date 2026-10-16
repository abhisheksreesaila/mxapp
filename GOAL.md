# GOAL 10: the Workbook, usable (Linux + web)

**End goal (owner's words, 2026-10-16):** "the Linux apps look less enticing, it looks like some eighties product… can we theme it so that it looks good"; "the insert didn't work: it added a chart but I could not find the chart, there was no scroll bar"; "the grid needs to have a scroll bar so that I can scroll faster"; "the page needs a scroll bar"; "when you click a column it highlights the column so you know exactly what you're sorting"; "make it easy to add pivots… let me use some of the basic functionality and get comfortable, then we can go with formatting"; "we are competing with Numbers… this app is the de facto app on which the whole framework is going to be based… don't compromise on the engine; any feature that interferes with the speed, let me know".

A polish pass on the Workbook so a person can use it without being told how: an opinionated look, a page that scrolls, an Insert that shows what it inserted, a grid with a scroll bar and column selection, and pivots that start from what you selected. The engine stays as fast as goal 9 measured it. Cell formatting is planned here and built next.

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | A look | one opinionated theme on GTK and web (Fluent 2 light, Numbers-like canvas): the page is a dotted canvas with floating "islands" for the chrome (a title island, a tool island with Insert Table/Pivot/Chart/Note, Undo, Save, Open, a status island with the filter and the engine time); toolbar and card actions are quiet icon buttons (`Button(…, icon=…, style=SUBTLE)`), fields have hairline borders; no bold grey buttons left on the page; GTK and web screenshots taken at 1440×900 and checked by eye in the report |
| M2 | The page scrolls | the Board is a scrolling viewport on both hosts (a scroll bar when the page is taller or wider than the window); the GTK window keeps the size it was given whatever the page holds; a card placed below the window is reachable |
| M3 | Insert shows what it inserted | Insert Table/Pivot/Chart/Note places the card in the visible part of the page (or scrolls it into view) on both hosts; both report the new card as in view (`INVIEW:` lines identical on GTK and web) |
| M4 | Grid scroll bar | the grid draws a vertical scroll bar (thumb sized to what's shown, 20M rows included); dragging the thumb and tapping the track move the grid on both hosts to the same first row; a new `PRESS` gesture (pointer down) tells a canvas where a drag starts |
| M5 | Columns | tapping a column header selects the column (header and cells tinted, the edit bar names it); Sort sorts the selected column and the header shows ▲/▼; GTK and web end identical |
| M6 | Easy pivots | Insert Pivot starts from the selection: a text column selected becomes the pivot's rows (a number column its value); the pivot card names its fields (Rows, Columns, Value); GTK and web identical |
| M7 | Engine speed kept | `tests/bench_frame.mojo` and the workbook's own timing: a group-by ≤ 2 ms on 20M rows on the GPU, a full page recompute ≤ 15 ms, a grid redraw ≤ 16 ms, sort ≤ 2.5 s; numbers in the report beside goal 9's |
| M8 | Nothing regressed | goal 9's checks still pass (their steps follow the new UI where the owner asked for it to change; no threshold lowered) |
| M9 | Formatting planned | `docs/plans/formatting.md`: cell and column formatting (number formats, text colour/weight, fills, conditional colours) designed column-first, with what each costs the engine (memory, GPU, redraw) and the order to build it |

## Done means
`scripts/check` prints PASS for M1–M9; `git push` after.

## Out of bounds
No deploying anything but the gallery's GitHub Pages site; push to `origin` after milestones pass; no sign-ups, secrets or licences; checks run headless (no windows on the desktop); don't touch `../mojo-ui-apple-test`; no compiler fork; nothing that slows the engine without saying so in the report.

## Assumptions
- "Opinionated": Fluent 2 light (the project's design language) shaped like a canvas app, following the owner's taste file: chrome as small floating islands over the canvas, flat hairline surfaces, colour for meaning only, laptop motion a short fade at most.
- Islands need an `Overlay` container (a base view with views pinned to its edges); the Board scrolls under them.
- Insert places the new card at the top-left of the visible part of the page when it's free, else the first free spot below; the host scrolls it into view (`Board(…, reveal=…)`).
- The grid's scroll bar is drawn by the app on its Canvas (one renderer everywhere); no horizontal bar yet (all columns fit at 1360 pt; noted).
- Several Table cards show the same table with one shared selection (one table per workbook so far; noted).
- Budget: 8 hours wall clock.
