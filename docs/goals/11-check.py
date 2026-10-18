"""Milestone checker for goal 11 (archived: docs/goals/11-mxstudio-sheet.md: MX Studio's Sheet, components first; goal 10's checks run as M6,
earlier goals' inside them). Rebuilds from scratch, prints PASS/FAIL per milestone. GTK runs headless.

Run: scripts/check   (a subset without rebuilding: scripts/check M4 M5; earlier goals: docs/goals/NN-check.py)
"""

import importlib.util
import re
import sys
from pathlib import Path

ROOT = next(p for p in Path(__file__).resolve().parents if (p / "pixi.toml").exists())  # (archived in docs/goals/)
sys.path.insert(0, str(ROOT / "scripts"))

_spec = importlib.util.spec_from_file_location("goal10", ROOT / "docs/goals/10-check.py")
g10 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g10)
g9 = g10.g9
run, BUILD = g10.run, g10.BUILD

import drive  # noqa: E402

EXAMPLES = g10.EXAMPLES + ["mxstudio"]
SHOWN = r"^(LABEL|TONE|SEGMENTED|TABS|DROPDOWN|BUTTON|FIELD|TEXTAREA|BOARD): "
TIMING = re.compile(r"^LABEL: [\d.]+ ms on ")

# Steps on the Sheet (grid = canvas 0; positions in thousandths of it). Row 7 of the ledger is "Acme Corp.".
EDIT = "doubletap:0=352,509;enter:Cell=Acme Corp;doubletap:0=875,509;enter:Cell=50000"  # rename, then $50,000 on the same order
MERGE = "tap:Merge into “Acme Corp”"
UNDO = MERGE + ";tap:Undo all edits"


def shown(out):
    return sorted(l for l in out.splitlines() if re.match(SHOWN, l) and not TIMING.match(l))


def label(out, start):
    return next((l[len("LABEL: "):] for l in out.splitlines() if l.startswith("LABEL: " + start)), None)


def labels(out):
    return [l[len("LABEL: "):] for l in out.splitlines() if l.startswith("LABEL: ")]


def gtk(steps, shot=None, env=None):
    e = {"MOJOUI_TEST": steps, "MOJOUI_SHOT": shot or str(BUILD / "mxstudio" / "gtk.png")}
    e.update(env or {})
    exe = BUILD / "mxstudio" / "linux" / "mxstudio"
    if not exe.exists():
        return None, f"no {exe}"
    r = run([str(exe)], env=e, timeout=900)
    out = r.stdout + r.stderr
    if r.returncode != 0 or "CRITICAL" in out or "TEST: " in out:
        return None, f"GTK run failed (exit {r.returncode}):\n{out[-600:]}"
    return r, out


def both(steps, name):
    rg, og = gtk(steps, shot=str(BUILD / "mxstudio" / f"{name}-gtk.png"))
    if rg is None:
        return None, f"GTK: {og[-300:]}"
    try:
        rw, ow = drive.web_run(BUILD / "mxstudio" / "web", steps, shot=str(BUILD / "mxstudio" / f"{name}-web.png"), viewport=(1440, 900))
    except Exception as e:
        return None, f"web run crashed: {e!r}"
    if rw.returncode != 0:
        return None, f"web: {ow[-300:]}"
    return og, ow


def built_test(src, out_name, marker, includes=(".",)):
    args = ["scripts/mxbuild.sh"]  # (goal 20: the tests link the MX frame package, D-189)
    for inc in includes:
        args += ["-I", inc]
    b = run(args + [src, "-o", str(BUILD / out_name)], timeout=900)
    if b.returncode != 0:
        return False, f"{src} build: {(b.stdout + b.stderr)[-400:]}"
    t = run(["pixi", "run", str(BUILD / out_name)], timeout=900)
    return marker in t.stdout, (t.stdout + t.stderr)[-400:]


