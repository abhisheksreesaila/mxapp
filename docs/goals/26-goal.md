# GOAL 26: the Scene spike: the grid as a display list on GTK's GPU renderer

**End goal (owner, 2026-10-19):** "we need to figure out the best rendering algorithm to leave perf off the table… pick the option which is the fastest, balanced with native feel + supporting the agent host and AG-UI." Chosen (D-252, D-253): content views draw a **display list (Scene) with keyed layers**, replayed by each host's own GPU path; text by each host's own engine. **The bar (owner: "super fast… it should feel like liquid… this is the whole point of the framework, or the Rust guys win"):** 120 fps on a 2.8k×1.4k window (the owner's 3440×1440 at 1.6×) while scrolling 1M rows and gliding the selection; ≤ 2 ms of main-thread work a frame; zero content repaints when only something moves; input on screen within one frame. The pixels go to the GPU (Vulkan on Linux, Metal on Apple Silicon); MX frame keeps the data on the GPU too (two GPUs: one can draw while the other computes). If GTK's render nodes can't meet the bar, plan B is our own instanced GPU renderer (option E, Zed's recipe), not a lower bar. This goal proves it on GTK with omxplorer's grid, behind `MOJOUI_SCENE=1`; today's path stays the default until the numbers say otherwise. Research: docs/research/rendering.md.

**Also (owner, 2026-10-19, after trying goal 25):** "when I was selecting multi cells… the box would be drawn on top of it… it didn't follow my cursor"; "the scroll bar didn't work on the import preview"; "some sort of a border or line… the column metadata… looked like without borders"; "when you insert a chart there's a cross mark… it should appear if you hover… not be there by default".

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M0 | The owner's four | with real input (scripts/live.py): during a drag the selected block's corner is under the pointer on every frame (no glide while dragging; arrow keys still glide); the import preview's scroll bar drags the rows (and the preview still selects nothing); the inspector's sections are separated by hairlines (GTK and the web); report tiles' and charts' remove buttons are hidden until the tile is hovered (GTK and the web) |
| M1 | Today measured | at 2800×1400 with 1M rows: a scroll frame and a glide frame, paint ms and texture ms apart (GTK, headless: CPU numbers), written to docs/goals/26/baseline.txt |
| M2 | A Scene | `mojoui/scene.mojo`: rect, rounded rect, line, text run, image, clip, layer (key, version), flat arrays; its tests; `scene.raster(surface)` (the CPU reference) draws a test scene to the pixels the old calls drew |
| M3 | The grid as a Scene | `DataGrid.draw_scene`: the same picture as `draw()` (the CPU replay of the Scene against `draw()`: nearly every pixel equal, text aside), the ring and its handle in their own layer; items can carry a meaning ("cell amount 2") the agent host reads |
| M4 | GTK draws the Scene | with `MOJOUI_SCENE=1` the GTK host replays it into GtkSnapshot render nodes (text: Pango text nodes, Inter), one paintable on the existing picture; a layer that comes again unchanged is reused (by its version when the drawing code gives one, else by comparing its items: the grid's cells are compared, D-257); screenshots of the old and new paths side by side (`build/g26/compare.html`) |
| M5 | The numbers | at 2800×1400 with 1M rows (main-thread CPU, headless): a scroll frame (Scene build + replay) ≤ 2 ms p95; a glide: 0 cell-layer builds, ≤ 0.3 ms a frame, no texture upload |
| M6 | On a real GPU | `scripts/scene-bench.sh` runs the same scroll and glide on the owner's display and prints frame intervals (proven if ≥ 99 % ≤ 9.5 ms at 120 Hz); waits for the owner's run (marked blocked, not faked) |
| M8 | The brand (owner's pick, D-254) | logo 1 in the menu bar and as the app icon; indigo #4f46e5 for the brand chrome; the sheet's accent Ledger green #0e7a43 and the report's Signal red #c8243f (ring, active tools, column highlight, tile accents), on GTK and the web, switching with the tab; in the report, false pills and errors are not red; contrast AA for every accent pair |
| M7 | Nothing regressed | goal 25's checks (M1–M7, every earlier goal inside them) pass with the flag off, and its M1–M6 with the flag on |

## Out of bounds
The web, Apple and Android replayers; charts and the lens on the Scene; moving work off the UI thread; making the Scene the default; the chart inspector (goal 27: the toolbar inserts, the inspector formats: Chart / Axis / Series); the query/pipeline mode's blue (designed with that mode).

## Done means
`scripts/check` prints PASS for M0–M5, M7 and M8; M6 is ready for the owner's run (blocked on them, not faked); the reviewer passes it; `docs/report.md` is short, with numbers. Push to `origin` after (owner's standing permission).

## After this goal (owner, 2026-10-19)
A showcase README for the world, built with the designer skill in Liquid once the GPU rendering works and the app "kicks ass": hero screenshots and motion clips of omxplorer, measured numbers (120 fps proof, MX frame on the GPU), the architecture in one picture (view tree → partial updates → Scene and layers → each platform's GPU; agent host and AG-UI), the component gallery per skin and platform, and an honest status (proven, built but unverified, next).
