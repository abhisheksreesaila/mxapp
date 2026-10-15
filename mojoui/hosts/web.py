"""Web host: serves a mojoui app with FastHTML + HTMX.

The app itself is Mojo, compiled as a Python module (`mojoui_app`, built by
`scripts/build.sh <example> web` from hosts/web_main.mojo). This file only turns
its screen (JSON nodes) into plain HTML controls and sends browser events back.
Every control is standard HTML (input, select, range, progress), so the browser
draws its own native widgets; HTMX posts events, with no custom JavaScript.

Run: pixi run python mojoui/hosts/web.py build/hello/web [port]
"""

import importlib
import json
import sys
import uuid
from pathlib import Path

from fasthtml.common import (
    Button, Div, FastHTML, Form, H1, H3, Hr, Input, Label, Main, Option, P, Progress, Select, Span, Style, Title,
)

# Mirrors mojoui/view.mojo and mojoui/diff.mojo.
TEXT, BUTTON, VSTACK, HSTACK, SPACER, FIELD, TOGGLE, DROPDOWN, SLIDER, PROGRESS, DIVIDER, SCROLL = range(1, 13)
BODY, TITLE, HEADLINE, CAPTION = 0, 1, 2, 3
PLAIN, PROMINENT, DESTRUCTIVE = 0, 1, 2
SET_TEXT, SET_MSG, SET_VALUE = 1, 2, 3

CSS = """
:root { color-scheme: light dark; --accent: #0a84ff; --danger: #ff453a; --muted: #8e8e93;
        --surface: rgba(120,120,128,.16); --line: rgba(120,120,128,.28); }
* { box-sizing: border-box; }
html, body { margin: 0; min-height: 100%; }
body { font: 15px/1.4 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; display: grid; place-items: center;
       min-height: 100vh; background: light-dark(#f5f5f7, #1c1c1e); color: light-dark(#1d1d1f, #f5f5f7); }
#mojoui-root { padding: 32px 20px; width: 100%; max-width: 560px; display: flex; justify-content: center; }
.vstack { display: flex; flex-direction: column; align-items: center; }
.hstack { display: flex; flex-direction: row; align-items: center; }
.spacer { flex: 1; }
.text { margin: 0; text-align: center; }
.text.title { font-size: 30px; font-weight: 700; letter-spacing: -.02em; }
.text.headline { font-size: 17px; font-weight: 600; }
.text.caption { font-size: 12px; color: var(--muted); }
button { font: inherit; font-weight: 600; border: 0; border-radius: 999px; padding: 9px 18px; min-height: 40px;
         cursor: pointer; background: var(--surface); color: inherit; transition: transform .08s, filter .15s; }
button:hover { filter: brightness(1.08); }
button:active { transform: scale(.97); }
button.prominent { background: var(--accent); color: #fff; padding: 11px 26px; }
button.destructive { color: var(--danger); }
:focus-visible { outline: 3px solid color-mix(in srgb, var(--accent) 60%, transparent); outline-offset: 2px; }
form.field { margin: 0; }
input[type=text] { font: inherit; width: 220px; min-height: 40px; padding: 8px 12px; border-radius: 10px;
                   border: 1px solid var(--line); background: light-dark(#fff, #2c2c2e); color: inherit; }
label.toggle { display: inline-flex; gap: 8px; align-items: center; min-height: 40px; cursor: pointer; }
label.toggle input { width: 20px; height: 20px; accent-color: var(--accent); }
select { font: inherit; min-height: 40px; padding: 6px 10px; border-radius: 10px; border: 1px solid var(--line);
         background: light-dark(#fff, #2c2c2e); color: inherit; }
input[type=range] { width: 240px; accent-color: var(--accent); }
progress { width: 240px; height: 8px; accent-color: var(--accent); }
hr { width: 280px; border: 0; border-top: 1px solid var(--line); margin: 4px 0; }
.scroll { overflow-y: auto; width: 100%; display: flex; justify-content: center; }
"""


