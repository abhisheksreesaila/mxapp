# omxplorer · editing a chart without Excel (2026-10-19)

Open `index.html` (1480 px wide or more) and reply "charts 1", "2" or "3".
The Report tab at 1440×900 with a chart tile selected. The toolbar only **inserts** (Sum / Average / Count tile, Chart); everything about the selected chart lives in the inspector, the way a cell's formatting does. The data is real: 4,000 synthetic orders in 2025 (amount, region, day, paid), and every change recomputes the groups (sum / average / count / median, group by, sort, top N, period, paid). The accent dots swap the accent colour.
URL shortcuts: `?dir=1&page=data`, `?dir=2&sel=West`, `?dir=3&ask=top 3, unpaid, as a donut`.

## Directions
- **1 · Inspector pages + live variants.** Selecting the chart turns the inspector into "Chart". On top: five **live thumbnails of your data** (Bars, Line, Area, Donut, Heatmap): you never pick a type blind; tap one and the chart cross-fades. Below: four rows that **say what is set** (Data: "Sum of amount · by region · all year"; Style; Axes; Labels and legend). Each opens a **sub-inspector page that slides in** with a back chevron (Esc goes back). Data has Value, Combine (Sum / Average / Count / Median), Group by, Sort, Top N stepper, Period and Paid filters, plus a live "4,000 orders → 5 groups in 0.4 ms" line. Style has palettes as cards (Accent, a colour per region, grey + highlight), a dot per category, bar ends, one bar or paid / unpaid. Axes keeps bars at 0 on purpose and offers Ends at, number format, gridlines.
- **2 · On the chart.** The chart grows **encoding wells**: y (top-left), x (under the axis), colour (top-right). **Drag a column chip** from the inspector onto a well (paid onto colour gives paid / unpaid bars; day onto x groups by month); wells light up while you drag. **Click a bar**: a small popover to recolour it, hide it, or keep only it, and the inspector shows that bar's numbers like a cell's details (value, orders, share). **Drag the "max" grip** on the axis to set the range (double-click for auto). Hidden bars show in the footer with "Show all".
- **3 · The title is the query.** The chart's title is a sentence: "**Sum** of amount by **region**, **every** region, **largest first**, in **all of 2025**, **all orders**, as **bars**". Every coloured word is a setting: tap it for its choices. An **ask field** under it changes several at once ("by month as a line, only paid", "top 3, unpaid, last 90 days"), echoes what it understood, and flashes the words that changed. Edits stack in the inspector ("Back to here"). This is a keyword parser, not an AI: it works offline and is instant.

## Recommendation: 1 as the structure, with 3's sentence title and 2's click-a-bar
1 is the inspector the owner asked for and the baseline to beat (Numbers' Chart / Axis / Series / Arrange tabs): it beats Numbers by showing the current value on every row and by thumbnails drawn from your own data. Take the **sentence title from 3** for every chart (it doubles as the chart's readable title and a one-tap editor) and **click a bar → recolour / hide from 2**. Keep the ask field and column dragging for later: they are the most original parts and also the riskiest.

Honest cons:
- **1** is still a settings panel; on its own it is the least distinctive and could be called "Numbers with nicer rows". Sub-pages hide their contents (one more tap to check), which the summaries only partly offset.
- **2** is the most fun but the hardest to discover (people don't know they can drag a column onto a chart), needs hover / drag affordances that don't exist on touch, and the wells add chrome on top of the chart. The axis grip only makes sense for bars and lines.
- **3** reads beautifully but the sentence gets long with many settings (a filter on two columns would wrap); the parser only understands its own words, and if it mis-hears, trust drops fast. Typing is slower than tapping for small changes.
- Colour: the series palette fails the dataviz validator's chroma check for today's teal (reads greyish for a category) and amber / green are below 3:1 on white; the prototype keeps value labels on and a 2 px gap between bars as relief. If indigo (brand C) is picked, re-run the validator.

## What it would take in mojo-ui
Exists (see `docs/components.md` and `mojoui/inspector.mojo`): `Inspector`, `Section`, `Row`, `Stepper`, `StatCards`, `Segmented`, `Toggle`, `Dropdown`, `Popover`, `Swatch picker` (`mojoui/swatches.mojo`), `ChartView` on `Canvas` (bars, line; GTK and web), `Report page` tiles, the GPU group-by in MX frame.

New:
1. **Inspector navigation stack** (`InspectorPage`, push / pop with a back chevron, 280 ms slide, the parent drifting 30 % and fading; Esc pops). On GTK: a GtkStack with `SLIDE_LEFT_RIGHT`, which is native. Needed by every direction.
2. **Nav row** (icon tile, title, one-line summary, chevron): small, extends `Row`.
3. **Chart spec model** (type, value, combine, group by, sort, top N, filters, palette, per-category colours, hidden, axis max, labels, legend) shared by sheet charts and report tiles; today these are separate inspector sections in `examples/omxplorer` (listed as debt in the matrix).
4. **ChartView: keyed marks that tween** (bars move and resize over 320 ms instead of redrawing), donut, area, heatmap, legend, value labels, hover tooltip. Drawn on `Canvas` with `on_frame`.
5. **Variant thumbnails**: `ChartView` at 48×32 with no axes, fed the same groups.
6. **(2) Drop wells and drag ghost**: needs a drag source on the inspector chips and drop targets on the chart's Canvas (`PRESS` / `RELEASE` exist; cross-widget drag does not).
7. **(2) Mark hit-testing and the axis grip** on ChartView (tap exists; drag on a sub-area is new).
8. **(3) Token text**: a rich label whose words are tappable and open a `Popover`; and the ask parser (plain Mojo, testable without UI).

Screenshots from the prototype (headless Chromium, 1440×900): `shot-1-root.png`, `shot-1-data.png`, `shot-2-mark.png`, `shot-2-paid-colour.png`, `shot-3-ask.png`.
