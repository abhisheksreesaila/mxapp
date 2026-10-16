# The Workbook: a two-minute walkthrough

One Mojo file (`examples/workbook/app.mojo`) over one engine (`mojoui/frame.mojo` + `frame_gpu.mojo`): a Numbers-style page where tables, pivots, charts and notes sit side by side and share the same 20 million rows. Columns, never cell addresses.

## Open it
```bash
scripts/workbook.sh          # the native Linux window (builds first if needed)
scripts/workbook.sh web      # the same file served at http://127.0.0.1:5001
```
The first start generates the Contoso data (20M order lines, about 5 s) and uploads it to the GPU once; on the web every tab shares that one copy.

## Try, in this order
1. **Edit a cell.** Tap a cell in the table (say a `cents` value): the caption left of the **Value** box names it ("Row 3 · cents") and the box shows its value. Type the new number in the box, press Enter. The revenue total at the top changes by exactly that amount, and so do the pivot and the charts. **Undo** puts it back.
2. **Type a formula.** In the **Formula** box: `margin = cents - cost`, Enter. A new column `ƒ margin` appears in the grid, and in every pivot's and chart's value list. Try `pct = margin / cents` or `bin = min(cents // 50, 23)`.
3. **Pivot.** In the pivot card, pick rows, columns and the value (for example `category` by `year`, value `margin`). It is a group-by on the GPU: about a millisecond for 20M rows.
4. **Click a chart.** Tap a bar in "Revenue by region": everything else filters to that region (crossfiltering, Power BI style). Tap it again, or **Clear filters**, to release it.
5. **Drag things.** Drag any card by its header; drag the bottom-right corner to resize; positions snap to an 8-point grid. Narrow the window below 720 points and the page becomes a list (that's the phone layout).
6. **Add a row, delete a row, sort.** Add row appends an empty line at the end (type its values); Delete row removes the selected one; Sort orders the table by the selected cell's column: tap a cell in `cents`, press Sort (largest first; Sort again flips it). The data never moves: it's a permutation, a radix sort, about a second for 20M rows.
7. **Add a card, remove a card.** The **Insert…** menu at the top adds a Table, Pivot, Chart or Note at the bottom of the page; drag it where you want it. Every card's **Remove** button takes it away (Undo doesn't bring a card back; Open does, if you saved before).
8. **Write a note.** Type in the Note card: "please review this".
9. **Save, then Open.** Save writes `~/Documents/Contoso Workbook.mxwb/` (a folder: `workbook.json` with the objects, formulas and your edits; tables without a reproducible source get a Parquet file). Open reads it back. An agent can write that JSON as easily as you can.

## What to look at while you do
- The caption at the top right: "N ms on NVIDIA …": every edit, pivot change and filter reruns the whole page on the GPU in that time.
- Edits never copy the 20M rows: they are a sparse overlay, applied as exact deltas to the GPU totals (`docs/decisions.md`, D-80).
- The same file, the same steps, in the browser: `scripts/workbook.sh web`.
