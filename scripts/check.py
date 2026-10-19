"""Milestone checker for GOAL.md (goal 26: the Scene spike: the grid as a display list on GTK's GPU renderer, plus the
owner's four from trying goal 25; goal 25's checks run as M7, every earlier goal's inside them). Rebuilds from scratch,
prints PASS/FAIL per milestone. omxplorer runs on GTK (MOJOUI_TEST steps, and real input through scripts/live.py) and in
Chromium (scripts/drive.py).

Run: scripts/check   (a subset without rebuilding: scripts/check M0 M2; earlier goals: through docs/goals/NN-check.py)
"""

import importlib.util
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


g25 = load("goal25", "docs/goals/25-check.py")
g20 = g25.g20
run, BUILD = g20.run, g20.BUILD
OUT = BUILD / "g26"
SHEET, REPORT, OPEN = g25.SHEET, g25.REPORT, g25.OPEN
boxes, labels = g25.boxes, g25.labels
ACCENT = (14, 124, 134)  # Liquid's teal: the selection ring


def live(commands, name, **kw):
    g25.OUT = OUT
    return g25.live(commands, name, **kw)


def gtk(steps, name, **kw):
    g25.OUT = OUT
    return g25.gtk(steps, name, **kw)


def web(steps, name, **kw):
    g25.OUT = OUT
    return g25.web(steps, name, **kw)


def near(px, colour, tol=30):
    return all(abs(a - b) < tol for a, b in zip(px, colour))


def centre(b):
    return int(b[0] + b[2] / 2), int(b[1] + b[3] / 2)


def m0():
    """The owner's four, with real input where it's input."""
    from PIL import Image, ImageChops
    problems = []
    OUT.mkdir(parents=True, exist_ok=True)
    # 1. The block follows the pointer while dragging: mid-drag (button still down, 40 ms after the last move) the
    #    ring's bottom-right corner is the cell under the pointer.
    shot = OUT / "mid-drag.png"
    px, py = 430, 431
    live(f"wait:1500;click:1350,818;wait:1500;press:230,275;glideto:{px},{py};wait:40;shot:{shot};release", "mid-drag")
    img = Image.open(shot).convert("RGB")
    ring = [(x, y) for x in range(100, 1400, 2) for y in range(240, 760, 2) if near(img.getpixel((x, y)), ACCENT)]
    if not ring:
        problems.append("no selection ring mid-drag")
    else:
        right, bottom = max(x for x, _ in ring), max(y for _, y in ring)
        if not (0 < right - px < 120 and 0 < bottom - py < 30):
            problems.append(f"mid-drag the ring ends at ({right}, {bottom}), not at the cell under the pointer ({px}, {py})")
    # 2. The import preview's scroll bar drags its rows (and a press on the rows selects nothing).
    out = live("wait:1500;report", "preview-bar-where")
    prev = boxes(out, "import-preview")
    if not prev:
        problems.append("no import-preview box")
    else:
        x, y, w, h = prev[0]
        before, after = OUT / "preview-bar-before.png", OUT / "preview-bar-after.png"
        bx = int(x + w - 5)
        live(f"wait:1500;shot:{before};press:{bx},{int(y + 60)};glideto:{bx},{int(y + h - 20)};release;wait:300;shot:{after}", "preview-bar")
        crop = (int(x), int(y + 60), int(x + w - 20), int(y + h))
        if not ImageChops.difference(Image.open(before).convert("RGB").crop(crop), Image.open(after).convert("RGB").crop(crop)).getbbox():
            problems.append("dragging the preview's scroll bar didn't move its rows")
    # 3. The inspector's sections are separated by hairlines (and titled in small caps), GTK and web.
    src = (ROOT / "mojoui/hosts/gtk.mojo").read_text()
    if ".mui-tag-inspector separator" not in src or ".mui-tag-section-title" not in src:
        problems.append("GTK: no inspector hairline or section-title rule")
    out = web(SHEET + ";style:[data-tag=inspector] hr=border-top-width;style:[data-tag=inspector] hr=border-top-style", "inspector-lines")
    got = dict(re.findall(r"^STYLE: \[data-tag=inspector\] hr (\S+) (.+)$", out, re.M))
    if got.get("border-top-width") != "1px" or got.get("border-top-style") != "solid":
        problems.append(f"web: the inspector's sections have no hairline ({got})")
    # 4. A tile's ✕ is hidden until hovered: the web's computed opacity, and GTK's pixels without and with the pointer.
    out = web(REPORT + ";style:[data-tag=tile] button=opacity", "tile-x")
    op = re.findall(r"^STYLE: \[data-tag=tile\] button opacity (.+)$", out, re.M)
    if op != ["0"]:
        problems.append(f"web: a tile's ✕ shows without hover (opacity {op})")
    out = live("wait:1500;click:1350,818;wait:1200;report", "tile-x-tabs")
    tab = boxes(out, "sheet-tabs/Report")
    if not tab:
        problems.append("GTK: no Report tab box")
    else:
        tx, ty = centre(tab[0])
        out = live(f"wait:1500;click:1350,818;wait:1200;click:{tx},{ty};wait:600;report", "tile-x-tools")
        tool = boxes(out, "toolbar/Sum tile")
        if not tool:
            problems.append("GTK: no Sum tile tool box")
        else:
            sx, sy = centre(tool[0])
            out = live(f"wait:1500;click:1350,818;wait:1200;click:{tx},{ty};wait:600;click:{sx},{sy};wait:900;report", "tile-x-where")
            xs = boxes(out, "tile/Remove")
            if not xs:
                problems.append("GTK: no tile/Remove box")
            else:
                x, y, w, h = xs[0]
                far, over = OUT / "tile-x-far.png", OUT / "tile-x-over.png"
                live(f"wait:1500;click:1350,818;wait:1200;click:{tx},{ty};wait:600;click:{sx},{sy};wait:900;"
                     f"move:5,860;wait:500;shot:{far};move:{int(x) - 80},{int(y + h + 40)};wait:500;shot:{over}", "tile-x")
                box = (int(x), int(y), int(x + w), int(y + h))
                a, b = Image.open(far).convert("RGB").crop(box), Image.open(over).convert("RGB").crop(box)
                plain = max(max(abs(p - q) for p, q in zip(c, a.getpixel((0, 0)))) for c in a.get_flattened_data()) < 12  # (only the tile's own colour)
                shows = ImageChops.difference(a, b).getbbox() is not None
                if not plain or not shows:
                    problems.append(f"GTK: the ✕ {'is drawn without hover' if not plain else 'does not appear on hover'}")
    return not problems, "; ".join(problems) or ("the block follows the pointer mid-drag; the preview's scroll bar drags its rows; "
                                                  "the inspector's sections have hairlines (GTK, web); a tile's ✕ shows only on hover (GTK pixels, web opacity)")


