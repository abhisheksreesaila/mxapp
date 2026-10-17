"""Milestone checker for GOAL.md (goal 15: omxplorer charts, pivots and a Report; goal 14's checks run as M6, earlier
goals' inside them). Rebuilds from scratch, prints PASS/FAIL per milestone. GTK runs headless; the web in Chromium.

Run: scripts/check   (a subset without rebuilding: scripts/check M2 M3; earlier goals: through docs/goals/NN-check.py)
"""

import csv
import importlib.util
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

_spec = importlib.util.spec_from_file_location("goal14", ROOT / "docs/goals/14-check.py")
g14 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g14)
run, BUILD, EXAMPLES = g14.run, g14.BUILD, g14.EXAMPLES
both, env_for, has, label, labels, _shown, money, average, ensure_csv, CSV_1M = (
    g14.both, g14.env_for, g14.has, g14.label, g14.labels, g14.shown, g14.money, g14.average, g14.ensure_csv, g14.CSV_1M)

OPEN = f"pick:Choose a CSV file={CSV_1M};tap:Create table;select:0=Currency"
TIMES = re.compile(r"^LABEL: [\d.]+ ms$")  # (an object's own timing: a measurement, not content)


def shown(out):
    return [l for l in g14.shown(out) if not TIMES.match(l)]


def oracle(path):
    """Independent sums over the CSV (Python's csv module): revenue (cents) by carrier, by region, by carrier ×
    region, and for West only: sum, rows, by carrier."""
    by_carrier, by_region, pivot, west_by_carrier = {}, {}, {}, {}
    west_sum = west_rows = 0
    with open(path, newline="") as f:
        for rec in csv.DictReader(f):
            cents = round(float(rec["revenue"]) * 100)
            c, r = rec["carrier"], rec["region"]
            by_carrier[c] = by_carrier.get(c, 0) + cents
            by_region[r] = by_region.get(r, 0) + cents
            pivot[(c, r)] = pivot.get((c, r), 0) + cents
            if r == "West":
                west_sum += cents
                west_rows += 1
                west_by_carrier[c] = west_by_carrier.get(c, 0) + cents
    return {"carrier": by_carrier, "region": by_region, "pivot": pivot, "west_sum": west_sum, "west_rows": west_rows,
            "west_carrier": west_by_carrier}


def readout_ok(out, totals):
    """The chart's readout ("Carrier A · $70,217,274.00") names a group and shows that group's total."""
    for l in labels(out):
        m = re.match(r"^(.+) · (\$[\d,]+\.\d\d)$", l)
        if m and m.group(1) in totals:
            return m.group(2) == money(totals[m.group(1)], "$"), l
    return False, None


def m1():
    problems = []
    for f, needle in (("mojoui/sheetpage.mojo", "def object_card("), ("mojoui/sheetpage.mojo", "def free_spot("),
                      ("mojoui/reportpage.mojo", "def ReportPage("), ("mojoui/reportpage.mojo", "struct ReportFilter"),
                      ("mojoui/omxfile.mojo", "def open_document(")):
        if needle not in (ROOT / f).read_text():
            problems.append(f"{f} lacks {needle}")
    b = run(["pixi", "run", "mojo", "build", "-I", ".", "tests/test_sheetpage.mojo", "-o", str(BUILD / "test_sheetpage")], timeout=900)
    t = run(["pixi", "run", str(BUILD / "test_sheetpage")], timeout=600) if b.returncode == 0 else b
    if "SHEETPAGE TESTS PASSED" not in t.stdout:
        problems.append(f"test_sheetpage: {(t.stdout + t.stderr)[-300:]}")
    r = run(["pixi", "run", "python", "scripts/components.py", "--check"], timeout=120)
    if r.returncode != 0:
        problems.append("docs/components.md is stale")
    doc = (ROOT / "docs/components.md").read_text()
    for name in ("`Sheet objects (charts, pivots)`", "`Report page (KPI and chart tiles, filters)`"):
        row = next((l for l in doc.splitlines() if l.startswith(f"| {name}")), "")
        states = [c.strip() for c in row.split("|") if c.strip() in ("✅", "🔨", "❌")]
        if states[:2] != ["✅", "✅"]:
            problems.append(f"the matrix shows {name} as {states[:2]} on Linux and web")
    return not problems, "; ".join(problems) or "sheet objects (charts, pivots: GPU sums = a CPU pass, with an edit) and the report page (tiles through a filter) in mojoui with a test; ✅ on Linux and web in the matrix"


