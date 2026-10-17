# GOAL 13: keys, so the grid feels like a spreadsheet (Linux + web)

**End goal (owner's words, 2026-10-16):** "double click on a cell and edit… like Excel"; "ask yourself what component do I need, then build the component… then go back and build the app"; "go for it and make me proud". Two review rounds ended at the same gap: the framework had no keyboard events, so Escape couldn't cancel an edit, arrows couldn't move the selection and typing couldn't start an edit.

## Components this needs (from `docs/components.md`, before the build)
| Component | Before | Plan |
|---|---|---|
| Key events on a Canvas (`KEY`: the key's name or the character typed, plus modifiers) | ❌ every host | GTK: a key controller on the canvas; web: keydown on a focusable canvas |
| Canvas focus (it receives keys after a press) | ❌ | GTK: focusable, grabbed on press; web: tabindex + focus on pointerdown; focus comes back when an in-place editor closes |
| DataGrid keyboard: arrows, Tab, Enter, PageUp/Down, Home/End (Ctrl: first/last row), F2, Escape, typing, Delete | ❌ | `mojoui/datagrid.mojo`, tested without a host |
| TextField Escape (`on_cancel`) and an editor that echoes the grid's typing (`.echo()`; was "caret after the text", D-134) | ❌ | GTK key controller on the entry; web keydown on the input |

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | Keys reach the app | `KEY`, `Runtime.key`, `TextField(on_cancel=)` in mojoui; on both hosts a tap then arrow keys move the grid's selection and F2 opens the editor on the cell they reached (identical on GTK and web; the web run uses real key presses); the matrix lists keys, Escape and the echo editor ✅ on Linux and web (D-134) |
| M2 | DataGrid's keyboard | `tests/test_grid_keys.mojo` (every key above, deleted rows skipped, scrolling keeps the cell on screen, computed columns read-only) and `tests/test_datagrid.mojo` pass |
| M3 | Spreadsheet editing in both apps | MX Studio's Sheet and the Workbook, on GTK and web: typing on a cell opens the editor with that text and Enter writes it (then the selection is on the cell below), Escape cancels without writing, Delete clears a text cell; after Enter or Escape the keyboard is back on the grid (the next arrow and F2 edit the right cell); identical on both hosts |
| M4 | Nothing regressed | goal 12's checks (and goals 3–11's inside them) still pass; the matrix is current |

## Done means
`scripts/check` prints PASS for M1–M4; push to `origin` after.

## Out of bounds
As goal 12. Android, Mac and iPhone keys are later (the matrix shows them ❌). Blank numbers and dates (Delete on a number) wait for MX frame's nulls (`docs/plans/needs-mxframe.md`).

## Assumptions
- Key names are the web's (`ArrowDown`, `Enter`, …); GTK maps its own names to them.
- Enter moves down and F2 edits, as in Excel; double click still edits.
- Ctrl/Alt shortcuts stay the window's or the browser's (the canvas doesn't take them, except Ctrl+Home/End).
- Budget: 2 hours wall clock.
