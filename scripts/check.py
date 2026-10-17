"""Milestone checker for GOAL.md (goal 13: keys, so the grid feels like a spreadsheet; goal 12's checks run as M4,
earlier goals' inside them). Rebuilds from scratch, prints PASS/FAIL per milestone. GTK runs headless; the web runs
use real key presses in Chromium (so focus is proven there, not just the events).

Run: scripts/check   (a subset without rebuilding: scripts/check M2 M3; earlier goals: through docs/goals/NN-check.py)
"""

import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

_spec = importlib.util.spec_from_file_location("goal12", ROOT / "docs/goals/12-check.py")
g12 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g12)
run, BUILD, EXAMPLES = g12.run, g12.BUILD, g12.EXAMPLES

import drive  # noqa: E402

SHOWN = r"^(LABEL|TONE|SEGMENTED|TABS|DROPDOWN|BUTTON|FIELD|TEXTAREA|BOARD): "
TIMING = re.compile(r"^LABEL: .*[\d.]+ ms on ")

# Each app's grid is canvas 0. MX Studio's tap lands on a header (a column: the first Down selects row 1); the
# Workbook's on row 1's cell (the first Down selects row 2). `start`: the row after the tap and one Down.
APPS = {
    "mxstudio": dict(tap="tapat:0=300,100", start=1, written=r"^LABEL: customer on row (\d+): .* → Zed Co$",
                     editing=r"^LABEL: Editing order row (\d+) · customer", cleared=r"^LABEL: customer on row (\d+): .* → \(empty\)$"),
    "workbook": dict(tap="tapat:0=300,200", start=2, written=r"^LABEL: Row (\d+): region = Zed Co$",
                     editing=r"^LABEL: Editing row (\d+) · region", cleared=r"^LABEL: Row (\d+): region cleared$"),
}


def shown(out):
    return sorted(l for l in out.splitlines() if re.match(SHOWN, l) and not TIMING.match(l))


def both(app, steps, name):
    exe = BUILD / app / "linux" / app
    r = run([str(exe)], env={"MOJOUI_TEST": steps, "MOJOUI_SHOT": str(BUILD / app / f"{name}-gtk.png")}, timeout=900)
    og = r.stdout + r.stderr
    if r.returncode != 0 or "CRITICAL" in og or "TEST: " in og:
        return None, f"{app} GTK run failed (exit {r.returncode}): {og[-300:]}"
    try:
        rw, ow = drive.web_run(BUILD / app / "web", steps, shot=str(BUILD / app / f"{name}-web.png"), viewport=(1440, 900))
    except Exception as e:
        return None, f"{app} web run crashed: {e!r}"
    if rw.returncode != 0:
        return None, f"{app} web: {ow[-300:]}"
    return og, ow


def first(pattern, out):
    m = re.search(pattern, out or "", re.M)
    return int(m.group(1)) if m and m.groups() else (True if m else None)


def m1():
    problems = []
    for f, needle in (("mojoui/view.mojo", "comptime KEY = 7"), ("mojoui/app.mojo", "def key("), ("mojoui/app.mojo", "def cancel("),
                      ("mojoui/view.mojo", "on_cancel: Int"), ("mojoui/hosts/gtk.mojo", "gtk_event_controller_key_new"),
                      ("mojoui/hosts/web.py", "addEventListener('keydown'")):
        if needle not in (ROOT / f).read_text():
            problems.append(f"{f} lacks {needle}")
    o = both("mxstudio", APPS["mxstudio"]["tap"] + ";key:0=ArrowDown;key:0=ArrowDown;key:0=F2", "keys-move")
    if o[0] is None:
        return False, o[1]
    for host, out in (("GTK", o[0]), ("web", o[1])):
        if first(APPS["mxstudio"]["editing"], out) != 2:
            problems.append(f"{host}: two arrows down from the column then F2 didn't edit row 2 ({first(APPS['mxstudio']['editing'], out)})")
    if shown(o[0]) != shown(o[1]):
        problems.append(f"GTK and web differ: {sorted(set(shown(o[0])) ^ set(shown(o[1])))[:4]}")
    r = run(["pixi", "run", "python", "scripts/components.py", "--check"], timeout=120)
    if r.returncode != 0:
        problems.append("docs/components.md is stale")
    doc = (ROOT / "docs/components.md").read_text()
    for name in ("Canvas: keys", "TextField: Escape cancels", "Editor: caret after the text"):
        row = next((l for l in doc.splitlines() if l.startswith(f"| {name}")), "")
        cells = [c.strip() for c in row.split("|")[3:5]]
        if cells != ["✅", "✅"]:
            problems.append(f"the matrix doesn't show '{name}' ✅ on Linux and web: {cells}")
    return not problems, "; ".join(problems) or "KEY events, canvas focus and on_cancel in mojoui; arrows then F2 edit the same cell on GTK and web (real key presses); the matrix shows them ✅ on Linux and web"


