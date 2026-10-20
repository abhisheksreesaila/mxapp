"""Milestone checker for GOAL.md (goal 28: editing a chart, the title is the query; goal 27's checks run as M7, every
earlier goal's inside them). Rebuilds from scratch, prints PASS/FAIL per milestone.

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


g27 = load("goal27", "docs/goals/27-check.py")
g26, g25 = g27.g26, g27.g25
g20 = g25.g20
run, BUILD = g20.run, g20.BUILD
OUT = BUILD / "g28"
labels = g25.labels
import drive  # noqa: E402

# M0's twelve specs (tests/chartspec_dump.mojo): (combine, order, top, only paid = …)
SPECS = [("sum", "table", 0, None), ("mean", "table", 0, None), ("count", "table", 0, None), ("sum", "largest", 0, None),
         ("sum", "smallest", 0, None), ("sum", "az", 0, None), ("sum", "largest", 3, None), ("mean", "smallest", 2, None),
         ("count", "table", 0, False), ("sum", "largest", 0, True), ("mean", "az", 5, True), ("count", "largest", 3, False)]


def expected(table, how, order, top, paid):
    """The chart pyarrow would draw: (region, value) in the spec's order, cut to its top N; empty regions "(blank)"."""
    rows = table.to_pylist()
    groups = {}
    first = []
    for r in rows:
        if paid is not None and r["paid"] is not paid:
            continue
        g = r["region"] if r["region"] is not None else "(blank)"
        if g not in groups:
            groups[g] = []
            first.append(g)
        groups[g].append(r["amount"])
    out = []
    for g in first:
        vals = [float(v) for v in groups[g] if v is not None]
        v = sum(vals) if how == "sum" else (sum(vals) / len(vals) if how == "mean" and vals else (len(groups[g]) if how == "count" else 0.0))
        out.append((g, v))
    if order == "largest":
        out.sort(key=lambda gv: -gv[1])
    elif order == "smallest":
        out.sort(key=lambda gv: gv[1])
    elif order == "az":
        out.sort(key=lambda gv: (gv[0] == "(blank)", gv[0].lower()))
    return out[:top] if top else out


def m0():
    """One chart model: twelve specs equal pyarrow's; a document keeps them; an older document opens as it was."""
    import pyarrow.parquet as pq
    problems = []
    b = run(["scripts/mxbuild.sh", "tests/chartspec_dump.mojo", "-o", str(BUILD / "chartspec_dump")], timeout=1800)
    if b.returncode != 0:
        return False, "chartspec_dump: " + (b.stdout + b.stderr)[-400:]
    out = run([str(BUILD / "chartspec_dump"), g25.small()], timeout=300).stdout
    table = pq.read_table(g25.small())
    blocks = re.split(r"^SPEC \d+\n", out.split("END")[0], flags=re.M)[1:]
    if len(blocks) != len(SPECS):
        return False, f"{len(blocks)} charts printed: {out[-300:]}"
    for k, (block, (how, order, top, paid)) in enumerate(zip(blocks, SPECS)):
        got = [(l.split("\t")[0], float(l.split("\t")[1].replace(",", "").replace("$", ""))) for l in block.strip().split("\n")[1:]]
        want = expected(table, how, order, top, paid)
        same = len(got) == len(want) and all(g[0] == w[0] and abs(g[1] - w[1]) <= 0.006 for g, w in zip(got, want))
        if order == "table":  # (the table's order is the engine's dictionary order: compare as sets)
            same = len(got) == len(want) and all(any(g[0] == w[0] and abs(g[1] - w[1]) <= 0.006 for w in want) for g in got)
        if not same:
            problems.append(f"spec {k} ({how}, {order}, top {top}, paid={paid}): {got[:4]} vs pyarrow {[(g, round(v, 2)) for g, v in want[:4]]}")
    err = g20.mojo_test("tests/test_chartspec.mojo", "CHARTSPEC TESTS PASSED", "test_chartspec", "tests")
    if err:
        problems.append(err)
    return not problems, "; ".join(problems) or ("12 specs (sum, average, count; as in the table, largest, smallest, A to Z; top 2/3/5; paid or unpaid) equal pyarrow's; "
                                                  "a document keeps a chart's spec and an older one opens as it was (tests/test_chartspec.mojo)")


