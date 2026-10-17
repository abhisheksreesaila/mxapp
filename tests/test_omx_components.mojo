# omxplorer's new components on their own: number formats, the inspector, the sheet chrome, tool buttons and
# the file picker (as view nodes; the hosts are checked by scripts/check).
#   pixi run mojo build -I . tests/test_omx_components.mojo -o build/test_omx_components && build/test_omx_components
from std.testing import assert_equal, assert_true

from mojoui import View, Button, FilePicker, Toggle, Dropdown, TOOL, TOOL_ON, BUTTON, SEGMENTED, TABS, FIELD, TEXT
from mojoui.numformat import (ColumnFormat, format_number, format_date, AUTO, NUMBER, CURRENCY, PERCENT, COMPACT,
                              DATE_LONG, DATE_MONTH, DATE_ISO)
from mojoui.inspector import Inspector, Section, Row, Stepper
from mojoui.sheetchrome import Tool, Toolbar, SheetTabs, FormulaBar, StatusBar


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
    var left: List[Tool] = [Tool("View", "view", 1, False), Tool("Zoom", "zoom", 2, False)]
    var middle: List[Tool] = [Tool("Table", "table", 3, True), Tool("Chart", "chart-bar", 4, False)]
    var right: List[Tool] = [Tool("Format", "format", 5, True)]
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
    print("OMX COMPONENT TESTS PASSED")
