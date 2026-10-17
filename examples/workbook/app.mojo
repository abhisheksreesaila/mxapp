# The Workbook: a Numbers-style page of objects over one engine (mojoui.frame + frame_gpu).
#   Table  — typed columns over 20M rows, edited row by row, formula columns ("margin = cents - cost")
#   Pivot  — rows × columns × value, aggregated on the GPU
#   Chart  — a Flint spec; tap a bar to filter the other objects (crossfiltering)
#   Note   — text
# Columns, never cell addresses. The data is shared by every session of the process (init_shared);
# a session's edits are a sparse overlay applied as exact deltas to the GPU totals.

from mojoui.view import (View, Text, Button, TextField, Dropdown, TextArea, Canvas, Board, Overlay, VStack, HStack, Card, Grid, Spacer,
                         Divider, Scroll, TITLE, HEADLINE, CAPTION, PROMINENT, DESTRUCTIVE, SUBTLE, ICON_ONLY, START, CENTER, END,
                         BETWEEN, TAP, PAN, ZOOM, PRESS, RELEASE, DOUBLE, FLUENT, OMARCHY, NO_MSG)
from mojoui.app import App, Event
from mojoui.canvas import Surface, rgba
from mojoui.text import Font, REGULAR, MEDIUM, MONO, LEFT, RIGHT, CENTRE
from mojoui.draw import rect, hline, line
from mojoui.charts import money, grouped, fixed, INK, INK2, INK3, BRAND, BRAND_TINT, BRAND_WASH, CARD_BG, GRID
from mojoui.flint import FlintChart
from mojoui.chartview import ChartView
from mojoui.pivot import PivotTable
from mojoui.frame import Frame, Range, share, OP_COL, OP_CONST, OP_SUB, TEXT, DECIMAL, DATE, INT
from mojoui.frame_gpu import GpuFrame, group_sum, pivot_program
from mojoui.contoso import generate_columns, CATEGORY, REGION, CHANNEL, PRODUCT, QUANTITY, CENTS, COST, YEAR
from mojoui.gpu import gpu_present, GroupSums
from mojoui.shared import put_shared, get_shared, keep, at, count_load, environment
from mojoui.workbook import save_workbook, open_workbook, read_widths, ObjectSpec
from mojoui.maths import log2
from mojoui.theme import Palette
from mojoui.datagrid import (DataGrid, GRID_NONE, GRID_REDRAW, GRID_SELECTED, GRID_COLUMN, GRID_EDIT, GRID_READ_ONLY,
                             GRID_FITTED, GRID_RESIZED, GRID_TYPED, GRID_CLEAR, GRID_CANCEL, GRID_HEADER_H, GRID_ROW_H, GRID_GUTTER, GRID_BAR_W)

comptime SOURCE_PREFIX = "contoso:"  # + the row count: the shared table's source name (a workbook file names it instead of copying it)
comptime SAMPLE = "examples/workbook/contoso.mxwb"

# messages
comptime GRID_GESTURE = 250  # + the table card's index (each table knows its own size)
comptime COMMIT = 2
comptime FORMULA = 3
comptime ADD_ROW = 4
comptime DELETE_ROW = 5
comptime UNDO = 6
comptime PIVOT_ROWS = 160  # + object index (each pivot has its own)
comptime PIVOT_COLS = 190  # + object index
comptime PIVOT_VALUE = 220  # + object index
comptime CHART_TAP = 10  # + object index
comptime NOTE = 40  # + object index
comptime CHART_FIELD = 70  # + object index
comptime CLEAR = 100
comptime SORT = 101
comptime MOVE = 102
comptime RESIZE = 103
comptime SAVE = 104
comptime OPEN = 105
comptime ADD_OBJ = 106  # + the kind (TABLE, PIVOT, CHART, NOTE_OBJ): the toolbar's Insert buttons
comptime REMOVE_OBJ = 130  # + object index
comptime MAX_OBJECTS = 30  # (the per-object message ranges above allow 30)

# object kinds
comptime TABLE = 0
comptime PIVOT = 1
comptime CHART = 2
comptime NOTE_OBJ = 3

