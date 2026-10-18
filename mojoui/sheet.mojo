# mojoui.sheet: omxplorer's table, on the MX frame package (`from mxframe import …`): a package `Frame` (the shared
# columns, this session's edits, formula columns), what the package leaves to the app (each column's display format),
# and the GPU copy of the table when there is a GPU. It is a DataGrid's source (nulls show blank, edited cells get the
# corner mark) and it formats values for cells, totals, charts and pivots. Every aggregate goes through
# `Sheet.totals`: one `Query(frame).on_device(dt)…compute(AUTO)` (docs/mxframe-mojo-api.md section 5).
#
# A sheet can also be *streamed* (D-185): a Parquet file too big for memory, opened with the package's `scan_parquet`.
# Then the grid reads its rows a row group at a time (the last few decoded groups are kept), every aggregate is a
# `Query(scan)` on the CPU, a column's plain totals are kept (the file doesn't change), and nothing can be edited.
#
# The stand-in engine (mojoui.frame, frame_gpu) stays for MX Studio and the Workbook.

from std.memory import ArcPointer
from std.collections import Dict
from mxframe import (Frame as MxFrame, Table, SharedTable, DeviceTable, Query, Expr, col, sum, count, min_of, max_of,
                     AUTO as MX_AUTO, GPU as MX_GPU, CPU as MX_CPU, TEXT as MX_TEXT, DECIMAL as MX_DECIMAL, DATE as MX_DATE,
                     gpu_available, ParquetScan)
from mojoui.datagrid import GridSource
from mojoui.cellstyle import CellStyle, ALL_PARTS
from mojoui.numformat import (ColumnFormat, format_number, format_date, date_text, parse_decimal, decimal_text, AUTO, NUMBER, PERCENT,
                              CURRENCY)

# column kinds as the app reads them (the package's ColumnKind values)
comptime INT = 0
comptime DECIMAL = 1
comptime TEXT = 2
comptime DATE = 3
comptime BOOL = 4
comptime STYLE_COLS = 1 << 16  # a cell override's key: row * STYLE_COLS + column


@fieldwise_init
struct StyleStep(Copyable, Movable):
    """One part of a format change, as it was before (Undo puts it back): a column's style (row -1), a cell's override
    (`had`: there was one), or a column's number format."""

    var col: Int
    var row: Int
    var bits: Int
    var had: Bool
    var number: ColumnFormat  # (a number-format step: the format before; `row` is -2)


@fieldwise_init
struct StyleChange(Copyable, Movable):
    """One format change the user made (it may touch a column and many overrides at once); `edits` is how many of
    the table's own edits there were then, so Undo knows which came last."""

    var steps: List[StyleStep]
    var edits: Int


@fieldwise_init
struct Sums(Copyable, Movable):
    """One group-by: per group the sum of the value column, the rows, and the rows where the value isn't empty."""

    var sums: List[Int]
    var counts: List[Int]  # rows
    var present: List[Int]  # rows whose value is not null (averages divide by this)
    var milliseconds: Float64
    var on_gpu: Bool


comptime KEPT_GROUPS = 4  # decoded row groups a streamed sheet keeps at most (a 2^20-row group of 5 columns is 40 MB)
comptime KEPT_BYTES = 512 << 20  # ...and while they fit in this much (always at least the group on screen)
comptime READ_ONLY = "the file is streamed from disk (too big for memory), so it's read-only"


