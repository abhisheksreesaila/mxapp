"""Milestone checker for GOAL.md (goal 21: omxplorer's formatting, tabs and toolbar; goal 20's checks run as M4, every
earlier goal's inside them). Rebuilds from scratch, prints PASS/FAIL per milestone. omxplorer is driven through the
agent host (scripts/agent_client.py), on GTK (MOJOUI_TEST steps) and in Chromium (scripts/drive.py), on the Parquet
file goal 20's checks write with pyarrow (build/g20/small.parquet: order, amount, region, day, paid; 5,000 rows).

Run: scripts/check   (a subset without rebuilding: scripts/check M1 M2; earlier goals: through docs/goals/NN-check.py)
"""

import importlib.util
import os
import re
import sys
import time
from pathlib import Path

ROOT = next(p for p in Path(__file__).resolve().parents if (p / "pixi.toml").exists())  # (archived in docs/goals/)
sys.path.insert(0, str(ROOT / "scripts"))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


g20 = load("goal20", "docs/goals/20-check.py")
g19 = g20.g19
run, BUILD = g20.run, g20.BUILD
from agent_client import Client  # noqa: E402
import drive  # noqa: E402

OUT = BUILD / "g21"
# the selected cell after Create table is amount on row 1 (the first decimal column); these steps style it fully
STYLE_STEPS = "tap:Bold;tap:Italic;tap:Underline;tap:Strikethrough;menu:Format>Red;tap:Fill colour;tapat:1=718,500;tap:Align centre"
STYLED = "amount on row 1: bold, italic, underlined, struck through, red, fill blue, centred"
COLUMN_X, HEADER_Y = 190, 12  # (canvas points: the amount column's header: after the gutter and order)


def env(tag, **more):
    """Test-only places for documents, settings and uploads (never the person's own)."""
    home = OUT / tag
    for d in ("docs", "config", "uploads"):
        (home / d).mkdir(parents=True, exist_ok=True)
    return dict(g19.env(), OMX_DOCUMENTS=str(home / "docs"), OMX_CONFIG=str(home / "config"), OMXCODE_UPLOADS=str(home / "uploads"),
                **{k: str(v) for k, v in more.items()})


def small():
    return g20.fixture("small", "small.parquet")


def gtk(steps, name, **more):
    """A GTK run of omxplorer with test steps; its printed labels (and boxes)."""
    exe = BUILD / "omxplorer" / "linux" / "omxplorer"
    r = run([str(exe)], env=dict(env(name, **more), MOJOUI_TEST=steps, MOJOUI_SHOT=str(OUT / f"{name}-gtk.png")), timeout=900)
    out = r.stdout + r.stderr
    if r.returncode != 0 or "CRITICAL" in out or "TEST: " in out:
        raise RuntimeError(f"GTK run {name} failed (exit {r.returncode}): {out[-500:]}")
    return out


def web(steps, name, **more):
    """The same steps in Chromium (the web host); its printed labels (and boxes)."""
    e = env(name, **more)
    saved = {k: os.environ.get(k) for k in e}
    os.environ.update(e)
    try:
        r, out = drive.web_run(BUILD / "omxplorer" / "web", steps, shot=str(OUT / f"{name}-web.png"), viewport=(1440, 900))
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    if r.returncode != 0:
        raise RuntimeError(f"web run {name} failed: {out[-500:]}")
    return out


def box(out, tag):
    m = re.search(rf"^BOX: {re.escape(tag)} ([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+)$", out, re.M)
    return tuple(float(v) for v in m.groups()) if m else None


def status_of(c):
    texts, _, _ = c.call("read")
    return [t[len("status-bar: "):] for t in texts.splitlines() if t.startswith("status-bar: ")]


def screen(c):
    text, _, _ = c.call("screen")
    return text


def pressed(text, title):
    """Whether the screen shows tool `title` pressed (the agent host writes `Button "Bold" = on`)."""
    return f'Button "{title}" = on' in text


def open_small(c, path=None):
    tool = g20.opener(c)
    c.call(tool, path=str(path or small()))
    c.call("create-table")


