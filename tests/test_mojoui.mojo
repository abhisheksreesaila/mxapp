# Tests for the declarative core. Run: pixi run mojo run -I . tests/test_mojoui.mojo
from std.testing import assert_equal, assert_true, assert_false

from mojoui import *

comptime GREET = 1
comptime ADD = 2
comptime NAME = 3
comptime SIZE = 4


def test_builders_make_a_flat_tree() raises:
    var v = VStack(Text("a", style=TITLE), HStack(Text("b"), Button("Go", on_tap=7)), spacing=4)
    assert_equal(len(v.nodes), 5)
    assert_equal(v.nodes[0].kind, VSTACK)
    assert_equal(v.nodes[0].spacing, 4)
    assert_equal(v.nodes[0].children, [1, 2])
    assert_equal(v.nodes[1], Node(TEXT, "a", style=TITLE))
    assert_equal(v.nodes[2].kind, HSTACK)
    assert_equal(v.nodes[2].children, [3, 4])
    assert_equal(v.nodes[4], Node(BUTTON, "Go", 7))


def test_components_record_their_values() raises:
    var v = VStack(
        TextField("Ada", placeholder="Your name", on_change=NAME, on_submit=GREET),
        Toggle("Dark mode", True, on_toggle=5),
        Dropdown(["Small", "Large"], 1, on_select=SIZE),
        Slider(30, on_change=6),
        ProgressBar(80),
        Divider(),
        Scroll(VStack(Text("row")), height=200),
    )
    assert_equal(v.nodes[0].children, [1, 2, 3, 4, 5, 6, 7])
    assert_equal(v.nodes[1], Node(FIELD, "Ada", NAME, hint="Your name", msg2=GREET))
    assert_equal(v.nodes[2], Node(TOGGLE, "Dark mode", 5, value=1))
    assert_equal(v.nodes[3], Node(DROPDOWN, "", SIZE, value=1, options=["Small", "Large"]))
    assert_equal(v.nodes[4], Node(SLIDER, "", 6, value=30))
    assert_equal(v.nodes[5], Node(PROGRESS, value=80))
    assert_equal(v.nodes[6], Node(DIVIDER))
    assert_equal(v.nodes[7], Node(SCROLL, size=200, children=[8]))
    assert_equal(v.nodes[8].children, [9])
    assert_equal(v.nodes[9].text, "row")


struct Counter(App):
    var n: Int

    def __init__(out self):
        self.n = 0

    def title(self) -> String:
        return "Counter"

    def update(mut self, event: Event):
        if event.message == GREET:
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


struct Form(App):
    var name: String
    var size: Int
    var loud: Bool

    def __init__(out self):
        self.name = ""
        self.size = 0
        self.loud = False

    def title(self) -> String:
        return "Form"

    def update(mut self, event: Event):
        if event.message == NAME:
            self.name = event.text
        elif event.message == SIZE:
            self.size = event.number
        elif event.message == ADD:
            self.loud = event.number == 1

    def view(self) -> View:
        return VStack(
            TextField(self.name, placeholder="Your name", on_change=NAME),
            Dropdown(["S", "M", "L"], self.size, on_select=SIZE),
            Toggle("Loud", self.loud, on_toggle=ADD),
            Text("Hi " + self.name),
        )


def test_typing_carries_text_and_patches_field_and_label() raises:
    var rt = Runtime(Form())
    var d = rt.dispatch(Event(NAME, "Grace", 0))
    assert_false(d.rebuild)
    assert_equal(len(d.patches), 2)
    assert_equal(d.patches[0], Patch(SET_TEXT, 1, "Grace", 0))
    assert_equal(d.patches[1], Patch(SET_TEXT, 4, "Hi Grace", 0))


def test_select_and_toggle_patch_values() raises:
    var rt = Runtime(Form())
    var d = rt.dispatch(Event(SIZE, "L", 2))
    assert_equal(len(d.patches), 1)
    assert_equal(d.patches[0], Patch(SET_VALUE, 2, "", 2))
    d = rt.dispatch(Event(ADD, "", 1))
    assert_equal(len(d.patches), 1)
    assert_equal(d.patches[0], Patch(SET_VALUE, 3, "", 1))


def test_changed_options_rebuild() raises:
    var d = diff(VStack(Dropdown(["a"], 0, on_select=1)), VStack(Dropdown(["a", "b"], 0, on_select=1)))
    assert_true(d.rebuild)


struct Rows(App):
    var count: Int

    def __init__(out self):
        self.count = 0

    def title(self) -> String:
        return "Rows"

    def update(mut self, event: Event):
        if event.message == ADD:
            self.count += 1

    def view(self) -> View:
        var rows = List[View]()
        for i in range(self.count):
            rows.append(Text("Row " + String(i + 1)))
        return VStack(Button("Add", on_tap=ADD), Scroll(VStack(rows)))


