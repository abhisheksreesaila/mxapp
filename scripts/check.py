"""Milestone checker for GOAL.md (goal 20: omxplorer on what MX frame can do now; goal 19's checks run as M4, every
earlier goal's inside them). Rebuilds from scratch, prints PASS/FAIL per milestone. omxplorer is driven through the
agent host (scripts/agent_client.py); the Parquet files are written by pyarrow (scripts/parquet_fixture.py), which
is also the oracle for their rows and sums.

Run: scripts/check   (a subset without rebuilding: scripts/check M1 M2; earlier goals: through docs/goals/NN-check.py)
"""

import decimal
import importlib.util
import os
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


g19 = load("goal19", "docs/goals/19-check.py")
g18 = g19.g18
run, BUILD, EXAMPLES = g18.run, g18.BUILD, g18.EXAMPLES
from agent_client import Client  # noqa: E402

DATA = BUILD / "g20"
BIG_ROWS = 100_000_000
GROUP = 1 << 20


def env(**more):
    return dict(g19.env(), **{k: str(v) for k, v in more.items()})


def fixture(kind, name, *args):
    """A pyarrow-written Parquet file in build/g20 (the big one is kept between runs: it takes a minute)."""
    DATA.mkdir(parents=True, exist_ok=True)
    path = DATA / name
    marker = DATA / (name + ".done")
    if not marker.exists() or marker.read_text() != (ROOT / "scripts/parquet_fixture.py").read_text():
        r = run(["pixi", "run", "python", "scripts/parquet_fixture.py", kind, str(path), *map(str, args)], timeout=1800)
        if r.returncode != 0:
            raise RuntimeError("parquet_fixture.py failed: " + (r.stdout + r.stderr)[-600:])
        marker.write_text((ROOT / "scripts/parquet_fixture.py").read_text())
    return path


def cell(v):
    """A value as omxplorer's grid shows it in a column with no format."""
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


def money(d):
    return f"{d:,.2f}"


def average(total, n):
    return money((total / n).quantize(decimal.Decimal("0.01"), rounding=decimal.ROUND_HALF_UP))


def opener(c):
    """The tool that opens a file (a FilePicker: it takes a path)."""
    return next((t["name"] for t in c.tools() if t["inputSchema"].get("required") == ["path"]), None)


def status_of(c):
    texts, _, _ = c.call("read")
    return [t[len("status-bar: "):] for t in texts.splitlines() if t.startswith("status-bar: ")]


def grid_rows(c, first, count):
    text, _, err = c.call("read", name="grid", first=first, count=count)
    if err or not text:
        return None, text
    head, *body = text.splitlines()
    return head.split("\t"), [r.split("\t") for r in body]


def peak_kb(pid):
    for line in Path(f"/proc/{pid}/status").read_text().splitlines():
        if line.startswith("VmHWM:"):
            return int(line.split()[1])
    return 0


def mojo_test(src, marker, name, *includes):
    b = run(["scripts/mxbuild.sh", *sum((["-I", i] for i in includes), []), src, "-o", str(BUILD / name)], timeout=1800)
    if b.returncode != 0:
        return f"{src} doesn't build: " + (b.stdout + b.stderr)[-600:]
    t = run([str(BUILD / name)], timeout=1800)
    if t.returncode != 0 or marker not in t.stdout:
        return f"{src} fails: " + (t.stdout + t.stderr)[-600:]
    return None


