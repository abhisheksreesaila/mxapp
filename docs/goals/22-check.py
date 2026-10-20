"""Milestone checker for GOAL.md (goal 22: omxplorer on MX frame 7cbcc04: streamed files editable, Distinct and Median
tiles; goal 21's checks run as M4, every earlier goal's inside them). Rebuilds from scratch, prints PASS/FAIL per
milestone. omxplorer is driven through the agent host (scripts/agent_client.py), on GTK and in Chromium; pyarrow writes
the Parquet files (scripts/parquet_fixture.py) and is the oracle for their rows, sums, distinct counts and medians.

Run: scripts/check   (a subset without rebuilding: scripts/check M1 M2; earlier goals: through docs/goals/NN-check.py)
"""

import decimal
import importlib.util
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


g21 = load("goal21", "docs/goals/21-check.py")
g20 = g21.g20
run, BUILD = g20.run, g20.BUILD
from agent_client import Client  # noqa: E402

OUT = BUILD / "g22"
LAPTOP = 8 << 30  # OMX_MEMORY_BYTES: act as an 8 GB machine (D-217): the 4 GB table streams, its sort (5 GB) doesn't fit
D = decimal.Decimal


def env(tag, **more):
    home = OUT / tag
    for d in ("docs", "config", "uploads"):
        (home / d).mkdir(parents=True, exist_ok=True)
    return dict(g20.g19.env(), OMX_DOCUMENTS=str(home / "docs"), OMX_CONFIG=str(home / "config"), OMXAPP_UPLOADS=str(home / "uploads"),
                **{k: str(v) for k, v in more.items()})


def status(c):
    return g20.status_of(c)


def timing(items):
    """The status bar's own timing ("12.3 ms on CPU") as milliseconds, else None."""
    for s in items:
        m = re.search(r"([\d.]+) ms on ", s)
        if m:
            return float(m.group(1))
    return None



from engine_lineage import vendored_at_least  # (D-269: a later stable engine, proved from its archive)


def m1():
    """The package at 7cbcc04; the 100M-row streamed file as goal 20 proved it; the times measured."""
    problems = []
    err = vendored_at_least("7cbcc04")
    if err:
        problems.append(err)
    ok, msg = g20.m2()  # (100M rows streamed: rows, Sum, Average, a chart and a pivot equal pyarrow's; the file deleted or grown)
    if not ok:
        problems.append("goal 20's M2: " + msg)
    opened = re.search(r"opened in ([\d.]+) s", msg)
    big = g20.fixture("big", "big.parquet", g20.BIG_ROWS)
    c = Client(BUILD / "omxplorer" / "web", env("times", OMX_STREAM_ROWS=10_000_000))
    times = {}
    try:
        c.call(g20.opener(c), path=str(big))
        c.call("create-table")
        times["total"] = timing(status(c))
        c.call("insert-chart")
        chart = [s for s in status(c) if s.startswith("Chart: ")]
        m = re.search(r"\(([\d.]+) ms on", chart[0]) if chart else None
        times["group-by"] = float(m.group(1)) if m else None
    finally:
        c.close()
    if None in times.values():
        problems.append(f"the streamed total's or chart's time wasn't shown: {times}")
    else:
        (OUT / "times.txt").write_text(f"open {opened.group(1) if opened else '?'} s, total {times['total']:.0f} ms, group-by {times['group-by']:.0f} ms\n")
    return not problems, "; ".join(problems) or (
        f"vendored from 7cbcc04; 100M streamed rows open in {opened.group(1) if opened else '?'} s, a total takes {times['total']:.0f} ms, "
        f"a group-by {times['group-by']:.0f} ms; rows, totals, a chart and a pivot equal pyarrow's (goal 20's M2)")


