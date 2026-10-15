# Charts drawn by Mojo on a Canvas: KPI tiles, horizontal bars, line/area, columns and histograms,
# in Fluent 2's colours, with axes, gridlines, labels, a highlighted selection and hit-testing.
# The same pixels on every platform.
#
#   var bars = BarChart(names, values, selected=2)
#   bars.draw(surface, font)                       # in App.draw()
#   var row = bars.hit(surface_size, scale, x, y)  # a TAP at (x, y) points → the row it landed on

from std.math import log10, floor
from mojoui.canvas import Surface, rgba
from mojoui.text import Font, REGULAR, MEDIUM, LEFT, CENTRE, RIGHT
from mojoui.draw import rect, line, circle, hline, area, with_alpha

# Fluent 2 tokens (light theme)
comptime PAGE = rgba(245, 245, 245)  # neutral background 3
comptime CARD_BG = rgba(255, 255, 255)
comptime INK = rgba(36, 36, 36)  # neutral foreground 1
comptime INK2 = rgba(97, 97, 97)  # neutral foreground 3
comptime INK3 = rgba(140, 140, 140)
comptime GRID = rgba(235, 235, 235)
comptime STROKE = rgba(224, 224, 224)
comptime BRAND = rgba(15, 108, 189)  # brand 80
comptime BRAND_DARK = rgba(17, 94, 163)
comptime BRAND_TINT = rgba(199, 224, 244)
comptime BRAND_WASH = rgba(235, 243, 252)
comptime GOOD = rgba(16, 124, 16)
comptime BAD = rgba(197, 15, 31)
# Fluent's qualitative data palette
comptime DATA: List[UInt32] = [
    rgba(15, 108, 189), rgba(42, 160, 164), rgba(147, 115, 192), rgba(202, 80, 16), rgba(87, 129, 27),
    rgba(227, 0, 140), rgba(58, 150, 221), rgba(174, 140, 0),
]


# ---------- numbers ----------

def money(cents: Int) -> String:
    """$1.24B, $512M, $12.4K, $940 (three significant digits)."""
    var dollars = Float64(cents) / 100.0
    return "$" + compact(dollars)


def axis_money(cents: Int) -> String:
    """Money for an axis label: no trailing zeros ($5M, $2.5M, $750K)."""
    var t = money(cents)
    var unit = String("")
    if t.endswith("B") or t.endswith("M") or t.endswith("K"):
        unit = String(t[byte = t.byte_length() - 1 :])
        t = String(t[byte : t.byte_length() - 1])
    if "." in t:
        while t.endswith("0"):
            t = String(t[byte : t.byte_length() - 1])
        if t.endswith("."):
            t = String(t[byte : t.byte_length() - 1])
    return t + unit


def compact(x: Float64) -> String:
    var v = abs(x)
    var unit = String("")
    if v >= 1e9:
        v /= 1e9
        unit = "B"
    elif v >= 1e6:
        v /= 1e6
        unit = "M"
    elif v >= 1e4:
        v /= 1e3
        unit = "K"
    var places = 0 if v >= 100 or unit == "" else (1 if v >= 10 else 2)
    return ("-" if x < 0 else "") + fixed(v, places) + unit


