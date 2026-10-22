# kit: every omxcode component on one screen, on every host (D-157): the proving ground for the menu bar, menus and a
# context menu, tool buttons with tooltips, a dialog, a toast, a popover, checkboxes, a Board with an Overlay island,
# a canvas with the keyboard, and the three skins. On Linux and the web it's driven by scripts/check; on iPad and Mac
# it builds, bundles and signs here and runs on the owner's devices.
from mojoui.view import (View, Text, Button, TextField, Canvas, Board, Overlay, VStack, HStack, Card, Spacer, Divider,
                         Dropdown, Segmented, Radio, Icon, HEADLINE, CAPTION, TITLE, PROMINENT, SUBTLE, ICON_ONLY, START, CENTER, END,
                         STRETCH, TONE_ACCENT, TONE_GOOD, TONE_WARN, NO_MSG, TAP, SECONDARY, KEY, DOUBLE)
from mojoui.menus import MenuBar, Menu, Item, Separator, Submenu, ContextMenu
from mojoui.overlays import Dialog, Toast, Popover, Checkbox
from mojoui.sheetchrome import Tool, Toolbar, StatusBar
from mojoui.app import App, Event
from mojoui.canvas import Surface, rgba
from mojoui.text import Font, CENTRE
from mojoui.theme import Palette, Theme
from themes.skins import ledger, graphite, blueprint
from mojoui.draw import rect, line

comptime LEDGER = 3  # the three skins (themes/skins.mojo)
comptime GRAPHITE = 4
comptime BLUEPRINT = 5


def skin_theme(skin: Int) -> Theme:
    return graphite() if skin == GRAPHITE else (blueprint() if skin == BLUEPRINT else ledger())


comptime NEW = 1
comptime SAVE = 2
comptime UNDO = 3
comptime ABOUT = 4
comptime ABOUT_CLOSE = 5
comptime SKIN = 6  # a Segmented or Radio: event.number
comptime SKIN_LEDGER = 7
comptime SKIN_GRAPHITE = 8
comptime SKIN_BLUEPRINT = 9
comptime INSPECTOR = 10
comptime GRID_LINES = 11
comptime SNAP = 12
comptime AGGREGATE = 13
comptime DIALOG_OPEN = 14
comptime DIALOG_CLOSE = 15
comptime POP_OPEN = 16
comptime POP_CLOSE = 17
comptime TOAST_OPEN = 18
comptime TOAST_CLOSE = 19
comptime UNDO_SAVE = 20
comptime CANVAS = 21
comptime MENU_CLOSE = 22
comptime SORT_AZ = 23
comptime SORT_ZA = 24
comptime DELETE = 25
comptime MOVE = 26
comptime RESIZE = 27
comptime SKINS: List[String] = ["Ledger", "Graphite", "Blueprint"]


