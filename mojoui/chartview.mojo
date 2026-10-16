# mojoui.chartview: a Flint chart shown on a Canvas, themed, with tap-to-select (for crossfiltering).
#
#   var chart = ChartView("Revenue by region", labels, values, money=True)
#   Canvas(id, version, on_gesture=TAP_MSG)            # in view()
#   chart.draw(surface, font, palette)                 # in draw()
#   if chart.tap(event.x, event.y, font, palette): …            # in update(): True when the selection changed

from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.flint import FlintChart


struct ChartView(Copyable, Movable):
    var title: String
    var labels: List[String]
    var values: List[Float64]
    var value_name: String
    var money: Bool  # values are cents
    var selected: Int  # the picked bar (-1: none)
    var size: Tuple[Float64, Float64]  # points, from the last draw

    def __init__(out self, title: String, var labels: List[String], var values: List[Float64], value_name: String = "value",
                 money: Bool = True, selected: Int = -1):
        self.title = title
        self.labels = labels^
        self.values = values^
        self.value_name = value_name
        self.money = money
        self.selected = selected
        self.size = (400.0, 240.0)

    def flint(self, pal: Palette) -> FlintChart:
        """The chart as a Flint spec (the same JSON Flint's own renderers take)."""
        return (FlintChart("Bar Chart", self.title).text("name", self.labels).number(self.value_name, self.values)
                .semantic("name", "Category").semantic(self.value_name, "Price" if self.money else "Count")
                .encode("x", self.value_name).encode("y", "name").size(Int(self.size[0]), Int(self.size[1]))
                .themed(pal))

    def draw(mut self, mut s: Surface, font: Font, pal: Palette):
        self.size = (s.points_width(), s.points_height())
        self.flint(pal).draw(s, font, self.selected)

    def tap(mut self, x: Float64, y: Float64, font: Font, pal: Palette) -> Bool:
        """A tap on a bar picks it (again: lets go). True when the selection changed."""
        var hit = self.flint(pal).hit(self.size[0], self.size[1], font, x, y)
        if hit < 0:
            return False
        self.selected = -1 if self.selected == hit else hit
        return True