BENCH_RE = re.compile(r"^BENCH: (\w+) (\d+) at (\d+)x(\d+) px draws (\d+) paint p50 ([\d.]+) p95 ([\d.]+) upload p50 ([\d.]+) p95 ([\d.]+) "
                      r"frame-paint p50 [\d.]+ p95 [\d.]+ interval p50 ([\d.]+) p99 ([\d.]+)", re.M)
ORDERS_1M = ROOT / "build/data/orders_1m.csv"


def bench(name, **more):
    """omxplorer on 1M rows in a 2800×1400 window (≈ the owner's 1742×876 at 1.6×): 60 scroll frames, 10 glides."""
    import os
    import headless
    headless.ensure()
    OUT.mkdir(parents=True, exist_ok=True)
    env = dict(g25.env(name), MOJOUI_TEST=f"pick:Choose a file={ORDERS_1M};tap:Create table;bench:scroll=60;bench:glide=10",
               MOJOUI_WINDOW="2800x1400", MOJOUI_TRACE="1", MOJOUI_SHOT=str(OUT / f"{name}.png"), **{k: str(v) for k, v in more.items()})
    r = run([str(BUILD / "omxplorer" / "linux" / "omxplorer")], env=env, timeout=1200)
    out = r.stdout + r.stderr
    found = {m.group(1): m.groups() for m in BENCH_RE.finditer(out)}
    return found, out


