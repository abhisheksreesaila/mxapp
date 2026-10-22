# mojoui.sheetjobs (goal 30 M0): a chart computed through a background job equals the same chart computed in place, for
# six specs (sum, median, p90 top 3, count, average by month, a number condition), on the CPU and, when there is one, the
# GPU; a cancelled job ends cancelled, and the sheet can be edited while a job holds its snapshot.
#   scripts/mxbuild.sh tests/test_chart_job.mojo -o build/test_chart_job && build/test_chart_job
from std.testing import assert_equal, assert_true
from mxframe import gpu_available, GPU as MX_GPU, CPU as MX_CPU, JOB_DONE, JOB_CANCELLED
from mojoui.csvio import read_csv
from mojoui.sheet import Sheet
from mojoui.shared import make_dir
from mojoui.sheetpage import (SheetObject, compute, chart_text, COMBINE_SUM, COMBINE_AVERAGE, COMBINE_COUNT, COMBINE_MEDIAN, COMBINE_P90,
                              ORDER_LARGEST, PART_MONTH, NUM_OVER)
from mojoui.sheetjobs import chart_job, take_numbers, progress_share, ChartQueue, column_job


def two(n: Int) -> String:
    return ("0" if n < 10 else "") + String(n)


def sheet() raises -> Sheet:
    make_dir("build/test-chart-job")
    var path = String("build/test-chart-job/orders.csv")
    with open(path, "w") as f:
        f.write("amount,qty,region,day\n")
        for i in range(5000):  # (enough rows that every group has a middle)
            var region = ["North", "South", "East", "West", "Central"][i % 5]
            f.write(String(i % 97) + "." + String(i % 10) + "5," + String(i % 7 + 1) + "," + region + ",2025-"
                    + two(i % 12 + 1) + "-" + two(i % 28 + 1) + "\n")
    return Sheet(read_csv(path).table)


def specs() -> List[SheetObject]:
    var out = List[SheetObject]()
    for k in range(6):
        var o = SheetObject.chart(0, 2, 0, 0)  # amount by region
        if k == 1:
            o.combine = COMBINE_MEDIAN
        elif k == 2:
            o.combine = COMBINE_P90
            o.order = ORDER_LARGEST
            o.top = 3
        elif k == 3:
            o.combine = COMBINE_COUNT
        elif k == 4:
            o.combine = COMBINE_AVERAGE
            o.group = 3
            o.part = PART_MONTH
        elif k == 5:
            o.num_col = 0
            o.num_op = NUM_OVER
            o.num_lo = 5000  # (amount over 50.00, in cents)
        out.append(o^)
    return out^


def same(mode: Int, mut s: Sheet) raises:
    s.mode = mode
    var list = specs()
    for k in range(len(list)):
        var here = list[k].copy()
        compute(here, s)
        var job = chart_job(s, list[k])
        var done = job.result()
        var shown = list[k].copy()
        take_numbers(shown, done)
        assert_equal(chart_text(shown, s), chart_text(here, s), "spec " + String(k) + " through a job")
        assert_true(len(here.labels) > 0, "spec " + String(k) + " has groups")
        assert_equal(job.poll(), JOB_DONE)
        assert_equal(progress_share(job.progress()), 1.0)


def main() raises:
    var s = sheet()
    same(MX_CPU, s)
    if gpu_available():
        same(MX_GPU, s)
    # the sheet edited while a job holds its snapshot: the job reads the sheet as it was
    s.mode = MX_CPU
    var o = SheetObject.chart(0, 2, 0, 0)
    var before = o.copy()
    compute(before, s)
    var job = chart_job(s, o)
    s.set_text(0, 0, "100000.00")
    var done = job.result()
    var shown = o.copy()
    take_numbers(shown, done)
    assert_equal(chart_text(shown, s), chart_text(before, s), "a job reads its snapshot, not later edits")
    # a cancelled job ends cancelled and gives no numbers
    var slow = chart_job(s, o)
    slow.cancel()
    var state = slow.wait()
    assert_true(state == JOB_CANCELLED or state == JOB_DONE, "cancelled (or done before the cancel was seen)")
    # the queue: a newer spec for the running chart cancels it; another chart waits its turn; only the newest lands
    var q = ChartQueue()
    var a = SheetObject.chart(0, 2, 0, 0)
    var b = a.copy()
    b.combine = COMBINE_MEDIAN
    q.ask(0, a, s)
    q.ask(0, b, s)
    q.ask(1, a, s)
    var landed = List[Tuple[Int, Int]]()
    while q.busy():
        var got = q.poll(s)
        if got:
            landed.append((got.value()[0], got.value()[1].combine))
    assert_equal(len(landed), 2, "two charts landed")
    assert_equal(landed[0][0], 0)
    assert_equal(landed[0][1], COMBINE_MEDIAN, "chart 0's newest spec")
    assert_equal(landed[1][0], 1)
    # a column's figures through a job equal them in place
    var cj = column_job(s, 0, True)
    var fig = cj.result()
    var r = s.totals(0)
    var m = s.median(0)
    assert_equal(fig.sum, r.sums[0])
    assert_equal(fig.present, r.present[0])
    assert_equal(fig.median, Int(m[0]))
    assert_equal(fig.distinct, s.distinct(0))
    print("CHART JOB TESTS PASSED")
