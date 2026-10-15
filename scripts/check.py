"""Milestone checker for GOAL.md (goal 4; goal 3's checks run as M10). Rebuilds from scratch, prints PASS/FAIL per milestone.

Run: scripts/check   (earlier goals' checkers: docs/goals/0N-check.py)

Interaction tests use one step language for every host (see scripts/drive.py):
  tap:Greet  tap:Remove@1  type:New task=Buy milk  submit:New task
  toggle:Dark mode  select:0=Done  slide:0=75
Each host then reports the real widgets' state as lines: LABEL/BUTTON/FIELD/
TOGGLE/DROPDOWN/SLIDER/PROGRESS, in screen order.
"""

import hashlib
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
sys.path.insert(0, str(ROOT / "scripts"))
EXAMPLES = ["hello", "gallery", "todo", "gpu", "kitchen", "expenses"]
NATIVE_APPLE = ["hello", "gallery", "todo", "kitchen", "expenses"]

ALLOWED = {
    # libobjc
    "_objc_getClass", "_objc_getProtocol", "_sel_registerName", "_objc_allocateClassPair",
    "_objc_registerClassPair", "_class_addMethod", "_class_addProtocol", "_objc_autoreleasePoolPush",
    # libSystem
    "_dlsym", "_dup", "_fclose", "_fdopen", "_fflush", "_memcpy", "_memmove", "_memset", "_bzero",
    "_strlen", "_write", "_posix_memalign", "_free",
    # UIKit
    "_UIApplicationMain",
}
MAC_DYLIBS = {"/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit", "/usr/lib/libobjc.A.dylib", "/usr/lib/libSystem.B.dylib"}
IOS_DYLIBS = {"/System/Library/Frameworks/UIKit.framework/UIKit", "/usr/lib/libobjc.A.dylib", "/usr/lib/libSystem.B.dylib"}
PLATFORM_WORDS = re.compile(r"\b(objc|msg|external_call|gtk_\w*|Gtk\w*|NS[A-Z]\w*|UI[A-Z]\w*|AppKit|UIKit|adw_\w*|fasthtml|htmx|jni\w*|JNI\w*|android)\b")


def run(cmd, env=None, timeout=900):
    e = dict(os.environ, **(env or {}))
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, env=e, timeout=timeout)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


STATE_KINDS = "LABEL|BUTTON|FIELD|TOGGLE|DROPDOWN|SLIDER|PROGRESS|IMAGE|SEGMENTED|RADIO|TEXTAREA|ALERT|TABS|NAV|DATE|ICON|GRID|LIST"


def state(out):
    return [l for l in out.splitlines() if re.match(rf"^({STATE_KINDS}): ", l)]


# ---------- hosts ----------

def gtk(example, steps, shot=None):
    exe = BUILD / example / "linux" / example
    if not exe.exists():
        return None, f"no {exe}"
    env = {"MOJOUI_TEST": steps}
    if shot:
        env["MOJOUI_SHOT"] = shot
    r = run([str(exe)], env=env, timeout=120)
    out = r.stdout + r.stderr
    if r.returncode != 0 or "CRITICAL" in out or "TEST: " in out:  # GTK warnings or a step that didn't apply
        return None, f"GTK run failed (exit {r.returncode}):\n{out[-600:]}"
    return r, out


def web(example, steps, shot=None):
    import drive  # scripts/drive.py: starts the FastHTML host, drives Chromium
    try:
        r, out = drive.web_run(BUILD / example / "web", steps, shot=shot)
    except Exception as e:  # a crashing run is a failing run
        return None, f"web run crashed: {e!r}"
    if r.returncode != 0:  # page errors
        return None, out[-600:]
    return r, out


# ---------- Apple checks (from goals 1–2) ----------

def undefined(objs):
    out = run(["llvm-nm", "-u", "-j", *map(str, objs)]).stdout.split()
    defined = set(run(["llvm-nm", "-j", "--defined-only", *map(str, objs)]).stdout.split())
    return {s for s in out if s not in defined and not s.endswith(":")}


