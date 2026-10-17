# Frame: typed columns, formulas with a dependency graph, edits, tombstones, sort permutation, undo.
# Run: pixi run mojo run -I . tests/test_frame.mojo
from std.testing import assert_equal, assert_true, assert_false
from mojoui.frame import (Column, Columns, Frame, Range, share, INT, DECIMAL, TEXT, DATE, date_text, parse_date,
                          decimal_text, parse_decimal, OP_COL)


def sample() -> Int:
    var cols = Columns()
    var product = Column("product", TEXT)
    product.dictionary = ["Chair", "Desk", "Lamp"]
    product.values = [0, 1, 2, 0, 1]
    cols.add(product^)
    var qty = Column("quantity", INT)
    qty.values = [2, 1, 4, 3, 2]
    cols.add(qty^)
    var cents = Column("cents", DECIMAL, 2)
    cents.values = [5000, 12000, 1500, 5000, 12000]
    cols.add(cents^)
    var cost = Column("cost", DECIMAL, 2)
    cost.values = [3000, 7000, 500, 3000, 7000]
    cols.add(cost^)
    var day = Column("day", DATE)
    day.values = [19723, 19724, 19724, 19725, 19800]  # 2024-01-01 …
    cols.add(day^)
    return share(cols^)


def main() raises:
    # dates and decimals
    assert_equal(date_text(19723), "2024-01-01")
    assert_equal(parse_date("2024-07-01"), Int64(19905))
    assert_equal(date_text(parse_date("1999-12-31")), "1999-12-31")
    assert_equal(parse_decimal("12.5", 2), Int64(1250))
    assert_equal(parse_decimal("-0.07", 2), Int64(-7))
    assert_equal(parse_decimal("$1,234.567", 2), Int64(123456))
    assert_equal(decimal_text(-1250, 2), "-12.50")
    assert_equal(decimal_text(5, 2), "0.05")

    var f = Frame(sample())
    assert_equal(f.columns(), 5)
    assert_equal(f.rows(), 5)
    assert_equal(f.display(0, 1), "Desk")
    assert_equal(f.display(2, 1), "120.00")
    assert_equal(f.display(4, 0), "2024-01-01")

    # formulas: scales tracked, a formula over a formula, dependants, cycles refused
    var margin = f.formula("margin = cents - cost")
    assert_equal(f.name(margin), "margin")
    assert_equal(f.kind(margin), DECIMAL)
    assert_equal(f.display(margin, 1), "50.00")
    var total = f.formula("total = quantity * margin")
    assert_equal(f.display(total, 1), "50.00")
    assert_equal(f.display(total, 2), "40.00")  # 4 × 10.00
    var pct = f.formula("pct = margin / cents")
    assert_equal(f.display(pct, 0), "0.40")
    var rate = f.formula("rate = margin * 0.5")
    assert_equal(f.display(rate, 1), "25.00")
    var bin = f.formula("bin = min(cents // 50, 2)")  # cents is money: 120.00 // 50
    assert_equal(f.kind(bin), INT)
    assert_equal(f.display(bin, 1), "2")
    assert_equal(f.display(bin, 2), "0")
    # scales land on the right operand (the reviewer's cases): q=1, cents=120.00, cost=70.00 on row 1
    var mixed = f.formula("mixed = quantity + cents * quantity")
    assert_equal(f.display(mixed, 1), "121.00")
    var ratio = f.formula("ratio = quantity / (cents - cost)")
    assert_equal(f.display(ratio, 1), "0.02")
    var least = f.formula("least = min(quantity, cents - cost)")
    assert_equal(f.display(least, 1), "1.00")
    var nested = f.formula("nested = (cents - cost) * (quantity + 1)")
    assert_equal(f.display(nested, 1), "100.00")
    # chained formulas are refused when the flattened program would need more than four stack slots
    var chain_ok = True
    try:
        _ = f.formula("deep = quantity + cost * (quantity * margin)")  # flattens to five slots
        chain_ok = False
    except:
        pass
    assert_true(chain_ok, "a chain too deep for the GPU must be refused")
    # replacing a formula recompiles the formulas built on it (a scale change: margin becomes a plain count)
    var plus = f.formula("plus = margin + cost")
    assert_equal(f.display(plus, 1), "120.00")
    _ = f.formula("margin = quantity")
    assert_equal(f.display(plus, 1), "71.00")  # 1 + 70.00, re-aligned
    _ = f.formula("margin = cents - cost")
    assert_equal(f.display(plus, 1), "120.00")
    # a replacement that would push a dependant past the GPU's depth is refused, and nothing changes
    var four = f.formula("four = quantity + cost * margin")  # 4 slots with margin = cents - cost
    var refused_replace = False
    try:
        _ = f.formula("margin = (cents - cost) * (quantity + 1)")  # fine alone; makes `four` need 5
    except:
        refused_replace = True
    assert_true(refused_replace, "a replacement that breaks a dependant must be refused")
    assert_equal(f.display(margin, 1), "50.00")
    assert_equal(f.display(four, 1), "3501.00")  # 1 + 70.00 × 50.00
    # bad values are refused
    var bad = 0
    for text in ["12.5x", "1.2.3", "2024-13-01", "2024-02-30"]:
        try:
            _ = f.parse(2 if "-" not in String(text) else 4, String(text))
        except:
            bad += 1
    assert_equal(bad, 4)
    var deps = f.dependants(f.index("cost"))
    assert_true(len(deps) >= 4)
    assert_equal(deps[0], "margin")
    assert_equal(deps[1], "total")
    var refused = False
    try:
        _ = f.formula("margin = total + 1")
    except:
        refused = True
    assert_true(refused, "a cycle must be refused")
    refused = False
    try:
        _ = f.formula("x = nothing + 1")
    except:
        refused = True
    assert_true(refused, "unknown columns must be refused")

    # edits change formulas; undo restores; the shared data is untouched
    f.set_text(f.index("cost"), 1, "100")
    assert_equal(f.display(margin, 1), "20.00")
    assert_equal(f.display(total, 1), "20.00")
    assert_true(f.edits >= 6)
    f.set_text(0, 1, "Stool")  # a new word
    assert_equal(f.display(0, 1), "Stool")
    assert_true(f.undo())
    assert_equal(f.display(0, 1), "Desk")
    assert_true(f.undo())
    assert_equal(f.display(margin, 1), "50.00")
    assert_equal(len(f.cells), 0)

    # append, remove, permutation, group sums
    var row = f.append(["Lamp", "10", "15.00", "5", "2024-02-01"])
    assert_equal(row, 5)
    assert_equal(f.display(total, 5), "100.00")
    f.remove(0)
    assert_false(f.alive(0))
    var order = f.permutation(f.index("cents"), descending=True)
    assert_equal(len(order), 5)
    assert_equal(order[0], 1)  # 120.00
    assert_equal(order[3], 2)  # the two 15.00 rows tie: lower row number first
    assert_equal(order[4], 5)
    var changed = f.changed_rows()
    assert_equal(len(changed), 2)
    var key = f.program_for(0)  # by product
    var value = f.program_for(total)
    var sums = f.group_sum(key, value, List[Range](), 3)
    assert_equal(sums[1][0], 1)  # Chair: row 0 removed, row 3 left
    assert_equal(sums[0][0], 6000)  # row 3: 3 × 20.00
    assert_equal(sums[0][2], 4000 + 10000)  # Lamp: row 2 + the appended row
    var ranges: List[Range] = [Range(4, 19724, 19724)]  # one day
    var day_sums = f.group_sum(key, value, ranges, 3)
    var day_counts = day_sums[1].copy()
    assert_equal(day_counts[1] + day_counts[2], 2)
    assert_true(f.undo())
    assert_true(f.alive(0))
    assert_true(f.undo())
    assert_equal(f.rows(), 5)
    assert_false(f.alive(5))  # the undone row is gone: not alive, not editable
    f.set(1, 5, 99)
    assert_equal(len(f.cells), 0)
    # merging text values: one undoable step, no chains, sorted and shown as the value they joined
    var names = Columns()
    var nc = Column("customer", TEXT)
    nc.dictionary = ["Acme", "Acme Corp.", "ACME Inc", "Globex", "Zed"]
    nc.values = [0, 1, 2, 3, 1, 4, 2]
    names.add(nc^)
    var mf = Frame(share(names^))
    assert_equal(mf.merge(0, [Int64(1)], Int64(4)), 1)  # Acme Corp. → Zed (a mistake, kept for the test)
    assert_equal(mf.display(0, 1), "Zed")
    assert_equal(mf.merge(0, [Int64(4)], Int64(0)), 1)  # Zed → Acme: Acme Corp. follows (no chain)
    assert_equal(mf.display(0, 1), "Acme")
    assert_equal(mf.display(0, 5), "Acme")
    assert_equal(mf.alias(0, 1), Int64(0))
    assert_equal(mf.merge(0, [Int64(2)], Int64(4)), 1)  # into a merged value lands on its final one
    assert_equal(mf.alias(0, 2), Int64(0))
    # sorting folds merges: every Acme-ish row comes before Globex
    var merged_order = mf.permutation(0)
    assert_equal(mf.display(0, merged_order[5]), "Acme")
    assert_equal(mf.display(0, merged_order[6]), "Globex")
    # undo walks back one merge at a time, exactly
    assert_true(mf.undo())  # ACME Inc → (Acme) undone
    assert_equal(mf.display(0, 2), "ACME Inc")
    assert_equal(mf.display(0, 1), "Acme")
    assert_true(mf.undo())  # Zed → Acme undone: Zed is Zed again, Acme Corp. back under Zed
    assert_equal(mf.display(0, 5), "Zed")
    assert_equal(mf.display(0, 1), "Zed")
    assert_true(mf.undo())
    assert_equal(mf.display(0, 1), "Acme Corp.")
    assert_equal(len(mf.aliases), 0)
    # keys never collide across columns, even past 65,536 codes
    assert_true(Frame.alias_key(2, 70000) != Frame.alias_key(3, 4464))
    print("FRAME TESTS PASSED")
