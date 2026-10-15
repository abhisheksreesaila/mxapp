# The declarative layer: a screen is a value (a View) built from small pieces.
#
#   VStack(Text("Hello", style=TITLE), TextField(self.name, placeholder="Your name", on_change=NAME))
#
# A View is a flat list of nodes; node 0 is the root and containers list their
# children by index. (Mojo can't yet put a List[View] inside View; flat lists
# are also easy to compare and to pair with native widgets.)

# Node kinds
comptime TEXT = 1
comptime BUTTON = 2
comptime VSTACK = 3
comptime HSTACK = 4
comptime SPACER = 5
comptime FIELD = 6  # one-line text input
comptime TOGGLE = 7  # on/off switch with a label
comptime DROPDOWN = 8  # pick one of several options
comptime SLIDER = 9  # 0–100
comptime PROGRESS = 10  # 0–100, read-only
comptime DIVIDER = 11
comptime SCROLL = 12  # one child, scrolls when taller than `size`
comptime IMAGE = 13  # pixels (RGBA), `spacing` x `size` in size

# Text styles (each platform maps them to its own type scale)
comptime BODY = 0
comptime TITLE = 1
comptime HEADLINE = 2
comptime CAPTION = 3

# Button styles
comptime PLAIN = 0
comptime PROMINENT = 1
comptime DESTRUCTIVE = 2

comptime NO_MSG = 0


struct Node(Copyable, Movable, Equatable, Writable):
    var kind: Int
    var text: String  # label text, button title, field contents, toggle label
    var msg: Int  # message sent on tap / change / toggle / select
    var style: Int
    var spacing: Int  # stacks: gap between children
    var children: List[Int]
    var value: Int  # toggle 0/1, dropdown index, slider/progress 0–100
    var options: List[String]  # dropdown choices
    var hint: String  # field placeholder
    var msg2: Int  # field: message sent on Return
    var size: Int  # scroll: visible height in points; image: height
    var pixels: List[UInt32]  # image: RGBA bytes, one UInt32 per pixel (R in the low byte)

    def __init__(
        out self,
        kind: Int,
        text: String = "",
        msg: Int = NO_MSG,
        style: Int = BODY,
        spacing: Int = 0,
        var children: List[Int] = [],
        value: Int = 0,
        var options: List[String] = [],
        hint: String = "",
        msg2: Int = NO_MSG,
        size: Int = 0,
        var pixels: List[UInt32] = [],
    ):
        self.kind = kind
        self.text = text
        self.msg = msg
        self.style = style
        self.spacing = spacing
        self.children = children^
        self.value = value
        self.options = options^
        self.hint = hint
        self.msg2 = msg2
        self.size = size
        self.pixels = pixels^

    def __eq__(self, other: Self) -> Bool:
        return (
            self.kind == other.kind
            and self.text == other.text
            and self.msg == other.msg
            and self.style == other.style
            and self.spacing == other.spacing
            and self.children == other.children
            and self.value == other.value
            and self.options == other.options
            and self.hint == other.hint
            and self.msg2 == other.msg2
            and self.size == other.size
            and self.pixels == other.pixels
        )

    def write_to(self, mut writer: Some[Writer]):
        writer.write("Node(kind=", self.kind, ", '", self.text, "', msg=", self.msg, ", value=", self.value, ", children=", self.children, ")")


@fieldwise_init
struct View(Copyable, Movable):
    var nodes: List[Node]


def _one(var node: Node) -> View:
    var nodes = List[Node]()
    nodes.append(node^)
    return View(nodes^)


# ---------- leaves ----------

def Text(text: String, style: Int = BODY) -> View:
    """A label. Styles: BODY, TITLE, HEADLINE, CAPTION."""
    return _one(Node(TEXT, text, style=style))


def Button(title: String, on_tap: Int, style: Int = PLAIN) -> View:
    """Sends `on_tap` when tapped. Styles: PLAIN, PROMINENT, DESTRUCTIVE."""
    return _one(Node(BUTTON, title, on_tap, style=style))


def TextField(value: String, placeholder: String = "", on_change: Int = NO_MSG, on_submit: Int = NO_MSG) -> View:
    """One line of text. Sends `on_change` (event.text = new text) as you type
    and `on_submit` when Return is pressed."""
    return _one(Node(FIELD, value, on_change, hint=placeholder, msg2=on_submit))


def Toggle(label: String, on: Bool, on_toggle: Int) -> View:
    """An on/off switch. Sends `on_toggle` with event.number = 1 (on) or 0 (off)."""
    return _one(Node(TOGGLE, label, on_toggle, value=1 if on else 0))


def Dropdown(options: List[String], selected: Int, on_select: Int) -> View:
    """Pick one option. Sends `on_select` with event.number = index, event.text = option."""
    return _one(Node(DROPDOWN, "", on_select, value=selected, options=options.copy()))


def Slider(value: Int, on_change: Int) -> View:
    """A 0–100 slider. Sends `on_change` with event.number = the new value."""
    return _one(Node(SLIDER, "", on_change, value=value))


def ProgressBar(value: Int) -> View:
    """Shows 0–100 progress."""
    return _one(Node(PROGRESS, value=value))


def Image(pixels: List[UInt32], width: Int, height: Int) -> View:
    """A picture from RGBA pixels (row by row; each UInt32 holds R, G, B, A from the low byte up).
    If there aren't exactly width × height pixels, it shows a transparent picture of that size."""
    var w = max(width, 0)
    var h = max(height, 0)
    if len(pixels) != w * h:
        return _one(Node(IMAGE, spacing=w, size=h, pixels=List[UInt32](length=w * h, fill=0)))
    return _one(Node(IMAGE, spacing=w, size=h, pixels=pixels.copy()))


def Divider() -> View:
    return _one(Node(DIVIDER))


def Spacer() -> View:
    return _one(Node(SPACER))


# ---------- containers ----------

def _container(var root: Node, items: List[View]) -> View:
    var nodes = List[Node]()
    nodes.append(root^)
    for item in items:
        var base = len(nodes)
        nodes[0].children.append(base)
        for node in item.nodes:
            var copy = node.copy()
            for i in range(len(copy.children)):
                copy.children[i] += base
            nodes.append(copy^)
    return View(nodes^)


def VStack(*items: View, spacing: Int = 16) -> View:
    """Children top to bottom."""
    var list = List[View]()
    for item in items:
        list.append(item.copy())
    return _container(Node(VSTACK, spacing=spacing), list)


def VStack(items: List[View], spacing: Int = 16) -> View:
    """Children top to bottom, from a list (for rows that come and go)."""
    return _container(Node(VSTACK, spacing=spacing), items)


def HStack(*items: View, spacing: Int = 8) -> View:
    """Children left to right."""
    var list = List[View]()
    for item in items:
        list.append(item.copy())
    return _container(Node(HSTACK, spacing=spacing), list)


def HStack(items: List[View], spacing: Int = 8) -> View:
    return _container(Node(HSTACK, spacing=spacing), items)


def Scroll(content: View, height: Int = 320) -> View:
    """Shows `content`, scrolling when it's taller than `height` points."""
    var list = List[View]()
    list.append(content.copy())
    return _container(Node(SCROLL, size=height), list)
