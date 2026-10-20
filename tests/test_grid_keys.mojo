# mojoui.datagrid's keyboard, on its own: the KEY events the hosts send (event.text = the key's name, or the
# character typed; event.dx = modifiers: 1 Shift, 2 Ctrl, 4 Alt), as a spreadsheet user expects them.
#   pixi run mojo build -I . tests/test_grid_keys.mojo -o build/test_grid_keys && build/test_grid_keys
from std.testing import assert_equal, assert_true, assert_false

from mojoui import Event, TAP, DOUBLE, KEY, SHIFT, CTRL
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from themes.omarchy import omarchy_palette
from mojoui.datagrid import (DataGrid, GridSource, GRID_NONE, GRID_SELECTED, GRID_EDIT, GRID_READ_ONLY, GRID_TYPED, GRID_CLEAR,
                             GRID_CANCEL, GRID_COMMIT, GRID_HEADER_H, GRID_ROW_H)

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

    def grid_badge(self, c: Int) -> String:
        var badges: List[String] = ["Aa", "#", "ƒx"]
        return badges[c]

    def grid_edited(self, c: Int, row: Int) -> Bool:
        return c == 1 and row == 2  # one cell changed this session


def key(name: String, mods: Int = 0) -> Event:
    return Event(MSG, name, KEY, 0, 0, Float64(mods), 0)