TOKENS = ["Sum", "amount", "region", "as in the table", "every region", "every row", "bars"]


def m1():
    """The title is a sentence: every setting a token; a token's choices in a popover; a pick changes the chart (GTK, web,
    a sheet chart and a Report chart tile)."""
    problems = []
    err = g20.mojo_test("tests/test_sentence.mojo", "SENTENCE TESTS PASSED", "test_sentence", "tests")
    if err:
        problems.append(err)
    g25.OUT = OUT
    steps = g25.SHEET + ";tap:Chart;pause:300"
    picks = ";tap:Sum;pause:200;tap:Average;pause:200;tap:as in the table;pause:200;tap:largest first;pause:200;tap:every region;pause:200;tap:top 3;pause:300"
    want = "Average of amount by region, largest first, top 3, every row, as bars"
    gtk, _ = g25.gtk(steps, "m1-tokens")
    buttons = re.findall(r"^BUTTON: (.*)$", gtk, re.M)
    missing = [t for t in TOKENS if t not in buttons]
    if missing:
        problems.append(f"GTK: the sentence lacks tokens {missing}")
    pop, _ = g25.gtk(steps + ";tap:region;pause:300", "m1-popover")
    if "POPOVER: Group by" not in pop:
        problems.append("GTK: tapping a word opens no choices")
    picked, _ = g25.gtk(steps + picks, "m1-picked")
    if not any(l.startswith(want) for l in labels(picked)):
        problems.append(f"GTK: after the picks the chart says {[l for l in labels(picked) if ' as ' in l][-1:]}")
    web = g25.web(steps + picks, "m1-picked")
    if not any(l.startswith(want) for l in labels(web)):
        problems.append(f"web: after the picks the chart says {[l for l in labels(web) if ' as ' in l][-1:]}")
    tile, _ = g25.gtk(g25.OPEN + ";tap:Create table;tap:Report;tap:Chart tile;pause:300;tap:bars;pause:200;tap:a line;pause:300", "m1-tile")
    if not any(l.startswith("Sum of amount by region, as in the table, every region, every row, as a line") for l in labels(tile)):
        problems.append(f"GTK Report tile: {[l for l in labels(tile) if ' as ' in l][-1:]}")
    return not problems, "; ".join(problems) or ("a chart's title is its sentence, every setting a token (GTK, web); a token's choices open on it; "
                                                  "Sum→Average, as in the table→largest first, every region→top 3 change the chart on both hosts; a Report tile's too")


ASK = "enter:Ask: top 3, unpaid, as a line="


def m2():
    """Ask: a phrase edits several settings at once; the field says what it took and skipped; nonsense changes nothing;
    the parser's phrases (tests/test_chartask.mojo)."""
    problems = []
    err = g20.mojo_test("tests/test_chartask.mojo", "CHARTASK TESTS PASSED", "test_chartask", "tests")
    if err:
        problems.append(err)
    g25.OUT = OUT
    steps = g25.SHEET + ";tap:Chart;pause:300;" + ASK + "top 3, unpaid, as a line;pause:400"
    want = "Sum of amount by region, largest first, top 3, not paid, as a line"
    for host in ("GTK", "web"):
        out = g25.gtk(steps, "m2-ask")[0] if host == "GTK" else g25.web(steps, "m2-ask")
        ls = labels(out)
        if "Took top 3 · not paid · a line" not in ls:
            problems.append(f"{host}: the field said {[l for l in ls if l.startswith(('Took', 'Didn'))][-1:]}")
        sentence = re.findall(r"^(?:BUTTON|LABEL): (.*)$", out, re.M)
        if not all(t in sentence for t in ("largest first", "top 3", "not paid", "a line")):
            problems.append(f"{host}: the sentence's words after the ask: {[t for t in sentence if t in ('largest first', 'top 3', 'not paid', 'a line')]}")
    nonsense = g25.gtk(g25.SHEET + ";tap:Chart;pause:300;" + ASK + "bananas and apples;pause:300", "m2-nonsense")[0]
    if not any(l.startswith("Didn't understand") for l in labels(nonsense)) or "as in the table" not in re.findall(r"^BUTTON: (.*)$", nonsense, re.M):
        problems.append("GTK: a phrase it can't use changed something or said nothing")
    tile = g25.gtk(g25.OPEN + ";tap:Create table;tap:Report;tap:Chart tile;pause:300;" + ASK + "average, smallest first;pause:400", "m2-tile")[0]
    if not any(l.startswith("Took average · smallest first") for l in labels(tile)):
        problems.append(f"GTK Report tile: {[l for l in labels(tile) if l.startswith(('Took', 'Didn'))][-1:]}")
    return not problems, "; ".join(problems) or ("\"top 3, unpaid, as a line\" turns a chart into the top 3 regions' unpaid amounts as a line and says so (GTK, web, a Report tile too); "
                                                  "nonsense changes nothing and says it; 37 phrases in tests/test_chartask.mojo")


