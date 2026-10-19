# A shape change rebuilds only what changed (goal 25): the diff keeps every widget it can and names the stacks whose
# children changed, so a column's inspector changing, or a menu opening, leaves the grid and the toolbar alone.
#   pixi run mojo run -I . tests/test_diff_keep.mojo
from std.testing import assert_equal, assert_true, assert_false
from mojoui import *
from mojoui.diff import SET_SIZE


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
    assert_equal(d.patches[0].op, SET_TEXT)
    assert_equal(d.patches[0].text, "region · Text")
    assert_equal(b.nodes[d.patches[0].node].text, "region · Text", "the patch names the right node")


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
    assert_equal(d.patches[0].op, SET_TEXT)
    assert_equal(b.nodes[d.patches[0].node].text, "region · Text", "the patch names the new title node")


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


def test_a_size_change_is_a_size_patch() raises:
    var a = screen(VStack(Text("x")).width(300).tag("inspector"), [])
    var b = screen(VStack(Text("x")).width(260).tag("inspector"), [])
    var d = diff(a, b)
    assert_true(d.rebuild and d.partial, "sizes travel only in partial diffs (hosts that only patch rebuild)")
    assert_equal(len(d.resync), 0)
    assert_equal(len(d.patches), 1)
    assert_equal(d.patches[0].op, SET_SIZE)
    assert_equal(d.patches[0].node, find(b, "inspector"))
    for k in range(len(d.kept)):
        assert_equal(d.kept[k], k, "every widget stays")


def test_a_size_set_where_there_was_none_is_a_new_layout() raises:
    var a = screen(VStack(Text("x")).tag("inspector"), [])
    var b = screen(VStack(Text("x")).width(260).tag("inspector"), [])
    var d = diff(a, b)
    assert_true(d.partial)
    assert_equal(d.kept[find(b, "inspector")], -1, "built again: a width where there was none changes how it takes space")


def test_a_failed_sibling_rolls_back_what_its_cousins_recorded() raises:
    # A centred row (justify spacers: not a stack hosts resync) whose second child changes kind is built again; its
    # first child, a stack, had recorded a resync of its own: that must be undone (the host builds it fresh instead).
    var a = VStack(HStack(VStack(Text("a"), Text("b")).tag("inner"), Text("x")).justify(CENTER).tag("row"), Text("keep"))
    var b = VStack(HStack(VStack(Text("a")).tag("inner"), Button("x", 9)).justify(CENTER).tag("row"), Text("keep"))
    var d = diff(a, b)
    assert_true(d.partial)
    var inner = find(b, "inner")
    for r in d.resync:
        assert_true(r != inner, "no resync of a stack inside a container built again")
    assert_equal(d.kept[inner], -1)
    assert_equal(d.kept[find(b, "row")], -1)
    assert_equal(len(d.resync), 1, "only the root re-lays its children (the row in place of the old one)")


def test_a_new_root_rebuilds_everything() raises:
    var d = diff(VStack(Text("x")), HStack(Text("x")))
    assert_true(d.rebuild)
    assert_false(d.partial)


def main() raises:
    test_a_text_change_is_a_patch()
    test_the_inspector_changing_keeps_the_grid()
    test_a_menu_opening_builds_only_the_menu()
    test_a_changed_child_of_a_fixed_container_replaces_the_container()
    test_a_size_change_is_a_size_patch()
    test_a_size_set_where_there_was_none_is_a_new_layout()
    test_a_failed_sibling_rolls_back_what_its_cousins_recorded()
    test_a_new_root_rebuilds_everything()
    print("DIFF KEEP TESTS PASSED")
