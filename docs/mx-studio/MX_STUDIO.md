# MX_STUDIO.md — build brief for the agent-native analytics workstation

_Written 2026-10-16. Read after `CLAUDE.md`, `ROADMAP.md`, `SPEC.md` and `EXPERIMENTS.md`. This brief expands ROADMAP decisions 6, 9, 10 and 11 into a build order. Where they disagree, `EXPERIMENTS.md` wins, then this file._

## 1. What we are building, in one paragraph

**MX Studio** is one app that does the jobs of Excel (edit transactions in a grid), Alteryx (build data pipelines), Power BI (pivots, charts, dashboards) and a SQL notebook (ask in words, get SQL, run it step by step). All four sit on **one engine, MX Frame**, written in Mojo and running on the user's own machine, Apple silicon first, using its GPU. The front end is Mojo too (mojo-ui), so it ships natively on every platform from one codebase. **Agents are the main users.** Desktop agents and MCP clients do the heavy lifting through typed tools; humans steer, check and touch: fix a cell, approve a suggestion, see where a number came from. This is not a clone of any existing product. It is different because of the points in §3.

## 2. Non-negotiables

1. **Engine first.** The UI will be redesigned several times; the engine must not be. MX Frame has to be correct, tested against an independent reference, benchmarked and boring before any screen work goes beyond a demo.
2. **Mojo everywhere.** Engine, plan, components, agent interface and UI are Mojo. Python is allowed only (a) as a **test oracle** (DuckDB or Polars, to check our answers) and (b) as a **temporary, clearly labelled shim** for file formats with no Mojo reader yet (e.g. `.xlsx`). Every shim gets a `SHIM:` comment and a line in `EXPERIMENTS.md`.
3. **Agent-native.** Every feature is built in this order: **engine op → agent tool → UI**. No feature may exist only in the UI. If a human can do it by clicking, an agent can do it by calling a tool, and both produce the same entry in the operation log.
4. **Human touch stays first-class.** Agents propose; humans can see, edit, approve, undo. Every write an agent makes is visible and reversible.
5. **Exact and traceable.** Numbers reconcile with the source to the cent. Every result carries its lineage (the plan that made it, row counts, source files). Anything binned, sampled or estimated says so on screen and in tool output.
6. **Local first.** Runs fully on one Mac with no server. The server engine (ROADMAP decision 11, level 1) comes later and must not change the protocol.
7. **Same working rules as `CLAUDE.md`:** one milestone (or less) per session, verify by running, log every session in `EXPERIMENTS.md`, explain plainly, list cons, mark anything unverified.

## 3. The ideas that make it different (protect these)

- **One plan for everything.** A pipeline step in Explore, a SQL cell in Query, a pivot in Sheet, a chart in Report and a hand-edited cell all compile to the **same logical plan IR**, a small serializable graph of operations. One optimizer, one executor, one lineage system. This is the real unification; the four screens are just four editors for the same thing.
- **Edits are pipeline steps.** When a person (or agent) changes a cell, it becomes a "Manual edits" step (row id, column, old value, new value, who, when) in the pipeline. A refresh keeps it. It can be audited and undone.
- **Everything is versioned.** Imports, edits, pipeline runs and agent actions append to an operation log. Versions share unchanged column chunks, so history is cheap. Undo, branches ("try this without touching the real data") and "what changed?" all come from the same log.
- **Every row, on the GPU, on your machine.** No sampling by default; Apple silicon's unified memory means the CPU and GPU share data without copying.
- **Agents are first-class citizens.** The tool interface is designed as carefully as the UI: compact answers, row counts, lineage, explain, and safe writes.

## 4. Architecture (layers, bottom to top)

```
 ┌───────────────────────────────────────────────────────────────────────┐
 │ Clients:  mojo-ui screens (Sheet · Query · Explore · Report)           │
 │           agents via MCP tools        both send the same operations    │
 ├───────────────────────────────────────────────────────────────────────┤
 │ Agent interface (MCP): describe · profile · query · explain · edit ... │
 ├───────────────────────────────────────────────────────────────────────┤
 │ Workbook: tables, objects (pivots, charts, cells), pipelines, op log,  │
 │           versions, lineage                                            │
 ├───────────────────────────────────────────────────────────────────────┤
 │ Front ends that compile to the plan: SQL parser · pipeline steps ·     │
 │           pivot spec · chart spec · words→SQL (local model)            │
 ├───────────────────────────────────────────────────────────────────────┤
 │ Logical plan IR (serializable) → optimizer → physical plan             │
 ├───────────────────────────────────────────────────────────────────────┤
 │ MX Frame execution: columnar memory · CPU SIMD + threads · GPU kernels │
 │           · I/O (CSV, Parquet, Arrow, XLSX)                            │
 └───────────────────────────────────────────────────────────────────────┘
```

