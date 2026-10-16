# SCREENS.md — the designed screens, described for the agent

_Written 2026-10-16. Companion to `PLAN.md` and `MX_STUDIO.md`. The owner's design canvases are private, so every screen is described here, and each screen's source is saved in the project under `mojo-ui/design/`._

## How to use this file

- These screens are **direction, not spec.** Keep the concepts, interactions and information on each screen; expect the layout and styling to change in UI iterations.
- Every action on a screen must exist first as an **engine operation** and an **agent tool** (MX_STUDIO.md §2, §6). The screens are one client of those tools, not the only one.
- The numbers on the screens are **illustrative** (a fictional ledger of ~2.4B orders with a planted story, below). Use the reference datasets in MX_STUDIO.md P4 for real tests.
- **Source files** (`.dc.html`) are HTML with a small template layer: `{{name}}` holes are filled from the `renderVals()` method in the `<script type="text/x-dc">` block at the bottom; `<sc-for>` repeats, `<sc-if>` shows or hides. Read the markup for layout and copy, and the script for the interaction logic. They need the design tool's runtime to render, so treat them as readable references, not as code to ship.

## The story every screen shares

One fictional company's orders ledger (~2.42B transactions; customers Acme Corp, Northwind, Globex, Initech; products Trail Pack, Tent 2P, Camp Stove; carriers A, B, C). The planted problems:
1. **Q3 gross margin fell 3.1 points** (41.8% → 38.7%).
2. **Carrier A's rate table v7** started charging a flat **$14.20** freight on parcels over 4 kg on **Jul 14**; heavy Outdoor items (e.g. SKU OUT-4471, $48 sale) went to negative margin. This explains about 2.7 of the 3.1 points.
3. **Duplicate customer spellings** ("Acme Corp.", "ACME Corporation") split one customer across pivot rows; merged, Acme is the top customer.
4. **412 duplicate orders** sharing ZIP 94110 (likely a double import).
5. The **carrier contract PDF** says v7 starts **Aug 1**, so 31,312 parcels were billed early (Doc Intelligence).

Build P4's synthetic dataset to reproduce this story so the screens can be tested end to end.

---

## Part A · MX Studio (the product) — `mojo-ui/design/mx-studio/`

### Look and feel ("Liquid Glass", light)
- Ground `#e6e9ef`. Chrome (top bar, side panels) is frosted glass: `rgba(255,255,255,0.62)`, backdrop blur 24px + saturate 170%, 1px border `rgba(255,255,255,0.85)`, soft shadow, radius 22px. Content (tables, charts, cards) is solid white, radius 18px.
- Text `#16181d`, secondary `#3c4250`, muted `#5b616e`. Accent `#2563eb` (tweakable). Anomaly/warning `#c2410c` / `#ea580c` on `#fff7ed` with `#fed7aa` border. Good/OK `#0f766e`.
- System font stack (SF Pro on Mac), tabular numbers everywhere numbers line up.
- **Mode switch** in the top bar: a capsule segmented control `Sheet · Report · Explore · Query` (plus `Docs` when the plugin is on). Same chrome on every mode.
- Every number that comes from the engine shows its source and scale nearby ("orders_clean · 2,418,330,116 rows · 18 ms").

### 1. Sheet — `Main.dc.html` (interactive) · milestone A1
- **Purpose:** Excel-like editing and analysis on one page, like Apple Numbers: tables, pivots and charts are objects placed together on a sheet, not one endless grid.
- **Layout:** top glass bar (doc title "Q3 Orders", mode switch, insert buttons: Table, Pivot, Chart, Text, Formula, Agent) → sheet tabs (Orders, Customers, Products, +) → canvas: **Transactions table** (left, selected), **agent card**, **Pivot 1** (revenue, customer × product), **Chart 1** (bars from Pivot 1) → right glass inspector (Table / Data / Style tabs).
- **Interactions (working in the prototype):** customer names are editable cells; typing recalculates the pivot, chart, totals and distinct-customer count on every keystroke. The agent card detects near-duplicate spellings (normalizes case, punctuation, Corp/Inc) and offers "Merge into Acme Corp"; affected cells and pivot rows are tinted orange. When clean, a green card says the edits are saved as a step in Explore. Inspector shows **Comes from** (orders_clean, the Explore output), **Feeds** (Pivot 1, Chart 1, Report tiles), **Your edits** (log of from → to), **Undo all edits**.
- **Engine/tools behind it:** C1 op log, C2 cell edits as a pipeline step, C5 pivot/chart specs, C6 duplicate detection, C7 `edit_cells`, `pivot`, `chart`, `find_anomalies`, `undo`.

