"""Milestone checker for GOAL.md (goal 18: the kit app on every host; the UIKit and AppKit hosts catch up; goal 17's checks
run as M5, earlier goals' inside them). Rebuilds from scratch, prints PASS/FAIL per milestone. GTK runs headless; the web in
Chromium; the iPad and Mac builds are linked, bundled and signed here (they run on the owner's devices, not here).

Run: scripts/check   (a subset without rebuilding: scripts/check M2 M3; earlier goals: through docs/goals/NN-check.py)
"""

import importlib.util
import plistlib
import re
import sys
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


g17 = load("goal17", "docs/goals/17-check.py")
g05 = load("goal05", "docs/goals/05-check.py")
run, BUILD, brightness = g17.run, g17.BUILD, g17.brightness
EXAMPLES = g17.EXAMPLES + ["kit"]
SHOWN = g17.SHOWN
TIMING = re.compile(r"[\d.]+ ms on ")
import drive  # noqa: E402

KINDS = ["TEXT", "BUTTON", "VSTACK", "HSTACK", "SPACER", "FIELD", "TOGGLE", "DROPDOWN", "SLIDER", "PROGRESS", "DIVIDER", "SCROLL", "IMAGE",
         "SEGMENTED", "RADIO", "TEXTAREA", "ALERT", "TABS", "NAVBAR", "DATE", "ICON", "GRID", "LAZYLIST", "CANVAS", "BOARD", "OVERLAY",
         "MENUBAR", "MENU", "ITEM", "DIALOG", "TOAST", "POPOVER"]
NEW_ROWS = ("`MenuBar`", "`Menu`", "`ContextMenu`", "`Dialog`", "`Toast`", "`Popover`", "`Checkbox`", "`Board`", "`Overlay`")


def shown(out):
    return sorted(l for l in out.splitlines() if re.match(SHOWN, l) and not TIMING.search(l))


def lines(out, prefix):
    return [l[len(prefix):] for l in out.splitlines() if l.startswith(prefix)]


def labels(out):
    return lines(out, "LABEL: ")


def kit(steps, name):
    """Runs the kit app's steps on GTK (headless) and the web (Chromium); returns (gtk output, web output) or (None, why)."""
    exe = BUILD / "kit" / "linux" / "kit"
    r = run([str(exe)], env={"MOJOUI_TEST": steps, "MOJOUI_SHOT": str(BUILD / "kit" / f"{name}-gtk.png")}, timeout=300)
    og = r.stdout + r.stderr
    if r.returncode != 0 or "CRITICAL" in og or "TEST: " in og:
        return None, f"GTK run failed (exit {r.returncode}): {og[-400:]}"
    try:
        rw, ow = drive.web_run(BUILD / "kit" / "web", steps, shot=str(BUILD / "kit" / f"{name}-web.png"), viewport=(1280, 800))
    except Exception as ex:
        return None, f"web run crashed: {ex!r}"
    if rw.returncode != 0:
        return None, f"web: {ow[-400:]}"
    return og, ow


def differ(name, a, b):
    sa, sb = shown(a), shown(b)
    return None if sa == sb else f"{name}: GTK and web differ: {sorted(set(sa) ^ set(sb))[:4]}"


def branches(host_file):
    """The node kinds a host builds: every `kind == X` in its source."""
    return set(re.findall(r"kind == ([A-Z_]+)", (ROOT / host_file).read_text()))


def matrix_states(name):
    doc = (ROOT / "docs/components.md").read_text()
    row = next((l for l in doc.splitlines() if l.startswith(f"| {name}")), "")
    return [c.strip() for c in row.split("|") if c.strip() in ("✅", "🔨", "❌")]