def main() raises:
    var src = People(0)
    var font = Font()
    var pal = omarchy_palette()
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
    _ = g.handle(key("PageDown"), src, font, pal)  # a screen less one row: 9 rows (10 on screen)
    assert_equal(g.cur_row, 44)
    assert_true(g.screen_line(44, src) >= 0, "PageDown keeps the cell on screen")
    _ = g.handle(key("PageUp"), src, font, pal)
    assert_equal(g.cur_row, 35)
    _ = g.handle(key("ArrowRight"), src, font, pal)
    _ = g.handle(key("Home"), src, font, pal)  # Home: the first column, the same row
    assert_equal(g.cur_row, 35)
    assert_equal(g.cur_col, 0)
    _ = g.handle(key("End", CTRL), src, font, pal)
    assert_equal(g.cur_row, 999)
    assert_true(g.screen_line(999, src) >= 0, "the last row is on screen")
    _ = g.handle(key("ArrowDown"), src, font, pal)  # the last row: Down stays
    assert_equal(g.cur_row, 999)
    _ = g.handle(key("Home", CTRL), src, font, pal)
    assert_equal(g.cur_row, 0)
    assert_equal(g.cur_col, 0)
    assert_equal(g.top, 0)  # scrolled back up to it
    _ = g.handle(key("ArrowUp"), src, font, pal)  # the first row: Up stays
    assert_equal(g.cur_row, 0)
    # going up one row past the screen's top scrolls by one row
    for _ in range(20):
        _ = g.handle(key("ArrowDown"), src, font, pal)
    var top = g.top
    var first_line = g.first_on_screen(src)
    g.select(first_line, 0)
    _ = g.handle(key("ArrowUp"), src, font, pal)
    assert_equal(g.top, top - 1)

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
    # keys typed before the editor appeared (a round trip on the web) go on the end
    assert_equal(g.handle(key("8"), src, font, pal), GRID_TYPED)
    assert_equal(g.typed, "78")
    # while a value is typed the grid has it: Backspace takes a character off, arrows don't move, Enter writes it
    assert_equal(g.handle(key("Backspace"), src, font, pal), GRID_TYPED)
    assert_equal(g.typed, "7")
    var at = g.cur_row
    var at_col = g.cur_col
    assert_equal(g.handle(key("Enter"), src, font, pal), GRID_COMMIT)
    assert_equal(g.typed, "7")
    g.committed(src)  # (the app wrote it): the cell below, nothing being typed
    assert_equal(g.cur_row, at + 1)
    assert_false(g.typing)
    # as in Excel: Tab writes and moves right, an arrow writes and moves its way
    _ = g.handle(key("4"), src, font, pal)
    assert_equal(g.handle(key("Tab"), src, font, pal), GRID_COMMIT)
    g.committed(src)
    assert_equal(g.cur_row, at + 1)
    assert_equal(g.cur_col, at_col + 1)
    _ = g.handle(key("ArrowLeft"), src, font, pal)
    _ = g.handle(key("4"), src, font, pal)
    assert_equal(g.handle(key("ArrowUp"), src, font, pal), GRID_COMMIT)
    g.committed(src)
    assert_equal(g.cur_row, at)
    assert_equal(g.cur_col, at_col)
    _ = g.handle(key("4"), src, font, pal)
    assert_equal(g.handle(key("Tab", SHIFT), src, font, pal), GRID_COMMIT)
    g.committed(src)
    assert_equal(at_col, 1)  # (so Shift+Tab has somewhere to go)
    assert_equal(g.cur_col, 0)
    _ = g.handle(key("4"), src, font, pal)
    assert_equal(g.handle(key("ArrowRight"), src, font, pal), GRID_COMMIT)
    g.committed(src)
    assert_equal(g.cur_col, 1)
    var before_down = g.cur_row
    _ = g.handle(key("4"), src, font, pal)
    assert_equal(g.handle(key("ArrowDown"), src, font, pal), GRID_COMMIT)
    g.committed(src)
    assert_equal(g.cur_row, before_down + 1)
    _ = g.handle(key("ArrowLeft"), src, font, pal)
    _ = g.handle(key("ArrowUp"), src, font, pal)
    # a refused write ends with Escape: the Tab that ended it doesn't move a later edit
    _ = g.handle(key("4"), src, font, pal)
    _ = g.handle(key("Tab"), src, font, pal)  # (the app refused it: no committed())
    _ = g.handle(key("Escape"), src, font, pal)
    _ = g.handle(key("F2"), src, font, pal)
    var col_before = g.cur_col
    g.committed(src)
    assert_equal(g.cur_col, col_before)
    # a double-click or F2 editor's Enter (the app writes the field's text) still moves down
    var row_before = g.cur_row
    _ = g.handle(key("F2"), src, font, pal)
    g.committed(src)
    assert_equal(g.cur_row, row_before + 1)
    _ = g.handle(key("Home"), src, font, pal)
    _ = g.handle(key("ArrowRight"), src, font, pal)  # (back on the age column for what follows)
    assert_equal(g.cur_col, 1)
    assert_equal(g.handle(key("8"), src, font, pal), GRID_TYPED)
    _ = g.handle(key("Escape"), src, font, pal)
    assert_equal(g.typed, "")
    # F2 after typing (or anything that closed the editor) selects the value again: nothing typed comes back
    _ = g.handle(key("5"), src, font, pal)
    g.editing = False  # (closed without cancel_edit(): F2 itself must drop what was typed)
    assert_equal(g.handle(key("F2"), src, font, pal), GRID_EDIT)
    assert_equal(g.typed, "")
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

    # sorted (the engine's order: here, last row first): arrows follow the order shown, not the row numbers
    var order = List[Int]()
    for r in range(999, -1, -1):
        order.append(r)
    g.set_order(order^, 1, True)
    g.select(500, 0)
    assert_equal(g.index_of(500, src), 499)
    _ = g.handle(key("ArrowDown"), src, font, pal)
    assert_equal(g.cur_row, 499)
    _ = g.handle(key("ArrowUp"), src, font, pal)
    _ = g.handle(key("ArrowUp"), src, font, pal)
    assert_equal(g.cur_row, 501)
    _ = g.handle(key("Home", CTRL), src, font, pal)
    assert_equal(g.cur_row, 999)
    assert_equal(g.handle(key("End", CTRL), src, font, pal), GRID_SELECTED)
    assert_equal(g.cur_row, 0)
    for _ in range(6):  # the deleted row 5 is skipped in this order too
        _ = g.handle(key("ArrowUp"), src, font, pal)
    assert_equal(g.cur_row, 7)

    # a key before the grid was ever drawn (no size yet) still works
    var fresh = DataGrid()
    assert_equal(fresh.handle(key("ArrowDown"), src, font, pal), GRID_SELECTED)
    assert_equal(fresh.cur_row, 0)
    assert_equal(fresh.handle(key("PageDown"), src, font, pal), GRID_SELECTED)
    assert_true(fresh.cur_row > 0, "PageDown moved")
    print("GRID KEY TESTS PASSED")
