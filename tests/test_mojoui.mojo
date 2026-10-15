# Tests for the declarative core. Run: pixi run mojo run -I . tests/test_mojoui.mojo
from std.testing import assert_equal, assert_true, assert_false

from mojoui import *

comptime GREET = 1
comptime ADD = 2


def test_builders_make_a_flat_tree() raises:
    var v = VStack(Text("a", style=TITLE), HStack(Text("b"), Button("Go", on_tap=7)), spacing=4)
    assert_equal(len(v.nodes), 5)
    assert_equal(v.nodes[0].kind, VSTACK)
    assert_equal(v.nodes[0].spacing, 4)
    assert_equal(v.nodes[0].children, [1, 2])
    assert_equal(v.nodes[1], Node(TEXT, "a", NO_MSG, TITLE, 0, []))
    assert_equal(v.nodes[2].kind, HSTACK)
    assert_equal(v.nodes[2].children, [3, 4])
    assert_equal(v.nodes[4], Node(BUTTON, "Go", 7, PLAIN, 0, []))


struct Counter(App):
    var n: Int

    def __init__(out self):
        self.n = 0

    def title(self) -> String:
        return "Counter"

    def update(mut self, message: Int):
        if message == GREET:
            self.n += 1

    def view(self) -> View:
        return VStack(Text("Count: " + String(self.n)), Button("+1", on_tap=GREET))


def test_tap_changes_only_the_label() raises:
    var rt = Runtime(Counter())
    var d = rt.dispatch(GREET)
    assert_false(d.rebuild)
    assert_equal(len(d.patches), 1)
    assert_equal(d.patches[0], Patch(SET_TEXT, 1, "Count: 1", 0))
    assert_equal(rt.shown.nodes[1].text, "Count: 1")


def test_unknown_message_changes_nothing() raises:
    var rt = Runtime(Counter())
    var d = rt.dispatch(99)
    assert_false(d.rebuild)
    assert_equal(len(d.patches), 0)


struct Rows(App):
    var count: Int

    def __init__(out self):
        self.count = 0

    def title(self) -> String:
        return "Rows"

    def update(mut self, message: Int):
        if message == ADD:
            self.count += 1

    def view(self) -> View:
        var rows = List[View]()
        for i in range(self.count):
            rows.append(Text("Row " + String(i + 1)))
        return VStack(Button("Add", on_tap=ADD), VStack(rows))


def test_new_row_rebuilds() raises:
    var rt = Runtime(Rows())
    var d = rt.dispatch(ADD)
    assert_true(d.rebuild)
    assert_equal(len(rt.shown.nodes), 4)
    assert_equal(rt.shown.nodes[3].text, "Row 1")


def test_diff_reports_message_changes() raises:
    var d = diff(VStack(Button("x", on_tap=1)), VStack(Button("x", on_tap=2)))
    assert_false(d.rebuild)
    assert_equal(len(d.patches), 1)
    assert_equal(d.patches[0], Patch(SET_MSG, 1, "", 2))


def test_button_title_change_is_a_patch() raises:
    var d = diff(VStack(Button("Start", on_tap=1)), VStack(Button("Stop", on_tap=1)))
    assert_false(d.rebuild)
    assert_equal(len(d.patches), 1)
    assert_equal(d.patches[0], Patch(SET_TEXT, 1, "Stop", 0))


def test_style_change_rebuilds() raises:
    var d = diff(VStack(Text("x", style=BODY)), VStack(Text("x", style=TITLE)))
    assert_true(d.rebuild)
    assert_equal(len(d.patches), 0)


def test_text_and_message_change_together() raises:
    var d = diff(VStack(Button("a", on_tap=1)), VStack(Button("b", on_tap=2)))
    assert_false(d.rebuild)
    assert_equal(len(d.patches), 2)
    assert_equal(d.patches[0], Patch(SET_TEXT, 1, "b", 0))
    assert_equal(d.patches[1], Patch(SET_MSG, 1, "", 2))


def test_spacer_is_a_leaf() raises:
    var v = HStack(Text("left"), Spacer(), Text("right"))
    assert_equal(len(v.nodes), 4)
    assert_equal(v.nodes[0].children, [1, 2, 3])
    assert_equal(v.nodes[2], Node(SPACER, "", NO_MSG, BODY, 0, []))


def main() raises:
    test_builders_make_a_flat_tree()
    test_tap_changes_only_the_label()
    test_unknown_message_changes_nothing()
    test_new_row_rebuilds()
    test_diff_reports_message_changes()
    test_button_title_change_is_a_patch()
    test_style_change_rebuilds()
    test_text_and_message_change_together()
    test_spacer_is_a_leaf()
    print("ALL TESTS PASSED")
