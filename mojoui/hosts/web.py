"""Web host: serves a mojoui app with FastHTML + HTMX.

The app itself is Mojo, compiled as a Python module (`mojoui_app`, built by
`scripts/build.sh <example> web` from hosts/web_main.mojo). This file only turns
its screen (JSON nodes) into plain HTML controls and sends browser events back.
Every control is standard HTML (input, select, range, progress, img), so the
browser draws its own native widgets; HTMX (vendored in static/, pinned 2.0.7)
posts events, with no custom JavaScript.

Run: pixi run python mojoui/hosts/web.py build/hello/web [port]
"""

import ctypes
import importlib
import json
import struct
import sys
import threading
import uuid
import zlib
from collections import OrderedDict
from pathlib import Path

from fasthtml.common import (
    Button, Div, FastHTML, Form, H1, H3, Hr, Img, Input, Label, Main, Meta, Option, P, Progress, Response, Script,
    Select, Span, Style, Title,
)

# Mirrors mojoui/view.mojo and mojoui/diff.mojo.
TEXT, BUTTON, VSTACK, HSTACK, SPACER, FIELD, TOGGLE, DROPDOWN, SLIDER, PROGRESS, DIVIDER, SCROLL, IMAGE = range(1, 14)
BODY, TITLE, HEADLINE, CAPTION = 0, 1, 2, 3
PLAIN, PROMINENT, DESTRUCTIVE = 0, 1, 2
SET_TEXT, SET_MSG, SET_VALUE, SET_IMAGE = 1, 2, 3, 4
MAX_SESSIONS = 200  # oldest tabs are closed beyond this
STATIC = Path(__file__).parent / "static"

CSS = """
:root { color-scheme: light dark; --accent: #0a84ff; --danger: #ff453a; --muted: #8e8e93;
        --surface: rgba(120,120,128,.16); --line: rgba(120,120,128,.28); }
* { box-sizing: border-box; }
html, body { margin: 0; }
body { font: 16px/1.4 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; display: grid; place-items: center;
       min-height: 100dvh; padding: env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left);
       background: light-dark(#f5f5f7, #1c1c1e); color: light-dark(#1d1d1f, #f5f5f7); }
#mojoui-root { padding: 32px 20px; width: 100%; max-width: 560px; display: flex; justify-content: center; }
.vstack { display: flex; flex-direction: column; align-items: center; }
.hstack { display: flex; flex-direction: row; align-items: center; flex-wrap: wrap; justify-content: center; }
.spacer { flex: 1; }
.text { margin: 0; text-align: center; }
.text.title { font-size: 30px; font-weight: 700; letter-spacing: -.02em; }
.text.headline { font-size: 17px; font-weight: 600; }
.text.caption { font-size: 13px; color: var(--muted); }
button { font: inherit; font-weight: 600; border: 0; border-radius: 999px; padding: 10px 20px; min-height: 48px;
         cursor: pointer; background: var(--surface); color: inherit; transition: transform .08s, filter .15s; }
button:hover { filter: brightness(1.08); }
button:active { transform: scale(.97); }
button.prominent { background: var(--accent); color: #fff; padding: 10px 26px; }
button.destructive { color: var(--danger); }
:focus-visible { outline: 3px solid color-mix(in srgb, var(--accent) 60%, transparent); outline-offset: 2px; }
form.field { margin: 0; }
input[type=text] { font: inherit; width: 220px; max-width: 70vw; min-height: 48px; padding: 8px 12px; border-radius: 12px;
                   border: 1px solid var(--line); background: light-dark(#fff, #2c2c2e); color: inherit; }
label.toggle { display: inline-flex; gap: 10px; align-items: center; min-height: 48px; cursor: pointer; }
label.toggle input { width: 22px; height: 22px; accent-color: var(--accent); }
select { font: inherit; min-height: 48px; padding: 6px 12px; border-radius: 12px; border: 1px solid var(--line);
         background: light-dark(#fff, #2c2c2e); color: inherit; }
input[type=range] { width: 240px; min-height: 48px; accent-color: var(--accent); }
progress { width: 240px; height: 8px; accent-color: var(--accent); }
hr { width: 280px; border: 0; border-top: 1px solid var(--line); margin: 4px 0; }
img.image { max-width: 100%; height: auto; border-radius: 12px; image-rendering: auto; }
.scroll { overflow-y: auto; width: 100%; display: flex; justify-content: center; }
@media (prefers-reduced-motion: reduce) { button { transition: none; } button:active { transform: none; } }
"""


