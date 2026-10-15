# GOAL 6: GPU Data Lens, native controls + a GPU canvas

**End goal (owner's words, 2026-10-15):** "develop a real fancy app which takes advantage of GPUs and shows the power of this… one language Mojo… if there's a GPU it just lights up… same code base which builds a web and a Linux and later a Mac app." The showcase is a **data lens**, step one toward hooking up MX frame ("billions of records").

The hybrid: native controls around a **Canvas** view the app draws itself (Mojo, on the GPU when there is one). The app file stays 100% declarative Mojo; hosts map Canvas onto each platform's own image surface, frame clock and gesture system.

## API
`Canvas(id, version, on_gesture=, on_frame=)`: hosts call the app's `draw(id, mut surface)` at the canvas's real pixel size, again whenever `version` changes or the canvas is resized. Gestures send `on_gesture` with `event.number` = PAN/ZOOM/TAP and `event.x, y, dx, dy, zoom` (points). `on_frame` sends one event per display frame (`event.number` = microseconds since the last). `mojoui.gpu` gains point binning + per-pixel shading over columns kept on the GPU, with the same functions on the CPU when there's no GPU.

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | Core | Canvas node, gesture/frame events, `draw()`, Surface, version → redraw patch; core tests pass |
| M2 | GTK canvas | the lens draws at its laid-out pixel size (points × display scale), not blank; drag and zoom gestures reach `update()` with the expected view change |
| M3 | Frame clock | GTK: playing, the lens redraws every display frame: ≥ 55 fps on this 60 Hz display over 180 frames with 20M points |
| M4 | GPU pipeline | data uploaded once; 20M points at 1920×1080 (bin + shade + copy) median ≤ 8 ms; GPU and CPU agree (same matched count, ≥ 99.9% identical pixels) |
| M5 | Data Lens | `examples/lens/app.mojo` imports only mojoui; hour slider, category, play, pan/zoom, stats; filter counts match an independent count; screenshot shows a rich image |
| M6 | Web | same app in Chromium: canvas frames streamed from the server GPU at the canvas's pixel size; real mouse drag + wheel reach the app; same steps → same state as GTK (geometry and timing lines aside); ≥ 20 fps playing |
| M7 | Apple | Canvas → NSImageView/UIImageView + CADisplayLink + pan/pinch recognizers; lens builds, links and signs for Mac + iPhone; no MAX/GPU runtime symbols (CPU path); only Apple system functions |
| M8 | Nothing regressed | goal 5's checks still pass |
| M9 | Docs + proof | README documents Canvas, gestures, frames, `draw()`, `mojoui.gpu`; report has fps/ms numbers and screenshots |

## Out of bounds
No deploying, sign-ups, logins, secrets, pushing or licences; windows may show briefly during checks only; don't touch `../mojo-ui-apple-test`. Android (Java listener shim approved 2026-10-15, needs the owner to accept Google's SDK licence), MX frame hookup, galaxy/fractal showcases and WebAssembly are later goals.

## Assumptions
- The canvas uses each platform's own image surface (GdkMemoryTexture, `<canvas>`, CGImage): one copy per frame from GPU to screen. Zero-copy GPU→display interop is a later optimisation.
- Web: Mojo runs on the server; frames are JPEG over a pull loop (back-pressure built in), gestures go through the normal event path. The browser's own JS is a small fixed adapter in the framework's host, never in apps.
- Apple builds use the CPU path (MAX's Apple GPU runtime isn't linkable into our runtime-free Apple builds); fewer points there. GPU on Mac is a later goal.
- Synthetic data (a fictional city's trips: x, y, hour, kind), columnar float32, so MX frame columns can replace it.

## Budget
~3 hours. Stop with a clear report if blocked.
