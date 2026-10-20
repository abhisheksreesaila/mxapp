# What an app provides, and the platform-independent loop every host runs.

from mojoui.view import View, CANVAS, BOARD, FIELD, PAN, ZOOM, KEY
from mojoui.diff import Diff, diff
from mojoui.canvas import Surface
from mojoui.scene import Scene
from mojoui.theme import Theme


struct Event(Copyable, Movable):
    """What happened: which message, plus any value it carries.

    Buttons: just `message`. TextField: `text` = the field's contents.
    Toggle: `number` = 1 or 0. Dropdown: `number` = index, `text` = option.
    Slider: `number` = 0–100.
    Canvas gestures: `number` = PAN, ZOOM, TAP, PRESS, RELEASE, DOUBLE or KEY (`text` = the key); `x`, `y` = pointer position in the canvas
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

    def describe(self, canvas: Int, first: Int, count: Int) -> String:
        """Canvas `canvas`'s content as text, for an agent (D-163): `count` rows from shown row `first`
        (count 0: what's on screen), tab-separated; "" when the canvas has no text to offer."""
        return ""

    def draw(mut self, canvas: Int, mut surface: Surface):
        """Paints Canvas `canvas` into `surface` (its real pixel size). May update state
        shown elsewhere on screen (e.g. how long drawing took); hosts refresh it afterwards."""
        surface.fill(0)

    def draw_scene(mut self, canvas: Int, mut scene: Scene) -> Bool:
        """Canvas `canvas` as a display list (goal 26): hosts with a GPU path draw it (GTK: render nodes) instead of
        pixels. Returns False (the default) when the canvas only paints pixels (draw())."""
        return False

    def window_size(self) -> Tuple[Int, Int]:
        """The window's starting size in points, on desktops."""
        return (480, 560)

    def resize(mut self, width: Int, height: Int):
        """The window's content area is now width × height points: hosts say so when it opens and whenever it
        changes (a person resizing it, a tiling desktop, a phone turning). Apps that lay out to the window keep
        it; size changes reach the screen as patches, not rebuilds. The default ignores it."""
        pass

    def logo(self) -> String:
        """The app's mark as SVG ("": none): hosts install it as the icon "app-logo" (Icon("app-logo", 18))."""
        return ""

    def theme(self) -> Theme:
        """How the app looks (mojoui.theme.Theme: CSS classes, a palette, a GTK and a web style sheet), built by a theme
        module outside the framework (this repo's themes/, or yours); hosts restyle whenever its key changes (a skin
        picked, a mode's tint). The default is no theme: each platform's own look. Called often: return a kept value."""
        return Theme.native()


def ms(ns: Int) -> String:
    """Nanoseconds as milliseconds with two decimals (for TRACE lines)."""
    var hundredths = Int(ns) // 10_000
    var frac = hundredths % 100
    return String(hundredths // 100) + "." + ("0" if frac < 10 else "") + String(frac)


struct Runtime[A: App](Movable):
    """Holds the app and the screen last shown. Hosts call dispatch() on every event."""

    var app: Self.A
    var shown: View
    var trace: Bool  # MOJOUI_TRACE=1: hosts print each change's time and kind (TRACE: lines); the runtime keeps no clock (Android and iOS link no timing symbols here)

    def __init__(out self, var app: Self.A):
        self.shown = app.view()
        self.app = app^
        self.trace = False  # (hosts that can read the environment turn it on: GTK reads MOJOUI_TRACE; iOS has no getenv)

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

    def resize(mut self, width: Int, height: Int) -> Diff:
        """The window's content area changed size: the app hears it, then the screen catches up."""
        self.app.resize(width, height)
        return self.refresh()

    def draw_scene(mut self, node: Int, mut scene: Scene) -> Tuple[Bool, Diff]:
        """Canvas node `node` as a display list, if the app records one; then what else changed on screen."""
        if node < 0 or node >= len(self.shown.nodes) or self.shown.nodes[node].kind != CANVAS:
            return (False, Diff(False, []))
        if not self.app.draw_scene(self.shown.nodes[node].style, scene):
            return (False, Diff(False, []))
        return (True, self.refresh())

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

    def key(mut self, node: Int, name: String, modifiers: Int) -> Diff:
        """A key pressed while canvas node `node` had focus: its gesture message with number = KEY,
        text = the key's name (or the character typed), dx = modifiers (SHIFT, CTRL, ALT)."""
        if node < 0 or node >= len(self.shown.nodes):
            return Diff(False, [])
        ref n = self.shown.nodes[node]
        if n.kind != CANVAS or n.msg == 0:
            return Diff(False, [])
        return self.dispatch(Event(n.msg, name, KEY, 0, 0, Float64(modifiers), 0, 1))

    def cancel(mut self, node: Int, text: String) -> Diff:
        """Escape in field node `node`: its on_cancel message (event.text = the field's text)."""
        if node < 0 or node >= len(self.shown.nodes) or self.shown.nodes[node].kind != FIELD or self.shown.nodes[node].size == 0:
            return Diff(False, [])
        return self.dispatch(Event(self.shown.nodes[node].size, text, 0))

    def frame(mut self, node: Int, microseconds: Int) -> Diff:
        """One display frame for canvas node `node` (only if it asked for frames)."""
        if node < 0 or node >= len(self.shown.nodes) or self.shown.nodes[node].kind != CANVAS or self.shown.nodes[node].msg2 == 0:
            return Diff(False, [])
        return self.dispatch(Event(self.shown.nodes[node].msg2, "", microseconds))
