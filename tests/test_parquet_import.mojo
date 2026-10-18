# mojoui.csvio's Parquet path (goal 20, D-183): a file pyarrow wrote (tests/fixtures/small.parquet, from
# scripts/parquet_fixture.py small) reads with pyarrow's rows, kinds, empty cells and values; the same file opened
# for streaming (OMX_STREAM_ROWS, D-184) reports the same columns and first rows; a file that isn't Parquet says so.
#   scripts/mxbuild.sh tests/test_parquet_import.mojo -o build/test_parquet_import && build/test_parquet_import
from std.testing import assert_equal, assert_true, assert_false
from std.os import setenv, unsetenv
from mojoui.csvio import read_table, streams, kind_name
from mojoui.sheet import Sheet, INT, DECIMAL, TEXT, DATE, BOOL

comptime SMALL = "tests/fixtures/small.parquet"


def main() raises:
    _ = unsetenv("OMX_STREAM_ROWS")
    var imp = read_table(SMALL)
    assert_false(imp.streamed())
    assert_equal(imp.rows, 5000)
    var kinds = String("")
    for c in imp.columns:
        kinds += c.name + ":" + kind_name(c.kind) + ":" + String(c.empty) + " "
    assert_equal(kinds, "order:Integer:0 amount:Decimal:250 region:Text:134 day:Date:0 paid:Yes/No:0 ")  # (pyarrow's null counts)
    assert_equal(imp.columns[1].scale, 2)
    assert_equal(imp.columns[2].distinct, 5)
    assert_equal(imp.columns[1].sample[0], "7196.89")
    assert_equal(imp.columns[3].sample[2], "2025-11-25")
    assert_equal(imp.columns[4].sample[0], "false")

    var sheet = Sheet(imp.table, False)
    assert_equal(sheet.rows(), 5000)
    assert_equal(sheet.display(0, 4321), "4322")
    assert_equal(sheet.display(1, 4321), "2713.35")
    assert_equal(sheet.display(2, 4321), "East")
    assert_equal(sheet.display(3, 4321), "2025-01-22")
    var t = sheet.totals(1)
    assert_equal(t.sums[0], 2379279342)  # pyarrow: 23,792,793.42 over 4,750 values
    assert_equal(t.present[0], 4750)
    assert_equal(t.counts[0], 5000)

    # the stream decision: a row count asked for, else a quarter of memory
    _ = setenv("OMX_STREAM_ROWS", "1000", True)
    assert_true(streams(5000, 5))
    assert_false(streams(1000, 5))
    _ = unsetenv("OMX_STREAM_ROWS")
    assert_false(streams(5000, 5))
    assert_true(streams(1 << 50, 5))

    # streamed: the same columns and first rows, no table read, empty cells not counted
    _ = setenv("OMX_STREAM_ROWS", "1000", True)
    var s = read_table(SMALL)
    _ = unsetenv("OMX_STREAM_ROWS")
    assert_true(s.streamed())
    assert_equal(s.rows, 5000)
    assert_equal(s.table.rows(), 0)
    for c in range(5):
        assert_equal(s.columns[c].name, imp.columns[c].name)
        assert_equal(s.columns[c].kind, imp.columns[c].kind)
        assert_equal(s.columns[c].empty, -1)
        for r in range(3):
            assert_equal(s.columns[c].sample[r], imp.columns[c].sample[r], s.columns[c].name)

    # not Parquet: a readable error
    with open("build/not-parquet.parquet", "w") as f:
        f.write("order,amount\n1,2\n")
    var said = String("")
    try:
        _ = read_table("build/not-parquet.parquet")
    except e:
        said = String(e)
    assert_true("not a Parquet file" in said, said)
    print("PARQUET IMPORT TESTS PASSED")
