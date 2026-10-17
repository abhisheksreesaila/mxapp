# Goal 13 report: keys, so the grid feels like a spreadsheet (2026-10-16 night)

Arrows, Tab, Enter, PageUp/PageDown, Home/End, F2, Escape, typing and Delete in the grid, on Linux and the web, from the framework up: a `KEY` gesture on any `Canvas(keys=True)`, `TextField(on_cancel=)` for Escape, and `DataGrid`'s own keyboard. MX Studio's Sheet and the Workbook use it with no keyboard code of their own beyond writing the cell.

## Checks
```
PASS  M1  KEY events, canvas focus and on_cancel in mojoui; arrows then F2 edit the same cell on GTK and web (real key presses); the matrix shows them ✅ on Linux and web
PASS  M2  DataGrid's keyboard: arrows, Tab, Enter, PageUp/Down, Home/End, F2, Escape, typing, Delete (deleted rows skipped, the cell kept on screen, formulas read-only); the grid's own tests pass
PASS  M3  MX Studio and the Workbook on both hosts: typing replaces and Enter writes (selection moves down), Escape cancels, Delete clears, the keyboard returns to the grid; identical on GTK and web
PASS  M4  goal 12's checks (and goals 3–11's inside them) pass
```

M1–M3 come from the run after the last code change. M4 runs every earlier goal's checks inside it; it passed once the machine was quiet. Two things about M4, neither a code change:
- Under the owner's other agents (load average 14), goal 6's lens dropped below its 55 fps bar. It reached 58–60 fps when quiet. The bar stays at 55.
- The emulator held the Android apps signed with the main checkout's debug key, so the worktree now uses the same key.

## What it does, as in Excel
| Key | Effect |
|---|---|
| Arrows, PageUp/Down, Home/End, Ctrl+Home/End | move the selection; the cell stays on screen; deleted rows are skipped; sorted tables move in the order shown |
| A character | opens the editor with it (it replaces the value); the grid keeps the keyboard while you type, so nothing is lost however fast you type or however slow the network |
| Enter / Tab / an arrow, while typing | writes the value and moves down / right / that way (Shift: up / left) |
| F2 or a double click | edits the value, selected |
| Escape | closes the editor without writing |
| Delete / Backspace | clears a text cell (numbers and dates wait for MX frame's blanks) |

## Components added
| Component | Linux | Web |
|---|---|---|
| Canvas keys (`Canvas(keys=True)`, `KEY`, focus on press, back after an editor closes) | ✅ | ✅ |
| TextField Escape (`on_cancel`) | ✅ | ✅ |
| Editor that echoes the grid's typing (`.echo()`) | ✅ | ✅ |
| DataGrid keyboard (`DataGrid.key`, `editor()`, `cancel_edit()`, `GRID_TYPED / COMMIT / CANCEL / CLEAR`) | ✅ | ✅ |

Android, Mac and iPhone don't have keys yet (❌ in the matrix).

## Review
Five rounds. What they changed, in short:
- **Fast typing on the web lost keys.** The root fix made the grid the one owner of a value being typed (D-132).
- **Some checks couldn't fail.** A slow test server and real focus on GTK made them able to fail, and those runs found three more lost-key bugs, now fixed.
- **Tab was trapped in every canvas.** Keys became opt-in per canvas.
- **The editor flow was copied in both apps.** It moved into DataGrid.
- **Tab and the arrows didn't match Excel while typing.** They do now.
- **A matrix ✅ that nothing ran** was removed (D-134). This changed GOAL.md's wording, so the owner should check it.

## Next
MX Studio's next rung (Explore needs MX frame's Mojo API; see docs/plans/needs-mxframe.md), or cell formatting (docs/plans/formatting.md), or keys on Android.
