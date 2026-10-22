"""Milestone checker for goal 17 (archived: docs/goals/17-universal-theme.md: the universal theme and its components; goal 15's checks
run as M6, earlier goals' inside them). Rebuilds from scratch, prints PASS/FAIL per milestone. GTK runs headless; the web in Chromium.

Run: scripts/check   (a subset without rebuilding: scripts/check M2 M3; earlier goals: through docs/goals/NN-check.py)
"""

import importlib.util
import re
import sys
import time
from pathlib import Path

ROOT = next(p for p in Path(__file__).resolve().parents if (p / "pixi.toml").exists())  # (archived in docs/goals/)
sys.path.insert(0, str(ROOT / "scripts"))

_spec = importlib.util.spec_from_file_location("goal15", ROOT / "docs/goals/15-check.py")
g15 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g15)
run, BUILD, EXAMPLES, OPEN = g15.run, g15.BUILD, g15.EXAMPLES, g15.OPEN
both, env_for, has, labels, ensure_csv, CSV_1M = g15.both, g15.env_for, g15.has, g15.labels, g15.ensure_csv, g15.CSV_1M

# Goal 24 made Liquid omxplorer's default (the owner, D-225); these checks were written for the Ledger, so every run
# without a saved setting starts as a person who picked the Ledger would (settings.txt: skin=ledger; D-239).
_env_for = g15.g14.env_for  # (both() is goal 14's and calls its own env_for)


def _ledger_env(tag, *a, **k):
    e = _env_for(tag, *a, **k)
    if "OMX_CONFIG" in e:
        f = Path(e["OMX_CONFIG"]) / "settings.txt"
        f.parent.mkdir(parents=True, exist_ok=True)
        if not f.exists():
            f.write_text("skin=ledger\n")
    return e


g15.g14.env_for = g15.env_for = env_for = _ledger_env

SHOWN = r"^(LABEL|TONE|SEGMENTED|TABS|DROPDOWN|BUTTON|FIELD|TEXTAREA|BOARD|TOGGLE|CHECK|MENU|DIALOG|TOAST|TIP|POPOVER|DESIGN|RADIO): "
TIMING = re.compile(r"read in [\d.]+ s|[\d.]+ ms on |^LABEL: Saved |^LABEL: Opened |^LABEL: [\d.]+ ms$|^LABEL: ● ")
FONTS = ROOT / "mojoui/hosts/static/fonts"
SKINS = {"ledger": ("#0e7c86", "#eef0f3", "#ffffff"), "graphite": ("#f5a524", "#161618", "#1d1e21"), "blueprint": ("#2f6fed", "#f3f5f9", "#ffffff")}


def shown(out):
    return sorted(l for l in out.splitlines() if re.match(SHOWN, l) and not TIMING.search(l))


def lines(out, prefix):
    return [l[len(prefix):] for l in out.splitlines() if l.startswith(prefix)]


def differ(name, a, b):
    sa, sb = shown(a), shown(b)
    return None if sa == sb else f"{name}: GTK and web differ: {sorted(set(sa) ^ set(sb))[:4]}"


def brightness(png):
    """Mean brightness 0–255 of a screenshot (PIL, from the pixi environment)."""
    from PIL import Image, ImageStat
    return ImageStat.Stat(Image.open(png).convert("L")).mean[0]


def settings(tag, text):
    """Writes the test config folder's settings.txt before a run (the skin a person chose)."""
    e = env_for(tag)
    (Path(e["OMX_CONFIG"]) / "settings.txt").write_text(text)
    return e


def mojo_test(name, passed):
    b = run(["scripts/mxbuild.sh", "-I", ".", f"tests/{name}.mojo", "-o", str(BUILD / name)], timeout=900)
    t = run(["pixi", "run", str(BUILD / name)], timeout=600) if b.returncode == 0 else b
    return None if passed in t.stdout else f"{name}: {(t.stdout + t.stderr)[-300:]}"


