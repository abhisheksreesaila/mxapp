# Report: the analytics showcase (goal 8)

**End goal (your words):** "the analytics part… the poster child for all this… make this really polished"; "UI charts with some sample data… then MX frame… aggregate on GPU… render it on the UI"; "a common language between the native and the web… the AI can understand it" (Flint).

**Result:** Contoso Retail, a Power BI-style sales dashboard in one Mojo file (`examples/analytics/app.mojo`), running on Linux and the web.

- **20 million order lines** (made up, with growth, seasons and a shift to online) are re-aggregated **every time you click**:
  - **6–9 ms** for all seven aggregations on the RTX 3090, depending on the filters;
  - about **115 ms** through **MX frame** on the CPU;
  - about 750 ms with plain Mojo loops on one core.

  A test compares every result of all three engines (910 numbers under 5 filter settings): they agree **to the cent**.
- **Every chart is a [Flint](https://microsoft.github.io/flint-chart/) spec**, Microsoft's chart language for AI agents. mojoui draws the specs natively (a Mojo backend for Flint, the same pixels on every platform), and all nine also compile through Flint's own Vega-Lite pipeline to SVG.
- **Crossfiltering:** tap a category, a region or a month and everything else filters. GTK and the browser end in the same state after the same real clicks.
- **Fluent 2** styles the native controls on Linux and the web. The dashboard fits 1440×900 and 1280×800 with no scrolling.

![The dashboard on Linux](img/analytics-linux.png)

**Gallery:** https://abhisheksreesaila.github.io/mxapp/gallery/

## Checker
```
CHECKER_OUTPUT
```

## Try it
```bash
scripts/build.sh analytics linux && build/analytics/linux/analytics      # Linux window
scripts/build.sh analytics web && pixi run python mojoui/hosts/web.py build/analytics/web   # http://127.0.0.1:5001
```
Switch the **Engine** between GPU, CPU and MX frame; pick a year or channel; tap bars, columns and months.

## What's new in mojoui
- **Text on canvases** (`mojoui/text.mojo`): Noto Sans baked into atlases (`scripts/bake_font.py`), anti-aliased at any size, widths within 0.04 px of the font's own.
- **Drawing and charts** (`mojoui/draw.mojo`, `mojoui/charts.mojo`): KPI tiles, bars, line/area, columns, bar tables, with hit-testing and selection.
- **Flint specs** (`mojoui/flint.mojo`): declare, draw natively, export JSON.
- **GPU group-by** (`mojoui/gpu.mojo`, `Table.group_sum`): exact 64-bit totals, per-block shared-memory sums, 20M rows in about 1 ms per pass.
- **MX frame engine** (`mojoui/mxframe.mojo`): the same queries through MX frame. The Python-free API it needs is specified for you in `docs/mxframe-mojo-api.md`.
- **Design and cards:** `design() -> FLUENT`, `Card(...)`.

## Decisions worth your second look
1. **D-76, Flint:** I first read "Flint" as Fluent, Microsoft's design system (D-73), then corrected course when you sent the link. Flint is now the chart language; Fluent stays as the look of the controls.
2. **D-74, charts drawn by Mojo:** no common native chart widget exists, so one renderer draws them, with text from a baked font atlas. Charts look identical everywhere, and the renderer can move to the GPU later.
3. **D-75, money in exact integer cents:** this is what lets three engines be compared to the cent. Flint receives dollars.

## Fixed along the way
- **GPU group-by contention:** global atomics took 22 ms for 5 groups (contention), so each block now sums in shared memory first: 1.1 ms.
- **GTK canvases sized from their own texture:** a picture asked for its pixel size as its natural size and stretched fixed-height rows on scaled screens. It now sits in a non-scrolling holder.
- **Dark theme on light cards:** the desktop's dark theme gave cards light text on white. Fluent (a light design) now forces the light scheme.
- **Revenue in cents in Flint's chart:** the gallery's side-by-side showed Flint's chart labelled in cents; the export now converts to dollars.

**Next:** the web "island" that renders the same Flint specs with Flint's own JavaScript; the Mac version (after the MX frame Mojo API); the notebook editor; "Ask your data".
