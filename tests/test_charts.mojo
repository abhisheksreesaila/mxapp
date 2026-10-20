# Charts. Run: pixi run mojo run -I . tests/test_charts.mojo (writes build/chart-*.png to look at)
from std.testing import assert_equal, assert_true

from mojoui import Surface, rgba
from mojoui.text import Font
from mojoui.png import encode_png
from mojoui.charts import thin_labels, KpiTile, BarChart, LineChart, ColumnChart, money, axis_money, compact, nice_max, grouped, BRAND, CARD_BG


def save(px: List[UInt32], w: Int, h: Int, name: String) raises:
    var png = encode_png(px, w, h)
    with open("build/chart-" + name + ".png", "w") as f:
        f.write_bytes(Span(png))


def main() raises:
    # numbers
    assert_equal(money(124_000_000_00), "$124M")
    assert_equal(money(1_240_000_000_00), "$1.24B")
    assert_equal(money(12_345_00), "$12.3K")
    assert_equal(money(940_00), "$940")
    assert_equal(compact(4_512_903), "4.51M")
    assert_equal(grouped(4_512_903), "4,512,903")
    assert_equal(nice_max(87.0), 100.0)
    assert_equal(axis_money(500_000_000), "$5M")
    assert_equal(axis_money(250_000_000), "$2.5M")
    assert_equal(nice_max(212.0), 250.0)
    var font = Font()
    var k = 1.6

    # KPI tile
    var w = Int(260 * k)
    var h = Int(118 * k)
    var px = List[UInt32](length=w * h, fill=0)
    var s = Surface(Int(px.unsafe_ptr()), w, h, k)
    KpiTile("Revenue", "$1.24B", "+12.4% vs last year", [3.0, 4, 3.5, 5, 6, 5.5, 7, 8, 7.5, 9], accent=True).draw(s, font)
    assert_equal(s.get(w // 2, h // 2) & 0xFFFFFF, BRAND & 0xFFFFFF)  # the focal tile is brand blue
    save(px, w, h, "kpi")

    # bars: proportional, selection, hit-test
    w = Int(420 * k)
    h = Int(240 * k)
    px = List[UInt32](length=w * h, fill=0)
    s = Surface(Int(px.unsafe_ptr()), w, h, k)
    var bars = BarChart(["Electronics", "Home", "Outdoor", "Toys"], [400.0, 200.0, 100.0, 50.0], ["$400M", "$200M", "$100M", "$50M"], selected=1)
    bars.draw(s, font)
    assert_equal(bars.hit(240, 10), 0)
    assert_equal(bars.hit(240, 130), 2)
    assert_equal(bars.hit(240, 239), 3)
    assert_equal(bars.hit(240, -1), -1)
    # bar lengths: count brand-ish pixels along each row's centre
    var lengths = List[Int]()
    for i in range(4):
        var y = Int(Float64(h) * (Float64(i) + 0.5) / 4.0)
        var n = 0
        for x in range(w):
            var c = s.get(x, y)
            if (c & 0xFF) < 210 and ((c >> 16) & 0xFF) > 150:  # blue or blue tint
                n += 1
        lengths.append(n)
    assert_true(abs(Float64(lengths[0]) / Float64(lengths[1]) - 2.0) < 0.1, "bar 0 is twice bar 1")
    save(px, w, h, "bars")

    # line: hit-test nearest month
    w = Int(560 * k)
    h = Int(240 * k)
    px = List[UInt32](length=w * h, fill=0)
    s = Surface(Int(px.unsafe_ptr()), w, h, k)
    var labels = List[String]()
    var values = List[Float64]()
    for m in range(36):
        labels.append(("Jan " + String(23 + m // 12)) if m % 12 == 0 else ("Jul" if m % 12 == 6 else ""))
        values.append(Float64(100_000_000 + m * 4_000_000 + (60_000_000 if m % 12 >= 10 else 0)))
    var lc = LineChart(labels^, values^, selected=22)
    lc.draw(s, font)
    var first = lc.hit(Float64(w), Float64(h), k, font, 0)
    var last = lc.hit(Float64(w), Float64(h), k, font, 559)
    assert_equal(last, 35)
    assert_true(first == 0 or first == -1)
    save(px, w, h, "line")

    # columns
    w = Int(300 * k)
    h = Int(220 * k)
    px = List[UInt32](length=w * h, fill=0)
    s = Surface(Int(px.unsafe_ptr()), w, h, k)
    var cols = ColumnChart(["North", "South", "East", "West", "Central"], [5.0, 3, 4, 2, 1], ["$5M", "$3M", "$4M", "$2M", "$1M"], selected=-1)
    cols.draw(s, font)
    assert_equal(cols.hit(300, 10), 0)
    assert_equal(cols.hit(300, 290), 4)
    save(px, w, h, "columns")
    _ = len(px)
    # x labels never touch: 12 month labels 60 px wide, 30 px apart: every 3rd, and the last only if it clears (goal 29)
    var xs = List[Float64]()
    var ws = List[Float64]()
    for m in range(12):
        xs.append(Float64(m) * 30.0)
        ws.append(60.0)
    var shown = thin_labels(ws, xs, 8.0)
    assert_equal(len(shown), 4)
    assert_true(shown[0] == 0 and shown[1] == 3 and shown[2] == 6 and shown[3] == 9, "every 3rd; Dec doesn't fit after Oct")
    var wide = List[Float64]()
    for m in range(12):
        wide.append(12.0)
    assert_equal(len(thin_labels(wide, xs, 8.0)), 12, "labels that fit are all drawn")
    print("CHARTS TESTS PASSED")