Seams to keep (already in `CLAUDE.md`): `State` is plain serializable data; views are renderer-neutral data; nothing assumes the engine runs in the same process as the UI.

## 5. Build order

Milestone names use new prefixes so they don't clash with M0–M5: **P** prerequisites, **E** engine, **C** components, **A** app, **X** extensions. Each milestone lists its acceptance checks. Don't start a milestone until the previous one's checks pass, unless the owner says so.

### P · Prerequisites (do these first)

| ID | What | Acceptance |
|---|---|---|
| P1 | Pin the Mojo version and record it. Confirm the dev machine (Apple silicon Mac) and Mojo install. | `mojo --version` recorded in `EXPERIMENTS.md`. |
| P2 | **Apple GPU go/no-go.** Write and run the smallest Mojo GPU kernel (vector add, then a sum reduction over 100M floats) on the Mac's GPU. Record what works, what's missing, and the speed against the CPU. | Kernel runs and matches the CPU result exactly; timings logged. If it fails, stop and record why; the owner decides (CPU-first is the fallback). |
| P3 | **Test oracle.** Install DuckDB (Python) for test-only use. Write a harness: run the same query on MX Frame and DuckDB, compare results (exact for ints/decimals/strings; documented tolerance for floats). | Harness runs one trivial query both ways and reports a match. |
| P4 | **Reference datasets.** TPC-H at scale factor 1 and 10 (generated with DuckDB's `dbgen`), one public real-world set (e.g. NYC taxi, a few months), and a synthetic "orders" set with known, planted problems: duplicate customer spellings, a freight rate change on a known date, text in a number column, nulls. Store a manifest with row counts and checksums. | Manifest committed; planted problems documented with their exact rows. |
| P5 | **Benchmark harness.** Time each query 5 times, report median and spread, CPU vs GPU, rows/s, peak memory. Results go to a dated file so regressions show. | Harness runs on one query and writes a results file. |
| P6 | **mojo-ui M1** (from `SPEC.md`): `core/` with `State`, `Msg`, `update`, `view`, `ViewTree` and tests. Needed before any screen work, but can run in parallel with the engine. | SPEC §9 M1 checks pass. |

### E · Step 1: the MX Frame engine (battle-tested before anything else)

| ID | What | Acceptance |
|---|---|---|
| E1 | **Columnar memory.** Types: int64/int32, float64, **decimal (for money)**, string (dictionary-encoded), bool, date, timestamp; null bitmaps; chunked columns; stable row ids. Arrow-compatible layout where practical. | Unit tests per type, including nulls and empty tables; memory checks clean. |
| E2 | **I/O.** Read and write CSV (type inference, quoted fields, bad rows reported, not dropped silently), Parquet and Arrow IPC. XLSX read via a labelled `SHIM:` first, a Mojo reader later. | Round-trip tests; reading P4 data matches DuckDB row counts and checksums. |
| E3 | **Logical plan IR.** Operations as data: scan, filter, project, computed column, sort, aggregate, join, union, limit, distinct, pivot/unpivot, top-k, bin (for charts). Serializable to JSON and back. An `explain()` that prints it plainly. | Plans round-trip through JSON unchanged; explain output snapshot-tested. |
| E4 | **Expression language** for filters and computed columns: arithmetic, comparisons, and/or/not, null handling (SQL semantics), string functions (lower, trim, contains), date parts, casts. | Expression tests, including nulls and division by zero, all matching DuckDB. |
| E5 | **CPU execution.** All E3 operations on CPU with SIMD and threads. Hash group-by (sum, count, avg, min, max, count distinct, percentiles), hash joins (inner, left), sort. Deterministic float sums (pairwise or Kahan) so results don't change run to run. | All 22 TPC-H queries at SF1 and SF10 match DuckDB; random-plan fuzz tests (thousands of generated plans) match DuckDB. |
| E6 | **GPU execution** on Apple silicon (if P2 passed): scan, filter, computed columns, group-by aggregate, hash join, top-k, binning. The planner picks CPU or GPU per operation; results must be identical either way. | Same differential tests pass on GPU; benchmark shows where GPU wins and loses (log both). |
| E7 | **Optimizer basics:** filter pushdown, column pruning, join order for simple star joins, constant folding. | Plans before/after snapshot-tested; results unchanged; TPC-H times improve or stay equal. |
| E8 | **Hardening.** Large data (data bigger than GPU memory: chunk and stream; bigger than RAM: clear error, spill later), cancellation of long queries, progress reporting, clear error messages, no crashes on bad input. | Soak test: P4 data loaded, queried and freed 1,000 times with no leaks or crashes; fuzzed CSVs never crash. |

**Definition of "battle-tested" for the engine:** E1–E8 checks green; differential tests vs DuckDB on all TPC-H queries plus fuzzed plans; benchmarks recorded for CPU and GPU; memory checks clean; a written list of known gaps.

### C · Step 2: components on top of the engine (no UI yet)

Each component is its own module with its own tests. Build them in this order:

| ID | What | Acceptance |
|---|---|---|
| C1 | **Workbook and operation log.** A workbook holds tables, pipelines and objects. Every change (import, edit, step added, query saved, agent action) appends to an op log with who (person or agent name), when and why. Versions share unchanged column chunks. Undo, redo, branch, and diff between two versions. | Tests: undo/redo across mixed operations; a branch never changes the main version; diff lists exact changed cells and row counts. |
| C2 | **Cell edits as a pipeline step.** Editing a cell writes an overlay (row id, column, old, new, who, when) that becomes a "Manual edits" step; re-running the pipeline keeps it; edits whose row disappears upstream are flagged, not lost. | Edit → refresh → edit still applied; upstream conflict produces a clear flag. |
| C3 | **Pipelines (Explore model).** A DAG of named steps, each a plan fragment: input, join, filter, clean names (fuzzy), formula, summarize, output. Per-step preview: row counts in and out, a sample, timing. Cached step outputs; re-run only what changed. | A planted-problem pipeline on P4 data produces the documented expected output; changing one step re-runs only downstream steps. |
| C4 | **SQL front end.** Parser for SELECT, FROM, JOIN (inner, left), WHERE, GROUP BY, HAVING, ORDER BY, LIMIT, WITH (CTEs), compiling to the same plan IR. `EXPLAIN`. Friendly errors that point at the problem. | TPC-H SQL text runs through our parser and matches DuckDB; malformed SQL gives useful errors, never a crash. |
| C5 | **Pivot and chart specs.** A pivot spec (rows, columns, values, filters) compiles to a plan. A chart spec (Flint is the candidate, ROADMAP decision 9; check its license first) compiles to a binned query: never more marks than pixels. Results carry lineage. | Pivot results match an equivalent SQL query; a 1B-row chart query returns at most the screen-bin count. |
| C6 | **Profiling and anomalies.** On load: column types, null counts, distinct counts, histograms. Simple, explainable detectors: duplicate or near-duplicate names, sudden level shifts over time, type mismatches (text in number columns), outliers. Each finding includes the exact rows behind it. | All planted problems in P4 are found, each with the right rows; false positives on clean TPC-H data are counted and logged. |
| C7 | **Agent interface (MCP server).** Tools: `describe`, `profile`, `query` (SQL or plan), `explain`, `preview_step`, `add_step`, `edit_cells`, `pivot`, `chart`, `find_anomalies`, `list_versions`, `diff`, `undo`. Typed, compact JSON results with row counts and lineage. Reads are free; writes go through the op log, are labelled with the agent's name, and can require human approval (a setting). | An external agent (e.g. Claude Code via MCP) completes a scripted task end to end, e.g. "load orders, find duplicate customers, merge them, show revenue by customer," with every step visible in the op log and undoable. |
| C8 | **Words → SQL.** A local small model turns a question into SQL (or a plan). The SQL is always shown and editable. Checks run before showing results: rows covered, join fan-out warnings (a join that multiplies rows), empty results explained. | On a fixed set of 50 questions over P4 data with known answers: accuracy logged; every wrong answer is visible as wrong SQL, never hidden. |

### A · Step 3: the app (iterate on the UI; the designs are direction, not spec)

The prototypes are on two design canvases (see §8). Take the concepts, not the pixels. Expect several redesigns; that's fine because everything underneath is stable. Each screen is a mojo-ui view over the workbook; every action on it is a C7 tool call underneath.

| ID | Screen | First version must do |
|---|---|---|
| A1 | **Sheet** | A page of objects (like Apple Numbers): a transactions grid over a large table (virtual scrolling, any row count), editable cells (C2), pivot and chart objects that update after an edit, a side panel showing where the table comes from, what it feeds, and the edit log. |
| A2 | **Agent activity** | A panel that shows what agents did and propose: queries run, edits made, findings. Approve, reject, undo. This is what makes it agent-native for the human. |
| A3 | **Query** | Notebook cells: type (or speak) a question → SQL (C8) → editable → run → results. Step through cells, run all, save a cell as a pipeline step or open its result in Sheet. |
| A4 | **Explore** | The pipeline as a graph of steps; select a step to see its preview and settings; "describe a step in words"; manual edits shown as their own step. |
| A5 | **Report** | Charts and dashboards only, all reading pipeline outputs; cross-filtering; every tile shows its source and can open its rows. |

Order: A1 → A2 → A3 → A4 → A5. Start on the web host (M2) if the native Mac window (M4) isn't ready; the ViewTree is the same.

### X · Later (don't start until the owner asks)

- **Doc Intelligence plugin:** PDFs, scans and emails → fields with the page they came from and a confidence score → tables joinable to transactions. Low-confidence fields wait for a human.
- **Embeddings and semantic catalog** (ROADMAP decision 10), for search by meaning and fuzzy joins.
- **Decision model:** decisions as data (question, options, evidence rows, choice, later outcome), with simulations over all rows.
- **Menu-bar companion** that watches an open Excel file.
- **Time machine UI** over C1's versions.
- **Server engine and browser handoff** (decision 11, levels 1–2), collaboration, permissions.

## 6. What "agent-native" means here, concretely

- Agents are the primary users; the UI is how a person supervises and joins in.
- **Engine op → agent tool → UI**, in that order, for every feature.
- Tool results are designed for agents: small, typed, with row counts, lineage and an `explain`. Big results return a handle plus a summary, not a million rows.
- Agent writes are labelled, logged, reviewable and undoable. A setting decides which writes need human approval.
- Findings (anomalies, suggestions) come with the exact rows behind them, so an agent or a person can check them.
- Branches let agents try things without touching the real data.

## 7. Not now

Collaboration and sharing, permissions and row-level security, cloud connectors beyond files, the server engine, Windows and Android, custom chart renderer polish, the X list above.

## 8. References

- Product prototypes (Sheet, Report, Explore, Query, plus future concepts): https://claude.ai/artifact/8hAz9d7J6HeCFLSoNQJ3ik
- Earlier concept board (agent-native BI directions, instruments, anomaly field, scrubbable pivots, Numbers-style cues): https://claude.ai/artifact/SRTaF1ztWmpfWQv57PzJze
- These are private to the owner; the agent may not be able to open them. The concepts are summarized in this file.

## 9. Risks and cons to keep in view

- **Apple GPU support in Mojo** may be less mature than NVIDIA support. P2 decides; CPU-first with SIMD is a solid fallback, and the plan IR keeps GPU optional per operation.
- **Building a query engine is a big job.** DuckDB and Polars took years. Keep the operation set small (§5 E3), lean hard on differential testing, and add operations only when a screen or tool needs them.
- **SQL compatibility is a rabbit hole.** Support the subset in C4 well; say clearly what isn't supported.
- **Two-way edits break trust if conflicts are hidden.** C2's conflict flags are not optional.
- **Words → SQL fails quietly.** Always show the SQL and the coverage checks (C8).
- **Excel compatibility** (formulas, formatting, `.xlsx` quirks) will be requested early. Decide how far to go; the `SHIM:` reader buys time.
- **Agent tools are an attack surface.** Writes need labels, limits and an approval setting from the start.
- **Competitors exist in pieces** (Sigma Computing for spreadsheets over big data, Microsoft Fabric for combining Excel, Power Query and Power BI, HEAVY.AI and RAPIDS for GPU analytics). The edge is one engine, one plan, local GPU, Mojo end to end, and agents first. Keep checking that the product shows that edge.
- **Scope.** The engine plus four screens is a lot. One milestone per session, and stop when its checks pass.
