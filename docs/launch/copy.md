# omxapp launch copy (draft 2)

The words for the launch page, the README's top half, the tweet and the forum post. Design comes later, from the owner's design language; this file is only what we say. Every number has a source line; if a number has no source, it doesn't go in.

**Voice:** plain, confident, a builder talking to builders. Short sentences. No borrowed keynote lines. What makes it ours: every claim shows where it came from (the mono line under a number), and we say what doesn't work yet.

**Open questions for the owner**
1. **Name.** The page and README say *omxapp*; the repo is `mxapp`. One name everywhere?
2. **Who reads it first.** Mojo developers (Modular forum) want the GPU and one language; app developers (Twitter) want "one app, every screen" and agents. The hero below leads with the app developer; the forum post leads with Mojo.
3. **Section 2.** Draft 1 had "A native app. A GPU engine. An agent's toolbox. These are not three things." That's the 2007 keynote's shape. Draft 2 replaces it with our own: "Four programs, one file."

---

## 1 · Hero

**Eyebrow:** Public alpha

**Name:** omxapp

**Line:** Write an app once, in Mojo. It runs natively on every screen, computes on the GPU, and any AI agent can use it.

**Short line** (tweet, badge, og:title): One Mojo file. Every screen. The GPU underneath. Agents built in.

**Buttons:** Get the alpha · Read the story

**Picture:** omxplorer's report over a million orders.
`1,000,000 orders · every tile and chart recomputed in 0.3 ms · RTX 3090`

---

## 2 · Now possible (moved up: the page leads with it)

**Headline:** What one language makes possible.

**Lede:** Each of these used to mean another language, another process, or another team.

**Lead card, full width: An interface you can talk to** (the old "sentence" section folded in)
- Before: A chart is a picture with a label; you change it in a settings panel.
- Now: The chart is its sentence. Every underlined word is a setting: tap it to change it, or type what you want and it recomputes.
- > **Sum** of **revenue** by **product**, **largest first**, **top 5**, **every row**, as **bars**
- Try: "median" · "monthly, as a line" · "only paid and over 5,000" (tests/test_chartask.mojo; the last is goal 29 M2 on GTK)
- It says what it understood and names what it skipped instead of guessing. A keyword reader, instant and offline, not a model.
- Proof: `1,000,000 rows · answered in 0.7 ms · RTX 3090`

Then the other cards: *what it took before → what you do now → the measured proof.*

| | Before | Now | Proof |
|---|---|---|---|
| **One source, real native controls** | A web page in a wrapper, or one codebase per platform. | One `app.mojo` becomes GTK on Linux, HTML on the web, Android views, AppKit on the Mac and UIKit on iPhone. | `4 platforms run · 2 build` |
| **A million rows inside the interface** | A server or a notebook, then JSON back to the screen. | The group-by runs on the GPU, in the app's own process. No request, no copy. | `1M rows · a chart in 0.6 ms` |
| **GPU drawing in your app's language** | Shaders in GLSL or Metal, an engine in C++, glue to the UI. | A plain Mojo function colours the pixels. Without a GPU, the same function runs on the CPU. | `20M points · 1.5 ms a frame` |
| **Agents with no API** | Build an API, then an MCP server, or let the agent read screenshots. | The app's buttons and fields are its tools, from the first line. | `29 components proven through the agent` |
| **The model in the same program** *(Next)* | The interface calls a model over HTTP, and waits. | Mojo is the language Modular writes its AI kernels in. The model can live beside the interface, on the same GPU. | `not in the alpha` |

---

## 3 · The problem, then the turn

**Headline:** Four programs, one file.

**Body:** A serious app today is really four programs. The interface, written again for each platform. The data work, in Python on a server. The graphics, in a shader language. And an API, so other software, now AI agents, can use it. Every line between them is a rewrite, a network hop, or another team.

omxapp is one program. Mojo writes the controls, the data engine and the GPU code. The same file runs as a native app on each platform, and it's a set of agent tools the moment it runs.

