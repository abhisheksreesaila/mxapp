# The Report's anomaly finder and KPIs on the GPU, checked against the same numbers computed here on the CPU.
#   pixi run mojo build -I examples/mxstudio -I . tests/test_report.mojo -o build/test_report && build/test_report
from std.testing import assert_equal, assert_true

from orders import order_columns, DAY, REGION, PRODUCT, REVENUE, COST, FREIGHT, WEIGHT, CARRIER, YEAR_START, RATE_CHANGE, CUSTOMER
from report_ops import worst_margin_fall, kpis, quarter_range, quarter_days, weekly, margin_heatmap, shares, WEEKS
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
    # the cause, found in those rows: Carrier A's freight an order jumped to the flat $14.20
    assert_equal(f.text_of(CARRIER, Int64(a.carrier)), "Carrier A")
    assert_true(abs(a.freight_after - 1420.0) < 1e-9, "after Jul 14 every such parcel pays $14.20: " + String(a.freight_after))
    assert_true(a.freight_before < 700.0)

    # every tile against the CPU, with a region filter and one session edit (the GPU base + the edit's delta)
    f.set(REVENUE, 7, f.get(REVENUE, 7) + 5_000_000)  # +$50,000 on one order
    var west = List[Range]()
    west.append(Range(REGION, 0, 0))
    var wk = weekly(f, gf, west)
    var cpu_rev = List[Int](length=WEEKS, fill=0)
    var cpu_mar = List[Int](length=WEEKS, fill=0)
    var heat_rev = List[Int](length=32, fill=0)
    var heat_mar = List[Int](length=32, fill=0)
    var mix = List[Int](length=8, fill=0)
    var q3 = quarter_range(2)
    for i in range(n):
        var day = Int(f.get(DAY, i))
        var rev = Int(f.get(REVENUE, i))
        var m = rev - Int(f.get(COST, i)) - Int(f.get(FREIGHT, i))
        var region = Int(f.get(REGION, i))
        var product = Int(f.get(PRODUCT, i))
        var w = (day - YEAR_START) // 7
        if region == 0 and w < WEEKS:
            cpu_rev[w] += rev
            cpu_mar[w] += m
        if Int(q3.lo) <= day <= Int(q3.hi):
            heat_rev[region * 8 + product] += rev
            heat_mar[region * 8 + product] += m
            if region == 0:
                mix[product] += rev
    for w in range(WEEKS):
        assert_equal(Int(wk.revenue[w]), cpu_rev[w], "week " + String(w))
        assert_true(abs(wk.margin[w] - Float64(cpu_mar[w]) / Float64(cpu_rev[w])) < 1e-12)
    var in_q3 = List[Range]()
    in_q3.append(q3.copy())
    var hm = margin_heatmap(f, gf, in_q3)
    for i in range(32):
        assert_true(abs(hm.values[i] - Float64(heat_mar[i]) / Float64(heat_rev[i])) < 1e-12, "heat cell " + String(i))
    var west_q3 = List[Range]()
    west_q3.append(q3.copy())
    west_q3.append(Range(REGION, 0, 0))
    var sh = shares(f, gf, PRODUCT, west_q3)
    for p in range(8):
        assert_equal(Int(sh.values[p]), mix[p], "mix " + String(p))
    var kw = kpis(f, gf, west_q3)
    var kr = 0
    var km = 0
    for p in range(8):
        kr += heat_rev[p]
        km += heat_mar[p]
    assert_equal(kw.revenue, kr)
    assert_equal(kw.margin, km)
    # Q4 is to date: its days and the same span of Q3
    assert_equal(quarter_days(3), 16)
    assert_equal(Int(quarter_range(2, 16).hi - quarter_range(2, 16).lo), 15)
    # Q3's KPIs against the CPU
    var q3_only = List[Range]()
    q3_only.append(quarter_range(2))
    var k = kpis(f, gf, q3_only)
    var r = 0
    var o = 0
    for i in range(n):
        if q3_only[0].lo <= f.get(DAY, i) <= q3_only[0].hi:  # (through the frame: the session's edit counts)
            r += Int(f.get(REVENUE, i))
            o += 1
    assert_equal(k.revenue, r)
    assert_equal(k.orders, o)
    assert_equal(k.customers, 20)
    _ = f.merge(CUSTOMER, [Int64(1), Int64(2)], Int64(0))
    assert_equal(kpis(f, gf, q3_only).customers, 18)
    print("REPORT: worst fall " + f.text_of(REGION, Int64(a.region)) + (" heavy" if a.heavy else " light") + " " + String(a.points())[byte=0:4] + " points on " + String(a.rows) + " orders; Q3 KPIs = CPU")
    print("REPORT TESTS PASSED")