struct Main(App):
    var skin: Int
    var pal: Palette
    var look: Theme  # the skin's theme
    var font: Font
    var last: String  # the last thing that happened (the status bar)
    var inspector: Bool
    var grid_lines: Bool
    var snap: Bool
    var aggregate: Int
    var dialog_open: Bool
    var about_open: Bool
    var pop_open: Bool
    var toast: String
    var ctx_x: Int  # a context menu open at (x, y) on the canvas (-1: none)
    var ctx_y: Int
    var note_x: Int  # the note card's place on the Board
    var note_y: Int
    var version: Int

    def __init__(out self):
        self.skin = LEDGER
        self.look = skin_theme(LEDGER)
        self.pal = self.look.palette.copy()
        self.font = Font()
        self.last = "Ready"
        self.inspector = True
        self.grid_lines = True
        self.snap = False
        self.aggregate = 0
        self.dialog_open = False
        self.about_open = False
        self.pop_open = False
        self.toast = ""
        self.ctx_x = -1
        self.ctx_y = -1
        self.note_x = 480
        self.note_y = 0
        self.version = 1

    def title(self) -> String:
        return "kit"

    def window_size(self) -> Tuple[Int, Int]:
        return (1280, 800)

    def theme(self) -> Theme:
        return self.look.copy()

    def set_skin(mut self, skin: Int):
        self.skin = skin
        self.look = skin_theme(skin)
        self.pal = self.look.palette.copy()
        self.last = "Skin: " + self.look.id
        self.version += 1

    def update(mut self, event: Event):
        var m = event.message
        if m == SAVE:
            self.last = "Saved kit.omx"
            self.toast = "Saved kit.omx"
        elif m == UNDO_SAVE:
            self.last = "Save undone"
            self.toast = ""
        elif m == TOAST_OPEN:
            self.toast = "Hello from the island"
        elif m == TOAST_CLOSE:
            self.toast = ""
        elif m == NEW:
            self.last = "New sheet"
        elif m == UNDO:
            self.last = "Undone"
        elif m == ABOUT or m == ABOUT_CLOSE:
            self.about_open = m == ABOUT
        elif m == DIALOG_OPEN or m == DIALOG_CLOSE:
            self.dialog_open = m == DIALOG_OPEN
        elif m == POP_OPEN or m == POP_CLOSE:
            self.pop_open = m == POP_OPEN and not self.pop_open
        elif m == SKIN:
            self.set_skin(LEDGER if event.number == 0 else (GRAPHITE if event.number == 1 else BLUEPRINT))
        elif m == SKIN_LEDGER or m == SKIN_GRAPHITE or m == SKIN_BLUEPRINT:
            self.set_skin(LEDGER if m == SKIN_LEDGER else (GRAPHITE if m == SKIN_GRAPHITE else BLUEPRINT))
        elif m == INSPECTOR:
            self.inspector = not self.inspector
        elif m == GRID_LINES:
            self.grid_lines = event.number == 1
            self.last = "Grid lines " + ("on" if self.grid_lines else "off")
        elif m == SNAP:
            self.snap = event.number == 1
        elif m == AGGREGATE:
            self.aggregate = event.number
        elif m == CANVAS:
            if event.number == SECONDARY:
                self.ctx_x = Int(event.x)
                self.ctx_y = Int(event.y)
            elif event.number == TAP:
                self.last = "Tapped the canvas at " + String(Int(event.x)) + ", " + String(Int(event.y))
            elif event.number == DOUBLE:
                self.last = "Double-tapped the canvas"
            elif event.number == KEY:
                self.last = "Key " + event.text
        elif m == MENU_CLOSE:
            self.ctx_x = -1
        elif m == SORT_AZ or m == SORT_ZA:
            self.ctx_x = -1
            self.last = "Sorted A→Z" if m == SORT_AZ else "Sorted Z→A"
        elif m == DELETE:
            self.ctx_x = -1
            self.last = "Deleted"
        elif m == MOVE:
            if event.number == 1:
                self.note_x = max(0, self.note_x + Int(event.dx))
                self.note_y = max(0, self.note_y + Int(event.dy))
                self.last = "Note moved to " + String(self.note_x) + ", " + String(self.note_y)
        self.version += 1

    def draw(mut self, canvas: Int, mut s: Surface):
        """The canvas: a small sheet drawn with the baked fonts and the skin's colours."""
        var k = s.scale
        ref p = self.pal
        s.fill(p.card)
        var w = Float64(s.width)
        var h = Float64(s.height)
        rect(s, 0, 0, w, 28 * k, p.raised)
        if self.grid_lines:
            var y = 28 * k
            while y < h:
                line(s, 0, y, w, y, 1, p.line)
                y += 26 * k
            var x = 0.0
            while x < w:
                line(s, x, 0, x, h, 1, p.line)
                x += 110 * k
        rect(s, 110 * k, 54 * k, 110 * k, 26 * k, p.accent_wash)
        rect(s, 110 * k, 54 * k, 110 * k, 26 * k, p.accent)
        rect(s, 112 * k, 56 * k, 106 * k, 22 * k, p.card)
        var names: List[String] = ["region", "revenue", "cost", "margin"]
        for c in range(4):
            self.font.draw(s, names[c], Float64(8 + 110 * c) * k, 19 * k, 12.5 * k, p.ink2, p.medium)
        self.font.draw(s, "Right-click (or long-press) for the column's menu", w / 2, h - 12 * k, 12 * k, p.ink3, p.regular, CENTRE)

    def menu_bar(self) -> View:
        return MenuBar([
            Menu("File", [Item("New", NEW, icon="grid", shortcut="Ctrl+N"), Item("Open…", NO_MSG, icon="open", shortcut="Ctrl+O", disabled=True),
                          Separator(), Item("Save", SAVE, icon="save", shortcut="Ctrl+S")]),
            Menu("Edit", [Item("Undo", UNDO, icon="undo", shortcut="Ctrl+Z"), Item("Redo", NO_MSG, shortcut="Ctrl+Shift+Z", disabled=True)]),
            Menu("View", [Submenu("Skin", [Item("Ledger", SKIN_LEDGER, checked=self.skin == LEDGER), Item("Graphite", SKIN_GRAPHITE, checked=self.skin == GRAPHITE),
                                           Item("Blueprint", SKIN_BLUEPRINT, checked=self.skin == BLUEPRINT)], icon="format"),
                          Separator(), Item("Inspector", INSPECTOR, checked=self.inspector, shortcut="Ctrl+Shift+I")]),
            Menu("Help", [Item("About kit", ABOUT, icon="file")]),
        ]).fill().padding(2, 8).tag("menubar")

    def toolbar(self) -> View:
        var left: List[Tool] = [Tool("Save", "save", SAVE, False, "Save the document (Ctrl+S)"), Tool("Undo", "undo", UNDO, False, "Undo the last edit (Ctrl+Z)")]
        var middle: List[Tool] = [Tool("Chart", "chart-bar", NO_MSG, False, "A chart of the selected column"), Tool("Pivot", "pivot", NO_MSG, False, "A pivot table")]
        var right: List[Tool] = [Tool("Format", "format", INSPECTOR, self.inspector, "Show or hide the inspector (Ctrl+Shift+I)")]
        return Toolbar(left, middle, right)

    def overlays(self) -> List[View]:
        var out = List[View]()
        if self.dialog_open:
            var at = 0 if self.skin == LEDGER else (1 if self.skin == GRAPHITE else 2)
            out.append(Dialog("Settings", VStack(
                Text("Appearance", HEADLINE), Text("The same on every device, whatever the system theme.", CAPTION),
                Radio(materialize[SKINS](), at, SKIN), Divider().fill(),
                Checkbox("Show grid lines", self.grid_lines, GRID_LINES), Checkbox("Snap to grid", self.snap, SNAP),
                HStack(Spacer(), Button("Done", DIALOG_CLOSE, PROMINENT), spacing=10).fill(), spacing=12).align(START), on_close=DIALOG_CLOSE))
        if self.about_open:
            out.append(Dialog("About kit", VStack(Text("kit", TITLE).tone(TONE_ACCENT), Text("every omxcode component, on every host", CAPTION),
                                                   HStack(Spacer(), Button("Done", ABOUT_CLOSE, PROMINENT), spacing=10).fill(), spacing=10).align(START), on_close=ABOUT_CLOSE, width=440))
        if self.pop_open:
            out.append(Popover("popover-button", "Formulas", VStack(Text("margin = revenue - cost", CAPTION), Text("+  −  ×  ÷   min   max", CAPTION), spacing=6).align(START), on_close=POP_CLOSE))
        if self.toast != "":
            out.append(Toast(self.toast, "Undo", UNDO_SAVE, on_close=TOAST_CLOSE))
        return out^

    def view(self) -> View:
        var table = Card(HStack(Text("Orders", HEADLINE), Text("1,000 rows", CAPTION).tone(TONE_ACCENT), Spacer(), spacing=8).fill().align(CENTER).height(36),
                         Canvas(0, self.version, on_gesture=CANVAS, keys=True).fill().height(214).tag("canvas"), spacing=6).at(0, 0).width(460).height(270).tag("table")
        var note = Card(HStack(Text("Note", HEADLINE), Spacer(), Button("Close", NO_MSG, ICON_ONLY, icon="close"), spacing=8).fill().align(CENTER).height(36),
                        Text("Drag me by my title. The island below floats over the board.", CAPTION), spacing=6).at(self.note_x, self.note_y).width(240).height(120).tag("note")
        var board = Board([table^, note^], 760, 320, on_move=MOVE).width(760).height(320)
        var island = HStack(Text("Island", CAPTION), Button("Show toast", TOAST_OPEN, SUBTLE, icon="comment"), spacing=8).align(CENTER).pin(END, END)
        var left = Overlay(board^, island^).width(760).height(320)
        var aggregates: List[String] = ["Sum", "Average", "Count"]
        var panel = List[View]()
        panel.append(Text("INSPECTOR", CAPTION))
        panel.append(Segmented(materialize[SKINS](), 0 if self.skin == LEDGER else (1 if self.skin == GRAPHITE else 2), SKIN).fill())
        panel.append(Checkbox("Show grid lines", self.grid_lines, GRID_LINES))
        panel.append(Checkbox("Snap to grid", self.snap, SNAP))
        panel.append(HStack(Text("Aggregate"), Spacer(), Dropdown(aggregates, self.aggregate, AGGREGATE), spacing=8).fill().align(CENTER))
        panel.append(TextField("", placeholder="A formula").fill())
        panel.append(Divider().fill())
        panel.append(Button("Open dialog", DIALOG_OPEN, icon="gear").tooltip("Settings: the skin and the grid").fill())
        panel.append(Button("Show popover", POP_OPEN, icon="formula").tooltip("What formulas can do").fill().tag("popover-button"))
        panel.append(Button("Delete", DELETE, PROMINENT).fill())
        var right = Card(VStack(panel^, spacing=10).fill().align(STRETCH), spacing=0).width(300)
        var body = HStack(left^, right^, spacing=24).padding(16, 24).align(START) if self.inspector else HStack(left^, spacing=24).padding(16, 24).align(START)
        var parts = List[View]()
        parts.append(self.menu_bar())
        parts.append(self.toolbar().height(64))
        parts.append(body^)
        parts.append(Spacer())
        parts.append(StatusBar([self.last, "Skin " + self.look.id], "kit · omxcode"))
        if self.ctx_x >= 0:
            parts.append(ContextMenu("canvas", self.ctx_x, self.ctx_y, [Item("Sort A→Z", SORT_AZ, icon="sort"), Item("Sort Z→A", SORT_ZA), Separator(),
                                                                       Submenu("Format as", [Item("Number", NO_MSG), Item("Currency", NO_MSG, checked=True)], icon="format"),
                                                                       Separator(), Item("Delete column", DELETE, icon="trash", danger=True)], on_close=MENU_CLOSE))
        for o in self.overlays():
            parts.append(o.copy())
        return VStack(parts^, spacing=6).fill().grow()
