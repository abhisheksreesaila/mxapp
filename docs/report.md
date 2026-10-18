# Goal 21 report: formatting, tabs at the bottom, a toolbar for the tab you're on

**End goal (owner, 2026-10-18, after trying 1M rows):** "when I say formatting you need to be able to provide the same set of stuff, bold underline all the stuff a cell can be done … rename the tabs … the same format as Excel and can be at the bottom … if it's a report you have to have report controls if it's a transaction or a sheet it has to have sheet controls."

## Result

RESULT_PLACEHOLDER

## What changed

- **Formatting, as Excel's Home tab has it.** The sheet's toolbar has these tools:
  - Bold, Italic, Underline and Strikethrough
  - Text colour and Fill colour (eight colours, picked from swatches)
  - Align left, centre and right
  - Currency, Percent, and fewer or more decimal places
  - Clear formatting

  They apply to the selected cell, or to the whole column when you select a column by its header. The Format menu has the same items, and Ctrl+B, Ctrl+I and Ctrl+U work. Each tool shows whether the selection already has that format. Undo takes format changes back, in order with your edits. Formats are saved in the `.omx` file.
- **Tabs at the bottom, Excel-style.** Tap the current tab, or use View › Rename tab…, to rename it in place. Enter keeps the new name, and Escape keeps the old one. Both names are saved with the document. Renaming the sheet doesn't rename the file.
- **A toolbar per tab.**
  - On the sheet: Save and Undo, the sheet's own tools (Add row, Formula, Sort), the formats, then Pivot and Chart.
  - On the Report: Save and Undo, the column new tiles use, Sum / Average / Count / Chart tile, and the filter. The Report page no longer has its own add-tile row.
- **Fixed on the way:** column headers no longer cut to "amou…", and a single Report chart spans the page on the web.

SCREENSHOTS_PLACEHOLDER

## Three decisions worth a second look

- **D-199: formats belong to columns first, with cell overrides as the exception.** Formatting a selected column also changes the cells in it that have their own format, as Excel does. This keeps 100M rows free: only the cells on screen read a format.
- **D-202: you can format a streamed (read-only) file.** Formats are how the file is shown, not its data, but they can't be saved, because Save is off for streamed files.
- **D-203: bold is Inter Medium drawn twice, 0.6 px apart, and italic is the regular face slanted.** Inter Medium on its own looked almost like regular at 13 px. Real Inter Bold and Italic fonts would cost about 400 KB more.

## Not in this goal (tell me if you want them next)

Font size and font family, borders, merged cells, conditional formats (rules such as "red when below zero"), adding more sheets or Reports, and filtering or sorting by colour.

## Next

Your call. The candidates are the formats above, or what MX frame brings next (the GPU for a streamed file, then editing over a scan).
