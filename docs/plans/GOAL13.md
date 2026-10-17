# GOAL 13 (draft): keys, so the grid feels like a spreadsheet (Linux + web)

**Why:** the owner's grid notes ("double click on a cell and edit", Excel muscle memory) and two review rounds ended at the
same gap: the framework has no keyboard events, so Escape can't cancel an edit, arrows can't move the selection, and
typing can't start an edit. It's a framework feature (every app with a grid needs it), so it's built components-first.

## Components this needs
| Component | Today | Plan |
|---|---|---|
| Key events on a Canvas (`on_key`: key name + text typed + modifiers) | ❌ every host | a `KEY` gesture: GTK EventControllerKey on the canvas, web keydown on a focusable canvas |
| Focus on a Canvas (so it receives keys after a click) | ❌ | GTK `set_focusable` + grab on press; web `tabindex=0` + focus on pointerdown |
| DataGrid keyboard: arrows/Tab/Enter move the selection (scrolling to keep it on screen), Escape cancels the editor, typing a character opens the editor with that character, Delete clears | ❌ | in `mojoui/datagrid.mojo`, tested without a host |
| Editor field: Escape cancels (the field itself) | ❌ | `TextField(on_cancel=)`: GTK key controller on the entry, web keydown Escape |

## Milestones
1. KEY events and canvas focus on GTK and web, with test steps (`key:0=ArrowDown`, `type:0=7`) on both hosts; the matrix lists them.
2. DataGrid's keyboard behaviour in the component, with its own test.
3. In MX Studio's Sheet and the Workbook: click a cell, arrows move, typing replaces, Enter writes and moves down, Escape cancels; identical on GTK and web.
4. Nothing regressed.
