# omxplorer · Liquid (light) — the showcase skin

A desktop data app that feels like a first-party Mac app: a calm white sheet, the controls floating above it on frosted glass, everything moving on springs. Liquid's two layers: **content is solid, controls are glass.**

## Colour (exact values)
- Window backdrop behind everything: a very soft cool gradient #eef2f7 → #e6ebf2 (top to bottom).
- Content layer (solid, opaque): sheet, tables, cards, report page #ffffff. Raised rows / header row #f6f8fb. Hairline rgba(15,23,42,0.07). Strong line rgba(15,23,42,0.14).
- Control layer (glass): toolbar, menu bar, inspector, sheet tabs, status bar, menus, popovers, dialogs: rgba(255,255,255,0.62) with 24px background blur and saturate 1.6, a 1px rgba(255,255,255,0.75) rim, a 1px inner top highlight rgba(255,255,255,0.9) and shadow 0 8px 32px rgba(15,23,42,0.10), 0 1px 2px rgba(15,23,42,0.06).
- Ink #0f172a · Body #334155 · Secondary #64748b · Tertiary #94a3b8.
- One accent, omxplorer's deep teal: #0e7c86 (hover #0b6870), wash rgba(14,124,134,0.10), selection fill rgba(14,124,134,0.08), text on accent #ffffff.
- Formula values #6a4fd6. Good #16a34a. Bad #dc2626. Warning #d97706.
- Chart series in order: #0e7c86, #f59e0b, #6366f1, #ec4899, #22c55e, #a16207, #64748b, #c026d3.

## Type
- Inter everywhere (it reads like SF Pro), tabular figures for every number. JetBrains Mono only for formulas and the formula bar.
- 13px body, 12px captions, 11px toolbar labels (500), 15px section titles (600), 22px page titles (700, -0.3px tracking), 34px for the one big number on a tile (650).
- Two weights per screen besides titles: 400 and 500.

## Shape (concentric)
- Window 14px. Floating glass islands 18px with 6px inner padding, so buttons inside are 12px. Cards and report tiles 16px. Menus 14px with 6px padding, items 8px. Inputs and dropdowns 10px. Chips, toggles, segmented thumbs, icon buttons: fully round. Table cells 0; the selection ring 4px.
- Islands float 10px in from the window edges with 10px between them; content scrolls under them.

## Components
- **Menu bar:** a slim glass strip, 13px items, every menu the same type; menus open as one glass panel (never glass on glass: a submenu is a solid white panel), items 30px with icon, label, shortcut right-aligned in tertiary text, a chevron for submenus.
- **Toolbar:** one floating glass island, icon-above-label buttons (18px Lucide icons, 1.5px stroke, 11px labels), groups separated by 12px of space and a faint 1px divider; hover shows a soft round-rect fill; the active tool a teal wash. Left: Save, Undo. Middle: the tab's tools. Right: Format.
- **Grid:** solid white, header row with name, a small round type badge and a tiny histogram; 30px rows; hairlines only horizontal; a row-number gutter in tertiary text; the selected range has a 2px teal ring with 4px corners, a soft teal fill and a small round fill handle; selected column/row headers tinted.
- **Inspector:** a floating glass panel on the right, 300px, a segmented control (glass track, solid white thumb) for its tabs; sections with small uppercase tertiary titles.
- **Sheet tabs and status bar:** one slim glass strip at the bottom: tabs as pills (active pill solid white with a soft shadow), then live figures for the selection (Sum, Average, Count), the GPU chip with a green dot.
- **Dialog / sheet:** a centred solid white panel, 20px radius, large soft shadow, over a dimmed and blurred window; title 17px 600, primary button a teal pill, secondary a quiet pill.
- **Report tile:** a white card, 16px radius, label in secondary text, the big number, the filter as a small chip; tiles sit in a tidy grid of equal widths, the remove button inside the tile's top-right corner, visible on hover.

## Motion (springs, never linear)
- Snappy spring (430 ms) for hover, press (scale 0.96) and toggles; bouncy spring (790 ms) for things that arrive (a menu, a dialog, a new tile); gentle spring (710 ms) for layout changes (the inspector sliding in, tiles reflowing). The selection ring glides between cells.