def m1():
    problems = []
    for f in ("Inter-Regular.ttf", "Inter-Medium.ttf", "Inter-SemiBold.ttf", "JetBrainsMono-Regular.ttf", "JetBrainsMono-Bold.ttf",
              "LICENSE-Inter.txt", "LICENSE-JetBrainsMono.txt"):
        if not (FONTS / f).exists():
            problems.append(f"fonts/{f} missing")
    bake = (ROOT / "scripts/bake_font.py").read_text()
    if "static/fonts" not in bake or "Inter-Regular.ttf" not in bake:
        problems.append("bake_font.py doesn't bake the vendored Inter")
    if "Inter" not in (ROOT / "mojoui/font_data.mojo").read_text()[:400]:
        problems.append("font_data.mojo wasn't baked from Inter")
    theme = "".join(t.read_text() for t in sorted((ROOT / "themes").glob("*.mojo")))  # (the skins' palettes are theme modules since goal 27, D-260)
    for skin in SKINS:
        if f"def {skin}(" not in theme:
            problems.append(f"Palette.{skin}() missing")
    p = mojo_test("test_theme", "THEME TESTS PASSED")
    if p:
        problems.append(p)
    if problems:
        return False, "; ".join(problems)
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    light = both(OPEN, "skin-ledger")
    dark = both(OPEN, "skin-graphite", extra=settings("skin-graphite", "skin=graphite\n"))
    for r in (light, dark):
        if r[0] is None:
            return False, r[1]
    for host, k in (("GTK", 0), ("web", 1)):
        if "DESIGN: ledger" not in light[k]:
            problems.append(f"{host}: the default isn't the Ledger skin")
        if "DESIGN: graphite" not in dark[k]:
            problems.append(f"{host}: settings.txt's skin=graphite wasn't applied")
        if not any(l.startswith("Inter") for l in lines(light[k], "FONT: ")):
            problems.append(f"{host}: Inter isn't loaded for the controls ({lines(light[k], 'FONT: ')})")
    for name, want_light in (("skin-ledger", True), ("skin-graphite", False)):
        for host in ("gtk", "web"):
            b = brightness(BUILD / "omxplorer" / f"{name}-{host}.png")
            if want_light and b < 180:
                problems.append(f"{name} on {host}: the sheet isn't light (brightness {b:.0f})")
            if not want_light and b > 90:
                problems.append(f"{name} on {host}: the sheet isn't dark (brightness {b:.0f})")
    for name, r in (("ledger", light), ("graphite", dark)):
        d = differ(name, r[0], r[1])
        if d:
            problems.append(d)
    return not problems, "; ".join(problems) or "Ledger, Graphite and Blueprint palettes with the kit's colours; Inter and JetBrains Mono vendored and baked; omxplorer is the Ledger by default and Graphite from settings.txt, on both hosts, with Inter loaded"


def m2():
    problems = []
    p = mojo_test("test_menus", "MENU TESTS PASSED")
    if p:
        return False, p
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    plain = both(OPEN, "menus")
    sorted_ = both(OPEN + ";menu:Data>Sort largest first", "menu-sort")
    saved = both(OPEN + ";shortcut:Ctrl+S", "menu-save", split=True)
    ctx = both(OPEN + ";rightclick:0=120,40", "menu-context")
    ctx_sort = both(OPEN + ";rightclick:0=120,40;menu:>Sort largest first", "menu-context-sort")
    for r in (plain, sorted_, saved, ctx, ctx_sort):
        if r[0] is None:
            return False, r[1]
    for host, k in (("GTK", 0), ("web", 1)):
        menus = lines(plain[k], "MENU: ")
        titles = [m.split(":")[0] for m in menus]
        for t in ("File", "Edit", "View", "Insert", "Data", "Format", "Help"):
            if t not in titles:
                problems.append(f"{host}: no {t} menu ({titles})")
        if not any(m.startswith("Data:") and "Sort largest first" in m for m in menus):
            problems.append(f"{host}: Data lacks Sort largest first")
        if not any(m.startswith("File:") and "Ctrl+S" in m for m in menus):
            problems.append(f"{host}: File > Save shows no Ctrl+S shortcut")
        if not any(l.startswith("sorted by ") and l.endswith("↓") for l in labels(sorted_[k])):
            problems.append(f"{host}: Data > Sort largest first didn't sort")
        if not any(m.startswith("context:") and "Sort largest first" in m for m in lines(ctx[k], "MENU: ")):
            problems.append(f"{host}: a right-click on the header opened no context menu ({lines(ctx[k], 'MENU: ')[-1:]})")
        if host == "GTK" and "MENUSHOWN: yes" not in ctx[k]:
            problems.append("GTK: the context menu's popover isn't on screen")
        if not any(l.startswith("sorted by ") and l.endswith("↓") for l in labels(ctx_sort[k])):
            problems.append(f"{host}: the context menu's Sort largest first didn't sort")
        if any(m.startswith("context:") for m in lines(ctx_sort[k], "MENU: ")):
            problems.append(f"{host}: the context menu stayed open after its item was chosen")
    for host in ("gtk", "web"):
        if not (Path(env_for(f"menu-save-{host}")["OMX_DOCUMENTS"]) / "orders_1m.omx").exists():
            problems.append(f"{host}: Ctrl+S didn't save orders_1m.omx")
    for name, r in (("plain", plain), ("sorted", sorted_), ("context", ctx), ("context-sort", ctx_sort)):
        d = differ(name, r[0], r[1])
        if d:
            problems.append(d)
    return not problems, "; ".join(problems[:6]) or "the menu bar (File … Help) with shortcuts on both hosts; Data > Sort largest first sorts; Ctrl+S saves; a right-click on a column header opens a context menu whose Sort largest first sorts and closes it; identical on GTK and web"


