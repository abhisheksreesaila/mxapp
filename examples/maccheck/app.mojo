# maccheck: every control on a few pages, for checking a host the checks can't see (the Mac, first run 2026-10-22).
# Press "Run tests" and it walks every page by itself, changing what omxplorer changes (a cell name, tabs, a selected
# cell, dialogs). The Mac host records a picture and a dump of the views after each change (App.records(), the Debug
# menu; mojoui/hosts/mac_report.mojo) into ~/Desktop/omxcode-report-maccheck/: zip that folder and send it.
# Each page copies a part of omxplorer that looked wrong on the Mac: the grid inside a Board, the side column, the
# inspector, the toolbar, the cell name and the bottom tabs, the Report's chart.

from mojoui.view import (View, Text, Button, TextField, TextArea, Toggle, Dropdown, Slider, Segmented, Radio, DatePicker,
                         ProgressBar, Icon, Tabs, Canvas, Board, VStack, HStack, Card, Spacer, Divider, Grid, Scroll, TITLE,
                         HEADLINE, CAPTION, PROMINENT, SUBTLE, ICON_ONLY, DESTRUCTIVE, START, CENTER, END, STRETCH,
                         TONE_ACCENT, TONE_GOOD, NO_MSG, SECONDARY)
from mojoui.menus import ContextMenu, Item, Separator
from mojoui.overlays import Dialog, Toast, Popover, Checkbox
from mojoui.sheetchrome import Tool, Toolbar, StatusBar, Tab, BottomTabs, FormulaBar
from mojoui.datagrid import DataGrid, GridSource
from mojoui.chartview import ChartView
from mojoui.app import App, Event
from mojoui.canvas import Surface
from mojoui.draw import rect
from mojoui.text import Font
from mojoui.theme import Palette, Theme
from themes.liquid import liquid

comptime PAGE = 1  # the page picker (event.number)
comptime RUN = 2
comptime TICK = 3  # the progress canvas's frames while the tests run
comptime TAP = 4  # controls that only show themselves
comptime GRID = 5  # the grid's gestures
comptime TAB = 10  # bottom tab k sends TAB + k
comptime TOP_TAB = 20
comptime DIALOG_OPEN = 21
comptime DIALOG_CLOSE = 22
comptime POP_OPEN = 23
comptime POP_CLOSE = 24
comptime TOAST_OPEN = 25
comptime TOAST_CLOSE = 26
comptime MENU_CLOSE = 27
comptime CHECK = 28
comptime SWITCH = 29

comptime TICKER = 20  # canvas ids
comptime GRID_C = 10
comptime CHART_C = 11

comptime PAGES: List[String] = ["Controls", "Icons", "Layout", "Canvas", "Grid", "Text", "Overlays"]
comptime N_STEPS = 14  # N_STEPS
comptime STEP_US = 1_600_000  # one test step every 1.6 s: time for AppKit to lay out and the report to take its picture

# every icon omxplorer asks for (and the app's own mark)
comptime ICONS: List[String] = ["align-center", "align-left", "align-right", "bold", "chart-bar", "check", "clear-format", "close", "copy",
                                "currency", "decimals-less", "decimals-more", "file", "fill", "filter-off", "format", "formula", "gear", "grid",
                                "import", "italic", "open", "percent", "pivot", "plus", "rename", "row-plus", "sample", "save", "settings",
                                "sheet", "sort", "strikethrough", "table", "text-colour", "underline", "undo", "app-logo"]

# what Run tests does, one line per step (the status bar shows it; the report's file names follow the changes)
comptime STEPS: List[String] = ["Controls page", "Icons page", "Layout page", "Canvas page", "Grid page", "Grid: select a cell",
                                "Text page: cell name 'freight 4'", "Text: cell name 'revenue 2', second tabs", "Text: a long cell name, first tabs",
                                "Overlays page: open a dialog", "Overlays: close it, open a popover", "Overlays: close it, show a toast",
                                "Overlays: a context menu", "Done"]


