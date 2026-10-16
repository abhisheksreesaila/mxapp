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
from mojoui.text import Font, REGULAR, MEDIUM, LEFT, RIGHT, CENTRE
from mojoui.draw import rect, hline, line
from mojoui.charts import money, grouped, fixed, INK, INK2, INK3, BRAND, BRAND_TINT, BRAND_WASH, CARD_BG, GRID
from mojoui.flint import FlintChart
from mojoui.frame import Frame, Range, share, OP_COL, OP_CONST, OP_SUB, TEXT, DECIMAL, DATE, INT
from mojoui.frame_gpu import GpuFrame, group_sum, pivot_program
from mojoui.contoso import generate_columns, CATEGORY, REGION, CHANNEL, PRODUCT, QUANTITY, CENTS, COST, YEAR
from mojoui.gpu import gpu_present, GroupSums
from mojoui.shared import put_shared, get_shared, keep, at, count_load, environment
from mojoui.workbook import save_workbook, open_workbook, read_widths, ObjectSpec
from mojoui.maths import log2
from mojoui.theme import Palette

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
comptime BAR_W = 14.0  # the grid's scroll bar
comptime CARD_PAD_X = 14  # a card's padding (both hosts' CSS) and where its grid starts inside it:
comptime GRID_TOP = 96  # padding 12 + header row 32 + gap 10 + formula bar 32 + gap 10
comptime CELL_COMMIT = 280  # the in-place editor's Enter

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
    var pal: Palette  # the person's Omarchy theme: the grid and the charts draw in it
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
    var bar_drag: Bool  # the grid's current drag started on its scroll bar
    var bar_grab: Float64  # where on the thumb it was grabbed (points from the thumb's top)
    var grid_k: Int  # the table card the last grid gesture came from (its size drives the scroll bar)
    var widths: List[Float64]  # per column: its width in points (0 = the default for its type)
    var left: Float64  # the grid scrolled sideways (points)
    var resize_col: Int  # a header edge being dragged, or -1
    var resize_x0: Float64
    var resize_w0: Float64
    var editing: Bool  # the in-place editor is open over the selected cell
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
        self.bar_drag = False
        self.bar_grab = 0
        self.grid_k = 0
        self.widths = List[Float64]()
        self.left = 0
        self.resize_col = -1
        self.resize_x0 = 0
        self.resize_w0 = 0
        self.editing = False
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
            self.order = List[Int]()
            self.sort_col = -1
            self.select_cell(-1, -1)
            self.widths = List[Float64]()
            for wd in read_widths(path):
                self.widths.append(Float64(wd))
            self.left = 0
            self.editing = False
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

    def col_width(self, c: Int) -> Float64:
        if c < len(self.widths) and self.widths[c] > 0:
            return self.widths[c]
        return self.default_width(c)

    def default_width(self, c: Int) -> Float64:
        """Its type's width, or its header's if that's wider."""
        return max(self.type_width(c), self.font.measure(self.frame.name(c), 12.5, self.pal.medium) + 26)

    def type_width(self, c: Int) -> Float64:
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
        """Where column c starts in the grid (points), the sideways scroll applied."""
        var x = GUTTER - self.left
        for k in range(c):
            x += self.col_width(k)
        return x

    def columns_width(self) -> Float64:
        var x = GUTTER
        for c in range(self.frame.columns()):
            x += self.col_width(c)
        return x

    def set_width(mut self, c: Int, w: Float64):
        while len(self.widths) <= c:
            self.widths.append(0)
        self.widths[c] = min(max(w, 40.0), 600.0)
        self.version += 1

    def fit(mut self, c: Int):
        """Column c as wide as its header and the values around what's on screen (200 rows)."""
        var w = self.font.measure(self.frame.name(c) + ("ƒ " if c >= self.frame.stored() else ""), 12.5, self.pal.medium) + 34
        var i = max(self.top - 100, 0)
        var seen = 0
        while seen < 200:
            var row = self.shown_row(i)
            if row < 0:
                break
            i += 1
            if self.frame.alive(row):
                w = max(w, self.font.measure(self.frame.display(c, row), 13, self.pal.regular) + 18)
                seen += 1
        self.set_width(c, w)

    def scroll_sideways(mut self, dx: Float64):
        var view = (self.sizes[self.grid_k][0] if self.grid_k < len(self.sizes) else 1200.0) - BAR_W
        var most = max(self.columns_width() - view, 0.0)
        var left = min(max(self.left - dx, 0.0), most)
        if left != self.left:
            self.left = left
            self.version += 1

    def edge_hit(self, x_pt: Float64, y_pt: Float64) -> Int:
        """The column whose header's right edge is under (x, y) (5 pt either side), or -1."""
        if y_pt >= HEADER_H:
            return -1
        for c in range(self.frame.columns()):
            var edge = self.col_left(c) + self.col_width(c)
            if abs(x_pt - edge) <= 5 and edge > GUTTER:
                return c
        return -1

    def clip(self, text: String, room: Float64, size: Float64, weight: Int) -> String:
        """text, cut with … to fit `room` pixels."""
        if self.font.measure(text, size, weight) <= room:
            return text
        var out = String("")
        for ch in text.codepoint_slices():
            if self.font.measure(out + String(ch) + "…", size, weight) > room:
                break
            out += String(ch)
        return out + "…"

    def shown_row(self, i: Int) -> Int:
        """The row number shown at display index i (sorted or natural order), or -1."""
        if len(self.order) > 0:
            return self.order[i] if 0 <= i < len(self.order) else -1
        return i if 0 <= i < self.frame.rows() else -1

    def display_index(self, row: Int) -> Int:
        """Where `row` sits in the shown order (sorted or natural), or -1."""
        if len(self.order) == 0:
            return row if 0 <= row < self.frame.rows() else -1
        for i in range(len(self.order)):
            if self.order[i] == row:
                return i
        return -1

    def editor_place(self) -> Tuple[Int, Int, Int]:
        """Where the in-place editor goes on the page: (x, y, width) over the selected cell, or width 0
        when it's closed or its cell isn't on screen."""
        var k = self.grid_k if 0 <= self.grid_k < len(self.objects) and self.objects[self.grid_k].kind == TABLE else self.table_index()
        if not self.editing or k < 0 or self.cur_row < 0 or self.cur_col < 0:
            return (0, 0, 0)
        var line = -1
        var i = self.top
        var seen = 0
        while seen < self.rows_in(self.sizes[k][1]):
            var row = self.shown_row(i)
            if row < 0:
                break
            i += 1
            if not self.frame.alive(row):
                continue
            if row == self.cur_row:
                line = seen
                break
            seen += 1
        var x = self.col_left(self.cur_col)
        if line < 0 or x < GUTTER:
            return (0, 0, 0)
        ref o = self.objects[k]
        var w = min(self.col_width(self.cur_col), self.sizes[k][0] - BAR_W - x)
        return (o.x + PAGE_X + CARD_PAD_X + Int(x), o.y + PAGE_Y + GRID_TOP + 30 + line * 26 - 2, Int(max(w, 60.0)))

    def shown_count(self) -> Int:
        return len(self.order) if len(self.order) > 0 else self.frame.rows()

    def grid_rows(self) -> Int:
        """Whole rows the grid shows (from the last-used table's drawn size)."""
        var k = self.grid_k if 0 <= self.grid_k < len(self.objects) and self.objects[self.grid_k].kind == TABLE else self.table_index()
        var h = self.sizes[k][1] if k >= 0 else 380.0
        return self.rows_in(h)

    def rows_in(self, h: Float64) -> Int:
        return max(Int((h - HEADER_H) / ROW_H), 1)

    def table_index(self) -> Int:
        for k in range(len(self.objects)):
            if self.objects[k].kind == TABLE:
                return k
        return -1

    def thumb(self, h: Float64) -> Tuple[Float64, Float64]:
        """The scroll bar's thumb (top, height) in points for a grid h points tall."""
        var track = h - HEADER_H
        var count = max(self.shown_count(), 1)
        var visible = min(self.rows_in(h), count)
        var size = max(track * Float64(visible) / Float64(count), 28.0)
        var span = max(count - visible, 1)
        return (HEADER_H + (track - size) * Float64(min(self.top, span)) / Float64(span), size)

    def scroll_to_thumb(mut self, thumb_top: Float64, h: Float64):
        """Moves the grid so the thumb's top sits at thumb_top (points)."""
        var t = self.thumb(h)
        var room = max(h - HEADER_H - t[1], 1.0)
        var span = max(self.shown_count() - min(self.rows_in(h), self.shown_count()), 0)
        var f = min(max((thumb_top - HEADER_H) / room, 0.0), 1.0)
        var top = Int(f * Float64(span) + 0.5)
        if top != self.top:
            self.top = top
            self.version += 1

    def draw_grid(mut self, mut s: Surface):
        var k = s.scale
        ref font = self.font
        ref p = self.pal
        s.fill(p.card)
        var w = Float64(s.width)
        var h = Float64(s.height)
        var right = w - BAR_W * k  # the columns stop where the scroll bar starts
        var gut = GUTTER * k
        var col_pick = self.cur_col if self.cur_row < 0 else -1  # a whole column selected
        # header
        rect(s, 0, 0, w, HEADER_H * k, p.raised)
        for c in range(self.frame.columns()):
            var x = self.col_left(c) * k
            var cw = self.col_width(c) * k
            if x >= right:
                break
            if x + cw <= gut:
                continue
            cw = min(cw, right - x)
            if c == col_pick:
                rect(s, x, 0, cw, h, p.accent_wash)  # the column, tinted top to bottom
                rect(s, x, 0, cw, HEADER_H * k, p.accent)
            var name = self.frame.name(c)
            if c >= self.frame.stored():
                name = "ƒ " + name
            var ink = p.accent_ink if c == col_pick else (p.accent if c == self.sort_col else p.ink2)
            font.draw(s, self.clip(name, cw - 26 * k, 12.5 * k, p.medium), x + 8 * k, 20 * k, 12.5 * k, ink, p.medium)
            if c == self.sort_col:  # a small triangle (the font has no arrows): ▼ largest first, ▲ smallest first
                var ax = x + cw - 14 * k
                var ay = 15 * k
                var tint = p.accent_ink if c == col_pick else p.accent
                for r in range(Int(5 * k)):
                    var half = Float64(r) * 0.9
                    var yy = ay + (2.5 * k - Float64(r) if self.sort_desc else Float64(r) - 2.5 * k)  # widest row on top: ▼
                    rect(s, ax - half, yy, 2 * half + 1, 1, tint)
            line(s, x + cw, 0, x + cw, h, 1, p.line)
            if c == self.resize_col:
                line(s, x + cw - 1, 0, x + cw - 1, h, 2, p.accent)  # the edge being dragged
        rect(s, 0, 0, gut, HEADER_H * k, p.raised)  # (the gutter stays put when the grid scrolls sideways)
        hline(s, 0, w, HEADER_H * k, p.line_strong)
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
                rect(s, 0, y, right, ROW_H * k, p.accent_wash)
            for c in range(self.frame.columns()):
                var x = self.col_left(c) * k
                var cw = self.col_width(c) * k
                if x >= right:
                    break
                if x + cw <= gut:
                    continue
                cw = min(cw, right - x)
                var kind = self.frame.kind(c)
                var text = self.clip(self.frame.display(c, row), cw - 16 * k, 13 * k, p.regular)
                var numeric = kind == INT or kind == DECIMAL
                var color = p.ink if c < self.frame.stored() else p.formula
                if row == self.cur_row and c == self.cur_col:
                    rect(s, x, y, cw, ROW_H * k, p.accent)
                    rect(s, x + 2 * k, y + 2 * k, cw - 4 * k, ROW_H * k - 4 * k, p.card)
                if numeric:
                    font.draw(s, text, x + cw - 8 * k, base, 13 * k, color, p.regular, RIGHT)
                else:
                    font.draw(s, text, x + 8 * k, base, 13 * k, color, p.regular)
            rect(s, 0, y, gut, ROW_H * k, p.accent_wash if row == self.cur_row else p.card)
            font.draw(s, grouped(row + 1), (GUTTER - 10) * k, base, 12 * k, p.ink3, p.regular, RIGHT)
            y += ROW_H * k
            hline(s, 0, right, y, p.line)
            shown += 1
        line(s, gut, 0, gut, h, 1, p.line)
        # the scroll bar: a thin track, a thumb sized to the share of rows on screen
        var t = self.thumb(h / k)
        rect(s, right, HEADER_H * k, BAR_W * k, h - HEADER_H * k, p.card)
        rect(s, right + 3 * k, t[0] * k + 2 * k, (BAR_W - 6) * k, t[1] * k - 4 * k, p.ink3 if self.bar_drag else p.line_strong)

    def on_bar(self, x_pt: Float64, y_pt: Float64) -> Bool:
        """Whether (x, y) is on the scroll bar of the last-used table (below its header)."""
        var t = self.grid_k
        return 0 <= t < len(self.sizes) and x_pt >= self.sizes[t][0] - BAR_W and y_pt >= HEADER_H

    def header_hit(self, x_pt: Float64, y_pt: Float64) -> Int:
        """The column whose header is under (x, y) in points, or -1."""
        if y_pt >= HEADER_H:
            return -1
        for c in range(self.frame.columns()):
            if self.col_left(c) <= x_pt < self.col_left(c) + self.col_width(c):
                return c
        return -1

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
                .semantic("name", "Category").semantic(vname, semantic).encode("x", vname).encode("y", "name").size(o.w, o.h - 60)
                .themed(self.pal))

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
        self.edit_text = self.frame.display(col, row) if row >= 0 and col >= 0 else ""  # (row -1: a whole column)
        self.version += 1

    def update(mut self, event: Event):
        var m = event.message
        if m != CELL_COMMIT and self.editing:  # anything else closes the in-place editor (its edit isn't written)
            self.editing = False
            self.version += 1
        if GRID_GESTURE <= m < GRID_GESTURE + MAX_OBJECTS:
            self.grid_k = m - GRID_GESTURE
            var h = self.sizes[self.grid_k][1] if self.grid_k < len(self.sizes) else 380.0
            if event.number == PRESS and self.edge_hit(event.x, event.y) >= 0:  # a header's edge: resize that column
                self.resize_col = self.edge_hit(event.x, event.y)
                self.resize_x0 = event.x
                self.resize_w0 = self.col_width(self.resize_col)
                self.bar_drag = False
                self.version += 1
            elif event.number == PRESS:  # a drag or tap starts: on the scroll bar it grabs (or jumps) the thumb
                self.resize_col = -1
                var was = self.bar_drag
                self.bar_drag = self.on_bar(event.x, event.y)
                if self.bar_drag:
                    var t = self.thumb(h)
                    if t[0] <= event.y < t[0] + t[1]:
                        self.bar_grab = event.y - t[0]
                    else:  # the track: the thumb jumps there, centred on the pointer
                        self.bar_grab = t[1] / 2
                        self.scroll_to_thumb(event.y - self.bar_grab, h)
                    self.version += 1
                elif was:
                    self.version += 1
            elif event.number == RELEASE:  # a drag ended: the thumb (or a column edge) lets go
                if self.resize_col >= 0:
                    self.message = "Column " + self.frame.name(self.resize_col) + " is " + String(Int(self.col_width(self.resize_col))) + " pt wide"
                    self.resize_col = -1
                    self.version += 1
                if self.bar_drag:
                    self.bar_drag = False
                    self.version += 1
            elif event.number == DOUBLE:
                if event.y < HEADER_H:  # a header: fit the column to what's in it
                    var c = self.header_hit(event.x, event.y)
                    if c < 0:
                        c = self.edge_hit(event.x, event.y)
                    if c >= 0:
                        self.fit(c)
                        self.message = "Column " + self.frame.name(c) + " fitted (" + String(Int(self.col_width(c))) + " pt)"
                elif not self.on_bar(event.x, event.y):  # a cell: edit it in place
                    var hit = self.grid_hit(event.x, event.y)
                    if hit[0] >= 0 and hit[1] >= 0:
                        self.select_cell(hit[0], hit[1])
                        if hit[1] < self.frame.stored():
                            self.editing = True
                            self.message = "Editing row " + grouped(hit[0] + 1) + " · " + self.frame.name(hit[1]) + ": Enter writes it"
                        else:
                            self.message = "ƒ " + self.frame.name(hit[1]) + " is a formula: edit the columns it uses"
                        self.version += 1
            elif event.number == TAP:
                if self.on_bar(event.x, event.y):
                    self.bar_drag = False
                    self.version += 1
                elif event.y < HEADER_H:
                    var c = self.header_hit(event.x, event.y)
                    if c >= 0:  # a header: the whole column (what Sort will sort)
                        self.select_cell(-1, c)
                        self.message = "Column " + self.frame.name(c) + " selected: Sort orders the table by it"
                else:
                    var hit = self.grid_hit(event.x, event.y)
                    if hit[0] >= 0 and hit[1] >= 0:
                        self.select_cell(hit[0], hit[1])
            elif event.number == PAN and self.resize_col >= 0:
                self.set_width(self.resize_col, self.resize_w0 + event.x - self.resize_x0)
            elif event.number == PAN and self.bar_drag:
                self.scroll_to_thumb(event.y - self.bar_grab, h)
            elif event.number == PAN:
                if event.dx != 0:
                    self.scroll_sideways(event.dx)
                self.pan -= event.dy / ROW_H
                var rows = Int(self.pan)  # whole rows; the remainder waits for the next motion
                self.pan -= Float64(rows)
                if rows != 0:
                    self.scroll_rows(rows)
            elif event.number == ZOOM and event.zoom > 0:
                self.scroll_rows(Int(-log2(event.zoom) * 12.0))
        elif m == CELL_COMMIT:  # the in-place editor's Enter: write the cell, then select the one below (as a spreadsheet does)
            if self.cur_row >= 0 and self.cur_col >= 0:
                try:
                    self.frame.set_text(self.cur_col, self.cur_row, event.text)
                    self.message = "Row " + grouped(self.cur_row + 1) + ": " + self.frame.name(self.cur_col) + " = " + self.frame.display(self.cur_col, self.cur_row)
                    var col = self.cur_col
                    var i = self.display_index(self.cur_row)
                    var below = self.shown_row(i + 1) if i >= 0 else -1
                    while below >= 0 and not self.frame.alive(below):
                        i += 1
                        below = self.shown_row(i + 1)
                    self.editing = False
                    self.select_cell(below if below >= 0 else self.cur_row, col)
                    self.compute()
                except e:
                    self.message = String(e)
                    self.editing = False
            self.version += 1
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
                self.fit(c)
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
                var ws = List[Int]()
                for wd in self.widths:
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
        if self.cur_col >= 0:
            var dims = materialize[DIMS]()
            for d in range(len(dims)):
                if dims[d] == self.cur_col:
                    dim = d
            var vcols = self.value_cols()
            for v in range(len(vcols)):
                if vcols[v] == self.cur_col:
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
        if self.cur_row >= 0 and self.cur_col >= 0:
            cell = "Row " + grouped(self.cur_row + 1) + " · " + self.frame.name(self.cur_col)
        elif self.cur_col >= 0:
            cell = "Column " + self.frame.name(self.cur_col)
        var formulas = String("")
        for c in range(self.frame.stored(), self.frame.columns()):
            formulas += (", " if formulas != "" else " · formulas: ") + self.frame.name(c) + " = " + self.frame.formulas[c - self.frame.stored()].formula
        var columns = String(self.frame.stored()) + " columns · " + grouped(self.frame.rows()) + " rows" + formulas
        var first = min(self.top + 1, self.shown_count())
        var position = "Rows " + grouped(first) + "–" + grouped(min(self.top + self.grid_rows(), self.shown_count())) + " of " + grouped(self.shown_count())
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
            Canvas(k, self.version, on_gesture=GRID_GESTURE + k).fill().height(o.h - 124),  # (a fixed size: the same cell under a tap on every host)
            spacing=10,
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
            Scroll(Grid(cells, cols + 1, spacing=6).tag("pivot"), height=o.h - 120).fill(),
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
            items.append(TextField(self.frame.display(self.cur_col, self.cur_row), placeholder="Cell", on_submit=CELL_COMMIT).focused()
                         .at(ed[0], ed[1]).width(ed[2]).height(30).tag("cell-editor"))  # (a row, 26 pt, and its 2-pt ring each side)
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
