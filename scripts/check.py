"""Milestone checker for GOAL.md (goal 30: cards that tile, tiles with defaults, bars that switch smoothly; goal 29's
checks run as M5, every earlier goal's inside them). Rebuilds from scratch, prints PASS/FAIL per milestone.

Run: scripts/check   (a subset without rebuilding: scripts/check M1 M2; earlier goals: through docs/goals/NN-check.py)
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


g29 = load("goal29", "docs/goals/29-check.py")
g15 = load("goal15", "docs/goals/15-check.py")
g20 = g29.g20
run, BUILD = g20.run, g20.BUILD
both, env_for, has, labels, money = g15.both, g15.env_for, g15.has, g15.labels, g15.money
OPEN = g15.OPEN
GAP = 16
PLACE = re.compile(r"^BOARD: (\S+) at (-?\d+),(-?\d+) (\d+)x(\d+)$", re.M)


def places(out):
    """Every Board child's place, by name: (x, y, w, h)."""
    return {m[1]: tuple(int(v) for v in m.groups()[1:]) for m in PLACE.finditer(out or "")}


def page_width(p):
    """The page's width as the tiles see it: the table fills it (its own place, child 0)."""
    t = [v for k, v in p.items() if k.startswith("table") or k == "grid" or k == "sheet-table"]
    return t[0][2] if t else None


def m0():
    """The tiling component's own test."""
    err = g20.mojo_test("tests/test_tiling.mojo", "PASSED", "test_tiling", "tests")
    return err is None, err or ("rows of 2 (3 from 1,500 points), equal splits with 16-point gaps; a full row starts another; removing closes "
                                "the gap; snaps to edges and lines within 24 points; a drop on a card swaps; resizes snap to ⅓ ½ ⅔ 1 and the row's "
                                "height; freely placed cards stay put (tests/test_tiling.mojo)")


def tiled_row(p, names, W, problems, where):
    """names share one row: one y, one height, equal widths, 16-point gaps, filling W."""
    got = [p.get(n) for n in names]
    if None in got:
        problems.append(f"{where}: missing {[n for n, g in zip(names, got) if g is None]} in {sorted(p)}")
        return None
    n = len(names)
    want_w = (W - GAP * (n - 1)) // n
    xs = sorted(got)
    for k, (x, y, w, h) in enumerate(xs):
        if y != xs[0][1] or h != xs[0][3] or abs(w - want_w) > 1 or abs(x - k * (want_w + GAP)) > 1:
            problems.append(f"{where}: {names} aren't one row split {n} ways of {W}: {got}")
            return None
    return xs[0][1], xs[0][3]


def m1():
    """omxplorer tiles its sheet: Chart, Pivot, Chart; removing; both hosts; save and reopen."""
    ok, msg = g15.ensure_csv()
    if not ok:
        return False, msg
    problems = []
    one = both(OPEN + ";tap:Chart", "g30-one")
    three = both(OPEN + ";tap:Chart;tap:Pivot;tap:Chart", "g30-three")
    gone = both(OPEN + ";tap:Chart;tap:Pivot;tap:Remove", "g30-gone")
    for r in (one, three, gone):
        if r[0] is None:
            return False, r[1]
    for host, k in (("GTK", 0), ("web", 1)):
        p1, p3, pg = places(one[k]), places(three[k]), places(gone[k])
        W = page_width(p1)
        if not W:
            problems.append(f"{host}: no table on the Board: {sorted(p1)}")
            continue
        tiled_row(p1, ["chart0"], W, problems, f"{host}, one chart")
        row = tiled_row(p3, ["chart0", "pivot1"], W, problems, f"{host}, a chart and a pivot")
        if row and "chart2" in p3:
            x, y, w, h = p3["chart2"]
            if (x, y, w) != (0, row[0] + row[1] + GAP, W):
                problems.append(f"{host}: the third card didn't start a row at full width: {p3['chart2']} (row at y {row[0]}, {row[1]} high)")
        tiled_row(pg, ["pivot0"], W, problems, f"{host}, after removing the chart")
    if not problems:
        for host, k in (("GTK", 0), ("web", 1)):
            if places(three[k]) != places(three[1 - k]):
                problems.append(f"GTK and web place the cards differently: {places(three[0])} vs {places(three[1])}")
                break
    if not problems:  # kept across save and reopen
        saved = both(OPEN + ";tap:Chart;tap:Pivot;tap:Chart;tap:Save", "g30-save", split=True)
        if saved[0] is None:
            return False, saved[1]
        for host in ("gtk", "web"):
            doc = Path(env_for(f"g30-save-{host}")["OMX_DOCUMENTS"]) / "orders_1m.omx"
            back = both("", f"g30-open-{host}", extra={"OMX_OPEN": str(doc)})
            if back[0] is None:
                return False, back[1]
            want = {n: v for n, v in places(saved[0 if host == "gtk" else 1]).items() if n != "cell-editor"}
            for viewer, k in (("GTK", 0), ("web", 1)):
                got = {n: v for n, v in places(back[k]).items() if n in want}
                if got != want:
                    problems.append(f"{host}'s file on {viewer}: places came back as {got}, saved {want}")
    return not problems, "; ".join(problems[:6]) or ("Chart fills the row under the table; Pivot shares it half and half; a third card starts a row at full "
                                                      "width; removing one closes the gap; the same places on GTK and the web, kept across save and reopen")


