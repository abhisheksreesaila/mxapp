# Compare the screen before and after an update, so hosts change only what changed.

from mojoui.view import View

comptime SET_TEXT = 1  # label text, button title, field contents, toggle label
comptime SET_MSG = 2
comptime SET_VALUE = 3  # toggle, dropdown index, slider, progress


@fieldwise_init
struct Patch(Copyable, Movable, Equatable, Writable):
    var op: Int
    var node: Int
    var text: String
    var number: Int  # new message (SET_MSG) or value (SET_VALUE)

    def __eq__(self, other: Self) -> Bool:
        return self.op == other.op and self.node == other.node and self.text == other.text and self.number == other.number

    def write_to(self, mut writer: Some[Writer]):
        writer.write("Patch(", self.op, ", node=", self.node, ", '", self.text, "', ", self.number, ")")


@fieldwise_init
struct Diff(Copyable, Movable):
    var rebuild: Bool  # the shape changed: hosts rebuild the window's content
    var patches: List[Patch]  # otherwise: small in-place changes


def same_shape(a: View, b: View) -> Bool:
    """Same nodes in the same places; only text, messages or values may differ."""
    if len(a.nodes) != len(b.nodes):
        return False
    for i in range(len(a.nodes)):
        ref x = a.nodes[i]
        ref y = b.nodes[i]
        if (
            x.kind != y.kind
            or x.style != y.style
            or x.spacing != y.spacing
            or x.children != y.children
            or x.options != y.options
            or x.hint != y.hint
            or x.msg2 != y.msg2
            or x.size != y.size
        ):
            return False
    return True


def diff(old: View, new: View) -> Diff:
    if not same_shape(old, new):
        return Diff(True, List[Patch]())
    var patches = List[Patch]()
    for i in range(len(new.nodes)):
        ref a = old.nodes[i]
        ref b = new.nodes[i]
        if a.text != b.text:
            patches.append(Patch(SET_TEXT, i, b.text, 0))
        if a.msg != b.msg:
            patches.append(Patch(SET_MSG, i, "", b.msg))
        if a.value != b.value:
            patches.append(Patch(SET_VALUE, i, "", b.value))
    return Diff(False, patches^)
