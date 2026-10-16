# DataGrid: from app code to a component (next, before new features)

Status: planned, 2026-10-16. The Workbook's grid is the biggest piece of app-local code (docs/components.md, "the debt"). The owner: "ask yourself what component do I need, build the component… then build the app with it; if you overfit the app you'll have to undo it."

## What moves into `mojoui/datagrid.mojo`
- State: first row, sideways offset, column widths, selection (cell or column), sort marker, scroll-bar drags, header-edge resize, in-place editing.
- A `GridSource` trait the data implements (rows shown, columns, name, kind, display text, row at display index); `mojoui.frame.Frame` implements it, so any app with a Frame gets the grid.
- `grid.view(...)` → the Canvas plus the in-place editor; `grid.draw(surface, font, palette)`; `grid.update(event) -> GridAction` (selected, commit text, sort asked, width changed) that the app turns into engine calls.
- Tests of its own (today's bench_workbook grid assertions move there).

## The reviewer's remaining grid items, fixed in the component, not the app
- Scroll a double-clicked cell fully into view before placing the editor; no 60-pt minimum that spills over the scroll bar.
- Opening and closing the editor without rebuilding the page (Board children resized by patch, not rebuild; also removes the rebuild on card resize).
- A horizontal scroll bar when columns overflow; horizontal wheel and touchpad scrolling on both hosts.
- Escape and arrow keys once the framework has key events (a `Key` event on both hosts first).

## Then
`PivotTable` and `Chart` (a Flint spec as a view, tap-to-filter built in) follow the same path, so the analytics showcase and the Workbook share them.
