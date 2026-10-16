# PivotTable, ChartView, Card tones and Text tones: the view nodes they make and their behaviour.
#   pixi run mojo build -I . tests/test_components.mojo -o build/test_components && build/test_components
from std.testing import assert_equal, assert_true, assert_false

from mojoui import Text, Card, CARD, CARD_WARN, CARD_GOOD, TONE_WARN, TONE_STRONG, TEXT, GRID, VSTACK
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.pivot import PivotTable
from mojoui.chartview import ChartView


def main() raises:
    # PivotTable: corner + 2 columns + Total; 2 rows + a Total row; the highlighted row in the warning tone
    var cells: List[String] = ["$1", "$2", "$3", "$4"]
    var v = PivotTable(["Acme", "Acme Corp."], ["Tent", "Stove"], cells, totals=True,
                       row_totals=["$3", "$7"], col_totals=["$4", "$6"], grand="$10", highlight=[False, True])
    var grid = -1
    var texts = List[String]()
    var tones = List[Int]()
    for i in range(len(v.nodes)):
        if v.nodes[i].kind == GRID:
            grid = i
        if v.nodes[i].kind == TEXT:
            texts.append(v.nodes[i].text)
            tones.append(v.nodes[i].value)
    assert_true(grid >= 0)
    assert_equal(v.nodes[grid].value, 4)  # 4 columns: label, Tent, Stove, Total
    assert_equal(len(texts), 16)  # 4 × (header + 2 rows + total row)
    assert_equal(texts[8], "Acme Corp.")
    assert_equal(tones[8], TONE_WARN)
    assert_equal(tones[9], TONE_WARN)
    assert_equal(texts[15], "$10")
    assert_equal(tones[15], TONE_STRONG)

    # Card tones
    assert_equal(Card(Text("x")).nodes[0].style, CARD)
    assert_equal(Card(Text("x"), tone=CARD_WARN).nodes[0].style, CARD_WARN)
    assert_equal(Card(Text("x"), tone=CARD_GOOD).nodes[0].style, CARD_GOOD)

    # ChartView: draws, and a tap on a bar picks it; again lets go
    var font = Font()
    var pal = Palette.omarchy()
    var cv = ChartView("Revenue by customer", ["Acme", "Globex", "Initech"], [300.0, 200.0, 100.0], "revenue")
    var w = 400
    var h = 180
    var px = List[UInt32](length=w * h, fill=0)
    var s = Surface(Int(px.unsafe_ptr()), w, h, 1.0)
    cv.draw(s, font, pal)
    assert_true(px[w * 30 + 300] != px[0] or px[w * 90 + 200] != px[0], "something was drawn")
    assert_true(cv.tap(200, 30, font, pal))  # the first bar's row
    assert_equal(cv.selected, 0)
    assert_true(cv.tap(200, 30, font, pal))
    assert_equal(cv.selected, -1)
    assert_false(cv.tap(200, 500, font, pal))  # below the chart: nothing
    var spec = cv.flint(pal).to_json()
    assert_true(spec.find('"chartType": "Bar Chart"') >= 0)
    _ = len(px)
    print("COMPONENT TESTS PASSED")
