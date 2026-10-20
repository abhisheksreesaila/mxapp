# mojoui.chartask (goal 28 M2): phrases that edit a chart's spec, on a small table read from CSV (amount, qty,
# region, product, paid: true/false → Yes/No). Each phrase: the spec it leaves, what it understood, what it skipped.
#   scripts/mxbuild.sh tests/test_chartask.mojo -o build/test_chartask && build/test_chartask
from std.testing import assert_equal, assert_true
from mojoui.csvio import read_csv
from mojoui.sheet import Sheet
from mojoui.shared import make_dir
from mojoui.sheetpage import (SheetObject, slot_text, chart_sentence, COMBINE_SUM, COMBINE_AVERAGE, COMBINE_COUNT, ORDER_TABLE, ORDER_LARGEST,
                              ORDER_SMALLEST, ORDER_AZ, CHART_BAR, CHART_LINE, SLOT_TOP, SLOT_FILTER, SLOT_MARK, SLOT_ORDER)
from mojoui.chartask import ask, ask_reply


def sheet() raises -> Sheet:
    make_dir("build/test-chartask")
    var path = String("build/test-chartask/orders.csv")
    with open(path, "w") as f:
        f.write("amount,qty,region,product,paid\n12.50,3,North,Bolt,true\n7.25,1,West,Nut,false\n9.00,2,North,Gear,true\n"
                + "4.75,5,South,Bolt,false\n3.10,4,West,Gear,true\n")
    return Sheet(read_csv(path).table)


def fresh() -> SheetObject:
    return SheetObject.chart(0, 2, 0, 0)  # sum of amount by region, as in the table, every region, every row, bars


def said(phrase: String, s: Sheet) -> String:
    """The chart's sentence after the phrase, then what the field said."""
    var o = fresh()
    var r = ask(o, s, phrase)
    return chart_sentence(o, s) + " | " + ask_reply(r)


def check(phrase: String, s: Sheet, sentence: String) raises:
    var o = fresh()
    _ = ask(o, s, phrase)
    assert_equal(chart_sentence(o, s), sentence, "“" + phrase + "”")


def main() raises:
    var s = sheet()
    var base = "Sum of amount by region, as in the table, every region, every row, as bars"
    assert_equal(chart_sentence(fresh(), s), base)
    # the spec's words
    check("average", s, "Average of amount by region, as in the table, every region, every row, as bars")
    check("mean", s, "Average of amount by region, as in the table, every region, every row, as bars")
    check("count", s, "Count of rows by region, as in the table, every region, every row, as bars")
    check("how many", s, "Count of rows by region, as in the table, every region, every row, as bars")
    check("total", s, base)
    check("largest first", s, "Sum of amount by region, largest first, every region, every row, as bars")
    check("biggest", s, "Sum of amount by region, largest first, every region, every row, as bars")
    check("smallest first", s, "Sum of amount by region, smallest first, every region, every row, as bars")
    check("ascending", s, "Sum of amount by region, smallest first, every region, every row, as bars")
    check("a to z", s, "Sum of amount by region, A to Z, every region, every row, as bars")
    check("alphabetical", s, "Sum of amount by region, A to Z, every region, every row, as bars")
    check("top 3", s, "Sum of amount by region, largest first, top 3, every row, as bars")
    check("top three", s, "Sum of amount by region, largest first, top 3, every row, as bars")
    check("bottom 2", s, "Sum of amount by region, smallest first, top 2, every row, as bars")
    check("top 2 smallest first", s, "Sum of amount by region, smallest first, top 2, every row, as bars")
    check("as a line", s, "Sum of amount by region, as in the table, every region, every row, as a line")
    check("line chart", s, "Sum of amount by region, as in the table, every region, every row, as a line")
    # the table's words
    check("by product", s, "Sum of amount by product, as in the table, every product, every row, as bars")
    check("qty", s, "Sum of qty by region, as in the table, every region, every row, as bars")
    check("average qty by product", s, "Average of qty by product, as in the table, every product, every row, as bars")
    check("paid", s, "Sum of amount by region, as in the table, every region, only paid, as bars")
    check("unpaid", s, "Sum of amount by region, as in the table, every region, not paid, as bars")
    check("not paid", s, "Sum of amount by region, as in the table, every region, not paid, as bars")
    check("only bolt", s, "Sum of amount by region, as in the table, every region, only Bolt, as bars")
    check("Gear", s, "Sum of amount by region, as in the table, every region, only Gear, as bars")
    # several at once (the owner's examples), any order, punctuation or none
    check("top 3, unpaid, as a line", s, "Sum of amount by region, largest first, top 3, not paid, as a line")
    check("average by region", s, "Average of amount by region, as in the table, every region, every row, as bars")
    check("as a line top 3 unpaid", s, "Sum of amount by region, largest first, top 3, not paid, as a line")
    check("Count of rows by product, A to Z", s, "Count of rows by product, A to Z, every product, every row, as bars")
    check("show me the average qty per product, largest first, only paid, as bars", s,
          "Average of qty by product, largest first, every product, only paid, as bars")
    check("count, then qty", s, "Sum of qty by region, as in the table, every region, every row, as bars")  # (a column to count reads as its sum)
    # undoing settings by words
    var o = fresh()
    _ = ask(o, s, "top 3, unpaid")
    _ = ask(o, s, "every row, every region, as in the table")
    assert_equal(chart_sentence(o, s), base, "words put settings back")
    # what it says, what it skips, and nothing changes when it understood nothing
    assert_equal(said("top 3 please, bananas", s), "Sum of amount by region, largest first, top 3, every row, as bars | Took top 3; skipped “bananas”")
    var before = fresh()
    var r = ask(before, s, "bananas and apples")
    assert_equal(chart_sentence(before, s), base, "nothing understood: nothing changed")
    assert_true(ask_reply(r).startswith("Didn't understand"))
    var c = fresh()
    var r2 = ask(c, s, "top 3, unpaid, as a line")
    assert_equal(len(r2.changed), 4, "top, order, filter and mark changed")
    var flagged = 0
    for slot in r2.changed:
        if slot == SLOT_TOP or slot == SLOT_FILTER or slot == SLOT_MARK or slot == SLOT_ORDER:
            flagged += 1
    assert_equal(flagged, 4)
    print("CHARTASK TESTS PASSED")
