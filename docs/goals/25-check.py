"""Milestone checker for GOAL.md (goal 25: omxplorer feels native: partial rebuilds, it fits the window, one straight
toolbar, the inspector follows the column, calm motion, the import screen; goal 24's checks run as M7, every earlier
goal's inside them). Rebuilds from scratch, prints PASS/FAIL per milestone. omxplorer runs on GTK (MOJOUI_TEST steps on
the headless display, and real input through scripts/live.py) and in Chromium (scripts/drive.py); pyarrow is the oracle.

Run: scripts/check   (a subset without rebuilding: scripts/check M1 M2; earlier goals: through docs/goals/NN-check.py)
"""

import importlib.util
import os
import re
import statistics
import subprocess
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


g24 = load("goal24", "docs/goals/24-check.py")
g20 = g24.g20
run, BUILD = g20.run, g20.BUILD
import drive  # noqa: E402

OUT = BUILD / "g25"
SIZES = [(1742, 876), (1280, 720), (2560, 1400)]  # the owner's window, a small laptop, a big screen
OPEN = "pick:Choose a file={f}"
SHEET = OPEN + ";tap:Create table"
REPORT = SHEET + ";tap:Report;tap:Sum tile;tap:Median tile;tap:Average tile;tap:Count tile;pause:600"
small = g24.small
boxes = g24.boxes


def env(tag, **more):
    """A fresh install each run (no settings.txt), with its own documents and uploads."""
    home = OUT / tag
    for d in ("docs", "config", "uploads"):
        (home / d).mkdir(parents=True, exist_ok=True)
    for f in (home / "config").glob("*"):
        f.unlink()
    return dict(g20.g19.env(), OMX_DOCUMENTS=str(home / "docs"), OMX_CONFIG=str(home / "config"), OMXCODE_UPLOADS=str(home / "uploads"),
                **{k: str(v) for k, v in more.items()})


def gtk(steps, name, size=(1742, 876), **more):
    exe = BUILD / "omxplorer" / "linux" / "omxplorer"
    OUT.mkdir(parents=True, exist_ok=True)
    shot = OUT / f"{name}-gtk.png"
    r = run([str(exe)], env=dict(env(name, **more), MOJOUI_TEST=steps.format(f=small()), MOJOUI_WINDOW=f"{size[0]}x{size[1]}",
                                 MOJOUI_SHOT=str(shot)), timeout=900)
    out = r.stdout + r.stderr
    if r.returncode != 0 or "CRITICAL" in out or "TEST: " in out:
        raise RuntimeError(f"GTK run {name} failed (exit {r.returncode}): {out[-600:]}")
    return out, shot


def web(steps, name, size=(1742, 876), **more):
    e = env(name, **more)
    saved = {k: os.environ.get(k) for k in e}
    os.environ.update(e)
    try:
        r, out = drive.web_run(BUILD / "omxplorer" / "web", steps.format(f=small()), shot=str(OUT / f"{name}-web.png"), viewport=size)
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    if r.returncode != 0:
        raise RuntimeError(f"web run {name} failed: {out[-600:]}")
    return out


def live(commands, name, size=(1742, 876), skin=None):
    """omxplorer with real input (XTest) on the headless display, opened on small.parquet's import screen."""
    e = env(name)
    if skin:
        (OUT / name / "config" / "settings.txt").write_text(f"skin={skin}\ntimings=no\n")
    args = ["pixi", "run", "python", "scripts/live.py", str(BUILD / "omxplorer" / "linux" / "omxplorer"), commands, "--size", f"{size[0]}x{size[1]}",
            "--env", f"OMX_OPEN={small()}", "--env", f"OMX_CONFIG={e['OMX_CONFIG']}", "--env", f"OMX_DOCUMENTS={e['OMX_DOCUMENTS']}", "--env", "MOJOUI_TRACE=1"]
    r = run(args, timeout=300)
    return r.stdout + r.stderr


def png_size(path):
    from PIL import Image
    return Image.open(path).size


def labels(out):
    return re.findall(r"^LABEL: (.*)$", out, re.M)