def m2():
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    o = oracle(CSV_1M)
    problems = []
    bars = both(OPEN + ";tap:Chart;tapat:1=500,200", "chart")
    regions = both(OPEN + ";tap:Chart;select:1=region;tapat:1=500,200", "chart-region")
    line = both(OPEN + ";tap:Chart;segment:1=Line", "chart-line")
    for r in (bars, regions, line):
        if r[0] is None:
            return False, r[1]
    for host, k in (("GTK", 0), ("web", 1)):
        if "BOARD: chart0 at 0,416 520x340" not in bars[k]:
            problems.append(f"{host}: the chart isn't on the sheet below the table")
        good, l = readout_ok(bars[k], o["carrier"])
        if not good:
            problems.append(f"{host}: picking a bar of revenue by carrier read {l} (want the CSV's total for it)")
        if not has(regions[k], "revenue by region"):
            problems.append(f"{host}: the inspector didn't regroup the chart by region")
        good, l = readout_ok(regions[k], o["region"])
        if not good:
            problems.append(f"{host}: picking a bar of revenue by region read {l}")
        if "SEGMENTED: Line" not in line[k]:
            problems.append(f"{host}: the chart didn't switch to a line")
    for name, r in (("bars", bars), ("regions", regions), ("line", line)):
        if shown(r[0]) != shown(r[1]):
            problems.append(f"{name}: GTK and web differ: {sorted(set(shown(r[0])) ^ set(shown(r[1])))[:4]}")
    return not problems, "; ".join(problems) or "Chart puts revenue by carrier on the sheet; the inspector regroups it by region and makes it a line; a picked bar reads its group's total in Currency, equal to the CSV's; identical on GTK and web"


def m3():
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    o = oracle(CSV_1M)
    problems = []
    piv = both(OPEN + ";tap:Pivot", "pivot")
    if piv[0] is None:
        return False, piv[1]
    carriers = sorted(o["carrier"])
    regions = sorted(o["region"])
    for host, k in (("GTK", 0), ("web", 1)):
        if "BOARD: pivot0 at 0,416 548x340" not in piv[k] and "BOARD: pivot0 at 0,416" not in piv[k]:
            problems.append(f"{host}: the pivot isn't on the sheet")
        got = labels(piv[k])
        for c in carriers:
            for r in regions:
                if money(o["pivot"][(c, r)], "$") not in got:
                    problems.append(f"{host}: no cell {c} × {r} = {money(o['pivot'][(c, r)], '$')}")
        for c in carriers:
            if money(o["carrier"][c], "$") not in got:
                problems.append(f"{host}: no row total for {c}")
        for r in regions:
            if money(o["region"][r], "$") not in got:
                problems.append(f"{host}: no column total for {r}")
        if money(sum(o["carrier"].values()), "$") not in got:
            problems.append(f"{host}: no grand total")
    if shown(piv[0]) != shown(piv[1]):
        problems.append(f"GTK and web differ: {sorted(set(shown(piv[0])) ^ set(shown(piv[1])))[:4]}")
    return not problems, "; ".join(problems[:6]) or f"Pivot puts revenue by carrier × region on the sheet with row, column and grand totals, all {len(carriers) * len(regions)} cells equal to the CSV's and in Currency; identical on GTK and web"


REPORT = (OPEN + ";tab:0=Report;tap:Sum tile;tap:Average tile;tap:Count tile;tap:Chart tile;select:1=region;select:2=West")


