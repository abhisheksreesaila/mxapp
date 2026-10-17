# mojoui.kpi: a headline number on a Canvas: label, value, change against the last period, a sparkline,
# the focal one in the accent colour.
#
#   var k = KpiView("Revenue", "$1.11B", "+4.2% vs Q2", spark, accent=True)
#   Canvas(id, version)                  # in view()
#   k.draw(surface, font, palette)       # in draw()

from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.charts import KpiTile


@fieldwise_init
struct KpiView(Copyable, Movable):
    var label: String
    var value: String
    var note: String
    var spark: List[Float64]
    var accent: Bool

    def draw(self, mut s: Surface, font: Font, pal: Palette):
        KpiTile(self.label, self.value, self.note, self.spark.copy(), self.accent).themed(pal).draw(s, font)
