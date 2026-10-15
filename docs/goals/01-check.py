"""Milestone checker for GOAL.md. Rebuilds from scratch, prints PASS/FAIL per milestone.

Run: scripts/check
"""

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

# Apple system functions the apps may need. Anything else undefined fails M2/M4.
ALLOWED = {
    # libobjc
    "_objc_getClass", "_objc_getProtocol", "_sel_registerName", "_objc_allocateClassPair",
    "_objc_registerClassPair", "_class_addMethod", "_class_addProtocol", "_objc_autoreleasePoolPush",
    # libSystem (dlsym finds objc_msgSend; the rest is Mojo's own print and memory)
    "_dlsym", "_dup", "_fclose", "_fdopen", "_fflush", "_memcpy", "_write", "_posix_memalign", "_free",
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


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)


def undefined(objs):
    out = run(["llvm-nm", "-u", "-j", *map(str, objs)]).stdout.split()
    defined = set(run(["llvm-nm", "-j", "--defined-only", *map(str, objs)]).stdout.split())
    return {s for s in out if s not in defined and not s.endswith(":")}


def load_commands(binary):
    return run(["llvm-otool", "-l", str(binary)]).stdout


def dylibs(binary):
    return set(re.findall(r"cmd LC_LOAD_DYLIB\n\s+cmdsize \d+\n\s+name (\S+)", load_commands(binary)))


def signature_ok(exe, plist, resources):
    # rcodesign's own verify is documented as unreliable, so recompute the hashes ourselves.
    r = run([sys.executable, "scripts/verify_signature.py", str(exe), str(plist), str(resources)])
    return r.returncode == 0, (r.stdout + r.stderr).strip()[-300:]


def m1():
    r = run(["pixi", "run", "mojo", "run", "-I", "apple", "tests/test_hello_core.mojo"])
    ok = r.returncode == 0 and "ALL TESTS PASSED" in r.stdout
    return ok, r.stdout.strip()[-300:] + r.stderr.strip()[-300:]


def no_foreign_sources():
    bad = [p for p in (ROOT / "apple").rglob("*") if p.suffix in {".c", ".m", ".swift", ".h"}]
    return bad


def objects_ok(platform):
    objs = [BUILD / platform / f"hello_{platform}.o", BUILD / platform / "mojo_rt.o"]
    missing = [o for o in objs if not o.exists()]
    if missing:
        return False, f"missing {missing}"
    extra = undefined(objs) - ALLOWED
    bad = no_foreign_sources()
    if extra or bad:
        return False, f"not allowed: {sorted(extra)}; foreign sources: {bad}"
    return True, f"undefined symbols all Apple system functions; no C/ObjC/Swift sources"


def m2():
    return objects_ok("mac")


def m4():
    return objects_ok("ios")


def bundle_ok(app, want_dylibs, platform, plist_keys):
    exe = app / ("Contents/MacOS/HelloMojo" if platform == "MACOS" else "HelloMojo")
    plist_path = app / ("Contents/Info.plist" if platform == "MACOS" else "Info.plist")
    if not exe.exists() or not plist_path.exists():
        return False, f"missing {exe} or {plist_path}"
    desc = run(["file", str(exe)]).stdout
    lc = load_commands(exe)
    problems = []
    if "Mach-O 64-bit arm64 executable" not in desc:
        problems.append(f"not an arm64 executable: {desc.strip()}")
    if "LC_MAIN" not in lc:
        problems.append("no LC_MAIN entry point")
    if f"platform {platform}" not in lc.replace("platform 1", "platform MACOS").replace("platform 2", "platform IOS"):
        problems.append(f"platform is not {platform}")
    libs = dylibs(exe)
    if libs != want_dylibs:
        problems.append(f"dylibs {sorted(libs)} != {sorted(want_dylibs)}")
    plist = plistlib.loads(plist_path.read_bytes())
    missing = [k for k in plist_keys if k not in plist]
    if missing:
        problems.append(f"Info.plist missing {missing}")
    entry = re.search(r"entryoff (\d+)", lc)
    sym = run(["llvm-nm", "--defined-only", str(exe)]).stdout
    m = re.search(r"^([0-9a-f]+) T _mojo_entry$", sym, re.M)
    if not entry or not m or int(m.group(1), 16) - 0x100000000 != int(entry.group(1)):
        problems.append("entry point is not _mojo_entry")
    resources = app / ("Contents/_CodeSignature/CodeResources" if platform == "MACOS" else "_CodeSignature/CodeResources")
    sig, msg = signature_ok(exe, plist_path, resources)
    if not sig:
        problems.append(f"signature: {msg}")
    return not problems, "; ".join(problems) or f"{desc.split(':', 1)[1].strip()}; loads {len(libs)} system libs; signed"


def m3():
    return bundle_ok(
        BUILD / "mac/HelloMojo.app",
        MAC_DYLIBS,
        "MACOS",
        ["CFBundleExecutable", "CFBundleIdentifier", "CFBundlePackageType", "LSMinimumSystemVersion"],
    )


def m5():
    ipa = BUILD / "ios/HelloMojo.ipa"
    if not ipa.exists():
        return False, "no ipa"
    with tempfile.TemporaryDirectory() as tmp:
        zipfile.ZipFile(ipa).extractall(tmp)
        app = Path(tmp) / "Payload/HelloMojo.app"
        exe = app / "HelloMojo"
        if exe.exists():
            exe.chmod(0o755)
        ok, msg = bundle_ok(
            app,
            IOS_DYLIBS,
            "IOS",
            ["CFBundleExecutable", "CFBundleIdentifier", "MinimumOSVersion", "LSRequiresIPhoneOS",
             "UIApplicationSceneManifest", "UIDeviceFamily", "UILaunchScreen"],
        )
        return ok, msg


def m6():
    readme = ROOT / "apple/README.md"
    if not readme.exists():
        return False, "no apple/README.md"
    text = readme.read_text()
    problems = [h for h in ("## Mac", "## iPhone") if h not in text]
    for ref in set(re.findall(r"`((?:apple|build|scripts|tests)/[^`\s]*)`", text)):
        if ref.startswith("build/"):
            continue  # build outputs: checked by M3/M5
        if not (ROOT / ref).exists():
            problems.append(f"missing {ref}")
    return not problems, "; ".join(problems) or "Mac and iPhone sections present; all referenced files exist"


def main():
    shutil.rmtree(BUILD / "mac", ignore_errors=True)
    shutil.rmtree(BUILD / "ios", ignore_errors=True)
    b = run(["apple/build.sh", "all"])
    if b.returncode != 0:
        print("build failed:\n" + (b.stdout + b.stderr)[-1500:])
    results = []
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5), ("M6", m6)]:
        try:
            ok, msg = fn()
        except Exception as e:  # a crashing check is a failing check
            ok, msg = False, f"check crashed: {e}"
        results.append(ok)
        print(f"{'PASS' if ok else 'FAIL'}  {name}  {msg}")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