def m4():
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    o = oracle(CSV_1M)
    problems = []
    every = both(OPEN + ";tab:0=Report;tap:Sum tile;tap:Count tile", "report-all")
    west = both(REPORT + ";tapat:3=500,200", "report-west")
    for r in (every, west):
        if r[0] is None:
            return False, r[1]
    total = sum(o["region"].values())
    rows = sum(1 for _ in open(CSV_1M)) - 1
    for host, k in (("GTK", 0), ("web", 1)):
        if not has(every[k], money(total, "$")) or not has(every[k], f"{rows:,}"):
            problems.append(f"{host}: the unfiltered tiles aren't the CSV's ({money(total, '$')}, {rows:,})")
        if not has(west[k], money(o["west_sum"], "$")):
            problems.append(f"{host}: Sum of revenue for West isn't {money(o['west_sum'], '$')}")
        if not has(west[k], f"{o['west_rows']:,}"):
            problems.append(f"{host}: Rows for West isn't {o['west_rows']:,}")
        if not has(west[k], "$" + average(o["west_sum"], o["west_rows"] * 100)):
            problems.append(f"{host}: Average of revenue for West isn't ${average(o['west_sum'], o['west_rows'] * 100)}")
        if labels(west[k]).count("region = West") < 3 or not has(west[k], "orders_1m · region = West"):
            problems.append(f"{host}: the tiles don't say they're filtered to West")
        good, l = readout_ok(west[k], o["west_carrier"])
        if not good:
            problems.append(f"{host}: the chart tile's picked bar read {l} (want West's total for that carrier)")
    for name, r in (("all", every), ("west", west)):
        if shown(r[0]) != shown(r[1]):
            problems.append(f"{name}: GTK and web differ: {sorted(set(shown(r[0])) ^ set(shown(r[1])))[:4]}")
    return not problems, "; ".join(problems) or f"a Report from scratch: Sum, Average, Count and a chart tile; the West filter changes every tile (sum {money(o['west_sum'], '$')}, {o['west_rows']:,} rows), all equal to the CSV's; identical on GTK and web"


def m5():
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    o = oracle(CSV_1M)
    problems = []
    saved = both(OPEN + ";tap:Chart;tap:Pivot;tab:0=Report;tap:Sum tile;tap:Chart tile;select:1=region;select:2=West;tap:Save", "objects-save", split=True)
    if saved[0] is None:
        return False, saved[1]
    for host in ("gtk", "web"):
        doc = Path(env_for(f"objects-save-{host}")["OMX_DOCUMENTS"]) / "orders_1m.omx"
        if not doc.exists():
            problems.append(f"{host}: Save didn't write {doc}")
            continue
        sheet = both("", f"objects-open-{host}", extra={"OMX_OPEN": str(doc)})
        report = both("tab:0=Report", f"objects-report-{host}", extra={"OMX_OPEN": str(doc)})
        for r in (sheet, report):
            if r[0] is None:
                return False, r[1]
        for viewer, k in (("GTK", 0), ("web", 1)):
            where = f"{host}'s file on {viewer}"
            if "BOARD: chart0 at 0,416 520x340" not in sheet[k] or "BOARD: pivot1 at 536,416" not in sheet[k]:
                problems.append(f"{where}: the chart and the pivot didn't come back where they were")
            if not has(report[k], money(o["west_sum"], "$")) or not has(report[k], "orders_1m · region = West"):
                problems.append(f"{where}: the Report's tiles or its West filter didn't come back")
    return not problems, "; ".join(problems) or "an .omx document keeps the sheet's chart and pivot (where they were) and the Report's tiles and West filter; both hosts' files reopen on both hosts"


def m6():
    problems = []
    for name in ("m1", "m2", "m3", "m4", "m5", "m6"):
        ok, msg = getattr(g14, name)()
        if not ok:
            problems.append(f"goal 14 {name.upper()}: {msg[:300]}")
    return not problems, "; ".join(problems) or "goal 14's checks (and goals 3–13's inside them) pass"


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
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5), ("M6", m6)]:
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
