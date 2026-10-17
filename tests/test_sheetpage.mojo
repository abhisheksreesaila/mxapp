# mojoui.sheetpage and mojoui.reportpage on their own: a chart's and a pivot's GPU sums against a CPU pass (with an
# edit), the readout in the column's format, free-space placement, and a Report tile through a filter.
#   pixi run mojo build -I . tests/test_sheetpage.mojo -o build/test_sheetpage && build/test_sheetpage
from std.testing import assert_equal, assert_true
from mojoui.frame import Frame, Range, share, TEXT, DECIMAL
from mojoui.frame_gpu import GpuFrame
from mojoui.orders import order_columns, REGION, PRODUCT, REVENUE, CARRIER
from mojoui.numformat import ColumnFormat, CURRENCY
from mojoui.sheetpage import SheetObject, compute, readout, free_spot, chart_view, OBJ_CHART, OBJ_PIVOT, CHART_LINE
from mojoui.reportpage import ReportFilter, new_tile, compute_tile, tile_value, TILE_SUM, TILE_AVERAGE, TILE_COUNT, TILE_CHART


def cpu_sums(frame: Frame, group: Int, value: Int, across: Int = -1, n_across: Int = 1, only: Int = -1, only_code: Int = 0) -> List[Int]:
    var ng = len(frame.base()[].cols[group].dictionary) + len(frame.words[group])
    var out = List[Int](length=ng * n_across, fill=0)
    for r in range(frame.rows()):
        if not frame.alive(r):
            continue
        if only >= 0 and Int(frame.get(only, r)) != only_code:
            continue
        var g = Int(frame.get(group, r))
        var a = Int(frame.get(across, r)) if across >= 0 else 0
        out[g * n_across + a] += Int(frame.get(value, r))
    return out^


def main() raises:
    var frame = Frame(share(order_columns(200_000)))
    frame.set_text(REVENUE, 0, "99999.99")  # an edit the GPU's copy doesn't have: added as a delta
    var gf = GpuFrame(frame.base_addr)

    # a chart: revenue by region
    var chart = SheetObject.chart(REVENUE, REGION, 0, 416)
    compute(chart, frame, gf)
    var want = cpu_sums(frame, REGION, REVENUE)
    assert_equal(len(chart.sums), len(want))
    for k in range(len(want)):
        assert_equal(chart.sums[k], want[k])
    assert_equal(chart.labels[0], frame.text_of(REGION, 0))
    assert_equal(readout(chart, frame), "Tap a bar to read it")
    frame.set_format(REVENUE, ColumnFormat(CURRENCY, 2, True, False, "$"))
    chart.selected = 1
    assert_equal(readout(chart, frame), chart.labels[1] + " · " + frame.format_value(REVENUE, Int64(want[1]), total=True))
    assert_true(readout(chart, frame).find(" · $") > 0, "the readout is in the column's format")
    chart.style = CHART_LINE
    assert_equal(chart_view(chart, frame).kind, "Line Chart")

    # a pivot: revenue by region × product
    var np = len(frame.base()[].cols[PRODUCT].dictionary)
    var pivot = SheetObject.pivot(REVENUE, REGION, PRODUCT, 536, 416)
    compute(pivot, frame, gf)
    var cells = cpu_sums(frame, REGION, REVENUE, PRODUCT, np)
    assert_equal(len(pivot.cols), np)
    for k in range(len(cells)):
        assert_equal(pivot.sums[k], cells[k])

    # placement: beside an object when it fits, else below everything
    var placed = List[SheetObject]()
    placed.append(SheetObject.chart(REVENUE, REGION, 0, 416, 520, 340))
    var spot = free_spot(placed, 400, 1084, 548, 340)
    assert_equal(spot[0], 536)
    assert_equal(spot[1], 416)
    placed.append(SheetObject.pivot(REVENUE, REGION, PRODUCT, 536, 416, 548, 340))
    spot = free_spot(placed, 400, 1084, 520, 340)
    assert_equal(spot[0], 0)
    assert_equal(spot[1], 772)

    # a Report tile through a filter (region = the first region)
    var filter = ReportFilter(REGION, 0)
    var sum = new_tile(TILE_SUM, REVENUE, -1)
    var count = new_tile(TILE_COUNT, REVENUE, -1)
    var avg = new_tile(TILE_AVERAGE, REVENUE, -1)
    var bars = new_tile(TILE_CHART, REVENUE, CARRIER)
    compute_tile(sum, frame, gf, filter)
    compute_tile(count, frame, gf, filter)
    compute_tile(avg, frame, gf, filter)
    compute_tile(bars, frame, gf, filter)
    var region0 = cpu_sums(frame, REGION, REVENUE)[0]
    var rows0 = 0
    for r in range(frame.rows()):
        if Int(frame.get(REGION, r)) == 0:
            rows0 += 1
    assert_equal(sum.total, region0)
    assert_equal(count.count, rows0)
    assert_equal(tile_value(sum, frame), frame.format_value(REVENUE, Int64(region0), total=True))
    var by_carrier = cpu_sums(frame, CARRIER, REVENUE, only=REGION, only_code=0)
    for k in range(len(by_carrier)):
        assert_equal(bars.chart.sums[k], by_carrier[k])
    assert_equal(filter.words(frame), "region = " + frame.text_of(REGION, 0))
    print("SHEETPAGE TESTS PASSED")