def m2():
    problems = []
    for src, out_name, marker in (("tests/test_grid_keys.mojo", "test_grid_keys", "GRID KEY TESTS PASSED"),
                                  ("tests/test_datagrid.mojo", "test_datagrid", "DATAGRID TESTS PASSED")):
        ok, out = g12.built_test(src, out_name, marker)
        if not ok:
            problems.append(f"{out_name}: {out}")
    return not problems, "; ".join(problems) or "DataGrid's keyboard: arrows, Tab, Enter, PageUp/Down, Home/End, F2, Escape, typing, Delete (deleted rows skipped, the cell kept on screen, formulas read-only); the grid's own tests pass"


def m3():
    problems = []
    for app, a in APPS.items():
        typed = both(app, a["tap"] + ";key:0=ArrowDown;key:0=ArrowDown;typekeys:0=Zed Co;key:0=Enter", "keys-type")
        onward = both(app, a["tap"] + ";key:0=ArrowDown;key:0=ArrowDown;typekeys:0=Zed Co;key:0=Enter;key:0=ArrowDown;key:0=F2", "keys-onward")
        escaped = both(app, a["tap"] + ";key:0=ArrowDown;typekeys:0=Zed;key:0=Escape", "keys-escape")
        back = both(app, a["tap"] + ";key:0=ArrowDown;typekeys:0=Zed;key:0=Escape;key:0=ArrowDown;key:0=F2", "keys-back")
        kept = both(app, a["tap"] + ";key:0=ArrowDown;typekeys:0=Zed;key:0=Escape;key:0=F2", "keys-kept")  # the cell after Escape
        plain = both(app, a["tap"] + ";key:0=ArrowDown;key:0=F2", "keys-plain")  # the same cell, never typed in
        cleared = both(app, a["tap"] + ";key:0=ArrowDown;key:0=Delete", "keys-delete")
        # data entry at a typist's pace: value, Enter, the next value, Enter (keys typed while Enter is answered wait)
        entry = both(app, a["tap"] + ";key:0=ArrowDown;key:0=ArrowDown;typekeys:0=Zed Co⏎AB⏎", "keys-entry")
        entry_up = both(app, a["tap"] + ";key:0=ArrowDown;key:0=ArrowDown;typekeys:0=Zed Co⏎AB⏎;key:0=ArrowUp;key:0=ArrowUp;key:0=F2", "keys-entry-up")
        for o in (typed, onward, escaped, back, kept, plain, cleared, entry, entry_up):
            if o[0] is None:
                return False, o[1]
        for host, k in (("GTK", 0), ("web", 1)):
            row = first(a["written"], typed[k])
            if row != a["start"] + 1:
                problems.append(f"{app} {host}: typing then Enter didn't write 'Zed Co' on row {a['start'] + 1} ({row})")
            elif first(a["editing"], onward[k]) != row + 2:  # Enter moved down a row, Down another, F2 edits there
                problems.append(f"{app} {host}: after Enter, Down and F2 didn't edit two rows below row {row} ({first(a['editing'], onward[k])})")
            if "LABEL: Edit cancelled" not in escaped[k]:
                problems.append(f"{app} {host}: Escape didn't say the edit was cancelled")
            fields = lambda out: sorted(l for l in out.splitlines() if l.startswith("FIELD: "))
            if fields(kept[k]) != fields(plain[k]) or any("Zed" in l for l in fields(kept[k])):
                problems.append(f"{app} {host}: after Escape the cell isn't what it was: {fields(kept[k])} vs {fields(plain[k])}")
            if first(a["editing"], back[k]) != a["start"] + 1:
                problems.append(f"{app} {host}: after Escape the keyboard isn't back on the grid ({first(a['editing'], back[k])})")
            if first(a["written"].replace("Zed Co", "AB"), entry[k]) != a["start"] + 2:
                problems.append(f"{app} {host}: typing 'AB' straight after Enter didn't write it on the next row ({first(a['written'].replace('Zed Co', 'AB'), entry[k])})")
            if "FIELD: Zed Co" not in entry_up[k]:
                problems.append(f"{app} {host}: the first value of the run wasn't kept (two rows up: {[l for l in entry_up[k].splitlines() if l.startswith('FIELD: ')]})")
            if first(a["cleared"], cleared[k]) != a["start"]:
                problems.append(f"{app} {host}: Delete didn't clear the text cell on row {a['start']} ({first(a['cleared'], cleared[k])})")
        for name, o in (("type", typed), ("onward", onward), ("escape", escaped), ("back", back), ("kept", kept), ("delete", cleared), ("entry", entry), ("entry-up", entry_up)):
            if shown(o[0]) != shown(o[1]):
                problems.append(f"{app} {name}: GTK and web differ: {sorted(set(shown(o[0])) ^ set(shown(o[1])))[:3]}")
    return not problems, "; ".join(problems) or "MX Studio and the Workbook on both hosts: typing replaces and Enter writes (selection moves down), Escape cancels, Delete clears, the keyboard returns to the grid; identical on GTK and web"


def m4():
    problems = []
    for name in ("m1", "m2", "m3", "m4", "m5"):
        ok, msg = getattr(g12, name)()
        if not ok:
            problems.append(f"goal 12 {name.upper()}: {msg[:300]}")
    return not problems, "; ".join(problems) or "goal 12's checks (and goals 3–11's inside them) pass"


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
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4)]:
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
