# PLAN.md — the unified plan: one engine, a ladder of views

_Written 2026-10-16. Read after `CLAUDE.md`. Details for the first app are in `MX_STUDIO.md`; decisions are in `ROADMAP.md`; real results in `EXPERIMENTS.md` (which wins when they disagree)._

## The idea in one paragraph

Start where the owner is strongest: **data transformation**. Build **one Mojo engine** (MX Frame plus a WebGPU graphics core) that is designed from day one to handle both data and graphics, but point it first at crunching data and drawing charts. Then the **view layer climbs a ladder**: 2D charts → 3D data scenes → animated scenes → characters. Each step reuses everything below it. Everything is Mojo, front end and back end, using Mojo's GPU support on every machine, Apple silicon first, running locally.

## Why one engine can serve all of it

To this engine, animation is just more data:
- a keyframe track is a time series
- a skeleton pose is a row
- a crowd is many copies (instances) of one mesh
- a scene can be stored as columns, so a timeline is a query, and scrubbing time works the same for sales figures and for a character's walk

## The stack (shared by every step)

| Layer | What | Where it's decided |
|---|---|---|
| UI core | mojo-ui: `State`, `Msg`, `update`, `view` → `ViewTree`; thin hosts (web, native) | SPEC.md, ROADMAP decisions 1–5 |
| Data engine | MX Frame: columnar, CPU SIMD + GPU, one logical plan IR | ROADMAP decision 6, MX_STUDIO.md §4–5 |
| Graphics core | WebGPU API: browser WebGPU on web, wgpu-native or Dawn from Mojo on native; one set of WGSL shaders | ROADMAP decision 12 |
| AI | Local models through MAX (small language model, embeddings, later pose/voice) | ROADMAP decision 10 |
| Agents | One MCP tool interface; every action is an operation in a versioned log | MX_STUDIO.md §6 |
| Web apps | SaaS pages stay FastHTML; Mojo only for data/AI-heavy pieces | ROADMAP decision 13 |

## Build order

### Step 0 · Prerequisites
- Pin the Mojo version.
- **Apple GPU go/no-go:** a Mojo GPU kernel on the Mac (vector add, then a 100M-float sum), checked against the CPU.
- **WebGPU spike:** Mojo draws through wgpu-native or Dawn on the Mac: a triangle, then 1M points, then text.
- Test oracle (DuckDB, test-only), reference datasets, benchmark harness (MX_STUDIO.md P1–P5).
- mojo-ui **M1** (SPEC.md §9).

Acceptance: each spike's result and timings logged in `EXPERIMENTS.md`. If the Apple GPU or WebGPU spike fails, stop and record why; the owner decides.

### Step 1 · Foundations (in parallel)
- **MX Frame engine,** battle-tested: MX_STUDIO.md E1–E8 (every answer matches DuckDB, identical results on CPU and GPU, soak tests clean).
- **mojo-ui hosts:** M2 web, M3 Linux window, M4 Mac window.
- **Graphics core v1:** points, lines, rectangles, text, many copies of one shape drawn in one call, pan/zoom, hit-testing; fed from engine results.

### Step 2 · Shared components
Versioned operation log (undo, branches, diff), MCP agent tools, the path from engine results into GPU buffers, local model runtime. Details: MX_STUDIO.md C1–C8.

### Step 3 · The view ladder

| Rung | Build | Demo that proves it | Reuses |
|---|---|---|---|
| 1. Data + 2D charts | **MX Studio**: Sheet, agent activity, Query, Explore, Report (MX_STUDIO.md A1–A5) | Real data in, edits, pivots, charts, agents working, all on the Mac | Everything in steps 0–2 |
| 2. Data in 3D | **mojo3d basics**: three.js-style API names (Scene, Camera, Mesh, materials) on the graphics core; point clouds, 3D scatter, terrain, network graphs | A billion-point "customer galaxy" you can fly through | Engine, graphics core, binning |
| 3. Animated scenes | Scene graph as data (OpenUSD), keyframes as time-series columns, transitions, camera moves, simple physics; the data time scrubber becomes the animation timeline | An animated, scrubbable 3D scene built and edited by an agent | Op log, versions, timeline, agents |
| 4. Characters | Rigs and skinning, poses from a webcam, lip sync from voice, AI "crew" notes: the **local AI animation studio**, starting with "script to animatic overnight" | A character acting a short scene, fully offline | All of the above |

Rule: **finish each rung's demo before starting the next.**

## Build in from day one (so later rungs don't force rewrites)
- The engine's column format can be handed straight to GPU buffers.
- Time is a first-class column type.
- The view description (`ViewTree`) can grow into a scene tree; keep it plain data.
- The graphics core supports drawing many copies of one shape (instancing) from the start.
- Every human and agent action is an operation in the log.

## Working rules (same as CLAUDE.md)
One milestone or less per session. Verify by running. Log every session in `EXPERIMENTS.md`. Explain plainly and list cons. Mark anything unverified. Production code is Mojo; Python only as a test oracle or a labelled `SHIM:`. Don't commit or push unless asked.

## Risks and cons
- **Rung 4 is a much bigger jump than rungs 1–3:** skinning, pose and voice models, model licenses (many are non-commercial), consent for voices and likenesses. Plan it as its own project.
- **Mojo on the Apple GPU** is the first thing to check; everything depends on it.
- **Mojo compute ↔ WebGPU drawing starts with a copy.** Fine for charts, painful for live characters at 60 fps. Zero-copy is a rung-3 goal.
- **No ray tracing in WebGPU yet.** Film-quality final frames need native Metal/Vulkan ray tracing or Mojo GPU path tracing.
- **The engine is the long pole.** DuckDB and Polars took years; keep the operation set small and test against DuckDB.
- **Focus.** Each rung tempts you to start the next one early. Don't.
