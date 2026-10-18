# omxplorer's new components on their own: number formats, the inspector, the sheet chrome, tool buttons and
# the file picker (as view nodes; the hosts are checked by scripts/check).
#   pixi run mojo build -I . tests/test_omx_components.mojo -o build/test_omx_components && build/test_omx_components
from std.testing import assert_equal, assert_true

from mojoui import View, Button, FilePicker, Toggle, Dropdown, TOOL, TOOL_ON, BUTTON, SEGMENTED, TABS, FIELD, TEXT
from mojoui.view import ICON_ONLY, ICON_ON, DIVIDER, PLAIN, SUBTLE
from mojoui.numformat import (ColumnFormat, format_number, format_date, AUTO, NUMBER, CURRENCY, PERCENT, COMPACT,
                              DATE_LONG, DATE_MONTH, DATE_ISO)
from mojoui.inspector import Inspector, Section, Row, Stepper
from mojoui.numformat import parse_decimal
from mojoui.sheetchrome import Tool, Toolbar, SheetTabs, FormulaBar, StatusBar, Toggles, Tab, BottomTabs
from mojoui.swatches import swatch_at, SWATCH_W


def count(v: View, kind: Int) -> Int:
    var n = 0
    for node in v.nodes:
        if node.kind == kind:
            n += 1
    return n


def texts(v: View) -> List[String]:
    var out = List[String]()
    for node in v.nodes:
        if node.kind == TEXT or node.kind == BUTTON:
            out.append(node.text)
    return out^