struct Pages(Movable):
    """A streamed sheet's decoded row groups (most recently used last) and each column's plain totals, behind an
    ArcPointer so the sheet's read-only methods (a grid draws through them) can fill them."""

    var starts: List[Int]  # the first row of each row group, then the row count
    var groups: List[Int]  # the row groups kept, least recently used first
    var tables: List[Table]
    var plain: List[Optional[Sums]]  # per column: its totals over every row, once asked
    var problem: String  # the last read that failed (a file changed or cut short since it was opened): shown, not hidden
    var last_gpu: Bool  # (any sheet) the last aggregate ran on the GPU

    def __init__(out self):
        self.starts = List[Int]()
        self.groups = List[Int]()
        self.tables = List[Table]()
        self.plain = List[Optional[Sums]]()
        self.problem = ""
        self.last_gpu = False

    def bytes(self, k: Int) -> Int:
        return self.tables[k].rows() * self.tables[k].columns() * 8

    def group_of(self, row: Int) -> Int:
        var lo = 0
        var hi = len(self.starts) - 2
        while lo < hi:
            var mid = (lo + hi + 1) // 2
            if self.starts[mid] <= row:
                lo = mid
            else:
                hi = mid - 1
        return lo

    def slot(mut self, g: Int, scan: ParquetScan) raises -> Int:
        """Where row group g's table is kept, decoding it (and letting the oldest go) when it isn't."""
        for k in range(len(self.groups)):
            if self.groups[k] == g:
                if k != len(self.groups) - 1:  # (now the most recently used)
                    var t = self.tables.pop(k)
                    _ = self.groups.pop(k)
                    self.tables.append(t^)
                    self.groups.append(g)
                return len(self.groups) - 1
        var cols = List[Int]()
        for c in range(scan.columns()):
            cols.append(c)
        var t = scan.read_group(g, cols)
        self.problem = ""  # (reads work again)
        var kept = t.rows() * t.columns() * 8
        for k in range(len(self.tables)):
            kept += self.bytes(k)
        while len(self.groups) > 0 and (len(self.groups) >= KEPT_GROUPS or kept > KEPT_BYTES):
            kept -= self.bytes(0)
            _ = self.tables.pop(0)
            _ = self.groups.pop(0)
        self.tables.append(t^)
        self.groups.append(g)
        return len(self.groups) - 1


def empty_table() raises -> Table:
    """A one-cell placeholder (a column "A" holding ""), what the app shows before a file is opened."""
    var t = Table.empty()
    var c = t.add_column("A", MX_TEXT)
    _ = t.add_word(c, "")
    t.append(c, 0)
    return t^


def blank_table(rows: Int = 20) raises -> Table:
    """A new blank sheet's table: Item (text), Amount (decimal, 2 places) and Date, `rows` empty-ish rows."""
    var t = Table.empty()
    var item = t.add_column("Item", MX_TEXT)
    _ = t.add_word(item, "")
    var amount = t.add_column("Amount", MX_DECIMAL, 2)
    var day = t.add_column("Date", MX_DATE)
    for _ in range(rows):
        t.append(item, 0)
        t.append(amount, 0)
        t.append(day, 20089)  # (2025-01-01)
    return t^


def placeholder_sheet() -> Sheet:
    """What the app holds before a file is opened (no GPU copy)."""
    try:
        return Sheet(empty_table().share(), False)
    except:
        return Sheet(Table.empty().share(), False)


