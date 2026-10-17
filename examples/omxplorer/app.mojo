# omxplorer: open your data, shape it, report on it, on your GPU. A Numbers-style data app built only from
# omxapp (mojoui) components, following the Stitch "classic" designs (docs/design/mxstudio-app/):
#   Start  → choose a file (or the sample, or a blank table)
#   Import → the columns as read, with their types and shapes, before the table exists
#   Sheet  → toolbar, sheet tabs, formula bar, the table, the format inspector, the status bar

from mojoui.view import (View, Text, Button, FilePicker, TextField, Canvas, Board, VStack, HStack, Card, Spacer, Divider,
                         Dropdown, Segmented, Toggle, Tabs, Grid, HEADLINE, CAPTION, TITLE, PROMINENT, SUBTLE, START, CENTER, END,
                         BETWEEN, STRETCH, OMARCHY, CARD, CARD_WARN, TONE_ACCENT, TONE_GOOD, TONE_WARN, NO_MSG, TOOL)
from mojoui.app import App, Event
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.charts import grouped, fixed
from mojoui.datagrid import (DataGrid, GRID_SELECTED, GRID_COLUMN, GRID_EDIT, GRID_READ_ONLY, GRID_REDRAW, GRID_FITTED, GRID_RESIZED,
                             GRID_TYPED, GRID_CLEAR, GRID_CANCEL, GRID_COMMIT)
from mojoui.frame import Frame, Column, Columns, Range, share, decimal_text, date_text, INT, DECIMAL, TEXT, DATE
from mojoui.frame_gpu import GpuFrame, group_sum
from mojoui.shared import keep, at, environment, make_dir
from mojoui.csvio import read_csv, CsvImport, CsvColumn, kind_name
from mojoui.omxfile import save_omx, open_omx
from mojoui.numformat import (ColumnFormat, AUTO, NUMBER, CURRENCY, PERCENT, COMPACT, DATE_LONG, DATE_MONTH, DATE_ISO,
                              NUMBER_STYLES, DATE_STYLES)
from mojoui.inspector import Inspector, Section, Row, Stepper
from mojoui.sheetchrome import Tool, Toolbar, FormulaBar, StatusBar
from mojoui.orders import order_columns
from mojoui.orders_ops import col_program, histogram

# screens
comptime START_SCREEN = 0
comptime IMPORT = 1
comptime SHEET = 2

# messages
comptime PICK = 1  # a FilePicker returned a path (event.text)
comptime SAMPLE = 2
comptime BLANK = 3
comptime CREATE = 4  # Import → the sheet
comptime BACK = 5
comptime GRID = 6  # the table's canvas
comptime CELL_COMMIT = 7
comptime CELL_CANCEL = 8
comptime FX_COMMIT = 9  # the formula bar's Enter
comptime INSP_TAB = 10
comptime FORMAT = 11
comptime DECIMALS_LESS = 12
comptime DECIMALS_MORE = 13
comptime THOUSANDS = 14
comptime NEGATIVES = 15
comptime SYMBOL = 16
comptime ADD_ROW = 17
comptime NEW_FORMULA = 18
comptime FORMULA_SUBMIT = 19
comptime SORT = 20
comptime UNDO = 21
comptime TOGGLE_INSPECTOR = 22
comptime SAVE = 24
comptime IMPORT_COLUMN = 23  # Import: the column whose details show
comptime RECENT = 40  # + index: open a recent file

comptime W = 1440  # the window (Stitch's artboards; the web check's viewport)
comptime INSPECTOR_W = 300
comptime GRID_H = 676
comptime SYMBOLS: List[String] = ["$", "€", "£", "₹"]
comptime NEGATIVE_STYLES: List[String] = ["−1,234", "(1,234)"]


