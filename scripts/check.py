"""Milestone checker for GOAL.md (goal 23: the GPU for streamed files, MX frame 1889b7f; text order as the owner
settled it; goal 22's checks run as M3, every earlier goal's inside them). Rebuilds from scratch, prints PASS/FAIL per
milestone. pyarrow writes the files and is the oracle; omxplorer is driven through the agent host.

Run: scripts/check   (a subset without rebuilding: scripts/check M1 M2; earlier goals: through docs/goals/NN-check.py)
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


g22 = load("goal22", "docs/goals/22-check.py")
g21, g20 = g22.g21, g22.g20
run, BUILD = g20.run, g20.BUILD
from agent_client import Client  # noqa: E402

OUT = BUILD / "g23"
MIXED = ["banana", "Zebra", "apple", "Apple", "cherry", "Banana"]
ORDER = ["Apple", "apple", "Banana", "banana", "cherry", "Zebra"]


def m1():
    """1889b7f vendored; a streamed sheet asks for AUTO; the GPU's answers equal the CPU's; times measured."""
    problems = []
    commit = (ROOT / "vendor/MXFRAME_COMMIT").read_text().splitlines()[0]
    if "1889b7f" not in commit:
        problems.append(f"vendor/MXFRAME_COMMIT isn't 1889b7f: {commit[:100]}")
    fresh = BUILD / "mxframe-src" / "build" / "mxframe.mojoc"
    if not fresh.exists() or fresh.read_bytes() != (ROOT / "vendor/mxframe.mojoc").read_bytes():
        problems.append("vendor/mxframe.mojoc isn't the package built from the archive in build/mxframe-src")
    src = (ROOT / "mojoui/sheet.mojo").read_text()
    if "self.mode = MX_AUTO  # (the package picks per machine and plan" not in src:
        problems.append("a streamed sheet doesn't ask for AUTO")
    err = g20.mojo_test("tests/test_streamed.mojo", "STREAMED GPU: totals, chart and pivot with edits equal the CPU's", "test_streamed")
    if err:
        problems.append(err)
    big = g20.fixture("big", "big.parquet", g20.BIG_ROWS)
    b = run(["scripts/mxbuild.sh", "tests/bench_stream_device.mojo", "-o", str(BUILD / "bench_stream_device")], timeout=1800)
    r = run([str(BUILD / "bench_stream_device"), str(big)], timeout=1800) if b.returncode == 0 else b
    times = [l for l in r.stdout.splitlines() if l.startswith(("total:", "group-by:"))]
    if r.returncode != 0 or "BENCH DONE" not in r.stdout or len(times) != 2 or "GPU" not in times[0]:
        problems.append("the 100M-row device benchmark failed (or ran no GPU): " + (r.stdout + r.stderr)[-500:])
    else:
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / "times.txt").write_text("\n".join(times) + "\n")
    c = Client(BUILD / "omxplorer" / "web", g22.env("device", OMX_STREAM_ROWS=10_000_000))
    try:
        c.call(g20.opener(c), path=str(big))
        c.call("create-table")
        c.call("insert-chart")
        chart = [s for s in g20.status_of(c) if s.startswith("Chart: ")]
        if not chart or " ms on " not in chart[0] or "streamed from disk" not in chart[0]:
            problems.append(f"the streamed chart's message doesn't say where it ran: {chart}")
    finally:
        c.close()
    short = "; ".join(t.split(" (")[0] for t in times)
    return not problems, "; ".join(problems) or (
        f"vendored from 1889b7f; streamed sheets ask for AUTO; the GPU's totals, chart and pivot over a streamed file with edits equal "
        f"the CPU's (test_streamed); 100M rows: {short}")


def m2():
    """Text order: case ignored, bytes breaking ties; in memory and streamed, through the app and the engine."""
    import pyarrow as pa
    import pyarrow.parquet as pq
    problems = []
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "names.parquet"
    pq.write_table(pa.table({"name": [MIXED[k % 6] for k in range(48)], "n": list(range(48))}), path, row_group_size=8)
    for kind, more in (("memory", {}), ("streamed", {"OMX_STREAM_ROWS": 10})):
        c = Client(BUILD / "omxplorer" / "web", g22.env("order-" + kind, **more))
        try:
            c.call(g20.opener(c), path=str(path))
            c.call("create-table")
            c.call("grid", gesture="tap", x=100, y=12)  # (the name column's header)
            for tool, want in (("data-sort-smallest-first", ORDER), ("data-sort-largest-first", ORDER[::-1])):
                c.call(tool)
                _, body = g20.grid_rows(c, 0, 48)
                seen = []
                for r in body or []:
                    if not seen or seen[-1] != r[0]:
                        seen.append(r[0])
                if seen != want:
                    problems.append(f"{kind}: {tool} gives {seen}, not {want}")
        finally:
            c.close()
    err = g20.mojo_test("tests/test_text_order.mojo", "TEXT ORDER TESTS PASSED", "test_text_order")
    if err:
        problems.append(err)
    return not problems, "; ".join(problems) or "a text column sorts Apple, apple, Banana, banana, cherry, Zebra (and back), in memory and streamed, in the app and the engine"


def m3():
    """Nothing regressed: goal 22's milestones (every earlier goal's inside them); the plan."""
    problems = []
    for name, fn in [("22-M1", g22.m1), ("22-M2", g22.m2), ("22-M3", g22.m3), ("22-M4", g22.m4)]:
        ok, msg = fn()
        if not ok:
            problems.append(f"{name}: {msg}")
    plan = (ROOT / "docs/plans/needs-mxframe.md").read_text()
    for needle in ("1889b7f", "GPU for a streamed file"):
        if needle not in plan:
            problems.append(f"docs/plans/needs-mxframe.md doesn't mention {needle!r}")
    return not problems, "; ".join(problems) or "goal 22's M1–M4 (goals 3–21 inside them) pass; needs-mxframe.md is current"


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
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3)]:
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
