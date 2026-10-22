"""Milestone checker for GOAL.md (goal 30: the island, and 100 million rows that never freeze the window; goal 29's
checks run as M5, every earlier goal's inside them). Rebuilds from scratch, prints PASS/FAIL per milestone.

Run: scripts/check   (a subset without rebuilding: scripts/check M1 M2; earlier goals: through docs/goals/NN-check.py)
Each milestone's proof is written before its work starts (todo() until then: it fails).
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
g20 = g29.g20
run, BUILD = g20.run, g20.BUILD
APPS = g29.APPS


def m0():
    """The new engine everywhere: vendored from 23edc59; every example built for every platform it lists; a chart
    through a job equals the chart in place."""
    problems = []
    stamp = (ROOT / "vendor/MXFRAME_COMMIT").read_text().split("\n")[0]
    if "23edc59" not in stamp:
        problems.append(f"vendor/MXFRAME_COMMIT says {stamp[:60]}")
    for ex in APPS:
        plats = (ROOT / "examples" / ex / "platforms").read_text().split() if (ROOT / "examples" / ex / "platforms").exists() else ["linux", "web", "mac", "ios"]
        for plat in plats:
            if plat in ("linux", "web", "mac", "ios") and not (BUILD / ex / plat).exists():
                problems.append(f"{ex} has no {plat} build")
    err = g20.mojo_test("tests/test_chart_job.mojo", "PASSED", "test_chart_job", "tests")
    if err:
        problems.append(err)
    return not problems, "; ".join(problems[:6]) or ("vendor/ is MX frame 23edc59; every example built for Linux, the web, Mac and iPhone (as its "
                                                      "platforms list); 6 charts through a job equal the same charts in place")


OUT = BUILD / "g30"


def big():
    """Goal 20's 100M-row file (order, amount, region, day, paid): the main checkout's copy, else this one's."""
    main = ROOT.parent / "mojo-ui" / "build" / "g20" / "big.parquet"
    return main if main.exists() else BUILD / "g20" / "big.parquet"


def gtk(steps, name, **more):
    """omxplorer on the private headless display, traced (MOJOUI_TRACE: the jobs say what they do, frame gaps), fresh settings."""
    home = OUT / name
    for d in ("docs", "config", "uploads"):
        (home / d).mkdir(parents=True, exist_ok=True)
    for f in (home / "config").glob("*"):
        f.unlink()
    env = dict(g20.g19.env(), OMX_DOCUMENTS=str(home / "docs"), OMX_CONFIG=str(home / "config"), MOJOUI_TRACE="1",
               MOJOUI_TEST=steps, MOJOUI_SHOT=str(OUT / f"{name}-gtk.png"), MOJOUI_WINDOW="1742x876", **more)
    r = run([str(BUILD / "omxplorer" / "linux" / "omxplorer")], env=env, timeout=900)
    out = r.stdout + r.stderr
    (OUT / f"{name}.txt").write_text(out)
    if r.returncode != 0 or "CRITICAL" in out or "TEST: " in out:
        raise RuntimeError(f"GTK run {name} failed (exit {r.returncode}): {out[-600:]}")
    return out


def charts_in(out):
    """Each chart's text as it landed (CHART: chartN, then its lines up to the next line that isn't a row)."""
    got = []
    lines = out.splitlines()
    for i, l in enumerate(lines):
        if l.startswith("CHART: "):
            rows = []
            for m in lines[i + 1:]:
                if " | " not in m:
                    break
                rows.append(m)
            got.append("\n".join(rows))
    return got


def gaps(out):
    return [float(v) for v in re.findall(r"^GAPS: \d+ frames, longest ([\d.]+) ms$", out, re.M)]


