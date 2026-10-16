# Formatting in the Workbook: the plan (goal 11 candidate)

Status: proposed, 2026-10-16. Asked for by the owner after the polish pass: "in any app like this we want to format the cell, add colours, simple text formatting… plan next once you fix the basics". Nothing here is built yet.

## The principle: format columns, not cells
Numbers and Excel store a format per cell. On 20M rows that is 20M format records, which is exactly the cost the Workbook avoids for values (shared columns plus a sparse overlay). So formatting follows the same shape as the data:

1. **Column formats** (the default, and almost always what people want): one record per column.
2. **Rules** (conditional formats): one small expression per rule, evaluated per *visible* row.
3. **Cell overrides** (the exception: "make this one cell red"): a sparse map, like edited values.

A column format is chosen from the column header (tap the header, then the format bar). A cell override is chosen with a cell selected.

## What a format holds
| Part | Choices | Applies to |
|---|---|---|
| Number format | integer, decimal places (0–4), thousands separators on/off, currency ($, €, £, ₹), percent, compact (1.2M) | INT, DECIMAL, formula columns |
| Date format | 2025-10-09, 9 Oct 2025, Oct 2025, Q4 2025, weekday | DATE |
| Text style | regular / medium / bold, italic, colour (8 swatches + ink) | every column |
| Fill | none or one of 8 tints (Fluent's shared colours, 10% strength so text stays readable) | every column |
| Alignment | auto (numbers right, text left), left, centre, right | every column |
| Width | drag the header edge (stored per column) | every column |

Conditional rules (first match wins, at most 8 per table): `when <expression> then <style>`, using the formula language that already exists, e.g. `when margin < 0 then text red`, `when cents > 1000.00 then fill green`, plus two presets that need no typing: **data bars** (a bar inside the cell, scaled to the column's min and max) and **colour scale** (low → high tint).

## What each part costs the engine
| Part | Memory | GPU / aggregation | Redraw | Verdict |
|---|---|---|---|---|
| Column format | ~100 bytes per column | none: aggregation works on the raw scaled integers | the grid formats ~10 rows × ~12 columns per frame (as now) | free |
| Cell override | ~40 bytes per formatted cell, sparse | none | a hash lookup per visible cell (~120 per frame, < 0.1 ms) | free at human scale; a "format 1M cells" action becomes a rule, not 1M overrides |
| Conditional rule | the rule's bytecode | none for showing it; the existing per-row evaluator runs on visible rows only | ≤ 8 rule evaluations per visible cell (~1,000 per frame, well under 1 ms) | free |
| Data bars / colour scale | none extra | needs the column's min and max: **one GPU min/max pass (≈1 ms on 20M rows) when the column changes**, cached, not per frame | a rectangle per visible cell | cheap; the one place formatting touches the GPU |
| Filter by colour / sort by colour | — | would need the rule evaluated on all 20M rows (a GPU kernel, ~2 ms) | — | **later, and the only item that costs real engine time**; flagged |
| Rich text inside one cell (two colours in one value) | per-cell runs | — | text layout per run | **not planned**: columns of typed values aren't documents; notes are where rich text goes |

None of this slows the group-by, the pivot, the charts or the crossfilter: formats are applied only when drawing what's on screen. The two items with an engine cost are called out (data bars' min/max pass; filtering by colour).

## Where it lives
- `mojoui/frame.mojo`: `ColumnFormat` (number/date/text/fill/align/width) per column, `overrides: Dict[Int, CellFormat]` beside `cells`, `rules: List[Rule]`; formats are part of the edit log, so Undo covers them.
- `mojoui/workbook.mojo`: formats, overrides and rules saved in `workbook.json` (an agent can write `"format": {"cents": {"currency": "$", "places": 2}}`).
- The Workbook app: a **format bar** island that appears when a column or cell is selected (number format dropdown, B/I, text colour, fill, align; a "Rules…" button), and the grid's draw applies it. Pivots and charts take the value column's number format (a pivot of `cents` shows $; of `margin %` shows %).
- Both hosts: nothing new (it's all drawn on the grid canvas and built from existing controls), so it works the same on GTK and the web from day one.

## Build order (each a verifiable slice)
1. **Number and date formats per column**, with the format bar; pivots and charts follow the column's format. Check: `$1,574.96`, `1.6K`, `9 Oct 2025` shown identically on GTK and web; aggregation timings unchanged.
2. **Text style, fill and alignment per column**, then **cell overrides**. Check: a bold red column and one filled cell survive save → open; Undo removes them.
3. **Column widths by dragging the header edge** (and a horizontal scroll bar for the grid once columns overflow). Check: widths round-trip through the file.
4. **Conditional rules** (`when … then …`) and the two presets (data bars, colour scale). Check: `when margin < 0 then text red` colours exactly the rows whose margin is negative on screen; the min/max pass measured (≤ 2 ms).
5. Later, only if wanted: sort or filter by colour (a GPU pass over all rows).

## Open questions for the owner
- Should a pivot or chart copy the table's colours (a red column stays red in the pivot), or only its number format?
- Is one table per workbook still the model, or do several tables (several data sources) come first? Several tables would change where formats live (per table, not per page).