def m1():
    """omxplorer opens Parquet: the Import step, the sheet's rows and sum equal pyarrow's; a bad file says so."""
    import pyarrow.parquet as pq
    problems = []
    small = fixture("small", "small.parquet")
    table = pq.read_table(small)
    rows = table.to_pylist()
    names = table.column_names
    bad = DATA / "not.parquet"
    bad.write_text("order,amount\n1,2\n")
    c = Client(BUILD / "omxplorer" / "web", env())
    try:
        tool = opener(c)
        desc = next((t["description"] for t in c.tools() if t["name"] == tool), "")
        if tool is None or "parquet" not in desc.lower():
            problems.append(f"the Start screen's file picker doesn't say it takes Parquet: {tool} {desc!r}")
        text, _, err = c.call(tool, path=str(small)) if tool else ("", None, True)
        screen, _, _ = c.call("screen")
        if err or "Import small.parquet" not in screen or "5,000 rows · 5 columns" not in screen:
            problems.append(f"small.parquet didn't open the Import step with 5,000 rows and 5 columns: {screen[:400]!r}")
        for k in ("Integer", "Decimal", "Text", "Date", "Yes/No"):
            if k not in screen:
                problems.append(f"the Import step shows no {k} column")
        empties = {n: table.column(n).null_count for n in names}
        texts, _, _ = c.call("read")
        lines = [l.split(": ", 1)[-1] for l in texts.splitlines()]
        for n, kind in (("amount", "Decimal"), ("region", "Text")):  # (the Import step's row: COLUMN, TYPE, EMPTY)
            at = lines.index(n) if n in lines else -1
            if at < 0 or lines[at + 1:at + 3] != [kind, f"{empties[n]:,}"]:
                problems.append(f"the Import step's {n} row doesn't show {kind} and {empties[n]} empty cells: {lines[at:at + 3] if at >= 0 else lines[:30]}")
        text, _, err = c.call("create-table")
        if err:
            problems.append(f"create-table failed: {text[:200]!r}")
        head, body = grid_rows(c, 0, 40)
        if head != names:
            problems.append(f"the grid's header isn't pyarrow's columns: {head} {body!r}")
        else:
            want = [[cell(r[n]) for n in names] for r in rows[:40]]
            if body != want:
                diff = next(((i, a, b) for i, (a, b) in enumerate(zip(body, want)) if a != b), None)
                problems.append(f"the grid's first 40 rows differ from pyarrow's (first difference {diff})")
        status = status_of(c)
        total = sum((v for v in table.column("amount").to_pylist() if v is not None), decimal.Decimal(0))
        present = len(rows) - empties["amount"]
        for want in ("Rows 5,000", "Sum " + money(total), "Average " + average(total, present)):
            if want not in status:
                problems.append(f"the status bar lacks {want!r}: {status}")
        tool = opener(c)
        text, _, err = c.call(tool, path=str(bad)) if tool else ("", None, True)
        status = status_of(c)
        if not any("not a Parquet file" in s for s in status) or "Rows 5,000" not in status:
            problems.append(f"a file that isn't Parquet didn't say so, or the sheet changed: {status}")
    finally:
        log = c.close()
    if "Traceback" in log:
        problems.append("the agent host logged a traceback: " + log[-400:])
    err = mojo_test("tests/test_parquet_import.mojo", "PARQUET IMPORT TESTS PASSED", "test_parquet_import")
    if err:
        problems.append(err)
    return not problems, "; ".join(problems) or "small.parquet (pyarrow) through the Import step; 40 rows, the sum and the average equal pyarrow's; a bad file says so and the sheet stays"


