# GOAL 28: editing a chart, the title is the query

**End goal (owner, 2026-10-19):** "for reports, charts can be on the inspector and a sub-inspector can have settings… we need to be creative with UI… can't ship an Excel clone, it will be rejected"; on the prototypes (docs/design/charts/): "The title is the query: ask, then tap any word is the genius!!" Decided (D-255): the chart's title is a sentence whose words are its settings (tap one, pick another); an ask field rewrites several at once; the inspector's pages hold the details; the toolbar only inserts. The ask field is a keyword matcher now; an agent (AG-UI) plugs into the same sentence later. After goal 27 (owner: "looks beautiful… I can see it's an app… continue").

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M0 | One chart model | a chart (on the sheet or a Report tile) has: combine (sum, average, count), value, group by, order (as in the table, largest first, smallest first, A to Z), top N (all, or 3, 5, 10), one filter (a text or Yes/No column's value, or every row), mark (bars, line); its numbers equal pyarrow's for 12 specs over small.parquet; a document saved with them reopens with them (and an older .omx opens unchanged) |
| M1 | The title is a sentence | every chart's title reads its spec ("**Sum** of **amount** by **region**, **largest first**, **top 5**, **every row**, as **bars**"); each setting word is a token: tap it, a popover lists its choices (the current one marked), pick one, the chart changes; GTK and the web; a framework `Sentence` (text runs and tokens, wrapping to lines), its test |
| M2 | Ask | a field under the selected chart's sentence takes a phrase ("top 3, unpaid, as a line"; "average by region"; "only West") and changes those settings at once; it says what it understood and what it skipped; the words that changed are marked for a moment; a phrase it can't use changes nothing; the parser is plain Mojo with ≥ 30 phrases tested |
| M3 | Inspector pages | selecting a chart shows its inspector: the sentence, then rows that say what's set (Data, Order, Filter, Style), each opening a page with a back button; framework `InspectorPage` and `NavRow` on GTK and the web; Report chart tiles get it too |
| M4 | Undo, and the toolbar only inserts | Undo takes back a chart change (a token, an ask: one step each), in order with table edits; Insert Chart (sheet) and Chart tile (Report) open the chart's inspector; no chart settings in any toolbar |
| M5 | Bars move | a spec change animates the bars to their new lengths and places over ~320 ms (bars keyed by their group, the calm curve) instead of a cut; every frame in between is drawn; ≤ 3 ms a frame for a 6-bar chart |
| M6 | With real input | scripts/live.py on GTK: click "Sum" in a chart's title, pick Average, the bars read pyarrow's means; type "top 3, as a line" and Return: the title and the line match; Undo twice brings back the first chart |
| M7 | Nothing regressed | goal 27's checks (M0–M8; every earlier goal inside them) pass |

## Out of bounds (waiting on MX frame: docs/mxframe-needs.md)
Median or percentiles per group, grouping by month or week, filters on ranges or several conditions (goal 29: MX frame 321870f has them, D-265); dragging columns onto a chart (direction 2's wells); an LLM behind the ask field; the menu-bar island (goal 30).

## Done means
`scripts/check` prints PASS for M0–M7; the reviewer passes it; `docs/report.md` is short with shots of a sentence being edited; pushed to `origin`.