def m2():
    """A 100M-row streamed file edited, totalled, charted, undone, sorted (refused on a small machine) and saved."""
    import pyarrow.parquet as pq
    import pyarrow.compute as pc
    problems = []
    big = g20.fixture("big", "big.parquet", g20.BIG_ROWS)
    pf = pq.ParquetFile(big)
    first = pf.read_row_group(0).slice(0, 3).to_pylist()
    total, by_region = D(0), {}
    for g in range(pf.num_row_groups):
        t = pf.read_row_group(g, columns=["amount", "region"])
        total += pc.sum(t.column("amount")).as_py() or 0
        grouped = t.group_by("region").aggregate([("amount", "sum")])
        for region, amount in zip(grouped.column("region").to_pylist(), grouped.column("amount_sum").to_pylist()):
            by_region[region] = by_region.get(region, D(0)) + (amount or 0)
    new0 = D("1000000.00")
    old0, old2 = first[0]["amount"] or D(0), first[2]["amount"] or D(0)
    want_total = total - old0 + new0 - old2
    want_regions = dict(by_region)
    want_regions[first[0]["region"]] += new0 - old0
    want_regions[first[2]["region"]] -= old2
    in_memory = g20.BIG_ROWS * 5 * 8
    doc = None
    c = Client(BUILD / "omxplorer" / "web", env("edit", OMX_MEMORY_BYTES=LAPTOP))
    try:
        c.call(g20.opener(c), path=str(big))
        if "streamed" not in g21.screen(c).lower():
            problems.append("on an 8 GB machine the 100M-row file doesn't open streamed by itself")
        c.call("create-table")
        c.call("value-or-formula", text=str(new0), submit=True)  # (amount on row 1 is selected)
        c.call("grid", gesture="tap", x=g21.COLUMN_X, y=86)  # (amount on row 3: empty it)
        c.call("value-or-formula", text="", submit=True)
        head, body = g20.grid_rows(c, 0, 3)
        if not body or body[0][1] != "1000000.00" or body[2][1] != "":
            problems.append(f"the streamed grid doesn't show the edits: {body}")
        c.call("add-row")  # (the grid scrolls to the new last row)
        if not any("Rows 100,000,001" in s for s in status(c)):
            problems.append(f"Add row on the streamed sheet didn't make 100,000,001 rows: {status(c)}")
        c.call("formula")
        c.call("a-new-column-its-name-then-its-formula", text="double = amount * 2", submit=True)
        head, body = g20.grid_rows(c, 0, 40)
        doubles = [r for r in body or [] if r[1] != ""]
        if (head or [""])[-1] != "double" or not doubles or any(D(r[-1]) != 2 * D(r[1]) for r in doubles) or body[-1][1] != "":
            problems.append(f"the formula column over the streamed rows isn't amount × 2 (or the new row isn't last and empty): {head} {body}")
        c.call("grid", gesture="tap", x=g21.COLUMN_X, y=12)  # (the column: its totals)
        if not any(s == "Sum " + g20.money(want_total) for s in status(c)):
            problems.append(f"the streamed Sum doesn't include the edits ({g20.money(want_total)}): {status(c)}")
        c.call("insert-chart")
        lines, _, err = c.call("read", name="chart-1")
        got = dict(l.split("\t") for l in lines.splitlines()[1:]) if not err else {}
        for region, amount in want_regions.items():
            if got.get(region if region is not None else "(blank)") != g20.money(amount):
                problems.append(f"the streamed chart's {region} is {got.get(region)}, not {g20.money(amount)} with the edits")
        c.call("undo")  # (the formula column goes: the sheet logs formulas)
        if "double" in (g20.grid_rows(c, 0, 1)[0] or []) or not any("Undid the formula column double" in s for s in status(c)):
            problems.append(f"Undo on the streamed sheet didn't take the formula column back: {status(c)}")
        c.call("undo")  # (then the added row)
        c.call("grid", gesture="tap", x=g21.COLUMN_X, y=12)
        if not any(s == "Rows 100,000,000" for s in status(c)) or not any(s == "Sum " + g20.money(want_total) for s in status(c)):
            problems.append(f"Undo on the streamed sheet didn't take the added row back: {status(c)}")
        c.call("formula")  # (the formula again, and a format, for the saved document)
        c.call("a-new-column-its-name-then-its-formula", text="double = amount * 2", submit=True)
        c.call("grid", gesture="tap", x=g21.COLUMN_X, y=12)
        c.call("currency")
        c.call("bold")
        c.call("tab-1")  # (the Report: on an 8 GB machine a median of 100M rows doesn't fit, a distinct count of a text column does)
        c.call("median-tile")
        if not any("the median of amount" in s and "GB" in s for s in status(c)):
            problems.append(f"a Median of 100M streamed rows on an 8 GB machine wasn't refused with the reason: {status(c)}")
        c.call("tiles-of", option="region")
        c.call("distinct-tile")
        if '"Different region"' not in g21.screen(c) or f'"{len([r for r in by_region if r is not None])}"' not in g21.screen(c):
            problems.append(f"the Distinct tile of region over 100M streamed rows isn't {len([r for r in by_region if r is not None])}")
        c.call("tab-0")
        c.call("sort")
        if not any("sorting" in s and "GB" in s for s in status(c)):
            problems.append(f"sorting 100M streamed rows on an 8 GB machine wasn't refused with the reason: {status(c)}")
        t0 = time.time()
        c.call("save")
        saved_s = time.time() - t0
        saved = [s for s in status(c) if s.startswith("Saved ")]
        doc = saved[0][len("Saved "):] if saved else None
        if not doc:
            problems.append(f"Save of the streamed sheet didn't save: {status(c)}")
        peak = g20.peak_kb(c.p.pid) * 1024
        if peak > in_memory // 4:
            problems.append(f"peak memory {peak / 1e9:.2f} GB is over a quarter of the {in_memory / 1e9:.1f} GB table")
    finally:
        log = c.close()
    if "Traceback" in log:
        problems.append("the agent host logged a traceback: " + log[-400:])
    if doc:
        sf = pq.ParquetFile(doc)
        rows = sf.metadata.num_rows
        top = sf.read_row_group(0).slice(0, 3).to_pylist()
        last = sf.read_row_group(sf.num_row_groups - 1).to_pylist()[-1]
        want_last = pf.read_row_group(pf.num_row_groups - 1).to_pylist()[-1]
        if rows != g20.BIG_ROWS or top[0]["amount"] != new0 or top[2]["amount"] is not None or last != want_last or "double" in sf.schema_arrow.names:
            problems.append(f"the saved file isn't the edited table: {rows:,} rows, row 1 {top[0]['amount']}, row 3 {top[2]['amount']}, last {last} vs {want_last}")
        c = Client(BUILD / "omxplorer" / "web", env("reopen", OMX_MEMORY_BYTES=LAPTOP, OMX_OPEN=doc))
        try:
            s = g21.screen(c)
            head, body = g20.grid_rows(c, 0, 2)
            if "streamed" not in s.lower() or not body or body[0][1] != "$1,000,000.00" or (head or [""])[-1] != "double":
                problems.append(f"the saved document doesn't reopen streamed with its edit, format and formula: {head} {(body or [])[:1]}")
            if not g21.pressed(s, "Bold") or not g21.pressed(s, "Currency"):
                problems.append("the reopened streamed document's amount isn't bold currency")
        finally:
            c.close()
    # where memory allows (this machine), sorting 100M streamed rows works: the largest first, in order far down
    sorted_s = None
    c = Client(BUILD / "omxplorer" / "web", env("sort", OMX_STREAM_ROWS=10_000_000))
    try:
        c.call(g20.opener(c), path=str(big))
        c.call("create-table")
        c.call("grid", gesture="tap", x=g21.COLUMN_X, y=12)
        t0 = time.time()
        c.call("data-sort-largest-first")
        sorted_s = time.time() - t0
        _, top = g20.grid_rows(c, 0, 3)
        _, far = g20.grid_rows(c, 50_000_000, 20)
        biggest = pc.max(pq.read_table(big, columns=["amount"]).column("amount")).as_py()
        amounts = [D(r[1]) for r in far or [] if r[1] != ""]
        if not top or top[0][1] != str(biggest) or len(amounts) < 10 or amounts != sorted(amounts, reverse=True):
            problems.append(f"sorting 100M streamed rows (allowed here) isn't largest first ({biggest}) and in order far down: {(top or [])[:1]} {amounts[:3]}")
    finally:
        log = c.close()
    if "Traceback" in log:
        problems.append("the agent host logged a traceback (sort): " + log[-400:])
    err = g20.mojo_test("tests/test_streamed.mojo", "STREAMED TESTS PASSED", "test_streamed")
    if err:
        problems.append(err)
    return not problems, "; ".join(problems) or (
        f"100M streamed rows: a typed value, an emptied cell, a new row and a formula show, total and chart with the edits; Undo takes the "
        f"formula, then the row back; on an 8 GB machine sorting and a median are refused with the reason, a distinct count of region "
        f"works; saved (streamed, {saved_s:.0f} s) to a file pyarrow reads with the edits, which reopens streamed, bold currency; peak "
        f"{peak / 1e9:.2f} GB; here, a sort of all 100M rows takes {sorted_s:.0f} s and reads in order far down")