struct Orders(Copyable, Movable, GridSource):
    """1,000 made-up orders: enough rows to scroll, the same every run."""

    var names: List[String]

    def __init__(out self):
        self.names = ["region", "product", "carrier", "units", "revenue"]

    def grid_rows(self) -> Int:
        return 1000

    def grid_alive(self, row: Int) -> Bool:
        return True

    def grid_columns(self) -> Int:
        return 5

    def grid_name(self, c: Int) -> String:
        return self.names[c]

    def grid_numeric(self, c: Int) -> Bool:
        return c >= 3

    def grid_editable(self, c: Int) -> Bool:
        return True

    def grid_text(self, c: Int, row: Int) -> String:
        var regions: List[String] = ["North", "South", "East", "West"]
        var products: List[String] = ["Widget", "Gadget", "Gizmo", "Doohickey", "Thing"]
        var carriers: List[String] = ["UPS", "FedEx", "DHL"]
        if c == 0:
            return regions[row % 4]
        if c == 1:
            return products[(row * 7) % 5]
        if c == 2:
            return carriers[(row * 3) % 3]
        if c == 3:
            return String(1 + (row * 13) % 40)
        return String(48 + (row * 37) % 400) + ".00"

    def grid_type_width(self, c: Int) -> Float64:
        return 110.0 if c < 3 else 90.0

    def grid_badge(self, c: Int) -> String:
        return "Aa" if c < 3 else ("#" if c == 3 else "0.0")

    def grid_edited(self, c: Int, row: Int) -> Bool:
        return False