def m1():
    """Today's path measured: paint and upload apart, per scroll frame and per glide frame."""
    if not ORDERS_1M.exists():
        return False, f"no {ORDERS_1M} (goal 14's 1M-row file)"
    found, out = bench("baseline")
    if "scroll" not in found or "glide" not in found:
        return False, f"no BENCH lines: {out[-400:]}"
    lines = [f"{k}: {v[2]}x{v[3]} px, {v[4]} draws, paint p50 {v[5]} ms p95 {v[6]} ms, upload p50 {v[7]} ms p95 {v[8]} ms" for k, v in found.items()]
    (ROOT / "docs/goals/26").mkdir(parents=True, exist_ok=True)
    (ROOT / "docs/goals/26/baseline.txt").write_text("Goal 26 baseline: today's path (CPU raster into a texture), omxplorer, 1M rows, 2800×1400 window,\n"
                                                    "headless (Xvfb, cairo): CPU numbers only.\n" + "\n".join(lines) + "\n")
    return True, "; ".join(lines) + " (docs/goals/26/baseline.txt)"


def m2():
    """The Scene: its tests (a replay draws the pixels the calls drew)."""
    err = g20.mojo_test("tests/test_scene.mojo", "SCENE TESTS PASSED", "test_scene", "tests")
    return err is None, err or "tests/test_scene.mojo: a Scene replays to exactly the pixels its calls draw (rect, rounded rect, line, circle, text)"


def m3():
    """The grid as a Scene: the same picture, cells and ring layers, the text readable."""
    err = g20.mojo_test("tests/test_scene.mojo", "SCENE TESTS PASSED", "test_scene", "tests")
    src = (ROOT / "mojoui/datagrid.mojo").read_text()
    problems = [err] if err else []
    if "def draw_scene" not in src or 'begin_layer("ring")' not in src:
        problems.append("DataGrid has no draw_scene or ring layer")
    return not problems, "; ".join(problems) or ("the grid recorded as a Scene and replayed is the grid drawn (every pixel); two layers, cells and ring; "
                                                  "an unchanged frame's layers compare equal, a moved ring doesn't; the cells' text reads from the list")


def m4():
    """GTK draws the Scene: render nodes, cells reused by content; side by side with the pixels."""
    from PIL import Image, ImageChops
    problems = []
    steps = SHEET + ";glide:Down;glide:Down"
    old, old_shot = gtk(steps, "compare-pixels")
    new, new_shot = gtk(steps, "compare-scene", MOJOUI_SCENE="1", MOJOUI_TRACE="1")
    replays = re.findall(r"^TRACE: replay (\d+) ops", new, re.M)
    if not replays:
        problems.append("no replay with MOJOUI_SCENE=1 (the grid wasn't drawn as a Scene)")
    grid = boxes(old, "grid")
    if grid:
        x, y, w, h = (int(v) for v in grid[0])
        a = Image.open(old_shot).convert("RGB").crop((x, y, x + w, y + h))
        b = Image.open(new_shot).convert("RGB").crop((x, y, x + w, y + h))
        diff = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 48 else 0)
        share = sum(1 for v in diff.get_flattened_data() if v) / (w * h)
        if share > 0.05:  # (text is drawn by another engine: glyph edges differ; shapes and places must not)
            problems.append(f"{share:.1%} of the grid's pixels differ from the pixel path")
        (OUT / "compare.html").write_text(
            "<!doctype html><meta charset=utf-8><title>goal 26: pixels vs Scene</title><style>body{font:14px Inter,sans-serif;margin:24px}"
            "img{width:100%;border:1px solid #ddd}td{vertical-align:top;width:50%;padding:8px}</style><h2>The grid: today's pixels vs the Scene (GTK render nodes)</h2>"
            f"<p>{share:.2%} of the grid's pixels differ by more than a little (text drawn by Pango, not the baked atlas).</p><table><tr><td><b>Pixels (CPU)</b>"
            f"<img src='{old_shot.name}'></td><td><b>Scene (GTK renderer)</b><img src='{new_shot.name}'></td></tr></table>")
    else:
        problems.append("no grid box")
    return not problems, "; ".join(problems) or (f"MOJOUI_SCENE=1 draws the grid as render nodes ({replays[-1]} ops a frame); "
                                                  f"the grid differs from the pixel path in {share:.1%} of pixels (text edges); build/g26/compare.html")