def m1():
    problems = []
    if "trait GridSource" not in (ROOT / "mojoui/datagrid.mojo").read_text():
        return False, "no GridSource in mojoui/datagrid.mojo"
    if "draw_grid" in (ROOT / "examples/workbook/app.mojo").read_text():
        problems.append("the Workbook still draws its own grid")
    ok, out = built_test("tests/test_datagrid.mojo", "test_datagrid", "DATAGRID TESTS PASSED")
    if not ok:
        problems.append(f"test_datagrid: {out}")
    ok, out = built_test("tests/bench_workbook.mojo", "bench_workbook", "WORKBOOK TESTS PASSED", ("examples/workbook", "."))
    if not ok:
        problems.append(f"bench_workbook: {out}")
    for name in ("m4", "m5", "m11", "m12"):
        ok, msg = getattr(g10, name)()
        if not ok:
            problems.append(f"goal 10 {name.upper()}: {msg[:200]}")
    return not problems, "; ".join(problems) or "mojoui/datagrid.mojo (GridSource) with its own test; the Workbook runs on it; goal 10's grid checks pass"


def m2():
    problems = []
    for f, needle in (("mojoui/pivot.mojo", "def PivotTable("), ("mojoui/chartview.mojo", "struct ChartView"), ("mojoui/view.mojo", "CARD_WARN")):
        if needle not in (ROOT / f).read_text():
            problems.append(f"{f} lacks {needle}")
    ok, out = built_test("tests/test_components.mojo", "test_components", "COMPONENT TESTS PASSED")
    if not ok:
        problems.append(f"test_components: {out}")
    app = (ROOT / "examples/workbook/app.mojo").read_text()
    for needle in ("PivotTable(", "ChartView("):
        if needle not in app:
            problems.append(f"the Workbook doesn't use {needle}")
    r = run(["pixi", "run", "python", "scripts/components.py", "--check"], timeout=120)
    if r.returncode != 0:
        problems.append("docs/components.md is stale")
    doc = (ROOT / "docs/components.md").read_text()
    for name in ("DataGrid", "PivotTable", "ChartView", "Card tones"):
        row = next((l for l in doc.splitlines() if l.startswith(f"| `{name}`") or l.startswith(f"| {name} ")), "")
        if row.count("✅") < 2:
            problems.append(f"the matrix doesn't show {name} ✅ on Linux and web: {row[:120]}")
    return not problems, "; ".join(problems) or "PivotTable, ChartView, Card and Text tones in mojoui with a test; the Workbook uses them; the matrix shows them ✅ on Linux and web"


def m3():
    ok, out = built_test("tests/test_orders.mojo", "test_orders", "ORDERS TESTS PASSED", ("examples/mxstudio", "."))
    if not ok:
        return False, f"test_orders: {out}"
    facts = re.search(r"ORDERS: .*", out)
    margin = re.search(r"MARGIN: .*", out)
    return True, (facts.group(0) if facts else "") + (" · " + margin.group(0) if margin else "")


def m4():
    problems = []
    start = both("", "sheet")
    edit = both(EDIT, "edit")
    for o in (start, edit):
        if o[0] is None:
            return False, o[1]
    for host, o in (("GTK", start[0]), ("web", start[1])):
        got = labels(o)
        for want in ("Transactions", "Pivot 1", "Chart 1", "Inspector", "Comes from", "Feeds", "Your edits"):
            if want not in got:
                problems.append(f"{host}: no '{want}'")
        if label(o, "Rows 2,000,000") is None or label(o, "Sum revenue $") is None or label(o, "Distinct customers 20") is None:
            problems.append(f"{host}: the status bar isn't exact: {[l for l in got if l.startswith(('Rows', 'Sum', 'Distinct'))]}")
        if not re.search(r"^SEGMENTED: Sheet", o, re.M):
            problems.append(f"{host}: no mode switch")
    for host, o in (("GTK", edit[0]), ("web", edit[1])):
        if label(o, "#100006 customer: Acme Corp. → Acme Corp") is None:
            problems.append(f"{host}: the inspector doesn't list the edit")
    pivot = lambda o: [l for l in labels(o) if l.startswith("$")]
    if pivot(start[0]) == pivot(edit[0]):
        problems.append("the pivot didn't change after the edits")
    for host, o in (("GTK", edit[0]), ("web", edit[1])):
        if label(o, "revenue on row 7: 30.00 → 50000.00") is None:
            problems.append(f"{host}: the revenue edit didn't write: {[l for l in labels(o) if 'row 7' in l][:2]}")
    if label(start[0], "Sum revenue") == label(edit[0], "Sum revenue"):
        problems.append("the exact sum didn't follow the revenue edit")
    if shown(start[0]) != shown(start[1]) or shown(edit[0]) != shown(edit[1]):
        diff = sorted(set(shown(edit[0])) ^ set(shown(edit[1])))[:4]
        problems.append(f"GTK and web differ: {diff}")
    big = gtk("", shot=str(BUILD / "mxstudio" / "sheet-20m-gtk.png"), env={"MOJOUI_ROWS": "20000000"})
    if big[0] is None or label(big[1], "Rows 20,000,000") is None:
        problems.append(f"at 20M rows: {(big[1] or '')[-200:]}")
    return not problems, "; ".join(problems) or "the Sheet on both hosts: grid, Pivot 1, Chart 1, inspector, exact status; an in-place edit regroups the pivot and shows in Your edits; also at 20M rows"


