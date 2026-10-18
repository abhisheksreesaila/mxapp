# GOAL 21: omxplorer's formatting, tabs and toolbar, the way a spreadsheet user expects

**End goal (owner, 2026-10-18, after trying 1M rows):** "when I say formatting you need to be able to provide the same set of stuff, bold underline all the stuff a cell can be done … you should be able to rename the tabs and ideally the tabs can follow the same format as Excel and can be at the bottom so that you get real estate at the top … if it's a report you have to have report controls if it's a transaction or a sheet it has to have sheet controls."

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | Cell and column formatting | omxapp gets the pieces: a cell style (bold, italic, underline, strikethrough, text colour, fill, alignment), a grid that draws it, an italic face, icon-only toggle buttons (`ICON_ON`) and a swatch picker; omxplorer's sheet toolbar has Bold, Italic, Underline, Strikethrough, Text colour, Fill, Align left/centre/right, Currency, Percent, fewer/more decimals and Clear formatting, also in the Format menu (Ctrl+B/I/U); they apply to the selected cell, or the whole column when a column is selected; Undo takes them back; they survive Save → open (.omx); a Mojo test proves the drawn pixels (fill, bold, italic, underline, strikethrough, colour, alignment) and the sheet's styles, overrides, undo and file round trip; driven on GTK and the web, the same steps give the same styles |
| M2 | Tabs at the bottom, renamed | the sheet's tabs sit at the bottom of the window, Excel-style, under the sheet; tapping the current tab (or Sheet ▸ Rename tab…) puts its name in an inline field: Enter renames, Escape keeps the old name, an empty name is refused; both tabs' names survive Save → open; GTK and the web agree |
| M3 | A toolbar for the tab you're on | on the sheet: the sheet's tools (Save, Undo, Add row, Formula, Sort, the format tools, Pivot, Chart); on the Report: the Report's (Save, Undo, the value column, Sum/Average/Count/Chart tile, the filter); the Report page no longer carries its own add-tile row; a streamed file shows no edit tools on either |
| M4 | Nothing regressed | goal 20's checks (M1–M4: goal 19's and every earlier goal's inside them) pass, with only the steps that point at moved controls updated (logged); the components matrix is current |

## Done means
`scripts/check` prints PASS for M1–M4; push to `origin` after (owner's standing permission). `docs/report.md` is short, with screenshots.

## Out of bounds
Conditional formats, data bars, borders, font families and sizes, merged cells, more than one sheet or Report (adding tabs), sorting or filtering by colour; Apple and Android builds beyond "still builds"; no deploying, no paid services, no secrets, nothing outside this repo; `../mojo-ui-apple-test` stays untouched.

## Assumptions
- D-199: formats follow docs/plans/formatting.md: one style per column, plus a sparse map of cell overrides (a cell's style wins over its column's). Formatting a whole column sets the column's style and the same parts of every override in it, as Excel does.
- D-200: eight named colours (red, orange, amber, green, teal, blue, purple, grey) for text and fill; a fill is the colour at low strength over the theme's card, so text stays readable on light and dark themes.
- D-201: bottom tabs are buttons (selected one shown on), not the `Tabs` control: tapping the current tab renames it, which a segmented control can't report.
- Budget: about 80 turns.
