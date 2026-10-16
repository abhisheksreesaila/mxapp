# mojoui.datagrid: a spreadsheet-style grid over any number of rows, drawn on a Canvas.
#
#   var grid = DataGrid()                                   # app state, one per table on screen
#   Canvas(id, version, on_gesture=GRID)                   # in view()
#   grid.draw(surface, source, font, palette)              # in draw()
#   var action = grid.handle(event, source, font, palette) # in update(): GRID_* tells the app what happened
#
# What it does on its own: virtual scrolling (only the rows on screen are read), a scroll bar (drag the
# thumb, click the track), cell and whole-column selection, a sort marker, column widths (drag a header's
# edge, double-click a header to fit), sideways scrolling, an in-place editor's placement, header
# histograms (when the app hands it the shapes), long text cut with "…". What it leaves to the app:
# the data (a GridSource), writing values and sorting (engine operations: the grid only shows them).

from mojoui.app import Event
from mojoui.view import TAP, PAN, ZOOM, PRESS, RELEASE, DOUBLE
from mojoui.canvas import Surface
from mojoui.text import Font, MONO, RIGHT
from mojoui.draw import rect, hline, line
from mojoui.theme import Palette
from mojoui.maths import log2

comptime GRID_ROW_H = 26.0
comptime GRID_HEADER_H = 30.0
comptime GRID_HISTOGRAM_H = 22.0  # extra header height when columns show their distributions
comptime GRID_GUTTER = 64.0
comptime GRID_BAR_W = 14.0

# what handle() reports
comptime GRID_NONE = 0
comptime GRID_REDRAW = 1  # only the grid's own state changed (scrolled, a drag, a width)
comptime GRID_SELECTED = 2  # a cell was selected (grid.cur_row, grid.cur_col)
comptime GRID_COLUMN = 3  # a whole column was selected (grid.cur_col)
comptime GRID_EDIT = 4  # the in-place editor opened over the selected cell
comptime GRID_READ_ONLY = 5  # a double click on a column that can't be edited (a formula)
comptime GRID_FITTED = 6  # a column was fitted (grid.cur_col is unchanged; grid.last_col is the column)
comptime GRID_RESIZED = 7  # a header edge drag ended (grid.last_col)


trait GridSource:
    """The data a DataGrid shows. Rows are numbered 0…grid_rows()-1; some may be gone (grid_alive)."""

    def grid_rows(self) -> Int:
        ...

    def grid_alive(self, row: Int) -> Bool:
        ...

    def grid_columns(self) -> Int:
        ...

    def grid_name(self, c: Int) -> String:
        ...

    def grid_numeric(self, c: Int) -> Bool:
        """Numbers are right-aligned."""
        ...

    def grid_editable(self, c: Int) -> Bool:
        """False for computed columns (drawn in the formula colour, marked ƒ)."""
        ...

    def grid_text(self, c: Int, row: Int) -> String:
        ...

    def grid_type_width(self, c: Int) -> Float64:
        """A sensible default width for the column's values (points)."""
        ...


