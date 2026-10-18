# mojoui.csvio (MX frame's reader, no Python) against an independent reader (Python's csv module, used only here):
# rows, types, sums, the first row's text; and empty cells (nulls) and true/false columns on a small file.
#   build/orders_csv 1000000 build/data/orders_1m.csv   (tools/orders_csv.mojo)
#   scripts/mxbuild.sh tests/test_csvio.mojo -o build/test_csvio && build/test_csvio build/data/orders_1m.csv
from std.testing import assert_equal, assert_true
from std.sys import argv
from std.python import Python
from mojoui.csvio import read_csv, kind_name
from mojoui.sheet import Sheet, DECIMAL, BOOL

comptime ORACLE = """
import csv

def count_rows(path):
    rows = 0
    sums = {}
    with open(path, newline="") as f:
        for rec in csv.DictReader(f):
            rows += 1
            for k, v in rec.items():
                try:
                    sums[k] = sums.get(k, 0.0) + float(v)
                except ValueError:
                    pass
    return {"rows": rows, "sums": sums}
"""


def main() raises:
    var args = argv()
    var path = String(args[1]) if len(args) > 1 else String("build/data/orders_1m.csv")
    var imp = read_csv(path)
    var sheet = Sheet(imp.table, False)
    var types = Python.import_module("types")
    var builtins = Python.import_module("builtins")
    var mod = types.ModuleType("oracle")
    _ = builtins.exec(ORACLE, mod.__dict__)
    var oracle = mod.count_rows(path)
    assert_equal(imp.rows, Int(py=oracle["rows"]))
    assert_equal(sheet.rows(), imp.rows)
    assert_equal(len(imp.columns), 12)
    var kinds = String("")
    for c in imp.columns:
        kinds += c.name + ":" + kind_name(c.kind) + " "
    assert_equal(kinds, "order:Integer day:Date customer:Text region:Text product:Text qty:Integer revenue:Decimal cost:Decimal freight:Decimal carrier:Text weight_g:Integer zip:Integer ")
    # sums: the engine's integers against the oracle's floats (to the cent)
    for name in ["qty", "revenue", "freight"]:
        var c = sheet.index(name)
        var total = Int64(sheet.totals(c).sums[0])
        var want = Float64(py=oracle["sums"][name])
        var got = Float64(total) / (100.0 if sheet.kind(c) == DECIMAL else 1.0)
        assert_true(abs(got - want) <= 0.01 + 1e-12 * abs(want), name + ": " + String(got) + " vs " + String(want))
    assert_equal(sheet.display(sheet.index("customer"), 0), "Northwind")
    assert_equal(sheet.display(sheet.index("day"), 0), "2025-06-13")
    assert_equal(sheet.display(sheet.index("revenue"), 0), "48.00")

    # empty cells are nulls, shown blank and left out of sums and averages; true/false is a BOOL column
    var small = "build/with-nulls.csv"
    with open(small, "w") as f:
        f.write("name,amount,paid\nAcme,10.50,true\n,,false\nBeta,4.25,\n")
    var s = read_csv(small)
    assert_equal(s.rows, 3)
    assert_equal(s.columns[0].empty, 1)
    assert_equal(s.columns[1].empty, 1)
    assert_equal(s.columns[2].kind, BOOL)
    var t = Sheet(s.table, False)
    assert_equal(t.display(0, 1), "")
    assert_equal(t.display(1, 1), "")
    assert_equal(t.display(1, 0), "10.50")
    assert_equal(t.display(2, 0), "true")
    assert_equal(t.display(2, 1), "false")
    assert_equal(t.display(2, 2), "")
    var amounts = t.totals(1)
    assert_equal(amounts.sums[0], 1475)
    assert_equal(amounts.counts[0], 3)
    assert_equal(amounts.present[0], 2)  # (the average divides by 2, not 3)
    assert_equal(t.format_average(1, amounts.sums[0], amounts.present[0]), "7.38")  # 14.75 / 2 = 7.375, rounded half away from zero
    var missing = False
    try:
        _ = read_csv("build/data/does-not-exist.csv")
    except e:
        missing = String(e).startswith("couldn't read build/data/does-not-exist.csv as CSV")
    assert_true(missing, "a missing file is refused with a readable message")
    print("CSVIO TESTS PASSED · " + String(imp.rows) + " rows in " + String(Int(imp.seconds * 1000)) + " ms")
