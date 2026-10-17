"""Milestone checker for GOAL.md (goal 14: omxplorer from scratch; goal 13's checks run as M6, earlier goals' inside them).
Rebuilds from scratch, prints PASS/FAIL per milestone. GTK runs headless; the web runs in Chromium with a real file upload.

Run: scripts/check   (a subset without rebuilding: scripts/check M2 M3; earlier goals: through docs/goals/NN-check.py)
"""

import csv
import importlib.util
import os
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

_spec = importlib.util.spec_from_file_location("goal13", ROOT / "docs/goals/13-check.py")
g13 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g13)
run, BUILD = g13.run, g13.BUILD
EXAMPLES = g13.EXAMPLES + ["omxplorer"]

import drive  # noqa: E402

DATA = BUILD / "data"
CSV_1M = DATA / "orders_1m.csv"
SHOWN = r"^(LABEL|TONE|SEGMENTED|TABS|DROPDOWN|BUTTON|FIELD|TEXTAREA|BOARD|TOGGLE): "
TIMING = re.compile(r"read in [\d.]+ s|[\d.]+ ms on |^LABEL: Saved |^LABEL: Opened ")
FX = "A new column: its name, then its formula"
MARGIN = "margin = revenue - cost - freight"


def env_for(tag):
    """Test-only places for documents, the recent list and uploads (never the person's own)."""
    home = BUILD / "omx-test" / tag
    for d in ("docs", "config", "uploads"):
        (home / d).mkdir(parents=True, exist_ok=True)
    return {"OMX_DOCUMENTS": str(home / "docs"), "OMX_CONFIG": str(home / "config"), "OMXAPP_UPLOADS": str(home / "uploads")}


def shown(out):
    return sorted(l for l in out.splitlines() if re.match(SHOWN, l) and not TIMING.search(l))


def labels(out):
    return [l[len("LABEL: "):] for l in out.splitlines() if l.startswith("LABEL: ")]


def label(out, start):
    return next((l for l in labels(out) if l.startswith(start)), None)


def both(steps, name, extra=None, web=True):
    e = env_for(name)
    e.update(extra or {})
    exe = BUILD / "omxplorer" / "linux" / "omxplorer"
    r = run([str(exe)], env=dict(e, MOJOUI_TEST=steps, MOJOUI_SHOT=str(BUILD / "omxplorer" / f"{name}-gtk.png")), timeout=900)
    og = r.stdout + r.stderr
    if r.returncode != 0 or "CRITICAL" in og or "TEST: " in og:
        return None, f"GTK run failed (exit {r.returncode}): {og[-400:]}"
    if not web:
        return og, None
    saved = {k: os.environ.get(k) for k in e}
    os.environ.update(e)
    try:
        rw, ow = drive.web_run(BUILD / "omxplorer" / "web", steps, shot=str(BUILD / "omxplorer" / f"{name}-web.png"), viewport=(1440, 900))
    except Exception as ex:
        return None, f"web run crashed: {ex!r}"
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    if rw.returncode != 0:
        return None, f"web: {ow[-400:]}"
    return og, ow


def oracle(path):
    """An independent pass over the CSV (Python's csv module): rows, and sums of revenue, qty and the margin."""
    rows, revenue, qty, margin = 0, 0, 0, 0
    with open(path, newline="") as f:
        for rec in csv.DictReader(f):
            rows += 1
            cents = round(float(rec["revenue"]) * 100)
            revenue += cents
            qty += int(rec["qty"])
            margin += cents - round(float(rec["cost"]) * 100) - round(float(rec["freight"]) * 100)
    return rows, revenue, qty, margin


def money(cents, symbol="", places=2):
    whole = f"{abs(cents) // 100:,}"
    text = f"{symbol}{whole}" + (f".{abs(cents) % 100:02d}" if places == 2 else (f".{(abs(cents) % 100) // 10}" if places == 1 else ""))
    return text


def ensure_csv():
    if CSV_1M.exists():
        return True, ""
    b = run(["pixi", "run", "mojo", "build", "-I", ".", "tools/orders_csv.mojo", "-o", str(BUILD / "orders_csv")], timeout=900)
    if b.returncode != 0:
        return False, f"orders_csv build: {(b.stdout + b.stderr)[-300:]}"
    r = run(["pixi", "run", str(BUILD / "orders_csv"), "1000000", str(CSV_1M)], timeout=900)
    return CSV_1M.exists(), (r.stdout + r.stderr)[-300:]