struct Main(App):
    var look: Theme
    var pal: Palette
    var font: Font
    var page: Int
    var step: Int  # the test step running (-1: none)
    var waited: Int  # microseconds since the last step
    var version: Int
    var cell: String  # the formula bar's cell name (the Mac drew new text over old)
    var tab: Int  # bottom tabs
    var top_tab: Int
    var checked: Bool
    var switched: Bool
    var dialog_open: Bool
    var pop_open: Bool
    var toast: String
    var ctx: Bool
    var grid: DataGrid
    var orders: Orders
    var sizes: List[String]  # what each canvas was given, as the app saw it ("id: w x h pt")
    var last: String

    def __init__(out self):
        self.look = liquid()
        self.pal = self.look.palette.copy()
        self.font = Font()
        self.page = 0
        self.step = -1
        self.waited = 0
        self.version = 1
        self.cell = "region 1"
        self.tab = 0
        self.top_tab = 0
        self.checked = True
        self.switched = False
        self.dialog_open = False
        self.pop_open = False
        self.toast = ""
        self.ctx = False
        self.grid = DataGrid()
        self.orders = Orders()
        self.grid.prepare(self.orders, self.font, self.pal)
        self.sizes = List[String]()
        self.last = "Ready: press Run tests"

    def title(self) -> String:
        return "maccheck"

    def records(self) -> Bool:
        return True

    def window_size(self) -> Tuple[Int, Int]:
        return (1280, 820)

    def theme(self) -> Theme:
        return self.look.copy()

    def logo(self) -> String:
        return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="24" height="24"><circle cx="42" cy="42" r="25" fill="none" stroke="#4f46e5" stroke-width="9"/><line x1="60" y1="60" x2="80" y2="80" stroke="#4f46e5" stroke-width="12" stroke-linecap="round"/></svg>'

    def run_step(mut self):
        """Test step `step`: what it changes is what omxplorer changes on the same kind of screen."""
        var s = self.step
        self.dialog_open = False
        self.pop_open = False
        self.ctx = False
        if s <= 4:
            self.page = s
        elif s == 5:
            self.grid.cur_row = 1
            self.grid.cur_col = 4
            self.grid.version += 1
        elif s == 6:
            self.page = 5
            self.cell = "freight 4"
        elif s == 7:
            self.cell = "revenue 2"
            self.tab = 1
            self.top_tab = 1
        elif s == 8:
            self.cell = "a much longer cell name 1000"
            self.tab = 0
            self.top_tab = 0
        elif s == 9:
            self.page = 6
            self.dialog_open = True
        elif s == 10:
            self.pop_open = True
        elif s == 11:
            self.toast = "Saved maccheck.omx"
        elif s == 12:
            self.toast = ""
            self.page = 4  # (the context menu opens on the grid)
            self.ctx = True
        self.last = "Step " + String(s + 1) + " of " + String(N_STEPS) + ": " + materialize[STEPS]()[s]
        if s == N_STEPS - 1:
            self.step = -1
            self.page = 0
            self.last = "Done: zip Desktop/omxcode-report-maccheck and send it"
        self.version += 1

    def update(mut self, event: Event):
        var m = event.message
        if m == PAGE:
            self.page = event.number
        elif m == RUN:
            self.step = 0
            self.waited = 0
            self.run_step()
        elif m == TICK:
            if self.step >= 0:
                self.waited += event.number
                if self.waited >= STEP_US:
                    self.waited = 0
                    self.step += 1
                    self.run_step()
        elif m >= TAB and m < TAB + 2:
            self.tab = m - TAB
        elif m == TOP_TAB:
            self.top_tab = event.number
        elif m == CHECK:
            self.checked = event.number == 1
        elif m == SWITCH:
            self.switched = event.number == 1
        elif m == DIALOG_OPEN or m == DIALOG_CLOSE:
            self.dialog_open = m == DIALOG_OPEN
        elif m == POP_OPEN or m == POP_CLOSE:
            self.pop_open = m == POP_OPEN
        elif m == TOAST_OPEN:
            self.toast = "Saved maccheck.omx"
        elif m == TOAST_CLOSE:
            self.toast = ""
        elif m == MENU_CLOSE:
            self.ctx = False
        elif m == GRID:
            if event.number == SECONDARY:
                self.ctx = True
        elif m == TAP:
            self.last = "Tapped " + event.text
        self.version += 1

    # ---------- drawing ----------

    def draw(mut self, canvas: Int, mut s: Surface):
        ref p = self.pal
        var w = s.points_width()
        var h = s.points_height()
        var k = s.scale
        var said = String(canvas) + ": " + String(Int(w)) + " x " + String(Int(h)) + " pt"
        var found = False
        for i in range(len(self.sizes)):
            if self.sizes[i].startswith(String(canvas) + ":"):
                self.sizes[i] = said
                found = True
        if not found:
            self.sizes.append(said)
        if canvas == GRID_C:
            self.grid.draw(s, self.orders, self.font, p)
            return
        if canvas == CHART_C:
            var labels: List[String] = ["UPS", "FedEx", "DHL", "USPS"]
            var values: List[Float64] = [41200.0, 33500.0, 18200.0, 7300.0]
            var cv = ChartView("Sum of revenue by carrier", labels^, values^, "revenue", True)
            cv.draw(s, self.font, p)
            return
        if canvas == TICKER:  # how far the tests are
            s.fill(p.card)
            if self.step >= 0:
                var done = (Float64(self.step) + Float64(self.waited) / Float64(STEP_US)) / Float64(N_STEPS - 1)
                rect(s, 0, 0, Float64(s.width) * min(done, 1.0), Float64(s.height), p.accent)
            return
        var colours: List[UInt32] = [p.accent_wash, p.raised, p.card, p.accent_wash, p.raised]
        s.fill(colours[canvas % 5])
        rect(s, 0, 0, Float64(s.width), 3 * k, p.accent)  # a bar along the top: the canvas starts here
        self.font.draw(s, "canvas " + said, 12 * k, 28 * k, 15 * k, p.ink, p.medium)
        self.font.draw(s, "if you can read this, it drew", 12 * k, 50 * k, 12 * k, p.ink2, p.regular)

    # ---------- pages ----------

    def controls_page(self) -> View:
        var kinds: List[String] = ["Small", "Medium", "Large"]
        var left = VStack(Text("Text styles", HEADLINE), Text("A title", TITLE), Text("A headline", HEADLINE), Text("Body text, the default"),
                          Text("A caption", CAPTION), Text("Accent tone", CAPTION).tone(TONE_ACCENT), Text("Good tone", CAPTION).tone(TONE_GOOD),
                          Divider().fill(), Text("Buttons", HEADLINE),
                          HStack(Button("Plain", TAP), Button("Prominent", TAP, PROMINENT), Button("Subtle", TAP, SUBTLE), Button("Delete", TAP, DESTRUCTIVE), spacing=8),
                          HStack(Button("With icon", TAP, icon="save"), Button("Subtle icon", TAP, SUBTLE, icon="grid"), Button("Close", TAP, ICON_ONLY, icon="close"), spacing=8),
                          spacing=10).align(START)
        var right = VStack(Text("Inputs", HEADLINE), TextField("", placeholder="A text field").width(320), TextArea("A text area\nwith two lines", height=70).width(320),
                           Toggle("A switch", self.switched, SWITCH), Checkbox("A checkbox", self.checked, CHECK), Dropdown(kinds, 1, TAP),
                           Slider(40, TAP).width(320), Segmented(kinds, 0, TAP), Radio(kinds, 2, TAP), DatePicker("2026-10-22", TAP),
                           ProgressBar(60).width(320), spacing=10).align(START)
        return HStack(left^, right^, spacing=48).align(START)

    def icons_page(self) -> View:
        var left: List[Tool] = [Tool("Save", "save", TAP, False, "Save"), Tool("Undo", "undo", TAP, False, "Undo")]
        var middle: List[Tool] = [Tool("Add row", "row-plus", TAP, False, ""), Tool("Formula", "formula", TAP, False, ""), Tool("Sort", "sort", TAP, False, ""),
                                  Tool("Pivot", "pivot", TAP, False, ""), Tool("Chart", "chart-bar", TAP, False, "")]
        var right: List[Tool] = [Tool("Format", "format", TAP, True, "")]
        var font: List[Tool] = [Tool("Bold", "bold", TAP, True, ""), Tool("Italic", "italic", TAP, False, ""), Tool("Underline", "underline", TAP, False, ""),
                                Tool("Strikethrough", "strikethrough", TAP, False, "")]
        var align: List[Tool] = [Tool("Left", "align-left", TAP, False, ""), Tool("Centre", "align-center", TAP, False, ""), Tool("Right", "align-right", TAP, False, "")]
        var toggles: List[List[Tool]] = [font^, align^]
        var cells = List[View]()
        for name in materialize[ICONS]():
            cells.append(VStack(Icon(name, 20), Text(name, CAPTION), spacing=4).align(CENTER).width(110))
        return VStack(Text("omxplorer's toolbar (inline, as the sheet has it)", HEADLINE), Toolbar(left, middle, right, toggles=toggles, inline=True).fill(),
                      Text("The same tools, icon over label", HEADLINE), Toolbar(left, middle, right).fill(),
                      Text("Every icon omxplorer uses: a '?' or an empty box is a missing one", HEADLINE), Grid(cells^, 8, spacing=10),
                      spacing=12).fill().align(START)

    def layout_page(self) -> View:
        var side = Card(VStack(Button("Start", TAP, SUBTLE, icon="file").fill().align(START), Button("New blank sheet", TAP, SUBTLE, icon="grid").fill().align(START),
                               Button("Open file…", TAP, SUBTLE, icon="open").fill().align(START), Divider().fill(),
                               Button("Settings…", TAP, SUBTLE, icon="settings").fill().align(START), Spacer(),
                               Card(Text("● CPU", CAPTION).tone(TONE_GOOD), Text("Parquet files bigger than memory open too: streamed from disk, a slice at a time.", CAPTION).max_width(220), spacing=4),
                               spacing=6).fill().grow().align(STRETCH), spacing=0).width(260).height(420).tag("side")
        var stats = Grid([Text("Mean", CAPTION), Text("Median", CAPTION), Text("114.01"), Text("90.00"), Text("Empty", CAPTION), Text("Distinct", CAPTION), Text("0"), Text("20")], 2, spacing=8)
        var inspector = Card(VStack(Segmented(["Table", "Cell"], 1, TAP).fill(), Text("COLUMN", CAPTION), Text("revenue · Decimal", HEADLINE),
                                    Text("A format applies to the whole column: the cells and its charts.", CAPTION).max_width(260), Divider().fill(),
                                    HStack(Text("Decimals"), Spacer(), Text("2"), spacing=8).fill(), HStack(Text("Thousands separator"), Spacer(), Checkbox("", True, TAP), spacing=8).fill(),
                                    Divider().fill(), Text("COLUMN STATS", CAPTION), stats^, spacing=10).fill().align(START), spacing=0).width(300).height(420).tag("inspector")
        var rows = List[View]()
        for k in range(30):
            rows.append(HStack(Text("Row " + String(k + 1)), Spacer(), Text(String(k * 37) + ".00", CAPTION), spacing=8).fill())
        var middle = VStack(Text("Start: side column (buttons left-aligned), CPU card (text wraps)", CAPTION), Text("Inspector: no gap under Table/Cell; stats aligned left", CAPTION),
                            HStack(Text("Left"), Spacer(), Text("right"), spacing=8).fill(), HStack(Spacer(), Text("Centred"), Spacer(), spacing=8).fill(),
                            Text("A scroll of 30 rows:", CAPTION), Scroll(VStack(rows^, spacing=6).fill(), height=220).fill(), spacing=10).width(380).align(START)
        return HStack(side^, middle^, inspector^, spacing=24).align(START)

    def canvas_page(self) -> View:
        var board = Board([VStack(Text("D · inside a Board, as omxplorer's grid", CAPTION), Canvas(4, self.version).fill().height(100).tag("canvas-board"), spacing=6)
                           .at(0, 0).width(360).height(130)], 380, 140).width(380).height(140)
        return VStack(HStack(VStack(Text("A · fixed size", CAPTION), Canvas(1, self.version).width(260).height(110).tag("canvas-fixed"), spacing=6).align(START),
                             VStack(Text("B · fills a fixed-width column", CAPTION), Canvas(2, self.version).fill().height(110).tag("canvas-fill"), spacing=6).width(300).align(STRETCH),
                             VStack(Text("C · in a card", CAPTION), Card(Canvas(3, self.version).fill().height(110).tag("canvas-card"), spacing=0).width(300), spacing=6).align(START),
                             spacing=24).align(START),
                      board^,
                      Text("E · a chart in a card, as the Report has it", CAPTION),
                      Card(Text("Sum of revenue by carrier", HEADLINE), Canvas(CHART_C, self.version).fill().height(220).tag("canvas-chart"), spacing=8).width(620),
                      Text("What the app was given: " + (", ".join(self.sizes) if len(self.sizes) > 0 else "nothing yet"), CAPTION),
                      spacing=12).align(START)

    def grid_page(self) -> View:
        var head = HStack(Text("orders", HEADLINE), Text("1,000 rows", CAPTION).tone(TONE_ACCENT), Spacer(), spacing=12).fill().align(CENTER).height(32)
        var table = VStack(head^, Canvas(GRID_C, self.version + self.grid.version, on_gesture=GRID, keys=True).fill().height(380).tag("grid"), spacing=8).at(0, 0).width(760).height(420).tag("table")
        var board = Board([table^], 780, 440).fill().height(450)
        return VStack(Text("omxplorer's grid exactly as the sheet places it: a canvas in a VStack, on a Board. Right-click it for the context menu.", CAPTION), board^, spacing=8).fill().align(START)

    def text_page(self) -> View:
        var tabs: List[Tab] = [Tab("orders", "sheet"), Tab("Report", "chart-bar")]
        var sections: List[String] = ["Sheet", "Report", "Notes"]
        return VStack(Text("The formula bar's cell name changes during the tests: old text must not stay under the new.", CAPTION),
                      FormulaBar(self.cell, "240.00", TAP, TAP).fill(),
                      Text("A label that changes: " + self.cell, HEADLINE),
                      Tabs(sections, self.top_tab, TOP_TAB),
                      Text("Bottom tabs (they drew twice on the Mac):", CAPTION),
                      BottomTabs(tabs, self.tab, TAB).height(30),
                      spacing=12).fill().align(START)

    def overlays_page(self) -> View:
        return VStack(Text("Dialogs and popovers are windows of their own: the report notes them, its pictures don't show them.", CAPTION),
                      HStack(Button("Open dialog", DIALOG_OPEN), Button("Show popover", POP_OPEN).tag("pop-anchor"), Button("Show toast", TOAST_OPEN), spacing=10),
                      Text("Right-click the grid on the Grid page for a context menu.", CAPTION), spacing=12).align(START)

    def overlays(self) -> List[View]:
        var out = List[View]()
        if self.dialog_open:
            out.append(Dialog("A dialog", VStack(Text("It should sit over the window, with a Done button."), HStack(Spacer(), Button("Done", DIALOG_CLOSE, PROMINENT), spacing=8).fill(), spacing=12).align(START), on_close=DIALOG_CLOSE, width=420))
        if self.pop_open:
            out.append(Popover("pop-anchor", "A popover", Text("It points at its button.", CAPTION), on_close=POP_CLOSE))
        if self.toast != "":
            out.append(Toast(self.toast, "Undo", TOAST_CLOSE, on_close=TOAST_CLOSE))
        return out^

    def view(self) -> View:
        var pages = List[View]()
        var body: View
        if self.page == 0:
            body = self.controls_page()
        elif self.page == 1:
            body = self.icons_page()
        elif self.page == 2:
            body = self.layout_page()
        elif self.page == 3:
            body = self.canvas_page()
        elif self.page == 4:
            body = self.grid_page()
        elif self.page == 5:
            body = self.text_page()
        else:
            body = self.overlays_page()
        var top = HStack(Icon("app-logo", 18), Text("maccheck", HEADLINE), Segmented(materialize[PAGES](), self.page, PAGE), Spacer(),
                         Button("Run tests", RUN, PROMINENT, icon="sample"), spacing=12).fill().align(CENTER).padding(8, 20)
        pages.append(top^)
        pages.append(Canvas(TICKER, self.version, on_frame=TICK if self.step >= 0 else NO_MSG).fill().height(4).tag("progress"))
        pages.append(body^.padding(12, 20))
        pages.append(Spacer())
        pages.append(StatusBar([self.last, "page " + materialize[PAGES]()[self.page]], "maccheck · omxcode"))
        if self.ctx:
            pages.append(ContextMenu("grid", 200, 120, [Item("Sort A→Z", MENU_CLOSE, icon="sort"), Item("Sort Z→A", MENU_CLOSE), Separator(), Item("Delete column", MENU_CLOSE, danger=True)], on_close=MENU_CLOSE))
        for o in self.overlays():
            pages.append(o.copy())
        return VStack(pages^, spacing=6).fill().grow()
