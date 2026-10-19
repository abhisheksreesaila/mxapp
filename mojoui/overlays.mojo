# mojoui.overlays: what floats over the page, the same on every host: a Dialog with a scrim, a Toast with an action,
# a Popover anchored to a view, a Checkbox, and a tooltip on any view.
#
#   Dialog("Settings", VStack(…, Button("Done", DONE, PROMINENT)), on_close=DONE)      # modal; Escape and ✕ send on_close
#   Toast("Sorted by revenue, largest first", "Undo", UNDO, on_close=TOAST_GONE)    # bottom centre; goes by itself after a while
#   Popover("formula-bar", "Formulas", VStack(…), on_close=POP_CLOSE)               # under the view tagged "formula-bar"
#   Checkbox("Show GPU timings", on, TIMINGS)                                        # a box with a tick (Toggle is the switch)
#   Button("Save", SAVE, icon="save").tooltip("Save the document (Ctrl+S)")
#
# Like a context menu, a dialog, toast or popover is part of the view while it shows: the app puts it in the tree
# and takes it out on its on_close (a click elsewhere, Escape, ✕, the toast's time running out) or its own buttons.

from mojoui.view import View, Node, DIALOG, TOAST, POPOVER, TOGGLE, CLIPBOARD, _one, _container


def Dialog(title: String, content: View, on_close: Int, width: Int = 560) -> View:
    """A modal panel over a dimmed page: a title bar with ✕, then `content` (its own buttons close it)."""
    var n = Node(DIALOG, title)
    n.msg2 = on_close
    n.w = width
    var items = List[View]()
    items.append(content.copy())
    return _container(n^, items)


def Clipboard(text: String, version: Int) -> View:
    """Puts `text` on the system clipboard each time `version` changes (0: nothing yet). Keep it in the screen while the
    app can copy, bump the version on Copy: the hosts copy declaratively, as they show a toast."""
    var n = Node(CLIPBOARD, text)
    n.value = version
    return _one(n^)


def Toast(text: String, action: String = "", on_action: Int = 0, on_close: Int = 0, seconds: Int = 6) -> View:
    """A short message at the bottom of the window, with one action (Undo); it leaves by itself after `seconds`."""
    var n = Node(TOAST, text, on_action)
    if action != "":
        n.options.append(action)
    n.msg2 = on_close
    n.size = seconds
    return _one(n^)


def Popover(anchor: String, title: String, content: View, on_close: Int, x: Int = 0, y: Int = 0) -> View:
    """A small panel attached to the view tagged `anchor` (below it, or at (x, y) inside it)."""
    var n = Node(POPOVER, anchor)
    n.hint = title
    n.msg2 = on_close
    n.x = x
    n.y = y
    var items = List[View]()
    items.append(content.copy())
    return _container(n^, items)


def Checkbox(label: String, on: Bool, on_toggle: Int) -> View:
    """A box with a tick. Sends `on_toggle` with event.number = 1 (ticked) or 0."""
    return _one(Node(TOGGLE, label, on_toggle, style=1, value=1 if on else 0))
