# The planted-story orders data: every planted problem is there, with exact counts.
#   pixi run mojo build -I examples/mxstudio -I . tests/test_orders.mojo -o build/test_orders && build/test_orders
from std.testing import assert_equal, assert_true

from orders import (order_columns, ORDER, DAY, CUSTOMER, PRODUCT, CARRIER, ZIP, WEIGHT, REVENUE, COST, FREIGHT,
                    YEAR_START, RATE_CHANGE, DUPLICATES, DUP_ZIP, FLAT_FREIGHT)
from mojoui.frame import share, Frame
from std.collections import Dict


def main() raises:
    var n = 2_000_000
    var f = Frame(share(order_columns(n)))
    assert_equal(f.rows(), n)
    ref cols = f.base()[].cols
    # 1. Acme under three spellings
    var spell = List[Int](length=20, fill=0)
    for i in range(n):
        spell[Int(cols[CUSTOMER].values[i])] += 1
    assert_equal(cols[CUSTOMER].dictionary[0], "Acme Corp")
    assert_equal(cols[CUSTOMER].dictionary[1], "Acme Corp.")
    assert_equal(cols[CUSTOMER].dictionary[2], "ACME Corporation")
    assert_true(spell[0] > 0 and spell[1] > 0 and spell[2] > 0)
    var acme = spell[0] + spell[1] + spell[2]
    var top_other = 0
    for c in range(3, 20):
        top_other = max(top_other, spell[c])
    assert_true(spell[0] < top_other, "split, Acme isn't the top customer")
    assert_true(acme > top_other, "merged, Acme is the top customer")
    # 2. Carrier A's v7: exactly the heavy carrier-A parcels from Jul 14 pay $14.20; none before
    var flat_after = 0
    var flat_before = 0
    var heavy_a_after = 0
    for i in range(n):
        var day = Int(cols[DAY].values[i]) - YEAR_START
        var heavy_a = cols[CARRIER].values[i] == 0 and cols[WEIGHT].values[i] > 4000
        if heavy_a and day >= RATE_CHANGE:
            heavy_a_after += 1
        if cols[FREIGHT].values[i] == FLAT_FREIGHT:
            if day >= RATE_CHANGE:
                flat_after += 1
            else:
                flat_before += 1
    assert_equal(flat_before, 0)
    assert_equal(flat_after, heavy_a_after)
    # 3. Q3's gross margin ~3 points below Q2's
    var rev = List[Int](length=4, fill=0)
    var margin = List[Int](length=4, fill=0)
    for i in range(n):
        var day = Int(cols[DAY].values[i]) - YEAR_START
        var q = 0 if day < 90 else (1 if day < 181 else (2 if day < 273 else 3))
        rev[q] += Int(cols[REVENUE].values[i])
        margin[q] += Int(cols[REVENUE].values[i] - cols[COST].values[i] - cols[FREIGHT].values[i])
    var q2 = Float64(margin[1]) / Float64(rev[1]) * 100
    var q3 = Float64(margin[2]) / Float64(rev[2]) * 100
    print("MARGIN: Q2 " + String(q2)[byte=0:5] + "% → Q3 " + String(q3)[byte=0:5] + "% (" + String(q2 - q3)[byte=0:4] + " points)")
    assert_true(2.0 <= q2 - q3 <= 4.0, "Q3 margin falls about 3 points")
    # 4. 412 orders twice, all at ZIP 94110, and nothing else at that ZIP
    var seen = Dict[Int, Int]()
    var twice = 0
    var at_zip = 0
    for i in range(n):
        var o = Int(cols[ORDER].values[i])
        if o in seen:
            twice += 1
            assert_equal(Int(cols[ZIP].values[i]), DUP_ZIP)
        seen[o] = i
        if cols[ZIP].values[i] == DUP_ZIP:
            at_zip += 1
    assert_equal(twice, DUPLICATES)
    assert_equal(at_zip, 2 * DUPLICATES)
    print("ORDERS: " + String(n) + " rows; Acme " + String(acme) + " under 3 spellings; " + String(flat_after) +
          " parcels at the flat $14.20 from Jul 14; " + String(twice) + " duplicates at ZIP 94110")
    print("ORDERS TESTS PASSED")