def m1():
    """Cell and column formatting: the toolbar's and the Format menu's tools on a cell and a column, Undo, Clear
    formatting, number formats, a document's round trip; GTK and the web agree; the pixels (test_cellstyle)."""
    problems = []
    OUT.mkdir(parents=True, exist_ok=True)
    # GTK and the web: the same steps give the same styled cell
    steps = f"pick:Choose a file={small()};tap:Create table;{STYLE_STEPS}"
    try:
        og = gtk(steps, "style")
        ow = web(steps, "style")
        for host, out in (("GTK", og), ("web", ow)):
            if f"LABEL: {STYLED}" not in out:
                problems.append(f"{host}: the styled cell isn't '{STYLED}': {[l for l in out.splitlines() if 'amount on row' in l][-3:]}")
        keys = f"pick:Choose a file={small()};tap:Create table;shortcut:Ctrl+B;shortcut:Ctrl+I;shortcut:Ctrl+U"  # (the Format menu's shortcuts)
        for host, out in (("GTK", gtk(keys, "keys")), ("web", web(keys, "keys"))):
            if "LABEL: amount on row 1: bold, italic, underlined" not in out:
                problems.append(f"{host}: Ctrl+B, Ctrl+I, Ctrl+U didn't make the cell bold, italic and underlined: {[l for l in out.splitlines() if 'amount on' in l][-2:]}")
    except RuntimeError as e:
        problems.append(str(e))
    # the agent host: tools, state, column formats, Undo, Clear, number formats, save and open
    doc = None
    c = Client(BUILD / "omxplorer" / "web", env("agent"))
    try:
        open_small(c)
        names = set(c.names())
        for t in ("bold", "italic", "underline", "strikethrough", "text-colour", "fill", "align-left", "align-center", "align-right",
                  "currency", "percent", "decimals-less", "decimals-more", "clear-format"):
            if t not in names:
                problems.append(f"the sheet's toolbar has no {t} tool")
        for t in ("format-bold", "format-italic", "format-underline", "format-strikethrough", "format-clear-formatting"):
            if t not in names:
                problems.append(f"the Format menu has no {t} item")
        c.call("bold")
        c.call("format-text-colour-green")
        c.call("format-fill-colour-amber")
        s = screen(c)
        if not pressed(s, "Bold") or pressed(s, "Italic"):
            problems.append("after Bold the toolbar doesn't show Bold on (and Italic off)")
        if not any("amount on row 1: bold, green, fill amber" in t for t in status_of(c)):
            problems.append(f"Bold, green and an amber fill aren't the cell's style: {status_of(c)}")
        c.call("grid", gesture="tap", x=COLUMN_X, y=HEADER_Y)  # the whole column
        c.call("italic")
        if not any("Column amount: italic (the whole column)" in t for t in status_of(c)):
            problems.append(f"Italic on the selected column didn't format the column: {status_of(c)}")
        c.call("undo")
        if pressed(screen(c), "Italic"):
            problems.append("Undo didn't take the column's italic back")
        c.call("currency")
        c.call("bold")  # (the column is still what's selected)
        if not any("Column amount: bold (the whole column)" in t for t in status_of(c)):
            problems.append(f"after Currency, Bold didn't format the still-selected column: {status_of(c)}")
        c.call("undo")
        _, body = g20.grid_rows(c, 0, 3)
        if not body or not all(r[1].startswith("$") or r[1] == "" for r in body):
            problems.append(f"Currency didn't show the column as money: {body}")
        if not pressed(screen(c), "Currency"):
            problems.append("Currency isn't shown on after it was chosen")
        c.call("grid", gesture="tap", x=COLUMN_X, y=60)  # (a cell: row 2)
        c.call("underline")
        c.call("clear-format")
        if not any("amount on row 2: plain" in t for t in status_of(c)):
            problems.append(f"Clear formatting didn't make the cell plain: {status_of(c)}")
        c.call("grid", gesture="tap", x=COLUMN_X, y=86)  # (row 3: an edit, then a format, undone newest first)
        c.call("value-or-formula", text="12.34", submit=True)
        c.call("grid", gesture="tap", x=COLUMN_X, y=86)
        c.call("strikethrough")
        c.call("undo")
        first = status_of(c)
        c.call("undo")
        second = status_of(c)
        _, rows = g20.grid_rows(c, 2, 1)
        if not any("Undid a format change" in t for t in first) or not any("Undid an edit" in t for t in second) or not rows or "12.34" in rows[0][1]:
            problems.append(f"Undo didn't take back the format, then the edit: {first} then {second}, row 3 {rows}")
        c.call("grid", gesture="tap", x=COLUMN_X, y=34)  # (row 1 again: still styled)
        c.call("save")
        saved = [t for t in status_of(c) if t.startswith("Saved ")]
        doc = saved[0][len("Saved "):] if saved else None
        if not doc:
            problems.append(f"Save didn't say where it saved: {status_of(c)}")
    finally:
        log = c.close()
    if "Traceback" in log:
        problems.append("the agent host logged a traceback: " + log[-400:])
    if doc:
        c = Client(BUILD / "omxplorer" / "web", env("agent-reopen", OMX_OPEN=doc))
        try:
            s = screen(c)
            if not (pressed(s, "Bold") and pressed(s, "Currency")) or pressed(s, "Italic"):
                problems.append("the reopened document's row 1 isn't bold in a currency column (or is italic)")
            if "Text colour: Green" not in s or "Fill: Amber" not in s:
                problems.append(f"the reopened cell lost its colours: {[l for l in s.splitlines() if 'colour' in l]}")
        finally:
            c.close()
    err = g20.mojo_test("tests/test_cellstyle.mojo", "CELL STYLE TESTS PASSED", "test_cellstyle")
    if err:
        problems.append(err)
    return not problems, "; ".join(problems) or (
        "Bold, Italic, Underline, Strikethrough, colours, fills and alignment on a cell, identical on GTK and the web, and Ctrl+B/I/U; "
        "a column's format (after Currency too), Undo in order with edits, Clear formatting; the document reopens styled; "
        "the pixels (test_cellstyle)")


