# mojoui.csvio against an independent reader (Python's csv module): rows, types, sums, the first row's text.
#   build/orders_csv 1000000 build/data/orders_1m.csv   (tools/orders_csv.mojo)
#   pixi run mojo build -I . tests/test_csvio.mojo -o build/test_csvio && pixi run build/test_csvio build/data/orders_1m.csv
from std.testing import assert_equal, assert_true
from std.sys import argv
from mojoui.csvio import read_csv, csv_oracle, kind_name
from mojoui.frame import Frame, INT, DECIMAL, TEXT, DATE


def main() raises:
    var args = argv()
    var path = String(args[1]) if len(args) > 1 else String("build/data/orders_1m.csv")
    var imp = read_csv(path)
    var frame = Frame(imp.base_addr)
    var oracle = csv_oracle(path)
    assert_equal(imp.rows, Int(py=oracle["rows"]))
    assert_equal(frame.rows(), imp.rows)
    assert_equal(len(imp.columns), 12)
    var kinds = String("")
    for c in imp.columns:
        kinds += c.name + ":" + kind_name(c.kind) + " "
    assert_equal(kinds, "order:Integer day:Date customer:Text region:Text product:Text qty:Integer revenue:Decimal cost:Decimal freight:Decimal carrier:Text weight_g:Integer zip:Integer ")
    # sums: the engine's integers against the oracle's floats (to the cent)
    for name in ["qty", "revenue", "freight"]:
        var c = frame.index(name)
        var total = Int64(0)
        for r in range(frame.rows()):
            total += frame.get(c, r)
        var want = Float64(py=oracle["sums"][name])
        var got = Float64(total) / (100.0 if frame.kind(c) == DECIMAL else 1.0)
        assert_true(abs(got - want) <= 0.01 + 1e-12 * abs(want), name + ": " + String(got) + " vs " + String(want))
    assert_equal(frame.display(frame.index("customer"), 0), "Northwind")
    assert_equal(frame.display(frame.index("day"), 0), "2025-06-13")
    assert_equal(frame.display(frame.index("revenue"), 0), "48.00")
    print("CSVIO TESTS PASSED · " + String(imp.rows) + " rows in " + String(Int(imp.seconds * 1000)) + " ms")
