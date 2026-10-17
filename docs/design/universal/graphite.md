# omxplorer · Graphite (dark, notebook-style)

One fixed look on every platform for people who live in dark editors and notebooks: neutral graphite (no blue tint), crisp white figures, a warm amber accent that reads instantly on dark.

## Colour (exact values)
- Window chrome and toolbar: #121214 · Page behind the sheet: #161618 · Sheet, tables, cards, inspector: #1d1e21
- Raised (hover, header row, gutter): #26272b · Selection fill: #3a2f17 · Hairline: #2e3034 · Strong line: #44464c
- Ink (text, numbers): #ececee · Body: #c2c4ca · Secondary: #858892
- Accent (selection ring, primary button, active tab, focus): #f5a524, text on accent #1d1e21
- Formula values: #b48cff · Good: #3ddc97 · Bad: #ff6b6b · Warning: #f5a524
- Chart series in order (colour-blind safe): #4cc2ff, #f5a524, #b48cff, #3ddc97, #ff6b6b, #e0c341, #8f98a8, #ff9de2

## Type (bundled with the app, so every platform looks identical)
- UI: Inter. 13px body, 12px captions, 11px toolbar labels, 15px section titles (600), 20px page titles (700).
- Numbers and code: JetBrains Mono, tabular, right-aligned in columns. Cell values, formulas, KPI figures and the status bar use it.

## Shape and depth
- Flat. No gradients, glass or blur. Only floating menus and dialogs get one soft shadow (0 4px 16px at 12%).
- Radius: 6px panels, cards and buttons; 4px inputs and chips; 0 for table cells.
- Icons: Lucide line icons, 1.5px stroke, 18px. Never emoji.

## Components (same on Linux, Mac, Windows, web and iPad; never the platform native look)
- Toolbar: icon-above-label buttons 64px wide, in groups separated by thin vertical hairlines; hover fills the raised colour; an active tool has the accent tint.
- Formula bar: cell reference box, "fx" label, monospace input, cancel and accept buttons.
- Data grid: row-number gutter 48px, header row with the column name, a small type badge (#, $, Aa, calendar) and a tiny distribution histogram under the name; body rows 28px with hairlines; selected cell 2px accent ring; selected column tinted; formula columns show their values in the formula colour.
- Inspector: right panel 300px, tabs across the top, small uppercase section titles, flat dropdowns, segmented controls, steppers, switches.
- Sheet tabs: bottom-left, like Excel: flat tabs, active tab on the surface colour with a 2px accent top edge, then a + button.
- Status bar: 26px, monospace figures: rows, selection sum / average / count, the GPU name and the last computation time.
- KPI card: label, big monospace figure, sparkline, delta chip (good or bad colour).
- Charts: flat, thin gridlines, no 3D, the chart series in order.

## Motion
- Short fades only (120 ms). No springs, zooms or blur.
