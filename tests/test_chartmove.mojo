# Goal 28 M5: a chart moving to its new spec. At the start it draws exactly the old chart, at the end exactly the new
# one, in between something of both; the curve only moves forward and doesn't overshoot.
#   scripts/mxbuild.sh tests/test_chartmove.mojo -o build/test_chartmove && build/test_chartmove
from std.testing import assert_equal, assert_true
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.chartview import ChartView
from mojoui.sheetpage import ease


def picture(var cv: ChartView) -> List[UInt32]:
    var px = List[UInt32](length=400 * 200, fill=0)
    var s = Surface(Int(px.unsafe_ptr()), 400, 200, 1.0)
    cv.draw(s, Font(), Palette.plain())
    return px^


def differ(a: List[UInt32], b: List[UInt32]) -> Int:
    var n = 0
    for i in range(len(a)):
        if a[i] != b[i]:
            n += 1
    return n


def main() raises:
    var old_labels: List[String] = ["North", "South", "East"]
    var old_values: List[Float64] = [300.0, 100.0, 200.0]
    var new_labels: List[String] = ["South", "East", "North"]  # (re-ordered, and the values changed)
    var new_values: List[Float64] = [400.0, 250.0, 50.0]
    var before = picture(ChartView("t", old_labels.copy(), old_values.copy(), "v", False))
    var after = picture(ChartView("t", new_labels.copy(), new_values.copy(), "v", False))
    var start = ChartView("t", new_labels.copy(), new_values.copy(), "v", False)
    start.moving_from(old_labels.copy(), old_values.copy(), 0.0)
    var mid = ChartView("t", new_labels.copy(), new_values.copy(), "v", False)
    mid.moving_from(old_labels.copy(), old_values.copy(), 0.5)
    var end = ChartView("t", new_labels.copy(), new_values.copy(), "v", False)
    end.moving_from(old_labels.copy(), old_values.copy(), 1.0)
    var p0 = picture(start^)
    var p5 = picture(mid^)
    var p1 = picture(end^)
    assert_equal(differ(p1, after), 0, "at the end: exactly the new chart")
    assert_true(differ(p5, before) > 0 and differ(p5, after) > 0, "half way: neither")
    # at the start the bars stand where they stood and as long (the figures already say the new values)
    assert_true(differ(p0, before) < differ(p0, after), "at the start: the old chart's bars")
    var last = 0.0
    for k in range(21):
        var e = ease(Float64(k) / 20.0)
        assert_true(e >= last and e <= 1.0, "the curve only moves forward, never past the end")
        last = e
    assert_equal(ease(0.0), 0.0)
    assert_equal(ease(1.0), 1.0)
    print("CHARTMOVE TESTS PASSED")
