"""Milestone checker for GOAL.md (goal 9: the Workbook; goal 8's checks run as M7, earlier goals' inside them).
Rebuilds from scratch, prints PASS/FAIL per milestone.

Run: scripts/check   (earlier goals' checkers: docs/goals/0N-check.py)
"""

import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

_spec = importlib.util.spec_from_file_location("goal8", ROOT / "docs/goals/08-check.py")
g8 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g8)
g7 = g8.g7
run, BUILD = g8.run, g8.BUILD

import drive  # noqa: E402

EXAMPLES = g8.EXAMPLES + ["workbook"]
SHOWN = r"^(LABEL|SEGMENTED|DROPDOWN|BUTTON|FIELD|TEXTAREA|BOARD): "
TIMING = ("LABEL: Recomputed", "LABEL: Loaded")

# The morning walkthrough, scripted. The grid is canvas 0 of the Table object; tapat is in thousandths.
EDIT = "tapat:0=620,300;enter:Value=7"  # tap a cell of the first table (the cents column, row 3), type 7, Enter
PIVOT = "select:0=category;select:1=year"  # the pivot's row and column dropdowns
CHART = "tapat:2=500,500"  # click a bar of the chart: crossfilter
FORMULA = "enter:Formula=margin = cents - cost"  # a formula column typed as text
MOVE = "move:note=160,96"  # drag the note object by 160, 96 points on the board
RESIZE = "resize:note=84,44"  # drag its bottom-right corner
NARROW = (640, 900)


def shown(out):
    """The widgets' state, as a sorted list: GTK and the web report the same widgets in a different order."""
    return sorted(l for l in out.splitlines() if re.match(SHOWN, l) and not l.startswith(TIMING))


def gtk(steps, size=None, shot=None, example="workbook"):
    env = {"MOJOUI_TEST": steps, "MOJOUI_SHOT": shot or str(BUILD / example / "gtk.png"),
           "MOJOUI_WORKBOOK": str(BUILD / "workbook" / "check.mxwb")}  # saves never touch the person's documents
    if size:
        env["MOJOUI_WINDOW"] = f"{size[0]}x{size[1]}"
    exe = BUILD / example / "linux" / example
    if not exe.exists():
        return None, f"no {exe}"
    r = run([str(exe)], env=env, timeout=600)
    out = r.stdout + r.stderr
    if r.returncode != 0 or "CRITICAL" in out or "TEST: " in out:
        return None, f"GTK run failed (exit {r.returncode}):\n{out[-600:]}"
    return r, out


def web(steps, size=(1440, 900), shot=None, example="workbook"):
    try:
        r, out = drive.web_run(BUILD / example / "web", steps, shot=shot, viewport=size)
    except Exception as e:
        return None, f"web run crashed: {e!r}"
    return (r, out) if r.returncode == 0 else (None, out[-600:])


def both(steps, size=(1440, 900), shot_name="shot"):
    """The same steps on GTK and web; returns (gtk_out, web_out) or (None, problem)."""
    rg, og = gtk(steps, size, shot=str(BUILD / "workbook" / f"{shot_name}-gtk.png"))
    if rg is None:
        return None, f"GTK: {og[-300:]}"
    rw, ow = web(steps, size, shot=str(BUILD / "workbook" / f"{shot_name}-web.png"))
    if rw is None:
        return None, f"web: {ow[-300:]}"
    return og, ow


def summary(out):
    return [l for l in out.splitlines() if l.startswith("LABEL: ") and "revenue" in l]


def built_test(src, out_name, marker, includes=(".",), timeout=900):
    args = ["pixi", "run", "mojo", "build"]
    for inc in includes:
        args += ["-I", inc]
    b = run(args + [src, "-o", str(BUILD / out_name)], timeout=timeout)
    if b.returncode != 0:
        return False, f"{src} didn't build: {(b.stdout + b.stderr)[-400:]}", ""
    t = run(["pixi", "run", str(BUILD / out_name)], timeout=timeout)
    text = t.stdout + t.stderr
    return marker in t.stdout, text[-500:], t.stdout


# ---------- milestones ----------

