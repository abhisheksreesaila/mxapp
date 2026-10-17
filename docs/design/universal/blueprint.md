# omxplorer · Blueprint (light with a branded navy band)

One fixed look on every platform with a strong identity, the way Office apps carry a coloured title band: a deep navy title bar and toolbar with white icons over a bright white sheet, and a clear blue accent.

## Colour (exact values)
- Title bar and toolbar band: #14213d, icons and labels on it #e8edf7, hover on it #22325a, active tool on it #2f6fed
- Page behind the sheet: #f3f5f9 · Sheet, tables, cards, inspector: #ffffff
- Raised (header row, gutter): #f1f4f9 · Selection fill: #e5eefe · Hairline: #e0e5ee · Strong line: #c5cede
- Ink (text, numbers): #111827 · Body: #374151 · Secondary: #6b7280
- Accent (selection ring, primary button, active tab, focus): #2f6fed, text on accent #ffffff
- Formula values: #7b3fe4 · Good: #138a52 · Bad: #d23f57 · Warning: #b7791f
- Chart series in order (colour-blind safe): #2f6fed, #f08c2e, #13a39a, #d9485f, #7b61ff, #8aa23b, #6b7785, #c2569f

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
