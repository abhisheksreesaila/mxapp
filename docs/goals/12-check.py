"""Milestone checker for goal 12 (archived: docs/goals/12-mxstudio-report.md: MX Studio's Report; goal 11's checks run as M5, earlier goals' inside them: MX Studio's Sheet, components first; goal 10's checks run as M6,
earlier goals' inside them). Rebuilds from scratch, prints PASS/FAIL per milestone. GTK runs headless.

Run: scripts/check   (a subset without rebuilding: scripts/check M4 M5; earlier goals: docs/goals/NN-check.py)
"""

import importlib.util
import re
import sys
from pathlib import Path

ROOT = next(p for p in Path(__file__).resolve().parents if (p / "pixi.toml").exists())  # (archived in docs/goals/)
sys.path.insert(0, str(ROOT / "scripts"))

_spec = importlib.util.spec_from_file_location("goal11", ROOT / "docs/goals/11-check.py")
g11 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g11)
g10 = g11.g10
run, BUILD = g11.run, g11.BUILD

import drive  # noqa: E402

EXAMPLES = g11.EXAMPLES
SHOWN = r"^(LABEL|TONE|SEGMENTED|TABS|DROPDOWN|BUTTON|FIELD|TEXTAREA|BOARD): "
TIMING = re.compile(r"^LABEL: .*[\d.]+ ms on ")

REPORT = "segment:0=Report"
WEST = REPORT + ";select:1=West"  # the Report's region filter (dropdowns: quarter, region, product)
MERGE_REPORT = "tap:Merge into “Acme Corp”;segment:0=Report"
OPEN = REPORT + ";tap:Open the rows"
MIX = REPORT + ";tapat:6=500,40"  # canvases in order: 4 KPI sparklines, weekly, top customers, product mix (the first bar)
TILES = ("Revenue and margin by week", "Top customers", "Product mix", "Margin · region × product", "Worth a look",
         "Revenue", "Orders", "Gross margin", "Active customers")


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


def kpi(out, name):
    """A KPI's value: the label after its name."""
    got = labels(out)
    return got[got.index(name) + 1] if name in got and got.index(name) + 1 < len(got) else None


def kpi_values(out):
    return [l for l in labels(out) if re.match(r"^\$[\d.]+[KMB]?$|^[\d,]+$|^[\d.]+%$", l)]


def m1():
    problems = []
    for f, needle in (("mojoui/kpi.mojo", "struct KpiView"), ("mojoui/finding.mojo", "def FindingCard("),
                      ("mojoui/charts.mojo", "struct Heatmap"), ("mojoui/charts.mojo", "def with_marker")):
        if needle not in (ROOT / f).read_text():
            problems.append(f"{f} lacks {needle}")
    ok, out = built_test("tests/test_components.mojo", "test_components", "COMPONENT TESTS PASSED")
    if not ok:
        problems.append(f"test_components: {out}")
    app = (ROOT / "examples/mxstudio/app.mojo").read_text()
    if "return FindingCard(" not in app[app.index("def agent_card"):]:
        problems.append("the Sheet's agent card isn't a FindingCard")
    r = run(["pixi", "run", "python", "scripts/components.py", "--check"], timeout=120)
    if r.returncode != 0:
        problems.append("docs/components.md is stale")
    doc = (ROOT / "docs/components.md").read_text()
    for name in ("KpiView", "FindingCard"):
        row = next((l for l in doc.splitlines() if l.startswith(f"| `{name}`")), "")
        if row.count("✅") < 2:
            problems.append(f"the matrix doesn't show {name} ✅ on Linux and web")
    return not problems, "; ".join(problems) or "KpiView, FindingCard, line markers and Heatmap in mojoui with tests; the matrix shows them ✅ on Linux and web"


def m2():
    ok, out = built_test("tests/test_report.mojo", "test_report", "REPORT TESTS PASSED", (".",))
    if not ok:
        return False, f"test_report: {out}"
    m = re.search(r"REPORT: .*", out)
    return True, (m.group(0) if m else "the anomaly finder and the KPIs match the CPU")


