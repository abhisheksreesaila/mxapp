# Goal 27 M5: the polish pass (omxplorer in Liquid, GTK and the web)

Found by looking at every screen at 1440×900 (build/g27/before) and against the Liquid spec (docs/design/liquid.md).
Each item: what's wrong, why it matters, the fix. Status: open → fixed (with the shot that shows it).

| # | Screen | What's wrong | Fix | Status |
|---|---|---|---|---|
| P1 | Settings (web) | the dialog sits against the left edge and only a 560 px strip is dimmed; it should float centred over a dimmed page | dialogs centre in the viewport, the scrim covers it all | open |
| P2 | Start | the sidebar's rows are centred, with a filled gear among outline icons, a stray caption ("Connect a database…") between rows, and the app's name repeated under the menu bar's | left-aligned nav rows, one icon set, the database line as a quiet row of its own, no repeated name | open |
| P3 | Start | an empty grey chip sits before "CPU" in the menu bar (the document chip with no document) | no chip without a document | open |
| P4 | Start (web) | "Choose a file" is a plain button on the web but the indigo primary on GTK | the same primary on both | open |
| P5 | Sheet, Report | the GPU's status shows three times (menu bar chip, the tab bar's right end, the status bar) | once: the menu bar chip | open |
| P6 | Report | every chart's bars are the report's red: red reads as a loss (D-254 kept red for the chrome) | charts draw in the skin's first series colour, not the mode's tint | open |
| P7 | Report | the toolbar is taller than the sheet's (labels above "Tiles of" and "Filter"), so switching tabs moves everything below it | labels beside their dropdowns: one line, the sheet's height | open |
| P8 | Report | the inspector's header is a one-item segmented control ("Report"): it reads as a button (in Graphite, an orange slab with grey text) | a plain title | open |
| P9 | Report | each bar has a pale full-width track and its value sits on the track | no track; the value just after the bar | open |
| P10 | Native (no theme) | GTK follows the system's dark mode but drawn views (charts, grids) keep the plain light palette: a white canvas in a dark window | hosts tell the app the system's appearance; no theme draws in a plain dark palette when it's dark | open |
| P11 | Paper | its charts use the plain palette's bright series | Paper's own muted series | open |