def m1():
    problems = []
    plain = kit("", "kit")
    saved = kit("menu:File>Save", "kit-save")
    undone = kit("menu:File>Save;toast:Undo", "kit-undo")
    key = kit("shortcut:Ctrl+S", "kit-shortcut")
    ctx = kit("rightclick:0=400,500", "kit-context")
    sorted_ = kit("rightclick:0=400,500;menu:>Sort Z→A", "kit-sorted")
    dlg = kit("tap:Open dialog", "kit-dialog")
    done = kit("tap:Open dialog;tap:Done", "kit-dialog-done")
    pop = kit("tap:Show popover", "kit-popover")
    closed = kit("tap:Show popover;dismiss:", "kit-popover-closed")
    dark = kit("segment:0=Graphite", "kit-graphite")
    check = kit("toggle:Show grid lines", "kit-check")
    moved = kit("move:1=40,30", "kit-moved")
    for r in (plain, saved, undone, key, ctx, sorted_, dlg, done, pop, closed, dark, check, moved):
        if r[0] is None:
            return False, r[1]
    for host, k in (("GTK", 0), ("web", 1)):
        menus = lines(plain[k], "MENU: ")
        if not any(m.startswith("File:") and "Save (Ctrl+S)" in m for m in menus) or not any(m.startswith("View:") and "Skin ▸" in m for m in menus):
            problems.append(f"{host}: the menu bar lacks File > Save or View > Skin ▸ ({menus[:2]})")
        if len(lines(plain[k], "TIP: ")) < 5:
            problems.append(f"{host}: the tool buttons lack tooltips")
        if "BOARD: table at 0,0 460x270" not in plain[k] or "BOARD: note at 480,0 240x120" not in plain[k]:
            problems.append(f"{host}: the Board's table and note aren't where the app put them")
        if not any(l.startswith("CANVAS: ") and " painted " in l and int(l.rsplit(" ", 1)[1]) > 0 for l in plain[k].splitlines()):
            problems.append(f"{host}: the canvas painted nothing")
        if "DESIGN: ledger" not in plain[k]:
            problems.append(f"{host}: the kit isn't the Ledger by default")
        if "Saved kit.omx" not in labels(saved[k]) or "TOAST: Saved kit.omx | Undo" not in saved[k]:
            problems.append(f"{host}: File > Save didn't save with a toast")
        if "Save undone" not in labels(undone[k]) or lines(undone[k], "TOAST: "):
            problems.append(f"{host}: the toast's Undo didn't undo (or the toast stayed)")
        if "Saved kit.omx" not in labels(key[k]):
            problems.append(f"{host}: Ctrl+S didn't save")
        if not any(m.startswith("context:") and "Sort Z→A" in m and "Delete column" in m for m in lines(ctx[k], "MENU: ")):
            problems.append(f"{host}: a right-click on the canvas opened no context menu")
        if host == "GTK" and "MENUSHOWN: yes" not in ctx[k]:
            problems.append("GTK: the context menu's popover isn't on screen")
        if "Sorted Z→A" not in labels(sorted_[k]) or any(m.startswith("context:") for m in lines(sorted_[k], "MENU: ")):
            problems.append(f"{host}: the context menu's Sort Z→A didn't sort and close")
        if "DIALOG: Settings" not in dlg[k] or "RADIO: Ledger" not in dlg[k] or "CHECK: Show grid lines=on" not in dlg[k]:
            problems.append(f"{host}: Open dialog showed no Settings dialog with its radio and checkboxes")
        if "DIALOG: Settings" in done[k]:
            problems.append(f"{host}: Done didn't close the dialog")
        if "POPOVER: Formulas" not in pop[k]:
            problems.append(f"{host}: Show popover opened no popover")
        if "POPOVER: Formulas" in closed[k]:
            problems.append(f"{host}: the popover didn't close")
        if "DESIGN: graphite" not in dark[k] or "Skin graphite" not in labels(dark[k]):
            problems.append(f"{host}: the Graphite segment didn't switch the skin")
        if "CHECK: Show grid lines=off" not in check[k] or "Grid lines off" not in labels(check[k]):
            problems.append(f"{host}: the checkbox didn't toggle")
        if "BOARD: note at 520,30 240x120" not in moved[k]:
            problems.append(f"{host}: dragging the note didn't move it ({lines(moved[k], 'BOARD: ')})")
    for name, want_light in (("kit", True), ("kit-graphite", False)):
        for host in ("gtk", "web"):
            b = brightness(BUILD / "kit" / f"{name}-{host}.png")
            if want_light and b < 170:
                problems.append(f"{name} on {host}: not light (brightness {b:.0f})")
            if not want_light and b > 100:
                problems.append(f"{name} on {host}: not dark (brightness {b:.0f})")
    for name, r in (("plain", plain), ("saved", saved), ("context", ctx), ("dialog", dlg), ("popover", pop), ("dark", dark), ("moved", moved)):
        d = differ(name, r[0], r[1])
        if d:
            problems.append(d)
    return not problems, "; ".join(problems[:8]) or "the kit app: menu bar, shortcuts, tooltips, a context menu on the canvas, a dialog, a toast with Undo, a popover, checkboxes, a Board with an island, a skin switch; identical on GTK and web, light and dark"


def m2():
    problems = []
    have = branches("mojoui/hosts/uikit.mojo")
    missing = [k for k in KINDS if k not in have]
    if missing:
        problems.append(f"uikit.mojo doesn't build {missing}")
    src = (ROOT / "mojoui/hosts/uikit.mojo").read_text()
    for needle, what in (("SECONDARY", "a right click / long press"), ("DOUBLE", "double taps"), ("PRESS", "press and release"), ("KEY", "hardware keys"),
                         ("node.tip", "tooltips"), ("skin_palette", "the skins' colours"), ("TOOL", "tool buttons"), ("ICON_ONLY", "icon buttons"),
                         ("TONE_WARN", "text tones"), ("sf_symbol", "icons")):
        if needle not in src:
            problems.append(f"uikit.mojo lacks {what} ({needle})")
    ok, msg = g05.apple_ok("kit", "ios")
    if not ok:
        problems.append(msg)
    if g05.same_source("kit", ["ios"]):
        problems.append("the iOS build isn't from the current kit app")
    r = run(["pixi", "run", "python", "scripts/components.py", "--check"], timeout=120)
    if r.returncode != 0:
        problems.append("docs/components.md is stale")
    for name in NEW_ROWS:
        states = matrix_states(name)
        if len(states) < 5 or states[4] not in ("🔨", "✅"):
            problems.append(f"the matrix shows {name} as {states[4:5]} on iPhone")
    return not problems, "; ".join(problems[:8]) or "the UIKit host builds every kind the kit uses, the button styles, tones, tooltips, the canvas gestures and the skins; the kit links, bundles and signs for iPad with only the allowed symbols; 🔨 on iPhone in the matrix"


