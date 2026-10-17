# MX Studio · Sheet (docs/mx-studio/SCREENS.md §1): the orders ledger as a page of objects over one engine:
# a transactions grid (every row, editable in place), a pivot and a chart that follow every edit, an
# inspector that says where the table comes from and what you changed, and an agent's finding (one customer
# under three spellings) that merges in one undoable step. Built from mojoui components only: DataGrid,
# PivotTable, ChartView, Card tones, Overlay islands, Segmented, Tabs.

from mojoui.view import (View, Text, Button, TextField, Canvas, Board, Overlay, VStack, HStack, Card, Spacer, Segmented, Tabs, TAP,
                         HEADLINE, CAPTION, TITLE, PROMINENT, SUBTLE, ICON_ONLY, START, CENTER, END, BETWEEN, OMARCHY,
                         CARD, CARD_WARN, CARD_GOOD, TONE_WARN, TONE_GOOD, TONE_STRONG, TONE_ACCENT, NO_MSG)
from mojoui.app import App, Event
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.charts import money, grouped, fixed
from mojoui.datagrid import DataGrid, GRID_SELECTED, GRID_COLUMN, GRID_EDIT, GRID_READ_ONLY, GRID_REDRAW, GRID_FITTED, GRID_RESIZED, GRID_TYPED, GRID_CLEAR, GRID_CANCEL
from mojoui.pivot import PivotTable
from mojoui.chartview import ChartView
from mojoui.kpi import KpiView
from mojoui.finding import FindingCard
from mojoui.view import Dropdown
from mojoui.frame import Range
from mojoui.frame import Frame, share, MERGE, SET
from mojoui.frame_gpu import GpuFrame, group_sum
from mojoui.gpu import gpu_present
from mojoui.shared import put_shared, get_shared, keep, at, count_load, environment
from mojoui.orders import order_columns, CUSTOMER, PRODUCT, REGION, CARRIER, REVENUE, COST, FREIGHT, ORDER, DAY, ZIP, WEIGHT, YEAR_START, RATE_CHANGE, REGIONS, PRODUCTS
from mojoui.orders_ops import (col_program, totals_by, fold, find_duplicate_names, customer_product, histogram, rows_with, text_groups, Finding, Totals, Pivot)
from mojoui.orders_report import (kpis, weekly, margin_heatmap, shares, worst_margin_fall, quarter_range, quarter_days, shares_by_region_product, Kpis, Weekly, Grid2, Anomaly, WEEKS)
from mojoui.view import TextArea

