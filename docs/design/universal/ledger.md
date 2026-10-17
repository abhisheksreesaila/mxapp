# omxplorer · Ledger (light, spreadsheet-classic)

One fixed look on every platform, like Excel or Numbers: a bright white sheet, quiet grey chrome, one deep teal accent. Built for long sessions with data: calm, high contrast, numbers first.

## Colour (exact values)
- Window chrome and toolbar: #f5f6f8 · Page behind the sheet: #eef0f3 · Sheet, tables, cards, inspector: #ffffff
- Raised (hover, header row, gutter): #f0f2f5 · Selection fill: #e3f2f3 · Hairline: #e1e4e8 · Strong line: #c9ced6
- Ink (text, numbers): #1b1f24 · Body: #3d434c · Secondary: #6b7380
- Accent (selection ring, primary button, active tab, focus): #0e7c86, text on accent #ffffff
- Formula values: #6a4fd6 · Good: #1f8a4c · Bad: #c8364c · Warning: #b7791f
- Chart series in order (colour-blind safe): #0e7c86, #e8833a, #5b5fc7, #d6455d, #2e9e5b, #b8892d, #7a8594, #c45cb5

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
