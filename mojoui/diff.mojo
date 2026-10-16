# Compare the screen before and after an update, so hosts change only what changed.

from mojoui.view import View, NAVBAR, ALERT, CANVAS, BOARD

comptime SET_TEXT = 1  # label text, button title, field contents, toggle label
comptime SET_MSG = 2
comptime SET_VALUE = 3  # toggle, dropdown index, slider, progress
comptime SET_IMAGE = 4  # new pixels (same size); hosts read them from the shown view
comptime SET_FRAMES = 5  # a canvas's on_frame message changed (number = new message, 0 = stop)
comptime SET_PLACE = 6  # an object moved on its Board (new x, y in the shown view), or the Board's own size changed


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


def placed(v: View) -> List[Bool]:
    """Which nodes sit on a Board (their x, y are a patch, not a new layout)."""
    var out = List[Bool](length=len(v.nodes), fill=False)
    for n in v.nodes:
        if n.kind == BOARD:
            for c in n.children:
                out[c] = True
    return out^


def same_shape(a: View, b: View) -> Bool:
    """Same nodes in the same places; only text, messages, values or Board positions may differ."""
    if len(a.nodes) != len(b.nodes):
        return False
    var on_board = placed(b)
    for i in range(len(a.nodes)):
        ref x = a.nodes[i]
        ref y = b.nodes[i]
        if (
            x.kind != y.kind
            or x.style != y.style
            or (x.spacing != y.spacing and x.kind != BOARD)  # a Board's width and height are a patch
            or x.children != y.children
            or x.options != y.options
            or x.hint != y.hint
            or (x.msg2 != y.msg2 and x.kind != CANVAS)  # a canvas starting or stopping frames is a patch
            or (x.size != y.size and x.kind != BOARD)
        ):
            return False
        if on_board[i]:
            var z = y.copy()
            z.x = x.x
            z.y = x.y
            if not x.same_layout(z):
                return False
        elif not x.same_layout(y):  # layout settings changed: lay it out again
            return False
        # A Back button appearing or going, or an alert's question changing, is a new layout.
        if x.kind == NAVBAR and (x.msg == 0) != (y.msg == 0):
            return False
        if x.kind == ALERT and (x.text != y.text or x.hint != y.hint):
            return False
    return True


def diff(old: View, new: View) -> Diff:
    if not same_shape(old, new):
        return Diff(True, List[Patch]())
    var patches = List[Patch]()
    var on_board = placed(new)
    for i in range(len(new.nodes)):
        ref a = old.nodes[i]
        ref b = new.nodes[i]
        if (on_board[i] and (a.x != b.x or a.y != b.y)) or (b.kind == BOARD and (a.spacing != b.spacing or a.size != b.size)):
            patches.append(Patch(SET_PLACE, i, "", 0))
        if a.text != b.text:
            patches.append(Patch(SET_TEXT, i, b.text, 0))
        if a.msg != b.msg:
            patches.append(Patch(SET_MSG, i, "", b.msg))
        if a.value != b.value:
            patches.append(Patch(SET_VALUE, i, "", b.value))
        if b.kind == CANVAS and a.msg2 != b.msg2:
            patches.append(Patch(SET_FRAMES, i, "", b.msg2))
        if a.pixels != b.pixels:
            patches.append(Patch(SET_IMAGE, i, "", 0))
    return Diff(False, patches^)