def m2():
    """Files bigger than memory: 100M rows streamed; rows far down, the totals, a chart and a pivot equal pyarrow's;
    edits off; peak memory under a quarter of the table."""
    import pyarrow.parquet as pq
    problems = []
    big = fixture("big", "big.parquet", BIG_ROWS)
    pf = pq.ParquetFile(big)
    names = pf.schema_arrow.names
    in_memory = BIG_ROWS * len(names) * 8
    total, present, by_region, rows_by_region = decimal.Decimal(0), 0, {}, {}
    import pyarrow.compute as pc
    for g in range(pf.num_row_groups):
        t = pf.read_row_group(g, columns=["amount", "region"])
        s = pc.sum(t.column("amount")).as_py()
        total += s if s is not None else 0
        present += len(t) - t.column("amount").null_count
        grouped = t.group_by("region").aggregate([("amount", "sum"), ("amount", "count")])
        for region, amount in zip(grouped.column("region").to_pylist(), grouped.column("amount_sum").to_pylist()):
            by_region[region] = by_region.get(region, decimal.Decimal(0)) + (amount or 0)
    far = 73_456_789
    want_far = [[cell(v) for v in r.values()] for r in pf.read_row_group(far // GROUP).slice(far % GROUP, 5).to_pylist()]
    want_top = [[cell(v) for v in r.values()] for r in pf.read_row_group(0).slice(0, 20).to_pylist()]
    c = Client(BUILD / "omxplorer" / "web", env(OMX_STREAM_ROWS=10_000_000))
    try:
        base = peak_kb(c.p.pid)
        tool = opener(c)
        t0 = time.time()
        c.call(tool, path=str(big)) if tool else None
        screen, _, _ = c.call("screen")
        if "streamed" not in screen.lower() or "100,000,000 rows" not in screen:
            problems.append(f"the Import step doesn't say the 100M-row file is streamed: {screen[:400]!r}")
        text, _, err = c.call("create-table")
        opened = time.time() - t0
        screen, _, _ = c.call("screen")
        if err or "Rows 100,000,000" not in screen:
            problems.append(f"the streamed sheet didn't open with 100,000,000 rows: {screen[:400]!r}")
        head, body = grid_rows(c, 0, 20)
        if head != names or body != want_top:
            problems.append(f"the streamed grid's first 20 rows differ from pyarrow's: {head} {(body or [])[:2]}")
        head, body = grid_rows(c, far, 5)
        if body != want_far:
            problems.append(f"rows {far:,}… differ from pyarrow's: {(body or [])[:2]} vs {want_far[:2]}")
        status = status_of(c)
        for want in ("Sum " + money(total), "Average " + average(total, present)):
            if want not in status:
                problems.append(f"the streamed status bar lacks {want!r}: {status}")
        names_now = set(c.names())
        for off in ("data-sort-largest-first", "data-sort-smallest-first", "file-save", "insert-formula-column", "edit-add-row"):
            if off in names_now:
                problems.append(f"{off} is offered on a streamed (read-only) sheet")
        if "read-only" not in screen.lower():
            problems.append("the streamed sheet doesn't say it's read-only")
        text, _, err = c.call("grid", gesture="double", x=160, y=60)  # (a cell: try to edit it)
        status = status_of(c)
        if err or not any("Can't edit" in s and "read-only" in s for s in status) or any("is a formula" in s for s in status):
            problems.append(f"editing a streamed cell doesn't say it's read-only: {status}")
        text, _, err = c.call("insert-chart")
        lines, _, err2 = c.call("read", name="chart-1") if "chart-1" in c.names() else ("", None, True)
        if err or err2:
            problems.append(f"the chart on the streamed sheet can't be read: {text[:200]!r} {lines[:200]!r} (tools {sorted(c.names())[:40]})")
        else:
            got = dict(l.split("\t") for l in lines.splitlines()[1:])
            for region, amount in by_region.items():
                if got.get(region if region is not None else "(blank)") != money(amount):
                    problems.append(f"the chart's {region} is {got.get(region)} (pyarrow {money(amount)})")
        text, _, err = c.call("insert-pivot-table")
        texts, _, _ = c.call("read")
        missing = [r for r, a in by_region.items() if money(a) not in texts]
        if err or missing:
            problems.append(f"the pivot on the streamed sheet lacks pyarrow's sums for {missing}: {text[:200]!r}")
        peak = peak_kb(c.p.pid) * 1024
        if peak > in_memory // 4:
            problems.append(f"peak memory {peak / 1e9:.2f} GB is over a quarter of the table's {in_memory / 1e9:.1f} GB (at the start {base * 1024 / 1e9:.2f} GB)")
    finally:
        log = c.close()
    if "Traceback" in log:
        problems.append("the agent host logged a traceback: " + log[-400:])
    err = mojo_test("tests/test_streamed.mojo", "STREAMED TESTS PASSED", "test_streamed")
    if err:
        problems.append(err)
    return not problems, "; ".join(problems) or f"100,000,000 rows streamed (opened in {opened:.1f} s): rows far down, Sum, Average, a chart and a pivot equal pyarrow's; edits, sorts, formulas and Save off; peak {peak / 1e9:.2f} GB for a {in_memory / 1e9:.1f} GB table"


def m3():
    """No Python in the framework: the Workbook's files and the analytics engine are on the package."""
    problems = []
    for f in sorted((ROOT / "mojoui").rglob("*.mojo")):
        if re.search(r"^\s*from std\.python|^\s*import std\.python", f.read_text(), re.M):
            problems.append(f"{f.relative_to(ROOT)} imports std.python")
    for app in ("workbook", "analytics"):
        exe = BUILD / app / "linux" / app
        if not exe.exists():
            problems.append(f"{exe} isn't built")
            continue
        if "libpython" in run(["ldd", str(exe)]).stdout.lower():
            problems.append(f"{app}'s Linux binary links libpython")
        if "KGEN_CompilerRT_Python" in run(["nm", "-D", str(exe)]).stdout:
            problems.append(f"{app}'s Linux binary uses Mojo's Python interop")
    for src, marker, name, inc in (("tests/test_workbook.mojo", "WORKBOOK TESTS PASSED", "test_workbook", ()),
                                   ("tests/test_analytics.mojo", "ANALYTICS TESTS PASSED", "test_analytics", ("examples/analytics",))):
        err = mojo_test(src, marker, name, *inc)
        if err:
            problems.append(err)
    t = (ROOT / "tests/test_workbook.mojo").read_text()
    if "workbook-pyarrow.mxwb" not in t:
        problems.append("test_workbook doesn't open the workbook pyarrow saved (tests/fixtures/workbook-pyarrow.mxwb)")
    return not problems, "; ".join(problems) or "no mojoui module imports std.python; the Workbook and analytics binaries link no libpython; workbooks round-trip and the pyarrow-saved one opens; analytics' engine totals pass"


def m4():
    """Nothing regressed: goal 19's milestones (goal 18's, F-138's guard and every earlier goal's inside them); the
    plans are current."""
    problems = []
    for name, fn in [("19-M1", g19.m1), ("19-M2", g19.m2), ("19-M3", g19.m3), ("19-M4", g19.m4), ("19-M5", g19.m5)]:
        ok, msg = fn()
        if not ok:
            problems.append(f"{name}: {msg}")
    plan = (ROOT / "docs/plans/needs-mxframe.md").read_text()
    for needle in ("scan_parquet", "Parquet files open", "no Python"):
        if needle not in plan:
            problems.append(f"docs/plans/needs-mxframe.md doesn't mention {needle!r}")
    return not problems, "; ".join(problems) or "goal 19's M1–M5 (goals 3–18 and F-138 inside them) pass; needs-mxframe.md is current"


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