def m5():
    problems = []
    start = both("", "finding")
    merged = both(MERGE, "merged")
    undone = both(UNDO, "undone")
    for o in (start, merged, undone):
        if o[0] is None:
            return False, o[1]
    for host, o in (("GTK", start[0]), ("web", start[1])):
        if "Agent noticed" not in labels(o) or label(o, "3 spellings of one customer") is None:
            problems.append(f"{host}: no finding at start")
        if not re.search(r"^TONE: Acme Corp\. = warn$", o, re.M):  # the host really colours the duplicate's pivot row
            problems.append(f"{host}: the duplicate spelling's pivot row isn't in the warning tone")
    for host, o in (("GTK", merged[0]), ("web", merged[1])):
        if re.search(r"^TONE: .* = warn$", o, re.M) and not re.search(r"^TONE: Agent", o, re.M):
            warn_rows = re.findall(r"^TONE: (.*) = warn$", o, re.M)
            if any(w.startswith("Acme") for w in warn_rows):
                problems.append(f"{host}: rows still in the warning tone after the merge: {warn_rows[:3]}")
    for host, o in (("GTK", merged[0]), ("web", merged[1])):
        if "Names are clean" not in labels(o) or label(o, "Distinct customers 18") is None:
            problems.append(f"{host}: the merge didn't regroup ({[l for l in labels(o) if 'Distinct' in l]})")
        if "Acme Corp." in labels(o):
            problems.append(f"{host}: 'Acme Corp.' still in the pivot after the merge")
        if label(o, "merged spellings into Acme Corp") is None:
            problems.append(f"{host}: the merge isn't one step in Your edits")
    for host, o in (("GTK", undone[0]), ("web", undone[1])):
        if label(o, "Distinct customers 20") is None or "Agent noticed" not in labels(o):
            problems.append(f"{host}: Undo all didn't bring the spellings back")
    for name, o in (("start", start), ("merged", merged), ("undone", undone)):
        if shown(o[0]) != shown(o[1]):
            problems.append(f"{name}: GTK and web differ: {sorted(set(shown(o[0])) ^ set(shown(o[1])))[:3]}")
    return not problems, "; ".join(problems) or "the agent finds 3 spellings with their rows; Merge regroups (20 → 18 customers) as one undoable step; identical on both hosts"


def m6():
    problems = []
    for name in ("m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m9", "m10", "m11", "m12", "m13", "m14"):
        ok, msg = getattr(g10, name)()
        if not ok:
            problems.append(f"goal 10 {name.upper()}: {msg[:200]}")
    r = run(["pixi", "run", "python", "scripts/components.py", "--check"], timeout=120)
    if r.returncode != 0:
        problems.append("the component matrix is stale")
    return not problems, "; ".join(problems) or "goal 10's checks (and goals 3–9's inside them) pass; the component matrix is current"


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
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5), ("M6", m6)]:
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
