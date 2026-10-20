# mojoui.chartview: a chart shown on a Canvas, themed, with tap-to-select (for crossfiltering).
# Kinds: "Bar Chart" (horizontal bars), "Line Chart" (a series over time, an optional second share series and
# an event marker), "Heatmap" (rows × columns of shares). Bars and lines go through a Flint spec.
#
#   var chart = ChartView("Revenue by region", labels, values, money=True)
#   Canvas(id, version, on_gesture=TAP_MSG)            # in view()
#   chart.draw(surface, font, palette)                 # in draw()
#   if chart.tap(event.x, event.y, font, palette): …   # in update(): True when the selection changed

from std.collections import Dict
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.flint import FlintChart
from mojoui.charts import LineChart, Heatmap, BarChart


struct ChartView(Copyable, Movable):
    var kind: String
    var title: String
    var labels: List[String]  # bars: categories; lines: x labels; heatmaps: columns
    var values: List[Float64]
    var value_name: String
    var money: Bool  # values are cents
    var selected: Int  # the picked bar / point / cell (-1: none)
    var size: Tuple[Float64, Float64]  # points, from the last draw
    var rows: List[String]  # heatmaps: row labels
    var second: List[Float64]  # lines: a second series (shares 0–1)
    var marker: Int  # lines: an event's index, or -1
    var marker_text: String
    var was_labels: List[String]  # the chart before a change, and how far it has moved to this one (1: there)
    var was_values: List[Float64]
    var t: Float64

    def __init__(out self, title: String, var labels: List[String], var values: List[Float64], value_name: String = "value",
                 money: Bool = True, selected: Int = -1):
        self.kind = "Bar Chart"
        self.title = title
        self.labels = labels^
        self.values = values^
        self.value_name = value_name
        self.money = money
        self.selected = selected
        self.size = (400.0, 240.0)
        self.rows = List[String]()
        self.second = List[Float64]()
        self.marker = -1
        self.marker_text = ""
        self.was_labels = List[String]()
        self.was_values = List[Float64]()
        self.t = 1.0

    @staticmethod
    def line(title: String, var labels: List[String], var values: List[Float64], var second: List[Float64] = [],
             marker: Int = -1, marker_text: String = "") -> ChartView:
        """A money series over time (labels "" where no tick), optionally a share (0–1) and an event marker."""
        var cv = ChartView(title, labels^, values^, "revenue", True)
        cv.kind = "Line Chart"
        cv.second = second^
        cv.marker = marker
        cv.marker_text = marker_text
        return cv^

    @staticmethod
    def heatmap(title: String, var rows: List[String], var cols: List[String], var values: List[Float64]) -> ChartView:
        """Shares (0–1) on rows × columns."""
        var cv = ChartView(title, cols^, values^, "share", False)
        cv.kind = "Heatmap"
        cv.rows = rows^
        return cv^

    def flint(self, pal: Palette) -> FlintChart:
        """Bars and lines as a Flint spec (the same JSON Flint's own renderers take)."""
        if self.kind == "Line Chart":
            return (FlintChart("Line Chart", self.title).text("x", self.labels).number(self.value_name, self.values)
                    .semantic("x", "Date").semantic(self.value_name, "Price").encode("x", "x").encode("y", self.value_name)
                    .size(Int(self.size[0]), Int(self.size[1])).themed(pal))
        return (FlintChart("Bar Chart", self.title).text("name", self.labels).number(self.value_name, self.values)
                .semantic("name", "Category").semantic(self.value_name, "Price" if self.money else "Count")
                .encode("x", self.value_name).encode("y", "name").size(Int(self.size[0]), Int(self.size[1]))
                .themed(pal))

    def moving_from(mut self, var labels: List[String], var values: List[Float64], t: Float64):
        """Draw the chart `t` of the way (0–1, already eased) from what it showed before: each bar from its group's old
        value and row (a new group grows from nothing; a group that left is gone); a line's points from theirs."""
        self.was_labels = labels^
        self.was_values = values^
        self.t = t

    def draw(mut self, mut s: Surface, font: Font, pal: Palette):
        self.size = (s.points_width(), s.points_height())
        if self.t < 1.0 and self.kind != "Heatmap":
            var now = List[Float64]()
            var places = List[Float64]()
            var was = Dict[String, Int]()  # (each group's old row: one look-up a bar, thousands of groups too)
            for j in range(len(self.was_labels)):
                was[self.was_labels[j]] = j
            for i in range(len(self.labels)):
                var old_v = 0.0
                var old_i = Float64(i)
                var j = was.get(self.labels[i], -1)
                if j >= 0:
                    old_v = self.was_values[j] if j < len(self.was_values) else 0.0
                    old_i = Float64(j)
                now.append(old_v + (self.values[i] - old_v) * self.t)
                places.append(old_i + (Float64(i) - old_i) * self.t)
            if self.kind == "Line Chart":
                LineChart(self.labels.copy(), now^, self.selected).with_second(self.second.copy()).with_marker(
                    self.marker, self.marker_text).numbers(self.money).themed(pal).draw(s, font)
                return
            var f = self.flint(pal)
            var texts = List[String]()
            for v in self.values:  # (the figures say where the bars are going)
                texts.append(f.label("x", v))
            BarChart(self.labels.copy(), now^, texts^, self.selected).themed(pal).moving(places^).draw(s, font)
            return
        if self.kind == "Heatmap":
            Heatmap(self.rows.copy(), self.labels.copy(), self.values.copy(), True, self.selected).themed(pal).draw(s, font)
        elif self.kind == "Line Chart":
            LineChart(self.labels.copy(), self.values.copy(), self.selected).with_second(self.second.copy()).with_marker(
                self.marker, self.marker_text).numbers(self.money).themed(pal).draw(s, font)
        else:
            self.flint(pal).draw(s, font, self.selected)

    def tap(mut self, x: Float64, y: Float64, font: Font, pal: Palette) -> Bool:
        """A tap picks a bar, point or cell (again: lets go). True when the selection changed."""
        var hit: Int
        if self.kind == "Heatmap":
            hit = Heatmap(self.rows.copy(), self.labels.copy(), self.values.copy()).themed(pal).hit(self.size[0], self.size[1], font, x, y)
        elif self.kind == "Line Chart":
            hit = LineChart(self.labels.copy(), self.values.copy()).with_second(self.second.copy()).with_marker(
                self.marker, self.marker_text).numbers(self.money).themed(pal).hit(self.size[0] * 2, self.size[1] * 2, 2.0, font, x)
        else:
            hit = self.flint(pal).hit(self.size[0], self.size[1], font, x, y)
        if hit < 0:
            return False
        self.selected = -1 if self.selected == hit else hit
        return True
