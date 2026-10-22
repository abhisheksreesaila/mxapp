"""Pictures of every component for the public components page, taken from the real framework running.

  pixi run python scripts/catalog.py              # build examples/catalog, shoot all 36 on GTK (and the web), write the JSON
  pixi run python scripts/catalog.py Button Menu  # only these (the JSON is still written for all)
  pixi run python scripts/catalog.py --no-build   # reuse build/catalog
  pixi run python scripts/catalog.py --no-web     # GTK pictures only
  pixi run python scripts/catalog.py --no-gtk     # web pictures only (a 720×520 page)

GTK: examples/catalog runs once per component (CATALOG=<name>) on the headless display at 2x (GDK_SCALE=2); the
display itself is grabbed (popovers and menus are their own surfaces, not in the window's own MOJOUI_SHOT), cropped
to what differs from the window's backdrop plus a uniform margin, saved as docs/img/components/<Name>.webp.
Web: the same app in headless Chromium at 2x, the same crop: docs/img/components/<Name>-web.webp.
docs/components.json: name, group, blurb, api, image(s) and status per platform, the status read by
scripts/components.py's own rules (✅ tested · 🔨 builds · ❌ missing), so the page and the matrix can't disagree.
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import components  # noqa: E402

OUT = ROOT / "docs" / "img" / "components"
JSON = ROOT / "docs" / "components.json"
EXE = ROOT / "build" / "catalog" / "linux" / "catalog"
SCALE = 2
MARGIN = 24  # points of backdrop kept around the component
MAX_W = 1100  # pixels (2x): wider pictures are scaled down

# The web host has no open: step (menu: chooses an item): a click on the bar's menu title opens it, as a person does.
WEB_OPEN = "js:document.querySelector(\".menubar > .menu[data-title='{menu}'] > .menu-title\").click()"
# (name, group, blurb, api: a line from real usage in examples/, the test steps that open it on GTK, on the web)
CATALOG = [
    ("Text", "Basics", "Words on screen, in one of four styles: title, headline, body or caption.", 'Text(summary, style=CAPTION)', "", ""),
    ("Button", "Basics", "Something to press; plain, prominent, subtle, destructive or with an icon.", 'Button("Undo", UNDO, SUBTLE)', "", ""),
    ("Icon", "Basics", "A small picture from the shared icon set, the same on every platform.", 'Icon("upload", 28)', "", ""),
    ("Image", "Basics", "Pixels your app made, shown as a picture.", 'Image(swatch(self.volume), 120, 40)', "", ""),
    ("Divider", "Basics", "A thin line between groups of things.", 'Divider().fill()', "", ""),
    ("VStack", "Layout", "Puts views in a column, one under the other.", 'VStack(parts^, spacing=6).fill().grow()', "", ""),
    ("HStack", "Layout", "Puts views in a row, side by side.", 'HStack(Text("Profile", HEADLINE), Spacer(), spacing=8)', "", ""),
    ("Spacer", "Layout", "Empty space that pushes the views around it apart.", 'HStack(Button("Cancel", SAVE, SUBTLE), Spacer(), Button("Save", SAVE, PROMINENT))', "", ""),
    ("Card", "Layout", "A raised panel that groups related views.", 'Card(VStack(recent^, spacing=8).fill(), spacing=8)', "", ""),
    ("Grid", "Layout", "Lays views out in rows of a fixed number of columns.", 'Grid(cards, 2, spacing=20)', "", ""),
    ("Scroll", "Layout", "A fixed-height area whose content scrolls when it's taller.", 'Scroll(VStack(rows, spacing=8).fill(), height=260)', "", ""),
    ("Tabs", "Layout", "Switches between a few sections of a screen.", 'Tabs(sections, self.tab, on_select=TAB)', "", ""),
    ("NavBar", "Layout", "A screen's title bar, with a back button when there's somewhere to go back to.", 'NavBar("Details", on_back=BACK)', "", ""),
    ("TextField", "Input", "One line of text to type, with a placeholder.", 'TextField(self.name, "Your name", on_change=NAME)', "", ""),
    ("TextArea", "Input", "Several lines of text to type, like notes.", 'TextArea(self.notes, placeholder="Notes", on_change=NOTES, height=140)', "", ""),
    ("Toggle", "Input", "An on/off switch with a label.", 'Toggle("Notifications", self.notify, on_toggle=NOTIFY)', "", ""),
    ("Checkbox", "Input", "A box with a tick, for settings in a list.", 'Checkbox("Snap to grid", self.snap, SNAP)', "", ""),
    ("Dropdown", "Input", "Pick one of several options from a list that opens.", 'Dropdown(["Small", "Medium", "Large"], self.size, SIZE)', "", ""),
    ("Segmented", "Input", "Pick one of a few options shown side by side.", 'Segmented(styles, 0, CHART_STYLE)', "", ""),
    ("Radio", "Input", "Pick one option from a short vertical list.", 'Radio(sizes, self.size, on_select=SIZE)', "", ""),
    ("Slider", "Input", "Choose a number from 0 to 100 by dragging.", 'Slider(self.volume, on_change=VOLUME)', "", ""),
    ("DatePicker", "Input", "Choose a day from a calendar.", 'DatePicker(self.date, on_change=DATE_CHANGED)', "", ""),
    ("ProgressBar", "Feedback", "Shows how far along something is, from 0 to 100.", 'ProgressBar(percent).fill()', "", ""),
    ("Alert", "Feedback", "A modal question with a few answers, like confirming a delete.", 'Alert("Delete everything?", "This can\'t be undone.", buttons, on_choose=ANSWER)', "tap:Close report", "tap:Close report"),
    ("Toast", "Feedback", "A short message at the bottom of the window, with one action like Undo.", 'Toast(self.toast, "Undo", UNDO_SAVE, on_close=TOAST_CLOSE)', "tap:Save", "tap:Save"),
    ("Clipboard", "Feedback", "Puts text on the system clipboard when its version changes; nothing on screen.", 'Clipboard(self.clip_text, self.clip_version)', "", ""),
    ("MenuBar", "Menus & overlays", "The row of menus along the top of the window (on a Mac, the system menu bar).", 'MenuBar([Menu("File", […]), Menu("Edit", […])])', "", ""),
    ("Menu", "Menus & overlays", "One menu of the bar, with its items.", 'Menu("Edit", [Item("Undo", UNDO, icon="undo", shortcut="Ctrl+Z")])', "open:File", WEB_OPEN.format(menu="File")),
    ("Item", "Menus & overlays", "One line of a menu: icon, title, shortcut; checked, disabled, danger or a submenu.", 'Item("Undo", UNDO, icon="undo", shortcut="Ctrl+Z")', "open:View", WEB_OPEN.format(menu="View")),
    ("ContextMenu", "Menus & overlays", "A menu opened where you right-clicked (or long-pressed).", 'ContextMenu("canvas", self.ctx_x, self.ctx_y, [Item("Sort A→Z", SORT_AZ, icon="sort"), …], on_close=MENU_CLOSE)', "rightclick:canvas=500,400", "rightclick:canvas=500,400"),
    ("Popover", "Menus & overlays", "A small panel attached to a view, for a few extra controls.", 'Popover("popover-button", "Formulas", VStack(…), on_close=POP_CLOSE)', "tap:Formulas", "tap:Formulas"),
    ("Dialog", "Menus & overlays", "A modal panel over a dimmed page, with its own buttons.", 'Dialog("Settings", VStack(…), on_close=DIALOG_CLOSE)', "tap:Delete 3 rows", "tap:Delete 3 rows"),
    ("Canvas", "Data & GPU", "A surface your app draws itself (charts, grids, GPU pictures), with gestures.", 'Canvas(1, self.version).fill().height(90)', "", ""),
    ("Board", "Data & GPU", "Cards at free positions that can be dragged, resized and snapped.", 'Board([table^, note^], 760, 320, on_move=MOVE)', "", ""),
    ("Overlay", "Data & GPU", "Floats small islands of controls over a view, pinned to an edge or corner.", 'Overlay(board^, island^).width(760).height(320)', "", ""),
    ("LazyList", "Data & GPU", "A long list that only builds the rows on screen (10,000 rows is fine).", 'LazyList(10000, ROWS_LIST, on_tap=ROW, height=320)', "", ""),
]
HOSTS = {"Linux (GTK)": "linux", "Web": "web", "Android": "android", "Mac (AppKit)": "mac", "iPhone (UIKit)": "iphone", "Agent (MCP)": "agent"}
# Shown alone, cropped to what opened: on the headless display (no window manager) a dialog is its own window at the
# screen's top-left corner, not centred over the page, so the page beside it would only mislead.
ALONE = {"Dialog", "Alert"}
STATUS = {"✅": "tested", "🔨": "builds", "❌": "missing"}


def statuses():
    """name -> {platform: tested|builds|missing}, by scripts/components.py's own cell()."""
    srcs = {h: components.host_text(p) for h, p in components.HOSTS}
    out = {}
    for ctor, kind in components.COMPONENTS:
        out[ctor] = {key: STATUS[components.cell(h, srcs[h], ctor, kind)] for h, key in HOSTS.items()}
    return out


