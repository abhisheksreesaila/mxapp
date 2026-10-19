# omxplorer: open your data, shape it, report on it, on your GPU. A Numbers-style data app built only from
# omxapp (mojoui) components, following the Stitch "classic" designs (docs/design/mxstudio-app/):
#   Start  → choose a file (or the sample, or a blank table)
#   Import → the columns as read, with their types and shapes, before the table exists
#   Sheet  → a toolbar for the tab you're on (the sheet's tools and formats, or the Report's tiles and filter), the formula
#            bar, the table, the inspector, the tabs along the bottom (Excel's way: tap the current one to rename it),
#            the status bar

from mojoui.view import (View, Text, Button, FilePicker, TextField, Canvas, Board, VStack, HStack, Card, Spacer, Divider,
                         Dropdown, Segmented, Toggle, Tabs, Grid, Scroll, Icon, HEADLINE, CAPTION, TITLE, PROMINENT, SUBTLE, START, CENTER, END,
                         BETWEEN, STRETCH, OMARCHY, CARD, CARD_WARN, CARD_GOOD, TONE_ACCENT, TONE_GOOD, TONE_WARN, TONE_STRONG, NO_MSG, TOOL, TOOL_INLINE, ICON_ONLY)
from mojoui.app import App, Event
from mojoui.scene import Scene
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette, skin_palette, skin_name, skin_of
from mojoui.menus import MenuBar, Menu, Item, Separator, Submenu, ContextMenu
from mojoui.overlays import Dialog, Toast, Popover, Checkbox, Clipboard
from mojoui.view import Radio, LEDGER, GRAPHITE, BLUEPRINT, LIQUID
from mojoui.view import SECONDARY
from mojoui.charts import grouped, fixed
from mojoui.numformat import fixed as numfixed, pow10


def money2(x: Float64) -> String:
    """x with two decimal places and thousands separators (rounded half away from zero), a minus when negative."""
    var a = x if x >= 0 else -x
    return ("-" if x < 0 else "") + numfixed(Int64(a * 100.0 + 0.5), 2, 2, True)
from mojoui.datagrid import (DataGrid, GRID_SELECTED, GRID_COLUMN, GRID_EDIT, GRID_READ_ONLY, GRID_REDRAW, GRID_FITTED, GRID_RESIZED,
                             GRID_TYPED, GRID_CLEAR, GRID_CANCEL, GRID_COMMIT)
from mojoui.sheet import Sheet, placeholder_sheet, blank_table, INT, DECIMAL, TEXT, DATE, BOOL
from mojoui.shared import environment, make_dir
from mojoui.files import file_name, file_stem, read_recent, remember, read_setting, write_setting
from mojoui.csvio import read_table, empty_import, CsvImport, CsvColumn, kind_name
from mojoui.omxfile import save_omx, open_document
from mojoui.numformat import (ColumnFormat, format_number, AUTO, NUMBER, CURRENCY, PERCENT, COMPACT, DATE_LONG, DATE_MONTH, DATE_ISO,
                              NUMBER_STYLES, DATE_STYLES)
from mojoui.inspector import Inspector, Section, Row, Stepper, StatCards
from mojoui.sheetchrome import Tool, Toolbar, FormulaBar, StatusBar, Tab, BottomTabs
from mojoui.cellstyle import (CellStyle, BOLD, ITALIC, UNDERLINE, STRIKE, INK_MASK, FILL_MASK, ALIGN_MASK, ink_bits, fill_bits, align_bits,
                              AUTO_ALIGN, ALIGN_LEFT, ALIGN_CENTRE, ALIGN_RIGHT, SWATCH_NAMES, swatch_name)
from mojoui.swatches import SwatchPicker, draw_swatches, swatch_at
from mojoui.sheetpage import (SheetObject, compute, shape_of, chart_view, chart_text, object_card, readout, free_spot, object_title, groups_of, OBJ_CHART, OBJ_PIVOT,
                              CHART_BAR, CHART_LINE, HEADER_H)
from mojoui.reportpage import (ReportTile, ReportFilter, ReportPage, new_tile, compute_tile, kpi_of, tile_fact, TILE_SUM, TILE_AVERAGE, TILE_COUNT,
                               TILE_CHART, TILE_DISTINCT, TILE_MEDIAN, TILE_LAST, TILE_NAMES)
from mojoui.chartview import ChartView
from mojoui.view import TAP, PAN, ZOOM, PRESS, RELEASE
from mojoui.sample import sample_table

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
comptime BLOCK_CAP = 100_000  # a block's cells read one by one (its figures, Copy, a format) at most: larger blocks say so
comptime COPY = 28  # Edit > Copy (Ctrl+C): the selected cell or block, as tab-separated text
comptime NEW_FORMULA = 18
comptime FORMULA_SUBMIT = 19
comptime SORT = 20
comptime UNDO = 21
comptime TOGGLE_INSPECTOR = 22
comptime SAVE = 24
comptime IMPORT_COLUMN = 23  # Import: the column whose details show
comptime RECENT = 40  # + index (40–49): open a recent file
comptime INSERT_CHART = 25
comptime INSERT_PIVOT = 26
comptime MOVE = 27  # a sheet object dragged by its title bar
comptime CHART_STYLE = 29
comptime OBJ_VALUE = 30
comptime OBJ_GROUP = 31
comptime OBJ_ACROSS = 32
comptime REPORT_COL = 33
comptime FILTER_COL = 34
comptime FILTER_VALUE = 35
comptime ADD_TILE = 50  # + TILE_SUM … TILE_LAST (50–55)
comptime OBJ_TAP = 100  # + object: its chart's canvas
comptime OBJ_CLOSE = 200  # + object
comptime OBJ_PICK = 300  # + object: show it in the inspector
comptime TILE_TAP = 400  # + tile: a chart tile's canvas
comptime TILE_CLOSE = 500  # + tile
comptime RESIZE = 36  # a sheet object (or the table) resized by its corner
comptime SORT_ASC = 37  # the menus' sorts (the context menu's column, else the selected one)
comptime SORT_DESC = 38
comptime MENU_CLOSE = 39  # the context menu dismissed
comptime SETTINGS = 64  # File > Settings…
comptime ABOUT = 65  # Help > About omxplorer
comptime SHOW_REPORT = 66  # View > Report / Sheet
comptime SHOW_SHEET = 67
comptime FMT_NUMBER = 68  # Format as ▸ (the context menu's column, else the selected one)
comptime FMT_CURRENCY = 69
comptime FMT_PERCENT = 70
comptime UNDO_SORT = 71  # the sort toast's Undo
comptime TOAST_CLOSE = 72
comptime SETTINGS_CLOSE = 73
comptime SKIN = 74  # Settings: the skin picked (event.number)
comptime TIMINGS = 75  # Settings: show GPU timings in the status bar
comptime KEEP_INSPECTOR = 76  # Settings: the inspector opens with a sheet
comptime ABOUT_CLOSE = 77
comptime FX_HELP = 78  # the formula bar's ƒx: what formulas can do
comptime HELP_CLOSE = 79
comptime STYLE_BOLD = 80  # the format toggles: the selected cell, or the whole column when a column is selected
comptime STYLE_ITALIC = 81
comptime STYLE_UNDERLINE = 82
comptime STYLE_STRIKE = 83
comptime STYLE_ALIGN = 84  # + AUTO_ALIGN … ALIGN_RIGHT (84–87)
comptime CLEAR_FORMAT = 88
comptime PICK_INK = 89  # open the text colour's swatches (a popover), or the fill's
comptime PICK_FILL = 90
comptime PICK_CLOSE = 91
comptime SWATCH = 92  # the swatches' canvas tapped
comptime TAB = 93  # + 0 (the sheet), 1 (the Report): a bottom tab tapped
comptime RENAME_TAB = 95  # Sheet > Rename tab…: the current tab's name becomes a field
comptime RENAME_SUBMIT = 96
comptime RENAME_CANCEL = 97
comptime PREVIEW = 98  # the import preview's gestures: it scrolls (it's read-only: taps and keys do nothing)
comptime SET_INK = 600  # + 0 (automatic) … 8: the Format menu's text colours
comptime SET_FILL = 610  # + 0 (none) … 8
comptime SWATCH_CANVAS = 5  # the swatches' canvas id
comptime SKINS: List[String] = ["Liquid", "Ledger", "Graphite", "Blueprint"]
comptime MAX_OBJECTS = 40  # per sheet, and tiles per report (canvas ids 10…49, 60…99, 120…159)
comptime TABLE_H = 400  # the table's height once objects share the sheet

comptime APP = "omxapp"  # (settings live in ~/.config/omxapp)
comptime W = 1440  # the window (Stitch's artboards; the web check's viewport)
comptime INSPECTOR_W = 300
comptime CHROME_H = 252  # the menu bar, toolbar, formula bar, bottom tabs, status bar and the gaps between them (goal 25: measured)
comptime COMPACT_W = 1440  # narrower windows: the toolbar's tools show only their icons (their titles are tooltips)
comptime FX_H = 42  # the formula bar and its gap (the report has none: its page is that much taller)
comptime SYMBOLS: List[String] = ["$", "€", "£", "₹"]
comptime NEGATIVE_STYLES: List[String] = ["−1,234", "(1,234)"]


