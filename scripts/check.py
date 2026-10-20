"""Milestone checker for GOAL.md (goal 27: a lean core, themes on top, and polish; goal 26's checks run as M7, every
earlier goal's inside them). Rebuilds from scratch, prints PASS/FAIL per milestone.

Run: scripts/check   (a subset without rebuilding: scripts/check M1 M3; earlier goals: through docs/goals/NN-check.py)
"""

import importlib.util
import re
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


g26 = load("goal26", "docs/goals/26-check.py")
g25 = g26.g25
g20 = g25.g20
run, BUILD = g20.run, g20.BUILD
OUT = BUILD / "g27"
shots = load("theme_shots", "scripts/theme_shots.py")
import drive  # noqa: E402

THEME_WORDS = re.compile(r"liquid|ledger|graphite|blueprint|fluent|omarchy|4f46e5|0e7a43|c8243f|E5464F|437A0E|3F24C8", re.I)


def m0():
    """Every themed screen as a picture before the move, twice: the noise between two runs."""
    a, b = OUT / "before", OUT / "before2"
    n = len(list(a.glob("*.png")))
    if n < 40 or len(list(b.glob("*.png"))) != n:
        return False, f"{n} shots in {a} (run: pixi run python scripts/theme_shots.py shoot {a}, then again into {b})"
    noise = max(share for _, share in shots.compare(a, b))
    return True, f"{n} shots (omxplorer's 4 screens in 4 skins, kit's skins, Fluent, Omarchy, native; GTK and the web); two runs differ by at most {noise * 100:.2f}% of pixels"


def m1():
    """No theme in the core: names, colours, style sheets; themes/ outside it; hosts take App.theme()."""
    problems = []
    hits = []
    for f in sorted((ROOT / "mojoui").rglob("*")):
        if f.suffix not in (".mojo", ".py", ".js", ".css") or "__pycache__" in f.parts:
            continue
        for i, line in enumerate(f.read_text(errors="replace").split("\n"), 1):
            if THEME_WORDS.search(line):
                hits.append(f"{f.relative_to(ROOT)}:{i}")
    if hits:
        problems.append(f"{len(hits)} theme mentions in mojoui/: " + ", ".join(hits[:8]))
    for t in ("liquid", "skins", "fluent", "omarchy"):
        if not (ROOT / "themes" / f"{t}.mojo").exists():
            problems.append(f"no themes/{t}.mojo")
    app = (ROOT / "mojoui/app.mojo").read_text()
    if "def theme(self) -> Theme" not in app or "def design(self)" in app or "def accent(self)" in app:
        problems.append("App: theme() replaces design() and accent()")
    if '"""' in (ROOT / "mojoui/hosts/gtk.mojo").read_text().replace('"""Writes', "").split("comptime G_APPLICATION")[1].split("def ")[0]:
        problems.append("the GTK host holds a style sheet")
    web = (ROOT / "mojoui/hosts/web.py").read_text()
    sheets = re.findall(r'^([A-Z_]+) = """', web, re.M)
    if [s for s in sheets if s.endswith("CSS") and s != "CSS"]:
        problems.append(f"the web host holds style sheets besides its base: {sheets}")
    return not problems, "; ".join(problems) or "mojoui/ names no theme, colour or style sheet (0 hits); Liquid, the skins, Fluent and Omarchy are themes/ modules; hosts apply App.theme()"


