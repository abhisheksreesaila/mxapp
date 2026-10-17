"""Milestone checker for goal 14 (archived: docs/goals/14-omxplorer.md: omxplorer from scratch; goal 13's checks run as M6, earlier goals' inside them).
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

ROOT = next(p for p in Path(__file__).resolve().parents if (p / "pixi.toml").exists())  # (archived in docs/goals/)
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
    """The first label that starts with `start` (to read a value); use has() to assert an exact one."""
    return next((l for l in labels(out) if l.startswith(start)), None)


def has(out, text):
    return text in labels(out)


def both(steps, name, extra=None, web=True, gtk=True, split=False):
    """Runs the steps on GTK and in Chromium. split: each host gets its own documents folder (env_for(name + '-gtk'/-web))."""
    og, ow = None, None
    if gtk:
        e = env_for(name + ("-gtk" if split else ""))
        e.update(extra or {})
        exe = BUILD / "omxplorer" / "linux" / "omxplorer"
        r = run([str(exe)], env=dict(e, MOJOUI_TEST=steps, MOJOUI_SHOT=str(BUILD / "omxplorer" / f"{name}-gtk.png")), timeout=900)
        og = r.stdout + r.stderr
        if r.returncode != 0 or "CRITICAL" in og or "TEST: " in og:
            return None, f"GTK run failed (exit {r.returncode}): {og[-400:]}"
    if not web:
        return og, None
    e = env_for(name + ("-web" if split else ""))
    e.update(extra or {})
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
    return (og if gtk else ow), ow


def oracle(path):
    """An independent pass over the CSV (Python's csv module): rows; sums of revenue, qty, the margin and the loss
    (cost − revenue); the first row's revenue and customer."""
    rows, revenue, qty, margin, first = 0, 0, 0, 0, None
    with open(path, newline="") as f:
        for rec in csv.DictReader(f):
            rows += 1
            cents = round(float(rec["revenue"]) * 100)
            revenue += cents
            qty += int(rec["qty"])
            margin += cents - round(float(rec["cost"]) * 100) - round(float(rec["freight"]) * 100)
            if first is None:
                first = (cents, rec["customer"])
    return {"rows": rows, "revenue": revenue, "qty": qty, "margin": margin, "first": first}


def money(cents, symbol="", places=2, parens=False):
    """cents as the app shows them: rounded half away from zero to `places`, thousands separators."""
    neg = cents < 0
    a = abs(cents)
    if places < 2:
        div = 10 ** (2 - places)
        a = (a + div // 2) // div
        whole, frac = divmod(a, 10 ** places)
    else:
        whole, frac = divmod(a, 100)
    text = f"{symbol}{whole:,}" + (f".{frac:0{places}d}" if places > 0 else "")
    if neg:
        return f"({text})" if parens else f"−{text}"
    return text


def average(total, count, places=2):
    """total / count rounded half away from zero, at `places` decimals, with separators (the status bar)."""
    scaled = abs(total) * 10 ** places
    q, r = divmod(scaled, count)
    if 2 * r >= count:
        q += 1
    whole, frac = divmod(q, 10 ** places)
    return ("−" if total < 0 else "") + f"{whole:,}" + (f".{frac:0{places}d}" if places else "")


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
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    for src, name, marker, args in (("tests/test_omx_components.mojo", "test_omx_components", "OMX COMPONENT TESTS PASSED", []),
                                    ("tests/test_csvio.mojo", "test_csvio", "CSVIO TESTS PASSED", [str(CSV_1M)]),
                                    ("tests/test_omx_files.mojo", "test_omx_files", "OMX FILE TESTS PASSED", [str(BUILD / "omx-files")])):
        b = run(["pixi", "run", "mojo", "build", "-I", ".", src, "-o", str(BUILD / name)], timeout=900)
        t = run(["pixi", "run", str(BUILD / name)] + args, timeout=600) if b.returncode == 0 else b
        if marker not in t.stdout:
            problems.append(f"{name}: {(t.stdout + t.stderr)[-300:]}")
    r = run(["pixi", "run", "python", "scripts/components.py", "--check"], timeout=120)
    if r.returncode != 0:
        problems.append("docs/components.md is stale")
    doc = (ROOT / "docs/components.md").read_text()
    want = {"Toolbar button (icon over label)": ["✅", "✅"], "File picker": ["🔨", "✅"],  # (GTK's dialog isn't driven by a check)
            "`Inspector`": ["✅", "✅"], "`Toolbar · FormulaBar · StatusBar`": ["✅", "✅"], "`Column number formats`": ["✅", "✅"]}
    for name, cells in want.items():
        row = next((l for l in doc.splitlines() if l.startswith(f"| {name}")), "")
        states = [c.strip() for c in row.split("|") if c.strip() in ("✅", "🔨", "❌")]
        if states[:2] != cells:
            problems.append(f"the matrix shows {name} as {states[:2]} on Linux and web (want {cells})")
    return not problems, "; ".join(problems) or "TOOL buttons, FilePicker, Inspector/Section/Row/Stepper, Toolbar/FormulaBar/StatusBar, column formats and the CSV reader in mojoui, with tests (formats, parser, CSV against Python's csv); the matrix: ✅ on Linux and web, GTK's file dialog 🔨"


def compact(cents):
    x = abs(cents) / 100.0
    for unit, size in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if x >= size:
            return f"{int(x / size * 10 + 0.5) / 10:.1f}{unit}"
    return f"{int(x + 0.5)}"


def m2():
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    problems = []
    o = oracle(CSV_1M)
    rows = o["rows"]
    imp = both(f"pick:Choose a CSV file={CSV_1M}", "import")
    sheet = both(f"pick:Choose a CSV file={CSV_1M};tap:Create table", "import-sheet")
    qty = both(f"pick:Choose a CSV file={CSV_1M};tap:Create table;key:0=ArrowLeft", "import-qty")
    start = both("", "start")
    for r in (imp, sheet, qty, start):
        if r[0] is None:
            return False, r[1]
    for host, k in (("GTK", 0), ("web", 1)):
        if not has(start[k], "omxplorer") or not has(start[k], "Open a CSV file"):
            problems.append(f"{host}: no Start screen")
        if not has(imp[k], "Import orders_1m.csv") or label(imp[k], f"{rows:,} rows · 12 columns · read in ") is None:
            problems.append(f"{host}: the Import step doesn't show the file")
        kinds = [l for l in labels(imp[k]) if l in ("Integer", "Decimal", "Date", "Text")]
        if kinds[:12] != ["Integer", "Date", "Text", "Text", "Text", "Integer", "Decimal", "Decimal", "Decimal", "Text", "Integer", "Integer"]:
            problems.append(f"{host}: inferred types {kinds[:12]}")
        if not has(sheet[k], f"Rows {rows:,}") or not has(sheet[k], "Columns 12"):
            problems.append(f"{host}: the table isn't {rows:,} rows × 12 columns")
        if not has(sheet[k], "Sum " + money(o["revenue"])) or not has(sheet[k], "Average " + average(o["revenue"], rows * 100)):
            problems.append(f"{host}: revenue's sum/average aren't the file's ({label(sheet[k], 'Sum')}, {label(sheet[k], 'Average')})")
        if not has(qty[k], f"Sum {o['qty']:,}") or not has(qty[k], "Average " + average(o["qty"], rows)):
            problems.append(f"{host}: qty's sum/average aren't the file's ({label(qty[k], 'Sum')}, {label(qty[k], 'Average')} vs {o['qty']:,}, {average(o['qty'], rows)})")
    for name, r in (("start", start), ("import", imp), ("sheet", sheet), ("qty", qty)):
        if shown(r[0]) != shown(r[1]):
            problems.append(f"{name}: GTK and web differ: {sorted(set(shown(r[0])) ^ set(shown(r[1])))[:4]}")
    return not problems, "; ".join(problems) or f"Start → choose orders_1m.csv → the Import step ({rows:,} rows, 12 columns, types inferred) → a table whose revenue ({money(o['revenue'])}) and qty ({o['qty']:,}) sums and averages equal an independent pass over the file; identical on GTK and web"


def m3():
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    problems = []
    o = oracle(CSV_1M)
    rows = o["rows"]
    loss = -o["margin"] - 0  # (cost + freight − revenue, as the loss formula below reads it)
    pick = f"pick:Choose a CSV file={CSV_1M};tap:Create table"
    fmt = both(pick + ";select:0=Currency;tap:−;segment:1=(1,234)", "format")
    cpt = both(pick + ";select:0=Compact (1.2M)", "compact")
    pct = both(pick + ";select:0=Percent", "percent")
    plain = both(pick + ";select:0=Currency;toggle:", "thousands-off")
    neg = both(pick + f";tap:Formula;enter:{FX}=loss = cost + freight - revenue;select:0=Currency;segment:1=(1,234)", "negatives")
    ops = both(pick + f";tap:Formula;enter:{FX}={MARGIN}", "formula")
    sort = both(pick + f";tap:Formula;enter:{FX}={MARGIN};tap:Sort", "sort")
    add = both(pick + ";tap:Add row", "add-row")
    for r in (fmt, cpt, pct, plain, neg, ops, sort, add):
        if r[0] is None:
            return False, r[1]
    first = o["first"][0]
    for host, k in (("GTK", 0), ("web", 1)):
        if not has(fmt[k], "Sum " + money(o["revenue"], "$", 1)):
            problems.append(f"{host}: Currency with 1 decimal didn't reach the total ({label(fmt[k], 'Sum')} vs {money(o['revenue'], '$', 1)})")
        if not has(fmt[k], "Selection revenue · row 1 · " + money(first, "$", 1)):
            problems.append(f"{host}: the cell doesn't show the format ({label(fmt[k], 'Selection')})")
        if "DROPDOWN: Currency" not in fmt[k] or "SEGMENTED: (1,234)" not in fmt[k]:
            problems.append(f"{host}: the inspector doesn't show the format it applied")
        if not has(cpt[k], "Sum " + compact(o["revenue"])):
            problems.append(f"{host}: Compact didn't reach the total ({label(cpt[k], 'Sum')} vs {compact(o['revenue'])})")
        if not has(pct[k], f"Sum {o['revenue']:,}.0%"):  # (revenue in dollars × 100 is its cents)
            problems.append(f"{host}: Percent didn't reach the total ({label(pct[k], 'Sum')} vs {o['revenue']:,}.0%)")
        if not has(plain[k], "Sum $" + money(o["revenue"]).replace(",", "")) or "TOGGLE: =off" not in plain[k]:
            problems.append(f"{host}: Thousands off didn't drop the separators ({label(plain[k], 'Sum')})")
        if not has(neg[k], "Sum " + money(loss, "$", 2, parens=True)):
            problems.append(f"{host}: a negative total isn't in parentheses ({label(neg[k], 'Sum')} vs {money(loss, '$', 2, parens=True)})")
        if not has(ops[k], "Sum " + money(o["margin"])) or label(ops[k], "New column margin") is None:
            problems.append(f"{host}: the formula column's sum isn't the file's {money(o['margin'])} ({label(ops[k], 'Sum')})")
        if not has(sort[k], "Sorted by margin (largest first)") or not has(sort[k], "sorted by margin ↓"):
            problems.append(f"{host}: Sort didn't sort by the new column")
        if not has(add[k], f"Rows {rows + 1:,}"):
            problems.append(f"{host}: Add row didn't add a row ({label(add[k], 'Rows')})")
        for tool in ("Save", "Undo", "Add row", "Formula", "Sort", "Format", "Open"):
            if f"BUTTON: {tool}" not in add[k]:
                problems.append(f"{host}: no {tool} in the toolbar")
    for name, r in (("format", fmt), ("compact", cpt), ("percent", pct), ("thousands-off", plain), ("negatives", neg), ("formula", ops), ("sort", sort), ("add", add)):
        if shown(r[0]) != shown(r[1]):
            problems.append(f"{name}: GTK and web differ: {sorted(set(shown(r[0])) ^ set(shown(r[1])))[:4]}")
    return not problems, "; ".join(problems) or f"the sheet on both hosts: Currency, decimals, Thousands off, Percent, parentheses (a negative total), Compact reach the cells and the totals; a formula column sums to the file's {money(o['margin'])}; Sort; Add row; identical on GTK and web"


EDITS = (f"pick:Choose a CSV file={CSV_1M};tap:Create table;select:0=Currency;typekeys:0=99999⏎;key:0=ArrowUp;"
         "key:0=ArrowLeft;key:0=ArrowLeft;key:0=ArrowLeft;key:0=ArrowLeft;typekeys:0=Zed Co⏎;tap:Add row;"
         f"tap:Formula;enter:{FX}={MARGIN};tap:Save")


def m4():
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    problems = []
    o = oracle(CSV_1M)
    rows = o["rows"]
    saved = both(EDITS, "save", split=True)  # GTK and web each edit and save their own copy
    if saved[0] is None:
        return False, saved[1]
    sizes = []
    for host in ("gtk", "web"):
        doc = Path(env_for(f"save-{host}")["OMX_DOCUMENTS"]) / "orders_1m.omx"
        if not doc.exists():
            problems.append(f"{host}: Save didn't write {doc}")
            continue
        sizes.append(doc.stat().st_size)
        revenue_after = o["revenue"] - o["first"][0] + 9_999_900
        top = both("", f"open-{host}", extra={"OMX_OPEN": str(doc)})
        cust = both("key:0=ArrowLeft;key:0=ArrowLeft;key:0=ArrowLeft;key:0=ArrowLeft;segment:0=Table", f"open-{host}-cust", extra={"OMX_OPEN": str(doc)})
        for r in (top, cust):
            if r[0] is None:
                return False, r[1]
        for viewer, k in (("GTK", 0), ("web", 1)):
            where = f"{host}'s file on {viewer}"
            if not has(top[k], f"Opened orders_1m.omx · {rows + 1:,} rows") or not has(top[k], f"Rows {rows + 1:,}"):
                problems.append(f"{where}: the added row didn't come back ({label(top[k], 'Rows')})")
            if not has(top[k], "Sum " + money(revenue_after, "$")) or not has(top[k], "Selection revenue · row 1 · $99,999.00"):
                problems.append(f"{where}: the edited revenue or its format didn't come back ({label(top[k], 'Selection')}, {label(top[k], 'Sum')})")
            if not has(cust[k], "Selection customer · row 1 · Zed Co"):
                problems.append(f"{where}: the new customer name didn't come back ({label(cust[k], 'Selection')})")
            if not has(cust[k], "margin") or label(cust[k], "Decimal · Currency") is None:
                problems.append(f"{where}: the formula column or the Currency format didn't come back")
        if shown(top[0]) != shown(top[1]) or shown(cust[0]) != shown(cust[1]):
            problems.append(f"{host}'s file: GTK and web differ: {sorted(set(shown(top[0])) ^ set(shown(top[1])))[:4]}")
    bad = BUILD / "omx-files" / "nulls.omx"  # (written by tests/test_omx_files.mojo in M1)
    kept = both(f"tap:Open the sample;pick:Open={bad}", "open-bad")
    if kept[0] is None:
        return False, kept[1]
    for viewer, k in (("GTK", 0), ("web", 1)):
        if label(kept[k], "can't open") is None or not has(kept[k], f"Rows {rows:,}"):
            problems.append(f"{viewer}: a bad file opened from a loaded sheet didn't leave the sheet as it was ({label(kept[k], 'Rows')}, {label(kept[k], 'can')})")
    return not problems, "; ".join(problems) or f"GTK and the web each edit (a number, a new name), add a row and a formula column, and Save one .omx file ({max(sizes) // 1_000_000} MB); both files reopen on both hosts with the edits, the row, the formula and the format; a bad file leaves the open sheet intact"


def m5():
    path = ROOT / "docs" / "scale.md"
    if not path.exists():
        return False, "docs/scale.md (the measurements at 1M, 10M, 50M, 100M rows) isn't written yet"
    text = path.read_text()
    problems = []
    for size in ("1M", "10M", "50M", "100M"):
        row = re.search(rf"^\| {size} \|(.*)$", text, re.M)
        if not row or row.group(1).count("|") != 7:
            problems.append(f"docs/scale.md: no full {size} row")
    b = run(["pixi", "run", "mojo", "build", "-I", ".", "tools/scale.mojo", "-o", str(BUILD / "scale")], timeout=900)
    if b.returncode != 0:
        return False, f"tools/scale.mojo build: {(b.stdout + b.stderr)[-300:]}"
    r = run(["pixi", "run", str(BUILD / "scale"), str(CSV_1M)], timeout=900)
    m = re.search(r"^\| 1M \| ([\d.]+) s \| ([\d.]+) s \| ([\d.]+) ms \|", r.stdout, re.M)
    if not m:
        return False, f"the 1M measurement didn't run: {(r.stdout + r.stderr)[-300:]}"
    imp, srt, fmt = float(m.group(1)), float(m.group(2)), float(m.group(3))
    if imp >= 5 or srt >= 1 or fmt >= 50:
        problems.append(f"1M misses its budget now: import {imp} s, sort {srt} s, format {fmt} ms")
    return not problems, "; ".join(problems) or f"1M measured now: import {imp} s, sort {srt} s, format {fmt} ms (budgets 5 s, 1 s, 50 ms); 10M, 50M and 100M recorded in docs/scale.md"


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