struct DataGrid(Copyable, Movable):
    var top: Int  # first shown row (an index into `order`, or a row number)
    var left: Float64  # scrolled sideways (points)
    var order: List[Int]  # the rows in shown order (a sort), or empty: natural order
    var sort_col: Int
    var sort_desc: Bool
    var cur_row: Int  # selection: a cell, or (cur_row -1) a whole column
    var cur_col: Int
    var widths: List[Float64]  # per column, points (0 = its default)
    var min_widths: List[Float64]  # per column: its header's width (from prepare())
    var histograms: List[List[Float64]]  # per column: bar heights 0–1 (empty: none drawn)
    var editing: Bool
    var bar_drag: Bool
    var bar_grab: Float64
    var resize_col: Int
    var resize_x0: Float64
    var resize_w0: Float64
    var last_col: Int
    var pan: Float64
    var size: Tuple[Float64, Float64]  # the canvas in points (from the last draw)
    var version: Int  # bumped whenever the grid needs redrawing (add it into the Canvas version)

    def __init__(out self):
        self.top = 0
        self.left = 0
        self.order = List[Int]()
        self.sort_col = -1
        self.sort_desc = False
        self.cur_row = -1
        self.cur_col = -1
        self.widths = List[Float64]()
        self.min_widths = List[Float64]()
        self.histograms = List[List[Float64]]()
        self.editing = False
        self.bar_drag = False
        self.bar_grab = 0
        self.resize_col = -1
        self.resize_x0 = 0
        self.resize_w0 = 0
        self.last_col = -1
        self.pan = 0
        self.size = (1200.0, 256.0)
        self.version = 1

    # ---------- geometry ----------

    def header_h(self) -> Float64:
        return GRID_HEADER_H + (GRID_HISTOGRAM_H if len(self.histograms) > 0 else 0.0)

    def prepare[S: GridSource](mut self, src: S, font: Font, pal: Palette):
        """Measures the headers (a column is never narrower than its name). Cheap; call before using widths."""
        var n = src.grid_columns()
        if len(self.min_widths) == n:
            return
        self.min_widths = List[Float64](capacity=n)
        for c in range(n):
            var name = src.grid_name(c) + ("" if src.grid_editable(c) else "ƒ ")
            self.min_widths.append(font.measure(name, 12.5, pal.medium) + 26)

    def col_width[S: GridSource](self, c: Int, src: S) -> Float64:
        if c < len(self.widths) and self.widths[c] > 0:
            return self.widths[c]
        var header = self.min_widths[c] if c < len(self.min_widths) else 0.0
        return max(src.grid_type_width(c), header)

    def col_left[S: GridSource](self, c: Int, src: S) -> Float64:
        """Where column c starts (points), the sideways scroll applied."""
        var x = GRID_GUTTER - self.left
        for k in range(c):
            x += self.col_width(k, src)
        return x

    def columns_width[S: GridSource](self, src: S) -> Float64:
        var x = GRID_GUTTER
        for c in range(src.grid_columns()):
            x += self.col_width(c, src)
        return x

    def rows_in(self, h: Float64) -> Int:
        return max(Int((h - self.header_h()) / GRID_ROW_H), 1)

    def shown_count[S: GridSource](self, src: S) -> Int:
        return len(self.order) if len(self.order) > 0 else src.grid_rows()

    def shown_row[S: GridSource](self, i: Int, src: S) -> Int:
        """The row at display index i (sorted or natural order), or -1."""
        if len(self.order) > 0:
            return self.order[i] if 0 <= i < len(self.order) else -1
        return i if 0 <= i < src.grid_rows() else -1

    def screen_line[S: GridSource](self, row: Int, src: S) -> Int:
        """Which line on screen shows `row` (0 = the first under the header), or -1."""
        var i = self.top
        var seen = 0
        while seen < self.rows_in(self.size[1]):
            var r = self.shown_row(i, src)
            if r < 0:
                return -1
            i += 1
            if not src.grid_alive(r):
                continue
            if r == row:
                return seen
            seen += 1
        return -1

    def thumb[S: GridSource](self, h: Float64, src: S) -> Tuple[Float64, Float64]:
        """The scroll bar's thumb (top, height) in points for a grid h points tall."""
        var head = self.header_h()
        var track = h - head
        var count = max(self.shown_count(src), 1)
        var visible = min(self.rows_in(h), count)
        var size = max(track * Float64(visible) / Float64(count), 28.0)
        var span = max(count - visible, 1)
        return (head + (track - size) * Float64(min(self.top, span)) / Float64(span), size)

    def editor_place[S: GridSource](self, src: S) -> Tuple[Int, Int, Int]:
        """Where the in-place editor goes, in the canvas's points: (x, y, width) over the selected cell,
        or width 0 when it's closed or the cell isn't fully on screen."""
        if not self.editing or self.cur_row < 0 or self.cur_col < 0:
            return (0, 0, 0)
        var line_no = self.screen_line(self.cur_row, src)
        var x = self.col_left(self.cur_col, src)
        var w = self.col_width(self.cur_col, src)
        if line_no < 0 or x < GRID_GUTTER or x + w > self.size[0] - GRID_BAR_W:
            return (0, 0, 0)
        return (Int(x), Int(self.header_h()) + line_no * 26 - 2, Int(w))  # (26: GRID_ROW_H)

    def position_text[S: GridSource](self, src: S) -> String:
        """ "Rows 1–8 of 20,000,000" """
        var count = self.shown_count(src)
        return "Rows " + _grouped(min(self.top + 1, count)) + "–" + _grouped(min(self.top + self.rows_in(self.size[1]), count)) + " of " + _grouped(count)

    # ---------- hit tests ----------

    def in_columns(self, x: Float64) -> Bool:
        return GRID_GUTTER <= x < self.size[0] - GRID_BAR_W

    def on_bar(self, x: Float64, y: Float64) -> Bool:
        return x >= self.size[0] - GRID_BAR_W and y >= self.header_h()

    def header_hit[S: GridSource](self, x: Float64, y: Float64, src: S) -> Int:
        if y >= self.header_h() or not self.in_columns(x):
            return -1
        var left = GRID_GUTTER - self.left
        for c in range(src.grid_columns()):
            var w = self.col_width(c, src)
            if left <= x < left + w:
                return c
            left += w
        return -1

    def edge_hit[S: GridSource](self, x: Float64, y: Float64, src: S) -> Int:
        """The column whose header's right edge is under (x, y) (5 pt either side), or -1."""
        if y >= self.header_h():
            return -1
        var edge = GRID_GUTTER - self.left
        for c in range(src.grid_columns()):
            edge += self.col_width(c, src)
            if abs(x - edge) <= 5 and edge > GRID_GUTTER:
                return c
        return -1

    def cell_hit[S: GridSource](self, x: Float64, y: Float64, src: S) -> Tuple[Int, Int]:
        """(row, column) under (x, y) in points, or (-1, -1). Only whole rows on screen count."""
        if y < self.header_h() or not self.in_columns(x):
            return (-1, -1)
        var line_no = Int((y - self.header_h()) / GRID_ROW_H)
        if line_no >= self.rows_in(self.size[1]):
            return (-1, -1)
        var i = self.top
        var seen = 0
        while True:
            var r = self.shown_row(i, src)
            if r < 0:
                return (-1, -1)
            i += 1
            if not src.grid_alive(r):
                continue
            if seen == line_no:
                var left = GRID_GUTTER - self.left
                for c in range(src.grid_columns()):
                    var w = self.col_width(c, src)
                    if left <= x < left + w:
                        return (r, c)
                    left += w
                return (r, -1)
            seen += 1

    # ---------- changes ----------

    def redraw(mut self):
        self.version += 1

    def select(mut self, row: Int, col: Int):
        self.cur_row = row
        self.cur_col = col
        self.editing = False
        self.redraw()

    def set_order(mut self, var order: List[Int], col: Int, descending: Bool):
        """Show the rows in this order (the engine's sort); col and descending set the header marker."""
        self.order = order^
        self.sort_col = col
        self.sort_desc = descending
        self.top = 0
        self.redraw()

    def clear_order(mut self):
        self.order = List[Int]()
        self.sort_col = -1
        self.redraw()

    def scroll_rows[S: GridSource](mut self, rows: Int, src: S):
        self.top = max(0, min(self.top + rows, max(self.shown_count(src) - 5, 0)))
        self.redraw()

    def scroll_to_thumb[S: GridSource](mut self, thumb_top: Float64, src: S):
        var h = self.size[1]
        var t = self.thumb(h, src)
        var room = max(h - self.header_h() - t[1], 1.0)
        var span = max(self.shown_count(src) - min(self.rows_in(h), self.shown_count(src)), 0)
        var f = min(max((thumb_top - self.header_h()) / room, 0.0), 1.0)
        var top = Int(f * Float64(span) + 0.5)
        if top != self.top:
            self.top = top
            self.redraw()

    def scroll_sideways[S: GridSource](mut self, dx: Float64, src: S):
        var most = max(self.columns_width(src) - (self.size[0] - GRID_BAR_W), 0.0)
        var left = min(max(self.left - dx, 0.0), most)
        if left != self.left:
            self.left = left
            self.redraw()

    def reveal_cell[S: GridSource](mut self, row: Int, col: Int, src: S):
        """Scrolls so the cell is fully on screen (rows and columns)."""
        if self.screen_line(row, src) < 0:
            var i = 0
            var shown = self.shown_count(src)
            if len(self.order) > 0:
                for k in range(len(self.order)):
                    if self.order[k] == row:
                        i = k
            else:
                i = row
            self.top = max(0, min(i - self.rows_in(self.size[1]) // 2, max(shown - 1, 0)))
        var x = self.col_left(col, src)
        var w = self.col_width(col, src)
        var room = self.size[0] - GRID_BAR_W
        if x < GRID_GUTTER:
            self.left -= GRID_GUTTER - x
        elif x + w > room:
            self.left += min(x + w - room, x - GRID_GUTTER)
        self.left = max(self.left, 0.0)
        self.redraw()

    def set_width(mut self, c: Int, w: Float64):
        while len(self.widths) <= c:
            self.widths.append(0)
        self.widths[c] = min(max(w, 40.0), 600.0)
        self.redraw()

    def fit[S: GridSource](mut self, c: Int, src: S, font: Font, pal: Palette):
        """Column c as wide as its header and the values around what's on screen (200 rows)."""
        var w = self.min_widths[c] + 8 if c < len(self.min_widths) else 60.0
        var i = max(self.top - 100, 0)
        var seen = 0
        while seen < 200:
            var r = self.shown_row(i, src)
            if r < 0:
                break
            i += 1
            if src.grid_alive(r):
                w = max(w, font.measure(src.grid_text(c, r), 13, pal.regular) + 18)
                seen += 1
        self.set_width(c, w)
        self.last_col = c

    def next_row[S: GridSource](self, row: Int, src: S) -> Int:
        """The row shown below `row` (skipping removed ones), or -1."""
        var line_no = self.screen_line(row, src)
        var i: Int
        if line_no >= 0:  # on screen: walk from the top (cheap even when sorted)
            i = self.top
            var seen = 0
            while seen <= line_no:
                var r = self.shown_row(i, src)
                i += 1
                if r >= 0 and src.grid_alive(r):
                    seen += 1
        else:
            i = row + 1 if len(self.order) == 0 else -1
            if i < 0:
                return -1
        while True:
            var r = self.shown_row(i, src)
            if r < 0:
                return -1
            if src.grid_alive(r):
                return r
            i += 1

    def committed[S: GridSource](mut self, src: S):
        """After the app wrote the editor's value: close it and select the cell below (as a spreadsheet does)."""
        var below = self.next_row(self.cur_row, src)
        var col = self.cur_col
        self.editing = False
        self.select(below if below >= 0 else self.cur_row, col)

    # ---------- events ----------

    def handle[S: GridSource](mut self, event: Event, src: S, font: Font, pal: Palette) -> Int:
        """A gesture on the grid's canvas. Returns GRID_*; the grid's own state is already updated."""
        self.prepare(src, font, pal)
        var head = self.header_h()
        if event.number == PRESS:
            self.editing = False
            if self.edge_hit(event.x, event.y, src) >= 0:  # a header's edge: resize that column
                self.resize_col = self.edge_hit(event.x, event.y, src)
                self.resize_x0 = event.x
                self.resize_w0 = self.col_width(self.resize_col, src)
                self.bar_drag = False
                self.redraw()
                return GRID_REDRAW
            self.resize_col = -1
            var was = self.bar_drag
            self.bar_drag = self.on_bar(event.x, event.y)
            if self.bar_drag:
                var t = self.thumb(self.size[1], src)
                if t[0] <= event.y < t[0] + t[1]:
                    self.bar_grab = event.y - t[0]
                else:  # the track: the thumb jumps there, centred on the pointer
                    self.bar_grab = t[1] / 2
                    self.scroll_to_thumb(event.y - self.bar_grab, src)
                self.redraw()
                return GRID_REDRAW
            if was:
                self.redraw()
                return GRID_REDRAW
            return GRID_NONE
        if event.number == RELEASE:  # a drag ended: the thumb (or a column edge) lets go
            var result = GRID_NONE
            if self.resize_col >= 0:
                self.last_col = self.resize_col
                self.resize_col = -1
                result = GRID_RESIZED
            if self.bar_drag:
                self.bar_drag = False
                if result == GRID_NONE:
                    result = GRID_REDRAW
            self.redraw()
            return result
        if event.number == DOUBLE:
            if event.y < head:  # a header: fit the column to what's in it
                var c = self.header_hit(event.x, event.y, src)
                if c < 0:
                    c = self.edge_hit(event.x, event.y, src)
                if c >= 0:
                    self.fit(c, src, font, pal)
                    return GRID_FITTED
                return GRID_NONE
            if self.on_bar(event.x, event.y):
                return GRID_NONE
            var hit = self.cell_hit(event.x, event.y, src)
            if hit[0] < 0 or hit[1] < 0:
                return GRID_NONE
            self.select(hit[0], hit[1])
            if not src.grid_editable(hit[1]):
                return GRID_READ_ONLY
            self.reveal_cell(hit[0], hit[1], src)
            self.editing = True
            return GRID_EDIT
        if event.number == TAP:
            if self.resize_col >= 0:  # a click on an edge without a drag: nothing to resize
                self.resize_col = -1
                self.redraw()
            if self.on_bar(event.x, event.y):
                self.bar_drag = False
                self.redraw()
                return GRID_REDRAW
            if event.y < head:
                var c = self.header_hit(event.x, event.y, src)
                if c >= 0:  # a header: the whole column
                    self.select(-1, c)
                    return GRID_COLUMN
                return GRID_NONE
            var hit = self.cell_hit(event.x, event.y, src)
            if hit[0] >= 0 and hit[1] >= 0:
                self.select(hit[0], hit[1])
                return GRID_SELECTED
            return GRID_NONE
        if event.number == PAN:
            if self.resize_col >= 0:
                self.set_width(self.resize_col, self.resize_w0 + event.x - self.resize_x0)
            elif self.bar_drag:
                self.scroll_to_thumb(event.y - self.bar_grab, src)
            else:
                if event.dx != 0:
                    self.scroll_sideways(event.dx, src)
                self.pan -= event.dy / GRID_ROW_H
                var rows = Int(self.pan)  # whole rows; the remainder waits for the next motion
                self.pan -= Float64(rows)
                if rows != 0:
                    self.scroll_rows(rows, src)
            return GRID_REDRAW
        if event.number == ZOOM and event.zoom > 0:
            self.scroll_rows(Int(-log2(event.zoom) * 12.0), src)
            return GRID_REDRAW
        return GRID_NONE

    # ---------- drawing ----------

    def clip(self, text: String, room: Float64, size: Float64, weight: Int, font: Font) -> String:
        """text, cut with … to fit `room` pixels."""
        if weight == MONO and Float64(text.byte_length()) * 0.6 * size <= room:
            return text  # (JetBrains Mono: every glyph is 0.6 em wide: short text fits without measuring)
        if font.measure(text, size, weight) <= room:
            return text
        var out = String("")
        for ch in text.codepoint_slices():
            if font.measure(out + String(ch) + "…", size, weight) > room:
                break
            out += String(ch)
        return out + "…"

    def draw[S: GridSource](mut self, mut s: Surface, src: S, font: Font, p: Palette):
        self.prepare(src, font, p)
        self.size = (s.points_width(), s.points_height())
        var k = s.scale
        s.fill(p.card)
        var w = Float64(s.width)
        var h = Float64(s.height)
        var head = self.header_h() * k
        var right = w - GRID_BAR_W * k  # the columns stop where the scroll bar starts
        var gut = GRID_GUTTER * k
        var col_pick = self.cur_col if self.cur_row < 0 else -1  # a whole column selected
        # every column's left edge and width, once per frame (pixels)
        var ncols = src.grid_columns()
        var lefts = List[Float64](capacity=ncols)
        var widths = List[Float64](capacity=ncols)
        var xpos = (GRID_GUTTER - self.left) * k
        for c in range(ncols):
            var cw = self.col_width(c, src) * k
            lefts.append(xpos)
            widths.append(cw)
            xpos += cw
        # header (and each column's distribution under its name)
        rect(s, 0, 0, w, head, p.raised)
        for c in range(ncols):
            var x = lefts[c]
            var cw = widths[c]
            if x >= right:
                break
            if x + cw <= gut:
                continue
            cw = min(cw, right - x)
            if c == col_pick:
                rect(s, x, 0, cw, h, p.accent_wash)  # the column, tinted top to bottom
                rect(s, x, 0, cw, head, p.accent)
            var name = src.grid_name(c)
            if not src.grid_editable(c):
                name = "ƒ " + name
            var ink = p.accent_ink if c == col_pick else (p.accent if c == self.sort_col else p.ink2)
            font.draw(s, self.clip(name, cw - 26 * k, 12.5 * k, p.medium, font), x + 8 * k, 20 * k, 12.5 * k, ink, p.medium)
            if c == self.sort_col:  # a small triangle (the font has no arrows): ▼ largest first, ▲ smallest first
                var ax = x + cw - 14 * k
                var ay = 15 * k
                var tint = p.accent_ink if c == col_pick else p.accent
                for r in range(Int(5 * k)):
                    var half = Float64(r) * 0.9
                    var yy = ay + (2.5 * k - Float64(r) if self.sort_desc else Float64(r) - 2.5 * k)  # widest row on top: ▼
                    rect(s, ax - half, yy, 2 * half + 1, 1, tint)
            if c < len(self.histograms) and len(self.histograms[c]) > 0:
                ref bars = self.histograms[c]
                var n = len(bars)
                var bw = (cw - 16 * k) / Float64(n)
                var base_y = head - 5 * k
                var tall = (GRID_HISTOGRAM_H - 7) * k
                for b in range(n):
                    var bh = max(bars[b] * tall, 1.0 * k if bars[b] > 0 else 0.0)
                    rect(s, x + 8 * k + Float64(b) * bw, base_y - bh, max(bw - 1.5 * k, 1.0), bh,
                         p.accent_ink if c == col_pick else p.accent_tint)
            line(s, x + cw, 0, x + cw, h, 1, p.line)
            if c == self.resize_col:
                line(s, x + cw - 1, 0, x + cw - 1, h, 2, p.accent)  # the edge being dragged
        rect(s, 0, 0, gut, head, p.raised)  # (the gutter stays put when the grid scrolls sideways)
        hline(s, 0, w, head, p.line_strong)
        # rows
        var y = head
        var i = self.top
        var shown = 0
        while y < h and shown < 400:
            var row = self.shown_row(i, src)
            if row < 0:
                break
            i += 1
            if not src.grid_alive(row):
                continue
            var base = y + 18 * k
            if row == self.cur_row:
                rect(s, 0, y, right, GRID_ROW_H * k, p.accent_wash)
            for c in range(ncols):
                var x = lefts[c]
                var cw = widths[c]
                if x >= right:
                    break
                if x + cw <= gut:
                    continue
                cw = min(cw, right - x)
                var text = self.clip(src.grid_text(c, row), cw - 16 * k, 13 * k, p.regular, font)
                var color = p.ink if src.grid_editable(c) else p.formula
                if row == self.cur_row and c == self.cur_col:
                    rect(s, x, y, cw, GRID_ROW_H * k, p.accent)
                    rect(s, x + 2 * k, y + 2 * k, cw - 4 * k, GRID_ROW_H * k - 4 * k, p.card)
                if src.grid_numeric(c):
                    font.draw(s, text, x + cw - 8 * k, base, 13 * k, color, p.regular, RIGHT)
                else:
                    font.draw(s, text, x + 8 * k, base, 13 * k, color, p.regular)
            rect(s, 0, y, gut, GRID_ROW_H * k, p.accent_wash if row == self.cur_row else p.card)
            font.draw(s, _grouped(row + 1), (GRID_GUTTER - 10) * k, base, 12 * k, p.ink3, p.regular, RIGHT)
            y += GRID_ROW_H * k
            hline(s, 0, right, y, p.line)
            shown += 1
        line(s, gut, 0, gut, h, 1, p.line)
        # the scroll bar: a thin track, a thumb sized to the share of rows on screen
        var t = self.thumb(h / k, src)
        rect(s, right, head, GRID_BAR_W * k, h - head, p.card)
        rect(s, right + 3 * k, t[0] * k + 2 * k, (GRID_BAR_W - 6) * k, t[1] * k - 4 * k, p.ink3 if self.bar_drag else p.line_strong)


def _grouped(n: Int) -> String:
    """12345678 → "12,345,678" """
    var digits = String(n if n >= 0 else -n)
    var out = String("")
    var count = 0
    var cs = List[String]()
    for c in digits.codepoint_slices():
        cs.append(String(c))
    for i in range(len(cs) - 1, -1, -1):
        out = cs[i] + out
        count += 1
        if count % 3 == 0 and i > 0:
            out = "," + out
    return ("-" if n < 0 else "") + out
