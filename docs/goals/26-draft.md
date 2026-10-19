# GOAL 26 (draft): the Scene spike: the grid as a display list on GTK's GPU renderer

**End goal (owner, 2026-10-19):** "we need to figure out the best rendering algorithm to leave perf off the table… pick the option which is the fastest, balanced with native feel + supporting the agent host and AG-UI." Chosen (D-252, D-253): content views draw a **display list (Scene) with keyed layers**, replayed by each host's own GPU path; text by each host's own engine. **The bar (owner: "super fast… it should feel like liquid… this is the whole point of the framework, or the Rust guys win"):** 120 fps on a 2.8k×1.4k window (the owner's 3440×1440 at 1.6×) while scrolling 1M rows and gliding the selection; ≤ 2 ms of main-thread work a frame; zero content repaints when only something moves; input on screen within one frame. The pixels go to the GPU (Vulkan on Linux, Metal on Apple Silicon); MX frame keeps the data on the GPU too (two GPUs: one can draw while the other computes). If GTK's render nodes can't meet the bar, plan B is our own instanced GPU renderer (option E, Zed's recipe), not a lower bar. This goal proves it on GTK with omxplorer's grid, behind `MOJOUI_SCENE=1`; today's path stays the default until the numbers say otherwise. Research: docs/research/rendering.md.

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | Today measured | at 2800×1400 with 1M rows: a scroll frame and a glide frame, paint ms and texture ms apart (GTK, headless: CPU numbers), written to docs/goals/26/baseline.txt |
| M2 | A Scene | `mojoui/scene.mojo`: rect, rounded rect, line, text run, image, clip, layer (key, version), flat arrays; its tests; `scene.raster(surface)` (the CPU reference) draws a test scene to the pixels the old calls drew |
| M3 | The grid as a Scene | `DataGrid.draw_scene`: the same picture as `draw()` (the CPU replay of the Scene against `draw()`: nearly every pixel equal, text aside), the ring and its handle in their own layer; items can carry a meaning ("cell amount 2") the agent host reads |
| M4 | GTK draws the Scene | with `MOJOUI_SCENE=1` the GTK host replays it into GtkSnapshot render nodes (text: Pango text nodes, Inter), one paintable on the existing picture; the cells layer is reused by version; screenshots of the old and new paths side by side (`build/g26/compare.html`) |
| M5 | The numbers | at 2800×1400 with 1M rows (main-thread CPU, headless): a scroll frame (Scene build + replay) ≤ 2 ms p95; a glide: 0 cell-layer builds, ≤ 0.3 ms a frame, no texture upload |
| M6 | On a real GPU | `scripts/scene-bench.sh` runs the same scroll and glide on the owner's display and prints frame intervals (proven if ≥ 99 % ≤ 9.5 ms at 120 Hz); waits for the owner's run (marked blocked, not faked) |
| M7 | Nothing regressed | goal 25's checks pass with the flag off, and its M1–M6 with the flag on |

## Out of bounds
The web, Apple and Android replayers; charts and the lens on the Scene; moving work off the UI thread; making the Scene the default.

## After this goal (owner, 2026-10-19)
A showcase README for the world, built with the designer skill in Liquid once the GPU rendering works and the app "kicks ass": hero screenshots and motion clips of omxplorer, measured numbers (120 fps proof, MX frame on the GPU), the architecture in one picture (view tree → partial updates → Scene and layers → each platform's GPU; agent host and AG-UI), the component gallery per skin and platform, and an honest status (proven, built but unverified, next).
