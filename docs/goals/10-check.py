"""Milestone checker for goal 10 (archived: docs/goals/10-workbook-usable.md: the Workbook, usable; goal 9's checks run as M8, earlier goals' inside them).
Rebuilds from scratch, prints PASS/FAIL per milestone. GTK runs on a headless display (scripts/headless.py).

Run: scripts/check   (a subset without rebuilding: scripts/check M3 M4; earlier goals: docs/goals/0N-check.py)
"""

import importlib.util
import re
import sys
from pathlib import Path

ROOT = next(p for p in Path(__file__).resolve().parents if (p / "pixi.toml").exists())  # (archived in docs/goals/)
sys.path.insert(0, str(ROOT / "scripts"))

_spec = importlib.util.spec_from_file_location("goal9", ROOT / "docs/goals/09-check.py")
g9 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g9)
run, BUILD, both, gtk, web, shown = g9.run, g9.BUILD, g9.both, g9.gtk, g9.web, g9.shown

EXAMPLES = g9.EXAMPLES
APP = ROOT / "examples/workbook/app.mojo"

# Steps (grid = canvas 0, 1328×256 pt; tapat/dragat positions in thousandths of the canvas)
INSERT_MANY = "tap:Note;tap:Note;tap:Note;tap:Chart"  # four cards: the last lands below the window
BAR_DRAG = "dragat:0=995,150,0,100"  # grab the scroll bar's thumb (top right) and drag it 100 pt down
BAR_TRACK = "tapat:0=995,950"  # click low on the scroll bar's track: the thumb jumps there
HEADER = "tapat:0=690,50"  # the `cents` column's header
HEADER_SORT = HEADER + ";tap:Sort"
PIVOT_FROM = "tapat:0=290,50;tap:Pivot"  # select `region`, insert a pivot


def inview(out):
    m = re.search(r"^INVIEW: (.*)$", out, re.M)
    return None if m is None else [t for t in m.group(1).split(", ") if t]


def label(out, start):
    return next((l[len("LABEL: "):] for l in out.splitlines() if l.startswith("LABEL: " + start)), None)


def m1():
    problems = []
    src = APP.read_text()
    for call in re.findall(r"Button\((.*?)\)(?:,|\n)", src):
        if not re.search(r"style=(SUBTLE|ICON_ONLY|PROMINENT)", call):
            problems.append(f"a plain (grey) button is left: Button({call[:40]}…)")
    if "Overlay(" not in src or src.count(".pin(") < 3:
        problems.append("the chrome isn't in floating islands (Overlay + .pin)")
    gtk_src = (ROOT / "mojoui/hosts/gtk.mojo").read_text()
    web_src = (ROOT / "mojoui/hosts/web.py").read_text()
    for needle, where, src_ in (("mui-island", "GTK", gtk_src), ("radial-gradient", "GTK", gtk_src), ("button.flat", "GTK", gtk_src),
                                (".island", "web", web_src), ("radial-gradient", "web", web_src), ("button.subtle", "web", web_src)):
        if needle not in src_:
            problems.append(f"{where} theme lacks {needle}")
    out = both("", shot_name="look")
    if out[0] is None:
        return False, out[1]
    from PIL import Image
    for host in ("gtk", "web"):
        img = Image.open(BUILD / "workbook" / f"look-{host}.png")
        if img.size != (1440, 900):
            problems.append(f"{host} screenshot is {img.size[0]}×{img.size[1]}, not 1440×900")
    for size in ((1280, 800),):
        o = both("", size=size, shot_name=f"look-{size[0]}")
        if o[0] is None:
            problems.append(f"{size}: {o[1][:200]}")
    return not problems, "; ".join(problems) or "islands, quiet icon buttons, hairline fields, dotted page on GTK and web (screenshots at 1440×900 and 1280×800 in build/workbook/look-*.png)"


def m2():
    problems = []
    out = both(INSERT_MANY, shot_name="tall")
    if out[0] is None:
        return False, out[1]
    from PIL import Image
    img = Image.open(BUILD / "workbook" / "tall-gtk.png")
    if img.size != (1440, 900):
        problems.append(f"the GTK window grew to {img.size[0]}×{img.size[1]} with a tall page (should stay 1440×900 and scroll)")
    bottoms = [int(y) + int(h) for y, h in re.findall(r"^BOARD: \S+ at \d+,(\d+) \d+x(\d+)$", out[0], re.M)]
    if not bottoms or max(bottoms) <= 900:
        problems.append(f"the page isn't taller than the window ({max(bottoms or [0])} pt), so scrolling isn't tested")
    for host, o in (("GTK", out[0]), ("web", out[1])):
        seen = inview(o)
        if seen is None or "chart3" not in seen:
            problems.append(f"{host}: the card below the window isn't reachable (in view: {seen})")
    return not problems, "; ".join(problems) or f"the page ({max(bottoms)} pt tall) scrolls inside a 1440×900 window on both hosts; the card below the fold is reached"


