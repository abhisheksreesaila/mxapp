# Goal 29 M4: what a chart costs: a sum by region (goal 28's), a median by region and a sum by month of a date, at the
# file's size (opened as omxplorer opens it: streamed when it's bigger than memory allows). Best of three each.
#   scripts/mxbuild.sh tests/chartbench.mojo -o build/chartbench && build/chartbench build/g20/big.parquet
from std.sys import argv
from std.time import perf_counter_ns
from mojoui.csvio import read_table
from mojoui.sheet import Sheet
from mojoui.sheetpage import SheetObject, compute, COMBINE_SUM, COMBINE_MEDIAN, PART_MONTH


def best(mut o: SheetObject, sheet: Sheet) raises -> Float64:
    var top = 1.0e18
    for _ in range(3):
        var t0 = perf_counter_ns()
        compute(o, sheet)
        top = min(top, Float64(perf_counter_ns() - t0) / 1.0e6)
    return top


def main() raises:
    var imp = read_table(String(argv()[1]))
    var sheet = Sheet(imp.scan.value()) if imp.streamed() else Sheet(imp.table)
    var value = sheet.index("amount") if sheet.index("amount") >= 0 else sheet.index("revenue")  # (by name: the files differ)
    var region = sheet.index("region")
    var day = sheet.index("day")
    var sums = SheetObject.chart(value, region, 0, 0)
    var medians = SheetObject.chart(value, region, 0, 0)
    medians.combine = COMBINE_MEDIAN
    var months = SheetObject.chart(value, day, 0, 0)
    months.part = PART_MONTH
    var a = best(sums, sheet)
    var b = best(medians, sheet)
    var c = best(months, sheet)
    print("BENCH rows=" + String(sheet.rows()) + " streamed=" + String(imp.streamed()) + " sum_ms=" + String(a) + " median_ms=" + String(b) + " month_ms=" + String(c))
