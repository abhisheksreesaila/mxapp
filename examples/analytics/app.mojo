# Contoso Retail: a sales dashboard over 20 million order lines, in one Mojo file.
#
# Every time a filter changes, all 20 million rows are added up again on the GPU (by month, by
# category, by region, by product, by order size, by year), exactly, to the cent. The charts are
# drawn by this file on canvases (the same on every platform); the controls around them are each
# platform's own, styled in Fluent 2. Tap a month, a category or a region to filter everything else.
#
# The data is made up (a seeded generator below): three years of order lines with growth,
# weekends, holiday peaks, summer for outdoor gear and a shift to online.

from mojoui.maths import sqrt, log, sin, cos
from mojoui import (
    App, Event, View, Surface, rgba, VStack, HStack, Text, Button, Segmented, Dropdown, Divider, Canvas, Card, LazyList, Spacer,
    TITLE, HEADLINE, CAPTION, PROMINENT, START, CENTER, BETWEEN, TAP, FLUENT, NO_MSG,
)
from mojoui.gpu import Table, Row, Filter, gpu_present
from mojoui.text import Font
from mojoui.charts import KpiTile, BarChart, LineChart, ColumnChart, money, compact, grouped, fixed

comptime YEAR = 1
comptime CHANNEL = 2
comptime CLEAR = 3
comptime ENGINE = 4
comptime TAP_MONTH = 5
comptime TAP_CATEGORY = 6
comptime TAP_REGION = 7

# canvases
comptime KPI_REVENUE = 0
comptime KPI_ORDERS = 1
comptime KPI_AOV = 2
comptime KPI_UNITS = 3
comptime CHART_MONTH = 4
comptime CHART_CATEGORY = 5
comptime CHART_REGION = 6
comptime CHART_SIZE = 7

comptime DAYS = 1096  # 2023-01-01 … 2025-12-31
comptime MONTHS = 36
comptime BINS = 24  # order value: $0–$1,200 in $50 steps (the last bin: $1,150 and up)

