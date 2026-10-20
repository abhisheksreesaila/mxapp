# Goal 28 M0: twelve chart specs over a file, each chart's text printed (what an agent reads), for scripts/check to hold
# against pyarrow. The file's columns are omxplorer's small.parquet: order, amount, region, day, paid.
#   scripts/mxbuild.sh tests/chartspec_dump.mojo -o build/chartspec_dump && build/chartspec_dump build/g20/small.parquet
from std.sys import argv
from mojoui.csvio import read_table
from mojoui.sheet import Sheet
from mojoui.sheetpage import (SheetObject, compute, chart_text, COMBINE_SUM, COMBINE_AVERAGE, COMBINE_COUNT, ORDER_TABLE, ORDER_LARGEST,
                              ORDER_SMALLEST, ORDER_AZ)


def spec(combine: Int, order: Int, top: Int, only_col: Int = -1, only_code: Int = 0) -> SheetObject:
    var o = SheetObject.chart(1, 2, 0, 0)  # amount by region
    o.combine = combine
    o.order = order
    o.top = top
    o.only_col = only_col
    o.only_code = only_code
    return o^


def main() raises:
    var imp = read_table(String(argv()[1]))
    var sheet = Sheet(imp.table)
    var specs: List[SheetObject] = [
        spec(COMBINE_SUM, ORDER_TABLE, 0), spec(COMBINE_AVERAGE, ORDER_TABLE, 0), spec(COMBINE_COUNT, ORDER_TABLE, 0),
        spec(COMBINE_SUM, ORDER_LARGEST, 0), spec(COMBINE_SUM, ORDER_SMALLEST, 0), spec(COMBINE_SUM, ORDER_AZ, 0),
        spec(COMBINE_SUM, ORDER_LARGEST, 3), spec(COMBINE_AVERAGE, ORDER_SMALLEST, 2), spec(COMBINE_COUNT, ORDER_TABLE, 0, 4, 0),
        spec(COMBINE_SUM, ORDER_LARGEST, 0, 4, 1), spec(COMBINE_AVERAGE, ORDER_AZ, 5, 4, 1), spec(COMBINE_COUNT, ORDER_LARGEST, 3, 4, 0),
    ]
    for k in range(len(specs)):
        compute(specs[k], sheet)
        print("SPEC " + String(k))
        print(chart_text(specs[k], sheet))
    print("END")