def m2():
    """No theme: each platform's own look (GTK: only padding rules, the system's scheme; the web: the system font)."""
    problems = []
    r = run([str(BUILD / "hello" / "linux" / "hello")], env={"MOJOUI_TEST": ""}, timeout=300)
    out = r.stdout + r.stderr
    m = re.search(r"^THEME: (.*)$", out, re.M)
    if not m or m.group(1) != "none":
        problems.append(f"GTK hello: {m.group(0) if m else 'no THEME line'}")
    w, log = drive.web_run(BUILD / "hello" / "web", "style:body=font-family;attr:body=class", viewport=(900, 700))
    font = re.search(r"^STYLE: body font-family (.*)$", log, re.M)
    cls = re.search(r"^ATTR: body class(.*)$", log, re.M)
    if not font or not font.group(1).startswith("system-ui"):
        problems.append(f"web hello font: {font.group(1) if font else log[-300:]}")
    if cls and cls.group(1).strip() not in ("", "none"):
        problems.append(f"web hello body class: {cls.group(1)}")
    return not problems, "; ".join(problems) or "hello names no theme: GTK loads no style sheet but layout (THEME: none); the web page is the system font and colours, no body class"


def m3():
    """The same pixels after the move (no more than the noise + 0.2 %)."""
    a, b = OUT / "before", OUT / "after"
    if not b.exists():
        return False, f"no {b} (pixi run python scripts/theme_shots.py shoot {b})"
    noise = max(share for _, share in shots.compare(a, OUT / "before2"))
    rows = shots.compare(a, b)
    bad = [(n, s) for n, s in rows if s is None or s > noise + 0.002]
    if bad:
        return False, "differ: " + ", ".join(f"{n} {'missing' if s is None else f'{s * 100:.2f}%'}" for n, s in bad[:8])
    return True, f"{len(rows)} screens again after the move: at most {max(s for _, s in rows) * 100:.2f}% of pixels differ (noise {noise * 100:.2f}%)"


def m4():
    """A theme written outside mojoui/ (themes/paper.mojo), picked by an example, switching live on GTK and the web."""
    problems = []
    if not (ROOT / "themes/paper.mojo").exists():
        return False, "no themes/paper.mojo"
    mentions = [str(f.relative_to(ROOT)) for f in (ROOT / "mojoui").rglob("*") if f.suffix in (".mojo", ".py", ".js") and "paper" in f.read_text(errors="replace").lower()]
    if mentions:
        problems.append(f"mojoui/ mentions Paper: {mentions}")
    for t in ("linux", "web"):
        if not (BUILD / "themes" / t).exists():
            b = run(["scripts/build.sh", "themes", t], timeout=1800)
            if b.returncode != 0:
                return False, f"themes {t} build: {(b.stdout + b.stderr)[-400:]}"
    OUT.mkdir(parents=True, exist_ok=True)
    exe = str(BUILD / "themes" / "linux" / "themes")
    first = run([exe], env={"MOJOUI_TEST": "", "MOJOUI_WINDOW": "900x760", "MOJOUI_SHOT": str(OUT / "themes-native-gtk.png")}, timeout=300)
    paper = run([exe], env={"MOJOUI_TEST": "segment:0=Paper", "MOJOUI_WINDOW": "900x760", "MOJOUI_SHOT": str(OUT / "themes-paper-gtk.png")}, timeout=300)
    if "THEME: none" not in first.stdout:
        problems.append("GTK: the example doesn't start native")
    if "DESIGN: paper" not in paper.stdout or "THEME: paper" not in paper.stdout:
        problems.append(f"GTK: picking Paper didn't apply it: {[l for l in paper.stdout.splitlines() if l.startswith(('THEME', 'DESIGN'))]}")
    else:
        from PIL import Image
        px = Image.open(OUT / "themes-paper-gtk.png").convert("RGB").getpixel((6, 750))
        if not g26.near(px, (244, 239, 230), 6):
            problems.append(f"GTK: the window's background is {px}, not Paper's #f4efe6")
    w, log = drive.web_run(BUILD / "themes" / "web", "segment:0=Paper;attr:body=class;style:body=background-color", shot=str(OUT / "themes-paper-web.png"), viewport=(900, 760))
    cls = re.search(r"^ATTR: body class (.*)$", log, re.M)
    bg = re.search(r"^STYLE: body background-color (.*)$", log, re.M)
    if not cls or "paper" not in cls.group(1).split():
        problems.append(f"web: body class {cls.group(1) if cls else log[-300:]}")
    if not bg or bg.group(1).strip() != "rgb(244, 239, 230)":
        problems.append(f"web: body background {bg.group(1) if bg else 'none'}")
    return not problems, "; ".join(problems) or "themes/paper.mojo (no line of it in mojoui/) picked in the themes example: GTK and the web switch live from native to Paper (window and page in #f4efe6)"


