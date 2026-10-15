"""Milestone checker for GOAL.md (goal 2). Rebuilds from scratch, prints PASS/FAIL per milestone.

Run: scripts/check        (goal 1's checker is kept in docs/goals/01-check.py)
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
EXAMPLES = ["hello", "todo"]

# Apple system functions the apps may need. Anything else undefined fails M3/M4.
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
MAC_DYLIBS = {
    "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit",
    "/usr/lib/libobjc.A.dylib",
    "/usr/lib/libSystem.B.dylib",
}
IOS_DYLIBS = {
    "/System/Library/Frameworks/UIKit.framework/UIKit",
    "/usr/lib/libobjc.A.dylib",
    "/usr/lib/libSystem.B.dylib",
}
# Words that would mean platform code leaked into an app file.
PLATFORM_WORDS = re.compile(r"\b(objc|msg|external_call|gtk_\w*|Gtk\w*|NS[A-Z]\w*|UI[A-Z]\w*|AppKit|UIKit|adw_\w*)\b")


def run(cmd, env=None, timeout=600):
    e = dict(os.environ, **(env or {}))
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, env=e, timeout=timeout)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


# ---------- shared Apple checks (from goal 1) ----------

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
    plat = {"MACOS": "platform 1", "IOS": "platform 2"}[platform]
    if plat not in lc:
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
    return not problems, "; ".join(problems) or "arm64, entry _mojo_entry, 3 system libs, signature verified"


def apple_ok(example, platform):
    d = BUILD / example / platform
    objs = sorted(d.glob("*.o"))
    if not objs:
        return False, f"no objects in {d}"
    extra = undefined(objs) - ALLOWED
    if extra:
        return False, f"{example}: not allowed: {sorted(extra)}"
    if platform == "mac":
        app = next(d.glob("*.app"), None)
        if not app:
            return False, f"{example}: no .app"
        return bundle_ok(app, MAC_DYLIBS, "MACOS",
                         ["CFBundleExecutable", "CFBundleIdentifier", "CFBundlePackageType", "LSMinimumSystemVersion"])
    ipa = next(d.glob("*.ipa"), None)
    if not ipa:
        return False, f"{example}: no ipa"
    with tempfile.TemporaryDirectory() as tmp:
        zipfile.ZipFile(ipa).extractall(tmp)
        app = next((Path(tmp) / "Payload").glob("*.app"))
        for p in app.iterdir():
            if p.is_file() and not p.suffix and p.name != "PkgInfo":
                p.chmod(0o755)
        return bundle_ok(app, IOS_DYLIBS, "IOS",
                         ["CFBundleExecutable", "CFBundleIdentifier", "MinimumOSVersion", "LSRequiresIPhoneOS",
                          "UIApplicationSceneManifest", "UIDeviceFamily", "UILaunchScreen"])


# ---------- milestones ----------

def gtk_run(example, steps):
    exe = BUILD / example / "linux" / example
    if not exe.exists():
        return None, f"no {exe}"
    r = run([str(exe)], env={"MOJOUI_TEST": steps}, timeout=60)
    return r, (r.stdout + r.stderr)


def m1():
    r = run(["pixi", "run", "mojo", "run", "-I", ".", "tests/test_mojoui.mojo"])
    ok = r.returncode == 0 and "ALL TESTS PASSED" in r.stdout
    return ok, (r.stdout + r.stderr).strip()[-300:]


def m2():
    r, out = gtk_run("hello", "Greet,Greet,Greet")
    if r is None:
        return False, out
    ok = r.returncode == 0 and "LABEL: Hello, Ada! (click 3)" in out and "NATIVE: GTK" in out
    return ok, "real GtkButton tapped 3x, real GtkLabel reads 'Hello, Ada! (click 3)'" if ok else out.strip()[-400:]


def m3():
    return apple_ok("hello", "mac")


def m4():
    return apple_ok("hello", "ios")


def m5():
    problems = []
    for ex in EXAMPLES:
        src = ROOT / "examples" / ex / "app.mojo"
        if not src.exists():
            problems.append(f"no {src.relative_to(ROOT)}")
            continue
        code = "\n".join(l.split("#")[0] for l in src.read_text().splitlines())
        imports = re.findall(r"^\s*(?:from|import)\s+([\w.]+)", code, re.M)
        bad_imports = [i for i in imports if not i.startswith("mojoui")]
        leaks = sorted(set(PLATFORM_WORDS.findall(code)))
        if bad_imports or leaks:
            problems.append(f"{ex}: imports {bad_imports}, platform words {leaks}")
        want = sha(src)
        for plat in ("linux", "mac", "ios"):
            stamp = BUILD / ex / plat / "app.sha256"
            if not stamp.exists() or stamp.read_text().strip() != want:
                problems.append(f"{ex}/{plat} not built from the current app.mojo")
    return not problems, "; ".join(problems) or "app files import only mojoui; Linux, Mac and iPhone builds all compiled the identical file"


def m6():
    r, out = gtk_run("todo", "Add task,Add task,Add task,Remove@1")
    if r is None:
        return False, out
    labels = re.findall(r"^LABEL: (.*)$", out, re.M)
    ok = (r.returncode == 0 and "NATIVE: GTK" in out and "Task 1" in labels and "Task 3" in labels
          and "Task 2" not in labels and "2 tasks" in labels)
    if not ok:
        return False, out.strip()[-400:]
    for plat in ("mac", "ios"):
        ok, msg = apple_ok("todo", plat)
        if not ok:
            return False, f"todo {plat}: {msg}"
    return True, "GTK run: 3 adds + 1 remove → rows 'Task 1', 'Task 3', '2 tasks'; Mac and iPhone builds pass"


def m7():
    problems = []
    for doc in ("README.md", "apple/README.md"):
        p = ROOT / doc
        if not p.exists():
            problems.append(f"no {doc}")
            continue
        text = p.read_text()
        if "examples/hello/app.mojo" not in text:
            problems.append(f"{doc} doesn't show the declarative app")
        for ref in set(re.findall(r"`((?:apple|scripts|tests|examples|mojoui)/[^`\s]*)`", text)):
            if not (ROOT / ref).exists():
                problems.append(f"{doc}: missing {ref}")
    readme = (ROOT / "README.md").read_text() if (ROOT / "README.md").exists() else ""
    for plat in ("Linux", "Mac", "iPhone"):
        if plat not in readme:
            problems.append(f"README.md has no {plat} instructions")
    return not problems, "; ".join(problems) or "README.md + apple/README.md cover Linux, Mac, iPhone; all paths exist"


def main():
    for ex in EXAMPLES:
        shutil.rmtree(BUILD / ex, ignore_errors=True)
    for ex in EXAMPLES:
        b = run(["scripts/build.sh", ex, "all"], timeout=1800)
        if b.returncode != 0:
            print(f"build {ex} failed:\n" + (b.stdout + b.stderr)[-1500:])
    results = []
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5), ("M6", m6), ("M7", m7)]:
        try:
            ok, msg = fn()
        except Exception as e:  # a crashing check is a failing check
            ok, msg = False, f"check crashed: {e!r}"
        results.append(ok)
        print(f"{'PASS' if ok else 'FAIL'}  {name}  {msg}")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
