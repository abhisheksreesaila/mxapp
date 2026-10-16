# The Workbook: a two-minute walkthrough

One Mojo file (`examples/workbook/app.mojo`) over one engine (`mojoui/frame.mojo` + `frame_gpu.mojo`): a Numbers-style page where tables, pivots, charts and notes sit side by side and share the same 20 million rows. Columns, never cell addresses.

## Open it
```bash
scripts/workbook.sh          # the native Linux window (builds first if needed)
scripts/workbook.sh web      # the same file served at http://127.0.0.1:5001
```
The first start generates the Contoso data (20M order lines, about 5 s) and uploads it to the GPU once; on the web every tab shares that one copy.

## The screen
The page is a dotted canvas you scroll (scroll bars on the right and bottom). The controls float over it in small islands: the title (top left), the **Insert** toolbar (top centre: Table, Pivot, Chart, Note, Undo), **Open** and **Save** (top right), the totals, filter and last message (bottom left) and the engine time (bottom right).

## Try, in this order
1. **Edit a cell.** Tap a cell in the table (say a `cents` value): the formula bar names it ("Row 3 · cents") and the **Value** box shows its value. Type the new number, press Enter. The revenue total at the bottom left changes by exactly that amount, and so do the pivot and the charts. **Undo** (in the toolbar) puts it back.
2. **Scroll the grid.** Drag the scroll bar's thumb on the grid's right edge, or click its track to jump; the mouse wheel moves a few rows at a time. The card's header says which rows you're looking at ("Rows 10,101,007–10,101,014 of 20,000,000").
3. **Select a column and sort it.** Tap a column header (say `cents`): the whole column turns blue and the formula bar says "Column cents". Press **Sort** in the table's header: largest first, with a ▼ in the header; Sort again flips it. A radix sort, under a second for 20M rows.
4. **Type a formula.** In the **ƒ Formula** box: `margin = cents - cost`, Enter. A new column `ƒ margin` appears in the grid, and in every pivot's and chart's value list. Try `pct = margin / cents` or `bin = min(cents // 50, 23)`.
5. **Insert a pivot from a column.** Tap the `region` header, then **Pivot** in the toolbar: a "Revenue by region and year" pivot appears in the first free space and the page scrolls to it (it flashes once on the web). Change its **Rows**, **Columns** and **Value**. A group-by on the GPU: about a millisecond for 20M rows. **Chart** works the same way (a chart of the selected column).
6. **Click a chart.** Tap a bar in "Revenue by region": everything else filters to that region (crossfiltering, Power BI style). Tap it again, or **Clear filters** (bottom left), to release it.
7. **Drag things.** Drag any card by its header; drag the bottom-right corner to resize; positions snap to an 8-point grid. The × in a card's header removes it (Undo doesn't bring a card back; Open does, if you saved before). Narrow the window below 720 points and the page becomes a list (the phone layout).
8. **Add or delete a row.** **Add row** (table header) appends an empty line at the end and selects it (type its values); **Delete row** removes the selected one.
9. **Write a note.** Type in the Note card: "please review this". **Note** in the toolbar adds another.
10. **Save, then Open.** Save writes `~/Documents/Contoso Workbook.mxwb/` (a folder: `workbook.json` with the objects, formulas and your edits; tables without a reproducible source get a Parquet file). Open reads it back. An agent can write that JSON as easily as you can.

## What to look at while you do
- The island at the bottom right: "N ms on NVIDIA …": every edit, pivot change and filter reruns the whole page on the GPU in that time (about 8 ms).
- Edits never copy the 20M rows: they are a sparse overlay, applied as exact deltas to the GPU totals (`docs/decisions.md`, D-80).
- The same file, the same steps, in the browser: `scripts/workbook.sh web`.
