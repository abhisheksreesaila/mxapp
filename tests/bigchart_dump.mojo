# Goal 30 M1: the charts omxplorer computes in the background at 100M rows, computed here in place, for scripts/check to
# compare with what the app shows: median amount by region, median amount by month of day (asked after it), and the amount column's sum.
# The file's columns are goal 20's big.parquet: order, amount, region, day, paid.
#   scripts/mxbuild.sh tests/bigchart_dump.mojo -o build/bigchart_dump && build/bigchart_dump build/g20/big.parquet
from std.sys import argv
from std.time import perf_counter_ns
from mojoui.csvio import read_table
from mojoui.sheet import Sheet
from mojoui.sheetpage import SheetObject, compute, chart_text, COMBINE_MEDIAN, PART_MONTH


def main() raises:
    var imp = read_table(String(argv()[1]))
    var sheet = Sheet(imp.table)
    var med = SheetObject.chart(1, 2, 0, 0)
    med.combine = COMBINE_MEDIAN
    compute(med, sheet)
    print("CHART median\n" + chart_text(med, sheet).replace("\t", " | "))
    var month = SheetObject.chart(1, 3, 0, 0)
    month.part = PART_MONTH
    month.combine = COMBINE_MEDIAN
    var t0 = perf_counter_ns()
    compute(month, sheet)
    print("MONTH_MS " + String(Float64(perf_counter_ns() - t0) / 1e6))
    print("CHART month\n" + chart_text(month, sheet).replace("\t", " | "))
    var r = sheet.totals(1)
    print("SUM " + sheet.format_value(1, Int64(r.sums[0]), total=True))
    print("END")
