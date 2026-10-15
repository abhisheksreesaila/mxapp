# The declarative layer: a screen is a value (a View) built from small pieces.
#
#   VStack(Text("Hello", style=TITLE), Button("Greet", on_tap=GREET))
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

# Text styles (each platform maps them to its own type scale)
comptime BODY = 0
comptime TITLE = 1
comptime HEADLINE = 2
comptime CAPTION = 3

# Button styles
comptime PLAIN = 0
comptime PROMINENT = 1

comptime NO_MSG = 0


@fieldwise_init
struct Node(Copyable, Movable, Equatable, Writable):
    var kind: Int
    var text: String  # label text or button title
    var msg: Int  # message sent when a button is tapped
    var style: Int
    var spacing: Int  # stacks: gap between children, in points
    var children: List[Int]

    def __eq__(self, other: Self) -> Bool:
        return (
            self.kind == other.kind
            and self.text == other.text
            and self.msg == other.msg
            and self.style == other.style
            and self.spacing == other.spacing
            and self.children == other.children
        )

    def write_to(self, mut writer: Some[Writer]):
        writer.write("Node(", self.kind, ", '", self.text, "', msg=", self.msg, ", style=", self.style, ", children=", self.children, ")")


@fieldwise_init
struct View(Copyable, Movable):
    var nodes: List[Node]

    def root(self) -> ref[self.nodes] Node:
        return self.nodes[0]


def _leaf(kind: Int, text: String, msg: Int, style: Int) -> View:
    var nodes = List[Node]()
    nodes.append(Node(kind, text, msg, style, 0, List[Int]()))
    return View(nodes^)


def Text(text: String, style: Int = BODY) -> View:
    return _leaf(TEXT, text, NO_MSG, style)


def Button(title: String, on_tap: Int, style: Int = PLAIN) -> View:
    return _leaf(BUTTON, title, on_tap, style)


def Spacer() -> View:
    return _leaf(SPACER, "", NO_MSG, BODY)


def _stack(kind: Int, items: List[View], spacing: Int) -> View:
    var nodes = List[Node]()
    nodes.append(Node(kind, "", NO_MSG, BODY, spacing, List[Int]()))
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
    return _stack(VSTACK, list, spacing)


def VStack(items: List[View], spacing: Int = 16) -> View:
    """Children top to bottom, from a list (for rows that come and go)."""
    return _stack(VSTACK, items, spacing)


def HStack(*items: View, spacing: Int = 8) -> View:
    """Children left to right."""
    var list = List[View]()
    for item in items:
        list.append(item.copy())
    return _stack(HSTACK, list, spacing)


def HStack(items: List[View], spacing: Int = 8) -> View:
    return _stack(HSTACK, items, spacing)