### 2. Report — `Report.dc.html` · milestone A5
- **Purpose:** a charts-only tab for dashboards, Power BI style.
- **Layout:** report page tabs (Revenue, Margin, Customers, +), filter capsules (Quarter, Region, Product), **KPI row** (Revenue $1.11B, Orders 121.6M, Gross margin 38.7%, Active customers 31.6M "after merging duplicates"), **revenue vs margin by week** (with the Jul 14 rate-table marker), **Top customers** (Acme +$38M "once 3 spellings were merged", with "Edit data" link to Sheet), **Product mix**, **Margin heatmap** (region × product), **"Worth a look"** anomaly card (links: open the rows, see the pipeline step), footer: every tile reads orders_clean, edits in Sheet redraw tiles.
- **Engine/tools:** C5 chart specs with binning, cross-filtering, lineage per tile.

### 3. Explore — `Explore.dc.html` · milestone A4
- **Purpose:** Alteryx-style pipeline from files to an output table.
- **Layout:** "Add a step" chips (Input, Join, Filter, Clean, Formula, Summarize, Output, **Describe a step in words**) → **pipeline graph**: inputs `orders.xlsx` (48,210 rows), `ledger` (2.42B), `rate_tables.csv` (212) → Join (on carrier, date) → **Clean names** (selected) → **Manual edits** (dashed, "2 cells, from Sheet", "edited like Excel") → Margin (formula) → Remove returns (filter) → **orders_clean** output ("feeds Sheet · Pivot 1 · Chart 1 · Report"); each node shows its time → **step preview** for the selected node (before → after, rows, match score, keep/review checkbox per change) → stats (rows in, rows out, names merged, whole run 1.8 s) → right inspector for the step (column, method "fuzzy match, ignore Corp/Inc", threshold slider 0.90, the step **in words**, "runs as Mojo on the GPU", "Open output in Sheet").
- **Key idea:** hand edits from Sheet appear as their own pipeline step, so refreshes keep them and they can be audited.
- **Engine/tools:** C3 pipelines, C2, C7 `preview_step`, `add_step`.

### 4. Query — `Query.dc.html` (interactive) · milestone A3
- **Purpose:** a SQL notebook, Jupyter-style: ask in words (or speak), get SQL, edit it, run it, step through cells.
- **Layout:** top bar with "Running on this Mac · Apple silicon GPU", **Step** and **Run all** → left glass panel: **Tables** (orders_clean, products, carriers with columns and where each came from), **Try asking** examples, a note on what the prototype supports → **cells**: `In [n]` question box with mic button and **Write SQL**, editable SQL text area, **Run cell**, "Save as pipeline step", "Open result in Sheet", results table with a share bar, `Out [n] · saved as qn`, status (not run / edited · run to update / ran) → **+ New cell**. The next cell to run is outlined.
- **Interactions (working):** a rule-based words → SQL generator (picks the group-by column from the question, adds JOINs to products and carriers when the question mentions margin, freight, cost or carrier, adds WHERE region, TOP n → LIMIT) and a tiny SQL interpreter over 12 sample rows (SELECT, JOIN, WHERE col = 'x', GROUP BY, ORDER BY, LIMIT; read-only; clear errors). The real versions are C4 (SQL) and C8 (words → SQL with a local model).
- **Engine/tools:** C4, C8, C7 `query`, `explain`.

### 5. Menu-bar companion — `Companion.dc.html` · later (X)
- A small glass popover that **watches the Excel file you have open**: revenue this quarter with a sparkline, **"Since your last save"** findings (214 new rows over $14 freight; a new spelling "ACME Corporation" with Merge / Leave it; a column that turned into text), an "Ask about this file" box, "On this Mac · nothing leaves it", "Open in MX Studio". Horizon: 2–3 months. The easiest way to start using it: people keep Excel and get MX Studio alongside it.

### 6. Doc Intelligence plugin — `Docs.dc.html` · later (X)
- **Purpose:** PDFs, scans and emails become rows that join to transactions.
- **Layout:** drop zone and documents list (carrier rate schedule PDF, 41 invoice PDFs, 612 customer emails) → **page preview** with highlighted passages → **Extracted fields** table (field, value, confidence; low-confidence fields wait for a human) → **"The contract and the ledger disagree"** card (contract: Aug 1; ledger and invoices: Jul 14; 31,312 parcels billed early; actions: show parcels, add the contract as a pipeline input, draft a claim) → three notes: matched by meaning (invoice "Bill-to" ≈ customer), every value has a source, search the text too.
- **Rule:** never invent a field; every value links back to its spot on the page.

