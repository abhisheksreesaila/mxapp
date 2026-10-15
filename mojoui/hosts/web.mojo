# Web host, Mojo side: the app runs inside the Python web server (FastHTML).
# Python calls three functions per app (see hosts/web_main.mojo): start a
# session, get the screen as JSON, and send an event (getting back what changed).
# The HTML is made in Python by mojoui/hosts/web.py.

from std.memory import Pointer
from std.memory.alloc import alloc, Layout

from mojoui.view import View
from mojoui.diff import Diff, SET_TEXT, SET_MSG
from mojoui.app import App, Runtime


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
        out += ',"style":' + String(n.style) + ',"spacing":' + String(n.spacing) + ',"children":['
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
        out += '{"op":' + String(p.op) + ',"node":' + String(p.node) + ',"text":' + json_str(p.text) + ',"msg":' + String(p.msg) + "}"
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


def web_event[A: App](handle: Int, message: Int) -> String:
    var rt = session_at[A](handle)
    var d = rt[].dispatch(message)
    return diff_to_json(d, rt[].shown)


def web_close[A: App](handle: Int):
    var rt = session_at[A](handle)
    rt.unsafe_deinit_pointee()
    rt.unsafe_free()
