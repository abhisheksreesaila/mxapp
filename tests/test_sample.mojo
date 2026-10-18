# mojoui.sample builds the sample orders straight into an MX frame table: every cell equals the stand-in's order_columns.
#   scripts/mxbuild.sh tests/test_sample.mojo -o build/test_sample && build/test_sample
from std.testing import assert_equal
from mojoui.orders import order_columns
from mojoui.sample import sample_table


def main() raises:
    for n in [5000, 25_000]:
        var want = order_columns(n)
        var got = sample_table(n)
        assert_equal(got.rows(), want.rows)
        assert_equal(got.columns(), len(want.cols))
        for c in range(len(want.cols)):
            assert_equal(got.name(c), want.cols[c].name)
            assert_equal(got.kind(c).value, want.cols[c].kind)
            if want.cols[c].kind == 2:
                assert_equal(len(got.dictionary(c)), len(want.cols[c].dictionary))
            for r in range(want.rows):
                assert_equal(got.get(c, r), want.cols[c].values[r])
    print("SAMPLE TESTS PASSED")
