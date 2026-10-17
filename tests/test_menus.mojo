# The menu model on its own: a bar of menus, items with icons, shortcuts and flags, submenus, a context menu
# (the hosts are checked by scripts/check: the same items on GTK and the web, shortcuts, a right-click).
#   pixi run mojo build -I . tests/test_menus.mojo -o build/test_menus && build/test_menus
from std.testing import assert_equal, assert_true

from mojoui import View, MENUBAR, MENU, ITEM
from mojoui.menus import MenuBar, Menu, Item, Separator, MenuLabel, Submenu, ContextMenu, CHECKED, DISABLED, DANGER, shortcut_of, items_text


def main() raises:
    var file = Menu("File", [Item("Open…", 11, icon="open", shortcut="Ctrl+O"), Separator(), Item("Save", 12, shortcut="Ctrl+S"),
                             Item("Delete", 13, icon="trash", danger=True), Item("Revert", 14, disabled=True)])
    var data = Menu("Data", [MenuLabel("Sort"), Item("Sort smallest first", 21), Item("Sort largest first", 22),
                             Submenu("Format as", [Item("Number", 31), Item("Currency", 32, checked=True)])])
    var bar = MenuBar([file.copy(), data.copy()])
    assert_equal(bar.nodes[0].kind, MENUBAR)
    assert_equal(len(bar.nodes[0].children), 2)
    var file_i = bar.nodes[0].children[0]
    assert_equal(bar.nodes[file_i].kind, MENU)
    assert_equal(bar.nodes[file_i].text, "File")
    assert_equal(len(bar.nodes[file_i].children), 5)
    var open = bar.nodes[bar.nodes[file_i].children[0]].copy()
    assert_equal(open.kind, ITEM)
    assert_equal(open.msg, 11)
    assert_equal(open.hint, "open")
    assert_equal(shortcut_of(bar, bar.nodes[file_i].children[0]), "Ctrl+O")
    assert_equal(shortcut_of(bar, bar.nodes[file_i].children[1]), "")  # a separator
    assert_equal(bar.nodes[bar.nodes[file_i].children[1]].style, 1)
    assert_equal(bar.nodes[bar.nodes[file_i].children[3]].value, DANGER)
    assert_equal(bar.nodes[bar.nodes[file_i].children[4]].value, DISABLED)
    var data_i = bar.nodes[0].children[1]
    var sub = bar.nodes[bar.nodes[data_i].children[3]].copy()
    assert_equal(sub.text, "Format as")
    assert_equal(len(sub.children), 2)
    assert_equal(bar.nodes[sub.children[1]].value, CHECKED)
    assert_equal(bar.nodes[sub.children[1]].msg, 32)
    # the one-line report both hosts print
    assert_equal(items_text(bar, file_i), "Open… (Ctrl+O), —, Save (Ctrl+S), Delete, Revert (off)")
    assert_equal(items_text(bar, data_i), "[Sort], Sort smallest first, Sort largest first, Format as ▸ (Number, Currency ✓)")
    # a context menu: anchored in a tagged view, with on_close
    var ctx = ContextMenu("grid", 120, 40, [Item("Sort largest first", 22), Item("Hide column", 23)], on_close=99)
    assert_equal(ctx.nodes[0].kind, MENU)
    assert_equal(ctx.nodes[0].style, 1)
    assert_equal(ctx.nodes[0].text, "grid")
    assert_equal(ctx.nodes[0].x, 120)
    assert_equal(ctx.nodes[0].y, 40)
    assert_equal(ctx.nodes[0].msg2, 99)
    assert_equal(items_text(ctx, 0), "Sort largest first, Hide column")
    # every item keeps its message when the menu is put inside a bigger view
    var messages = List[Int]()
    for n in bar.nodes:
        if n.kind == ITEM and n.msg != 0:
            messages.append(n.msg)
    assert_equal(len(messages), 8)
    assert_true(messages[0] == 11 and messages[7] == 32, "items in order")
    print("MENU TESTS PASSED")
