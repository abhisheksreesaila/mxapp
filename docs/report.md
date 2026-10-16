# Goal 10 report: the Workbook, usable (2026-10-16)

The owner's first real use of goal 9's Workbook found it dated-looking and hard to use: an inserted chart couldn't be found, neither the page nor the grid had a scroll bar, and you couldn't select a column to sort. Goal 10 fixes those without touching the engine. Goal 9's report is in `docs/goals/09-report.md`.

## Full check, headless (rebuilt from scratch)
```
PASS  M1  islands, quiet icon buttons, hairline fields, dotted page on GTK and web (screenshots at 1440×900 and 1280×800 in build/workbook/look-*.png)
PASS  M2  the page (1404 pt tall) scrolls inside a 1440×900 window on both hosts; the card below the fold is reached
PASS  M3  Insert Table/Pivot/Chart/Note puts the card in view on both hosts (identical states)
PASS  M4  scroll bar on the grid: thumb drag → Rows 10,101,007–10,101,014 of 20,000,000; track click → Rows 19,999,993–20,000,000 of 20,000,000; same rows on GTK and web
PASS  M5  a header tap selects the column (tinted, named in the formula bar); Sort sorts it; identical on both hosts
PASS  M6  Insert Pivot with `region` selected: 'Revenue by region and year'; fields labelled Rows, Columns, Value
PASS  M7  recompute 7.6 ms, grid redraw 9.5 ms, group-by ≤ 0.96 ms, sort category 0.35 s, cents 0.90 s, margin 2.38 s
PASS  M8  goal 9's checks (and goals 3–8's inside them) still pass
PASS  M9  formatting planned column-first, with each step's cost to the engine and the build order
```

## Screenshots, checked by eye
| Screen | Judgement |
|---|---|
| `look-gtk.png`, `look-web.png` (1440×900) | Islands for title, Insert toolbar, Open/Save, status, engine time; no grey bold buttons left; the page is a dotted canvas; GTK and web match closely (the web's pivot columns are tighter). |
| `look-1280-gtk.png`, `look-1280-web.png` (1280×800) | The whole 1232-pt page width fits, including the table's Sort button (it didn't at 1360 pt: D-98). |
| `column-sort-gtk.png` | The `cents` column is tinted, its header blue with a ▼; the formula bar says "Column cents". The arrow was a missing-glyph box on the first try; it's drawn as a triangle now. |
| `insert-*-gtk.png`, `tall-gtk.png` | Each inserted card lands in free space and the page scrolls to it; the window stays 1440×900 with scroll bars. |

## Engine speed, beside goal 9's
| Measure | Goal 9 | Goal 10 |
|---|---|---|
| GPU group-by on 20M rows | 0.8–1.9 ms | ≤ 0.96 ms (bench_frame) |
| Full page recompute (every pivot, chart, total) | ~8 ms (the engine caption) | 7.6–9.0 ms |
| Grid redraw (one scroll step, 1328×256 pt at 2×) | not measured | 4.4–9.5 ms (worst of 20; higher under load) |
| Sort 20M rows | 0.4–2.1 s | 0.35–2.38 s |

Nothing in goal 10 touches the engine. The only new per-interaction work is a press event on canvases and the page's scroll, both outside the data path.

## Review
One reviewer round found no blocking bug, and seven should-fix items. All are fixed in commit 2b476eb.
- A second table's scroll bar used the first table's size; each table card now sends its own gesture.
- A thumb drag could outlive its drag; a `RELEASE` gesture ends it (D-104).
- The header strip above the scroll bar acted as the track.
- On GTK, reveal in the narrow list layout used page positions; it uses the widget's real bounds now.
- The reveal ring ignored reduced motion.
- The lens redrew 20M points on every press.
- The bench didn't test Sort or the exact thumb position.

The reviewer also asked for this report and a note on where Insert places cards (D-103).

## Left for later
- Formatting: `docs/plans/formatting.md` (column formats → style/fill/overrides → widths → rules). Two items cost engine time and are flagged there: data bars' min/max pass and filtering by colour.
- No horizontal scroll bar on the grid yet: columns are clipped at the bar once formulas overflow the width.
- Several Table cards show one table with one shared selection.
- Keyboard: arrow keys and typing straight into a cell need key events the framework doesn't have yet.
- The Mac, iPhone and Android hosts don't know `Overlay` yet (the Workbook ships for Linux and web only).
