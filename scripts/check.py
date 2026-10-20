"""Milestone checker for GOAL.md (goal 29: charts that ask MX frame 321870f more; goal 28's checks run as M5, every
earlier goal's inside them). Rebuilds from scratch, prints PASS/FAIL per milestone.

Run: scripts/check   (a subset without rebuilding: scripts/check M1 M2; earlier goals: through docs/goals/NN-check.py)
"""

import importlib.util
import math
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


g28 = load("goal28", "docs/goals/28-check.py")
g27, g26, g25 = g28.g27, g28.g26, g28.g25
g20 = g25.g20
run, BUILD = g20.run, g20.BUILD
OUT = BUILD / "g29"
labels = g25.labels
APPS = ["hello", "gallery", "todo", "gpu", "kitchen", "expenses", "layout", "lens", "analytics", "workbook", "mxstudio", "omxplorer", "kit", "themes"]


def m0():
    """The new engine everywhere: vendored from 321870f; every example built for every platform it lists; FLOAT columns."""
    problems = []
    stamp = (ROOT / "vendor/MXFRAME_COMMIT").read_text()
    if "321870f" not in stamp.split("\n")[0]:
        problems.append(f"vendor/MXFRAME_COMMIT says {stamp.split(chr(10))[0][:60]}")
    for ex in APPS:
        plats = (ROOT / "examples" / ex / "platforms").read_text().split() if (ROOT / "examples" / ex / "platforms").exists() else ["linux", "web", "mac", "ios"]
        for plat in plats:
            if plat in ("linux", "web", "mac", "ios") and not (BUILD / ex / plat).exists():
                problems.append(f"{ex} has no {plat} build")
    err = g20.mojo_test("tests/test_float_column.mojo", "PASSED", "test_float_column", "tests")
    if err:
        problems.append(err)
    return not problems, "; ".join(problems[:6]) or "vendor/ is MX frame 321870f; every example built for Linux, the web, Mac and iPhone (as its platforms list); FLOAT columns show their numbers"


STATS = [("median", "table", 0, None), ("p90", "table", 0, None), ("median", "largest", 3, None), ("median", "table", 0, True),
         ("p90", "az", 0, False), ("p90", "smallest", 2, None)]


def stat(vals, how):
    v = sorted(vals)
    if not v:
        return None
    if how == "median":
        n = len(v)
        return v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) / 2
    return v[max(math.ceil(0.9 * len(v)) - 1, 0)]  # (DuckDB's quantile_disc)


def m1():
    """Median and p90 per group: six specs equal pyarrow's (the "(blank)" group has none yet: "—")."""
    import pyarrow.parquet as pq
    problems = []
    b = run(["scripts/mxbuild.sh", "tests/chartstats_dump.mojo", "-o", str(BUILD / "chartstats_dump")], timeout=1800)
    if b.returncode != 0:
        return False, "chartstats_dump: " + (b.stdout + b.stderr)[-400:]
    out = run([str(BUILD / "chartstats_dump"), g25.small()], timeout=300).stdout
    rows = pq.read_table(g25.small()).to_pylist()
    blocks = re.split(r"^SPEC \d+\n", out.split("END")[0], flags=re.M)[1:]
    if len(blocks) != len(STATS):
        return False, f"{len(blocks)} charts printed: {out[-300:]}"
    for k, (block, (how, order, top, paid)) in enumerate(zip(blocks, STATS)):
        groups = {}
        for r in rows:
            if paid is not None and r["paid"] is not paid:
                continue
            if r["region"] is None:
                continue
            groups.setdefault(r["region"], []).append(float(r["amount"]) if r["amount"] is not None else None)
        want = {g: stat([v for v in vs if v is not None], how) for g, vs in groups.items()}
        got = [(l.split("\t")[0], l.split("\t")[1]) for l in block.strip().split("\n")[1:]]
        for name, text in got:
            if name == "(blank)":
                if text != "—":
                    problems.append(f"spec {k}: (blank) reads {text}")
                continue
            if abs(float(text.replace(",", "")) - want[name]) > 0.006:
                problems.append(f"spec {k} ({how}, {order}): {name} {text} vs pyarrow {want[name]:.3f}")
        named = [n for n, _ in got if n != "(blank)"]
        if order == "largest" and named != sorted(named, key=lambda n: -want[n])[:len(named)]:
            problems.append(f"spec {k}: not largest first: {named}")
        if order == "smallest" and named != sorted(want, key=lambda n: want[n])[:top]:
            problems.append(f"spec {k}: not the {top} smallest: {named}")
    for phrase, sentence in (("median", "Median of amount by region"), ("p90", "p90 of amount by region")):
        o = g25.gtk(g25.SHEET + ";tap:Chart;pause:300;" + g28.ASK + phrase + ";pause:400", f"m1-{phrase}")[0]
        if not any(l.startswith(sentence) for l in labels(o)):
            problems.append(f"GTK: asking \"{phrase}\" didn't make {sentence}")
    return not problems, "; ".join(problems[:6]) or ("median and p90 per group equal pyarrow's for 6 specs (interpolated median; quantile_disc), "
                                                      "in every order and with a filter; \"median\" and \"p90\" asked on GTK")