def m1():
    """Partial rebuilds: the diff's tests; every shape change after the sheet opens is partial and small; a real drag."""
    problems = []
    err = g20.mojo_test("tests/test_diff_keep.mojo", "DIFF KEEP TESTS PASSED", "test_diff_keep")
    if err:
        problems.append(err)
    # Each action that changes the screen's shape: 4 column moves (the inspector changes with the column's kind), a
    # right-click's context menu and choosing from it, Settings and its close, the Report tab, two tiles.
    out, _ = gtk(SHEET + ";glide:Left;glide:Right;glide:Right;glide:Right;glide:Right;rightclick:0=300,200;pause:200;dismiss;"
                 "menu:File>Settings…;pause:300;dismiss;tap:Report;tap:Sum tile;tap:Median tile", "partial", MOJOUI_TRACE="1")
    sheet_at = [m.start() for m in re.finditer(r"^TRACE: rebuild [\d.]+ widgets (\d+)$", out, re.M)]
    after = out[sheet_at[-1]:] if sheet_at else ""
    full = re.findall(r"^TRACE: rebuild ", after, re.M)
    shape_changes = len(re.findall(r"^TRACE: (?:event|refresh|resize).* REBUILD$", after, re.M))
    parts = [(int(b), int(n)) for b, n in re.findall(r"^TRACE: partial [\d.]+ built (\d+) of (\d+)", after, re.M)]
    if len(sheet_at) != 3 or len(full) != 1:  # (the start, the import, the sheet: then partial updates only)
        problems.append(f"full rebuilds after the sheet opened: {len(full) - 1} ({len(sheet_at)} in all)")
    if shape_changes < 10 or len(parts) != shape_changes:
        problems.append(f"{shape_changes} shape changes (want at least 10: columns, a context menu, Settings, the Report tab, tiles), {len(parts)} partial updates")
    big = [(b, n) for b, n in parts if b * 5 > n]
    if big:
        problems.append(f"partial updates building more than a fifth of the window: {big}")
    shot = OUT / "drag-live.png"
    out = live(f"wait:1500;click:1350,818;wait:1500;drag:230,275,430,431;wait:600;report;shot:{shot}", "drag-live")
    got = labels(out)
    if "Cells 21" not in got or "LIVE: reported" not in out:
        problems.append(f"a real drag from amount row 2 to day row 8 didn't select 21 cells: {[l for l in got if l.startswith(('Cells', 'Count', 'Selection'))]}")
    import pyarrow.parquet as pq
    t = pq.read_table(small()).to_pydict()
    want = round(sum(v for v in t["amount"][1:8] if v is not None), 2)
    if f"Sum {want:,.2f}" not in got:
        problems.append(f"the dragged block's sum isn't pyarrow's {want:,.2f}: {[l for l in got if l.startswith('Sum')]}")
    return not problems, "; ".join(problems) or (f"the diff's tests pass; after the sheet opens every change is partial ({len(parts)} updates, "
                                                  f"at most {max(b for b, _ in parts)} widgets built); a real drag selects the 21-cell block (Sum {want:,.2f})")


def gap_beside(content, insp, width):
    """How far the content stops short of the inspector; None when either is missing, overlaps the other, or the
    inspector runs past the window's right edge."""
    if not content or not insp:
        return None
    gap = insp[0][0] - (content[0][0] + content[0][2])
    if gap < 0 or insp[0][0] + insp[0][2] > width + 0.5 or content[0][0] < 0:
        return None
    return gap


def m2():
    """The sheet and the report fit the window at three sizes, on GTK and the web."""
    problems = []
    for w, h in SIZES:
        for screen, steps, tag in (("sheet", SHEET, "table"), ("report", REPORT, "report-page")):
            name = f"fit-{screen}-{w}x{h}"
            out, shot = gtk(steps, name, (w, h))
            status, insp, content = boxes(out, "status-bar"), boxes(out, "inspector"), boxes(out, tag)
            if png_size(shot) != (w, h):
                problems.append(f"GTK {screen} {w}x{h}: the window grew to {png_size(shot)}")
            if not status or status[0][1] + status[0][3] > h + 0.5:
                problems.append(f"GTK {screen} {w}x{h}: the status bar isn't inside the window ({status})")
            g = gap_beside(content, insp, w)
            if g is None or g > 24 + 16:  # (16: the stack's spacing between them)
                problems.append(f"GTK {screen} {w}x{h}: the {tag} stops {g} pt short of the inspector")
            out = web(steps, name, (w, h))
            page = re.search(r"^PAGE: (\d+)x(\d+) in", out, re.M)
            status, insp, content = boxes(out, "status-bar"), boxes(out, "inspector"), boxes(out, tag)
            if not page or (int(page.group(1)), int(page.group(2))) != (w, h):
                problems.append(f"web {screen} {w}x{h}: the page is {page.group(0) if page else '?'} (it scrolls)")
            if not status or status[0][1] + status[0][3] > h + 0.5:
                problems.append(f"web {screen} {w}x{h}: the status bar isn't inside the window ({status})")
            g = gap_beside(content, insp, w)
            if g is None or g > 24 + 16:
                problems.append(f"web {screen} {w}x{h}: the {tag} stops {g} px short of the inspector")
    return not problems, "; ".join(problems) or "the sheet and the report fit 1742×876, 1280×720 and 2560×1400 on GTK and the web (status bar inside, no gap beside the inspector)"