def m3():
    problems = []
    p = mojo_test("test_overlays", "OVERLAY TESTS PASSED")
    if p:
        return False, p
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    dlg = both(OPEN + ";menu:File>Settings…", "settings", split=True)
    swapped = both(OPEN + ";menu:File>Settings…;radio:0=Graphite", "settings-graphite", split=True)
    done = both(OPEN + ";menu:File>Settings…;radio:0=Graphite;tap:Done", "settings-done", split=True)
    # (goal 30, D-287: the toast became the island's undo face; Undo is its right end)
    toast = both(OPEN + ";menu:Data>Sort largest first;say:island", "toast")
    undone = both(OPEN + ";menu:Data>Sort largest first;tapat:island=995,500;pause:300;say:island", "toast-undo")
    pop = both(OPEN + ";tap:ƒx", "popover")
    closed = both(OPEN + ";tap:ƒx;dismiss:", "popover-closed")
    for r in (dlg, swapped, done, toast, undone, pop, closed):
        if r[0] is None:
            return False, r[1]
    for host, k in (("GTK", 0), ("web", 1)):
        if "DIALOG: Settings" not in dlg[k] or "RADIO: Ledger" not in dlg[k]:
            problems.append(f"{host}: File > Settings… shows no Settings dialog with the skin picker")
        if not any(l.startswith("CHECK: ") for l in dlg[k].splitlines()):
            problems.append(f"{host}: the Settings dialog has no checkboxes")
        if "DESIGN: graphite" not in swapped[k] or "RADIO: Graphite" not in swapped[k]:
            problems.append(f"{host}: picking Graphite didn't switch the skin live")
        if "DIALOG: Settings" in done[k]:
            problems.append(f"{host}: Done didn't close the Settings dialog")
        if "DESIGN: graphite" not in done[k]:
            problems.append(f"{host}: the skin didn't stay after Done")
        says = re.findall(r"^SAYS: island = (.*)$", toast[k], re.M)
        if not says or "largest first" not in says[0] or lines(toast[k], "TOAST: "):
            problems.append(f"{host}: the island didn't say the sort ({says})")
        undo_says = re.findall(r"^SAYS: island = (.*)$", undone[k], re.M)
        if any(l.startswith("sorted by ") for l in labels(undone[k])) or not undo_says or not undo_says[-1].startswith("Sort undone"):
            problems.append(f"{host}: the island's Undo didn't undo the sort ({undo_says})")
        tips = lines(toast[k], "TIP: ")
        if len(tips) < 6 or not any(t.startswith("Save = ") and "Ctrl+S" in t for t in tips):
            problems.append(f"{host}: the toolbar's tooltips are missing ({tips[:3]})")
        if "POPOVER: Formulas" not in pop[k]:
            problems.append(f"{host}: ƒx opened no popover")
        if "POPOVER: Formulas" in closed[k]:
            problems.append(f"{host}: the popover didn't close")
    for host in ("gtk", "web"):
        s = Path(env_for(f"settings-graphite-{host}")["OMX_CONFIG"]) / "settings.txt"
        if not s.exists() or "skin=graphite" not in s.read_text():
            problems.append(f"{host}: settings.txt wasn't written with skin=graphite")
        b = brightness(BUILD / "omxplorer" / f"settings-done-{host}.png")
        if b > 90:
            problems.append(f"settings-done on {host}: the sheet isn't dark after switching (brightness {b:.0f})")
    for name, r in (("settings", dlg), ("swapped", swapped), ("done", done), ("toast", toast), ("undone", undone), ("popover", pop), ("closed", closed)):
        d = differ(name, r[0], r[1])
        if d:
            problems.append(d)
    return not problems, "; ".join(problems[:6]) or "Settings dialog (skin picker, checkboxes) switches the skin live and saves it; a sort's toast undoes it; every toolbar button has a tooltip; ƒx opens and closes a popover; identical on GTK and web"


