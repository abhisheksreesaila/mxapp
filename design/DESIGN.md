# MX Studio · Omarchy design system (desktop)

The person's Omarchy desktop theme (Tokyo Night), applied to a native data app. Flat, technical, calm. Dark only.

## Colour (exact values, nothing else)
- Page (behind sheets): #13141c   · Window chrome / toolbar: #0e0e14
- Surface (tables, cards, inspector): #1a1b26   · Raised (hover, header rows, selected row band): #24283b
- Selection fill: #292e42   · Hairline: #2a2e40   · Strong line: #414868
- Ink (primary text, numbers): #c0caf5   · Body text: #a9b1d6   · Secondary text: #565f89
- Accent (focus, selection ring, primary button, active tab): #7aa2f7, text on accent #1a1b26
- Formula / computed values: #ad8ee6 (magenta)   · Good: #9ece6a   · Bad: #f7768e   · Warning: #e0af68
- Chart series in order: #7aa2f7, #449dab, #ad8ee6, #e0af68, #9ece6a, #f7768e, #0db9d7, #eb927b

## Type
- One family everywhere: JetBrains Mono (numbers line up in columns). 13px body, 12px captions, 15px section titles (medium), 20px sheet title (bold). Numbers right-aligned, tabular.

## Shape and depth
- Flat. No gradients, no glass, no blur, no drop shadows except a 1px hairline (#2a2e40) around floating panels.
- Radius: 6px panels and buttons, 4px inputs and chips, 0 for table cells.
- Toolbar buttons: icon above a 11px label (as in Apple Numbers), 64px wide, no button outline; hover fills #24283b.
- Icons: Lucide line icons, 1.5px stroke, 18px. Never emoji.

## Components
- **Table**: header row #24283b with medium text, body rows #1a1b26 with hairlines, row numbers in a 48px gutter (#565f89), selected cell 2px accent ring, selected column header tinted #292e42; footer row for totals; a small "+" handle under the last row and right of the last column to add rows/columns.
- **Inspector**: right panel 300px, tabs across the top (Table · Cell · Text · Arrange or Chart · Data), sections with small caps titles, controls are flat dropdowns, segmented controls, steppers, colour swatches.
- **Sheet tabs**: a row of flat tabs under the toolbar, active tab ink text with a 2px accent underline, "+" at the end.
- **Formula bar**: appears above the table while editing: "ƒx" label, mono input, Cancel ✕ and Accept ✓.
- **Dialogs**: centred sheet panel #1a1b26 with hairline, title 15px, primary button accent, secondary flat.

## Motion
- Laptop: short fades only (120 ms). No springs, zooms or blurs.