def m1():
    t = run(["pixi", "run", "mojo", "run", "-I", ".", "tests/test_frame.mojo"], timeout=900)
    if "FRAME TESTS PASSED" not in t.stdout:
        return False, f"frame tests: {(t.stdout + t.stderr)[-500:]}"
    src = (ROOT / "mojoui/frame.mojo").read_text()
    missing = [w for w in ("def set(", "def append(", "def remove(", "def permutation(", "def undo(", "def formula(")
               if w not in src]
    if missing:
        return False, f"frame.mojo lacks {missing}"
    return True, "typed columns, formulas with a dependency graph, edits, tombstones, sort permutation, undo"


def m2():
    ok, tail, out = built_test("tests/test_frame_gpu.mojo", "test_frame_gpu", "FRAME GPU TESTS PASSED")
    if not ok:
        return False, f"frame GPU tests: {tail}"
    m = re.search(r"^GROUPBY: (\d+) rows, GPU = CPU on (\d+) numbers, max ([\d.]+) ms, device (.+)$", out, re.M)
    if not m:
        return False, f"no GROUPBY line: {out[-300:]}"
    problems = []
    if int(m[1]) < 20_000_000:
        problems.append(f"only {m[1]} rows")
    if float(m[3]) > 10:
        problems.append(f"{m[3]} ms > 10")
    if "PATCH: edit visible in the next group-by" not in out:
        problems.append("edits don't reach the GPU")
    if "PIVOT: 2-D agrees with the CPU" not in out:
        problems.append("no pivot")
    return not problems, "; ".join(problems) or f"{int(m[1]):,} rows: GPU = CPU on {m[2]} numbers, ≤ {m[3]} ms, patch + pivot, on {m[4]}"


def m3():
    problems = []
    before = both("", shot_name="start")
    if before[0] is None:
        return False, before[1]
    if shown(before[0]) != shown(before[1]):
        problems.append(f"GTK and web start differently: {sorted(set(shown(before[0])) ^ set(shown(before[1])))[:4]}")
    for tag in ("table", "pivot", "chart", "note"):
        for host, out in (("GTK", before[0]), ("web", before[1])):
            if not re.search(rf"^BOX: {tag} ", out, re.M):
                problems.append(f"no object tagged {tag} on {host}")
    after = both(EDIT, shot_name="edit")
    if after[0] is None:
        return False, after[1]
    if shown(after[0]) != shown(after[1]):
        problems.append(f"GTK and web differ after an edit: {sorted(set(shown(after[0])) ^ set(shown(after[1])))[:4]}")
    if summary(before[0]) == summary(after[0]):
        problems.append(f"an edit didn't change the totals: {summary(after[0])[:2]}")
    piv = both(PIVOT, shot_name="pivot")
    if piv[0] is None:
        return False, piv[1]
    if shown(piv[0]) != shown(piv[1]):
        problems.append("GTK and web differ after choosing pivot fields")
    if not re.search(r"^LABEL: 2023$", piv[0], re.M) or re.search(r"^LABEL: 2023$", before[0], re.M):
        problems.append("the pivot didn't switch to year columns")
    cf = both(CHART, shot_name="chart")
    if cf[0] is None:
        return False, cf[1]
    if summary(cf[0]) == summary(before[0]) or shown(cf[0]) != shown(cf[1]):
        problems.append("tapping the chart didn't crossfilter identically on both hosts")
    fm = both(FORMULA, shot_name="formula")
    if fm[0] is None:
        return False, fm[1]
    if not re.search(r"^LABEL: .*formulas: margin = cents - cost", fm[0], re.M) or shown(fm[0]) != shown(fm[1]):
        problems.append("the formula column didn't appear identically on both hosts")
    return not problems, "; ".join(problems) or "table, pivot, chart and note objects; edits, pivots, crossfilter and formulas identical on GTK and web"