struct Sheet(Movable, GridSource):
    var frame: MxFrame
    var formats: List[ColumnFormat]  # per column (stored, then formulas): how its values read; AUTO = by type
    var device: Optional[DeviceTable]  # the table on the GPU (None: no GPU, or the table didn't fit)
    var device_name: String
    var mode: Int  # CPU, GPU or AUTO (the default: the GPU from a million rows); tests force the GPU to compare it with the CPU
    var scan: Optional[ParquetScan]  # a streamed file (D-185): rows come from here, a row group at a time
    var pages: ArcPointer[Pages]
    var styles: List[Int]  # per column: its CellStyle's bits (mojoui.cellstyle); missing = plain
    var cell_styles: Dict[Int, Int]  # row * STYLE_COLS + column → the cell's own style, over its column's (sparse)
    var style_log: List[StyleChange]  # format changes Undo can take back, newest last
    var tab_names: List[String]  # the names a document's tabs were saved under (the sheet's, the Report's); empty: none

    def __init__(out self, table: SharedTable, use_gpu: Bool = True):
        self.frame = MxFrame(table)
        self.formats = List[ColumnFormat]()
        self.styles = List[Int]()
        self.cell_styles = Dict[Int, Int]()
        self.style_log = List[StyleChange]()
        self.tab_names = List[String]()
        self.device = None
        self.device_name = "CPU"
        self.mode = MX_AUTO
        self.scan = None
        self.pages = ArcPointer(Pages())
        if use_gpu and gpu_available():
            try:
                var dt = DeviceTable(table)
                self.device_name = dt.context().name()
                self.device = dt
            except:
                self.device = None

    def __init__(out self, scan: ParquetScan):
        """A streamed sheet over a Parquet file: its columns and dictionaries now, its rows when they're shown."""
        self.frame = MxFrame(scan.schema)
        self.formats = List[ColumnFormat]()
        self.styles = List[Int]()
        self.cell_styles = Dict[Int, Int]()
        self.style_log = List[StyleChange]()
        self.tab_names = List[String]()
        self.device = None
        self.device_name = "CPU"
        self.mode = MX_CPU  # (the package streams on the CPU)
        self.scan = scan.copy()
        var pages = Pages()
        var at = 0
        for g in range(scan.row_groups()):
            pages.starts.append(at)
            at += scan.group_rows(g)
        pages.starts.append(at)
        for _ in range(scan.columns()):
            pages.plain.append(None)
        self.pages = ArcPointer(pages^)

    def streamed(self) -> Bool:
        return Bool(self.scan)

    def last_device(self) -> String:
        """Where the last aggregate ran: the GPU's name, or "CPU"."""
        return self.device_name if self.pages[].last_gpu else "CPU"

    def read_problem(self) -> String:
        """Why the last rows read from a streamed file failed ("" when they didn't)."""
        return self.pages[].problem

    def release(mut self):
        """Gives the GPU copy back (the document closed or was replaced)."""
        if self.device:
            self.device.value().release()
        self.device = None

    def table(self) -> SharedTable:
        return self.frame.base

    # ---------- shape ----------

    def stored(self) -> Int:
        return self.frame.stored()

    def columns(self) -> Int:
        return self.frame.columns()

    def rows(self) -> Int:
        if self.scan:
            return self.scan.value().rows()
        return self.frame.rows()

    def alive(self, row: Int) -> Bool:
        if self.scan:
            return 0 <= row < self.rows()
        return self.frame.alive(row)

    def name(self, c: Int) -> String:
        return self.frame.name(c)

    def kind(self, c: Int) -> Int:
        return self.frame.kind(c).value

    def scale(self, c: Int) -> Int:
        return self.frame.scale(c)

    def index(self, name: String) -> Int:
        return self.frame.index(name)

    def edits(self) -> Int:
        return self.frame.edits

    def word_count(self, c: Int) -> Int:
        """A text column's values now (its dictionary and the words typed into it): its codes run 0 up to this.
        Streamed: the file's dictionary, built by the package on first use."""
        if not (c < self.stored() and self.kind(c) == TEXT):
            return 0
        if self.scan:
            try:
                return self.scan.value().word_count(c)
            except e:
                self.pages[].problem = String(e)
                return 0
        return self.frame.word_count(c)

    def text_of(self, c: Int, code: Int64) -> String:
        if self.scan:
            try:
                return self.scan.value().text_of(c, Int(code))
            except e:
                self.pages[].problem = String(e)
                return ""
        return self.frame.text_of(c, code)

    def code_of(self, c: Int, word: String) -> Int:
        if self.scan:
            try:
                return self.scan.value().code_of(c, word)
            except e:
                self.pages[].problem = String(e)
                return -1
        return self.frame.code_of(c, word)

    # ---------- values ----------

    def value(self, c: Int, row: Int) -> Int64:
        try:
            if self.scan:
                ref p = self.pages[]
                var g = p.group_of(row)
                var k = p.slot(g, self.scan.value())
                return p.tables[k].get(c, row - p.starts[g])
            return self.frame.get(c, row)
        except e:
            if self.scan:
                self.pages[].problem = String(e)
            return 0

    def is_null(self, c: Int, row: Int) -> Bool:
        try:
            if self.scan:
                ref p = self.pages[]
                var g = p.group_of(row)
                var k = p.slot(g, self.scan.value())
                return p.tables[k].is_null(c, row - p.starts[g])
            return self.frame.is_null(c, row)
        except e:
            if self.scan:
                self.pages[].problem = String(e)
            return False

    def edited(self, c: Int, row: Int) -> Bool:
        return c < self.stored() and not self.scan and self.frame.edited(c, row)

    # ---------- formats (per column; applied only to what's shown) ----------

    def format_of(self, c: Int) -> ColumnFormat:
        return self.formats[c].copy() if 0 <= c < len(self.formats) else ColumnFormat.auto()

    def set_format(mut self, c: Int, f: ColumnFormat):
        while len(self.formats) <= c:
            self.formats.append(ColumnFormat.auto())
        self.formats[c] = f.copy()

    def format_value(self, c: Int, v: Int64, total: Bool = False) -> String:
        """A value of column c (as stored, scaled) as the column's format shows it: cells, totals, pivots, charts.
        total: a sum or an average (a column without a format still gets thousands separators there)."""
        var kind = self.kind(c)
        var f = self.format_of(c)
        if total and f.is_auto() and (kind == INT or kind == DECIMAL):
            f = ColumnFormat(NUMBER, -1, True, False, "$")
        if kind == DATE:
            return date_text(v) if f.is_auto() else format_date(v, f)
        if kind == TEXT:
            return String(v)
        if kind == BOOL:
            return "true" if v != 0 else "false"
        if f.is_auto():
            return decimal_text(v, self.scale(c)) if kind == DECIMAL else String(v)
        return format_number(v, self.scale(c) if kind == DECIMAL else 0, f)

    def plain_text(self, c: Int, row: Int) -> String:
        """The value as typed, without its column's format ($, separators, %): what an editor starts from."""
        if self.is_null(c, row):
            return ""
        var v = self.value(c, row)
        var kind = self.kind(c)
        if kind == TEXT and c < self.stored():
            return self.text_of(c, v)
        if kind == DATE:
            return date_text(v)
        if kind == DECIMAL:
            return decimal_text(v, self.scale(c))
        if kind == BOOL:
            return "true" if v != 0 else "false"
        return String(v)

    def format_average(self, c: Int, total: Int, count: Int) -> String:
        """total ÷ count of column c in its format, rounded once (half away from zero), with two more places
        than a whole-number column has (qty's 4.8 reads 4.80) and two more for a percent (36.42%)."""
        var scale = self.scale(c) if self.kind(c) == DECIMAL else 0
        var f = self.format_of(c)
        if f.is_auto():
            f = ColumnFormat(NUMBER, -1, True, False, "$")
        if f.decimals < 0:
            f.decimals = scale if scale > 0 else 2
        var places = f.decimals + (2 if f.style == PERCENT else 0)
        var num = total * Int(10 ** places)
        var den = max(count, 1) * Int(10 ** scale)
        var q = (abs(num) + den // 2) // den
        return format_number(Int64(q if num >= 0 else -q), places, f)

    def display(self, c: Int, row: Int) -> String:
        """What the cell shows: blank for a null, the column's format for a number or date."""
        if self.is_null(c, row):
            return ""
        var v = self.value(c, row)
        var kind = self.kind(c)
        if kind == TEXT and c < self.stored():
            return self.text_of(c, v)
        if not self.format_of(c).is_auto() or kind == BOOL:
            return self.format_value(c, v)
        if kind == DATE:
            return date_text(v)
        if kind == DECIMAL:
            return decimal_text(v, self.scale(c))
        return String(v)

    # ---------- edits ----------

    def set_text(mut self, c: Int, row: Int, text: String) raises:
        """A typed value: empty makes the cell empty (null); numbers read what the formats print back
        ("$1,234.50", "(1,234)", "36.4%"); the other kinds as the package parses them."""
        if self.scan:
            raise Error(READ_ONLY)
        var kind = self.kind(c)
        if String(text.strip()) == "" or (c >= self.stored()):
            self.frame.set_text(c, row, text)
        elif kind == INT:
            self.frame.set(c, row, parse_decimal(text, 0))
        elif kind == DECIMAL:
            self.frame.set(c, row, parse_decimal(text, self.scale(c)))
        else:
            self.frame.set_text(c, row, text)

    def append(mut self) raises -> Int:
        """A new empty row; returns its number."""
        if self.scan:
            raise Error(READ_ONLY)
        return self.frame.append(List[String]())

    def undo(mut self) -> Bool:
        """Takes back the last change: a format change (styles, number formats) or an edit to the table, whichever
        came last. A streamed sheet's formats can be undone; its table has no edits."""
        var edits = 0 if self.scan else len(self.frame.log)
        if len(self.style_log) > 0 and self.style_log[len(self.style_log) - 1].edits >= edits:
            var change = self.style_log.pop()
            var k = len(change.steps) - 1
            while k >= 0:
                ref s = change.steps[k]
                if s.row == -2:
                    self.set_format(s.col, s.number)
                elif s.row < 0:
                    self.set_column_style(s.col, s.bits)
                elif s.had:
                    self.cell_styles[s.row * STYLE_COLS + s.col] = s.bits
                else:
                    _ = self.cell_styles.pop(s.row * STYLE_COLS + s.col, 0)
                k -= 1
            return True
        return False if self.scan else self.frame.undo()

    # ---------- cell styles (mojoui.cellstyle: a column's, and sparse cell overrides) ----------

    def column_style(self, c: Int) -> CellStyle:
        return CellStyle(self.styles[c]) if 0 <= c < len(self.styles) else CellStyle()

    def style_of(self, c: Int, row: Int) -> CellStyle:
        """How cell (c, row) looks: its own style if it has one, else its column's (row -1: the column's)."""
        if row >= 0 and len(self.cell_styles) > 0:
            var own = self.cell_styles.get(row * STYLE_COLS + c)
            if own:
                return CellStyle(own.value())
        return self.column_style(c)

    def set_column_style(mut self, c: Int, bits: Int):
        while len(self.styles) <= c:
            self.styles.append(0)
        self.styles[c] = bits

    def set_cell_style(mut self, c: Int, row: Int, bits: Int):
        """A cell's own style, as read from a file (not logged)."""
        self.cell_styles[row * STYLE_COLS + c] = bits

    def styled_cells(self) -> List[Tuple[Int, Int, Int]]:
        """Every cell override as (column, row, bits), in row then column order (a file writes them)."""
        var out = List[Tuple[Int, Int, Int]]()
        var keys = List[Int]()
        for e in self.cell_styles.items():
            keys.append(e.key)
        sort(keys)
        for key in keys:
            out.append((key % STYLE_COLS, key // STYLE_COLS, self.cell_styles.get(key).value()))
        return out^

    def restyle(mut self, c: Int, row: Int, mask: Int, value: Int):
        """Sets the parts of the style under `mask` (mojoui.cellstyle's bits) to `value`'s: on cell (c, row), or with
        row -1 on the whole column, which sets the same parts of every cell override in it too, as a spreadsheet
        does (an override left equal to its column's goes). Undo takes it back in one step."""
        if not (0 <= c < self.columns()):
            return
        var steps = List[StyleStep]()
        if row >= 0:
            var key = row * STYLE_COLS + c
            var own = self.cell_styles.get(key)
            steps.append(StyleStep(c, row, own.value() if own else 0, Bool(own), ColumnFormat.auto()))
            var bits = self.style_of(c, row).set(mask, value).bits
            if bits == self.column_style(c).bits:
                _ = self.cell_styles.pop(key, 0)
            else:
                self.cell_styles[key] = bits
        else:
            steps.append(StyleStep(c, -1, self.column_style(c).bits, False, ColumnFormat.auto()))
            self.set_column_style(c, self.column_style(c).set(mask, value).bits)
            var mine = List[Tuple[Int, Int]]()
            for e in self.cell_styles.items():
                if e.key % STYLE_COLS == c:
                    mine.append((e.key, e.value))
            var column = self.column_style(c).bits
            for m in mine:
                var key = m[0]
                var before = m[1]
                steps.append(StyleStep(c, key // STYLE_COLS, before, True, ColumnFormat.auto()))
                var bits = CellStyle(before).set(mask, value).bits
                if bits == column:
                    _ = self.cell_styles.pop(key, 0)
                else:
                    self.cell_styles[key] = bits
        self.style_log.append(StyleChange(steps^, 0 if self.scan else len(self.frame.log)))

    def clear_style(mut self, c: Int, row: Int):
        """Clear formatting: the cell (or with row -1 the column and every cell in it) back to plain, its number
        format too when it's the whole column."""
        if row < 0:
            self.change_format(c, ColumnFormat.auto())
            var number = self.style_log.pop()  # (one Undo step for both)
            self.restyle(c, -1, ALL_PARTS, 0)
            self.style_log[len(self.style_log) - 1].steps.insert(0, number.steps[0].copy())
        else:
            self.restyle(c, row, ALL_PARTS, 0)

    def change_format(mut self, c: Int, f: ColumnFormat):
        """A column's number format, changed by the user (Undo takes it back; set_format doesn't log)."""
        var steps = List[StyleStep]()
        steps.append(StyleStep(c, -2, 0, False, self.format_of(c)))
        self.set_format(c, f)
        self.style_log.append(StyleChange(steps^, 0 if self.scan else len(self.frame.log)))

    def formula(mut self, text: String) raises -> Int:
        if self.scan:
            raise Error(READ_ONLY)
        return self.frame.formula(text)

    def permutation(self, c: Int, descending: Bool = False) raises -> List[Int]:
        if self.scan:
            raise Error(READ_ONLY)
        return self.frame.permutation(c, descending)

    # ---------- aggregates ----------

    def query(self) raises -> Query:
        """A query over this session's view of the table, on the GPU copy when there is one; over the file, a row
        group at a time, when the sheet is streamed."""
        if self.scan:
            return Query(self.scan.value())
        var q = Query(self.frame)
        if self.device:
            q = q^.on_device(self.device.value())
        return q^

    def totals(self, value: Int, key: Optional[Expr] = None, groups: Int = 1, filter: Optional[Expr] = None) raises -> Sums:
        """Sum of column `value` (a formula column too), the rows and the non-empty rows, per group of `key`
        (0 … groups-1; none: one group), over the rows `filter` keeps. The session's edits are included.
        A streamed sheet keeps each column's plain totals (no key, no filter): the file doesn't change."""
        var plain = not key and not filter and Bool(self.scan) and value < len(self.pages[].plain)
        if plain and self.pages[].plain[value]:
            return self.pages[].plain[value].value().copy()
        var q = self.query()
        if filter:
            q = q^.where(filter.value().copy())
        if key:
            q = q^.group_by(key.value().copy(), groups)
        var v = col(self.name(value))
        q = q^.agg(sum(v), count(), count(v))
        var r = q^.compute(self.mode)
        var sums = Sums(r.values(0), r.counts.copy(), r.values(2), r.milliseconds, r.device == MX_GPU)
        self.pages[].last_gpu = sums.on_gpu
        if plain:
            self.pages[].plain[value] = sums.copy()
        return sums^

    def span(self, c: Int) raises -> Tuple[Int64, Int64, Bool]:
        """The smallest and largest value of column c over its non-empty rows (False: there are none)."""
        var v = col(self.name(c))
        var r = self.query().agg(min_of(v), max_of(v)).compute(self.mode)
        if not r.present(0, 0):
            return (Int64(0), Int64(0), False)
        return (Int64(r.values(0)[0]), Int64(r.values(1)[0]), True)

    def where_is(self, c: Int, code: Int) -> Expr:
        """The filter "column c is the text with this code"."""
        return col(self.name(c)) == Expr(code)

    # ---------- as a DataGrid's source (mojoui.datagrid) ----------

    def grid_rows(self) -> Int:
        return self.rows()

    def grid_alive(self, row: Int) -> Bool:
        return self.alive(row)

    def grid_columns(self) -> Int:
        return self.columns()

    def grid_name(self, c: Int) -> String:
        return self.name(c)

    def grid_numeric(self, c: Int) -> Bool:
        return self.kind(c) == INT or self.kind(c) == DECIMAL

    def grid_editable(self, c: Int) -> Bool:
        return c < self.stored() and not self.scan

    def grid_formula(self, c: Int) -> Bool:
        return c >= self.stored()

    def grid_text(self, c: Int, row: Int) -> String:
        return self.display(c, row)

    def grid_badge(self, c: Int) -> String:
        if c >= self.stored():
            return "ƒx"
        var kind = self.kind(c)
        if kind == TEXT:
            return "Aa"
        if kind == DATE:
            return "date"
        if kind == BOOL:
            return "bool"
        if kind == INT:
            return "#"
        var f = self.format_of(c)
        return (f.symbol if f.symbol != "" else "$") if f.style == CURRENCY else ("%" if f.style == PERCENT else "0.0")

    def grid_edited(self, c: Int, row: Int) -> Bool:
        return self.edited(c, row)

    def grid_style(self, c: Int, row: Int) -> CellStyle:
        return self.style_of(c, row)

    def grid_type_width(self, c: Int) -> Float64:
        var kind = self.kind(c)
        if kind == DATE:
            return 104
        if kind == TEXT and c < self.stored() and self.scan:
            return 118  # (a streamed file's words aren't read just to size a column)
        if kind == TEXT and c < self.stored():
            var longest = 0
            for w in self.frame.base.dictionary(c):
                longest = max(longest, w.byte_length())
            return 190 if longest > 20 else 118  # (long names, such as products, get a wider column)
        if kind == DECIMAL:
            return 96
        if kind == BOOL:
            return 72
        return 72
