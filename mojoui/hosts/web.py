"""Web host: serves a mojoui app with FastHTML + HTMX.

The app itself is Mojo, compiled as a Python module (`mojoui_app`, built by
`scripts/build.sh <example> web` from hosts/web_main.mojo). This file only turns
its screen (JSON nodes) into plain HTML controls and sends browser events back.
Every control is standard HTML (input, select, range, progress, img), so the
browser draws its own native widgets; HTMX (vendored in static/, pinned 2.0.7)
posts events. The one piece of JavaScript is CANVAS_JS below, a fixed adapter for
Canvas views: it streams the frames the Mojo app paints (JPEG, pulled one at a time,
so a slow link just gets fewer frames) and sends pointer gestures back as events.

Run: pixi run python mojoui/hosts/web.py build/hello/web [port]
"""

import ctypes
import importlib
import io
import json
import time
import struct
import sys
import threading
import uuid
import zlib
from collections import OrderedDict
from pathlib import Path

from fasthtml.common import (
    Button, Canvas, Dialog, Div, FastHTML, Form, H1, H2, H3, Header, Hr, I, Img, Input, Label, Main, Meta, NotStr,
    Option, P, Progress, Response, Script, Select, Span, Style, Textarea, Title,
)
from PIL import Image

# Mirrors mojoui/view.mojo and mojoui/diff.mojo.
(TEXT, BUTTON, VSTACK, HSTACK, SPACER, FIELD, TOGGLE, DROPDOWN, SLIDER, PROGRESS, DIVIDER, SCROLL, IMAGE,
 SEGMENTED, RADIO, TEXTAREA, ALERT, TABS, NAVBAR, DATE, ICON, GRID, LAZYLIST, CANVAS) = range(1, 25)
