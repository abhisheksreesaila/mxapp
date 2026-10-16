# Flint charts in Mojo: declare a chart as a Flint spec (https://microsoft.github.io/flint-chart/,
# Microsoft's visualization language for the AI era), draw it natively with mojoui.charts, or export
# it as Flint's JSON (ChartAssemblyInput) for Flint's own backends (Vega-Lite, ECharts…) or an AI agent.
#
#   var chart = FlintChart("Bar Chart", "Revenue by category")
#   chart.text("category", names).number("revenue", values)
#   chart.semantic("revenue", "Price").encode("x", "revenue").encode("y", "category")
#   chart.draw(surface, font, selected)     # mojoui's native renderer (the same pixels everywhere)
#   chart.to_json()                         # valid Flint input
#
# Supported here: KPI Card, Area Chart, Line Chart, Bar Chart (horizontal or vertical), Bar Table.
# Money (semantic type Price, Revenue, Amount or Cost) is kept in exact cents; the JSON has dollars.

from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.charts import KpiTile, BarChart, LineChart, ColumnChart, money, compact, BRAND, DATA
from mojoui.theme import Palette


def json_string(s: String) -> String:
    var out = String('"')
    for c in s.codepoint_slices():
        if c == '"':
            out += '\\"'
        elif c == "\\":
            out += "\\\\"
        elif c == "\n":
            out += "\\n"
        else:
            out += c
    return out + '"'


def json_number(x: Float64) -> String:
    if x == Float64(Int(x)) and abs(x) < 1e15:
        return String(Int(x))
    return String(x)


