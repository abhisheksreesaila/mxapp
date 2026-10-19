# omxplorer · Liquid (light) · design handoff

Engines: Stitch (project "omxplorer · liquid", 15162298038433052241) and Claude (live HTML), same brief and design system (`docs/design/liquid/liquid.md`). Side by side: `docs/design/liquid/compare.html`. Web and desktop language: Liquid light; phone: Liquid (reference only this goal).

## Chosen
**Stitch's screens** (owner, 2026-10-18: "I love the STITCH designs, I absolutely want that", D-232), with macOS-level fluidity. References: `docs/design/liquid/img/stitch-{start,import,sheet,report,phone}.png` and their HTML beside them. What that means for the build:
- **Menu bar:** the app's mark and name, the document chip (name · rows) and a GPU chip in one slim bar; the same menus as today.
- **Toolbar:** one glass island; icon-and-label tools in groups; the report's toolbar as inline icon + label pills ("+ Sum tile").
- **Sheet:** yes/no cells as small green/red pills; empty cells as a faint dash; the selected block ringed with a fill handle; histograms on the right of each header.
- **Inspector:** a "Selection Details" title with the device chip; the Format · Column · Table segmented control; column stats as small cards (Mean, Median, Std Dev, Nulls) and a frequency chart.
- **Report:** tiles with a small icon at the top-right (✕ on hover), the figure, a hairline, then a footer: the filter chip left, a fact right ("199,812 matched", "p50 exact", "σ = 2,886.7"); an "Add metric tile" dashed card; a title row with an "Active view" pill and the GPU timing in green.
- **Left out:** Stitch's invented actions (Execute Query, Export View, Share, the Window menu, Grid 3-col): GOAL.md keeps new features out of bounds.

## Tokens
Exact values in `docs/design/liquid/liquid.md`. Summary: backdrop #eef2f7 → #e6ebf2; sheet #ffffff; raised #f6f8fb; hairline rgba(15,23,42,.07); ink #0f172a / body #334155 / secondary #64748b / tertiary #94a3b8; accent #0e7c86 (wash rgba(14,124,134,.10)); glass rgba(255,255,255,.62) + rim rgba(255,255,255,.75) + highlight + shadow 0 8px 32px rgba(15,23,42,.10). Radii: window 14, islands 18, cards/tiles 16, menus 14 (items 8), inputs 10, pills full, cells 0, selection ring 4. Type: Inter (tabular figures), JetBrains Mono for formulas; scale 11 · 12 · 13 · 15 · 17 · 22 · 34 px.

## Motion
| Moment | Curve | GTK | Web |
|---|---|---|---|
| Hover, press (scale .96), toggles | snappy spring, 430 ms | CSS `transition` (cubic-bezier .2,.9,.3,1.15) | `linear()` spring |
| Menu, popover, dialog, new tile arriving | bouncy spring, 790 ms | `@keyframes` with an overshoot | `linear()` spring |
| Inspector sliding, tiles reflowing | gentle spring, 710 ms | `@keyframes` / revealer | `linear()` spring |
| Selection ring moving between cells | critically damped spring, ~120 ms | drawn on the canvas, frame clock | same, canvas |
`prefers-reduced-motion` (web) and GTK's `gtk-enable-animations=false` drop to 150 ms fades.

## Gestures
| Gesture | What it does | Visible alternative | Threshold |
|---|---|---|---|
| Drag across cells | selects the block | Shift+click, Shift+arrows | 4 pt before it counts as a drag |
| Shift+click a cell | extends the block from the anchor | Shift+arrows | — |
| Shift+arrows | grows/shrinks the block | drag | one cell per press |
| Ctrl+C on a block | copies it as tab-separated text | Edit › Copy | — |
| Hover a tile | shows its ✕ in the corner | View › Report tile menu | 0 ms in, 120 ms out |

## States
Empty report (a dashed "Add a tile" card), import of a streamed file (the amber note under the column table), a long file name (ellipsised in the title, full in a tooltip), no GPU (the chip says "CPU" in grey).

## Phone
Reference only: glass top bar, a strip of round tools, the grid as a solid sheet, a glass bottom sheet with the selection's figures and quick formats, a floating glass tab bar (Sheet, Report, +). Brand pieces shared with the desktop: the teal accent, Inter, the histogram headers.