def oracle_stats(path, west=False):
    import pyarrow.parquet as pq
    import statistics
    t = pq.read_table(path).to_pylist()
    if west:
        t = [r for r in t if r["region"] == "West"]
    amounts = sorted(r["amount"] for r in t if r["amount"] is not None)
    median = statistics.median(amounts)  # (the mean of the two middle values: pandas, DuckDB, Excel)
    return {"median": f"{median.quantize(D('0.01'), rounding=decimal.ROUND_HALF_UP):,}",
            "regions": len({r["region"] for r in t if r["region"] is not None}),
            "amounts": len(set(amounts))}


def m3():
    """Distinct and Median tiles from the engine, in memory and streamed, filtered, saved; GTK and the web agree."""
    problems = []
    small = g20.fixture("small", "small.parquet")
    every, west = oracle_stats(small), oracle_stats(small, west=True)
    docs = {}
    for kind, more in (("memory", {}), ("streamed", {"OMX_STREAM_ROWS": 1000})):
        c = Client(BUILD / "omxplorer" / "web", env("stats-" + kind, **more))
        try:
            g21.open_small(c, small)
            c.call("tab-1")
            c.call("median-tile")
            c.call("distinct-tile")
            c.call("tiles-of", option="region")
            c.call("distinct-tile")
            c.call("median-tile")  # (refused: region is text)
            s = g21.screen(c)
            for want in (f'"Median of amount"', f'"{every["median"]}"', '"Different amount"', f'"{every["amounts"]:,}"', '"Different region"', f'"{every["regions"]}"'):
                if want not in s:
                    problems.append(f"{kind}: the Report lacks {want}")
            if not any("Median needs a number column" in t for t in status(c)):
                problems.append(f"{kind}: a Median of a text column wasn't refused with the reason: {status(c)}")
            c.call("filter-column", option="region")
            c.call("filter-value", option="West")
            s = g21.screen(c)
            for want in (f'"{west["median"]}"', f'"{west["amounts"]:,}"'):
                if want not in s:
                    problems.append(f"{kind}: with region = West the tiles don't show {want}")
            c.call("save")
            saved = [t for t in status(c) if t.startswith("Saved ")]
            docs[kind] = saved[0][len("Saved "):] if saved else None
        finally:
            log = c.close()
        if "Traceback" in log:
            problems.append(f"{kind}: the agent host logged a traceback: " + log[-300:])
        if docs.get(kind):
            c = Client(BUILD / "omxplorer" / "web", env("stats-reopen-" + kind, OMX_OPEN=docs[kind], **more))
            try:
                c.call("tab-1")
                s = g21.screen(c)
                if f'"{west["median"]}"' not in s or '"Different region"' not in s:
                    problems.append(f"{kind}: the reopened Report lost its Median or Distinct tiles")
            finally:
                c.close()
    steps = f"pick:Choose a file={small};tap:Create table;tap:Report;tap:Median tile;tap:Distinct tile;select:0=region;tap:Distinct tile"
    try:
        og, ow = g21.gtk(steps, "stats"), g21.web(steps, "stats")
        for host, out in (("GTK", og), ("web", ow)):
            lines = set(out.splitlines())
            for want in (every["median"], f'{every["amounts"]:,}', str(every["regions"])):
                if f"LABEL: {want}" not in lines:  # (whole lines: "5" mustn't match "5,005.54")
                    problems.append(f"{host}: the tiles don't show {want}")
    except RuntimeError as e:
        problems.append(str(e))
    # a formula column a tile reads can't be undone from under it: Undo says what reads it; without the tile it goes
    c = Client(BUILD / "omxplorer" / "web", env("stats-undo"))
    try:
        g21.open_small(c, small)
        c.call("formula")
        c.call("a-new-column-its-name-then-its-formula", text="double = amount * 2", submit=True)
        c.call("tab-1")
        c.call("tiles-of", option="double")
        c.call("sum-tile")
        c.call("undo")
        if not any("Can't undo the formula column double yet: a Report tile reads it" in t for t in status(c)) or '"Sum of double"' not in g21.screen(c):
            problems.append(f"Undo of a formula column a tile reads wasn't refused with the reason: {status(c)}")
        c.call("remove")
        c.call("undo")
        if not any("Undid the formula column double" in t for t in status(c)):
            problems.append(f"without the tile, Undo didn't take the formula column back: {status(c)}")
    finally:
        log = c.close()
    if "Traceback" in log:
        problems.append("the agent host logged a traceback (undo): " + log[-300:])
    err = g20.mojo_test("tests/test_report_stats.mojo", "REPORT STATS TESTS PASSED", "test_report_stats")
    if err:
        problems.append(err)
    return not problems, "; ".join(problems) or (
        f"Median ({every['median']}) and Distinct (amounts {every['amounts']:,}, regions {every['regions']}) tiles equal pyarrow's, "
        "in memory and streamed, through the filter (West), saved and reopened; a Median of text is refused; identical on GTK and the web")


def m4():
    """Nothing regressed: goal 21's milestones (goal 20's and every earlier goal's inside them); the plans."""
    problems = []
    for name, fn in [("21-M1", g21.m1), ("21-M2", g21.m2), ("21-M3", g21.m3), ("21-M4", g21.m4)]:
        ok, msg = fn()
        if not ok:
            problems.append(f"{name}: {msg}")
    plan = (ROOT / "docs/plans/needs-mxframe.md").read_text()
    for needle in ("7cbcc04", "editable", "count_distinct"):
        if needle not in plan:
            problems.append(f"docs/plans/needs-mxframe.md doesn't mention {needle!r}")
    return not problems, "; ".join(problems) or "goal 21's M1–M4 (goals 3–20 and F-138 inside them) pass; needs-mxframe.md is current"


def main():
    import shutil
    import headless
    headless.ensure()
    OUT.mkdir(parents=True, exist_ok=True)
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
