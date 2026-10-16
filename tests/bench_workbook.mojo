# The Workbook's own speed on 20M rows: a full page recompute (every pivot, chart and the totals on
# the GPU) and a grid redraw (what a scroll costs), plus the scroll bar and column logic.
#   pixi run mojo build -I examples/workbook -I . tests/bench_workbook.mojo -o build/bench_workbook && pixi run build/bench_workbook
from std.testing import assert_equal, assert_true

from app import Main, GRID_GESTURE, ADD_OBJ, TABLE, PIVOT, CHART, HEADER_H, SORT
from mojoui import Event, TAP, PAN, PRESS, RELEASE
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
    for i in range(20):
        app.update(Event(GRID_GESTURE, "", PAN, 600, 120, 0, -26 * 7))  # scroll 7 rows
        var t0 = now_ns()
        app.draw(0, s)
        worst_draw = max(worst_draw, Float64(now_ns() - t0) / 1e6)
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
    assert_equal(app.top, expect, "a press on the track puts the thumb's centre under the pointer")
    # a press on the header strip above the bar is a header tap, not a jump
    app.update(Event(GRID_GESTURE, "", PRESS, x_bar, 10))
    assert_equal(app.top, expect, "the header above the scroll bar doesn't scroll")
    # dragging the thumb back to the top
    var t = app.thumb(256)
    app.update(Event(GRID_GESTURE, "", PRESS, x_bar, t[0] + 2))
    app.update(Event(GRID_GESTURE, "", PAN, x_bar, HEADER_H + 2, 0, -1000))
    assert_equal(app.top, 0, "the thumb dragged to the top shows row 1")
    app.update(Event(GRID_GESTURE, "", RELEASE, x_bar, HEADER_H + 2))
    assert_true(not app.bar_drag, "letting go ends the thumb drag")
    app.update(Event(GRID_GESTURE, "", PAN, 600, 120, 0, -26 * 3))  # a later plain drag pans rows, not the thumb
    assert_equal(app.top, 3)
    # a header tap selects the column; Sort sorts it
    app.update(Event(GRID_GESTURE, "", PRESS, 830, 12))
    app.update(Event(GRID_GESTURE, "", TAP, 830, 12))
    assert_equal(app.cur_row, -1)
    assert_equal(app.frame.name(app.cur_col), "cents")
    app.update(Event(SORT, "", 0))
    assert_equal(app.frame.name(app.sort_col), "cents")
    assert_true(app.sort_desc, "money sorts largest first")
    assert_true(app.frame.get(app.cur_col, app.order[0]) >= app.frame.get(app.cur_col, app.order[1]), "sorted")
    print("WORKBOOK: recompute " + String(worst_compute) + " ms, grid redraw " + String(worst_draw) + " ms (worst of 10 / 20)")
    print("WORKBOOK TESTS PASSED")