def m2():
    """Snap and glide on both hosts."""
    ok, msg = g15.ensure_csv()
    if not ok:
        return False, msg
    problems = []
    base = OPEN + ";tap:Chart;tap:Pivot;tap:Chart"
    start = both(base, "g30-start")
    if start[0] is None:
        return False, start[1]
    p0 = places(start[0])
    W = page_width(p0)
    if not W or "chart2" not in p0:
        return False, f"no tiled start: {p0}"
    x2, y2, w2, h2 = p0["chart2"]
    half = (W - GAP) // 2
    cx, cy, cw, ch = p0["chart0"]
    steps = {
        "half": f";resize:chart2={half - 30 - w2},0",  # a corner drag to 30 points under half: snaps to half
        "edge": f";resize:chart2={half - 30 - w2},0;move:chart2={half + GAP + 10},0",  # then dropped 10 points past the right half's line
        "swap": f";move:chart2={cx - x2 + 40},{cy - y2 + 40}",  # dropped onto chart0: they swap
    }
    runs = {name: both(base + s, f"g30-{name}") for name, s in steps.items()}
    for name, r in runs.items():
        if r[0] is None:
            return False, f"{name}: {r[1]}"
    for host, k in (("GTK", 0), ("web", 1)):
        ph, pe, ps = places(runs["half"][k]), places(runs["edge"][k]), places(runs["swap"][k])
        if ph.get("chart2", (0, 0, 0, 0))[2] != half:
            problems.append(f"{host}: a resize to 30 under half left it {ph.get('chart2')} (half is {half})")
        if pe.get("chart2", (0,))[0] != half + GAP or pe.get("chart2", (0, 0, 0))[2] != half:
            problems.append(f"{host}: dropped 10 points off the right half's line, it landed at {pe.get('chart2')} (want x {half + GAP})")
        if ps.get("chart2") != (cx, cy, cw, ch) or ps.get("chart0") != (x2, y2, w2, h2):
            problems.append(f"{host}: dropped on chart0, chart2 is at {ps.get('chart2')} and chart0 at {ps.get('chart0')} (want them swapped)")
    g = runs["swap"][0]
    glides = re.findall(r"^GLIDE: (\S+) .* in (\d+) frames$", g, re.M)
    if not any(n == "chart0" and int(f) >= 3 for n, f in glides):
        problems.append(f"GTK: no glide of chart0 to its new place in 3 frames or more: {glides}")
    still = both(base + steps["swap"], "g30-still", extra={"MOJOUI_REDUCE_MOTION": "1"}, web=False)
    if still[0] is None:
        return False, still[1]
    if any(int(f) > 0 for _, f in re.findall(r"^GLIDE: (\S+) .* in (\d+) frames$", still[0], re.M)):
        problems.append("GTK with less motion asked: a card still glided")
    if "GLIDE-CSS: left" not in runs["swap"][1]:
        problems.append("web: the Board's objects have no transition on their place (GLIDE-CSS)")
    return not problems, "; ".join(problems[:6]) or ("a corner drag snaps to half; a card dropped 10 points off a line lands on it; dropped on another, "
                                                      "the two swap; GTK glides the card over frames (at once with less motion), the web by a CSS transition")


