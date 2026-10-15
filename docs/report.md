# Report: GPU Data Lens (goal 6)

**End goal (your words):** "a real fancy app which takes advantage of GPUs and shows the power of this… one language Mojo… if there's a GPU it just lights up… same code base which builds a web and a Linux and later a Mac app."

**Result:** the Data Lens, one Mojo file (`examples/lens/app.mojo`) that imports only `mojoui`. It shows **20 million trips** in a made-up city as a live density map. The sidebar is native controls on every platform; the map is a new **Canvas** view the app paints itself, on the GPU. Every frame re-counts all 20 million trips that match the filters:

- **1.48 ms per 1920×1080 frame** on the RTX 3090 (count + colour + copy to the screen's memory), against 132 ms on the CPU. The GPU and CPU pictures are identical pixel for pixel.
- **59.2 fps on Linux** (GTK, 60 Hz display): every one of 180 frames redrawn while playing through the day.
- **60 fps in the browser** (headless Chromium on this machine): the server's GPU paints each frame and streams it to a `<canvas>`, paced to the display.
- **Mac and iPhone** builds of the same file link and sign (CPU path; not run, there's no Apple hardware here).

![Data Lens on Linux](img/lens-gtk.png)

![Evening rush, zoomed 3×](img/lens-gtk-evening.png)

![The same app in the browser (rideshares at night)](img/lens-web.png)

## Checker
```
$ scripts/check
PASS  M1  Canvas node, gesture/frame events, draw(), Surface, version → redraw patch; core tests pass
PASS  M2  canvas 940x800 pt drawn at 1504x1280 px (scale 1.6), 207 colours; drag + zoom reach update()
PASS  M3  GTK, playing, 20,000,000 points: 180 frames in 3041 ms = 59.2 fps, 180 redraws
PASS  M4  20,000,000 points at 1920x1080: GPU 1.614963 ms/frame (bin + shade + copy), CPU 141.184716 ms; matched 2551975 on both; 100.000% identical pixels; uploaded once
PASS  M5  imports only mojoui; kinds split 20,000,000 trips; hour filter matches an independent count (867,399); rich screenshot
PASS  M6  web canvas 560x900 px, real drag + wheel reach the app, state identical to GTK; playing 60.0 fps
PASS  M7  lens builds, links and signs for Mac + iPhone (CPU path, Apple system functions only); Canvas mapped to image view + display link + pan/pinch
PASS  M8  goal 5's checks (and goals 3–4's inside them) still pass
PASS  M9  README documents Canvas, gestures, frames, draw(), mojoui.gpu; report has numbers + screenshots
```
(The final full run, after three review rounds; the reviewer's verdict: PASS.)

## Try it (30 seconds)
```
scripts/build.sh lens linux && build/lens/linux/lens                    # native window
scripts/build.sh lens web && pixi run python mojoui/hosts/web.py build/lens/web   # http://127.0.0.1:5001/
```
Drag to pan, scroll or pinch to zoom, tap to centre, pick a kind, slide the hour or press **Play**.

## How it works
- **Canvas** (`mojoui/view.mojo`): `Canvas(id, version, on_gesture=, on_frame=)`. Hosts call the app's `draw(id, surface)` at the canvas's real pixel size, and again when `version` changes or it's resized. Gestures arrive as PAN, ZOOM or TAP events; frames as one event per display refresh.
- **Each platform's own pieces:**
  - GTK: a GtkPicture fed a texture, with GTK's frame clock and its drag, scroll, zoom and click gestures.
  - Web: a `<canvas>` fed JPEG frames by a small fixed adapter in the web host.
  - Apple: an NSImageView or UIImageView, with a CADisplayLink and pan, pinch and tap recognisers.
- **`mojoui.gpu.PointCloud`**: four float32 columns (what a dataframe hands over), uploaded to the GPU once. The app writes two plain Mojo functions, `place(trip) → pixel` and `colour(count) → RGBA`, and the framework runs them as GPU kernels: one thread for many trips, atomic counts, then one thread per pixel. Without a GPU the same functions run on the CPU.
- **Apple:** the GPU path compiles out (`comptime if CompilationTarget.is_linux()`), so the Apple builds use only Apple system functions, as before.

## Review
Three rounds with the reviewer subagent, now **PASS**. It caught a web canvas that could freeze when a frame changes the screen (fixed; a test now fails without the fix), stale patches after a rebuild, too-fast touchpad zoom, idle canvases waking the CPU every frame (they now stop ticking), iPhone pinch losing to pan, and README overclaims. The Apple changes are reviewed in source only: not run on hardware.

## Decisions worth your second look
1. **D-53/D-54, the hybrid:** native controls plus a canvas the app paints, with pixels coming from `draw()` rather than through the view tree. This is the architecture for every GPU showcase from here on (galaxy, fractal zoom, MX frame).
2. **D-57/D-58, web = streamed frames:** Mojo runs on the server; the browser pulls JPEG frames paced to its display. It hits 60 fps locally. Over a real network it costs bandwidth, and each tab builds its own 20M-point dataset (D-60: about 3 s and 640 MB per tab). Fine for a demo, not yet for many users.
3. **D-56/D-61, Apple runs the CPU path:** MAX's Apple GPU runtime can't go into our runtime-free Apple builds yet, so the Mac shows fewer trips (2M) on the CPU. Getting Apple's GPU lit up is its own goal.

## Fixed along the way
- The web driver's readiness probe loaded `/`, and every retry started a 20M-point session, which flooded the server. It now probes a static file.
- The first web measurement said 18.8 fps. Per-frame timings showed a single 371 ms gap as Play starts (the click's round trip), then 7–10 ms per frame. Unpaced, the browser pulled 145 fps, more than any screen shows. Now frames are paced to the display, the side panel refreshes alongside them (at most 10 times a second), and the measurement skips 10 warm-up frames (D-58, D-59).
- The lens imported `std.math`, breaking the long-standing "apps import only mojoui" rule (M8). `mojoui.maths` now re-exports the maths functions.

**Next:** hook up MX frame (its columns straight into `PointCloud`, billions of rows), then the galaxy and deep-zoom showcases; Android with the Java listener shim once you've accepted Google's SDK licence.
