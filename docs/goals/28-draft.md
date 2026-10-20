# GOAL 28 (draft; was 27 until the owner put polish first, D-260): editing a chart, the title is the query

**End goal (owner, 2026-10-19):** "for reports, charts can be on the inspector and a sub-inspector can have settings… but we need to be creative with UI… can't ship an Excel clone, it will be rejected"; then, on the prototypes (docs/design/charts/): "The title is the query: ask, then tap any word is the genius!!" Decided (D-255): direction 3 at the core (the chart's title is a sentence whose words are its settings; an ask field rewrites it), direction 1's inspector pages behind it for the details, the toolbar only inserts. The ask field is a keyword matcher now; the agent (AG-UI) plugs into the same sentence later.

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M0 | One chart model | `ChartSpec` in mojoui (value, combine: sum / average / count / median, group by, sort, top N, a filter, mark: bars / line / donut), used by sheet charts and report chart tiles alike; saved in `.omx` (old files open unchanged); tests: each setting changes the computed groups as pyarrow does |
| M1 | The title is a sentence | every chart's title reads its spec ("**Sum** of **amount** by **region**, **largest first**, **top 5**, as **bars**"); each setting word is a token: tap it, a popover offers its choices, the chart changes; GTK and the web (a new `Sentence` view: text runs and tappable tokens) |
| M2 | Ask | an ask field under the title takes a phrase ("top 3, unpaid, as a line", "average by month") and changes several settings at once; it says what it understood, and the words that changed flash once; a phrase it doesn't understand changes nothing and says which words it skipped; the parser is plain Mojo with its own tests (30+ phrases) |
| M3 | Inspector pages | selecting a chart turns the inspector into Chart: rows that say what is set (Data, Style, Axes) and open a page that slides in, with a back chevron and Esc; a framework `InspectorPages` (GTK: GtkStack slide; web: CSS transform), its test |
| M4 | The toolbar only inserts | no chart formatting in the toolbar on either tab; Insert Chart picks the first sensible columns and opens the chart's inspector |
| M5 | Marks move | a spec change animates the bars to their new sizes and places (keyed by group, 320 ms, the calm curve) instead of a cut; drawn through the Scene on GTK with `MOJOUI_SCENE=1`, so a frame stays under 1 ms |
| M6 | With real input | scripts/live.py: tap "sum", choose average, the figures equal pyarrow's; type an ask, press Return, the title and bars match; Undo takes back one ask as one step |
| M7 | Nothing regressed | goal 26's checks pass (M6 still the owner's) |

## Out of bounds
Dragging columns onto the chart (direction 2's wells); an LLM behind the ask field (AG-UI later); the menu-bar island (goal 28); charts for the web, Apple and Android drawn through the Scene (they keep pixels).

## Done means
PASS for M0–M7, the reviewer passes it, a short `docs/report.md` with screenshots of a sentence being edited.

## What the code map found (2026-10-19, before starting)
- Charts only **sum** today; `Sums` already has counts and present counts, so average and count per group are cheap; a **median per group** needs engine work (MX frame or our own): M0 offers sum / average / count first, median only if the engine gives it.
- No sort, no top N, no per-chart filter (one global Report filter: `ReportFilter{col, code}`).
- **Chart changes aren't undoable** (Undo only goes to the table's log): M6's "Undo takes back one ask" needs an app-level settings log.
- `.omx` is FORMAT 2 with optional keys and defaults: the spec goes in as new optional keys (no format bump, old files open).
- Nothing like tappable text tokens exists, and no host has slide-in pages: `Sentence` and `InspectorPages` are new view kinds (34, 35) on GTK, web and the agent; Mac/iPhone/Android in the debt table.
- Checks in the live chain that pin today's chart: status starts with "Chart: " (goals 22–23), `read chart-1` tab-separated numbers (20, 22), the toolbar names (21). Goal 15's archived check (titles "revenue by region", `segment:1=Line`) isn't in the chain.