def m3():
    """The toolbar: every tool's icon on one line, every tool one height; GTK and the web, wide and narrow."""
    problems = []
    for size in ((1742, 876), (1280, 720)):
        for host in ("GTK", "web"):
            out = gtk(SHEET, f"toolbar-{size[0]}", size)[0] if host == "GTK" else web(SHEET, f"toolbar-{size[0]}", size)
            tools = boxes(out, "toolbar/*")
            if len(tools) < 20:
                problems.append(f"{host} {size[0]}: {len(tools)} toolbar buttons measured")
                continue
            centres = [y + h / 2 for _, y, _, h in tools]
            heights = [h for _, _, _, h in tools]
            if max(centres) - min(centres) > 1 or max(heights) - min(heights) > 1:
                problems.append(f"{host} {size[0]}: tools not on one line (centres {min(centres):.1f}–{max(centres):.1f}, heights {min(heights):.1f}–{max(heights):.1f})")
    return not problems, "; ".join(problems) or "every tool and toggle on one line, one height (GTK and the web, 1742 and 1280 wide)"


def m4():
    """The inspector names the selected column and shows its own stats (pyarrow); no number settings for Yes/No, Date, Text."""
    import pyarrow.parquet as pq
    t = pq.read_table(small()).to_pydict()
    problems = []
    moves = {"order": "glide:Left", "amount": "pause:10", "region": "glide:Right", "day": "glide:Right;glide:Right", "paid": "glide:Right;glide:Right;glide:Right"}
    kinds = {"order": "Integer", "amount": "Decimal", "region": "Text", "day": "Date", "paid": "Yes/No"}
    for col, move in moves.items():
        out, _ = gtk(SHEET + ";" + move, f"inspector-{col}")
        got = labels(out)
        if f"{col} · {kinds[col]}" not in got:
            problems.append(f"{col}: the inspector doesn't name it ({[l for l in got if ' · ' in l][:3]})")
        cards = dict(zip(got, got[1:]))
        if col in ("order", "amount"):
            vals = [float(v) for v in t[col] if v is not None]
            want = {"Mean": sum(vals) / len(vals), "Median": statistics.median(vals), "Empty": len(t[col]) - len(vals), "Distinct": len(set(vals))}
            for k, v in want.items():
                shown = cards.get(k, "")
                try:
                    ok = abs(float(shown.replace(",", "")) - v) <= 0.006
                except ValueError:
                    ok = False
                if not ok:
                    problems.append(f"{col}: {k} shows {shown!r}, pyarrow says {v}")
        else:
            for k in ("Decimals", "Thousands separator", "Mean"):
                if k in got:
                    problems.append(f"{col} ({kinds[col]}): the inspector offers {k}")
    return not problems, "; ".join(problems) or "each column's inspector names it; order's and amount's Mean, Median, Empty and Distinct are pyarrow's; Text, Date and Yes/No offer no number settings"


def durations(css, pattern):
    return [int(ms) for ms in re.findall(pattern, css)]


def m5():
    """Calm motion: short transitions and arrivals, no overshoot; reduced motion turns arrivals off (web) (GTK obeys the
    desktop's own setting); widgets that stay don't replay (M1's partial updates)."""
    problems = []
    src = (ROOT / "themes/liquid.mojo").read_text()  # (Liquid is a theme module since goal 27, D-260)
    m = re.search(r"def liquid_css\(.*?\n(?=def |comptime )", src, re.S)
    gcss = m.group(0) if m else ""
    wsrc = src
    m = re.search(r'LIQUID_WEB = """(.*?)"""', wsrc, re.S)
    wcss = m.group(1) if m else ""
    for host, css, trans in (("GTK", gcss, r'(\d+)ms " \+ spring'), ("web", wcss, r"(\d+)ms var\(--sp-snappy\)")):
        t = durations(css, trans)
        if not t or max(t) > 160:
            problems.append(f"{host}: hover and press take up to {max(t) if t else '?'} ms")
        for name, cap in (("liquid-arrive", 240), ("liquid-rise", 340), ("liquid-land", 340)):
            d = durations(css, name + r" (\d+)ms")
            if not d or max(d) > cap:
                problems.append(f"{host}: {name} runs {d} ms (at most {cap})")
            frames = re.search(r"@keyframes " + name + r" \{(.*?)\}\s*\}", css, re.S)
            body = frames.group(1) if frames else ""
            if re.search(r"\b(?!0%|100%)\d+%", body) or any(float(s) > 1.02 for s in re.findall(r"scale\(([\d.]+)\)", body)):
                problems.append(f"{host}: {name} overshoots ({body.strip()[:80]})")
        curves = re.findall(r"cubic-bezier\(([^)]*)\)", css)
        if any(float(c.split(",")[3]) > 1.02 for c in curves if len(c.split(",")) == 4):
            problems.append(f"{host}: a curve overshoots ({[c for c in curves if float(c.split(',')[3]) > 1.02]})")
        if "linear(" in css and host == "web" and "--sp-bouncy: linear" in css:
            problems.append("web: the bouncy spring is still there")
    if "prefers-reduced-motion: reduce) { body.liquid *, body.liquid *::before, body.liquid *::after { animation: none" not in wcss:
        problems.append("web: reduced motion doesn't turn arrivals off")
    return not problems, "; ".join(problems) or "hover and press ≤ 150 ms, menus 200 ms, dialogs 300 ms, tiles 320 ms, no overshoot, on GTK and the web; reduced motion turns arrivals off"


