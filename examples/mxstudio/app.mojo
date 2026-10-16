# MX Studio · Sheet (docs/mx-studio/SCREENS.md §1): the orders ledger as a page of objects over one engine:
# a transactions grid (every row, editable in place), a pivot and a chart that follow every edit, an
# inspector that says where the table comes from and what you changed, and an agent's finding (one customer
# under three spellings) that merges in one undoable step. Built from mojoui components only: DataGrid,
# PivotTable, ChartView, Card tones, Overlay islands, Segmented, Tabs.

from mojoui.view import (View, Text, Button, TextField, Canvas, Board, Overlay, VStack, HStack, Card, Spacer, Segmented, Tabs,
                         HEADLINE, CAPTION, TITLE, PROMINENT, SUBTLE, ICON_ONLY, START, CENTER, END, BETWEEN, OMARCHY,
                         CARD, CARD_WARN, CARD_GOOD, TONE_WARN, TONE_GOOD, TONE_STRONG, TONE_ACCENT, NO_MSG)
from mojoui.app import App, Event
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.charts import money, grouped, fixed
from mojoui.datagrid import DataGrid, GRID_SELECTED, GRID_COLUMN, GRID_EDIT, GRID_READ_ONLY, GRID_REDRAW, GRID_FITTED, GRID_RESIZED
from mojoui.pivot import PivotTable
from mojoui.chartview import ChartView
from mojoui.frame import Frame, share, MERGE, SET
from mojoui.frame_gpu import GpuFrame
from mojoui.gpu import gpu_present
from mojoui.shared import put_shared, get_shared, keep, at, count_load, environment
from orders import order_columns, CUSTOMER, PRODUCT, REVENUE, COST, FREIGHT, ORDER, DAY, ZIP, WEIGHT
from ops import (totals_by, fold, find_duplicate_names, customer_product, histogram, rows_with, text_groups, Finding, Totals, Pivot)

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

# the page: objects at fixed places (draggable by their headers)
comptime PAGE_X = 24
comptime PAGE_Y = 80
comptime CARD_PAD_X = 14
comptime GRID_TOP = 54  # padding 12 + header row 32 + gap 10
comptime TABLE = 0
comptime INSPECTOR = 1
comptime PIVOT = 2
comptime AGENT = 3
comptime CHART = 4
comptime MODES: List[String] = ["Sheet", "Report", "Explore", "Query"]
comptime SHEETS: List[String] = ["Orders", "Customers", "Products"]
comptime TOP_CUSTOMERS = 8