def crop(img, scale, before=None):
    """The component: what differs from the backdrop (each row compared with its left edge: the backdrop is a vertical
    gradient), or from `before` (the page before a dialog opened), plus MARGIN points, kept inside the window."""
    from PIL import ImageChops, Image
    w, h = img.size
    edge = before if before is not None else img.crop((1, 0, 2, h)).resize((w, h))
    diff = ImageChops.difference(img, edge).convert("L").point(lambda v: 255 if v > 10 else 0)
    box = diff.getbbox()
    if box is None:
        return None
    m = MARGIN * scale
    return img.crop((max(0, box[0] - m), max(0, box[1] - m), min(w, box[2] + m), min(h, box[3] + m)))


def save(img, path):
    if img.width > MAX_W:
        img = img.resize((MAX_W, round(img.height * MAX_W / img.width)), 3)
    q = 86
    while True:
        img.save(path, "WEBP", quality=q, method=6)
        if path.stat().st_size < 60_000 or q <= 50:
            return
        q -= 8


def grab_gtk(name, steps, window):
    """Runs the catalog on the headless display showing `name` and grabs the display: once the page has settled, and
    (when there are steps that open a popup) again once the popup has settled. Xvfb has no compositor, so a popover's
    see-through margin (where its shadow would be) comes out pure black: those pixels are taken from the first grab,
    the page as it was under them. Returns the window's area."""
    from Xlib import X, display
    from PIL import Image
    env = dict(os.environ, CATALOG=name, GDK_SCALE=str(SCALE), MOJOUI_TEST="pause:3000;" + (steps + ";" if steps else "") + "pause:5000",
               MOJOUI_SHOT=str(ROOT / "build" / "catalog" / "window.png"))
    app = subprocess.Popen([str(EXE)], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    d = display.Display(os.environ["DISPLAY"])
    w, h = window[0] * SCALE, window[1] * SCALE

    def grab():
        raw = d.screen().root.get_image(0, 0, w, h, X.ZPixmap, 0xFFFFFFFF)
        return Image.frombytes("RGB", (w, h), raw.data, "raw", "BGRX")

    def settled(differs_from=None, until=None):
        last = None
        while time.time() < until:
            img = grab()
            if img.getpixel((2, 2)) != (0, 0, 0) and (differs_from is None or img.tobytes() != differs_from):
                if last is not None and img.tobytes() == last.tobytes():
                    return img
                last = img
            else:
                last = None
            time.sleep(0.2)
        return None

    start = time.time()
    before = settled(until=start + 3.0)
    shot = before
    if before is not None and steps:
        shot = settled(differs_from=before.tobytes(), until=start + 8.0)
        if shot is not None:
            shot = see_through(shot, before)
    tops = []  # the toplevel windows on screen (x, y, w, h): the app's window, a dialog's own window, popups
    for c in d.screen().root.query_tree().children:
        try:
            if c.get_attributes().map_state == X.IsViewable:
                g = c.get_geometry()
                tops.append((g.x, g.y, g.width, g.height))
        except Exception:
            pass
    d.close()
    out = app.communicate(timeout=120)[0]
    if "TEST: " in out or app.returncode != 0:
        print(f"  {name}: the run said: " + "; ".join(l for l in out.splitlines() if l.startswith("TEST")) + f" (exit {app.returncode})")
    return shot, before, tops, out


def see_through(after, before):
    """Pure black in `after` (a popup's margin without a compositor) shows what `before` had there."""
    from PIL import Image
    a = after.convert("RGB")
    black = a.convert("L").point(lambda v: 255 if v <= 3 else 0)
    return Image.composite(before, a, black)


def window_of(out):
    """The window's size from the run's report (BOX: component x y w h)."""
    for line in out.splitlines():
        if line.startswith("BOX: component "):
            p = line.split()
            return int(float(p[4])), int(float(p[5]))
    return None


def web_shots(names, todo):
    """The same app in headless Chromium at 2x: one server per component (CATALOG is read when the app starts)."""
    import drive
    from playwright.sync_api import sync_playwright
    from PIL import Image
    made = []
    for name, steps in [(n, s) for n, _, _, _, _, s in CATALOG if n in todo]:
        port = drive.free_port()
        server = subprocess.Popen([sys.executable, str(ROOT / "mojoui/hosts/web.py"), str(ROOT / "build/catalog/web"), str(port)], cwd=ROOT,
                                  env=dict(os.environ, CATALOG=name), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        url = f"http://127.0.0.1:{port}/"
        try:
            for _ in range(300):
                try:
                    import urllib.request
                    urllib.request.urlopen(url + "static/htmx.min.js", timeout=1)
                    break
                except OSError:
                    time.sleep(0.1)
            with sync_playwright() as p:
                browser = p.chromium.launch(executable_path=drive.CHROMIUM, headless=True)
                vw, vh = names[name]
                page = browser.new_page(viewport={"width": vw, "height": vh}, device_scale_factor=SCALE)
                page.goto(url)
                drive.settle(page)
                for s in [s for s in steps.split(";") if s]:
                    drive.step(page, s)
                    drive.settle(page)
                page.wait_for_timeout(1200)
                tmp = ROOT / "build" / "catalog" / "web.png"
                page.screenshot(path=str(tmp))
                browser.close()
            img = crop(Image.open(tmp).convert("RGB"), SCALE)
            if img is None:
                print(f"  {name} (web): nothing on the page")
                continue
            save(img, OUT / f"{name}-web.webp")
            made.append(name)
            print(f"  {name}-web.webp {img.width}x{img.height} {(OUT / f'{name}-web.webp').stat().st_size // 1024} KB")
        finally:
            server.terminate()
            server.wait(timeout=10)
    return made


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    known = [c[0] for c in CATALOG]
    todo = args or known
    for n in todo:
        if n not in known:
            sys.exit(f"no component called {n}")
    if "--no-build" not in sys.argv:
        for what in ("linux",) + (() if "--no-web" in sys.argv else ("web",)):
            subprocess.run(["scripts/build.sh", "catalog", what], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    import headless
    headless.ensure()
    OUT.mkdir(parents=True, exist_ok=True)
    windows = {}
    failed = []
    for name, _, _, _, steps, _ in CATALOG:
        if name not in todo:
            continue
        if "--no-gtk" in sys.argv:
            windows[name] = (720, 520)
            continue
        # the window's size is the app's own (window_size): a first run with no steps reports it
        size = (720, 520)
        shot, before, tops, out = grab_gtk(name, steps, size)
        windows[name] = window_of(out) or size
        if shot is None:
            failed.append(name)
            print(f"  {name}: the display never settled")
            continue
        shot = shot.crop((0, 0, windows[name][0] * SCALE, windows[name][1] * SCALE))
        if name in ALONE:  # the dialog's own window (the biggest one that isn't the app's), then what differs in it
            ww, wh = windows[name][0] * SCALE, windows[name][1] * SCALE
            own = [t for t in tops if (t[2], t[3]) != (ww, wh) and t[2] * t[3] < ww * wh and t[2] > 50 and t[3] > 50]
            if own:
                x, y, tw, th = max(own, key=lambda t: t[2] * t[3])
                box = (max(0, x), max(0, y), min(ww, x + tw), min(wh, y + th))
                shot, before = shot.crop(box), before.crop(box)
        else:
            before = None
        img = crop(shot, SCALE, before)
        if img is None:
            failed.append(name)
            print(f"  {name}: nothing but backdrop")
            continue
        save(img, OUT / f"{name}.webp")
        print(f"  {name}.webp {img.width}x{img.height} {(OUT / f'{name}.webp').stat().st_size // 1024} KB")
    web = []
    if "--no-web" not in sys.argv:
        web = web_shots(windows, todo)
    status = statuses()
    entries = []
    for name, group, blurb, api, _, _ in CATALOG:
        img = OUT / f"{name}.webp"
        webimg = OUT / f"{name}-web.webp"
        entries.append({"name": name, "group": group, "blurb": blurb, "api": api,
                        "image": str(img.relative_to(ROOT / "docs")) if img.exists() else None,
                        "image_web": str(webimg.relative_to(ROOT / "docs")) if webimg.exists() else None,
                        "status": status[name]})
    JSON.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {JSON.relative_to(ROOT)} ({len(entries)} components); GTK pictures failed: {failed or 'none'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
