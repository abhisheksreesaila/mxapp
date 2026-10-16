# mojoui.datagrid on its own: a small GridSource (no engine), driven by the same events the hosts send.
#   pixi run mojo build -I . tests/test_datagrid.mojo -o build/test_datagrid && build/test_datagrid
from std.testing import assert_equal, assert_true, assert_false

from mojoui import Event, TAP, PAN, PRESS, RELEASE, DOUBLE, ZOOM
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.datagrid import (DataGrid, GridSource, GRID_NONE, GRID_REDRAW, GRID_SELECTED, GRID_COLUMN, GRID_EDIT, GRID_READ_ONLY,
                             GRID_FITTED, GRID_RESIZED, GRID_HEADER_H, GRID_HISTOGRAM_H, GRID_ROW_H, GRID_GUTTER, GRID_BAR_W)

comptime MSG = 1


@fieldwise_init
struct People(GridSource, Movable):
    """1,000 rows × 3 columns: name, age, a computed column; row 5 is deleted."""

    var unused: Int

    def grid_rows(self) -> Int:
        return 1000

    def grid_alive(self, row: Int) -> Bool:
        return row != 5

    def grid_columns(self) -> Int:
        return 3

    def grid_name(self, c: Int) -> String:
        var names: List[String] = ["name", "age", "decade"]
        return names[c]

    def grid_numeric(self, c: Int) -> Bool:
        return c > 0

    def grid_editable(self, c: Int) -> Bool:
        return c < 2

    def grid_text(self, c: Int, row: Int) -> String:
        if c == 0:
            return "Person " + String(row) + (" with a very long family name indeed" if row == 3 else "")
        if c == 1:
            return String(20 + row % 50)
        return String((20 + row % 50) // 10 * 10)

    def grid_type_width(self, c: Int) -> Float64:
        return 120 if c == 0 else 72


def ev(kind: Int, x: Float64, y: Float64, dx: Float64 = 0, dy: Float64 = 0) -> Event:
    return Event(MSG, "", kind, x, y, dx, dy)


def main() raises:
    var src = People(0)
    var font = Font()
    var pal = Palette.omarchy()
    var g = DataGrid()
    var w = 600
    var h = 290  # 30 header + 10 rows of 26
    var px = List[UInt32](length=w * h, fill=0)
    var s = Surface(Int(px.unsafe_ptr()), w, h, 1.0)
    g.draw(s, src, font, pal)
    assert_equal(g.rows_in(Float64(h)), 10)
    assert_equal(g.position_text(src), "Rows 1–10 of 1,000")

    # a tap on a cell selects it; row 5 is gone, so the 6th line shows row 6
    var x_age = g.col_left(1, src) + 5
    assert_equal(g.handle(ev(TAP, x_age, GRID_HEADER_H + 5 * GRID_ROW_H + 3), src, font, pal), GRID_SELECTED)
    assert_equal(g.cur_row, 6)
    assert_equal(g.cur_col, 1)
    # the row-number gutter and the scroll bar never pick a cell
    assert_equal(g.handle(ev(TAP, 20, GRID_HEADER_H + 3), src, font, pal), GRID_NONE)
    # a header tap selects the column
    assert_equal(g.handle(ev(TAP, x_age, 10), src, font, pal), GRID_COLUMN)
    assert_equal(g.cur_row, -1)
    assert_equal(g.cur_col, 1)

    # the scroll bar: a press low on the track centres the thumb there; dragging it back reaches the top
    var bar_x = Float64(w) - GRID_BAR_W / 2
    _ = g.handle(ev(PRESS, bar_x, 250), src, font, pal)
    assert_true(g.top > 800, "the track jumps near the end: " + String(g.top))
    _ = g.handle(ev(RELEASE, bar_x, 250), src, font, pal)
    var t = g.thumb(Float64(h), src)
    _ = g.handle(ev(PRESS, bar_x, t[0] + 2), src, font, pal)
    _ = g.handle(ev(PAN, bar_x, GRID_HEADER_H, 0, -500), src, font, pal)
    assert_equal(g.top, 0)
    _ = g.handle(ev(RELEASE, bar_x, GRID_HEADER_H), src, font, pal)
    assert_false(g.bar_drag)
    # a plain drag scrolls rows (3 rows up = 3 down the table); the wheel too
    _ = g.handle(ev(PAN, 300, 150, 0, -3 * GRID_ROW_H), src, font, pal)
    assert_equal(g.top, 3)
    _ = g.handle(Event(MSG, "", ZOOM, 300, 150, 0, 0, 0.5), src, font, pal)  # one notch down
    assert_equal(g.top, 15)

    # sort: the app hands the order; the header shows the marker
    var order = List[Int]()
    for r in range(999, -1, -1):
        order.append(r)
    g.set_order(order^, 1, True)
    assert_equal(g.top, 0)
    assert_equal(g.shown_row(0, src), 999)
    assert_equal(g.sort_col, 1)

    # resize: a header edge dragged 40 pt right widens the column by 40
    var edge = g.col_left(0, src) + g.col_width(0, src)
    var before = g.col_width(0, src)
    _ = g.handle(ev(PRESS, edge - 1, 10), src, font, pal)
    _ = g.handle(ev(PAN, edge + 39, 10, 40, 0), src, font, pal)
    assert_equal(g.handle(ev(RELEASE, edge + 39, 10), src, font, pal), GRID_RESIZED)
    assert_true(abs(g.col_width(0, src) - (before + 40)) < 0.01)
    # a double click on the header fits it to the values on and around the screen (row 3's long name included)
    g.set_order(List[Int](), -1, False)
    assert_equal(g.handle(ev(DOUBLE, g.col_left(0, src) + 10, 10), src, font, pal), GRID_FITTED)
    assert_true(g.col_width(0, src) > 300, "fitted to the long name: " + String(g.col_width(0, src)))
    # sideways: once the columns are wider than the canvas, a sideways drag scrolls them, never past the end
    g.set_width(1, 300)
    _ = g.handle(ev(PAN, 300, 150, -2000, 0), src, font, pal)
    assert_true(g.left > 0)
    assert_true(g.left <= g.columns_width(src) - (Float64(w) - GRID_BAR_W) + 0.01)
    _ = g.handle(ev(PAN, 300, 150, 5000, 0), src, font, pal)
    assert_equal(g.left, 0)

    # edit in place: a double click opens the editor over the cell (only for editable columns)
    g.widths = List[Float64]()
    var y1 = GRID_HEADER_H + 1 * GRID_ROW_H + 3
    assert_equal(g.handle(ev(DOUBLE, g.col_left(1, src) + 5, y1), src, font, pal), GRID_EDIT)
    assert_true(g.editing)
    var at = g.editor_place(src)
    assert_equal(at[0], Int(g.col_left(1, src)))
    assert_equal(at[1], 30 + 26 - 2)  # (header 30, one row 26, a 2-pt ring)
    assert_equal(at[2], Int(g.col_width(1, src)))
    # the app writes the value, then the grid moves down (skipping the deleted row 5)
    g.select(4, 1)
    g.editing = True
    g.committed(src)
    assert_equal(g.cur_row, 6)
    assert_false(g.editing)
    assert_equal(g.handle(ev(DOUBLE, g.col_left(2, src) + 5, y1), src, font, pal), GRID_READ_ONLY)
    assert_false(g.editing)
    # a press anywhere closes an open editor
    _ = g.handle(ev(DOUBLE, g.col_left(1, src) + 5, y1), src, font, pal)
    _ = g.handle(ev(PRESS, 300, 200), src, font, pal)
    assert_false(g.editing)

    # header histograms: a taller header, and the rows start below it
    g.histograms = [[0.2, 1.0, 0.5], [1.0, 0.3], []]
    assert_equal(g.header_h(), GRID_HEADER_H + GRID_HISTOGRAM_H)
    g.draw(s, src, font, pal)
    assert_equal(g.rows_in(Float64(h)), Int((Float64(h) - GRID_HEADER_H - GRID_HISTOGRAM_H) / GRID_ROW_H))
    assert_equal(g.handle(ev(TAP, g.col_left(1, src) + 5, GRID_HEADER_H + 5), src, font, pal), GRID_COLUMN)  # (still header)
    _ = len(px)
    print("DATAGRID TESTS PASSED")
