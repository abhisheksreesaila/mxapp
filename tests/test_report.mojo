# The Report's anomaly finder and KPIs on the GPU, checked against the same numbers computed here on the CPU.
#   pixi run mojo build -I examples/mxstudio -I . tests/test_report.mojo -o build/test_report && build/test_report
from std.testing import assert_equal, assert_true

from orders import order_columns, DAY, REGION, REVENUE, COST, FREIGHT, WEIGHT, YEAR_START, RATE_CHANGE, CUSTOMER
from report_ops import worst_margin_fall, kpis, quarter_range
from mojoui.frame import share, Frame, Range
from mojoui.frame_gpu import GpuFrame


def main() raises:
    var n = 2_000_000
    var addr = share(order_columns(n))
    var f = Frame(addr)
    var gf = GpuFrame(addr)
    ref cols = f.base()[].cols
    # the CPU's view: margin by region × heavy × before/after Jul 14
    var rev = List[Int](length=16, fill=0)
    var mar = List[Int](length=16, fill=0)
    var count = List[Int](length=16, fill=0)
    for i in range(n):
        var g = Int(cols[REGION].values[i]) * 4 + (2 if cols[WEIGHT].values[i] > 4000 else 0) + (1 if cols[DAY].values[i] >= YEAR_START + RATE_CHANGE else 0)
        rev[g] += Int(cols[REVENUE].values[i])
        mar[g] += Int(cols[REVENUE].values[i] - cols[COST].values[i] - cols[FREIGHT].values[i])
        count[g] += 1
    var best = -1
    var worst = -1e9
    for b in range(0, 16, 2):
        var fall = Float64(mar[b]) / Float64(rev[b]) - Float64(mar[b + 1]) / Float64(rev[b + 1])
        if fall > worst:
            worst = fall
            best = b
    var a = worst_margin_fall(f, gf)
    assert_equal(a.region, best // 4)
    assert_equal(a.heavy, (best // 2) % 2 == 1)
    assert_equal(a.rows, count[best + 1])
    assert_true(abs(a.points() - worst * 100.0) < 1e-9)
    assert_equal(f.text_of(REGION, Int64(a.region)), "West")
    assert_true(a.heavy)
    assert_true(a.points() >= 5.0, "the West's heavy parcels lose at least 5 points: " + String(a.points()))
    # Q3's KPIs against the CPU
    var q3 = List[Range]()
    q3.append(quarter_range(2))
    var k = kpis(f, gf, q3)
    var r = 0
    var o = 0
    for i in range(n):
        if q3[0].lo <= cols[DAY].values[i] <= q3[0].hi:
            r += Int(cols[REVENUE].values[i])
            o += 1
    assert_equal(k.revenue, r)
    assert_equal(k.orders, o)
    assert_equal(k.customers, 20)
    _ = f.merge(CUSTOMER, [Int64(1), Int64(2)], Int64(0))
    assert_equal(kpis(f, gf, q3).customers, 18)
    print("REPORT: worst fall " + f.text_of(REGION, Int64(a.region)) + (" heavy" if a.heavy else " light") + " " + String(a.points())[byte=0:4] + " points on " + String(a.rows) + " orders; Q3 KPIs = CPU")
    print("REPORT TESTS PASSED")