comptime DIMS: List[Int] = [CATEGORY, REGION, CHANNEL, PRODUCT, YEAR]  # what pivots and charts group by
comptime SNAP = 8
comptime PAGE_X = 24  # where the objects start on the page (clear of the islands floating over it)
comptime PAGE_Y = 80
comptime PAGE_W = 1232  # the objects' width (the page is PAGE_X wider each side: 1280 pt in all, a 13" laptop)
comptime CARD_PAD_X = 14  # a card's padding (both hosts' CSS) and where its grid starts inside it:
comptime GRID_TOP = 96  # padding 12 + header row 32 + gap 10 + formula bar 32 + gap 10
comptime CELL_COMMIT = 280  # the in-place editor's Enter
comptime CELL_CANCEL = 281  # the in-place editor's Escape

comptime HEADER_H = GRID_HEADER_H  # (the grid's, re-exported for tests)


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
    var pal: Palette  # the person's Omarchy theme: the grid and the charts draw in it
    var objects: List[Obj]
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
    var grid: DataGrid  # the table's grid (mojoui.datagrid): scroll, selection, widths, sort marker, editor
    var grid_k: Int  # the table card the last grid gesture came from (its size drives the scroll bar)
    var reveal_k: Int  # the object the page should scroll to (the one just inserted), or -1
    var reveal_count: Int

    @staticmethod
    def init_shared():
        if get_shared(0) != 0:
            return
        var rows = 20_000_000 if gpu_present() else 2_000_000
        var asked = environment("MOJOUI_ROWS")  # e.g. 1000000 while iterating on the UI
        if asked != "":
            try:
                rows = max(Int(asked), 1000)
            except:
                pass
        var addr = share(generate_columns(rows))
        put_shared(0, addr)
        put_shared(1, keep(GpuFrame(addr)))
        count_load()

    def __init__(out self):
        if get_shared(0) == 0:  # no host built the shared data (a test constructing the app directly)
            Self.init_shared()
        self.frame = Frame(get_shared(0))
        self.gf_addr = get_shared(1)
        self.font = Font()
        self.pal = Palette.omarchy()
        self.objects = List[Obj]()
        self.objects.append(obj(TABLE, "Order lines", 0, 0, 1232, 380))
        self.objects.append(obj(PIVOT, "Revenue by region and channel", 0, 396, 480, 300, a=1, b=2, c=1))
        self.objects.append(obj(CHART, "Revenue by category", 496, 396, 360, 300, a=0, c=1))
        self.objects.append(obj(CHART, "Revenue by region", 872, 396, 360, 300, a=1, c=1))
        self.objects.append(obj(NOTE_OBJ, "Note", 0, 712, 480, 136, text="Please review this: Q4 revenue by region, then the margin column."))
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
        self.grid_k = 0
        self.grid = DataGrid()
        self.reveal_k = -1
        self.reveal_count = 0
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
            self.grid = DataGrid()
            self.select_cell(-1, -1)
            for wd in read_widths(path):
                self.grid.widths.append(Float64(wd))
            self.message = "Opened " + path
        except e:
            if not quiet:
                self.message = "Couldn't open: " + String(e)

    def title(self) -> String:
        return "Contoso Workbook"

    def window_size(self) -> Tuple[Int, Int]:
        return (1440, 900)

    def design(self) -> Int:
        return OMARCHY

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

    def table_index(self) -> Int:
        for k in range(len(self.objects)):
            if self.objects[k].kind == TABLE:
                return k
        return -1

    def editor_place(self) -> Tuple[Int, Int, Int]:
        """Where the in-place editor goes on the page: the grid's place for it, plus where the grid sits
        on the page (its table card's position and the card's fixed rows above the grid)."""
        var k = self.grid_k if 0 <= self.grid_k < len(self.objects) and self.objects[self.grid_k].kind == TABLE else self.table_index()
        var at = self.grid.editor_place(self.frame)
        if k < 0 or at[2] == 0:
            return (0, 0, 0)
        ref o = self.objects[k]
        return (o.x + PAGE_X + CARD_PAD_X + at[0], o.y + PAGE_Y + GRID_TOP + at[1], at[2])

    # ---------- charts ----------

    def chart(self, k: Int) -> ChartView:
        """Chart object k as a ChartView (mojoui.chartview): its group-by results, its picked bar."""
        ref o = self.objects[k]
        var labels = List[String]()
        var values = List[Float64]()
        var groups = self.dim_groups(o.a)
        for g in range(groups):
            labels.append(self.dim_label(o.a, g))
            values.append(Float64(self.results[k][g]) if g < len(self.results[k]) else 0.0)
        var vc = self.value_cols()[min(o.c, len(self.value_cols()) - 1)]
        var cv = ChartView(o.title, labels^, values^, self.frame.name(vc), self.frame.kind(vc) == DECIMAL, o.selected)
        cv.size = self.sizes[k]
        return cv^

    def draw(mut self, canvas: Int, mut surface: Surface):
        if canvas >= len(self.objects):
            return
        self.sizes[canvas] = (surface.points_width(), surface.points_height())
        if self.objects[canvas].kind == TABLE:
            self.grid.draw(surface, self.frame, self.font, self.pal)
        elif self.objects[canvas].kind == CHART:
            var cv = self.chart(canvas)
            cv.draw(surface, self.font, self.pal)

    # ---------- events ----------

    def select_cell(mut self, row: Int, col: Int):
        self.grid.cur_row = row
        self.grid.cur_col = col
        self.edit_text = self.frame.display(col, row) if row >= 0 and col >= 0 else ""  # (row -1: a whole column)
        self.version += 1

    def update(mut self, event: Event):
        var m = event.message
        if m != CELL_COMMIT and m != CELL_CANCEL and self.grid.editing and not (GRID_GESTURE <= m < GRID_GESTURE + MAX_OBJECTS):
            self.grid.editing = False  # anything else closes the in-place editor (its edit isn't written)
            self.version += 1
        if GRID_GESTURE <= m < GRID_GESTURE + MAX_OBJECTS:
            self.grid_k = m - GRID_GESTURE
            var action = self.grid.handle(event, self.frame, self.font, self.pal)
            ref g = self.grid
            if action == GRID_SELECTED or action == GRID_EDIT or action == GRID_READ_ONLY:
                self.select_cell(g.cur_row, g.cur_col)
                if action == GRID_EDIT:
                    self.message = "Editing row " + grouped(g.cur_row + 1) + " · " + self.frame.name(g.cur_col) + ": Enter writes it, Escape cancels"
                elif action == GRID_READ_ONLY:
                    self.message = "ƒ " + self.frame.name(g.cur_col) + " is a formula: edit the columns it uses"
            elif action == GRID_TYPED:  # a key typed on a cell: the editor starts from it (it replaces the value)
                self.select_cell(g.cur_row, g.cur_col)
                self.edit_text = g.typed
                self.message = "Editing row " + grouped(g.cur_row + 1) + " · " + self.frame.name(g.cur_col) + ": Enter writes it, Escape cancels"
            elif action == GRID_CANCEL:
                self.select_cell(g.cur_row, g.cur_col)
                self.message = "Edit cancelled"
            elif action == GRID_CLEAR:
                var col = g.cur_col
                var row = g.cur_row
                try:
                    self.frame.set_text(col, row, "")
                    self.message = "Row " + grouped(row + 1) + ": " + self.frame.name(col) + " cleared"
                    self.select_cell(row, col)
                    self.compute()
                except:  # numbers and dates have no blank yet (docs/plans/needs-mxframe.md)
                    self.message = self.frame.name(col) + " can't be empty yet: type a value (0 to zero it)"
                self.version += 1
            elif action == GRID_COLUMN:
                self.select_cell(-1, g.cur_col)
                self.message = "Column " + self.frame.name(g.cur_col) + " selected: Sort orders the table by it"
            elif action == GRID_FITTED:
                self.message = "Column " + self.frame.name(g.last_col) + " fitted (" + String(Int(g.col_width(g.last_col, self.frame))) + " pt)"
                self.version += 1
            elif action == GRID_RESIZED:
                self.message = "Column " + self.frame.name(g.last_col) + " is " + String(Int(g.col_width(g.last_col, self.frame))) + " pt wide"
                self.version += 1
            elif action == GRID_REDRAW:
                self.version += 1
        elif m == CELL_COMMIT:  # the in-place editor's Enter: write the cell, then select the one below (as a spreadsheet does)
            if self.grid.editing and self.grid.cur_row >= 0 and self.grid.cur_col >= 0:  # (a second Enter after it closed writes nothing)
                try:
                    self.frame.set_text(self.grid.cur_col, self.grid.cur_row, event.text)
                    self.message = "Row " + grouped(self.grid.cur_row + 1) + ": " + self.frame.name(self.grid.cur_col) + " = " + self.frame.display(self.grid.cur_col, self.grid.cur_row)
                    self.grid.committed(self.frame)
                    self.select_cell(self.grid.cur_row, self.grid.cur_col)
                    self.compute()
                except e:
                    self.edit_text = event.text
                    self.message = String(e) + " (fix it and press Enter)"  # the editor stays open with what was typed
            self.version += 1
        elif m == CELL_CANCEL:  # the in-place editor's Escape: nothing written
            self.grid.cancel_edit()
            self.select_cell(self.grid.cur_row, self.grid.cur_col)
            self.message = "Edit cancelled"
        elif m == COMMIT:
            if self.grid.cur_row >= 0 and self.grid.cur_col >= 0:
                try:
                    self.frame.set_text(self.grid.cur_col, self.grid.cur_row, event.text)
                    self.message = "Row " + grouped(self.grid.cur_row + 1) + ": " + self.frame.name(self.grid.cur_col) + " = " + self.frame.display(self.grid.cur_col, self.grid.cur_row)
                    self.edit_text = self.frame.display(self.grid.cur_col, self.grid.cur_row)
                    self.compute()
                except e:
                    self.message = String(e)
            else:
                self.message = "Tap a cell first"
            self.version += 1
        elif m == FORMULA:
            try:
                var c = self.frame.formula(event.text)
                self.grid.min_widths = List[Float64]()  # (a new column: measure the headers again)
                self.grid.prepare(self.frame, self.font, self.pal)
                self.grid.fit(c, self.frame, self.font, self.pal)
                self.message = "Formula column " + self.frame.name(c) + " added"
                self.compute()
            except e:
                self.message = String(e)
            self.version += 1
        elif m == ADD_ROW:
            try:
                var row = self.frame.append(List[String]())
                self.grid.clear_order()
                self.grid.top = max(row - 6, 0)
                self.select_cell(row, 0)
                self.message = "Row " + grouped(row + 1) + " added: type its values"
                self.compute()
            except e:
                self.message = String(e)
        elif m == DELETE_ROW:
            if self.grid.cur_row >= 0:
                self.frame.remove(self.grid.cur_row)
                self.message = "Row " + grouped(self.grid.cur_row + 1) + " removed (Undo brings it back)"
                self.select_cell(-1, -1)
                self.compute()
        elif m == UNDO:
            var rows = self.frame.rows()
            if self.frame.undo():
                self.message = "Undone"
                if self.frame.rows() != rows:  # an appended row went away: nothing may point at it
                    self.grid.clear_order()
                    if self.grid.cur_row >= self.frame.rows():
                        self.select_cell(-1, -1)
                if self.grid.cur_row >= 0 and self.grid.cur_col >= 0:
                    self.edit_text = self.frame.display(self.grid.cur_col, self.grid.cur_row)
                self.compute()
            else:
                self.message = "Nothing to undo"
            self.version += 1
        elif m == SORT:
            var col = self.grid.cur_col
            if col >= 0:
                var desc = (not self.grid.sort_desc) if self.grid.sort_col == col else (self.frame.kind(col) == DECIMAL or self.frame.kind(col) == INT)
                self.grid.set_order(self.frame.permutation(col, desc), col, desc)
                self.message = "Sorted by " + self.frame.name(col) + (" (largest first)" if desc else "")
            else:
                self.message = "Tap a column header (or a cell) to choose what to sort by"
            self.version += 1
        elif PIVOT_ROWS <= m < PIVOT_VALUE + MAX_OBJECTS:
            var k = (m - PIVOT_ROWS) % MAX_OBJECTS
            if k < len(self.objects) and self.objects[k].kind == PIVOT:
                if m < PIVOT_COLS:
                    self.objects[k].a = event.number
                elif m < PIVOT_VALUE:
                    self.objects[k].b = event.number
                else:
                    self.objects[k].c = event.number
                self.objects[k].title = self.pivot_title(self.objects[k])
                self.compute()
        elif CHART_TAP <= m < NOTE:
            var k = m - CHART_TAP
            if event.number == TAP and k < len(self.objects):
                var cv = self.chart(k)
                if cv.tap(event.x, event.y, self.font, self.pal):
                    self.objects[k].selected = cv.selected
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
                var ws = List[Int]()
                for wd in self.grid.widths:
                    ws.append(Int(wd))
                save_workbook(self.path, self.frame, self.source(), self.specs(), ws)
                self.message = "Saved " + self.path
            except e:
                self.message = "Couldn't save: " + String(e)
            self.version += 1
        elif m == OPEN:
            var path = self.path
            self.load(path)
            self.compute()
            self.version += 1
        elif ADD_OBJ <= m < ADD_OBJ + 4:
            if len(self.objects) < MAX_OBJECTS:
                self.insert(m - ADD_OBJ)
            else:
                self.message = "This page holds " + String(MAX_OBJECTS) + " cards at most"
                self.version += 1
        elif REMOVE_OBJ <= m < REMOVE_OBJ + MAX_OBJECTS:
            var k = m - REMOVE_OBJ
            if k < len(self.objects):
                self.message = "Removed " + self.objects[k].title
                _ = self.objects.pop(k)
                _ = self.sizes.pop(k)
                self.reveal_k = -1
                self.compute()
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

    def value_label(self, c: Int) -> String:
        var vname = self.frame.name(self.value_cols()[min(c, len(self.value_cols()) - 1)])
        if vname == "cents":
            return "Revenue"
        if vname == "quantity":
            return "Units"
        return String(vname[byte=0:1]).upper() + String(vname[byte=1:])

    def pivot_title(self, o: Obj) -> String:
        return self.value_label(o.c) + " by " + self.dim_names()[o.a] + " and " + self.dim_names()[o.b]

    def free_spot(self, w: Int, h: Int) -> Tuple[Int, Int]:
        """The first place on the page (top to bottom, left to right, 16-pt steps) where a w×h card
        overlaps nothing, with a 16-pt gap."""
        var y = 0
        while y < 20000:
            var x = 0
            while x + w <= PAGE_W:
                var clear = True
                for o in self.objects:
                    if x < o.x + o.w + 16 and o.x < x + w + 16 and y < o.y + o.h + 16 and o.y < y + h + 16:
                        clear = False
                        break
                if clear:
                    return (x, y)
                x += 16
            y += 16
        return (0, y)

    def insert(mut self, kind: Int):
        """A new card in the first free spot; the page scrolls to it. Pivots and charts start from the
        selection: a selected text column (or year) becomes what they group by, a number column their value."""
        var dim = -1
        var value = 1  # cents
        if self.grid.cur_col >= 0:
            var dims = materialize[DIMS]()
            for d in range(len(dims)):
                if dims[d] == self.grid.cur_col:
                    dim = d
            var vcols = self.value_cols()
            for v in range(len(vcols)):
                if vcols[v] == self.grid.cur_col:
                    value = v
        var o: Obj
        if kind == TABLE:
            o = obj(TABLE, "Order lines", 0, 0, PAGE_W, 380)
        elif kind == PIVOT:
            var rows = dim if dim >= 0 else 0
            var cols = 4 if rows != 4 else 2  # by year (or, for a year pivot, by channel)
            o = obj(PIVOT, "", 0, 0, 480, 300, a=rows, b=cols, c=value)
            o.title = self.pivot_title(o)
        elif kind == CHART:
            var by = dim if dim >= 0 else 2
            o = obj(CHART, self.value_label(value) + " by " + self.dim_names()[by], 0, 0, 360, 300, a=by, c=value)
        else:
            o = obj(NOTE_OBJ, "Note", 0, 0, 480, 136)
        var at = self.free_spot(o.w, o.h)
        o.x = at[0]
        o.y = at[1]
        self.objects.append(o^)
        self.sizes.append((400.0, 300.0))
        self.reveal_k = len(self.objects) - 1
        self.reveal_count += 1
        var names: List[String] = ["table", "pivot", "chart", "note"]
        self.message = "Added a " + names[kind] + ": " + self.objects[self.reveal_k].title + " (drag it by its header)"
        self.compute()

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
            return "Tap a bar to filter"
        var out = String("Filtered to ")
        for i in range(len(parts)):
            out += (" · " if i > 0 else "") + parts[i]
        return out

    def card_header(self, k: Int, var title: View, var extra: View) -> View:
        """A card's header row: its title (and what goes beside it) on the left, its actions and a
        quiet Remove on the right. The header is also where the card is dragged from."""
        return HStack(title^, HStack(extra^, Button("Remove", on_tap=REMOVE_OBJ + k, style=ICON_ONLY, icon="close"), spacing=4),
                      spacing=12).justify(BETWEEN).fill().height(32)  # (fixed heights: the in-place editor knows where the grid starts)

    def table_card(self, k: Int) -> View:
        ref o = self.objects[k]
        var cell = String("Select a cell")
        if self.grid.cur_row >= 0 and self.grid.cur_col >= 0:
            cell = "Row " + grouped(self.grid.cur_row + 1) + " · " + self.frame.name(self.grid.cur_col)
        elif self.grid.cur_col >= 0:
            cell = "Column " + self.frame.name(self.grid.cur_col)
        var formulas = String("")
        for c in range(self.frame.stored(), self.frame.columns()):
            formulas += (", " if formulas != "" else " · formulas: ") + self.frame.name(c) + " = " + self.frame.formulas[c - self.frame.stored()].formula
        var columns = String(self.frame.stored()) + " columns · " + grouped(self.frame.rows()) + " rows" + formulas
        var position = self.grid.position_text(self.frame)
        return Card(
            self.card_header(k,
                HStack(Text(o.title, style=HEADLINE), Text(columns, style=CAPTION).tag("columns"),
                       Text(position, style=CAPTION).tag("position"), spacing=12),
                HStack(
                    Button("Add row", on_tap=ADD_ROW, style=SUBTLE, icon="row-plus"),
                    Button("Delete row", on_tap=DELETE_ROW, style=SUBTLE, icon="row-minus"),
                    Button("Sort", on_tap=SORT, style=SUBTLE, icon="sort"),
                    spacing=2,
                )),
            HStack(  # the formula bar: what's selected, its value, and a new formula column
                Text(cell, style=CAPTION).tag("cell").width(150),
                TextField(self.edit_text, placeholder="Value", on_submit=COMMIT).grow(),
                Text("ƒ", style=HEADLINE),
                TextField("", placeholder="Formula", on_submit=FORMULA).width(320),
                spacing=8,
            ).fill().height(32),
            Canvas(k, self.version + self.grid.version, on_gesture=GRID_GESTURE + k, keys=True).fill().height(o.h - 124),  # (a fixed size: the same cell under a tap on every host)
            spacing=10,
        )

    def pivot_card(self, k: Int) -> View:
        ref o = self.objects[k]
        var dims = self.dim_names()
        var rows = self.dim_groups(o.a)
        var cols = self.dim_groups(o.b)
        var row_labels = List[String]()
        var col_labels = List[String]()
        var cells = List[String]()
        for j in range(cols):
            col_labels.append(self.dim_label(o.b, j))
        for i in range(rows):
            row_labels.append(self.dim_label(o.a, i))
            for j in range(cols):
                var v = self.results[k][i * cols + j] if i * cols + j < len(self.results[k]) else 0
                cells.append(self.value_text(o.c, v))
        return Card(
            self.card_header(k, Text(o.title, style=HEADLINE), HStack()),
            HStack(
                Text("Rows", style=CAPTION),
                Dropdown(dims, o.a, on_select=PIVOT_ROWS + k),
                Text("Columns", style=CAPTION),
                Dropdown(dims, o.b, on_select=PIVOT_COLS + k),
                Text("Value", style=CAPTION),
                Dropdown(self.value_names(), o.c, on_select=PIVOT_VALUE + k),
                spacing=6,
            ),
            PivotTable(row_labels, col_labels, cells, height=o.h - 120),
            spacing=10,
        )

    def chart_card(self, k: Int) -> View:
        ref o = self.objects[k]
        return Card(
            self.card_header(k, Text(o.title, style=HEADLINE), Dropdown(self.dim_names(), o.a, on_select=CHART_FIELD + k)),
            Canvas(k, self.version, on_gesture=CHART_TAP + k).grow().fill(),
            spacing=8,
        )

    def note_card(self, k: Int) -> View:
        ref o = self.objects[k]
        return Card(
            self.card_header(k, Text(o.title, style=HEADLINE), HStack()),
            TextArea(o.text, placeholder="Write a note…", on_change=NOTE + k, height=o.h - 92).fill(),
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
            items.append(card^.at(o.x + PAGE_X, o.y + PAGE_Y).width(o.w).height(o.h).tag(name))
            board_h = max(board_h, o.y + o.h)
        var ed = self.editor_place()
        if ed[2] > 0:  # the in-place editor floats on the page over its cell (last: drawn on top)
            items.append(self.grid.editor(self.edit_text, CELL_COMMIT, CELL_CANCEL)
                         .at(ed[0], ed[1]).width(ed[2]).height(30))  # (a row, 26 pt, and its 2-pt ring each side)
        var engine = self.gf()[].device_name()
        # The chrome floats over the page in islands; the page scrolls underneath.
        var title = HStack(Text("Contoso Workbook", style=HEADLINE), spacing=12)
        var tools = HStack(
            Button("Table", on_tap=ADD_OBJ + TABLE, style=SUBTLE, icon="table"),
            Button("Pivot", on_tap=ADD_OBJ + PIVOT, style=SUBTLE, icon="pivot"),
            Button("Chart", on_tap=ADD_OBJ + CHART, style=SUBTLE, icon="chart-bar"),
            Button("Note", on_tap=ADD_OBJ + NOTE_OBJ, style=SUBTLE, icon="note"),
            Button("Undo", on_tap=UNDO, style=SUBTLE, icon="undo"),
            spacing=2,
        )
        var file = HStack(
            Button("Open", on_tap=OPEN, style=SUBTLE, icon="open"),
            Button("Save", on_tap=SAVE, style=PROMINENT, icon="save"),
            spacing=6,
        )
        var status = HStack(
            Text(exact_money(self.revenue) + " revenue · " + grouped(self.lines) + " lines", style=CAPTION).tag("summary"),
            Text(self.filter_text(), style=CAPTION).tag("filter"),
            Button("Clear filters", on_tap=CLEAR, style=SUBTLE, icon="filter-off"),
            Text(self.message, style=CAPTION).tag("message"),
            spacing=10,
        )
        var engine_island = Text(fixed(self.milliseconds, 1) + " ms on " + engine, style=CAPTION).tag("engine")
        return Overlay(
            Board(items, PAGE_W + 2 * PAGE_X, board_h + PAGE_Y + 72, on_move=MOVE, on_resize=RESIZE,
                  reveal=self.reveal_k, reveal_count=self.reveal_count).tag("board").grow().fill(),
            title^.pin(START, START),
            tools^.pin(CENTER, START),
            file^.pin(END, START),
            status^.pin(START, END),
            engine_island^.pin(END, END),
        ).grow().fill()


comptime BRAND_DARK_INK = rgba(17, 94, 163)
comptime HEADER_BG = rgba(250, 250, 250)
comptime SELECTED_HEADER = rgba(15, 108, 189)  # (Fluent's brand blue: a selected column's header)
comptime GRID_DARK = rgba(209, 209, 209)
comptime BAR_TRACK = rgba(250, 250, 250)
comptime BAR_THUMB = rgba(194, 194, 194)
comptime BAR_THUMB_ACTIVE = rgba(138, 138, 138)


def exact_money(cents: Int) -> String:
    """$3,812,345,678.90: every cent, so an edit anywhere shows in the total."""
    var a = cents if cents >= 0 else -cents
    var frac = String(a % 100)
    if a % 100 < 10:
        frac = "0" + frac
    return ("-" if cents < 0 else "") + "$" + grouped(a // 100) + "." + frac