def fixed(x: Float64, places: Int) -> String:
    var scale = 10**places
    var n = Int(x * Float64(scale) + 0.5)
    if places == 0:
        return grouped(n)
    var frac = String(n % scale)
    while frac.byte_length() < places:
        frac = "0" + frac
    return grouped(n // scale) + "." + frac


def grouped(n: Int) -> String:
    """12,345,678"""
    var s = String(abs(n))
    var out = String("")
    var count = 0
    for i in range(s.byte_length() - 1, -1, -1):
        out = String(s[byte=i]) + out
        count += 1
        if count % 3 == 0 and i > 0:
            out = "," + out
    return ("-" if n < 0 else "") + out


def nice_max(x: Float64) -> Float64:
    """A round number ≥ x for an axis top (1, 2, 2.5, 5 × 10^k)."""
    if x <= 0:
        return 1
    var p = 10.0 ** floor(log10(x))
    for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
        if m * p >= x * 0.999:
            return m * p
    return 10 * p


# ---------- tiles ----------

struct KpiTile(Movable):
    """A headline number: label, value, a note below, and a sparkline. `accent` = the focal tile (brand blue)."""

    var label: String
    var value: String
    var note: String
    var spark: List[Float64]
    var accent: Bool

    def __init__(out self, label: String, value: String, note: String, var spark: List[Float64], accent: Bool = False):
        self.label = label
        self.value = value
        self.note = note
        self.spark = spark^
        self.accent = accent

    def draw(self, mut s: Surface, font: Font):
        var k = s.scale
        s.fill(PAGE)
        var bg = BRAND if self.accent else CARD_BG
        var ink = CARD_BG if self.accent else INK
        var ink2 = with_alpha(CARD_BG, 0.82) if self.accent else INK2
        var w = Float64(s.width)
        var h = Float64(s.height)
        # Fluent "shadow4": a soft drop under the tile
        rect(s, 1 * k, 2.5 * k, w - 2 * k, h - 3.5 * k, rgba(0, 0, 0, 22), 8 * k)
        rect(s, 0.5 * k, 0.5 * k, w - 1 * k, h - 2 * k, rgba(0, 0, 0, 18), 8 * k)
        rect(s, 1 * k, 1 * k, w - 2 * k, h - 3 * k, bg, 8 * k)
        var pad = 16 * k
        font.draw(s, self.label, pad, pad + 13 * k, 13 * k, ink2, MEDIUM)
        font.draw(s, self.value, pad, pad + 13 * k + 38 * k, 34 * k, ink, MEDIUM)
        font.draw(s, self.note, pad, h - 16 * k, 12 * k, ink2)
        # sparkline, bottom right
        var n = len(self.spark)
        if n >= 2:
            var top = 0.0
            for v in self.spark:
                top = max(top, v)
            var x0 = w * 0.55
            var x1 = w - pad
            var y1 = h - 18 * k
            var y0 = y1 - 34 * k
            var xs = List[Float64]()
            var ys = List[Float64]()
            for i in range(n):
                xs.append(x0 + (x1 - x0) * Float64(i) / Float64(n - 1))
                ys.append(y1 - (y1 - y0) * (self.spark[i] / top if top > 0 else 0))
            var line_color = CARD_BG if self.accent else BRAND
            area(s, xs, ys, y1, with_alpha(line_color, 0.30), with_alpha(line_color, 0.0))
            for i in range(n - 1):
                line(s, xs[i], ys[i], xs[i + 1], ys[i + 1], 1.75 * k, line_color)


# ---------- horizontal bars ----------

struct BarChart(Movable):
    """Ranked horizontal bars with names on the left and values on the right. selected: -1 = none."""

    var names: List[String]
    var values: List[Float64]
    var labels: List[String]  # the value text for each bar
    var selected: Int

    def __init__(out self, var names: List[String], var values: List[Float64], var labels: List[String], selected: Int = -1):
        self.names = names^
        self.values = values^
        self.labels = labels^
        self.selected = selected

    def row_height(self, s_height: Float64) -> Float64:
        return s_height / Float64(max(len(self.names), 1))

    def draw(self, mut s: Surface, font: Font):
        var k = s.scale
        s.fill(CARD_BG)
        var n = len(self.names)
        if n == 0:
            return
        var name_w = 0.0
        var value_w = 0.0
        for i in range(n):
            name_w = max(name_w, font.measure(self.names[i], 13 * k))
            value_w = max(value_w, font.measure(self.labels[i], 13 * k, MEDIUM))
        var x0 = name_w + 12 * k
        var x1 = Float64(s.width) - value_w - 10 * k
        var top = 0.0
        for v in self.values:
            top = max(top, v)
        var rh = self.row_height(Float64(s.height))
        for i in range(n):
            var cy = rh * (Float64(i) + 0.5)
            var on = self.selected < 0 or self.selected == i
            var bar_w = (x1 - x0) * (self.values[i] / top if top > 0 else 0)
            var bh = min(rh * 0.62, 26 * k)
            rect(s, x0, cy - bh / 2, x1 - x0, bh, rgba(245, 245, 245), 3 * k)  # the track
            rect(s, x0, cy - bh / 2, max(bar_w, 2 * k), bh, BRAND if on else BRAND_TINT, 3 * k)
            var base = cy + 4.5 * k
            font.draw(s, self.names[i], x0 - 12 * k, base, 13 * k, INK if on else INK3, MEDIUM if self.selected == i else REGULAR, RIGHT)
            font.draw(s, self.labels[i], x0 + bar_w + 8 * k, base, 13 * k, INK if on else INK3, MEDIUM)

    def hit(self, height_pt: Float64, y_pt: Float64) -> Int:
        """The row a tap at y (points) landed on, or -1."""
        if len(self.names) == 0 or y_pt < 0 or y_pt >= height_pt:
            return -1
        return min(Int(y_pt / (height_pt / Float64(len(self.names)))), len(self.names) - 1)


# ---------- line / area over time ----------

struct LineChart(Movable):
    """A value over time (e.g. 36 months) as a line over a fading area, with a y-axis in money."""

    var labels: List[String]  # x labels ("" = no label at that point)
    var values: List[Float64]  # in cents
    var selected: Int

    def __init__(out self, var labels: List[String], var values: List[Float64], selected: Int = -1):
        self.labels = labels^
        self.values = values^
        self.selected = selected

    def plot_box(self, w: Float64, h: Float64, k: Float64, font: Font) -> SIMD[DType.float64, 4]:
        """(left, top, right, bottom) of the plotting area, in pixels."""
        var top_value = nice_max(self.max_value())
        var axis_w = font.measure(axis_money(Int(top_value)), 12 * k) + 10 * k
        return SIMD[DType.float64, 4](axis_w, 10 * k, w - 8 * k, h - 26 * k)

    def max_value(self) -> Float64:
        var top = 0.0
        for v in self.values:
            top = max(top, v)
        return top

    def draw(self, mut s: Surface, font: Font):
        var k = s.scale
        s.fill(CARD_BG)
        var n = len(self.values)
        if n < 2:
            return
        var box = self.plot_box(Float64(s.width), Float64(s.height), k, font)
        var left = box[0]
        var top = box[1]
        var right = box[2]
        var bottom = box[3]
        var top_value = nice_max(self.max_value())
        for g in range(5):  # gridlines and y labels
            var y = bottom - (bottom - top) * Float64(g) / 4.0
            hline(s, left, right, y, GRID if g > 0 else STROKE)
            font.draw(s, axis_money(Int(top_value * Float64(g) / 4.0)), left - 8 * k, y + 4 * k, 12 * k, INK2, REGULAR, RIGHT)
        var xs = List[Float64]()
        var ys = List[Float64]()
        for i in range(n):
            xs.append(left + (right - left) * Float64(i) / Float64(n - 1))
            ys.append(bottom - (bottom - top) * self.values[i] / top_value)
        for i in range(n):  # x labels
            if self.labels[i] != "":
                font.draw(s, self.labels[i], xs[i], bottom + 18 * k, 12 * k, INK2, REGULAR, CENTRE)
        area(s, xs, ys, bottom, with_alpha(BRAND, 0.22), with_alpha(BRAND, 0.0))
        for i in range(n - 1):
            line(s, xs[i], ys[i], xs[i + 1], ys[i + 1], 2.25 * k, BRAND)
        if 0 <= self.selected < n:
            var x = xs[self.selected]
            var y = ys[self.selected]
            line(s, x, top, x, bottom, 1 * k, with_alpha(BRAND, 0.45))
            circle(s, x, y, 6 * k, CARD_BG)
            circle(s, x, y, 4.5 * k, BRAND)
            var tag = money(Int(self.values[self.selected]))
            var tw = font.measure(tag, 12 * k, MEDIUM) + 16 * k
            var tx = min(max(x - tw / 2, left), right - tw)
            var ty = max(y - 34 * k, top)
            rect(s, tx, ty, tw, 22 * k, INK, 4 * k)
            font.draw(s, tag, tx + tw / 2, ty + 15.5 * k, 12 * k, CARD_BG, MEDIUM, CENTRE)

    def hit(self, width_px: Float64, height_px: Float64, scale: Float64, font: Font, x_pt: Float64) -> Int:
        """The point nearest a tap at x (points), or -1 outside the plot."""
        var n = len(self.values)
        if n < 2:
            return -1
        var box = self.plot_box(width_px, height_px, scale, font)
        var x = x_pt * scale
        if x < box[0] - 12 * scale or x > box[2] + 12 * scale:
            return -1
        var i = Int((x - box[0]) / (box[2] - box[0]) * Float64(n - 1) + 0.5)
        return min(max(i, 0), n - 1)


# ---------- columns and histograms ----------

struct ColumnChart(Movable):
    """Vertical bars with a label under each (categories) or under some (histogram bins).
    `gap` = space between bars as a share of each slot (small for histograms)."""

    var labels: List[String]
    var values: List[Float64]
    var top_labels: List[String]  # text above each bar ("" = none)
    var selected: Int
    var gap: Float64
    var color: UInt32

    def __init__(out self, var labels: List[String], var values: List[Float64], var top_labels: List[String],
                 selected: Int = -1, gap: Float64 = 0.35, color: UInt32 = BRAND):
        self.labels = labels^
        self.values = values^
        self.top_labels = top_labels^
        self.selected = selected
        self.gap = gap
        self.color = color

    def draw(self, mut s: Surface, font: Font):
        var k = s.scale
        s.fill(CARD_BG)
        var n = len(self.values)
        if n == 0:
            return
        var left = 4 * k
        var right = Float64(s.width) - 4 * k
        var top = 22 * k
        var bottom = Float64(s.height) - 24 * k
        var vmax = 0.0
        for v in self.values:
            vmax = max(vmax, v)
        var slot = (right - left) / Float64(n)
        hline(s, left, right, bottom, STROKE)
        for i in range(n):
            var on = self.selected < 0 or self.selected == i
            var bh = (bottom - top) * (self.values[i] / vmax if vmax > 0 else 0)
            var bw = slot * (1 - self.gap)
            var x = left + slot * Float64(i) + (slot - bw) / 2
            var fill = self.color if on else BRAND_TINT
            rect(s, x, bottom - bh, bw, bh, fill, min(3 * k, bh / 2))
            rect(s, x, bottom - min(3 * k, bh), bw, min(3 * k, bh), fill)  # square bottoms on the axis
            if i < len(self.top_labels) and self.top_labels[i] != "":
                font.draw(s, self.top_labels[i], x + bw / 2, bottom - bh - 7 * k, 12 * k, INK if on else INK3, MEDIUM, CENTRE)
            if self.labels[i] != "":
                font.draw(s, self.labels[i], x + bw / 2, bottom + 17 * k, 12 * k, INK2 if on else INK3,
                          MEDIUM if self.selected == i else REGULAR, CENTRE)

    def hit(self, width_pt: Float64, x_pt: Float64) -> Int:
        var n = len(self.values)
        if n == 0 or x_pt < 4 or x_pt > width_pt - 4:
            return -1
        return min(Int((x_pt - 4) / ((width_pt - 8) / Float64(n))), n - 1)