def bundle_ok(app, want_dylibs, platform, plist_keys):
    plist_path = app / ("Contents/Info.plist" if platform == "MACOS" else "Info.plist")
    if not plist_path.exists():
        return False, f"missing {plist_path}"
    plist = plistlib.loads(plist_path.read_bytes())
    exe = app / ("Contents/MacOS" if platform == "MACOS" else ".") / plist.get("CFBundleExecutable", "?")
    if not exe.exists():
        return False, f"missing {exe}"
    desc = run(["file", str(exe)]).stdout
    lc = run(["llvm-otool", "-l", str(exe)]).stdout
    problems = []
    if "Mach-O 64-bit arm64 executable" not in desc:
        problems.append(f"not an arm64 executable: {desc.strip()}")
    if {"MACOS": "platform 1", "IOS": "platform 2"}[platform] not in lc:
        problems.append(f"platform is not {platform}")
    entry = re.search(r"entryoff (\d+)", lc)
    m = re.search(r"^([0-9a-f]+) T _mojo_entry$", run(["llvm-nm", "--defined-only", str(exe)]).stdout, re.M)
    if not entry or not m or int(m.group(1), 16) - 0x100000000 != int(entry.group(1)):
        problems.append("entry point is not _mojo_entry")
    libs = set(re.findall(r"cmd LC_LOAD_DYLIB\n\s+cmdsize \d+\n\s+name (\S+)", lc))
    if libs != want_dylibs:
        problems.append(f"dylibs {sorted(libs)} != {sorted(want_dylibs)}")
    missing = [k for k in plist_keys if k not in plist]
    if missing:
        problems.append(f"Info.plist missing {missing}")
    seal = app / ("Contents/_CodeSignature/CodeResources" if platform == "MACOS" else "_CodeSignature/CodeResources")
    r = run([sys.executable, "scripts/verify_signature.py", str(exe), str(plist_path), str(seal)])
    if r.returncode != 0:
        problems.append(f"signature: {(r.stdout + r.stderr).strip()[-200:]}")
    return not problems, "; ".join(problems)


def apple_ok(example, platform):
    d = BUILD / example / platform
    objs = sorted(d.glob("*.o"))
    if not objs:
        return False, f"{example}/{platform}: no objects"
    extra = undefined(objs) - ALLOWED
    if extra:
        return False, f"{example}/{platform}: not allowed: {sorted(extra)}"
    if platform == "mac":
        app = next(d.glob("*.app"), None)
        if not app:
            return False, f"{example}: no .app"
        ok, msg = bundle_ok(app, MAC_DYLIBS, "MACOS", ["CFBundleExecutable", "CFBundleIdentifier", "CFBundlePackageType", "LSMinimumSystemVersion"])
        return ok, f"{example}/mac: {msg}"
    ipa = next(d.glob("*.ipa"), None)
    if not ipa:
        return False, f"{example}: no ipa"
    with tempfile.TemporaryDirectory() as tmp:
        zipfile.ZipFile(ipa).extractall(tmp)
        app = next((Path(tmp) / "Payload").glob("*.app"))
        for p in app.iterdir():
            if p.is_file() and not p.suffix and p.name != "PkgInfo":
                p.chmod(0o755)
        ok, msg = bundle_ok(app, IOS_DYLIBS, "IOS", ["CFBundleExecutable", "CFBundleIdentifier", "MinimumOSVersion",
                                                      "LSRequiresIPhoneOS", "UIApplicationSceneManifest", "UIDeviceFamily", "UILaunchScreen"])
        return ok, f"{example}/ios: {msg}"


def same_source(example, platforms):
    want = sha(ROOT / "examples" / example / "app.mojo")
    bad = [p for p in platforms if not (BUILD / example / p / "app.sha256").exists()
           or (BUILD / example / p / "app.sha256").read_text().strip() != want]
    return bad


# ---------- milestones ----------

def g3_m1():
    r, out = web("hello", "tap:Greet;tap:Greet;tap:Greet")
    if r is None:
        return False, out
    if "LABEL: Hello, Ada! (click 3)" not in state(out) or same_source("hello", ["web", "linux"]):
        return False, out[-500:]
    # Goal 2's checks, kept: the GTK hello still works and GTK really draws its window.
    with tempfile.TemporaryDirectory() as tmp:
        shot = str(Path(tmp) / "hello.png")
        r, gout = gtk("hello", "tap:Greet;tap:Greet;tap:Greet", shot=shot)
        if r is None or "LABEL: Hello, Ada! (click 3)" not in state(gout):
            return False, f"GTK hello regressed: {gout[-300:]}"
        data = Path(shot).read_bytes() if Path(shot).exists() else b""
        if not data.startswith(b"\x89PNG") or len(data) < 5000:
            return False, "GTK didn't draw the hello window"
    return True, "Chromium clicked Greet 3x on the FastHTML page → 'Hello, Ada! (click 3)'; GTK hello still passes and draws"