def m1():
    problems = []
    for f, needle in (("mojoui/view.mojo", "comptime TOOL = 5"), ("mojoui/view.mojo", "def FilePicker("), ("mojoui/inspector.mojo", "def Inspector("),
                      ("mojoui/inspector.mojo", "def Stepper("), ("mojoui/sheetchrome.mojo", "def FormulaBar("), ("mojoui/numformat.mojo", "struct ColumnFormat"),
                      ("mojoui/csvio.mojo", "SHIM"), ("mojoui/hosts/gtk.mojo", "gtk_file_dialog_open"), ("mojoui/hosts/web.py", '@app.post("/upload/{sid}")')):
        if needle not in (ROOT / f).read_text():
            problems.append(f"{f} lacks {needle}")
    for src, name, marker in (("tests/test_omx_components.mojo", "test_omx_components", "OMX COMPONENT TESTS PASSED"),):
        b = run(["pixi", "run", "mojo", "build", "-I", ".", src, "-o", str(BUILD / name)], timeout=900)
        t = run(["pixi", "run", str(BUILD / name)], timeout=300) if b.returncode == 0 else b
        if marker not in t.stdout:
            problems.append(f"{name}: {(t.stdout + t.stderr)[-300:]}")
    r = run(["pixi", "run", "python", "scripts/components.py", "--check"], timeout=120)
    if r.returncode != 0:
        problems.append("docs/components.md is stale")
    doc = (ROOT / "docs/components.md").read_text()
    for name in ("Toolbar button (icon over label)", "File picker", "`Inspector`", "`Toolbar · FormulaBar · StatusBar`", "`Column number formats`"):
        row = next((l for l in doc.splitlines() if l.startswith(f"| {name}")), "")
        states = [c.strip() for c in row.split("|") if c.strip() in ("✅", "🔨", "❌")]
        if states[:2] != ["✅", "✅"]:  # (the first two platform columns: Linux, then Web)
            problems.append(f"the matrix doesn't show {name} ✅ on Linux and web")
    return not problems, "; ".join(problems) or "TOOL buttons, FilePicker, Inspector/Section/Row/Stepper, Toolbar/FormulaBar/StatusBar, column formats and the CSV reader in mojoui with tests; ✅ on Linux and web in the matrix"


def m2():
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    problems = []
    rows, revenue, qty, _ = oracle(CSV_1M)
    imp = both(f"pick:Choose a CSV file={CSV_1M}", "import")
    sheet = both(f"pick:Choose a CSV file={CSV_1M};tap:Create table", "import-sheet")
    start = both("", "start")
    for o in (imp, sheet, start):
        if o[0] is None:
            return False, o[1]
    for host, k in (("GTK", 0), ("web", 1)):
        if "omxplorer" not in labels(start[k]) or label(start[k], "Drop a CSV file") is None:
            problems.append(f"{host}: no Start screen")
        if label(imp[k], "Import orders_1m.csv") is None or label(imp[k], f"{rows:,} rows · 12 columns") is None:
            problems.append(f"{host}: the Import step doesn't show the file ({label(imp[k], 'Import')}, {label(imp[k], '1,0')})")
        kinds = [l for l in labels(imp[k]) if l in ("Integer", "Decimal", "Date", "Text")]
        if kinds[:12] != ["Integer", "Date", "Text", "Text", "Text", "Integer", "Decimal", "Decimal", "Decimal", "Text", "Integer", "Integer"]:
            problems.append(f"{host}: inferred types {kinds[:12]}")
        if label(sheet[k], f"Rows {rows:,}") is None:
            problems.append(f"{host}: the table doesn't have {rows:,} rows")
        if label(sheet[k], "Sum " + money(revenue)) is None:
            problems.append(f"{host}: revenue's sum isn't the file's {money(revenue)} ({label(sheet[k], 'Sum')})")
    for name, o in (("start", start), ("import", imp), ("sheet", sheet)):
        if shown(o[0]) != shown(o[1]):
            problems.append(f"{name}: GTK and web differ: {sorted(set(shown(o[0])) ^ set(shown(o[1])))[:4]}")
    _ = qty
    return not problems, "; ".join(problems) or f"Start → choose orders_1m.csv → the Import step ({rows:,} rows, 12 columns, types inferred) → a table whose revenue sums to the file's {money(revenue)}; identical on GTK and web"