def m3():
    problems = []
    rep = both(REPORT, "report")
    west = both(WEST, "report-west")
    for o in (rep, west):
        if o[0] is None:
            return False, o[1]
    for host, o in (("GTK", rep[0]), ("web", rep[1])):
        missing = [t for t in TILES if t not in labels(o)]
        if missing:
            problems.append(f"{host}: no {missing}")
        if not re.search(r"^LABEL: (Heavy|Light) parcels in the \w+ lost [\d.]+ margin points after Jul 14", o, re.M):
            problems.append(f"{host}: 'Worth a look' doesn't name the fall")
        if not re.search(r"Carrier A's freight rose from \$[\d.,]+ to \$14\.20 an order", o):
            problems.append(f"{host}: the finding doesn't give the cause the engine found")
        if kpi(o, "Active customers") != "20":
            problems.append(f"{host}: active customers before a merge: {kpi(o, 'Active customers')}")
    if shown(rep[0]) != shown(rep[1]) or shown(west[0]) != shown(west[1]):
        problems.append(f"GTK and web differ: {sorted(set(shown(rep[0])) ^ set(shown(rep[1])))[:4]}")
    if kpi_values(rep[0]) == kpi_values(west[0]):
        problems.append("picking the West didn't change the KPIs")
    return not problems, "; ".join(problems) or "the Report on both hosts: filters, four KPIs, weekly revenue and margin (the marker proven in test_components), top customers, product mix, heatmap, 'Worth a look' with the cause it found; the West filter changes the KPIs"


def m4():
    problems = []
    merged = both(MERGE_REPORT, "report-merged")
    opened = both(OPEN, "report-open")
    mix = both(MIX, "report-mix")
    for o in (merged, opened, mix):
        if o[0] is None:
            return False, o[1]
    for host, o in (("GTK", merged[0]), ("web", merged[1])):
        if kpi(o, "Active customers") != "18":
            problems.append(f"{host}: active customers after the merge: {kpi(o, 'Active customers')} (want 18)")
        if "after merging duplicate names" not in labels(o):
            problems.append(f"{host}: the Report didn't see the Sheet's merge")
        if not any(re.match(r"^\+\$[\d.]+[KMB]? for Acme Corp once 3 spellings were merged", l) for l in labels(o)):
            problems.append(f"{host}: top customers doesn't say what the merge added")
    rep = both(REPORT, "report-count")
    m = re.search(r"([\d,]+) orders\)\.", rep[0] or "")
    for host, o in (("GTK", opened[0]), ("web", opened[1])):
        if not re.search(r"^LABEL: Transactions$", o, re.M):
            problems.append(f"{host}: Open the rows didn't go to the Sheet")
        if m is None or label(o, "showing " + m.group(1) + " heavy parcels in the West after Jul 14") is None:
            problems.append(f"{host}: the Sheet isn't filtered to the finding's rows ({m.group(1) if m else '?'})")
    for host, o in (("GTK", mix[0]), ("web", mix[1])):
        if label(o, "Filtered to Trail Pack") is None:
            problems.append(f"{host}: tapping a product bar didn't filter")
        if kpi(o, "Revenue") == kpi(rep[0], "Revenue"):
            problems.append(f"{host}: the product filter didn't change the KPIs ({kpi(o, 'Revenue')})")
    for name, o in (("merged", merged), ("opened", opened), ("mix", mix)):
        if shown(o[0]) != shown(o[1]):
            problems.append(f"{name}: GTK and web differ: {sorted(set(shown(o[0])) ^ set(shown(o[1])))[:3]}")
    return not problems, "; ".join(problems) or "one engine: the Sheet's merge reaches the Report; Open the rows filters the Sheet to the finding's rows; a product bar filters the tiles; identical on both hosts"


def m5():
    problems = []
    for name in ("m1", "m2", "m3", "m4", "m5", "m6"):
        ok, msg = getattr(g11, name)()
        if not ok:
            problems.append(f"goal 11 {name.upper()}: {msg[:300]}")
    return not problems, "; ".join(problems) or "goal 11's checks (and goals 3–10's inside them) pass"


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
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5)]:
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