struct Main(App):
    var screen: Int
    var has_table: Bool
    var frame: Sheet
    var ran_gpu: Bool  # the last totals ran on the GPU
    var imp: CsvImport
    var source: String  # what the table came from (a path, "sample", "blank")
    var name: String  # the table's name (the file's name without .csv)
    var grid: DataGrid
    var preview: DataGrid  # Import: the first rows, read-only
    var font: Font
    var pal: Palette
    var win_w: Int  # the window's content area in points (App.resize; W × 900 until the host says)
    var win_h: Int
    var skin: Int  # the design (LIQUID by default, D-225; Settings → Appearance writes settings.txt, D-156)
    var import_col: Int
    var insp_tab: Int  # 0 Table, 1 Cell
    var inspector_open: Bool
    var formula_open: Bool  # the formula bar adds a column instead of editing a cell
    var edit_text: String
    var message: String
    var block_lines: List[String]  # the block's figures for the status bar (computed when the selection changes, not per redraw)
    var stats: List[Tuple[String, String]]  # the selected column's figures for the inspector's cards, and what they're for
    var stats_key: String
    var clip_text: String  # what Copy put on the clipboard last, and its version (the Clipboard view)
    var clip_version: Int
    var sum: Int  # the selected column's total and count (GPU, with the session's edits)
    var count: Int
    var milliseconds: Float64
    var recent: List[String]
    var version: Int
    var objects: List[SheetObject]  # charts and pivots on the sheet
    var active: Int  # the object the inspector shows (-1: none)
    var chart_sizes: List[Tuple[Float64, Float64]]  # per canvas id: points from the last draw (taps)
    var sheet_tab: Int  # 0: the table's sheet, 1: the Report
    var tiles: List[ReportTile]
    var filter: ReportFilter
    var report_col: Int  # the column new tiles use
    var seen_edits: Int  # the frame's edit count when the objects and tiles were last computed
    var table_x: Int  # the table's place and size on the sheet (it moves and resizes like any object)
    var table_y: Int
    var table_w: Int
    var table_h_set: Int  # 0: automatic
    var reveal: Int  # the sheet child to scroll into view (a new object), and how many times asked
    var reveal_count: Int
    var ctx_col: Int  # the column a context menu is open for (-1: none), and where it opened on the grid
    var ctx_x: Int
    var ctx_y: Int
    var settings_open: Bool  # File > Settings…
    var about_open: Bool  # Help > About
    var help_open: Bool  # ƒx's popover
    var toast: String  # the toast showing ("" none) and what its Undo does
    var toast_undo: Int
    var show_timings: Bool  # Settings: the GPU time in the status bar (settings.txt: timings)
    var sheet_name: String  # the sheet tab's name (the document's name until it's renamed; the file keeps the document's)
    var report_name: String  # the Report tab's name ("Report" until it's renamed)
    var renaming: Int  # the tab being renamed (0 the sheet, 1 the Report), -1 none
    var picking: Int  # the swatches open: PICK_INK or PICK_FILL, 0 none

    def __init__(out self):
        self.screen = START_SCREEN
        self.has_table = False
        self.frame = placeholder_sheet()
        self.ran_gpu = False
        self.imp = empty_import()
        self.source = ""
        self.name = ""
        self.grid = DataGrid()
        self.preview = DataGrid()
        self.font = Font()
        self.skin = skin_of(read_setting(APP, "skin", "liquid"))
        self.win_w = W
        self.win_h = 900
        self.pal = skin_palette(self.skin)
        self.import_col = 0
        self.insp_tab = 1
        self.inspector_open = read_setting(APP, "inspector", "yes") != "no"
        self.formula_open = False
        self.edit_text = ""
        self.message = ""
        self.sum = 0
        self.count = 0
        self.clip_text = ""
        self.stats = List[Tuple[String, String]]()
        self.stats_key = ""
        self.block_lines = List[String]()
        self.clip_version = 0
        self.milliseconds = 0
        self.recent = read_recent(APP)
        self.objects = List[SheetObject]()
        self.active = -1
        self.chart_sizes = List[Tuple[Float64, Float64]](length=1000, fill=(400.0, 240.0))
        self.sheet_tab = 0
        self.tiles = List[ReportTile]()
        self.filter = ReportFilter(-1, 0)
        self.report_col = -1
        self.seen_edits = 0
        self.table_x = 0
        self.table_y = 0
        self.table_w = 0
        self.table_h_set = 0
        self.reveal = -1
        self.reveal_count = 0
        self.ctx_col = -1
        self.ctx_x = 0
        self.ctx_y = 0
        self.settings_open = False
        self.about_open = False
        self.help_open = False
        self.toast = ""
        self.toast_undo = NO_MSG
        self.show_timings = read_setting(APP, "timings", "yes") != "no"
        self.sheet_name = ""
        self.report_name = "Report"
        self.renaming = -1
        self.picking = 0
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

    def resize(mut self, width: Int, height: Int):
        """The window's content area: the sheet, the report and the inspector fill it (goal 25 M2)."""
        self.win_w = max(width, 640)
        self.win_h = max(height, 480)

    def grid_h(self) -> Int:
        """The sheet's height: the window less the menu bar, toolbar, formula bar, tabs and status bar."""
        return max(240, self.win_h - CHROME_H)

    def design(self) -> Int:
        return self.skin  # omxplorer's own skin on every platform (D-149), never the desktop's theme

    # ---------- data in ----------

    def use_table(mut self, var sheet: Sheet):
        """The new table takes over; only then is the old one's memory given back (CPU and GPU: ~26 GB at 100M
        rows). A file that fails to open never gets here, so the sheet on screen stays intact."""
        swap(self.frame, sheet)  # (sheet is the old one now)
        sheet.release()
        self.has_table = True
        self.stats_key = ""  # (the new file's edits count from 0 again: its stats are its own)

    def open_path(mut self, path: String):
        """A CSV or Parquet file → the Import step (its columns as read; a Parquet file too big for memory is streamed,
        D-184); an .omx document → straight to its sheet."""
        if path.endswith(".omx"):
            try:
                var objects = List[SheetObject]()
                var tiles = List[ReportTile]()
                var filter = ReportFilter(-1, 0)
                var tab_names = List[String]()
                var frame = open_document(path, objects, tiles, filter, tab_names)
                self.use_table(frame^)
                self.source = path
                self.name = file_stem(path)
                remember(APP, path, self.recent)
                self.to_sheet()
                if len(tab_names) > 0 and tab_names[0] != "":  # (the tabs' names as saved)
                    self.sheet_name = tab_names[0]
                if len(tab_names) > 1 and tab_names[1] != "":
                    self.report_name = tab_names[1]
                self.objects = objects^  # the sheet's charts and pivots, and the Report, as they were saved
                self.tiles = tiles^
                self.filter = filter^
                self.refresh()
                self.message = "Opened " + file_name(path) + " · " + grouped(self.frame.rows()) + " rows"
            except e:
                self.message = String(e)
            self.version += 1
            return
        try:
            var imp = read_table(path)
            self.use_table(Sheet(imp.scan.value()) if imp.streamed() else Sheet(imp.table))
            imp.let_go()  # (the sheet holds the table now; the import keeps only what it showed)
            self.imp = imp^
            self.source = path
            self.name = file_stem(path)
            self.preview = DataGrid()
            self.preview.browse = True
            self.preview.prepare(self.frame, self.font, self.pal)
            if not self.frame.streamed():  # (a histogram reads every row: a streamed file's would take seconds a column)
                for c in range(self.frame.stored()):
                    self.preview.histograms.append(self.shape_of(c))
            self.import_col = 0
            self.screen = IMPORT
            self.message = ""
            remember(APP, path, self.recent)
        except e:
            self.message = String(e)
        self.version += 1

    def shape_of(self, c: Int) -> List[Float64]:
        """A column's distribution over every row, for the header's small histogram."""
        try:
            return shape_of(self.frame, c)
        except:
            return List[Float64]()

    def open_sample(mut self):
        var rows = 1_000_000
        var asked = environment("OMX_ROWS")
        if asked != "":
            try:
                rows = max(Int(asked), 1000)
            except:
                pass
        try:
            self.use_table(Sheet(sample_table(rows).share()))
        except e:
            self.message = String(e)
            self.version += 1
            return
        self.source = "sample"
        self.name = "orders"
        self.to_sheet()

    def open_blank(mut self):
        try:
            self.use_table(Sheet(blank_table().share()))
        except e:
            self.message = String(e)
            self.version += 1
            return
        self.source = "blank"
        self.name = "Table 1"
        self.to_sheet()

    def to_sheet(mut self):
        self.screen = SHEET
        self.objects = List[SheetObject]()
        self.active = -1
        self.tiles = List[ReportTile]()
        self.filter = ReportFilter(-1, 0)
        self.sheet_tab = 0
        self.sheet_name = self.name
        self.report_name = "Report"
        self.renaming = -1
        self.picking = 0
        var nums = self.numbers()
        var money = self.first_number()  # (the first decimal column: revenue rather than an order number)
        self.report_col = money if self.frame.kind(money) == DECIMAL else (nums[0] if len(nums) > 0 else 0)  # (no number column: the first, for Distinct and Count)
        self.table_x = 0
        self.table_y = 0
        self.table_w = 0
        self.table_h_set = 0
        self.seen_edits = self.frame.edits()
        self.grid = DataGrid()
        self.grid.prepare(self.frame, self.font, self.pal)
        for c in range(self.frame.stored()):
            if self.frame.kind(c) == TEXT:
                self.grid.fit(c, self.frame, self.font, self.pal)
        self.grid.select(0, min(self.first_number(), self.frame.columns() - 1))
        self.select_cell(self.grid.cur_row, self.grid.cur_col)
        self.message = ("Imported " + grouped(self.frame.rows()) + " rows from " + file_name(self.source)) if self.source != "sample" and self.source != "blank" else ""
        if self.frame.streamed():
            self.message = "Streamed from " + file_name(self.source) + ": your edits are kept beside it until you save"
        self.version += 1

    def numbers(self) -> List[Int]:
        """The columns a chart or tile can sum (numbers and formulas)."""
        var out = List[Int]()
        for c in range(self.frame.columns()):
            if self.frame.kind(c) == INT or self.frame.kind(c) == DECIMAL:
                out.append(c)
        return out^

    def texts(self) -> List[Int]:
        """The columns a chart or pivot can group by."""
        var out = List[Int]()
        for c in range(self.frame.stored()):
            if self.frame.kind(c) == TEXT:
                out.append(c)
        return out^

    def groupings(self) -> List[Int]:
        """Text columns by how few values they have (2 or more): a new chart groups by the first (region before
        customer), a new pivot uses the first two."""
        var out = List[Int]()
        var used = List[Bool](length=self.frame.stored(), fill=False)
        for _ in range(len(self.texts())):
            var best = -1
            for c in self.texts():
                var n = groups_of(self.frame, c)
                if not used[c] and n >= 2 and (best < 0 or n < groups_of(self.frame, best)):
                    best = c
            if best < 0:
                break
            used[best] = True
            out.append(best)
        return out^

    def names_of(self, cols: List[Int]) -> List[String]:
        var out = List[String]()
        for c in cols:
            out.append(self.frame.name(c))
        return out^

    def index_in(self, cols: List[Int], col: Int) -> Int:
        for k in range(len(cols)):
            if cols[k] == col:
                return k
        return 0

    def refresh(mut self):
        """Every chart, pivot and tile again (after an edit or a change to one)."""
        self.seen_edits = self.frame.edits()
        try:
            for k in range(len(self.objects)):
                compute(self.objects[k], self.frame)
            for k in range(len(self.tiles)):
                compute_tile(self.tiles[k], self.frame, self.filter)
        except e:
            self.message = "Couldn't compute: " + String(e)
        self.version += 1

    def table_h(self) -> Int:
        if self.table_h_set > 0:
            return self.table_h_set
        return TABLE_H if len(self.objects) > 0 else self.grid_h() - 30  # (the Board keeps 30 pt under it)

    def first_number(self) -> Int:
        for c in range(self.frame.columns()):
            if self.frame.kind(c) == DECIMAL:
                return c
        return 0

    # ---------- the selection and its totals ----------

    def select_cell(mut self, row: Int, col: Int):
        self.edit_text = self.frame.plain_text(col, row) if row >= 0 and col >= 0 else ""
        if self.grid.has_block():  # a block: its own figures (a drag sends one per cell crossed: no column totals)
            self.block_lines = self.block_status()
            self.column_stats()  # (the inspector follows the selected cell's column during a block too)
        else:
            self.block_lines = List[String]()
            self.totals()
        self.version += 1

    def totals(mut self):
        """The selected column's sum and count of values over every row (edits included)."""
        var col = self.grid.cur_col
        if col < 0 or not self.has_table or self.frame.kind(col) == TEXT:
            self.sum = 0
            self.count = self.frame.rows()
            self.column_stats()
            return
        try:
            var r = self.frame.totals(col)
            self.sum = r.sums[0]
            self.count = r.present[0]  # (empty cells aren't averaged)
            self.milliseconds = r.milliseconds
            self.ran_gpu = r.on_gpu
        except e:
            self.sum = 0
            self.count = 0
            self.message = "Couldn't total " + self.frame.name(col) + ": " + String(e)
        self.column_stats()

    def column_stats(mut self):
        """The inspector's cards for the selected number column: Mean, Median, Empty, Distinct (the engine's, recomputed
        only when the column or its numbers change)."""
        var col = self.grid.cur_col
        if col < 0 or not self.has_table or self.frame.kind(col) == TEXT or self.frame.kind(col) == DATE or self.frame.kind(col) == BOOL or not self.inspector_open:
            self.stats = List[Tuple[String, String]]()
            self.stats_key = ""  # (the inspector closed: nothing to show; computed again when it opens)
            return
        var key = String(col) + "/" + String(self.frame.rows()) + "/" + String(self.frame.edits()) + "/" + String(self.frame.format_of(col).style)
        if key == self.stats_key:
            return
        self.stats_key = key
        var total = 0  # (the column's own totals: the status bar's may be a block's, goal 25 M4)
        var present = 0
        try:
            var r = self.frame.totals(col)
            total = r.sums[0]
            present = r.present[0]
        except:
            pass
        var out = List[Tuple[String, String]]()
        out.append(("Mean", self.frame.format_average(col, total, present)))
        var median = String("—")  # (a streamed file: median and distinct read every row group, so they wait for a tile)
        try:
            if self.frame.scan:
                raise Error("streamed")
            var m = self.frame.median(col)
            if m[1]:
                median = self.frame.format_median(col, m[0])
        except:
            pass
        out.append(("Median", median))
        out.append(("Empty", grouped(self.frame.rows() - present)))
        var distinct = String("—")
        try:
            if self.frame.scan:
                raise Error("streamed")
            distinct = grouped(self.frame.distinct(col))
        except:
            pass
        out.append(("Distinct", distinct))
        self.stats = out^

    def column_format(self) -> ColumnFormat:
        return self.frame.format_of(self.grid.cur_col) if self.grid.cur_col >= 0 else ColumnFormat.auto()

    def set_format(mut self, var f: ColumnFormat):
        if self.grid.cur_col < 0:
            return
        self.frame.change_format(self.grid.cur_col, f)  # (Undo takes it back)
        self.grid.redraw()
        if self.grid.cur_row >= 0:
            self.select_cell(self.grid.cur_row, self.grid.cur_col)
        self.message = self.frame.name(self.grid.cur_col) + ": " + f.summary() + " (the whole column)"
        self.version += 1

    def uses(self, c: Int) -> String:
        """What reads column c and would break without it: a chart, a pivot, a Report tile or its filter ("" none)."""
        if c < 0:
            return ""
        for o in self.objects:
            if o.value == c or o.group == c or o.across == c:
                return "a chart" if o.kind == OBJ_CHART else "a pivot"
        for t in self.tiles:
            if t.col == c or (t.kind == TILE_CHART and t.group == c):
                return "a Report tile"
        if self.filter.col == c:
            return "the Report's filter"
        return ""

    # ---------- cell formats ----------

    def style_target(mut self) -> Tuple[Int, Int]:
        """What a format tool changes: the selected cell (column, row), or (column, -1) when a whole column is
        selected; (-1, -1) and a message when nothing is."""
        if self.grid.cur_col < 0:
            self.message = "Select a cell, or a column by its header, then format it"
            self.version += 1
            return (-1, -1)
        return (self.grid.cur_col, self.grid.cur_row)

    def restyle(mut self, mask: Int, value: Int):
        var at = self.style_target()
        if at[0] < 0:
            return
        if self.grid.has_block():  # every cell of the block, one Undo step
            if self.grid.block_size(self.frame) > BLOCK_CAP:
                self.message = "That block has " + grouped(self.grid.block_size(self.frame)) + " cells: format up to " + grouped(BLOCK_CAP) + " at a time, or a whole column by its header"
                self.version += 1
                return
            var cells = self.block_cells()
            self.frame.restyle_cells(cells, mask, value)
            self.message = String(len(cells)) + " cells: " + self.frame.style_of(at[0], at[1]).words()
            self.grid.redraw()
            self.version += 1
            return
        self.frame.restyle(at[0], at[1], mask, value)
        self.after_style(at[0], at[1])

    def block_cells(self) -> List[Tuple[Int, Int]]:
        """The selected block's cells as (column, row), row by row (a single cell when there's no block)."""
        var out = List[Tuple[Int, Int]]()
        var b = self.grid.block(self.frame)
        if b[0] < 0:
            return out^
        for i in range(b[0], b[1] + 1):
            var row = self.grid.shown_row(i, self.frame)
            if row < 0 or not self.frame.grid_alive(row):
                continue
            for c in range(b[2], b[3] + 1):
                out.append((c, row))
        return out^

    def copy_block(mut self):
        """Edit > Copy: the cell or block as tab-separated text (cells as shown), onto the clipboard."""
        if self.grid.block_size(self.frame) > BLOCK_CAP:
            self.message = "That block has " + grouped(self.grid.block_size(self.frame)) + " cells: copy up to " + grouped(BLOCK_CAP) + " at a time"
            self.version += 1
            return
        var b = self.grid.block(self.frame)
        if b[0] < 0:
            self.message = "Select a cell or a block of cells to copy"
            self.version += 1
            return
        var text = String("")
        var lines = 0
        for i in range(b[0], b[1] + 1):
            var row = self.grid.shown_row(i, self.frame)
            if row < 0 or not self.frame.grid_alive(row):
                continue
            if lines > 0:
                text += "\n"
            for c in range(b[2], b[3] + 1):
                if c > b[2]:
                    text += "\t"
                text += self.frame.display(c, row)
            lines += 1
        self.clip_text = text
        self.clip_version += 1
        self.message = "Copied " + String(lines * (b[3] - b[2] + 1)) + " cells"
        self.version += 1

    def block_status(self) -> List[String]:
        """The block's figures for the status bar: Cells (its size), Count (non-empty), Sum and Average (its numbers),
        each number column totalled exactly at its own scale. Over BLOCK_CAP cells only its size (reading millions of
        cells one by one would stall the window; a Report tile totals whole columns on the engine)."""
        var out = List[String]()
        var size = self.grid.block_size(self.frame)
        if size > BLOCK_CAP:
            out.append("Cells " + grouped(size))
            out.append("Too many cells to total here (over " + grouped(BLOCK_CAP) + "): a Report tile totals whole columns")
            return out^
        var b = self.grid.block(self.frame)
        var cells = 0
        var filled = 0
        var numbers = 0
        var sums = List[Int64]()  # per column of the block, at its own scale
        for _ in range(b[2], b[3] + 1):
            sums.append(0)
        for i in range(b[0], b[1] + 1):
            var row = self.grid.shown_row(i, self.frame)
            if row < 0 or not self.frame.grid_alive(row):
                continue
            for c in range(b[2], b[3] + 1):
                cells += 1
                if self.frame.is_null(c, row):
                    continue
                filled += 1
                if self.frame.kind(c) == INT or self.frame.kind(c) == DECIMAL:
                    numbers += 1
                    sums[c - b[2]] += self.frame.value(c, row)
        out.append("Cells " + grouped(cells))
        out.append("Count " + grouped(filled))
        if numbers > 0:
            var scale = -1  # (none seen yet)
            var exact = True  # one scale: the total stays an exact integer
            var total = 0.0
            for c in range(b[2], b[3] + 1):
                if self.frame.kind(c) == INT or self.frame.kind(c) == DECIMAL:
                    var sc = self.frame.scale(c)
                    if scale >= 0 and sc != scale:
                        exact = False
                    scale = max(scale, sc)
                    total += Float64(sums[c - b[2]]) / Float64(pow10(sc))
            var one = Int64(0)
            for c in range(b[2], b[3] + 1):
                if self.frame.kind(c) == INT or self.frame.kind(c) == DECIMAL:
                    one += sums[c - b[2]]
            var sum_text = (("-" if one < 0 else "") + numfixed(one, scale, 2, True)) if exact else money2(total)
            out.append("Sum " + sum_text)
            out.append("Average " + money2(total / Float64(numbers)))
        return out^

    def after_style(mut self, col: Int, row: Int):
        var words = self.frame.style_of(col, row).words()
        if row >= 0:
            self.message = self.frame.name(col) + " on row " + grouped(row + 1) + ": " + words
        else:
            self.message = "Column " + self.frame.name(col) + ": " + words + " (the whole column)"
        self.grid.redraw()
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
        self.handle(event)
        if self.has_table and self.frame.edits() != self.seen_edits:  # the table changed (any way): every object and tile again
            self.refresh()

    def handle(mut self, event: Event):
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
        elif m == GRID and event.number == SECONDARY:  # a right click: the column's menu where it happened
            var col = self.grid.header_hit(event.x, event.y, self.frame)
            if col < 0:
                var rc = self.grid.cell_hit(event.x, event.y, self.frame)
                col = rc[1]
                if rc[0] >= 0 and rc[1] >= 0:
                    self.grid.select(rc[0], rc[1])
                    self.select_cell(rc[0], rc[1])
            self.ctx_col = col
            self.ctx_x = Int(event.x)
            self.ctx_y = Int(event.y)
            self.version += 1
        elif m == MENU_CLOSE:
            self.ctx_col = -1
            self.version += 1
        elif m == SETTINGS or m == SETTINGS_CLOSE:
            self.settings_open = m == SETTINGS
            self.version += 1
        elif m == ABOUT or m == ABOUT_CLOSE:
            self.about_open = m == ABOUT
            self.version += 1
        elif m == FX_HELP or m == HELP_CLOSE:
            self.help_open = m == FX_HELP and not self.help_open
            self.version += 1
        elif m == SKIN:
            if 0 <= event.number < 4:
                var all: List[Int] = [LIQUID, LEDGER, GRAPHITE, BLUEPRINT]
                self.skin = all[event.number]
                self.pal = skin_palette(self.skin)
                write_setting(APP, "skin", skin_name(self.skin))
                self.grid.redraw()
                self.preview.redraw()
            self.version += 1
        elif m == TIMINGS:
            self.show_timings = event.number == 1
            write_setting(APP, "timings", "yes" if self.show_timings else "no")
            self.version += 1
        elif m == KEEP_INSPECTOR:
            self.inspector_open = event.number == 1
            write_setting(APP, "inspector", "yes" if self.inspector_open else "no")
            self.version += 1
        elif m == TOAST_CLOSE:
            self.toast = ""
            self.version += 1
        elif m == UNDO_SORT:
            self.grid.clear_order()
            self.toast = ""
            self.message = "Sort undone"
            self.version += 1
        elif m == PREVIEW:  # (only scrolling: the preview selects and edits nothing)
            if event.number == PAN or event.number == ZOOM or event.number == PRESS or event.number == RELEASE:  # (browse: no selecting)
                _ = self.preview.handle(event, self.frame, self.font, self.pal)
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
            self.column_stats()
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
        elif (m == DECIMALS_LESS or m == DECIMALS_MORE) and (self.grid.cur_col < 0 or not (self.frame.kind(self.grid.cur_col) == INT or self.frame.kind(self.grid.cur_col) == DECIMAL)):
            self.message = "Decimal places apply to number columns"
            self.version += 1
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
        elif m == COPY:
            self.copy_block()
        elif m == ADD_ROW:
            try:
                var row = self.frame.append()
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
        elif m == SORT or m == SORT_ASC or m == SORT_DESC:
            var col = self.ctx_col if self.ctx_col >= 0 else self.grid.cur_col
            self.ctx_col = -1
            if col >= 0:
                var desc = (not self.grid.sort_desc) if self.grid.sort_col == col else self.frame.kind(col) != TEXT
                if m == SORT_ASC:
                    desc = False
                elif m == SORT_DESC:
                    desc = True
                try:
                    self.grid.set_order(self.frame.permutation(col, desc), col, desc)
                    self.message = "Sorted by " + self.frame.name(col) + (" (largest first)" if desc else "")
                    self.toast = "Sorted by " + self.frame.name(col) + (", largest first" if desc else ", smallest first")
                    self.toast_undo = UNDO_SORT
                except e:
                    self.message = "Couldn't sort: " + String(e)
            self.version += 1
        elif m == FMT_NUMBER or m == FMT_CURRENCY or m == FMT_PERCENT:
            var col = self.ctx_col if self.ctx_col >= 0 else self.grid.cur_col
            self.ctx_col = -1
            if col >= 0 and self.frame.kind(col) != TEXT and self.frame.kind(col) != DATE:
                if col != self.grid.cur_col:  # (the context menu's column: select it, keeping a whole-column selection whole)
                    self.grid.select(max(self.grid.cur_row, 0), col)
                var f = self.frame.format_of(col)
                var style = NUMBER if m == FMT_NUMBER else (CURRENCY if m == FMT_CURRENCY else PERCENT)
                f.style = AUTO if f.style == style else style  # (chosen again: back to automatic)
                if f.style == CURRENCY and f.decimals < 0:
                    f.decimals = 2
                if f.style == PERCENT and f.decimals < 0:
                    f.decimals = 1
                self.set_format(f^)
            else:
                self.message = "Formats apply to number columns"
                self.version += 1
        elif m == SHOW_REPORT or m == SHOW_SHEET:
            self.sheet_tab = 1 if m == SHOW_REPORT else 0
            self.renaming = -1
            self.picking = 0
            self.version += 1
        elif m == SAVE:
            var folder = environment("OMX_DOCUMENTS", environment("HOME", ".") + "/Documents/omxplorer")
            make_dir(folder)
            var path = folder + "/" + self.name + ".omx"
            try:
                var tabs: List[String] = [self.sheet_name, self.report_name]
                save_omx(path, self.frame, self.objects, self.tiles, self.filter, tabs)
                self.source = path
                remember(APP, path, self.recent)
                self.message = "Saved " + path
            except e:
                self.message = "Couldn't save: " + String(e)
            self.version += 1
        elif m == INSERT_CHART or m == INSERT_PIVOT:
            var texts = self.groupings()
            if len(self.objects) >= MAX_OBJECTS:
                self.message = "A sheet holds up to " + String(MAX_OBJECTS) + " charts and pivots: remove one first"
            elif len(texts) == 0 or len(self.numbers()) == 0:
                self.message = "A chart needs a number column and a text column to group by"
            else:
                var value = self.grid.cur_col if self.grid.cur_col >= 0 and (self.frame.kind(self.grid.cur_col) == INT or self.frame.kind(self.grid.cur_col) == DECIMAL) else self.numbers()[0]
                var width = self.sheet_width()
                var w = 520 if m == INSERT_CHART else max(width - 520 - 16, 520)  # (a chart and a pivot side by side)
                var spot = free_spot(self.objects, self.table_y + (self.table_h_set if self.table_h_set > 0 else TABLE_H), width, w, 340)  # (below the table as it'll be once objects share the sheet, wherever it is)
                var obj = SheetObject.chart(value, texts[0], spot[0], spot[1], w, 340) if m == INSERT_CHART else SheetObject.pivot(value, texts[0], texts[1] if len(texts) > 1 else -1, spot[0], spot[1], w, 340)
                var problem = String("")
                try:
                    compute(obj, self.frame)
                except e:
                    problem = String(e)
                self.objects.append(obj^)
                self.active = len(self.objects) - 1
                self.insp_tab = 2
                self.reveal = self.active + 1  # (child 0 is the table)
                self.reveal_count += 1
                if problem != "":  # (said, not replaced by the chart's timing)
                    self.message = "Couldn't compute the " + ("chart" if m == INSERT_CHART else "pivot") + ": " + problem
                else:
                    self.message = ("Chart: " if m == INSERT_CHART else "Pivot: ") + object_title(self.objects[self.active], self.frame) + " (" + fixed(self.objects[self.active].milliseconds, 1) + " ms on " + self.frame.last_device() + (", streamed from disk" if self.frame.streamed() else "") + ")"
            self.version += 1
        elif m == MOVE or m == RESIZE:  # a sheet object (child 0: the table) dragged by its title bar, or by its corner
            var k = event.number - 1
            if k == -1:
                if m == MOVE:
                    self.table_x = max(0, self.table_x + Int(event.dx))
                    self.table_y = max(0, self.table_y + Int(event.dy))
                else:
                    self.table_w = max(360, (self.table_w if self.table_w > 0 else self.sheet_width()) + Int(event.dx))
                    self.table_h_set = max(200, self.table_h() + Int(event.dy))
            elif 0 <= k < len(self.objects):
                if m == MOVE:
                    self.objects[k].x = max(0, self.objects[k].x + Int(event.dx))
                    self.objects[k].y = max(0, self.objects[k].y + Int(event.dy))
                else:
                    self.objects[k].w = max(320, self.objects[k].w + Int(event.dx))
                    self.objects[k].h = max(220, self.objects[k].h + Int(event.dy))
            self.version += 1
        elif m >= OBJ_TAP and m < OBJ_TAP + 100:
            var k = m - OBJ_TAP
            if k < len(self.objects) and event.number == TAP:
                var cv = chart_view(self.objects[k], self.frame)
                cv.size = self.chart_sizes[10 + k]
                if cv.tap(event.x, event.y, self.font, self.pal):
                    self.objects[k].selected = cv.selected
                    self.active = k
                    self.version += 1
        elif m >= OBJ_CLOSE and m < OBJ_CLOSE + 100:
            var k = m - OBJ_CLOSE
            if k < len(self.objects):
                _ = self.objects.pop(k)
                if self.active == k:
                    self.active = -1  # (the one shown was removed: show none)
                elif self.active > k:
                    self.active -= 1  # (the same object, one place earlier)
                if self.active < 0 and self.insp_tab == 2:
                    self.insp_tab = 1
                self.version += 1
        elif m >= OBJ_PICK and m < OBJ_PICK + 100:
            if m - OBJ_PICK < len(self.objects):
                self.active = m - OBJ_PICK
                self.insp_tab = 2
                self.inspector_open = True
                self.version += 1
        elif m == CHART_STYLE or m == OBJ_VALUE or m == OBJ_GROUP or m == OBJ_ACROSS:
            if 0 <= self.active < len(self.objects):
                ref o = self.objects[self.active]
                var nums = self.numbers()
                var texts = self.texts()
                if m == CHART_STYLE:
                    o.style = CHART_LINE if event.number == 1 else CHART_BAR
                elif m == OBJ_VALUE and 0 <= event.number < len(nums):
                    o.value = nums[event.number]
                elif m == OBJ_GROUP and 0 <= event.number < len(texts):
                    o.group = texts[event.number]
                elif m == OBJ_ACROSS and 0 <= event.number <= len(texts):
                    o.across = texts[event.number - 1] if event.number > 0 else -1
                o.selected = -1
                try:
                    compute(o, self.frame)
                    self.message = object_title(o, self.frame)
                except e:
                    self.message = "Couldn't compute: " + String(e)
                self.version += 1
        elif m == REPORT_COL:  # (every column: Distinct counts text too; the number tiles say so on a text column)
            if 0 <= event.number < self.frame.columns():
                self.report_col = event.number
            self.version += 1
        elif m >= ADD_TILE and m <= ADD_TILE + TILE_LAST:
            var texts = self.groupings()
            var col = self.report_col
            var t = new_tile(m - ADD_TILE, col, texts[0] if len(texts) > 0 else -1)
            var number = col >= 0 and (self.frame.kind(col) == INT or self.frame.kind(col) == DECIMAL)
            if col < 0:
                self.message = "A tile needs a column: pick one in Tiles of"
            elif not number and t.kind != TILE_DISTINCT and t.kind != TILE_COUNT:
                self.message = materialize[TILE_NAMES]()[t.kind] + " needs a number column: " + self.frame.name(col) + " isn't one (Distinct counts any column)"
            elif len(self.tiles) >= MAX_OBJECTS:
                self.message = "A report holds up to " + String(MAX_OBJECTS) + " tiles: remove one first"
            elif t.kind == TILE_CHART and len(texts) == 0:
                self.message = "A chart tile needs a text column to group by"
            else:
                try:
                    compute_tile(t, self.frame, self.filter)
                except e:
                    self.message = "Couldn't compute: " + String(e)
                self.tiles.append(t^)
            self.version += 1
        elif m >= TILE_CLOSE and m < TILE_CLOSE + 100:
            if m - TILE_CLOSE < len(self.tiles):
                _ = self.tiles.pop(m - TILE_CLOSE)
                self.version += 1
        elif m >= TILE_TAP and m < TILE_TAP + 100:
            var k = m - TILE_TAP
            if k < len(self.tiles) and event.number == TAP:
                var cv = chart_view(self.tiles[k].chart, self.frame)
                cv.size = self.chart_sizes[60 + k]
                if cv.tap(event.x, event.y, self.font, self.pal):
                    self.tiles[k].chart.selected = cv.selected
                    self.version += 1
        elif m == FILTER_COL:
            var texts = self.texts()
            if 0 <= event.number <= len(texts):
                self.filter = ReportFilter(texts[event.number - 1] if event.number > 0 else -1, 0)
                self.refresh()
        elif m == FILTER_VALUE:
            if self.filter.col >= 0 and 0 <= event.number < groups_of(self.frame, self.filter.col):
                self.filter.code = event.number
                self.refresh()
        elif m == STYLE_BOLD or m == STYLE_ITALIC or m == STYLE_UNDERLINE or m == STYLE_STRIKE:
            var part = BOLD if m == STYLE_BOLD else (ITALIC if m == STYLE_ITALIC else (UNDERLINE if m == STYLE_UNDERLINE else STRIKE))
            var at = self.style_target()
            if at[0] >= 0:
                var on = self.frame.style_of(at[0], at[1]).bits & part != 0
                self.restyle(part, 0 if on else part)
        elif m >= STYLE_ALIGN and m <= STYLE_ALIGN + ALIGN_RIGHT:
            self.restyle(ALIGN_MASK, align_bits(m - STYLE_ALIGN))
        elif m >= SET_INK and m <= SET_INK + 8:
            self.picking = 0
            self.restyle(INK_MASK, ink_bits(m - SET_INK))
        elif m >= SET_FILL and m <= SET_FILL + 8:
            self.picking = 0
            self.restyle(FILL_MASK, fill_bits(m - SET_FILL))
        elif m == PICK_INK or m == PICK_FILL:
            self.picking = 0 if self.picking == m else m
            self.version += 1
        elif m == PICK_CLOSE:
            self.picking = 0
            self.version += 1
        elif m == SWATCH:
            var k = swatch_at(event.x, event.y)
            if event.number == TAP and k >= 0 and self.picking != 0:
                var fill = self.picking == PICK_FILL
                self.picking = 0
                self.restyle(FILL_MASK if fill else INK_MASK, fill_bits(k) if fill else ink_bits(k))
        elif m == CLEAR_FORMAT:
            var at = self.style_target()
            if at[0] >= 0:
                self.frame.clear_style(at[0], at[1])
                self.after_style(at[0], at[1])
        elif m == TAB or m == TAB + 1:
            if self.sheet_tab == m - TAB and self.renaming < 0:  # the current tab again: rename it
                self.renaming = m - TAB
            else:
                self.sheet_tab = m - TAB
                self.renaming = -1
                self.picking = 0
            self.version += 1
        elif m == RENAME_TAB:
            self.renaming = self.sheet_tab
            self.version += 1
        elif m == RENAME_SUBMIT:
            var name = String(event.text.strip())
            if name == "":
                self.message = "A tab needs a name: type one, or press Escape to keep " + (self.sheet_name if self.renaming == 0 else self.report_name)
            elif name.byte_length() > 64:
                self.message = "That name is too long: 64 letters at most"
            else:
                var was = self.sheet_name if self.renaming == 0 else self.report_name
                if self.renaming == 0:
                    self.sheet_name = name
                elif self.renaming == 1:
                    self.report_name = name
                self.message = "Renamed " + was + " to " + name
                self.renaming = -1
            self.version += 1
        elif m == RENAME_CANCEL:
            self.renaming = -1
            self.message = "Kept the name"
            self.version += 1
        elif m == UNDO and self.uses(self.frame.undo_drops()) != "":
            var gone = self.frame.undo_drops()
            self.message = "Can't undo the formula column " + self.frame.name(gone) + " yet: " + self.uses(gone) + " reads it. Remove that first"
            self.version += 1
        elif m == UNDO:
            var gone = self.frame.undo_drops()
            if gone >= 0:  # (what only looks at the column lets go of it: a sort, the Report's tile column)
                if self.grid.sort_col == gone:
                    self.grid.clear_order()
                if self.report_col == gone:
                    self.report_col = self.first_number()
            if self.frame.undo():
                self.grid.min_widths = List[Float64]()  # (a formula column may have gone)
                self.grid.prepare(self.frame, self.font, self.pal)
                if self.grid.cur_col >= self.frame.columns():
                    self.grid.select(self.grid.cur_row, self.frame.columns() - 1)
                self.grid.redraw()
                self.select_cell(self.grid.cur_row, self.grid.cur_col)
                self.refresh()
                self.message = "Undid " + self.frame.last_undone + " (" + self.sheet_name + ")"
            else:
                self.message = "Nothing to undo"
            self.version += 1

    # ---------- drawing ----------

    def describe(self, canvas: Int, first: Int, count: Int) -> String:
        """A chart's numbers, or the grid's shown rows, as tab-separated text for an agent (D-163). The grid: the header, then `count` rows from
        shown row `first` (count 0: what fits on screen, or 25 before the grid has been drawn)."""
        if self.screen != SHEET:
            return ""
        if 10 <= canvas < 10 + len(self.objects) and self.objects[canvas - 10].kind == OBJ_CHART:
            return chart_text(self.objects[canvas - 10], self.frame)  # (a chart: its bars' numbers)
        if canvas != 0:
            return ""
        var cols = self.frame.grid_columns()
        var out = String()
        for c in range(cols):
            out += ("\t" if c > 0 else "") + self.frame.grid_name(c)
        var n = count if count > 0 else (self.grid.rows_in(self.grid.size[1]) if self.grid.size[1] > 0 else 25)
        var i = self.grid.top + first
        var got = 0
        while got < n:
            var r = self.grid.shown_row(i, self.frame)
            if r < 0:
                break
            i += 1
            if not self.frame.grid_alive(r):
                continue
            out += "\n"
            for c in range(cols):
                out += ("\t" if c > 0 else "") + self.frame.grid_text(c, r)
            got += 1
        return out

    def draw_scene(mut self, canvas: Int, mut scene: Scene) -> Bool:
        """The grid as a display list (goal 26; hosts that can draw one: GTK with MOJOUI_SCENE=1)."""
        if canvas != 0:
            return False
        self.grid.draw_scene(scene, self.frame, self.font, self.pal)
        return True

    def draw(mut self, canvas: Int, mut surface: Surface):
        if 0 <= canvas < len(self.chart_sizes):
            self.chart_sizes[canvas] = (surface.points_width(), surface.points_height())
        if canvas == 0:
            self.grid.draw(surface, self.frame, self.font, self.pal)
        elif canvas == 1:
            self.preview.draw(surface, self.frame, self.font, self.pal)
        elif canvas == SWATCH_CANVAS:
            var col = self.grid.cur_col
            var st = self.frame.style_of(col, self.grid.cur_row) if col >= 0 else CellStyle()
            draw_swatches(surface, st.fill() if self.picking == PICK_FILL else st.ink(), self.picking == PICK_FILL, self.font, self.pal)
        elif 10 <= canvas < 10 + len(self.objects):
            var cv = chart_view(self.objects[canvas - 10], self.frame)
            cv.draw(surface, self.font, self.pal)
        elif 60 <= canvas < 60 + len(self.tiles):
            var cv = chart_view(self.tiles[canvas - 60].chart, self.frame)
            cv.draw(surface, self.font, self.pal)
        else:
            surface.fill(self.pal.card)  # (a KPI tile's sparkline: none yet)

    # ---------- screens ----------

    def view(self) -> View:
        if self.screen == IMPORT:
            return self.import_screen()
        if self.screen == SHEET:
            return self.sheet_screen()
        return self.start_screen()

    def gpu_chip(self) -> String:
        if self.frame.device:
            return "● " + self.frame.device_name + " · ready"
        return "● CPU"

    def start_screen(self) -> View:
        """The Start screen (docs/design/universal/kit.html, 7): a side column of actions, a drop zone, recent files, samples."""
        var side = List[View]()
        side.append(Text("omxplorer", HEADLINE).tone(TONE_ACCENT))
        side.append(Button("Start", NO_MSG, SUBTLE, icon="file").fill())
        side.append(Button("New blank sheet", BLANK, SUBTLE, icon="grid").fill())
        side.append(FilePicker("Open file…", PICK, style=SUBTLE, icon="open", accept=".csv,.tsv,.txt,.parquet,.omx").fill())
        side.append(Text("Connect a database · with MX frame, next", CAPTION))
        side.append(Divider().fill())
        side.append(Button("Settings…", SETTINGS, SUBTLE, icon="gear").fill())
        side.append(Spacer())
        side.append(Card(Text(self.gpu_chip(), CAPTION).tone(TONE_GOOD), Text("Parquet files bigger than memory open too: streamed from disk, and you can still edit and save them.", CAPTION), spacing=4, tone=CARD_GOOD).fill())
        var sidebar = Card(VStack(side^, spacing=6).fill().grow().align(START), spacing=0).width(300).fill()
        var drop = Card(
            HStack(Icon("upload", 28),
                   VStack(Text("Drop a CSV, Parquet or .omx file here", HEADLINE),
                          Text("or choose a file. A million rows is fine: you see a preview first, and the rest loads while you work.", CAPTION), spacing=4).align(START),
                   Spacer(), FilePicker("Choose a file", PICK, style=PROMINENT, icon="import", accept=".csv,.tsv,.txt,.parquet,.omx"), spacing=16).fill().align(CENTER),
            spacing=0,
        ).fill()
        var recent = List[View]()
        if len(self.recent) == 0:
            recent.append(HStack(Text("Files you open show up here.", CAPTION), Spacer()).fill())
        for k in range(min(len(self.recent), 6)):
            recent.append(HStack(Icon("file", 16), Text(file_name(self.recent[k])), Text(self.recent[k], CAPTION), Spacer(),
                                 Button("Open", RECENT + k, SUBTLE), spacing=12).fill().align(CENTER))
        var samples = HStack(
            Card(Text("Orders", HEADLINE), Text("1M rows · a year of sales by region, product and carrier", CAPTION), Spacer(),
                 Button("Open the sample", SAMPLE, icon="sample"), spacing=8).width(330).height(150),
            Card(Text("Blank sheet", HEADLINE), Text("An empty table to type into", CAPTION), Spacer(),
                 Button("New blank sheet", BLANK, icon="grid"), spacing=8).width(330).height(150),
            Card(Text("Taxi trips", HEADLINE), Text("100M rows · a GPU workout (docs/scale.md)", CAPTION), Spacer(), Text("Coming with MX frame", CAPTION), spacing=8).width(330).height(150),
            spacing=16,
        )
        var main = VStack(
            Text("Open a file", HEADLINE),
            drop,
            Text("Recent", HEADLINE),
            Card(VStack(recent^, spacing=8).fill(), spacing=8).fill(),
            Text("Try a sample", HEADLINE),
            samples,
            Text(self.message, CAPTION).tone(TONE_WARN) if self.message != "" else Spacer(),
            spacing=16,
        ).grow().align(START)
        var body = HStack(sidebar, main, spacing=24).padding(24, 32).fill().grow().align(STRETCH)
        var parts = List[View]()
        parts.append(self.menu_bar())
        parts.append(body^)
        parts.append(StatusBar(["Ready"], "omxplorer · omxapp"))
        for o in self.overlays():
            parts.append(o.copy())
        return VStack(parts^, spacing=0).fill().grow()

    def import_screen(self) -> View:
        """Import, step 2 (docs/design/liquid.md): a centred sheet: the file's facts and the steps, a preview of the first
        rows, then one left-aligned row per column (name, type, empty, distinct, first values), then Back and Create table."""
        var rows = List[View]()
        rows.append(self.import_row(Text("COLUMN", CAPTION), Text("TYPE", CAPTION), Text("EMPTY", CAPTION), Text("DISTINCT", CAPTION), Text("FIRST VALUES", CAPTION)))
        for k in range(len(self.imp.columns)):
            ref c = self.imp.columns[k]
            var first = String("")
            for s in range(min(3, len(c.sample))):
                first += ("  ·  " if s > 0 else "") + c.sample[s]
            rows.append(self.import_row(Text(c.name).tone(TONE_STRONG), Text(kind_name(c.kind)).tone(TONE_ACCENT),
                                        Text(grouped(c.empty) if c.empty >= 0 else "—").tone(TONE_WARN if c.empty > 0 else 0),
                                        Text(grouped(c.distinct) if c.kind == TEXT else "—"), Text(first, CAPTION)))
        var note = String("Empty cells stay empty; a column's type can change later from its menu.")
        if len(self.imp.skipped) > 0:
            note = String(len(self.imp.skipped)) + " more columns aren't read (4,096 is the limit)"
        if self.imp.streamed():
            note = "Too big for memory: streamed from disk, a row group at a time. You can edit, chart and save it as usual; its empty cells aren't counted up front."
        var dialog = Card(
            HStack(VStack(Text("Import " + file_name(self.imp.path), HEADLINE),
                          Text(grouped(self.imp.rows) + " rows · " + String(len(self.imp.columns)) + " columns · "
                               + ("streamed, opened in " if self.imp.streamed() else "read in ") + fixed(self.imp.seconds, 2) + " s", CAPTION).tone(TONE_GOOD), spacing=2).align(START),
                   Spacer(), Text("✓ File   ›   2  Columns   ›   3  Table", CAPTION), spacing=12).fill().align(CENTER),
            Canvas(1, self.version + self.preview.version, on_gesture=PREVIEW).fill().height(300).tag("import-preview"),
            Text("Columns", HEADLINE),
            Scroll(VStack(rows^, spacing=0).fill(), height=250).fill().tag("import-columns"),
            Spacer(),
            HStack(Button("Back", BACK), Text(note, CAPTION).tone(TONE_WARN if self.imp.streamed() or len(self.imp.skipped) > 0 else 0), Spacer(),
                   Button("Create table", CREATE, style=PROMINENT, icon="table"), spacing=14).fill().align(CENTER),
            spacing=14,
        ).width(1120).fill().grow().tag("import")
        return VStack(dialog, spacing=0).padding(28, 40).fill().grow().align(CENTER)

    def import_row(self, name: View, kind: View, empty: View, distinct: View, first: View) -> View:
        """One row of the import's column table: fixed columns, left-aligned, a hairline under it."""
        return VStack(HStack(name.copy().width(180), kind.copy().width(140), empty.copy().width(110), distinct.copy().width(110), first.copy(), Spacer(), spacing=12)
                      .fill().align(CENTER).height(34), Divider().fill(), spacing=0).fill()

    def menu_bar(self) -> View:
        """The menus every screen carries (on a Mac, the system menu bar): the same actions as the toolbar, with shortcuts."""
        var on_sheet = self.screen == SHEET
        var edits = on_sheet  # (a streamed file edits too, D-213)
        var col = self.ctx_col if self.ctx_col >= 0 else self.grid.cur_col
        var style = self.frame.format_of(col).style if on_sheet and col >= 0 else AUTO
        var format_as = Submenu("Format as", [Item("Number", FMT_NUMBER, checked=style == NUMBER, disabled=not on_sheet),
                                               Item("Currency", FMT_CURRENCY, checked=style == CURRENCY, disabled=not on_sheet),
                                               Item("Percent", FMT_PERCENT, checked=style == PERCENT, disabled=not on_sheet)], icon="format")
        var cells = on_sheet and self.sheet_tab == 0  # (formats apply to the sheet's cells; the Report has none)
        var st = self.frame.style_of(self.grid.cur_col, self.grid.cur_row) if cells and self.grid.cur_col >= 0 else CellStyle()
        var inks = List[View]()
        var fills = List[View]()
        for k in range(9):
            inks.append(Item(swatch_name(k), SET_INK + k, checked=st.ink() == k, disabled=not cells))
            fills.append(Item("None" if k == 0 else swatch_name(k), SET_FILL + k, checked=st.fill() == k, disabled=not cells))
        var bar = MenuBar([
            Menu("File", [Item("New blank sheet", BLANK, icon="grid", shortcut="Ctrl+N"), Item("Open…", BACK, icon="open", shortcut="Ctrl+O", disabled=not on_sheet),
                          Separator(), Item("Save", SAVE, icon="save", shortcut="Ctrl+S", disabled=not edits), Separator(),
                          Item("Settings…", SETTINGS, icon="gear", shortcut="Ctrl+,")]),
            Menu("Edit", [Item("Undo", UNDO, icon="undo", shortcut="Ctrl+Z", disabled=not on_sheet), Separator(),
                          Item("Copy", COPY, icon="copy", shortcut="Ctrl+C", disabled=not on_sheet or self.sheet_tab != 0), Separator(),  # (a streamed file's formats can be undone)
                          Item("Add row", ADD_ROW, icon="row-plus", shortcut="Ctrl+Shift+R", disabled=not edits)]),
            Menu("View", [Item("Inspector", TOGGLE_INSPECTOR, checked=self.inspector_open, shortcut="Ctrl+Shift+I", disabled=not on_sheet), Separator(),
                          Item("Sheet", SHOW_SHEET, icon="sheet", checked=on_sheet and self.sheet_tab == 0, disabled=not on_sheet),
                          Item("Report", SHOW_REPORT, icon="chart-bar", checked=on_sheet and self.sheet_tab == 1, disabled=not on_sheet), Separator(),
                          Item("Rename tab…", RENAME_TAB, icon="rename", disabled=not on_sheet)]),
            Menu("Insert", [Item("Chart", INSERT_CHART, icon="chart-bar", shortcut="Ctrl+Shift+C", disabled=not on_sheet),
                            Item("Pivot table", INSERT_PIVOT, icon="pivot", shortcut="Ctrl+Shift+P", disabled=not on_sheet), Separator(),
                            Item("Formula column", NEW_FORMULA, icon="formula", checked=self.formula_open, disabled=not edits),
                            Item("Row", ADD_ROW, icon="row-plus", disabled=not edits)]),
            Menu("Data", [Item("Sort smallest first", SORT_ASC, icon="sort", shortcut="Ctrl+Shift+↑", disabled=not edits),
                          Item("Sort largest first", SORT_DESC, shortcut="Ctrl+Shift+↓", disabled=not edits), Separator(), format_as.copy()]),
            Menu("Format", [Item("Bold", STYLE_BOLD, icon="bold", shortcut="Ctrl+B", checked=st.bold(), disabled=not cells),
                            Item("Italic", STYLE_ITALIC, icon="italic", shortcut="Ctrl+I", checked=st.italic(), disabled=not cells),
                            Item("Underline", STYLE_UNDERLINE, icon="underline", shortcut="Ctrl+U", checked=st.underline(), disabled=not cells),
                            Item("Strikethrough", STYLE_STRIKE, icon="strikethrough", shortcut="Ctrl+5", checked=st.strike(), disabled=not cells), Separator(),
                            Submenu("Text colour", inks^, icon="text-colour"), Submenu("Fill colour", fills^, icon="fill"),
                            Submenu("Align", [Item("Automatic", STYLE_ALIGN + AUTO_ALIGN, checked=st.align() == AUTO_ALIGN, disabled=not cells),
                                              Item("Left", STYLE_ALIGN + ALIGN_LEFT, checked=st.align() == ALIGN_LEFT, disabled=not cells),
                                              Item("Centre", STYLE_ALIGN + ALIGN_CENTRE, checked=st.align() == ALIGN_CENTRE, disabled=not cells),
                                              Item("Right", STYLE_ALIGN + ALIGN_RIGHT, checked=st.align() == ALIGN_RIGHT, disabled=not cells)], icon="align-left"),
                            Separator(), format_as.copy(), Item("Clear formatting", CLEAR_FORMAT, icon="clear-format", disabled=not cells), Separator(),
                            Item("Format inspector", TOGGLE_INSPECTOR, icon="format", checked=self.inspector_open, disabled=not on_sheet)]),
            Menu("Help", [Item("About omxplorer", ABOUT, icon="file")]),
        ])
        var doc = (self.sheet_name + " · " + grouped(self.frame.rows()) + " rows") if on_sheet else String("")
        return HStack(Text("omxplorer", HEADLINE).tag("app-mark"), bar^, Spacer(), Text(doc, CAPTION).tag("doc-chip"),
                      Text(self.gpu_chip(), CAPTION).tag("gpu-chip"), spacing=10).fill().align(CENTER).height(38).padding(2, 10).tag("menubar")

    def context_menu(self) -> View:
        """The column's menu, open over the grid where the right click was."""
        var col = self.ctx_col
        var numeric = self.frame.kind(col) == INT or self.frame.kind(col) == DECIMAL
        var style = self.frame.format_of(col).style
        var edits = True
        return ContextMenu("grid", self.ctx_x, self.ctx_y, [
            Item("Sort smallest first", SORT_ASC, icon="sort", disabled=not edits), Item("Sort largest first", SORT_DESC, disabled=not edits), Separator(),
            Submenu("Format as", [Item("Number", FMT_NUMBER, checked=style == NUMBER), Item("Currency", FMT_CURRENCY, checked=style == CURRENCY),
                                  Item("Percent", FMT_PERCENT, checked=style == PERCENT)], icon="format").copy() if numeric else Item("Format as", NO_MSG, icon="format", disabled=True),
            Separator(), Item("Insert formula column", NEW_FORMULA, icon="formula", disabled=not edits), Item("Add row", ADD_ROW, icon="row-plus", disabled=not edits)], on_close=MENU_CLOSE)

    def overlays(self) -> List[View]:
        """What floats over the screen right now: a dialog, the toast, ƒx's popover (each is in the view only while open)."""
        var out = List[View]()
        if self.settings_open:
            var at = 0 if self.skin == LIQUID else (1 if self.skin == LEDGER else (2 if self.skin == GRAPHITE else 3))
            out.append(Dialog("Settings", VStack(
                Text("Appearance", HEADLINE), Text("The same on every computer, whatever the system theme.", CAPTION),
                Radio(materialize[SKINS](), at, SKIN),
                Divider().fill(),
                Checkbox("Show GPU timings in the status bar", self.show_timings, TIMINGS),
                Checkbox("Open the inspector with a sheet", self.inspector_open, KEEP_INSPECTOR),
                HStack(Text("Kept in settings.txt in your config folder, so every launch looks the same.", CAPTION), Spacer(), Button("Done", SETTINGS_CLOSE, PROMINENT), spacing=10).fill().align(CENTER),
                spacing=12).align(START), on_close=SETTINGS_CLOSE))
        if self.about_open:
            out.append(Dialog("About omxplorer", VStack(
                Text("omxplorer", TITLE).tone(TONE_ACCENT), Text("open data, shape it, report on it, on your GPU", CAPTION),
                Text(self.gpu_chip(), CAPTION).tone(TONE_GOOD),
                Text("Written once in Mojo with omxapp: the same app, the same look, on Linux, the web, Mac, iPhone and Android.", CAPTION),
                HStack(Spacer(), Button("Done", ABOUT_CLOSE, PROMINENT), spacing=10).fill(),
                spacing=10).align(START), on_close=ABOUT_CLOSE, width=480))
        if self.picking != 0 and self.screen == SHEET:
            var fill = self.picking == PICK_FILL
            var names = String("Automatic") if not fill else String("None")
            for n in materialize[SWATCH_NAMES]():
                names += " · " + n
            out.append(Popover("fill" if fill else "text-colour", "Fill colour" if fill else "Text colour", VStack(
                SwatchPicker(SWATCH_CANVAS, self.version, SWATCH), Text(names, CAPTION), spacing=6).align(START), on_close=PICK_CLOSE))
        if self.help_open:
            out.append(Popover("formula-bar", "Formulas", VStack(
                Text("A formula makes a whole column from other columns: margin = revenue - cost", CAPTION),
                Text("+  −  ×  ÷  //  %   and parentheses", CAPTION), Text("min(a, b)   max(a, b)   −a", CAPTION),
                Text("Money keeps its decimals; division rounds the way the column does.", CAPTION), spacing=6).align(START).max_width(420), on_close=HELP_CLOSE))
        if self.toast != "":
            out.append(Toast(self.toast, "Undo" if self.toast_undo != NO_MSG else "", self.toast_undo, on_close=TOAST_CLOSE))
        return out^

    def toolbar(self) -> View:
        """The tools for the tab you're on: the sheet's (edit, data, formats, insert) or the Report's (tiles, filter)."""
        var streamed = self.frame.streamed()  # (from disk, editable: D-213)
        var left: List[Tool] = [Tool("Save", "save", SAVE, False, "Save the document (Ctrl+S)"), Tool("Undo", "undo", UNDO, False, "Undo the last change (Ctrl+Z)")]
        var right: List[Tool] = [Tool("Format", "format", TOGGLE_INSPECTOR, self.inspector_open, "Show or hide the inspector (Ctrl+Shift+I)")]
        var extra = List[View]()
        if streamed:
            extra.append(Text("Streamed from disk", CAPTION).tone(TONE_ACCENT).tooltip("This file is bigger than memory: its rows are read from disk as they're shown, and your edits are kept beside it until you save").tag("streamed"))
        extra.append(FilePicker("Open", PICK, style=TOOL_INLINE, icon="import", accept=".csv,.tsv,.txt,.parquet,.omx").tooltip("Open a CSV, Parquet or .omx file"))
        if self.sheet_tab == 1:
            return Toolbar(left, self.report_tools(), right, extra, before=self.report_controls(), after=self.filter_controls(), inline=True)  # (its tile tools share one icon: their titles stay)
        var middle = List[Tool]()
        middle.append(Tool("Add row", "row-plus", ADD_ROW, False, "A new row at the end (Ctrl+Shift+R)"))
        middle.append(Tool("Formula", "formula", NEW_FORMULA, self.formula_open, "A new column computed from others"))
        middle.append(Tool("Sort", "sort", SORT, self.grid.sort_col >= 0, "Sort by the selected column; again to flip"))
        middle.append(Tool("Pivot", "pivot", INSERT_PIVOT, False, "A pivot table of the selected column (Ctrl+Shift+P)"))
        middle.append(Tool("Chart", "chart-bar", INSERT_CHART, False, "A chart of the selected column (Ctrl+Shift+C)"))
        return Toolbar(left, middle, right, extra, toggles=self.format_tools(), inline=True, compact=self.win_w < COMPACT_W)

    def format_tools(self) -> List[List[Tool]]:
        """Excel's Home tab, in small toggles: font, colours, alignment, number. Each shows the selection's state."""
        var col = self.grid.cur_col
        var st = self.frame.style_of(col, self.grid.cur_row) if col >= 0 else CellStyle()
        var number = self.frame.format_of(col).style if col >= 0 else AUTO
        var target = "the selected cell" if self.grid.cur_row >= 0 else "the selected column"
        var font: List[Tool] = [Tool("Bold", "bold", STYLE_BOLD, st.bold(), "Bold: " + target + " (Ctrl+B)"),
                                Tool("Italic", "italic", STYLE_ITALIC, st.italic(), "Italic (Ctrl+I)"),
                                Tool("Underline", "underline", STYLE_UNDERLINE, st.underline(), "Underline (Ctrl+U)"),
                                Tool("Strikethrough", "strikethrough", STYLE_STRIKE, st.strike(), "Strikethrough (Ctrl+5)")]
        var colours: List[Tool] = [Tool("Text colour", "text-colour", PICK_INK, st.ink() > 0 or self.picking == PICK_INK, "Text colour: " + swatch_name(st.ink())),
                                   Tool("Fill colour", "fill", PICK_FILL, st.fill() > 0 or self.picking == PICK_FILL, "Fill: " + (swatch_name(st.fill()) if st.fill() > 0 else "none"))]
        var align: List[Tool] = [Tool("Align left", "align-left", STYLE_ALIGN + ALIGN_LEFT, st.align() == ALIGN_LEFT, "Align left"),
                                 Tool("Align centre", "align-center", STYLE_ALIGN + ALIGN_CENTRE, st.align() == ALIGN_CENTRE, "Centre"),
                                 Tool("Align right", "align-right", STYLE_ALIGN + ALIGN_RIGHT, st.align() == ALIGN_RIGHT, "Align right")]
        var numbers: List[Tool] = [Tool("Currency", "currency", FMT_CURRENCY, number == CURRENCY, "Currency: the whole column (again: automatic)"),
                                   Tool("Percent", "percent", FMT_PERCENT, number == PERCENT, "Percent: the whole column (again: automatic)"),
                                   Tool("Fewer decimals", "decimals-less", DECIMALS_LESS, False, "One decimal place fewer: the whole column"),
                                   Tool("More decimals", "decimals-more", DECIMALS_MORE, False, "One decimal place more: the whole column"),
                                   Tool("Clear formatting", "clear-format", CLEAR_FORMAT, False, "Back to plain: " + target)]
        return [font^, colours^, align^, numbers^]

    def report_tools(self) -> List[Tool]:
        return [Tool("Sum tile", "plus", ADD_TILE + TILE_SUM, False, "A tile with the column's total"),
                Tool("Average tile", "plus", ADD_TILE + TILE_AVERAGE, False, "A tile with the column's average"),
                Tool("Median tile", "plus", ADD_TILE + TILE_MEDIAN, False, "A tile with the column's middle value"),
                Tool("Distinct tile", "plus", ADD_TILE + TILE_DISTINCT, False, "A tile with how many different values the column holds (text too)"),
                Tool("Count tile", "plus", ADD_TILE + TILE_COUNT, False, "A tile with the number of rows"),
                Tool("Chart tile", "chart-bar", ADD_TILE + TILE_CHART, False, "A chart of the column by group")]

    def report_controls(self) -> List[View]:
        """Before the Report's tile tools: the column new tiles use; after them, the filter every tile reads through."""
        var every = List[Int]()
        for c in range(self.frame.columns()):
            every.append(c)
        var out = List[View]()
        out.append(VStack(Text("Tiles of", CAPTION), Dropdown(self.names_of(every), max(self.report_col, 0), REPORT_COL).tag("tiles-of").tooltip("The column new tiles add up, average or count"), spacing=2).align(START))
        return out^

    def filter_controls(self) -> List[View]:
        var texts = self.texts()
        var cols = List[String]()
        cols.append("Every row")
        for c in texts:
            cols.append(self.frame.name(c))
        var at_col = 0
        for k in range(len(texts)):
            if texts[k] == self.filter.col:
                at_col = k + 1
        var out = List[View]()
        out.append(VStack(Text("Filter · every tile", CAPTION), Dropdown(cols, at_col, FILTER_COL).tag("filter-column"), spacing=2).align(START))
        if self.filter.col >= 0:
            var values = List[String]()
            for code in range(groups_of(self.frame, self.filter.col)):
                values.append(self.frame.text_of(self.filter.col, Int64(code)))
            out.append(VStack(Text("is", CAPTION), Dropdown(values, self.filter.code, FILTER_VALUE).tag("filter-value"), spacing=2).align(START))
        return out^

    def report_inspector(self) -> View:
        """The Report's inspector: where its numbers come from (the tiles and the filter are in the toolbar)."""
        var sections = List[View]()
        var data = List[View]()
        data.append(Row("Source", Text(self.sheet_name)))
        data.append(Row("Rows", Text(grouped(self.frame.rows()))))
        data.append(Row("Filter", Text(self.filter.words(self.frame), CAPTION)))
        data.append(Text("Edits in the table show here at once. Add tiles and set the filter in the toolbar.", CAPTION))
        sections.append(Section("Data", data))
        var tabs: List[String] = [self.report_name]
        return Inspector(tabs, 0, NO_MSG, sections, INSPECTOR_W)

    def object_inspector(self) -> List[View]:
        """The selected chart's or pivot's settings."""
        var sections = List[View]()
        ref o = self.objects[self.active]
        var nums = self.numbers()
        var texts = self.texts()
        var head = List[View]()
        head.append(Text(object_title(o, self.frame), HEADLINE))
        head.append(Text("Follows edits to " + self.sheet_name + " (" + fixed(o.milliseconds, 1) + " ms on " + self.frame.last_device() + ")", CAPTION))
        sections.append(Section("Chart" if o.kind == OBJ_CHART else "Pivot", head))
        var data = List[View]()
        if o.kind == OBJ_CHART:
            var styles: List[String] = ["Bar", "Line"]
            data.append(Row("Type", Segmented(styles, 1 if o.style == CHART_LINE else 0, CHART_STYLE)))
            data.append(Row("Value", Dropdown(self.names_of(nums), self.index_in(nums, o.value), OBJ_VALUE)))
            data.append(Row("Group by", Dropdown(self.names_of(texts), self.index_in(texts, o.group), OBJ_GROUP)))
        else:
            var across = List[String]()
            across.append("None")
            for c in texts:
                across.append(self.frame.name(c))
            data.append(Row("Value", Dropdown(self.names_of(nums), self.index_in(nums, o.value), OBJ_VALUE)))
            data.append(Row("Rows", Dropdown(self.names_of(texts), self.index_in(texts, o.group), OBJ_GROUP)))
            data.append(Row("Columns", Dropdown(across, self.index_in(texts, o.across) + 1 if o.across >= 0 else 0, OBJ_ACROSS)))
        sections.append(Section("Data", data))
        return sections^

    def inspector(self) -> View:
        if self.sheet_tab == 1:
            return self.report_inspector()
        var tabs: List[String] = ["Table", "Cell"]
        if 0 <= self.active < len(self.objects):
            tabs.append("Chart" if self.objects[self.active].kind == OBJ_CHART else "Pivot")
            if self.insp_tab == 2:
                return Inspector(tabs, 2, INSP_TAB, self.object_inspector(), INSPECTOR_W)
        var sections = List[View]()
        if self.insp_tab == 0:
            var info = List[View]()
            info.append(Row("Name", Text(self.sheet_name)))
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
            elif kind == BOOL:  # (no decimals or separators: a yes or a no, shown as a pill)
                fmt.append(Text("Yes / No", CAPTION))
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
            if len(self.stats) > 0:
                sections.append(Section("Column stats", [StatCards(self.stats)]))
        return Inspector(tabs, min(self.insp_tab, 1), INSP_TAB, sections, INSPECTOR_W)

    def status(self) -> View:
        var items = List[String]()
        var col = self.grid.cur_col
        if self.grid.has_block():
            var b = self.grid.block(self.frame)
            items.append("Selection " + String(b[1] - b[0] + 1) + " rows × " + String(b[3] - b[2] + 1) + " columns")
            for t in self.block_lines:
                items.append(t)
            if self.message != "":
                items.append(self.message)
            return StatusBar(items, (fixed(self.milliseconds, 1) + " ms on " + (self.frame.device_name if self.ran_gpu else "CPU")) if self.show_timings else "")
        if col >= 0 and self.grid.cur_row >= 0:
            items.append("Selection " + self.frame.name(col) + " · row " + grouped(self.grid.cur_row + 1) + " · " + self.frame.display(col, self.grid.cur_row))
        elif col >= 0:
            items.append("Selection column " + self.frame.name(col))
        items.append("Rows " + grouped(self.frame.rows()))
        items.append("Columns " + String(self.frame.columns()))
        if col >= 0 and (self.frame.kind(col) == INT or self.frame.kind(col) == DECIMAL):
            items.append("Sum " + self.frame.format_value(col, Int64(self.sum), total=True))
            items.append("Average " + self.frame.format_average(col, self.sum, self.count))
        if self.message != "":
            items.append(self.message)
        if self.frame.read_problem() != "":
            items.append("Couldn't read the file: " + self.frame.read_problem())
        return StatusBar(items, (fixed(self.milliseconds, 1) + " ms on " + (self.frame.device_name if self.ran_gpu else "CPU")) if self.show_timings else "")

    def sheet_width(self) -> Int:
        return self.win_w - 40 - (INSPECTOR_W + 16 if self.inspector_open else 0)

    def report_view(self) -> View:
        """The Report tab (Stitch 06): KPI and chart tiles over the filtered rows, and the row that adds them."""
        var kpis = List[View]()
        var charts = List[View]()
        var first_kpi = True
        for k in range(len(self.tiles)):
            ref t = self.tiles[k]
            if t.kind == TILE_CHART:
                var cv = chart_view(t.chart, self.frame)
                charts.append(Card(HStack(Text(cv.title, HEADLINE), Spacer(), Button("Remove", TILE_CLOSE + k, ICON_ONLY, icon="close"), spacing=8).fill().align(CENTER),
                                   Canvas(60 + k, self.version, on_gesture=TILE_TAP + k).fill().height(240),
                                   Text(readout(t.chart, self.frame), CAPTION), spacing=6).fill().tag("chart-tile"))
            else:
                kpis.append(kpi_of(t, self.frame, self.filter, first_kpi).view(120 + k, self.version, TILE_CLOSE + k, tile_fact(t, self.frame)).fill().tag("tile"))
                first_kpi = False
        if len(kpis) > 0:  # (Stitch's report: a dashed card where the next tile goes)
            kpis.append(Card(Spacer(), HStack(Spacer(), Icon("plus", 16), Text("Add a tile from the toolbar", CAPTION), Spacer(), spacing=8).fill().align(CENTER), Spacer(),
                             spacing=0).fill().tag("add-tile"))
        var matched = String("")
        for t in self.tiles:
            if t.kind == TILE_SUM or t.kind == TILE_AVERAGE or t.kind == TILE_COUNT:
                matched = " · " + grouped(t.count) + " of " + grouped(self.frame.rows()) + " rows"
                break
        var ran = " · " + fixed(self.milliseconds, 1) + " ms on " + ("the GPU" if self.ran_gpu else "the CPU") if self.show_timings else String("")
        var facts = String(matched + ran)
        if facts.startswith(" · "):
            var cut = String(facts[byte=len(String(" · ").as_bytes()):])  # (the dot is two bytes: " · " is four)
            facts = cut
        var page = ReportPage(self.report_name, self.sheet_name + " · " + self.filter.words(self.frame), kpis, charts, facts)
        if len(self.tiles) == 0:  # (an empty report says where tiles come from)
            page = VStack(page^, Card(Text("An empty report: add a tile from the toolbar above (Sum, Average, Count or Chart of the column you pick there). Every tile reads the table, so edits show here at once.", CAPTION), spacing=8).fill(), spacing=16).fill().align(START)
        return Scroll(page^.width(self.sheet_width() - 8).padding(4, 4), height=self.grid_h() + FX_H).fill().grow().tag("report-page")  # (full width: the charts span it)

    def sheet_screen(self) -> View:
        var width = self.sheet_width()
        var cell = (self.frame.name(self.grid.cur_col) if self.grid.cur_col >= 0 else "") + (" " + String(self.grid.cur_row + 1) if self.grid.cur_row >= 0 else "")
        var fx = FormulaBar("New column", "", FORMULA_SUBMIT, placeholder="A new column: its name, then its formula", on_help=FX_HELP) if self.formula_open else FormulaBar(cell, self.edit_text, FX_COMMIT, CELL_CANCEL, on_help=FX_HELP)
        var sorted = ("sorted by " + self.frame.name(self.grid.sort_col) + (" ↓" if self.grid.sort_desc else " ↑")) if self.grid.sort_col >= 0 else String("")
        var head = HStack(Text(self.sheet_name, HEADLINE), Text(grouped(self.frame.rows()) + " rows", CAPTION).tone(TONE_ACCENT), Spacer(),
                          Text(sorted, CAPTION), spacing=12).fill().align(CENTER).height(HEADER_H - 8)
        var th = self.table_h()
        var items = List[View]()  # child 0: the table (its title bar is the drag handle; it stays put); then the objects; then the editor
        items.append(VStack(head, Canvas(0, self.version + self.grid.version, on_gesture=GRID, keys=True).fill().height(th - HEADER_H).tag("grid"), spacing=8)
                     .at(self.table_x, self.table_y).width(self.table_w if self.table_w > 0 else width).height(th).tag("table"))
        var bottom = self.table_y + th
        for k in range(len(self.objects)):
            ref o = self.objects[k]
            items.append(object_card(o, self.frame, 10 + k, self.version, OBJ_TAP + k, OBJ_CLOSE + k, OBJ_PICK + k)
                         .at(o.x, o.y).width(o.w).height(o.h).tag("chart" + String(k) if o.kind == OBJ_CHART else "pivot" + String(k)))
            bottom = max(bottom, o.y + o.h)
        var ed = self.grid.editor_place(self.frame)
        if ed[2] > 0:
            items.append(self.grid.editor(self.edit_text, CELL_COMMIT, CELL_CANCEL).at(self.table_x + ed[0], self.table_y + HEADER_H + ed[1]).width(ed[2]).height(30))
        var area = (Board(items^, width, bottom + 24, on_move=MOVE, on_resize=RESIZE, reveal=self.reveal, reveal_count=self.reveal_count)
                    .fill().grow()) if self.sheet_tab == 0 else self.report_view()
        # The sheet's column takes the room the inspector leaves, the row takes the height the bars leave: sizes
        # come from the window (App.resize), never asked of it, so the window never grows to fit them (goal 25 M2).
        var main = (VStack(fx, area^, spacing=6) if self.sheet_tab == 0 else VStack(area^, spacing=6)).grow().align(STRETCH)
        var row = (HStack(main, self.inspector(), spacing=16) if self.inspector_open else HStack(main, spacing=0)).align(STRETCH)
        var tabs: List[Tab] = [Tab(self.sheet_name, "sheet"), Tab(self.report_name, "chart-bar")]
        var chip: List[View] = [Text(self.gpu_chip(), CAPTION).tone(TONE_GOOD)]
        var parts = List[View]()
        parts.append(self.menu_bar())
        parts.append(self.toolbar())
        parts.append(row^.padding(0, 20).fill().grow())
        parts.append(BottomTabs(tabs, self.sheet_tab, TAB, self.renaming, RENAME_SUBMIT, RENAME_CANCEL, chip).height(30))  # (Excel's place for them)
        parts.append(self.status().height(30))
        if self.ctx_col >= 0 and self.sheet_tab == 0:
            parts.append(self.context_menu())
        parts.append(Clipboard(self.clip_text, self.clip_version))
        for o in self.overlays():
            parts.append(o.copy())
        return VStack(parts^, spacing=6).fill().grow()
