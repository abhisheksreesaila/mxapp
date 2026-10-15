# The app's logic, shared by the Mac and iPhone versions. No UI code here.


@fieldwise_init
struct Hello(Copyable, Movable):
    var name: String
    var clicks: Int


def greet(mut state: Hello) -> String:
    """Handles one tap of Greet and returns the new text to show."""
    state.clicks += 1
    return "Hello, " + state.name + "! (click " + String(state.clicks) + ")"