def g3_m2():
    r = run(["pixi", "run", "mojo", "run", "-I", ".", "tests/test_mojoui.mojo"])
    out = r.stdout + r.stderr
    needed = ["TextField", "Toggle", "Dropdown", "Slider", "ProgressBar", "Divider", "Scroll"]
    view = (ROOT / "mojoui/view.mojo").read_text()
    tests = (ROOT / "tests/test_mojoui.mojo").read_text()
    missing = [c for c in needed if f"def {c}(" not in view or f"{c}(" not in tests]
    png = run(["pixi", "run", "mojo", "run", "-I", ".", "tests/test_png.mojo"])  # the encoder Mac/iPhone images use
    ok = r.returncode == 0 and "ALL TESTS PASSED" in out and not missing and "PNG TESTS PASSED" in png.stdout
    return ok, "core + PNG tests pass; every component built and tested" if ok else f"missing {missing}; {out[-300:]}{png.stdout[-200:]}"


GALLERY_STEPS = ("type:Your name=Grace;toggle:Notifications;select:0=Large;slide:0=70;tap:Reset@0;"
                 "type:Your name=Ada;submit:Your name")
GALLERY_EXPECT = ["LABEL: Hello, Ada", "FIELD: Ada", "TOGGLE: Notifications=on", "LABEL: Notifications are on",
                  "DROPDOWN: Large", "LABEL: Volume 70", "SLIDER: 70", "PROGRESS: 70", "IMAGE: 120x40",
                  "BUTTON: Say hello (1)"]


def gallery_ok(out):
    s = state(out)
    missing = [e for e in GALLERY_EXPECT if e not in s]
    return not missing, missing


def g3_m3():
    r, out = gtk("gallery", GALLERY_STEPS)
    if r is None:
        return False, out
    ok, missing = gallery_ok(out)
    ok = ok and not same_source("gallery", ["linux"])
    return ok, "GTK: typed, toggled, chose, slid, pressed Return on real widgets; every echo label right" if ok else f"missing {missing}: {out[-500:]}"


def g3_m4():
    r, out = web("gallery", GALLERY_STEPS)
    if r is None:
        return False, out
    ok, missing = gallery_ok(out)
    ok = ok and not same_source("gallery", ["web"])
    return ok, "Chromium: same interactions, same echoed state" if ok else f"missing {missing}: {out[-500:]}"


def g3_m5():
    problems = []
    for ex in NATIVE_APPLE:
        for plat in ("mac", "ios"):
            ok, msg = apple_ok(ex, plat)
            if not ok:
                problems.append(msg)
        bad = same_source(ex, ["mac", "ios"])
        if bad:
            problems.append(f"{ex}: {bad} not built from current app.mojo")
    return not problems, "; ".join(problems) or "hello, gallery, todo: Mac + iPhone build, link, sign; only Apple system functions"


# "enter:" = type and press Return with no pause (the race the review found).
TODO_STEPS = ("enter:What needs doing?=Buy milk;type:What needs doing?=Walk the dog;tap:Add;"
              "enter:What needs doing?=Write Mojo;enter:What needs doing?=Feed the cat;"
              "toggle:Buy milk;toggle:Feed the cat;select:0=Active;tap:Remove@0;"
              "select:0=Done;tap:Clear done;select:0=All;type:What needs doing?=Just a draft")
# The last step types without submitting: it must stay a draft, not become a task.
TODO_EXPECT = ["TOGGLE: Write Mojo=off", "DROPDOWN: All", "LABEL: 1 left · 0 done", "PROGRESS: 0", "FIELD: Just a draft"]
TODO_GONE = ["Buy milk", "Walk the dog", "Feed the cat", "TOGGLE: Just a draft"]


