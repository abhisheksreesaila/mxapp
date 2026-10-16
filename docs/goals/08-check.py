"""Milestone checker for GOAL.md (goal 8: the analytics showcase; goal 7's checks run as M9, earlier goals' inside them).
Rebuilds from scratch, prints PASS/FAIL per milestone.

Run: scripts/check   (earlier goals' checkers: docs/goals/0N-check.py)
"""

import importlib.util
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = next(p for p in Path(__file__).resolve().parents if (p / "pixi.toml").exists())  # (archived in docs/goals/)
sys.path.insert(0, str(ROOT / "scripts"))

_spec = importlib.util.spec_from_file_location("goal7", ROOT / "docs/goals/07-check.py")
g7 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g7)
g5 = g7.g5
run, BUILD = g7.run, g7.BUILD

import drive  # noqa: E402

EXAMPLES = g7.EXAMPLES + ["analytics"]
CLICKS = "segment:0=2024;select:0=Online;tapat:5=500,320;tapat:6=300,700;tapat:4=600,500"
SHOWN = r"^(LABEL|SEGMENTED|DROPDOWN|BUTTON): "
TIMING = ("LABEL: Recomputed",)
PAGES_URL = "https://abhisheksreesaila.github.io/mxapp/gallery/"


def shown(out):
    return [l for l in out.splitlines() if re.match(SHOWN, l) and not l.startswith(TIMING)]


def analytics_gtk(steps, size=None, shot=None):
    env = {"MOJOUI_TEST": steps, "MOJOUI_SHOT": shot or str(BUILD / "analytics" / "gtk.png")}
    if size:
        env["MOJOUI_WINDOW"] = f"{size[0]}x{size[1]}"
    r = run([str(BUILD / "analytics" / "linux" / "analytics")], env=env, timeout=300)
    out = r.stdout + r.stderr
    if r.returncode != 0 or "CRITICAL" in out or "TEST: " in out:
        return None, f"GTK run failed (exit {r.returncode}):\n{out[-600:]}"
    return r, out


def analytics_web(steps, size=(1440, 900), shot=None):
    try:
        r, out = drive.web_run(BUILD / "analytics" / "web", steps, shot=shot, viewport=size)
    except Exception as e:
        return None, f"web run crashed: {e!r}"
    return (r, out) if r.returncode == 0 else (None, out[-600:])


def test_passes(file, marker):
    t = run(["pixi", "run", "mojo", "run", "-I", ".", file], timeout=900)
    return marker in t.stdout, (t.stdout + t.stderr)[-400:]


# ---------- milestones ----------

def m1():
    problems = []
    ok, out = test_passes("tests/test_canvas.mojo", "CANVAS TESTS PASSED")
    if not ok:
        problems.append(f"canvas tests: {out}")
    r, gout = analytics_gtk("")
    if r is None or "DESIGN: fluent" not in gout:
        problems.append(f"GTK doesn't apply the Fluent design: {(gout or '')[-200:]}")
    web = (ROOT / "mojoui/hosts/web.py").read_text()
    if "FLUENT_CSS" not in web or "classList.add('fluent')" not in web or "vstack card" not in web:
        problems.append("the web host has no Fluent stylesheet or cards")
    if '"mui-card"' not in (ROOT / "mojoui/hosts/gtk.mojo").read_text():
        problems.append("GTK draws no cards")
    return not problems, "; ".join(problems) or "Fluent 2 on GTK and web; Card on every host (a VStack where cards aren't known); tests pass"


def m2():
    t = run(["pixi", "run", "mojo", "run", "-I", ".", "tests/test_text.mojo"], timeout=600)
    if "TEXT TESTS PASSED" not in t.stdout:
        return False, f"text tests: {(t.stdout + t.stderr)[-300:]}"
    from PIL import ImageFont
    font = ImageFont.truetype("/usr/share/fonts/noto/NotoSans-Regular.ttf", 1000)
    worst = 0.0
    for line in t.stdout.splitlines():
        if line.startswith("WIDTH: "):
            text, size, width = line[7:].split("|")
            worst = max(worst, abs(font.getlength(text) * float(size) / 1000 - float(width)))
    if worst > 2:
        return False, f"text widths differ from the font's by up to {worst:.2f} px"
    return True, f"Noto Sans atlas text on canvases; widths within {worst:.2f} px of the font's metrics"