def m4():
    problems = []
    src = (ROOT / "mojoui/view.mojo").read_text()
    if "def Board(" not in src:
        return False, "no Board container in mojoui/view.mojo"
    before = both("", shot_name="board")
    if before[0] is None:
        return False, before[1]
    pos = lambda out: sorted(l for l in out.splitlines() if l.startswith("BOARD: "))
    if not pos(before[0]) or pos(before[0]) != pos(before[1]):
        problems.append(f"board positions differ or missing: {pos(before[0])[:2]} vs {pos(before[1])[:2]}")
    after = both(MOVE, shot_name="moved")
    if after[0] is None:
        return False, after[1]
    if pos(after[0]) == pos(before[0]):
        problems.append("the drag didn't move the note")
    if pos(after[0]) != pos(after[1]):
        problems.append(f"after the drag GTK and web disagree: {pos(after[0])[:2]} vs {pos(after[1])[:2]}")
    note = [l for l in pos(after[0]) if "note" in l]
    if note and not re.search(r"at (\d+),(\d+)", note[0]):
        problems.append("no position reported for the note")
    elif note:
        x, y = map(int, re.search(r"at (\d+),(\d+)", note[0]).groups())
        if x % 8 or y % 8:
            problems.append(f"not snapped to the 8-pt grid: {note[0]}")
    rs = both(RESIZE, shot_name="resized")
    if rs[0] is None:
        return False, rs[1]
    note_rs = [l for l in pos(rs[0]) if " note " in l]
    if pos(rs[0]) != pos(rs[1]) or not note_rs:
        problems.append(f"after the resize GTK and web disagree: {[l for l in pos(rs[0]) if 'note' in l]} vs {[l for l in pos(rs[1]) if 'note' in l]}")
    elif not re.search(r" (\d+)x(\d+)$", note_rs[0]):
        problems.append("no size reported for the note")
    else:
        w, h = map(int, re.search(r" (\d+)x(\d+)$", note_rs[0]).groups())
        if (w, h) == (520, 104):
            problems.append("the corner drag didn't resize the note")
        if w % 8 or h % 8:
            problems.append(f"size not snapped to the 8-pt grid: {note_rs[0]}")
    narrow = both("", size=NARROW, shot_name="narrow")
    if narrow[0] is None:
        return False, narrow[1]
    if pos(narrow[0]) or not re.search(r"^LAYOUT: list", narrow[0], re.M) or not re.search(r"^LAYOUT: list", narrow[1], re.M):
        problems.append("a narrow window should render the page as a list")
    return not problems, "; ".join(problems) or "Board: absolute positions, drag, resize + snap identical on GTK and web; narrow windows show a list"


def m5():
    problems = []
    sample = ROOT / "examples/workbook/contoso.mxwb"
    if not (sample / "workbook.json").exists():
        return False, "no sample workbook"
    ok, tail, out = built_test("tests/test_workbook.mojo", "test_workbook", "WORKBOOK TESTS PASSED", includes=(".", "examples/workbook"))
    if not ok:
        return False, f"workbook round-trip: {tail}"
    if "ROUNDTRIP: identical" not in out:
        problems.append("round-trip not proven identical")
    r, o = gtk(f"{EDIT};tap:Save;tap:Open")
    if r is None:
        return False, o
    edited = gtk(EDIT)[1] or ""
    if not re.search(r"^LABEL: Opened ", o, re.M):
        problems.append(f"the app didn't report opening the file: {[l for l in o.splitlines() if l.startswith('LABEL: ') and ('Saved' in l or 'open' in l.lower())][:2]}")
    if summary(o) != summary(edited) or summary(o) == summary(gtk("")[1] or ""):
        problems.append("save then open didn't keep the edit in the app")
    start = gtk("")[1] or ""
    if not re.search(r"^LABEL: Opened .*contoso\.mxwb", start, re.M):
        problems.append("the app doesn't open the sample workbook at start")
    return not problems, "; ".join(problems) or "save → open round-trips tables, formulas, pivots, charts, notes and layout"


def m6():
    problems = []
    for f in ("build/workbook/linux/workbook", "scripts/workbook.sh", "docs/morning.md", "build/workbook/web/mojoui_app.so"):
        if not (ROOT / f).exists():
            problems.append(f"missing {f}")
    gallery = (ROOT / "docs/gallery/index.html").read_text()
    if "workbook" not in gallery.lower():
        problems.append("the gallery doesn't show the workbook")
    readme = (ROOT / "README.md").read_text()
    if "scripts/workbook.sh" not in readme:
        problems.append("README doesn't say how to run the workbook")
    morning = (ROOT / "docs/morning.md").read_text() if (ROOT / "docs/morning.md").exists() else ""
    for w in ("drag", "formula", "chart", "note", "save"):
        if w not in morning.lower():
            problems.append(f"docs/morning.md lacks '{w}'")
    return not problems, "; ".join(problems) or "packaged Linux app + web, launcher, morning walkthrough, gallery and README updated"


def m7():
    problems = []
    for name in ("m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m9", "m10"):
        ok, msg = getattr(g8, name)()
        if not ok:
            problems.append(f"goal 8 {name.upper()}: {msg[:200]}")
    return not problems, "; ".join(problems) or "goal 8's checks (and goals 3–7's inside them) still pass"


