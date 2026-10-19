# mojoui.kpi: a headline number: label, value, the change against the last period, and a sparkline. Native
# labels (readable, selectable, the same on every host) in a card; the sparkline on a small Canvas.
#
#   var k = KpiView("Revenue", "$1.11B", "+4.2% vs Q2", spark, True, TONE_GOOD)
#   k.view(canvas_id, version)          # in view()
#   k.draw(surface, palette)            # in draw(), for that canvas: the sparkline

from mojoui.view import View, Text, Card, HStack, VStack, Canvas, Button, Spacer, Divider, CAPTION, TITLE, TONE_ACCENT, TONE_GOOD, TONE_WARN, NO_MSG, START, CENTER, ICON_ONLY
from mojoui.canvas import Surface
from mojoui.theme import Palette
from mojoui.draw import line, area, with_alpha


@fieldwise_init
struct KpiView(Copyable, Movable):
    var label: String
    var value: String
    var note: String  # e.g. "+4.2% vs Q2"
    var spark: List[Float64]
    var accent: Bool  # the focal number (its value in the accent colour)
    var tone: Int  # the note's tone: TONE_GOOD, TONE_WARN or 0 (the app says whether a change is good: a rising cost isn't)

    def view(self, canvas: Int, version: Int, on_close: Int = NO_MSG, fact: String = "") -> View:
        """The card; with on_close, a small Remove (✕) button inside its top-right corner (it shows fully on hover).
        With `fact`, a footer under a hairline instead of the sparkline: the note as a chip on the left, the fact on the
        right ("199,812 matched")."""
        var bottom: View
        if fact != "":
            bottom = VStack(Divider().fill(), HStack(Text(self.note, style=CAPTION).tone(self.tone).tag("kpi-note"), Spacer(),
                                                     Text(fact, style=CAPTION).tag("kpi-fact"), spacing=8).fill().align(CENTER), spacing=10).fill()
        else:  # (the sparkline's canvas even when empty: apps count canvases in order, e.g. MX Studio's checks)
            bottom = HStack(Text(self.note, style=CAPTION).tone(self.tone).tag("kpi-note"),
                            Canvas(canvas, version, on_gesture=NO_MSG).width(110).height(34), spacing=8).fill()
        var head = HStack(Text(self.label, style=CAPTION).tag("kpi-label"), Spacer(), Button("Remove", on_close, ICON_ONLY, icon="close"), spacing=8).fill().align(CENTER) \
            if on_close != NO_MSG else Text(self.label, style=CAPTION).tag("kpi-label")
        return Card(
            head^,
            Text(self.value, style=TITLE).tone(TONE_ACCENT if self.accent else 0).tag("kpi-value"),
            bottom^,
            spacing=4,
        )

    def draw(self, mut s: Surface, pal: Palette):
        """The sparkline (a line over a fading area); nothing when there's no series."""
        s.fill(pal.card)
        var n = len(self.spark)
        if n < 2:
            return
        var k = s.scale
        var top = 0.0
        var low = self.spark[0]
        for v in self.spark:
            top = max(top, v)
            low = min(low, v)
        var w = Float64(s.width)
        var h = Float64(s.height)
        var xs = List[Float64]()
        var ys = List[Float64]()
        for i in range(n):
            xs.append(2 * k + (w - 4 * k) * Float64(i) / Float64(n - 1))
            ys.append(h - 3 * k - (h - 6 * k) * ((self.spark[i] - low) / (top - low) if top > low else 0.5))
        area(s, xs, ys, h, with_alpha(pal.accent, 0.28), with_alpha(pal.accent, 0.0))
        for i in range(n - 1):
            line(s, xs[i], ys[i], xs[i + 1], ys[i + 1], 1.75 * k, pal.accent)