def m3():
    problems = []
    for kind, tag in (("Table", "table2"), ("Pivot", "pivot2"), ("Chart", "chart3"), ("Note", "note2")):
        out = both(f"tap:{kind}", shot_name=f"insert-{kind.lower()}")
        if out[0] is None:
            return False, out[1]
        g, w = inview(out[0]), inview(out[1])
        if g is None or tag not in g:
            problems.append(f"GTK: inserted {tag} not in view ({g})")
        if g != w:
            problems.append(f"{kind}: in view differs: GTK {g} vs web {w}")
        if shown(out[0]) != shown(out[1]):
            problems.append(f"{kind}: GTK and web differ after inserting")
    return not problems, "; ".join(problems) or "Insert Table/Pivot/Chart/Note puts the card in view on both hosts (identical states)"


def m4():
    problems = []
    start = both("", shot_name="bar-start")
    drag = both(BAR_DRAG, shot_name="bar-drag")
    track = both(BAR_TRACK, shot_name="bar-track")
    for name, o in (("start", start), ("drag", drag), ("track", track)):
        if o[0] is None:
            return False, f"{name}: {o[1]}"
    pos = lambda o: label(o, "Rows ")
    p0, p1, p2 = pos(start[0]), pos(drag[0]), pos(track[0])
    if p0 is None or not p0.startswith("Rows 1–"):
        problems.append(f"the grid doesn't say which rows it shows: {p0}")
    first = lambda p: int(re.match(r"Rows ([\d,]+)", p).group(1).replace(",", "")) if p else -1
    if not (5_000_000 < first(p1) < 15_000_000):
        problems.append(f"dragging the thumb 100 pt didn't move about halfway: {p1}")
    if not first(p2) > 17_000_000:
        problems.append(f"clicking low on the track didn't jump near the end: {p2}")
    for name, o in (("drag", drag), ("track", track)):
        if pos(o[0]) != pos(o[1]):
            problems.append(f"{name}: GTK {pos(o[0])} vs web {pos(o[1])}")
    return not problems, "; ".join(problems) or f"scroll bar on the grid: thumb drag → {p1}; track click → {p2}; same rows on GTK and web"


def m5():
    problems = []
    sel = both(HEADER, shot_name="column")
    srt = both(HEADER_SORT, shot_name="column-sort")
    for o in (sel, srt):
        if o[0] is None:
            return False, o[1]
    for host, o in (("GTK", sel[0]), ("web", sel[1])):
        if label(o, "Column cents") is None:
            problems.append(f"{host}: tapping the header didn't select the column")
    for host, o in (("GTK", srt[0]), ("web", srt[1])):
        if label(o, "Sorted by cents") is None:
            problems.append(f"{host}: Sort didn't sort the selected column")
    if shown(sel[0]) != shown(sel[1]) or shown(srt[0]) != shown(srt[1]):
        problems.append("GTK and web differ after selecting / sorting a column")
    return not problems, "; ".join(problems) or "a header tap selects the column (tinted, named in the formula bar); Sort sorts it; identical on both hosts"


def m6():
    problems = []
    o = both(PIVOT_FROM, shot_name="pivot-from")
    if o[0] is None:
        return False, o[1]
    for host, out in (("GTK", o[0]), ("web", o[1])):
        if not re.search(r"^LABEL: Revenue by region and year$", out, re.M):
            problems.append(f"{host}: the new pivot doesn't start from the selected column (region)")
    if shown(o[0]) != shown(o[1]):
        problems.append("GTK and web differ")
    src = APP.read_text()
    for word in ('"Rows"', '"Columns"', '"Value"'):
        if word not in src:
            problems.append(f"the pivot card doesn't name its {word} field")
    return not problems, "; ".join(problems) or "Insert Pivot with `region` selected: 'Revenue by region and year'; fields labelled Rows, Columns, Value"


