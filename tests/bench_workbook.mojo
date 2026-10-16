# The Workbook's own speed on 20M rows: a full page recompute (every pivot, chart and the totals on
# the GPU) and a grid redraw (what a scroll costs), plus the scroll bar and column logic.
#   pixi run mojo build -I examples/workbook -I . tests/bench_workbook.mojo -o build/bench_workbook && pixi run build/bench_workbook
from std.testing import assert_equal, assert_true

from app import Main, GRID_GESTURE, ADD_OBJ, TABLE, PIVOT, CHART, HEADER_H, SORT, CELL_COMMIT, CENTS
from mojoui import Event, TAP, PAN, PRESS, RELEASE, DOUBLE
from mojoui.canvas import Surface
from mojoui.clock import now_ns


def main() raises:
    var app = Main()
    # a grid redraw at the size the page gives it (1328×256 pt at 2× = what a laptop screen draws)
    var w = 1328 * 2
    var h = 256 * 2
    var px = List[UInt32](length=w * h, fill=0)
    var s = Surface(Int(px.unsafe_ptr()), w, h, 2.0)
    app.draw(0, s)  # (first draw: sizes known)
    var worst_draw = 0.0
    var draws = List[Float64]()
    for i in range(20):
        app.update(Event(GRID_GESTURE, "", PAN, 600, 120, 0, -26 * 7))  # scroll 7 rows
        var t0 = now_ns()
        app.draw(0, s)
        draws.append(Float64(now_ns() - t0) / 1e6)
        worst_draw = max(worst_draw, draws[len(draws) - 1])
    sort(draws)
    print("GRID: redraw median " + String(draws[10]) + " ms, best " + String(draws[0]) + " ms")
    _ = len(px)
    var worst_compute = 0.0
    for _ in range(10):
        var t0 = now_ns()
        app.compute()
        worst_compute = max(worst_compute, Float64(now_ns() - t0) / 1e6)
    # the scroll bar: a press on the track centres the thumb on the pointer
    var x_bar = 1328.0 - 7
    var rows = 20_000_000
    var visible = 8  # (256 - 30) // 26
    var thumb_h = 28.0  # the minimum: 8 of 20M rows
    var room = 256.0 - HEADER_H - thumb_h
    app.update(Event(GRID_GESTURE, "", PRESS, x_bar, 130))
    app.update(Event(GRID_GESTURE, "", TAP, x_bar, 130))
    var expect = Int((130.0 - thumb_h / 2 - HEADER_H) / room * Float64(rows - visible) + 0.5)
    assert_equal(app.grid.top, expect, "a press on the track puts the thumb's centre under the pointer")
    # a press on the header strip above the bar is a header tap, not a jump
    app.update(Event(GRID_GESTURE, "", PRESS, x_bar, 10))
    assert_equal(app.grid.top, expect, "the header above the scroll bar doesn't scroll")
    # dragging the thumb back to the top
    var t = app.grid.thumb(256, app.frame)
    app.update(Event(GRID_GESTURE, "", PRESS, x_bar, t[0] + 2))
    app.update(Event(GRID_GESTURE, "", PAN, x_bar, HEADER_H + 2, 0, -1000))
    assert_equal(app.grid.top, 0, "the thumb dragged to the top shows row 1")
    app.update(Event(GRID_GESTURE, "", RELEASE, x_bar, HEADER_H + 2))
    assert_true(not app.grid.bar_drag, "letting go ends the thumb drag")
    app.update(Event(GRID_GESTURE, "", PAN, 600, 120, 0, -26 * 3))  # a later plain drag pans rows, not the thumb
    assert_equal(app.grid.top, 3)
    # a header tap selects the column; Sort sorts it
    app.update(Event(GRID_GESTURE, "", PRESS, 830, 12))
    app.update(Event(GRID_GESTURE, "", TAP, 830, 12))
    assert_equal(app.grid.cur_row, -1)
    assert_equal(app.frame.name(app.grid.cur_col), "cents")
    app.update(Event(SORT, "", 0))
    assert_equal(app.frame.name(app.grid.sort_col), "cents")
    assert_true(app.grid.sort_desc, "money sorts largest first")
    assert_true(app.frame.get(app.grid.cur_col, app.grid.order[0]) >= app.frame.get(app.grid.cur_col, app.grid.order[1]), "sorted")
    # a column's header edge dragged 40 pt right widens it by 40; a double click on the header fits it again
    var c = CENTS
    var edge = app.grid.col_left(c, app.frame) + app.grid.col_width(c, app.frame)
    var before = app.grid.col_width(c, app.frame)
    app.update(Event(GRID_GESTURE, "", PRESS, edge - 1, 12))
    app.update(Event(GRID_GESTURE, "", PAN, edge + 39, 12, 40, 0))
    app.update(Event(GRID_GESTURE, "", RELEASE, edge + 39, 12))
    assert_true(abs(app.grid.col_width(c, app.frame) - (before + 40)) < 0.01, "dragging the header edge resizes the column by the drag")
    app.update(Event(GRID_GESTURE, "", DOUBLE, app.grid.col_left(c, app.frame) + 10, 12))
    assert_true(app.grid.col_width(c, app.frame) < before + 40, "a double click on the header fits the column to its values")
    # a double click on a cell opens the editor over it; Enter writes the value and moves down a row
    app.update(Event(GRID_GESTURE, "", DOUBLE, app.grid.col_left(c, app.frame) + 10, HEADER_H + 26 + 5))  # (row 2 on screen)
    assert_true(app.grid.editing, "a double click on a cell opens the in-place editor")
    var row = app.grid.cur_row
    assert_true(app.editor_place()[2] > 0, "the editor is placed over the cell")
    app.update(Event(CELL_COMMIT, "7", 0))
    assert_equal(app.frame.display(c, row), "7.00")
    assert_true(not app.grid.editing)
    assert_equal(app.grid.cur_row, app.grid.next_row(row, app.frame), "the selection moved to the next row")
    app.update(Event(CELL_COMMIT, "8", 0))  # a second Enter after the editor closed writes nothing
    assert_equal(app.frame.display(c, app.grid.cur_row) != "8.00", True)
    # a click anywhere else closes the editor without writing
    app.update(Event(GRID_GESTURE, "", DOUBLE, app.grid.col_left(c, app.frame) + 10, HEADER_H + 26 * 3 + 5))
    assert_true(app.grid.editing)
    var open_row = app.grid.cur_row
    var was = app.frame.display(c, open_row)
    app.update(Event(GRID_GESTURE, "", PRESS, app.grid.col_left(c, app.frame) + 10, HEADER_H + 26 * 5 + 5))
    assert_true(not app.grid.editing, "a click elsewhere closes the editor")
    assert_equal(app.frame.display(c, open_row), was)
    # the row-number gutter never selects a column (even scrolled sideways)
    app.update(Event(GRID_GESTURE, "", TAP, 20, HEADER_H + 5))
    assert_true(app.grid.cur_col == c, "a tap on a row number doesn't pick a hidden column")
    print("WORKBOOK: recompute " + String(worst_compute) + " ms, grid redraw " + String(worst_draw) + " ms (worst of 10 / 20)")
    print("WORKBOOK TESTS PASSED")