def m2():
    """Tabs at the bottom, renamed in place, saved."""
    problems = []
    steps = f"pick:Choose a file={small()};tap:Create table;tap:small;enter:Tab name=Orders 2025;tap:Report;tap:Report;enter:Tab name=Board"
    try:
        for host, out in (("GTK", gtk(steps, "tabs")), ("web", web(steps, "tabs"))):
            for want in ("BUTTON: Orders 2025", "LABEL: Renamed Report to Board"):  # (the labels are the last screen's)
                if want not in out:
                    problems.append(f"{host}: no {want!r}")
            tabs, status, toolbar = box(out, "sheet-tabs"), box(out, "status-bar"), box(out, "toolbar")
            if not (tabs and status and toolbar) or not (toolbar[1] < tabs[1] < status[1] and tabs[1] > 600):
                problems.append(f"{host}: the tabs aren't along the bottom, above the status bar: tabs {tabs}, status {status}, toolbar {toolbar}")
        out = web(f"pick:Choose a file={small()};tap:Create table;tap:small;type:Tab name=Nope;dismiss", "tabs-escape")
        if "LABEL: Kept the name" not in out or "Nope" in "".join(l for l in out.splitlines() if l.startswith("BUTTON:")):
            problems.append("Escape in the tab's name field didn't keep the old name")
    except RuntimeError as e:
        problems.append(str(e))
    c = Client(BUILD / "omxplorer" / "web", env("tabs-agent"))
    doc = None
    try:
        open_small(c)
        c.call("tab-0")  # the current tab: rename it
        if "tab-name" not in c.names():
            problems.append("tapping the current tab didn't put its name in a field")
        c.call("tab-name", text="   ", submit=True)
        if not any("A tab needs a name" in t for t in status_of(c)):
            problems.append(f"an empty tab name wasn't refused: {status_of(c)}")
        c.call("tab-name", text="Q3 orders", submit=True)
        c.call("view-rename-tab")
        c.call("tab-name", text="Q3 orders (all)", submit=True)
        c.call("tab-1")
        c.call("tab-1")
        c.call("tab-name", text="Q3 board", submit=True)
        c.call("save")
        saved = [t for t in status_of(c) if t.startswith("Saved ")]
        doc = saved[0][len("Saved "):] if saved else None
        if not doc or not doc.endswith("/small.omx"):
            problems.append(f"Save didn't keep the document's own name (small.omx): {status_of(c)}")
    finally:
        c.close()
    if doc:
        c = Client(BUILD / "omxplorer" / "web", env("tabs-reopen", OMX_OPEN=doc))
        try:
            s = screen(c)
            if 'Button "Q3 orders (all)"' not in s or 'Button "Q3 board"' not in s:
                problems.append(f"the reopened document's tabs aren't Q3 orders (all) and Q3 board: {[l for l in s.splitlines() if 'Button' in l][-6:]}")
        finally:
            c.close()
    return not problems, "; ".join(problems) or (
        "the tabs sit along the bottom on GTK and the web; tapping the current one (or View > Rename tab…) renames it; "
        "Escape keeps the name, an empty one is refused; both names survive save and open")