NUMS = [("sum", ">", 5000, None, None), ("count", "<", None, 1000, None), ("mean", "between", 2000, 4000, None), ("sum", ">", 5000, None, True),
        ("median", ">=", 5000, None, None)]


def m2():
    """Numbers as filters: five charts with number conditions (and a Yes/No one) equal pyarrow's; the ask and the Rows page set them."""
    import pyarrow.parquet as pq
    problems = []
    b = run(["scripts/mxbuild.sh", "tests/chartnum_dump.mojo", "-o", str(BUILD / "chartnum_dump")], timeout=1800)
    if b.returncode != 0:
        return False, "chartnum_dump: " + (b.stdout + b.stderr)[-400:]
    out = run([str(BUILD / "chartnum_dump"), g25.small()], timeout=300).stdout
    rows = pq.read_table(g25.small()).to_pylist()
    blocks = re.split(r"^SPEC \d+\n", out.split("END")[0], flags=re.M)[1:]
    if len(blocks) != len(NUMS):
        return False, f"{len(blocks)} charts printed: {out[-300:]}"
    for k, (block, (how, op, lo, hi, paid)) in enumerate(zip(blocks, NUMS)):
        keep = lambda a: a is not None and ((op == ">" and a > lo) or (op == "<" and a < hi) or (op == "between" and lo <= a <= hi) or (op == ">=" and a >= lo))
        groups = {}
        for r in rows:
            if paid is not None and r["paid"] is not paid:
                continue
            a = float(r["amount"]) if r["amount"] is not None else None
            if not keep(a):
                continue
            groups.setdefault(r["region"] if r["region"] is not None else "(blank)", []).append(a)
        for line in block.strip().split("\n")[1:]:
            name, text = line.split("\t")
            vals = groups.get(name, [])
            want = (sum(vals) if how == "sum" else len(vals) if how == "count" else (sum(vals) / len(vals) if vals else None) if how == "mean"
                    else stat(vals, "median"))
            if text == "—":
                if want is not None and name != "(blank)":
                    problems.append(f"spec {k}: {name} reads — but pyarrow has {want}")
                continue
            if want is None or abs(float(text.replace(",", "")) - want) > 0.006:
                problems.append(f"spec {k} ({how} {op}): {name} {text} vs pyarrow {want}")
    asked = g25.gtk(g25.SHEET + ";tap:Chart;pause:300;" + g28.ASK + "only paid and over 5,000;pause:400", "m2-ask")[0]
    if "paid, amount over 5,000.00" not in " ".join(re.findall(r"^BUTTON: (.*)$", asked, re.M)):
        problems.append("GTK: asking \"only paid and over 5,000\" didn't set both")
    page = g25.gtk(g25.SHEET + ";tap:Chart;pause:300;tap:Rows;pause:300;select:1=Over;pause:300;enter:From=2,500;pause:400", "m2-page")[0]
    if "amount over 2,500.00" not in re.findall(r"^BUTTON: (.*)$", page, re.M):
        problems.append(f"GTK Rows page: {[b for b in re.findall(r'^BUTTON: (.*)$', page, re.M) if 'amount' in b]}")
    return not problems, "; ".join(problems[:6]) or ("five number conditions (over, under, between, at least; with a Yes/No filter too) equal pyarrow's; "
                                                      "\"only paid and over 5,000\" sets both; the Rows page's Over 2,500 filters the chart (GTK)")


def todo(what):
    def fn():
        return False, f"not built yet: {what}"
    return fn


def m5():
    """Goal 28's checks (every earlier goal's inside them)."""
    problems = []
    for name, fn in [(f"28-M{i}", getattr(g28, f"m{i}")) for i in range(8)]:
        ok, msg = fn()
        if not ok:
            problems.append(f"{name}: {msg}")
    return not problems, "; ".join(problems) or "goal 28's M0–M7 (goals 3–27 inside them) pass"


MILESTONES = [("M0", m0), ("M1", m1), ("M2", m2), ("M3", todo("by month, quarter, weekday")), ("M4", todo("timings")), ("M5", m5)]


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