def test_new_row_rebuilds() raises:
    var rt = Runtime(Rows())
    var d = rt.dispatch(ADD)
    assert_true(d.rebuild)
    assert_equal(len(rt.shown.nodes), 5)
    assert_equal(rt.shown.nodes[4].text, "Row 1")


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


def test_progress_change_is_a_value_patch() raises:
    var d = diff(VStack(ProgressBar(10), Slider(10, on_change=1)), VStack(ProgressBar(55), Slider(55, on_change=1)))
    assert_false(d.rebuild)
    assert_equal(len(d.patches), 2)
    assert_equal(d.patches[0], Patch(SET_VALUE, 1, "", 55))
    assert_equal(d.patches[1], Patch(SET_VALUE, 2, "", 55))


def test_image_holds_pixels_and_patches_when_they_change() raises:
    var a: List[UInt32] = [1, 2, 3, 4]
    var b: List[UInt32] = [1, 2, 3, 5]
    var v = VStack(Image(a, 2, 2))
    assert_equal(v.nodes[1], Node(IMAGE, spacing=2, size=2, pixels=[1, 2, 3, 4]))
    var d = diff(v, VStack(Image(b, 2, 2)))
    assert_false(d.rebuild)
    assert_equal(len(d.patches), 1)
    assert_equal(d.patches[0], Patch(SET_IMAGE, 1, "", 0))
    assert_true(diff(v, VStack(Image(a, 4, 1))).rebuild)  # new size: rebuild
    var short: List[UInt32] = [1, 2]
    var safe = Image(short, 2, 2)  # wrong pixel count: a blank picture of the stated size
    assert_equal(len(safe.nodes[0].pixels), 4)
    assert_equal(safe.nodes[0].pixels[3], 0)


def test_hint_submit_and_scroll_size_changes_rebuild() raises:
    assert_true(diff(VStack(TextField("", placeholder="a")), VStack(TextField("", placeholder="b"))).rebuild)
    assert_true(diff(VStack(TextField("", on_submit=1)), VStack(TextField("", on_submit=2))).rebuild)
    assert_true(diff(Scroll(Text("x"), height=100), Scroll(Text("x"), height=200)).rebuild)


def test_toggle_label_change_is_a_text_patch() raises:
    var d = diff(VStack(Toggle("Off", False, on_toggle=1)), VStack(Toggle("On", True, on_toggle=1)))
    assert_false(d.rebuild)
    assert_equal(len(d.patches), 2)
    assert_equal(d.patches[0], Patch(SET_TEXT, 1, "On", 0))
    assert_equal(d.patches[1], Patch(SET_VALUE, 1, "", 1))


def test_spacer_is_a_leaf() raises:
    var v = HStack(Text("left"), Spacer(), Text("right"))
    assert_equal(len(v.nodes), 4)
    assert_equal(v.nodes[0].children, [1, 2, 3])
    assert_equal(v.nodes[2], Node(SPACER))


def test_goal4_components_record_their_values() raises:
    var opts: List[String] = ["A", "B"]
    var cells = List[View]()
    for i in range(5):
        cells.append(Text(String(i)))
    var v = VStack(
        Segmented(opts, 1, on_select=3),
        Radio(opts, 0, on_select=4),
        TextArea("x\ny", placeholder="Notes", on_change=5, height=90),
        Alert("Sure?", "Really.", opts, on_choose=6),
        Tabs(opts, 1, on_select=7),
        NavBar("Details", on_back=8),
        DatePicker("2026-10-15", on_change=9),
        Icon("star", size=20),
        Grid(cells, 2),
        LazyList(10000, 1, on_tap=10, height=300, row_height=40),
    )
    assert_equal(v.nodes[1], Node(SEGMENTED, "", 3, value=1, options=["A", "B"]))
    assert_equal(v.nodes[2], Node(RADIO, "", 4, value=0, options=["A", "B"]))
    assert_equal(v.nodes[3], Node(TEXTAREA, "x\ny", 5, hint="Notes", size=90))
    assert_equal(v.nodes[4], Node(ALERT, "Sure?", 6, hint="Really.", options=["A", "B"]))
    assert_equal(v.nodes[5], Node(TABS, "", 7, value=1, options=["A", "B"]))
    assert_equal(v.nodes[6], Node(NAVBAR, "Details", 8))
    assert_equal(v.nodes[7], Node(DATE, "2026-10-15", 9))
    assert_equal(v.nodes[8], Node(ICON, "star", size=20))
    assert_equal(v.nodes[9].kind, GRID)
    assert_equal(v.nodes[9].value, 2)
    assert_equal(len(v.nodes[9].children), 5)
    assert_equal(v.nodes[15], Node(LAZYLIST, "", 10, value=10000, msg2=1, size=300, spacing=40))


