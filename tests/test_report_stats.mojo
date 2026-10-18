# The Report's Distinct and Median tiles (goal 22 M3): the engine's count_distinct and median through mojoui.sheet equal
# a count over every row done here by hand, on a sheet in memory and the same file streamed, over every row and through
# the Report's filter, after an edit too; the median is the mean of the two middle values (as DuckDB, Excel and pandas)
# and shows in the column's places.
#   scripts/mxbuild.sh tests/test_report_stats.mojo -o build/test_report_stats && build/test_report_stats
from std.testing import assert_equal, assert_true
from mxframe import read_parquet, write_parquet, scan_parquet, UNCOMPRESSED
from mojoui.sheet import Sheet
from mojoui.reportpage import ReportFilter, new_tile, compute_tile, tile_value, tile_label, TILE_DISTINCT, TILE_MEDIAN

comptime SMALL = "tests/fixtures/small.parquet"  # (order, amount, region, day, paid; 5,000 rows, some empty)
comptime GROUPED = "build/test_report_stats.parquet"


def by_hand(s: Sheet, c: Int, keep_col: Int, keep_code: Int) -> Tuple[Int, Int64, Bool]:
    """(distinct non-empty values, median ×10 at the column's scale + 1, any values) over the rows kept."""
    var seen = List[Int64]()
    var values = List[Int64]()
    for row in range(s.rows()):
        if not s.alive(row) or s.is_null(c, row):
            continue
        if keep_col >= 0 and (s.is_null(keep_col, row) or Int(s.value(keep_col, row)) != keep_code):
            continue
        var v = s.value(c, row)
        values.append(v)
        var known = False
        for w in seen:
            if w == v:
                known = True
                break
        if not known:
            seen.append(v)
    if len(values) == 0:
        return (0, Int64(0), False)
    sort(values)
    var n = len(values)
    var m = values[n // 2] * 10 if n % 2 == 1 else (values[n // 2 - 1] + values[n // 2]) * 5
    return (len(seen), m, True)


def check(s: Sheet, what: String) raises:
    var west = s.code_of(2, "West")
    for keep in [-1, 2]:
        var code = west if keep >= 0 else 0
        var filter = ReportFilter(keep, code)
        for c in [0, 1, 2, 3]:  # (order, amount, region: text, day)
            var want = by_hand(s, c, keep, code)
            assert_equal(s.distinct(c, filter.condition(s)), want[0], what + ": distinct " + s.name(c) + " filter " + String(keep))
        for c in [0, 1]:
            var want = by_hand(s, c, keep, code)
            var got = s.median(c, filter.condition(s))
            assert_equal(got[1], want[2])
            assert_equal(got[0], want[1], what + ": median " + s.name(c) + " filter " + String(keep))


def main() raises:
    var r = read_parquet(SMALL)
    var t = r.take_table()
    write_parquet(GROUPED, t, "", UNCOMPRESSED, 312)
    var whole = Sheet(t^.share(), False)
    var streamed = Sheet(scan_parquet(GROUPED))
    check(whole, "in memory")
    check(streamed, "streamed")
    for sheet_k in range(2):  # an edit (a new word and a new amount) counts at once
        ref x = whole if sheet_k == 0 else streamed
        x.set_text(2, 9, "Antarctica")
        x.set_text(1, 9, "123456.78")
    check(whole, "in memory, edited")
    check(streamed, "streamed, edited")
    assert_equal(whole.distinct(2), 6)  # (North, South, East, West, Central and the new word; empty cells don't count)

    # the tiles: labels and the median in the column's places (an even count: the mean of the two middle values)
    var d = new_tile(TILE_DISTINCT, 2, -1)
    compute_tile(d, whole, ReportFilter(-1, 0))
    assert_equal(tile_label(d, whole), "Different region")
    assert_equal(tile_value(d, whole), "6")
    var m = new_tile(TILE_MEDIAN, 1, -1)
    compute_tile(m, whole, ReportFilter(-1, 0))
    assert_equal(tile_label(m, whole), "Median of amount")
    var exact = whole.median(1)[0]
    var places = (exact + 5) // 10 if exact >= 0 else -((-exact + 5) // 10)  # (half away from zero, to the column's 2 places)
    var whole_part = places // 100
    var cents = places % 100
    assert_true(tile_value(m, whole).endswith(String(whole_part % 1000) + "." + ("0" if cents < 10 else "") + String(cents)),
                "median shown in amount's places: " + tile_value(m, whole) + " for " + String(exact))
    var orders = new_tile(TILE_MEDIAN, 0, -1)  # (whole numbers: 5,000 rows, so the middle falls between two: .5)
    compute_tile(orders, whole, ReportFilter(-1, 0))
    assert_equal(tile_value(orders, whole), "2,500.5")
    print("REPORT STATS: distinct and median equal a count by hand, in memory and streamed, filtered and edited")
    print("REPORT STATS TESTS PASSED")