def m8():
    problems = []
    for f in ("examples/workbook/app.mojo", "examples/analytics/app.mojo"):
        if "init_shared" not in (ROOT / f).read_text():
            problems.append(f"{f} doesn't use init_shared")
    if "def init_shared" not in (ROOT / "mojoui/app.mojo").read_text():
        return False, "no App.init_shared in mojoui/app.mojo"
    try:
        r, out = drive.web_run(BUILD / "workbook" / "web", "", tabs=2)
    except Exception as e:
        return False, f"two-tab web run crashed: {e!r}"
    found = re.findall(r"^SHARED: (\d+) loads?, (\d+) sessions", out, re.M)
    if not found:
        problems.append(f"the server didn't report shared loads: {out[-300:]}")
    elif found[-1][0] != "1" or int(found[-1][1]) < 2:  # the last line: after both tabs opened
        problems.append(f"expected 1 load for 2 sessions, got {found[-1]}")
    try:  # the analytics app too: one copy for two tabs
        r2, out2 = drive.web_run(BUILD / "analytics" / "web", "", tabs=2)
    except Exception as e:
        return False, f"two-tab analytics run crashed: {e!r}"
    found2 = re.findall(r"^SHARED: (\d+) loads?, (\d+) sessions", out2, re.M)
    if not found2 or found2[-1][0] != "1" or int(found2[-1][1]) < 2:
        problems.append(f"analytics: expected 1 load for 2 sessions, got {found2[-1:] or out2[-200:]}")
    return not problems, "; ".join(problems) or "20M rows loaded once per process and shared by every session (workbook and analytics)"


def m9():
    doc = ROOT / "docs/wasm.md"
    if not doc.exists():
        return False, "no docs/wasm.md"
    spike = run(["scripts/wasm_spike.sh"], timeout=1200)  # rebuilds build/wasm from spike/*.mojo
    if spike.returncode != 0 or spike.stdout.count("WASM: hello") < 4:
        return False, f"wasm spike: {(spike.stdout + spike.stderr)[-400:]}"
    text = doc.read_text()
    m = re.search(r"^WASM: (shim-sized|wall)", text, re.M)
    count = re.search(r"(\d+) (missing|undefined) symbols", text)
    if not m or not count:
        return False, "docs/wasm.md lacks the verdict line or the symbol count"
    if m[1] == "shim-sized":
        wasm = ROOT / "build/wasm/hello.wasm"
        if not wasm.exists():
            return False, "verdict shim-sized but no build/wasm/hello.wasm"
        r = run(["pixi", "run", "python", "scripts/wasm_run.py", str(wasm)], timeout=300)
        if "WASM: hello" not in r.stdout:
            return False, f"hello.wasm didn't run in Chromium: {(r.stdout + r.stderr)[-300:]}"
        return True, f"wasm: {count[0]} before the shim; hello, List/String and print samples run in headless Chromium"
    for w in ("missing", "compiler"):
        if w not in text:
            return False, f"docs/wasm.md (wall) lacks '{w}'"
    return True, f"wasm: the wall is documented ({count[0]})"


def m10():
    readme = (ROOT / "README.md").read_text()
    head = "\n".join(readme.splitlines()[:60])
    images = len(re.findall(r"!\[[^\]]*\]\(docs/img/[^)]+\)|<img src=\"docs/img/", head))  # pictures of the apps, not badges
    problems = []
    if images < 4:
        problems.append(f"only {images} images in the first 60 lines")
    if "diagram" not in head.lower() and "platform" not in head.lower():
        problems.append("no one-code-many-platforms diagram up top")
    if "workbook" not in readme.lower():
        problems.append("the workbook isn't in the README")
    return not problems, "; ".join(problems) or f"README opens picture-first ({images} images) and shows the workbook"


def main():
    import shutil
    only = sys.argv[1:]  # scripts/check M3 M4: just those (no rebuild of everything)
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
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5), ("M6", m6), ("M7", m7), ("M8", m8), ("M9", m9), ("M10", m10)]:
        if only and name not in only:
            continue
        try:
            ok, msg = fn()
        except Exception as e:  # a crashing check is a failing check
            ok, msg = False, f"check crashed: {e!r}"
        results.append(ok)
        print(f"{'PASS' if ok else 'FAIL'}  {name}  {msg}", flush=True)
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
