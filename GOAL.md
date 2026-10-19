# GOAL 25: omxplorer feels native: only what changed moves, it fits the window, nothing twitches

**End goal (owner, 2026-10-19, after using goal 24's build):** "liquid feel more natural… multi select does not work well… the icons on the toolbar are not in a straight line… the bottom bar is outside the screen for sheet, but good for report… still not an app I would use. Is it implementation? Is the UI in a different thread running and sort of decoupled (as it should be)? …there isn't a smooth feel to it." The vision stays (one language, one set of components, every platform); this goal fixes how the framework updates the screen, so every app built on it (AG-UI screens, a video editor, simulations) feels native by default.

## What the code showed (2026-10-19, MOJOUI_TRACE and real input on the headless display)
- Every change of the screen's shape tore down and rebuilt **every widget in the window** (10–40 ms on GTK): moving the selection from a number column to a text column (the inspector changes), opening a menu or dialog, adding a tile. The rebuild replayed every Liquid arrival animation, reset hover and scroll, and **killed a drag in progress**: a real drag across columns stopped at the first column whose inspector differs (the "multi select doesn't work" the owner saw).
- The layout was fixed for a 1440×900 window (the sheet's width and height were constants): on the owner's 1742×876 window the bottom bar fell off the screen and the grid left a gap on the right.
- One thread runs everything (events, the app's update, layout, drawing the grid on the CPU). That is how GTK and AppKit work (the UI belongs to the main thread); what matters is that the main thread is never busy for long. view() and diff take ~0.1 ms; a grid frame 4–7 ms. Heavy data work (opening a file: 215 ms for 5,000 rows) still runs on it: moving that onto a worker is goal 26's question, not this goal's.

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | Only what changed is rebuilt (GTK) | moving the selection across every column, opening a menu, opening Settings and adding a report tile each update part of the window (`TRACE: partial`), building at most a tenth of its widgets; the diff's own tests (tests/test_diff_keep.mojo) pass; with **real input** (XTest, `scripts/live.py`) a drag from amount row 2 to day row 8 selects the whole 3×7 block (the status bar says 21 cells) |
| M2 | It fits the window | at 1742×876, 1280×720 and 2560×1400, on GTK and the web, on the sheet and the report: the status bar is inside the window and the grid (or the report) fills the width beside the inspector (a gap of at most 24 pt) |
| M3 | The toolbar is one straight line | every tool's icon sits on one line (icon centres within 1 pt) and every tool is the same height, on GTK and the web |
| M4 | The inspector shows the selected column | for each column of small.parquet the inspector names it and its stat cards are that column's (pyarrow); Yes/No, Date and Text columns don't offer decimals or a thousands separator |
| M5 | Motion that feels natural | a widget that stays never replays its arrival (M1); the Liquid motion is short and calm: hover and press ≤ 160 ms, menus and popovers ≤ 240 ms, dialogs and tiles ≤ 340 ms, overshoot at most 2 %, on GTK and the web; reduced motion turns arrivals off |
| M6 | The import screen | with real input the preview scrolls, Back and Create table respond, and nothing is drawn outside the preview (the area under it is the card's own colour apart from the column table), in Liquid and Ledger |
| M7 | Nothing regressed | goal 24's checks (M1–M7; every earlier goal's inside them) pass |

## Done means
`scripts/check` prints PASS for M1–M7; the reviewer passes it; `docs/report.md` is short, with before/after numbers and screenshots. Push to `origin` after (owner's standing permission).

## Out of bounds
New features (the chart inspector waits for the owner's jam after they look at Apple Numbers); moving data work to a worker thread (goal 26 question); changing MX frame; partial rebuilds on the web, Mac, iPhone and Android hosts (they keep full rebuilds this goal: the Diff says what it kept, they ignore it); `../mojo-ui-apple-test` stays untouched.

## Assumptions
- D-242: this goal is 25; the MX frame dc1a722 vendoring the mxapp-e6 session had claimed as 25 moves to 26 (that session exited before goal 24 was pushed).
- D-243: partial rebuilds pair children in order by kind, style and tag (a longest common run); a stack (VStack/HStack without justify spacers) can add, drop and reorder children in place; any other container whose children change is built again whole. Widgets keep ids, not node numbers, so the ones that stay need no new data.
- Budget: about 80 turns.