def m4():
    src = (ROOT / "tests/test_datagrid.mojo").read_text()
    problems = []
    for needle in ("badge", "corner"):
        if needle not in src:
            problems.append(f"test_datagrid doesn't check the {needle}")
    p = mojo_test("test_datagrid", "DATAGRID TESTS PASSED")
    if p:
        problems.append(p)
    return not problems, "; ".join(problems) or "the grid's header shows a type badge per column and an edited cell gets an accent corner mark (drawn and read back in test_datagrid)"


def m5():
    problems = []
    ok, msg = ensure_csv()
    if not ok:
        return False, msg
    start = both("", "start")
    sheet = both(OPEN, "sheet")
    about = both(OPEN + ";menu:Help>About omxplorer", "about")
    for r in (start, sheet, about):
        if r[0] is None:
            return False, r[1]
    for host, k in (("GTK", 0), ("web", 1)):
        if not any(m.startswith("File:") for m in lines(start[k], "MENU: ")):
            problems.append(f"{host}: the Start screen has no menu bar")
        if not has(start[k], "Drop a CSV, Parquet or .omx file here") or "BUTTON: Open file…" not in start[k]:  # (Parquet opens since goal 20)
            problems.append(f"{host}: the Start screen lacks the drop zone")
        if not has(start[k], "Recent") or not has(start[k], "Try a sample"):
            problems.append(f"{host}: the Start screen lacks Recent or the samples")
        if "DIALOG: About omxplorer" not in about[k]:
            problems.append(f"{host}: Help > About opened no dialog")
    for name, r in (("start", start), ("sheet", sheet), ("about", about)):
        d = differ(name, r[0], r[1])
        if d:
            problems.append(d)
    return not problems, "; ".join(problems) or "the Ledger Start screen (drop zone, recent files, samples) and the sheet carry the menu bar; Help > About opens a dialog; identical on GTK and web"


def m6():
    problems = []
    for name in ("m1", "m2", "m3", "m4", "m5", "m6"):
        ok, msg = getattr(g15, name)()
        if not ok:
            problems.append(f"goal 15 {name.upper()}: {msg[:300]}")
    r = run(["pixi", "run", "python", "scripts/components.py", "--check"], timeout=120)
    if r.returncode != 0:
        problems.append("docs/components.md is stale")
    doc = (ROOT / "docs/components.md").read_text()
    for name in ("`MenuBar`", "`ContextMenu`", "`Dialog`", "`Toast`", "`Popover`", "`Checkbox`"):
        row = next((l for l in doc.splitlines() if l.startswith(f"| {name}")), "")
        states = [c.strip() for c in row.split("|") if c.strip() in ("✅", "🔨", "❌")]
        if states[:2] != ["✅", "✅"]:
            problems.append(f"the matrix shows {name} as {states[:2]} on Linux and web")
    return not problems, "; ".join(problems) or "goal 15's checks (and goals 3–14's inside them) pass; the matrix is current with the new components ✅ on Linux and web"


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
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5), ("M6", m6)]:
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