def m6():
    """The import screen with real input: the preview scrolls, Back and Create table respond, nothing stray under the table."""
    problems = []
    for skin in ("liquid", "ledger"):
        name = f"import-live-{skin}"
        shot = OUT / f"{name}.png"
        after = OUT / f"{name}-scrolled.png"
        out = live(f"wait:1500;shot:{shot};report;wheel:800,250,5;wait:400;report;shot:{after}", name, skin=skin)
        reps = out.split("LIVE: reported")
        if len(reps) < 3:
            problems.append(f"{skin}: the live app didn't report ({out[-300:]})")
            continue
        first, second = labels(reps[0]), labels(reps[1])
        if "Import small.parquet" not in first:
            problems.append(f"{skin}: not on the import screen ({first[:3]})")
        prev = boxes(reps[0], "import-preview")
        if prev and after.exists():
            from PIL import ImageChops, Image
            x, y, w, h = (int(v) for v in prev[0])
            crop = (x, y + 60, x + w, y + h)  # (the rows, below the header)
            moved = ImageChops.difference(Image.open(shot).convert("RGB").crop(crop), Image.open(after).convert("RGB").crop(crop)).getbbox()
            if not moved:
                problems.append(f"{skin}: the preview's rows didn't move under the wheel")
        else:
            problems.append(f"{skin}: no import-preview box or second screenshot")
        cols = boxes(reps[0], "import-columns")
        back = boxes(reps[0], "import/Back")
        if cols:
            from PIL import Image
            img = Image.open(shot).convert("RGB")
            x0, y0, w0, h0 = cols[0]
            y_top = int(y0 + h0) + 6
            y_bottom = int(back[0][1]) - 6 if back else y_top + 60
            card = img.getpixel((int(x0 + w0 / 2), y_top))
            odd = 0
            for y in range(y_top, max(y_top + 1, y_bottom), 6):
                for x in range(int(x0), int(x0 + w0), 12):
                    px = img.getpixel((x, y))
                    if max(abs(a - b) for a, b in zip(px, card)) > 6:
                        odd += 1
            if odd:
                problems.append(f"{skin}: {odd} pixels under the column table differ from the card ({card})")
        else:
            problems.append(f"{skin}: no import-columns box")
        out = live("wait:1500;click:354,818;wait:900;report", f"import-back-{skin}", skin=skin)
        if "Open a file" not in labels(out):
            problems.append(f"{skin}: Back didn't go back to the start ({labels(out)[:4]})")
        out = live("wait:1500;click:1350,818;wait:900;report", f"import-create-{skin}", skin=skin)
        if "Rows 5,000" not in labels(out):
            problems.append(f"{skin}: Create table didn't open the sheet")
    return not problems, "; ".join(problems) or "with real input in Liquid and Ledger: the preview scrolls, Back and Create table respond, nothing stray under the column table"


def m7():
    problems = []
    for name, fn in [("24-M1", g24.m1), ("24-M2", g24.m2), ("24-M3", g24.m3), ("24-M4", g24.m4), ("24-M5", g24.m5), ("24-M7", g24.m7), ("24-M6", g24.m6)]:
        ok, msg = fn()
        if not ok:
            problems.append(f"{name}: {msg}")
    return not problems, "; ".join(problems) or "goal 24's M1–M7 (goals 3–23 inside them) pass"


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
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5), ("M6", m6), ("M7", m7)]:
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
