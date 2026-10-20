# Goal 29 M2: charts with number conditions over a file, each chart's text printed (what an agent reads), for scripts/check to hold
# against pyarrow. The file's columns are omxplorer's small.parquet: order, amount, region, day, paid.
#   scripts/mxbuild.sh tests/chartnum_dump.mojo -o build/chartnum_dump && build/chartnum_dump build/g20/small.parquet
from std.sys import argv
from mojoui.csvio import read_table
from mojoui.sheet import Sheet
from mojoui.sheetpage import (SheetObject, compute, chart_text, COMBINE_SUM, COMBINE_AVERAGE, COMBINE_COUNT, COMBINE_MEDIAN, COMBINE_P90, NUM_OVER, NUM_UNDER, NUM_BETWEEN, NUM_AT_LEAST, NUM_AT_MOST, ORDER_TABLE, ORDER_LARGEST,
                              ORDER_SMALLEST, ORDER_AZ)


def spec(combine: Int, order: Int, top: Int, only_col: Int = -1, only_code: Int = 0) -> SheetObject:
    var o = SheetObject.chart(1, 2, 0, 0)  # amount by region
    o.combine = combine
    o.order = order
    o.top = top
    o.only_col = only_col
    o.only_code = only_code
    return o^


def num(var o: SheetObject, op: Int, lo: Int, hi: Int) -> SheetObject:
    o.num_col = 1  # (amount, in cents)
    o.num_op = op
    o.num_lo = lo
    o.num_hi = hi
    return o^


def main() raises:
    var imp = read_table(String(argv()[1]))
    var sheet = Sheet(imp.table)
    var specs: List[SheetObject] = [
        num(spec(COMBINE_SUM, ORDER_TABLE, 0), NUM_OVER, 500000, 0), num(spec(COMBINE_COUNT, ORDER_TABLE, 0), NUM_UNDER, 0, 100000),
        num(spec(COMBINE_AVERAGE, ORDER_TABLE, 0), NUM_BETWEEN, 200000, 400000), num(spec(COMBINE_SUM, ORDER_TABLE, 0, 4, 1), NUM_OVER, 500000, 0),
        num(spec(COMBINE_MEDIAN, ORDER_TABLE, 0), NUM_AT_LEAST, 500000, 0),
    ]
    for k in range(len(specs)):
        compute(specs[k], sheet)
        print("SPEC " + String(k))
        print(chart_text(specs[k], sheet))
    print("END")
