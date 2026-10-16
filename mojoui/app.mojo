# What an app provides, and the platform-independent loop every host runs.

from mojoui.view import View, CANVAS, BOARD, PAN, ZOOM
from mojoui.diff import Diff, diff
from mojoui.canvas import Surface


struct Event(Copyable, Movable):
    """What happened: which message, plus any value it carries.

    Buttons: just `message`. TextField: `text` = the field's contents.
    Toggle: `number` = 1 or 0. Dropdown: `number` = index, `text` = option.
    Slider: `number` = 0–100.
    Canvas gestures: `number` = PAN, ZOOM or TAP; `x`, `y` = pointer position in the canvas
    (points from its top-left); PAN: `dx`, `dy` = movement in points; ZOOM: `zoom` = scale factor.
    Canvas frames: `number` = microseconds since the previous frame.
    """

    var message: Int
    var text: String
    var number: Int
    var x: Float64
    var y: Float64
    var dx: Float64
    var dy: Float64
    var zoom: Float64

    def __init__(
        out self, message: Int, text: String, number: Int,
        x: Float64 = 0, y: Float64 = 0, dx: Float64 = 0, dy: Float64 = 0, zoom: Float64 = 1,
    ):
        self.message = message
        self.text = text
        self.number = number
        self.x = x
        self.y = y
        self.dx = dx
        self.dy = dy
        self.zoom = zoom


trait App(Movable, Deinitable):
    def __init__(out self):
        """The starting state. Hosts create the app themselves."""
        ...

    @staticmethod
    def init_shared():
        """Builds what every session of a process shares (large read-only data, GPU buffers), once,
        before the first session; see mojoui.shared. Sessions find it with get_shared()."""
        pass

    def title(self) -> String:
        """The window title."""
        ...

    def update(mut self, event: Event):
        """Changes the state in response to an event (a tap, typing, a toggle…)."""
        ...

    def view(self) -> View:
        """Describes the whole screen for the current state."""
        ...

    def row(self, list_id: Int, index: Int) -> String:
        """The text of one row of a LazyList (hosts ask only for rows on screen)."""
        return ""

    def draw(mut self, canvas: Int, mut surface: Surface):
        """Paints Canvas `canvas` into `surface` (its real pixel size). May update state
        shown elsewhere on screen (e.g. how long drawing took); hosts refresh it afterwards."""
        surface.fill(0)

    def window_size(self) -> Tuple[Int, Int]:
        """The window's starting size in points, on desktops."""
        return (480, 560)

    def design(self) -> Int:
        """The design language hosts style native controls with: NATIVE (default) or FLUENT."""
        return 0


struct Runtime[A: App](Movable):
    """Holds the app and the screen last shown. Hosts call dispatch() on every event."""

    var app: Self.A
    var shown: View

    def __init__(out self, var app: Self.A):
        self.shown = app.view()
        self.app = app^

    def dispatch(mut self, event: Event) -> Diff:
        self.app.update(event)
        var next = self.app.view()
        var d = diff(self.shown, next)
        self.shown = next^
        return d^

    def dispatch(mut self, message: Int) -> Diff:
        """A plain message with no value (a button tap)."""
        return self.dispatch(Event(message, "", 0))

    def refresh(mut self) -> Diff:
        """The screen again after state changed outside update() (e.g. in draw())."""
        var next = self.app.view()
        var d = diff(self.shown, next)
        self.shown = next^
        return d^

    def draw(mut self, node: Int, mut surface: Surface) -> Diff:
        """Paints canvas node `node`, then returns what else changed on screen."""
        if node < 0 or node >= len(self.shown.nodes) or self.shown.nodes[node].kind != CANVAS:
            return Diff(False, [])
        self.app.draw(self.shown.nodes[node].style, surface)
        return self.refresh()

    def gesture(mut self, node: Int, kind: Int, x: Float64, y: Float64, dx: Float64, dy: Float64, zoom: Float64) -> Diff:
        """A gesture on canvas node `node` (PAN, ZOOM or TAP); on a Board node, a child moved
        (PAN: x = the child's index, dx/dy = how far) or resized (ZOOM: the same fields)."""
        if node < 0 or node >= len(self.shown.nodes):
            return Diff(False, [])
        ref n = self.shown.nodes[node]
        if n.kind == BOARD:
            var msg = n.msg if kind == PAN else (n.msg2 if kind == ZOOM else 0)
            if msg == 0:
                return Diff(False, [])
            return self.dispatch(Event(msg, "", Int(x), x, y, dx, dy, zoom))
        if n.kind != CANVAS or n.msg == 0:
            return Diff(False, [])
        return self.dispatch(Event(n.msg, "", kind, x, y, dx, dy, zoom))

    def frame(mut self, node: Int, microseconds: Int) -> Diff:
        """One display frame for canvas node `node` (only if it asked for frames)."""
        if node < 0 or node >= len(self.shown.nodes) or self.shown.nodes[node].kind != CANVAS or self.shown.nodes[node].msg2 == 0:
            return Diff(False, [])
        return self.dispatch(Event(self.shown.nodes[node].msg2, "", microseconds))
