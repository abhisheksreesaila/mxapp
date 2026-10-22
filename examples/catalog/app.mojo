# catalog: one component at a time, centred on a plain surface, in the Liquid light theme: the real framework drawing
# the pictures for the public components page (scripts/catalog.py runs it once per component and crops the shot).
#
#   CATALOG=Button build/catalog/linux/catalog        (any name from NAMES; unset: Button)
#
# Popups open the way they do in an app, from an event the test steps send (scripts/catalog.py): a menu of the bar with
# open:<title>, a context menu with a right click on the canvas, a popover, dialog, toast or alert with a tap on the
# page's button. Clipboard has nothing on screen: its picture is the text it copied, with the real Clipboard node in the
# view.

from mojoui.shared import environment
from mojoui.view import (View, Text, Button, TextField, TextArea, Toggle, Dropdown, Slider, Segmented, Radio, DatePicker,
                         ProgressBar, Image, Icon, Alert, Tabs, NavBar, LazyList, Canvas, Board, Overlay, VStack, HStack,
                         Card, Spacer, Divider, Grid, Scroll, TITLE, HEADLINE, CAPTION, PROMINENT, SUBTLE, ICON_ONLY,
                         DESTRUCTIVE, START, CENTER, END, STRETCH, TONE_ACCENT, TONE_GOOD, NO_MSG, SECONDARY)
from mojoui.menus import MenuBar, Menu, Item, Separator, Submenu, ContextMenu
from mojoui.overlays import Dialog, Toast, Popover, Checkbox, Clipboard
from mojoui.app import App, Event
from mojoui.canvas import Surface
from mojoui.draw import rect, line
from mojoui.text import Font, CENTRE
from mojoui.theme import Palette, Theme
from themes.liquid import liquid

comptime TAP = 1  # every control sends this: the catalog only shows them
comptime CLOSE = 2
comptime BACK = 3
comptime OPEN = 4  # the page's button: opens the popover, dialog, toast or alert
comptime CANVAS = 5  # the canvas's gestures: a right click opens the context menu
comptime ROWS = 1  # the LazyList's id

comptime NAMES: List[String] = [
    "Text", "Button", "VStack", "HStack", "Spacer", "Card", "Scroll", "Grid", "Divider",
    "TextField", "TextArea", "Toggle", "Dropdown", "Slider", "Segmented", "Radio", "DatePicker", "ProgressBar",
    "Image", "Icon", "Alert", "Tabs", "NavBar", "LazyList", "Canvas", "Board", "Overlay",
    "MenuBar", "Menu", "Item", "ContextMenu", "Dialog", "Toast", "Popover", "Checkbox", "Clipboard",
]
comptime REGIONS: List[String] = ["North", "South", "East", "West"]
comptime SALES: List[Int] = [62, 88, 45, 71, 54, 93]