def m6():
    """The Scene is GTK's default: goal 26's numbers with no flag; goal 25's checks (goals 3–24 inside) on it."""
    import os
    problems = []
    if 'getenv("MOJOUI_SCENE") != "0"' not in (ROOT / "mojoui/hosts/gtk.mojo").read_text():
        problems.append("the GTK host doesn't draw Scenes by default (MOJOUI_SCENE=0 turns them off)")
    best = None
    for attempt in range(3):  # (best of three, D-256)
        found, out = g26.bench(f"default-{attempt}")
        if "scroll" in found and "glide" in found:
            cost = float(found["scroll"][6]) + float(found["scroll"][8])
            if best is None or cost < best[0]:
                best = (cost, found)
    if best is None:
        return False, "no BENCH lines without the flag"
    sc, gl = best[1]["scroll"], best[1]["glide"]
    scroll_p95 = float(sc[6]) + float(sc[8])
    glide_p50 = float(gl[5]) + float(gl[7])
    if scroll_p95 > 2.0 or glide_p50 > 0.3 or int(gl[12]) != 0 or int(gl[13]) + int(sc[13]) != 0:
        problems.append(f"without the flag: scroll {scroll_p95:.1f} ms p95, glide {glide_p50:.1f} ms, cells built {gl[12]}, textures {int(gl[13]) + int(sc[13])}")
    os.environ.pop("MOJOUI_SCENE", None)
    g25.OUT = BUILD / "g25-default"
    ok, msg = g25.m7()
    if not ok:
        problems.append(f"goal 25's M7 on the Scene: {msg}")
    return not problems, "; ".join(problems) or (f"no flag: scroll {scroll_p95:.1f} ms p95, glide {glide_p50:.1f} ms, 0 cell rebuilds, 0 uploads; "
                                                  "goals 3–24 (goal 25's M7) pass on the Scene; MOJOUI_SCENE=0 is the pixel path")


def m8():
    """docs/mxframe-needs.md: each need with why, what we do meanwhile, how much it matters."""
    f = ROOT / "docs/mxframe-needs.md"
    if not f.exists():
        return False, "no docs/mxframe-needs.md"
    text = f.read_text()
    rows = re.findall(r"^\| (\d+) \| \*\*|^\| (\d+) \| [A-Z]", text, re.M)
    rated = re.findall(r"\| (high|medium|low|high, later|later) \|$", text, re.M)
    if len(rows) < 15 or len(rated) < len(rows):
        return False, f"{len(rows)} needs, {len(rated)} rated"
    return True, f"docs/mxframe-needs.md: {len(rows)} operations, each with why, what the app does meanwhile and how much it matters; the order to ask in"


def todo(what):
    def fn():
        return False, f"not built yet: {what}"
    return fn


def m7():
    """Goal 26's checks (every earlier goal's inside them), its M6 aside (the owner's display)."""
    problems = []
    for name, fn in [("26-M0", g26.m0), ("26-M1", g26.m1), ("26-M2", g26.m2), ("26-M3", g26.m3), ("26-M4", g26.m4), ("26-M5", g26.m5), ("26-M8", g26.m8), ("26-M7", g26.m7)]:
        ok, msg = fn()
        if not ok:
            problems.append(f"{name}: {msg}")
    return not problems, "; ".join(problems) or "goal 26's M0–M5, M8 and M7 (goals 3–25 inside them) pass"


MILESTONES = [("M0", m0), ("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4),
              ("M5", todo("the polish pass")), ("M6", m6), ("M8", m8), ("M7", m7)]


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
