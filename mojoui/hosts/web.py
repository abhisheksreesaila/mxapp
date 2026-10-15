"""Web host: serves a mojoui app with FastHTML + HTMX.

The app itself is Mojo, compiled as a Python module (`mojoui_app`, built by
`scripts/build.sh <example> web` from hosts/web_main.mojo). This file only turns
its screen (JSON nodes) into HTML and sends browser events back to it.

Run: pixi run python mojoui/hosts/web.py build/hello/web [port]
"""

import importlib
import json
import sys
import uuid
from pathlib import Path

from fasthtml.common import (
    A, Button, Div, FastHTML, H1, H3, Main, NotStr, P, Script, Span, Style, Title, serve,
)

# Node kinds, mirrored from mojoui/view.mojo.
TEXT, BUTTON, VSTACK, HSTACK, SPACER = 1, 2, 3, 4, 5
# Text styles and button styles.
BODY, TITLE, HEADLINE, CAPTION = 0, 1, 2, 3
PLAIN, PROMINENT = 0, 1

CSS = """
:root { color-scheme: light dark; --accent: #0a84ff; --muted: #8e8e93; --surface: rgba(120,120,128,.16); }
* { box-sizing: border-box; }
html, body { margin: 0; height: 100%; }
body { font: 15px/1.4 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; display: grid; place-items: center;
       background: light-dark(#f5f5f7, #1c1c1e); color: light-dark(#1d1d1f, #f5f5f7); }
#mojoui-root { padding: 32px; max-width: 640px; width: 100%; display: flex; justify-content: center; }
.vstack { display: flex; flex-direction: column; align-items: center; }
.hstack { display: flex; flex-direction: row; align-items: center; }
.spacer { flex: 1; }
.text { margin: 0; text-align: center; }
.text.title { font-size: 30px; font-weight: 700; letter-spacing: -.02em; }
.text.headline { font-size: 17px; font-weight: 600; }
.text.caption { font-size: 12px; color: var(--muted); }
button { font: inherit; font-weight: 600; border: 0; border-radius: 999px; padding: 9px 20px; min-height: 40px;
         cursor: pointer; background: var(--surface); color: inherit; transition: transform .08s, filter .15s; }
button:hover { filter: brightness(1.08); }
button:active { transform: scale(.97); }
button.prominent { background: var(--accent); color: #fff; padding: 11px 28px; }
button:focus-visible { outline: 3px solid color-mix(in srgb, var(--accent) 60%, transparent); outline-offset: 2px; }
"""


def render(nodes, i, sid):
    """One mojoui node → FastHTML components (ids n<i> so patches can find them)."""
    n = nodes[i]
    nid = f"n{i}"
    kind = n["kind"]
    if kind == TEXT:
        cls = {TITLE: "text title", HEADLINE: "text headline", CAPTION: "text caption"}.get(n["style"], "text")
        tag = H1 if n["style"] == TITLE else (H3 if n["style"] == HEADLINE else P)
        return tag(n["text"], cls=cls, id=nid)
    if kind == BUTTON:
        return Button(
            n["text"], id=nid, cls="prominent" if n["style"] == PROMINENT else "",
            hx_post=f"/e/{sid}", hx_vals=json.dumps({"n": i}), hx_swap="none",
        )
    if kind == SPACER:
        return Div(cls="spacer", id=nid)
    kids = [render(nodes, c, sid) for c in n["children"]]
    cls = "vstack" if kind == VSTACK else "hstack"
    return Div(*kids, cls=cls, id=nid, style=f"gap:{n['spacing']}px")


def make_app(module_dir):
    sys.path.insert(0, str(Path(module_dir).resolve()))
    mod = importlib.import_module("mojoui_app")
    app = FastHTML(hdrs=(Style(CSS),))
    sessions = {}  # sid → {"handle": int, "nodes": list}

    def root(sid):
        return Main(render(sessions[sid]["nodes"], 0, sid), id="mojoui-root")

    @app.get("/")
    def index():
        sid = uuid.uuid4().hex  # one app session per page load (tab)
        handle = mod.new_session()
        sessions[sid] = {"handle": handle, "nodes": json.loads(mod.view(handle))}
        return Title(mod.title(handle)), root(sid)

    @app.post("/e/{sid}")
    def event(sid: str, n: int):
        s = sessions.get(sid)
        if s is None:
            return Div(P("This page expired: reload it.", cls="text caption"), id="mojoui-root", hx_swap_oob="true")
        message = s["nodes"][n]["msg"]  # look the message up in the current screen
        d = json.loads(mod.event(s["handle"], message))
        if d["rebuild"]:
            s["nodes"] = d["nodes"]
            return Main(render(s["nodes"], 0, sid), id="mojoui-root", hx_swap_oob="true")
        out = []
        for p in d["patches"]:
            node = s["nodes"][p["node"]]
            if p["op"] == 1:  # SET_TEXT
                node["text"] = p["text"]
            elif p["op"] == 2:  # SET_MSG
                node["msg"] = p["msg"]
            if p["op"] == 1:
                el = render(s["nodes"], p["node"], sid)
                el.attrs["hx-swap-oob"] = "true"
                out.append(el)
        return tuple(out) if out else ""

    return app


if __name__ == "__main__":
    module_dir = sys.argv[1] if len(sys.argv) > 1 else "build/hello/web"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 5001
    import uvicorn

    uvicorn.run(make_app(module_dir), host="127.0.0.1", port=port, log_level="warning")