# messages
comptime GRID = 1
comptime CHART_TAP = 2
comptime CELL_COMMIT = 3
comptime MODE = 4
comptime SHEET = 5
comptime MERGE_NAMES = 6
comptime UNDO_ALL = 7
comptime SHOW_ROWS = 8
comptime ALL_ROWS = 9
comptime MOVE = 10
comptime SORT = 11
comptime FIND = 12
comptime CELL_CANCEL = 13
comptime QUARTER = 20  # Report: filters, taps, actions
comptime REGION_PICK = 21
comptime PRODUCT_PICK = 22
comptime TAP_LINE = 23
comptime TAP_CUSTOMERS = 24
comptime TAP_MIX = 25
comptime TAP_HEAT = 26
comptime OPEN_ROWS = 27
comptime REPORT_PAGE = 28
comptime QUARTERS: List[String] = ["Q1", "Q2", "Q3", "Q4"]
comptime REPORT_PAGES: List[String] = ["Revenue", "Margin", "Customers"]
comptime MONTHS: List[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct"]

# the page: objects at fixed places (draggable by their headers)
comptime PAGE_X = 24
comptime PAGE_Y = 80
comptime CARD_PAD_X = 14
comptime GRID_TOP = 54  # padding 12 + header row 32 + gap 10 (the grid's place inside its card)
comptime TABLE = 0  # object kinds (the first four objects are these, in this order)
comptime PIVOT = 1
comptime AGENT = 2
comptime CHART = 3
comptime REGION_PIVOT = 4  # inserted: revenue by region × product
comptime REGION_CHART = 5  # inserted: revenue by region
comptime NOTE = 6  # inserted: text
comptime INSERT = 30  # + the kind (Pivot, Chart, Note) or INSERT_FORMULA / INSERT_TABLE
comptime INSERT_FORMULA = 40
comptime INSERT_TABLE = 41
comptime FORMULA = 42
comptime NOTE_TEXT = 50  # + object index
comptime PAGE_W = 1040  # where new objects go (the inspector floats over the right side)
comptime MAX_OBJECTS = 24
comptime MODES: List[String] = ["Sheet", "Report", "Explore", "Query"]
comptime SHEETS: List[String] = ["Orders", "Customers", "Products"]
comptime TOP_CUSTOMERS = 8


struct Main(App):
    var frame: Frame
    var gf_addr: Int
    var font: Font
    var pal: Palette
    var grid: DataGrid
    var kinds: List[Int]  # per object on the page: TABLE, PIVOT, AGENT, CHART, then inserted ones
    var x: List[Int]
    var y: List[Int]
    var w: List[Int]
    var h: List[Int]
    var notes: List[String]  # per object (NOTE)
    var sizes: List[Tuple[Float64, Float64]]  # per canvas id: its size when last drawn (points)
    var reveal_k: Int
    var reveal_count: Int
    var formula_open: Bool
    var region_pivot: List[Int]  # revenue by region × product (cents), when an inserted object needs it
    var mode: Int
    var sheet: Int
    var customers: Totals  # rows and revenue per customer code (raw; fold() applies merges)
    var pivot: Pivot
    var findings: List[Finding]
    var chart_pick: Int
    var revenue: Int
    var rows: Int
    var margin: Int
    var milliseconds: Float64
    var message: String
    var edit_text: String
    var showing: String  # what the grid is filtered to ("" = every row)
    var lows: List[Int64]  # per column: min and max (for the header histograms' bins)
    var highs: List[Int64]
    var version: Int
    # Report
    var quarter: Int
    var region: Int  # -1 = all
    var product: Int  # -1 = all
    var now: Kpis
    var before: Kpis
    var weeks: Weekly
    var heat: Grid2
    var mix: Grid2
    var top: Grid2  # revenue per customer (merged folded)
    var unmerged_top: Int  # the top customer's revenue under its main spelling only (what merging adds)
    var anomaly: Anomaly
    var anomaly_at: Int  # the frame's edit count when the anomaly was found (it ignores filters: found again only after edits)
    var report_ms: Float64

    @staticmethod
    def init_shared():
        if get_shared(0) != 0:
            return
        var rows = 2_000_000
        var asked = environment("MOJOUI_ROWS")
        if asked != "":
            try:
                rows = max(Int(asked), 10_000)
            except:
                pass
        var addr = share(order_columns(rows))
        put_shared(0, addr)
        put_shared(1, keep(GpuFrame(addr)))
        count_load()

    def __init__(out self):
        if get_shared(0) == 0:
            Self.init_shared()
        self.frame = Frame(get_shared(0))
        self.gf_addr = get_shared(1)
        self.font = Font()
        self.pal = Palette.omarchy()
        self.grid = DataGrid()
        self.kinds = [TABLE, PIVOT, AGENT, CHART]
        self.x = [0, 416, 0, 0]  # the table across the top; the agent's card and Chart 1 left, Pivot 1 right
        self.y = [0, 516, 516, 756]
        self.w = [900, 624, 400, 400]  # (900: clear of the inspector even in a 1280-pt window)
        self.h = [500, 524, 224, 284]
        self.notes = ["", "", "", ""]
        self.sizes = List[Tuple[Float64, Float64]](length=64, fill=(400.0, 240.0))
        self.reveal_k = -1
        self.reveal_count = 0
        self.formula_open = False
        self.region_pivot = List[Int]()
        self.mode = 0
        self.sheet = 0
        self.customers = Totals(List[Int](), List[Int](), 0)
        self.pivot = Pivot(List[Int](), List[Int](), 0, 0)
        self.findings = List[Finding]()
        self.chart_pick = -1
        self.revenue = 0
        self.rows = 0
        self.margin = 0
        self.milliseconds = 0
        self.message = ""
        self.edit_text = ""
        self.showing = ""
        self.lows = List[Int64]()
        self.highs = List[Int64]()
        self.version = 1
        self.quarter = 2
        self.region = -1
        self.product = -1
        self.now = Kpis(0, 0, 0, 0, 0)
        self.before = Kpis(0, 0, 0, 0, 0)
        self.weeks = Weekly(List[Float64](), List[Float64](), 0)
        self.heat = Grid2(List[Float64](), 0, List[Float64]())
        self.mix = Grid2(List[Float64](), 0, List[Float64]())
        self.top = Grid2(List[Float64](), 0, List[Float64]())
        self.unmerged_top = 0
        self.anomaly = Anomaly(0, False, 0, 0, 0, 0, -1, 0, 0)
        self.anomaly_at = -1
        self.report_ms = 0
        self.ranges()
        self.grid.prepare(self.frame, self.font, self.pal)
        self.grid.fit(CUSTOMER, self.frame, self.font, self.pal)  # (names are the column people read)
        self.compute()
        self.find()
        self.histograms()

    def title(self) -> String:
        return "MX Studio · Q3 Orders"

    def window_size(self) -> Tuple[Int, Int]:
        return (1440, 900)

    def design(self) -> Int:
        return OMARCHY

    def gf(self) -> Pointer[GpuFrame, MutUntrackedOrigin]:
        return at[GpuFrame](self.gf_addr)

    # ---------- the engine ----------

    def ranges(mut self):
        """Each column's smallest and largest value (the histograms' bins), once."""
        ref cols = self.frame.base()[].cols
        for c in range(len(cols)):
            var lo = cols[c].values[0]
            var hi = lo
            for v in cols[c].values:
                lo = min(lo, v)
                hi = max(hi, v)
            self.lows.append(lo)
            self.highs.append(hi)

    def histograms(mut self):
        """Every column's distribution, over every row, on the GPU (the header shapes)."""
        self.grid.histograms = List[List[Float64]]()
        for c in range(self.frame.stored()):
            self.grid.histograms.append(histogram(self.frame, self.gf()[], c, self.lows[c], self.highs[c]))
        self.grid.redraw()

    def compute(mut self):
        """Totals, customers and the pivot after any change: GPU group-bys plus the session's edits as deltas."""
        self.customers = totals_by(self.frame, self.gf()[], CUSTOMER, REVENUE)
        var cost = totals_by(self.frame, self.gf()[], CUSTOMER, COST)
        var freight = totals_by(self.frame, self.gf()[], CUSTOMER, FREIGHT)
        self.pivot = customer_product(self.frame, self.gf()[], TOP_CUSTOMERS)
        var rp = shares_by_region_product(self.frame, self.gf()[])
        self.region_pivot = rp.copy()
        self.revenue = 0
        self.rows = 0
        var spent = 0
        for k in range(len(self.customers.sums)):
            self.revenue += self.customers.sums[k]
            self.rows += self.customers.rows[k]
            spent += cost.sums[k] + freight.sums[k]
        self.margin = self.revenue - spent
        self.milliseconds = self.customers.milliseconds + cost.milliseconds + freight.milliseconds + self.pivot.milliseconds
        self.version += 1

    def distinct_customers(self) -> Int:
        var folded = fold(self.frame, CUSTOMER, self.customers.rows)
        var n = 0
        for r in folded:
            if r > 0:
                n += 1
        return n

    def find(mut self):
        """The agent's look at the customer names: near-duplicate spellings, with the rows behind them."""
        self.findings = find_duplicate_names(self.frame, CUSTOMER, self.customers.rows)

    # ---------- the Report ----------

    def filters(self, quarter: Int, days: Int = 1000) -> List[Range]:
        var out = List[Range]()
        out.append(quarter_range(quarter, days))
        if self.region >= 0:
            out.append(Range(REGION, Int64(self.region), Int64(self.region)))
        if self.product >= 0:
            out.append(Range(PRODUCT, Int64(self.product), Int64(self.product)))
        return out^

    def filters_no_quarter(self) -> List[Range]:
        var out = List[Range]()
        if self.region >= 0:
            out.append(Range(REGION, Int64(self.region), Int64(self.region)))
        if self.product >= 0:
            out.append(Range(PRODUCT, Int64(self.product), Int64(self.product)))
        return out^

    def compute_report(mut self):
        """Every tile, on the GPU, over the ledger as the Sheet left it (edits and merges included)."""
        var f = self.filters(self.quarter)
        self.now = kpis(self.frame, self.gf()[], f)
        # against the previous quarter over the same number of days (Q4 is to date: its first 16 days vs Q3's)
        self.before = kpis(self.frame, self.gf()[], self.filters(max(self.quarter - 1, 0), quarter_days(self.quarter))) if self.quarter > 0 else Kpis(0, 0, 0, 0, 0)
        self.weeks = weekly(self.frame, self.gf()[], self.filters_no_quarter())
        var in_quarter = List[Range]()
        in_quarter.append(quarter_range(self.quarter))
        self.heat = margin_heatmap(self.frame, self.gf()[], in_quarter)
        var mix_filters = List[Range]()
        mix_filters.append(quarter_range(self.quarter))
        if self.region >= 0:
            mix_filters.append(Range(REGION, Int64(self.region), Int64(self.region)))
        self.mix = shares(self.frame, self.gf()[], PRODUCT, mix_filters)
        self.top = shares(self.frame, self.gf()[], CUSTOMER, f)  # (its .raw: before merges, for what a merge added)
        if self.anomaly_at != self.frame.edits:  # the finder looks at every row, unfiltered: again only after edits
            self.anomaly = worst_margin_fall(self.frame, self.gf()[])
            self.anomaly_at = self.frame.edits
        self.report_ms = (self.now.milliseconds + self.before.milliseconds + self.weeks.milliseconds + self.heat.milliseconds
                          + self.mix.milliseconds + self.top.milliseconds + self.anomaly.milliseconds)
        self.version += 1

    def vs(self) -> String:
        var q = materialize[QUARTERS]()
        var days = quarter_days(self.quarter)
        return "vs " + q[self.quarter - 1] + (" (same " + String(days) + " days)" if days < 89 else "")

    def change(self, now: Float64, was: Float64) -> String:
        if was == 0:
            return "first quarter of data"
        var pct = (now - was) / was * 100.0
        return ("+" if pct >= 0 else "-") + fixed(abs(pct), 1) + "% " + self.vs()

    def kpi(self, k: Int) -> KpiView:
        var spark = List[Float64]()
        var start = (max(self.quarter, 0) * 13)
        for w in range(start, min(start + 13, len(self.weeks.revenue))):
            spark.append(self.weeks.revenue[w])
        var first = self.quarter == 0
        if k == 0:
            return KpiView("Revenue", money(self.now.revenue), self.change(Float64(self.now.revenue), Float64(self.before.revenue)), spark^, True,
                           0 if first else (TONE_GOOD if self.now.revenue >= self.before.revenue else TONE_WARN))
        if k == 1:
            return KpiView("Orders", grouped(self.now.orders), self.change(Float64(self.now.orders), Float64(self.before.orders)), List[Float64](), False,
                           0 if first else (TONE_GOOD if self.now.orders >= self.before.orders else TONE_WARN))
        if k == 2:
            var pts = (self.now.margin_share() - self.before.margin_share()) * 100.0
            var note = (("+" if pts >= 0 else "-") + fixed(abs(pts), 1) + " pts " + self.vs()) if not first else "first quarter of data"
            return KpiView("Gross margin", fixed(self.now.margin_share() * 100.0, 1) + "%", note, List[Float64](), False,
                           0 if first else (TONE_GOOD if pts >= 0 else TONE_WARN))
        var merged = len(self.frame.aliases) > 0
        return KpiView("Active customers", grouped(self.now.customers), "after merging duplicate names" if merged else "3 spellings of Acme still split",
                       List[Float64](), False, 0)

    def week_chart(self) -> ChartView:
        var labels = List[String]()
        var months = materialize[MONTHS]()
        for w in range(len(self.weeks.revenue)):
            var m = (w * 7) // 30
            labels.append(months[m] if (w * 7) % 30 < 7 and m < len(months) else "")
        var mark = RATE_CHANGE // 7
        var cv = ChartView.line("Revenue and margin by week", labels^, self.weeks.revenue.copy(), self.weeks.margin.copy(), mark, "Jul 14 · rate table v7")
        cv.size = (Float64(self.w_report(6)), 240.0)
        return cv^

    def customer_chart(self) -> ChartView:
        var order = List[Int]()
        var used = List[Bool](length=len(self.top.values), fill=False)
        for _ in range(5):
            var best = -1
            for c in range(len(self.top.values)):
                if not used[c] and self.top.values[c] > 0 and (best < 0 or self.top.values[c] > self.top.values[best]):
                    best = c
            if best < 0:
                break
            used[best] = True
            order.append(best)
        var labels = List[String]()
        var values = List[Float64]()
        for c in order:
            labels.append(self.frame.text_of(CUSTOMER, Int64(c)))
            values.append(self.top.values[c])
        return ChartView("Top customers", labels^, values^, "revenue", True)

    def mix_chart(self) -> ChartView:
        var labels = List[String]()
        var values = List[Float64]()
        for p in range(len(self.mix.values)):
            labels.append(self.frame.text_of(PRODUCT, Int64(p)))
            values.append(self.mix.values[p])
        return ChartView("Product mix", labels^, values^, "revenue", True, self.product)

    def heat_chart(self) -> ChartView:
        var rows = List[String]()
        var cols = List[String]()
        for r in range(text_groups(self.frame, REGION)):
            rows.append(self.frame.text_of(REGION, Int64(r)))
        for p in range(text_groups(self.frame, PRODUCT)):
            var name = self.frame.text_of(PRODUCT, Int64(p))
            cols.append(String(name.split(" ")[0]))
        var ncols = len(cols)
        var cv = ChartView.heatmap("Margin · region × product", rows^, cols^, self.heat.values.copy())
        if self.region >= 0 and self.product >= 0:
            cv.selected = self.region * ncols + self.product
        return cv^

    def w_report(self, canvas: Int) -> Int:
        return 790

    # ---------- drawing ----------

    def chart(self) -> ChartView:
        var labels = List[String]()
        var values = List[Float64]()
        var np = self.pivot.products
        for i in range(len(self.pivot.customers)):
            labels.append(self.frame.text_of(CUSTOMER, Int64(self.pivot.customers[i])))
            var t = 0
            for p in range(np):
                t += self.pivot.cells[i * np + p]
            values.append(Float64(t))
        var cv = ChartView("Revenue by customer", labels^, values^, "revenue", True, self.chart_pick)
        cv.size = self.sizes[1]  # (as drawn: taps hit what's on screen)
        return cv^

    def region_chart(self) -> ChartView:
        var labels = List[String]()
        var values = List[Float64]()
        var np = text_groups(self.frame, PRODUCT)
        for r in range(text_groups(self.frame, REGION)):
            labels.append(self.frame.text_of(REGION, Int64(r)))
            var t = 0
            for p in range(np):
                var i = r * np + p
                t += self.region_pivot[i] if i < len(self.region_pivot) else 0
            values.append(Float64(t))
        return ChartView("Revenue by region", labels^, values^, "revenue", True)

    def draw(mut self, canvas: Int, mut surface: Surface):
        if 0 <= canvas < len(self.sizes):
            self.sizes[canvas] = (surface.points_width(), surface.points_height())
        if canvas >= 10:  # an inserted chart (canvas 10 + its object)
            var cv = self.region_chart()
            cv.draw(surface, self.font, self.pal)
        elif canvas == 0:
            self.grid.draw(surface, self.frame, self.font, self.pal)
        elif canvas == 1:
            var cv = self.chart()
            cv.draw(surface, self.font, self.pal)
        elif 2 <= canvas <= 5:
            self.kpi(canvas - 2).draw(surface, self.pal)
        elif canvas == 6:
            var cv = self.week_chart()
            cv.draw(surface, self.font, self.pal)
        elif canvas == 7:
            var cv = self.customer_chart()
            cv.draw(surface, self.font, self.pal)
        elif canvas == 8:
            var cv = self.mix_chart()
            cv.draw(surface, self.font, self.pal)
        elif canvas == 9:
            var cv = self.heat_chart()
            cv.draw(surface, self.font, self.pal)

    # ---------- events ----------

    def select_cell(mut self, row: Int, col: Int):
        self.edit_text = self.frame.display(col, row) if row >= 0 and col >= 0 else ""
        self.version += 1

    def after_edit(mut self):
        self.compute()
        self.find()
        self.histograms()  # (the headers' shapes follow the edit too)

    def update(mut self, event: Event):
        var m = event.message
        if m != CELL_COMMIT and m != CELL_CANCEL and m != GRID and self.grid.editing:
            self.grid.editing = False
            self.version += 1
        if m == GRID:
            var action = self.grid.handle(event, self.frame, self.font, self.pal)
            if action == GRID_SELECTED or action == GRID_EDIT or action == GRID_READ_ONLY:
                self.select_cell(self.grid.cur_row, self.grid.cur_col)
                if action == GRID_EDIT:
                    self.message = "Editing order row " + grouped(self.grid.cur_row + 1) + " · " + self.frame.name(self.grid.cur_col) + ": Enter writes it, Escape cancels"
                elif action == GRID_READ_ONLY:
                    self.message = self.frame.name(self.grid.cur_col) + " is a formula: edit the columns it reads"
            elif action == GRID_TYPED:  # a key typed on a cell: the editor starts from it (it replaces the value)
                self.select_cell(self.grid.cur_row, self.grid.cur_col)
                self.edit_text = self.grid.typed
                self.message = "Editing order row " + grouped(self.grid.cur_row + 1) + " · " + self.frame.name(self.grid.cur_col) + ": Enter writes it, Escape cancels"
            elif action == GRID_CANCEL:
                self.select_cell(self.grid.cur_row, self.grid.cur_col)
                self.message = "Edit cancelled"
            elif action == GRID_CLEAR:
                var col = self.grid.cur_col
                var row = self.grid.cur_row
                var before = self.frame.display(col, row)
                try:
                    self.frame.set_text(col, row, "")
                    self.message = self.frame.name(col) + " on row " + grouped(row + 1) + ": " + before + " → (empty)"
                    self.select_cell(row, col)
                    self.after_edit()
                except:  # numbers and dates have no blank yet (docs/plans/needs-mxframe.md)
                    self.message = self.frame.name(col) + " can't be empty yet: type a value (0 to zero it)"
                self.version += 1
            elif action == GRID_COLUMN:
                self.message = "Column " + self.frame.name(self.grid.cur_col) + " selected: Sort orders the table by it"
                self.version += 1
            elif action != 0:
                self.version += 1
        elif m == CELL_COMMIT:
            if self.grid.editing and self.grid.cur_row >= 0 and self.grid.cur_col >= 0:
                try:
                    var col = self.grid.cur_col
                    var row = self.grid.cur_row
                    var before = self.frame.display(col, row)
                    self.frame.set_text(col, row, event.text)
                    self.message = self.frame.name(col) + " on row " + grouped(row + 1) + ": " + before + " → " + self.frame.display(col, row)
                    self.grid.committed(self.frame)
                    self.select_cell(self.grid.cur_row, self.grid.cur_col)
                    self.after_edit()
                except e:
                    self.edit_text = event.text
                    self.message = String(e) + " (fix it and press Enter)"
            self.version += 1
        elif m == CELL_CANCEL:  # Escape in the editor: nothing written
            self.grid.cancel_edit()
            self.select_cell(self.grid.cur_row, self.grid.cur_col)
            self.message = "Edit cancelled"
        elif m == SORT:
            var col = self.grid.cur_col
            if col >= 0:
                var desc = (not self.grid.sort_desc) if self.grid.sort_col == col else self.frame.grid_numeric(col)
                self.grid.set_order(self.frame.permutation(col, desc), col, desc)
                self.showing = ""
                self.message = "Sorted by " + self.frame.name(col) + (" (largest first)" if desc else "")
            else:
                self.message = "Tap a column header to choose what to sort by"
            self.version += 1
        elif m == MERGE_NAMES:
            if len(self.findings) > 0:
                ref f = self.findings[0]
                var n = self.frame.merge(CUSTOMER, f.codes, f.into)
                self.message = "Merged " + String(n) + " spellings into “" + self.frame.text_of(CUSTOMER, f.into) + "” (" + grouped(f.other_rows()) + " rows): one step, Undo all brings them back"
                self.compute()
                self.find()
                self.histograms()
                self.grid.redraw()
        elif m == SHOW_ROWS:
            if len(self.findings) > 0:
                var codes = List[Int64]()
                for c in self.findings[0].codes:
                    if c != self.findings[0].into:
                        codes.append(c)
                self.grid.set_order(rows_with(self.frame, CUSTOMER, codes), -1, False)
                self.showing = "the " + grouped(len(self.grid.order)) + " rows under the other spellings"
                self.message = "Showing " + self.showing
                self.version += 1
        elif m == ALL_ROWS:
            self.grid.clear_order()
            self.showing = ""
            self.version += 1
        elif m == UNDO_ALL:
            var n = 0
            while self.frame.undo():
                n += 1
            self.message = ("Undid every edit (" + String(n) + (" step" if n == 1 else " steps") + "): the ledger is as it was imported") if n > 0 else "Nothing to undo"
            self.compute()
            self.find()
            self.histograms()
            self.grid.redraw()
        elif m == FIND:
            self.find()
            self.message = "Agent looked again: " + (String(len(self.findings)) + " finding" + ("s" if len(self.findings) != 1 else "") if len(self.findings) > 0 else "nothing new")
            self.version += 1
        elif m == CHART_TAP and event.number == TAP:
            var cv = self.chart()
            if cv.tap(event.x, event.y, self.font, self.pal):
                self.chart_pick = cv.selected
                self.version += 1
        elif m == MODE:
            if event.number <= 1:
                self.mode = event.number
                if self.mode == 1:
                    self.compute_report()
                    self.message = "Every tile reads orders_clean, the table you edit in Sheet"
            else:
                self.message = materialize[MODES]()[event.number] + " comes next: Sheet and Report are proven first, end to end"
            self.version += 1
        elif m == QUARTER:
            self.quarter = event.number
            self.compute_report()
        elif m == REGION_PICK:
            self.region = event.number - 1
            self.compute_report()
        elif m == PRODUCT_PICK:
            self.product = event.number - 1
            self.compute_report()
        elif m == TAP_MIX and event.number == TAP:
            var cv = self.mix_chart()
            cv.size = self.sizes[8]
            if cv.tap(event.x, event.y, self.font, self.pal):
                self.product = cv.selected
                self.message = ("Filtered to " + self.frame.text_of(PRODUCT, Int64(self.product))) if self.product >= 0 else "Product filter cleared"
                self.compute_report()
        elif m == TAP_HEAT and event.number == TAP:
            var cv = self.heat_chart()
            cv.size = self.sizes[9]
            if cv.tap(event.x, event.y, self.font, self.pal):
                var nc = text_groups(self.frame, PRODUCT)
                if cv.selected >= 0:
                    self.region = cv.selected // nc
                    self.product = cv.selected % nc
                    self.message = "Filtered to " + self.frame.text_of(REGION, Int64(self.region)) + " · " + self.frame.text_of(PRODUCT, Int64(self.product))
                else:
                    self.region = -1
                    self.product = -1
                    self.message = "Filters cleared"
                self.compute_report()
        elif m == TAP_LINE and event.number == TAP:
            var cv = self.week_chart()
            cv.size = self.sizes[6]
            if cv.tap(event.x, event.y, self.font, self.pal):
                var w = cv.selected
                if w >= 0 and w < len(self.weeks.revenue):
                    self.message = "Week " + String(w + 1) + ": " + money(Int(self.weeks.revenue[w])) + " revenue, " + fixed(self.weeks.margin[w] * 100.0, 1) + "% gross margin"
                self.version += 1
        elif m == REPORT_PAGE:
            if event.number != 0:
                self.message = materialize[REPORT_PAGES]()[event.number] + " page: next (Revenue is the one built)"
            self.version += 1
        elif m == TAP_CUSTOMERS:
            self.message = "Customers come from the Sheet: Edit data opens it"
            self.version += 1
        elif m == OPEN_ROWS:  # the anomaly's rows, in the Sheet
            ref a = self.anomaly
            var rows = List[Int]()
            for row in range(self.frame.rows()):
                if self.frame.alive(row) and Int(self.frame.get(REGION, row)) == a.region and (self.frame.get(WEIGHT, row) > 4000) == a.heavy \
                        and self.frame.get(DAY, row) >= YEAR_START + RATE_CHANGE:
                    rows.append(row)
            self.grid.set_order(rows^, -1, False)
            self.showing = grouped(len(self.grid.order)) + " " + ("heavy" if a.heavy else "light") + " parcels in the " + self.frame.text_of(REGION, Int64(a.region)) + " after Jul 14"
            self.mode = 0
            self.message = "Showing " + self.showing
            self.version += 1
        elif m == SHEET:
            self.sheet = event.number
            if event.number != 0:
                self.message = materialize[SHEETS]()[event.number] + " is a view of the same ledger: next"
            self.sheet = 0
            self.version += 1
        elif INSERT <= m <= INSERT + NOTE or m == INSERT_FORMULA or m == INSERT_TABLE:
            if m == INSERT_FORMULA:
                self.formula_open = not self.formula_open
                self.message = "Type a formula column, e.g. margin = revenue - cost - freight" if self.formula_open else ""
            elif m == INSERT_TABLE:
                self.message = "A second table needs a second source: that comes with Explore (inputs and joins)"
            elif len(self.kinds) >= MAX_OBJECTS:
                self.message = "This page holds " + String(MAX_OBJECTS) + " objects at most"
            else:
                self.insert(m - INSERT)
            self.version += 1
        elif m == FORMULA:
            try:
                var c = self.frame.formula(event.text)
                self.grid.min_widths = List[Float64]()
                self.grid.prepare(self.frame, self.font, self.pal)
                self.grid.fit(c, self.frame, self.font, self.pal)
                self.grid.reveal_cell(max(self.grid.cur_row, 0), c, self.frame)
                self.histograms()
                self.formula_open = False
                self.message = "Formula column " + self.frame.name(c) + " added: computed on the GPU in every group-by, never stored"
            except e:
                self.message = String(e)
            self.version += 1
        elif NOTE_TEXT <= m < NOTE_TEXT + MAX_OBJECTS:
            var k = m - NOTE_TEXT
            if k < len(self.notes):
                self.notes[k] = event.text
        elif m == MOVE:
            var k = event.number
            if 0 <= k < len(self.x):
                self.x[k] = max(0, (self.x[k] + Int(event.dx) + 4) // 8 * 8)
                self.y[k] = max(0, (self.y[k] + Int(event.dy) + 4) // 8 * 8)
                self.version += 1

    def free_spot(self, w: Int, h: Int) -> Tuple[Int, Int]:
        var y = 0
        while y < 20000:
            var x = 0
            while x + w <= PAGE_W:
                var clear = True
                for k in range(len(self.kinds)):
                    if x < self.x[k] + self.w[k] + 16 and self.x[k] < x + w + 16 and y < self.y[k] + self.h[k] + 16 and self.y[k] < y + h + 16:
                        clear = False
                        break
                if clear:
                    return (x, y)
                x += 16
            y += 16
        return (0, y)

    def insert(mut self, kind: Int):
        """Inserted objects: a pivot of revenue by region × product, a chart of revenue by region, a note."""
        var w = 520 if kind == REGION_PIVOT else (400 if kind == REGION_CHART else 400)
        var h = 236 if kind == REGION_PIVOT else (280 if kind == REGION_CHART else 150)
        var at = self.free_spot(w, h)
        self.kinds.append(kind)
        self.x.append(at[0])
        self.y.append(at[1])
        self.w.append(w)
        self.h.append(h)
        self.notes.append("")
        self.reveal_k = len(self.kinds) - 1
        self.reveal_count += 1
        var names: List[String] = ["", "", "", "", "a pivot (revenue · region × product)", "a chart (revenue by region)", "a note"]
        self.message = "Added " + names[kind] + ": drag it by its header"

    # ---------- the screen ----------

    def edits(self) -> List[String]:
        """The inspector's edit log, newest first (merges as one line)."""
        var out = List[String]()
        var last_merge = -1
        for i in range(len(self.frame.log) - 1, -1, -1):
            ref e = self.frame.log[i]
            if e.kind == MERGE:
                if e.row != last_merge:
                    out.append("merged spellings into " + self.frame.text_of(e.col, e.new))
                    last_merge = e.row
            elif e.kind == SET:
                var name = self.frame.name(e.col)
                var was = self.frame.text_of(e.col, e.old) if e.col == CUSTOMER or e.col == PRODUCT else String(e.old)
                var now = self.frame.text_of(e.col, e.new) if e.col == CUSTOMER or e.col == PRODUCT else String(e.new)
                out.append("#" + String(Int(self.frame.get(ORDER, e.row))) + " " + name + ": " + was + " → " + now)
            if len(out) >= 6:
                break
        return out^

    def table_card(self) -> View:
        var source = "orders_clean · " + grouped(self.frame.rows()) + " rows · " + self.grid.position_text(self.frame)
        if self.showing != "":
            source = "showing " + self.showing
        return Card(
            HStack(
                HStack(Text("Transactions", style=HEADLINE), Text(source, style=CAPTION).tag("source"), spacing=12),
                HStack(
                    TextField("", placeholder="Formula", on_submit=FORMULA).width(300) if self.formula_open else Spacer(),
                    Button("All rows", on_tap=ALL_ROWS, style=SUBTLE) if self.showing != "" else Button("Sort", on_tap=SORT, style=SUBTLE, icon="sort"),
                    spacing=4,
                ),
                spacing=12,
            ).justify(BETWEEN).fill().height(32),
            Canvas(0, self.version + self.grid.version, on_gesture=GRID, keys=True).fill().height(self.h[TABLE] - 66),
            spacing=10,
        )

    def inspector(self) -> View:
        """The inspector: where the table comes from, what it feeds, what you changed (and Undo all)."""
        var items = List[View]()
        items.append(Text("Inspector", style=HEADLINE))
        items.append(Text("Comes from", style=CAPTION).tone(TONE_ACCENT))
        items.append(Text("orders_clean"))
        items.append(Text("the Explore pipeline's output (Explore is next)", style=CAPTION))
        items.append(Text("Feeds", style=CAPTION).tone(TONE_ACCENT))
        items.append(Text("Pivot 1 and Chart 1 on this page · the Report's tiles"))
        items.append(Text("Your edits", style=CAPTION).tone(TONE_ACCENT))
        var log = self.edits()
        if len(log) == 0:
            items.append(Text("None yet. Double-click a cell to edit it; each edit is a step you can undo.", style=CAPTION))
        for e in log:
            items.append(Text(e).tag("edit"))
        items.append(Button("Undo all edits", on_tap=UNDO_ALL, style=SUBTLE, icon="undo"))
        return VStack(items, spacing=8).align(START).fill()

    def agent_card(self) -> View:
        """The agent's finding (mojoui.finding.FindingCard): the spellings and their rows, and what to do."""
        if len(self.findings) > 0:
            ref f = self.findings[0]
            var names = String("")
            for k in range(len(f.names)):
                names += ("" if k == 0 else (" and " if k == len(f.names) - 1 else ", ")) + "“" + f.names[k] + "”"
            return FindingCard("Agent noticed", String(len(f.names)) + " spellings of one customer: " + names + " · " + grouped(f.total_rows()) + " orders",
                               ["Merge into “" + self.frame.text_of(CUSTOMER, f.into) + "”", "Show the rows"], [MERGE_NAMES, SHOW_ROWS],
                               note="or fix the cells by hand: double-click a name", again=FIND)
        return FindingCard("Names are clean", "Pivot 1 and Chart 1 regrouped: " + String(self.distinct_customers()) +
                           " customers. The merge is a step in Your edits; Undo all brings the spellings back.", resolved=True, again=FIND)

    def pivot_card(self) -> View:
        var np = self.pivot.products
        var rows = List[String]()
        var cols = List[String]()
        var cells = List[String]()
        var row_totals = List[String]()
        var col_totals = List[Int](length=np, fill=0)
        var highlight = List[Bool]()
        var flagged = List[Int64]()
        for f in self.findings:
            for c in f.codes:
                flagged.append(c)
        for p in range(np):
            cols.append(self.frame.text_of(PRODUCT, Int64(p)))
        var grand = 0
        for i in range(len(self.pivot.customers)):
            var code = self.pivot.customers[i]
            rows.append(self.frame.text_of(CUSTOMER, Int64(code)))
            var t = 0
            for p in range(np):
                var v = self.pivot.cells[i * np + p]
                cells.append(money(v) if v != 0 else "—")
                t += v
                col_totals[p] += v
            row_totals.append(money(t))
            grand += t
            var hot = False
            for c in flagged:
                if Int(c) == code:
                    hot = True
            highlight.append(hot)
        var ct = List[String]()
        for v in col_totals:
            ct.append(money(v))
        return Card(
            HStack(Text("Pivot 1", style=HEADLINE), Text("revenue · customer × product · top " + String(TOP_CUSTOMERS), style=CAPTION), spacing=12).height(32),
            PivotTable(rows, cols, cells, totals=True, row_totals=row_totals, col_totals=ct, grand=money(grand), highlight=highlight,
                       height=self.h[PIVOT] - 70, corner="Customer", total_label="Top " + String(TOP_CUSTOMERS)),
            spacing=8,
        )

    def chart_card(self) -> View:
        return Card(
            HStack(Text("Chart 1", style=HEADLINE), Text("from Pivot 1 · revenue by customer", style=CAPTION), spacing=12).height(32),
            Canvas(1, self.version, on_gesture=CHART_TAP).grow().fill(),
            spacing=8,
        )

    def report_items(self) -> List[View]:
        """The Report page: filters, four KPIs, revenue and margin by week, top customers, product mix, the
        margin heatmap and what's worth a look."""
        var items = List[View]()
        var regions = List[String]()
        regions.append("All regions")
        for r in range(text_groups(self.frame, REGION)):
            regions.append(self.frame.text_of(REGION, Int64(r)))
        var products = List[String]()
        products.append("All products")
        for p in range(text_groups(self.frame, PRODUCT)):
            products.append(self.frame.text_of(PRODUCT, Int64(p)))
        var bar = Card(HStack(
            Text("Quarter", style=CAPTION), Dropdown(materialize[QUARTERS](), self.quarter, on_select=QUARTER),
            Text("Region", style=CAPTION), Dropdown(regions^, self.region + 1, on_select=REGION_PICK),
            Text("Product", style=CAPTION), Dropdown(products^, self.product + 1, on_select=PRODUCT_PICK),
            Spacer(),
            Text(String(7) + " tiles · " + grouped(self.frame.rows()) + " rows · " + fixed(self.report_ms, 1) + " ms on " + ("GPU" if self.gf()[].on_gpu() else "CPU"), style=CAPTION).tag("tiles"),
            spacing=8,
        ).fill())
        items.append(bar^.at(PAGE_X, PAGE_Y).width(1232).height(64).tag("filters"))
        for k in range(4):
            items.append(self.kpi(k).view(2 + k, self.version).at(PAGE_X + k * 312, PAGE_Y + 80).width(296).height(120).tag("kpi" + String(k + 1)))
        items.append(Card(
            HStack(Text("Revenue and margin by week", style=HEADLINE), Text("orders_clean · revenue (blue) and gross margin (orange)", style=CAPTION), spacing=12).height(32),
            Canvas(6, self.version, on_gesture=TAP_LINE).fill().height(240),
            spacing=8).at(PAGE_X, PAGE_Y + 216).width(816).height(310).tag("weekly"))
        var merged = len(self.frame.aliases) > 0
        var top_code = 0  # the top customer (merges folded) and how many spellings were merged into it
        for c in range(len(self.top.values)):
            if self.top.values[c] > self.top.values[top_code]:
                top_code = c
        var top_name = self.frame.text_of(CUSTOMER, Int64(top_code))
        var joined = 1
        for item in self.frame.aliases.items():
            if (item.key >> 32) == CUSTOMER and Int(item.value) == top_code:
                joined += 1
        var gain = Int(self.top.values[top_code] - self.top.raw[top_code]) if top_code < len(self.top.raw) else 0
        items.append(Card(
            HStack(Text("Top customers", style=HEADLINE), Spacer(), Button("Edit data", on_tap=MODE, style=SUBTLE), spacing=8).fill().height(32),
            Canvas(7, self.version, on_gesture=TAP_CUSTOMERS).fill().height(190),
            Text(("+" + money(gain) + " for " + top_name + " once " + String(joined) + " spellings were merged") if merged and joined > 1 else "Acme is split across 3 spellings: merge them in the Sheet", style=CAPTION).tone(TONE_GOOD if merged and joined > 1 else TONE_WARN).tag("merge-note"),
            spacing=8).at(PAGE_X + 832, PAGE_Y + 216).width(400).height(310).tag("customers"))
        items.append(Card(
            HStack(Text("Product mix", style=HEADLINE), Text("tap a bar to filter", style=CAPTION), spacing=12).height(32),
            Canvas(8, self.version, on_gesture=TAP_MIX).fill().height(236),
            spacing=8).at(PAGE_X + 832, PAGE_Y + 542).width(400).height(300).tag("mix"))
        items.append(Card(
            HStack(Text("Margin · region × product", style=HEADLINE), Text("same pivot engine as the Sheet · tap a cell to filter", style=CAPTION), spacing=12).height(32),
            Canvas(9, self.version, on_gesture=TAP_HEAT).fill().height(236),
            spacing=8).at(PAGE_X, PAGE_Y + 542).width(816).height(300).tag("heatmap"))
        ref a = self.anomaly
        var what = ("Heavy" if a.heavy else "Light") + " parcels in the " + self.frame.text_of(REGION, Int64(a.region)) + " lost " + fixed(a.points(), 1) + \
                   " margin points after Jul 14 (" + fixed(a.before * 100.0, 1) + "% → " + fixed(a.after * 100.0, 1) + "%, " + grouped(a.rows) + " orders)."
        if a.carrier >= 0:  # the cause, as the engine found it in those rows
            what += " " + self.frame.text_of(CARRIER, Int64(a.carrier)) + "'s freight rose from " + money_exact(Int(a.freight_before)) + \
                    " to " + money_exact(Int(a.freight_after)) + " an order on them."
        items.append(FindingCard("Worth a look", what, ["Open the rows"], [OPEN_ROWS], note="the rows open in the Sheet, filtered")
                     .at(PAGE_X, PAGE_Y + 858).width(816).height(170).tag("worth"))
        return items^

    def region_pivot_card(self, k: Int) -> View:
        var np = text_groups(self.frame, PRODUCT)
        var rows = List[String]()
        var cols = List[String]()
        var cells = List[String]()
        var totals = List[String]()
        for p in range(np):
            cols.append(String(self.frame.text_of(PRODUCT, Int64(p)).split(" ")[0]))
        for r in range(text_groups(self.frame, REGION)):
            rows.append(self.frame.text_of(REGION, Int64(r)))
            var t = 0
            for p in range(np):
                var v = self.region_pivot[r * np + p] if r * np + p < len(self.region_pivot) else 0
                cells.append(money(v))
                t += v
            totals.append(money(t))
        return Card(
            HStack(Text("Pivot " + String(k), style=HEADLINE), Text("revenue · region × product", style=CAPTION), spacing=12).height(32),
            PivotTable(rows, cols, cells, totals=True, row_totals=totals, height=self.h[k] - 70, corner="Region"),
            spacing=8,
        )

    def card(self, k: Int) -> View:
        var kind = self.kinds[k]
        if kind == TABLE:
            return self.table_card()
        if kind == PIVOT:
            return self.pivot_card()
        if kind == AGENT:
            return self.agent_card()
        if kind == CHART:
            return self.chart_card()
        if kind == REGION_PIVOT:
            return self.region_pivot_card(k)
        if kind == REGION_CHART:
            return Card(
                HStack(Text("Chart " + String(k), style=HEADLINE), Text("revenue by region", style=CAPTION), spacing=12).height(32),
                Canvas(10 + k, self.version, on_gesture=NO_MSG).grow().fill(),
                spacing=8,
            )
        return Card(
            HStack(Text("Note", style=HEADLINE), spacing=12).height(32),
            TextArea(self.notes[k], placeholder="Write a note…", on_change=NOTE_TEXT + k, height=self.h[k] - 70).fill(),
            spacing=8,
        )

    def view(self) -> View:
        if self.mode == 1:
            var report = self.report_items()
            return self.page(report^, 858 + 170)
        var names: List[String] = ["table", "pivot", "agent", "chart", "pivot", "chart", "note"]
        var seen = List[Int](length=7, fill=0)
        var items = List[View]()
        var bottom = 0
        for k in range(len(self.kinds)):
            var kind = self.kinds[k]
            var name = names[kind] + ("" if seen[kind] == 0 and kind < REGION_PIVOT else String(k))
            seen[kind] += 1
            items.append(self.card(k).at(self.x[k] + PAGE_X, self.y[k] + PAGE_Y).width(self.w[k]).height(self.h[k]).tag(name))
            bottom = max(bottom, self.y[k] + self.h[k])
        var ed = self.grid.editor_place(self.frame)
        if ed[2] > 0:  # the in-place editor, over its cell, on the page
            items.append(self.grid.editor(self.edit_text, CELL_COMMIT, CELL_CANCEL)
                         .at(self.x[TABLE] + PAGE_X + CARD_PAD_X + ed[0], self.y[TABLE] + PAGE_Y + GRID_TOP + ed[1])
                         .width(ed[2]).height(30))
        return self.page(items^, bottom)

    def page(self, var items: List[View], bottom: Int) -> View:
        """The page and the islands floating over it: title and Insert (top left), the mode switch (top
        centre), the sheet tabs and the inspector (right), the status and the last message (bottom)."""
        var title = VStack(
            HStack(
                Text("MX", style=HEADLINE).tone(TONE_ACCENT),
                Text("Q3 Orders", style=HEADLINE),
                Text("Saved · engine on " + ("GPU" if self.gf()[].on_gpu() else "CPU"), style=CAPTION),
                spacing=10,
            ),
            HStack(
                Button("Table", on_tap=INSERT_TABLE, style=SUBTLE, icon="table"),
                Button("Pivot", on_tap=INSERT + REGION_PIVOT, style=SUBTLE, icon="pivot"),
                Button("Chart", on_tap=INSERT + REGION_CHART, style=SUBTLE, icon="chart-bar"),
                Button("Text", on_tap=INSERT + NOTE, style=SUBTLE, icon="note"),
                Button("Formula", on_tap=INSERT_FORMULA, style=SUBTLE),
                Button("Agent", on_tap=FIND, style=SUBTLE),
                spacing=2,
            ) if self.mode == 0 else HStack(Text("Report · live", style=CAPTION), spacing=2),
            spacing=4,
        ).align(START)
        var modes = Segmented(materialize[MODES](), self.mode, on_select=MODE)
        var right = List[View]()
        right.append(Tabs(materialize[SHEETS](), self.sheet, on_select=SHEET) if self.mode == 0 else Tabs(materialize[REPORT_PAGES](), 0, on_select=REPORT_PAGE))
        if self.mode == 0:
            right.append(self.inspector())
        var side = VStack(right, spacing=10).align(START).width(336)
        var status = HStack(
            Text("Rows " + grouped(self.rows), style=CAPTION).tag("rows"),
            Text("Sum revenue " + money_exact(self.revenue), style=CAPTION).tag("revenue"),
            Text("Gross margin " + fixed(Float64(self.margin) * 100.0 / Float64(max(self.revenue, 1)), 1) + "%", style=CAPTION).tag("margin"),
            Text("Distinct customers " + String(self.distinct_customers()), style=CAPTION).tag("customers"),
            Text(fixed(self.milliseconds, 1) + " ms on " + self.gf()[].device_name(), style=CAPTION).tag("engine"),
            spacing=14,
        )
        var note = Text(self.message if self.message != "" else "Double-click a cell to edit it · drag a card by its header",
                        style=CAPTION).tag("message")
        return Overlay(
            Board(items, 1232 + 2 * PAGE_X, bottom + PAGE_Y + 90, on_move=MOVE if self.mode == 0 else NO_MSG,
                  reveal=self.reveal_k, reveal_count=self.reveal_count).tag("board").grow().fill(),
            title^.pin(START, START),
            modes^.pin(CENTER, START),
            side^.pin(END, START),
            status^.pin(START, END),
            note^.pin(END, END),
        ).grow().fill()


def money_exact(cents: Int) -> String:
    """$3,812,345.90: every cent."""
    var a = cents if cents >= 0 else -cents
    var frac = String(a % 100)
    if a % 100 < 10:
        frac = "0" + frac
    return ("-" if cents < 0 else "") + "$" + grouped(a // 100) + "." + frac