---

## 4 · Native everywhere

**Headline:** Real controls, not imitations.

**Body:** A button is a GTK button on Linux, an HTML button on the web, an Android view on a phone, an NSButton on a Mac. Each platform brings its own look, keyboard and screen reader. The drawn parts, like charts and the million-row grid, are one Mojo display list, replayed by each platform's GPU renderer.

**Status:** Linux runs · Web runs · Agent runs · Android runs · Mac builds · iPhone builds
`"Runs" means a script drives it there today. Mac and iPhone build and sign; no check runs them yet.`

---

## 5 · Data on the GPU

**Headline:** Instant at a million rows.

**Body:** The code that sums your data is plain Mojo, running on the GPU next to the code that draws it. Nothing leaves the process.

| | |
|---|---|
| a chart over 1M rows, grouped and sorted | **0.6 ms** |
| the status bar's sum and average over 1M rows | **0.3 ms** |
| a frame of 1M-row grid scrolling (p95) | **0.8 ms** |
| 20M points counted and coloured, one 1080p frame | **1.5 ms** (130 ms on the CPU) |
| opening a 100M-row, 4 GB file, streamed | **0.2 s** |

**Honest edge:** At 100M rows in memory, a median chart takes about 0.7 s, and today the window waits for it. Moving that work off the window is the next piece of engine work.
`one Linux machine · NVIDIA RTX 3090 · docs/goals/26, 29`

---

## 6 · Agent native

**Headline:** Every app is already a set of agent tools.

**Body:** The agent is a platform, like Linux or the web. omxapp shows it the same app as a list of MCP tools: a button's tag names its tool, its tooltip describes it, and calling the tool is tapping the button. No API to write, no screenshots to read.

**A real session:**
```
→ choose-a-file  {"path": "orders_1m.csv"}
→ create-table
→ insert-chart
→ ask  {"text": "revenue by product, largest first, top 5"}
← Did ask.
  Now: chart0: 0.6 ms
  Now: inspector: Sum of revenue by product, largest first, top 5, as bars
```

**Three points:**
- **No per-app work.** Every omxapp app is an MCP server from its first line.
- **Safe by construction.** An agent can't do anything a person couldn't. A disabled button isn't a tool; a dialog's buttons exist only while it's open.
- **It hears what changed.** Every call answers in words: the new texts, what opened or closed, which tools appeared.

---

## 7 · Where it's going

**Headline:** GPU-native generative interfaces.

**Body:** Today an AI app is two programs: an interface on one side, a model behind an HTTP API on the other, and JSON in between. Mojo is the language of both: the GPU code that runs models, and the GPU code that draws and computes this app. So they can be one program, where the model reads the app's data where it already sits and the interface answers in the same frame.

| An AI app today | Where omxapp is going |
|---|---|
| interface in JavaScript or Swift | your app, in Mojo |
| → HTTP request, JSON | → the model: same process, same GPU |
| model server in Python | → the data engine: same GPU |
| → HTTP response, JSON | → the interface, drawn on the GPU |
| three languages, two processes, a network hop per answer | one language, one program, no API in between |

`Not in the alpha. Today the interface, the data and the drawing share one language and one GPU; the model is the next piece.`

---

## 8 · Get it

**Headline:** Available today.

**Body:** omxapp is a public alpha, free and open source under MIT. Linux with an NVIDIA GPU is the best place to start.

```
git clone https://github.com/abhisheksreesaila/mxapp
cd mxapp && pixi install
scripts/omxplorer.sh
```

**Buttons:** Get it on GitHub · Read the docs

---

## Footer note

Every number here is measured on one Linux machine with an NVIDIA RTX 3090, by a script in the repository. "Runs" means a script drives the app on that platform today. The model in the same program is the next step, not part of the alpha.

**Links:** GitHub · README · Install | Reference · Components · Architecture | Agent host · Android · Web | Gallery · Decision log · What's next