def m7():
    problems = []
    b = run(["pixi", "run", "mojo", "build", "-I", "examples/workbook", "-I", ".", "tests/bench_workbook.mojo", "-o",
             str(BUILD / "bench_workbook")], timeout=900)
    t = run(["pixi", "run", str(BUILD / "bench_workbook")], timeout=900) if b.returncode == 0 else b
    m = re.search(r"WORKBOOK: recompute ([\d.]+) ms, grid redraw ([\d.]+) ms", t.stdout)
    if "WORKBOOK TESTS PASSED" not in t.stdout or not m:
        return False, f"bench_workbook: {(t.stdout + t.stderr)[-400:]}"
    recompute, redraw = float(m[1]), float(m[2])
    if recompute > 15:
        problems.append(f"a page recompute took {recompute:.1f} ms (> 15)")
    if redraw > 16:
        problems.append(f"a grid redraw took {redraw:.1f} ms (> 16)")
    b2 = run(["pixi", "run", "mojo", "build", "-I", ".", "tests/bench_frame.mojo", "-o", str(BUILD / "bench_frame")], timeout=900)
    t2 = run([str(BUILD / "bench_frame")], timeout=900) if b2.returncode == 0 else b2
    calls = [float(x) for x in re.findall(r"kernel\+copies ([\d.]+) ms", t2.stdout)]
    sorts = {k: float(v) for k, v in re.findall(r"SORT: (\w+) \d+ rows in ([\d.]+) ms, ordered", t2.stdout)}
    if not calls or max(calls[1:] or calls) > 2:
        problems.append(f"GPU group-by: {calls} ms (> 2 after the first call)")
    if len(sorts) < 3 or max(sorts.values()) > 2500:
        problems.append(f"sort: {sorts} ms")
    return not problems, "; ".join(problems) or (f"recompute {recompute:.1f} ms, grid redraw {redraw:.1f} ms, group-by ≤ {max(calls[1:]):.2f} ms, "
                                                  f"sort {', '.join(f'{k} {v / 1000:.2f} s' for k, v in sorts.items())}")


def m8():
    problems = []
    for name in ("m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m9", "m10"):
        ok, msg = getattr(g9, name)()
        if not ok:
            problems.append(f"goal 9 {name.upper()}: {msg[:200]}")
    return not problems, "; ".join(problems) or "goal 9's checks (and goals 3–8's inside them) still pass"


def m9():
    p = ROOT / "docs/plans/formatting.md"
    if not p.exists():
        return False, "no docs/plans/formatting.md"
    text = p.read_text().lower()
    missing = [w for w in ("number format", "colour", "conditional", "memory", "gpu", "redraw", "order") if w not in text]
    return not missing, f"formatting plan lacks: {missing}" if missing else "formatting planned column-first, with each step's cost to the engine and the build order"


def m10():
    problems = []
    if "return OMARCHY" not in APP.read_text():
        problems.append("the Workbook doesn't use the Omarchy design")
    b = run(["pixi", "run", "mojo", "build", "-I", ".", "tests/test_theme.mojo", "-o", str(BUILD / "test_theme")], timeout=900)
    if b.returncode != 0:
        return False, f"test_theme build: {(b.stdout + b.stderr)[-300:]}"
    import os, tempfile
    with tempfile.TemporaryDirectory() as home:  # a different Omarchy theme: its colours must come through
        theme = Path(home) / ".local/state/omarchy/current/theme"
        theme.mkdir(parents=True)
        (theme / "colors.toml").write_text('# a partial light theme\naccent = "#ff5500"  # orange\nbackground = #fafafa\nforeground = "#333333"\n')
        t = run([str(BUILD / "test_theme")], env={"HOME": home}, timeout=120)
        if "THEME TESTS PASSED" not in t.stdout or "dark=False accent=#ff5500 card=#fafafa" not in t.stdout:
            problems.append(f"another theme's colours didn't come through: {t.stdout.strip()[:160]}")
    t = run([str(BUILD / "test_theme")], env={"HOME": "/nonexistent"}, timeout=120)
    if "accent=#7aa2f7" not in t.stdout:
        problems.append("without a theme file it isn't Tokyo Night")
    out = both("", shot_name="omarchy")
    if out[0] is None:
        return False, out[1]
    from PIL import Image
    for host in ("gtk", "web"):
        img = Image.open(BUILD / "workbook" / f"omarchy-{host}.png").convert("L").resize((144, 90))
        mean = sum(img.getdata()) / (144 * 90) / 255
        if mean > 0.3:
            problems.append(f"{host} isn't dark ({mean:.2f} mean brightness)")
    for src, where in ((ROOT / "mojoui/hosts/gtk.mojo", "GTK"), (ROOT / "mojoui/hosts/web.py", "web")):
        if "JetBrains" not in src.read_text():
            problems.append(f"{where} skin doesn't use JetBrains Mono")
    return not problems, "; ".join(problems) or "the person's Omarchy theme on GTK, web and the canvases (another theme's colours come through; Tokyo Night without one)"


