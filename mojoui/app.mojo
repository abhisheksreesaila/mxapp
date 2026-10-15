# What an app provides, and the platform-independent loop every host runs.

from mojoui.view import View
from mojoui.diff import Diff, diff


@fieldwise_init
struct Event(Copyable, Movable):
    """What happened: which message, plus any value it carries.

    Buttons: just `message`. TextField: `text` = the field's contents.
    Toggle: `number` = 1 or 0. Dropdown: `number` = index, `text` = option.
    Slider: `number` = 0–100.
    """

    var message: Int
    var text: String
    var number: Int


trait App(Movable, Deinitable):
    def __init__(out self):
        """The starting state. Hosts create the app themselves."""
        ...

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