def gradient(w: Int, h: Int) -> List[UInt32]:
    """A teal-to-violet gradient made in plain Mojo (RGBA pixels), for Image."""
    var pixels = List[UInt32](capacity=w * h)
    for y in range(h):
        for x in range(w):
            var t = Float64(x) / Float64(w - 1)
            var r = UInt32(Int(14 + (106 - 14) * t))
            var g = UInt32(Int(124 + (79 - 124) * t) + y // 4)
            var b = UInt32(Int(134 + (214 - 134) * t))
            pixels.append(r | (g << 8) | (b << 16) | (UInt32(255) << 24))
    return pixels^


struct Main(App):
    var name: String
    var pal: Palette
    var font: Font
    var open: Bool  # the popup is showing
    var ctx_x: Int  # where the context menu opened, in the canvas
    var ctx_y: Int

    def __init__(out self):
        self.name = environment("CATALOG", "Button")
        self.pal = liquid().palette.copy()
        self.font = Font()
        self.open = False
        self.ctx_x = 0
        self.ctx_y = 0

    def title(self) -> String:
        return "catalog · " + self.name

    def window_size(self) -> Tuple[Int, Int]:
        if self.name == "Dialog" or self.name == "Alert":
            return (720, 520)
        if self.name == "Board" or self.name == "Overlay" or self.name == "MenuBar" or self.name == "Menu" or self.name == "Item" or self.name == "ContextMenu":
            return (720, 460)
        if self.name == "LazyList" or self.name == "Scroll" or self.name == "Popover" or self.name == "Toast":
            return (640, 440)
        return (560, 360)

    def theme(self) -> Theme:
        return liquid()

    def update(mut self, event: Event):
        if event.message == OPEN:
            self.open = True
        elif event.message == CLOSE:
            self.open = False
        elif event.message == CANVAS and event.number == SECONDARY:
            self.open = True
            self.ctx_x = Int(event.x)
            self.ctx_y = Int(event.y)

    def row(self, list_id: Int, index: Int) -> String:
        return "Order " + String(1024 + index) + " · " + materialize[REGIONS]()[index % 4] + " · $" + String(120 + (index * 37) % 900)

    def draw(mut self, canvas: Int, mut s: Surface):
        """A small bar chart in the theme's series colours (Canvas, and the base of Board and Overlay)."""
        ref p = self.pal
        var k = s.scale
        s.fill(p.card)
        var w = Float64(s.width)
        var h = Float64(s.height)
        var base = h - 26 * k
        line(s, 12 * k, base, w - 12 * k, base, 1, p.line)
        var sales = materialize[SALES]()
        var n = len(sales)
        var slot = (w - 24 * k) / Float64(n)
        for i in range(n):
            var bh = (base - 14 * k) * Float64(sales[i]) / 100.0
            rect(s, 12 * k + Float64(i) * slot + slot * 0.18, base - bh, slot * 0.64, bh, p.data(0), 3 * k)
            var months: List[String] = ["May", "Jun", "Jul", "Aug", "Sep", "Oct"]
            self.font.draw(s, months[i], 12 * k + (Float64(i) + 0.5) * slot, h - 8 * k, 11 * k, p.ink3, p.regular, CENTRE)

    def chart(self, tag: String) -> View:
        return Canvas(0, 1, on_gesture=CANVAS).width(300).height(160).tag(tag)

    def show(self) -> View:
        """The component itself, with realistic content."""
        var n = self.name
        if n == "Text":
            return VStack(Text("Quarterly revenue", TITLE), Text("North region", HEADLINE), Text("Up 12% on last quarter, led by the new stores.", CAPTION), spacing=6).align(START)
        if n == "Button":
            return HStack(Button("Cancel", TAP, SUBTLE), Button("Preview", TAP), Button("Save", TAP, PROMINENT), spacing=10)
        if n == "VStack":
            return VStack(Card(Text("Revenue")).width(220), Card(Text("Cost")).width(220), Card(Text("Margin")).width(220), spacing=8)
        if n == "HStack":
            return HStack(Card(Text("North")), Card(Text("South")), Card(Text("East")), spacing=8)
        if n == "Spacer":
            return HStack(Button("Cancel", TAP, SUBTLE), Spacer(), Button("Save", TAP, PROMINENT), spacing=8).width(380)
        if n == "Card":
            return Card(HStack(Text("Orders", HEADLINE), Spacer(), Text("1,000 rows", CAPTION).tone(TONE_ACCENT), spacing=8).fill().align(CENTER),
                        Text("Imported from orders.parquet a minute ago.", CAPTION), spacing=8).width(340)
        if n == "Scroll":
            var rows = List[View]()
            for i in range(14):
                rows.append(HStack(Text("Order " + String(1024 + i)), Spacer(), Text("$" + String(120 + (i * 37) % 900), CAPTION), spacing=8).fill())
            return Card(Scroll(VStack(rows^, spacing=10).fill(), height=200).fill(), spacing=0).width(320)
        if n == "Grid":
            var cells = List[View]()
            var labels: List[String] = ["Revenue", "Cost", "Margin", "Orders", "Returns", "Stores"]
            var values: List[String] = ["$1.24M", "$810K", "34.7%", "1,000", "2.1%", "18"]
            for i in range(6):
                cells.append(Card(Text(labels[i], CAPTION), Text(values[i], HEADLINE), spacing=4).width(120))
            return Grid(cells^, 3, spacing=10)
        if n == "Divider":
            return VStack(Text("Revenue  $1.24M"), Divider().fill(), Text("Cost  $810K"), spacing=10).width(260).align(START)
        if n == "TextField":
            return VStack(Text("Your name", CAPTION), TextField("Ada Lovelace", "Your name", on_change=TAP).width(300), spacing=6).align(START)
        if n == "TextArea":
            return TextArea("Call the North stores about the October returns.\nCheck the new pricing on Monday.", "Notes", on_change=TAP, height=110).width(340).height(110)
        if n == "Toggle":
            return VStack(Toggle("Notifications", True, TAP), Toggle("Weekly summary", False, TAP), spacing=10).width(280).align(STRETCH)
        if n == "Dropdown":
            return HStack(Text("Region"), Dropdown(materialize[REGIONS](), 0, TAP), spacing=12).align(CENTER)
        if n == "Slider":
            return VStack(Text("Zoom 70%", CAPTION), Slider(70, TAP).width(300), spacing=6).align(START)
        if n == "Segmented":
            return Segmented(["Day", "Week", "Month"], 1, TAP)
        if n == "Radio":
            return Radio(["Small", "Medium", "Large"], 1, TAP)
        if n == "DatePicker":
            return DatePicker("2026-10-22", TAP)
        if n == "ProgressBar":
            return VStack(Text("Importing orders.parquet · 62%", CAPTION), ProgressBar(62).width(320), spacing=8).align(START)
        if n == "Image":
            return Image(gradient(240, 96), 240, 96)
        if n == "Icon":
            return HStack(Icon("star"), Icon("search"), Icon("gear"), Icon("chart-bar"), Icon("table"), Icon("calendar"), spacing=18)
        if n == "Alert":
            var page = VStack(Text("Report", HEADLINE), Button("Close report", OPEN), spacing=10)
            if self.open:
                page = VStack(Text("Report", HEADLINE), Button("Close report", OPEN), Alert("Discard changes?", "The report's last 3 edits haven't been saved.", ["Cancel", "Discard"], CLOSE), spacing=10)
            return page^
        if n == "Tabs":
            return Tabs(["Overview", "Rows", "Charts"], 0, TAP)
        if n == "NavBar":
            return NavBar("Order 1024", on_back=BACK).width(360)
        if n == "LazyList":
            return LazyList(10000, ROWS, on_tap=TAP, height=240, row_height=40).width(340).height(240)
        if n == "Canvas":
            return self.chart("canvas")
        if n == "Board":
            var a = Card(Text("Sales by month", HEADLINE), Canvas(0, 1).fill().height(120), spacing=6).at(0, 0).width(300).height(180)
            var b = Card(Text("Note", HEADLINE), Text("Drag a card by its title.", CAPTION), spacing=6).at(320, 30).width(200).height(110)
            return Board([a^, b^], 540, 200, on_move=TAP).width(540).height(200)
        if n == "Overlay":
            var island = HStack(Text("Island", CAPTION), Button("Share", TAP, SUBTLE, icon="share"), spacing=8).align(CENTER).pin(END, END)
            return Overlay(Canvas(0, 1).width(440).height(220), island^).width(440).height(220)
        if n == "MenuBar" or n == "Menu" or n == "Item":
            return VStack(self.menu_bar(), Spacer().height(220), spacing=0).width(520)
        if n == "ContextMenu":
            return VStack(Text("Right-click a column", CAPTION), self.chart("canvas"), spacing=6)
        if n == "Dialog":
            return VStack(Text("Orders", HEADLINE), Text("3 rows selected", CAPTION), Button("Delete 3 rows", OPEN, DESTRUCTIVE), spacing=8)
        if n == "Toast":
            return VStack(Text("Report", HEADLINE), Button("Save", OPEN, PROMINENT, icon="save"), spacing=10)
        if n == "Popover":
            return Button("Formulas", OPEN, icon="formula").tag("anchor")
        if n == "Checkbox":
            return VStack(Checkbox("Show grid lines", True, TAP), Checkbox("Snap to grid", False, TAP), spacing=10).align(START)
        if n == "Clipboard":
            return VStack(Button("Copy", TAP, icon="save"), Text("Copied “North  $1.24M” to the clipboard", CAPTION), Clipboard("North\t$1.24M", 1), spacing=8)
        return Text("No component called " + n)

    def menu_bar(self) -> View:
        return MenuBar([
            Menu("File", [Item("New", TAP, icon="grid", shortcut="Ctrl+N"), Item("Open…", TAP, icon="open", shortcut="Ctrl+O"),
                          Separator(), Item("Save", TAP, icon="save", shortcut="Ctrl+S"), Item("Export…", TAP, icon="export", disabled=True)]),
            Menu("Edit", [Item("Undo", TAP, icon="undo", shortcut="Ctrl+Z"), Item("Redo", TAP, shortcut="Ctrl+Shift+Z", disabled=True)]),
            Menu("View", [Item("Grid lines", TAP, checked=True), Item("Inspector", TAP, checked=False, shortcut="Ctrl+Shift+I"),
                          Submenu("Zoom", [Item("100%", TAP, checked=True), Item("150%", TAP)], icon="zoom"),
                          Separator(), Item("Clear all filters", TAP, icon="filter-off", danger=True)]),
            Menu("Help", [Item("About", TAP, icon="file")]),
        ]).fill().padding(2, 8).tag("menubar")

    def popups(self) -> List[View]:
        var out = List[View]()
        var n = self.name
        if not self.open:
            return out^
        if n == "ContextMenu":
            out.append(ContextMenu("canvas", self.ctx_x, self.ctx_y, [Item("Sort A→Z", TAP, icon="sort"), Item("Sort Z→A", TAP), Separator(),
                                                       Submenu("Format as", [Item("Number", TAP), Item("Currency", TAP, checked=True)], icon="format"),
                                                       Separator(), Item("Delete column", TAP, icon="trash", danger=True)], on_close=CLOSE))
        elif n == "Dialog":
            out.append(Dialog("Delete 3 rows?", VStack(Text("Rows 12, 18 and 40 of Orders will be removed. Undo brings them back."),
                                                       HStack(Spacer(), Button("Cancel", CLOSE, SUBTLE), Button("Delete", CLOSE, DESTRUCTIVE), spacing=10).fill(),
                                                       spacing=16).align(START), on_close=CLOSE, width=420))
        elif n == "Toast":
            out.append(Toast("Saved report.omx", "Undo", TAP, on_close=CLOSE, seconds=60))
        elif n == "Popover":
            out.append(Popover("anchor", "Formulas", VStack(Text("margin = revenue - cost", CAPTION), Text("+  −  ×  ÷   min   max", CAPTION), spacing=6).align(START), on_close=CLOSE))
        return out^

    def view(self) -> View:
        var parts = List[View]()
        parts.append(VStack(self.show(), spacing=0).align(CENTER).justify(CENTER).fill().grow().padding(32).tag("component"))
        for p in self.popups():
            parts.append(p.copy())
        return VStack(parts^, spacing=0).fill().grow()