def m3():
    """Tiles and charts start from a default; the inspector changes them."""
    import pyarrow.csv as pc
    ok, msg = g15.ensure_csv()
    if not ok:
        return False, msg
    problems = []
    t = pc.read_csv(g15.CSV_1M).to_pylist()
    revenue = [float(r["revenue"]) for r in t]
    qty = sorted(float(r["qty"]) for r in t)
    n = len(qty)
    med_qty = (qty[n // 2] + qty[(n - 1) // 2]) / 2
    added = both(OPEN + ";tap:Report;tap:Tile;tap:Chart", "g30-tile")
    edited = both(OPEN + ";tap:Report;tap:Tile;tap:Sum of revenue;segment:1=Median;select:1=qty", "g30-tile-edit")
    for r in (added, edited):
        if r[0] is None:
            return False, r[1]
    for host, k in (("GTK", 0), ("web", 1)):
        a, e = added[k], edited[k]
        if "tiles-of" in a:
            problems.append(f"{host}: the Report's toolbar still has the Tiles of dropdown")
        if g15.kpi(a, "Sum of revenue") != money(sum(revenue), "$"):
            problems.append(f"{host}: Tile didn't add Sum of revenue = {money(sum(revenue), '$')} (got {g15.kpi(a, 'Sum of revenue')})")
        words = set(re.findall(r"^BUTTON: (.*)$", a, re.M))
        if not {"revenue", "carrier"} <= words:
            problems.append(f"{host}: Chart didn't add revenue by carrier (the fewest groups): {sorted(words)[:12]}")
        got = g15.kpi(e, "Median of qty")
        if got is None or abs(float(got.replace(",", "")) - med_qty) > 0.006:
            problems.append(f"{host}: the inspector didn't make it Median of qty = {med_qty} (got {got})")
    return not problems, "; ".join(problems[:6]) or ("the Report's toolbar has Tile and Chart, no column picker: Tile adds Sum of revenue, Chart revenue by "
                                                      "carrier; the tile's inspector makes it Median of qty, equal to pyarrow's; GTK and web")


def m4():
    """Bars that switch without a jitter: the move's frames (tests/test_chart_move.mojo) and the pick's cost at 1M rows."""
    problems = []
    err = g20.mojo_test("tests/test_chart_move.mojo", "PASSED", "test_chart_move", "tests")
    if err:
        problems.append(err)
    ok, msg = g15.ensure_csv()
    if not ok:
        return False, msg
    o = both(OPEN + ";tap:Chart;tap:Data;segment:1=Count;segment:1=Median;segment:1=Average", "g30-switch", web=False)
    if o[0] is None:
        return False, o[1]
    sizes = set(re.findall(r"^CANVAS: chart-1 (\d+x\d+)$", o[0], re.M))
    if len(sizes) > 1:
        problems.append(f"GTK: the chart's canvas changed size across the picks: {sorted(sizes)}")
    costs = [float(v) for v in re.findall(r"^PICK: ([\d.]+) ms$", o[0], re.M)]
    if len(costs) < 3 or max(costs) > 16.0:
        problems.append(f"GTK: a pick's compute and first frame at 1M rows: {costs} ms (want 3, each under 16)")
    return not problems, "; ".join(problems[:6]) or (f"the move is timed by the clock; Sum → Count → Median → Average keep the plot area still, bars move "
                                                      f"one way; the canvas keeps its size; at 1M rows each pick fits {max(costs):.1f} ms")


def m5():
    """Goal 29's checks (every earlier goal's inside them)."""
    problems = []
    for name, fn in [(f"29-M{i}", getattr(g29, f"m{i}")) for i in range(6)]:
        ok, msg = fn()
        if not ok:
            problems.append(f"{name}: {msg}")
    return not problems, "; ".join(problems) or "goal 29's M0–M5 (goals 3–28 inside them) pass"


MILESTONES = [("M0", m0), ("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5)]


def main():
    import headless
    headless.ensure()
    only = sys.argv[1:]
    if not only:
        build_all()
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


def build_all():
    import shutil
    every = list(dict.fromkeys(list(g20.EXAMPLES) + g29.APPS))
    for ex in every:
        shutil.rmtree(BUILD / ex, ignore_errors=True)
    for ex in every:
        if not (ROOT / "examples" / ex / "app.mojo").exists():
            continue
        b = run(["scripts/build.sh", ex, "all"], timeout=3600)
        if b.returncode != 0:
            print(f"build {ex} failed:\n" + (b.stdout + b.stderr)[-1500:])
        if ex in ("hello", "gallery", "layout", "lens", "todo"):
            a = run(["scripts/build.sh", ex, "android"], timeout=3600)
            if a.returncode != 0:
                print(f"android build {ex} failed:\n" + (a.stdout + a.stderr)[-1500:])


if __name__ == "__main__":
    main()