def render(nodes, i, sid):
    """One mojoui node → FastHTML components. Ids are n<i> so patches can find them;
    data-kind marks controls for tests and for anyone reading the HTML."""
    n = nodes[i]
    nid, kind, post = f"n{i}", n["kind"], f"/e/{sid}"
    vals = json.dumps({"n": i})
    if kind == TEXT:
        cls = {TITLE: "text title", HEADLINE: "text headline", CAPTION: "text caption"}.get(n["style"], "text")
        tag = H1 if n["style"] == TITLE else (H3 if n["style"] == HEADLINE else P)
        return tag(n["text"], cls=cls, id=nid, data_kind="label")
    if kind == BUTTON:
        cls = {PROMINENT: "prominent", DESTRUCTIVE: "destructive"}.get(n["style"], "")
        return Button(n["text"], id=nid, cls=cls, data_kind="button", hx_post=post, hx_vals=vals, hx_swap="none")
    if kind == FIELD:
        # The form makes Return submit (on_submit); typing posts on_change as you go.
        field = Input(type="text", name="text", value=n["text"], placeholder=n["hint"], data_kind="field",
                      autocomplete="off", hx_post=post, hx_vals=json.dumps({"n": i, "kind": "change"}),
                      hx_trigger="input changed delay:150ms", hx_swap="none")
        return Form(field, cls="field", id=nid, hx_post=post, hx_vals=json.dumps({"n": i, "kind": "submit"}),
                    hx_swap="none", hx_sync="this:queue last")
    if kind == TOGGLE:
        box = Input(type="checkbox", name="on", checked=bool(n["value"]), hx_post=post, hx_vals=vals,
                    hx_trigger="change", hx_swap="none")
        return Label(box, Span(n["text"]), cls="toggle", id=nid, data_kind="toggle")
    if kind == DROPDOWN:
        opts = [Option(o, value=str(j), selected=(j == n["value"])) for j, o in enumerate(n["options"])]
        return Select(*opts, name="number", id=nid, data_kind="dropdown", hx_post=post, hx_vals=vals,
                      hx_trigger="change", hx_swap="none")
    if kind == SLIDER:
        return Input(type="range", min="0", max="100", value=str(n["value"]), name="number", id=nid, data_kind="slider",
                     hx_post=post, hx_vals=vals, hx_trigger="input changed delay:80ms", hx_swap="none")
    if kind == PROGRESS:
        return Progress(value=str(n["value"]), max="100", id=nid, data_kind="progress")
    if kind == DIVIDER:
        return Hr(id=nid)
    if kind == SPACER:
        return Div(cls="spacer", id=nid)
    kids = [render(nodes, c, sid) for c in n["children"]]
    if kind == SCROLL:
        return Div(*kids, cls="scroll", id=nid, style=f"max-height:{n['size']}px")
    cls = "vstack" if kind == VSTACK else "hstack"
    return Div(*kids, cls=cls, id=nid, style=f"gap:{n['spacing']}px")


def make_app(module_dir):
    sys.path.insert(0, str(Path(module_dir).resolve()))
    mod = importlib.import_module("mojoui_app")
    app = FastHTML(hdrs=(Style(CSS),))
    sessions = {}  # sid → {"handle": int, "nodes": list}

    def root(sid, oob=False):
        el = Main(render(sessions[sid]["nodes"], 0, sid), id="mojoui-root")
        if oob:
            el.attrs["hx-swap-oob"] = "true"
        return el

    @app.get("/")
    def index():
        sid = uuid.uuid4().hex  # one app session per page load (tab)
        handle = mod.new_session()
        sessions[sid] = {"handle": handle, "nodes": json.loads(mod.view(handle))}
        return Title(mod.title(handle)), root(sid)

    @app.post("/e/{sid}")
    def event(sid: str, n: int, kind: str = "change", text: str = "", number: int = 0, on: str = ""):
        s = sessions.get(sid)
        if s is None:
            return Main(P("This page expired: reload it.", cls="text caption"), id="mojoui-root", hx_swap_oob="true")
        node = s["nodes"][n]
        message = node["msg2"] if kind == "submit" else node["msg"]  # looked up in the current screen
        if not message:
            return ""
        if node["kind"] == TOGGLE:
            number = 1 if on else 0
        if node["kind"] == DROPDOWN:
            text = node["options"][number] if 0 <= number < len(node["options"]) else ""
        d = json.loads(mod.event(s["handle"], message, text, number))
        if d["rebuild"]:
            s["nodes"] = d["nodes"]
            return root(sid, oob=True)
        changed = []
        for p in d["patches"]:
            target = s["nodes"][p["node"]]
            if p["op"] == SET_TEXT:
                target["text"] = p["text"]
            elif p["op"] == SET_MSG:
                target["msg"] = p["number"]
            elif p["op"] == SET_VALUE:
                target["value"] = p["number"]
            # Don't re-send the control the person is using if it already shows this value
            # (replacing it would steal focus or interrupt a drag).
            source_echo = p["node"] == n and (
                (target["kind"] == FIELD and target["text"] == text)
                or (target["kind"] in (TOGGLE, DROPDOWN, SLIDER) and target["value"] == number))
            if p["op"] != SET_MSG and not source_echo and p["node"] not in changed:
                changed.append(p["node"])
        out = []
        for i in changed:
            el = render(s["nodes"], i, sid)
            el.attrs["hx-swap-oob"] = "true"
            out.append(el)
        return tuple(out) if out else ""

    return app


if __name__ == "__main__":
    module_dir = sys.argv[1] if len(sys.argv) > 1 else "build/hello/web"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 5001
    import uvicorn

    print(f"mojoui web: http://127.0.0.1:{port}/", flush=True)
    uvicorn.run(make_app(module_dir), host="127.0.0.1", port=port, log_level="warning")