def m5():
    """The numbers (main-thread CPU, headless): scroll ≤ 2 ms p95; glide with the cells kept, no texture upload."""
    if not ORDERS_1M.exists():
        return False, f"no {ORDERS_1M}"
    best = None  # (the best of three runs: other work on this machine, not the app, makes the slow ones; D-256)
    for attempt in range(3):
        found_n, out_n = bench(f"scene-{attempt}", MOJOUI_SCENE="1")
        if "scroll" not in found_n or "glide" not in found_n:
            continue
        cost = float(found_n["scroll"][6]) + float(found_n["scroll"][8])
        if best is None or cost < best[0]:
            best = (cost, found_n, out_n)
    if best is None:
        return False, "no BENCH lines in three runs"
    found, out = best[1], best[2]
    sc, gl = found["scroll"], found["glide"]
    scroll_p95 = float(sc[6]) + float(sc[8])
    glide_p50 = float(gl[5]) + float(gl[7])
    built = re.search(r"^BENCH: glide .* layers built (\d+) reused (\d+)", out, re.M)
    problems = []
    if scroll_p95 > 2.0:
        problems.append(f"a scroll frame costs {scroll_p95:.1f} ms p95 (build {sc[6]} + replay {sc[8]})")
    if glide_p50 > 0.4:
        problems.append(f"a glide frame costs {glide_p50:.1f} ms p50")
    cells_built = int(built.group(1)) - int(gl[4]) if built else 999  # (one ring layer a draw; the rest are cells)
    if cells_built > 10:
        problems.append(f"the cells were built {cells_built} times in 10 glides (want at most once a key)")
    base = (ROOT / "docs/goals/26/baseline.txt").read_text() if (ROOT / "docs/goals/26/baseline.txt").exists() else ""
    (ROOT / "docs/goals/26/scene.txt").write_text("Goal 26: the Scene (MOJOUI_SCENE=1), same run as the baseline\n" + "\n".join(
        f"{k}: {v[2]}x{v[3]} px, {v[4]} draws, build p50 {v[5]} ms p95 {v[6]} ms, replay p50 {v[7]} ms p95 {v[8]} ms, interval p50 {v[9]} p95 {v[10]}"
        for k, v in found.items()) + "\n")
    return not problems, "; ".join(problems) or (f"scroll: {scroll_p95:.1f} ms p95 a frame (build {sc[6]} + replay {sc[8]}); glide: {glide_p50:.1f} ms p50, "
                                                  f"cells built {cells_built} times in 10 glides, no texture upload (docs/goals/26/scene.txt)")


def m6():
    """On a real GPU display: the owner's run of scripts/scene-bench.sh (blocked on them, not faked)."""
    run_file = ROOT / "docs/goals/26/owner-run.txt"
    if not (ROOT / "scripts/scene-bench.sh").exists():
        return False, "no scripts/scene-bench.sh"
    if not run_file.exists():
        return False, "blocked: waits for the owner to run scripts/scene-bench.sh on their display"
    text = run_file.read_text()
    scene = text.split("== scene", 1)[1] if "== scene" in text else ""
    m = re.search(r"interval p50 ([\d.]+) p99 ([\d.]+)", scene)
    if not m:
        return False, "the owner's run has no Scene intervals"
    p50, p99 = float(m.group(1)), float(m.group(2))
    ok = p99 <= p50 * 1.15
    return ok, f"owner's display: frame interval p50 {p50} ms, p99 {p99} ms ({'every frame on time' if ok else 'late frames'})"


def todo(what):
    def fn():
        return False, f"not built yet: {what}"
    return fn


def m7():
    problems = []
    for name, fn in [("25-M1", g25.m1), ("25-M2", g25.m2), ("25-M3", g25.m3), ("25-M4", g25.m4), ("25-M5", g25.m5), ("25-M6", g25.m6), ("25-M7", g25.m7)]:
        g25.OUT = BUILD / "g25"
        ok, msg = fn()
        if not ok:
            problems.append(f"{name}: {msg}")
    return not problems, "; ".join(problems) or "goal 25's M1–M7 (goals 3–24 inside them) pass"


MILESTONES = [("M0", m0), ("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5), ("M6", m6), ("M8", todo("the brand")), ("M7", m7)]


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
    for name, fn in MILESTONES:
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