def test_segment_and_date_changes_are_patches_but_alert_appearing_rebuilds() raises:
    var opts: List[String] = ["A", "B"]
    var d = diff(VStack(Segmented(opts, 0, on_select=1), DatePicker("2026-01-01", on_change=2)),
                 VStack(Segmented(opts, 1, on_select=1), DatePicker("2026-12-25", on_change=2)))
    assert_false(d.rebuild)
    assert_equal(len(d.patches), 2)
    assert_equal(d.patches[0], Patch(SET_VALUE, 1, "", 1))
    assert_equal(d.patches[1], Patch(SET_TEXT, 2, "2026-12-25", 0))
    assert_true(diff(VStack(Text("x")), VStack(Text("x"), Alert("?", "", opts, on_choose=3))).rebuild)
    var grown = diff(VStack(LazyList(10, 1)), VStack(LazyList(11, 1)))
    assert_false(grown.rebuild)  # a longer list is a value patch: hosts reload rows, not the screen
    assert_equal(grown.patches[0], Patch(SET_VALUE, 1, "", 11))


struct WithRows(App):
    def __init__(out self):
        pass

    def title(self) -> String:
        return "Rows"

    def update(mut self, event: Event):
        pass

    def view(self) -> View:
        return VStack(LazyList(1000, 7))

    def row(self, list_id: Int, index: Int) -> String:
        return "list " + String(list_id) + " row " + String(index)


def test_back_button_and_alert_question_changes_rebuild() raises:
    assert_true(diff(VStack(NavBar("A")), VStack(NavBar("A", on_back=2))).rebuild)
    var b: List[String] = ["OK"]
    assert_true(diff(VStack(Alert("Q1", "m", b, on_choose=1)), VStack(Alert("Q2", "m", b, on_choose=1))).rebuild)
    assert_false(diff(VStack(NavBar("A", on_back=2)), VStack(NavBar("B", on_back=3))).rebuild)  # title/message: patches


def test_layout_settings_chain_onto_the_view_itself() raises:
    var v = HStack(Text("a").grow(), Button("b", on_tap=1).width(120).tag("pay"), spacing=8).padding(16, 8).justify(BETWEEN).fill()
    assert_equal(v.nodes[0].pad_v, 16)
    assert_equal(v.nodes[0].pad_h, 8)
    assert_equal(v.nodes[0].justify_items, BETWEEN)
    assert_true(v.nodes[0].fills)
    assert_true(v.nodes[1].grows)
    assert_false(v.nodes[2].grows)
    assert_equal(v.nodes[2].w, 120)
    assert_equal(v.nodes[2].name, "pay")
    assert_equal(v.nodes[0].children, [1, 2])  # settings don't change the tree


def test_layout_change_rebuilds_but_same_layout_still_patches() raises:
    assert_true(diff(VStack(Text("x")), VStack(Text("x").padding(4))).rebuild)
    assert_true(diff(VStack(Text("x")).align(START), VStack(Text("x")).align(END)).rebuild)
    var d = diff(VStack(Text("x").width(100)), VStack(Text("y").width(100)))
    assert_false(d.rebuild)
    assert_equal(d.patches[0], Patch(SET_TEXT, 1, "y", 0))


def test_apps_provide_rows_on_demand() raises:
    var rt = Runtime(WithRows())
    assert_equal(rt.app.row(7, 999), "list 7 row 999")
    var plain = Runtime(Counter())
    assert_equal(plain.app.row(1, 2), "")  # the default


def main() raises:
    test_builders_make_a_flat_tree()
    test_components_record_their_values()
    test_tap_changes_only_the_label()
    test_unknown_message_changes_nothing()
    test_typing_carries_text_and_patches_field_and_label()
    test_select_and_toggle_patch_values()
    test_changed_options_rebuild()
    test_new_row_rebuilds()
    test_diff_reports_message_changes()
    test_button_title_change_is_a_patch()
    test_style_change_rebuilds()
    test_text_and_message_change_together()
    test_progress_change_is_a_value_patch()
    test_spacer_is_a_leaf()
    test_image_holds_pixels_and_patches_when_they_change()
    test_hint_submit_and_scroll_size_changes_rebuild()
    test_toggle_label_change_is_a_text_patch()
    test_goal4_components_record_their_values()
    test_segment_and_date_changes_are_patches_but_alert_appearing_rebuilds()
    test_apps_provide_rows_on_demand()
    test_back_button_and_alert_question_changes_rebuild()
    test_layout_settings_chain_onto_the_view_itself()
    test_layout_change_rebuilds_but_same_layout_still_patches()
    print("ALL TESTS PASSED")
