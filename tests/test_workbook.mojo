# A workbook saved and opened again is the same workbook: columns, dictionaries, formulas, edits,
# added and removed rows, objects and layout. Build it: pixi run mojo build -I . tests/test_workbook.mojo -o build/test_workbook
from std.testing import assert_equal, assert_true
from mojoui.frame import Column, Columns, Frame, share, INT, DECIMAL, TEXT, DATE
from mojoui.workbook import save_workbook, open_workbook, read_widths, ObjectSpec


def main() raises:
    var cols = Columns()
    var product = Column("product", TEXT)
    product.dictionary = ["Chair", "Desk", "Lamp"]
    product.values = [0, 1, 2, 0, 1, 2]
    cols.add(product^)
    var qty = Column("quantity", INT)
    qty.values = [2, 1, 4, 3, 2, 9]
    cols.add(qty^)
    var cents = Column("cents", DECIMAL, 2)
    cents.values = [5000, 12000, 1500, 5000, 12000, 777]
    cols.add(cents^)
    var day = Column("day", DATE)
    day.values = [19723, 19724, 19724, 19725, 19800, 19801]
    cols.add(day^)
    var f = Frame(share(cols^))
    _ = f.formula("total = quantity * cents")
    _ = f.formula("big = total // 100")
    f.set_text(0, 1, "Stool")
    f.set_text(2, 2, "99.50")
    _ = f.append(["Lamp", "7", "1.25", "2024-12-31"])
    f.remove(0)
    var objects = List[ObjectSpec]()
    objects.append(ObjectSpec(0, "Lines", 0, 0, 800, 300, 0, 1, 1, "", -1))
    objects.append(ObjectSpec(3, "Note", 0, 320, 400, 100, 0, 0, 0, "please review \"this\"\nline two", -1))
    var path = String("build/test_workbook.mxwb")
    save_workbook(path, f, "", objects)
    var specs = List[ObjectSpec]()
    var addr = 0
    var of = open_workbook(path, "contoso", 0, specs, addr)
    assert_true(addr != 0)
    assert_equal(of.columns(), f.columns())
    assert_equal(of.rows(), f.rows())
    var compared = 0
    for c in range(f.columns()):
        assert_equal(of.name(c), f.name(c))
        assert_equal(of.kind(c), f.kind(c))
        for r in range(f.rows()):
            assert_equal(of.alive(r), f.alive(r))
            assert_equal(of.display(c, r), f.display(c, r), f.name(c) + " row " + String(r))
            compared += 1
    assert_equal(of.display(0, 1), "Stool")
    assert_equal(of.display(4, 6), "8.75")  # total of the appended row: 7 × 1.25
    assert_equal(len(specs), 2)
    assert_equal(specs[1].text, objects[1].text)
    assert_equal(specs[1].y, 320)
    # saved again from the opened copy: the same file
    save_workbook("build/test_workbook2.mxwb", of, "", specs, [0, 140, 0, 96])
    var ws = read_widths("build/test_workbook2.mxwb")
    assert_equal(len(ws), 4)
    assert_equal(ws[1], 140)
    assert_equal(ws[3], 96)
    var specs2 = List[ObjectSpec]()
    var again = open_workbook("build/test_workbook2.mxwb", "contoso", 0, specs2, addr)
    assert_equal(again.display(2, 2), "99.50")
    assert_equal(again.rows(), 7)
    print("ROUNDTRIP: identical on " + String(compared) + " cells, formulas, objects")
    print("WORKBOOK TESTS PASSED")