def main() raises:
    # ---- number formats: values arrive scaled (cents with scale 2) ----
    var cur = ColumnFormat(CURRENCY, 2, True, False, "$")
    assert_equal(format_number(121450, 2, cur), "$1,214.50")
    assert_equal(format_number(-121450, 2, cur), "−$1,214.50")
    cur.parens = True
    assert_equal(format_number(-121450, 2, cur), "($1,214.50)")
    assert_equal(format_number(0, 2, cur), "$0.00")
    assert_equal(format_number(-1, 2, ColumnFormat(CURRENCY, 0, True, False, "$")), "$0")  # (rounds to zero: no sign)
    assert_equal(format_number(22804129000, 2, ColumnFormat(CURRENCY, 0, True, False, "$")), "$228,041,290")
    assert_equal(format_number(123456789, 0, ColumnFormat(NUMBER, -1, True, False, "$")), "123,456,789")
    assert_equal(format_number(123456789, 0, ColumnFormat(NUMBER, -1, False, False, "$")), "123456789")
    assert_equal(format_number(1255, 3, ColumnFormat(NUMBER, 2, True, False, "$")), "1.26")  # (rounds half up)
    assert_equal(format_number(364, 3, ColumnFormat(PERCENT, 1, True, False, "$")), "36.4%")  # 0.364
    assert_equal(format_number(1, 0, ColumnFormat(PERCENT, 0, True, False, "$")), "100%")
    assert_equal(format_number(-30, 3, ColumnFormat(PERCENT, 1, True, False, "$")), "−3.0%")
    assert_equal(format_number(22804129000, 2, ColumnFormat(COMPACT, -1, True, False, "$")), "228.0M")
    assert_equal(format_number(1500, 0, ColumnFormat(COMPACT, -1, True, False, "$")), "1.5K")
    assert_equal(format_number(999, 0, ColumnFormat(COMPACT, -1, True, False, "$")), "999")
    assert_equal(format_date(20370, ColumnFormat(DATE_LONG, -1, True, False, "")), "9 Oct 2025")
    assert_equal(format_date(20370, ColumnFormat(DATE_MONTH, -1, True, False, "")), "Oct 2025")
    assert_equal(format_date(20370, ColumnFormat(DATE_ISO, -1, True, False, "")), "2025-10-09")
    assert_true(ColumnFormat.auto().is_auto())
    # edges the review found: compact rounding carries to the next unit; percent negatives keep the % inside the
    # parentheses; values too big for the asked decimals fall back to fewer places instead of overflowing
    assert_equal(format_number(999950, 0, ColumnFormat(COMPACT, -1, True, False, "$")), "1.0M")
    assert_equal(format_number(999949, 0, ColumnFormat(COMPACT, -1, True, False, "$")), "999.9K")
    assert_equal(format_number(-364, 3, ColumnFormat(PERCENT, 1, True, True, "$")), "(36.4%)")
    assert_true(not format_number(Int64(9_000_000_000_000_000_000), 0, ColumnFormat(NUMBER, 6, True, False, "$")).startswith("-"),
                "no overflow into a negative")
    assert_true(not ColumnFormat(12, 2, True, False, "$").valid(), "a style from a bad file is refused")
    assert_equal(ColumnFormat(12, 2, True, False, "$").summary(), "Automatic")
    # what the formats print, the parser reads back
    assert_equal(parse_decimal("$1,214.50", 2), 121450)
    assert_equal(parse_decimal("−$1,214.50", 2), -121450)
    assert_equal(parse_decimal("($1,214.50)", 2), -121450)
    assert_equal(parse_decimal("€9", 2), 900)
    assert_equal(parse_decimal("36.4%", 3), 364)
    assert_equal(parse_decimal("(36.4%)", 3), -364)
    assert_equal(parse_decimal("-3.0", 1), -30)

    # ---- tool buttons and the file picker ----
    var tool = Button("Table", 7, TOOL, icon="table")
    assert_equal(tool.nodes[0].style, TOOL)
    assert_equal(tool.nodes[0].hint, "table")
    var picker = FilePicker("Choose a file…", 9, icon="import", accept=".csv,.parquet")
    assert_equal(picker.nodes[0].kind, BUTTON)
    assert_equal(picker.nodes[0].msg, 0)  # (no plain tap: it opens a dialog)
    assert_equal(picker.nodes[0].msg2, 9)
    assert_equal(picker.nodes[0].options[0], ".csv,.parquet")

    # ---- the inspector ----
    var sections = List[View]()
    var data_format = List[View]()
    var styles: List[String] = ["Automatic", "Number", "Currency"]
    data_format.append(Dropdown(styles, 2, 20))
    data_format.append(Row("Decimals", Stepper("2", 21, 22)))
    data_format.append(Row("Thousands", Toggle("", True, 23)))
    sections.append(Section("Data format", data_format))
    var tabs: List[String] = ["Table", "Cell", "Text", "Arrange"]
    var insp = Inspector(tabs, 1, 10, sections)
    assert_equal(count(insp, SEGMENTED), 1)
    assert_true("DATA FORMAT" in texts(insp), "the section title")
    assert_true("Decimals" in texts(insp) and "−" in texts(insp) and "+" in texts(insp), "the stepper row")
    assert_equal(insp.nodes[0].w, 300)

    # ---- the sheet chrome ----
    var left: List[Tool] = [Tool("View", "view", 1, False, ""), Tool("Zoom", "zoom", 2, False, "")]
    var middle: List[Tool] = [Tool("Table", "table", 3, True, "Show as a table"), Tool("Chart", "chart-bar", 4, False, "")]
    var right: List[Tool] = [Tool("Format", "format", 5, True, "")]
    var bar = Toolbar(left, middle, right)
    var tools = 0
    var on = 0
    for node in bar.nodes:
        if node.kind == BUTTON and (node.style == TOOL or node.style == TOOL_ON):
            tools += 1
            if node.style == TOOL_ON:
                on += 1
    assert_equal(tools, 5)
    assert_equal(on, 2)
    var names: List[String] = ["Orders", "Report"]
    assert_equal(count(SheetTabs(names, 0, 30, 31), TABS), 1)
    var fx = FormulaBar("G6", "=revenue - cost", 40, 41)
    assert_equal(count(fx, FIELD), 1)
    assert_true("ƒx" in texts(fx) and "G6" in texts(fx), "ƒx and the cell's name")
    var status: List[String] = ["Rows 1,000,000", "Sum $228.0M"]
    assert_true("Sum $228.0M" in texts(StatusBar(status, "2.1 ms on GPU")), "the status bar")

    # ---- format toggles: icon-only, pressed while on; groups after the middle tools, a divider before each ----
    var font_tools: List[Tool] = [Tool("Bold", "bold", 80, True, "Bold (Ctrl+B)"), Tool("Italic", "italic", 81, False, "")]
    var t = Toggles(font_tools)
    assert_equal(t[0].nodes[0].style, ICON_ON)
    assert_equal(t[1].nodes[0].style, ICON_ONLY)
    assert_equal(t[0].nodes[0].text, "Bold")  # (the title: what an agent and a screen reader use)
    assert_equal(t[0].nodes[0].hint, "bold")
    assert_equal(t[0].nodes[0].name, "bold")  # (tagged by icon: a popover anchors to it)
    var groups: List[List[Tool]] = [font_tools.copy(), [Tool("Fill colour", "fill", 90, False, "")]]
    var formatted = Toolbar(left, middle, right, toggles=groups)
    assert_equal(count(formatted, DIVIDER), 2)
    var pressed_icons = 0
    for node in formatted.nodes:
        if node.kind == BUTTON and node.style == ICON_ON:
            pressed_icons += 1
    assert_equal(pressed_icons, 1)

    # ---- bottom tabs: the current one stands out; the one being renamed is a field with its name ----
    var doc_tabs: List[Tab] = [Tab("Orders", "sheet"), Tab("Report", "chart-bar")]
    var bottom = BottomTabs(doc_tabs, 1, 93)
    var tab_styles = List[Int]()
    var msgs = List[Int]()
    for node in bottom.nodes:
        if node.kind == BUTTON:
            tab_styles.append(node.style)
            msgs.append(node.msg)
    assert_equal(len(tab_styles), 2)
    assert_equal(tab_styles[0], SUBTLE)
    assert_equal(tab_styles[1], PLAIN)
    assert_equal(msgs[0], 93)
    assert_equal(msgs[1], 94)
    var renaming = BottomTabs(doc_tabs, 0, 93, 0, 96, 97)
    assert_equal(count(renaming, FIELD), 1)
    for node in renaming.nodes:
        if node.kind == FIELD:
            assert_equal(node.text, "Orders")
            assert_equal(node.msg2, 96)  # (Enter)
            assert_equal(node.value, 1)  # (.focused(): it takes the keyboard, its text selected)
    assert_true("Report" in texts(renaming) and not ("Orders" in texts(renaming)), "the other tab stays a button")

    # ---- the swatch picker: automatic, then eight colours, one row; gaps hit nothing ----
    assert_equal(swatch_at(6 + 15, 21), 0)
    assert_equal(swatch_at(6 + 6 * 36 + 15, 21), 6)
    assert_equal(swatch_at(6 + 8 * 36 + 29, 35), 8)
    assert_equal(swatch_at(6 + 30 + 3, 21), -1)
    assert_equal(swatch_at(100, 2), -1)
    assert_equal(swatch_at(Float64(SWATCH_W) + 10, 21), -1)
    print("OMX COMPONENT TESTS PASSED")
