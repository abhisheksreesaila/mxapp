# Rendering: how to take performance off the table (research, 2026-10-19)

Question: how should mojo-ui draw content views (grid, charts, lens, later video and simulations) so a
3440×1440 screen at 1.6× (≈2.8k×1.4k device pixels per window) feels like macOS at 120 Hz?
Status: research only. Nothing here was built or measured, except where it says "measured" (from docs/journal.md).

## 1. The answer

**Stop sending pixels. Send a display list, and keep moving parts in their own layers.**

- A Canvas's `draw()` writes a **display list**: a flat array of primitives (rect, rounded rect, line,
  text run, image, path, clip). Mojo still decides *what* goes where (layout, hit tests, virtual rows).
- Each host turns that list into its **own GPU path**: GTK → GskRenderNodes (GTK's Vulkan/GL renderer
  does the glyph atlas, batching and damage); web → Canvas2D (WebGL2/WebGPU only if measured slow);
  Apple → a small Metal instanced-quad renderer plus CALayers; Android → a RenderNode replayed in Java.
- A canvas has **layers with keys**. Content (the cells) is one layer, reused as-is when nothing in it
  changed. Overlays (selection ring, cursor, drag ghost, playhead) are separate small layers whose
  position the host animates. A ring glide never rebuilds the grid.
- Keep the CPU rasterizer we have (`draw.mojo`, `text.mojo`) as the **reference and fallback** backend
  (tests, screenshots, PNG export, hosts without a GPU path).
- Mojo GPU kernels (MAX) stay for **data-dense layers** (20M-point lens, heatmaps, video frames): they
  produce an *image* primitive inside the display list. They are not the UI renderer.

Rejected as the main path: (b) Mojo/MAX rasterizes the whole UI on the GPU (no graphics interop on any
host today), and (c) CPU raster + damage + partial uploads alone (cannot meet the 120 Hz budget when scrolling).

## 2. Why (with numbers)

**Our budget.** 120 Hz leaves 8.33 ms per frame for everything: events, update, layout, drawing
(Zed's own framing of the problem). The main thread should spend ≤ 2–3 ms of that on a canvas.

**Where we are (measured):** a grid frame costs 4–7 ms of CPU at ~1.6 Mpx (docs/journal.md). At
2.8k×1.4k (3.9 Mpx, 2.4× the pixels) that extrapolates to roughly 10–17 ms (not measured). On top,
each frame is a 15.7 MB buffer that `texture()` copies into GBytes and GTK uploads again: about
1.9 GB/s of copying at 120 Hz. The ring glide pays all of it every frame because it redraws the whole grid.

**What the work really is.** At 1.6× a 26-pt row is 41.6 px, so a 1,400-px-tall grid shows ~32 rows ×
~14 columns ≈ 450 cells, ≈ 4–5k glyphs and ~1–2k rects. As a display list that is ~6k items, ~100–200 KB.
Writing that in Mojo is well under 1 ms (estimate). Today's cost is per *pixel* (`s.fill` of 3.9 Mpx, a
bilinear float sample per glyph pixel in `Font.draw`), not per *item*. The GPU is built for per-pixel work.

**How the best systems do it:**
- **Zed GPUI** (macOS, 120 fps): the UI is a `Scene` of a few primitive kinds (rects, shadows, glyphs,
  icons, images) in layers. Each kind has one shader; all instances of a kind go in one instanced draw.
  Rounded rects and shadows are signed distance functions in the shader (no tessellation). Glyphs are
  rasterized once by the OS into an alpha-only atlas (up to 16 sub-pixel variants per glyph), shaped
  text is cached per (text, font) and reused across frames. It redraws the whole window every frame:
  with the GPU doing pixels, that is cheap.
- **Makepad**: the same idea taken further: widgets emit instances straight into instanced draws,
  batched by shader. Works on WebGL1/GLES2-class hardware, no compute shaders needed (third-party write-up).
- **Flutter Impeller**: the win over Skia was *predictability*: "Impeller compiles all shaders and
  reflection offline at build time. It builds all pipeline state objects upfront." Default on iOS
  (only engine), Android API 29+, and desktop as of Flutter 3.47. Lesson: a small fixed set of shaders,
  known before the first frame.
