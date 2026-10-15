# Web host, Mojo side: the app runs inside the Python web server (FastHTML).
# Python calls three functions per app (see hosts/web_main.mojo): start a
# session, get the screen as JSON, and send an event (getting back what changed).
# The HTML is made in Python by mojoui/hosts/web.py.

from std.memory import Pointer
from std.memory.alloc import alloc, Layout

from mojoui.view import View, DROPDOWN, IMAGE, SEGMENTED, RADIO, TABS, ALERT, LAZYLIST
from mojoui.diff import Diff
from mojoui.app import App, Event, Runtime


def json_str(s: String) -> String:
    """A JSON string literal."""
    var out = String('"')
    for c in s.codepoint_slices():
        if c == '"':
            out += '\\"'
        elif c == "\\":
            out += "\\\\"
        elif c == "\n":
            out += "\\n"
        elif c == "\r":
            out += "\\r"
        elif c == "\t":
            out += "\\t"
        elif c.byte_length() == 1 and Int(c.as_bytes()[0]) < 0x20:  # other control characters
            var b = Int(c.as_bytes()[0])
            out += "\\u00" + String("0123456789abcdef"[byte = b // 16]) + String("0123456789abcdef"[byte = b % 16])
        else:
            out += c
    return out + '"'


def view_to_json(v: View) -> String:
    var out = String("[")
    for i in range(len(v.nodes)):
        ref n = v.nodes[i]
        if i > 0:
            out += ","
        out += '{"kind":' + String(n.kind) + ',"text":' + json_str(n.text) + ',"msg":' + String(n.msg)
        out += ',"style":' + String(n.style) + ',"spacing":' + String(n.spacing) + ',"value":' + String(n.value)
        out += ',"hint":' + json_str(n.hint) + ',"msg2":' + String(n.msg2) + ',"size":' + String(n.size) + ',"options":['
        for j in range(len(n.options)):
            if j > 0:
                out += ","
            out += json_str(n.options[j])
        out += '],"children":['
        for j in range(len(n.children)):
            if j > 0:
                out += ","
            out += String(n.children[j])
        out += "]}"
    return out + "]"


def diff_to_json(d: Diff, shown: View) -> String:
    if d.rebuild:
        return '{"rebuild":true,"nodes":' + view_to_json(shown) + "}"
    var out = String('{"rebuild":false,"patches":[')
    for i in range(len(d.patches)):
        ref p = d.patches[i]
        if i > 0:
            out += ","
        out += '{"op":' + String(p.op) + ',"node":' + String(p.node) + ',"text":' + json_str(p.text) + ',"number":' + String(p.number) + "}"
    return out + "]}"


def session_at[A: App](handle: Int) -> Pointer[Runtime[A], MutUntrackedOrigin]:
    return Pointer[Runtime[A], MutUntrackedOrigin](unsafe_from_address=handle)


def web_new[A: App]() -> Int:
    """Starts one app session (one browser tab) and returns its handle."""
    var rt = alloc(Layout[Runtime[A]].single()).unsafe_leak()
    rt.unsafe_write(Runtime(A()))
    return Int(rt)


def web_title[A: App](handle: Int) -> String:
    return session_at[A](handle)[].app.title()


def web_view[A: App](handle: Int) -> String:
    return view_to_json(session_at[A](handle)[].shown)


def web_event[A: App](handle: Int, node: Int, second: Bool, text: String, number: Int) -> String:
    """A control changed: look its message up in the current screen (like the native
    hosts do), run update(), and return what changed. Bad node → nothing happens."""
    var rt = session_at[A](handle)
    if node < 0 or node >= len(rt[].shown.nodes):
        return '{"ignored":true}'
    ref n = rt[].shown.nodes[node]
    var message = n.msg2 if second else n.msg
    if message == 0:
        return '{"ignored":true}'
    var event_text = text
    if n.kind == DROPDOWN or n.kind == SEGMENTED or n.kind == RADIO or n.kind == TABS or n.kind == ALERT:
        # the option's text comes from the screen, not the browser
        event_text = n.options[number] if 0 <= number < len(n.options) else String("")
    var d = rt[].dispatch(Event(message, event_text, number))
    return diff_to_json(d, rt[].shown)


def web_rows[A: App](handle: Int, node: Int, first: Int, count: Int) -> String:
    """JSON list of row texts first..first+count of a LazyList (asked for on demand)."""
    var rt = session_at[A](handle)
    if node < 0 or node >= len(rt[].shown.nodes) or rt[].shown.nodes[node].kind != LAZYLIST:
        return "[]"
    ref n = rt[].shown.nodes[node]
    var out = String("[")
    var last = min(first + count, n.value)
    for i in range(max(first, 0), last):
        if i > max(first, 0):
            out += ","
        out += json_str(rt[].app.row(n.msg2, i))
    return out + "]"


def web_image[A: App](handle: Int, node: Int) -> String:
    """Where an image's RGBA pixels are: "address width height bytes" (valid until the next event)."""
    var rt = session_at[A](handle)
    if node < 0 or node >= len(rt[].shown.nodes) or rt[].shown.nodes[node].kind != IMAGE:
        return "0 0 0 0"
    ref n = rt[].shown.nodes[node]
    var nbytes = len(n.pixels) * 4
    return String(Int(n.pixels.unsafe_ptr())) + " " + String(n.spacing) + " " + String(n.size) + " " + String(nbytes)


def web_close[A: App](handle: Int):
    var rt = session_at[A](handle)
    rt.unsafe_deinit_pointee()
    rt.unsafe_free()
