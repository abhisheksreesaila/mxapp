"""Archived milestone checker (goal 7: Android; goal 6's checks run as M7, earlier goals' inside them).
Rebuilds from scratch, prints PASS/FAIL per milestone.

Run: scripts/check   (earlier goals' checkers: docs/goals/0N-check.py)

Android runs use the emulator (AVD "mojoui", started headless if needed) and real input
from adb (scripts/android_drive.py), with the same step language as GTK and the web.
"""

import importlib.util
import re
import subprocess
import sys
from pathlib import Path

ROOT = next(p for p in Path(__file__).resolve().parents if (p / "pixi.toml").exists())  # (archived in docs/goals/)
sys.path.insert(0, str(ROOT / "scripts"))

_spec = importlib.util.spec_from_file_location("goal6", ROOT / "docs/goals/06-check.py")
g6 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g6)
g5 = g6.g5
run, gtk, state, BUILD = g6.run, g6.gtk, g6.state, g6.BUILD

import android_drive  # noqa: E402

EXAMPLES = g6.EXAMPLES
SDK = android_drive.SDK
ANDROID_LIBS = {"libc.so", "liblog.so", "libm.so", "libdl.so"}
# What a libmojoui.so may ask Android's system libraries for (bionic libc, libm, liblog).
ANDROID_SYMBOLS = {"__android_log_write", "clock_gettime", "cos", "sin", "dup", "fclose", "fdopen", "fflush", "free",
                   "memcpy", "memmove", "memset", "posix_memalign", "strlen", "write"}
SHOWN = r"^(LABEL|BUTTON|FIELD|TOGGLE|DROPDOWN|SLIDER|PROGRESS|IMAGE|SEGMENTED|TABS|RADIO): "


def shown_state(out):
    return [l for l in out.splitlines() if re.match(SHOWN, l)]


def droid(example, steps, shot=None, **kw):
    try:
        r, out = android_drive.android_run(example, steps, shot=shot, **kw)
    except Exception as e:  # a crashing run is a failing run
        return None, f"android run crashed: {e!r}"
    if r.returncode != 0:
        return None, out[-600:]
    return r, out


def build_tools():
    return sorted((SDK / "build-tools").iterdir())[-1]


# ---------- milestones ----------

def m1():
    problems = []
    apk = next((BUILD / "hello" / "android").glob("*.apk"), None)
    if apk is None:
        return False, "no hello APK"
    v = subprocess.run([str(build_tools() / "apksigner"), "verify", str(apk)], capture_output=True, text=True)
    if v.returncode != 0:
        problems.append(f"apksigner: {v.stderr.strip()[-200:]}")
    names = subprocess.run(["unzip", "-Z1", str(apk)], capture_output=True, text=True).stdout.split()
    for want in ("classes.dex", "AndroidManifest.xml", "lib/arm64-v8a/libmojoui.so", "lib/x86_64/libmojoui.so"):
        if want not in names:
            problems.append(f"APK lacks {want}")
    javas = [p for d in ("mojoui", "hosts", "examples", "apple") for p in (ROOT / d).rglob("*.java")]
    if [str(p.relative_to(ROOT)) for p in javas] != ["mojoui/hosts/android/MojoActivity.java"]:
        problems.append(f"Java files should be just the framework's one: {javas}")
    elif len(javas[0].read_text().splitlines()) > 80:
        problems.append(f"MojoActivity.java is {len(javas[0].read_text().splitlines())} lines (> 80)")
    for ex in ("hello", "gallery", "todo", "layout", "lens"):
        for abi in ("arm64-v8a", "x86_64"):
            so = BUILD / ex / "android" / "lib" / abi / "libmojoui.so"
            if not so.exists():
                problems.append(f"{ex}: no {abi} library")
                continue
            needed = set(re.findall(r"\(NEEDED\).*\[(.+?)\]", run(["llvm-readelf", "-d", str(so)]).stdout))
            undefined = set(run(["llvm-nm", "-D", "--undefined-only", "-j", str(so)]).stdout.split())
            if not needed <= ANDROID_LIBS:
                problems.append(f"{ex}/{abi} needs {sorted(needed - ANDROID_LIBS)}")
            if not undefined <= ANDROID_SYMBOLS:
                problems.append(f"{ex}/{abi} uses {sorted(undefined - ANDROID_SYMBOLS)}")
    return not problems, "; ".join(problems) or (
        "signed APKs (arm64-v8a + x86_64), one framework Java file (≤ 80 lines), libraries need only Android's libc/libm/liblog")


def m2():
    r, out = droid("hello", "tap:Greet;tap:Greet;tap:Greet", shot=str(BUILD / "hello" / "android.png"))
    if r is None:
        return False, out
    if "LABEL: Hello, Ada! (click 3)" not in out or "BUTTON: Greet" not in out:
        return False, f"after 3 real taps: {shown_state(out)}"
    return True, "hello APK runs on Android 16 (emulator); 3 real taps → 'Hello, Ada! (click 3)' in a real TextView"


def same_as_gtk(example, steps, name):
    r, out = droid(example, steps)
    if r is None:
        return False, out
    rg, gout = gtk(example, steps)
    if rg is None:
        return False, gout
    a, g = shown_state(out), [l for l in state(gout) if re.match(SHOWN, l)]
    if a != g:
        return False, f"{name}: Android and GTK differ:\n  android {a}\n  gtk     {g}"
    return True, f"{name}: {len(a)} views identical to GTK after real input"