def m3():
    problems = []
    plist = plistlib.loads((ROOT / "apple/ios/Info.plist").read_bytes())
    ipad = plist.get("UISupportedInterfaceOrientations~ipad", [])
    if len(ipad) != 4:
        problems.append("Info.plist doesn't allow every iPad orientation")
    if plist.get("UIRequiresFullScreen", True) is not False:
        problems.append("Info.plist doesn't allow iPad multitasking (UIRequiresFullScreen must be false)")
    if 2 not in plist.get("UIDeviceFamily", []):
        problems.append("Info.plist doesn't list the iPad")
    src = (ROOT / "mojoui/hosts/uikit.mojo").read_text()
    for needle, what in (("UIKeyCommand", "keyboard shortcuts"), ("UIToolTipInteraction", "pointer tooltips"), ("buttonMaskRequired", "a secondary-button tap"),
                         ("UILongPressGestureRecognizer", "a long press"), ("CTFontManagerRegisterFontsForURL", "the bundled fonts"),
                         ("UIPopoverPresentationController", "popovers"), ("pressesBegan", "hardware keys on a canvas")):
        if needle not in src:
            problems.append(f"uikit.mojo lacks {what} ({needle})")
    ipa = next((BUILD / "kit" / "ios").glob("*.ipa"), None)
    if not ipa:
        problems.append("no kit .ipa")
    else:
        names = zipfile.ZipFile(ipa).namelist()
        for f in ("Inter-Regular.ttf", "Inter-Medium.ttf", "JetBrainsMono-Regular.ttf"):
            if not any(n.endswith("/fonts/" + f) for n in names):
                problems.append(f"the .ipa doesn't carry fonts/{f}")
    build = (ROOT / "scripts/build.sh").read_text()
    if "fonts" not in build.split("build_ios()")[1].split("}")[0]:
        problems.append("build.sh doesn't copy the fonts into the iOS app")
    return not problems, "; ".join(problems) or "iPad: every orientation and multitasking allowed; Items' shortcuts become ⌘ key commands; pointer tooltips; a secondary tap or long press is SECONDARY; hardware keys reach the canvas; the fonts ship in the .ipa and register at start"


def m4():
    problems = []
    have = branches("mojoui/hosts/appkit.mojo")
    missing = [k for k in KINDS if k not in have]
    if missing:
        problems.append(f"appkit.mojo doesn't build {missing}")
    src = (ROOT / "mojoui/hosts/appkit.mojo").read_text()
    for needle, what in (("setMainMenu:", "the system menu bar"), ("setKeyEquivalent", "⌘ shortcuts"), ("NSPopover", "popovers"), ("setToolTip:", "tooltips"),
                         ("beginSheet", "dialogs as sheets"), ("SECONDARY", "right clicks"), ("skin_palette", "the skins"), ("CTFontManagerRegisterFontsForURL", "the bundled fonts")):
        if needle not in src:
            problems.append(f"appkit.mojo lacks {what} ({needle})")
    ok, msg = g05.apple_ok("kit", "mac")
    if not ok:
        problems.append(msg)
    if g05.same_source("kit", ["mac"]):
        problems.append("the Mac build isn't from the current kit app")
    for name in NEW_ROWS:
        states = matrix_states(name)
        if len(states) < 4 or states[3] not in ("🔨", "✅"):
            problems.append(f"the matrix shows {name} as {states[3:4]} on Mac")
    return not problems, "; ".join(problems[:8]) or "the AppKit host builds every kind the kit uses, the menu bar as the system menu bar with ⌘ shortcuts, popovers, sheets, tooltips, right clicks and the skins; the kit links, bundles and signs for Mac; 🔨 on Mac in the matrix"


def m5():
    problems = []
    for name in ("m1", "m2", "m3", "m4", "m5", "m6"):
        ok, msg = getattr(g17, name)()
        if not ok:
            problems.append(f"goal 17 {name.upper()}: {msg[:300]}")
    r = run(["pixi", "run", "python", "scripts/components.py", "--check"], timeout=120)
    if r.returncode != 0:
        problems.append("docs/components.md is stale")
    return not problems, "; ".join(problems) or "goal 17's checks (and goals 3–15's inside them) pass; the matrix is current"


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
            if ex in ("hello", "gallery", "layout", "lens", "todo"):
                a = run(["scripts/build.sh", ex, "android"], timeout=3600)
                if a.returncode != 0:
                    print(f"android build {ex} failed:\n" + (a.stdout + a.stderr)[-1500:])
    results = []
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5)]:
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
