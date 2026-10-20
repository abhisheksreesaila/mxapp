# Goal 29 M3: a chart by a date's month, quarter or weekday reads every date right, before 1970 too and across a year's
# end: the engine's key (calendar_key, civil-from-days in whole numbers) against numformat's civil(), date by date.
#   scripts/mxbuild.sh tests/test_calendar.mojo -o build/test_calendar && build/test_calendar
from std.testing import assert_equal
from mojoui.csvio import read_csv
from mojoui.sheet import Sheet
from mojoui.omxfile import read_spec
from mojoui.json import Json
from mojoui.sheetpage import SheetObject, compute, chart_text, COMBINE_COUNT, ORDER_TABLE, PART_MONTH, PART_QUARTER, PART_WEEKDAY

comptime CSV = "build/test_calendar.csv"
comptime FAR = "build/test_calendar_far.csv"


def by(sheet: Sheet, part: Int) raises -> String:
    var o = SheetObject.chart(1, 0, 0, 0)  # count of amount by day
    o.combine = COMBINE_COUNT
    o.order = ORDER_TABLE
    o.part = part
    compute(o, sheet)
    var text = chart_text(o, sheet)
    var lines = text.split("\n")
    var out = String("")
    for k in range(1, len(lines)):  # (the first line is the sentence)
        out += String(lines[k]) + ";"
    return out


def main() raises:
    with open(CSV, "w") as f:
        f.write("day,amount\n1969-10-05,1\n1969-12-31,2\n1970-01-01,4\n1970-03-01,8\n1969-12-01,16\n")
    var s = Sheet(read_csv(CSV).table, False)
    # (every month of the span, the empty ones too; 1969-12-31 is a Wednesday, 1970-01-01 a Thursday)
    assert_equal(by(s, PART_MONTH), "Oct 1969\t1;Nov 1969\t0;Dec 1969\t2;Jan 1970\t1;Feb 1970\t0;Mar 1970\t1;")
    assert_equal(by(s, PART_QUARTER), "Q4 1969\t3;Q1 1970\t2;")
    assert_equal(by(s, PART_WEEKDAY), "Mon\t1;Tue\t0;Wed\t1;Thu\t1;Fri\t0;Sat\t0;Sun\t2;")
    # a document's part on a date group opens as saved; past weekday (3) it's refused
    var o = SheetObject.chart(1, 0, 0, 0)
    read_spec(Json.parse('{"part": 2}'), 0, o, s)
    assert_equal(o.part, PART_QUARTER)
    read_spec(Json.parse('{"part": 4}'), 0, o, s)
    assert_equal(o.part, 0)
    with open(FAR, "w") as f:
        f.write("day,amount\n1900-01-01,1\n1600-03-01,2\n1600-02-29,4\n2400-02-29,8\n")
    var far = Sheet(read_csv(FAR).table, False)
    # (centuries away: 1900-01-01 Mon, 1600-02-29 Tue, 1600-03-01 Wed, 2400-02-29 Tue; Python's datetime agrees)
    assert_equal(by(far, PART_WEEKDAY), "Mon\t1;Tue\t2;Wed\t1;Thu\t0;Fri\t0;Sat\t0;Sun\t0;")
    print("CALENDAR TESTS PASSED")
