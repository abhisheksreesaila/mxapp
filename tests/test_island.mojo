# mojoui.island (goal 30 M2): the capsule's faces, its morph between them (320 ms on the calm curve, at once with less
# motion), a result and an undo giving way to the rest in their time, an error staying, hit areas, and every face drawn
# (its pixels differ from the others', and the capsule's tint follows the state).
#   scripts/mxbuild.sh tests/test_island.mojo -o build/test_island && build/test_island
from std.testing import assert_equal, assert_true, assert_false
from std.memory.alloc import alloc, Layout
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.island import (Island, Activity, IDLE, RUNNING, DONE, UNDO, ERROR, HIT_NONE, HIT_BODY, HIT_ACTION, ISLAND_W, ISLAND_H,
                           MORPH_MS, calm)

comptime MS = 1_000_000


def pixels_of(island: Island, font: Font, pal: Palette, t: Int) -> List[UInt32]:
    var w = ISLAND_W * 2
    var h = ISLAND_H * 2
    var buf = List[UInt32](length=w * h, fill=0)
    var s = Surface(Int(buf.unsafe_ptr()), w, h, 2.0)
    island.draw(s, font, pal, t)
    var out = buf.copy()
    _ = len(buf)
    return out^


def differ(a: List[UInt32], b: List[UInt32]) -> Int:
    var n = 0
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            n += 1
    return n


def main() raises:
    var font = Font()
    var pal = Palette.plain()
    var isl = Island()
    var t = 1_000 * MS
    isl.set_rest(Activity.idle("big", "100,000,000 rows · RTX 3090"), font, t)
    t += 400 * MS
    assert_equal(isl.now.kind, IDLE)
    var rest = isl.size_at(t)
    assert_equal(rest[1], 28.0, "at rest: 28 points high")
    # a query: the capsule grows over 320 ms on the calm curve, from the rest's size
    isl.show(Activity.running("Median of revenue by region", 0.0, "starting"), font, t)
    var goal = isl.size_of(isl.now, font)
    assert_true(goal[0] > rest[0], "the running face is wider")
    var half = isl.size_at(t + 160 * MS)
    var want = rest[0] + (goal[0] - rest[0]) * calm(0.5)
    assert_true(abs(half[0] - want) < 0.01, "half way in time: the calm curve's share of the way")
    assert_equal(isl.size_at(t + 320 * MS), goal, "there at 320 ms")
    assert_true(isl.wants_frames(t + 2000 * MS), "running: frames (the spinner, and the app polls its job)")
    var before = isl.size_at(t + 400 * MS)[0]
    isl.progress(0.43, "43% · 1.2B rows/s, and a longer pace", font, t + 400 * MS)
    assert_equal(isl.now.progress, 0.43)
    assert_equal(isl.size_at(t + 400 * MS)[0], before, "growing words: the capsule sets off from where it is (no jump)")
    assert_equal(isl.size_at(t + 720 * MS), isl.size_of(isl.now, font), "and fits them 320 ms later")
    var wide = isl.to_w
    isl.progress(0.5, "50%", font, t + 800 * MS)
    assert_equal(isl.to_w, wide, "shorter words while running: it doesn't shrink")
    # done: it stays 4 s, then gives way to the rest
    t += 1000 * MS
    isl.show(Activity.done("Median of revenue by region", "0.69 s on RTX 3090"), font, t)
    assert_false(isl.tick(font, t + 3900 * MS), "still showing at 3.9 s")
    assert_true(isl.tick(font, t + 4000 * MS), "gives way at 4 s")
    assert_equal(isl.now.kind, IDLE)
    t += 4000 * MS
    assert_false(isl.wants_frames(t + 1000 * MS), "at rest, settled: no frames")
    # undo: an action at its right end, 5 s
    t += 1000 * MS
    isl.show(Activity.undo("Bold applied to 21 cells"), font, t)
    t += 400 * MS
    var c = isl.capsule(t, Float64(ISLAND_W), Float64(ISLAND_H))
    assert_equal(isl.hit(c[0] + c[2] - 20, c[1] + c[3] / 2, t=t), HIT_ACTION, "the right end is Undo")
    assert_equal(isl.hit(c[0] + 20, c[1] + c[3] / 2, t=t), HIT_BODY, "the rest opens the panel")
    assert_equal(isl.hit(c[0] - 30, c[1] + c[3] / 2, t=t), HIT_NONE, "left of the capsule: nothing")
    assert_true(abs(c[0] + c[2] - (Float64(ISLAND_W) - 2.0)) < 0.01, "right-aligned: it grows leftwards")
    assert_true(isl.tick(font, t + 5000 * MS), "undo gives way at 5 s")
    # an error stays until it's seen
    isl.show(Activity.error("region: 3 rows aren't text"), font, t)
    assert_false(isl.tick(font, t + 60_000 * MS), "an error stays")
    isl.seen(font, t + 61_000 * MS)
    assert_equal(isl.now.kind, IDLE)
    # less motion: the size jumps
    var still = Island()
    still.still = True
    still.set_rest(Activity.idle("big", "100,000,000 rows"), font, 0)
    still.show(Activity.running("Sum by month", 0.5), font, 10 * MS)
    assert_equal(still.size_at(10 * MS), still.size_of(still.now, font), "less motion: there at once")
    # every face draws, and draws differently (its tint, icon and texts)
    var faces: List[Activity] = [Activity.idle("big", "100,000,000 rows · RTX 3090"), Activity.running("Median of revenue by region", 0.43, "43%"),
                                 Activity.done("Median of revenue by region", "0.69 s on RTX 3090"), Activity.undo("Bold applied to 21 cells"),
                                 Activity.error("region: 3 rows aren't text")]
    var shots = List[List[UInt32]]()
    for f in faces:
        var one = Island()
        one.show(f.copy(), font, 0)
        shots.append(pixels_of(one, font, pal, 2000 * MS))
    for i in range(len(shots)):
        for j in range(i + 1, len(shots)):
            assert_true(differ(shots[i], shots[j]) > 200, "faces " + String(i) + " and " + String(j) + " draw differently")
    # mid-morph, the capsule is between the two faces' widths (drawn, not only computed)
    var m = Island()
    m.show(Activity.idle("big", "rows"), font, 0)
    m.show(Activity.running("Median of revenue by region", 0.1), font, 1000 * MS)
    var mid = m.capsule(1000 * MS + 120 * MS, Float64(ISLAND_W), Float64(ISLAND_H))
    assert_true(mid[2] > m.from_w and mid[2] < m.to_w, "mid-morph width between the faces'")
    print("ISLAND TESTS PASSED")
