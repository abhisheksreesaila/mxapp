# Launch posts (drafts, not posted)

Three drafts for the public alpha: a GitHub release, an X thread, a Modular forum post. Words and numbers come from
`docs/launch/copy.md` and the README; every number is measured on one Linux machine with an RTX 3090 (sources in brackets,
for checking, not for posting). **Nothing here is posted or pushed without the owner's yes.**

Before posting, the owner decides:
1. **Name.** The posts say *omxapp* and link the `mxapp` repo (copy.md, open question 1).
2. **Clips.** The X thread and the forum post want the short clips (`docs/img/clip-*.mp4`); attach them by hand.
3. **Tag.** The release is `v0.1.0-alpha` from whatever commit is on `main` when it's pushed.

---

## 1 · GitHub release

**Tag:** `v0.1.0-alpha` · **Title:** omxapp 0.1 alpha: one Mojo file, every screen, the GPU underneath, agents built in

omxapp is a framework for writing an app once, in Mojo, and running it natively on Linux, the web and Android, with Mac and
iPhone building today. The same file computes on the GPU, and any AI agent can use the app as a set of MCP tools.

Its showcase, **omxplorer**, is a data app in the spirit of Numbers and Power BI, about 2,100 lines of Mojo.

**What's in the alpha**
- **Native controls on every host.** One `app.mojo` becomes GTK 4 on Linux, HTML on the web (FastHTML), Android views,
  AppKit and UIKit. Linux, the web and Android are run by checks; Mac and iPhone build and sign but no check runs them yet.
- **Data on the GPU, in the app's process.** MX frame, a Mojo dataframe engine: sum, median and p90 per group, number
  conditions, months, quarters and weekdays. A chart over 1M rows takes 0.5 to 0.7 ms; a 100M-row file opens in 0.2 s.
- **The chart is its sentence.** "**Sum** of **revenue** by **product**, **largest first**, **top 5**" — tap a word to
  change it, or type "median" or "by month, as a line". It's a keyword reader, instant and offline, not a model.
- **Agents with no API.** Every app is an MCP server from its first line: a button's tag names its tool, and calling the
  tool is tapping the button. A disabled button isn't a tool.
- **Drawn views on the GPU.** A 1M-row grid scrolls at 0.8 ms a frame (p95); the Data Lens colours 20M points in 1.5 ms.

**Known limits**
- At 100M rows in memory, a median chart takes about 0.7 s and the window waits for it. Moving that work off the window is next.
- The GPU path is NVIDIA. Apple and phone GPUs use the CPU path, which runs the same functions.
- Mojo 1.1 has no official iPhone, Android or WebAssembly target; omxapp cross-compiles with two hand-written runtime
  functions (`spike/kgen_shim.c`). There's no Windows build.
- The agent can't yet read a chart's figures as text or drag objects on a page.

**Try it** (x86-64 Linux, GTK 4, libadwaita 1.7+, [pixi](https://pixi.sh); an NVIDIA GPU for the GPU path)
```bash
git clone https://github.com/abhisheksreesaila/mxapp
cd mxapp && pixi install
scripts/omxplorer.sh            # native window
scripts/omxplorer.sh web        # the same app at http://127.0.0.1:5001
```

MIT licence. Every number above comes from `scripts/check` or its benchmarks on one machine (RTX 3090).

---

## 2 · X thread

**1/**
I wrote one app in Mojo. It runs as a real GTK app on Linux, in the browser, and as real Android views. The same file sums
a million rows on the GPU. And an AI agent can use it with no API.

It's called omxapp. Public alpha, MIT.
[clip: omxplorer, a chart edited by its sentence]

**2/**
A chart's title isn't a label. It is the chart:

"Sum of revenue by product, largest first, top 5, as bars"

Every coloured word is a setting. Tap one, pick another. Or type "median" or "by month, as a line". The bars move to the new answer.
[clip: tap Sum → Median; ask "top 3, as a line"]

**3/**
The data never leaves the app. A Mojo dataframe engine runs on the GPU next to the code that draws it.

1M rows: a chart in 0.6 ms. The status bar's sum in 0.3 ms.
100M rows (4 GB): opens in 0.2 s.
One Linux box, RTX 3090.

**4/**
Agents get the app as MCP tools, for free. A button's tag names its tool; calling it is tapping it. A disabled button isn't a tool.

→ ask {"text": "revenue by product, top 5"}
← chart0: 0.6 ms

No screenshots, no coordinates.

**5/**
Honest edges: Mac and iPhone build but aren't run by a check yet. At 100M rows a median waits ~0.7 s on the UI thread (next
up: background queries). Mojo is young: no official phone target, no Windows yet.

**6/**
Built on Mojo 1.1, one small step at a time, with every claim proven by a script in the repo.

github.com/abhisheksreesaila/mxapp

---

## 3 · Modular forum post

**Category:** Community Showcase · **Title:** omxapp: native apps on Linux, web and Android from one Mojo file, with the data on the GPU

Hi all. I've been building a UI framework in Mojo and it's reached a public alpha, so I'd like to
share it and hear what you think.

**The idea.** An app is one `app.mojo` with `view()` and `update()`. Hosts draw it with the platform's own controls: GTK 4
on Linux, HTML through FastHTML on the web, Android views over JNI, AppKit and UIKit. The same file runs GPU kernels for
its data and its drawn views. A sixth host turns the view tree into MCP tools, so any agent can use the app.

**What Mojo made possible.** One language from the button to the kernel. The group-by behind a chart runs on the GPU in
the app's own process (MX frame, a Mojo dataframe engine), so a chart over 1M rows takes 0.5 to 0.7 ms and there's no
server in between. The grid and the charts are a display list replayed as GSK render nodes: a 1M-row grid scrolls at 0.8 ms
a frame (p95). The Data Lens colours 20M points in 1.5 ms on the GPU, 130 ms through the same function on the CPU.

**What I had to work around (Mojo 1.1), in case it helps others:**
- Cross-compiling to iPhone and Android objects works; the app then needs two runtime functions, which I stand in for
  with a small, clearly labelled C shim (`spike/kgen_shim.c`). I'd love an official answer here.
- FFI: scalars and `(pointer, length)` strings only, never structs by value; exports with `@export` and `abi("C")`.
- A `SIMD` vector indexed at run time as scratch space crashed the compiler; `stack_allocation` works.
- No Windows release yet, and no WebAssembly target (a spike is in `docs/wasm.md`).

**What doesn't work yet.** Mac and iPhone build and sign but no check runs them. The GPU path is NVIDIA only; other
machines use the CPU path. At 100M rows a median still runs on the UI thread (~0.7 s).

**Try it:**
```bash
git clone https://github.com/abhisheksreesaila/mxapp && cd mxapp && pixi install && scripts/omxplorer.sh
```

Repo: https://github.com/abhisheksreesaila/mxapp. MIT. Questions, and especially "you should have done X in Mojo", are very welcome.

[clip: omxplorer, a chart edited by its sentence]