def m3():
    """A toolbar for the tab you're on; a streamed file shows no edit tools."""
    problems = []
    c = Client(BUILD / "omxplorer" / "web", env("toolbar"))
    try:
        open_small(c)
        sheet = set(c.names())
        for t in ("save", "undo", "add-row", "formula", "sort", "bold", "fill", "pivot", "chart"):
            if t not in sheet:
                problems.append(f"the sheet's toolbar lacks {t}")
        for t in ("sum-tile", "chart-tile"):
            if t in sheet:
                problems.append(f"the sheet's toolbar offers the Report's {t}")
        c.call("tab-1")
        report = set(c.names())
        s = screen(c)
        for t in ("save", "undo", "sum-tile", "average-tile", "count-tile", "chart-tile"):
            if t not in report:
                problems.append(f"the Report's toolbar lacks {t}")
        for t in ("bold", "add-row", "sort", "formula"):
            if t in report:
                problems.append(f"the Report's toolbar offers the sheet's {t}")
        if "Filter · every tile" not in s or "Tiles of" not in s:
            problems.append("the Report's toolbar doesn't carry the tile column and the filter")
        if "Add a tile" in s:
            problems.append("the Report page still has its own add-tile row")
        c.call("sum-tile")
        if "Sum of amount" not in screen(c):
            problems.append("the toolbar's Sum tile didn't add a tile")
    finally:
        c.close()
    c = Client(BUILD / "omxplorer" / "web", env("toolbar-streamed", OMX_STREAM_ROWS=1000))
    try:
        open_small(c)
        # (goal 22, D-216: a streamed file edits and saves since MX frame 7cbcc04; this used to require these off)
        c.call("tab-0")
        names = set(c.names())
        for t in ("save", "add-row", "formula", "sort", "bold"):
            if t not in names:
                problems.append(f"a streamed file's sheet toolbar lacks {t}")
        c.call("tab-1")
        names = set(c.names())
        for t in ("save", "sum-tile"):
            if t not in names:
                problems.append(f"a streamed file's Report toolbar lacks {t}")
        for t in ("add-row", "sort"):
            if t in names:
                problems.append(f"a streamed file's Report toolbar offers the sheet's {t}")
    finally:
        c.close()
    return not problems, "; ".join(problems) or (
        "the sheet's toolbar has the sheet's tools and formats, the Report's its tiles and filter (its page has no add-tile row); "
        "a streamed file gets the same toolbars (goal 22)")


def m4():
    """Nothing regressed: goal 20's milestones (goal 19's and every earlier goal's inside them); the components matrix."""
    problems = []
    for name, fn in [("20-M1", g20.m1), ("20-M2", g20.m2), ("20-M3", g20.m3), ("20-M4", g20.m4)]:
        ok, msg = fn()
        if not ok:
            problems.append(f"{name}: {msg}")
    r = run(["pixi", "run", "python", "scripts/components.py", "--check"])
    if r.returncode != 0:
        problems.append("docs/components.md is out of date: " + (r.stdout + r.stderr)[-300:])
    return not problems, "; ".join(problems) or "goal 20's M1–M4 (goals 3–19 and F-138 inside them) pass; the components matrix is current"


def main():
    import shutil
    import headless
    headless.ensure()
    only = sys.argv[1:]
    if not only:
        for ex in g20.EXAMPLES:
            shutil.rmtree(BUILD / ex, ignore_errors=True)
        for ex in g20.EXAMPLES:
            if not (ROOT / "examples" / ex / "app.mojo").exists():
                continue
            b = run(["scripts/build.sh", ex, "all"], timeout=3600)
            if b.returncode != 0:
                print(f"build {ex} failed:\n" + (b.stdout + b.stderr)[-1500:])
            if ex in ("hello", "gallery", "layout", "lens", "todo"):
                a = run(["scripts/build.sh", ex, "android"], timeout=3600)
                if a.returncode != 0:
                    print(f"android build {ex} failed:\n" + (a.stdout + a.stderr)[-1500:])
    results = []
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4)]:
        if only and name not in only:
            continue
        t0 = time.time()
        try:
            ok, msg = fn()
        except Exception as e:
            ok, msg = False, f"crashed: {e!r}"
        results.append(ok)
        print(f"{'PASS' if ok else 'FAIL'}  {name}  {msg}  ({time.time() - t0:.0f} s)", flush=True)
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