comptime CATEGORIES: List[String] = ["Electronics", "Home", "Fashion", "Outdoor", "Beauty", "Toys", "Grocery", "Sports"]
comptime REGIONS: List[String] = ["North America", "Europe", "Asia Pacific", "Latin America", "Middle East"]
comptime REGIONS_SHORT: List[String] = ["N. America", "Europe", "Asia Pac.", "Latin Am.", "Mid. East"]
comptime CHANNELS: List[String] = ["All channels", "Online", "Stores", "Partners"]
comptime YEARS: List[String] = ["All", "2023", "2024", "2025"]
comptime MONTH_NAMES: List[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
comptime PRODUCTS: List[String] = [
    "Noise-cancelling headphones", "4K TV 55\"", "Laptop 14\"", "Smart watch", "Tablet 11\"", "Wireless earbuds", "Game console", "Phone charger",
    "Espresso machine", "Robot vacuum", "Air fryer", "Duvet set", "Desk lamp", "Cookware set", "Office chair", "Bath towels",
    "Rain jacket", "Running shoes", "Denim jeans", "Wool sweater", "Sunglasses", "Leather bag", "Sneakers", "Summer dress",
    "Tent 4-person", "Hiking boots", "Camping stove", "Sleeping bag", "Backpack 40L", "Kayak paddle", "Garden hose", "BBQ grill",
    "Face serum", "Perfume", "Hair dryer", "Sunscreen", "Lipstick set", "Shampoo", "Electric shaver", "Nail kit",
    "Building blocks", "Board game", "RC car", "Plush bear", "Puzzle 1000", "Doll house", "Drone mini", "Art set",
    "Coffee beans", "Olive oil", "Chocolate box", "Green tea", "Pasta pack", "Honey jar", "Spice set", "Snack box",
    "Yoga mat", "Dumbbells", "Bike helmet", "Tennis racket", "Football", "Fitness band", "Water bottle", "Gym bag",
]


# ---------- the group and amount functions (run on the GPU, one call per row) ----------
# A row: (day, category, region, channel, product, quantity, cents, month).
# The filter: (first day, last day, channel or -1, category or -1, region or -1, month or -1, …).
# Each chart ignores its own filter (crossfiltering): picking a category doesn't empty the category chart.

def keep(r: Row, f: Filter, own: Int) -> Bool:
    if r[0] < f[0] or r[0] > f[1]:
        return False
    if f[2] >= 0 and r[3] != f[2]:
        return False
    if own != 1 and f[3] >= 0 and r[1] != f[3]:
        return False
    if own != 2 and f[4] >= 0 and r[2] != f[4]:
        return False
    if own != 3 and f[5] >= 0 and r[7] != f[5]:
        return False
    return True


def by_month(r: Row, f: Filter) -> Int:
    return Int(r[7]) if keep(r, f, 3) else -1


def by_category(r: Row, f: Filter) -> Int:
    return Int(r[1]) if keep(r, f, 1) else -1


def by_region(r: Row, f: Filter) -> Int:
    return Int(r[2]) if keep(r, f, 2) else -1


def by_product(r: Row, f: Filter) -> Int:
    return Int(r[4]) if keep(r, f, 0) else -1


def by_size(r: Row, f: Filter) -> Int:
    return min(Int(r[6]) // 5000, BINS - 1) if keep(r, f, 0) else -1


def by_year(r: Row, f: Filter) -> Int:
    """Every year (the year filter ignored), for year-on-year comparisons."""
    var g = Filter(0, DAYS - 1, f[2], f[3], f[4], f[5], 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    return Int(r[7]) // 12 if keep(r, g, 0) else -1


def cents(r: Row, f: Filter) -> Int:
    return Int(r[6])


def units(r: Row, f: Filter) -> Int:
    return Int(r[5])


# ---------- a made-up retailer ----------

def mix(z0: UInt64) -> UInt64:
    var z = z0 + 0x9E3779B97F4A7C15
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB
    return z ^ (z >> 31)


def uniform(i: Int, salt: Int) -> Float64:
    return Float64(Int(mix(UInt64(i) * 16 + UInt64(salt)) >> 11)) / 9007199254740992.0


def month_of(day: Int) -> Int:
    """Month 0–35 of day 0–1095 (2024 is a leap year)."""
    var lengths: List[Int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    var d = day
    for y in range(3):
        for m in range(12):
            var n = lengths[m] + (1 if y == 1 and m == 1 else 0)
            if d < n:
                return y * 12 + m
            d -= n
    return 35


def season(m: Int) -> Float64:
    """How busy each calendar month is (holiday peak, January dip)."""
    var s: List[Float64] = [0.78, 0.8, 0.92, 0.95, 1.0, 1.02, 0.98, 1.0, 0.96, 1.05, 1.42, 1.75]
    return s[m]


def generate(n: Int) -> Table:
    # Day weights: growth × weekends × season → a cumulative table to sample days from.
    var cdf = List[Float64](length=DAYS, fill=0)
    var total = 0.0
    for d in range(DAYS):
        var weekend = 1.28 if (d + 6) % 7 >= 5 else 1.0  # 2023-01-01 was a Sunday
        total += (1.0 + 0.32 * Float64(d) / Float64(DAYS)) * weekend * season(month_of(d) % 12)
        cdf[d] = total
    var month_table = List[Int](length=DAYS, fill=0)
    for d in range(DAYS):
        month_table[d] = month_of(d)
    var price = List[Int](length=64, fill=0)  # cents per product
    var base: List[Int] = [24000, 9000, 7000, 12000, 4500, 3500, 1800, 5500]
    for p in range(64):
        price[p] = Int(Float64(base[p // 8]) * (0.45 + 1.7 * uniform(p, 99)))
    var cols = List[List[Int32]]()
    for _ in range(8):
        cols.append(List[Int32](length=n, fill=0))
    for i in range(n):
        # day
        var u = uniform(i, 0) * total
        var lo = 0
        var hi = DAYS - 1
        while lo < hi:
            var mid = (lo + hi) // 2
            if cdf[mid] < u:
                lo = mid + 1
            else:
                hi = mid
        var day = lo
        var m = month_table[day] % 12
        var t = Float64(day) / Float64(DAYS)
        # category: outdoor in summer, toys and electronics at the holidays
        var w: List[Float64] = [1.25, 1.0, 1.1, 0.75, 0.7, 0.55, 0.9, 0.7]
        if 4 <= m <= 7:
            w[3] = 1.6
            w[7] = 1.0
        if m >= 10:
            w[5] = 1.7
            w[0] = 1.8
        var wt = 0.0
        for x in w:
            wt += x
        var c = 0
        var pick = uniform(i, 1) * wt
        while c < 7 and pick >= w[c]:
            pick -= w[c]
            c += 1
        # region (Asia Pacific grows), channel (online grows)
        var rw: List[Float64] = [0.34, 0.27, 0.19 + 0.08 * t, 0.10, 0.07]
        var rt = 0.0
        for x in rw:
            rt += x
        var region = 0
        var pr = uniform(i, 2) * rt
        while region < 4 and pr >= rw[region]:
            pr -= rw[region]
            region += 1
        var online = 0.42 + 0.2 * t
        var pc = uniform(i, 3)
        var channel = 0 if pc < online else (1 if pc < 0.88 else 2)
        # product: a few best sellers in each category
        var product = c * 8 + min(Int(8.0 * uniform(i, 4) * uniform(i, 5) * 1.6), 7)
        var q = uniform(i, 6)
        var qty = 1 if q < 0.62 else (2 if q < 0.86 else (3 if q < 0.95 else 4 + Int(uniform(i, 7) * 3)))
        var discount = 0 if uniform(i, 8) < (0.55 if m >= 10 else 0.78) else (10 if uniform(i, 9) < 0.7 else 25)
        var inflation = 100 + 4 * (month_table[day] // 12)  # prices rise 4% a year
        var cents = qty * price[product] * (100 - discount) // 100 * inflation // 100
        cols[0][i] = Int32(day)
        cols[1][i] = Int32(c)
        cols[2][i] = Int32(region)
        cols[3][i] = Int32(channel)
        cols[4][i] = Int32(product)
        cols[5][i] = Int32(qty)
        cols[6][i] = Int32(cents)
        cols[7][i] = Int32(month_table[day])
    return Table(cols)


# ---------- the app ----------

struct Main(App):
    var table: Table
    var font: Font
    var year: Int  # 0 = all, 1–3 = 2023–2025
    var channel: Int  # 0 = all
    var category: Int  # -1 = all
    var region: Int
    var month: Int
    var gpu: Bool  # the engine: GPU (or CPU, to compare)
    var version: Int
    # results
    var month_rev: List[Int]
    var cat_rev: List[Int]
    var region_rev: List[Int]
    var product_rev: List[Int]
    var size_orders: List[Int]
    var year_rev: List[Int]
    var year_orders: List[Int]
    var year_units: List[Int]
    var top: List[Int]  # products by revenue, best first
    var cat_order: List[Int]  # categories by revenue, best first
    var milliseconds: Float64
    var passes: Int
    var sizes: List[Tuple[Float64, Float64]]  # each canvas's size in points, from its last draw

    def __init__(out self):
        self.table = generate(20_000_000 if gpu_present() else 2_000_000)
        self.font = Font()
        self.year = 0
        self.channel = 0
        self.category = -1
        self.region = -1
        self.month = -1
        self.gpu = self.table.on_gpu()
        self.version = 0
        self.month_rev = List[Int]()
        self.cat_rev = List[Int]()
        self.region_rev = List[Int]()
        self.product_rev = List[Int]()
        self.size_orders = List[Int]()
        self.year_rev = List[Int]()
        self.year_orders = List[Int]()
        self.year_units = List[Int]()
        self.top = List[Int]()
        self.cat_order = List[Int]()
        self.milliseconds = 0
        self.passes = 0
        self.sizes = List[Tuple[Float64, Float64]](length=8, fill=(0.0, 0.0))
        self.compute()

    def title(self) -> String:
        return "Contoso Retail · Sales"

    def window_size(self) -> Tuple[Int, Int]:
        return (1440, 900)

    def design(self) -> Int:
        return FLUENT

    def filter(self) -> Filter:
        var first = 0
        var last = DAYS - 1
        if self.year > 0:
            first = (self.year - 1) * 365
            last = first + (365 if self.year == 2 else 364)  # 2024 has 366 days
            if self.year == 3:
                first = 731
                last = DAYS - 1
        return Filter(Int32(first), Int32(last), Int32(self.channel - 1), Int32(self.category), Int32(self.region), Int32(self.month),
                      0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    def compute(mut self):
        """Adds up all the rows again for every chart (on the GPU, or the CPU to compare)."""
        var f = self.filter()
        var on = self.gpu
        var m = self.table.group_sum[by_month, cents](MONTHS, f, on)
        var c = self.table.group_sum[by_category, cents](8, f, on)
        var r = self.table.group_sum[by_region, cents](5, f, on)
        var p = self.table.group_sum[by_product, cents](64, f, on)
        var s = self.table.group_sum[by_size, cents](BINS, f, on)
        var y = self.table.group_sum[by_year, cents](3, f, on)
        var yu = self.table.group_sum[by_year, units](3, f, on)
        self.milliseconds = m.milliseconds + c.milliseconds + r.milliseconds + p.milliseconds + s.milliseconds + y.milliseconds + yu.milliseconds
        self.passes = 7
        self.month_rev = m.sums.copy()
        self.cat_rev = c.sums.copy()
        self.region_rev = r.sums.copy()
        self.product_rev = p.sums.copy()
        self.size_orders = s.counts.copy()
        self.year_rev = y.sums.copy()
        self.year_orders = y.counts.copy()
        self.year_units = yu.sums.copy()
        self.top = ranked(self.product_rev)
        self.cat_order = ranked(self.cat_rev)
        self.version += 1

    # ---------- totals for the selected period ----------

    def years(self) -> List[Int]:
        if self.year == 0:
            return [0, 1, 2]
        return [self.year - 1]

    def total(self, values: List[Int]) -> Int:
        var t = 0
        for y in self.years():
            t += values[y]
        return t

    def change(self, values: List[Int]) -> String:
        """Year-on-year change of the selected year (or 2025 against 2024 when all years are shown)."""
        var y = 2 if self.year == 0 else self.year - 1
        if y == 0 or values[y - 1] == 0:
            return "First year of data"
        var pct = (Float64(values[y]) / Float64(values[y - 1]) - 1.0) * 100.0
        return ("+" if pct >= 0 else "") + fixed(pct, 1) + "% vs " + String(2022 + y)

    def spark(self, values: List[Int]) -> List[Float64]:
        var out = List[Float64]()
        for v in values:
            out.append(Float64(v))
        return out^

    # ---------- events ----------

    def update(mut self, event: Event):
        if event.message == YEAR:
            self.year = event.number
            self.month = -1
            self.compute()
        elif event.message == CHANNEL:
            self.channel = event.number
            self.compute()
        elif event.message == ENGINE:
            self.gpu = event.number == 0 and self.table.on_gpu()
            self.compute()
        elif event.message == CLEAR:
            self.category = -1
            self.region = -1
            self.month = -1
            self.compute()
        elif event.message == TAP_CATEGORY and event.number == TAP:
            var chart = self.category_chart()
            var row = chart.hit(self.sizes[CHART_CATEGORY][1], event.y)
            if row >= 0:
                var c = self.cat_order[row]
                self.category = -1 if self.category == c else c
                self.compute()
        elif event.message == TAP_REGION and event.number == TAP:
            var col = self.region_chart().hit(self.sizes[CHART_REGION][0], event.x)
            if col >= 0:
                self.region = -1 if self.region == col else col
                self.compute()
        elif event.message == TAP_MONTH and event.number == TAP:
            var w = self.sizes[CHART_MONTH][0]
            var h = self.sizes[CHART_MONTH][1]
            var k = 2.0  # (hit-testing in points; the scale only sets label widths)
            var i = self.month_chart().hit(w * k, h * k, k, self.font, event.x)
            var first = 0 if self.year == 0 else (self.year - 1) * 12
            if i >= 0:
                var m = first + i
                self.month = -1 if self.month == m else m
                self.compute()

    # ---------- charts ----------

    def month_chart(self) -> LineChart:
        var labels = List[String]()
        var values = List[Float64]()
        var first = 0 if self.year == 0 else (self.year - 1) * 12
        var count = MONTHS if self.year == 0 else 12
        var names = materialize[MONTH_NAMES]()
        for i in range(count):
            var m = first + i
            if self.year == 0:
                labels.append(names[m % 12] + " " + String(23 + m // 12) if m % 6 == 0 else "")
            else:
                labels.append(names[m % 12] if i % 2 == 0 else "")
            values.append(Float64(self.month_rev[m]))
        return LineChart(labels^, values^, self.month - first if self.month >= 0 else -1)

    def category_chart(self) -> BarChart:
        var cats = materialize[CATEGORIES]()
        var names = List[String]()
        var values = List[Float64]()
        var labels = List[String]()
        var selected = -1
        for k in range(8):
            var c = self.cat_order[k]
            names.append(cats[c])
            values.append(Float64(self.cat_rev[c]))
            labels.append(money(self.cat_rev[c]))
            if c == self.category:
                selected = k
        return BarChart(names^, values^, labels^, selected)

    def region_chart(self) -> ColumnChart:
        var names = materialize[REGIONS_SHORT]()
        var values = List[Float64]()
        var tops = List[String]()
        for r in range(5):
            values.append(Float64(self.region_rev[r]))
            tops.append(money(self.region_rev[r]))
        return ColumnChart(names^, values^, tops^, self.region)

    def size_chart(self) -> ColumnChart:
        var labels = List[String]()
        var values = List[Float64]()
        var tops = List[String]()
        for b in range(BINS):
            labels.append(("$" + String(b * 50) if b * 50 < 1000 else "$" + fixed(Float64(b * 50) / 1000.0, 1) + "K") if b % 4 == 0 else "")
            values.append(Float64(self.size_orders[b]))
            tops.append("")
        return ColumnChart(labels^, values^, tops^, -1, 0.14, rgba(42, 160, 164))  # Fluent teal

    def draw(mut self, canvas: Int, mut surface: Surface):
        self.sizes[canvas] = (surface.points_width(), surface.points_height())
        var revenue = self.total(self.year_rev)
        var orders = self.total(self.year_orders)
        var unit_count = self.total(self.year_units)
        if canvas == KPI_REVENUE:
            KpiTile("Revenue", money(revenue), self.change(self.year_rev), self.spark(self.month_rev), accent=True).draw(surface, self.font)
        elif canvas == KPI_ORDERS:
            KpiTile("Orders", compact(Float64(orders)), self.change(self.year_orders), List[Float64]()).draw(surface, self.font)
        elif canvas == KPI_AOV:
            var aov = revenue // max(orders, 1)
            KpiTile("Average order", "$" + fixed(Float64(aov) / 100.0, 2), "per order line", List[Float64]()).draw(surface, self.font)
        elif canvas == KPI_UNITS:
            KpiTile("Units sold", compact(Float64(unit_count)), self.change(self.year_units), List[Float64]()).draw(surface, self.font)
        elif canvas == CHART_MONTH:
            self.month_chart().draw(surface, self.font)
        elif canvas == CHART_CATEGORY:
            self.category_chart().draw(surface, self.font)
        elif canvas == CHART_REGION:
            self.region_chart().draw(surface, self.font)
        elif canvas == CHART_SIZE:
            self.size_chart().draw(surface, self.font)

    def row(self, list_id: Int, index: Int) -> String:
        if index >= len(self.top):
            return ""
        var p = self.top[index]
        var names = materialize[PRODUCTS]()
        return String(index + 1) + ".  " + names[p] + "   " + money(self.product_rev[p])

    # ---------- the screen ----------

    def selection(self) -> String:
        var parts = List[String]()
        if self.category >= 0:
            parts.append(materialize[CATEGORIES]()[self.category])
        if self.region >= 0:
            parts.append(materialize[REGIONS]()[self.region])
        if self.month >= 0:
            parts.append(materialize[MONTH_NAMES]()[self.month % 12] + " " + String(2023 + self.month // 12))
        if len(parts) == 0:
            return "Nothing selected: tap a month, a category or a region to filter"
        var out = String("")
        for i in range(len(parts)):
            out += (" · " if i > 0 else "") + parts[i]
        return out

    def view(self) -> View:
        var revenue = self.total(self.year_rev)
        var orders = self.total(self.year_orders)
        var period = "2023–2025" if self.year == 0 else materialize[YEARS]()[self.year]
        var engine = self.table.device_name() if self.gpu else String("CPU")
        var sidebar = VStack(
            Text("Contoso Retail", style=HEADLINE),
            Text("Sales analytics", style=CAPTION),
            Divider().fill(),
            Text("Year", style=CAPTION),
            Segmented(materialize[YEARS](), self.year, on_select=YEAR).fill(),
            Text("Channel", style=CAPTION),
            Dropdown(materialize[CHANNELS](), self.channel, on_select=CHANNEL).fill(),
            Text("Selection", style=CAPTION),
            Text(self.selection()).max_width(244).tag("selection"),
            Button("Clear selection", on_tap=CLEAR),
            Divider().fill(),
            Text("Engine", style=CAPTION),
            Segmented(["GPU", "CPU"], 0 if self.gpu else 1, on_select=ENGINE).fill(),
            Text(grouped(self.table.count) + " rows, " + String(self.passes) + " passes", style=CAPTION),
            Text("Recomputed in " + fixed(self.milliseconds, 1) + " ms on " + engine, style=CAPTION).max_width(244),
            Spacer(),
            Text("One Mojo file · mojo-ui", style=CAPTION),
            spacing=10,
        ).width(284).padding(20, 20).align(START).fill()
        var kpis = HStack(
            Canvas(KPI_REVENUE, self.version).grow().height(118).tag("kpi_revenue"),
            Canvas(KPI_ORDERS, self.version).grow().height(118).tag("kpi_orders"),
            Canvas(KPI_AOV, self.version).grow().height(118).tag("kpi_aov"),
            Canvas(KPI_UNITS, self.version).grow().height(118).tag("kpi_units"),
            spacing=16,
        ).fill()
        var row1 = HStack(
            Card(
                Text("Revenue by month", style=HEADLINE),
                Canvas(CHART_MONTH, self.version, on_gesture=TAP_MONTH).grow().fill(),
                spacing=8,
            ).grow().fill().tag("card_month"),
            Card(
                Text("Revenue by category", style=HEADLINE),
                Canvas(CHART_CATEGORY, self.version, on_gesture=TAP_CATEGORY).grow().fill(),
                spacing=8,
            ).width(400).fill().tag("card_category"),
            spacing=16,
        ).grow().fill()
        var row2 = HStack(
            Card(
                Text("Revenue by region", style=HEADLINE),
                Canvas(CHART_REGION, self.version, on_gesture=TAP_REGION).grow().fill(),
                spacing=8,
            ).width(380).fill().tag("card_region"),
            Card(
                Text("Orders by size", style=HEADLINE),
                Canvas(CHART_SIZE, self.version).grow().fill(),
                spacing=8,
            ).grow().fill().tag("card_size"),
            Card(
                Text("Top products", style=HEADLINE),
                LazyList(10, 0, height=120, row_height=32).grow().fill(),
                spacing=8,
            ).width(300).fill().tag("card_products"),
            spacing=16,
        ).grow().fill()
        var main = VStack(
            HStack(
                Text("Sales overview · " + period, style=TITLE),
                Text(money(revenue) + " revenue · " + grouped(orders) + " order lines", style=CAPTION).tag("summary"),
                spacing=16,
            ).justify(BETWEEN).fill(),
            kpis,
            row1,
            row2,
            spacing=16,
        ).grow().fill().padding(20, 24)
        return HStack(sidebar, main, spacing=0).grow().fill()


def ranked(values: List[Int]) -> List[Int]:
    """Indexes of `values`, largest first."""
    var order = List[Int]()
    for i in range(len(values)):
        order.append(i)
    for i in range(1, len(order)):  # insertion sort (small lists)
        var j = i
        while j > 0 and values[order[j - 1]] < values[order[j]]:
            var t = order[j - 1]
            order[j - 1] = order[j]
            order[j] = t
            j -= 1
    return order^
