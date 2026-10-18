# A streamed sheet (mojoui.sheet, D-185) equals the same file read whole: every cell (text, decimals, dates, booleans,
# empty cells) across row groups and back again (only a few groups are kept), the totals, a chart's and a pivot's
# group-bys, a column's span; and it refuses edits, formulas, rows and sorting with the reason.
#   scripts/mxbuild.sh tests/test_streamed.mojo -o build/test_streamed && build/test_streamed
from std.testing import assert_equal, assert_true, assert_false
from std.os import remove
from mxframe import read_parquet, write_parquet, scan_parquet, UNCOMPRESSED
from mojoui.sheet import Sheet, KEPT_GROUPS, READ_ONLY, TEXT
from mojoui.sheetpage import SheetObject, compute

comptime SMALL = "tests/fixtures/small.parquet"  # (pyarrow wrote it: 5,000 rows, one row group)
comptime GROUPED = "build/test_streamed.parquet"  # the same rows in row groups of 312 (17 groups, the last short)


def main() raises:
    var r = read_parquet(SMALL)
    var t = r.take_table()
    write_parquet(GROUPED, t, "", UNCOMPRESSED, 312)
    var whole = Sheet(t^.share(), False)
    var scan = scan_parquet(GROUPED)
    assert_equal(scan.row_groups(), 17)
    var s = Sheet(scan)
    assert_true(s.streamed())
    assert_false(whole.streamed())
    assert_equal(s.rows(), whole.rows())
    assert_equal(s.columns(), whole.columns())

    # every cell, forwards, then a backwards walk that jumps between far groups (the kept groups turn over)
    var cells = 0
    for row in range(s.rows()):
        for c in range(s.columns()):
            assert_equal(s.display(c, row), whole.display(c, row), s.name(c) + " row " + String(row))
            assert_equal(s.is_null(c, row), whole.is_null(c, row))
            cells += 1
    var row = s.rows() - 1
    while row >= 0:
        for c in range(s.columns()):
            assert_equal(s.display(c, row), whole.display(c, row))
        row -= 1 + (row * 7919) % 900
    assert_true(len(s.pages[].groups) <= KEPT_GROUPS)
    for c in range(s.columns()):
        assert_false(s.grid_editable(c))  # read-only...
        assert_false(s.grid_formula(c))  # ...but not a formula (no ƒ on its header)
    assert_false(s.edited(1, 3))
    assert_equal(s.read_problem(), "")

    # totals (kept per column: the second call is the same), a chart and a pivot, a span
    for c in [0, 1, 3, 4]:
        var a = s.totals(c)
        var b = whole.totals(c)
        assert_equal(a.sums[0], b.sums[0], s.name(c))
        assert_equal(a.present[0], b.present[0])
        assert_equal(a.counts[0], b.counts[0])
        assert_equal(s.totals(c).sums[0], a.sums[0])
    var chart = SheetObject.chart(1, 2, 0, 0)
    var chart_whole = chart.copy()
    compute(chart, s)
    compute(chart_whole, whole)
    assert_equal(chart.labels, chart_whole.labels)
    assert_equal(chart.sums, chart_whole.sums)
    assert_equal(chart.labels[len(chart.labels) - 1], "(blank)")  # (134 rows have no region)
    var pivot = SheetObject.pivot(1, 2, 2, 0, 0)  # (region × region: the only text column; blanks on both sides)
    var pivot_whole = pivot.copy()
    compute(pivot, s)
    compute(pivot_whole, whole)
    assert_equal(pivot.sums, pivot_whole.sums)
    assert_equal(pivot.counts, pivot_whole.counts)
    var span = s.span(1)
    var span_whole = whole.span(1)
    assert_equal(span[0], span_whole[0])
    assert_equal(span[1], span_whole[1])

    # read-only, with the reason
    var refused = 0
    try:
        s.set_text(1, 0, "1.00")
    except e:
        assert_equal(String(e), READ_ONLY)
        refused += 1
    try:
        _ = s.formula("double = amount * 2")
    except e:
        refused += 1
    try:
        _ = s.append()
    except e:
        refused += 1
    try:
        _ = s.permutation(1)
    except e:
        refused += 1
    assert_equal(refused, 4)
    assert_false(s.undo())
    assert_equal(s.display(1, 0), whole.display(1, 0))
    # a file that goes away after it was opened: the rows read say so instead of showing zeros
    var gone = "build/test_streamed_gone.parquet"
    var again = read_parquet(SMALL)
    write_parquet(gone, again.take_table(), "", UNCOMPRESSED, 312)
    var g = Sheet(scan_parquet(gone))
    remove(gone)
    _ = g.display(1, 4000)
    assert_true(g.read_problem() != "", "a failed read left no problem")
    # ...and when the file is back, the next row group read clears it
    var back = read_parquet(SMALL)
    write_parquet(gone, back.take_table(), "", UNCOMPRESSED, 312)
    _ = g.display(1, 100)
    assert_equal(g.read_problem(), "")
    assert_equal(g.display(1, 100), whole.display(1, 100))
    print("STREAMED: " + String(cells) + " cells over 17 row groups equal the whole read; totals, chart, pivot, span")
    print("STREAMED TESTS PASSED")
