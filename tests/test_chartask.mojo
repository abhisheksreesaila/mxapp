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
        f.write("amount,qty,region,product,paid,day\n12.50,3,North,Bolt,true,2025-01-15\n7.25,1,West,Nut,false,2025-02-03\n9.00,2,North,Gear,true,2025-02-20\n"
                + "4.75,5,South,Bolt,false,2025-04-01\n3.10,4,West,Gear,true,2025-06-30\n")
    return Sheet(read_csv(path).table)


def fresh() -> SheetObject:
    return SheetObject.chart(0, 2, 0, 0)  # sum of amount by region, in data order, every region, every row, bars


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
    var base = "Sum of amount by region, in data order, every region, every row, as bars"
    assert_equal(chart_sentence(fresh(), s), base)
    # the spec's words
    check("average", s, "Average of amount by region, in data order, every region, every row, as bars")
    check("mean", s, "Average of amount by region, in data order, every region, every row, as bars")
    check("count", s, "Count of rows by region, in data order, every region, every row, as bars")
    check("how many", s, "Count of rows by region, in data order, every region, every row, as bars")
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
    check("as a line", s, "Sum of amount by region, in data order, every region, every row, as a line")
    check("line chart", s, "Sum of amount by region, in data order, every region, every row, as a line")
    # the table's words
    check("by product", s, "Sum of amount by product, in data order, every product, every row, as bars")
    check("qty", s, "Sum of qty by region, in data order, every region, every row, as bars")
    check("average qty by product", s, "Average of qty by product, in data order, every product, every row, as bars")
    check("paid", s, "Sum of amount by region, in data order, every region, only paid, as bars")
    check("unpaid", s, "Sum of amount by region, in data order, every region, not paid, as bars")
    check("not paid", s, "Sum of amount by region, in data order, every region, not paid, as bars")
    check("only bolt", s, "Sum of amount by region, in data order, every region, only Bolt, as bars")
    check("Gear", s, "Sum of amount by region, in data order, every region, only Gear, as bars")
    # several at once (the owner's examples), any order, punctuation or none
    check("top 3, unpaid, as a line", s, "Sum of amount by region, largest first, top 3, not paid, as a line")
    check("average by region", s, "Average of amount by region, in data order, every region, every row, as bars")
    check("as a line top 3 unpaid", s, "Sum of amount by region, largest first, top 3, not paid, as a line")
    check("Count of rows by product, A to Z", s, "Count of rows by product, A to Z, every product, every row, as bars")
    check("show me the average qty per product, largest first, only paid, as bars", s,
          "Average of qty by product, largest first, every product, only paid, as bars")
    check("count, then qty", s, "Sum of qty by region, in data order, every region, every row, as bars")  # (a column to count reads as its sum)
    # undoing settings by words
    var o = fresh()
    _ = ask(o, s, "top 3, unpaid")
    _ = ask(o, s, "every row, every region, in data order")
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
    # the table's own words come first: a column called Total, a value called Line, a column called Name
    with open("build/test-chartask/clash.csv", "w") as f:
        f.write("total,region,name,product\n5,North,Ann,Line\n7,West,Bob,Bar\n2,North,Cy,Line\n")
    var t = Sheet(read_csv("build/test-chartask/clash.csv").table)
    var clash = SheetObject.chart(0, 1, 0, 0)  # sum of total by region
    var r3 = ask(clash, t, "average total")
    assert_equal(chart_sentence(clash, t), "Average of total by region, in data order, every region, every row, as bars", "“total” is the column")
    _ = ask(clash, t, "Line")
    assert_equal(slot_text(clash, t, SLOT_FILTER), "only Line", "“Line” is a product, not the mark")
    _ = ask(clash, t, "by name")
    assert_equal(chart_sentence(clash, t), "Average of total by name, in data order, every name, only Line, as bars", "“by name” groups by the Name column")
    # an ask that changes nothing says so and lights nothing
    var same = fresh()
    _ = ask(same, s, "top 3")
    var r4 = ask(same, s, "top 3")
    assert_equal(len(r4.changed), 0)
    assert_equal(ask_reply(r4), "Already so: top 3")
    assert_equal(r3.understood[0], "average")
    assert_equal(r3.understood[1], "total")
    # the chart's choices list a filter an ask set on a column too long to list, and picking it keeps it
    from mojoui.sheetpage import chart_choices, apply_choice, chosen, SLOT_FILTER
    var long = fresh()
    long.only_col = 2  # region = (its code 1), set by hand as an ask on a long column would
    long.only_code = 1
    var choices = chart_choices(long, s, SLOT_FILTER)
    assert_equal(choices[chosen(long, s, SLOT_FILTER)], slot_text(long, s, SLOT_FILTER), "the current filter is listed")
    _ = apply_choice(long, s, SLOT_FILTER, len(choices) - 1) if choices[len(choices) - 1] == slot_text(long, s, SLOT_FILTER) else True
    assert_equal(long.only_col, 2, "picking the current filter keeps it")
    # number conditions (goal 29): on the chart's value, or on a column named before them; with a text filter too
    check("over 9", s, "Sum of amount by region, in data order, every region, amount over 9.00, as bars")
    check("amount under 5", s, "Sum of amount by region, in data order, every region, amount under 5.00, as bars")
    check("qty between 2 and 4", s, "Sum of amount by region, in data order, every region, qty between 2 and 4, as bars")
    check("only bolt and more than 4.5", s, "Sum of amount by region, in data order, every region, only Bolt, amount over 4.50, as bars")
    check("qty at least 3", s, "Sum of amount by region, in data order, every region, qty at least 3, as bars")
    check("over 1,000", s, "Sum of amount by region, in data order, every region, amount over 1,000.00, as bars")
    check("over 1k", s, "Sum of amount by region, in data order, every region, amount over 1,000.00, as bars")
    var nums = fresh()
    _ = ask(nums, s, "only bolt, over 9")
    _ = ask(nums, s, "every row")
    assert_equal(chart_sentence(nums, s), base, "every row clears both conditions")
    check("by month", s, "Sum of amount by month of day, in data order, every month, every row, as bars")
    check("monthly, as a line", s, "Sum of amount by month of day, in data order, every month, every row, as a line")
    check("by quarter of day", s, "Sum of amount by quarter of day, in data order, every quarter, every row, as bars")
    check("count by weekday", s, "Count of rows by weekday of day, in data order, every weekday, every row, as bars")
    var months = fresh()
    _ = ask(months, s, "by month")
    _ = ask(months, s, "by region")
    assert_equal(slot_text(months, s, SLOT_FILTER), "every row")
    assert_equal(chart_sentence(months, s), base, "by region after by month: the region's values again")
    check("median", s, "Median of amount by region, in data order, every region, every row, as bars")
    check("90th percentile", s, "p90 of amount by region, in data order, every region, every row, as bars")
    # review round 1 (goal 29): exact amounts, strict words, one number condition, the choice lists
    check("qty under 2.5", s, base)  # (2.5 on a whole-number column: skipped, not rounded)
    var frac = fresh()
    var rf = ask(frac, s, "qty under 2.5")
    assert_true(len(rf.skipped) > 0, "a fraction on a whole-number column is skipped")
    check("over 1.5k", s, "Sum of amount by region, in data order, every region, amount over 1,500.00, as bars")
    check("p95", s, base)  # (only p90 is offered: p95 isn't silently p90)
    var two = fresh()
    var r5 = ask(two, s, "over 5, under 10")
    assert_equal(slot_text(two, s, SLOT_FILTER), "amount over 5.00")
    assert_true("under" in r5.skipped, "a second number condition is skipped and said")
    var named = fresh()  # (review round 2: two conditions naming their columns: the first stays, the second is said skipped)
    var r6 = ask(named, s, "amount over 5, qty under 3")
    assert_equal(slot_text(named, s, SLOT_FILTER), "amount over 5.00")
    assert_true("qty" in r6.skipped and "under" in r6.skipped, "a second named condition is skipped and said")
    var huge = fresh()  # (an amount past what a column can hold is skipped, not wrapped round)
    _ = ask(huge, s, "over 99999999999999999k")
    assert_equal(huge.num_op, 0)
    _ = ask(huge, s, "over 99999999999999")  # (fits as a number, not once scaled to the parse's places)
    assert_true(huge.num_op == 0 or huge.num_lo == 9999999999999900, "a big amount is exact or skipped")
    from mojoui.sheetpage import SLOT_GROUP, SLOT_TOP, PART_WEEKDAY
    var g = fresh()
    var groups = chart_choices(g, s, SLOT_GROUP)  # (text columns, then each date column's month, quarter, weekday)
    var at = -1
    for k in range(len(groups)):
        if groups[k] == "weekday of day":
            at = k
    assert_true(at >= 0, "the group choices offer the date's weekday")
    _ = apply_choice(g, s, SLOT_GROUP, at)
    assert_true(g.part == PART_WEEKDAY and s.name(g.group) == "day")
    assert_equal(groups[chosen(g, s, SLOT_GROUP)], "weekday of day")
    assert_equal(chart_choices(g, s, SLOT_TOP)[0], "every weekday")
    var anyc = fresh()
    _ = ask(anyc, s, "only bolt, over 9")
    var rows = chart_choices(anyc, s, SLOT_FILTER)
    assert_equal(rows[chosen(anyc, s, SLOT_FILTER)], "only Bolt, amount over 9.00", "the combined filter is listed and marked")
    var any_at = -1
    for k in range(len(rows)):
        if rows[k] == "any amount":
            any_at = k
    _ = apply_choice(anyc, s, SLOT_FILTER, any_at)
    assert_equal(slot_text(anyc, s, SLOT_FILTER), "only Bolt", "any amount clears the number condition only")
    print("CHARTASK TESTS PASSED")
