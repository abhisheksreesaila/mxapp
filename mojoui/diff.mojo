# Compare the screen before and after an update, so hosts change only what changed.

from mojoui.view import View

comptime SET_TEXT = 1
comptime SET_MSG = 2


@fieldwise_init
struct Patch(Copyable, Movable, Equatable, Writable):
    var op: Int
    var node: Int
    var text: String
    var msg: Int

    def __eq__(self, other: Self) -> Bool:
        return self.op == other.op and self.node == other.node and self.text == other.text and self.msg == other.msg

    def write_to(self, mut writer: Some[Writer]):
        writer.write("Patch(", self.op, ", node=", self.node, ", '", self.text, "', msg=", self.msg, ")")


@fieldwise_init
struct Diff(Copyable, Movable):
    var rebuild: Bool  # the shape changed: hosts rebuild the window's content
    var patches: List[Patch]  # otherwise: small in-place changes


def same_shape(a: View, b: View) -> Bool:
    if len(a.nodes) != len(b.nodes):
        return False
    for i in range(len(a.nodes)):
        ref x = a.nodes[i]
        ref y = b.nodes[i]
        if x.kind != y.kind or x.style != y.style or x.spacing != y.spacing or x.children != y.children:
            return False
    return True


def diff(old: View, new: View) -> Diff:
    if not same_shape(old, new):
        return Diff(True, List[Patch]())
    var patches = List[Patch]()
    for i in range(len(new.nodes)):
        if old.nodes[i].text != new.nodes[i].text:
            patches.append(Patch(SET_TEXT, i, new.nodes[i].text, 0))
        if old.nodes[i].msg != new.nodes[i].msg:
            patches.append(Patch(SET_MSG, i, "", new.nodes[i].msg))
    return Diff(False, patches^)