def m3():
    """Inspector pages: a chart's inspector says what's set, a row per part opens its page, a page's control changes the
    chart, Back returns; GTK and the web; a Report chart tile's too."""
    problems = []
    g25.OUT = OUT
    root = g25.SHEET + ";tap:Chart;pause:300"
    for host in ("GTK", "web"):
        out = g25.gtk(root, "m3-root")[0] if host == "GTK" else g25.web(root, "m3-root")
        ls = labels(out)
        missing = [t for t in ("Sum of amount · by region", "as in the table · every region", "every row", "bars") if t not in ls]
        if missing or "PARTS" not in ls:
            problems.append(f"{host}: the chart inspector's rows lack {missing}")
        page = root + ";tap:Order;pause:300;segment:1=Top 5;pause:300"
        out = g25.gtk(page, "m3-order")[0] if host == "GTK" else g25.web(page, "m3-order")
        if "Back" not in re.findall(r"^BUTTON: (.*)$", out, re.M) or not any(l.startswith("Sum of amount by region, largest first, top 5") for l in labels(out)):
            problems.append(f"{host}: the Order page didn't change the chart: {[l for l in labels(out) if ' as ' in l][-1:]}")
        back = page + ";tap:Back;pause:300"
        out = g25.gtk(back, "m3-back")[0] if host == "GTK" else g25.web(back, "m3-back")
        if "largest first · top 5" not in labels(out):
            problems.append(f"{host}: Back didn't return to the chart's rows (or they don't say top 5)")
    tile = g25.gtk(g25.OPEN + ";tap:Create table;tap:Report;tap:Chart tile;pause:300;tap:Style;pause:300;segment:0=A line;pause:300", "m3-tile")[0]
    if not any(l.startswith("Sum of amount by region, as in the table, every region, every row, as a line") for l in labels(tile)):
        problems.append(f"GTK Report tile: the Style page didn't make a line: {[l for l in labels(tile) if ' as ' in l][-1:]}")
    return not problems, "; ".join(problems) or ("a chart's inspector: its sentence and four rows saying what's set (Data, Order, Rows, Style); "
                                                  "Order → Top 5 changes the chart, Back returns (GTK, web); a Report tile's Style page makes a line")


