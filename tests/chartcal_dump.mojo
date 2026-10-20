# Goal 29 M3: charts by a date's month, quarter and weekday over a file, each chart's text printed (what an agent reads), for scripts/check to hold
# against pyarrow. The file's columns are omxplorer's small.parquet: order, amount, region, day, paid.
#   scripts/mxbuild.sh tests/chartcal_dump.mojo -o build/chartcal_dump && build/chartcal_dump build/g20/small.parquet
from std.sys import argv
from mojoui.csvio import read_table
from mojoui.sheet import Sheet
from mojoui.sheetpage import (SheetObject, compute, chart_text, COMBINE_SUM, COMBINE_AVERAGE, COMBINE_COUNT, COMBINE_MEDIAN, COMBINE_P90, PART_MONTH, PART_QUARTER, PART_WEEKDAY, ORDER_TABLE, ORDER_LARGEST,
                              ORDER_SMALLEST, ORDER_AZ)


def spec(combine: Int, order: Int, top: Int, only_col: Int = -1, only_code: Int = 0) -> SheetObject:
    var o = SheetObject.chart(1, 2, 0, 0)  # amount by region
    o.combine = combine
    o.order = order
    o.top = top
    o.only_col = only_col
    o.only_code = only_code
    return o^


def cal(var o: SheetObject, part: Int) -> SheetObject:
    o.group = 3  # (day)
    o.part = part
    return o^


def main() raises:
    var imp = read_table(String(argv()[1]))
    var sheet = Sheet(imp.table)
    var specs: List[SheetObject] = [
        cal(spec(COMBINE_SUM, ORDER_TABLE, 0), PART_MONTH), cal(spec(COMBINE_COUNT, ORDER_TABLE, 0), PART_QUARTER),
        cal(spec(COMBINE_AVERAGE, ORDER_TABLE, 0), PART_WEEKDAY), cal(spec(COMBINE_MEDIAN, ORDER_TABLE, 0, 4, 1), PART_MONTH),
    ]
    for k in range(len(specs)):
        compute(specs[k], sheet)
        print("SPEC " + String(k))
        print(chart_text(specs[k], sheet))
    print("END")
