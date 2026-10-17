# mojoui.datagrid's keyboard, on its own: the KEY events the hosts send (event.text = the key's name, or the
# character typed; event.dx = modifiers: 1 Shift, 2 Ctrl, 4 Alt), as a spreadsheet user expects them.
#   pixi run mojo build -I . tests/test_grid_keys.mojo -o build/test_grid_keys && build/test_grid_keys
from std.testing import assert_equal, assert_true, assert_false

from mojoui import Event, TAP, DOUBLE, KEY, SHIFT, CTRL
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.datagrid import (DataGrid, GridSource, GRID_NONE, GRID_SELECTED, GRID_EDIT, GRID_READ_ONLY, GRID_TYPED, GRID_CLEAR,
                             GRID_CANCEL, GRID_HEADER_H, GRID_ROW_H)

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
            return "Person " + String(row)
        if c == 1:
            return String(20 + row % 50)
        return String((20 + row % 50) // 10 * 10)

    def grid_type_width(self, c: Int) -> Float64:
        return 120 if c == 0 else 72


def key(name: String, mods: Int = 0) -> Event:
    return Event(MSG, name, KEY, 0, 0, Float64(mods), 0)


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

    # nothing selected: an arrow selects the first cell on screen
    assert_equal(g.handle(key("ArrowDown"), src, font, pal), GRID_SELECTED)
    assert_equal(g.cur_row, 0)
    assert_equal(g.cur_col, 0)
    # arrows move one cell, skipping the deleted row 5, and stop at the edges
    for _ in range(4):
        _ = g.handle(key("ArrowDown"), src, font, pal)
    assert_equal(g.cur_row, 4)
    _ = g.handle(key("ArrowDown"), src, font, pal)
    assert_equal(g.cur_row, 6)
    _ = g.handle(key("ArrowUp"), src, font, pal)
    assert_equal(g.cur_row, 4)
    _ = g.handle(key("ArrowLeft"), src, font, pal)
    assert_equal(g.cur_col, 0)
    _ = g.handle(key("ArrowRight"), src, font, pal)
    _ = g.handle(key("ArrowRight"), src, font, pal)
    _ = g.handle(key("ArrowRight"), src, font, pal)
    assert_equal(g.cur_col, 2)
    # Tab moves right, Shift+Tab left; Enter moves down, Shift+Enter up (as in a spreadsheet)
    _ = g.handle(key("Tab", SHIFT), src, font, pal)
    assert_equal(g.cur_col, 1)
    _ = g.handle(key("Tab"), src, font, pal)
    assert_equal(g.cur_col, 2)
    _ = g.handle(key("Enter"), src, font, pal)
    assert_equal(g.cur_row, 6)
    _ = g.handle(key("Enter", SHIFT), src, font, pal)
    assert_equal(g.cur_row, 4)

    # moving below the screen scrolls so the cell stays in view
    for _ in range(30):
        _ = g.handle(key("ArrowDown"), src, font, pal)
    assert_equal(g.cur_row, 35)
    assert_true(g.screen_line(35, src) >= 0, "the selected row is on screen")
    # PageDown moves a screenful; Ctrl+Home / Ctrl+End go to the first / last row
    var before = g.cur_row
    _ = g.handle(key("PageDown"), src, font, pal)
    assert_true(g.cur_row >= before + 8, "PageDown moved about a screen")
    _ = g.handle(key("End", CTRL), src, font, pal)
    assert_equal(g.cur_row, 999)
    assert_true(g.screen_line(999, src) >= 0, "the last row is on screen")
    _ = g.handle(key("Home", CTRL), src, font, pal)
    assert_equal(g.cur_row, 0)
    assert_equal(g.cur_col, 0)

    # F2 opens the editor on an editable cell; a computed column says read-only
    assert_equal(g.handle(key("F2"), src, font, pal), GRID_EDIT)
    assert_true(g.editing)
    # Escape closes it without writing
    assert_equal(g.handle(key("Escape"), src, font, pal), GRID_CANCEL)
    assert_false(g.editing)
    _ = g.handle(key("End"), src, font, pal)  # End: the last column
    assert_equal(g.cur_col, 2)
    assert_equal(g.handle(key("F2"), src, font, pal), GRID_READ_ONLY)

    # typing a character opens the editor with it (it replaces the value); not on a computed column
    assert_equal(g.handle(key("7"), src, font, pal), GRID_READ_ONLY)
    _ = g.handle(key("ArrowLeft"), src, font, pal)
    assert_equal(g.handle(key("7"), src, font, pal), GRID_TYPED)
    assert_true(g.editing)
    assert_equal(g.typed, "7")
    _ = g.handle(key("Escape"), src, font, pal)
    # Ctrl+a character isn't typing
    assert_equal(g.handle(key("c", CTRL), src, font, pal), GRID_NONE)
    assert_false(g.editing)

    # Delete / Backspace ask the app to clear the cell (an editable one)
    assert_equal(g.handle(key("Delete"), src, font, pal), GRID_CLEAR)
    assert_equal(g.handle(key("Backspace"), src, font, pal), GRID_CLEAR)
    _ = g.handle(key("ArrowRight"), src, font, pal)
    assert_equal(g.handle(key("Delete"), src, font, pal), GRID_READ_ONLY)

    # a whole column selected: Down goes to its first row
    _ = g.handle(Event(MSG, "", TAP, g.col_left(1, src) + 5, 10), src, font, pal)
    assert_equal(g.cur_row, -1)
    _ = g.handle(key("ArrowDown"), src, font, pal)
    assert_equal(g.cur_col, 1)
    assert_true(g.cur_row >= 0, "a row is selected")

    # keys the grid doesn't use are ignored
    assert_equal(g.handle(key("Shift"), src, font, pal), GRID_NONE)
    print("GRID KEY TESTS PASSED")
