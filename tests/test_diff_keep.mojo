# A shape change rebuilds only what changed (goal 25): the diff keeps every widget it can and names the stacks whose
# children changed, so a column's inspector changing, or a menu opening, leaves the grid and the toolbar alone.
#   pixi run mojo run -I . tests/test_diff_keep.mojo
from std.testing import assert_equal, assert_true, assert_false
from mojoui import *


def screen(var inspector: View, var extra: List[View]) -> View:
    var parts = List[View]()
    parts.append(HStack(Button("Save", 1), Button("Undo", 2)).tag("toolbar"))
    parts.append(HStack(Canvas(0, 1, on_gesture=3, keys=True).tag("grid"), inspector^, spacing=16))
    parts.append(Text("Ready", CAPTION))
    for e in extra:
        parts.append(e.copy())
    return VStack(parts^, spacing=0)


def find(v: View, tag: String) -> Int:
    for k in range(len(v.nodes)):
        if v.nodes[k].name == tag:
            return k
    return -1


def test_a_text_change_is_a_patch() raises:
    var a = screen(VStack(Text("amount · Decimal")), [])
    var b = screen(VStack(Text("region · Text")), [])
    var d = diff(a, b)
    assert_false(d.rebuild)
    assert_equal(len(d.patches), 1)


def test_the_inspector_changing_keeps_the_grid() raises:
    var a = screen(VStack(Text("amount · Decimal"), Dropdown(["Automatic", "Currency"], 0, on_select=4), Text("Mean")).tag("inspector"), [])
    var b = screen(VStack(Text("region · Text"), Text("Mean")).tag("inspector"), [])
    var d = diff(a, b)
    assert_true(d.rebuild and d.partial, "a partial rebuild")
    var grid = find(b, "grid")
    assert_equal(d.kept[grid], find(a, "grid"), "the grid keeps its widget")
    assert_equal(d.kept[find(b, "toolbar")], find(a, "toolbar"), "the toolbar keeps its widget")
    assert_equal(len(d.resync), 1, "one stack lays out its children again")
    assert_equal(d.resync[0], find(b, "inspector"))
    assert_equal(len(d.patches), 1, "the title's text")


def test_a_menu_opening_builds_only_the_menu() raises:
    var a = screen(VStack(Text("x")), [])
    var b = screen(VStack(Text("x")), [Menu("Format", [Item("Bold", 5)]).tag("menu")])
    var d = diff(a, b)
    assert_true(d.partial)
    assert_equal(len(d.resync), 1)
    assert_equal(d.resync[0], 0, "the root stack gains a child")
    var fresh = 0
    for k in range(len(d.kept)):
        if d.kept[k] < 0:
            fresh += 1
    assert_equal(fresh, 2, "the menu and its item are new; everything else stays")


def test_a_changed_child_of_a_fixed_container_replaces_the_container() raises:
    var a = screen(VStack(Scroll(Text("x"), height=100).tag("scroll")), [])
    var b = screen(VStack(Scroll(Button("x", 9), height=100).tag("scroll")), [])
    var d = diff(a, b)
    assert_true(d.partial)
    assert_equal(d.kept[find(b, "scroll")], -1, "the scroll is built again (it isn't a stack)")
    assert_equal(d.kept[find(b, "grid")], find(a, "grid"))


def test_a_new_root_rebuilds_everything() raises:
    var d = diff(VStack(Text("x")), HStack(Text("x")))
    assert_true(d.rebuild)
    assert_false(d.partial)


def main() raises:
    test_a_text_change_is_a_patch()
    test_the_inspector_changing_keeps_the_grid()
    test_a_menu_opening_builds_only_the_menu()
    test_a_changed_child_of_a_fixed_container_replaces_the_container()
    test_a_new_root_rebuilds_everything()
    print("DIFF KEEP TESTS PASSED")