def m4():
    """Undo takes back chart changes one step each, in order with table edits; Insert Chart and Chart tile open the
    chart's inspector; no chart settings in any toolbar."""
    problems = []
    g25.OUT = OUT
    base = g25.SHEET + ";tap:Chart;pause:300;" + ASK + "average;pause:200;tap:Add row;pause:200;" + ASK + "top 3;pause:200"
    want = [("Average", "top 3", "Rows 5,001"), ("Average", "every region", "Rows 5,001"), ("Average", "every region", "Rows 5,000"), ("Sum", "every region", "Rows 5,000")]
    for n, (combine, top, rows) in enumerate(want):
        out = g25.gtk(base + ";menu:Edit>Undo;pause:200" * n, f"m4-undo{n}")[0]
        buttons = re.findall(r"^BUTTON: (.*)$", out, re.M)
        ls = labels(out)
        if combine not in buttons or top not in buttons or rows not in ls:
            problems.append(f"after {n} undos: want {combine}, {top}, {rows}; got {[b for b in buttons if b in ('Sum', 'Average', 'top 3', 'every region')]} {[l for l in ls if l.startswith('Rows ')]}")
    e = g25.env("m4-closed")
    (OUT / "m4-closed" / "config" / "settings.txt").write_text("inspector=no\ntimings=no\n")
    closed = run([str(BUILD / "omxplorer" / "linux" / "omxplorer")], env=dict(e, MOJOUI_TEST=(g25.SHEET + ";tap:Chart;pause:300").format(f=g25.small())), timeout=600).stdout
    if "PARTS" not in labels(closed):  # (the chart inspector's rows: on screen only when it's open)
        problems.append("Insert Chart didn't open the chart's inspector (with the inspector closed before)")
    sheet = g25.gtk(g25.SHEET, "m4-toolbar")[0]
    report = g25.gtk(g25.OPEN + ";tap:Create table;tap:Report", "m4-toolbar-report")[0]
    for name, out in (("sheet", sheet), ("Report", report)):
        tools = [b[0] for b in [(m.group(1),) for m in re.finditer(r"^BOX: toolbar/(.+?) [\d.-]+ [\d.-]+ [\d.-]+ [\d.-]+$", out, re.M)]]
        settings = [t for t in tools if t in ("Bar", "Line", "Average", "Group by", "Largest first", "Top 3", "Value")]
        if settings:
            problems.append(f"the {name} toolbar holds chart settings: {settings}")
    return not problems, "; ".join(problems) or ("Undo takes back an ask (top 3), then the added row, then the earlier ask (average), each one step; "
                                                  "a new chart opens its inspector; the toolbars only insert")


def m5():
    """Bars move: a spec change animates over ~20 frames, each ≤ 3 ms; the first frame is the old chart, the last the new."""
    problems = []
    err = g20.mojo_test("tests/test_chartmove.mojo", "CHARTMOVE TESTS PASSED", "test_chartmove", "tests")
    if err:
        problems.append(err)
    g25.OUT = OUT
    out = g25.gtk(g25.SHEET + ";tap:Chart;pause:600;tap:as in the table;pause:150;tap:largest first;pause:900", "m5-move", MOJOUI_TRACE="1")[0]
    draws = [float(d) for d in re.findall(r"^TRACE: draw canvas 10 \S+ ([\d.]+) ms", out, re.M)]
    if len(draws) < 18:
        problems.append(f"the chart drew {len(draws)} times: the change was a cut, not a move")
    elif max(draws) > 3.0:
        problems.append(f"a frame of the move took {max(draws):.2f} ms")
    return not problems, "; ".join(problems) or (f"a re-order moves the bars over {len(draws) - 2} frames, each ≤ {max(draws):.1f} ms; "
                                                  "the first frame is the old chart, the last exactly the new (tests/test_chartmove.mojo)")


def todo(what):
    def fn():
        return False, f"not built yet: {what}"
    return fn


def m7():
    """Goal 27's checks (every earlier goal's inside them)."""
    problems = []
    for name, fn in [("27-M0", g27.m0), ("27-M1", g27.m1), ("27-M2", g27.m2), ("27-M3", g27.m3), ("27-M4", g27.m4), ("27-M5", g27.m5),
                     ("27-M6", g27.m6), ("27-M8", g27.m8), ("27-M7", g27.m7)]:
        ok, msg = fn()
        if not ok:
            problems.append(f"{name}: {msg}")
    return not problems, "; ".join(problems) or "goal 27's M0–M8 (goals 3–26 inside them) pass"


MILESTONES = [("M0", m0), ("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4),
              ("M5", m5), ("M6", todo("real input")), ("M7", m7)]


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
