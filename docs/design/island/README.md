# omxplorer · the island (2026-10-19)

Open `index.html` in a browser (1480 px wide or more) and reply "island A", "B" or "C".
The buttons above the window trigger each state; **Play all** runs them in order; click the capsule to expand it, click outside or press Esc to collapse. The accent dots swap the accent colour (teal today, or the brand page's C / A / D) so the pick doesn't depend on the colour decision.
URL shortcuts for screenshots: `?dir=B&state=edit`, `?state=agent&open=1`.

One capsule in the menu bar replaces three things in today's app: the document chip ("small · 5,000 rows"), the GPU chip, and the toasts / "Imported …" message in the status bar. The status bar keeps only the selection's figures.

## States (same in every direction)
| State | Face | Leaves by |
|---|---|---|
| Idle | ● orders · 2,000,000 rows · RTX 3090 | — |
| Query running | spinner · Filtering **amount > 500** · progress · 1.2B rows/s | becomes Result |
| Result | ✓ **199,812 matched** · 0.4 ms on RTX | back to idle after 4 s |
| Edit | Bold applied to **21 cells** · Undo · 5 s countdown ring | idle after 5 s (Ctrl+Z still works) |
| Big file | trips_2024.parquet · 48 row-group ticks fill · "18 / 48 row groups" | "48,212,904 rows ready · 2.3 s" |
| Error | ⚠ **region**: 3 rows aren't text · Show | stays until seen ("Show" rings the cell) |
| Agent (AG-UI, later) | ✦ Agent · grouping by region · 4 step dots, shimmering text | "Chart added to Report · Review" |

**Expanded** (click): the document (name, rows, columns, saved), a "Now" card with the rich version of the current state (rows scanned, rows/s, row groups, the agent's step and a Stop), **Recent** operations with timings and Undo on the undoable ones (the history the toasts used to throw away), and **Device**: GPU name, memory used, the last 12 timings as tiny bars, p50/p95.

## Directions
- **A · Ink capsule, centred.** A dark navy capsule in the middle of the menu bar, the iPhone island in spirit. It is the one dark object on a light screen, so status always lives in the same place and is seen without looking for it. Expanded, it becomes a dark panel dropping from the bar.
- **B · Glass pill where the chips are.** A frosted pill on the right of the menu bar, tinted by state (teal wash while working, green done, red error, indigo agent). The smallest change from today: it reads as part of the bar, not a new object.
- **C · Twin islands.** White capsules, centred-left. Long background work (a streaming file, the agent) splits into a second small island, so a query can still report in the main one. Try "Stream a big file", then "Run a query".

## Recommendation: A, with C's split held back for the agent
A is the strongest focal point and has nothing to lose on GTK (it needs no blur), and centring gives the capsule room to grow both ways without pushing anything. Add C's second island only when the agent ships, because that is the first time two long things will genuinely run at once.

Honest cons:
- **A** is a dark object in a light skin. Some will find it heavy; it may fight the logo if the brand colour is dark too. It also leaves the right side of the menu bar empty, and the menus already sit left, so the bar looks less "full" than today.
- **B** keeps today's layout but is easy to miss (the point of a living island is that you notice it), and it loses its frost on GTK, where it becomes a flat tinted pill. Growing leftwards also covers menus when it expands wide.
- **C** is the most capable and the most complex (two lanes of state, two widgets to keep in step); two capsules can look like two buttons. White-on-light has the least contrast of the three.
- All three: hiding results after 4 s means a slow reader misses them; Recent (expand) is the safety net, so it must be one click away and keyboard-reachable (a shortcut such as Ctrl+. is a suggestion, not decided).

## What GTK can do natively (and Mac / web)
- **Yes, on GTK 4:** CSS `transition` on background colour, colour, opacity, border-radius, box-shadow, transform, `min-width` / `min-height`, padding; `@keyframes` (the Liquid theme already uses them in `mojoui/hosts/gtk.mojo`); the curve `cubic-bezier(0.22,1,0.36,1)`. GtkStack crossfade for swapping the face; GtkPopover (autohide closes on click outside) or GtkRevealer for the expanded panel.
- **No:** `backdrop-filter`. Glass becomes solid white at 70–100 %. A and C lose nothing; B loses its frost.
- **Careful:** a GTK widget's width comes from its content, so "the capsule morphs to fit the new text" does not animate by itself. Two ways: draw the capsule on a `Canvas` with `on_frame` (interpolate width, height and radius ourselves; the text is drawn, as DataGrid already draws text), or measure the new face and animate `min-width` from the old size. The Canvas route is smoother and is the same code on every host. Unverified on GTK: a spike should prove it before the build.
- **Mac:** the real menu bar belongs to macOS. The capsule lives in the window's unified title bar, centred (an `NSTitlebarAccessoryViewController` or a centred toolbar item), the way Xcode shows its activity. **iPhone:** the top of the glass top bar; long streams can also feed a Live Activity. **Web:** everything on this page as written.
- **Agent host (MCP):** each state is a plain event, `activity(kind, text, progress)`, so the agent host can report the same things.

## What it would take in mojo-ui
Exists (see `docs/components.md`): `Canvas` with `on_frame` (GTK, web, Android), `Toast` and `Popover` (GTK, web), `Overlay`, the Liquid theme's keyframes.

New:
1. **`Island` (morphing capsule)**: a component with `state: Activity` (kind, text parts, progress, actions) that owns its frame clock: width / height / radius tween over 320 ms, a 150 ms out / 220 ms in face crossfade, actions as hit areas. Best drawn on `Canvas` so the morph is identical on every host.
2. **`Activity` model in the app runtime**: one queue that queries, imports, edits, errors and the agent post to (replacing `Toast` calls), with transient vs sticky, and an undo hook per entry. This is what feeds Recent.
3. **Expanded panel**: a `Popover` anchored to the island, no arrow, the same width as the expanded capsule so it looks like one object growing (on GTK a GtkPopover with `has-arrow=false`).
4. **Twin lane (C only)**: a second `Island` bound to background activities.

Remove when it ships: the document and GPU chips in the menu bar, the GPU chip and import message in the status bar, and `Toast` uses in `examples/omxplorer`.

Screenshots from the prototype (headless Chromium, 1440×900): `shot-A-query.png`, `shot-A-open.png`, `shot-B-undo.png`, `shot-C-twin.png`.
