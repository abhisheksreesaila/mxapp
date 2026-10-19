# The Scene (goal 26 M2, M3): a display list replays to exactly the pixels the drawing calls make; the grid recorded
# as a Scene replays to exactly the grid drawn into pixels; its cells and its ring are separate layers, so a host
# can tell when only the ring moved; the cells' text can be read from the list.
#   pixi run mojo run -I . tests/test_scene.mojo
from std.testing import assert_equal, assert_true, assert_false

from mojoui import Event, KEY
from mojoui.canvas import Surface
from mojoui.draw import rect, line, circle
from mojoui.text import Font, REGULAR, MEDIUM, LEFT, RIGHT
from mojoui.theme import Palette
from mojoui.scene import Scene, SurfacePainter, OP_TEXT
from mojoui.datagrid import DataGrid
from tests.test_datagrid import People


def same(a: List[UInt32], b: List[UInt32]) -> Int:
    """How many pixels differ."""
    var n = 0
    for i in range(len(a)):
        if a[i] != b[i]:
            n += 1
    return n


def test_a_scene_replays_to_the_same_pixels() raises:
    var font = Font()
    var a = List[UInt32](length=300 * 120, fill=0)
    var b = List[UInt32](length=300 * 120, fill=0)
    var sa = Surface(Int(a.unsafe_ptr()), 300, 120, 2.0)
    sa.fill(0xFFFFFFFF)
    rect(sa, 10, 10, 120, 40, 0xFF86_7C0E, 8)
    line(sa, 0, 60, 300, 60, 1, 0xFF00_0000)
    circle(sa, 200, 30, 12, 0xFF33_22EE)
    font.draw(sa, "1,204.50", 290, 100, 26, 0xFF2A_170F, MEDIUM, RIGHT, 0)
    var sc = Scene(300, 120, 2.0)
    sc.fill(0xFFFFFFFF)
    sc.rect(10, 10, 120, 40, 0xFF86_7C0E, 8)
    sc.line(0, 60, 300, 60, 1, 0xFF00_0000)
    sc.circle(200, 30, 12, 0xFF33_22EE)
    sc.text(font, "1,204.50", 290, 100, 26, 0xFF2A_170F, MEDIUM, RIGHT, 0)
    var sb = Surface(Int(b.unsafe_ptr()), 300, 120, 2.0)
    sc.raster(sb, font)
    assert_equal(same(a, b), 0, "the replay draws every pixel the calls did")
    assert_equal(sc.ops(), 5)


def test_the_grid_as_a_scene_is_the_grid() raises:
    var font = Font()
    var pal = Palette.liquid()
    var src = People(0)
    var w = 900
    var h = 500
    var g1 = DataGrid()
    var g2 = DataGrid()
    var a = List[UInt32](length=w * h, fill=0)
    var b = List[UInt32](length=w * h, fill=0)
    var sa = Surface(Int(a.unsafe_ptr()), w, h, 1.0)
    sa.still = True
    g1.select(4, 1)
    g2.select(4, 1)
    g1.draw(sa, src, font, pal)
    var sc = Scene(w, h, 1.0)
    sc.is_still = True
    g2.draw_scene(sc, src, font, pal)
    var sb = Surface(Int(b.unsafe_ptr()), w, h, 1.0)
    sc.raster(sb, font)
    assert_equal(same(a, b), 0, "the grid recorded and replayed is the grid drawn")
    assert_equal(sc.layers(), 2, "cells, then the ring")
    assert_equal(sc.layer_keys[0], "cells")
    assert_equal(sc.layer_keys[1], "ring")
    var ring = sc.layer_range(1)
    assert_true(ring[1] - ring[0] <= 8, "the ring layer is a handful of shapes")
    var texts = List[String]()
    for op in range(sc.ops()):
        if Int(sc.kinds[op]) == OP_TEXT:
            texts.append(sc.text_at(op))
    assert_true("Person 7" in texts, "the cells' text is readable from the list (an agent, a test)")


def test_only_the_ring_changes_when_the_selection_glides() raises:
    var font = Font()
    var pal = Palette.liquid()
    var src = People(0)
    var g = DataGrid()
    g.select(4, 1)
    g.extend(6, 2, src)  # a block: the cells are tinted as one
    var first = Scene(900, 500, 1.0)
    first.is_still = True
    g.draw_scene(first, src, font, pal)
    var again = Scene(900, 500, 1.0)  # the next frame: nothing changed
    again.is_still = True
    g.draw_scene(again, src, font, pal)
    assert_true(again.same_layer(0, first, 0), "an unchanged frame: the cells layer is the same (a host reuses its nodes)")
    assert_true(again.same_layer(1, first, 1))
    _ = g.handle(Event(1, "ArrowDown", KEY, 0, 0, 0, 0, 1), src, font, pal)  # (the block collapses: the cells change)
    var moved = Scene(900, 500, 1.0)
    moved.is_still = True
    g.draw_scene(moved, src, font, pal)
    assert_false(moved.same_layer(1, first, 1), "the ring moved")


def main() raises:
    test_a_scene_replays_to_the_same_pixels()
    test_the_grid_as_a_scene_is_the_grid()
    test_only_the_ring_changes_when_the_selection_glides()
    print("SCENE TESTS PASSED")