CHOICES = (DROPDOWN, SEGMENTED, RADIO, TABS)  # value = selected index
BODY, TITLE, HEADLINE, CAPTION = 0, 1, 2, 3
PLAIN, PROMINENT, DESTRUCTIVE = 0, 1, 2
SET_TEXT, SET_MSG, SET_VALUE, SET_IMAGE, SET_FRAMES = 1, 2, 3, 4, 5
JPEG_QUALITY = 85
MAX_SESSIONS = 200  # oldest tabs are closed beyond this
STATIC = Path(__file__).parent / "static"
ICONS = {p.stem: p.read_text().split("-->", 1)[-1].strip() for p in (STATIC / "icons").glob("*.svg")}  # Lucide (ISC)
LIST_WINDOW = 30  # rows sent around the visible part of a LazyList

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
form.field { display: flex; }
input[type=text] { font: inherit; width: var(--control-width, 220px); max-width: 70vw; min-height: 48px; padding: 8px 12px; border-radius: 12px;
                   border: 1px solid var(--line); background: light-dark(#fff, #2c2c2e); color: inherit; }
label.toggle { display: inline-flex; gap: 10px; align-items: center; min-height: 48px; cursor: pointer; }
label.toggle input { width: 22px; height: 22px; accent-color: var(--accent); }
select { font: inherit; width: var(--control-width, auto); min-height: 48px; padding: 6px 12px; border-radius: 12px; border: 1px solid var(--line);
         background: light-dark(#fff, #2c2c2e); color: inherit; }
input[type=range] { width: var(--control-width, 240px); min-height: 48px; accent-color: var(--accent); }
progress { width: var(--control-width, 240px); height: 8px; accent-color: var(--accent); }
hr { width: var(--control-width, 280px); border: 0; border-top: 1px solid var(--line); margin: 4px 0; }
img.image { max-width: 100%; height: auto; border-radius: 12px; image-rendering: auto; }
.scroll { overflow-y: auto; width: 100%; display: flex; flex-direction: column; align-items: center; }  /* like a VStack */
.segmented, .tabs { display: inline-flex; padding: 3px; gap: 2px; border-radius: 12px; background: var(--surface); }
.segmented label, .tabs label { position: relative; }
.segmented input, .tabs input { position: absolute; opacity: 0; inset: 0; margin: 0; cursor: pointer; }
.segmented span, .tabs span { display: inline-flex; align-items: center; min-height: 48px; padding: 0 16px; border-radius: 9px; font-weight: 600; }
.segmented input:checked + span, .tabs input:checked + span { background: light-dark(#fff, #3a3a3c); box-shadow: 0 1px 3px rgba(0,0,0,.15); }
.segmented input:focus-visible + span, .tabs input:focus-visible + span { outline: 3px solid color-mix(in srgb, var(--accent) 60%, transparent); }
.tabs span { padding: 0 20px; }
.radio { display: flex; flex-direction: column; gap: 2px; }
.radio label { display: inline-flex; gap: 10px; align-items: center; min-height: 48px; cursor: pointer; }
.radio input { width: 20px; height: 20px; accent-color: var(--accent); }
textarea { font: inherit; width: var(--control-width, 320px); max-width: 80vw; padding: 10px 12px; border-radius: 12px; resize: vertical;
           border: 1px solid var(--line); background: light-dark(#fff, #2c2c2e); color: inherit; }
input[type=date] { font: inherit; min-height: 48px; padding: 6px 12px; border-radius: 12px; border: 1px solid var(--line);
                   background: light-dark(#fff, #2c2c2e); color: inherit; }
header.nav { display: flex; align-items: center; gap: 8px; width: 100%; max-width: 420px; }
header.nav h2 { margin: 0; font-size: 22px; }
header.nav button { padding: 10px 14px; }
.alert-backdrop { position: fixed; inset: 0; background: rgba(0,0,0,.35); z-index: 10; }
dialog.alert { position: fixed; inset: 0; margin: auto; height: fit-content; z-index: 11; border: 0; border-radius: 18px;
               padding: 22px; max-width: 320px; text-align: center; box-shadow: 0 20px 50px rgba(0,0,0,.3);
               background: light-dark(#fff, #2c2c2e); color: inherit; }
dialog.alert h3 { margin: 0 0 6px; } dialog.alert p { margin: 0 0 16px; color: var(--muted); }
dialog.alert .buttons { display: flex; gap: 8px; justify-content: center; }
.icon { display: inline-flex; color: var(--accent); }
.grid { display: grid; justify-items: center; align-items: center; }
.lazylist { position: relative; overflow-y: auto; width: var(--control-width, 340px); max-width: 90vw; border-radius: 12px;
            background: light-dark(#fff, #2c2c2e); border: 1px solid var(--line); }
.lazylist .row { position: absolute; left: 0; right: 0; display: flex; align-items: center; padding: 0 14px; cursor: pointer;
                 border-bottom: 1px solid var(--line); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.lazylist .row:hover, .lazylist .row:focus-visible { background: var(--surface); }
#mojoui-root.full { max-width: none; padding: 0; height: 100dvh; align-items: stretch; }
#mojoui-root.full > div { flex: 1 1 0; min-width: 0; }
.canvas { position: relative; min-width: 240px; min-height: 240px; overflow: hidden; background: var(--surface); }
.canvas canvas { position: absolute; inset: 0; width: 100%; height: 100%; display: block; touch-action: none; cursor: grab; }
.canvas canvas:active { cursor: grabbing; }
.vstack.card { background: light-dark(#fff, #2c2c2e); border-radius: 12px; box-shadow: 0 1px 3px rgba(0,0,0,.08), 0 0 0 1px var(--line); }
@media (prefers-reduced-motion: reduce) { button { transition: none; } button:active { transform: none; } }
"""


CANVAS_JS = r"""
// mojoui Canvas adapter (fixed, part of the web host; apps never contain JavaScript).
// Frames: pulled one at a time from /frame (JPEG painted by the Mojo app at the canvas's
// pixel size); pulled continuously while the canvas asks for frames, otherwise only when
// its version or size changes. Gestures: drag = PAN, wheel/pinch = ZOOM, click = TAP,
// sent through htmx like any other event, so the rest of the page updates as usual.
(() => {
  const PAN = 1, ZOOM = 2, TAP = 3;
  const shape = () => document.getElementById('mojoui-v').value;
  function attach(div) {
    if (div.mojoui) return;
    const cv = div.querySelector('canvas'), g = cv.getContext('2d');
    const n = Number(div.dataset.node), sid = div.dataset.sid;
    const st = div.mojoui = { want: true, busy: false, drawn: -1, count: 0, times: [], queue: [], sending: false, updating: false };
    const meta = () => document.getElementById('n' + n + '-meta');
    const playing = () => { const m = meta(); return !!m && m.dataset.frames !== '0'; };
    async function pump() {
      if (st.busy) return;
      st.busy = true;
      try {
        while (div.isConnected && (st.want || playing())) {
          const tick = playing() ? 1 : 0, m = meta();
          if (tick) await new Promise(ok => requestAnimationFrame(ok));  // at most one frame per display refresh
          const version = m ? m.dataset.version : '';
          st.want = false;
          const r = div.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
          const w = Math.max(1, Math.round(r.width * dpr)), h = Math.max(1, Math.round(r.height * dpr));
          const res = await fetch(`/frame/${sid}/${n}?w=${w}&h=${h}&scale=${dpr}&v=${shape()}&tick=${tick}`);
          if (res.status !== 200) {
            if (res.headers.get('X-Mojoui-Pending') === '1') update();  // e.g. a frame changed the screen's shape
            if (res.status === 409) await new Promise(ok => setTimeout(ok, 50));
            if (res.status === 404) return;
            continue;
          }
          const img = await createImageBitmap(await res.blob());
          if (cv.width !== img.width || cv.height !== img.height) { cv.width = img.width; cv.height = img.height; }
          g.drawImage(img, 0, 0);
          st.drawn = version; st.count++; st.times.push(performance.now());
          if (st.times.length > 1200) st.times.splice(0, 600);  // (frame times, for tests; bounded)
          div.dataset.frame = `${st.count} ${cv.width}x${cv.height} ${r.width.toFixed(0)}x${r.height.toFixed(0)} ${dpr}`;
          if (res.headers.get('X-Mojoui-Pending') === '1') update();
          if (meta() && meta().dataset.version !== String(st.drawn)) st.want = true;
        }
      } finally { st.busy = false; }
    }
    // The rest of the screen (labels the app changed while drawing): fetched alongside the
    // frames, at most ~10 times a second, and always once more after the last change.
    function update() {
      if (st.updating) { st.again = true; return; }
      const wait = 100 - (performance.now() - (st.updated || 0));
      if (wait > 0) { st.again = true; if (!st.timer) st.timer = setTimeout(() => { st.timer = 0; update(); }, wait); return; }
      st.updating = true; st.again = false; st.updated = performance.now();
      htmx.ajax('POST', `/pending/${sid}`, { values: { v: shape() }, swap: 'none', source: div })
        .finally(() => { st.updating = false; if (st.again) update(); });
    }
    st.pump = pump;
    function send(kind, x, y, dx, dy, zoom) {
      const last = st.queue[st.queue.length - 1];
      if (last && last.number === kind && kind === PAN) { last.dx += dx; last.dy += dy; last.x = x; last.y = y; }
      else if (last && last.number === kind && kind === ZOOM) { last.zoom *= zoom; }
      else st.queue.push({ n, number: kind, x, y, dx, dy, zoom });
      flush();
    }
    async function flush() {
      if (st.sending) return;
      st.sending = true;
      try {
        while (st.queue.length) {
          const e = st.queue.shift();
          await htmx.ajax('POST', `/e/${sid}`, { values: { ...e, v: shape() }, swap: 'none', source: div });
          st.want = true; pump();
        }
      } finally { st.sending = false; }
    }
    const pointers = new Map();
    let moved = false, spread = 0;
    const at = e => { const r = cv.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
    const distance = () => { const [a, b] = [...pointers.values()]; return Math.hypot(a[0] - b[0], a[1] - b[1]); };
    cv.addEventListener('pointerdown', e => {
      cv.setPointerCapture(e.pointerId); pointers.set(e.pointerId, at(e));
      if (pointers.size === 1) moved = false;
      if (pointers.size === 2) spread = distance();
    });
    cv.addEventListener('pointermove', e => {
      if (!pointers.has(e.pointerId)) return;
      const [x, y] = at(e), [px, py] = pointers.get(e.pointerId);
      pointers.set(e.pointerId, [x, y]);
      if (pointers.size === 1) {
        if (Math.abs(x - px) + Math.abs(y - py) > 0) { if (Math.abs(x - px) + Math.abs(y - py) > 3) moved = true; send(PAN, x, y, x - px, y - py, 1); }
      } else if (pointers.size === 2) {
        const d = distance(), [a, b] = [...pointers.values()];
        if (spread > 0 && d > 0) send(ZOOM, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0, 0, d / spread);
        spread = d; moved = true;
      }
    });
    const up = e => {
      if (!pointers.has(e.pointerId)) return;
      const [x, y] = at(e);
      pointers.delete(e.pointerId);
      if (pointers.size === 0 && !moved && e.type === 'pointerup') send(TAP, x, y, 0, 0, 1);
    };
    cv.addEventListener('pointerup', up); cv.addEventListener('pointercancel', up);
    cv.addEventListener('wheel', e => {
      e.preventDefault();
      const [x, y] = at(e), dy = e.deltaMode === 1 ? e.deltaY * 40 : e.deltaY;
      send(ZOOM, x, y, 0, 0, Math.pow(2, -dy / 400));  // 4 notches of 100 = 2×
    }, { passive: false });
    new ResizeObserver(() => { st.want = true; pump(); }).observe(div);
    pump();
  }
  const scan = () => document.querySelectorAll('[data-kind=canvas]').forEach(attach);
  document.addEventListener('DOMContentLoaded', scan);
  document.addEventListener('htmx:afterSettle', () => {
    scan();
    document.querySelectorAll('[data-kind=canvas]').forEach(div => {
      const st = div.mojoui, m = document.getElementById('n' + div.dataset.node + '-meta');
      if (st && m && (m.dataset.version !== String(st.drawn) || m.dataset.frames !== '0')) { st.want = true; st.pump(); }
    });
  });
})();
"""


# Fluent 2 (Microsoft's design system) tokens, for apps whose design() is FLUENT: neutral greys,
# the brand blue, 4/8 px corners, the Segoe type ramp, soft elevation. Light theme.
FLUENT_CSS = """
body.fluent { color-scheme: light; --accent: #0F6CBD; --danger: #C50F1F; --muted: #616161; --surface: #F0F0F0;
  --line: #E0E0E0; background: #F5F5F5; color: #242424;
  font: 14px/20px "Segoe UI Variable", "Segoe UI", system-ui, -apple-system, "Noto Sans", sans-serif; }
body.fluent .text.title { font-size: 28px; line-height: 36px; font-weight: 600; letter-spacing: 0; }
body.fluent .text.headline { font-size: 16px; line-height: 22px; font-weight: 600; }
body.fluent .text.caption { font-size: 12px; line-height: 16px; color: #616161; }
body.fluent .text { text-align: left; }
body.fluent button { border-radius: 4px; min-height: 32px; padding: 5px 12px; font-weight: 600; background: #fff;
  border: 1px solid #D1D1D1; transition: background .1s; }
body.fluent button:hover { filter: none; background: #F5F5F5; }
body.fluent button:active { transform: none; background: #E0E0E0; }
body.fluent button.prominent { background: #0F6CBD; border-color: transparent; color: #fff; }
body.fluent button.prominent:hover { background: #115EA3; }
body.fluent select, body.fluent input[type=text], body.fluent input[type=date] { border-radius: 4px; min-height: 32px;
  border: 1px solid #D1D1D1; border-bottom-color: #616161; background: #fff; }
body.fluent label.toggle { min-height: 32px; }
body.fluent .segmented, body.fluent .tabs { background: transparent; padding: 0; gap: 4px; }
body.fluent .segmented span, body.fluent .tabs span { min-height: 32px; padding: 0 12px; border-radius: 4px; font-weight: 400; color: #424242; }
body.fluent .segmented input:checked + span, body.fluent .tabs input:checked + span { background: #EBF3FC; color: #0F6CBD;
  box-shadow: inset 0 0 0 1px #B4D6FA; font-weight: 600; }
body.fluent .vstack.card { background: #fff; border-radius: 8px; box-shadow: 0 0 2px rgba(0,0,0,.12), 0 2px 4px rgba(0,0,0,.14); }
body.fluent hr { border-top-color: #E0E0E0; }
body.fluent .lazylist { border-radius: 4px; border-color: #E0E0E0; background: #fff; }
body.fluent .lazylist .row { border-bottom-color: #F0F0F0; }
body.fluent .canvas { background: transparent; }
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
        self.closed = False  # set (under lock) when the tab is evicted; its Mojo handle is gone
        self.list_top = {}  # LazyList node → last scroll position, to re-send its visible rows
        self.pending = None  # screen changes made while drawing canvases, not yet sent (a diff)
        self.frame_time = {}  # canvas node → time of its last frame event


ALIGN_CSS = {1: "flex-start", 2: "center", 3: "flex-end", 4: "stretch"}  # START, CENTER, END, STRETCH
JUSTIFY_CSS = {1: "flex-start", 2: "center", 3: "flex-end", 5: "space-between"}  # START, CENTER, END, BETWEEN
SIZED_CONTROLS = (FIELD, TEXTAREA, SLIDER, PROGRESS, DROPDOWN, DATE, LAZYLIST, DIVIDER, SCROLL)


def render(s, i, sid):
    """One mojoui node → FastHTML components, plus its layout settings as CSS flexbox
    (a direct mapping: the browser's own layout does the work)."""
    el = render_node(s, i, sid)
    n = s.nodes[i]
    css = []
    if n["pad_v"] or n["pad_h"]:
        css.append(f"padding:{n['pad_v']}px {n['pad_h']}px")
    if n["w"]:
        css.append(f"width:{n['w']}px;flex-shrink:0")
    if n["h"]:
        css.append(f"height:{n['h']}px")
    if n["min_w"]:
        css.append(f"min-width:{n['min_w']}px")
    if n["max_w"]:
        css.append(f"max-width:{n['max_w']}px")
    if n["grows"]:
        css.append("flex:1 1 0;min-width:0")  # grow from zero, so a growing field never pushes its row onto two lines
    if n["fills"]:
        css.append("align-self:stretch")
        if n["max_w"]:
            css.append("width:100%;margin-inline:auto")  # min(max, available), centred, as GTK's clamp does
    if n["align_items"] in ALIGN_CSS:
        css.append(f"align-items:{ALIGN_CSS[n['align_items']]}")
    if n["justify_items"] in JUSTIFY_CSS:
        css.append(f"justify-content:{JUSTIFY_CSS[n['justify_items']]}")
    if n["kind"] in SIZED_CONTROLS and (n["w"] or n["grows"] or n["fills"]):
        css.append("--control-width:100%")  # the control inside takes the size it was given
    if css:
        old = el.attrs.get("style", "")
        el.attrs["style"] = (old + ";" if old else "") + ";".join(css)
    if n["name"]:
        el.attrs["data-tag"] = n["name"]
    return el


def render_node(s, i, sid):
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
        # hx-vals is inherited from ancestors, so the input says second=0 explicitly
        # (otherwise it would pick up the form's second=1 and every keystroke would "submit").
        field = Input(type="text", name="text", value=n["text"], placeholder=n["hint"], data_kind="field",
                      autocomplete="off", autofocus=(s.focus == i), hx_trigger="input",
                      hx_sync="closest form:queue all", **dict(common, hx_vals=json.dumps({"n": i, "second": 0})))
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
    if kind in (SEGMENTED, TABS, RADIO):
        group = f"g{s.shape}-{i}"
        # Each group needs its own name (browsers link all same-named radios on a page);
        # the chosen index travels in hx-vals instead.
        items = [Label(Input(type="radio", name=group, value=str(j), checked=(j == n["value"]), hx_trigger="change",
                             **dict(common, hx_vals=json.dumps({"n": i, "number": j}))), Span(o))
                 for j, o in enumerate(n["options"])]
        cls, kind_name = {SEGMENTED: ("segmented", "segmented"), TABS: ("tabs", "tabs"), RADIO: ("radio", "radio")}[kind]
        return Div(*items, cls=cls, id=nid, role="radiogroup", data_kind=kind_name, data_group=group)
    if kind == TEXTAREA:
        return Textarea(n["text"], name="text", placeholder=n["hint"], id=nid, data_kind="textarea",
                        rows=str(max(n["size"] // 24, 2)), autofocus=(s.focus == i), hx_trigger="input",
                        hx_sync="this:queue all", **common)
    if kind == ALERT:
        return Div(id=nid, hidden=True)  # drawn in the overlay beside the page (render_alert)
    if kind == NAVBAR:
        back = (Button("‹ Back", data_kind="navback", **common),) if n["msg"] else ()
        return Header(*back, H2(n["text"]), cls="nav", id=nid, data_kind="nav", data_back="1" if n["msg"] else "0")
    if kind == DATE:
        return Input(type="date", name="text", value=n["text"], id=nid, data_kind="date", hx_trigger="change", **common)
    if kind == ICON:
        size = n["size"] or 24
        svg = ICONS.get(n["text"], "").replace('width="24"', f'width="{size}"').replace('height="24"', f'height="{size}"')
        return Span(NotStr(svg), cls="icon", id=nid, data_kind="icon", data_icon=n["text"], aria_hidden="true")
    if kind == GRID:
        kids = [render(s, c, sid) for c in n["children"]]
        return Div(*kids, cls="grid", id=nid, data_kind="grid", data_columns=str(n["value"]),
                   style=f"grid-template-columns:repeat({n['value']}, auto);gap:{n['spacing']}px")
    if kind == LAZYLIST:
        row_h = n["spacing"] or 48
        # Scroll events ask for the rows around the new position: throttled while scrolling, plus a
        # trailing request when it stops (so a fast drag ends on the right rows); newest reply wins.
        return Div(rows_div(s, i, sid, s.list_top.get(i, 0)),
                   cls="lazylist", id=nid, data_kind="list", data_row_height=str(row_h), style=f"height:{n['size']}px",
                   hx_post=f"/rows/{sid}/{i}", hx_trigger="scroll throttle:60ms, scroll delay:150ms",
                   hx_target=f"#rows{i}", hx_swap="outerHTML", hx_sync="this:replace",
                   hx_vals="js:{top: event.target.scrollTop}", hx_include="#mojoui-v")
    if kind == CANVAS:
        return Div(Canvas(), canvas_meta(n, i), id=nid, cls="canvas", data_kind="canvas", data_node=str(i), data_sid=sid)
    if kind == DIVIDER:
        return Hr(id=nid)
    if kind == SPACER:
        return Div(cls="spacer", id=nid)
    kids = [render(s, c, sid) for c in n["children"]]
    if kind == SCROLL:
        return Div(*kids, cls="scroll", id=nid, style=f"max-height:{n['size']}px")
    cls = ("vstack card" if n["style"] == 1 else "vstack") if kind == VSTACK else "hstack"
    return Div(*kids, cls=cls, id=nid, style=f"gap:{n['spacing']}px")


def canvas_meta(n, i):
    """What the canvas adapter needs to know (version, whether it wants frames), kept beside
    the <canvas> so a patch can replace it without clearing the picture."""
    return I(id=f"n{i}-meta", hidden=True, data_version=str(n["value"]), data_frames=str(n["msg2"]))


def render_alert(s, i, sid):
    """The modal for Alert node i, drawn in the overlay beside the inert page.
    Modal without scripts: a full-screen backdrop catches every click, focus starts on the
    first button, and Escape anywhere answers like the first button (Cancel), as elsewhere."""
    n = s.nodes[i]
    mid = f"n{i}-modal"  # its own id (the page keeps a hidden placeholder with id n<i>)
    common = dict(hx_post=f"/e/{sid}", hx_swap="none", hx_include="#mojoui-v")
    buttons = [Button(o, cls="prominent" if j == len(n["options"]) - 1 else "", autofocus=(j == 0),
                      hx_vals=json.dumps({"n": i, "number": j}), **common) for j, o in enumerate(n["options"])]
    dialog = Dialog(H3(n["text"], id=f"{mid}-t"), P(n["hint"]), Div(*buttons, cls="buttons"), open=True,
                    cls="alert", data_kind="alert", role="alertdialog", aria_labelledby=f"{mid}-t", aria_modal="true")
    return Div(Div(cls="alert-backdrop"), dialog, id=mid, hx_trigger="keyup[key=='Escape'] from:body",
               hx_vals=json.dumps({"n": i, "number": 0}), **common)


def rows_div(s, i, sid, top):
    """The tall inner box of LazyList node i, holding only the rows around scroll position `top`."""
    n = s.nodes[i]
    row_h, count = n["spacing"] or 48, n["value"]
    return Div(*rows_html(s, i, sid, top), cls="rows", id=f"rows{i}", data_count=str(count),
               style=f"height:{count * row_h}px;position:relative")


def rows_html(s, i, sid, top):
    """The rows of LazyList node i around scroll position `top` (only these exist in the page)."""
    n = s.nodes[i]
    row_h, count = n["spacing"] or 48, n["value"]
    first = max(0, top // row_h - 5)
    texts = json.loads(s.mod.rows(s.handle, i, first, LIST_WINDOW))
    return [Div(t, cls="row", data_row=str(first + k), style=f"top:{(first + k) * row_h}px;height:{row_h}px",
                role="button", tabindex="0", hx_trigger="click, keyup[key=='Enter'], keyup[key==' ']",
                hx_post=f"/e/{sid}", hx_vals=json.dumps({"n": i, "number": first + k}), hx_swap="none",
                hx_target="this",  # htmx inherits hx-target: without this, rows inherit the list's
                hx_include="#mojoui-v") for k, t in enumerate(texts)]  # "find .rows", fail to find it, and silently send nothing


def make_app(module_dir):
    sys.path.insert(0, str(Path(module_dir).resolve()))
    mod = importlib.import_module("mojoui_app")
    app = FastHTML(default_hdrs=False, secret_key=uuid.uuid4().hex, hdrs=(  # no .sesskey file
        Meta(charset="utf-8"), Meta(name="viewport", content="width=device-width, initial-scale=1, viewport-fit=cover"),
        # No attribute inheritance: every element states its own hx-* attributes (list rows once
        # inherited their list's hx-target and silently sent nothing). Note: hx-vals is still
        # merged from ancestors even so, so elements set every key they rely on themselves.
        Meta(name="htmx-config", content='{"disableInheritance": true}'),
        Script(src="/static/htmx.min.js"), Script(src="/static/mojoui-canvas.js"), Style(CSS), Style(FLUENT_CSS)))
    sessions = OrderedDict()  # sid → Session, oldest first
    sessions_lock = threading.Lock()

    def root(s, sid, oob=False):
        version = Input(type="hidden", id="mojoui-v", name="v", value=str(s.shape))
        alerts = [i for i, n in enumerate(s.nodes) if n["kind"] == ALERT]
        # While an alert is up the page behind is inert (no clicks, no keyboard focus);
        # the alert lives in an overlay beside it.
        full = s.nodes[0]["grows"] or s.nodes[0]["fills"]  # the screen fills the window
        page = Main(version, render(s, 0, sid), id="mojoui-root", cls="full" if full else None, inert=bool(alerts))
        layer = Div(*[render_alert(s, i, sid) for i in alerts], id="mojoui-overlay")
        if oob:
            page.attrs["hx-swap-oob"] = "true"
            layer.attrs["hx-swap-oob"] = "true"
        return page, layer

    @app.get("/static/htmx.min.js")
    def htmx_js():
        return Response((STATIC / "htmx.min.js").read_bytes(), media_type="text/javascript",
                        headers={"Cache-Control": "public, max-age=86400"})

    @app.get("/static/mojoui-canvas.js")
    def canvas_js():
        return Response(CANVAS_JS, media_type="text/javascript", headers={"Cache-Control": "no-cache"})

    @app.get("/")
    def index():
        sid = uuid.uuid4().hex  # one app session per page load (tab)
        s = Session(mod)
        with sessions_lock:
            sessions[sid] = s
            while len(sessions) > MAX_SESSIONS:
                _, old = sessions.popitem(last=False)
                with old.lock:
                    old.closed = True
                    mod.close(old.handle)
        fluent = mod.design(s.handle) == 1
        body_class = Script("document.body.classList.add('fluent')") if fluent else ""
        return Title(mod.title(s.handle)), *root(s, sid), body_class

    @app.get("/img/{sid}/{n}")
    def image(sid: str, n: int):
        s = sessions.get(sid)
        if s is None:
            return Response(status_code=404)
        with s.lock:  # the pixels belong to the current screen: read them before any other event
            if s.closed:
                return Response(status_code=404)
            addr, w, h, nbytes = map(int, mod.image(s.handle, n).split())
            if not addr or nbytes != w * h * 4:
                return Response(status_code=404)
            data = png(ctypes.string_at(addr, nbytes), w, h)
        return Response(data, media_type="image/png", headers={"Cache-Control": "no-store"})

    @app.post("/rows/{sid}/{n}")
    def rows(sid: str, n: int, top: int = 0, v: int = -1):
        s = sessions.get(sid)
        if s is None:
            return ""
        with s.lock:
            if s.closed or v != s.shape or not 0 <= n < len(s.nodes) or s.nodes[n]["kind"] != LAZYLIST:
                return Response(status_code=204)  # htmx leaves the list alone on 204
            s.list_top[n] = max(top, 0)
            return rows_div(s, n, sid, s.list_top[n])

    def changes(s, sid, d, n=-1, text="", number=0):
        """What to send the page after a change: the whole screen on a rebuild, else the changed
        controls (out-of-band swaps). Call with s.lock held, after s.nodes was refreshed."""
        if d["rebuild"]:
            s.pending = None  # the whole screen goes out: older pending patches name old nodes
            s.shape += 1
            s.images.clear()
            s.list_top.clear()
            source = s.nodes[n] if 0 <= n < len(s.nodes) else None
            typing = (FIELD, TEXTAREA)
            s.focus = n if source and source["kind"] in typing and s.nodes[n]["kind"] == source["kind"] else None
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
            echo = i == n and ((op == SET_TEXT and target["kind"] in (FIELD, TEXTAREA, DATE) and target["text"] == text)
                               or (op == SET_VALUE and target["kind"] in (TOGGLE, SLIDER) + CHOICES
                                   and target["value"] == number))
            if (op != SET_MSG or target["kind"] == CANVAS) and not echo and i not in changed:
                changed.append(i)
        out = []
        for i in changed:
            if s.nodes[i]["kind"] == LAZYLIST:
                continue  # refreshed below without resetting its scroll position
            # A canvas keeps its <canvas> (and picture): only its version/frames note changes.
            el = canvas_meta(s.nodes[i], i) if s.nodes[i]["kind"] == CANVAS else render(s, i, sid)
            el.attrs["hx-swap-oob"] = "true"
            out.append(el)
        # Re-send the visible rows of every long list: row text isn't part of the view,
        # so an edit that keeps the count wouldn't show otherwise.
        for i, node in enumerate(s.nodes):
            if node["kind"] == LAZYLIST:
                el = rows_div(s, i, sid, s.list_top.get(i, 0))
                el.attrs["hx-swap-oob"] = "true"
                out.append(el)
        return tuple(out) if out else ""

    def merge(a, b):
        """Two diffs one after the other, as one."""
        if a is None:
            return b
        if a["rebuild"] or b["rebuild"]:
            return {"rebuild": True}
        return {"rebuild": False, "patches": a["patches"] + b["patches"]}

    @app.post("/e/{sid}")
    def event(sid: str, n: int, v: int = -1, second: int = 0, text: str = "", number: int = 0, on: str = "",
              x: float = 0, y: float = 0, dx: float = 0, dy: float = 0, zoom: float = 1):
        s = sessions.get(sid)
        if s is None:
            return Main(P("This page expired: reload it.", cls="text caption"), id="mojoui-root", hx_swap_oob="true")
        with s.lock:
            if s.closed:
                return Main(P("This page expired: reload it.", cls="text caption"), id="mojoui-root", hx_swap_oob="true")
            if s.pending and s.pending.get("rebuild"):  # a frame changed the screen; this event names old nodes
                return changes(s, sid, s.pending)  # send the new screen instead of acting on the wrong control
            if v != s.shape or not 0 <= n < len(s.nodes):
                return ""  # from an older screen (e.g. a double click on a row that's gone): ignore
            source = s.nodes[n]
            if source["kind"] == TOGGLE:
                number = 1 if on else 0
            if source["kind"] == CANVAS:
                d = json.loads(mod.gesture(s.handle, n, number, x, y, dx, dy, zoom))
            else:
                d = json.loads(mod.event(s.handle, n, second, text, number))
            if d.get("ignored"):
                return ""
            s.nodes = json.loads(mod.view(s.handle))  # the screen as Mojo now has it
            return changes(s, sid, d, n, text, number)

    @app.get("/frame/{sid}/{n}")
    def frame(sid: str, n: int, w: int = 0, h: int = 0, scale: float = 1, v: int = -1, tick: int = 0):
        """One canvas frame as a JPEG, painted by the app at w × h pixels. With tick=1 (the
        canvas asked for frames), a frame event goes to the app first. Changes to the rest of
        the screen wait in the session until the page asks for /pending."""
        sess = sessions.get(sid)
        if sess is None:
            return Response(status_code=404)
        with sess.lock:
            if sess.closed:
                return Response(status_code=404)
            if v != sess.shape or not 0 <= n < len(sess.nodes) or sess.nodes[n]["kind"] != CANVAS:
                return Response(status_code=409)  # the screen changed under it: the page will catch up
            now = time.perf_counter()
            if sess.pending and sess.pending.get("rebuild"):  # the page must catch up first; don't run the app on
                return Response(status_code=409, headers={"X-Mojoui-Pending": "1"})
            if tick and sess.nodes[n]["msg2"]:
                last = sess.frame_time.get(n)
                us = int((now - last) * 1e6) if last else 16667
                sess.frame_time[n] = now
                sess.pending = merge(sess.pending, json.loads(mod.frame(sess.handle, n, us)))
                sess.nodes = json.loads(mod.view(sess.handle))
                if sess.pending.get("rebuild") or sess.nodes[n]["kind"] != CANVAS:
                    return Response(status_code=409, headers={"X-Mojoui-Pending": "1"})
            else:
                sess.frame_time.pop(n, None)
            r = json.loads(mod.draw(sess.handle, n, w, h, scale))
            sess.pending = merge(sess.pending, r["diff"])
            sess.nodes = json.loads(mod.view(sess.handle))
            rgba = ctypes.string_at(r["address"], r["width"] * r["height"] * 4)
            pending = bool(sess.pending and (sess.pending.get("rebuild") or sess.pending.get("patches")))
        out = io.BytesIO()
        picture = Image.frombuffer("RGBA", (r["width"], r["height"]), rgba, "raw", "RGBA", 0, 1).convert("RGB")
        if tick:  # animating: small, fast JPEG frames
            picture.save(out, "JPEG", quality=JPEG_QUALITY)
        else:  # a still picture (charts, text): exact PNG
            picture.save(out, "PNG", compress_level=1)
        return Response(out.getvalue(), media_type="image/jpeg" if tick else "image/png",
                        headers={"Cache-Control": "no-store", "X-Mojoui-Pending": "1" if pending else "0",
                                 "X-Mojoui-Draw-Ms": f"{(time.perf_counter() - now) * 1000:.2f}"})

    @app.post("/pending/{sid}")
    def pending(sid: str, v: int = -1):
        """Screen changes made while drawing canvases (e.g. a frame-time label)."""
        s = sessions.get(sid)
        if s is None:
            return ""
        with s.lock:
            if s.closed or s.pending is None:
                return ""
            d, s.pending = s.pending, None
            return changes(s, sid, d)

    return app


if __name__ == "__main__":
    module_dir = sys.argv[1] if len(sys.argv) > 1 else "build/hello/web"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 5001
    import uvicorn

    print(f"mojoui web: http://127.0.0.1:{port}/", flush=True)
    uvicorn.run(make_app(module_dir), host="127.0.0.1", port=port, log_level="warning")