struct Main(App):
    var screen: Int
    var has_table: Bool
    var frame: Frame
    var gf_addr: Int
    var imp: CsvImport
    var source: String  # what the table came from (a path, "sample", "blank")
    var name: String  # the table's name (the file's name without .csv)
    var grid: DataGrid
    var preview: DataGrid  # Import: the first rows, read-only
    var font: Font
    var pal: Palette
    var import_col: Int
    var insp_tab: Int  # 0 Table, 1 Cell
    var inspector_open: Bool
    var formula_open: Bool  # the formula bar adds a column instead of editing a cell
    var edit_text: String
    var message: String
    var sum: Int  # the selected column's total and count (GPU, with the session's edits)
    var count: Int
    var milliseconds: Float64
    var recent: List[String]
    var version: Int

    def __init__(out self):
        self.screen = START_SCREEN
        self.has_table = False
        var empty = Columns()
        var c = Column("A", TEXT)
        c.dictionary.append("")
        c.values.append(0)
        empty.add(c^)
        self.frame = Frame(share(empty^))
        self.gf_addr = 0
        self.imp = CsvImport("", 0, List[CsvColumn](), List[String](), 0, 0)
        self.source = ""
        self.name = ""
        self.grid = DataGrid()
        self.preview = DataGrid()
        self.font = Font()
        self.pal = Palette.omarchy()
        self.import_col = 0
        self.insp_tab = 1
        self.inspector_open = True
        self.formula_open = False
        self.edit_text = ""
        self.message = ""
        self.sum = 0
        self.count = 0
        self.milliseconds = 0
        self.recent = read_recent()
        self.version = 1
        var auto_open = environment("OMX_OPEN")  # a file to open straight away (the launcher's argument)
        if auto_open != "":
            self.open_path(auto_open)

    @staticmethod
    def init_shared():
        pass

    def title(self) -> String:
        return "omxplorer" + (" · " + self.name if self.name != "" else "")

    def window_size(self) -> Tuple[Int, Int]:
        return (W, 900)

    def design(self) -> Int:
        return OMARCHY

    def gf(self) -> Pointer[GpuFrame, MutUntrackedOrigin]:
        return at[GpuFrame](self.gf_addr)

    # ---------- data in ----------

    def open_path(mut self, path: String):
        """A CSV file → the Import step (its columns as read); an .omx document → straight to its sheet."""
        if path.endswith(".omx"):
            try:
                self.frame = open_omx(path)
                self.gf_addr = keep(GpuFrame(self.frame.base_addr))
                self.source = path
                self.name = file_stem(path)
                self.has_table = True
                remember(path, self.recent)
                self.to_sheet()
                self.message = "Opened " + file_name(path) + " · " + grouped(self.frame.rows()) + " rows"
            except e:
                self.message = String(e)
            self.version += 1
            return
        try:
            self.imp = read_csv(path)
            self.frame = Frame(self.imp.base_addr)
            self.gf_addr = keep(GpuFrame(self.imp.base_addr))
            self.source = path
            self.name = file_stem(path)
            self.has_table = True
            self.preview = DataGrid()
            self.preview.prepare(self.frame, self.font, self.pal)
            for c in range(self.frame.stored()):
                self.preview.histograms.append(self.shape_of(c))
            self.import_col = 0
            self.screen = IMPORT
            self.message = ""
            remember(path, self.recent)
        except e:
            self.message = String(e)
        self.version += 1

    def shape_of(self, c: Int) -> List[Float64]:
        """A column's distribution over every row (the GPU), for the header's small histogram."""
        ref vals = self.frame.base()[].cols[c].values
        if len(vals) == 0:
            return List[Float64]()
        var lo = vals[0]
        var hi = lo
        for v in vals:
            lo = min(lo, v)
            hi = max(hi, v)
        return histogram(self.frame, self.gf()[], c, lo, hi)

    def open_sample(mut self):
        var rows = 1_000_000
        var asked = environment("OMX_ROWS")
        if asked != "":
            try:
                rows = max(Int(asked), 1000)
            except:
                pass
        var addr = share(order_columns(rows))
        self.frame = Frame(addr)
        self.gf_addr = keep(GpuFrame(addr))
        self.source = "sample"
        self.name = "orders"
        self.has_table = True
        self.to_sheet()

    def open_blank(mut self):
        var cols = Columns()
        var names: List[String] = ["Item", "Amount", "Date"]
        var kinds: List[Int] = [TEXT, DECIMAL, DATE]
        for k in range(3):
            var c = Column(names[k], kinds[k])
            if kinds[k] == TEXT:
                c.dictionary.append("")
            for _ in range(20):
                c.values.append(Int64(20089 if kinds[k] == DATE else 0))
            cols.add(c^)
        var addr = share(cols^)
        self.frame = Frame(addr)
        self.gf_addr = keep(GpuFrame(addr))
        self.source = "blank"
        self.name = "Table 1"
        self.has_table = True
        self.to_sheet()

    def to_sheet(mut self):
        self.screen = SHEET
        self.grid = DataGrid()
        self.grid.prepare(self.frame, self.font, self.pal)
        for c in range(self.frame.stored()):
            if self.frame.kind(c) == TEXT:
                self.grid.fit(c, self.frame, self.font, self.pal)
        self.grid.select(0, min(self.first_number(), self.frame.columns() - 1))
        self.select_cell(self.grid.cur_row, self.grid.cur_col)
        self.message = ("Imported " + grouped(self.frame.rows()) + " rows from " + self.name + ".csv") if self.source != "sample" and self.source != "blank" else ""
        self.version += 1

    def first_number(self) -> Int:
        for c in range(self.frame.columns()):
            if self.frame.kind(c) == DECIMAL:
                return c
        return 0

    # ---------- the selection and its totals ----------

    def select_cell(mut self, row: Int, col: Int):
        self.edit_text = self.frame.grid_text(col, row) if row >= 0 and col >= 0 else ""
        if row >= 0 and col >= 0 and self.frame.kind(col) != TEXT:
            self.edit_text = raw_text(self.frame, col, row)
        self.totals()
        self.version += 1

    def totals(mut self):
        """The selected column's sum and count over every row, on the GPU (edits included)."""
        var col = self.grid.cur_col
        if col < 0 or not self.has_table or self.frame.kind(col) == TEXT:
            self.sum = 0
            self.count = self.frame.rows()
            return
        var key = List[Int64]()
        key.append(0)  # OP_CONST 0: one group
        key.append(0)
        var r = group_sum(self.frame, self.gf()[], key, self.frame.flatten(col_program(col)), List[Range](), 1)  # (a formula: its stored-column steps)
        self.sum = r.sums[0]
        self.count = r.counts[0]
        self.milliseconds = r.milliseconds

    def column_format(self) -> ColumnFormat:
        return self.frame.format_of(self.grid.cur_col) if self.grid.cur_col >= 0 else ColumnFormat.auto()

    def set_format(mut self, var f: ColumnFormat):
        if self.grid.cur_col < 0:
            return
        self.frame.set_format(self.grid.cur_col, f)
        self.grid.redraw()
        if self.grid.cur_row >= 0:
            self.select_cell(self.grid.cur_row, self.grid.cur_col)
        self.message = self.frame.name(self.grid.cur_col) + ": " + f.summary() + " (the whole column)"
        self.version += 1

    # ---------- events ----------

    def write_cell(mut self, text: String):
        if self.grid.editing and self.grid.cur_row >= 0 and self.grid.cur_col >= 0:
            try:
                var col = self.grid.cur_col
                var row = self.grid.cur_row
                var before = self.frame.display(col, row)
                self.frame.set_text(col, row, text)
                self.message = self.frame.name(col) + " on row " + grouped(row + 1) + ": " + before + " → " + self.frame.display(col, row)
                self.grid.committed(self.frame)
                self.select_cell(self.grid.cur_row, self.grid.cur_col)
            except e:
                self.edit_text = text
                self.message = String(e) + " (fix it and press Enter)"
        self.version += 1

    def update(mut self, event: Event):
        var m = event.message
        if m != CELL_COMMIT and m != CELL_CANCEL and m != GRID and self.grid.editing:
            self.grid.cancel_edit()
            self.version += 1
        if m == PICK or (m >= RECENT and m < RECENT + 10):
            var path = event.text if m == PICK else (self.recent[m - RECENT] if m - RECENT < len(self.recent) else String(""))
            if path != "":
                self.open_path(path)
        elif m == SAMPLE:
            self.open_sample()
        elif m == BLANK:
            self.open_blank()
        elif m == CREATE:
            self.to_sheet()
        elif m == BACK:
            self.screen = START_SCREEN
            self.version += 1
        elif m == IMPORT_COLUMN:
            self.import_col = event.number
            self.version += 1
        elif m == GRID:
            var action = self.grid.handle(event, self.frame, self.font, self.pal)
            if action == GRID_SELECTED or action == GRID_EDIT or action == GRID_READ_ONLY or action == GRID_COLUMN:
                self.select_cell(self.grid.cur_row, self.grid.cur_col)
                if action == GRID_EDIT:
                    self.message = "Editing " + self.frame.name(self.grid.cur_col) + " on row " + grouped(self.grid.cur_row + 1) + ": Enter writes it, Escape cancels"
                elif action == GRID_READ_ONLY:
                    self.message = self.frame.name(self.grid.cur_col) + " is a formula: edit the columns it uses"
                elif action == GRID_COLUMN:
                    self.message = "Column " + self.frame.name(self.grid.cur_col) + ": format it in the inspector, or Sort"
            elif action == GRID_TYPED:
                self.select_cell(self.grid.cur_row, self.grid.cur_col)
                self.edit_text = self.grid.typed
            elif action == GRID_CANCEL:
                self.select_cell(self.grid.cur_row, self.grid.cur_col)
                self.message = "Edit cancelled"
            elif action == GRID_COMMIT:
                var typed = String(self.grid.typed)
                self.write_cell(typed)
            elif action == GRID_CLEAR:
                try:
                    self.frame.set_text(self.grid.cur_col, self.grid.cur_row, "")
                    self.select_cell(self.grid.cur_row, self.grid.cur_col)
                except:
                    self.message = self.frame.name(self.grid.cur_col) + " can't be empty yet: type a value"
            if action != 0:
                self.version += 1
        elif m == CELL_COMMIT or m == FX_COMMIT:
            if m == FX_COMMIT and not self.grid.editing:
                self.grid.editing = True  # (the formula bar edits the selected cell)
            self.write_cell(event.text)
        elif m == CELL_CANCEL:
            self.grid.cancel_edit()
            self.select_cell(self.grid.cur_row, self.grid.cur_col)
            self.message = "Edit cancelled"
        elif m == INSP_TAB:
            self.insp_tab = event.number
            self.version += 1
        elif m == TOGGLE_INSPECTOR:
            self.inspector_open = not self.inspector_open
            self.version += 1
        elif m == FORMAT:
            var f = self.column_format()
            var kind = self.frame.kind(self.grid.cur_col) if self.grid.cur_col >= 0 else TEXT
            if kind == DATE:
                f.style = AUTO if event.number == 0 else DATE_LONG + event.number - 1
            else:
                f.style = event.number
                if f.style == CURRENCY and f.decimals < 0:
                    f.decimals = 2
                if f.style == PERCENT and f.decimals < 0:
                    f.decimals = 1
            self.set_format(f^)
        elif m == DECIMALS_LESS or m == DECIMALS_MORE:
            var f = self.column_format()
            if f.style == AUTO:
                f.style = NUMBER
            var now = f.decimals if f.decimals >= 0 else (self.frame.scale(self.grid.cur_col) if self.frame.kind(self.grid.cur_col) == DECIMAL else 0)
            f.decimals = max(0, min(6, now + (1 if m == DECIMALS_MORE else -1)))
            self.set_format(f^)
        elif m == THOUSANDS:
            var f = self.column_format()
            if f.style == AUTO:
                f.style = NUMBER
            f.thousands = event.number == 1
            self.set_format(f^)
        elif m == NEGATIVES:
            var f = self.column_format()
            if f.style == AUTO:
                f.style = NUMBER
            f.parens = event.number == 1
            self.set_format(f^)
        elif m == SYMBOL:
            var f = self.column_format()
            f.style = CURRENCY
            f.symbol = materialize[SYMBOLS]()[event.number]
            if f.decimals < 0:
                f.decimals = 2
            self.set_format(f^)
        elif m == ADD_ROW:
            try:
                var row = self.frame.append(List[String]())
                self.grid.select(row, max(self.grid.cur_col, 0))
                self.grid.keep_in_view(row, max(self.grid.cur_col, 0), self.frame)
                self.select_cell(row, max(self.grid.cur_col, 0))
                self.message = "Row " + grouped(row + 1) + " added: type to fill it"
            except e:
                self.message = String(e)
            self.version += 1
        elif m == NEW_FORMULA:
            self.formula_open = not self.formula_open
            self.version += 1
        elif m == FORMULA_SUBMIT:
            try:
                var c = self.frame.formula(event.text)
                self.grid.min_widths = List[Float64]()
                self.grid.prepare(self.frame, self.font, self.pal)
                self.grid.select(max(self.grid.cur_row, 0), c)
                self.grid.reveal_cell(max(self.grid.cur_row, 0), c, self.frame)
                self.select_cell(self.grid.cur_row, c)
                self.formula_open = False
                self.message = "New column " + self.frame.name(c) + " = " + event.text
            except e:
                self.message = String(e)
            self.version += 1
        elif m == SORT:
            var col = self.grid.cur_col
            if col >= 0:
                var desc = (not self.grid.sort_desc) if self.grid.sort_col == col else self.frame.kind(col) != TEXT
                self.grid.set_order(self.frame.permutation(col, desc), col, desc)
                self.message = "Sorted by " + self.frame.name(col) + (" (largest first)" if desc else "")
            self.version += 1
        elif m == SAVE:
            var folder = environment("OMX_DOCUMENTS", environment("HOME", ".") + "/Documents/omxplorer")
            make_dir(folder)
            var path = folder + "/" + self.name + ".omx"
            try:
                save_omx(path, self.frame)
                self.source = path
                remember(path, self.recent)
                self.message = "Saved " + path
            except e:
                self.message = "Couldn't save: " + String(e)
            self.version += 1
        elif m == UNDO:
            if self.frame.undo():
                self.grid.redraw()
                self.select_cell(self.grid.cur_row, self.grid.cur_col)
                self.message = "Undone"
            else:
                self.message = "Nothing to undo"
            self.version += 1

    # ---------- drawing ----------

    def draw(mut self, canvas: Int, mut surface: Surface):
        if canvas == 0:
            self.grid.draw(surface, self.frame, self.font, self.pal)
        elif canvas == 1:
            self.preview.draw(surface, self.frame, self.font, self.pal)

    # ---------- screens ----------

    def view(self) -> View:
        if self.screen == IMPORT:
            return self.import_screen()
        if self.screen == SHEET:
            return self.sheet_screen()
        return self.start_screen()

    def gpu_chip(self) -> String:
        if self.gf_addr != 0 and self.gf()[].on_gpu():
            return "● " + self.gf()[].device_name() + " · ready"
        return "● GPU ready" if self.gf_addr == 0 else "● CPU"

    def start_screen(self) -> View:
        var tiles = HStack(
            Card(Text("Blank sheet", HEADLINE), Text("An empty table to type into", CAPTION), Spacer(),
                 Button("New blank sheet", BLANK, icon="grid"), spacing=8).width(316).height(170),
            Card(Text("Import a file", HEADLINE), Text("CSV now · Parquet, Excel, JSON next", CAPTION), Spacer(),
                 FilePicker("Choose a file…", PICK, icon="import", accept=".csv,.tsv,.txt,.omx"), spacing=8).width(316).height(170),
            Card(Text("Connect a database", HEADLINE), Text("Postgres · DuckDB · SQLite (with MX frame)", CAPTION), Spacer(),
                 Text("Coming next", CAPTION), spacing=8).width(316).height(170),
            Card(Text("Sample · 1M orders", HEADLINE), Text("A year of orders with a story in them", CAPTION), Spacer(),
                 Button("Open the sample", SAMPLE, icon="sample"), spacing=8).width(316).height(170),
            spacing=16,
        )
        var drop = Card(
            Text("Drop a CSV file here, or choose one", HEADLINE),
            Text("It opens as a table you can sort, format, add formulas to and report on, on your GPU.", CAPTION),
            FilePicker("Choose a CSV file", PICK, style=PROMINENT, icon="import", accept=".csv,.tsv,.txt,.omx"),
            spacing=12,
        ).fill().height(200).align(CENTER).justify(CENTER)
        var recent = List[View]()
        recent.append(HStack(Text("RECENT", CAPTION), Spacer()).fill())
        if len(self.recent) == 0:
            recent.append(HStack(Text("Files you open show up here.", CAPTION), Spacer()).fill())
        for k in range(min(len(self.recent), 6)):
            recent.append(HStack(Text(file_name(self.recent[k])), Text(self.recent[k], CAPTION), Spacer(),
                                 Button("Open", RECENT + k, SUBTLE), spacing=12).fill().align(CENTER))
        var body = VStack(
            HStack(Text("omxplorer", TITLE).tone(TONE_ACCENT), Text("open data, shape it, report on it, on your GPU", CAPTION),
                   Spacer(), Text(self.gpu_chip(), CAPTION).tone(TONE_GOOD), spacing=14).fill().align(CENTER),
            HStack(Text("START", CAPTION), Spacer()).fill(),
            tiles,
            drop,
            Card(VStack(recent^, spacing=8).fill(), spacing=8).fill(),
            Text(self.message, CAPTION).tone(TONE_WARN) if self.message != "" else Spacer(),
            spacing=18,
        ).padding(28, 48).fill()
        return VStack(body, Spacer(), StatusBar(["Choose a file, drop one on the button, or open the sample"], "omxplorer · omxapp"), spacing=0).fill().grow()

    def import_screen(self) -> View:
        var cols = List[View]()
        var heads: List[String] = ["COLUMN", "TYPE", "EMPTY", "VALUES", "FIRST ROWS"]
        for h in heads:
            cols.append(Text(h, CAPTION))
        for k in range(len(self.imp.columns)):
            ref c = self.imp.columns[k]
            var first = String("")
            for s in range(min(3, len(c.sample))):
                first += ("  ·  " if s > 0 else "") + c.sample[s]
            cols.append(Text(c.name))
            cols.append(Text(kind_name(c.kind), CAPTION).tone(TONE_ACCENT))
            cols.append(Text(grouped(c.empty), CAPTION).tone(TONE_WARN if c.empty > 0 else 0))
            cols.append(Text(grouped(c.distinct) if c.kind == TEXT else "—", CAPTION))
            cols.append(Text(first, CAPTION))
        var skipped = String("")
        if len(self.imp.skipped) > 0:
            skipped = String(len(self.imp.skipped)) + " more columns aren't read yet (16 is the limit until MX frame)"
        var dialog = Card(
            HStack(VStack(Text("Import " + file_name(self.imp.path), HEADLINE),
                          Text(grouped(self.imp.rows) + " rows · " + String(len(self.imp.columns)) + " columns · read in "
                               + fixed(self.imp.seconds, 2) + " s", CAPTION).tone(TONE_GOOD), spacing=2).align(START),
                   Spacer(), Text("1 File  ›  2 Columns  ›  3 Table", CAPTION), spacing=12).fill().align(CENTER),
            Canvas(1, self.version + self.preview.version, on_gesture=NO_MSG).fill().height(330),
            Grid(cols^, 5, spacing=6).align(START),
            Text(skipped, CAPTION).tone(TONE_WARN) if skipped != "" else Spacer(),
            HStack(Button("Back", BACK), Spacer(), Button("Create table", CREATE, style=PROMINENT, icon="table"),
                   spacing=10).fill(),
            spacing=12,
        ).fill()
        return VStack(dialog, spacing=0).padding(24, 48).fill().grow()

    def toolbar(self) -> View:
        var left: List[Tool] = [Tool("Save", "save", SAVE, False), Tool("Undo", "undo", UNDO, False)]
        var middle: List[Tool] = [Tool("Add row", "row-plus", ADD_ROW, False), Tool("Formula", "formula", NEW_FORMULA, self.formula_open),
                                  Tool("Sort", "sort", SORT, self.grid.sort_col >= 0)]
        var right: List[Tool] = [Tool("Format", "format", TOGGLE_INSPECTOR, self.inspector_open)]
        var extra = List[View]()
        extra.append(FilePicker("Open", PICK, style=TOOL, icon="import", accept=".csv,.tsv,.txt,.omx"))
        return Toolbar(left, middle, right, extra)

    def inspector(self) -> View:
        var tabs: List[String] = ["Table", "Cell"]
        var sections = List[View]()
        if self.insp_tab == 0:
            var info = List[View]()
            info.append(Row("Name", Text(self.name)))
            info.append(Row("Rows", Text(grouped(self.frame.rows()))))
            info.append(Row("Columns", Text(String(self.frame.columns()))))
            info.append(Row("From", Text(file_name(self.source) if self.source != "sample" else "the sample", CAPTION)))
            sections.append(Section("Table", info))
            var cols = List[View]()
            for c in range(self.frame.columns()):
                cols.append(Row(self.frame.name(c), Text(kind_name(self.frame.kind(c)) + ("" if self.frame.format_of(c).is_auto() else " · " + self.frame.format_of(c).summary()), CAPTION)))
            sections.append(Section("Columns", cols))
        else:
            var col = self.grid.cur_col
            var f = self.column_format()
            var kind = self.frame.kind(col) if col >= 0 else TEXT
            var head = List[View]()
            head.append(Text((self.frame.name(col) if col >= 0 else "No column") + " · " + kind_name(kind), HEADLINE))
            head.append(Text("A format applies to the whole column: the cells, the totals below, and everything that reads it.", CAPTION))
            sections.append(Section("Column", head))
            var fmt = List[View]()
            if kind == DATE:
                fmt.append(Dropdown(materialize[DATE_STYLES](), 0 if f.style == AUTO else f.style - DATE_LONG + 1, FORMAT).fill())
            elif kind == TEXT:
                fmt.append(Text("Text", CAPTION))
            else:
                fmt.append(Dropdown(materialize[NUMBER_STYLES](), f.style, FORMAT).fill())
                var places = f.decimals if f.decimals >= 0 else (self.frame.scale(col) if kind == DECIMAL else 0)
                fmt.append(Row("Decimals", Stepper(String(places), DECIMALS_LESS, DECIMALS_MORE)))
                fmt.append(Row("Thousands separator", Toggle("", f.thousands, THOUSANDS)))
                fmt.append(Row("Negatives", Segmented(materialize[NEGATIVE_STYLES](), 1 if f.parens else 0, NEGATIVES)))
                if f.style == CURRENCY:
                    var symbols = materialize[SYMBOLS]()
                    var at_symbol = 0
                    for k in range(len(symbols)):
                        if symbols[k] == f.symbol:
                            at_symbol = k
                    fmt.append(Row("Currency", Segmented(symbols, at_symbol, SYMBOL)))
            sections.append(Section("Data format", fmt))
        return Inspector(tabs, self.insp_tab, INSP_TAB, sections, INSPECTOR_W)

    def status(self) -> View:
        var items = List[String]()
        var col = self.grid.cur_col
        if col >= 0 and self.grid.cur_row >= 0:
            items.append("Selection " + self.frame.name(col) + " · row " + grouped(self.grid.cur_row + 1))
        elif col >= 0:
            items.append("Selection column " + self.frame.name(col))
        items.append("Rows " + grouped(self.frame.rows()))
        if col >= 0 and self.frame.kind(col) != TEXT:
            items.append("Sum " + self.frame.format_value(col, Int64(self.sum), total=True))
            items.append("Average " + self.frame.format_value(col, Int64(self.sum // max(self.count, 1)), total=True))
        if self.message != "":
            items.append(self.message)
        return StatusBar(items, fixed(self.milliseconds, 1) + " ms on " + (self.gf()[].device_name() if self.gf_addr != 0 else "CPU"))

    def sheet_screen(self) -> View:
        var width = W - 40 - (INSPECTOR_W + 16 if self.inspector_open else 0)
        var cell = (self.frame.name(self.grid.cur_col) if self.grid.cur_col >= 0 else "") + (" " + String(self.grid.cur_row + 1) if self.grid.cur_row >= 0 else "")
        var fx = FormulaBar("New column", "", FORMULA_SUBMIT, placeholder="A new column: its name, then its formula") if self.formula_open else FormulaBar(cell, self.edit_text, FX_COMMIT, CELL_CANCEL)
        var items = List[View]()
        items.append(Canvas(0, self.version + self.grid.version, on_gesture=GRID, keys=True).at(0, 0).width(width).height(GRID_H).tag("table"))
        var ed = self.grid.editor_place(self.frame)
        if ed[2] > 0:
            items.append(self.grid.editor(self.edit_text, CELL_COMMIT, CELL_CANCEL).at(ed[0], ed[1]).width(ed[2]).height(30))
        var main = VStack(fx, Board(items^, width, GRID_H).width(width).height(GRID_H), spacing=6).width(width)
        var row = HStack(main, self.inspector(), spacing=16).align(START) if self.inspector_open else HStack(main, spacing=0)
        var names = List[String]()
        names.append(self.name)
        return VStack(
            self.toolbar().height(64),
            HStack(Tabs(names, 0, NO_MSG), Spacer(), Text(self.gpu_chip(), CAPTION).tone(TONE_GOOD), spacing=8).fill().align(CENTER).padding(0, 20).height(36),
            row^.padding(0, 20),
            Spacer(),
            self.status().height(30),
            spacing=6,
        ).fill().grow()


# ---------- small helpers ----------

def file_name(path: String) -> String:
    var i = path.rfind("/")
    return String(path[byte = i + 1 :]) if i >= 0 else path


def file_stem(path: String) -> String:
    var name = file_name(path)
    var dot = name.rfind(".")
    return String(name[byte=:dot]) if dot > 0 else name


def raw_text(frame: Frame, col: Int, row: Int) -> String:
    """A number or date as typed (no currency signs or separators): what the editor starts from."""
    var v = frame.get(col, row)
    var kind = frame.kind(col)
    if kind == DATE:
        return date_text(v)
    if kind == DECIMAL:
        return decimal_text(v, frame.scale(col))
    return String(v)


def config_dir() -> String:
    return environment("OMX_CONFIG", environment("HOME", ".") + "/.config/omxapp")


def recent_path() -> String:
    return config_dir() + "/recent.txt"


def read_recent() -> List[String]:
    var out = List[String]()
    try:
        with open(recent_path(), "r") as f:
            for line in f.read().split("\n"):
                var p = String(line.strip())
                if p != "":
                    out.append(p)
    except:
        pass
    return out^


def remember(path: String, mut recent: List[String]):
    var out = List[String]()
    out.append(path)
    for p in recent:
        if p != path and len(out) < 10:
            out.append(p)
    recent = out^
    try:
        make_dir(config_dir())
        with open(recent_path(), "w") as f:
            for p in recent:
                f.write(p + "\n")
    except:
        pass