def m3():
    problems = []
    ok, out = test_passes("tests/test_charts.mojo", "CHARTS TESTS PASSED")
    if not ok:
        problems.append(f"chart tests: {out}")
    if "FlintChart(" not in (ROOT / "examples/analytics/app.mojo").read_text():
        problems.append("the dashboard's charts aren't Flint specs")
    b = run(["pixi", "run", "mojo", "build", "-I", "examples/analytics", "-I", ".", "tests/flint_specs.mojo",
             "-o", str(BUILD / "flint_specs")], timeout=900)
    if b.returncode != 0:
        return False, f"spec export didn't build: {(b.stdout + b.stderr)[-300:]}"
    specs = run([str(BUILD / "flint_specs")], timeout=300).stdout
    flint = BUILD / "flint"
    flint.mkdir(exist_ok=True)
    if not (flint / "node_modules" / "flint-chart").exists():
        run(["bash", "-c", f"cd {flint} && (test -f package.json || npm init -y >/dev/null) && npm install flint-chart vega vega-lite --silent"],
            timeout=900)
    (flint / "flint_validate.mjs").write_text((ROOT / "scripts/flint_validate.mjs").read_text())
    v = subprocess.run(["node", "flint_validate.mjs"], cwd=flint, input=specs, capture_output=True, text=True, timeout=300)
    m = re.search(r"VALID (\d+)/(\d+)", v.stdout)
    if not m or m[1] != m[2] or int(m[2]) < 9:
        problems.append(f"Flint rejected specs: {v.stdout[-400:]}{v.stderr[-200:]}")
        return False, "; ".join(problems)
    return not problems, "; ".join(problems) or (
        f"charts drawn natively from Flint specs; all {m[2]} dashboard specs compile through Flint → Vega-Lite → SVG")


def m4():
    b = run(["pixi", "run", "mojo", "build", "-I", ".", "tests/bench_groupby.mojo", "-o", str(BUILD / "bench_groupby")], timeout=900)
    if b.returncode != 0:
        return False, f"bench build: {(b.stdout + b.stderr)[-300:]}"
    r = run([str(BUILD / "bench_groupby")], timeout=600)
    m = re.search(r"^GROUPBY: (.*)$", r.stdout, re.M)
    if not m:
        return False, f"bench: {(r.stdout + r.stderr)[-300:]}"
    f = dict(kv.split("=", 1) for kv in m[1].split())
    problems = []
    if f["exact"] != "1":
        problems.append("GPU and CPU totals differ")
    if int(f["rows"]) < 20_000_000:
        problems.append(f"only {f['rows']} rows")
    for k in ("gpu_ms_5_groups", "gpu_ms_36_groups"):
        if float(f[k]) > 5:
            problems.append(f"{k} = {f[k]} > 5")
    return not problems, "; ".join(problems) or (
        f"20M rows: {float(f['gpu_ms_5_groups']):.2f} ms (5 groups), {float(f['gpu_ms_36_groups']):.2f} ms (36) on the GPU, "
        f"{float(f['cpu_ms']):.0f} ms on the CPU, exact")


def fits(name, out, size):
    b = g5.boxes(out)
    cards = [t for t in b if t.startswith(("kpi_", "card_", "summary", "sidebar", "main"))]
    if len(cards) < 12:
        return f"{name}: only {len(cards)} tagged cards: {sorted(cards)}"
    bad = [t for t in cards if b[t][0] + b[t][2] > size[0] + 1 or b[t][1] + b[t][3] > size[1] + 1]
    page = re.search(r"^PAGE: (\d+)x(\d+) in (\d+)x(\d+)$", out, re.M)  # (the web: the page itself doesn't scroll)
    if page and (int(page[1]) > int(page[3]) or int(page[2]) > int(page[4])):
        bad.append(f"the page scrolls ({page[1]}x{page[2]} in {page[3]}x{page[4]})")
    return f"{name} at {size[0]}×{size[1]}: {bad} spill outside" if bad else ""


def m5():
    problems = []
    rg, gout = analytics_gtk(CLICKS, shot=str(BUILD / "analytics" / "gtk-clicked.png"))
    rw, wout = analytics_web(CLICKS, shot=str(BUILD / "analytics" / "web-clicked.png"))
    if rg is None or rw is None:
        return False, (gout if rg is None else wout)[-400:]
    if shown(gout) != shown(wout):
        problems.append(f"GTK and web differ after the clicks:\n  gtk {shown(gout)}\n  web {shown(wout)}")
    if not any("Home · Europe · Jul 2024" in l for l in shown(gout)):
        problems.append(f"chart taps didn't select: {[l for l in shown(gout) if '·' in l][:3]}")
    for size in ((1440, 900), (1280, 800)):
        r1, o1 = analytics_gtk("", size=size)
        r2, o2 = analytics_web("", size=size)
        if r1 is None or r2 is None:
            problems.append(f"run at {size} failed: {(o1 if r1 is None else o2)[-200:]}")
            continue
        for name, out in (("GTK", o1), ("web", o2)):
            p = fits(name, out, size)
            if p:
                problems.append(p)
    from PIL import Image
    colours = len(set(Image.open(BUILD / "analytics" / "gtk.png").convert("RGB").getdata()))
    if colours < 1500:
        problems.append(f"screenshot has only {colours} colours")
    return not problems, "; ".join(problems) or (
        "dashboard over 20M rows; GTK and web identical after year/channel/bar/column/line taps; fits 1440×900 and 1280×800 on both")