### 7. Decisions — `Decisions.dc.html` (interactive) · later (X)
- **Purpose:** the home screen is a list of decisions to make, not charts to read.
- **Layout:** open decisions list (move heavy parcels off Carrier A; claim back early-billed freight; raise Tent 2P price 4%) → selected decision with a **slider** (share of heavy parcels moved to Carrier B) → live outcomes: gross margin, freight saved per quarter (with range), average delivery time, Carrier B capacity used (turns orange above 88%) → an **uncertainty band** from simulations → Approve at N% / Ask ops to review / Try it on 10% first → why the model suggests it, what would change its mind, what it's built from.
- **Rule:** track predicted against actual outcomes from day one.

### 8. Data time machine — `TimeMachine.dc.html` (interactive) · later (X)
- **Purpose:** every import, edit, pipeline run and document is a version you can scrub through.
- **Layout:** a version slider plus six clickable version chips (Jul 1 imported, Jul 14 new rate table, Aug 3 clean names, Aug 3 two cell edits, Sep 2 contract PDF, Oct 16 now) → KPIs at that version (rows, gross margin, customers, top customer) → **what changed** (who, what, a before/after table) → "Ask the history" (e.g. margin started falling Jul 14 from new ledger rows, not from any edit) → why it matters (version on every number, undo across everything, branches, shared unchanged columns keep history cheap).
- **Engine:** C1 versions and diff.

---

## Part B · Earlier concept board (exploration) — `mojo-ui/design/concepts/`

These came before MX Studio. Ideas marked **adopt** feed the product; **later** are future directions; **dropped** were too close to existing tools.

| File | Concept | Idea it carries | Status |
|---|---|---|---|
| `Main.dc.html` | A · Ask-first | Question → agent plan → answer with a margin bridge; agent trail with the Mojo it ran, editable | **adopt** the agent trail (A2 activity panel) |
| `Findings.dc.html` | B · Findings board | Agent proposes findings; human curates a board of live tiles; change log | **adopt** propose → approve pattern |
| `Workbench.dc.html` | C · Every-row workbench | Virtual table over all rows, filter chips, agent adds a filter (marked "agent") | dropped as a screen; **adopt** "agent-added" labels |
| `Instrument.dc.html` | D · Question becomes an instrument | No chat; a bespoke scrubbable view per question; dialogue shown as a filmstrip of views | later |
| `Radar.dc.html` | E · Data watches itself | Home = every metric × every week scored for surprise; a lens per hot cell; watches in plain words | later; **adopt** "watches in plain words" |
| `Canvas.dc.html` | F · Shared canvas with branches | Dialogue by doing (drop chips, circle a region); human and agent forks compared; replayable timeline | later; branches are in C1 |
| `Sheet.dc.html` | G · The sheet is the database | 2B-row grid, column-wide formulas in words, **histogram in every column header**, cells that hold a chart, pivot or what-if, exact status bar | **adopt** header histograms and exact status bar in A1 |
| `Pivot.dc.html` | H · Scrubbable pivot | Pivot cells show the **distribution**, not just an average; time scrubber replays the pivot; agent ranks which pivot explains a change | **adopt** as a Number / Distribution / Trend toggle and "explain this change" |
| `Model.dc.html` | I · Measures in plain words | Measures written in words, compiled to readable Mojo, checked against every row, with lineage; no DAX | **adopt** for the measure layer (ROADMAP decision 6.2) |
| `Page.dc.html` | J · Page of objects | Numbers-style page with tables and charts placed freely; inspector panel | **adopted** into MX Studio Sheet |
| `Categories.dc.html` | K · Categories | Grouped rows with live summary rows and spread shapes; chart with a play/scrub slider | **adopt** categories in A1 tables |
| `Tablet.dc.html` | L · Tablet with pencil | Circle to ask why, strike to exclude, arrow to compare, write a question | later (iPad) |

The concept board's dark screens (A–I) use IBM Plex Sans/Mono on near-black; the light ones (J–L) moved to the system font, which MX Studio keeps.

## What the screens add to the build

- An **agent activity panel** (A2) is required, not optional: it's how a person supervises agents.
- **Every finding carries its rows** (anomaly cards, doc mismatches, decisions).
- **Plain-language mirrors everywhere:** filters, pipeline steps, measures and watches all have a words version next to the exact one.
- **Scale and source labels** next to engine numbers ("N rows · ms · on this Mac").