def g3_m6():
    problems = []
    r1, gout = gtk("todo", TODO_STEPS)
    r2, wout = web("todo", TODO_STEPS)
    if r1 is None or r2 is None:
        return False, (gout if r1 is None else wout)[-400:]
    gs, ws = state(gout), state(wout)
    if "NATIVE: GTK" not in gout or "NATIVE: Chromium" not in wout:
        problems.append("a run didn't report its native toolkit")
    missing = [e for e in TODO_EXPECT if e not in gs]
    if missing:
        problems.append(f"GTK missing {missing}")
    if any(t in l for l in gs for t in TODO_GONE):
        problems.append("a removed or cleared task is still shown")
    if gs != ws:
        problems.append(f"GTK and web differ:\n  gtk={gs}\n  web={ws}")
    for plat in ("mac", "ios"):
        ok, msg = apple_ok("todo", plat)
        if not ok:
            problems.append(msg)
    for src in sorted((ROOT / "examples").glob("*/app.mojo")):  # every app that exists
        ex = src.parent.name
        code = "\n".join(l.split("#")[0] for l in src.read_text().splitlines())
        bad_imports = [i for i in re.findall(r"^\s*(?:from|import)\s+([\w.]+)", code, re.M) if not i.startswith("mojoui")]
        leaks = sorted(set(PLATFORM_WORDS.findall(code)))
        if bad_imports or leaks:
            problems.append(f"{ex}: imports {bad_imports}, platform words {leaks}")
    bad = [str(p.relative_to(ROOT)) for d in ("mojoui", "hosts", "examples", "apple")
           for p in (ROOT / d).rglob("*") if p.suffix in {".c", ".m", ".swift", ".h"}]
    if bad:
        problems.append(f"foreign sources: {bad}")
    if same_source("todo", ["linux", "web", "mac", "ios"]):
        problems.append("todo builds not all from the current app.mojo")
    return not problems, "; ".join(problems) or "todo: GTK and Chromium give identical state; Mac + iPhone build; apps import only mojoui"


def g3_m7():
    so = BUILD / "todo" / "android" / "lib" / "arm64-v8a" / "libmojoui.so"
    doc = ROOT / "docs" / "android.md"
    if so.exists():
        desc = run(["file", str(so)]).stdout
        syms = run(["llvm-nm", "-D", "--defined-only", str(so)]).stdout
        ok = "ELF 64-bit LSB shared object, ARM aarch64" in desc and ("ANativeActivity_onCreate" in syms or "JNI_OnLoad" in syms)
        if ok and not same_source("todo", ["android"]):
            apk = next((BUILD / "todo" / "android").glob("*.apk"), None)
            return True, f"todo for Android arm64: {so.name} with a native entry point" + (f"; APK {apk.name}" if apk else "; no APK yet (see docs/android.md)")
        return False, f"android library not right: {desc.strip()[:120]}"
    if doc.exists() and re.search(r"^Status: blocked", doc.read_text(), re.M):
        return True, "Android blocked, with evidence in docs/android.md"
    return False, "no Android build and no docs/android.md"


def g3_m8():
    problems = []
    r1, gout = gtk("gpu", "tap:Run on GPU")
    r2, wout = web("gpu", "tap:Run on GPU")
    for name, r, out in (("GTK", r1, gout), ("web", r2, wout)):
        if r is None:
            problems.append(f"{name}: {out[-200:]}")
            continue
        s = state(out)
        if (not any(l.startswith("LABEL: GPU: NVIDIA") for l in s)
                or not any(l.startswith("LABEL: Result:") and "✓" in l for l in s)
                or "IMAGE: 480x320" not in s):
            problems.append(f"{name}: no GPU result or picture in {s}")
    # Without a GPU the app must explain itself, not crash.
    exe = BUILD / "gpu" / "linux" / "gpu"
    r = run([str(exe)], env={"MOJOUI_TEST": "tap:Run on GPU", "CUDA_VISIBLE_DEVICES": ""}, timeout=120)
    if r.returncode != 0 or "LABEL: GPU: no GPU found" not in r.stdout or "CRITICAL" in r.stdout + r.stderr:
        problems.append(f"no-GPU run failed (exit {r.returncode}): {(r.stdout + r.stderr)[-300:]}")
    return not problems, "; ".join(problems) or "GPU kernel ran on the NVIDIA GPU; result shown in GTK and web, verified against the CPU; no-GPU run degrades gracefully"


def g3_m9():
    problems = []
    readme = (ROOT / "README.md").read_text()
    for word in ("Linux", "Mac", "iPhone", "Web", "Android", "GPU", "TextField", "Dropdown", "examples/todo/app.mojo"):
        if word not in readme:
            problems.append(f"README.md doesn't mention {word}")
    for doc in ("README.md", "apple/README.md"):
        for ref in set(re.findall(r"`((?:apple|scripts|tests|examples|mojoui|hosts|docs)/[^`\s]*)`", (ROOT / doc).read_text())):
            if not (ROOT / ref).exists():
                problems.append(f"{doc}: missing {ref}")
    return not problems, "; ".join(problems) or "README covers every platform and component; all paths exist"


# ---------- goal 4 ----------