def m6():
    problems = []
    b = run(["pixi", "run", "mojo", "build", "-I", "examples/analytics", "-I", ".", "tests/test_analytics.mojo",
             "-o", str(BUILD / "test_analytics")], timeout=900)
    t = run(["pixi", "run", str(BUILD / "test_analytics")], timeout=900) if b.returncode == 0 else b
    engines = re.search(r"^ENGINES: identical on (\d+) numbers", t.stdout, re.M)
    if "ANALYTICS TESTS PASSED" not in t.stdout or not engines:
        return False, f"engine/app tests: {(t.stdout + t.stderr)[-400:]}"
    lines = {}
    for engine in ("GPU", "MX frame"):
        for host in ("gtk", "web"):
            steps = f"segment:1={engine};segment:0=2024;select:0=Online;tapat:5=500,320"
            r, out = analytics_gtk(steps) if host == "gtk" else analytics_web(steps)
            if r is None:
                return False, f"{engine} on {host}: {out[-300:]}"
            lines[(engine, host)] = [l for l in shown(out) if not l.startswith("SEGMENTED: ") or "2024" in l]
            if engine == "MX frame" and not any("MX frame (CPU)" in l for l in out.splitlines()):
                problems.append(f"MX frame didn't run on {host}: {[l for l in out.splitlines() if 'Recomputed' in l]}")
    base = lines[("GPU", "gtk")]
    for key, value in lines.items():
        if value != base:
            problems.append(f"{key} differs from the GPU on GTK: {sorted(set(value) ^ set(base))[:4]}")
    return not problems, "; ".join(problems) or (
        f"GPU kernels, CPU and MX frame agree on all {engines[1]} results under 5 filter settings; identical dashboards on GTK and web")


def m7():
    problems = []
    page = ROOT / "docs/gallery/index.html"
    if not page.exists():
        return False, "no docs/gallery/index.html"
    html = page.read_text()
    for ref in re.findall(r'(?:src|href)="([^"#:?]+)"', html):
        if not (page.parent / ref).resolve().exists():
            problems.append(f"missing {ref}")
    for word in ("native", "web", "both", "Flint", "examples/analytics/app.mojo"):
        if word.lower() not in html.lower():
            problems.append(f"gallery doesn't mention {word}")
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=drive.CHROMIUM, headless=True)
        tab = browser.new_page(viewport={"width": 1440, "height": 900})
        errors = []
        tab.on("pageerror", lambda e: errors.append(str(e)))
        tab.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        tab.goto(page.as_uri())
        for y in range(0, 6000, 400):  # scroll through, so lazy images load
            tab.evaluate(f"window.scrollTo(0, {y})")
            tab.wait_for_timeout(80)
        tab.wait_for_timeout(800)
        broken = tab.evaluate("() => [...document.images].filter(i => !i.complete || i.naturalWidth === 0).map(i => i.src)")
        browser.close()
    if errors:
        problems.append(f"console errors: {errors[:3]}")
    if broken:
        problems.append(f"broken images: {broken[:3]}")
    try:
        live = urllib.request.urlopen(PAGES_URL, timeout=20).status == 200
    except Exception:
        live = False
    if not live:
        problems.append(f"not live at {PAGES_URL}")
    return not problems, "; ".join(problems) or f"gallery renders cleanly, every image and link resolves, live at {PAGES_URL}"


def m8():
    doc = ROOT / "docs/mxframe-mojo-api.md"
    if not doc.exists():
        return False, "no docs/mxframe-mojo-api.md"
    text = doc.read_text()
    missing = [w for w in ("group_sum", "MxFrame", "memory", "GPU", "Arrow", "examples/analytics/app.mojo", "mojoui/mxframe.mojo")
               if w not in text]
    return not missing, f"spec lacks {missing}" if missing else "the Mojo-level MX frame API spec, from the app's call sites"


def m9():
    problems = []
    for name in ("m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8"):
        ok, msg = getattr(g7, name)()
        if not ok:
            problems.append(f"goal 7 {name.upper()}: {msg[:200]}")
    return not problems, "; ".join(problems) or "goal 7's checks (and goals 3–6's inside them) still pass"


def m10():
    readme = (ROOT / "README.md").read_text()
    missing = [w for w in ("examples/analytics/app.mojo", "Flint", "MX frame", "gallery", "scripts/build.sh analytics")
               if w not in readme]
    return not missing, f"README lacks {missing}" if missing else "README shows the analytics showcase, how to run it, the gallery"


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
        if ex in ("hello", "gallery", "layout", "lens"):
            a = run(["scripts/build.sh", ex, "android"], timeout=3600)
            if a.returncode != 0:
                print(f"android build {ex} failed:\n" + (a.stdout + a.stderr)[-1500:])
    results = []
    for name, fn in [("M1", m1), ("M2", m2), ("M3", m3), ("M4", m4), ("M5", m5), ("M6", m6), ("M7", m7), ("M8", m8),
                     ("M9", m9), ("M10", m10)]:
        try:
            ok, msg = fn()
        except Exception as e:  # a crashing check is a failing check
            ok, msg = False, f"check crashed: {e!r}"
        results.append(ok)
        print(f"{'PASS' if ok else 'FAIL'}  {name}  {msg}")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