struct Main(App):
    var frame: Frame
    var gf_addr: Int
    var font: Font
    var pal: Palette
    var grid: DataGrid
    var x: List[Int]  # per object
    var y: List[Int]
    var w: List[Int]
    var h: List[Int]
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
        self.x = [0, 896, 0, 832, 496]
        self.y = [0, 0, 516, 516, 836]
        self.w = [880, 336, 816, 400, 480]
        self.h = [500, 500, 304, 224, 280]
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
        cv.size = (Float64(self.w[CHART] - 28), Float64(self.h[CHART] - 70))
        return cv^

    def draw(mut self, canvas: Int, mut surface: Surface):
        if canvas == 0:
            self.grid.draw(surface, self.frame, self.font, self.pal)
        elif canvas == 1:
            var cv = self.chart()
            cv.draw(surface, self.font, self.pal)

    # ---------- events ----------

    def select_cell(mut self, row: Int, col: Int):
        self.edit_text = self.frame.display(col, row) if row >= 0 and col >= 0 else ""
        self.version += 1

    def update(mut self, event: Event):
        var m = event.message
        if m != CELL_COMMIT and m != GRID and self.grid.editing:
            self.grid.editing = False
            self.version += 1
        if m == GRID:
            var action = self.grid.handle(event, self.frame, self.font, self.pal)
            if action == GRID_SELECTED or action == GRID_EDIT or action == GRID_READ_ONLY:
                self.select_cell(self.grid.cur_row, self.grid.cur_col)
                if action == GRID_EDIT:
                    self.message = "Editing order row " + grouped(self.grid.cur_row + 1) + " · " + self.frame.name(self.grid.cur_col) + ": Enter writes it"
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
                    self.compute()
                    self.find()
                except e:
                    self.edit_text = event.text
                    self.message = String(e) + " (fix it and press Enter)"
            self.version += 1
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
            self.message = "Undid every edit (" + String(n) + " steps): the ledger is as it was imported" if n > 0 else "Nothing to undo"
            self.compute()
            self.find()
            self.histograms()
            self.grid.redraw()
        elif m == FIND:
            self.find()
            self.message = "Agent looked again: " + (String(len(self.findings)) + " finding" + ("s" if len(self.findings) != 1 else "") if len(self.findings) > 0 else "nothing new")
            self.version += 1
        elif m == CHART_TAP:
            var cv = self.chart()
            if cv.tap(event.x, event.y, self.font, self.pal):
                self.chart_pick = cv.selected
                self.version += 1
        elif m == MODE:
            if event.number != 0:
                self.message = materialize[MODES]()[event.number] + " comes next: the Sheet is proven first, end to end"
            self.mode = 0
            self.version += 1
        elif m == SHEET:
            self.sheet = event.number
            if event.number != 0:
                self.message = materialize[SHEETS]()[event.number] + " is a view of the same ledger: next"
            self.sheet = 0
            self.version += 1
        elif m == MOVE:
            var k = event.number
            if 0 <= k < len(self.x):
                self.x[k] = max(0, (self.x[k] + Int(event.dx) + 4) // 8 * 8)
                self.y[k] = max(0, (self.y[k] + Int(event.dy) + 4) // 8 * 8)
                self.version += 1

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
                    Button("All rows", on_tap=ALL_ROWS, style=SUBTLE) if self.showing != "" else Button("Sort", on_tap=SORT, style=SUBTLE, icon="sort"),
                    spacing=4,
                ),
                spacing=12,
            ).justify(BETWEEN).fill().height(32),
            Canvas(0, self.version + self.grid.version, on_gesture=GRID).fill().height(self.h[TABLE] - 66),
            spacing=10,
        )

    def inspector(self) -> View:
        var items = List[View]()
        items.append(Text("Inspector", style=HEADLINE))
        items.append(Text("Comes from", style=CAPTION).tone(TONE_ACCENT))
        items.append(Text("orders_clean"))
        items.append(Text("the Explore pipeline's output (Explore is next)", style=CAPTION))
        items.append(Text("Feeds", style=CAPTION).tone(TONE_ACCENT))
        items.append(Text("Pivot 1 and Chart 1, on this page"))
        items.append(Text("Your edits", style=CAPTION).tone(TONE_ACCENT))
        var log = self.edits()
        if len(log) == 0:
            items.append(Text("None yet. Double-click a cell to edit it; each edit is a step you can undo.", style=CAPTION))
        for e in log:
            items.append(Text(e).tag("edit"))
        items.append(Button("Undo all edits", on_tap=UNDO_ALL, style=SUBTLE, icon="undo"))
        var v = VStack(items, spacing=8).align(START).fill()
        return Card(v^)

    def agent_card(self) -> View:
        if len(self.findings) > 0:
            ref f = self.findings[0]
            var names = String("")
            for k in range(len(f.names)):
                names += ("" if k == 0 else (" and " if k == len(f.names) - 1 else ", ")) + "“" + f.names[k] + "”"
            return Card(
                HStack(Text("Agent noticed", style=HEADLINE).tone(TONE_WARN), Spacer(), Button("Look again", on_tap=FIND, style=SUBTLE), spacing=8).fill().height(32),
                Text(String(len(f.names)) + " spellings of one customer: " + names + " · " + grouped(f.total_rows()) + " orders").tag("finding"),
                HStack(
                    Button("Merge into “" + self.frame.text_of(CUSTOMER, f.into) + "”", on_tap=MERGE_NAMES, style=PROMINENT),
                    Button("Show the rows", on_tap=SHOW_ROWS, style=SUBTLE),
                    spacing=8,
                ),
                Text("or fix the cells by hand: double-click a name", style=CAPTION),
                spacing=8, tone=CARD_WARN,
            )
        return Card(
            HStack(Text("Names are clean", style=HEADLINE).tone(TONE_GOOD), Spacer(), Button("Look again", on_tap=FIND, style=SUBTLE), spacing=8).fill().height(32),
            Text("Pivot 1 and Chart 1 regrouped: " + String(self.distinct_customers()) + " customers. The merge is a step in Your edits; Undo all brings the spellings back.").tag("finding"),
            spacing=8, tone=CARD_GOOD,
        )

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
                       height=self.h[PIVOT] - 70, corner="Customer"),
            spacing=8,
        )

    def chart_card(self) -> View:
        return Card(
            HStack(Text("Chart 1", style=HEADLINE), Text("from Pivot 1 · revenue by customer", style=CAPTION), spacing=12).height(32),
            Canvas(1, self.version, on_gesture=CHART_TAP).grow().fill(),
            spacing=8,
        )

    def view(self) -> View:
        var cards = List[View]()
        var names: List[String] = ["table", "inspector", "pivot", "agent", "chart"]
        cards.append(self.table_card())
        cards.append(self.inspector())
        cards.append(self.pivot_card())
        cards.append(self.agent_card())
        cards.append(self.chart_card())
        var items = List[View]()
        var bottom = 0
        for k in range(len(cards)):
            items.append(cards[k].copy().at(self.x[k] + PAGE_X, self.y[k] + PAGE_Y).width(self.w[k]).height(self.h[k]).tag(names[k]))
            bottom = max(bottom, self.y[k] + self.h[k])
        var ed = self.grid.editor_place(self.frame)
        if ed[2] > 0:  # the in-place editor, over its cell, on the page
            items.append(TextField(self.edit_text, placeholder="Cell", on_submit=CELL_COMMIT).focused()
                         .at(self.x[TABLE] + PAGE_X + CARD_PAD_X + ed[0], self.y[TABLE] + PAGE_Y + GRID_TOP + ed[1])
                         .width(ed[2]).height(30).tag("cell-editor"))
        var title = HStack(
            Text("MX", style=HEADLINE).tone(TONE_ACCENT),
            Text("Q3 Orders", style=HEADLINE),
            Text("Saved · engine on " + ("GPU" if self.gf()[].on_gpu() else "CPU"), style=CAPTION),
            spacing=10,
        )
        var modes = Segmented(materialize[MODES](), self.mode, on_select=MODE)
        var sheets = HStack(
            Tabs(materialize[SHEETS](), self.sheet, on_select=SHEET),
            spacing=8,
        )
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
            Board(items, 1232 + 2 * PAGE_X, bottom + PAGE_Y + 90, on_move=MOVE).tag("board").grow().fill(),
            title^.pin(START, START),
            modes^.pin(CENTER, START),
            sheets^.pin(END, START),
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
