# The Workbook: a Numbers-style page of objects over one engine (mojoui.frame + frame_gpu).
#   Table  — typed columns over 20M rows, edited row by row, formula columns ("margin = cents - cost")
#   Pivot  — rows × columns × value, aggregated on the GPU
#   Chart  — a Flint spec; tap a bar to filter the other objects (crossfiltering)
#   Note   — text
# Columns, never cell addresses. The data is shared by every session of the process (init_shared);
# a session's edits are a sparse overlay applied as exact deltas to the GPU totals.

from mojoui.view import (View, Text, Button, TextField, Dropdown, TextArea, Canvas, Board, VStack, HStack, Card, Grid, Spacer, Divider,
                         Scroll, TITLE, HEADLINE, CAPTION, PROMINENT, DESTRUCTIVE, START, CENTER, BETWEEN, TAP, PAN, ZOOM, FLUENT, NO_MSG)
from mojoui.app import App, Event
from mojoui.canvas import Surface, rgba
from mojoui.text import Font, REGULAR, MEDIUM, LEFT, RIGHT, CENTRE
from mojoui.draw import rect, hline, line
from mojoui.charts import money, grouped, fixed, INK, INK2, INK3, BRAND, BRAND_TINT, BRAND_WASH, CARD_BG, GRID
from mojoui.flint import FlintChart
from mojoui.frame import Frame, Range, share, OP_COL, OP_CONST, OP_SUB, TEXT, DECIMAL, DATE, INT
from mojoui.frame_gpu import GpuFrame, group_sum, pivot_program
from mojoui.contoso import generate_columns, CATEGORY, REGION, CHANNEL, PRODUCT, QUANTITY, CENTS, COST, YEAR
from mojoui.gpu import gpu_present, GroupSums
from mojoui.shared import put_shared, get_shared, keep, at, count_load, environment
from mojoui.workbook import save_workbook, open_workbook, ObjectSpec
from mojoui.maths import log2

comptime SOURCE_PREFIX = "contoso:"  # + the row count: the shared table's source name (a workbook file names it instead of copying it)
comptime SAMPLE = "examples/workbook/contoso.mxwb"

# messages
comptime GRID_GESTURE = 1
comptime COMMIT = 2
comptime FORMULA = 3
comptime ADD_ROW = 4
comptime DELETE_ROW = 5
comptime UNDO = 6
comptime PIVOT_ROWS = 7
comptime PIVOT_COLS = 8
comptime PIVOT_VALUE = 9
comptime CHART_TAP = 10  # + object index
comptime NOTE = 40  # + object index
comptime CHART_FIELD = 70  # + object index
comptime CLEAR = 100
comptime SORT = 101
comptime MOVE = 102
comptime RESIZE = 103
comptime SAVE = 104
comptime OPEN = 105

# object kinds
comptime TABLE = 0
comptime PIVOT = 1
comptime CHART = 2
comptime NOTE_OBJ = 3

comptime DIMS: List[Int] = [CATEGORY, REGION, CHANNEL, PRODUCT, YEAR]  # what pivots and charts group by
comptime SNAP = 8

comptime HEADER_H = 30.0
comptime ROW_H = 26.0
comptime GUTTER = 64.0


@fieldwise_init
struct Obj(Copyable, Movable):
    var kind: Int
    var title: String
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    var a: Int  # pivot: rows field (index into DIMS); chart: field
    var b: Int  # pivot: columns field
    var c: Int  # pivot/chart: value (index into the value columns)
    var text: String  # note
    var selected: Int  # chart: the bar picked (crossfilter), -1 = none


def obj(kind: Int, title: String, x: Int, y: Int, w: Int, h: Int, a: Int = 0, b: Int = 1, c: Int = 1, text: String = "") -> Obj:
    return Obj(kind, title, x, y, w, h, a, b, c, text, -1)