def m3():
    return same_as_gtk("gallery", g5.GALLERY_STEPS, "gallery (typing, Return, switch, dropdown, slider, reset)")


def m4():
    return same_as_gtk("todo", g5.TODO_STEPS, "todo (goal 3's steps)")


def m5():
    # At 300 dpi the whole example fits on screen (uiautomator reports only views on screen);
    # the rules are in dp, so the density doesn't change them.
    r, out = droid("layout", "tab:0=Boxes", dpi=300)
    if r is None:
        return False, out
    rt, tout = droid("layout", "tab:0=About;tab:0=Boxes;tab:0=About")  # switching tabs really switches (real taps)
    if rt is None or "TABS: About" not in tout:
        return False, f"tapping another tab didn't switch: {shown_state(tout or '')[:3]}"
    saved = dict(g5._layout_cache)
    g5._layout_cache.clear()
    g5._layout_cache["android"] = (True, g5.boxes(out))
    problems = []
    try:
        for name in ("m2", "m3", "m4", "m5", "m6", "m7"):  # goal 5's relations, measured on Android
            ok, msg = getattr(g5, name)()
            if not ok:
                problems.append(f"goal 5 {name.upper()}: {msg}")
    finally:
        g5._layout_cache.clear()
        g5._layout_cache.update(saved)
    return not problems, "; ".join(problems) or "padding, fixed/min/max sizes, fill, grow, justify and align hold on Android (real view bounds, dp)"


def m6():
    problems = []
    shot = BUILD / "lens" / "android.png"
    r, out = droid("lens", "", shot=str(shot), landscape=True, dpi=200)
    if r is None:
        return False, out
    try:
        from PIL import Image
        img = Image.open(shot).convert("RGB")
        w, h = img.size
        # The canvas side: mostly painted (not the empty background) with a real gradient. (2M points on the
        # CPU path give a few dozen density levels, so a colour count alone isn't the measure; D-70.)
        pixels = list(img.crop((w // 3, h // 6, w * 9 // 10, h * 5 // 6)).getdata())
        background = max(set(pixels), key=pixels.count)
        painted = sum(1 for p in pixels if sum(abs(a - b) for a, b in zip(p, background)) > 30) / len(pixels)
        colours = len(set(pixels))
        if painted < 0.15 or colours < 20:  # (a blank canvas is ~0% painted; the lens ~26%)
            problems.append(f"canvas looks blank ({painted:.0%} painted, {colours} colours)")
    except Exception as e:
        problems.append(f"screenshot unreadable: {e!r}")
    view = lambda o: next((l for l in o.splitlines() if l.startswith("LABEL: View:")), None)
    r2, moved = droid("lens", "drag:0=96,48", landscape=True, dpi=200)
    rg, gmoved = gtk("lens", "drag:0=96,48")
    if r2 is None or rg is None:
        return False, (moved if r2 is None else gmoved)[-300:]
    if not view(moved) or view(moved) != view(gout := gmoved) or view(moved) == view(out):
        problems.append(f"a real swipe should pan like GTK's drag: android {view(moved)} vs gtk {view(gout)} (start {view(out)})")
    return not problems, "; ".join(problems) or f"lens on Android (CPU, 2M trips) draws the map; a real swipe pans it as on GTK: {view(moved)}"


def m7():
    problems = []
    for name in ("m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8"):
        ok, msg = getattr(g6, name)()
        if not ok:
            problems.append(f"goal 6 {name.upper()}: {msg[:200]}")
    return not problems, "; ".join(problems) or "goal 6's checks (and goals 3–5's inside them) still pass"


def m8():
    problems = []
    readme = (ROOT / "README.md").read_text()
    android = (ROOT / "docs/android.md").read_text()
    if not re.search(r"\*\*Android\*\*[^\n]*runs", readme):
        problems.append("README status doesn't say Android runs")
    for word in ("MojoActivity.java", "JNI", "emulator", "scripts/android_drive.py"):
        if word not in android:
            problems.append(f"docs/android.md doesn't mention {word}")
    imgs = re.findall(r"\]\((img/android[^)]*\.png)\)", android)
    if not imgs or any(not (ROOT / "docs" / i).exists() for i in imgs):
        problems.append(f"docs/android.md screenshots missing: {imgs}")
    ok, msg = g6.m9()
    if not ok:
        problems.append(msg)
    return not problems, "; ".join(problems) or "README and docs/android.md describe what runs on Android, with screenshots"


def main():
    import shutil
    for ex in EXAMPLES:
        shutil.rmtree(BUILD / ex, ignore_errors=True)
    for ex in EXAMPLES:
        if not (ROOT / "examples" / ex / "app.mojo").exists():
            continue
        b = run(["scripts/build.sh", ex, "all"], timeout=3600)
        if b.returncode != 0:
            print(f"build {ex} failed:\n" + (b.stdout + b.stderr)[-1500:])
        if ex in ("hello", "gallery", "layout", "lens"):  # ("all" means their platforms file, or Linux/web/Apple)
            a = run(["scripts/build.sh", ex, "android"], timeout=3600)
            if a.returncode != 0:
                print(f"android build {ex} failed:\n" + (a.stdout + a.stderr)[-1500:])
    results = []
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5), ("M6", m6), ("M7", m7), ("M8", m8)]:
        try:
            ok, msg = fn()
        except Exception as e:  # a crashing check is a failing check
            ok, msg = False, f"check crashed: {e!r}"
        results.append(ok)
        print(f"{'PASS' if ok else 'FAIL'}  {name}  {msg}")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
