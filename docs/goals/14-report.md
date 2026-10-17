# Goal 14 report: omxplorer from scratch (2026-10-17 night)

omxplorer is the owner's killer app, on Linux and the web, following the Stitch classic design. It goes from Start to choosing a CSV, reviewing its columns, and getting a Numbers-style sheet. The sheet has a toolbar, sheet tabs, a formula bar, the table, a format inspector and a status bar. It saves a one-file `.omx` document and opens it again. Everything is built from omxapp components; the app adds only the wiring.

![omxplorer on Linux: 1M orders, Currency with 1 decimal and parentheses on revenue](img/omxplorer-sheet.png)

## Checks
```
PASS  M1  TOOL buttons, FilePicker, Inspector/Section/Row/Stepper, Toolbar/FormulaBar/StatusBar, column formats and the CSV reader in mojoui, with tests (formats, parser, CSV against Python's csv); the matrix: ✅ on Linux and web, GTK's file dialog 🔨
PASS  M2  Start → choose orders_1m.csv → the Import step (1,000,000 rows, 12 columns, types inferred) → a table whose revenue (114,007,922.00) and qty (1,390,039) sums and averages equal an independent pass over the file; identical on GTK and web
PASS  M3  the sheet on both hosts: Currency, decimals, Thousands off, Percent, parentheses (a negative total), Compact reach the cells and the totals; a formula column sums to the file's 43,687,646.44; Sort; Add row; identical on GTK and web
PASS  M4  GTK and the web each edit (a number, a new name), add a row and a formula column, and Save one .omx file (12 MB); both files reopen on both hosts with the edits, the row, the formula and the format; a bad file leaves the open sheet intact
PASS  M5  1M measured now: import 0.52 s, sort 0.02 s, format 7.9 ms (budgets 5 s, 1 s, 50 ms); 10M, 50M and 100M recorded in docs/scale.md
PASS  M6  goal 13's checks (and goals 3–12's inside them) pass
```

M1–M5 come from the run after the last change. M6 reruns every earlier goal's checks (about 23 minutes) and passed after two fixes. Goal 5 wants a current `docs/report.md`, and this report is it. A "System UI isn't responding" dialog on the Android emulator, left over from heavy load, blocked the next run; the Android driver now closes system dialogs before each launch.

![The Start screen](img/omxplorer-start.png)

![Import: the columns before the table exists](img/omxplorer-import.png)

## Components added (omxapp)
| Component | Linux | Web |
|---|---|---|
| Toolbar button, icon over label (`Button(style=TOOL/TOOL_ON)`) | ✅ | ✅ |
| File picker (`FilePicker`: GTK's dialog / an upload) | 🔨 (the dialog isn't driven by a check) | ✅ |
| Inspector (`Inspector`, `Section`, `Row`, `Stepper`) | ✅ | ✅ |
| Toolbar · FormulaBar · SheetTabs · StatusBar | ✅ | ✅ |
| Column number formats (number, currency, percent, compact, dates; decimals, separators, negatives) | ✅ | ✅ |
| CSV reader (`mojoui.csvio`, pyarrow until MX frame's readers) and `.omx` documents (`mojoui.omxfile`) | ✅ | ✅ |
| `mojoui.files` (file names, the recent list) | ✅ | ✅ |

## Scale
Measured from 1M to 100M rows: [docs/scale.md](scale.md). At 100M rows a sort takes 3.7 s, a format change 54 ms, and a GPU sum over every row 19 ms. The CSV import (106 s on a machine with 32 GB of other work in swap) is the part MX frame's readers will replace.

## Review
Two rounds, which:
- **made checks that could pass while broken unable to:** exact labels, rounded money, qty, Save with real edits on both hosts, scale measured during the check.
- **validated `.omx` files before they reach memory**, with nine kinds of bad file refused by a test.
- **fixed averages, formatting edges and the parser.**
- **released tables when another file opens.**
- **gave the grid the keyboard.**

## Next (goal 15)
Insert a chart and a pivot onto the sheet (Stitch 05), and build a Report page from scratch (Stitch 06). Also: the menu row, the toolbar's group dividers, ✓/✕ on the formula bar, and a Σ total row.
