# PivotTable, ChartView, Card tones and Text tones: the view nodes they make and their behaviour.
#   pixi run mojo build -I . tests/test_components.mojo -o build/test_components && build/test_components
from std.testing import assert_equal, assert_true, assert_false

from mojoui import Text, Card, CARD, CARD_WARN, CARD_GOOD, TONE_WARN, TONE_STRONG, TEXT, GRID, VSTACK
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.pivot import PivotTable
from mojoui.chartview import ChartView
from mojoui.kpi import KpiView
from mojoui.finding import FindingCard
from mojoui import CARD_WARN, CARD_GOOD, TONE_GOOD, BUTTON


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
    assert_true(cv.tap(200, 150, font, pal))  # the third bar's row
    assert_equal(cv.selected, 2)
    assert_false(cv.tap(200, 500, font, pal))  # below the chart: nothing
    var spec = cv.flint(pal).to_json()
    assert_true(spec.find('"chartType": "Bar Chart"') >= 0)
    # a line with a second series and an event marker draws the marker (the warning colour) where the event is
    var labels = List[String]()
    var vals = List[Float64]()
    var shares = List[Float64]()
    for i in range(20):
        labels.append("W" + String(i) if i % 5 == 0 else "")
        vals.append(Float64(1000 + i * 50))
        shares.append(0.40 - (0.03 if i >= 10 else 0.0))
    var line = ChartView.line("Revenue and margin", labels^, vals^, shares^, 10, "rate table v7")
    line.draw(s, font, pal)
    var warn_px = 0  # pixels close to the warning colour (lines and text are anti-aliased)
    for i in range(w * h):
        var d = 0
        for shift in [0, 8, 16]:
            d += abs(Int((px[i] >> UInt32(shift)) & 255) - Int((pal.warn >> UInt32(shift)) & 255))
        if d < 90:
            warn_px += 1
    assert_true(warn_px > 20, "the marker is drawn: " + String(warn_px))
    # a heatmap: a tap picks the cell under it; the second tap lets go
    var heat = ChartView.heatmap("Margin", ["West", "East"], ["Tent", "Pack", "Stove"], [0.31, 0.40, 0.39, 0.41, 0.43, 0.40])
    heat.draw(s, font, pal)
    assert_true(heat.tap(Float64(w) - 10, Float64(h) - 10, font, pal))
    assert_equal(heat.selected, 5)  # bottom-right: East × Stove
    assert_true(heat.tap(Float64(w) - 10, Float64(h) - 10, font, pal))
    assert_equal(heat.selected, -1)
    # a KPI: native labels (its value in the accent when focal), and a sparkline drawn in the accent
    var kv = KpiView("Revenue", "$1.11B", "+4.2% vs Q2", [1.0, 3.0, 2.0, 5.0], True)
    var kview = kv.view(7, 1)
    var value_tone = -1
    for i in range(len(kview.nodes)):
        if kview.nodes[i].kind == TEXT and kview.nodes[i].text == "$1.11B":
            value_tone = kview.nodes[i].value
    assert_equal(value_tone, 4)  # TONE_ACCENT
    kv.draw(s, pal)
    var accent_px = 0
    for i in range(w * h):
        if px[i] == pal.accent:
            accent_px += 1
    assert_true(accent_px > 50, "the sparkline is drawn: " + String(accent_px))
    # FindingCard: warning while open, good once resolved; its first action is the main button
    var open_card = FindingCard("Agent noticed", "3 spellings", ["Merge", "Show the rows"], [6, 8], note="or by hand", again=12)
    assert_equal(open_card.nodes[0].style, CARD_WARN)
    var first_button = -1
    for i in range(len(open_card.nodes)):
        if open_card.nodes[i].kind == BUTTON and open_card.nodes[i].text == "Merge":
            first_button = i
    assert_true(first_button >= 0 and open_card.nodes[first_button].msg == 6)
    var done = FindingCard("Names are clean", "regrouped", resolved=True)
    assert_equal(done.nodes[0].style, CARD_GOOD)
    _ = len(px)
    print("COMPONENT TESTS PASSED")