def m1():
    """Queries off the window at 100M rows: opening, a median, a month chart, a column's figures; a newer pick cancels."""
    problems = []
    if not big().exists():
        return False, f"no 100M-row file at {big()} (goal 20's big.parquet)"
    b = run(["scripts/mxbuild.sh", "tests/bigchart_dump.mojo", "-o", str(BUILD / "bigchart_dump")], timeout=1800)
    if b.returncode != 0:
        return False, "bigchart_dump: " + (b.stdout + b.stderr)[-400:]
    want = run([str(BUILD / "bigchart_dump"), str(big())], timeout=900).stdout
    blocks = re.findall(r"^CHART (\w+)\n(.*?)(?=^CHART |^SUM )", want, re.M | re.S)
    want_chart = {k: "\n".join(l for l in v.strip().splitlines() if " | " in l) for k, v in blocks}  # (rows only: the tool also prints timings)
    want_sum = re.search(r"^SUM (.*)$", want, re.M).group(1)
    opened = "gaps:start;pick:Choose a file={f};gaps:3500;tap:Create table;pause:300;tap:Chart;pause:1500".format(f=big())
    a = gtk(opened + ";tap:Data;gaps:start;segment:1=Median;gaps:2000;tap:Back;gaps:start;" + g29.g28.ASK + "by month;gaps:5500", "g30-m1")
    g = gaps(a)
    if len(g) != 3 or max(g) > 50.0:
        problems.append(f"frame gaps while opening, the median and the month chart ran: {g} ms (want 3, each ≤ 50)")
    landed = charts_in(a)
    if want_chart.get("median") not in landed:
        problems.append(f"the median chart that landed isn't the in-place one: {landed[-2:] if landed else 'none'}")
    if want_chart.get("month") not in landed:
        problems.append(f"the month chart that landed isn't the in-place one (got {len(landed)} charts)")
    for job in ("open big.parquet", "chart0 median amount by region", "chart0 median amount by month", "column amount"):
        if f"JOB: start {job}" not in a:
            problems.append(f"no background job for {job}")
    if not re.search(r"^LABEL: Sum " + re.escape(want_sum) + "$", a, re.M):
        problems.append(f"the status bar's sum isn't the in-place {want_sum}")
    c = gtk(opened + ";tap:Data;gaps:start;segment:1=Median;pause:100;segment:1=Sum;gaps:2000", "g30-m1-cancel")
    after = c.split("JOB: start chart0 median amount by region", 1)[-1]
    if "JOB: start chart0 median amount by region" not in c or "landed chart0" not in after:
        problems.append("the cancel run didn't start the median and then land a chart")
    elif re.search(r"^region \| median amount$", after, re.M):
        problems.append("the median landed though Sum was picked while it ran (want it cancelled)")
    if max(gaps(c) or [999]) > 50.0:
        problems.append(f"frame gaps around the cancel: {gaps(c)} ms")
    return not problems, "; ".join(problems[:6]) or (f"at 100M rows on GTK the window kept drawing (longest frame gaps {', '.join(f'{v:.0f}' for v in g)} ms) "
                                                      "while the file opened, a median and a month chart ran and the column's figures came; each "
                                                      "equals the in-place answer; Sum picked during the median cancels it")


def todo(what):
    def fn():
        return False, f"not built yet: {what}"
    return fn


def m5():
    """Goal 29's checks (every earlier goal's inside them)."""
    problems = []
    for name, fn in [(f"29-M{i}", getattr(g29, f"m{i}")) for i in range(6)]:
        ok, msg = fn()
        if not ok:
            problems.append(f"{name}: {msg}")
    return not problems, "; ".join(problems) or "goal 29's M0–M5 (goals 3–28 inside them) pass"


MILESTONES = [("M0", m0), ("M1", m1), ("M2", todo("the Island component")),
              ("M3", todo("omxplorer wears the island")), ("M4", todo("the 100M demo")), ("M5", m5)]


def build_all():
    import shutil
    every = list(dict.fromkeys(list(g20.EXAMPLES) + APPS))
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


if __name__ == "__main__":
    main()