def m3():
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    problems = []
    rows, revenue, _, margin = oracle(CSV_1M)
    pick = f"pick:Choose a CSV file={CSV_1M};tap:Create table"
    fmt = both(pick + ";select:0=Currency;tap:−;segment:1=(1,234)", "format")
    pct = both(pick + ";select:0=Compact (1.2M)", "compact")
    ops = both(pick + f";tap:Formula;enter:{FX}={MARGIN}", "formula")
    sort = both(pick + f";tap:Formula;enter:{FX}={MARGIN};tap:Sort", "sort")
    add = both(pick + ";tap:Add row", "add-row")
    for o in (fmt, pct, ops, sort, add):
        if o[0] is None:
            return False, o[1]
    for host, k in (("GTK", 0), ("web", 1)):
        want = "Sum " + money(revenue, "$", 1)
        if label(fmt[k], want) is None:
            problems.append(f"{host}: Currency, 1 decimal didn't reach the total ({label(fmt[k], 'Sum')} vs {want})")
        if "DROPDOWN: Currency" not in fmt[k] or "SEGMENTED: (1,234)" not in fmt[k]:
            problems.append(f"{host}: the inspector doesn't show the format it applied")
        if label(pct[k], "Sum 114.0M") is None and label(pct[k], f"Sum {revenue / 1e8:.1f}M") is None:
            problems.append(f"{host}: Compact didn't reach the total ({label(pct[k], 'Sum')})")
        if label(ops[k], "Sum " + money(margin)) is None or label(ops[k], "New column margin") is None:
            problems.append(f"{host}: the formula column's sum isn't the file's {money(margin)} ({label(ops[k], 'Sum')})")
        if label(sort[k], "Sorted by margin (largest first)") is None:
            problems.append(f"{host}: Sort didn't sort by the new column")
        if label(add[k], f"Rows {rows + 1:,}") is None:
            problems.append(f"{host}: Add row didn't add a row ({label(add[k], 'Rows')})")
        for tool in ("Save", "Undo", "Add row", "Formula", "Sort", "Format", "Open"):
            if f"BUTTON: {tool}" not in add[k]:
                problems.append(f"{host}: no {tool} in the toolbar")
    for name, o in (("format", fmt), ("compact", pct), ("formula", ops), ("sort", sort), ("add", add)):
        if shown(o[0]) != shown(o[1]):
            problems.append(f"{name}: GTK and web differ: {sorted(set(shown(o[0])) ^ set(shown(o[1])))[:4]}")
    return not problems, "; ".join(problems) or f"the sheet on both hosts: Currency / decimals / parentheses / Compact change the column and its totals; a formula column sums to the file's {money(margin)}; Sort; Add row; identical on GTK and web"


def m4():
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    problems = []
    tag = env_for("save")
    saved = both(f"pick:Choose a CSV file={CSV_1M};tap:Create table;select:0=Currency;tap:Formula;enter:{FX}={MARGIN};tap:Save", "save", web=False)
    if saved[0] is None:
        return False, saved[1]
    doc = Path(tag["OMX_DOCUMENTS"]) / "orders_1m.omx"
    if not doc.exists():
        return False, f"Save didn't write {doc}"
    rows, revenue, _, margin = oracle(CSV_1M)
    opened = both("segment:0=Table", "open", extra={"OMX_OPEN": str(doc)})
    if opened[0] is None:
        return False, opened[1]
    for host, k in (("GTK", 0), ("web", 1)):
        out = opened[k]
        if label(out, "Opened orders_1m.omx") is None:
            problems.append(f"{host}: the document didn't open")
        if label(out, f"Rows {rows:,}") is None:
            problems.append(f"{host}: rows after opening: {label(out, 'Rows')}")
        if "LABEL: margin" not in out or label(out, "Decimal · Currency") is None:
            problems.append(f"{host}: the formula column or the format didn't come back")
        if label(out, "Sum " + money(revenue, "$")) is None:
            problems.append(f"{host}: revenue after opening: {label(out, 'Sum')} (want {money(revenue, '$')})")
    if shown(opened[0]) != shown(opened[1]):
        problems.append(f"GTK and web differ: {sorted(set(shown(opened[0])) ^ set(shown(opened[1])))[:4]}")
    _ = margin
    return not problems, "; ".join(problems) or f"Save writes orders_1m.omx ({doc.stat().st_size // 1_000_000} MB, one Parquet file); opening it brings back the rows, the formula column and the Currency format on both hosts"


def m5():
    path = ROOT / "docs" / "scale.md"
    if not path.exists():
        return False, "docs/scale.md (the measurements at 1M, 10M, 50M, 100M rows) isn't written yet"
    text = path.read_text()
    problems = []
    for size in ("1M", "10M", "50M", "100M"):
        if not re.search(rf"^\| {size} \|", text, re.M):
            problems.append(f"no {size} row")
    m = re.search(r"^\| 1M \| ([\d.]+) s \| ([\d.]+) s \| ([\d.]+) ms \|", text, re.M)
    if not m:
        problems.append("the 1M row isn't 'import s | sort s | format ms'")
    elif float(m.group(1)) >= 5 or float(m.group(2)) >= 1 or float(m.group(3)) >= 50:
        problems.append(f"1M misses its budget: import {m.group(1)} s, sort {m.group(2)} s, format {m.group(3)} ms")
    return not problems, "; ".join(problems) or "measured at 1M, 10M, 50M and 100M rows (docs/scale.md); 1M within budget"


def m6():
    problems = []
    for name in ("m1", "m2", "m3", "m4"):
        ok, msg = getattr(g13, name)()
        if not ok:
            problems.append(f"goal 13 {name.upper()}: {msg[:300]}")
    return not problems, "; ".join(problems) or "goal 13's checks (and goals 3–12's inside them) pass"


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