- **Skia Graphite** (Chrome on Apple Silicon): same lesson. Fewer, consolidated pipelines compiled at
  startup (no mid-scroll shader jank), depth buffer to skip hidden pixels, recording on several
  threads. ~15% higher MotionMark 1.3 on an M3 MacBook Pro.
- **Vello / sparse strips** (Linebender): a compute-shader 2D renderer for *vector paths*; the newer
  sparse-strips CPU and hybrid renderers target devices without compute shaders. Blend2D still wins
  their CPU benchmark; Vello CPU is often second, ahead of Skia and Cairo on big geometry. Not
  production-ready (their README). Relevant later for charts with heavy paths, not for grids of rects and text.
- **Text on the GPU**: atlas of pre-rasterized glyphs (GPUI, GTK, Chrome) is the standard for UI sizes.
  MSDF (msdfgen) and Slug (curves evaluated per pixel; now public domain) win when text is scaled,
  rotated or zoomed continuously (a video editor's titles, a zoomable canvas). Not needed for the grid.
- **Core Animation / WinUI Composition**: the app commits a *layer tree*; a separate render server
  (Apple, a separate process) or composition engine (Windows, "independent from the UI thread")
  composites and runs animations. A busy app thread does not stop a running animation.
- **Chrome**: a display list per layer → layers rasterized into GPU tiles → a compositor thread that
  scrolls and animates transform/opacity "entirely on the compositor thread" without the main thread.
- **GTK4 GSK**: widgets produce immutable GskRenderNode trees (color, rounded clip, border, shadow,
  text, texture, transform, opacity …). Since 4.14 the "ngl" and Vulkan renderers share one codebase
  with a shared glyph and texture cache; Vulkan is the default on Wayland since 4.16 (we have 4.22).
  They render at the real fractional size (no 2× then downscale). GTK diffs consecutive node trees to
  find damage, but a *new texture* counts as fully damaged (WebKit bug 252648): this is exactly why our
  ring glide re-uploads everything. `GdkMemoryTextureBuilder.set_update_region/_texture` (4.16) can
  describe a partial change, but only helps if we also raster only that part.
- **Browsers**: WebGPU ships in Chrome/Edge, Safari 26 and Firefox 141 (Windows; macOS ARM in 145;
  Linux/Android still in progress). Canvas2D is GPU-backed in Chrome (Skia/Graphite) and available
  everywhere. OffscreenCanvas lets a worker draw so the page's main thread stays free.

**The pattern every fast system shares:** (1) the app describes *what* to draw as cheap data, (2) a GPU
renderer with a small fixed shader set draws it, (3) glyphs are rasterized once and cached, (4) things
that move are separate layers, so moving them is a transform, not a repaint. Retained (Core Animation,
GSK widget nodes) vs immediate (GPUI, Makepad) matters less than (1)–(4): GPUI redraws everything and
still hits 120 fps because the per-frame CPU work is per item, not per pixel.

**Why not (b), Mojo rasterizing on the GPU:** MAX targets compute (CUDA/ROCm); it has no swapchain and
no documented way to export a buffer as a dmabuf (GTK `GdkDmabufTextureBuilder`), IOSurface/MTLTexture
(Apple) or AHardwareBuffer (Android). Without that, the result goes GPU → CPU → GPU every frame, which is
today's copy problem plus a readback. MAX on Apple GPUs and Android isn't there yet, and the web can't
run it at all. It also means writing our own Vello (paths, AA, text) before the first frame ships.
Keep it for data layers, where it already pays (lens: 20M points, 1.5 ms on the GPU).

**Why not (c) alone:** damage + partial upload fixes the ring glide, but scrolling changes every pixel.
A full scroll frame stays at ~10–17 ms of CPU raster + 15.7 MB upload at 2.8k×1.4k: over budget at 120 Hz.
It is still worth keeping the CPU path honest (it becomes the fallback backend).

**Why (a)+(d) together:** (a) moves per-pixel work to the GPU on every host using code the platform
already ships and tunes; (d) makes the common animations (ring, cursor, hover, drag) cost almost nothing
and, on Apple/web/Android, keeps them smooth even while Mojo is busy.

## 3. Per-host mapping

| Host | Content layer | Text | Overlay layers / animation | Escape hatch |
|---|---|---|---|---|
| GTK (Linux) | `gtk_snapshot_new()` → append color / rounded-clip / border / transform nodes → `gtk_snapshot_free_to_paintable()` → `gtk_picture_set_paintable()` (same widget as today, no GType subclass) | `gsk_text_node_new(PangoFont, PangoGlyphString, color, offset)`; Inter/JetBrains Mono loaded as app fonts; glyph ids from the font's cmap, advances from our table (no shaping for plain Latin; Pango shaping, cached, for the rest). GSK owns the atlas | Keep last frame's content node (nodes are immutable and refcounted) and append it again with a fresh small ring node: GSK's node diff damages only the ring's area. GTK has no compositor thread: animation still ticks on the main thread, but costs ~µs | GtkGLArea or a dmabuf texture with our own instanced renderer, only if GSK measures too slow |
| Web | Mojo sends the display list (binary, over the existing pull loop or a WebSocket) instead of a JPEG; JS replays it into Canvas2D (`fillRect`, `roundRect`, `fillText` with the same web fonts) | Browser shaping and glyph cache; widths still come from Mojo's metrics | Ring = an absolutely positioned element moved with a CSS transform/transition: runs on the browser's compositor thread with no server round trip | WebGL2 instanced quads + our atlas (WebGPU where shipped), in an OffscreenCanvas worker |
| macOS / iOS | `CAMetalLayer` + one small instanced renderer: rect/rounded-rect SDF shader, glyph-atlas shader, image shader (the GPUI recipe, proven at 120 fps by Zed) | Core Text rasterizes glyphs into the atlas; cache shaped runs | Overlays as plain `CALayer`s; set the frame, Core Animation's render server animates it (implicit animation), even if Mojo is busy. `CADisplayLink.preferredFrameRateRange` up to 120 (a hint, not a promise) | Core Graphics into layer contents (CPU, tiled) as a first, slower step |
| Android | One JNI call per frame passes the list as a direct `ByteBuffer`; a Java replayer records it into a `RenderNode` via `RecordingCanvas` (GPU, drawn on Android's RenderThread) | `Canvas.drawText` with the bundled Typeface | Overlays as separate RenderNodes/Views: their position/transform changes "without re-recording" | GLES/Vulkan surface with the same instanced renderer |
| Reference (all) | Today's `draw.mojo` + `text.mojo` rasterizer replays the display list into a Surface | Baked atlas | n/a | Tests, PNG export, golden images |

Data layers (lens, heatmap, video frame) everywhere: an `image` primitive. On GTK the Mojo/MAX kernel's
pixels become a `GdkMemoryTexture` (as today) with an update region when only part changes; zero-copy
(dmabuf) is an unknown worth one later spike.

## 4. What changes in mojo-ui's API

1. **`draw()` gets a `Scene` (display list), not a `Surface`.** Same coordinate system (points × scale):
   `sc.rect(x, y, w, h, color, radius)`, `sc.line(...)`, `sc.text(str, x, baseline, size, color, face)`,
   `sc.image(key, x, y, w, h)`, `sc.path(...)` later, `sc.clip(...)`/`sc.end()`. `DataGrid.draw` keeps its
   logic; `rect(s, …)` becomes `sc.rect(…)`. Fill-the-background becomes one rect.
2. **Layers with keys and versions.** `sc.layer("cells", version)` … `sc.layer("ring")`. If a layer's key
   and version match last frame, the app may skip it (`if sc.reuse("cells", v): …`) and the host
   re-appends its cached node/texture. Grid version = hash of (top row, left, column widths, data
   version, styles, selection block): the ring's position is *not* part of it.
3. **Animated layer properties instead of `surface.again`.** `sc.layer("ring", frame=(x, y, w, h),
   animate=SPRING)`: the host animates from the old frame to the new one (Core Animation, CSS transition,
   RenderNode property; on GTK the host's tick interpolates and re-appends the cached content). The app
   gets a `SETTLED` event if it cares. `again` stays for physics the host can't express.
4. **Text metrics stay in Mojo**, from the same font files every host draws with (read advances from
   the font, not only the baked table), so `measure`, clipping with "…", and hit tests agree everywhere.
   Add a per-frame cache for `measure` and for shaped runs, keyed by (text, face, size).
5. **The CPU rasterizer becomes `scene.raster(surface)`**: nothing is thrown away; test checks that read
   pixels keep working through it.
6. **Display lists are data, so tests get cheaper**: assert "cell (3, 2) shows '1,204.50' right-aligned"
   on the list, without a window.

## 5. First spike: GTK only, measurable

**Build (behind a flag, `MOJOUI_SCENE=1`, old path untouched):**
1. `mojoui/scene.mojo`: a `Scene` with rect, rounded rect, line, text, clip, layer (flat arrays of
   Float32/UInt32, no per-item heap allocation).
2. `DataGrid.draw_scene(sc, src, font, p)`: the same picture as `draw()`, ring in its own layer.
3. GTK host: replay the Scene into a GtkSnapshot → paintable → the existing GtkPicture. Text via
   `gsk_text_node_new` with Inter loaded through fontconfig. Cache the "cells" node by version; re-append it
   under a new ring node during a glide.
4. Instrument: Mojo scene build time, host replay time, paintable set time, separately; frame-clock
   intervals during a glide and a scroll.

**Measure first:** today's path at 2800×1400 in omxplorer with 1M rows (draw ms and `texture()` ms apart).

**It's proven if**, at 2800×1400, scale 1.6, 1M rows, on the owner's real display (not Xvfb; see risks):
- Scroll frame (whole grid new): Mojo scene build ≤ 1.0 ms and host replay ≤ 1.0 ms, so **≤ 2 ms CPU
  p95** on the main thread (vs ~10–17 ms extrapolated today).
- Ring glide: **0 grid scene builds** during the glide (a counter), ≤ 0.3 ms CPU per frame, and frame-clock
  intervals ≤ 9.5 ms for ≥ 99% of frames on a 120 Hz output.
- Bytes copied per glide frame: ~0 (no texture upload), vs 15.7 MB today.
- Looks: a side-by-side screenshot of old and new paths, read by eye (lessons: "look at every screenshot");
  text may differ slightly (FreeType vs baked atlas), nothing else should.

**If it fails:** if replay (FFI + node creation) is the cost, batch text per row (one glyph string per
row, many glyph runs) or move to the GtkGLArea instanced renderer; if GSK's GPU time is the cost, note
the renderer (`GSK_RENDERER=vulkan|ngl`) and driver, and try the other.

**Then, one at a time:** web replayer (Canvas2D, ring as CSS overlay), charts and lens onto Scene
(lens = image primitive), Apple Metal renderer (needs the owner's Mac), Android replayer.

## 6. Risks and unknowns (stated plainly)

- **Xvfb has no GPU.** GTK there renders with llvmpipe (software), so GPU-path timings from
  `scripts/check` mean nothing. Frame-rate proof needs the real display (or a GPU-backed headless
  compositor); lessons already note covered windows get no ticks. CPU-side numbers are fine headless.
- **GTK has no compositor thread.** Unlike Apple, web and Android, a GTK animation stops when the main
  thread is busy (opening a file: 215 ms). Layers make animation cheap, not independent. Heavy data work
  still has to move to workers (goal 26).
- **FFI volume.** ~6k GSK calls per frame from Mojo is unmeasured. GTK apps build trees this size, but
  each of our calls also crosses FFI and allocates a GdkRGBA/graphene rect. Mitigation: one text node per
  row, rects merged per row.
- **Text parity.** Hosts rasterize with their own engines (FreeType, Core Text, browser, Skia): glyphs
  will differ slightly from today's baked atlas and between platforms. Metrics must come from the same
  font files or "…" clipping and right-alignment drift. Complex scripts (Arabic, CJK) need real shaping
  (HarfBuzz/Pango/Core Text); today's text has none.
- **More host code.** Four replayers instead of four "show this texture" calls. The Apple Metal renderer
  is new code nobody can run here (owner's Mac only).
- **GSK specifics:** node diffing can give up and damage the whole window when many nodes change (GTK
  issue 4620); NVIDIA + Vulkan has had driver bugs (GTK recommends recent Mesa; proprietary drivers vary).
- **Web.** Canvas2D `fillText` throughput for ~5k glyphs per frame is unmeasured; WebGPU is missing on
  Firefox Linux/Android; any display-list protocol is a new wire format to version.
- **Zero-copy GPU data layers** (MAX output straight into a GTK/Metal texture) are unknown; until then the
  lens keeps its copy (fine at its sizes, a problem for 4K video).
- **Video editor and simulations** will want their own GPU passes (YUV decode, effects, 3D). The display
  list's `image` primitive covers showing their output; producing it is a separate design.

## 7. Sources

- Zed, "Leveraging Rust and the GPU to render user interfaces at 120 FPS": https://zed.dev/blog/videogame
- GTK blog, "New renderers for GTK" (2024-01-28): https://blog.gtk.org/2024/01/28/new-renderers-for-gtk/
- GTK 4.16.0 release notes (Vulkan default on Wayland): https://download.gnome.org/sources/gtk/4.16/gtk-4.16.0.news
- GskRenderNode reference: https://docs.gtk.org/gsk4/class.RenderNode.html
- GtkSnapshot.free_to_paintable: https://docs.gtk.org/gtk4/method.Snapshot.free_to_paintable.html
- GdkMemoryTextureBuilder.set_update_region (4.16): https://docs.gtk.org/gdk4/method.MemoryTextureBuilder.set_update_region.html
- WebKit bug 252648 (GTK treats a new texture as fully damaged; tile workaround): https://bugs.webkit.org/show_bug.cgi?id=252648
- GTK issue 4620 (node diff falls back to whole-window damage): https://gitlab.gnome.org/GNOME/gtk/-/issues/4620
- libmks MR 14 (GdkGLTextureBuilder for damage): https://gitlab.gnome.org/GNOME/libmks/-/merge_requests/14
- Flutter, Impeller rendering engine: https://docs.flutter.dev/perf/impeller
- Chromium, "Introducing Skia Graphite": https://blog.google/chromium/introducing-skia-graphite-chromes/
- Chrome, RenderingNG architecture: https://developer.chrome.com/docs/chromium/renderingng-architecture
- Linebender, Vello sparse strips README: https://github.com/linebender/vello/tree/main/sparse_strips ; status and CPU benchmarks: https://linebender.org/blog/tmil-19/
- Slug (Lengyel): https://terathon.com/blog/decade-slug.html ; MSDF: https://github.com/Chlumsky/msdfgen
- Makepad architecture (third-party write-up, unverified): https://hackmd.io/@guofoo/rJpSeJzXR
- Apple WWDC 2014 session 419 (render server), notes: https://www.wwdcnotes.com/notes/wwdc14/419 ; CATransaction: https://developer.apple.com/documentation/quartzcore/catransaction
- Apple, Optimizing ProMotion refresh rates: https://developer.apple.com/documentation/quartzcore/optimizing-promotion-refresh-rates-for-iphone-13-pro-and-ipad-pro
- Microsoft, Visual layer / Composition animation: https://learn.microsoft.com/windows/uwp/composition/visual-layer
- Android RenderNode / RecordingCanvas: https://developer.android.com/reference/android/graphics/RenderNode
- web.dev, "WebGPU is now supported in major browsers": https://web.dev/blog/webgpu-supported-major-browsers
- MDN, OffscreenCanvas: https://developer.mozilla.org/en-US/docs/Web/API/OffscreenCanvas
- This repo: docs/journal.md (grid frame 4–7 ms, line 282), mojoui/hosts/gtk.mojo (`texture`, `draw_canvas`),
  mojoui/text.mojo (`Font.draw`), mojoui/hosts/web.py (`/frame`, JPEG frames).
