# The overlay model on its own: a dialog with its content, a toast with an action, a popover on an anchor, a
# checkbox, tooltips (the hosts are checked by scripts/check: Settings, a sort's toast, ƒx's popover, TIP: lines).
#   pixi run mojo build -I . tests/test_overlays.mojo -o build/test_overlays && build/test_overlays
from std.testing import assert_equal, assert_true

from mojoui import View, Text, Button, VStack, Radio, DIALOG, TOAST, POPOVER, TOGGLE, BUTTON, TEXT, RADIO, PROMINENT, diff
from mojoui.overlays import Dialog, Toast, Popover, Checkbox


def main() raises:
    var skins: List[String] = ["Ledger", "Graphite", "Blueprint"]
    var content = VStack(Text("Appearance"), Radio(skins, 0, 5), Checkbox("Show GPU timings in the status bar", True, 6),
                         Button("Done", 7, PROMINENT), spacing=10)
    var d = Dialog("Settings", content, on_close=7)
    assert_equal(d.nodes[0].kind, DIALOG)
    assert_equal(d.nodes[0].text, "Settings")
    assert_equal(d.nodes[0].msg2, 7)
    assert_equal(d.nodes[0].w, 560)
    assert_equal(len(d.nodes[0].children), 1)
    var kinds = List[Int]()
    for n in d.nodes:
        kinds.append(n.kind)
    assert_true(RADIO in kinds and TOGGLE in kinds and BUTTON in kinds and TEXT in kinds, "the dialog carries its content")
    for n in d.nodes:
        if n.kind == TOGGLE:
            assert_equal(n.style, 1)  # a checkbox, not a switch
            assert_equal(n.value, 1)
            assert_equal(n.msg, 6)
        if n.kind == RADIO:
            assert_equal(n.msg, 5)
    # a toast: text, one action, and when it leaves
    var t = Toast("Sorted by revenue, largest first", "Undo", 21, on_close=22)
    assert_equal(t.nodes[0].kind, TOAST)
    assert_equal(t.nodes[0].options[0], "Undo")
    assert_equal(t.nodes[0].msg, 21)
    assert_equal(t.nodes[0].msg2, 22)
    assert_equal(t.nodes[0].size, 6)
    var quiet = Toast("Saved", on_close=22, seconds=3)
    assert_equal(len(quiet.nodes[0].options), 0)
    assert_equal(quiet.nodes[0].size, 3)
    # a popover: on an anchor, with a title and content
    var p = Popover("formula-bar", "Formulas", VStack(Text("+ − × ÷"), Text("min, max"), spacing=4), on_close=31)
    assert_equal(p.nodes[0].kind, POPOVER)
    assert_equal(p.nodes[0].text, "formula-bar")
    assert_equal(p.nodes[0].hint, "Formulas")
    assert_equal(p.nodes[0].msg2, 31)
    assert_equal(p.nodes[0].x, 0)
    assert_equal(len(p.nodes), 4)
    # tooltips: on any view; changing one is a new layout (hosts set it when they build)
    var b = Button("Save", 1, icon="save").tooltip("Save the document (Ctrl+S)")
    assert_equal(b.nodes[0].tip, "Save the document (Ctrl+S)")
    assert_equal(Button("Save", 1).nodes[0].tip, "")
    assert_true(diff(Button("Save", 1), b).rebuild, "a tooltip appearing rebuilds")
    assert_true(not diff(b, Button("Save", 2, icon="save").tooltip("Save the document (Ctrl+S)")).rebuild, "a message change is a patch")
    # a checkbox off
    var c = Checkbox("Keep the inspector open", False, 9)
    assert_equal(c.nodes[0].kind, TOGGLE)
    assert_equal(c.nodes[0].value, 0)
    print("OVERLAY TESTS PASSED")
