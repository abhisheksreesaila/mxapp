# mojoui.menus: a menu bar, menus and context menus, one model for every host (D-154).
#
#   MenuBar([Menu("File", [Item("Open…", OPEN, icon="open", shortcut="Ctrl+O"), Separator(), Item("Save", SAVE, shortcut="Ctrl+S")]),
#            Menu("Data", [Submenu("Format as", [Item("Number", FMT_NUMBER), Item("Currency", FMT_CURRENCY, checked=True)])])])
#   ContextMenu("grid", x, y, [Item("Sort largest first", SORT_DESC)], on_close=MENU_CLOSE)   # over the view tagged "grid"
#
# The hosts draw them with their own popovers (GTK) or positioned divs (web), styled by the design; an item sends its
# message like a button; a shortcut ("Ctrl+S", "Ctrl+Shift+Z", "F5") fires the item from anywhere in the window.
# A context menu is part of the view while it's open: the app puts it in the tree after a SECONDARY gesture and
# takes it out on the item's message or on_close (a click elsewhere, Escape).

from mojoui.view import View, Node, MENUBAR, MENU, ITEM, _one, _container

comptime CHECKED = 1
comptime DISABLED = 2
comptime DANGER = 4


def Item(title: String, on_tap: Int, icon: String = "", shortcut: String = "", checked: Bool = False, disabled: Bool = False,
         danger: Bool = False) -> View:
    """One line of a menu: an icon, the title, its shortcut; a checkmark when checked; greyed when disabled; red for danger."""
    var n = Node(ITEM, title, on_tap)
    n.hint = icon
    if shortcut != "":
        n.options.append(shortcut)
    n.value = (CHECKED if checked else 0) + (DISABLED if disabled else 0) + (DANGER if danger else 0)
    return _one(n^)


def Separator() -> View:
    """A thin line between groups of items."""
    return _one(Node(ITEM, "", style=1))


def MenuLabel(text: String) -> View:
    """A small uppercase heading over a group of items ("GROUP REVENUE BY")."""
    return _one(Node(ITEM, text, style=2))


def Submenu(title: String, items: List[View], icon: String = "") -> View:
    """An item that opens another menu beside it."""
    var n = Node(ITEM, title)
    n.hint = icon
    return _container(n^, items)


def Menu(title: String, items: List[View]) -> View:
    """A menu in the bar: its title, then its items."""
    return _container(Node(MENU, title), items)


def MenuBar(menus: List[View]) -> View:
    """The row of menus along the top of the window (on a Mac, the system menu bar)."""
    return _container(Node(MENUBAR), menus)


def ContextMenu(anchor: String, x: Int, y: Int, items: List[View], on_close: Int) -> View:
    """A menu opened at (x, y) inside the view tagged `anchor` (a canvas's right-click point). `on_close` is sent when
    it's dismissed without choosing (a click elsewhere, Escape): the app then takes it out of the view."""
    var n = Node(MENU, anchor, style=1)
    n.msg2 = on_close
    n.x = x
    n.y = y
    return _container(n^, items)


def shortcut_of(v: View, i: Int) -> String:
    """The shortcut an ITEM node declares ("" when none)."""
    ref n = v.nodes[i]
    return n.options[0] if n.kind == ITEM and len(n.options) > 0 else String("")


def items_text(v: View, i: Int) -> String:
    """A menu's items in one line, the way hosts report them: "Open… (Ctrl+O), —, Format as ▸ (Number, Currency ✓)"."""
    var out = String("")
    for k in range(len(v.nodes[i].children)):
        var c = v.nodes[i].children[k]
        ref n = v.nodes[c]
        if k > 0:
            out += ", "
        if n.style == 1:
            out += "—"
        elif n.style == 2:
            out += "[" + n.text + "]"
        elif len(n.children) > 0:
            out += n.text + " ▸ (" + items_text(v, c) + ")"
        else:
            out += n.text
            if len(n.options) > 0:
                out += " (" + n.options[0] + ")"
            if n.value & CHECKED != 0:
                out += " ✓"
            if n.value & DISABLED != 0:
                out += " (off)"
    return out
