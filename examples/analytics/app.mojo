# Contoso Retail: a sales dashboard over 20 million order lines, in one Mojo file.
#
# Every time a filter changes, all 20 million rows are added up again on the GPU (by month, by
# category, by region, by product, by order size, by year), exactly, to the cent. The charts are
# Flint specs (Microsoft's chart language for AI agents) drawn by mojoui on canvases (the same on every
# platform); the controls around them are each
# platform's own, styled in Fluent 2. Tap a month, a category or a region to filter everything else.
#
# The data is made up (a seeded generator below): three years of order lines with growth,
# weekends, holiday peaks, summer for outdoor gear and a shift to online.

from mojoui.maths import sqrt, log, sin, cos
from mojoui import (
    App, Event, View, Surface, rgba, VStack, HStack, Text, Button, Segmented, Dropdown, Divider, Canvas, Card, Spacer,
    TITLE, HEADLINE, CAPTION, PROMINENT, START, CENTER, BETWEEN, TAP, FLUENT, NO_MSG,
)
from mojoui.gpu import Table, Row, Filter, gpu_present
from mojoui.text import Font
from mojoui.charts import money, compact, grouped, fixed
from mojoui.flint import FlintChart
from mojoui.mxframe import MxFrame, GroupSums
from mojoui.shared import put_shared, get_shared, at, count_load
from mojoui.shared import keep as keep_shared
from std.memory import Pointer

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
comptime CHART_PRODUCTS = 8

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
    """Every month of every year (the year filter ignored): the chart shows the selected year's
    twelve, and a month can be compared with the same month a year before."""
    var g = Filter(0, DAYS - 1, f[2], f[3], f[4], f[5], 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    return Int(r[7]) if keep(r, g, 3) else -1


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
    var table_addr: Int  # the 20M rows, built once per process (init_shared) and shared by every session
    var font: Font
    var year: Int  # 0 = all, 1–3 = 2023–2025
    var channel: Int  # 0 = all
    var category: Int  # -1 = all
    var region: Int
    var month: Int
    var engine: Int  # 0 = this file's GPU kernels, 1 = the same on the CPU, 2 = MX frame
    var mx: List[MxFrame]  # MX frame over the same rows (made the first time it's picked)
    var version: Int
    # results
    var month_rev: List[Int]
    var month_orders: List[Int]
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

    @staticmethod
    def init_shared():
        if get_shared(10) != 0:
            return
        put_shared(10, keep_shared(generate(20_000_000 if gpu_present() else 2_000_000)))
        count_load()

    def table(self) -> Pointer[Table, MutUntrackedOrigin]:
        return at[Table](self.table_addr)

    def __init__(out self):
        if get_shared(10) == 0:  # no host built the shared data (a test constructing the app directly)
            Self.init_shared()
        self.table_addr = get_shared(10)
        self.font = Font()
        self.year = 0
        self.channel = 0
        self.category = -1
        self.region = -1
        self.month = -1
        self.engine = 0 if at[Table](self.table_addr)[].on_gpu() else 1
        self.mx = List[MxFrame]()
        self.version = 0
        self.month_rev = List[Int]()
        self.month_orders = List[Int]()
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
        self.sizes = List[Tuple[Float64, Float64]](length=9, fill=(0.0, 0.0))
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

    def mx_sum(mut self, by: String, value: String, groups: Int, skip: String, all_years: Bool = False) -> GroupSums:
        """One group-by through MX frame, with every filter except `skip` (crossfiltering)."""
        var f = self.filter()
        var ranges = List[Tuple[String, Int, Int]]()
        var equals = List[Tuple[String, Int]]()
        if skip != "year" and not all_years:
            ranges.append(("day", Int(f[0]), Int(f[1])))
        if self.channel > 0:
            equals.append(("channel", self.channel - 1))
        if self.category >= 0 and skip != "category":
            equals.append(("category", self.category))
        if self.region >= 0 and skip != "region":
            equals.append(("region", self.region))
        if self.month >= 0 and skip != "month":
            equals.append(("month", self.month))
        return self.mx[0].group_sum(by, value, groups, ranges, equals)

    def compute(mut self):
        """Adds up all the rows again for every chart (GPU kernels, the same on the CPU, or MX frame)."""
        if self.engine == 2:
            if len(self.mx) == 0:
                self.mx.append(MxFrame(self.table()[], ["day", "category", "region", "channel", "product", "quantity", "cents", "month"],
                                       [("bin", "cents", 5000, BINS - 1), ("year", "month", 12, 2)]))
            if self.mx[0].ready:
                var m = self.mx_sum("month", "cents", MONTHS, "month", all_years=True)
                var c = self.mx_sum("category", "cents", 8, "category")
                var r = self.mx_sum("region", "cents", 5, "region")
                var p = self.mx_sum("product", "cents", 64, "")
                var sz = self.mx_sum("bin", "cents", BINS, "")
                var y = self.mx_sum("year", "cents", 3, "year")
                var yu = self.mx_sum("year", "quantity", 3, "year")
                if self.mx[0].ready:  # (a query can fail; then the CPU answers, and the sidebar says why)
                    self.store(m, c, r, p, sz, y, yu)
                    return
        var f = self.filter()
        var on = self.engine == 0  # (MX frame unavailable: the CPU)
        var m = self.table()[].group_sum[by_month, cents](MONTHS, f, on)
        var c = self.table()[].group_sum[by_category, cents](8, f, on)
        var r = self.table()[].group_sum[by_region, cents](5, f, on)
        var p = self.table()[].group_sum[by_product, cents](64, f, on)
        var s = self.table()[].group_sum[by_size, cents](BINS, f, on)
        var y = self.table()[].group_sum[by_year, cents](3, f, on)
        var yu = self.table()[].group_sum[by_year, units](3, f, on)
        self.store(m, c, r, p, s, y, yu)

    def store(mut self, m: GroupSums, c: GroupSums, r: GroupSums, p: GroupSums, s: GroupSums, y: GroupSums, yu: GroupSums):
        self.milliseconds = m.milliseconds + c.milliseconds + r.milliseconds + p.milliseconds + s.milliseconds + y.milliseconds + yu.milliseconds
        self.passes = 7
        self.month_rev = m.sums.copy()
        self.month_orders = m.counts.copy()
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

    def change(self, values: List[Int], monthly: List[Int]) -> String:
        """Year-on-year change: the selected month against the same month a year before, else the
        selected year (or 2025 when all years are shown) against the year before."""
        if self.month >= 0:
            if len(monthly) == 0:
                return "in " + materialize[MONTH_NAMES]()[self.month % 12] + " " + String(2023 + self.month // 12)
            if self.month < 12 or monthly[self.month - 12] == 0:
                return "First year of data"
            var pct = (Float64(monthly[self.month]) / Float64(monthly[self.month - 12]) - 1.0) * 100.0
            return ("+" if pct >= 0 else "") + fixed(pct, 1) + "% vs " + materialize[MONTH_NAMES]()[self.month % 12] + " " + String(2022 + self.month // 12)
        var y = 2 if self.year == 0 else self.year - 1
        if y == 0 or values[y - 1] == 0:
            return "First year of data"
        var pct = (Float64(values[y]) / Float64(values[y - 1]) - 1.0) * 100.0
        return (String(2023 + y) + ": " if self.year == 0 else "") + ("+" if pct >= 0 else "") + fixed(pct, 1) + "% vs " + String(2022 + y)

    def spark(self, values: List[Int]) -> List[Float64]:
        """The selected period's months."""
        var out = List[Float64]()
        var first = 0 if self.year == 0 else (self.year - 1) * 12
        for m in range(first, first + (MONTHS if self.year == 0 else 12)):
            out.append(Float64(values[m]))
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
            self.engine = event.number if (event.number != 0 or self.table()[].on_gpu()) else 1
            self.compute()
        elif event.message == CLEAR:
            self.category = -1
            self.region = -1
            self.month = -1
            self.compute()
        elif event.message == TAP_CATEGORY and event.number == TAP:
            var row = self.category_chart().hit(self.sizes[CHART_CATEGORY][0], self.sizes[CHART_CATEGORY][1], self.font, event.x, event.y)
            if row >= 0:
                var c = self.cat_order[row]
                self.category = -1 if self.category == c else c
                self.compute()
        elif event.message == TAP_REGION and event.number == TAP:
            var col = self.region_chart().hit(self.sizes[CHART_REGION][0], self.sizes[CHART_REGION][1], self.font, event.x, event.y)
            if col >= 0:
                self.region = -1 if self.region == col else col
                self.compute()
        elif event.message == TAP_MONTH and event.number == TAP:
            var i = self.month_chart().hit(self.sizes[CHART_MONTH][0], self.sizes[CHART_MONTH][1], self.font, event.x, event.y)
            var first = 0 if self.year == 0 else (self.year - 1) * 12
            if i >= 0:
                var m = first + i
                self.month = -1 if self.month == m else m
                self.compute()

    # ---------- charts, as Flint specs ----------

    def month_chart(self) -> FlintChart:
        var labels = List[String]()
        var values = List[Float64]()
        var first = 0 if self.year == 0 else (self.year - 1) * 12
        var names = materialize[MONTH_NAMES]()
        for i in range(MONTHS if self.year == 0 else 12):
            var m = first + i
            labels.append(names[m % 12] + (" " + String(23 + m // 12) if self.year == 0 else ""))
            values.append(Float64(self.month_rev[m]))
        return (FlintChart("Area Chart", "Revenue by month").text("month", labels).number("revenue", values)
                .semantic("month", "Month").semantic("revenue", "Price").encode("x", "month").encode("y", "revenue")
                .size(720, 260))

    def category_chart(self) -> FlintChart:
        var cats = materialize[CATEGORIES]()
        var names = List[String]()
        var values = List[Float64]()
        for k in range(8):
            names.append(cats[self.cat_order[k]])
            values.append(Float64(self.cat_rev[self.cat_order[k]]))
        return (FlintChart("Bar Chart", "Revenue by category").text("category", names).number("revenue", values)
                .semantic("category", "Category").semantic("revenue", "Price").encode("x", "revenue").encode("y", "category")
                .property("cornerRadius", "3").size(400, 260))

    def region_chart(self) -> FlintChart:
        var values = List[Float64]()
        for r in range(5):
            values.append(Float64(self.region_rev[r]))
        return (FlintChart("Bar Chart", "Revenue by region").text("region", materialize[REGIONS_SHORT]()).number("revenue", values)
                .semantic("region", "Region").semantic("revenue", "Price").encode("x", "region").encode("y", "revenue")
                .property("cornerRadius", "3").property("showValueLabels", "true").size(380, 300))

    def size_chart(self) -> FlintChart:
        var labels = List[String]()
        var values = List[Float64]()
        for b in range(BINS):  # each bin's start; the last one is open-ended
            labels.append("$" + grouped(b * 50) + ("+" if b == BINS - 1 else ""))
            values.append(Float64(self.size_orders[b]))
        return (FlintChart("Bar Chart", "Orders by size").text("order value", labels).number("orders", values)
                .semantic("order value", "Range").semantic("orders", "Count").encode("x", "order value").encode("y", "orders")
                .size(420, 300))

    def products_chart(self) -> FlintChart:
        var names = materialize[PRODUCTS]()
        var products = List[String]()
        var values = List[Float64]()
        for k in range(8):
            products.append(names[self.top[k]])
            values.append(Float64(self.product_rev[self.top[k]]))
        return (FlintChart("Bar Table", "Top products").text("product", products).number("revenue", values)
                .semantic("product", "Name").semantic("revenue", "Price").encode("y", "product").encode("x", "revenue")
                .property("maxRows", "8").size(320, 300))

    def kpi(self, metric: String, value: Int) -> FlintChart:
        var chart = FlintChart("KPI Card", metric).text("metric", [metric]).number("value", [Float64(value)])
        chart = chart^.encode("metric", "metric").encode("value", "value").size(240, 118)
        if metric == "Revenue":
            chart = chart^.semantic("value", "Price")
        return chart^

    def charts(self) -> List[FlintChart]:
        """Every chart on the dashboard, as Flint specs (in canvas order)."""
        var revenue = self.total(self.year_rev)
        var orders = self.total(self.year_orders)
        var out = List[FlintChart]()
        out.append(self.kpi("Revenue", revenue))
        out.append(self.kpi("Order lines", orders))
        out.append(self.kpi("Average line", revenue // max(orders, 1)).semantic("value", "Price"))
        out.append(self.kpi("Units sold", self.total(self.year_units)))
        out.append(self.month_chart())
        out.append(self.category_chart())
        out.append(self.region_chart())
        out.append(self.size_chart())
        out.append(self.products_chart())
        return out^

    def draw(mut self, canvas: Int, mut surface: Surface):
        self.sizes[canvas] = (surface.points_width(), surface.points_height())
        if canvas == KPI_REVENUE:
            var c = self.kpi("Revenue", self.total(self.year_rev)).number("trend", self.spark(self.month_rev))
            c.draw(surface, self.font, -1, True, self.change(self.year_rev, self.month_rev))
        elif canvas == KPI_ORDERS:
            self.kpi("Order lines", self.total(self.year_orders)).draw(surface, self.font, -1, False, self.change(self.year_orders, self.month_orders))
        elif canvas == KPI_AOV:
            var aov = self.total(self.year_rev) // max(self.total(self.year_orders), 1)
            self.kpi("Average line", aov).semantic("value", "Price").draw(surface, self.font, -1, False, "revenue per order line")
        elif canvas == KPI_UNITS:
            self.kpi("Units sold", self.total(self.year_units)).draw(surface, self.font, -1, False, self.change(self.year_units, List[Int]()))
        elif canvas == CHART_MONTH:
            var first = 0 if self.year == 0 else (self.year - 1) * 12
            self.month_chart().draw(surface, self.font, self.month - first if self.month >= 0 else -1)
        elif canvas == CHART_CATEGORY:
            var selected = -1
            for k in range(8):
                if self.cat_order[k] == self.category:
                    selected = k
            self.category_chart().draw(surface, self.font, selected)
        elif canvas == CHART_REGION:
            self.region_chart().draw(surface, self.font, self.region)
        elif canvas == CHART_SIZE:
            self.size_chart().draw(surface, self.font)
        elif canvas == CHART_PRODUCTS:
            self.products_chart().draw(surface, self.font)

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
        var engine = self.table()[].device_name() if self.engine == 0 else (String("the CPU (Mojo loops)") if self.engine == 1 else String("MX frame (CPU)"))
        if self.engine == 2 and len(self.mx) > 0 and not self.mx[0].ready:
            engine = "the CPU: MX frame unavailable (" + self.mx[0].problem + ")"
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
            Segmented(["GPU", "CPU", "MX frame"], self.engine, on_select=ENGINE).fill(),
            Text(grouped(self.table()[].count) + " rows, " + String(self.passes) + " passes", style=CAPTION),
            Text("Recomputed in " + fixed(self.milliseconds, 1) + " ms on " + engine, style=CAPTION).max_width(244),
            Spacer(),
            Text("One Mojo file · mojo-ui", style=CAPTION),
            spacing=10,
        ).width(284).padding(20, 20).align(START).fill().tag("sidebar")
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
                Canvas(CHART_PRODUCTS, self.version).grow().fill(),
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
        ).grow().fill().padding(20, 24).tag("main")
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