KITCHEN_STEPS = ("segment:0=Week;radio:0=Large;tab:0=Text;textarea:0=Line one\\nLine two;tab:0=More;"
                 "date:0=2026-12-25;tap:Delete everything;alert:Cancel;tap:Delete everything;alert:Delete;"
                 "tab:0=Choices;tap:Open details;back;tab:0=List;scroll:0=7500;row:0=7500")
KITCHEN_SUMMARY = "LABEL: Week · Large · 2 lines · 2026-12-25 · deleted 1 · details 1 · row 7500"


def both(example, steps):
    """Runs steps on GTK and web; returns (problems, gtk_state, web_state, gtk_out)."""
    r1, gout = gtk(example, steps)
    r2, wout = web(example, steps)
    if r1 is None or r2 is None:
        return [(gout if r1 is None else wout)[-500:]], [], [], ""
    gs, ws = state(gout), state(wout)
    problems = [] if gs == ws else [f"GTK and web differ:\n  gtk={gs}\n  web={ws}"]
    if same_source(example, ["linux", "web"]):
        problems.append(f"{example}: builds not from the current app.mojo")
    return problems, gs, ws, gout


def kitchen_has(expected, steps=KITCHEN_STEPS):
    problems, gs, _, _ = both("kitchen", steps)
    missing = [e for e in expected if e not in gs]
    if missing:
        problems.append(f"missing {missing} in {gs}")
    return not problems, "; ".join(problems)


def m1():
    ok, msg = kitchen_has(["SEGMENTED: Week", "RADIO: Large", "LABEL: Period: Week · Size: Large"], "segment:0=Week;radio:0=Large")
    return ok, msg or "Segmented + Radio: chosen on GTK and web, echoed, identical"


def m2():
    ok, msg = kitchen_has(["TEXTAREA: Line one\\nLine two", "LABEL: 2 lines, 17 characters"], "tab:0=Text;textarea:0=Line one\\nLine two")
    return ok, msg or "TextArea: two lines typed and echoed on GTK and web, identical"


def m3():
    ok, msg = kitchen_has(["ALERT: Delete everything? | This can't be undone. | Cancel, Delete"], "tab:0=More;tap:Delete everything")
    if not ok:
        return ok, msg
    ok, msg = kitchen_has(["LABEL: Deleted 1 time"], "tab:0=More;tap:Delete everything;alert:Cancel;tap:Delete everything;alert:Delete")
    if not ok:
        return ok, msg
    # Escape must answer like Cancel (not leave the app stuck), on both.
    ok, msg = kitchen_has(["LABEL: Deleted 1 time"], "tab:0=More;tap:Delete everything;alert:Escape;tap:Delete everything;alert:Delete")
    if not ok:
        return ok, f"Escape: {msg}"
    # And the GTK alert really appears on screen (not just driven unseen).
    with tempfile.TemporaryDirectory() as tmp:
        r, out = gtk("kitchen", "tab:0=More;tap:Delete everything", shot=str(Path(tmp) / "a.png"))
        if r is None or "ALERTSHOWN: yes" not in out:
            return False, f"GTK alert wasn't shown on screen: {out[-300:]}"
    return True, "Alert shown on screen while in the view; Cancel, Delete and Escape answered on GTK and web, identical"


def m4():
    ok, msg = kitchen_has(["NAV: Details (back)", "LABEL: This is the details screen."], "tap:Open details")
    if not ok:
        return ok, msg
    ok, msg = kitchen_has(["TABS: More", "LABEL: Details opened 1 time"], "tap:Open details;back;tab:0=More")
    return ok, msg or "Tabs switch sections; NavBar opens a screen and Back returns, on GTK and web, identical"


def m5():
    ok, msg = kitchen_has(["DATE: 2026-12-25", "LABEL: Date: 2026-12-25"], "tab:0=More;date:0=2026-12-25")
    return ok, msg or "DatePicker set on GTK and web; event carried 2026-12-25; identical"


def m6():
    ok, msg = kitchen_has(["ICON: star", "ICON: trash", "ICON: gear"], "tab:0=More")
    return ok, msg or "Icons: star, trash, gear shown with each platform's own icons"


def m7():
    ok, msg = kitchen_has(["GRID: 3 columns, 6 items", "LABEL: Cell 6"], "tab:0=More")
    return ok, msg or "Grid: 6 items in rows of 3 on GTK and web"