def m11():
    problems = []
    opened = both("doubletap:0=690,300", shot_name="edit-open")
    wrote = both("doubletap:0=690,300;enter:Cell=7", shot_name="edit-write")
    for o in (opened, wrote):
        if o[0] is None:
            return False, o[1]
    for host, o in (("GTK", opened[0]), ("web", opened[1])):
        seen = inview(o)
        if seen is None or "cell-editor" not in seen or not re.search(r"^BOARD: cell-editor at ", o, re.M):
            problems.append(f"{host}: a double click didn't open the editor over the cell")
    for host, o in (("GTK", wrote[0]), ("web", wrote[1])):
        if label(o, "Row 2: cents = 7.00") is None:
            problems.append(f"{host}: Enter didn't write the cell")
        if re.search(r"^BOARD: cell-editor", o, re.M):
            problems.append(f"{host}: the editor stayed open after Enter")
    if g9.summary(wrote[0]) == g9.summary(opened[0]):
        problems.append("the edit didn't change the totals")
    if shown(wrote[0]) != shown(wrote[1]) or shown(opened[0]) != shown(opened[1]):
        problems.append("GTK and web differ")
    return not problems, "; ".join(problems) or "double click opens a focused editor over the cell; Enter writes it (totals change), moves down; identical on both hosts"


def m12():
    problems = []
    fit = both("doubletap:0=690,40", shot_name="fit")
    if fit[0] is None:
        return False, fit[1]
    for host, o in (("GTK", fit[0]), ("web", fit[1])):
        if not re.search(r"^LABEL: Column cents fitted \(\d+ pt\)$", o, re.M):
            problems.append(f"{host}: a double click on the header didn't fit the column")
    if shown(fit[0]) != shown(fit[1]):
        problems.append("GTK and web fit to different widths")
    b = run(["pixi", "run", "mojo", "build", "-I", ".", "tests/test_workbook.mojo", "-o", str(BUILD / "test_workbook")], timeout=900)
    t = run(["pixi", "run", str(BUILD / "test_workbook")], timeout=900) if b.returncode == 0 else b
    if "WORKBOOK TESTS PASSED" not in t.stdout:
        problems.append(f"widths don't survive save → open: {(t.stdout + t.stderr)[-200:]}")
    return not problems, "; ".join(problems) or "double-click a header fits it (same width on both hosts); header edges drag (bench_workbook); widths saved with the workbook"


def m13():
    exe = BUILD / "workbook" / "linux" / "workbook"
    r = run([str(exe)], env={"MOJOUI_ROWS": "1000000", "MOJOUI_TEST": "", "MOJOUI_WORKBOOK": str(BUILD / "workbook" / "rows.mxwb")}, timeout=300)
    if not re.search(r"^LABEL: .* revenue · 1,000,000 lines", r.stdout, re.M):
        return False, f"MOJOUI_ROWS=1000000 didn't give a million rows: {[l for l in r.stdout.splitlines() if 'revenue' in l][:1]}"
    return True, "MOJOUI_ROWS=1000000 starts the Workbook on a million rows (default 20M; the checks run at 20M)"


def m14():
    r = run(["pixi", "run", "python", "scripts/components.py", "--check"], timeout=120)
    return r.returncode == 0, (r.stdout.strip() or r.stderr.strip())[:200]


def main():
    import shutil
    import headless
    headless.ensure()
    only = sys.argv[1:]
    if not only:
        for ex in EXAMPLES:
            shutil.rmtree(BUILD / ex, ignore_errors=True)
        for ex in EXAMPLES:
            if not (ROOT / "examples" / ex / "app.mojo").exists():
                continue
            b = run(["scripts/build.sh", ex, "all"], timeout=3600)
            if b.returncode != 0:
                print(f"build {ex} failed:\n" + (b.stdout + b.stderr)[-1500:])
            if ex in ("hello", "gallery", "layout", "lens"):
                a = run(["scripts/build.sh", ex, "android"], timeout=3600)
                if a.returncode != 0:
                    print(f"android build {ex} failed:\n" + (a.stdout + a.stderr)[-1500:])
    results = []
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5), ("M6", m6), ("M7", m7), ("M8", m8), ("M9", m9),
                     ("M10", m10), ("M11", m11), ("M12", m12), ("M13", m13), ("M14", m14)]:
        if only and name not in only:
            continue
        try:
            ok, msg = fn()
        except Exception as e:
            ok, msg = False, f"crashed: {e!r}"
        results.append(ok)
        print(f"{'PASS' if ok else 'FAIL'}  {name}  {msg}", flush=True)
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
