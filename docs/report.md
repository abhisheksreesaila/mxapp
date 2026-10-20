# Goal 28 report: editing a chart, the title is the query

**End goal (owner, 2026-10-19):** "charts can be on the inspector and a sub-inspector can have settings… be creative with UI… can't ship an Excel clone"; on the prototypes: "The title is the query: ask, then tap any word is the genius!!" And the standing bar: one language, every platform; the showcase dashboard with macOS polish, Linux speed and Windows usability.

## Result
RESULT_LINES

## What you can do with a chart now
A chart's title **is** its settings, as a sentence:

> **Sum** of **amount** by **region**, **in data order**, **every region**, **every row**, as **bars**

| Tap a word | Ask | Open a part |
|---|---|---|
| ![](goals/28/picked-gtk.jpg) | ![](goals/28/asked-gtk.jpg) | ![](goals/28/pages-gtk.jpg) |

- **Tap any coloured word** and its choices open on it: Sum, Average or Count; any number column; group by any text column; in data order, largest first, smallest first, A to Z; every group or the top 3, 5 or 10; every row, only paid, not paid, only West…; bars or a line. The arrow keys and Return work in the list, as in a native menu.
- **Ask** in the field under the chart: "top 3, unpaid, as a line", "average qty by product", "only West, smallest first". It changes several words at once, says what it took (and what it skipped), and the words that changed glow for a moment. It reads the table's own names too: columns, Yes/No columns, text values. It's a keyword reader (instant, offline), not a model: an agent can write the same sentence later.
- **The inspector** shows the sentence and what's set (Data, Order, Rows, Style); each row opens a page that slides in, with Back.
- **The bars move** to their new length and place (about 330 ms, the calm curve) instead of cutting.
- **Undo** takes back each chart change as one step, in order with your table edits (Ctrl+Z).
- Report chart tiles work the same way; Insert Chart opens the chart's inspector; the toolbars only insert.
- Saved in the document; older documents open as they were.

The same on the web: ![](goals/28/asked-web.jpg)

## Fixed on the way (all in today's build)
- **Undo right after Add row crashed the app** (the selection stayed on the removed row: the engine's bounds check aborted).
- **Picking a choice scrolled the sheet** by 90 pt (the keyboard going back to the grid scrolled to it): the host's own focus moves no longer scroll a board.
- **A line chart of a plain column read its values as cents** ($15K for 1.5M); its last label was cut off; its axis cut wide labels.
- A popover's choices had no keyboard (GTK gives popovers no arrow keys): focus goes in, Up/Down move.

## Your test
```
cd ~/Projects/mxapp/mojo-ui
scripts/omxplorer.sh build/data/orders_1m.csv
```
Insert → Chart (or the Chart tool), then tap "Sum" in its title, or type in "Ask": *top 5, largest first, as a line*. Ctrl+Z to step back. On the Report: Chart tile, same.

## Not done
- **Median per group, by month or week, ranges and several conditions** wait for MX frame 321870f (stable now): goal 29 vendors it and moves the charts' queries onto it, so the sentence gains "median", "by month", "over $1,000".
- The ask reads English keywords only; a value equal to a vocabulary word (a tier called "Top") wins over the word (D-266).
- Mac, iPhone and Android draw the sentence's words as plain buttons (no token style there yet); a dark Mac still draws charts light.
- The bars move on GTK, measured; on the web they move too but no check measures them.