def m8():
    problems, gs, _, gout = both("kitchen", "tab:0=List;scroll:0=7500;row:0=7500")
    if "LIST: 10000 rows" not in gs or "LABEL: Tapped row 7500" not in gs:
        problems.append(f"list state wrong: {gs}")
    built = [int(x) for x in re.findall(r"^LISTBUILT: (\d+)$", gout, re.M)]
    if not built or max(built) >= 500:
        problems.append(f"GTK built {built} rows; must build far fewer than 10,000")
    _, wout = web("kitchen", "tab:0=List;scroll:0=7500;row:0=7500")
    in_page = [int(x) for x in re.findall(r"^LISTROWS: (\d+)$", wout or "", re.M)]
    if not in_page or max(in_page) >= 100:
        problems.append(f"web page held {in_page} rows; must hold far fewer than 10,000")
    return not problems, "; ".join(problems) or (f"10,000-row list: scrolled to and tapped row 7500 on GTK and web; GTK made {max(built)} row widgets "
                                                 f"(its recycling cache), the web page held {max(in_page)} rows")


EXPENSES_STEPS = ("type:Amount=12.50;segment:0=Travel;date:0=2026-10-01;textarea:0=Taxi to the airport;tap:Add expense;"
                  "tab:0=History;row:0=0;tap:Delete;alert:Cancel;tap:Delete;alert:Delete;tab:0=Insights")


def m9():
    t = run(["pixi", "run", "mojo", "run", "-I", "examples/expenses", "-I", ".", "tests/test_expenses.mojo"])
    if "EXPENSES TESTS PASSED" not in t.stdout:
        return False, f"expenses unit tests: {(t.stdout + t.stderr)[-300:]}"
    problems, gs, _, _ = both("expenses", EXPENSES_STEPS)
    if "TABS: Insights" not in gs or not any(l.startswith("LABEL: Total: ") and "5000 expenses" in l for l in gs):
        problems.append(f"expenses end state wrong: {gs}")
    if not any(l.startswith("ICON: ") for l in gs) or not any(l.startswith("GRID: ") for l in gs):
        problems.append("Insights should show icons in a grid")
    r1, gout = gtk("expenses", "type:Amount=12.50;segment:0=Travel;tap:Add expense;tab:0=History")
    if r1 is None or not any("Travel" in l and "12.50" in l for l in state(gout)):
        problems.append(f"added expense not at the top of History: {state(gout) if r1 else gout[-300:]}")
    for plat in ("mac", "ios"):
        ok, msg = apple_ok("expenses", plat)
        if not ok:
            problems.append(msg)
    return not problems, "; ".join(problems) or "Expenses app: add → history → detail → confirm delete → insights; GTK and web identical; Mac + iPhone build"


def m10():
    problems = []
    for name, fn in [("M1", g3_m1), ("M2", g3_m2), ("M3", g3_m3), ("M4", g3_m4), ("M5", g3_m5), ("M6", g3_m6),
                     ("M7", g3_m7), ("M8", g3_m8)]:
        ok, msg = fn()
        if not ok:
            problems.append(f"goal 3 {name}: {msg[:200]}")
    for plat in ("mac", "ios"):
        ok, msg = apple_ok("kitchen", plat)
        if not ok:
            problems.append(msg)
    return not problems, "; ".join(problems) or "goal 3's M1–M8 still pass; kitchen builds for Mac + iPhone"


def m11():
    problems = []
    readme = (ROOT / "README.md").read_text()
    for c in ("Segmented", "Radio", "TextArea", "Alert", "Tabs", "NavBar", "DatePicker", "Icon", "Grid", "LazyList",
              "examples/expenses/app.mojo"):
        if c not in readme:
            problems.append(f"README.md doesn't mention {c}")
    ok, msg = g3_m9()
    if not ok:
        problems.append(msg)
    return not problems, "; ".join(problems) or "README covers every component and the expenses app; all paths exist"


def main():
    for ex in EXAMPLES:
        shutil.rmtree(BUILD / ex, ignore_errors=True)
    for ex in EXAMPLES:
        if not (ROOT / "examples" / ex / "app.mojo").exists():
            continue
        b = run(["scripts/build.sh", ex, "all"], timeout=3600)
        if b.returncode != 0:
            print(f"build {ex} failed:\n" + (b.stdout + b.stderr)[-1500:])
    results = []
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5), ("M6", m6), ("M7", m7),
                     ("M8", m8), ("M9", m9), ("M10", m10), ("M11", m11)]:
        try:
            ok, msg = fn()
        except Exception as e:  # a crashing check is a failing check
            ok, msg = False, f"check crashed: {e!r}"
        results.append(ok)
        print(f"{'PASS' if ok else 'FAIL'}  {name}  {msg}")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