def png(rgba, w, h):
    """Encodes RGBA bytes as a PNG (no dependencies: zlib + the PNG chunk format)."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    rows = b"".join(b"\x00" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b""))


class Session:
    """One browser tab: its Mojo app, the screen last sent, and a lock so its events run one at a time."""

    def __init__(self, mod):
        self.mod = mod
        self.handle = mod.new_session()
        self.nodes = json.loads(mod.view(self.handle))
        self.shape = 0  # bumps on every rebuild; node numbers only mean something within one shape
        self.images = {}  # node → version, for cache-busting image URLs
        self.focus = None  # field to focus after the next rebuild
        self.lock = threading.Lock()


def render(s, i, sid):
    """One mojoui node → FastHTML components. Ids are n<i> so patches can find them;
    data-kind marks controls for tests and for anyone reading the HTML."""
    n = s.nodes[i]
    nid, kind, post = f"n{i}", n["kind"], f"/e/{sid}"
    vals = json.dumps({"n": i})
    common = dict(hx_post=post, hx_vals=vals, hx_swap="none", hx_include="#mojoui-v")
    if kind == TEXT:
        cls = {TITLE: "text title", HEADLINE: "text headline", CAPTION: "text caption"}.get(n["style"], "text")
        tag = H1 if n["style"] == TITLE else (H3 if n["style"] == HEADLINE else P)
        return tag(n["text"], cls=cls, id=nid, data_kind="label")
    if kind == BUTTON:
        cls = {PROMINENT: "prominent", DESTRUCTIVE: "destructive"}.get(n["style"], "")
        return Button(n["text"], id=nid, cls=cls, data_kind="button", **common)
    if kind == FIELD:
        # The form makes Return submit (on_submit); typing posts on_change. Both go through
        # the form's queue, so a fast Return can't overtake the typing it follows.
        field = Input(type="text", name="text", value=n["text"], placeholder=n["hint"], data_kind="field",
                      autocomplete="off", autofocus=(s.focus == i), hx_trigger="input",
                      hx_sync="closest form:queue all", **common)
        return Form(field, cls="field", id=nid, hx_post=post, hx_vals=json.dumps({"n": i, "second": 1}),
                    hx_swap="none", hx_include="#mojoui-v", hx_sync="this:queue all")
    if kind == TOGGLE:
        box = Input(type="checkbox", name="on", checked=bool(n["value"]), hx_trigger="change", **common)
        return Label(box, Span(n["text"]), cls="toggle", id=nid, data_kind="toggle")
    if kind == DROPDOWN:
        opts = [Option(o, value=str(j), selected=(j == n["value"])) for j, o in enumerate(n["options"])]
        return Select(*opts, name="number", id=nid, data_kind="dropdown", hx_trigger="change", **common)
    if kind == SLIDER:
        return Input(type="range", min="0", max="100", value=str(n["value"]), name="number", id=nid,
                     data_kind="slider", hx_trigger="input changed delay:60ms", **common)
    if kind == PROGRESS:
        return Progress(value=str(n["value"]), max="100", id=nid, data_kind="progress")
    if kind == IMAGE:
        return Img(src=f"/img/{sid}/{i}?v={s.shape}.{s.images.get(i, 0)}", width=str(n["spacing"]),
                   height=str(n["size"]), id=nid, cls="image", data_kind="image", alt="")
    if kind == DIVIDER:
        return Hr(id=nid)
    if kind == SPACER:
        return Div(cls="spacer", id=nid)
    kids = [render(s, c, sid) for c in n["children"]]
    if kind == SCROLL:
        return Div(*kids, cls="scroll", id=nid, style=f"max-height:{n['size']}px")
    cls = "vstack" if kind == VSTACK else "hstack"
    return Div(*kids, cls=cls, id=nid, style=f"gap:{n['spacing']}px")


def make_app(module_dir):
    sys.path.insert(0, str(Path(module_dir).resolve()))
    mod = importlib.import_module("mojoui_app")
    app = FastHTML(default_hdrs=False, secret_key=uuid.uuid4().hex, hdrs=(  # no .sesskey file
        Meta(charset="utf-8"), Meta(name="viewport", content="width=device-width, initial-scale=1, viewport-fit=cover"),
        Script(src="/static/htmx.min.js"), Style(CSS)))
    sessions = OrderedDict()  # sid → Session, oldest first
    sessions_lock = threading.Lock()

    def root(s, sid, oob=False):
        version = Input(type="hidden", id="mojoui-v", name="v", value=str(s.shape))
        el = Main(version, render(s, 0, sid), id="mojoui-root")
        if oob:
            el.attrs["hx-swap-oob"] = "true"
        return el

    @app.get("/static/htmx.min.js")
    def htmx_js():
        return Response((STATIC / "htmx.min.js").read_bytes(), media_type="text/javascript",
                        headers={"Cache-Control": "public, max-age=86400"})

    @app.get("/")
    def index():
        sid = uuid.uuid4().hex  # one app session per page load (tab)
        s = Session(mod)
        with sessions_lock:
            sessions[sid] = s
            while len(sessions) > MAX_SESSIONS:
                _, old = sessions.popitem(last=False)
                with old.lock:
                    mod.close(old.handle)
        return Title(mod.title(s.handle)), root(s, sid)

    @app.get("/img/{sid}/{n}")
    def image(sid: str, n: int):
        s = sessions.get(sid)
        if s is None:
            return Response(status_code=404)
        with s.lock:  # the pixels belong to the current screen: read them before any other event
            addr, w, h = map(int, mod.image(s.handle, n).split())
            if not addr:
                return Response(status_code=404)
            data = png(ctypes.string_at(addr, w * h * 4), w, h)
        return Response(data, media_type="image/png", headers={"Cache-Control": "no-store"})

    @app.post("/e/{sid}")
    def event(sid: str, n: int, v: int = -1, second: int = 0, text: str = "", number: int = 0, on: str = ""):
        s = sessions.get(sid)
        if s is None:
            return Main(P("This page expired: reload it.", cls="text caption"), id="mojoui-root", hx_swap_oob="true")
        with s.lock:
            if v != s.shape or not 0 <= n < len(s.nodes):
                return ""  # from an older screen (e.g. a double click on a row that's gone): ignore
            source = s.nodes[n]
            if source["kind"] == TOGGLE:
                number = 1 if on else 0
            d = json.loads(mod.event(s.handle, n, second, text, number))
            if d.get("ignored"):
                return ""
            s.nodes = json.loads(mod.view(s.handle))  # the screen as Mojo now has it
            if d["rebuild"]:
                s.shape += 1
                s.images.clear()
                s.focus = n if source["kind"] == FIELD and n < len(s.nodes) and s.nodes[n]["kind"] == FIELD else None
                out = root(s, sid, oob=True)
                s.focus = None
                return out
            changed = []
            for p in d["patches"]:
                i, op = p["node"], p["op"]
                target = s.nodes[i]
                if op == SET_IMAGE:
                    s.images[i] = s.images.get(i, 0) + 1
                # Don't re-send the control in use if it already shows this (that would steal
                # focus or interrupt a drag); other changes to it still go out.
                echo = i == n and ((op == SET_TEXT and target["kind"] == FIELD and target["text"] == text)
                                   or (op == SET_VALUE and target["kind"] in (TOGGLE, DROPDOWN, SLIDER)
                                       and target["value"] == number))
                if op != SET_MSG and not echo and i not in changed:
                    changed.append(i)
            out = []
            for i in changed:
                el = render(s, i, sid)
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