struct Main(App):
    var frame: Frame
    var gf_addr: Int
    var font: Font
    var objects: List[Obj]
    var order: List[Int]  # the table sorted (a permutation of alive rows), or empty: natural order
    var sort_col: Int
    var sort_desc: Bool
    var top: Int  # first row shown in the grid (an index into order, or a row number)
    var cur_row: Int  # the selected cell
    var cur_col: Int
    var edit_text: String
    var message: String  # the last error or confirmation
    var results: List[List[Int]]  # per object: group sums
    var counts: List[List[Int]]
    var revenue: Int
    var lines: Int
    var milliseconds: Float64
    var version: Int
    var sizes: List[Tuple[Float64, Float64]]  # per object: its canvas size in points
    var path: String  # where Save writes and Open reads (MOJOUI_WORKBOOK, or ~/Documents/Contoso Workbook.mxwb)
    var pan: Float64  # a drag's leftover below one row, carried to the next motion event

    @staticmethod
    def init_shared():
        if get_shared(0) != 0:
            return
        var addr = share(generate_columns(20_000_000 if gpu_present() else 2_000_000))
        put_shared(0, addr)
        put_shared(1, keep(GpuFrame(addr)))
        count_load()

    def __init__(out self):
        if get_shared(0) == 0:  # no host built the shared data (a test constructing the app directly)
            Self.init_shared()
        self.frame = Frame(get_shared(0))
        self.gf_addr = get_shared(1)
        self.font = Font()
        self.objects = List[Obj]()
        self.objects.append(obj(TABLE, "Order lines", 0, 0, 1360, 380))
        self.objects.append(obj(PIVOT, "Revenue by region and channel", 0, 396, 520, 300, a=1, b=2, c=1))
        self.objects.append(obj(CHART, "Revenue by category", 536, 396, 400, 300, a=0, c=1))
        self.objects.append(obj(CHART, "Revenue by region", 952, 396, 408, 300, a=1, c=1))
        self.objects.append(obj(NOTE_OBJ, "Note", 0, 712, 520, 104, text="Please review this: Q4 revenue by region, then the margin column."))
        self.order = List[Int]()
        self.sort_col = -1
        self.sort_desc = False
        self.top = 0
        self.cur_row = -1
        self.cur_col = -1
        self.edit_text = ""
        self.message = ""
        self.results = List[List[Int]]()
        self.counts = List[List[Int]]()
        self.revenue = 0
        self.lines = 0
        self.milliseconds = 0
        self.version = 1
        self.sizes = List[Tuple[Float64, Float64]]()
        for _ in range(len(self.objects)):
            self.sizes.append((400.0, 300.0))
        self.path = environment("MOJOUI_WORKBOOK")
        if self.path == "":
            self.path = environment("HOME", ".") + "/Documents/Contoso Workbook.mxwb"
        self.pan = 0
        self.load(SAMPLE, quiet=True)  # the sample workbook, when run from the repo; else the built-in page
        self.compute()

    def source(self) -> String:
        return SOURCE_PREFIX + String(self.frame.base()[].rows)

    def load(mut self, path: String, quiet: Bool = False):
        """Opens a workbook file into this session (objects, formulas, edits)."""
        try:
            var specs = List[ObjectSpec]()
            var base_addr = 0
            self.frame = open_workbook(path, self.source(), get_shared(0), specs, base_addr)
            self.gf_addr = get_shared(1) if base_addr == get_shared(0) else keep(GpuFrame(base_addr))  # (a table of its own: on the GPU for this process; not freed)
            self.objects = List[Obj]()
            for o in specs:
                self.objects.append(Obj(o.kind, o.title, o.x, o.y, o.w, o.h, o.a, o.b, o.c, o.text, o.selected))
            self.sizes = List[Tuple[Float64, Float64]]()
            for _ in range(len(self.objects)):
                self.sizes.append((400.0, 300.0))
            self.order = List[Int]()
            self.sort_col = -1
            self.select_cell(-1, -1)
            self.message = "Opened " + path
        except e:
            if not quiet:
                self.message = "Couldn't open: " + String(e)

    def title(self) -> String:
        return "Contoso Workbook"

    def window_size(self) -> Tuple[Int, Int]:
        return (1440, 900)

    def design(self) -> Int:
        return FLUENT

    def gf(self) -> Pointer[GpuFrame, MutUntrackedOrigin]:
        return at[GpuFrame](self.gf_addr)

    # ---------- fields ----------

    def dim_names(self) -> List[String]:
        var out = List[String]()
        for d in materialize[DIMS]():
            out.append(self.frame.name(d))
        return out^

    def dim_groups(self, d: Int) -> Int:
        var col = materialize[DIMS]()[d]
        return 3 if col == YEAR else len(self.frame.base()[].cols[col].dictionary)

    def dim_label(self, d: Int, k: Int) -> String:
        var col = materialize[DIMS]()[d]
        return String(2023 + k) if col == YEAR else self.frame.text_of(col, Int64(k))

    def dim_program(self, d: Int) -> List[Int64]:
        var col = materialize[DIMS]()[d]
        var p = List[Int64]()
        p.append(Int64(OP_COL))
        p.append(Int64(col))
        if col == YEAR:
            p.append(Int64(OP_CONST))
            p.append(2023)
            p.append(Int64(OP_SUB))
            p.append(0)
        return p^

    def value_cols(self) -> List[Int]:
        """Columns a pivot or chart can sum: the numeric stored ones, then every formula."""
        var out: List[Int] = [QUANTITY, CENTS, COST]
        for c in range(self.frame.stored(), self.frame.columns()):
            out.append(c)
        return out^

    def value_names(self) -> List[String]:
        var out = List[String]()
        for c in self.value_cols():
            out.append(self.frame.name(c))
        return out^

    def value_text(self, c: Int, v: Int) -> String:
        var col = self.value_cols()[min(c, len(self.value_cols()) - 1)]
        return money(v) if self.frame.kind(col) == DECIMAL else grouped(v)

    def ranges(self, skip: Int) -> List[Range]:
        """The crossfilter: every chart's picked bar, except object `skip`'s own."""
        var out = List[Range]()
        for k in range(len(self.objects)):
            ref o = self.objects[k]
            if o.kind == CHART and o.selected >= 0 and k != skip:
                var col = materialize[DIMS]()[o.a]
                var v = Int64(o.selected + (2023 if col == YEAR else 0))
                out.append(Range(col, v, v))
        return out^

    # ---------- the engine ----------

    def compute(mut self):
        var ms = 0.0
        self.results = List[List[Int]]()
        self.counts = List[List[Int]]()
        for k in range(len(self.objects)):
            ref o = self.objects[k]
            if o.kind == PIVOT:
                var cols = self.dim_groups(o.b)
                var r = group_sum(self.frame, self.gf()[], pivot_program(self.dim_program(o.a), cols, self.dim_program(o.b)),
                                  self.frame.program_for(self.value_cols()[min(o.c, len(self.value_cols()) - 1)]), self.ranges(-1),
                                  self.dim_groups(o.a) * cols)
                ms += r.milliseconds
                self.results.append(r.sums.copy())
                self.counts.append(r.counts.copy())
            elif o.kind == CHART:
                var r = group_sum(self.frame, self.gf()[], self.dim_program(o.a),
                                  self.frame.program_for(self.value_cols()[min(o.c, len(self.value_cols()) - 1)]), self.ranges(k),
                                  self.dim_groups(o.a))
                ms += r.milliseconds
                self.results.append(r.sums.copy())
                self.counts.append(r.counts.copy())
            else:
                self.results.append(List[Int]())
                self.counts.append(List[Int]())
        var zero = List[Int64]()
        zero.append(Int64(OP_CONST))
        zero.append(0)
        var total = group_sum(self.frame, self.gf()[], zero, self.frame.program_for(CENTS), self.ranges(-1), 1)
        ms += total.milliseconds
        self.revenue = total.sums[0]
        self.lines = total.counts[0]
        self.milliseconds = ms
        self.version += 1

    # ---------- the grid ----------

    def col_width(self, c: Int) -> Float64:
        var kind = self.frame.kind(c)
        if c == PRODUCT:
            return 190
        if kind == DATE:
            return 104
        if kind == TEXT:
            return 118
        if kind == DECIMAL:
            return 96
        return 72

    def col_left(self, c: Int) -> Float64:
        var x = GUTTER
        for k in range(c):
            x += self.col_width(k)
        return x

    def shown_row(self, i: Int) -> Int:
        """The row number shown at display index i (sorted or natural order), or -1."""
        if len(self.order) > 0:
            return self.order[i] if 0 <= i < len(self.order) else -1
        return i if 0 <= i < self.frame.rows() else -1

    def shown_count(self) -> Int:
        return len(self.order) if len(self.order) > 0 else self.frame.rows()

    def draw_grid(mut self, mut s: Surface):
        var k = s.scale
        ref font = self.font
        s.fill(CARD_BG)
        var w = Float64(s.width)
        var h = Float64(s.height)
        # header
        rect(s, 0, 0, w, HEADER_H * k, BRAND_WASH)
        for c in range(self.frame.columns()):
            var x = self.col_left(c) * k
            var cw = self.col_width(c) * k
            if x > w:
                break
            var name = self.frame.name(c)
            if c >= self.frame.stored():
                name = "ƒ " + name
            font.draw(s, name, x + 8 * k, 20 * k, 13 * k, INK if c != self.sort_col else BRAND, MEDIUM)
            if c == self.sort_col:
                font.draw(s, "▼" if self.sort_desc else "▲", x + cw - 8 * k, 20 * k, 10 * k, BRAND, REGULAR, RIGHT)
            line(s, x, 0, x, h, 1, GRID)
        hline(s, 0, w, HEADER_H * k, GRID)
        # rows
        var y = HEADER_H * k
        var i = self.top
        var shown = 0
        while y < h and shown < 400:
            var row = self.shown_row(i)
            if row < 0:
                break
            i += 1
            if not self.frame.alive(row):
                continue
            var base = y + 18 * k
            if row == self.cur_row:
                rect(s, 0, y, w, ROW_H * k, BRAND_WASH)
            font.draw(s, grouped(row + 1), (GUTTER - 10) * k, base, 12 * k, INK3, REGULAR, RIGHT)
            for c in range(self.frame.columns()):
                var x = self.col_left(c) * k
                var cw = self.col_width(c) * k
                if x > w:
                    break
                var kind = self.frame.kind(c)
                var text = self.frame.display(c, row)
                var numeric = kind == INT or kind == DECIMAL
                var color = INK if c < self.frame.stored() else BRAND_DARK_INK
                if row == self.cur_row and c == self.cur_col:
                    rect(s, x + 1, y + 1, cw - 2, ROW_H * k - 2, CARD_BG)
                    rect(s, x, y, cw, ROW_H * k, BRAND)
                    rect(s, x + 2 * k, y + 2 * k, cw - 4 * k, ROW_H * k - 4 * k, CARD_BG)
                if numeric:
                    font.draw(s, text, x + cw - 8 * k, base, 13 * k, color, REGULAR, RIGHT)
                else:
                    font.draw(s, text, x + 8 * k, base, 13 * k, color)
            y += ROW_H * k
            hline(s, 0, w, y, GRID)
            shown += 1

    def grid_hit(self, x_pt: Float64, y_pt: Float64) -> Tuple[Int, Int]:
        """(row, column) under a tap in points, or (-1, -1)."""
        if y_pt < HEADER_H:
            return (-1, -1)
        var i = self.top
        var y = HEADER_H
        while y + ROW_H <= y_pt + ROW_H:
            var row = self.shown_row(i)
            if row < 0:
                return (-1, -1)
            i += 1
            if not self.frame.alive(row):
                continue
            if y_pt < y + ROW_H:
                for c in range(self.frame.columns()):
                    if self.col_left(c) <= x_pt < self.col_left(c) + self.col_width(c):
                        return (row, c)
                return (row, -1)
            y += ROW_H
        return (-1, -1)

    def scroll_rows(mut self, rows: Int):
        self.top = max(0, min(self.top + rows, max(self.shown_count() - 5, 0)))
        self.version += 1

    # ---------- charts ----------

    def chart(self, k: Int) -> FlintChart:
        ref o = self.objects[k]
        var labels = List[String]()
        var values = List[Float64]()
        var groups = self.dim_groups(o.a)
        for g in range(groups):
            labels.append(self.dim_label(o.a, g))
            values.append(Float64(self.results[k][g]) if g < len(self.results[k]) else 0.0)
        var vc = self.value_cols()[min(o.c, len(self.value_cols()) - 1)]
        var vname = self.frame.name(vc)
        var semantic = String("Price") if self.frame.kind(vc) == DECIMAL else String("Count")
        return (FlintChart("Bar Chart", o.title).text("name", labels).number(vname, values)
                .semantic("name", "Category").semantic(vname, semantic).encode("x", vname).encode("y", "name").size(o.w, o.h - 60))

    def draw(mut self, canvas: Int, mut surface: Surface):
        if canvas >= len(self.objects):
            return
        self.sizes[canvas] = (surface.points_width(), surface.points_height())
        if self.objects[canvas].kind == TABLE:
            self.draw_grid(surface)
        elif self.objects[canvas].kind == CHART:
            self.chart(canvas).draw(surface, self.font, self.objects[canvas].selected)

    # ---------- events ----------

    def select_cell(mut self, row: Int, col: Int):
        self.cur_row = row
        self.cur_col = col
        self.edit_text = self.frame.display(col, row) if row >= 0 and col >= 0 else ""
        self.version += 1

    def update(mut self, event: Event):
        var m = event.message
        if m == GRID_GESTURE:
            if event.number == TAP:
                var hit = self.grid_hit(event.x, event.y)
                if hit[0] >= 0 and hit[1] >= 0:
                    self.select_cell(hit[0], hit[1])
            elif event.number == PAN:
                self.pan -= event.dy / ROW_H
                var rows = Int(self.pan)  # whole rows; the remainder waits for the next motion
                self.pan -= Float64(rows)
                if rows != 0:
                    self.scroll_rows(rows)
            elif event.number == ZOOM and event.zoom > 0:
                self.scroll_rows(Int(-log2(event.zoom) * 12.0))
        elif m == COMMIT:
            if self.cur_row >= 0 and self.cur_col >= 0:
                try:
                    self.frame.set_text(self.cur_col, self.cur_row, event.text)
                    self.message = "Row " + grouped(self.cur_row + 1) + ": " + self.frame.name(self.cur_col) + " = " + self.frame.display(self.cur_col, self.cur_row)
                    self.edit_text = self.frame.display(self.cur_col, self.cur_row)
                    self.compute()
                except e:
                    self.message = String(e)
            else:
                self.message = "Tap a cell first"
            self.version += 1
        elif m == FORMULA:
            try:
                var c = self.frame.formula(event.text)
                self.message = "Formula column " + self.frame.name(c) + " added"
                self.compute()
            except e:
                self.message = String(e)
            self.version += 1
        elif m == ADD_ROW:
            try:
                var row = self.frame.append(List[String]())
                self.order = List[Int]()
                self.sort_col = -1
                self.top = max(row - 6, 0)
                self.select_cell(row, 0)
                self.message = "Row " + grouped(row + 1) + " added: type its values"
                self.compute()
            except e:
                self.message = String(e)
        elif m == DELETE_ROW:
            if self.cur_row >= 0:
                self.frame.remove(self.cur_row)
                self.message = "Row " + grouped(self.cur_row + 1) + " removed (Undo brings it back)"
                self.select_cell(-1, -1)
                self.compute()
        elif m == UNDO:
            var rows = self.frame.rows()
            if self.frame.undo():
                self.message = "Undone"
                if self.frame.rows() != rows:  # an appended row went away: nothing may point at it
                    self.order = List[Int]()
                    self.sort_col = -1
                    if self.cur_row >= self.frame.rows():
                        self.select_cell(-1, -1)
                if self.cur_row >= 0 and self.cur_col >= 0:
                    self.edit_text = self.frame.display(self.cur_col, self.cur_row)
                self.compute()
            else:
                self.message = "Nothing to undo"
            self.version += 1
        elif m == SORT:
            if self.cur_col >= 0:
                if self.sort_col == self.cur_col:
                    self.sort_desc = not self.sort_desc
                else:
                    self.sort_col = self.cur_col
                    self.sort_desc = self.frame.kind(self.cur_col) == DECIMAL or self.frame.kind(self.cur_col) == INT
                self.order = self.frame.permutation(self.sort_col, self.sort_desc)
                self.top = 0
                self.message = "Sorted by " + self.frame.name(self.sort_col) + (" (largest first)" if self.sort_desc else "")
            else:
                self.message = "Tap a cell in the column to sort by"
            self.version += 1
        elif m == PIVOT_ROWS or m == PIVOT_COLS or m == PIVOT_VALUE:
            for k in range(len(self.objects)):
                if self.objects[k].kind == PIVOT:
                    if m == PIVOT_ROWS:
                        self.objects[k].a = event.number
                    elif m == PIVOT_COLS:
                        self.objects[k].b = event.number
                    else:
                        self.objects[k].c = event.number
                    var vname = self.frame.name(self.value_cols()[min(self.objects[k].c, len(self.value_cols()) - 1)])
                    self.objects[k].title = (String("Revenue") if vname == "cents" else vname.upper()) + " by " + self.dim_names()[self.objects[k].a] + " and " + self.dim_names()[self.objects[k].b]
            self.compute()
        elif CHART_TAP <= m < NOTE:
            var k = m - CHART_TAP
            if event.number == TAP and k < len(self.objects):
                var hit = self.chart(k).hit(self.sizes[k][0], self.sizes[k][1], self.font, event.x, event.y)
                if hit >= 0:
                    self.objects[k].selected = -1 if self.objects[k].selected == hit else hit
                    self.compute()
        elif NOTE <= m < CHART_FIELD:
            var k = m - NOTE
            if k < len(self.objects):
                self.objects[k].text = event.text
        elif CHART_FIELD <= m < CLEAR:
            var k = m - CHART_FIELD
            if k < len(self.objects):
                self.objects[k].a = event.number
                self.objects[k].selected = -1
                self.objects[k].title = "Revenue by " + self.dim_names()[event.number]
                self.compute()
        elif m == CLEAR:
            for k in range(len(self.objects)):
                self.objects[k].selected = -1
            self.compute()
        elif m == SAVE:
            try:
                save_workbook(self.path, self.frame, self.source(), self.specs())
                self.message = "Saved " + self.path
            except e:
                self.message = "Couldn't save: " + String(e)
            self.version += 1
        elif m == OPEN:
            var path = self.path
            self.load(path)
            self.compute()
            self.version += 1
        elif m == MOVE or m == RESIZE:
            var k = event.number
            if 0 <= k < len(self.objects):
                var dx = Int(event.dx)
                var dy = Int(event.dy)
                if m == MOVE:
                    self.objects[k].x = max(0, (self.objects[k].x + dx + SNAP // 2) // SNAP * SNAP)
                    self.objects[k].y = max(0, (self.objects[k].y + dy + SNAP // 2) // SNAP * SNAP)
                else:
                    self.objects[k].w = max(200, (self.objects[k].w + dx + SNAP // 2) // SNAP * SNAP)
                    self.objects[k].h = max(120, (self.objects[k].h + dy + SNAP // 2) // SNAP * SNAP)
                self.version += 1

    def specs(self) -> List[ObjectSpec]:
        var out = List[ObjectSpec]()
        for o in self.objects:
            out.append(ObjectSpec(o.kind, o.title, o.x, o.y, o.w, o.h, o.a, o.b, o.c, o.text, o.selected))
        return out^

    # ---------- the screen ----------

    def filter_text(self) -> String:
        var parts = List[String]()
        for k in range(len(self.objects)):
            ref o = self.objects[k]
            if o.kind == CHART and o.selected >= 0:
                parts.append(self.dim_label(o.a, o.selected))
        if len(parts) == 0:
            return "No filter: tap a bar in a chart"
        var out = String("Filtered to ")
        for i in range(len(parts)):
            out += (" · " if i > 0 else "") + parts[i]
        return out

    def table_card(self, k: Int) -> View:
        ref o = self.objects[k]
        var cell = String("Tap a cell to edit it")
        if self.cur_row >= 0 and self.cur_col >= 0:
            cell = "Row " + grouped(self.cur_row + 1) + " · " + self.frame.name(self.cur_col)
        var formulas = String("")
        for c in range(self.frame.stored(), self.frame.columns()):
            formulas += (", " if formulas != "" else " · formulas: ") + self.frame.name(c) + " = " + self.frame.formulas[c - self.frame.stored()].formula
        var columns = String(self.frame.stored()) + " columns · " + grouped(self.frame.rows()) + " rows" + formulas
        return Card(
            HStack(
                Text(o.title, style=HEADLINE),
                Text(columns, style=CAPTION).tag("columns"),
                spacing=12,
            ).justify(BETWEEN).fill(),
            HStack(
                Text(cell, style=CAPTION).tag("cell"),
                TextField(self.edit_text, placeholder="Value", on_submit=COMMIT).width(150),
                Button("Add row", on_tap=ADD_ROW),
                Button("Delete row", on_tap=DELETE_ROW),
                Button("Sort", on_tap=SORT),
                Button("Undo", on_tap=UNDO),
                TextField("", placeholder="Formula", on_submit=FORMULA).width(260),
                Text(self.message, style=CAPTION).tag("message"),
                spacing=8,
            ).fill(),
            Canvas(k, self.version, on_gesture=GRID_GESTURE).fill().height(o.h - 128),  # (a fixed size: the same cell under a tap on every host)
            spacing=8,
        )

    def pivot_card(self, k: Int) -> View:
        ref o = self.objects[k]
        var dims = self.dim_names()
        var rows = self.dim_groups(o.a)
        var cols = self.dim_groups(o.b)
        var cells = List[View]()
        cells.append(Text("", style=CAPTION))
        for j in range(cols):
            cells.append(Text(self.dim_label(o.b, j), style=CAPTION))
        for i in range(rows):
            cells.append(Text(self.dim_label(o.a, i), style=CAPTION))
            for j in range(cols):
                var v = self.results[k][i * cols + j] if i * cols + j < len(self.results[k]) else 0
                cells.append(Text(self.value_text(o.c, v)))
        return Card(
            Text(o.title, style=HEADLINE),
            HStack(
                Dropdown(dims, o.a, on_select=PIVOT_ROWS),
                Text("by", style=CAPTION),
                Dropdown(dims, o.b, on_select=PIVOT_COLS),
                Dropdown(self.value_names(), o.c, on_select=PIVOT_VALUE),
                spacing=8,
            ),
            Scroll(Grid(cells, cols + 1, spacing=6).tag("pivot"), height=o.h - 120).fill(),
            spacing=8,
        )

    def chart_card(self, k: Int) -> View:
        ref o = self.objects[k]
        return Card(
            HStack(
                Text(o.title, style=HEADLINE),
                Dropdown(self.dim_names(), o.a, on_select=CHART_FIELD + k),
                spacing=8,
            ).justify(BETWEEN).fill(),
            Canvas(k, self.version, on_gesture=CHART_TAP + k).grow().fill(),
            spacing=8,
        )

    def note_card(self, k: Int) -> View:
        ref o = self.objects[k]
        return Card(
            Text(o.title, style=HEADLINE),
            TextArea(o.text, placeholder="Write a note…", on_change=NOTE + k, height=o.h - 70).fill(),
            spacing=8,
        )

    def view(self) -> View:
        var items = List[View]()
        var names: List[String] = ["table", "pivot", "chart", "note"]
        var seen = List[Int](length=4, fill=0)
        var board_h = 0
        for k in range(len(self.objects)):
            ref o = self.objects[k]
            var card = self.table_card(k) if o.kind == TABLE else (self.pivot_card(k) if o.kind == PIVOT else (self.chart_card(k) if o.kind == CHART else self.note_card(k)))
            var name = names[o.kind] + ("" if seen[o.kind] == 0 else String(seen[o.kind] + 1))
            seen[o.kind] += 1
            items.append(card^.at(o.x, o.y).width(o.w).height(o.h).tag(name))
            board_h = max(board_h, o.y + o.h)
        var engine = self.gf()[].device_name()
        var bar = HStack(
            Text("Contoso Workbook", style=TITLE),
            Text(exact_money(self.revenue) + " revenue · " + grouped(self.lines) + " order lines", style=CAPTION).tag("summary"),
            Text(self.filter_text(), style=CAPTION).tag("filter"),
            Button("Clear filters", on_tap=CLEAR),
            Spacer(),
            Button("Save", on_tap=SAVE),
            Button("Open", on_tap=OPEN),
            Text("Recomputed in " + fixed(self.milliseconds, 1) + " ms on " + engine, style=CAPTION),
            spacing=16,
        ).fill()
        return VStack(
            bar,
            Board(items, 1360, board_h + 16, on_move=MOVE, on_resize=RESIZE).tag("board"),
            spacing=12,
        ).padding(16, 24).align(START).fill().grow()


comptime BRAND_DARK_INK = rgba(17, 94, 163)


def exact_money(cents: Int) -> String:
    """$3,812,345,678.90: every cent, so an edit anywhere shows in the total."""
    var a = cents if cents >= 0 else -cents
    var frac = String(a % 100)
    if a % 100 < 10:
        frac = "0" + frac
    return ("-" if cents < 0 else "") + "$" + grouped(a // 100) + "." + frac
