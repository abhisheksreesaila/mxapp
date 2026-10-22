# mojoui.tiling (goal 30 M0): cards on a Board in rows, as a tiling window manager keeps windows: a new card joins the
# last row while it has room and the row splits its width equally; removing one closes the gap; a drop snaps to edges
# and lines nearby, or swaps with the card under the pointer; a resize snaps to a share of the page and the row's height.
#   scripts/mxbuild.sh tests/test_tiling.mojo -o build/test_tiling && build/test_tiling
from std.testing import assert_equal, assert_true
from mojoui.tiling import Place, per_row, tile_insert, tile_remove, snap_move, snap_resize, GAP


def show(p: List[Place]) -> String:
    var out = String("")
    for q in p:
        out += String(q.x) + "," + String(q.y) + " " + String(q.w) + "x" + String(q.h) + "; "
    return out


def main() raises:
    var W = 1360
    var top = 432  # (just under the table)
    assert_equal(per_row(1360), 2)
    assert_equal(per_row(1500), 3)
    # one card: the whole row; two: halves; a third starts a row (2 a row at 1,360)
    var p = List[Place]()
    p = tile_insert(p, top, W, 340)
    assert_equal(show(p), "0,432 1360x340; ")
    p = tile_insert(p, top, W, 340)
    assert_equal(show(p), "0,432 672x340; 688,432 672x340; ")
    p = tile_insert(p, top, W, 340)
    assert_equal(show(p), "0,432 672x340; 688,432 672x340; 0,788 1360x340; ")
    # three a row on a wide page; the row keeps its tallest height
    var wide = List[Place]()
    wide = tile_insert(wide, 0, 1600, 340)
    wide[0].h = 400
    wide = tile_insert(wide, 0, 1600, 340)
    wide = tile_insert(wide, 0, 1600, 340)
    assert_equal(show(wide), "0,0 522x400; 539,0 522x400; 1078,0 522x400; ")
    # removing closes the gap: the row's other card takes the whole row; an emptied row lets the rows below move up
    var r = tile_remove(p, 0, top, W)
    assert_equal(show(r), "0,432 1360x340; 0,788 1360x340; ")
    var r2 = tile_remove(p, 2, top, W)
    assert_equal(show(r2), "0,432 672x340; 688,432 672x340; ")
    var single = tile_insert(List[Place](), top, W, 340)
    single = tile_insert(single, top, W, 340)
    single = tile_insert(single, top, W, 340)  # (row 2: one card)
    single = tile_insert(single, top, W, 340)  # (row 2: two)
    var up = tile_remove(tile_remove(single, 0, top, W), 0, top, W)  # (row 1 emptied: row 2 moves up)
    assert_equal(show(up), "0,432 672x340; 688,432 672x340; ")
    # a card moved off the rows is never moved by another's insert: the new one starts a row below everything
    var free = tile_insert(List[Place](), top, W, 340)
    free[0].x = 100
    free[0].y = 500
    free = tile_insert(free, top, W, 340)
    assert_equal(show(free), "100,500 1360x340; 0,856 1360x340; ")
    # a drop within 24 points of a line snaps to it: 10 past the right half's line lands on it
    var d = p.copy()
    d[2].w = 672
    var before = d[2].copy()
    d[2].x = 698
    d = snap_move(d, 2, before, 698 + 20, 788 + 16, top, W)
    assert_equal(show(d), "0,432 672x340; 688,432 672x340; 688,788 672x340; ")
    # 30 off: nothing within reach but the row's own line (y) and the page's edge (x 0 is 30 away: stays)
    var far = p.copy()
    far[2].w = 600
    var fb = far[2].copy()
    far[2].x = 30
    far[2].y = 790
    far = snap_move(far, 2, fb, 50, 806, top, W)
    assert_equal(show(far), "0,432 672x340; 688,432 672x340; 30,788 600x340; ")
    # a drop with the pointer on another card swaps them (place and size)
    var s = p.copy()
    var sb = s[2].copy()
    s[2].x = 40
    s[2].y = 472
    s = snap_move(s, 2, sb, 60, 488, top, W)
    assert_equal(show(s), "0,788 1360x340; 688,432 672x340; 0,432 672x340; ")
    # a resize snaps to a third, a half, two thirds or the whole width, and to its row's height
    var z = p.copy()
    z[2].w = 650
    z = snap_resize(z, 2, top, W)
    assert_equal(z[2].w, 672, "30 under half: half")
    z[2].w = 900
    z = snap_resize(z, 2, top, W)
    assert_equal(z[2].w, 901, "near two thirds: two thirds ((1360 - 32) / 3 * 2 + 16)")
    z[2].w = 800
    z = snap_resize(z, 2, top, W)
    assert_equal(z[2].w, 800, "nothing near: kept")
    var row = p.copy()
    row[1].h = 360
    row = snap_resize(row, 1, top, W)
    assert_equal(row[1].h, 340, "within 24 of its row's height: the row's")
    print("TILING TESTS PASSED")
