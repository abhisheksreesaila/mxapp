# What an app provides, and the platform-independent loop every host runs.

from mojoui.view import View
from mojoui.diff import Diff, diff


trait App(Movable, Deinitable):
    def __init__(out self):
        """The starting state. Hosts create the app themselves."""
        ...

    def title(self) -> String:
        """The window title."""
        ...

    def update(mut self, message: Int):
        """Changes the state in response to a message (e.g. a button tap)."""
        ...

    def view(self) -> View:
        """Describes the whole screen for the current state."""
        ...


struct Runtime[A: App](Movable):
    """Holds the app and the screen last shown. Hosts call dispatch() on every tap."""

    var app: Self.A
    var shown: View

    def __init__(out self, var app: Self.A):
        self.shown = app.view()
        self.app = app^

    def dispatch(mut self, msg: Int) -> Diff:
        self.app.update(msg)
        var next = self.app.view()
        var d = diff(self.shown, next)
        self.shown = next^
        return d^