struct FlintChart(Movable):
    """A Flint chart spec: chart type, title, data columns, semantic types and encodings."""

    var chart_type: String
    var title: String
    var subtitle: String
    var names: List[String]  # columns, in order
    var is_text: List[Bool]
    var texts: List[List[String]]
    var numbers: List[List[Float64]]
    var semantic_fields: List[String]
    var semantic_types: List[String]
    var channels: List[String]
    var fields: List[String]
    var properties: List[String]  # "key": value pairs, already JSON
    var width: Int
    var height: Int
    var pal: Palette  # how mojoui draws it (not part of the Flint spec)

    def __init__(out self, chart_type: String, title: String = "", subtitle: String = ""):
        self.chart_type = chart_type
        self.title = title
        self.subtitle = subtitle
        self.names = List[String]()
        self.is_text = List[Bool]()
        self.texts = List[List[String]]()
        self.numbers = List[List[Float64]]()
        self.semantic_fields = List[String]()
        self.semantic_types = List[String]()
        self.channels = List[String]()
        self.fields = List[String]()
        self.properties = List[String]()
        self.width = 400
        self.height = 320
        self.pal = Palette.fluent()

    def text(var self, name: String, values: List[String]) -> FlintChart:
        self.names.append(name)
        self.is_text.append(True)
        self.texts.append(values.copy())
        self.numbers.append(List[Float64]())
        return self^

    def number(var self, name: String, values: List[Float64]) -> FlintChart:
        self.names.append(name)
        self.is_text.append(False)
        self.texts.append(List[String]())
        self.numbers.append(values.copy())
        return self^

    def semantic(var self, field: String, semantic_type: String) -> FlintChart:
        """Flint's semantic type for a field, e.g. "Price", "Category", "Month", "Count"."""
        self.semantic_fields.append(field)
        self.semantic_types.append(semantic_type)
        return self^

    def encode(var self, channel: String, field: String) -> FlintChart:
        self.channels.append(channel)
        self.fields.append(field)
        return self^

    def property(var self, key: String, json_value: String) -> FlintChart:
        self.properties.append(json_string(key) + ": " + json_value)
        return self^

    def themed(var self, pal: Palette) -> FlintChart:
        """Draw it in another palette (Palette.omarchy()); the Flint spec is unchanged."""
        self.pal = pal.copy()
        return self^

    def size(var self, width: Int, height: Int) -> FlintChart:
        self.width = width
        self.height = height
        return self^

    # ---------- reading it back ----------

    def column(self, name: String) -> Int:
        for k in range(len(self.names)):
            if self.names[k] == name:
                return k
        return -1

    def field_of(self, channel: String) -> String:
        for k in range(len(self.channels)):
            if self.channels[k] == channel:
                return self.fields[k]
        return ""

    def numbers_of(self, channel: String) -> List[Float64]:
        var c = self.column(self.field_of(channel))
        return self.numbers[c].copy() if c >= 0 and not self.is_text[c] else List[Float64]()

    def texts_of(self, channel: String) -> List[String]:
        var c = self.column(self.field_of(channel))
        if c < 0:
            return List[String]()
        if self.is_text[c]:
            return self.texts[c].copy()
        var out = List[String]()
        for v in self.numbers[c]:
            out.append(String(v))
        return out^

    def is_text_channel(self, channel: String) -> Bool:
        var c = self.column(self.field_of(channel))
        return c >= 0 and self.is_text[c]

    def rows(self) -> Int:
        return len(self.texts[0]) if len(self.names) > 0 and self.is_text[0] else (len(self.numbers[0]) if len(self.names) > 0 else 0)

    # ---------- Flint JSON ----------

    def to_json(self) -> String:
        """Flint's ChartAssemblyInput: { data: {values: rows}, semantic_types, chart_spec }."""
        var out = String('{"data": {"values": [')
        for r in range(self.rows()):
            out += ("," if r > 0 else "") + "{"
            for c in range(len(self.names)):
                out += ("," if c > 0 else "") + json_string(self.names[c]) + ": "
                if self.is_text[c]:
                    out += json_string(self.texts[c][r])
                else:  # money is kept in exact cents here; Flint gets dollars
                    out += json_number(self.numbers[c][r] / 100.0 if self.is_money(self.names[c]) else self.numbers[c][r])
            out += "}"
        out += ']}, "semantic_types": {'
        for k in range(len(self.semantic_fields)):
            out += ("," if k > 0 else "") + json_string(self.semantic_fields[k]) + ": " + json_string(self.semantic_types[k])
        out += '}, "chart_spec": {"chartType": ' + json_string(self.chart_type)
        if self.title != "":
            out += ', "title": ' + json_string(self.title)
        if self.subtitle != "":
            out += ', "subtitle": ' + json_string(self.subtitle)
        out += ', "encodings": {'
        for k in range(len(self.channels)):
            out += ("," if k > 0 else "") + json_string(self.channels[k]) + ': {"field": ' + json_string(self.fields[k]) + "}"
        out += '}, "baseSize": {"width": ' + String(self.width) + ', "height": ' + String(self.height) + "}"
        if len(self.properties) > 0:
            out += ', "chartProperties": {'
            for k in range(len(self.properties)):
                out += ("," if k > 0 else "") + self.properties[k]
            out += "}"
        return out + "}}"

    # ---------- drawing (mojoui's native Flint backend) ----------

    def is_money(self, field: String) -> Bool:
        """Money fields (semantic type Price/Revenue/Amount/Cost) hold exact cents in mojoui."""
        for k in range(len(self.semantic_fields)):
            if self.semantic_fields[k] == field:
                var t = self.semantic_types[k]
                return t == "Price" or t == "Revenue" or t == "Amount" or t == "Cost"
        return False

    def money_axis(self, channel: String) -> Bool:
        return self.is_money(self.field_of(channel))

    def label(self, channel: String, v: Float64) -> String:
        return money(Int(v)) if self.money_axis(channel) else compact(v)

    def draw(self, mut s: Surface, font: Font, selected: Int = -1, accent: Bool = False, note: String = ""):
        """Draws the chart into `s`. selected: the highlighted row (-1: none)."""
        if self.chart_type == "KPI Card":
            var metric = self.texts_of("metric")
            var value = self.numbers_of("value")
            var spark = List[Float64]()
            var c = self.column("trend")  # (an extra data column: the tile's sparkline)
            if c >= 0:
                spark = self.numbers[c].copy()
            KpiTile(metric[0] if len(metric) > 0 else "", self.label("value", value[0] if len(value) > 0 else 0), note, spark^, accent).themed(self.pal).draw(s, font)
        elif self.chart_type == "Area Chart" or self.chart_type == "Line Chart":
            var all = self.texts_of("x")
            var every = max((len(all) + 6) // 7, 1)  # about seven labels along the axis
            var labels = List[String]()
            for i in range(len(all)):
                labels.append(all[i] if i % every == 0 else "")
            LineChart(labels^, self.numbers_of("y"), selected).themed(self.pal).draw(s, font)
        elif self.chart_type == "Bar Chart" or self.chart_type == "Bar Table":
            if self.is_text_channel("y"):  # categories down the side: horizontal bars
                var values = self.numbers_of("x")
                var labels = List[String]()
                for v in values:
                    labels.append(self.label("x", v))
                BarChart(self.texts_of("y"), values^, labels^, selected, self.chart_type == "Bar Table").themed(self.pal).draw(s, font)
            else:  # categories along the bottom: columns
                var values = self.numbers_of("y")
                var tops = List[String]()
                for v in values:
                    tops.append(self.label("y", v) if len(values) <= 12 else "")
                var many = len(values) > 12  # a distribution: narrow bars in the second palette colour
                ColumnChart(self.texts_of("x"), values^, tops^, selected, 0.14 if many else 0.35,
                            self.pal.data(1) if many else self.pal.accent).themed(self.pal).draw(s, font)

    def hit(self, width_pt: Float64, height_pt: Float64, font: Font, x_pt: Float64, y_pt: Float64) -> Int:
        """The row a tap at (x, y) points landed on, or -1."""
        if self.chart_type == "Area Chart" or self.chart_type == "Line Chart":
            var k = 2.0  # (in points; the scale only sets label widths)
            return LineChart(self.texts_of("x"), self.numbers_of("y"), -1).themed(self.pal).hit(width_pt * k, height_pt * k, k, font, x_pt)
        if self.chart_type == "Bar Chart" or self.chart_type == "Bar Table":
            if self.is_text_channel("y"):
                return BarChart(self.texts_of("y"), self.numbers_of("x"), List[String](), -1).hit(height_pt, y_pt)
            return ColumnChart(self.texts_of("x"), self.numbers_of("y"), List[String](), -1).hit(width_pt, x_pt)
        return -1
