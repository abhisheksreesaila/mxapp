"""Milestone checker for GOAL.md (goal 30: the island, and 100 million rows that never freeze the window; goal 29's
checks run as M5, every earlier goal's inside them). Rebuilds from scratch, prints PASS/FAIL per milestone.

Run: scripts/check   (a subset without rebuilding: scripts/check M1 M2; earlier goals: through docs/goals/NN-check.py)
Each milestone's proof is written before its work starts (todo() until then: it fails).
"""

import importlib.util
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


MILESTONES = [("M0", m0), ("M1", todo("queries off the window")), ("M2", todo("the Island component")),
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
